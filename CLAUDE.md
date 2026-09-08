# Claude review guide

Claude reviews supplied Where2Go diffs independently. Read `AGENTS.md`, `docs/CURRENT_STATE.md`, and `docs/CODEMAP.md`; inspect only the assigned scope. Do not edit, commit, change Git state, or bypass permissions.

Use a model different from the implementation model. Report severity-ordered findings with file and line references, or state that none remain. Call out changed/deleted WoW API calls, events, or SavedVariables without a user live-QA record. Local Claude CLI success is evidence of invocation, not proof of review quality.
