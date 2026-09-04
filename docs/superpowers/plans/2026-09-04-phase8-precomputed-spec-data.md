# Phase 8: Precomputed All-Class Spec-Eligibility Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 7's per-character live spec-eligibility scan with a
committed, precomputed data file covering every class/spec in the game, so
no shipped-client player ever runs the scan themselves.

**Architecture:** A new committed data file
(`Where2Go/Core/SpecEligibilityData.lua`) becomes `IsEligibleForSpec`'s
primary source of truth, replacing its old per-character
`Where2GoCharDB.specEligibility` read. The existing scan engine
(`Core/SpecEligibilityScan.lua`) is repurposed from an automatic
every-player trigger into a maintainer-only tool (`/where2go genspec`)
that accumulates results into an account-wide
`Where2GoDB.specEligibilityExport` table across sessions/classes, which a
human hand-merges into the committed data file after eyeballing it.

**Tech Stack:** Lua (WoW addon), `lua5.1` for the plain-Lua test harness
(`tests/run_tests.lua`).

**Spec:** `docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md`

**Task order note:** Tasks are ordered so every commit leaves a working
addon, not just a working test suite. In particular, the UI trigger
removal (Task 2) happens *before* the scan engine's `EnsureScanned` is
deleted (Task 3) — deleting it first would leave the still-wired UI
calling a nonexistent function, and worse, since Task 3 also stops
`FinalizeScan` from ever refreshing `Where2GoCharDB.specEligibility`,
`EnsureScanned` would see that cache as permanently stale and restart the
~40s scan on *every single panel open* until Task 2 removes the trigger.
Doing Task 2 first avoids that window entirely.

## Global Constraints

- Committed data files (`Sources.lua`, `ItemStats.lua`,
  `VoidcacheIds.lua`, and now `SpecEligibilityData.lua`) are never
  hand-edited casually — regenerate/re-merge from source, human reviews
  the diff before committing.
- Every `.lua` file under `Where2Go/Core` or `Where2Go/UI` must be
  referenced in `Where2Go/Where2Go.toc`, enforced by
  `tests/toc_spec.lua`'s completeness sweep.
- Pure (no-WoW-API) functions get unit tests in `tests/`; WoW-API-dependent
  code (anything touching `C_TooltipInfo`, `C_Item`, `SetLootSpecialization`,
  frame/event code) is verified live instead, matching this project's
  existing convention (see `SpecEligibilityScan.lua`'s own header comment).
- Run the full suite with:
  `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`

---

## Task 1: Committed `SpecEligibilityData.lua` data file

**Files:**
- Create: `Where2Go/Core/SpecEligibilityData.lua`
- Modify: `Where2Go/Where2Go.toc`
- Create: `tests/specEligibilityData_spec.lua`
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Produces: `Where2GoSpecEligibilityData.BY_SPEC` — a global table,
  `{ [specId] = { [itemId] = true, ... }, ... }`, consumed by Task 4.

- [ ] **Step 1: Create the data file**

```lua
-- Precomputed all-class spec-eligibility data: for every class/spec in
-- the game, which of Where2Go's tracked dungeon/raid items that spec can
-- actually receive as loot, per Blizzard's own server-computed loot
-- table (built via Core/SpecEligibilityScan.lua's tooltip-scan
-- technique). See
-- docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md.
-- Do not hand-edit item/spec entries directly -- regenerate via
-- `/where2go genspec` (see docs/SEASON_CHECKLIST.md) and hand-merge the
-- reviewed result here, the same convention as Sources.lua/ItemStats.lua.
--
-- Starts empty until the first `/where2go genspec` generation pass for
-- each class is run and hand-merged in. Core/DirectDrop.lua's
-- IsEligibleForSpec falls back to its own heuristic for any spec with no
-- entry here yet.

Where2GoSpecEligibilityData = {}

Where2GoSpecEligibilityData.BY_SPEC = {
    -- [specId] = { [itemId] = true, ... },
}
```

Save as `Where2Go/Core/SpecEligibilityData.lua`.

- [ ] **Step 2: Register it in the TOC**

In `Where2Go/Where2Go.toc`, insert a new line `Core\SpecEligibilityData.lua`
immediately after the existing `Core\VoidcacheIds.lua` line (grouping it
with the project's other static data files, before `Core\ItemStats.lua`):

```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\VoidcacheIds.lua
Core\SpecEligibilityData.lua
Core\ItemStats.lua
Core\ItemBrowser.lua
Core\RaidRanks.lua
Core\Ranking.lua
Core\DirectDrop.lua
Core\VoidcoreHistory.lua
Core\VoidcoreDrop.lua
Core\SpecEligibilityScan.lua
Core\Compare.lua
Core\Equipment.lua
Core\Init.lua
UI\Panel.lua
UI\BrowserPanel.lua
```

- [ ] **Step 3: Write the structural test**

Create `tests/specEligibilityData_spec.lua`:

```lua
dofile("Where2Go/Core/SpecEligibilityData.lua")

assert(type(Where2GoSpecEligibilityData) == "table", "Where2GoSpecEligibilityData should be a table")
assert(type(Where2GoSpecEligibilityData.BY_SPEC) == "table", "Where2GoSpecEligibilityData.BY_SPEC should be a table")

local specCount = 0
for specId, itemSet in pairs(Where2GoSpecEligibilityData.BY_SPEC) do
    specCount = specCount + 1
    assert(type(specId) == "number", "BY_SPEC keys should be numeric spec IDs")
    assert(type(itemSet) == "table", "BY_SPEC[" .. tostring(specId) .. "] should be a table of item IDs")
    for itemId, value in pairs(itemSet) do
        assert(type(itemId) == "number", "BY_SPEC[" .. specId .. "] keys should be numeric item IDs")
        assert(value == true, "BY_SPEC[" .. specId .. "][" .. tostring(itemId) .. "] should be exactly `true`")
    end
end

-- Deliberately no "every class must be covered" assertion here: this
-- file starts empty and fills in gradually across many
-- `/where2go genspec` sessions per docs/SEASON_CHECKLIST.md, so a hard
-- coverage gate here would fail the whole suite for as long as that
-- generation work is in progress. Only structural correctness (numeric
-- keys, `true` values) is enforced unconditionally.
print("specEligibilityData_spec: OK, " .. specCount .. " spec(s) currently populated (structural check only)")
```

This must pass even while `BY_SPEC` is still empty (`specCount == 0`),
since real per-class data is generated in later maintainer sessions, not
by this plan.

- [ ] **Step 4: Register the test in the runner**

In `tests/run_tests.lua`, add `"tests/specEligibilityData_spec.lua"` to
the `specs` list, right after `"tests/voidcacheids_spec.lua"`:

```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/toc_spec.lua",
    "tests/tracks_spec.lua",
    "tests/compare_spec.lua",
    "tests/sources_spec.lua",
    "tests/voidcacheids_spec.lua",
    "tests/specEligibilityData_spec.lua",
    "tests/itemstats_spec.lua",
    "tests/raidranks_spec.lua",
    "tests/ranking_spec.lua",
    "tests/voidcorehistory_spec.lua",
    "tests/specEligibilityScan_spec.lua",
    "tests/itembrowser_spec.lua",
}
```

- [ ] **Step 5: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]`, including the new
`specEligibilityData_spec.lua` and `toc_spec.lua` (which now also
confirms the new file is both on disk and TOC-referenced).

- [ ] **Step 6: Commit**

```bash
git add Where2Go/Core/SpecEligibilityData.lua Where2Go/Where2Go.toc tests/specEligibilityData_spec.lua tests/run_tests.lua
git commit -m "feat: add committed SpecEligibilityData.lua data file"
```

---

## Task 2: Remove the automatic scan trigger from both UI panels

**Files:**
- Modify: `Where2Go/UI/Panel.lua`
- Modify: `Where2Go/UI/BrowserPanel.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — this task only deletes code. After this task,
  neither file references `Where2GoSpecEligibilityScan` at all. Regular
  players stop getting any spec-eligibility scan starting from this
  task's commit (`IsEligibleForSpec` simply falls through to its existing
  heuristic, since Task 4 hasn't repointed it at the new committed data
  yet) — an intentional, safe intermediate state, not a regression.

- [ ] **Step 1: Remove `scanStatusText` from Panel.lua's locals**

In `Where2Go/UI/Panel.lua`, replace:

```lua
local panelFrame
local contentFrame
local cardFrames = {}
local Layout
local currentView = "DROP"
local scanStatusText

local HEADER_HEIGHT = 62
```

with:

```lua
local panelFrame
local contentFrame
local cardFrames = {}
local Layout
local currentView = "DROP"

local HEADER_HEIGHT = 62
```

- [ ] **Step 2: Remove the `scanStatusText` widget from `CreatePanel`**

Still in `Where2Go/UI/Panel.lua`, replace:

```lua
    scanStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scanStatusText:SetPoint("BOTTOMLEFT", 6, 6)
    scanStatusText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    scanStatusText:SetJustifyH("LEFT")
    scanStatusText:SetText("")

    CreateTab(frame, "Drop", "DROP", 12)
```

with:

```lua
    CreateTab(frame, "Drop", "DROP", 12)
```

- [ ] **Step 3: Remove `HandleScanProgress` and the scan trigger in `Where2Go_TogglePanel`**

Still in `Where2Go/UI/Panel.lua`, replace:

```lua
local function HandleScanProgress(specName, current, total, finishedReason)
    if finishedReason then
        scanStatusText:SetText("")
        RefreshContent()
        return
    end
    scanStatusText:SetText(string.format("Where2Go: scanning spec eligibility... %d/%d (%s)", current or 0, total or 0, specName or ""))
end

function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        Where2GoSpecEligibilityScan.SetProgressCallback("panel", HandleScanProgress)
        Where2GoSpecEligibilityScan.EnsureScanned()
        RefreshContent()
        panelFrame:Show()
    end
end
```

with:

```lua
function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        RefreshContent()
        panelFrame:Show()
    end
end
```

- [ ] **Step 4: Remove `scanStatusText` from BrowserPanel.lua's locals**

In `Where2Go/UI/BrowserPanel.lua`, replace:

```lua
local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { dungeonName = nil, bossName = nil, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil, specId = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit
local scanStatusText
local specDropdown
```

with:

```lua
local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { dungeonName = nil, bossName = nil, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil, specId = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit
local specDropdown
```

- [ ] **Step 5: Remove the `scanStatusText` widget from `CreateBrowserPanel`**

Still in `Where2Go/UI/BrowserPanel.lua`, replace:

```lua
    scanStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scanStatusText:SetPoint("BOTTOMLEFT", 6, 6)
    scanStatusText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    scanStatusText:SetJustifyH("LEFT")
    scanStatusText:SetText("")

    -- Drop/Voidcore mode toggle
```

with:

```lua
    -- Drop/Voidcore mode toggle
```

- [ ] **Step 6: Remove `HandleScanProgress` and the scan trigger in `Where2GoBrowserPanel.Toggle`**

Still in `Where2Go/UI/BrowserPanel.lua`, replace:

```lua
local function HandleScanProgress(specName, current, total, finishedReason)
    if finishedReason then
        scanStatusText:SetText("")
        RebuildFilteredResults()
        return
    end
    scanStatusText:SetText(string.format("Where2Go: scanning spec eligibility... %d/%d (%s)", current or 0, total or 0, specName or ""))
end

Where2GoBrowserPanel = {}
```

with:

```lua
Where2GoBrowserPanel = {}
```

Then replace:

```lua
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        Where2GoSpecEligibilityScan.SetProgressCallback("browser", HandleScanProgress)
        Where2GoSpecEligibilityScan.EnsureScanned()
        if not userSelectedSpec then
            SyncDefaultSpec()
        end
        RebuildFilteredResults()
        browserFrame:Show()
    end
end
```

with:

```lua
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        if not userSelectedSpec then
            SyncDefaultSpec()
        end
        RebuildFilteredResults()
        browserFrame:Show()
    end
end
```

- [ ] **Step 7: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`.

- [ ] **Step 8: Commit**

```bash
git add Where2Go/UI/Panel.lua Where2Go/UI/BrowserPanel.lua
git commit -m "feat: remove automatic spec-eligibility scan trigger from both UI panels"
```

---

## Task 3: Repurpose the scan engine for export/merge

**Depends on Task 2** — this task's Step 10 deletes
`Where2GoSpecEligibilityScan.EnsureScanned` entirely, which is only safe
because Task 2 already removed its only two callers.

**Files:**
- Modify: `Where2Go/Core/SpecEligibilityScan.lua`
- Test: `tests/specEligibilityScan_spec.lua`

**Interfaces:**
- Consumes: `Where2GoConstants.SEASON_LABEL` (string, `Core/Constants.lua`).
- Produces: `Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, newBySpec) -> mergedBySpec`
  (pure), `Where2GoSpecEligibilityScan.CheckExportSeasonStale(export, currentSeasonLabel) -> boolean`
  (pure), both consumed internally by this task's `Start()`/`FinalizeScan`
  changes and reused directly by Task 5's slash command. `Start()` gains a
  new possible second return value `"STALE_SEASON"` alongside its existing
  `"RUNNING"`/`"COMBAT"`/`"NO_SPECS"`/`"NO_ITEMS"` failure reasons.
  `Where2GoSpecEligibilityScan.EnsureScanned` no longer exists after this
  task.

- [ ] **Step 1: Write the failing tests for the two new pure functions**

Open `tests/specEligibilityScan_spec.lua` and insert the following right
before the final `print("specEligibilityScan_spec: OK")` line:

```lua
-- MergeBySpec: adds new specs, preserves untouched existing specs,
-- fully replaces any spec this pass actually scanned.
local merged1 = Where2GoSpecEligibilityScan.MergeBySpec(nil, { [71] = { [100] = true } })
assert(merged1[71][100] == true, "should merge into a nil existing table")

local existingBySpec = { [71] = { [100] = true }, [72] = { [200] = true } }
local merged2 = Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, { [73] = { [300] = true } })
assert(merged2[71][100] == true, "should preserve untouched existing spec 71")
assert(merged2[72][200] == true, "should preserve untouched existing spec 72")
assert(merged2[73][300] == true, "should add new spec 73")

local replaced = Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, { [71] = { [999] = true } })
assert(replaced[71][999] == true, "should replace spec 71 wholesale with the new scan's result")
assert(replaced[71][100] == nil, "should not keep spec 71's stale old item after a full re-scan of that spec")
assert(replaced[72][200] == true, "should still preserve untouched spec 72")

-- CheckExportSeasonStale: nil export or matching season is never stale;
-- a season mismatch is stale.
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale(nil, "S2") == false, "nil export is never stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S2" }, "S2") == false, "matching season is not stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S1" }, "S2") == true, "mismatched season is stale")

print("specEligibilityScan_spec: OK")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/specEligibilityScan_spec.lua` with an error like
`attempt to call a nil value (field 'MergeBySpec')`.

- [ ] **Step 3: Update the file header comment**

In `Where2Go/Core/SpecEligibilityScan.lua`, replace:

```lua
-- Scans the "Nebulous Voidcache" tooltip for each of the player's own
-- class's specializations to build an authoritative
-- Where2GoCharDB.specEligibility table, consumed by
-- Core/DirectDrop.lua's IsEligibleForSpec. See
-- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md.
--
-- ParseTooltipLines below is pure (no WoW API) and unit-tested in
-- tests/specEligibilityScan_spec.lua. The scan state machine that calls
-- it is WoW-API-dependent like Core/VoidcoreDrop.lua/VoidcoreHistory.lua
-- -- not unit-tested, verified live instead.
```

with:

```lua
-- Scans the "Nebulous Voidcache" tooltip for each of the current
-- character's class's specializations. Historically (Phase 7) this ran
-- automatically for every player and cached its result per-character;
-- as of Phase 8 it is a maintainer-only tool triggered by
-- `/where2go genspec`, merging its result into the account-wide
-- Where2GoDB.specEligibilityExport table for manual hand-merging into
-- the committed Core/SpecEligibilityData.lua (consumed by
-- Core/DirectDrop.lua's IsEligibleForSpec). See
-- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md
-- (original scan design) and
-- docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md
-- (export/generation workflow).
--
-- ParseTooltipLines, MergeBySpec, and CheckExportSeasonStale below are
-- pure (no WoW API) and unit-tested in tests/specEligibilityScan_spec.lua.
-- The scan state machine that calls them is WoW-API-dependent like
-- Core/VoidcoreDrop.lua/VoidcoreHistory.lua -- not unit-tested, verified
-- live instead.
```

- [ ] **Step 4: Add the two pure functions**

Immediately after `Where2GoSpecEligibilityScan.ParseTooltipLines`'s
closing `end` (right before the `local RETRY_DELAY = 0.35` line), insert:

```lua

-- Pure: merges a scan pass's per-spec results into the existing export
-- table's bySpec, replacing any spec entries this pass actually scanned
-- (a full re-scan of a spec supersedes its old result entirely, so a
-- since-removed item can't linger) while leaving every other spec's
-- previously accumulated entries untouched. Does not mutate either
-- argument.
function Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, newBySpec)
    local merged = {}
    for specId, itemSet in pairs(existingBySpec or {}) do
        merged[specId] = itemSet
    end
    for specId, itemSet in pairs(newBySpec or {}) do
        merged[specId] = itemSet
    end
    return merged
end

-- Pure: true if `export` (Where2GoDB.specEligibilityExport) carries data
-- from a season other than `currentSeasonLabel`. A nil export, or one
-- with no seasonVersion yet, is never stale (nothing to conflict with).
function Where2GoSpecEligibilityScan.CheckExportSeasonStale(export, currentSeasonLabel)
    return export ~= nil and export.seasonVersion ~= nil and export.seasonVersion ~= currentSeasonLabel
end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[PASS] tests/specEligibilityScan_spec.lua`.

- [ ] **Step 6: Commit the pure-function additions**

```bash
git add Where2Go/Core/SpecEligibilityScan.lua tests/specEligibilityScan_spec.lua
git commit -m "feat: add MergeBySpec/CheckExportSeasonStale pure helpers to SpecEligibilityScan"
```

- [ ] **Step 7: Update `CollectAllPoolItemIds`'s comment**

Still in `Where2Go/Core/SpecEligibilityScan.lua`, replace:

```lua
-- Every item ID Sources.lua tracks -- the pool a scanned item name needs
-- to resolve against to recover its numeric item ID (tooltips only give
-- names). Requires the item cache to be warm; an item whose name isn't
-- cached yet at scan time is silently skipped for this scan. Unlike
-- Core/DirectDrop.lua's own cold-cache limitation -- which is
-- recomputed on every render and so self-heals naturally as the item
-- cache warms up during normal play -- this scan's result is written
-- once to Where2GoCharDB.specEligibility (persistent SavedVariables)
-- and isn't revisited until the next season's SEASON_LABEL bump, so a
-- cold-cache failure here does NOT self-heal the same way. The actual
-- mitigation is FinalizeScan's empty-result guard below, which refuses
-- to persist a scan whose name resolution came back empty rather than
-- silently writing bad (all-ineligible) data.
```

with:

```lua
-- Every item ID Sources.lua tracks -- the pool a scanned item name needs
-- to resolve against to recover its numeric item ID (tooltips only give
-- names). Requires the item cache to be warm; an item whose name isn't
-- cached yet at scan time is silently skipped for this scan. Unlike
-- Core/DirectDrop.lua's own cold-cache limitation -- which is
-- recomputed on every render and so self-heals naturally as the item
-- cache warms up during normal play -- this scan's result is merged
-- into Where2GoDB.specEligibilityExport (persistent SavedVariables) and
-- eventually hand-merged into the committed Core/SpecEligibilityData.lua,
-- so a cold-cache failure here does NOT self-heal the same way. The
-- actual mitigation is FinalizeScan's empty-result guard below, which
-- refuses to persist a scan whose name resolution came back empty
-- rather than silently writing bad (all-ineligible) data -- plus the
-- manual eyeball-check step in the Phase 8 design doc's export workflow.
```

- [ ] **Step 8: Change `FinalizeScan`'s persistence target**

Replace:

```lua
    if not coldCacheFailure then
        Where2GoCharDB.specEligibility = {
            seasonVersion = Where2GoConstants.SEASON_LABEL,
            scannedAt = time(),
            bySpec = bySpec,
        }
    end
    -- else: leave Where2GoCharDB.specEligibility untouched -- any
    -- previous (stale but non-empty) scan keeps being used, or if there
    -- was none, IsEligibleForSpec correctly falls through to the old
    -- heuristic. seasonVersion won't have been written/updated, so the
    -- next EnsureScanned() call (next panel open) will retry the scan.
```

with:

```lua
    if not coldCacheFailure then
        local existingBySpec = Where2GoDB.specEligibilityExport and Where2GoDB.specEligibilityExport.bySpec
        Where2GoDB.specEligibilityExport = {
            seasonVersion = Where2GoConstants.SEASON_LABEL,
            bySpec = Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, bySpec),
        }
    end
    -- else: leave Where2GoDB.specEligibilityExport untouched -- this
    -- pass's result is discarded rather than merging in bad
    -- (all-ineligible) data; re-running /where2go genspec retries.
```

- [ ] **Step 9: Add the season-stale guard to `Start()`**

Replace:

```lua
function Where2GoSpecEligibilityScan.Start()
    if Where2GoSpecEligibilityScan.IsRunning() then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end

    local numSpecs = GetNumSpecializations()
```

with:

```lua
function Where2GoSpecEligibilityScan.Start()
    if Where2GoSpecEligibilityScan.IsRunning() then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end
    if Where2GoSpecEligibilityScan.CheckExportSeasonStale(Where2GoDB.specEligibilityExport, Where2GoConstants.SEASON_LABEL) then
        return false, "STALE_SEASON"
    end

    local numSpecs = GetNumSpecializations()
```

- [ ] **Step 10: Remove `EnsureScanned`**

Delete this whole function (safe now — Task 2 already removed its only
two callers, so no dangling references exist before or after this
step):

```lua
function Where2GoSpecEligibilityScan.EnsureScanned()
    local cache = Where2GoCharDB.specEligibility
    if cache and cache.seasonVersion == Where2GoConstants.SEASON_LABEL then
        return
    end
    if Where2GoSpecEligibilityScan.IsRunning() then
        return
    end
    if InCombatLockdown() then
        return
    end
    Where2GoSpecEligibilityScan.Start()
end
```

Replace it with nothing (delete the whole block, including its
surrounding blank lines so exactly one blank line separates the
preceding and following functions, matching the file's existing style).

- [ ] **Step 11: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]` (this step is WoW-API-dependent code, not covered
by the plain-Lua harness beyond confirming the file still loads without
syntax errors via `dofile` in `specEligibilityScan_spec.lua`'s first line).

- [ ] **Step 12: Commit**

```bash
git add Where2Go/Core/SpecEligibilityScan.lua
git commit -m "feat: repurpose SpecEligibilityScan to write Where2GoDB.specEligibilityExport"
```

---

## Task 4: `IsEligibleForSpec` consumes the committed data first

**Files:**
- Modify: `Where2Go/Core/DirectDrop.lua`

**Interfaces:**
- Consumes: `Where2GoSpecEligibilityData.BY_SPEC` (Task 1).
- Produces: `Where2GoDirectDrop.IsEligibleForSpec(specId)` — same public
  signature as before (`(specId) -> function(itemId) -> boolean`), only
  its internal precedence changes. `Core/VoidcoreDrop.lua` and
  `Where2Go/UI/BrowserPanel.lua` both call this function already and
  need no changes themselves.

- [ ] **Step 1: Update the file header comment**

In `Where2Go/Core/DirectDrop.lua`, replace:

```lua
-- Assembles the real ranked direct-drop content list: current-spec
-- detection, item eligibility (IsEligibleForSpec below consults
-- Where2GoCharDB.specEligibility -- built by Core/SpecEligibilityScan.lua
-- -- first when available, falling back to the live
-- C_Item.GetItemSpecInfo/IsEquippableItem heuristic otherwise), item
-- name lookup, and calls Where2GoRanking.RankContent. WoW-API-dependent;
-- not unit-tested (Where2GoRanking carries the pure ranking math this
-- feeds).
```

with:

```lua
-- Assembles the real ranked direct-drop content list: current-spec
-- detection, item eligibility (IsEligibleForSpec below consults the
-- committed Core/SpecEligibilityData.lua -- generated via
-- Core/SpecEligibilityScan.lua's maintainer-only tooltip-scan tool --
-- first when available, falling back to the live
-- C_Item.GetItemSpecInfo/IsEquippableItem heuristic otherwise), item
-- name lookup, and calls Where2GoRanking.RankContent. WoW-API-dependent;
-- not unit-tested (Where2GoRanking carries the pure ranking math this
-- feeds).
```

- [ ] **Step 2: Change `IsEligibleForSpec`'s primary check**

Replace:

```lua
function Where2GoDirectDrop.IsEligibleForSpec(specId)
    return function(itemId)
        -- Prefer real scanned data (Core/SpecEligibilityScan.lua) when
        -- available for this season and this spec: it's Blizzard's own
        -- server-computed loot table for the spec, not a heuristic, so
        -- it correctly rejects wrong-weapon/armor-type items the
        -- fallback below cannot (see
        -- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md).
        local cache = Where2GoCharDB.specEligibility
        if cache and cache.seasonVersion == Where2GoConstants.SEASON_LABEL and cache.bySpec and cache.bySpec[specId] and next(cache.bySpec[specId]) ~= nil then
            return cache.bySpec[specId][itemId] == true
        end
```

with:

```lua
function Where2GoDirectDrop.IsEligibleForSpec(specId)
    return function(itemId)
        -- Prefer the committed, precomputed data (Core/SpecEligibilityData.lua,
        -- generated via Core/SpecEligibilityScan.lua's tooltip-scan
        -- technique and hand-merged in -- see
        -- docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md)
        -- when this spec has an entry: it's Blizzard's own
        -- server-computed loot table for the spec, not a heuristic, so
        -- it correctly rejects wrong-weapon/armor-type items the
        -- fallback below cannot.
        local bySpec = Where2GoSpecEligibilityData.BY_SPEC[specId]
        if bySpec and next(bySpec) ~= nil then
            return bySpec[itemId] == true
        end
```

The rest of the function (the `IsEquippableItem`/`GetItemSpecInfo`
fallback below this block) is unchanged.

- [ ] **Step 3: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]` (no existing test exercises `IsEligibleForSpec`
directly — it's WoW-API-dependent, same as before this change).

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/DirectDrop.lua
git commit -m "fix: IsEligibleForSpec consults committed SpecEligibilityData.lua first"
```

- [ ] **Step 5: Manual live verification (partial, completed in the Final verification section)**

In-game, immediately after this task: since `SpecEligibilityData.lua`'s
`BY_SPEC` is still empty at this point in the plan, confirm behavior is
identical to the old heuristic-only path (nothing should look different
yet — that's expected). The check that the committed data actually
*overrides* the heuristic correctly is deferred to this plan's Final
verification section, after Task 5 has produced at least one real
hand-merged spec.

---

## Task 5: `/where2go genspec` and `/where2go genspec reset` commands

**Depends on Task 3** (uses `Start()`'s new `"STALE_SEASON"` reason and
the repurposed export target).

**Files:**
- Modify: `Where2Go/Core/Init.lua`

**Interfaces:**
- Consumes: `Where2GoSpecEligibilityScan.Start()` (Task 3, now returning
  `"STALE_SEASON"` as a possible failure reason too),
  `Where2GoSpecEligibilityScan.SetProgressCallback(name, fn)` (unchanged,
  Phase 7), `Where2GoDB.specEligibilityExport` (Task 3's write target).
- Produces: two new subcommands under the existing `/where2go` dispatcher.

- [ ] **Step 1: Add the progress-callback handler and command handler functions**

In `Where2Go/Core/Init.lua`, insert the following right after
`HandleCompareCommand`'s closing `end` (and before the
`SLASH_WHERE2GO1 = "/where2go"` line):

```lua
local _lastGenspecSpecName

local function HandleGenspecProgress(specName, _current, _total, finishedReason)
    if finishedReason then
        _lastGenspecSpecName = nil
        if finishedReason == "COMPLETE" then
            print("Where2Go: genspec scan complete -- log out to flush SavedVariables, then hand-merge Where2GoDB.specEligibilityExport into Core/SpecEligibilityData.lua.")
        elseif finishedReason == "ABORTED_NAME_RESOLUTION" then
            print("Where2Go: genspec scan aborted -- item cache was cold. Try again after items have loaded (e.g. open your bags first).")
        elseif finishedReason == "ABORTED_COMBAT" then
            print("Where2Go: genspec scan aborted -- entered combat.")
        elseif finishedReason == "ABORTED_MANUAL_SPEC_CHANGE" then
            print("Where2Go: genspec scan aborted -- loot specialization was changed manually mid-scan.")
        elseif finishedReason == "ABORTED_ERROR" then
            print("Where2Go: genspec scan aborted due to an error -- see the error log.")
        end
        return
    end
    if specName ~= _lastGenspecSpecName then
        _lastGenspecSpecName = specName
        print(string.format("Where2Go: genspec scanning %s...", specName or "?"))
    end
end

local function DescribeCurrentClassSpecs()
    local names = {}
    for i = 1, GetNumSpecializations() do
        local _, specName = GetSpecializationInfo(i)
        if specName then
            table.insert(names, specName)
        end
    end
    return names
end

local function HandleGenspecCommand(args)
    local action = args[2]

    if action == "reset" then
        if not Where2GoDB.specEligibilityExport then
            print("Where2Go: no genspec export data to reset.")
            return
        end
        Where2GoDB.specEligibilityExport = nil
        print("Where2Go: genspec export data cleared.")
        return
    end

    if action then
        print("Usage: /where2go genspec [reset]")
        return
    end

    local _, className = UnitClass("player")
    local specNames = DescribeCurrentClassSpecs()
    print(string.format(
        "Where2Go: about to scan %d spec(s) for %s (%s) -- make sure this is a throwaway/safe character, this will temporarily change your loot specialization.",
        #specNames, className or "?", table.concat(specNames, ", ")))

    Where2GoSpecEligibilityScan.SetProgressCallback("genspec", HandleGenspecProgress)
    local ok, reason = Where2GoSpecEligibilityScan.Start()
    if ok then
        return
    end

    if reason == "STALE_SEASON" then
        print(string.format(
            "Where2Go: existing export data is from a previous season (%s) -- run '/where2go genspec reset' first, or it will be merged with the new season's data.",
            Where2GoDB.specEligibilityExport.seasonVersion))
    elseif reason == "RUNNING" then
        print("Where2Go: a genspec scan is already running.")
    elseif reason == "COMBAT" then
        print("Where2Go: cannot start a genspec scan while in combat.")
    elseif reason == "NO_SPECS" then
        print("Where2Go: this character has no specializations to scan.")
    elseif reason == "NO_ITEMS" then
        print("Where2Go: no Voidcache items configured to scan (check VoidcacheIds.lua).")
    end
end
```

- [ ] **Step 2: Wire the subcommand into the dispatcher**

Replace:

```lua
SLASH_WHERE2GO1 = "/where2go"
SLASH_WHERE2GO2 = "/w2g"
SlashCmdList["WHERE2GO"] = function(msg)
    local args = SplitArgs(msg)
    local subcommand = args[1]
    if subcommand == "pref" then
        HandlePrefCommand(args)
    elseif subcommand == "compare" then
        HandleCompareCommand()
    elseif subcommand == "browse" then
        Where2GoBrowserPanel.Toggle()
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare, /where2go browse")
    end
end
```

with:

```lua
SLASH_WHERE2GO1 = "/where2go"
SLASH_WHERE2GO2 = "/w2g"
SlashCmdList["WHERE2GO"] = function(msg)
    local args = SplitArgs(msg)
    local subcommand = args[1]
    if subcommand == "pref" then
        HandlePrefCommand(args)
    elseif subcommand == "compare" then
        HandleCompareCommand()
    elseif subcommand == "browse" then
        Where2GoBrowserPanel.Toggle()
    elseif subcommand == "genspec" then
        HandleGenspecCommand(args)
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare, /where2go browse, /where2go genspec [reset]")
    end
end
```

- [ ] **Step 3: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]` (`Init.lua` has no dedicated spec file — same as
before this change; `toc_spec.lua` still passes since no new file was
added).

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/Init.lua
git commit -m "feat: add /where2go genspec and genspec reset maintainer commands"
```

- [ ] **Step 5: Manual live verification**

In-game, on any character:
1. Run `/where2go genspec` — confirm the pre-scan message prints with the
   correct class name and spec list, the scan runs (~40s for a typical
   3-4 spec class), and `Where2Go: genspec scanning <spec>...` prints
   once per spec (not spammed every step).
2. Confirm `Where2Go: genspec scan complete...` prints at the end.
3. Run `/where2go genspec` again immediately — confirm it starts a fresh
   scan without complaint (same season, no staleness warning).
4. Log out, reopen `WTF/Account/<acct>/SavedVariables/Where2Go.lua`, and
   confirm `Where2GoDB.specEligibilityExport.bySpec` contains entries for
   every spec of the scanned class, each with a plausible non-empty item
   count.
5. Manually edit that file's `Where2GoDB.specEligibilityExport.seasonVersion`
   to a different string, log back in, and run `/where2go genspec` —
   confirm the stale-season warning prints and the scan does not start.
   Run `/where2go genspec reset` — confirm the data clears and a normal
   `/where2go genspec` now proceeds.

---

## Task 6: Document the season-changeover generation step

**Files:**
- Modify: `docs/SEASON_CHECKLIST.md`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Insert the new checklist step**

In `docs/SEASON_CHECKLIST.md`, insert a new step between the existing
step 4 ("Refresh `Where2Go/Core/VoidcacheIds.lua`") and step 5
("Re-run the item-stats data-prep script"), renumbering steps 5-10 to
6-11 accordingly. New step text:

```markdown
5. **Regenerate `Where2Go/Core/SpecEligibilityData.lua`.** This depends
   on step 4's refreshed `VoidcacheIds.lua`, so do it right after. Run
   `/where2go genspec reset` once to clear any leftover data from the
   previous season. Then, for every class in the game, log into (or
   create a throwaway) character of that class and run
   `/where2go genspec` — it scans all of that character's own class
   specs in one ~40-second pass and merges the result into
   `Where2GoDB.specEligibilityExport`, which survives across
   logins/characters until you reset it again. This is the slowest step
   in this checklist (one full pass per class); it's fine to spread it
   across as many sessions as needed since the data accumulates.

   Once every class is scanned, log out to flush SavedVariables, open
   `WTF/Account/<acct>/SavedVariables/Where2Go.lua`, and find the
   `Where2GoDB.specEligibilityExport.bySpec` table. **Eyeball it before
   copying anything**: every spec you scanned should have a plausible
   non-empty item count (roughly similar across specs of the same
   class) — a spec showing zero items usually means the item cache was
   cold during that scan and needs re-running. Once it looks right,
   hand-merge `bySpec`'s entries into
   `Where2Go/Core/SpecEligibilityData.lua`'s `BY_SPEC` table (matching
   this project's existing "human reviews the diff, never
   auto-overwrite" convention for committed data files), and update the
   file's own comment/history if useful context changed. See
   `docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md`
   for the full design rationale.
```

- [ ] **Step 2: Renumber the remaining steps and update their cross-references**

Renumber the old steps 5 through 10 to 6 through 11. Update the two
internal step-number references that point at each other:
- The old step 4's final bullet point ("This edit ... requires step 8's
  `SEASON_LABEL` bump ...") must now say "step 9's `SEASON_LABEL` bump"
  (since the old step 8 is now step 9).
- The old step 10 ("Run the full test suite and commit") stays last,
  renumbered to 11, and its file list should also mention
  `Where2Go/Core/SpecEligibilityData.lua` alongside the other data files
  it already lists (`Sources.lua`, `ItemStats.lua`, etc.), since it's
  now part of the same season-changeover commit.

- [ ] **Step 3: Commit**

```bash
git add docs/SEASON_CHECKLIST.md
git commit -m "docs: add SpecEligibilityData.lua regeneration step to season checklist"
```

---

## Final verification (after all tasks)

- [ ] Run the full suite one more time:
  `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
  Expected: all `[PASS]`, including `toc_spec.lua`'s completeness sweep
  (confirms `SpecEligibilityData.lua` is both present and TOC-registered)
  and the new `specEligibilityData_spec.lua`.
- [ ] Live check (deferred from Task 4, Step 5): after Task 5's manual
  verification has hand-merged at least one class's real scan result
  into `Where2Go/Core/SpecEligibilityData.lua`, open the item browser
  (`/where2go browse`) on a character of that class, select "eligible
  only," and confirm the result list matches what the committed data
  says — and that no `scanStatusText`/"scanning..." row appears anywhere
  in either panel anymore.
