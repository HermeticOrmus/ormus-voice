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
- Toggle stop-phase never firing — first toggle commit shipped with `arecord ... &` + `disown` which removed the job from the shell's table but left arecord's inherited stdout/stderr FDs open. ormus-term's `tokio::process::Command::output()` waits for those FDs to drain, so the wrapper's exit didn't unblock `Task::perform` and the second Super+V press hit the in-flight guard. Replaced with `setsid -f arecord ... </dev/null >/dev/null 2>&1` so the FDs close immediately on spawn. Discovers the grandchild PID via a pgrep poll against the unique WAV path.

### Added (quality tuning)
- `vocabulary.txt` config at `~/.config/ormus-voice/vocabulary.txt` — proper nouns and technical terms biasing both stages of the pipeline. Seed file with ~80 words shipped.
- Stage 1: whisper acoustic biasing — wrapper passes `--prompt "$(cat vocab)" --carry-initial-prompt` to whisper-cli so the decoder hears proper nouns correctly. Token cap is `n_text_ctx/2` (~224 for `base.en`, ~448 for `medium.en`).
- Stage 2: rewriter linguistic correction — wrapper exports `VOICE_REWRITE_VOCABULARY` to the rewriter, which appends a "Known proper nouns" section to its system prompt. Defense in depth — catches mishearings whisper still produces.
- Stage 3: corrections journal — wrapper writes the last successful transcript to `~/.local/share/ormus-voice/last-paste.txt`. New `bin/voice-correct "what I actually meant"` command appends a `{ts, heard, actual}` JSONL row to `~/.local/share/ormus-voice/corrections.jsonl`. Future tuning reads this for vocabulary distillation, few-shot examples, or fine-tuning a local rewriter.
- New recipe `docs/recipes/quality-tuning.md` covering all three stages with what-to-include / what-to-avoid guidance.
