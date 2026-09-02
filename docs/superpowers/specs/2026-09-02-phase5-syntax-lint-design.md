# Phase 5, Sub-project 2: Automated Syntax and Contract Checks — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 5's second bullet ("Add automated
syntax and contract checks suitable for Windows development"). Builds on
Phase 5 Sub-project 1 (`docs/superpowers/specs/2026-09-02-phase5-data-ingestion-design.md`,
merged), which is otherwise unrelated to this sub-project.

## Decisions carried into this design

- **Tool**: `luacheck` (https://github.com/lunarmodules/luacheck), the
  standard static analyzer/linter for Lua. Its official Windows release is
  a single-file 64-bit binary (`luacheck.exe`) bundling Lua 5.4.4,
  luacheck, LuaFileSystem, and LuaLanes via LuaStatic — no build
  toolchain, no LuaRocks, no admin rights required. This avoids the
  install friction Phase 1 hit with the Lua 5.1 interpreter (`choco`
  needing elevation).
- **Coverage goal**: `luacheck` performs a full parse before linting, so
  running it over every `.lua` file in `Where2Go/` gives us syntax
  checking as a side effect of linting — no separate syntax-check tool is
  needed. This closes a real gap: 5 of the addon's 12 Lua files
  (`Init.lua`, `DirectDrop.lua`, `Equipment.lua`, `VoidcoreDrop.lua`,
  `Panel.lua`) are never `dofile`'d by any existing unit test (they're
  WoW-API-dependent, per the established pure/WoW-API-dependent split),
  so today a syntax error in any of them is invisible until a live
  `/reload` in-game. `Init.lua` additionally calls `CreateFrame("Frame")`
  at file top level (unguarded), which is why a naive `dofile`-based
  checker can't be reused for this purpose — `dofile` would execute that
  call and error outside WoW even on a file with zero syntax problems.
  `luacheck`'s parse-only-then-static-analyze approach never executes the
  code, so it's safe against exactly this pattern.
- **Globals allowlist scope**: `.luacheckrc`'s WoW-API globals list is
  built from this addon's actual usage (grepped from the real
  codebase), not imported from a general-purpose community WoW-API
  globals list. Smaller, more precise, and each new API this project uses
  is a small deliberate addition rather than trusting an external,
  independently-maintained list's completeness or currency.
- **Binary placement**: `luacheck.exe` is installed once by the developer
  outside the repo, at a fixed documented path (matching this project's
  existing `lua5.1.exe` path convention — see
  `docs/superpowers/plans/2026-09-02-phase1-foundations.md`'s Global
  Constraints for precedent). It is never committed to git — a binary
  executable doesn't belong in version control, and the whole point of
  the official single-file release is that installing it is a one-time,
  no-elevation download.
- **Invocation**: a standalone script (`tools/lint.ps1`), not merged into
  `tests/run_tests.lua`. Linting and the Lua unit-test suite are different
  concerns run at different times (lint is about code hygiene across
  every file including untested ones; `run_tests.lua` is about verified
  behavior of the pure-logic files) — keeping them as separate commands
  means either can be run and reasoned about independently.
- **"Contract checks"**: already satisfied by the existing
  `tests/toc_spec.lua` (bidirectional TOC ↔ filesystem check, from Phase
  1). This sub-project does not add a new contract-check mechanism; it
  completes Phase 5's "syntax and contract checks" bullet by adding the
  syntax/lint half phase 1-4 never had.

## Reference material

- `codex/pre-restart-backup` branch, `tools/data-prep/luacheck.js`: a
  fengari-based (JS Lua VM) syntax-only checker built for the old
  architecture. Examined and NOT reused — it only ever did
  `luaL_loadstring` syntax checking, none of real `luacheck`'s lint rules
  (unused variables, shadowing, undefined globals), and the real
  `luacheck.exe` binary is now confirmed available for Windows with no
  worse an install story.
- `Where2Go/Core/Init.lua` line 1: `local eventFrame =
  CreateFrame("Frame")` — the concrete example of why a `dofile`-based
  checker is unsafe for this codebase's WoW-API-dependent files, and why
  `luacheck`'s parse-without-execute model is the right fit.
- `tests/toc_spec.lua`: the existing "contract check" this design
  explicitly does not duplicate or replace.
- `docs/superpowers/plans/2026-09-02-phase1-foundations.md`: established
  the pattern (in this project) of a hand-verified, fixed external-tool
  path recorded as a Global Constraint, reused here for `luacheck.exe`.

## Architecture

```
(outside the repo)
C:\tools\luacheck\luacheck.exe   Developer-installed once, from
                                  https://github.com/lunarmodules/luacheck
                                  releases (official Windows single-file
                                  binary). Never committed.

.luacheckrc                       NEW: std = "lua51", plus a `globals`/
                                  `read_globals` table of exactly the WoW
                                  API names this addon references.

tools/lint.ps1                    NEW: runs luacheck.exe against every
                                  Where2Go/**/*.lua file. Accepts an
                                  optional -LuacheckPath parameter that
                                  overrides the fixed default path.

tools/LINT_README.md              NEW: one-time setup instructions
                                  (download link, where to place the exe,
                                  how to run tools/lint.ps1).
```

## Components

- **`.luacheckrc`** (new, repo root): luacheck's config file, auto-loaded
  when luacheck runs from the repo root.
  - `std = "lua51"` — matches the addon's actual Lua runtime (WoW's
    client embeds Lua 5.1), so syntax accepted/rejected matches what the
    game itself would accept.
  - `read_globals` — WoW API identifiers this addon calls/reads but never
    reassigns: `CreateFrame`, `C_Item`, `C_Container`,
    `GetInventoryItemLink`, `GetInventoryItemID`, `GetSpecialization`,
    `GetSpecializationInfo`, and others found by the implementation
    task's grep pass over `Where2Go/`.
  - `globals` — identifiers this addon itself assigns to at the top
    level, which luacheck would otherwise flag as accidental global
    writes: this addon's own cross-file module tables (`Where2GoSources`,
    `Where2GoTracks`, `Where2GoRaidRanks`, `Where2GoRanking`,
    `Where2GoDirectDrop`, `Where2GoVoidcoreHistory`,
    `Where2GoVoidcoreDrop`, `Where2GoCompare`, `Where2GoEquipment`,
    `Where2GoConstants`), the SavedVariables globals (`Where2GoDB`,
    `Where2GoCharDB`), and the WoW-provided globals this addon writes
    into rather than merely reads (`SLASH_WHERE2GO1`, `SLASH_WHERE2GO2`,
    `SlashCmdList`).
  - Reasonable defaults left alone unless the first real run shows they're
    too noisy for this codebase's patterns (e.g., WoW event-handler
    callbacks with conventionally-unused leading parameters like `self`)
    — tuned during implementation against real output, not speculatively
    pre-configured.

- **`tools/lint.ps1`** (new): a short PowerShell script.
  - Default `luacheck.exe` path matches the convention already
    established for `lua5.1.exe` in this project's plans — the exact
    fixed path is recorded as a Global Constraint in the implementation
    plan once the developer has installed it (mirroring how the Lua
    interpreter's path was handled in Phase 1).
  - Collects every `*.lua` file under `Where2Go\` recursively.
  - Runs `luacheck.exe` against that file list from the repo root (so
    `.luacheckrc` is picked up automatically).
  - Passes through luacheck's exit code, so the script fails loudly (non-
    zero exit) when luacheck finds any issue — no silent pass on warnings.

- **`tools/LINT_README.md`** (new): mirrors `tools/data-prep/README.md`'s
  role from Sub-project 1 — one-time setup (where to get `luacheck.exe`,
  where to place it, how `tools/lint.ps1` finds it, how to override the
  path) plus the run command.

## Data flow

1. Developer runs `tools\lint.ps1` from the repo root (one time after
   installing `luacheck.exe`, then anytime after that as a habit or before
   a release).
2. The script finds every `.lua` file under `Where2Go\` and invokes
   `luacheck.exe` against them.
3. `luacheck` reads `.luacheckrc` from the repo root automatically, parses
   every file (catching syntax errors), then applies its lint rules
   against the configured globals allowlist (catching unused locals,
   accidental global leaks not in the allowlist, shadowed variables, and
   other default lint checks).
4. Output and exit code surface directly in the terminal — no
   separate reporting layer, matching Sub-project 1's preference for
   direct tool output over custom tooling.

## Testing

- No automated test suite for `tools/lint.ps1` itself — like Sub-project
  1's `generate_sources.py`, this is a thin, low-complexity wrapper around
  a real external tool; the meaningful verification is running it for
  real against this codebase and confirming a clean (or fully explained)
  result, done as this sub-project's own completion check rather than as
  a unit test.
- This sub-project's completion check: running `tools\lint.ps1` against
  the current `Where2Go/` tree produces zero false-positive warnings (any
  real warnings surfaced by the first real run get fixed as part of this
  sub-project, or explicitly accepted with a `.luacheckrc` exception if
  they're stylistic false positives inherent to a WoW addon pattern, not
  a real defect).

## Error handling

- `luacheck.exe` missing at the configured path: `tools\lint.ps1` should
  fail with a clear message pointing at `tools/LINT_README.md`'s setup
  instructions, rather than a raw PowerShell "command not found" error.
- Any file luacheck can't parse (a real syntax error) is exactly the kind
  of failure this tool exists to surface — no special-casing, the script's
  non-zero exit is the correct behavior.

## Acceptance check

- Running `tools\lint.ps1` from a fresh clone (after the one-time
  `luacheck.exe` setup) against the current `Where2Go/` tree exits 0 with
  no warnings, or with only warnings the team has explicitly reviewed and
  intentionally suppressed via `.luacheckrc`.
- All 12 `Where2Go/**/*.lua` files are covered, including the 5 currently
  untested by `tests/run_tests.lua` (`Init.lua`, `DirectDrop.lua`,
  `Equipment.lua`, `VoidcoreDrop.lua`, `Panel.lua`) — confirmed by the
  implementation task actually listing which files luacheck ran against,
  not just trusting a glob pattern silently.

## Out of scope for this sub-project

- Any CI/GitHub Actions integration — this project has no CI configured
  yet (confirmed: no `.github/workflows/` directory exists) and adding one
  is not part of Phase 5's stated bullets. `tools/lint.ps1` is a local
  developer command for now.
- Auto-fixing lint issues — luacheck reports, it doesn't rewrite code;
  no auto-fix tooling is being added.
- Expanding `tests/toc_spec.lua`'s contract-check logic — unchanged by
  this design, per the "Contract checks" decision above.
- Packaging, clean-install smoke test, release checklist — Phase 5's
  third bullet, its own separate sub-project.
