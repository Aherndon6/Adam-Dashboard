# Claude Code Instructions: Adam-Dashboard

Standing law: read `AGENTS.md`. It is authoritative for architecture, standing rules, the Do Not Touch list, schema/migration conventions, and test gates.

Current state: read `CODEX_STATUS.md` for the active phase pointer, gates, and next-session starting point.

Session protocol:

- Start: read `AGENTS.md` and `CODEX_STATUS.md`. When available locally, read the AI Context files from ~/AI-Context (00, 02, 05, 08); never copy them into this repo, and do not assume the repo requires those files to exist. Confirm the active goal, affected files/functions, intended tests, and risk areas before changing code.
- End: propose a clear commit message, state test status and any manual e2e Adam must run, and update the `CODEX_STATUS.md` current-state pointer.

Guardrails:

- Adam approves pushes, prod Supabase migrations, destructive actions, secrets, and Context Manager patch application.
- Never copy AI Context files into this repo. Never commit personal context files.
