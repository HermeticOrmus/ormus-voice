# Recipe: GPU acceleration (Vulkan)

The default `install.sh` auto-detects `glslc` and builds whisper.cpp
with the Vulkan backend if it's available; otherwise it falls back to
CPU. CPU performance is already strong (sub-second on a modern desktop
with `base.en`). Vulkan is most useful for `medium.en` and larger
models where the encode step dominates.

Vulkan rather than CUDA was chosen because:

- Works with the **open NVIDIA driver** (no CUDA toolkit dance).
- Works on **AMD and Intel GPUs** through Mesa.
- No Blackwell-specific gotchas (CUDA 12.8+ for sm_120 and the apt
  toolchain often lags).
- Single backend that covers most modern Linux desktops.

## Prerequisites

```bash
sudo apt install -y libvulkan-dev mesa-vulkan-drivers glslang-tools
```

Then add **`glslc`** (the GLSL → SPIR-V compiler whisper.cpp needs at
build time). Pop!_OS / Ubuntu noble does NOT ship `glslc` in any apt
package — `glslang-tools` provides `glslangValidator` only. You have to
build it from Google's `shaderc`:

```bash
git clone --depth 1 https://github.com/google/shaderc \
    ~/projects/contributions/shaderc
cd ~/projects/contributions/shaderc
./utils/git-sync-deps                    # fetches glslang, SPIRV-Tools, SPIRV-Headers
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release \
      -DSHADERC_SKIP_TESTS=ON \
      -DSHADERC_SKIP_EXAMPLES=ON \
      -DCMAKE_INSTALL_PREFIX=$HOME/.local ..
cmake --build . -j --target glslc_exe
install -Dm0755 glslc/glslc ~/.local/bin/glslc
```

About 5 min on a 24-core CPU. Verify:

```bash
glslc --version
```

## Rebuild whisper.cpp with Vulkan

Re-run the installer — it auto-detects `glslc` and builds with Vulkan
when present:

```bash
cd ~/projects/ormus-voice
./install.sh
```

Or manually:

```bash
SPIRV_HEADERS=$HOME/projects/contributions/shaderc/third_party/spirv-headers/include
cd $HOME/projects/contributions/whisper.cpp
rm -rf build
cmake -B build -S . \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_VULKAN=ON \
      "-DCMAKE_CXX_FLAGS=-I$SPIRV_HEADERS" \
      "-DCMAKE_C_FLAGS=-I$SPIRV_HEADERS"
cmake --build build -j --config Release
install -Dm0755 build/bin/whisper-cli ~/.local/bin/whisper-cli
```

The `-I$SPIRV_HEADERS` is a Pop!_OS quirk — `libvulkan-dev` doesn't
ship `<spirv/unified1/spirv.hpp>` so we point at shaderc's bundled
copy.

## Verify Vulkan is working

```bash
whisper-cli -m ~/.local/share/ormus-voice/models/ggml-base.en.bin \
    -f $HOME/projects/contributions/whisper.cpp/samples/jfk.wav \
    -nt 2>&1 | grep -E "Vulkan|use gpu|gpu_device"
```

You should see something like:

```
whisper_init_with_params_no_state: use gpu    = 1
whisper_init_with_params_no_state: gpu_device = 0
ggml_vulkan: Found 2 Vulkan devices:
ggml_vulkan: 0 = Intel(R) Graphics (ARL) | uma: 1 | …
ggml_vulkan: 1 = NVIDIA GeForce RTX 5070 Ti | uma: 0 | …
```

## ⚠ Device index matters more than you'd think

On systems with both an Intel iGPU and an NVIDIA dGPU, Mesa enumerates
the iGPU as device 0 and whisper-cli **defaults to device 0**. The
iGPU is significantly slower than the dGPU AND slower than a
24-core CPU. Running with default device on this kind of machine
makes things *worse* than CPU.

**Always pass `-dev <index>` (or set `VOICE_PASTE_GPU_DEVICE` in the
wrapper) to pick the right device.**

Measured on Sun (Core Ultra 9 275HX iGPU + RTX 5070 Ti dGPU), 11 s of
JFK audio, hot cache:

| Backend | base.en | medium.en |
|---|---|---|
| CPU build (no Vulkan), 24 threads | 0.62 s | ~3-5 s* |
| Vulkan, default device 0 (Intel iGPU) | **1.66 s** ← worse than CPU | **17 s** ← much worse |
| Vulkan, device 1 (RTX 5070 Ti) | **0.47 s** | **1.5 s** |
| Vulkan, `-ng` (force CPU on Vulkan binary) | 3.7 s | n/a |

\* CPU medium.en not benchmarked on this build; estimated from scaling.

The headline: **base.en is fine on either CPU or dGPU**; **medium.en
absolutely needs the dGPU** to be interactive.

## Wrapper integration

The wrapper script (`bin/whisper-paste`) exposes two env vars:

- `VOICE_PASTE_GPU=1` (default) → use GPU; `=0` → CPU only
- `VOICE_PASTE_GPU_DEVICE=1` (default) → Vulkan device index

The default of `1` assumes a Mesa enumeration where the dGPU is at
index 1. Adjust if your setup differs.

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
