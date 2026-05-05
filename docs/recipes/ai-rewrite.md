# Recipe: AI rewrite hook

Pipe the raw whisper transcript through an LLM before paste. Cleans up
filler words, applies punctuation, interprets spoken punctuation
("comma", "period", "new line"), preserves technical terms verbatim.
Parity with WisprFlow's headline feature, with the bonus that you
control the model and the prompt.

## How it wires

The wrapper checks `VOICE_PASTE_REWRITE_COMMAND`. If set, the raw
transcript is piped to that command's stdin; whatever it prints on
stdout becomes the paste payload. The hook is failure-tolerant — if
the command exits non-zero, returns empty, or times out, voice paste
falls through to raw paste so the feature degrades gracefully when the
network or API is flaky.

```
arecord → whisper.cpp → silence/halluc filter → raw transcript
                                                    │
                                                    ▼ stdin
                                          $VOICE_PASTE_REWRITE_COMMAND
                                                    │ stdout
                                                    ▼
                                       cleaned text → bracketed paste
```

## Two reference scripts ship in `bin/`

| Script | Backend | Latency target | Cost |
|---|---|---|---|
| `voice-rewrite-claude` | Anthropic API (Haiku 4.5) | ~0.8–1.5 s | ~$0.0002/call (with prompt caching) |
| `voice-rewrite-ollama` | Local Ollama (3B model) | ~0.5–1.0 s | $0, ~2 GB disk for the model |

Both follow the same contract — read transcript on stdin, print
cleaned text on stdout, fall through to passthrough on failure.

## Setup — Claude API path (recommended for accuracy)

```bash
# 1. Get an Anthropic API key from https://console.anthropic.com
#    Save it where the script can find it:
mkdir -p ~/.credentials/anthropic
echo "sk-ant-..." > ~/.credentials/anthropic/api-token-default
chmod 600 ~/.credentials/anthropic/api-token-default

# 2. Verify the script works
echo "um hello there comma like how are you" | voice-rewrite-claude
# → Hello, how are you?

# 3. Wire into ormus-term
cosmic_dir=~/.config/cosmic/solutions.ormus.OrmusTerm/v1
echo -n '"VOICE_PASTE_REWRITE_COMMAND=voice-rewrite-claude $HOME/.local/bin/whisper-paste"' \
  > "$cosmic_dir/voice_paste_command"
```

That last step uses a shell-style `KEY=val cmd` invocation in
`voice_paste_command` — the env var propagates into the wrapper's
subshell.

The Claude prompt uses **prompt caching** on the system message, so
repeated rewrites within ~5 min hit the cache and run noticeably
faster than first-call latency.

## Setup — Ollama (local, no API)

```bash
# 1. Install ollama (already on Sun)
#    https://ollama.com/download

# 2. Pull a small model. llama3.2:3b is the recommended balance.
ollama pull llama3.2:3b

# 3. Verify
echo "um hello there comma like how are you" | voice-rewrite-ollama
# → Hello, how are you?

# 4. Wire into ormus-term (same as the API path, swap the script name)
echo -n '"VOICE_PASTE_REWRITE_COMMAND=voice-rewrite-ollama $HOME/.local/bin/whisper-paste"' \
  > ~/.config/cosmic/solutions.ormus.OrmusTerm/v1/voice_paste_command
```

### Model recommendations

| Model | Size | Speed (M.2 SSD, mid-range GPU) | Notes |
|---|---|---|---|
| `llama3.2:3b` | 2 GB | ~600 ms | Best general-purpose default |
| `qwen2.5:3b` | 2 GB | ~700 ms | Better with technical vocabulary, code identifiers |
| `phi3.5:3.8b` | 2.3 GB | ~800 ms | Strong fallback if the others over-paraphrase |
| `qwen2.5-coder:14b` | 9 GB | ~25 s ⚠ | Too slow for interactive use — don't use this for voice paste |

The 7B+ models add accuracy you usually don't need for transcript
cleanup. 3B is the sweet spot.

## Tunables (env vars)

Both scripts honour these:

| Env | Default | Effect |
|---|---|---|
| `VOICE_REWRITE_MODEL` | `claude-haiku-4-5` / `llama3.2:3b` | Model id |
| `VOICE_REWRITE_TIMEOUT` | `6` (claude) / `8` (ollama) | curl `--max-time` |
| `VOICE_REWRITE_DEBUG` | `0` | `1` → log inputs/responses to `~/.local/share/ormus-voice/rewrite.log` |

Plus script-specific:

| Env | Script | Effect |
|---|---|---|
| `ANTHROPIC_API_KEY` | claude | API key (overrides credential file lookup) |
| `ANTHROPIC_API_KEY_FILE` | claude | Path to file containing the key |
| `OLLAMA_HOST` | ollama | Base URL (default `http://localhost:11434`) |

## Disabling per-tab

The hook reads `VOICE_PASTE_REWRITE_COMMAND` from the subshell env. To
turn it off for a specific tab while keeping it on globally:

```bash
unset VOICE_PASTE_REWRITE_COMMAND
```

Useful when you want raw transcripts for technical input (file paths,
exact command strings) and don't want the model second-guessing them.

## Designing your own rewriter

The contract is the smallest possible interface — read stdin, print
stdout. Roll your own with anything:

```bash
#!/usr/bin/env bash
INPUT=$(cat)
# do anything with $INPUT...
echo "$INPUT" | tr '[:lower:]' '[:upper:]'   # silly: ALL CAPS rewrite
```

Realistic ideas worth trying:

- **Domain-specific cleanup** — pre-load a list of your team's technical
  vocabulary (proper nouns, internal codenames) into the system prompt
  so the model doesn't mis-correct "lromer" → "Roamer"
- **Multi-pass** — chain a transcript-cleaner script through an
  intent-classifier (e.g. Slack message vs shell command vs prose) and
  apply different formatting rules per intent
- **Streaming response** — use the API streaming endpoint and pipe
  partial output to whisper-paste's bracketed-paste; gives "live
  typing" UX at the cost of more wrapper plumbing

## Failure modes

The wrapper logs `⚠ Rewrite failed; raw paste` via `notify-send`
when the rewrite command exits non-zero or returns empty. Common
causes:

- **Missing API key** (`voice-rewrite-claude`) → ensure
  `ANTHROPIC_API_KEY` or `~/.credentials/anthropic/api-token-*` is
  readable
- **Network timeout** → bump `VOICE_REWRITE_TIMEOUT`
- **Wrong Ollama model name** → `ollama list` to confirm tag
- **Ollama model still loading** → first call after fresh start can be
  slow; subsequent calls hit the loaded model

Set `VOICE_REWRITE_DEBUG=1` and tail the log to see the raw API
response when a rewrite goes sideways.
