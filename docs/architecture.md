# Architecture

## Pipeline

```
key trigger (terminal-side)
   │
   ▼
voice_paste_command (sh -c)
   │
   ├─ arecord -f S16_LE -r 16000 -c 1 -t wav  ──►  TMP_WAV
   │  (16 kHz mono — whisper's native rate; skip resampling)
   │
   ├─ sox -n stat → RMS amplitude
   │  if RMS < threshold: print nothing, exit 0     ◄── silence gate
   │
   ├─ whisper-cli -m model -f WAV -nt -np
   │                                                ◄── transcribe
   │
   ├─ hallucination filter
   │  - exact-match list ("you", "thank you", "music", …)
   │  - regex: same word ≥4× in a row (repetition cascade)
   │  if matched: print nothing, exit 0
   │
   └─ echo $TRANSCRIPT  ──►  stdout
                              │
                              ▼
                      terminal captures stdout, bracketed-pastes into
                      the focused tab's PTY
```

## Why PTY injection beats clipboard injection

Three commercial dictation tools dominate the AI-dictation space (WisprFlow,
SuperWhisper, VibeTyper). All three use the same OS-level injection
pattern:

1. Save current clipboard contents.
2. Write transcript to clipboard.
3. Simulate Cmd-V / Ctrl-V keystroke into focused window.
4. Restore clipboard ~500 ms later.

This pattern is structurally fragile. Three failure modes are unavoidable:

**Mode 1: terminal emulator boundary.** SSH, tmux, screen, mosh, distrobox,
container shells — every layer past the local terminal has its own
conception of "paste" and may not respond to the simulated Ctrl-V. From
WisprFlow's official documentation: *"Direct paste fails in WSL terminals,
SSH sessions, tmux, screen."* They acknowledge this and ship no workaround.

**Mode 2: clipboard race.** Anything that touches the clipboard during the
~500 ms window (clipboard managers like Maccy, secondary tools, browser
extensions, accessibility software) can inject its content into the
"paste" or interfere with the restore.

**Mode 3: focus race.** If the focused window changes between transcript
write and paste-keystroke send (e.g. notification steals focus), the
transcript lands in the wrong app — sometimes a destructive surface like
Slack or a chat field.

Ormus Voice avoids all three by **never touching the OS clipboard and never
simulating a keystroke**. The transcript bytes are written into the
terminal's PTY through the same path as typed input. The terminal
emulator's native bracketed-paste handling kicks in if the running program
advertises support; otherwise the bytes flow as raw input. SSH, tmux,
screen, mosh — none of them care, because the transcript is already
inside the local terminal's input pipeline by the time those layers
process it.

## The contract is dead simple

The wrapper is required to do exactly one thing: **print the transcript on
stdout, and nothing else**. Empty stdout means "paste nothing" (used by
the silence gate and hallucination filter to fail closed). The terminal
side reads stdout, frames the bytes with bracketed-paste markers if
appropriate, and writes them to the PTY.

This means the entire pipeline can be replaced by anything that respects
that contract:

- swap whisper.cpp for faster-whisper, MLX whisper, an API service, vosk,
  a remote whisper-server
- pipe the transcript through Claude / Ollama for cleanup before printing
- pre-process the audio (noise reduction, gain, mic selection)
- chain multiple transcription engines and pick the highest-confidence
  result

The terminal doesn't care. It runs `sh -c $voice_paste_command`, captures
stdout, pastes.

## Bracketed paste

Programs running inside the terminal can advertise support for
bracketed paste by setting `BRACKETED_PASTE` mode (DECSET 2004). When
set, the terminal frames pastes with `CSI 200~` ... `CSI 201~` so the
program knows "this is pasted text, not typed". This matters for:

- **Claude Code** — recognises pastes and treats them as a single
  message turn instead of typing.
- **vim insert mode** — disables auto-indent / smart-tab so pasted code
  doesn't stair-step.
- **bash with `set enable-bracketed-paste on`** — the shell prints the
  paste literally instead of executing line-by-line.

When the running program doesn't advertise `BRACKETED_PASTE`, bytes are
sent raw — which still works, just without the "this is paste"
disambiguation.

## File layout

```
$XDG_DATA_HOME/ormus-voice/models/    models (gitignored, downloaded by install.sh)
~/.local/bin/whisper-cli              transcription binary (built from whisper.cpp)
~/.local/bin/whisper-paste            wrapper script
~/projects/contributions/whisper.cpp  source checkout (default; configurable)
```

Everything respects XDG. Nothing requires sudo for the default CPU
build — Vulkan GPU builds need `glslc` from `glslang-tools` /
`shaderc`, which is the only system-level dependency.
