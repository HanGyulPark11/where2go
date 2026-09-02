# Phase 5, Sub-project 3: Packaging and Release Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a packaging script that zips the addon into a
drag-into-`AddOns`-ready archive, a smoke test that structurally verifies
that archive by reusing the existing `tests/toc_spec.lua` check, and a
release checklist tying the whole release process together.

**Architecture:** `tools/package.ps1` reads the version out of
`Where2Go/Where2Go.toc` and zips the `Where2Go/` folder into
`dist/Where2Go-<version>.zip`. `tools/smoke-test.ps1` extracts a given zip
to a temp directory and re-runs `tests/toc_spec.lua` with that directory as
the working directory, reusing the existing TOC↔filesystem check against
the packaged artifact instead of writing new verification logic.
`docs/RELEASE_CHECKLIST.md` sequences both scripts together with the
manual steps (version bump, live-client check, git tag) nothing here can
automate.

**Tech Stack:** PowerShell (`tools/package.ps1`, `tools/smoke-test.ps1`),
using only built-in cmdlets (`Compress-Archive`, `Expand-Archive`) — no
third-party binary is needed anywhere in this sub-project, unlike
Sub-projects 1 and 2.

**Spec:** `docs/superpowers/specs/2026-09-03-phase5-packaging-release-design.md`

## Global Constraints

- No pip/npm/external-binary dependency of any kind — only PowerShell's
  built-in `Compress-Archive`/`Expand-Archive` cmdlets and the Lua
  interpreter already installed at
  `C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe` from Phase 1.
- Both scripts must resolve the repo root via `$PSScriptRoot` (matching
  `tools/lint.ps1`'s established convention from Sub-project 2) so they
  work regardless of the caller's current directory.
- `tools/package.ps1` never hardcodes a version number — it always reads
  `Where2Go/Where2Go.toc`'s `## Version:` line. Bumping the version is a
  human decision made by editing that line directly, not something either
  script does.
- Any `Push-Location`/`Pop-Location` pairing must wrap the pushed section
  in `try { ... } finally { Pop-Location }`, with the script's `exit`
  statement placed after (outside) that try/finally block — this exact
  pattern was established and verified correct in Sub-project 2's
  `tools/lint.ps1` after its final review caught a version without the
  `finally` wrapper; reuse it rather than re-deriving the same fix here.
- `dist/` (the packaging output directory) must be gitignored before
  either script can produce output there.
- Unlike Sub-projects 1 and 2, no external binary blocks real functional
  testing here — `Compress-Archive`, `Expand-Archive`, and the
  already-installed `lua5.1.exe` are sufficient to actually run both
  scripts end-to-end during implementation, not just syntax-check them.
  Task verification steps below call for real execution, not just parsing.

---

## File Structure

```
.pkgmeta                       NEW — repo root, minimal CurseForge-
                                packager-convention scaffolding
tools/package.ps1               NEW — produces dist/Where2Go-<version>.zip
tools/smoke-test.ps1            NEW — structurally verifies a packaged zip
docs/RELEASE_CHECKLIST.md       NEW — full release procedure
.gitignore                      MODIFY — add dist/
```

---

### Task 1: Add `.pkgmeta` and gitignore `dist/`

**Files:**
- Create: `.pkgmeta` (repo root)
- Modify: `.gitignore`

**Interfaces:**
- Produces: an ignored `dist/` path that Task 2's script writes into.

- [ ] **Step 1: Write `.pkgmeta`**

```yaml
package-as: Where2Go
```

This is not read by any tool in this sub-project — it's forward-compatible
scaffolding matching the convention the real BigWigsMods/packager tool
would expect, for when a future CI-based CurseForge publishing step gets
wired up. `docs/RELEASE_CHECKLIST.md` (Task 4) documents this explicitly.

- [ ] **Step 2: Add `dist/` to `.gitignore`**

Read the current `.gitignore` (it currently contains `.worktrees/`,
`tools/data-prep/scratch/`, and `__pycache__/`). Add a new line:

```
dist/
```

- [ ] **Step 3: Verify the ignore rule works**

Run: `mkdir -p dist && touch dist/test.txt && git status --porcelain`
Expected: no output mentioning `dist/test.txt`.

Then remove the test file and directory: `rm -rf dist`

- [ ] **Step 4: Commit**

```bash
git add .pkgmeta .gitignore
git commit -m "chore: add .pkgmeta scaffolding and gitignore dist/"
```

---

### Task 2: Implement `tools/package.ps1`

**Files:**
- Create: `tools/package.ps1`

**Interfaces:**
- Consumes: `Where2Go/Where2Go.toc`'s `## Version:` line (currently
  `0.1.0`).
- Produces: `dist/Where2Go-<version>.zip`, with the `Where2Go` folder as
  the zip's own top-level entry (so extracting the zip anywhere yields a
  `Where2Go/` folder ready to drop into an `AddOns/` directory).

- [ ] **Step 1: Write the script**

```powershell
$repoRoot = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $repoRoot "Where2Go\Where2Go.toc"

$version = $null
foreach ($line in Get-Content $tocPath) {
    if ($line -match '^## Version:\s*(.+)$') {
        $version = $Matches[1].Trim()
        break
    }
}

if (-not $version) {
    Write-Error "Could not find a '## Version:' line in $tocPath"
    exit 1
}

$outputDir = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$zipPath = Join-Path $outputDir "Where2Go-$version.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath
}

Compress-Archive -Path (Join-Path $repoRoot "Where2Go") -DestinationPath $zipPath

Write-Output "Packaged $zipPath"
```

- [ ] **Step 2: Run it for real and verify the output**

Run: `.\tools\package.ps1` (from the repo root)
Expected: prints `Packaged <path>\dist\Where2Go-0.1.0.zip` (the current
version in `Where2Go.toc` is `0.1.0`), and the file actually exists:

Run: `powershell -NoProfile -Command "Test-Path dist\Where2Go-0.1.0.zip"`
Expected: `True`

- [ ] **Step 3: Verify the zip's internal structure is correct**

Run:
```powershell
powershell -NoProfile -Command "Expand-Archive -Path dist\Where2Go-0.1.0.zip -DestinationPath dist\_verify -Force; Get-ChildItem dist\_verify -Recurse -File | ForEach-Object { $_.FullName.Substring((Resolve-Path dist\_verify).Path.Length) }"
```
Expected output: exactly these 13 relative paths (order may vary), each
prefixed with `\Where2Go`:
```
\Where2Go\Core\Compare.lua
\Where2Go\Core\Constants.lua
\Where2Go\Core\DirectDrop.lua
\Where2Go\Core\Equipment.lua
\Where2Go\Core\Init.lua
\Where2Go\Core\RaidRanks.lua
\Where2Go\Core\Ranking.lua
\Where2Go\Core\Sources.lua
\Where2Go\Core\Tracks.lua
\Where2Go\Core\VoidcoreDrop.lua
\Where2Go\Core\VoidcoreHistory.lua
\Where2Go\UI\Panel.lua
\Where2Go\Where2Go.toc
```
Clean up the verification extraction afterward:
`Remove-Item -Recurse -Force dist\_verify`

- [ ] **Step 4: Commit**

```bash
git add tools/package.ps1
git commit -m "feat: add package.ps1 to zip the addon for distribution"
```

Note: `dist/Where2Go-0.1.0.zip` itself is gitignored (Task 1) and should
NOT be committed — only the script.

---

### Task 3: Implement `tools/smoke-test.ps1`

**Files:**
- Create: `tools/smoke-test.ps1`

**Interfaces:**
- Consumes: a zip produced by Task 2's `tools/package.ps1` (same
  `Where2Go/Where2Go.toc`-at-top-level structure); `tests/toc_spec.lua`
  (Phase 1, unmodified).
- Produces: process exit code 0 on a structurally valid package, non-zero
  otherwise.

- [ ] **Step 1: Write the script**

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath,
    [string]$LuaPath = "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"
)

if (-not (Test-Path $ZipPath)) {
    Write-Error "Zip not found at '$ZipPath'. Run tools\package.ps1 first."
    exit 1
}

if (-not (Test-Path $LuaPath)) {
    Write-Error "Lua interpreter not found at '$LuaPath'. Pass -LuaPath to point at your install."
    exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tocSpecPath = Join-Path $repoRoot "tests\toc_spec.lua"
$tempDir = Join-Path $env:TEMP ("where2go-smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Expand-Archive -Path $ZipPath -DestinationPath $tempDir

$extractedToc = Join-Path $tempDir "Where2Go\Where2Go.toc"
if (-not (Test-Path $extractedToc)) {
    Write-Error "Extracted package does not contain Where2Go\Where2Go.toc -- packaging structure is wrong (expected it at '$extractedToc')."
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

$exitCode = 1
Push-Location $tempDir
try {
    & $LuaPath $tocSpecPath
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
exit $exitCode
```

- [ ] **Step 2: Run it for real against a valid package and verify success**

If `dist\Where2Go-0.1.0.zip` doesn't already exist from Task 2, run
`.\tools\package.ps1` first.

Run: `.\tools\smoke-test.ps1 -ZipPath dist\Where2Go-0.1.0.zip`
Expected: prints `toc_spec: OK, 12 file(s) verified, ...` (the same
success message `tests/run_tests.lua` prints for this spec normally), and
the command's exit code is 0 (`powershell -NoProfile -Command
"$LASTEXITCODE"` after running it, or check via `if ($?) { 'PASS' }`).

- [ ] **Step 3: Run it against a missing zip and verify graceful failure**

Run: `.\tools\smoke-test.ps1 -ZipPath dist\does-not-exist.zip`
Expected: prints the "Zip not found... Run tools\package.ps1 first."
error message and exits non-zero — not a raw PowerShell exception.

- [ ] **Step 4: Commit**

```bash
git add tools/smoke-test.ps1
git commit -m "feat: add smoke-test.ps1 to structurally verify a packaged zip"
```

---

### Task 4: Write `docs/RELEASE_CHECKLIST.md`

**Files:**
- Create: `docs/RELEASE_CHECKLIST.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write the file**

```markdown
# Release Checklist

Follow these steps in order to cut a release. Do not skip ahead -- later
steps assume earlier ones passed.

1. **Run the full Lua test suite.**
   ```
   "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
   ```
   All specs must pass before continuing.

2. **Run the lint check.**
   ```
   .\tools\lint.ps1
   ```
   Must exit 0 with no warnings before continuing. See
   `tools/LINT_README.md` if `luacheck.exe` isn't installed yet.

3. **Bump the version.** Edit `Where2Go/Where2Go.toc`'s `## Version:` line
   to the new version number. This is the single source of truth every
   other step in this checklist reads from.

4. **Package the addon.**
   ```
   .\tools\package.ps1
   ```
   Produces `dist/Where2Go-<version>.zip`.

5. **Run the structural smoke test.**
   ```
   .\tools\smoke-test.ps1 -ZipPath dist\Where2Go-<version>.zip
   ```
   Confirms the packaged zip's contents match the TOC exactly (the same
   check `tests/toc_spec.lua` runs against the source tree, re-run against
   the extracted package). Must exit 0 before continuing.

6. **Manually verify in a real WoW client.** Extract
   `dist/Where2Go-<version>.zip` into a *separate* AddOns folder -- not
   the development junction this repo's live `AddOns\Where2Go` normally
   points at (extracting alongside or over it risks masking a real
   packaging bug with the dev copy's already-working state). Launch WoW,
   confirm the addon loads with no Lua errors, `/where2go` opens the
   panel, and both the Drop and Voidcore tabs work.

7. **Commit and tag.**
   ```
   git add Where2Go/Where2Go.toc
   git commit -m "chore: bump version to <version>"
   git tag v<version>
   ```
   Push the tag when ready to make the release visible
   (`git push --tags`).

## Publishing to CurseForge (not yet set up)

This checklist does not cover actually publishing anywhere. When ready to
publish to CurseForge: register the project on CurseForge's site (a
one-time manual step tied to your own account), then wire up CI (e.g. a
GitHub Action) to run the real BigWigsMods/packager tool against this
repo's existing `.pkgmeta` and upload the result using a CurseForge API
token stored as a repo secret. Nothing in this repo needs to change
structurally for that -- `.pkgmeta`'s `package-as: Where2Go` already
matches this addon's folder name.
```

- [ ] **Step 2: Commit**

```bash
git add docs/RELEASE_CHECKLIST.md
git commit -m "docs: add release checklist"
```

---

### Task 5: Manual live checkpoint — verify a real package loads in WoW

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — install the packaged zip in a clean location and load it**

Tasks 2-3 already proved the packaging pipeline works correctly using
real (not simulated) tool execution -- the zip's structure is verified
byte-accurate against the TOC. What remains is the one thing nothing in
this session can do: confirming a real WoW client actually loads the
packaged result. Whoever executes this task should:

1. Run `.\tools\package.ps1` to produce the current version's zip (if not
   already fresh from Task 2).
2. Extract `dist\Where2Go-<version>.zip` into a *separate* location --
   NOT over the existing `AddOns\Where2Go` dev junction. For example,
   extract it to a temp folder, then copy the resulting `Where2Go` folder
   into `AddOns\` under a different name temporarily (e.g.
   `Where2GoPackageTest`), or briefly swap the junction for the real
   extracted copy if that's easier -- whichever avoids ambiguity between
   "the dev copy is what's loading" and "the packaged copy is what's
   loading."
3. Launch WoW (or `/reload` if already running with the swapped copy),
   confirm no Lua errors appear.
4. Run `/where2go`, confirm the panel opens with both "Drop" and
   "Voidcore" tabs working as they do through the normal dev setup.
5. Restore the original dev junction/setup afterward if it was changed
   for this test.
6. Report back: did it load cleanly, and were there any differences from
   the dev-junction experience?

This satisfies `docs/superpowers/specs/2026-09-03-phase5-packaging-release-design.md`'s
acceptance check.

---

## Done

This sub-project -- and Phase 5 as a whole -- is complete when all four
code/doc tasks' commits exist and Task 5's manual checkpoint confirms a
real WoW client loads the packaged zip cleanly. There is no further phase
queued after this one in `docs/DEVELOPMENT_PLAN.md`; completing this
closes out the restart plan's delivery sequence.
