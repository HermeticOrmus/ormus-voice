# Recipe: Quality tuning

Three independent levers raise transcription accuracy. The first two
ship with v0.4 and are auto-on when their config files exist. The
third is a long-term active-learning loop that requires periodic
review.

| Stage | Mechanism | Effect | Config |
|---|---|---|---|
| 1. Acoustic | `whisper-cli --prompt` | Biases what whisper *hears* — proper nouns and technical terms come back spelled correctly | `~/.config/ormus-voice/vocabulary.txt` |
| 2. Linguistic | Rewriter system prompt | Catches mishearings whisper still produces; canonical-spelling correction | Same vocabulary file |
| 3. Feedback loop | `voice-correct` + corrections journal | Records "what I actually meant" for future few-shot tuning | `~/.local/share/ormus-voice/corrections.jsonl` |

## Stage 1 — vocabulary biasing

`whisper-cli` accepts an `--prompt` arg that the model treats as
"context the user would say." It biases the acoustic decoder so close
homophones resolve toward the prompted vocabulary.

The wrapper auto-loads `${XDG_CONFIG_HOME:-~/.config}/ormus-voice/vocabulary.txt`,
strips comments and blank lines, joins on space, and passes the result
as `--prompt "..." --carry-initial-prompt` (so it applies across audio
chunks for long recordings).

A seed file is included. Edit it freely:

```
~/.config/ormus-voice/vocabulary.txt
```

Format:

```
# Comments start with #
# One concept per line, comma-separated within a line is fine

Ormus, Hermetic Ormus, Athanor
James Loewen, Diego Bodart, Laura Römer
whisper.cpp, ggml, Vulkan, glslc
```

Whisper has a token limit of `n_text_ctx/2` for the prompt — about
**224 tokens for `base.en`**, **448 for `medium.en`**. Roughly 100–200
short terms is the practical ceiling. Past that, drop low-frequency
items.

What to put in the file:

- Proper nouns whisper mishears (people, projects, products)
- Domain-specific technical terms (your stack, your codebase)
- Acronyms you say a lot (TMS, OSC, PTY, IDE specifics)
- Common phrases that act as anchors (full project names rather than
  abbreviations)

What NOT to put in:

- Common English words — they compete with the model's prior and
  reduce accuracy on normal prose
- Generic technical terms (function, variable, list) — already known
- Jokes / slang you say once — pollutes the prior

Override the file location:

```bash
export VOICE_PASTE_VOCABULARY_FILE=~/.config/ormus-voice/work-vocab.txt
```

## Stage 2 — rewriter as backup canonical-speller

Even with `--prompt`, whisper occasionally outputs `Talin` for `Talon`
or `Karin` for `Corvin`. The rewriter receives the same vocabulary as
a "Known proper nouns (correct any near-homophones to these canonical
spellings)" line in its system prompt, so the rewriter cleans up what
whisper missed.

This is automatic — when both `VOICE_PASTE_REWRITE_COMMAND` and
the vocabulary file are configured, the wrapper exports the
`VOICE_REWRITE_VOCABULARY` env var to the rewriter. Both
`voice-rewrite-claude` and `voice-rewrite-ollama` honour it.

## Stage 3 — corrections journal (long-term tuning)

After every successful voice paste, the wrapper writes the final
transcript to:

```
~/.local/share/ormus-voice/last-paste.txt
```

When a paste was wrong, run `voice-correct` with what you actually
meant:

```bash
voice-correct "Send the message to Talon, not the agent named Talin."
```

The script logs a JSONL row to:

```
~/.local/share/ormus-voice/corrections.jsonl
{"ts":"2026-05-07T...","heard":"Send the message to Talin not the agent named Talin","actual":"Send the message to Talon, not the agent named Talin."}
```

Three things get easier with this journal:

1. **Vocabulary distillation.** Periodically scan the journal for
   recurring `heard → actual` swaps. Add the actual term to
   `vocabulary.txt`. Future transcriptions get the term right at the
   acoustic stage, not the rewrite stage.

2. **Few-shot prompting.** A future rewrite-script variant can read
   the last N corrections and inject them as in-context examples
   ahead of the current transcript, so the model has concrete
   "you've previously corrected X to Y" memory.

3. **Fine-tuning.** With ~hundreds of correction pairs, you can
   fine-tune a small local model on the diff and run that as the
   rewriter via `voice-rewrite-ollama` — model that's been trained
   on your own correction history.

The journal is plain JSONL so it's trivial to grep, transform, or
ship to a model directly.

## Diagnostics

Set `VOICE_REWRITE_DEBUG=1` to log every rewriter call (full
input/response) to:

```
~/.local/share/ormus-voice/rewrite.log
```

Useful when a transcription "looks fine" but the rewriter is making
it worse — you can see exactly what the model received and produced.

For whisper-side debugging, drop `2>/dev/null` from the wrapper's
whisper-cli invocation and re-run; whisper logs the segment-level
decoder choices and confidence scores to stderr.
