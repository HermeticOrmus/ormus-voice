# Recipe: Ormus Terminal (`Super+V`)

[Ormus Terminal](https://github.com/HermeticOrmus/ormus-term) is a
Claude-native fork of `pop-os/cosmic-term`. It exposes a built-in voice
paste action (`Action::VoicePaste`) bound to `Super+V` by default.

## Wire it up

1. Install Ormus Voice (this repo's `install.sh`).
2. Set the cosmic-config key:

   ```bash
   echo -n '"$HOME/.local/bin/whisper-paste"' > \
       ~/.config/cosmic/solutions.ormus.OrmusTerm/v1/voice_paste_command
   ```

3. Press `Super+V` in any tab. Speak for the recording window
   (default 8 s). Wait ~0.6 s. The transcript bracketed-pastes at the
   cursor.

## How the integration works

```
Super+V keypress
   │
   ▼ KeyBindAction::VoicePaste → Action::VoicePaste → Message::VoicePaste
   │
   ├─ Read self.config.voice_paste_command
   ├─ If empty → log warn, return
   ├─ If voice_paste_active.is_some() → ignore (debounce)
   ├─ Override active tab title → "● Voice ▸ recording…"
   ├─ Spawn cosmic::Task::perform(async sh -c $cmd)
   │
   ▼ stdout arrives as Result<String, String>
   ├─ Restore tab title
   ├─ Read TermMode::BRACKETED_PASTE on focused tab
   ├─ Wrap in CSI 200~/201~ if set, else send raw
   └─ terminal.input_no_scroll(bytes) — paste at cursor
```

Source: `ormus-term/src/main.rs:2677-2757`,
`ormus-term/src/shortcuts.rs:500`.

## Tab-title indicator

While voice paste is in flight, the active tab's title flips to
`● Voice ▸ recording…` so you can see at a glance which tab will
receive the paste. The 2-second `RefreshTabTitles` tick checks
`voice_paste_active` before overwriting, and the title is restored on
both success and failure paths.

## Working alongside SSH / tmux

Because the transcript bytes flow through the local terminal's PTY,
voice paste works seamlessly inside:

- `ssh remote-host` — paste lands in the remote shell, not the local one
- `tmux attach` — paste lands in the focused tmux pane
- nested combinations: `ssh → tmux → distrobox enter → claude` all
  receive the paste correctly

This is the core reason Ormus Voice exists as a terminal-first project
instead of a generic dictation tool. Commercial alternatives (WisprFlow,
SuperWhisper) all break at the SSH boundary because they inject via OS
clipboard + simulated Ctrl-V, which the local terminal absorbs before it
reaches the remote shell.

## Tuning for the tab you're in

You can override config per-tab by exporting env vars before launching
the wrapper. Example: a tab dedicated to Claude prompts where you want
longer recording time:

```bash
# In a Claude tab's startup
export VOICE_PASTE_MAX_SECONDS=300   # 5-minute cap in toggle mode
```

(Variables defined in your shell are inherited by the `sh -c` subshell
that runs `voice_paste_command`.)

## Toggle vs fixed recording

Two recording modes:

- **`VOICE_PASTE_MODE=toggle`** (default) — first Super+V starts
  recording, second Super+V stops + transcribes + pastes. Closer to
  WisprFlow's UX. Recording caps at `VOICE_PASTE_MAX_SECONDS` (default
  120 s) if you forget to press again. The system notification shows
  "🎙 Recording — press Super+V again to stop" with that long timeout
  so you can see the state without the indicator going stale.

- **`VOICE_PASTE_MODE=fixed`** — record `VOICE_PASTE_SECONDS` (default
  8 s) then auto-transcribe. Single-press flow, useful when you know
  in advance how long the message is.

To set globally:

```bash
echo -n '"VOICE_PASTE_MODE=fixed $HOME/.local/bin/whisper-paste"' \
  > ~/.config/cosmic/solutions.ormus.OrmusTerm/v1/voice_paste_command
```

State for toggle mode lives at `${XDG_RUNTIME_DIR:-/tmp}/ormus-voice/`.
A stale state file from a crashed recording (e.g. machine slept
mid-take) will cause the next press to enter the stop phase with no
audio — it will notify "🤫 Empty" and clear cleanly. After that, a
normal new press starts fresh.

### Hold-to-talk (the WisprFlow UX)

Ormus Terminal builds from `local/all-features` (commit picks up
`feat(voice): hold-to-talk via key-up handling`) fire
`Action::VoicePasteRelease` on key-up of the same binding that fires
`Action::VoicePaste` on key-down. The terminal sets
`VOICE_PASTE_PHASE=start` env var on the start invocation and
`VOICE_PASTE_PHASE=stop` on the stop invocation. The wrapper honors
those explicitly (overrides any `VOICE_PASTE_MODE` setting), so
hold-to-talk works regardless of the user's mode preference.

UX flow:

1. **Press and hold Super+V** — recording starts immediately, tab
   title flips to `● Voice ▸ recording…`, system notification shows
   "🎙 Recording — release Super+V to stop".
2. **Speak.**
3. **Release Super+V** — recording stops, transcription runs,
   transcript bracketed-pastes at cursor.

If you only tap briefly (sub-100 ms), the recording is too short for
useful audio and the silence gate eats it cleanly.

### Mode override

The Rust side always sends `VOICE_PASTE_PHASE=start`/`stop` for hold
UX. To opt out and use the wrapper's own MODE detection (toggle or
fixed) instead, you'd need to strip the env var — most users won't.
