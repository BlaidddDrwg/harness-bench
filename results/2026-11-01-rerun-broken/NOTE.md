# Rerun of Claude Code and OpenCode, 2026-11-01 (Claude Code results invalid)

Run after installing ripgrep and setting `CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768`.

- **Claude Code: invalid.** With a 32k window and no `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, Claude
  Code reserved 32,000 tokens for output (its default for unknown models), compacted every
  other turn ("Autocompact is thrashing", "Prompt is too long") and scored 4 of 7.
  Fixed in run 3 with `CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192`.
- **OpenCode: valid**, ripgrep working: 6 of 7 (failed `csv`, 699.75 instead of 700).
