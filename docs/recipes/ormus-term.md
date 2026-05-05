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
export VOICE_PASTE_SECONDS=20
```

(Variables defined in your shell are inherited by the `sh -c` subshell
that runs `voice_paste_command`.)
