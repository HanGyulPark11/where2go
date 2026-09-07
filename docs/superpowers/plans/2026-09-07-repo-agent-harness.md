# Repository Agent Harness Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development with the repository-specific overrides below. The user approved the design in conversation and requested implementation on a new branch.

**Goal:** Reduce Astra context and execution usage through current documentation, scoped lower-model workers, local Claude review, and a verifiable completion gate.

**Architecture:** Keep policies and agent definitions project-local. Use PowerShell adapters and a state-bound completion manifest instead of a general orchestration service. Documentation is the navigation layer; source and test evidence remain authoritative.

**Tech Stack:** Markdown, project-local Codex TOML, PowerShell, existing Lua 5.1 tests and luacheck, installed Claude Code CLI.

**Spec:** Approved conversation design, captured in this plan's contract below.

## Global constraints and approved contract

- Work on `chore/repo-agent-harness` in the existing checkout; no addon behavior changes.
- English source, documentation, developer output and commits; Korean conversation is allowed.
- Astra owns planning and architectural rulings. Terra implements; Sol handles difficult fixes; Claude Sonnet reviews independently. Workers receive bounded briefs, not full conversation history.
- Read AGENTS, CURRENT_STATE and CODEMAP before targeted source. Historical specs are optional context, not the current state contract.
- Consult relevant vault pages by topic. Never assume old API findings apply unchanged.
- No worker commits before independent review. The final integrator commits only explicitly selected task files after applicable checks, documentation audit and required user QA pass. Never push or merge automatically.
- This direct user authorization overrides plugin requirements for repeated design approval, pre-review commits, Astra final review, and compulsory new worktrees. Preserve global plugin files.
- On two unsuccessful fixes, escalate diagnosis/model; do not run unbounded retry loops.
- Keep machine paths configurable. Never bypass permission controls. Claude is a local CLI with remote inference.

## Task 1: Navigation and policy

**Owner:** Terra documentation worker.
**Files:** AGENTS.md, CLAUDE.md, docs/CODEMAP.md, docs/CURRENT_STATE.md, docs/HARNESS.md, docs/modules/*.md, README.md, TODO.md, tools/LINT_README.md, .codex/config.toml, .codex/agents/*.toml.

- [ ] Inspect current module entry points and tests; create a concise functional map and only useful module contracts.
- [ ] Separate current status from historical TODO descriptions, preserving historical findings and open live QA.
- [ ] Define project-local routing and explicit plugin overrides; document native configuration activation as unverified until checked.
- [ ] Describe vault topic lookup, end-of-session documentation audit, usage measurement and Claude limitations.
- [ ] Validate links and consistency against actual symbols and test coverage; return evidence and remaining limitations.

## Task 2: Executable workflow

**Owner:** Terra tooling worker.
**Files:** tools/harness/*, tests/harness/*, .gitignore (only harness scratch entries).
**Interface:** Task 1 documents the actual commands produced by Task 2 after integration. Scripts must have comment-based help and an executable usage example.

- [ ] Build a small Claude review adapter: configurable executable/model, explicit read-only tools, fresh invocation, bounded prompt input, JSON output, exit/error/schema validation, timeout, no permission bypass. Keep raw artifacts in ignored task scratch.
- [ ] Build a completion gate with explicit file selection and content fingerprints, baseline HEAD, independent review and documentation attestations, applicable automatic checks and user-QA status. Missing, failed, stale, or pending evidence must block commits. Attestations are auditable workflow records, not proof of review quality.
- [ ] Default to verification; expose an explicit commit action after gate checks. Reject unrelated staged files, changed baseline/content, protected branches and unsafe paths. Stage only selected paths; handle additions and deletions. Keep evidence outside the selected commit set to avoid self-reference.
- [ ] Add meaningful isolated tests using temporary Git repositories and fake Claude executables/results: success, failed review, malformed result, stale evidence, pending QA, unrelated staging, command failure, and safe explicit staging.
- [ ] Run tooling tests and existing Lua/lint baseline; report exact commands and results. No commits.

## Task 3: Integration, independent review and completion

**Owner:** Integrator with lower-model/Claude review.

- [ ] Reconcile documented interfaces with actual scripts; validate native TOML against installed capabilities when possible.
- [ ] Run local Claude on the completed diff for independent review. If execution is blocked, record the reason and use a lower-model independent reviewer; never claim Claude was tested.
- [ ] Address findings and rerun affected checks, then obtain scoped re-review.
- [ ] Audit documentation against the final diff, record verified limitations and reusable discoveries; save durable cross-project findings to vault with proper permission if needed.
- [ ] Commit the selected files after verified completion, report hash, branch, checks and limitations. No in-game QA is required for a harness-only change.

## Preflight interface review

| Tasks | Shared interface | Ruling |
| --- | --- | --- |
| 1 and 2 | docs/HARNESS.md describes tools/harness commands | Tool owner publishes exact interface; doc owner reconciles after implementation. |
| 1 | Current documentation vs historical claims | Current code/tests win; retain explicitly unverified live behavior. |
| 2 | Mutable evidence vs commit fingerprint | Evidence lives outside selected paths and binds baseline plus all selected file contents. |
| 3 | Review vs subsequent edits | Source/tool changes invalidate evidence; rerun affected checks and review before commit. |

## Progress

- Branch created from clean `master` at `a83e678`.
- Plan approved by the user's instruction to implement the preceding design.
- Resume audit (2026-09-08): switched from the user's parallel Claude branch to this branch. HEAD remains `a83e678`, with zero commits ahead of master. Only this untracked plan exists; Tasks 1-3 have not been implemented and navigation documents do not exist. The two earlier workers stopped on usage limits without producing files.
- The previous Progress entries were accurate but incomplete: branch creation and design approval did not imply implementation. The user explicitly requested an initial plan-only commit before implementation; this is the sole exception to the final review-before-commit policy.
- Do not inspect, modify, switch to, merge, or push the parallel `chore/repo-agent-harness-claude` branch. All workers must stay on this branch and must stop if its identity changes.
