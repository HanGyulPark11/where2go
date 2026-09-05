# Phase 8b: Encounter-Journal-Based `genspec` Rescan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Core/SpecEligibilityScan.lua`'s Nebulous-Voidcache-tooltip
scan (self-class-only, requires an alt per class) with Blizzard's
Encounter Journal loot filter (class-agnostic, scans every class/spec in
the game from one character in a single synchronous pass), without
changing `/where2go genspec`'s output format or the hand-merge workflow
downstream of it.

**Architecture:** `Core/SpecEligibilityScan.lua` is rewritten in place,
keeping its public API (`Start()`, `SetProgressCallback`, `IsRunning()`,
`MergeBySpec`, `CheckExportSeasonStale`) so `Init.lua`'s `/where2go
genspec` wiring needs only small changes. The old async tooltip-read
state machine is replaced by a synchronous loop over every
`Where2GoSources.lua` encounter × every class/spec in the game, driven by
`EJ_SetLootFilter`/`C_EncounterJournal.GetLootInfoByIndex`, with a new
pure `FilterKnownItemIds` helper ensuring only item IDs `Sources.lua`
already tracks can ever reach `BY_SPEC`. `Core/VoidcacheIds.lua` is
untouched (kept for an unrelated, separate backlog feature) — only its
consumer in `SpecEligibilityScan.lua` goes away.

**Tech Stack:** Lua (WoW addon), `lua5.1` for the plain-Lua test harness
(`tests/run_tests.lua`).

**Spec:** `docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md`

## Global Constraints

- Committed data files (`Sources.lua`, `ItemStats.lua`, `VoidcacheIds.lua`,
  `SpecEligibilityData.lua`) are never hand-edited casually — regenerate/
  re-merge from source, human reviews the diff before committing. This
  plan does not touch any committed data file's *content*, only the tool
  that generates `SpecEligibilityData.lua`'s input.
- `Core/VoidcacheIds.lua` and `tests/voidcacheids_spec.lua` must NOT be
  deleted or modified by this plan — they're kept for a separate,
  unstarted backlog feature (see the spec's "Why VoidcacheIds.lua
  survives" section). Do not remove them even though this plan removes
  their only current consumer.
- Every `.lua` file under `Where2Go/Core` or `Where2Go/UI` must be
  referenced in `Where2Go/Where2Go.toc`, enforced by
  `tests/toc_spec.lua`'s completeness sweep.
- Pure (no-WoW-API) functions get unit tests in `tests/`; WoW-API-dependent
  code (anything touching `C_EncounterJournal`, `EJ_*` globals, class/spec
  enumeration APIs) is verified live instead, matching this project's
  existing convention.
- Run the full suite with:
  `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`

---

## Task 1: Rewrite `Core/SpecEligibilityScan.lua` around the Encounter Journal

**Files:**
- Modify (full-file replacement): `Where2Go/Core/SpecEligibilityScan.lua`
- Modify (full-file replacement): `tests/specEligibilityScan_spec.lua`

**Interfaces:**
- Consumes: `Where2GoSources.DUNGEONS`/`.RAIDS` (each dungeon/raid entry's
  `instanceId` and each `encounters[i]`'s `bossId`/`itemIds`, all
  pre-existing fields, `Core/Sources.lua`), `Where2GoConstants.SEASON_LABEL`
  (`Core/Constants.lua`), `Where2GoDB.specEligibilityExport` (SavedVariables,
  `Core/Constants.lua`'s `BuildDefaultAccountDB`).
- Produces (unchanged public shape, new internals):
  `Where2GoSpecEligibilityScan.Start() -> ok, reason` (`reason` is now one
  of `"RUNNING"`, `"COMBAT"`, `"STALE_SEASON"`, `"EJ_LOAD_FAILED"`,
  `"ERROR"` — `"NO_SPECS"`/`"NO_ITEMS"` no longer occur and are removed),
  `Where2GoSpecEligibilityScan.SetProgressCallback(name, fn)`,
  `Where2GoSpecEligibilityScan.IsRunning() -> boolean`,
  `Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, newBySpec) -> mergedBySpec`
  (unchanged), `Where2GoSpecEligibilityScan.CheckExportSeasonStale(export, currentSeasonLabel) -> boolean`
  (unchanged). New pure function:
  `Where2GoSpecEligibilityScan.FilterKnownItemIds(filteredIds, knownItemIds) -> matchedIdSet`,
  consumed internally and by Task 1's own tests.
  `Where2GoSpecEligibilityScan.ParseTooltipLines` and
  `Where2GoSpecEligibilityScan.EnsureScanned` no longer exist after this
  task (the latter was already removed in Phase 8; confirm it's still
  gone).

- [ ] **Step 1: Replace the test file with the new pure-function coverage**

Overwrite `tests/specEligibilityScan_spec.lua` with:

```lua
dofile("Where2Go/Core/SpecEligibilityScan.lua")

-- FilterKnownItemIds: only ever returns item IDs present in BOTH the
-- filtered set and the known/tracked list -- this is the mechanism that
-- keeps non-gear Encounter Journal loot (mounts, pets, toys, quest
-- items, crafting reagents) out of BY_SPEC even if EJ's raw per-boss
-- loot list includes them.
local filtered = { [100] = true, [200] = true, [999] = true }
local known = { 100, 200, 300 }
local matched = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, known)
assert(matched[100] == true, "100 is in both filtered and known -- should match")
assert(matched[200] == true, "200 is in both filtered and known -- should match")
assert(matched[300] == nil, "300 is known but not in the filtered result -- should not match")
assert(matched[999] == nil, "999 is in the filtered result but NOT in the known/tracked list -- must never leak an untracked item")

local emptyFiltered = Where2GoSpecEligibilityScan.FilterKnownItemIds({}, known)
assert(next(emptyFiltered) == nil, "empty filtered set should produce an empty match set")

local emptyKnown = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, {})
assert(next(emptyKnown) == nil, "empty known list should produce an empty match set")

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

This drops the old `ParseTooltipLines` test cases entirely (the function
they covered is deleted in Step 3) and adds coverage for the new
`FilterKnownItemIds` function; `MergeBySpec`/`CheckExportSeasonStale`
coverage is unchanged.

- [ ] **Step 2: Run the test to verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/specEligibilityScan_spec.lua` with an error like
`attempt to call a nil value (field 'FilterKnownItemIds')` — the old
`SpecEligibilityScan.lua` (still in place until Step 3) has no such
function yet.

- [ ] **Step 3: Replace `Where2Go/Core/SpecEligibilityScan.lua`**

Overwrite the entire file with:

```lua
-- Generates Core/SpecEligibilityData.lua's BY_SPEC precomputed data: for
-- every class/spec in the game, which of Where2GoSources.lua's tracked
-- dungeon/raid items that spec can actually receive as loot.
-- Maintainer-only, triggered by `/where2go genspec`, merging its result
-- into the account-wide Where2GoDB.specEligibilityExport table for
-- manual hand-merging into the committed Core/SpecEligibilityData.lua
-- (consumed by Core/DirectDrop.lua's IsEligibleForSpec).
--
-- As of Phase 8b this drives Blizzard's own Encounter Journal loot
-- filter (EJ_SetLootFilter(classId, specId) + C_EncounterJournal.GetLootInfoByIndex)
-- instead of Phase 7/8's original Nebulous-Voidcache-tooltip +
-- SetLootSpecialization technique -- the Encounter Journal filter is
-- class-agnostic (works from a single character for every class/spec in
-- the game, not just the scanning character's own class) and returns
-- real numeric item IDs directly, with no tooltip-name-resolution/
-- cold-item-cache step at all. See
-- docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md.
-- Core/VoidcacheIds.lua is intentionally NOT used here anymore (kept in
-- the codebase for a separate, unstarted backlog feature -- see that
-- design doc's "Why VoidcacheIds.lua survives" section).
--
-- FilterKnownItemIds, MergeBySpec, and CheckExportSeasonStale below are
-- pure (no WoW API) and unit-tested in tests/specEligibilityScan_spec.lua.
-- The scan loop that calls them is WoW-API-dependent like
-- Core/VoidcoreDrop.lua/VoidcoreHistory.lua -- not unit-tested, verified
-- live instead.

Where2GoSpecEligibilityScan = {}

-- Pure: given the set of item IDs a loot filter currently returns
-- (`filteredIds`, `{[itemId]=true,...}`) and the list of item IDs
-- Where2GoSources.lua already tracks for one encounter (`knownItemIds`,
-- a plain array), returns only the intersection as a set. This is the
-- mechanism that keeps non-gear Encounter Journal loot (mounts, pets,
-- toys, quest items, crafting reagents) out of BY_SPEC entirely: an
-- item ID never appears in the result unless it was already in
-- `knownItemIds`, regardless of what else `filteredIds` contains.
function Where2GoSpecEligibilityScan.FilterKnownItemIds(filteredIds, knownItemIds)
    local matched = {}
    for _, itemId in ipairs(knownItemIds) do
        if filteredIds[itemId] then
            matched[itemId] = true
        end
    end
    return matched
end

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

local _running = false
local _progressCallbacks = {}

-- Registry keyed by an arbitrary caller-chosen name (e.g. "panel",
-- "browser") rather than a single slot, so multiple UI panels can each
-- register their own callback without one overwriting another's -- both
-- stay in sync regardless of which panel triggered the scan or which is
-- currently visible. Registering under the same name again (e.g. every
-- time a panel is shown) simply overwrites that caller's own entry, so
-- it's safe to call on every show.
function Where2GoSpecEligibilityScan.SetProgressCallback(name, fn)
    _progressCallbacks[name] = fn
end

local function NotifyProgress(specName, current, total, finishedReason)
    for _, fn in pairs(_progressCallbacks) do
        fn(specName, current, total, finishedReason)
    end
end

function Where2GoSpecEligibilityScan.IsRunning()
    return _running
end

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- Every dungeon/raid entry Where2GoSources.lua tracks, in one flat list,
-- each still carrying its own `encounters` array -- the scan loop below
-- iterates this directly rather than DUNGEONS/RAIDS separately, since
-- both need identical treatment (select instance, then per-encounter
-- work).
local function AllTrackedSources()
    local all = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(all, dungeon)
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        table.insert(all, raid)
    end
    return all
end

local function CollectCurrentLootItemIds()
    local ids = {}
    local numLoot = EJ_GetNumLoot() or 0
    for i = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then
            ids[info.itemID] = true
        end
    end
    return ids
end

-- The actual scan: for every tracked encounter, for every class/spec in
-- the game, ask the Encounter Journal which of that encounter's known
-- items this spec can receive. Runs synchronously (no C_Timer chunking)
-- since every call here is local client data with no server round-trip,
-- unlike the old tooltip-read/SetLootSpecialization flow. Wrapped in
-- pcall by Start() below, so any error here still leaves _running reset
-- correctly.
local function RunFullScan()
    local bySpec = {}
    local numClasses = GetNumClasses()
    local sex = UnitSex("player")

    for _, source in ipairs(AllTrackedSources()) do
        for _, encounter in ipairs(source.encounters) do
            EJ_SelectInstance(source.instanceId)
            EJ_SelectEncounter(encounter.bossId)

            for classIndex = 1, numClasses do
                local _, _, classId = GetClassInfo(classIndex)
                local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
                for specIndex = 1, numSpecs do
                    local specId = GetSpecializationInfoForClassID(classId, specIndex, sex)
                    if specId then
                        EJ_SetLootFilter(classId, specId)
                        local filtered = CollectCurrentLootItemIds()
                        local matched = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, encounter.itemIds)
                        if next(matched) ~= nil then
                            local existing = bySpec[specId] or {}
                            for itemId in pairs(matched) do
                                existing[itemId] = true
                            end
                            bySpec[specId] = existing
                        end
                    end
                end
            end
        end
        NotifyProgress(source.name, nil, nil, nil)
    end

    EJ_SetLootFilter(0, 0)
    return bySpec
end

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

    EnsureEncounterJournalLoaded()
    if not EJ_SelectInstance or not EJ_SelectEncounter or not C_EncounterJournal then
        return false, "EJ_LOAD_FAILED"
    end

    _running = true
    local ok, result = pcall(RunFullScan)
    _running = false

    if not ok then
        -- Surface the actual error via WoW's global error handler (the
        -- standard addon idiom -- routes to whatever error-display
        -- addon/console the player has, same as an unhandled Lua error
        -- would), rather than swallowing it silently.
        geterrorhandler()(result)
        NotifyProgress(nil, nil, nil, "ABORTED_ERROR")
        return false, "ERROR"
    end

    Where2GoDB.specEligibilityExport = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        bySpec = Where2GoSpecEligibilityScan.MergeBySpec(
            Where2GoDB.specEligibilityExport and Where2GoDB.specEligibilityExport.bySpec,
            result),
    }
    NotifyProgress(nil, nil, nil, "COMPLETE")
    return true
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`, including `tests/specEligibilityScan_spec.lua` and
`tests/toc_spec.lua` (the file still exists and is still TOC-registered,
only its contents changed).

- [ ] **Step 5: Commit**

```bash
git add Where2Go/Core/SpecEligibilityScan.lua tests/specEligibilityScan_spec.lua
git commit -m "feat: rewrite SpecEligibilityScan to use the Encounter Journal loot filter"
```

---

## Task 2: Update `/where2go genspec` and remove the throwaway diagnostic

**Depends on Task 1** (uses `Start()`'s new failure-reason set).

**Files:**
- Modify: `Where2Go/Core/Init.lua`
- Delete: `Where2Go/Core/EJDiagnostic.lua`
- Modify: `Where2Go/Where2Go.toc`

**Interfaces:**
- Consumes: `Where2GoSpecEligibilityScan.Start()` (Task 1, new reason set:
  `"RUNNING"`, `"COMBAT"`, `"STALE_SEASON"`, `"EJ_LOAD_FAILED"`, `"ERROR"`),
  `Where2GoSpecEligibilityScan.SetProgressCallback(name, fn)` (unchanged).
- Produces: no change to the command surface (`/where2go genspec`,
  `/where2go genspec reset` still exist with the same names) — only their
  internal messages change, and the throwaway `/where2go ejtest` command
  (added only to verify the spike, see
  `docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md`'s
  Problem section) is removed entirely.

- [ ] **Step 1: Replace the genspec progress/command handlers**

In `Where2Go/Core/Init.lua`, replace the entire block from
`local _lastGenspecSpecName` through `HandleGenspecCommand`'s closing
`end` (i.e. everything between `DescribeCandidate`'s/the preceding
function's closing `end` and the `SLASH_WHERE2GO1 = "/where2go"` line)
with:

```lua
local _lastGenspecSpecName

local function HandleGenspecProgress(specName, _current, _total, finishedReason)
    if finishedReason then
        _lastGenspecSpecName = nil
        if finishedReason == "COMPLETE" then
            print("Where2Go: genspec scan complete -- log out to flush SavedVariables, then hand-merge Where2GoDB.specEligibilityExport into Core/SpecEligibilityData.lua.")
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

    print("Where2Go: scanning every class/spec in the game via the Encounter Journal -- this does not change your loot specialization and should finish quickly.")

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
    elseif reason == "EJ_LOAD_FAILED" then
        print("Where2Go: genspec could not load the Blizzard_EncounterJournal addon -- try opening the in-game Dungeon Journal (default key: Shift+J) once, then run this again.")
    elseif reason == "ERROR" then
        print("Where2Go: genspec scan aborted due to an error -- see the error log.")
    end
end
```

This removes `DescribeCurrentClassSpecs` entirely (it enumerated only the
*scanning character's own* specs via `GetNumSpecializations()`, which no
longer describes what `/where2go genspec` actually scans) and drops the
`"NO_SPECS"`/`"NO_ITEMS"` branches (Task 1's `Start()` can no longer
return those reasons).

- [ ] **Step 2: Remove the `ejtest` dispatch and update the usage string**

Still in `Where2Go/Core/Init.lua`, replace:

```lua
    elseif subcommand == "genspec" then
        HandleGenspecCommand(args)
    elseif subcommand == "ejtest" then
        Where2GoEJDiagnostic.TestBoss(tonumber(args[2]), tonumber(args[3]))
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare, /where2go browse, /where2go genspec [reset], /where2go ejtest [bossId] [classId]")
    end
```

with:

```lua
    elseif subcommand == "genspec" then
        HandleGenspecCommand(args)
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare, /where2go browse, /where2go genspec [reset]")
    end
```

- [ ] **Step 3: Delete the throwaway diagnostic file and its TOC entry**

Delete `Where2Go/Core/EJDiagnostic.lua`:

```bash
git rm Where2Go/Core/EJDiagnostic.lua
```

In `Where2Go/Where2Go.toc`, remove the `Core\EJDiagnostic.lua` line
(between `Core\SpecEligibilityScan.lua` and `Core\Compare.lua`) so that
section reads:

```
Core\SpecEligibilityScan.lua
Core\Compare.lua
```

- [ ] **Step 4: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`, including `tests/toc_spec.lua` (confirms
`EJDiagnostic.lua` is gone from both disk and the TOC, and that every
remaining `.lua` file is still properly registered).

- [ ] **Step 5: Commit**

```bash
git add Where2Go/Core/Init.lua Where2Go/Where2Go.toc
git commit -m "feat: update genspec command for the Encounter Journal rescan, remove EJDiagnostic spike"
```

---

## Task 3: Update `docs/SEASON_CHECKLIST.md`

**Files:**
- Modify: `docs/SEASON_CHECKLIST.md`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Reword step 4 (VoidcacheIds.lua refresh)**

Replace:

```markdown
4. **Refresh `Where2Go/Core/VoidcacheIds.lua`.** No API endpoint exists
   for this data (see
   `docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`'s
   Data Sourcing section) — it's a manual per-entry Wowhead lookup. For
   every dungeon in the just-updated `Sources.lua` `DUNGEONS` list and
   every raid boss in `RAIDS`, search Wowhead for
   `"Nebulous Voidcache: <exact dungeon or boss name>"` and note the
   item ID from the result page's URL (`wowhead.com/item=<id>`). Update
   `Where2GoVoidcacheIds.DUNGEONS`/`RAID_BOSSES` with the new
   `[instanceId or bossId] = itemId` entries, replacing stale ones for
   content that rotated out.
   - A mid-season edit to this file or to `Sources.lua`'s item pools
     requires re-running step 5's `/where2go genspec` regeneration and
     hand-merge for every affected class — a newly-added item has no
     `BY_SPEC[specId]` entry yet, and absence means "ineligible", not
     "unknown", until it's regenerated. Do **not** bump `SEASON_LABEL`
     to try to force this: that field no longer triggers anything for
     spec-eligibility data, and bumping it mid-season will trip
     `Where2GoDB.specEligibilityExport`'s season-staleness guard and
     block further `/where2go genspec` runs until a `genspec reset`
     throws away any in-progress accumulated export data.
```

with:

```markdown
4. **Refresh `Where2Go/Core/VoidcacheIds.lua` (optional — currently
   unused by any shipped feature).** No API endpoint exists for this
   data (see
   `docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`'s
   Data Sourcing section) — it's a manual per-entry Wowhead lookup. As of
   Phase 8b, this file is no longer a dependency of step 5's
   spec-eligibility regeneration (that now drives the Encounter Journal
   directly off `Sources.lua`'s own `instanceId`/`bossId` fields). It's
   kept only for a separate, not-yet-built feature (backfilling a
   player's own pre-addon-install Voidcore obtained-item history — see
   `docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md`'s
   "Why VoidcacheIds.lua survives" section). **Skip this step during a
   normal season changeover** unless that feature has since been built —
   in which case refresh it the same way as before: for every dungeon in
   the just-updated `Sources.lua` `DUNGEONS` list and every raid boss in
   `RAIDS`, search Wowhead for `"Nebulous Voidcache: <exact dungeon or
   boss name>"` and note the item ID from the result page's URL
   (`wowhead.com/item=<id>`). Update
   `Where2GoVoidcacheIds.DUNGEONS`/`RAID_BOSSES` with the new
   `[instanceId or bossId] = itemId` entries, replacing stale ones for
   content that rotated out.
```

- [ ] **Step 2: Reword step 5 (SpecEligibilityData.lua regeneration)**

Replace:

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

with:

```markdown
5. **Regenerate `Where2Go/Core/SpecEligibilityData.lua`.** As of Phase
   8b this is independent of step 4 — it drives Blizzard's Encounter
   Journal loot filter directly off the just-updated `Sources.lua`'s own
   `instanceId`/`bossId` fields, not `VoidcacheIds.lua`. Log into any one
   character (any class) and run `/where2go genspec` once — it now scans
   every class and spec in the game in a single pass (not one pass per
   class), merging the result into `Where2GoDB.specEligibilityExport`.
   If leftover export data exists from a previous season, run
   `/where2go genspec reset` first to clear it (the scan will otherwise
   warn and refuse to run, to avoid silently merging two seasons' data
   together).

   A mid-season edit to `Sources.lua`'s item pools (e.g. a hotfixed item
   addition) also requires re-running this step — a newly-added item has
   no `BY_SPEC[specId]` entry yet, and absence means "ineligible", not
   "unknown", until regenerated. Do **not** bump `SEASON_LABEL` to try to
   force this: that field doesn't trigger anything here either, and
   bumping it mid-season will trip `Where2GoDB.specEligibilityExport`'s
   season-staleness guard and block `/where2go genspec` until a
   `genspec reset` throws away any in-progress accumulated data.

   Once scanned, log out to flush SavedVariables, open
   `WTF/Account/<acct>/SavedVariables/Where2Go.lua`, and find the
   `Where2GoDB.specEligibilityExport.bySpec` table. **Eyeball it before
   copying anything**: every spec should have a plausible non-empty item
   count (roughly similar across specs of the same class) — an
   unexpectedly-empty spec is worth re-running before trusting it. Once
   it looks right, hand-merge `bySpec`'s entries into
   `Where2Go/Core/SpecEligibilityData.lua`'s `BY_SPEC` table (matching
   this project's existing "human reviews the diff, never
   auto-overwrite" convention for committed data files). See
   `docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md`
   for the full design rationale.
```

- [ ] **Step 3: Update step 11's file list**

Replace:

```markdown
11. **Run the full test suite and commit.**
    ```
    "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
    ```
    Confirm all specs pass before committing the updated `Sources.lua`,
    `ItemStats.lua`, `RaidRanks.lua`, `Tracks.lua`, `Constants.lua`,
    `Where2Go/Core/VoidcacheIds.lua`, `Where2Go/Core/SpecEligibilityData.lua`, and `sources_spec.lua` together.
```

with:

```markdown
11. **Run the full test suite and commit.**
    ```
    "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
    ```
    Confirm all specs pass before committing the updated `Sources.lua`,
    `ItemStats.lua`, `RaidRanks.lua`, `Tracks.lua`, `Constants.lua`,
    `Where2Go/Core/SpecEligibilityData.lua`, `sources_spec.lua`, and (only
    if step 4 was actually performed this season) `Where2Go/Core/VoidcacheIds.lua`
    together.
```

- [ ] **Step 4: Commit**

```bash
git add docs/SEASON_CHECKLIST.md
git commit -m "docs: update season checklist for the Encounter-Journal-based genspec rescan"
```

---

## Final verification (after all tasks)

- [ ] Run the full suite one more time:
  `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
  Expected: all `[PASS]`, same spec count as before this plan minus zero
  (no spec files were removed, only `specEligibilityScan_spec.lua`'s
  contents changed) — `toc_spec.lua` in particular confirms
  `EJDiagnostic.lua` is fully gone and every remaining file is still
  TOC-registered.
- [ ] **Live timing measurement (unverified risk flagged in the spec's
  Performance section).** In-game, on any character: run
  `/where2go genspec` and time it. Confirm it completes without a "script
  ran too long" error/disconnect. The spec estimates ~1,500
  `EJ_SetLootFilter` calls (37 tracked encounters × ~40 total specs
  across 13 classes) and expects well under a second, but this has never
  been measured live. If it *does* trip the watchdog or visibly hitch the
  client, that's a real finding — do not silently patch around it as part
  of this plan; report it back so a minimal `C_Timer.After(0, ...)` yield
  (e.g. once per `source` in `RunFullScan`'s outer loop) can be added as
  a small follow-up, per the spec's guidance.
- [ ] **Spot-check against the already-confirmed diagnostic result.**
  Before this plan, the throwaway `EJDiagnostic.lua` spike was run live
  against Zul'jan (Altar of Fangs, bossId 2880) for Druid (classId 11)
  and confirmed correct per-spec filtering (see the design doc's Problem
  section for the exact result). After running `/where2go genspec`, log
  out, open `WTF/Account/<acct>/SavedVariables/Where2Go.lua`, and check
  `Where2GoDB.specEligibilityExport.bySpec` for each Druid spec ID:
  confirm item 273778 appears only under the two intellect specs
  (Balance/Restoration), item 273797 appears under Feral but not
  Guardian, and none of Zul'jan's 12 tracked item IDs
  (`Where2Go/Core/Sources.lua`'s `Altar of Fangs` → `Zul'jan` entry) leak
  into a spec that shouldn't have them. This confirms the rewritten
  engine reproduces the spike's already-verified result, not just that it
  runs without erroring.
- [ ] Confirm `Where2Go/Core/VoidcacheIds.lua` and
  `tests/voidcacheids_spec.lua` are unchanged (`git diff` against the
  commit before this plan started should show no changes to either
  file) — a regression here would silently break the future backlog
  feature that depends on this data surviving untouched.
- [ ] Confirm `/where2go genspec reset` still works: with export data
  present from the timing-measurement run above, run
  `/where2go genspec reset`, confirm the clear message prints, then run
  `/where2go genspec` again and confirm it starts a fresh scan without a
  stale-season complaint.
