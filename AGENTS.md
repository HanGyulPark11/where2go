# Where2Go agent guide

Read this file, [current state](docs/CURRENT_STATE.md), and [code map](docs/CODEMAP.md) before targeted source. Source and registered tests are authoritative.

- Keep developer material in English. Preserve unrelated work; do not push, merge, or commit before independent review.
- Astra owns planning; Terra implements routine work; Sol handles difficult fixes. Workers receive a bounded brief.
- A reviewer must use a **different model** from the implementer. Claude Sonnet is preferred, but its local CLI uses remote inference. Record unavailable CLI/auth/quota as a limitation; do not claim a review ran.
- After two failed fixes, escalate rather than retrying indefinitely.
- Run applicable checks, audit affected docs, and use the completion gate immediately before a commit. It may stage only the selected files.
- Any changed or deleted WoW API call, event, or SavedVariables behavior requires completed user live-client QA. Harness-only changes do not.
- Consult relevant `C:\Users\hangy\ai\vault` topics, verify them against current code, and save only durable cross-project findings at session end.

`.codex/` records project policy. Native activation from a repository `.codex` directory is unverified; this file remains effective policy. The project policy overrides plugin requirements for repeated design approval, pre-review commits, mandatory Astra final review, or new worktrees.
