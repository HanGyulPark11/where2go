# Phase 5, Sub-project 2: Automated Syntax and Lint Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `luacheck`-based syntax/lint checking covering every
`Where2Go/**/*.lua` file (including the 5 WoW-API-dependent files no unit
test currently touches), via a `.luacheckrc` scoped to this addon's real
WoW API usage and a `tools/lint.ps1` wrapper script.

**Architecture:** `luacheck.exe` (the official Windows single-file binary
release, no build toolchain or admin rights needed) is installed once by
the developer outside the repo. `tools/lint.ps1` finds every `.lua` file
under `Where2Go/` and runs `luacheck.exe` against them from the repo root,
so `.luacheckrc` (which allowlists this addon's own module globals and the
specific WoW API identifiers it calls) is picked up automatically.

**Tech Stack:** PowerShell (`tools/lint.ps1`), Lua (`.luacheckrc`, executed
by luacheck's own bundled runtime), `luacheck.exe` (external, developer-
installed, not committed).

**Spec:** `docs/superpowers/specs/2026-09-02-phase5-syntax-lint-design.md`

## Global Constraints

- `luacheck.exe` is never committed to git. Its default expected location
  is `C:\tools\luacheck\luacheck.exe`; `tools/lint.ps1` must accept a
  `-LuacheckPath` parameter to override this default.
- `.luacheckrc` targets `std = "lua51"` (WoW's client embeds Lua 5.1).
- The `read_globals` and `globals` lists in `.luacheckrc` must be exactly
  the values given in Task 1 below — these were derived by reading every
  `.lua` file in `Where2Go/` in full (not guessed, not copied from a
  generic community WoW-API list), so they should be used verbatim, not
  re-derived.
- No pip/npm/LuaRocks dependency of any kind — only the single
  `luacheck.exe` binary the developer downloads directly from GitHub
  releases.
- No automated test suite for `tools/lint.ps1` itself, matching Sub-
  project 1's precedent — verification is a syntax-only check of each
  new file (Tasks 1-2) plus a live run against the real codebase as the
  final manual checkpoint (Task 4), since `luacheck.exe` cannot be
  installed or invoked without a human downloading a third-party binary.
- Never install or execute `luacheck.exe` (or any downloaded binary)
  during implementation — Tasks 1-3 are verified by static/syntax checks
  only, using tools already present in this environment
  (`lua5.1.exe`, PowerShell's own script parser). Task 4 is the one place
  the actual binary gets run, and only by the human.

---

## File Structure

```
.luacheckrc                  NEW — repo root, luacheck config
tools/lint.ps1                NEW — runs luacheck.exe against Where2Go/**/*.lua
tools/LINT_README.md          NEW — one-time setup + run instructions
```

---

### Task 1: Write `.luacheckrc`

**Files:**
- Create: `.luacheckrc` (repo root)

**Interfaces:** none (config file, no code interface).

- [ ] **Step 1: Write the file**

```lua
std = "lua51"

read_globals = {
    "CreateFrame",
    "UIParent",
    "C_Item",
    "C_Container",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetInventorySlotInfo",
    "GetInventoryItemLink",
    "GetInventoryItemID",
}

globals = {
    "Where2GoConstants",
    "Where2GoTracks",
    "Where2GoSources",
    "Where2GoRaidRanks",
    "Where2GoRanking",
    "Where2GoDirectDrop",
    "Where2GoVoidcoreHistory",
    "Where2GoVoidcoreDrop",
    "Where2GoCompare",
    "Where2GoEquipment",
    "Where2GoDB",
    "Where2GoCharDB",
    "Where2Go_TogglePanel",
    "SLASH_WHERE2GO1",
    "SLASH_WHERE2GO2",
    "SlashCmdList",
}
```

This list was built by reading every file in `Where2Go/Core/` and
`Where2Go/UI/` in full and cataloguing every bare-global reference (not
method calls on locals, not this addon's own local functions). Do not add
or remove entries beyond what's written above — if Task 4's live run later
finds a gap, that's handled there, not by guessing here.

- [ ] **Step 2: Verify the file is syntactically valid Lua**

`.luacheckrc` is itself a Lua script luacheck executes, so a plain Lua
interpreter can syntax-check it without needing luacheck itself installed.

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" -e "assert(loadfile('.luacheckrc'))" && echo OK`
Expected: `OK` printed, no error. (`loadfile` compiles without executing,
so this is a pure syntax check.)

- [ ] **Step 3: Commit**

```bash
git add .luacheckrc
git commit -m "chore: add luacheck config scoped to this addon's real API usage"
```

---

### Task 2: Write `tools/lint.ps1`

**Files:**
- Create: `tools/lint.ps1`

**Interfaces:**
- Consumes: nothing from Task 1 at execution time other than `.luacheckrc`
  being auto-discovered by `luacheck.exe` when run from the repo root.
- Produces: an executable script other tasks/docs (Task 3, Task 4) refer
  to by its path and its `-LuacheckPath` parameter name.

- [ ] **Step 1: Write the script**

```powershell
param(
    [string]$LuacheckPath = "C:\tools\luacheck\luacheck.exe"
)

if (-not (Test-Path $LuacheckPath)) {
    Write-Error "luacheck.exe not found at '$LuacheckPath'. See tools/LINT_README.md for setup instructions, or pass -LuacheckPath to point at your own install."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

$luaFiles = Get-ChildItem -Path (Join-Path $repoRoot "Where2Go") -Filter "*.lua" -Recurse | ForEach-Object { $_.FullName }
& $LuacheckPath $luaFiles
$exitCode = $LASTEXITCODE

Pop-Location
exit $exitCode
```

- [ ] **Step 2: Verify the script is syntactically valid PowerShell**

Run: `powershell -NoProfile -Command "$null = [scriptblock]::Create((Get-Content -Raw tools/lint.ps1)); Write-Output 'OK'"`
Expected: `OK` printed, no `ParseException`. (`[scriptblock]::Create`
compiles the script without invoking it — the same "syntax only, never
execute" principle as Task 1's `loadfile` check, and it doesn't require
`luacheck.exe` to exist.)

- [ ] **Step 3: Commit**

```bash
git add tools/lint.ps1
git commit -m "feat: add lint.ps1 wrapper to run luacheck over all Where2Go Lua files"
```

---

### Task 3: Write `tools/LINT_README.md`

**Files:**
- Create: `tools/LINT_README.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write the file**

```markdown
# Where2Go lint tooling

`tools/lint.ps1` runs [luacheck](https://github.com/lunarmodules/luacheck)
against every `.lua` file under `Where2Go/`, catching both syntax errors
and common Lua mistakes (unused variables, accidental global writes) --
including the 5 WoW-API-dependent files (`Init.lua`, `DirectDrop.lua`,
`Equipment.lua`, `VoidcoreDrop.lua`, `Panel.lua`) that no unit test
currently touches, since today a syntax error in any of them is only
found via a live `/reload` in-game.

## One-time setup

Download the official Windows binary release from
https://github.com/lunarmodules/luacheck/releases -- a single
`luacheck.exe` bundling everything needed (Lua 5.4.4, luacheck itself, and
its dependencies). No build tools, no LuaRocks, no admin rights required.

Place it at:

```
C:\tools\luacheck\luacheck.exe
```

(Or anywhere else you like -- pass `-LuacheckPath` when running the script
to point at a different location.)

## Running it

From the repo root, in PowerShell:

```powershell
.\tools\lint.ps1
```

With a non-default luacheck location:

```powershell
.\tools\lint.ps1 -LuacheckPath "D:\somewhere\luacheck.exe"
```

A clean run exits 0 with no output. Any warnings or errors luacheck finds
print directly to the terminal with file:line references.
```

- [ ] **Step 2: Commit**

```bash
git add tools/LINT_README.md
git commit -m "docs: add lint tooling README"
```

---

### Task 4: Manual live checkpoint — install luacheck and run it for real

**Files:** none (verification only, plus whatever follow-up fixes real
output requires — see Step 3).

- [ ] **Step 1: MANUAL CHECKPOINT — install luacheck.exe and run tools/lint.ps1**

This cannot be done by an agent: it requires downloading and running a
third-party binary, which is outside what this session is allowed to do
itself. Whoever executes this task should do the following themselves:

1. Download `luacheck.exe` from
   https://github.com/lunarmodules/luacheck/releases (the Windows
   single-file binary release) and place it at
   `C:\tools\luacheck\luacheck.exe` (or note wherever else you put it, to
   pass via `-LuacheckPath`).
2. From the repo root, run `.\tools\lint.ps1` (or
   `.\tools\lint.ps1 -LuacheckPath "<your path>"`).
3. Report the full output back — this is safe to share in full (unlike
   Sub-project 1's credential-bearing script, nothing here is sensitive).

- [ ] **Step 2: Interpret the output**

Unlike Sub-project 1's Task 7, this step is not "confirm an empty/
explainable diff" — real lint output needs judgment calls that are easier
to make once actual output exists rather than guessed at in advance. When
the output comes back:

- **"accessing undefined variable 'X'" for a genuine WoW API identifier**
  this codebase actually calls (i.e. Task 1's list missed it): add `X` to
  `.luacheckrc`'s `read_globals` (if the addon only ever reads/calls it)
  or `globals` (if the addon also assigns to it) list.
- **"accessing undefined variable 'X'" for anything else**: this is
  probably a real typo or bug (e.g. a misspelled module/function name) —
  do not silence it by adding it to the allowlist; fix the actual
  reference.
- **"unused variable/argument" on a WoW event-callback parameter** (e.g.
  `event` in `Init.lua`'s `ADDON_LOADED` handler, or `self` in
  `VoidcoreHistory.lua`'s `BONUS_ROLL_RESULT` handler, if either is never
  referenced inside the handler body) — this is a known, expected pattern
  for WoW addons, which always receive a fixed callback signature whether
  every parameter is used or not. Fix by prefixing the specific unused
  parameter name with `_` at its declaration (`_event`, `_self`) --
  luacheck's own convention for "intentionally unused" -- not by disabling
  the check project-wide (`unused_args = false` would hide real unused-
  argument bugs everywhere else too).
- **"unused variable" anywhere else**: treat as a real finding and fix the
  actual code (remove the dead variable, or use it if it was meant to be
  used).
- **Any other warning class**: read what it's flagging and use judgment;
  when genuinely unsure whether something is a false positive or a real
  issue, err toward asking rather than silently suppressing it in
  `.luacheckrc`.

- [ ] **Step 3: Apply fixes and confirm a clean re-run**

If Step 2 identified any needed changes, make them (either directly or via
a small follow-up implementer dispatch scoped to exactly what Step 2
found), then re-run `.\tools\lint.ps1` and confirm it now exits 0 with no
output. Repeat until clean.

This satisfies `docs/superpowers/specs/2026-09-02-phase5-syntax-lint-design.md`'s
acceptance check.

---

## Done

This sub-project is complete when all three code/doc tasks' commits exist
and Task 4's live checkpoint confirms `tools\lint.ps1` runs clean (exit 0,
no warnings) against the real `Where2Go/` tree. Phase 5's third
sub-project (packaging, clean-install smoke test, release checklist)
starts a new brainstorm/design/plan cycle built on this foundation.
