# Consul — Claude Code

This project is shared between agents: the canonical service guide lives in
`AGENTS.md` (imported below) and the Consul skills live in `.claude/skills/`
(also registered for opencode via `opencode.jsonc`).

Claude Code priorities:

- Consult `.claude/skills/` first — Claude auto-invokes a skill when a task
  matches its description.
- Consult the ecosystem documentation in the
  [sca-docs](https://github.com/sca-templates/sca-docs) repository before
  documenting or touching topology/ports/networks — start at
  `00-ecosystem/conventions.md` and `04-infrastructure/INDEX.md`, and keep the
  vault in sync when this repo changes.
- Run `make register && make validate` before finishing any change that
  touches `scripts/services.txt` or the registration flow, and report the
  result.

@AGENTS.md
