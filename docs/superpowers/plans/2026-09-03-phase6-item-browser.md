# Phase 6, Sub-project B: Item Browser & Preferred-List Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A separate browser window where a player filters the full
dungeon/raid item pool (by dungeon/boss, slot, stat, spec-eligibility,
name search), sees which items are already preferred, checks several
candidates, and commits them to the active mode's (Drop/Voidcore)
preferred list in one action.

**Architecture:** `Where2GoItemBrowser` (pure) builds a flat, per-boss
item pool directly from `Where2GoSources` and filters/sorts it given a
filter-state table and a small context of WoW-API-dependent lookup
functions passed in by the caller. `BrowserPanel.lua` (WoW-API-dependent)
owns the actual frame: filter controls built from plain buttons/
checkboxes (no dropdown widget, no Ace3 — matching this project's
existing style), a small fixed pool of recycled row frames scrolled via
mouse wheel (no scroll-frame template dependency, to avoid betting on a
specific template's continued existence in this client version), and the
three action buttons.

**Tech Stack:** Lua 5.1, plain FrameXML (no Ace3/vendored libraries, per
the project's standing decision).

**Spec:** `docs/superpowers/specs/2026-09-03-phase6-item-browser-design.md`

## Global Constraints

- No Ace3/vendored UI libraries — plain `CreateFrame` widgets throughout,
  matching `UI/Panel.lua`'s existing style.
- Lua 5.1 has no `goto`/labels — filter logic must use early-return helper
  functions, not a `goto continue` pattern.
- **Deliberate refinement from the design spec**: the browser needs
  per-boss granularity even for Mythic+ dungeons (so a player can filter
  down to one boss's drops), but `Where2GoDirectDrop.BuildContentList()`
  intentionally flattens a whole dungeon's bosses into one content entry
  (correct for M+ ranking, wrong for per-boss browsing). `Where2GoItemBrowser.BuildItemPool()`
  therefore reads `Where2GoSources.DUNGEONS`/`.RAIDS` directly at the
  per-boss level, rather than reusing `BuildContentList()`. This does not
  duplicate ranking logic — it's a different, boss-level view of the same
  underlying source data.
- The item pool intentionally does **not** deduplicate items that drop
  from more than one boss (the two known duplicate-item-ID encounters
  noted in `Sources.lua`'s header, or any item genuinely available from
  multiple bosses) — for browsing, seeing "this item drops from boss X"
  once per boss it can drop from is useful information, unlike
  `Ranking.lua`'s counting logic which must dedupe for its ratio math.
- `Where2GoItemStats.STATS` (Sub-project A) is referenced directly as a
  global from `Where2GoItemBrowser.lua`'s stat-filter logic, not injected
  via the `context` parameter — it's pure static data, not a WoW API call,
  so referencing it directly keeps the module simple without hurting
  testability (a test can set up a fixture `Where2GoItemStats` table
  before calling the filter function, the same way other pure-file specs
  in this project stub their dependencies).
- Destructive action ("선호 목록 전체 삭제") must use `StaticPopupDialogs`/
  `StaticPopup_Show` for confirmation — WoW's standard, stable
  confirmation-dialog API, not a custom-built confirmation frame.
- Scrolling is implemented via `OnMouseWheel` + a clamped offset into the
  filtered/sorted results array, with a small fixed pool of recycled row
  frames (`VISIBLE_ROWS` of them) whose content/visibility is updated on
  every scroll or filter change — never one frame created per underlying
  item. This avoids depending on `FauxScrollFrameTemplate` or the newer
  `WowScrollBoxList` system, since this plan cannot verify with certainty
  which is present in this specific client version; mouse-wheel-driven
  manual offset math only needs `CreateFrame`, `EnableMouseWheel`, and
  `OnMouseWheel`, which have been stable across every WoW client version.

---

## File Structure

```
Where2Go/Core/ItemBrowser.lua   NEW — pure pool/filter/sort logic
tests/itembrowser_spec.lua       NEW — unit tests against fixture data
Where2Go/UI/BrowserPanel.lua     NEW — the browser window
Where2Go/UI/Panel.lua            MODIFY — button to open the browser
Where2Go/Core/Init.lua           MODIFY — /where2go browse subcommand
Where2Go.toc                     MODIFY — register the two new files
tests/run_tests.lua               MODIFY — register itembrowser_spec
```

---

### Task 1: `Where2Go/Core/ItemBrowser.lua` (pure pool/filter/sort logic)

**Files:**
- Create: `Where2Go/Core/ItemBrowser.lua`
- Create: `tests/itembrowser_spec.lua`
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Consumes: `Where2GoSources.DUNGEONS`/`.RAIDS` (Phase 3); `Where2GoItemStats.STATS`
  (Sub-project A, referenced as a global) for stat filtering.
- Produces: `Where2GoItemBrowser.BuildItemPool()` → array of `{itemId,
  bossId, bossName, contentName, raidName, kind}`;
  `Where2GoItemBrowser.FilterItems(pool, filters, context)` → filtered
  array (same entry shape); `Where2GoItemBrowser.SortItems(items,
  sortMode, context)` → new sorted array. `filters` is `{dungeonName =
  nil|string, bossName = nil|string, slot = nil|string, stats =
  {<secondary stat strings>}, specEligibleOnly = false, searchText =
  nil|string}`. `context` is `{getSlot = function(itemId) end, isEligible
  = function(itemId) end, getItemName = function(itemId) end}` — the
  WoW-API-dependent facts this module needs but never calls itself.

- [ ] **Step 1: Write the failing tests**

```lua
-- Fixture pool: 4 items across 2 dungeon bosses and 1 raid boss
local function fixturePool()
    return {
        { itemId = 100, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 101, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 200, bossId = 2, bossName = "Boss B", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 300, bossId = 3, bossName = "Boss C", contentName = "Raid One", raidName = "Raid One", kind = "raid" },
    }
end

local function fixtureContext()
    local slots = { [100] = "HEAD", [101] = "TRINKET", [200] = "TRINKET", [300] = "WEAPON" }
    local eligible = { [100] = true, [101] = true, [200] = false, [300] = true }
    local names = { [100] = "Helm of Testing", [101] = "Trinket Alpha", [200] = "Trinket Beta", [300] = "Sword of Fixtures" }
    return {
        getSlot = function(itemId) return slots[itemId] end,
        isEligible = function(itemId) return eligible[itemId] end,
        getItemName = function(itemId) return names[itemId] end,
    }
end

dofile("Where2Go/Core/ItemBrowser.lua")

-- BuildItemPool: reads real Where2GoSources -- exercised in Step 4's
-- structural check below, not with fixtures (it has no parameters to
-- inject fixture data through).

-- FilterItems: dungeon filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Raid One" }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 300, "dungeonName filter should isolate the raid boss's item")
end

-- FilterItems: boss filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { bossName = "Boss A" }, fixtureContext())
    assert(#results == 2, "bossName filter should return both Boss A items")
end

-- FilterItems: slot filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { slot = "TRINKET" }, fixtureContext())
    assert(#results == 2, "slot filter should return both trinkets (101, 200)")
end

-- FilterItems: specEligibleOnly filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { specEligibleOnly = true }, fixtureContext())
    assert(#results == 3, "specEligibleOnly should exclude itemId 200 (ineligible)")
end

-- FilterItems: searchText filter (case-insensitive substring)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { searchText = "trinket" }, fixtureContext())
    assert(#results == 2, "searchText 'trinket' should match both trinket names")
end

-- FilterItems: stat filter
do
    Where2GoItemStats = { STATS = {
        [100] = { primaryStats = {}, secondaryStats = { "CRIT_RATING" } },
        [101] = { primaryStats = {}, secondaryStats = { "HASTE_RATING" } },
    } }
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { stats = { "HASTE_RATING" } }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 101, "stat filter should match only item 101's Haste")
end

-- FilterItems: combined filters (AND logic)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Dungeon One", slot = "TRINKET" }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 200, "combined dungeon+slot filter should AND together")
end

-- FilterItems: no matches
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Nonexistent" }, fixtureContext())
    assert(#results == 0, "an impossible filter should return an empty (not nil) array")
end

-- SortItems: by name
do
    local sorted = Where2GoItemBrowser.SortItems(fixturePool(), "NAME", fixtureContext())
    assert(sorted[1].itemId == 100, "sorted by name, 'Helm of Testing' should sort before the others alphabetically")
end

-- SortItems: default (dungeon/boss order), does not mutate the input
do
    local original = fixturePool()
    local sorted = Where2GoItemBrowser.SortItems(original, nil, fixtureContext())
    assert(sorted ~= original, "SortItems should return a new array, not mutate the input in place")
    assert(sorted[1].contentName == "Dungeon One" and sorted[#sorted].contentName == "Raid One",
        "default sort should keep dungeon-before-raid pool order")
end

print("itembrowser_spec: OK")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/itembrowser_spec.lua`
Expected: FAIL with an error about `Where2GoItemBrowser` being nil (the
file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

```lua
-- Pure per-boss item pool/filter/sort logic for the item browser. No WoW
-- API dependency -- callers pass in slot/eligibility/name lookups via a
-- `context` table rather than this module calling live APIs itself, so
-- it can be unit-tested with fixture data the same way Ranking.lua is.

Where2GoItemBrowser = {}

function Where2GoItemBrowser.BuildItemPool()
    local pool = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        for _, encounter in ipairs(dungeon.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                table.insert(pool, {
                    itemId = itemId,
                    bossId = encounter.bossId,
                    bossName = encounter.name,
                    contentName = dungeon.name,
                    raidName = nil,
                    kind = "dungeon",
                })
            end
        end
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                table.insert(pool, {
                    itemId = itemId,
                    bossId = encounter.bossId,
                    bossName = encounter.name,
                    contentName = raid.name,
                    raidName = raid.name,
                    kind = "raid",
                })
            end
        end
    end
    return pool
end

local function matchesFilters(entry, filters, context)
    if filters.dungeonName and entry.contentName ~= filters.dungeonName then
        return false
    end
    if filters.bossName and entry.bossName ~= filters.bossName then
        return false
    end
    if filters.slot and context.getSlot(entry.itemId) ~= filters.slot then
        return false
    end
    if filters.stats and #filters.stats > 0 then
        local itemStats = Where2GoItemStats.STATS[entry.itemId]
        if not itemStats then
            return false
        end
        local matchesAny = false
        for _, wantedStat in ipairs(filters.stats) do
            for _, s in ipairs(itemStats.secondaryStats) do
                if s == wantedStat then
                    matchesAny = true
                end
            end
        end
        if not matchesAny then
            return false
        end
    end
    if filters.specEligibleOnly and not context.isEligible(entry.itemId) then
        return false
    end
    if filters.searchText and filters.searchText ~= "" then
        local name = context.getItemName(entry.itemId)
        if not name or not name:lower():find(filters.searchText:lower(), 1, true) then
            return false
        end
    end
    return true
end

function Where2GoItemBrowser.FilterItems(pool, filters, context)
    local results = {}
    for _, entry in ipairs(pool) do
        if matchesFilters(entry, filters, context) then
            table.insert(results, entry)
        end
    end
    return results
end

function Where2GoItemBrowser.SortItems(items, sortMode, context)
    local sorted = {}
    for _, item in ipairs(items) do
        table.insert(sorted, item)
    end
    if sortMode == "NAME" then
        table.sort(sorted, function(a, b)
            return (context.getItemName(a.itemId) or "") < (context.getItemName(b.itemId) or "")
        end)
    end
    return sorted
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/itembrowser_spec.lua`
Expected: `itembrowser_spec: OK` printed, no assertion errors.

- [ ] **Step 5: Add a structural check for BuildItemPool against real data**

Append to `tests/itembrowser_spec.lua` (this part needs the real
`Where2GoSources`, dofile it too):

```lua
dofile("Where2Go/Core/Sources.lua")
local realPool = Where2GoItemBrowser.BuildItemPool()
assert(#realPool > 0, "BuildItemPool() should return a non-empty pool against real Sources.lua")
for _, entry in ipairs(realPool) do
    assert(type(entry.itemId) == "number", "every pool entry should have a numeric itemId")
    assert(type(entry.bossName) == "string" and #entry.bossName > 0, "every pool entry should have a bossName")
    assert(type(entry.contentName) == "string" and #entry.contentName > 0, "every pool entry should have a contentName")
end
print("itembrowser_spec: OK, " .. #realPool .. " real pool entries")
```

Run again: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/itembrowser_spec.lua`
Expected: both `OK` lines print, no errors.

- [ ] **Step 6: Register the spec in run_tests.lua**

Read `tests/run_tests.lua` and add `"itembrowser_spec"` to its spec-name
list, following the same pattern as the existing entries.

- [ ] **Step 7: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs pass, including the new `itembrowser_spec`.

- [ ] **Step 8: Commit**

```bash
git add Where2Go/Core/ItemBrowser.lua tests/itembrowser_spec.lua tests/run_tests.lua
git commit -m "feat: add pure item pool/filter/sort logic for the item browser"
```

---

### Task 2: `Where2Go/UI/BrowserPanel.lua` — window skeleton and filter controls

**Files:**
- Create: `Where2Go/UI/BrowserPanel.lua`

**Interfaces:**
- Consumes: `Where2GoItemBrowser.BuildItemPool()`/`.FilterItems()` (Task
  1); `Where2GoSources.DUNGEONS`/`.RAIDS` (dungeon/boss button lists);
  `Where2GoDirectDrop.GetCurrentSpecIdAndName()`/`.IsEligibleForSpec()`
  (Phase 3/4, already public); `Where2GoConstants.EQUIPLOC_TO_SLOT`;
  `C_Item.GetItemInfoInstant` (slot lookup, same call `Equipment.lua`
  already makes); `Where2GoItemStats.STATS` keys for the stat checkbox
  list.
- Produces: `Where2GoBrowserPanel.Toggle()` — the function Task 4's
  `Panel.lua`/`Init.lua` changes call to open/close this window. Not
  unit-tested (WoW-API-dependent), matching `Panel.lua`'s precedent.

This task builds the frame, the Drop/Voidcore toggle, and every filter
control, wiring them all to a single `RebuildFilteredResults()` function
that Task 3 will populate the actual result list from. Task 3 appends the
result list and action buttons to this same file.

- [ ] **Step 1: Write the file's state, slot/eligibility helpers, and frame skeleton**

```lua
local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { dungeonName = nil, bossName = nil, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit

-- Forward declaration (same pattern UI/Panel.lua uses for `Layout`):
-- Task 2 Step 3 assigns a filter-only stub; Task 3 Step 1 replaces that
-- assignment with the real version that also refreshes the visible rows.
-- Every caller below (RebuildBossButtons, the mode toggle, every filter
-- control's OnClick) calls it by this same upvalue, so whichever body is
-- currently assigned is the one that runs -- no redefinition ambiguity.
local RebuildFilteredResults

local dungeonButtons = {}
local bossButtons = {}
local slotButtons = {}
local statCheckboxes = {}

local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }
local STAT_LABELS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Versatility" }

local function GetItemSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

local function GetItemEligible(itemId)
    local specId = select(1, Where2GoDirectDrop.GetCurrentSpecIdAndName())
    if not specId then
        return true
    end
    return Where2GoDirectDrop.IsEligibleForSpec(specId)(itemId)
end

local function GetItemName(itemId)
    return Where2GoDirectDrop.GetItemNames({ itemId })[itemId]
end

local function BuildContext()
    return {
        getSlot = GetItemSlot,
        isEligible = GetItemEligible,
        getItemName = GetItemName,
    }
end

local function IsPreferred(itemId)
    return Where2GoCharDB.preferredItems[currentMode][itemId] == true
end
```

- [ ] **Step 2: Add the toggle-button-group helper (reused for dungeon/boss/slot lists)**

```lua
-- A row of mutually-exclusive toggle buttons (only one active at a time,
-- or none). `onSelect` is called with the selected value (or nil if the
-- currently-active button is clicked again, deselecting it).
local function CreateToggleButtonRow(parent, values, labelFn, onSelect)
    local buttons = {}
    local selectedValue = nil
    local x = 0
    for _, value in ipairs(values) do
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(90, 20)
        button:SetPoint("TOPLEFT", x, 0)
        button:SetText(labelFn(value))
        button:SetScript("OnClick", function()
            if selectedValue == value then
                selectedValue = nil
            else
                selectedValue = value
            end
            for v, btn in pairs(buttons) do
                if v == selectedValue then
                    btn:LockHighlight()
                else
                    btn:UnlockHighlight()
                end
            end
            onSelect(selectedValue)
        end)
        buttons[value] = button
        x = x + 94
    end
    return buttons
end
```

- [ ] **Step 3: Add `RebuildFilteredResults` (stub filled in by Task 3) and the filter-changing callbacks**

```lua
-- Task 3 Step 1 reassigns this to also refresh the visible rows.
RebuildFilteredResults = function()
    local unsorted = Where2GoItemBrowser.FilterItems(itemPool, filters, BuildContext())
    filteredResults = Where2GoItemBrowser.SortItems(unsorted, nil, BuildContext())
end

local function RebuildBossButtons(parent, dungeonOrRaid)
    for _, btn in pairs(bossButtons) do
        btn:Hide()
    end
    bossButtons = {}
    if not dungeonOrRaid then
        RebuildFilteredResults()
        return
    end
    local bossNames = {}
    for _, encounter in ipairs(dungeonOrRaid.encounters) do
        table.insert(bossNames, encounter.name)
    end
    bossButtons = CreateToggleButtonRow(parent, bossNames, function(v) return v end, function(selected)
        filters.bossName = selected
        RebuildFilteredResults()
    end)
    RebuildFilteredResults()
end
```

- [ ] **Step 4: Add `CreateBrowserPanel()` — the frame, Drop/Voidcore toggle, and all filter rows**

```lua
local function CreateBrowserPanel()
    local frame = CreateFrame("Frame", "Where2GoBrowserPanel", UIParent, "BackdropTemplate")
    frame:SetSize(520, 480)
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
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Where2Go - Item Browser")

    -- Drop/Voidcore mode toggle
    local dropButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dropButton:SetSize(80, 20)
    dropButton:SetPoint("TOPLEFT", 12, -36)
    dropButton:SetText("Drop")
    local voidcoreButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    voidcoreButton:SetSize(80, 20)
    voidcoreButton:SetPoint("LEFT", dropButton, "RIGHT", 6, 0)
    voidcoreButton:SetText("Voidcore")
    local function SetMode(mode)
        currentMode = mode
        if mode == "DROP" then
            dropButton:LockHighlight()
            voidcoreButton:UnlockHighlight()
        else
            voidcoreButton:LockHighlight()
            dropButton:UnlockHighlight()
        end
        stagedSelection = {}
        RebuildFilteredResults()
    end
    dropButton:SetScript("OnClick", function() SetMode("DROP") end)
    voidcoreButton:SetScript("OnClick", function() SetMode("VOIDCORE") end)

    -- Dungeon/raid row. `bossRow` is declared before `dungeonButtons` is
    -- built, since dungeonButtons' OnClick closures capture it by
    -- reference (a Lua local is only visible to code compiled after its
    -- declaration -- declaring bossRow later would make those closures
    -- silently resolve it as an undeclared global instead).
    local dungeonRow = CreateFrame("Frame", nil, frame)
    dungeonRow:SetPoint("TOPLEFT", 12, -64)
    dungeonRow:SetSize(496, 20)

    -- Boss row (populated once a dungeon/raid is selected)
    local bossRow = CreateFrame("Frame", nil, frame)
    bossRow:SetPoint("TOPLEFT", dungeonRow, "BOTTOMLEFT", 0, -26)
    bossRow:SetSize(496, 20)

    local dungeonAndRaidEntries = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(dungeonAndRaidEntries, dungeon)
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        table.insert(dungeonAndRaidEntries, raid)
    end
    dungeonButtons = CreateToggleButtonRow(dungeonRow, dungeonAndRaidEntries, function(d) return d.name end, function(selected)
        filters.dungeonName = selected and selected.name or nil
        filters.bossName = nil
        RebuildBossButtons(bossRow, selected)
    end)

    -- Slot row
    local slotRow = CreateFrame("Frame", nil, frame)
    slotRow:SetPoint("TOPLEFT", bossRow, "BOTTOMLEFT", 0, -26)
    slotRow:SetSize(496, 20)
    slotButtons = CreateToggleButtonRow(slotRow, SLOT_ORDER, function(s) return s end, function(selected)
        filters.slot = selected
        RebuildFilteredResults()
    end)

    -- Stat checkbox row (multi-select)
    local statRow = CreateFrame("Frame", nil, frame)
    statRow:SetPoint("TOPLEFT", slotRow, "BOTTOMLEFT", 0, -26)
    statRow:SetSize(496, 20)
    local statX = 0
    for _, stat in ipairs(STAT_ORDER) do
        local checkbox = CreateFrame("CheckButton", nil, statRow, "UICheckButtonTemplate")
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("TOPLEFT", statX, 0)
        local label = statRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
        label:SetText(STAT_LABELS[stat])
        checkbox:SetScript("OnClick", function(self)
            filters.stats = filters.stats or {}
            if self:GetChecked() then
                table.insert(filters.stats, stat)
            else
                for i, s in ipairs(filters.stats) do
                    if s == stat then
                        table.remove(filters.stats, i)
                        break
                    end
                end
            end
            RebuildFilteredResults()
        end)
        statCheckboxes[stat] = checkbox
        statX = statX + 90
    end

    -- Spec-eligible-only checkbox
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("TOPLEFT", statRow, "BOTTOMLEFT", 0, -26)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText("Current spec eligible only")
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

    -- Search box
    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", eligibleCheckbox, "BOTTOMLEFT", 4, -26)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        filters.searchText = self:GetText()
        RebuildFilteredResults()
    end)

    frame.dungeonRow = dungeonRow
    frame.bossRow = bossRow
    frame.searchBox = searchBox
    frame:Hide()
    return frame
end
```

- [ ] **Step 5: Verify the file compiles as a syntax check**

Since this file calls `CreateFrame` at multiple points inside functions
(never at file top level unguarded), it's safe to syntax-check with the
same `loadfile`-only approach used elsewhere in this project (compiles
without executing, so `CreateFrame` never actually gets called):

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" -e "assert(loadfile('Where2Go/UI/BrowserPanel.lua'))" && echo OK`
Expected: `OK` printed, no error.

- [ ] **Step 6: Commit**

```bash
git add Where2Go/UI/BrowserPanel.lua
git commit -m "feat: add item browser window skeleton and filter controls"
```

---

### Task 3: `Where2Go/UI/BrowserPanel.lua` — result list, staging, and action buttons

**Files:**
- Modify: `Where2Go/UI/BrowserPanel.lua`

**Interfaces:**
- Consumes: `filteredResults`, `stagedSelection`, `currentMode`, `RebuildFilteredResults`,
  `IsPreferred` (Task 2's local state/functions in the same file).
- Produces: `Where2GoBrowserPanel.Toggle()` (the public entry point Task
  4 wires a button/slash command to).

- [ ] **Step 1: Reassign `RebuildFilteredResults` to also refresh the visible rows**

`RebuildFilteredResults` was forward-declared as a local in Task 2 Step 1
and given a filter-only body in Task 2 Step 3. Replace that assignment
(not a new `local` declaration — reassign the same forward-declared
upvalue, so every existing caller picks up this new body automatically)
with:

```lua
local ROW_HEIGHT = 20
local VISIBLE_ROWS = 12
local resultRows = {}
local scrollOffset = 0

local function ClampScrollOffset()
    local maxOffset = math.max(0, #filteredResults - VISIBLE_ROWS)
    if scrollOffset < 0 then
        scrollOffset = 0
    elseif scrollOffset > maxOffset then
        scrollOffset = maxOffset
    end
end

local function RefreshVisibleRows()
    for i = 1, VISIBLE_ROWS do
        local row = resultRows[i]
        local entry = filteredResults[scrollOffset + i]
        if entry and row then
            row:Show()
            row.entry = entry
            local prefix = entry.raidName and (entry.raidName .. " - ") or ""
            local name = GetItemName(entry.itemId) or ("Item #" .. entry.itemId)
            local preferredMark = IsPreferred(entry.itemId) and "|cff00ff00[preferred]|r " or ""
            row.text:SetText(preferredMark .. prefix .. entry.contentName .. " / " .. entry.bossName .. ": " .. name)
            row.checkbox:SetChecked(stagedSelection[entry.itemId] == true)
        elseif row then
            row:Hide()
            row.entry = nil
        end
    end
end

RebuildFilteredResults = function()
    local unsorted = Where2GoItemBrowser.FilterItems(itemPool, filters, BuildContext())
    filteredResults = Where2GoItemBrowser.SortItems(unsorted, nil, BuildContext())
    ClampScrollOffset()
    RefreshVisibleRows()
end
```

This step's code must appear in the file AFTER `RefreshVisibleRows` and
`ClampScrollOffset` are defined (both above it in this same step), but
BEFORE `CreateBrowserPanel()`'s body runs (Task 2 Step 4) — place it
right after Task 2 Step 3's `RebuildBossButtons` function, replacing
that step's `RebuildFilteredResults` assignment in place.

- [ ] **Step 2: Add row creation and the mouse-wheel scroll handler, appended inside `CreateBrowserPanel()` after the search box**

```lua
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -12)
    listFrame:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    listFrame:SetHeight(VISIBLE_ROWS * ROW_HEIGHT)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollOffset = scrollOffset - delta
        ClampScrollOffset()
        RefreshVisibleRows()
    end)

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, listFrame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)

        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("LEFT", 0, 0)
        checkbox:SetScript("OnClick", function(self)
            local r = self:GetParent()
            if r.entry then
                if self:GetChecked() then
                    stagedSelection[r.entry.itemId] = true
                else
                    stagedSelection[r.entry.itemId] = nil
                end
            end
        end)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")

        row.checkbox = checkbox
        row.text = text
        resultRows[i] = row
    end
```

- [ ] **Step 3: Add the three action buttons, appended after the row list**

```lua
    local addSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSelectedButton:SetSize(140, 22)
    addSelectedButton:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 4, -12)
    addSelectedButton:SetText("Add selected")
    addSelectedButton:SetScript("OnClick", function()
        for itemId in pairs(stagedSelection) do
            Where2GoCharDB.preferredItems[currentMode][itemId] = true
        end
        stagedSelection = {}
        RebuildFilteredResults()
    end)

    local clearSelectionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearSelectionButton:SetSize(140, 22)
    clearSelectionButton:SetPoint("LEFT", addSelectedButton, "RIGHT", 8, 0)
    clearSelectionButton:SetText("Clear selection")
    clearSelectionButton:SetScript("OnClick", function()
        stagedSelection = {}
        RefreshVisibleRows()
    end)

    local clearPreferredButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearPreferredButton:SetSize(160, 22)
    clearPreferredButton:SetPoint("LEFT", clearSelectionButton, "RIGHT", 8, 0)
    clearPreferredButton:SetText("Clear preferred list")
    clearPreferredButton:SetScript("OnClick", function()
        StaticPopup_Show("WHERE2GO_CLEAR_PREFERRED")
    end)
```

- [ ] **Step 4: Register the confirmation dialog and the public `Toggle()` entry point, added at file scope (outside `CreateBrowserPanel`)**

```lua
StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"] = {
    text = "Remove every preferred item from the current list?",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        Where2GoCharDB.preferredItems[currentMode] = {}
        RebuildFilteredResults()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

Where2GoBrowserPanel = {}

function Where2GoBrowserPanel.Toggle()
    if not browserFrame then
        browserFrame = CreateBrowserPanel()
        itemPool = Where2GoItemBrowser.BuildItemPool()
        RebuildFilteredResults()
    end
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        browserFrame:Show()
    end
end
```

- [ ] **Step 5: Verify the file still compiles**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" -e "assert(loadfile('Where2Go/UI/BrowserPanel.lua'))" && echo OK`
Expected: `OK` printed, no error.

- [ ] **Step 6: Commit**

```bash
git add Where2Go/UI/BrowserPanel.lua
git commit -m "feat: add result list, staged selection, and action buttons to item browser"
```

---

### Task 4: Wire up access — TOC, main panel button, slash command

**Files:**
- Modify: `Where2Go.toc`
- Modify: `Where2Go/UI/Panel.lua`
- Modify: `Where2Go/Core/Init.lua`

**Interfaces:**
- Consumes: `Where2GoBrowserPanel.Toggle()` (Task 3).

- [ ] **Step 1: Register the two new files in Where2Go.toc**

Add `Core\ItemBrowser.lua` after `Core\Sources.lua` (grouping data/logic
files together, matching Sub-project A's placement of `ItemStats.lua`),
and add `UI\BrowserPanel.lua` after `UI\Panel.lua`:

```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
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

- [ ] **Step 2: Add a button to the main panel that opens the browser**

In `Where2Go/UI/Panel.lua`'s `CreatePanel()` function, after the existing
`CreateTab(frame, "Drop", "DROP", 12)` / `CreateTab(frame, "Voidcore",
"VOIDCORE", 96)` lines, add:

```lua
    local browseButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    browseButton:SetSize(70, 20)
    browseButton:SetPoint("TOPRIGHT", -28, -34)
    browseButton:SetText("Browse")
    browseButton:SetScript("OnClick", function()
        Where2GoBrowserPanel.Toggle()
    end)
```

- [ ] **Step 3: Add a `/where2go browse` slash subcommand**

In `Where2Go/Core/Init.lua`'s `SlashCmdList["WHERE2GO"]` handler, add a
new branch alongside the existing `pref`/`compare` ones:

```lua
    elseif subcommand == "browse" then
        Where2GoBrowserPanel.Toggle()
```

(Insert this as an additional `elseif` branch in the existing chain,
before the final `else` that prints the usage message — update that usage
message to also mention `/where2go browse`.)

- [ ] **Step 4: Run the full test suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs pass, `toc_spec` reports the new file count (15
files: 13 from Sub-project A plus `ItemBrowser.lua` and
`BrowserPanel.lua`).

- [ ] **Step 5: Commit**

```bash
git add Where2Go.toc Where2Go/UI/Panel.lua Where2Go/Core/Init.lua
git commit -m "feat: wire up the item browser via a panel button and slash command"
```

---

### Task 5: Manual live checkpoint

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — verify the item browser live**

This cannot be run by an agent — it requires the WoW client. Whoever
executes this task should:

1. `/reload` and confirm no Lua error appears.
2. Open the main panel (`/where2go`), click "Browse" — confirm the
   browser window opens showing a Drop/Voidcore toggle and filter
   controls, with no error.
3. Click a dungeon button — confirm boss buttons for that dungeon appear,
   and the result list updates to only that dungeon's items.
4. Click a boss button — confirm the list narrows further to that boss's
   items only.
5. Toggle a slot button and a stat checkbox — confirm the list narrows
   further (combined AND filtering).
6. Toggle "Current spec eligible only" — confirm ineligible items drop
   out of the list.
7. Type a search term matching a known item's name — confirm the list
   filters to matches.
8. Check a few item checkboxes across different filter views (staged
   selection should persist as you change filters), then click "Add
   selected" — confirm those items now show the `[preferred]` marker in
   the list, and appear as targets in the main panel's corresponding
   Drop/Voidcore tab on next refresh.
9. Check a couple more items, click "Clear selection" — confirm the
   checkboxes uncheck and nothing was added to the preferred list.
10. Click "Clear preferred list" — confirm a confirmation dialog appears;
    cancel it once (confirm nothing changes), then accept it — confirm
    the active mode's entire preferred list empties (verify via the main
    panel or `/where2go pref list <drop|voidcore>`) while the OTHER
    mode's list is untouched.
11. Scroll the result list with the mouse wheel over a filter broad
    enough to exceed the visible row count — confirm scrolling works and
    doesn't show stale/duplicate rows.
12. Close and reopen the browser (and `/reload`) — confirm no leftover
    frames, no error, and the browser's filter state resetting on reopen
    is acceptable (not required to persist across sessions).

Report back to the controller: what worked, and any Lua errors or visual
issues encountered (existing widget templates like `UIPanelButtonTemplate`/
`UICheckButtonTemplate`/`InputBoxTemplate` are assumed present and stable
across WoW versions, but confirm none produced a "template not found"
error, which would indicate this client version needs different template
names).

This satisfies `docs/superpowers/specs/2026-09-03-phase6-item-browser-design.md`'s
acceptance check.

---

## Done

Phase 6 (both sub-projects) is complete when all five tasks' commits
exist and Task 5's manual checkpoint confirms the browser works live,
including the three action buttons behaving distinctly as designed.
