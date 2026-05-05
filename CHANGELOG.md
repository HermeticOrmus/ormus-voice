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

### Added (AI rewrite hook)
- `VOICE_PASTE_REWRITE_COMMAND` env var on the wrapper — when set, raw transcript is piped through that command before paste; stdout becomes the paste payload.
- `bin/voice-rewrite-claude` — reference script using Anthropic API + Claude Haiku 4.5 with prompt caching on the system message.
- `bin/voice-rewrite-ollama` — local-only alternative using a small Ollama model (recommended: `llama3.2:3b`).
- `docs/recipes/ai-rewrite.md` — setup guide, model recommendations, tunables, failure modes.
- Failure-tolerant wiring — if the rewriter exits non-zero or returns empty, the wrapper falls through to raw paste so a flaky network or missing API key never breaks voice paste; only the cleanup is lost.
