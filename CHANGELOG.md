# Changelog

## Unreleased

### Added
- Initial public release.
- Wrapper script (`bin/whisper-paste`) wiring arecord → silence gate → whisper.cpp → hallucination filter → stdout.
- One-shot installer (`install.sh`) that builds whisper.cpp, installs the binary, downloads `ggml-base.en`, and links the wrapper.
- Auto-detection of `glslc` in `install.sh` — Vulkan backend is built when present, CPU-only otherwise.
- `VOICE_PASTE_GPU` and `VOICE_PASTE_GPU_DEVICE` env vars for explicit device selection (defaults to device 1, the dGPU on hybrid iGPU+dGPU systems).
- Recipe for Ormus Terminal `Super+V` integration.
- GPU Vulkan upgrade recipe with shaderc/glslc bootstrap (Pop!_OS / Ubuntu noble doesn't ship `glslc` in apt).
- Architecture and design-decision documentation.

### Notes
- On hybrid iGPU + dGPU systems, Vulkan device 0 is typically the iGPU and is *slower than CPU*. The wrapper defaults to `-dev 1` to force the dGPU. Override via `VOICE_PASTE_GPU_DEVICE` if your enumeration differs.
