# Context size test, 2026-11-01

`ctxtest.py qwen3.5:9b 32768 65536 81920` with `OLLAMA_FLASH_ATTENTION=1` and
`OLLAMA_KV_CACHE_TYPE=q8_0`, voice tools (whisper, kokoro) running, GTX 1080 Ti (11 GB).
Each test fills about 90% of the window with filler hiding one fact a quarter of the way in.

| Context | Fully on GPU? | GPU used (whole card) | Recall | Read | Write | Time |
|---|---|---|---|---|---|---|
| 32k | ✅ | 9,030 MiB | ✅ | 682 tok/s | 46.0 tok/s | 48 s |
| 64k | ✅ | 9,735 MiB | ✅ | 506 tok/s | 40.1 tok/s | 125 s |
| **80k** | ✅ | 10,087 MiB | ✅ | 447 tok/s | 38.6 tok/s | 175 s |
| 96k | ❌ 90% GPU | 10,336 MiB | (invalid run) | — | — | — |

Raw output: `ctxtest-output.txt`. The 96k figure comes from the first, invalid run (prompts
overflowed the window and were cut), which still showed where the model spills to the CPU.

- **The model's own maximum is 262,144 tokens.** The GPU, not the model, sets the limit.
- **Context memory:** qwen3.5 stores per-token data in only 8 of its 32 layers. With an 8-bit
  cache that is 17 KiB per token (1,360 MiB at 80k, confirmed in Ollama's log).
- **Window size doesn't slow down a given question.** The same 20,061-token prompt read in
  26.6 s at 32k and 27.0 s at 80k. Slowdown comes from how much text is actually in the
  window: each token is compared with all earlier ones.
- **A prompt longer than the window is cut silently.** Ollama keeps about half the window and
  drops the beginning, with no error.

Chosen setting: `OLLAMA_CONTEXT_LENGTH=81920`.
