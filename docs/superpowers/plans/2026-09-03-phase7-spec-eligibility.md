# Phase 7: Accurate Spec-Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Where2GoDirectDrop.IsEligibleForSpec`'s known-imperfect
`GetItemSpecInfo`/`IsEquippableItem` heuristic with real per-spec data
scanned live from Blizzard's own "Nebulous Voidcache" tooltips, so
wrong-weapon/armor-type items stop showing as spec-eligible everywhere
they currently do (DirectDrop's ranking, VoidcoreDrop's ranking, and the
item browser's "spec eligible only" filter).

**Architecture:** A new committed data file maps each dungeon/raid boss
to its per-content "Nebulous Voidcache" item ID. A new scan module reads
that item's tooltip once per player-class-spec (switching
`SetLootSpecialization` temporarily), parses the item names it lists,
and matches them against Where2Go's own known item pool to build a
per-character `{ [specId] = { [itemId] = true } }` table. This table is
consulted first by the existing `IsEligibleForSpec` function, falling
back to today's heuristic when absent. The scan runs automatically (no
button) the first time a ranked panel or the item browser opens each
season, covering every spec of the player's class in one pass. The item
browser also gains a spec-selector dropdown so its "spec eligible only"
filter can target any of the player's specs, not just the active one.

**Tech Stack:** World of Warcraft addon Lua 5.1 (`Where2Go/Core/*.lua`,
`Where2Go/UI/*.lua`), WoW client APIs (`C_TooltipInfo`, `C_Item`,
`SetLootSpecialization`, `GetSpecializationInfo`), the project's custom
test harness (`tests/run_tests.lua`, run via
`"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"`).

**Spec:** `docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`

## Global Constraints

- No manual scan trigger (no button, no slash command) — the scan starts
  automatically when needed, per the spec's Trigger section.
- The scan covers only the specializations of the player's own current
  class, in one pass covering all of them — not a global, multi-class
  data file, and not one-spec-at-a-time lazy scanning.
- `Where2GoCharDB.specEligibility` is per-character saved data, never a
  committed file.
- `Where2Go/Core/VoidcacheIds.lua` data must not be copied from
  `rolferik12/VoidcoreAdvisor` (unlicensed) — this plan uses only the 17
  IDs already independently verified against Wowhead in the design doc's
  Data Sourcing table.
- The spec-selector dropdown is added to the item browser only —
  DirectDrop's and VoidcoreDrop's own ranked-card panels keep using only
  the character's actual current active spec.
- `IsEligibleForSpec` must keep working exactly as it does today when no
  scan data is available yet (graceful degrade, never a hard failure).
- Any new `.lua` file under `Where2Go/Core` or `Where2Go/UI` must be
  added to `Where2Go/Where2Go.toc` (enforced by `tests/toc_spec.lua`'s
  completeness sweep) and, if it has pure testable logic, its spec file
  added to `tests/run_tests.lua`'s `specs` list.

---

## Task 1: `Where2Go/Core/VoidcacheIds.lua` data file

**Files:**
- Create: `Where2Go/Core/VoidcacheIds.lua`
- Modify: `Where2Go/Where2Go.toc` (add the new file after `Core\Sources.lua`)
- Modify: `docs/SEASON_CHECKLIST.md` (add a refresh-procedure step)
- Test: `tests/voidcacheids_spec.lua`
- Modify: `tests/run_tests.lua` (register the new spec)

**Interfaces:**
- Produces: `Where2GoVoidcacheIds.DUNGEONS` — `{ [instanceId] = voidcacheItemId }`.
  `Where2GoVoidcacheIds.RAID_BOSSES` — `{ [bossId] = voidcacheItemId }`.
  Both consumed by Task 3's `SpecEligibilityScan.lua`.

- [ ] **Step 1: Write the failing coverage test**

Create `tests/voidcacheids_spec.lua`:

```lua
dofile("Where2Go/Core/VoidcacheIds.lua")
dofile("Where2Go/Core/Sources.lua")

assert(type(Where2GoVoidcacheIds) == "table", "Where2GoVoidcacheIds should be a table")
assert(type(Where2GoVoidcacheIds.DUNGEONS) == "table", "Where2GoVoidcacheIds.DUNGEONS should be a table")
assert(type(Where2GoVoidcacheIds.RAID_BOSSES) == "table", "Where2GoVoidcacheIds.RAID_BOSSES should be a table")

local dungeonCount = 0
for instanceId, itemId in pairs(Where2GoVoidcacheIds.DUNGEONS) do
    assert(type(instanceId) == "number", "DUNGEONS keys should be numeric instance IDs")
    assert(type(itemId) == "number", "DUNGEONS values should be numeric item IDs")
    dungeonCount = dungeonCount + 1
end
assert(dungeonCount > 0, "Where2GoVoidcacheIds.DUNGEONS should be non-empty")

local bossCount = 0
for bossId, itemId in pairs(Where2GoVoidcacheIds.RAID_BOSSES) do
    assert(type(bossId) == "number", "RAID_BOSSES keys should be numeric boss IDs")
    assert(type(itemId) == "number", "RAID_BOSSES values should be numeric item IDs")
    bossCount = bossCount + 1
end
assert(bossCount > 0, "Where2GoVoidcacheIds.RAID_BOSSES should be non-empty")

-- Cross-check every Sources.lua dungeon/boss has a corresponding
-- Voidcache item ID, so a season changeover that regenerates Sources.lua
-- can't silently leave VoidcacheIds.lua stale.
for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
    assert(
        Where2GoVoidcacheIds.DUNGEONS[dungeon.instanceId] ~= nil,
        "Where2GoVoidcacheIds.DUNGEONS is missing an entry for instance " .. dungeon.instanceId .. " (" .. dungeon.name .. ")"
    )
end

for _, raid in ipairs(Where2GoSources.RAIDS) do
    for _, encounter in ipairs(raid.encounters) do
        assert(
            Where2GoVoidcacheIds.RAID_BOSSES[encounter.bossId] ~= nil,
            "Where2GoVoidcacheIds.RAID_BOSSES is missing an entry for boss " .. encounter.bossId .. " (" .. encounter.name .. ")"
        )
    end
end

print("voidcacheids_spec: OK, " .. dungeonCount .. " dungeon(s), " .. bossCount .. " raid boss(es), all cross-checked against Sources.lua")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/voidcacheids_spec.lua`
Expected: FAIL — cannot open `Where2Go/Core/VoidcacheIds.lua` (file does not exist yet).

- [ ] **Step 3: Create the data file**

Create `Where2Go/Core/VoidcacheIds.lua`:

```lua
-- Nebulous Voidcache item IDs per dungeon instance / raid boss for the
-- current season. Each dungeon and raid boss has its own distinct
-- "Nebulous Voidcache: <content name>" item; its tooltip lists exactly
-- what a given loot specialization can receive from that content (see
-- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md).
--
-- Sourced by searching Wowhead for "Nebulous Voidcache: <exact
-- Sources.lua dungeon/boss name>" and confirming the item ID from the
-- page for all 17 entries below -- NOT copied from any third-party
-- addon's data file (see that design doc's Data Sourcing section for
-- the full verified table and provenance).
--
-- Do not hand-edit without re-verifying on Wowhead. Refresh procedure:
-- docs/SEASON_CHECKLIST.md.

Where2GoVoidcacheIds = {}

-- [instanceId] = Nebulous Voidcache itemId, one per Sources.lua DUNGEONS entry.
Where2GoVoidcacheIds.DUNGEONS = {
    [1322] = 279618, -- Altar of Fangs
    [1311] = 279620, -- Den of Nalorakk
    [1304] = 279623, -- Murder Row
    [1309] = 279619, -- The Blinding Vale
    [1313] = 279625, -- Voidscar Arena
    [1041] = 279621, -- Kings' Rest
    [1202] = 279622, -- Ruby Life Pools
    [1030] = 279624, -- Temple of Sethraliss
}

-- [bossId] = Nebulous Voidcache itemId, one per Sources.lua RAIDS encounter.
Where2GoVoidcacheIds.RAID_BOSSES = {
    [2849] = 274708, -- Nymrissa Wavecaller (The Tidebound Grotto)
    [2888] = 278285, -- Nek'zali the Soulcoiler (The Venomous Abyss)
    [2874] = 278283, -- Entombed Sentinels
    [2894] = 278286, -- The Lost Explorers
    [2882] = 278287, -- Vashnik the Malignant
    [2871] = 278288, -- Sszorak
    [2887] = 278289, -- The Twin Fangs
    [2883] = 278290, -- The Coiled Altar
    [2895] = 278284, -- Ula'tek
}
```

- [ ] **Step 4: Register the file in the TOC**

Modify `Where2Go/Where2Go.toc` — insert `Core\VoidcacheIds.lua` right
after `Core\Sources.lua`:

```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\VoidcacheIds.lua
Core\ItemStats.lua
Core\ItemBrowser.lua
Core\RaidRanks.lua
Core\Ranking.lua
Core\DirectDrop.lua
Core\VoidcoreHistory.lua
Core\VoidcoreDrop.lua
Core\Compare.lua
Core\Equipment.lua
Core\Init.lua
UI\Panel.lua
UI\BrowserPanel.lua
```

- [ ] **Step 5: Register the spec in run_tests.lua**

Modify `tests/run_tests.lua` — add `"tests/voidcacheids_spec.lua"` to the
`specs` list, next to `"tests/sources_spec.lua"`:

```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/toc_spec.lua",
    "tests/tracks_spec.lua",
    "tests/compare_spec.lua",
    "tests/sources_spec.lua",
    "tests/voidcacheids_spec.lua",
    "tests/itemstats_spec.lua",
    "tests/raidranks_spec.lua",
    "tests/ranking_spec.lua",
    "tests/voidcorehistory_spec.lua",
    "tests/itembrowser_spec.lua",
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/voidcacheids_spec.lua`
Expected: PASS — prints `voidcacheids_spec: OK, 8 dungeon(s), 9 raid boss(es), all cross-checked against Sources.lua`

- [ ] **Step 7: Add the season refresh procedure to SEASON_CHECKLIST.md**

Modify `docs/SEASON_CHECKLIST.md` — insert a new step 4 (renumbering the
existing steps 4-9 to 5-10) between the current step 3 (Sources.lua
review) and the current step 4 (ItemStats.lua regeneration), so
`VoidcacheIds.lua` is refreshed right after `Sources.lua` changes since
its entries are keyed off `Sources.lua`'s dungeon/boss list:

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
```

Renumber the remaining steps (old step 4 "Re-run the item-stats
data-prep script" becomes step 5, and so on through old step 9 becoming
step 10), keeping their content unchanged otherwise.

- [ ] **Step 8: Run the full suite and commit**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `11 spec file(s), 0 failure(s)`

```bash
git add Where2Go/Core/VoidcacheIds.lua Where2Go/Where2Go.toc tests/voidcacheids_spec.lua tests/run_tests.lua docs/SEASON_CHECKLIST.md
git commit -m "feat: add VoidcacheIds.lua dungeon/boss Voidcache item ID data"
```

---

## Task 2: `SpecEligibilityScan.lua` tooltip-parsing (pure, tested)

**Files:**
- Create: `Where2Go/Core/SpecEligibilityScan.lua`
- Modify: `Where2Go/Where2Go.toc` (add the new file after `Core\VoidcoreDrop.lua`)
- Test: `tests/specEligibilityScan_spec.lua`
- Modify: `tests/run_tests.lua` (register the new spec)

**Interfaces:**
- Produces: `Where2GoSpecEligibilityScan.ParseTooltipLines(lines)` — pure
  function. `lines` is an array shaped like `C_TooltipInfo.GetItemByID(...).lines`
  (each entry `{ leftText = "..." }`). Returns `{ [itemName] = true }` or
  `nil` if `lines` is nil/empty or has fewer than 7 entries. Consumed by
  Task 3's scan step.

- [ ] **Step 1: Write the failing tests**

Create `tests/specEligibilityScan_spec.lua`:

```lua
dofile("Where2Go/Core/SpecEligibilityScan.lua")

-- Too few lines (or none) -> nil
assert(Where2GoSpecEligibilityScan.ParseTooltipLines(nil) == nil, "nil lines should return nil")
assert(Where2GoSpecEligibilityScan.ParseTooltipLines({}) == nil, "empty lines should return nil")

local shortLines = {}
for i = 1, 6 do
    shortLines[i] = { leftText = "Line " .. i }
end
assert(Where2GoSpecEligibilityScan.ParseTooltipLines(shortLines) == nil, "fewer than 7 lines should return nil")

-- A realistic tooltip: 6 header lines, then item lines starting at index 7.
local fullLines = {
    { leftText = "Nebulous Voidcache: Altar of Fangs" }, -- 1
    { leftText = "Item Level 200" },                      -- 2
    { leftText = "Binds when picked up" },                -- 3
    { leftText = "Unique" },                               -- 4
    { leftText = "Use: Open to receive one of the following items:" }, -- 5
    { leftText = "Requires a Loot Specialization" },      -- 6
    { leftText = "- Sample Sword" },                       -- 7
    { leftText = "- Sample Ring" },                        -- 8
    { leftText = "|cffffffff- Colored Item Name|r" },      -- 9
}
local parsed = Where2GoSpecEligibilityScan.ParseTooltipLines(fullLines)
assert(parsed ~= nil, "7+ lines should parse successfully")
assert(parsed["Sample Sword"] == true, "should extract 'Sample Sword'")
assert(parsed["Sample Ring"] == true, "should extract 'Sample Ring'")
assert(parsed["Colored Item Name"] == true, "should strip color codes before extracting the name")

local count = 0
for _ in pairs(parsed) do count = count + 1 end
assert(count == 3, "should extract exactly 3 item names, got " .. count)

-- A non-prefixed line at index >= 7 should be ignored, not mistaken for an item.
local withNoise = {
    { leftText = "H1" }, { leftText = "H2" }, { leftText = "H3" },
    { leftText = "H4" }, { leftText = "H5" }, { leftText = "H6" },
    { leftText = "Not an item line" },
    { leftText = "- Real Item" },
}
local parsedNoise = Where2GoSpecEligibilityScan.ParseTooltipLines(withNoise)
assert(parsedNoise["Real Item"] == true, "should extract the prefixed item line")
local noiseCount = 0
for _ in pairs(parsedNoise) do noiseCount = noiseCount + 1 end
assert(noiseCount == 1, "should ignore non-prefixed lines, got " .. noiseCount .. " entries")

print("specEligibilityScan_spec: OK")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/specEligibilityScan_spec.lua`
Expected: FAIL — cannot open `Where2Go/Core/SpecEligibilityScan.lua` (file does not exist yet).

- [ ] **Step 3: Create the module with the pure parsing function**

Create `Where2Go/Core/SpecEligibilityScan.lua`:

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

Where2GoSpecEligibilityScan = {}

-- Item-name lines in a Nebulous Voidcache tooltip start at this index
-- (1-based) and are each prefixed "- ". Fewer lines than this means the
-- tooltip hasn't finished loading yet.
local MIN_LINES = 7

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Pure function: parses tooltip line data (shaped like
-- C_TooltipInfo.GetItemByID(...).lines, an array of { leftText = "..." })
-- into a { [itemName] = true } set. Returns nil if there are fewer than
-- MIN_LINES lines (tooltip not fully loaded yet).
function Where2GoSpecEligibilityScan.ParseTooltipLines(lines)
    if not lines or #lines < MIN_LINES then
        return nil
    end
    local items = {}
    for i, lineData in ipairs(lines) do
        if i >= MIN_LINES then
            local text = lineData.leftText
            if text then
                local clean = StripColorCodes(text)
                if clean:sub(1, 2) == "- " then
                    local itemName = clean:sub(3):match("^(.-)%s*$")
                    if itemName and itemName ~= "" then
                        items[itemName] = true
                    end
                end
            end
        end
    end
    return items
end
```

- [ ] **Step 4: Register the file in the TOC**

Modify `Where2Go/Where2Go.toc` — insert `Core\SpecEligibilityScan.lua`
right after `Core\VoidcoreDrop.lua`:

```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\VoidcacheIds.lua
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

- [ ] **Step 5: Register the spec in run_tests.lua**

Modify `tests/run_tests.lua` — add `"tests/specEligibilityScan_spec.lua"`
right after `"tests/voidcorehistory_spec.lua"`:

```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/toc_spec.lua",
    "tests/tracks_spec.lua",
    "tests/compare_spec.lua",
    "tests/sources_spec.lua",
    "tests/voidcacheids_spec.lua",
    "tests/itemstats_spec.lua",
    "tests/raidranks_spec.lua",
    "tests/ranking_spec.lua",
    "tests/voidcorehistory_spec.lua",
    "tests/specEligibilityScan_spec.lua",
    "tests/itembrowser_spec.lua",
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/specEligibilityScan_spec.lua`
Expected: PASS — prints `specEligibilityScan_spec: OK`

- [ ] **Step 7: Run the full suite and commit**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `12 spec file(s), 0 failure(s)`

```bash
git add Where2Go/Core/SpecEligibilityScan.lua Where2Go/Where2Go.toc tests/specEligibilityScan_spec.lua tests/run_tests.lua
git commit -m "feat: add SpecEligibilityScan tooltip-line parsing"
```

---

## Task 3: `SpecEligibilityScan.lua` scan engine

**Files:**
- Modify: `Where2Go/Core/SpecEligibilityScan.lua` (append to the file
  created in Task 2; do not touch `ParseTooltipLines` or `MIN_LINES`)

**Interfaces:**
- Consumes: `Where2GoSpecEligibilityScan.ParseTooltipLines(lines)` (Task 2).
  `Where2GoVoidcacheIds.DUNGEONS` / `.RAID_BOSSES` (Task 1).
  `Where2GoSources.DUNGEONS` / `.RAIDS` (existing).
  `Where2GoConstants.SEASON_LABEL` (existing, `Core/Constants.lua`).
- Produces: `Where2GoSpecEligibilityScan.Start()` — returns `true` on
  success or `false, reason` (`reason` one of `"RUNNING"`, `"COMBAT"`,
  `"NO_SPECS"`, `"NO_ITEMS"`). `Where2GoSpecEligibilityScan.EnsureScanned()`
  — no-op if already scanned for the current season, already running, or
  in combat; otherwise calls `Start()`. `Where2GoSpecEligibilityScan.IsRunning()`
  — returns boolean. `Where2GoSpecEligibilityScan.SetProgressCallback(fn)`
  — `fn(specName, current, total, finishedReason)`; `finishedReason` is
  `nil` while scanning and one of `"COMPLETE"`/`"ABORTED_COMBAT"`/
  `"ABORTED_MANUAL_SPEC_CHANGE"` when done. Writes
  `Where2GoCharDB.specEligibility = { seasonVersion, scannedAt,
  bySpec = { [specId] = { [itemId] = true, ... } } }` on completion.
  Consumed by Task 4 (`DirectDrop.IsEligibleForSpec`) and Task 6 (UI wiring).

This task is WoW-API-dependent (combat state, tooltip reads, loot
specialization) and not unit-tested — verify live per the Testing
Checkpoint at the end of this task, the same way `Core/VoidcoreDrop.lua`
and `Core/VoidcoreHistory.lua` are.

- [ ] **Step 1: Append the scan engine to the module**

Add the following to the end of `Where2Go/Core/SpecEligibilityScan.lua`
(after `ParseTooltipLines`'s closing `end`):

```lua
local RETRY_DELAY = 0.35
local STEP_DELAY = 0.5
local SPEC_CHANGE_DELAY = 1.2
local MAX_RETRIES = 5

local _state = nil
local _progressCallback = nil

function Where2GoSpecEligibilityScan.SetProgressCallback(fn)
    _progressCallback = fn
end

local function NotifyProgress(specName, current, total, finishedReason)
    if _progressCallback then
        _progressCallback(specName, current, total, finishedReason)
    end
end

function Where2GoSpecEligibilityScan.IsRunning()
    return _state ~= nil and _state.running == true
end

local function CollectVoidcacheItemList()
    local items = {}
    for _, itemId in pairs(Where2GoVoidcacheIds.DUNGEONS) do
        table.insert(items, itemId)
    end
    for _, itemId in pairs(Where2GoVoidcacheIds.RAID_BOSSES) do
        table.insert(items, itemId)
    end
    return items
end

-- Every item ID Sources.lua tracks -- the pool a scanned item name needs
-- to resolve against to recover its numeric item ID (tooltips only give
-- names). Requires the item cache to be warm; an item whose name isn't
-- cached yet at scan time is silently skipped for this scan, the same
-- accepted limitation Core/DirectDrop.lua's own header already notes
-- for a cold item cache.
local function CollectAllPoolItemIds()
    local ids = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        for _, encounter in ipairs(dungeon.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                ids[itemId] = true
            end
        end
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                ids[itemId] = true
            end
        end
    end
    return ids
end

local function BuildNameToItemId()
    local nameToItemId = {}
    for itemId in pairs(CollectAllPoolItemIds()) do
        local name = C_Item.GetItemInfo(itemId)
        if name and name ~= "" then
            nameToItemId[name] = itemId
        end
    end
    return nameToItemId
end

local _combatFrame
if CreateFrame then
    _combatFrame = CreateFrame("Frame")
end

local function AbortScan(reason)
    if not _state then
        return
    end
    _state.running = false
    if _combatFrame then
        _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end
    if _state.originalLootSpec ~= nil then
        SetLootSpecialization(_state.originalLootSpec)
    end
    NotifyProgress(nil, nil, nil, reason)
    _state = nil
end

local function FinalizeScan()
    if not _state then
        return
    end
    local bySpec = {}
    for _, specEntry in ipairs(_state.specs) do
        local nameSet = _state.results[specEntry.specId] or {}
        local itemSet = {}
        for name in pairs(nameSet) do
            local itemId = _state.nameToItemId[name]
            if itemId then
                itemSet[itemId] = true
            end
        end
        bySpec[specEntry.specId] = itemSet
    end

    Where2GoCharDB.specEligibility = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        scannedAt = time(),
        bySpec = bySpec,
    }

    if _combatFrame then
        _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end
    SetLootSpecialization(_state.originalLootSpec or 0)
    NotifyProgress(nil, nil, nil, "COMPLETE")
    _state = nil
end

local ScanStep
ScanStep = function()
    if not _state or not _state.running then
        return
    end

    if _state.specIdx > #_state.specs then
        FinalizeScan()
        return
    end

    local specEntry = _state.specs[_state.specIdx]
    local voidcacheItemId = _state.items[_state.itemIdx]

    -- Switch loot spec once at the start of each spec's pass (first
    -- item, no retries yet), then wait for it to take effect.
    -- expectingSpecChange tells the PLAYER_LOOT_SPEC_UPDATED handler
    -- below that this particular change came from the scan itself, not
    -- the player manually changing loot spec mid-scan (which would
    -- otherwise silently attribute the rest of this pass's tooltip
    -- reads to the wrong spec).
    if _state.itemIdx == 1 and _state.retries == 0 and not _state.specSwitchDone then
        _state.expectingSpecChange = true
        SetLootSpecialization(specEntry.specId)
        _state.specSwitchDone = true
        C_Timer.After(SPEC_CHANGE_DELAY, ScanStep)
        return
    end
    _state.expectingSpecChange = false

    local tooltipData = C_TooltipInfo.GetItemByID(voidcacheItemId)
    local lines = tooltipData and tooltipData.lines
    local parsed = Where2GoSpecEligibilityScan.ParseTooltipLines(lines)

    if not parsed then
        _state.retries = _state.retries + 1
        if _state.retries <= MAX_RETRIES then
            C_Timer.After(RETRY_DELAY, ScanStep)
            return
        end
        parsed = {}
    end

    local specNames = _state.results[specEntry.specId] or {}
    for name in pairs(parsed) do
        specNames[name] = true
    end
    _state.results[specEntry.specId] = specNames

    _state.retries = 0
    _state.itemIdx = _state.itemIdx + 1
    if _state.itemIdx > #_state.items then
        _state.itemIdx = 1
        _state.specIdx = _state.specIdx + 1
        _state.specSwitchDone = false
    end

    local completedSteps = (_state.specIdx - 1) * #_state.items + (_state.itemIdx == 1 and 0 or _state.itemIdx - 1)
    NotifyProgress(specEntry.specName, completedSteps, #_state.specs * #_state.items, nil)

    C_Timer.After(STEP_DELAY, ScanStep)
end

function Where2GoSpecEligibilityScan.Start()
    if Where2GoSpecEligibilityScan.IsRunning() then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end

    local numSpecs = GetNumSpecializations()
    local specs = {}
    for i = 1, numSpecs do
        local specId, specName = GetSpecializationInfo(i)
        if specId then
            table.insert(specs, { specId = specId, specName = specName })
        end
    end
    if #specs == 0 then
        return false, "NO_SPECS"
    end

    local items = CollectVoidcacheItemList()
    if #items == 0 then
        return false, "NO_ITEMS"
    end

    for itemId in pairs(CollectAllPoolItemIds()) do
        C_Item.RequestLoadItemDataByID(itemId)
    end

    _state = {
        running = true,
        specs = specs,
        items = items,
        specIdx = 1,
        itemIdx = 1,
        retries = 0,
        specSwitchDone = false,
        expectingSpecChange = false,
        results = {},
        nameToItemId = BuildNameToItemId(),
        originalLootSpec = GetLootSpecialization(),
    }

    if _combatFrame then
        _combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end

    NotifyProgress(specs[1].specName, 0, #specs * #items, nil)
    C_Timer.After(0, ScanStep)
    return true
end

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

if _combatFrame then
    _combatFrame:SetScript("OnEvent", function(_self, event)
        if not _state or not _state.running then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            AbortScan("ABORTED_COMBAT")
        elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
            if not _state.expectingSpecChange then
                AbortScan("ABORTED_MANUAL_SPEC_CHANGE")
            end
        end
    end)
end
```

- [ ] **Step 2: Run the full test suite to confirm nothing broke**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `12 spec file(s), 0 failure(s)` — the new code is guarded behind
`if CreateFrame then ... end` and function bodies that are never called
by the plain-Lua test harness, so `specEligibilityScan_spec.lua` still
passes unchanged.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/Core/SpecEligibilityScan.lua
git commit -m "feat: add SpecEligibilityScan scan engine"
```

- [ ] **Step 4: Live Testing Checkpoint**

In the live WoW client, with the addon loaded:
1. `/run Where2GoSpecEligibilityScan.SetProgressCallback(function(n,c,t,f) print(n,c,t,f) end)`
2. `/run print(Where2GoSpecEligibilityScan.Start())` — expect `true`
   printed, then a stream of progress prints as it runs (roughly
   `(specCount * 17)` steps total, ~15-40s per spec).
3. Watch chat for the final `nil nil nil COMPLETE` progress line.
4. `/dump Where2GoCharDB.specEligibility.seasonVersion` — should print
   the current season label.
5. `/dump Where2GoCharDB.specEligibility.bySpec` — should show one key
   per class spec, each a non-empty item-ID table.
6. Pick one item ID from your current spec's `bySpec` entry and confirm
   with `/dump C_Item.GetItemInfo(<id>)` that it's a real, class-
   appropriate item (not, e.g., a wrong-weapon-type item that shouldn't
   be there).
7. Move into combat (or `/run Where2GoSpecEligibilityScan.Start()` then
   immediately enter combat) and confirm the scan aborts cleanly — chat
   shows an `ABORTED_COMBAT` progress line and your loot specialization
   reverts to what it was before the scan (`/run print(GetLootSpecialization())`
   before and after to compare).
8. `/run Where2GoSpecEligibilityScan.Start()`, then within the first
   couple seconds manually change your loot specialization via the
   in-game Specialization UI — confirm the scan aborts with
   `ABORTED_MANUAL_SPEC_CHANGE` rather than silently continuing and
   attributing the rest of that pass's tooltip reads to the wrong spec.

If any check fails, fix the code in this task before moving on — later
tasks assume `Where2GoCharDB.specEligibility` is populated correctly by
a working scan.

---

## Task 4: `DirectDrop.lua` consults scanned data first

**Files:**
- Modify: `Where2Go/Core/DirectDrop.lua:68-100` (`IsEligibleForSpec`)

**Interfaces:**
- Consumes: `Where2GoCharDB.specEligibility` (Task 3's output shape).
  `Where2GoConstants.SEASON_LABEL` (existing).
- Produces: `Where2GoDirectDrop.IsEligibleForSpec(specId)` — same public
  signature as before (`function(itemId) -> boolean`), now backed by
  scanned data when available. No change to any caller
  (`Where2GoVoidcoreDrop.GetRankedResults`, `Where2GoDirectDrop.GetRankedResults`,
  `Where2Go/UI/BrowserPanel.lua`'s `GetItemEligible`) — they all keep
  calling it exactly as today.

This file has no existing test file (its own header notes it is
WoW-API-dependent and verified live) — this task follows that same
convention; no new test is added.

- [ ] **Step 1: Modify `IsEligibleForSpec`**

In `Where2Go/Core/DirectDrop.lua`, replace the existing function (lines
68-100):

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
        if cache and cache.seasonVersion == Where2GoConstants.SEASON_LABEL and cache.bySpec[specId] then
            return cache.bySpec[specId][itemId] == true
        end

        -- Gate on basic class/weapon-type equippability first:
        -- GetItemSpecInfo returning empty is ambiguous between "no
        -- restriction" (universal items like necklaces) and "not
        -- applicable, this class can't equip this item type at all"
        -- (e.g. a bow for a non-Hunter) -- IsEquippableItem disambiguates
        -- the second case directly from the live client, no static data
        -- needed.
        if C_Item.IsEquippableItem(itemId) == false then
            return false
        end
        local specTable = C_Item.GetItemSpecInfo(itemId)
        -- C_Item.GetItemSpecInfo returning nil is ambiguous between "no
        -- spec restriction" and "not yet cached by the client" -- on a
        -- cold item cache (e.g. right after login), this can inflate
        -- eligibleCount and skew the ranking ratio until the cache warms
        -- up naturally through normal play. Accepted as a known Phase 3
        -- limitation; a proper fix would need
        -- C_Item.RequestLoadItemDataByID + waiting for the item to
        -- actually cache before ranking, which is real async-design work
        -- deferred to a later phase.
        if not specTable or #specTable == 0 then
            return true
        end
        for _, id in ipairs(specTable) do
            if id == specId then
                return true
            end
        end
        return false
    end
end
```

- [ ] **Step 2: Run the full test suite to confirm nothing broke**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `12 spec file(s), 0 failure(s)` — no existing test exercises
`DirectDrop.lua`, so this is a regression check on everything else.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/Core/DirectDrop.lua
git commit -m "fix: IsEligibleForSpec consults scanned spec-eligibility data first"
```

- [ ] **Step 4: Live Testing Checkpoint**

With a completed scan from Task 3's checkpoint still in
`Where2GoCharDB.specEligibility`:
1. Open the main panel (`/where2go`) and confirm the ranked cards still
   render (no errors in `/console scriptErrors 1`).
2. Find a wrong-weapon/armor-type item you previously confirmed showed
   as incorrectly eligible (the bow-for-Shaman case from Phase 6's
   checkpoint, or an equivalent for your class) and confirm it no longer
   appears as eligible / no longer inflates `eligibleCount` on its card.
3. Confirm a universal item (e.g. a neck/ring item) still counts as
   eligible (this must not regress the Phase 6 fix).
4. Switch to the Voidcore tab and spot-check the same two cases there
   (it shares this function via `Where2GoVoidcoreDrop.GetRankedResults`).

---

## Task 5: Item browser spec-selector dropdown

**Files:**
- Modify: `Where2Go/UI/BrowserPanel.lua:4` (`filters` table)
- Modify: `Where2Go/UI/BrowserPanel.lua:30-36` (`GetItemEligible`)
- Modify: `Where2Go/UI/BrowserPanel.lua:163-380` (`CreateBrowserPanel`)

**Interfaces:**
- Consumes: `Where2GoDirectDrop.GetCurrentSpecIdAndName()`,
  `Where2GoDirectDrop.IsEligibleForSpec(specId)` (existing, unchanged
  signatures). `GetSpecializationInfo`/`GetNumSpecializations` (WoW API).
- Produces: `filters.specId` — the browser's currently-selected spec,
  defaulting to the player's active spec. No change to
  `Where2GoItemBrowser.FilterItems`/`SortItems`'s signatures (Task 5
  only changes what `context.isEligible` closes over).

- [ ] **Step 1: Add `specId` to the filters table**

In `Where2Go/UI/BrowserPanel.lua`, modify line 4:

```lua
local filters = { dungeonName = nil, bossName = nil, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil, specId = nil }
```

- [ ] **Step 2: Make `GetItemEligible` use the selected spec**

Replace the existing `GetItemEligible` (lines 30-36):

```lua
local function GetItemEligible(itemId)
    if not filters.specId then
        return true
    end
    return Where2GoDirectDrop.IsEligibleForSpec(filters.specId)(itemId)
end
```

- [ ] **Step 3: Add the dropdown UI and default selection**

In `Where2Go/UI/BrowserPanel.lua`'s `CreateBrowserPanel()`, add the
dropdown right after the Drop/Voidcore mode buttons block (after the
`voidcoreButton:SetScript("OnClick", ...)` line, before the "Dungeon/raid
row" comment):

```lua
    -- Spec selector dropdown, defaulting to the player's current active
    -- spec. Browser-only -- DirectDrop's and VoidcoreDrop's own ranked
    -- panels keep using only the character's actual current spec.
    local function GetAvailableSpecs()
        local specs = {}
        for i = 1, GetNumSpecializations() do
            local specId, specName = GetSpecializationInfo(i)
            if specId then
                table.insert(specs, { specId = specId, specName = specName })
            end
        end
        return specs
    end

    local specDropdown = CreateFrame("Frame", "Where2GoBrowserSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("LEFT", voidcoreButton, "RIGHT", 20, -2)
    UIDropDownMenu_SetWidth(specDropdown, 130)

    local function SelectSpec(specId, specName)
        filters.specId = specId
        UIDropDownMenu_SetText(specDropdown, specName)
        RebuildFilteredResults()
    end

    UIDropDownMenu_Initialize(specDropdown, function(_self, level)
        for _, spec in ipairs(GetAvailableSpecs()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spec.specName
            info.func = function() SelectSpec(spec.specId, spec.specName) end
            info.checked = (filters.specId == spec.specId)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local defaultSpecId, defaultSpecName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    filters.specId = defaultSpecId
    if defaultSpecId then
        UIDropDownMenu_SetText(specDropdown, defaultSpecName)
    end
```

- [ ] **Step 4: Run the full test suite to confirm nothing broke**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `12 spec file(s), 0 failure(s)` — `BrowserPanel.lua` has no
existing unit tests (WoW-UI-dependent), so this is a regression check
that `itembrowser_spec.lua` (the pure `ItemBrowser.lua` module it calls
into) is still unaffected.

- [ ] **Step 5: Commit**

```bash
git add Where2Go/UI/BrowserPanel.lua
git commit -m "feat: add spec-selector dropdown to the item browser"
```

- [ ] **Step 6: Live Testing Checkpoint**

1. Open the browser (`/where2go browse`). Confirm the dropdown shows
   your current active spec's name by default and doesn't overlap the
   Drop/Voidcore buttons or the dungeon/raid row below it — adjust the
   `SetPoint` offsets in Step 3 if the layout looks wrong (this template
   has nonstandard internal padding; treat the `20, -2` offsets as a
   starting point, not exact).
2. Click the dropdown and confirm it lists every spec of your current
   class.
3. Select a different spec, then check "Current spec eligible only" —
   confirm the filtered results change to match that spec's eligibility
   rather than your character's actual active spec.
4. Switch back to your active spec in the dropdown and confirm results
   match what DirectDrop's own panel considers eligible for you right
   now.

---

## Task 6: Automatic scan trigger and progress indicator

**Files:**
- Modify: `Where2Go/UI/Panel.lua:1-9` (module-level locals)
- Modify: `Where2Go/UI/Panel.lua:138-196` (`CreatePanel`, `Where2Go_TogglePanel`)
- Modify: `Where2Go/UI/BrowserPanel.lua:1-6` (module-level locals)
- Modify: `Where2Go/UI/BrowserPanel.lua:163-166` (`CreateBrowserPanel` start)
- Modify: `Where2Go/UI/BrowserPanel.lua:398-420` (`Where2GoBrowserPanel.Toggle`)

**Interfaces:**
- Consumes: `Where2GoSpecEligibilityScan.EnsureScanned()`,
  `Where2GoSpecEligibilityScan.SetProgressCallback(fn)` (Task 3).

- [ ] **Step 1: Add a status line and trigger to `Panel.lua`**

In `Where2Go/UI/Panel.lua`, add a module-level local near the top (after
line 5's `local currentView = "DROP"`):

```lua
local scanStatusText
```

In `CreatePanel()`, add the status FontString right after the `title`
block (after `title:SetText(Where2GoConstants.ADDON_NAME)`):

```lua
    scanStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scanStatusText:SetPoint("BOTTOMLEFT", 6, 6)
    scanStatusText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    scanStatusText:SetJustifyH("LEFT")
    scanStatusText:SetText("")
```

Add this function above `Where2Go_TogglePanel` (after `CreatePanel`'s
closing `end`):

```lua
local function HandleScanProgress(specName, current, total, finishedReason)
    if finishedReason then
        scanStatusText:SetText("")
        RefreshContent()
        return
    end
    scanStatusText:SetText(string.format("Where2Go: scanning spec eligibility... %d/%d (%s)", current or 0, total or 0, specName or ""))
end
```

Modify `Where2Go_TogglePanel` to register the callback and trigger the
scan when the panel is shown:

```lua
function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        Where2GoSpecEligibilityScan.SetProgressCallback(HandleScanProgress)
        Where2GoSpecEligibilityScan.EnsureScanned()
        RefreshContent()
        panelFrame:Show()
    end
end
```

- [ ] **Step 2: Add a status line and trigger to `BrowserPanel.lua`**

In `Where2Go/UI/BrowserPanel.lua`, add a module-level local near the top
(after line 6's `local stagedSelection = {}`):

```lua
local scanStatusText
```

In `CreateBrowserPanel()`, add the status FontString right after the
`title` block (after `title:SetText("Where2Go - Item Browser")`):

```lua
    scanStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scanStatusText:SetPoint("BOTTOMLEFT", 6, 6)
    scanStatusText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    scanStatusText:SetJustifyH("LEFT")
    scanStatusText:SetText("")
```

Add this function above `Where2GoBrowserPanel.Toggle` (after
`StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"]`'s closing brace):

```lua
local function HandleScanProgress(specName, current, total, finishedReason)
    if finishedReason then
        scanStatusText:SetText("")
        RebuildFilteredResults()
        return
    end
    scanStatusText:SetText(string.format("Where2Go: scanning spec eligibility... %d/%d (%s)", current or 0, total or 0, specName or ""))
end
```

Modify `Where2GoBrowserPanel.Toggle` to register the callback and
trigger the scan when the browser is shown:

```lua
function Where2GoBrowserPanel.Toggle()
    if not browserFrame then
        browserFrame = CreateBrowserPanel()
        itemPool = Where2GoItemBrowser.BuildItemPool()
        for _, entry in ipairs(itemPool) do
            C_Item.RequestLoadItemDataByID(entry.itemId)
        end
        local itemLoadWatcher = CreateFrame("Frame")
        itemLoadWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        itemLoadWatcher:SetScript("OnEvent", function()
            if browserFrame and browserFrame:IsShown() then
                RebuildFilteredResults()
            end
        end)
        RebuildFilteredResults()
    end
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        Where2GoSpecEligibilityScan.SetProgressCallback(HandleScanProgress)
        Where2GoSpecEligibilityScan.EnsureScanned()
        RebuildFilteredResults()
        browserFrame:Show()
    end
end
```

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `12 spec file(s), 0 failure(s)`

- [ ] **Step 4: Commit**

```bash
git add Where2Go/UI/Panel.lua Where2Go/UI/BrowserPanel.lua
git commit -m "feat: auto-trigger spec-eligibility scan when a panel opens"
```

- [ ] **Step 5: Live Testing Checkpoint**

Start from a clean state so the scan hasn't run yet this session: `/run Where2GoCharDB.specEligibility = nil`, then `/reload`.
1. Open the main panel (`/where2go`). Confirm the status line at the
   bottom shows "scanning spec eligibility... n/total (specName)" and
   updates as it progresses, and the ranked cards are still usable while
   it runs.
2. Wait for the scan to finish — confirm the status line clears and the
   cards silently refresh.
3. Close and reopen the panel (or open the browser via the "Browse"
   button) — confirm no new scan starts (`Where2GoCharDB.specEligibility.seasonVersion`
   already matches, so `EnsureScanned()` is a no-op).
4. `/run Where2GoCharDB.specEligibility.seasonVersion = "stale-test"`,
   then reopen the panel — confirm a fresh scan starts automatically
   (staleness detection works).
5. Enter combat, then open the panel while in combat — confirm no scan
   starts (`InCombatLockdown()` guard) and the panel still renders using
   the fallback heuristic without error.
6. Open the item browser directly (`/where2go browse`) from a state with
   no scan yet (`/run Where2GoCharDB.specEligibility = nil`, `/reload`,
   then go straight to `/where2go browse`) and confirm the same
   progress/auto-trigger behavior works from that entry point too.

---

## Plan Self-Review Notes

- **Spec coverage:** Data sourcing (Task 1), scan engine + combat-abort
  (Task 3), `IsEligibleForSpec` fallback priority (Task 4), browser-only
  spec selector (Task 5), automatic trigger + progress indicator with no
  manual button (Task 6), pure-function unit testing split from
  WoW-API-dependent code (Tasks 2/3) — every section of the design doc
  has a corresponding task.
- **Non-goals confirmed respected:** no changes to `VoidcoreHistory.lua`,
  no global/multi-class data file, no spec-selector added to
  `Panel.lua`'s own ranked view.
- **Type/name consistency checked:** `Where2GoSpecEligibilityScan.EnsureScanned`,
  `.Start`, `.IsRunning`, `.SetProgressCallback`, `.ParseTooltipLines`
  and the `Where2GoCharDB.specEligibility = { seasonVersion, scannedAt,
  bySpec }` shape are used identically across Tasks 3, 4, and 6.
