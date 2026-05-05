#!/usr/bin/env bash
# Ormus Voice — one-shot installer.
#
# Builds whisper.cpp (CPU), installs whisper-cli, downloads a model,
# and links the wrapper script into ~/.local/bin/.
#
# Idempotent: re-running upgrades whisper.cpp to the current main and
# re-links the wrapper without re-downloading the model if present.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_CPP_DIR="${WHISPER_CPP_DIR:-$HOME/projects/contributions/whisper.cpp}"
MODEL_NAME="${ORMUS_VOICE_MODEL:-base.en}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ormus-voice/models"
BIN_DIR="$HOME/.local/bin"

say() { printf "\033[1;36m▸\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

# Preconditions
for tool in cmake make git arecord; do
    command -v "$tool" >/dev/null || err "missing dependency: $tool (apt install alsa-utils cmake build-essential git)"
done

mkdir -p "$BIN_DIR" "$DATA_DIR"

# 1) whisper.cpp — clone or update
if [ -d "$WHISPER_CPP_DIR/.git" ]; then
    say "updating whisper.cpp at $WHISPER_CPP_DIR"
    git -C "$WHISPER_CPP_DIR" pull --ff-only
else
    say "cloning whisper.cpp into $WHISPER_CPP_DIR"
    mkdir -p "$(dirname "$WHISPER_CPP_DIR")"
    git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$WHISPER_CPP_DIR"
fi

# 2) Build. Auto-detect Vulkan toolchain; fall through to CPU if missing.
#    For full GPU recipe (including how to get glslc on Pop!_OS), see
#    docs/recipes/gpu-vulkan.md.
CMAKE_FLAGS=(-DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON)
if command -v glslc >/dev/null && [ -f /usr/include/vulkan/vulkan.h ]; then
    say "glslc + Vulkan headers present — building with Vulkan backend"
    CMAKE_FLAGS+=(-DGGML_VULKAN=ON)
    # Pop!_OS / Ubuntu noble's libvulkan-dev doesn't ship spirv.hpp — add
    # shaderc's bundled SPIRV-Headers to the include path if it's there.
    SPIRV_HEADERS="$HOME/projects/contributions/shaderc/third_party/spirv-headers/include"
    if [ -d "$SPIRV_HEADERS" ]; then
        CMAKE_FLAGS+=("-DCMAKE_CXX_FLAGS=-I$SPIRV_HEADERS" "-DCMAKE_C_FLAGS=-I$SPIRV_HEADERS")
    fi
else
    say "no glslc on PATH — building CPU-only (see docs/recipes/gpu-vulkan.md to add GPU)"
fi
cmake -B "$WHISPER_CPP_DIR/build" -S "$WHISPER_CPP_DIR" "${CMAKE_FLAGS[@]}" >/dev/null
cmake --build "$WHISPER_CPP_DIR/build" -j --config Release >/dev/null

# 3) Install whisper-cli
say "installing whisper-cli to $BIN_DIR"
install -Dm0755 "$WHISPER_CPP_DIR/build/bin/whisper-cli" "$BIN_DIR/whisper-cli"

# 4) Model
MODEL_FILE="$DATA_DIR/ggml-${MODEL_NAME}.bin"
if [ -f "$MODEL_FILE" ]; then
    say "model present: $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1))"
else
    say "downloading $MODEL_NAME model"
    bash "$WHISPER_CPP_DIR/models/download-ggml-model.sh" "$MODEL_NAME"
    cp "$WHISPER_CPP_DIR/models/ggml-${MODEL_NAME}.bin" "$MODEL_FILE"
    say "installed: $MODEL_FILE"
fi

# 5) Wrapper
say "installing wrapper to $BIN_DIR/whisper-paste"
install -Dm0755 "$REPO_DIR/bin/whisper-paste" "$BIN_DIR/whisper-paste"

# 6) Smoke test on the JFK sample
SAMPLE="$WHISPER_CPP_DIR/samples/jfk.wav"
if [ -f "$SAMPLE" ]; then
    say "smoke test: transcribing JFK sample"
    OUT=$("$BIN_DIR/whisper-cli" -m "$MODEL_FILE" -f "$SAMPLE" -l en -nt -np 2>/dev/null \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$OUT" ]; then
        printf "  → \033[2m%s\033[0m\n" "$(echo "$OUT" | head -c 100)"
    else
        err "smoke test produced empty transcript"
    fi
fi

cat <<EOF

Ormus Voice installed.

Next:
  1. Bind whisper-paste to a key in your terminal of choice.
     For Ormus Terminal (Super+V):
        echo -n '"\$HOME/.local/bin/whisper-paste"' > \\
            ~/.config/cosmic/solutions.ormus.OrmusTerm/v1/voice_paste_command

  2. Make sure ~/.local/bin is on your PATH.

  3. Press your binding, speak for ${VOICE_PASTE_SECONDS:-8}s, get a paste.

Recipes for other terminals: docs/recipes/
GPU upgrade path:           docs/recipes/gpu-vulkan.md
EOF
