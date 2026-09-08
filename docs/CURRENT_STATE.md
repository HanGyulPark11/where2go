# Current state

Where2Go ranks dungeon or raid content by the share of eligible loot matching a character's saved preferred items. Direct-drop and Voidcore views remain separate. The manifest targets Interface `120100` (Midnight Season 2).

The TOC loads 23 Lua modules. The registered Lua suite contains 19 passing specs, including the documentation map check; Luacheck covers 23 addon Lua files with zero baseline warnings/errors.

The merged two-window UI redesign passed automated checks, but its live WoW checklist remains open in [UI_REDESIGN_QA.md](UI_REDESIGN_QA.md). `BONUS_ROLL_RESULT` behavior for a real Voidcore roll is also unconfirmed; see [TODO.md](../TODO.md). Unit tests do not make either live behavior verified.

Entry points: `/where2go` or `/w2g` toggle recommendations; `/where2go browse` opens the browser; `pref`, `compare`, and `genspec [reset]` are implemented in `Core/Init.lua`. Historical plans/specs under `docs/superpowers/` are context, not the current contract.

The repository agent harness now provides bounded Claude review evidence, content- and baseline-bound completion manifests, required-check and live-QA routing, protected-branch and unrelated-change guards, and explicit selected-file commits. Its authoritative PowerShell runner currently passes. An earlier Claude attempt was quota-blocked and the GPT-5.5 fallback later stopped on its usage limit. On 2026-09-08 at 11:25 KST, Claude Sonnet 4.6 completed a real 24-turn inference (`is_error: false`) and returned `changes_requested`; its enclosing JSON code fence exposed an adapter parsing issue. The parser now accepts one enclosing JSON fence and rejects malformed output, and the manifest generator rejects empty check lists. Review and verification outcomes are recorded per task in ignored `.harness` evidence; commits require a passing gate. Project-local `.codex` policy files parse as TOML, but native activation from the repository directory is also unverified.
