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

### Added (toggle mode)
- `VOICE_PASTE_MODE=toggle` (now default) — first Super+V starts recording, second Super+V stops + transcribes + pastes. Closer to WisprFlow's UX.
- `VOICE_PASTE_MAX_SECONDS` (default 120) — hard cap on toggle-mode recordings if you forget to press stop.
- Per-user state at `${XDG_RUNTIME_DIR:-/tmp}/ormus-voice/recording.state` — auto-cleaned on logout.
- `VOICE_PASTE_MODE=fixed` preserves the original 8-second-record-then-paste flow as an opt-in.
- True hold-to-talk (press-down + press-up) is on the roadmap — needs key-up handling in ormus-term.

### Fixed
- Notification replacement — earlier versions left "✍️ Transcribing" stuck on screen for its 30 s timeout while a "✓ Pasted" briefly flashed alongside it. Each `note()` call now uses `--print-id`/`--replace-id` so subsequent notifications replace the previous one in-place. State persists across the toggle's two-process boundary via `${XDG_RUNTIME_DIR}/ormus-voice/notify.id`.
