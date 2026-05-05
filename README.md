# Ormus Voice

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
| `VOICE_PASTE_SECONDS` | `8` | Recording duration |
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
| AI rewrite hook | ✓ headline feature | ? | planned |
| Push-to-talk | ? | ? | planned |

VibeTyper's product surface wasn't documented well enough on the public
web to fill in for sure — happy to update if anyone has links.

## Roadmap

- [ ] AI rewrite hook (`voice_paste_rewrite_command`) — pipe transcript
      through Claude / Ollama / any cleaner before paste
- [ ] Push-to-talk via key-up handling (currently fixed-duration only)
- [ ] Last-transcript replay (re-paste without re-recording)
- [ ] GPU Vulkan recipe verified end-to-end (currently CPU-validated)
- [ ] Recipes for Alacritty, kitty, gnome-terminal, foot

## License

MIT. See [`LICENSE`](LICENSE).

`whisper.cpp` (the transcription engine) is also MIT — same upstream
license, no copyleft entanglement.
