# Recipe: GPU acceleration (Vulkan)

The default `install.sh` builds whisper.cpp CPU-only. CPU performance is
already strong (sub-second on a modern desktop with `base.en`), but the
Vulkan backend gives another 3–5× on the encode step, which dominates
transcription cost.

Vulkan rather than CUDA was chosen because:

- Works with the **open NVIDIA driver** (no toolkit install dance).
- Works on **AMD and Intel GPUs** through Mesa.
- No Blackwell-specific gotchas (CUDA 12.8+ is required for sm_120 and
  the apt toolchain often lags).
- Single backend that covers most modern Linux desktops.

## Prerequisites

```bash
sudo apt install -y \
    libvulkan-dev \
    glslang-tools \
    mesa-vulkan-drivers
```

`glslang-tools` provides `glslc` (the GLSL → SPIR-V compiler whisper.cpp
needs at build time). On distros where `glslang-tools` doesn't ship
`glslc`, install Google's `shaderc` instead — they provide the same
binary.

Verify Vulkan works before rebuilding:

```bash
vulkaninfo --summary | head -20
```

You should see your GPU(s) listed. NVIDIA users on the open driver
should see `nvidia` as a device line.

## Rebuild whisper.cpp with Vulkan

```bash
WHISPER_CPP_DIR="${WHISPER_CPP_DIR:-$HOME/projects/contributions/whisper.cpp}"
cd "$WHISPER_CPP_DIR"
rm -rf build
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DGGML_VULKAN=ON
cmake --build build -j --config Release
install -Dm0755 build/bin/whisper-cli ~/.local/bin/whisper-cli
```

## Verify Vulkan is being used

When whisper-cli starts up, the log lines should include:

```
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = NVIDIA GeForce RTX 5070 Ti Laptop GPU (NVIDIA … driver) | …
```

Run a quick benchmark against the JFK sample:

```bash
time whisper-cli \
    -m ~/.local/share/ormus-voice/models/ggml-base.en.bin \
    -f $WHISPER_CPP_DIR/samples/jfk.wav \
    -l en -nt -np
```

Compare wall-clock time against the CPU build (recorded by
`install.sh` smoke test). Expect ~3–5× lower wall-clock for `base.en`
and a much larger gap for `medium.en`.

## When Vulkan doesn't help (or hurts)

- **Very small models on a fast CPU**: model load + GPU memory transfer
  can dominate transcription time for `tiny.en` on short clips. CPU
  may be faster.
- **Headless / VM environments**: no Vulkan device exposed → whisper.cpp
  falls back to CPU silently.
- **Intel iGPUs without VAAPI**: limited Vulkan support, marginal
  speedup. Test before committing.

## CUDA path (alternative, not recommended for Blackwell)

For pre-Blackwell NVIDIA cards (sm_70 through sm_90) where the apt
toolkit is recent enough:

```bash
sudo apt install -y nvidia-cuda-toolkit
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON
cmake --build build -j --config Release
```

Faster than Vulkan on dedicated NVIDIA cards but locks you to NVIDIA
and adds toolkit-version coupling. Skip unless Vulkan benchmarks
disappoint.
