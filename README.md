<p align="center">
  <img src="https://ormus.solutions/mascot/pixellab_liquid_to_terminal.gif" alt="Ormus Voice" width="128" style="image-rendering: pixelated;" />
</p>

<h1 align="center">Ormus Voice</h1>

<p align="center">
  <em>Voice paste for Linux terminals — works inside SSH, tmux, screen because it injects into the PTY, not the OS clipboard. whisper.cpp pipeline, sub-second latency on CPU.</em>
</p>

<p align="center">
  <a href="https://github.com/HermeticOrmus/ormus-voice/stargazers"><img src="https://img.shields.io/github/stars/HermeticOrmus/ormus-voice?style=flat-square&color=aa8142" alt="Stars" /></a>
  <a href="https://github.com/HermeticOrmus/ormus-voice/blob/main/LICENSE"><img src="https://img.shields.io/github/license/HermeticOrmus/ormus-voice?style=flat-square&color=aa8142" alt="License" /></a>
  <a href="https://github.com/HermeticOrmus/ormus-voice/commits"><img src="https://img.shields.io/github/last-commit/HermeticOrmus/ormus-voice?style=flat-square&color=aa8142" alt="Last Commit" /></a>
  <img src="https://img.shields.io/badge/Claude_Code-aa8142?style=flat-square&logo=anthropic&logoColor=white" alt="Claude Code" />
</p>

---
Voice paste for Linux terminals. Press a key, speak, get the transcript
inserted at your cursor — and unlike every commercial alternative, it
works inside SSH, tmux, screen, mosh, and distrobox.

## Why it works where others don't

Commercial dictation tools (WisprFlow, et al.) use OS-level clipboard
paste injection: they save your clipboard, write the transcript to it,
simulate a paste keystroke into the focused window, then restore the
clipboard ~500 ms later. That race breaks past the terminal emulator
boundary — by their own docs, *"direct paste fails in WSL terminals,
SSH sessions, tmux, screen."*

Ormus Voice ignores the OS clipboard entirely. The transcript is
written **directly into the terminal's PTY**, the same pipeline your
keystrokes flow through. Anything that handles typing handles this:
local shells, remote shells, tmux panes, screen windows, container
shells, mosh, byobu, ssh-into-tmux-into-distrobox.

## Pipeline

```
key trigger
   │
   ▼
arecord ──► (silence gate, sox) ──► whisper.cpp ──► hallucination filter ──► stdout
                                                                                │
                                                                                ▼
                                                              your terminal pastes it
                                                              (bracketed-paste when
                                                              the running program
                                                              advertises it)
```

The wrapper script is bash. The transport is stdout. The terminal is
whatever you configured to invoke the wrapper. Want to swap whisper.cpp
for faster-whisper, MLX whisper, an API-based service, or pipe the
transcript through Claude / Ollama for cleanup before paste? Edit one
file.

## Performance

Measured on Sun (Core Ultra 9 275HX, 24 cores + RTX 5070 Ti), 11 s of
JFK audio, hot cache:

| Backend | base.en | medium.en |
|---|---|---|
| openai-whisper (Python) | ~5 s | minutes |
| whisper.cpp CPU (24 threads) | **0.6 s** | ~3–5 s |
| whisper.cpp Vulkan (RTX 5070 Ti) | **0.47 s** | **1.5 s** |
| Vulkan default device 0 (Intel iGPU) | 1.66 s ← *worse than CPU* | 17 s |

Two takeaways:

1. **Sub-second voice paste is reachable on CPU alone** — no GPU
   needed for `base.en`, just whisper.cpp's native AVX-512 + OpenMP.
2. **GPU device selection matters more than you'd think.** On hybrid
   iGPU + dGPU systems, Vulkan defaults to the iGPU (device 0), which
   is *slower than CPU*. The wrapper auto-passes `-dev 1` to force the
   dGPU. See [`docs/recipes/gpu-vulkan.md`](docs/recipes/gpu-vulkan.md)
   for the full story including the Pop!_OS-specific glslc gotcha.

## Install

One command:

```bash
git clone https://github.com/HermeticOrmus/ormus-voice ~/projects/ormus-voice
cd ~/projects/ormus-voice
./install.sh
```

The installer:
1. Clones and builds [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (CPU, ~3 min)
2. Installs `whisper-cli` to `~/.local/bin/`
3. Downloads `ggml-base.en.bin` (142 MB) to `~/.local/share/ormus-voice/models/`
4. Installs the wrapper to `~/.local/bin/whisper-paste`

System dependencies you need first (Pop!_OS / Ubuntu):

```bash
sudo apt install -y alsa-utils sox cmake build-essential libnotify-bin
```

## Wire to a terminal

### Ormus Terminal (`Super+V`)

```bash
echo -n '"$HOME/.local/bin/whisper-paste"' > \
    ~/.config/cosmic/solutions.ormus.OrmusTerm/v1/voice_paste_command
```

See [`docs/recipes/ormus-term.md`](docs/recipes/ormus-term.md) for the
full integration story.

### Other terminals

Any terminal that can bind a key to "run a command and paste its
stdout" works. For terminals that don't expose that natively, the
fallback is `xdotool type` / `wtype` (sub-optimal — loses the SSH/tmux
benefit). See [`docs/recipes/`](docs/recipes/) for per-terminal recipes
as they're added.

## Configuration (env vars)

| Var | Default | Effect |
|---|---|---|
| `VOICE_PASTE_MODE` | `toggle` | `toggle` (press to start, press to stop) or `fixed` (record N seconds then auto-paste) |
| `VOICE_PASTE_SECONDS` | `8` | Fixed-mode recording length |
| `VOICE_PASTE_MAX_SECONDS` | `120` | Toggle-mode hard cap if you forget to press stop |
| `VOICE_PASTE_MODEL` | `base.en` | Model name (`tiny.en`, `base.en`, `small.en`, `medium.en`) |
| `VOICE_PASTE_MODEL_PATH` | `${XDG_DATA_HOME}/ormus-voice/models/ggml-${MODEL}.bin` | Explicit model path |
| `VOICE_PASTE_THREADS` | `$(nproc)` | whisper-cli thread count |
| `VOICE_PASTE_RMS_MIN` | `0.005` | Silence-gate threshold |

## Compared to alternatives

| | WisprFlow | VibeTyper | Ormus Voice |
|---|---|---|---|
| Native Linux | ✗ (WSL only) | ? | ✓ |
| Works in SSH / tmux / screen | ✗ documented broken | ? | ✓ |
| Open source | ✗ | ✗ | ✓ (MIT) |
| Touches your clipboard | ✓ saves+restores | ? | ✗ direct PTY input |
| Bracketed paste | ✗ | ? | ✓ |
| Hallucination filter | ? | ? | ✓ silence gate + repetition / known-output filter |
| Backend swappable | ✗ | ✗ | ✓ (one bash file) |
| AI rewrite hook | ✓ headline feature | ? | ✓ (Claude API + Ollama) |
| Toggle (press start / press stop) | ✓ | ? | ✓ default mode |
| Push-to-talk (hold) | ? | ? | planned (needs key-up handling) |

VibeTyper's product surface wasn't documented well enough on the public
web to fill in for sure — happy to update if anyone has links.

## AI rewrite hook (the headline feature)

Pipe the raw transcript through an LLM to clean up filler, apply
punctuation, and interpret spoken punctuation ("comma", "period",
"new line") before paste. Same idea as WisprFlow's headline feature,
with the bonus that you control the model and the prompt.

```
"um hello there comma like how are you"
   ↓ raw whisper transcript
   ↓ pipe through voice-rewrite-claude (Haiku 4.5) or voice-rewrite-ollama (local)
"Hello, how are you?"
   ↓ paste at cursor
```

Two reference scripts ship in `bin/`:

- **`voice-rewrite-claude`** — Anthropic API + Haiku 4.5 with prompt
  caching. ~0.8–1.5 s per call, ~$0.0002 per call.
- **`voice-rewrite-ollama`** — local Ollama. ~0.5–1.0 s with
  `llama3.2:3b`. No network, no per-call cost.

Wire either by setting `VOICE_PASTE_REWRITE_COMMAND` — the wrapper
pipes the transcript to that command's stdin and uses its stdout as
the paste payload. Failures fall through to raw paste so a flaky
network or missing API key never breaks voice paste — you just lose
the cleanup. Full guide:
[`docs/recipes/ai-rewrite.md`](docs/recipes/ai-rewrite.md).

## Roadmap

- [x] AI rewrite hook (Claude API + Ollama scripts)
- [x] Toggle mode (press to start, press to stop)
- [ ] True push-to-talk (hold) — needs key-up handling in ormus-term
- [ ] Last-transcript replay (re-paste without re-recording)
- [ ] Recipes for Alacritty, kitty, gnome-terminal, foot

## License

MIT. See [`LICENSE`](LICENSE).

`whisper.cpp` (the transcription engine) is also MIT — same upstream
license, no copyleft entanglement.

---

## Part of the Libre Open-Source Stack for Claude Code

This repository is part of a growing family of open-source toolkits for Claude Code.

### Libre suite — comprehensive plugin bundles

- [LibreUIUX-Claude-Code](https://github.com/HermeticOrmus/LibreUIUX-Claude-Code) — UI/UX development (152 agents, 70 plugins, 76 commands, 74 skills)
- [LibreArch-Claude-Code](https://github.com/HermeticOrmus/LibreArch-Claude-Code) — Software architecture and system design
- [LibreCopy-Claude-Code](https://github.com/HermeticOrmus/LibreCopy-Claude-Code) — Technical writing and documentation engineering
- [LibreDevOps-Claude-Code](https://github.com/HermeticOrmus/LibreDevOps-Claude-Code) — DevOps engineering and infrastructure automation
- [LibreEmbed-Claude-Code](https://github.com/HermeticOrmus/LibreEmbed-Claude-Code) — Embedded systems, firmware, and IoT development
- [LibreFinTech-Claude-Code](https://github.com/HermeticOrmus/LibreFinTech-Claude-Code) — Financial technology development
- [LibreGEO-Claude-Code](https://github.com/HermeticOrmus/LibreGEO-Claude-Code) — AI-search optimization (ChatGPT, Perplexity, Gemini, Google AI Overviews)
- [LibreGameDev-Claude-Code](https://github.com/HermeticOrmus/LibreGameDev-Claude-Code) — Game development across Godot, Unity, Unreal
- [LibreMLOps-Claude-Code](https://github.com/HermeticOrmus/LibreMLOps-Claude-Code) — ML engineering and AI operations
- [LibreMobileDev-Claude-Code](https://github.com/HermeticOrmus/LibreMobileDev-Claude-Code) — Mobile app development (Flutter, React Native, native iOS, native Android)
- [LibreSecOps-Claude-Code](https://github.com/HermeticOrmus/LibreSecOps-Claude-Code) — Security operations

### Skills mini-repos — single CLAUDE.md drop-ins

- [vibe-engineer-skills](https://github.com/HermeticOrmus/vibe-engineer-skills) — Direct AI codegen well (hypothesis → scope → validate → reject working-but-wrong)
- [markdown-discipline-skills](https://github.com/HermeticOrmus/markdown-discipline-skills) — Strip AI-slop from markdown (no em dashes, no marketing fluff)
- [shell-safety-skills](https://github.com/HermeticOrmus/shell-safety-skills) — `set -euo pipefail` discipline + 15 failure-mode examples
- [commit-standard-skills](https://github.com/HermeticOrmus/commit-standard-skills) — Ormus Commit Standard v1.0 + commit-msg hook + commitlint
- [unwoke-skills](https://github.com/HermeticOrmus/unwoke-skills) — Strip AI theater (ten sins to eliminate, symmetric engagement)
- [python-conventions-skills](https://github.com/HermeticOrmus/python-conventions-skills) — Modern Python 3.11+ (types, pathlib, async, ruff, mypy, uv)
- [typescript-conventions-skills](https://github.com/HermeticOrmus/typescript-conventions-skills) — TypeScript strict mode, discriminated unions, Result types
- [hermetic-laws-skills](https://github.com/HermeticOrmus/hermetic-laws-skills) — Seven Hermetic Principles applied to engineering
- [riper-workflow-skills](https://github.com/HermeticOrmus/riper-workflow-skills) — Research / Innovate / Plan / Execute / Review systematic dev
- [six-day-cycle-skills](https://github.com/HermeticOrmus/six-day-cycle-skills) — Sustainable shipping cadence with mandatory rest
- [token-optimization-skills](https://github.com/HermeticOrmus/token-optimization-skills) — Claude Code token + context optimization
- [osint-skills](https://github.com/HermeticOrmus/osint-skills) — OSINT research methodology (multi-wave investigative spiral)
- [calcinate-skills](https://github.com/HermeticOrmus/calcinate-skills) — Stage 1 of the Magnum Opus (burn project bloat)
- [claude-md-overhaul-skills](https://github.com/HermeticOrmus/claude-md-overhaul-skills) — Audit CLAUDE.md and MEMORY.md against caps
- [session-handoff-skills](https://github.com/HermeticOrmus/session-handoff-skills) — Session handoff + pickup discipline
- [naming-skills](https://github.com/HermeticOrmus/naming-skills) — Product naming methodology (mine the brand's vocabulary)
- [magnum-opus-skills](https://github.com/HermeticOrmus/magnum-opus-skills) — Seven-stage alchemy applied to project transformation

### Template source

- [andrej-karpathy-skills](https://github.com/HermeticOrmus/andrej-karpathy-skills) — the canonical single-file CLAUDE.md pattern (fork of jiayuan_jy's original)

Star the family, not just one — that's how the suite stays coherent.
