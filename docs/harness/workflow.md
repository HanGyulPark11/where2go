# Harness workflow

The harness records completion evidence without granting extra authority. Evidence is stored under ignored `.harness/`, outside selected commit files.

Give each worker a bounded brief rather than the parent conversation: objective, selected files, behavior/contracts to preserve, required checks, and the exact evidence or findings to return. Include only the repository context needed for that scope.

First run a fresh read-only review. For example:

```powershell
.\tools\harness\Invoke-ClaudeReview.ps1 -PromptPath .harness\task\prompt.md -TaskId task -Files AGENTS.md,docs\CODEMAP.md -Model sonnet
```

It supplies both `--tools` and `--allowedTools` with only `Read`, `Glob`, and `Grep`; the installed CLI accepts these flags, and a real invocation completed with that restriction. The adapter validates Claude's outer response and the review JSON, which may optionally be enclosed in one Markdown code fence, then writes raw and normalized results. Evidence records both the requested model and the single model reported by Claude when available; model independence uses the reported model. A failed CLI, authentication, quota, parser, or schema result is not review evidence.

After review, create the state-bound manifest, then verify it:

```powershell
.\tools\harness\New-CompletionManifest.ps1 -TaskId task -Files AGENTS.md,docs\CODEMAP.md -ImplementationModel gpt-5.6-terra -ReviewEvidencePath .harness\task\review.json -DocumentationBy reviewer -Checks lua-tests,lint -UserQaStatus not-required -OutputPath .harness\task\completion.json
.\tools\harness\Complete-Task.ps1 -ManifestPath .harness\task\completion.json -Action Verify
.\tools\harness\Complete-Task.ps1 -ManifestPath .harness\task\completion.json -Action Commit -CommitMessage 'docs: complete task'
```

The manifest v1 binds baseline, selected file hashes, implementation and reviewer model identities, review evidence, documentation attestation, applicable trusted checks, and user QA. `-Checks` must always contain at least one named check: use `git-head` plus the documentation audit for docs-only work, and include `lua-tests` when map or documentation specs apply. Verification re-runs named checks (`harness-tests`, `lua-tests`, `lint`, or `git-head`) and blocks missing required checks, stale state, failed review, pending QA, unsafe paths, or unrelated staging. Explicit `-Action Commit` may run only after passing verification and stages only selected paths. When the user has already authorized the commit, this action does not require a second per-commit confirmation.

Changed/deleted WoW API, event, or SavedVariables behavior requires `userQa.status: passed`; harness-only work uses `not-required`. The gate compares both baseline and current CODEMAP classifications and conservatively requires live QA when an addon Lua path has no classification. Keep other writers stopped while verification and commit run; fingerprint checks reduce stale evidence but cannot make a mutable working tree transactional.

Run the authoritative harness test runner:

```powershell
powershell -NoProfile -File tests\harness\Run-Tests.ps1
```

`Complete-Task.ps1` accepts `-LuaPath` and `-LuacheckPath` when the trusted-check executables are not installed at their defaults.

At task end audit state/map/module docs and consult relevant vault topics. In the task scratch record the model, input/output/reasoning token counts when the runner exposes them (otherwise `unavailable`), elapsed time, retry/rework count, and files read or changed. Do not estimate missing token counts.
