# Phase 4: Voidcore Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track items obtained via Voidcore bonus rolls per character, and
add an independent Voidcore ranking view (tabbed alongside Direct-drop in
the existing panel) that excludes already-obtained items from the pool —
matching `docs/DEVELOPMENT_PLAN.md` Phase 4's acceptance check (adding a
known Voidcore reward changes only the Voidcore result for its relevant
pool).

**Architecture:** One new file has a pure, unit-tested helper alongside
WoW-API-guarded event glue (`Core/VoidcoreHistory.lua`). One new file is
pure WoW-API glue reusing Phase 3's already-tested `Ranking.lua` plus three
newly-public `DirectDrop.lua` helpers (`Core/VoidcoreDrop.lua`). `Panel.lua`
gains two tab buttons and a `currentView` dispatch; card
rendering/collapse/`Layout()` are untouched.

**Tech Stack:** Plain FrameXML/Lua, no Ace3, no vendored libraries
(unchanged). Lua 5.1 via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"`.

**Spec:** `docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md`

## Global Constraints

- The Voidcore pool is the same real content Phase 3 built (all 8
  dungeons unioned per-dungeon, all raid encounters per-boss) — Voidcore
  does **not** get a separate/smaller content set. Reuse
  `Where2GoDirectDrop.BuildContentList()`; do not duplicate it.
- Voidcore's eligibility predicate is "spec-eligible (same rule as
  Direct-drop) AND not already obtained via Voidcore" — an obtained item
  is removed from the pool entirely (it must not count toward
  `eligibleCount`), not merely deprioritized.
- Voidcore ranks against `Where2GoCharDB.preferredItems.VOIDCORE`, never
  `.DROP`. Direct-drop's own ranking, predicate, and preferred list are
  completely unchanged by this phase — verify this explicitly in each
  task's self-review.
- `Where2Go/Core/VoidcoreHistory.lua` contains one pure, testable function
  (`ParseItemIdFromLink`) alongside WoW-API event-registration code in the
  same file. The WoW-API code must be guarded with `if CreateFrame then ... end`
  so the file can still be `dofile`'d by the standalone test harness
  without crashing on the undefined `CreateFrame` global — this is a
  deliberate, documented pattern, not a bug to "simplify away."
- `tests/toc_spec.lua` (built in Phase 1) checks both directions — every
  task that adds a file must add its TOC line in the same task.
- Tests run via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua` from the repository root.
- Source code, comments, and commit messages are English.

---

## File Structure

```
Where2Go/
├── Where2Go.toc                  MODIFY across Tasks 2, 4
├── Core/
│   ├── Constants.lua              MODIFY (Task 1): BuildDefaultCharDB
│   │                              adds voidcoreObtainedItems = {}
│   ├── Init.lua                   MODIFY (Task 1): ADDON_LOADED schema-
│   │                              upgrade guard for the new field
│   ├── VoidcoreHistory.lua         CREATE (Task 2): pure ParseItemIdFromLink
│   │                              + guarded BONUS_ROLL_RESULT listener
│   ├── DirectDrop.lua             MODIFY (Task 3): promote BuildContentList/
│   │                              GetCurrentSpecIdAndName/IsEligibleForSpec
│   │                              from local to public
│   ├── VoidcoreDrop.lua            CREATE (Task 4): Voidcore-specific
│   │                              ranked results (WoW-API, no unit test)
│   └── (Tracks.lua, Sources.lua, RaidRanks.lua, Ranking.lua, Compare.lua,
│        Equipment.lua unchanged)
└── UI/
    └── Panel.lua                  MODIFY (Task 5): Drop/Voidcore tabs

tests/
├── run_tests.lua                  MODIFY (Task 2): append voidcorehistory_spec
├── constants_spec.lua              MODIFY (Task 1)
└── voidcorehistory_spec.lua         CREATE (Task 2)
```

**Final TOC order after Task 4**: `Core\Constants.lua`, `Core\Tracks.lua`,
`Core\Sources.lua`, `Core\RaidRanks.lua`, `Core\Ranking.lua`,
`Core\DirectDrop.lua`, `Core\VoidcoreHistory.lua`, `Core\VoidcoreDrop.lua`,
`Core\Compare.lua`, `Core\Equipment.lua`, `Core\Init.lua`, `UI\Panel.lua`
(12 files).

---

### Task 1: Voidcore storage schema

**Files:**
- Modify: `Where2Go/Core/Constants.lua`
- Modify: `Where2Go/Core/Init.lua`
- Modify: `tests/constants_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `Where2GoConstants.BuildDefaultCharDB()` now also returns
  `voidcoreObtainedItems = {}`. `Where2GoCharDB.voidcoreObtainedItems` is
  guaranteed to exist (via `Init.lua`'s upgrade guard) by the time any
  other code reads it. `Core/VoidcoreHistory.lua` (Task 2) writes to it;
  `Core/VoidcoreDrop.lua` (Task 4) reads it.

- [ ] **Step 1: Write the failing test**

Replace the full contents of `tests/constants_spec.lua` with:
```lua
dofile("Where2Go/Core/Constants.lua")

assert(Where2GoConstants.ADDON_NAME == "Where2Go", "ADDON_NAME should be Where2Go")
assert(Where2GoConstants.INTERFACE_VERSION == 120100, "INTERFACE_VERSION should match the TOC")
assert(type(Where2GoConstants.SEASON_LABEL) == "string" and #Where2GoConstants.SEASON_LABEL > 0,
    "SEASON_LABEL should be a non-empty string")

local expectedSlots = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST",
    "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND",
}
assert(type(Where2GoConstants.SLOT_TO_INVSLOT) == "table", "SLOT_TO_INVSLOT should be a table")
for _, slot in ipairs(expectedSlots) do
    assert(type(Where2GoConstants.SLOT_TO_INVSLOT[slot]) == "string",
        "SLOT_TO_INVSLOT should map " .. slot .. " to an inventory slot name")
end

assert(type(Where2GoConstants.FINGER_SLOTS) == "table" and #Where2GoConstants.FINGER_SLOTS == 2,
    "FINGER_SLOTS should have exactly 2 entries")
assert(type(Where2GoConstants.TRINKET_SLOTS) == "table" and #Where2GoConstants.TRINKET_SLOTS == 2,
    "TRINKET_SLOTS should have exactly 2 entries")

assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_HEAD == "HEAD", "EQUIPLOC_TO_SLOT should map INVTYPE_HEAD to HEAD")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_FINGER == "FINGER", "EQUIPLOC_TO_SLOT should map INVTYPE_FINGER to FINGER")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_TRINKET == "TRINKET", "EQUIPLOC_TO_SLOT should map INVTYPE_TRINKET to TRINKET")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_WEAPONMAINHAND == "MAINHAND", "EQUIPLOC_TO_SLOT should map INVTYPE_WEAPONMAINHAND to MAINHAND")

local accountDB = Where2GoConstants.BuildDefaultAccountDB()
assert(type(accountDB) == "table", "BuildDefaultAccountDB should return a table")
assert(accountDB.panelShown == false, "panelShown should default to false")

local charDB = Where2GoConstants.BuildDefaultCharDB()
assert(type(charDB) == "table", "BuildDefaultCharDB should return a table")
assert(type(charDB.preferredItems) == "table", "preferredItems should default to a table")
assert(type(charDB.preferredItems.DROP) == "table", "preferredItems.DROP should default to a table")
assert(type(charDB.preferredItems.VOIDCORE) == "table", "preferredItems.VOIDCORE should default to a table")
assert(next(charDB.preferredItems.DROP) == nil, "preferredItems.DROP should default to empty")
assert(next(charDB.preferredItems.VOIDCORE) == nil, "preferredItems.VOIDCORE should default to empty")
assert(type(charDB.voidcoreObtainedItems) == "table", "voidcoreObtainedItems should default to a table")
assert(next(charDB.voidcoreObtainedItems) == nil, "voidcoreObtainedItems should default to empty")

-- Regression guard: each call must return independent tables at every
-- level. If the builder ever returns a shared table by reference, one
-- character's saved data would leak into every other character's.
local secondCharDB = Where2GoConstants.BuildDefaultCharDB()
charDB.preferredItems.DROP[12345] = true
charDB.preferredItems.VOIDCORE[54321] = true
charDB.voidcoreObtainedItems[99999] = true
assert(next(secondCharDB.preferredItems.DROP) == nil,
    "BuildDefaultCharDB must return an independent DROP table on each call")
assert(next(secondCharDB.preferredItems.VOIDCORE) == nil,
    "BuildDefaultCharDB must return an independent VOIDCORE table on each call")
assert(next(secondCharDB.voidcoreObtainedItems) == nil,
    "BuildDefaultCharDB must return an independent voidcoreObtainedItems table on each call")

print("constants_spec: OK")
```

- [ ] **Step 2: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/constants_spec.lua: ...` (`voidcoreObtainedItems` is
`nil` on the current `BuildDefaultCharDB()`, so `type(nil) == "table"` fails).

- [ ] **Step 3: Update Constants.lua**

In `Where2Go/Core/Constants.lua`, change:
```lua
function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {
            DROP = {},
            VOIDCORE = {},
        },
    }
end
```
to:
```lua
function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {
            DROP = {},
            VOIDCORE = {},
        },
        voidcoreObtainedItems = {},
    }
end
```

- [ ] **Step 4: Update Init.lua's schema-upgrade guard**

In `Where2Go/Core/Init.lua`, change:
```lua
    Where2GoCharDB.preferredItems = Where2GoCharDB.preferredItems or {}
    Where2GoCharDB.preferredItems.DROP = Where2GoCharDB.preferredItems.DROP or {}
    Where2GoCharDB.preferredItems.VOIDCORE = Where2GoCharDB.preferredItems.VOIDCORE or {}
```
to:
```lua
    Where2GoCharDB.preferredItems = Where2GoCharDB.preferredItems or {}
    Where2GoCharDB.preferredItems.DROP = Where2GoCharDB.preferredItems.DROP or {}
    Where2GoCharDB.preferredItems.VOIDCORE = Where2GoCharDB.preferredItems.VOIDCORE or {}
    Where2GoCharDB.voidcoreObtainedItems = Where2GoCharDB.voidcoreObtainedItems or {}
```
(Same reasoning as the Phase 2 fix this mirrors: a character who already
ran an earlier phase has a `Where2GoCharDB` on disk without this new
field, and the `or Where2GoConstants.BuildDefaultCharDB()` guard above it
only fires when the whole table is `nil`.)

- [ ] **Step 5: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 7 spec files — this task only modifies
existing files), exit code `0`.

- [ ] **Step 6: Commit**

```bash
git add Where2Go/Core/Constants.lua Where2Go/Core/Init.lua tests/constants_spec.lua
git commit -m "feat: add voidcore-obtained-items storage schema"
```

---

### Task 2: Core/VoidcoreHistory.lua

**Files:**
- Create: `Where2Go/Core/VoidcoreHistory.lua`
- Test: `tests/voidcorehistory_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/voidcorehistory_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\VoidcoreHistory.lua` after
  `Core\DirectDrop.lua`, before `Core\Compare.lua`)

**Interfaces:**
- Consumes: `Where2GoCharDB.voidcoreObtainedItems` (Task 1, at event-fire
  time only — not at file-load time).
- Produces: `Where2GoVoidcoreHistory.ParseItemIdFromLink(itemLink)` → item
  ID number or `nil` (pure, tested). A guarded `BONUS_ROLL_RESULT` event
  handler that writes to `Where2GoCharDB.voidcoreObtainedItems[itemId] = true`
  (WoW-API-dependent, untested).

- [ ] **Step 1: Write the failing test**

`tests/voidcorehistory_spec.lua`:
```lua
dofile("Where2Go/Core/VoidcoreHistory.lua")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("|cffa335ee|Hitem:12345::::::::80:::::|h[Sample Item]|h|r") == 12345,
    "should parse the item ID out of a real-shaped item link")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("|cffffffff|Hitem:271092:0:0:0:0:0:0:0:80:0:0:0:0:0|h[Janthrazet]|h|r") == 271092,
    "should parse a different item link's ID correctly")

assert(Where2GoVoidcoreHistory.ParseItemIdFromLink(nil) == nil, "nil input should return nil")
assert(Where2GoVoidcoreHistory.ParseItemIdFromLink(12345) == nil, "non-string input should return nil")
assert(Where2GoVoidcoreHistory.ParseItemIdFromLink("not a link") == nil, "unparseable string should return nil")

print("voidcorehistory_spec: OK")
```

- [ ] **Step 2: Update the harness**

Append `"tests/voidcorehistory_spec.lua"` to the `specs` list in
`tests/run_tests.lua`.

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/voidcorehistory_spec.lua: ...` (file doesn't exist yet).

- [ ] **Step 4: Implement VoidcoreHistory.lua**

`Where2Go/Core/VoidcoreHistory.lua`:
```lua
-- Tracks items obtained via a Voidcore bonus roll for this character.
-- Ported in spirit from codex/pre-restart-backup's Core/VoidcoreHistory.lua
-- -- listens for BONUS_ROLL_RESULT and marks the rewarded item ID obtained
-- in Where2GoCharDB.voidcoreObtainedItems. This only tracks items obtained
-- from the moment the addon is installed onward -- see
-- docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md for the
-- deferred tooltip-scanning alternative that wouldn't have this limit.

Where2GoVoidcoreHistory = {}

-- Pure string parse, no WoW API -- extracts the numeric item ID from a
-- real item link string. Returns nil for a non-string or unparseable
-- input. Testable standalone (see tests/voidcorehistory_spec.lua).
function Where2GoVoidcoreHistory.ParseItemIdFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    return tonumber(itemLink:match("item:(%d+)"))
end

-- The event registration below is WoW-API-dependent (CreateFrame doesn't
-- exist outside the game client). Guarded so this file can still be
-- dofile'd by the standalone test harness to exercise the pure function
-- above without crashing on a missing global -- this is deliberate, not
-- a workaround to "clean up."
if CreateFrame then
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
    eventFrame:SetScript("OnEvent", function(self, event, typeIdentifier, itemLink)
        if event ~= "BONUS_ROLL_RESULT" or typeIdentifier ~= "item" then
            return
        end
        local itemId = Where2GoVoidcoreHistory.ParseItemIdFromLink(itemLink)
        if itemId then
            Where2GoCharDB.voidcoreObtainedItems[itemId] = true
        end
    end)
end
```

- [ ] **Step 5: Update the manifest**

Insert `Core\VoidcoreHistory.lua` immediately after `Core\DirectDrop.lua`
and before `Core\Compare.lua` in `Where2Go/Where2Go.toc`.

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (8 spec files; `toc_spec` now verifies 11
files), exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/VoidcoreHistory.lua tests/voidcorehistory_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: track items obtained via Voidcore bonus rolls"
```

---

### Task 3: Promote DirectDrop.lua's internal helpers to public

**Files:**
- Modify: `Where2Go/Core/DirectDrop.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces (newly public, was `local`): `Where2GoDirectDrop.BuildContentList()`,
  `Where2GoDirectDrop.GetCurrentSpecIdAndName()`,
  `Where2GoDirectDrop.IsEligibleForSpec(specId)`. `Core/VoidcoreDrop.lua`
  (Task 4) calls all three. `Where2GoDirectDrop.GetRankedResults()`'s own
  external behavior is unchanged — this task only changes how its
  internals are organized.

No test changes — this file has no unit test (WoW-API-dependent), and
promoting `local function` to `Where2GoDirectDrop.function` doesn't change
that. Verified by the rest of the suite staying green.

- [ ] **Step 1: Replace DirectDrop.lua's contents**

Replace the full contents of `Where2Go/Core/DirectDrop.lua` with:
```lua
-- Assembles the real ranked direct-drop content list: current-spec
-- detection, live C_Item.GetItemSpecInfo eligibility, item name lookup,
-- and calls Where2GoRanking.RankContent. WoW-API-dependent; not
-- unit-tested (Where2GoRanking carries the pure ranking math this feeds).
--
-- BuildContentList/GetCurrentSpecIdAndName/IsEligibleForSpec are public
-- (not local) so Core/VoidcoreDrop.lua can reuse them instead of
-- duplicating the same content-assembly and spec-detection logic -- see
-- docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md.

Where2GoDirectDrop = {}

local function FlattenItemIds(encounters)
    local ids = {}
    for _, encounter in ipairs(encounters) do
        for _, itemId in ipairs(encounter.itemIds) do
            table.insert(ids, itemId)
        end
    end
    return ids
end

function Where2GoDirectDrop.BuildContentList()
    local content = {}

    local mplusIlvl, mplusTrackLabel, mplusRank = Where2GoRaidRanks.GetMythicPlusIlvl()
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(content, {
            id = "dungeon:" .. dungeon.instanceId,
            name = dungeon.name,
            kind = "dungeon",
            raidName = nil,
            itemIds = FlattenItemIds(dungeon.encounters),
            ilvl = mplusIlvl,
            trackLabel = mplusTrackLabel,
            trackRank = mplusRank,
        })
    end

    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            local ilvl, trackLabel, rank = Where2GoRaidRanks.GetRaidIlvl(encounter.bossId)
            table.insert(content, {
                id = "boss:" .. encounter.bossId,
                name = encounter.name,
                kind = "raid",
                raidName = raid.name,
                itemIds = encounter.itemIds,
                ilvl = ilvl,
                trackLabel = trackLabel,
                trackRank = rank,
            })
        end
    end

    return content
end

function Where2GoDirectDrop.GetCurrentSpecIdAndName()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil, nil
    end
    local specId, specName = GetSpecializationInfo(specIndex)
    return specId, specName
end

function Where2GoDirectDrop.IsEligibleForSpec(specId)
    return function(itemId)
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
        if not specTable then
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

local function IsPreferred(itemId)
    return Where2GoCharDB.preferredItems.DROP[itemId] == true
end

-- Returns (results, specName) on success, or (nil, "unsupported_spec") if
-- the player has no specialization chosen. `results` is
-- Where2GoRanking.RankContent's output, ranked best-first.
function Where2GoDirectDrop.GetRankedResults()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = Where2GoDirectDrop.BuildContentList()
    local results = Where2GoRanking.RankContent(content, Where2GoDirectDrop.IsEligibleForSpec(specId), IsPreferred)
    return results, specName
end

-- Resolves display names for a list of item IDs, falling back to a
-- placeholder for anything not yet cached by the client.
function Where2GoDirectDrop.GetItemNames(itemIds)
    local names = {}
    for _, itemId in ipairs(itemIds) do
        local name = C_Item.GetItemInfo(itemId)
        names[itemId] = name or ("Item #" .. itemId)
    end
    return names
end
```

- [ ] **Step 2: Run the automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 8 spec files), exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/Core/DirectDrop.lua
git commit -m "refactor: expose DirectDrop's content/spec helpers for reuse"
```

---

### Task 4: Core/VoidcoreDrop.lua

**Files:**
- Create: `Where2Go/Core/VoidcoreDrop.lua`
- Modify: `Where2Go/Where2Go.toc` (insert `Core\VoidcoreDrop.lua` after
  `Core\VoidcoreHistory.lua`, before `Core\Compare.lua`)

**Interfaces:**
- Consumes: `Where2GoDirectDrop.BuildContentList`/`GetCurrentSpecIdAndName`/
  `IsEligibleForSpec` (Task 3), `Where2GoRanking.RankContent` (Phase 3),
  `Where2GoCharDB.voidcoreObtainedItems` (Task 1/2),
  `Where2GoCharDB.preferredItems.VOIDCORE` (Phase 2).
- Produces: `Where2GoVoidcoreDrop.GetRankedResults()` → `(results, specName)`
  or `(nil, "unsupported_spec")` — same contract shape as
  `Where2GoDirectDrop.GetRankedResults()`. `UI/Panel.lua` (Task 5) calls
  this when the Voidcore tab is active.

No unit test — WoW-API-dependent, and its only real logic (the eligibility
composition) is a one-line `and`/`not` combination of two already-tested-
elsewhere primitives (`Ranking.lua`'s contract, `DirectDrop.lua`'s spec
check). Correctness signal is the rest of the suite staying green.

- [ ] **Step 1: Implement VoidcoreDrop.lua**

`Where2Go/Core/VoidcoreDrop.lua`:
```lua
-- Voidcore-specific ranked results: reuses Where2GoDirectDrop's content
-- assembly and spec detection, but filters out items already obtained via
-- Voidcore (Where2GoCharDB.voidcoreObtainedItems) and ranks against the
-- separate preferredItems.VOIDCORE list instead of .DROP. WoW-API-
-- dependent; not unit-tested (Where2GoRanking carries the pure ranking
-- math this feeds).

Where2GoVoidcoreDrop = {}

local function IsObtained(itemId)
    return Where2GoCharDB.voidcoreObtainedItems[itemId] == true
end

local function IsPreferredVoidcore(itemId)
    return Where2GoCharDB.preferredItems.VOIDCORE[itemId] == true
end

-- Returns (results, specName) on success, or (nil, "unsupported_spec") --
-- same contract as Where2GoDirectDrop.GetRankedResults().
function Where2GoVoidcoreDrop.GetRankedResults()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = Where2GoDirectDrop.BuildContentList()
    local specEligible = Where2GoDirectDrop.IsEligibleForSpec(specId)
    local function isEligible(itemId)
        return specEligible(itemId) and not IsObtained(itemId)
    end
    local results = Where2GoRanking.RankContent(content, isEligible, IsPreferredVoidcore)
    return results, specName
end
```

- [ ] **Step 2: Update the manifest**

Insert `Core\VoidcoreDrop.lua` immediately after `Core\VoidcoreHistory.lua`
and before `Core\Compare.lua`. The file list section should now read:
```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\RaidRanks.lua
Core\Ranking.lua
Core\DirectDrop.lua
Core\VoidcoreHistory.lua
Core\VoidcoreDrop.lua
Core\Compare.lua
Core\Equipment.lua
Core\Init.lua
UI\Panel.lua
```

- [ ] **Step 3: Run the automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 8 spec files; `toc_spec` now verifies
12 files), exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/VoidcoreDrop.lua Where2Go/Where2Go.toc
git commit -m "feat: add independent Voidcore ranking view"
```

---

### Task 5: Add Drop/Voidcore tabs to Panel.lua

**Files:**
- Modify (full rewrite): `Where2Go/UI/Panel.lua`

**Interfaces:**
- Consumes: `Where2GoDirectDrop.GetRankedResults`/`GetItemNames` (unchanged),
  `Where2GoVoidcoreDrop.GetRankedResults` (Task 4).
- Produces: `Where2Go_TogglePanel()` — same contract as before.

Not unit-tested (WoW-API-dependent). Verified live in Task 6.

- [ ] **Step 1: Replace Panel.lua's contents**

Replace the full contents of `Where2Go/UI/Panel.lua` with:
```lua
local panelFrame
local contentFrame
local cardFrames = {}
local Layout
local currentView = "DROP"

local HEADER_HEIGHT = 62

local function BuildHeaderText(result, expanded)
    local mark = expanded and "[-]" or "[+]"
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    return string.format("%s %s%s   %d/%d  |cffffffff%d|r |cff9d9d9d(%s %d/6)|r",
        mark, prefix, result.name, result.targetCount, result.eligibleCount,
        result.ilvl, result.trackLabel, result.trackRank)
end

local function CreateCard(parent, result)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("LEFT", parent, "LEFT", 0, 0)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local header = CreateFrame("Button", nil, card)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    header:SetHeight(18)

    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", 0, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWidth(336)

    local itemRows = {}
    local itemNames = Where2GoDirectDrop.GetItemNames(result.targetItemIds)
    local rowY = -18
    for _, itemId in ipairs(result.targetItemIds) do
        local row = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetJustifyH("LEFT")
        row:SetWidth(324)
        row:SetText(itemNames[itemId])
        table.insert(itemRows, row)
        rowY = rowY - 14
    end

    local cardData = {
        frame = card,
        expanded = true,
        collapsedHeight = 18,
        expandedHeight = 18 + (#itemRows * 14),
    }
    headerText:SetText(BuildHeaderText(result, cardData.expanded))

    header:SetScript("OnClick", function()
        cardData.expanded = not cardData.expanded
        for _, row in ipairs(itemRows) do
            if cardData.expanded then
                row:Show()
            else
                row:Hide()
            end
        end
        headerText:SetText(BuildHeaderText(result, cardData.expanded))
        Layout()
    end)

    return cardData
end

Layout = function()
    local y = 0
    for _, cardData in ipairs(cardFrames) do
        cardData.frame:ClearAllPoints()
        cardData.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, y)
        cardData.frame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
        local height = cardData.expanded and cardData.expandedHeight or cardData.collapsedHeight
        cardData.frame:SetHeight(height)
        y = y - height - 6
    end
    local totalHeight = -y
    contentFrame:SetHeight(totalHeight)
    panelFrame:SetHeight(HEADER_HEIGHT + totalHeight + 12)
end

local function GetRankedResultsForCurrentView()
    if currentView == "VOIDCORE" then
        return Where2GoVoidcoreDrop.GetRankedResults()
    end
    return Where2GoDirectDrop.GetRankedResults()
end

local function RefreshContent()
    for _, cardData in ipairs(cardFrames) do
        cardData.frame:Hide()
        cardData.frame:SetParent(nil)
    end
    cardFrames = {}

    local results = GetRankedResultsForCurrentView()
    if not results then
        local msgFrame = CreateFrame("Frame", nil, contentFrame)
        msgFrame:SetPoint("TOPLEFT", 0, 0)
        local text = msgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetText("Where2Go: no specialization selected.")
        msgFrame:SetHeight(18)
        contentFrame:SetHeight(18)
        panelFrame:SetHeight(HEADER_HEIGHT + 18 + 12)
        return
    end

    for _, result in ipairs(results) do
        table.insert(cardFrames, CreateCard(contentFrame, result))
    end
    Layout()
end

local function CreateTab(parent, label, view, x)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(80, 20)
    tab:SetPoint("TOPLEFT", x, -34)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label)

    tab:SetScript("OnClick", function()
        currentView = view
        RefreshContent()
    end)

    return tab
end

local function CreatePanel()
    local frame = CreateFrame("Frame", "Where2GoPanel", UIParent, "BackdropTemplate")
    frame:SetSize(380, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(Where2GoConstants.ADDON_NAME)

    CreateTab(frame, "Drop", "DROP", 12)
    CreateTab(frame, "Voidcore", "VOIDCORE", 96)

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 12, -HEADER_HEIGHT)
    contentFrame:SetPoint("RIGHT", frame, "RIGHT", -12, 0)

    frame:Hide()
    return frame
end

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

Note: the `local Layout` forward declaration and the exact ordering
(`CreateCard` defined, then `Layout` assigned, then `RefreshContent`
defined) is preserved from Phase 3 — do not reorder these, the closure
inside `CreateCard`'s `OnClick` depends on `Layout` being an upvalue that
gets assigned later, same mechanism as before.

- [ ] **Step 2: Run the full automated suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 8 spec files, no test touches
`Panel.lua`), exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/UI/Panel.lua
git commit -m "feat: add Drop/Voidcore tabs to the recommendation panel"
```

---

### Task 6: Manual live-client verification

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — verify the Voidcore tab and history live**

This step cannot be run by an agent — it requires the WoW client. Whoever
executes this task should do the following themselves and report the
result back before Phase 4 is considered done:

1. `/reload` and confirm no Lua error appears.
2. Run `/where2go` (or `/w2g`). Confirm two tabs, "Drop" and "Voidcore,"
   appear near the top of the panel, with "Drop" showing the same ranked
   results as Phase 3 left it.
3. Click the "Voidcore" tab — confirm the panel shows a ranked list (the
   same 17 dungeon/boss entries, since the pool is identical to Drop's
   until history/preferences differ it).
4. Pick a real item ID and register it on the Voidcore list specifically:
   `/where2go pref add <itemID> voidcore`. Reopen (or refresh by clicking
   the Voidcore tab again) — confirm that item's boss/dungeon card now
   shows a non-zero target count on the Voidcore tab, while the Drop tab
   (unaffected, since it's a different preferred list) does not show it
   as a target unless you separately added it there too.
5. Simulate obtaining that item via Voidcore (a real bonus roll is the
   most faithful test if you have one available; otherwise, directly set
   `Where2GoCharDB.voidcoreObtainedItems[<itemID>] = true` via `/run` and
   reopen the panel) — confirm the item drops out of the Voidcore tab's
   target count and item list for that card, while the Drop tab's ranking
   for the same content is completely unaffected (this is the core
   acceptance check: "adding a known Voidcore reward changes only the
   Voidcore result for its relevant pool").
6. Click back and forth between the two tabs a few times — confirm no
   Lua error, no leftover cards from the other tab lingering underneath.

This satisfies `docs/DEVELOPMENT_PLAN.md` Phase 4's acceptance check.

---

## Done

Phase 4 is complete when all five code tasks' commits exist and the
Task 6 manual checkpoint has been confirmed in a live client. Phase 5
(data and release readiness) starts a new plan built on this foundation.
