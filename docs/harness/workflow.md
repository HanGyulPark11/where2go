# Harness workflow

The harness records completion evidence without granting extra authority. Evidence is stored under ignored `.harness/`, outside selected commit files.

Give each worker a bounded brief rather than the parent conversation: objective, selected files, behavior/contracts to preserve, required checks, and the exact evidence or findings to return. Include only the repository context needed for that scope.

First run a fresh read-only review. For example:

```powershell
.\tools\harness\Invoke-ClaudeReview.ps1 -PromptPath .harness\task\prompt.md -TaskId task -Files AGENTS.md,docs\CODEMAP.md -Model sonnet
```

The runner defaults to `-TimeoutSeconds 1200` and `-MaxBudgetUsd 3.0`; both bounds must be positive and can be adjusted per review. It asks Claude to prioritize a final JSON decision over extended analysis, uses Claude `stream-json` output with verbose partial messages, and terminates the Windows process tree when the wall-clock deadline expires.

Each run incrementally appends stdout events to `claude-stream.jsonl` and stderr to `claude-stderr.log` under its task scratch directory. Failure writes `failure.json` with a machine-readable `reason` (`harness`, `timeout`, `process`, `api`, or `parser`) and never writes `review.json`; partial diagnostics remain available. Successful runs require exactly one final `type=result` stream event with `is_error: false`. The final review accepts a bare JSON object, one enclosing JSON fence, or explanatory prose followed by one final JSON fence; ambiguous or malformed content is rejected. The runner supplies a JSON schema for `status` and `findings`, then retains the existing status, model, baseline, and file-hash evidence fields.

It supplies both `--tools` and `--allowedTools` with only `Read`, `Glob`, and `Grep`, ignores inherited MCP servers through an empty strict MCP configuration, and keeps `--no-session-persistence`. A Claude CLI, authentication, quota, API, timeout, or parser failure is not review evidence. Start a separate independent Sol review after such a failure; do not use Claude's `--fallback-model` as a substitute for that review path.

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
