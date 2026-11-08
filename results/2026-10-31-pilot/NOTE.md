# Pilot run, 2026-10-31 (not valid for comparison)

- Model: qwen3.5:9b, Ollama 0.40.13, 32k context, GTX 1080 Ti.
- Both harness sandboxes failed to start: Ubuntu's AppArmor setting
  `kernel.apparmor_restrict_unprivileged_userns=1` blocks bubblewrap.
  - Codex refused to run commands (0/7, a setup failure, not a model result).
  - Claude Code fell back to running commands unsandboxed.
- Claude Code used the user's personal configuration (CLAUDE.md, plugins, MCP servers),
  which added about 13,400 tokens of context and confused the model on `replace`.
  With a clean configuration its overhead is 11,059 tokens.
  Its `replace` log is not included, because it quoted that personal configuration.
