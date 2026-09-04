# Phase 9: Item Browser / Recommendation Panel UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both UI windows (item browser, recommendation panel) a real
user-facing pass: localized UI chrome, icon+quality-colored-name+ilvl/stat
item rows with real tooltips, a merged multi-select Source filter, and a
new visible Staged/Preferred side-by-side layout in the browser.

**Architecture:** Two new small shared modules
(`Where2Go/Core/Locale.lua`, `Where2Go/UI/ItemRow.lua`) get consumed by
both existing UI files. `Where2Go/Core/ItemBrowser.lua`'s pure filter
logic gains a `sourceKey`-based filter replacing the old
`dungeonName`/`bossName` pair. `Where2Go/UI/BrowserPanel.lua` is
substantially rebuilt (new dropdown, three-column layout); `Where2Go/UI/Panel.lua`
gets a small, contained change (its card item rows adopt the shared
treatment; everything else — cards, expand/collapse, tabs — is untouched).

**Tech Stack:** Lua (WoW addon), `lua5.1` for the plain-Lua test harness.

**Spec:** `docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md`

## Global Constraints

- Committed/shared data files follow this project's established
  conventions: pure (no-WoW-API) logic gets unit tests in `tests/`;
  anything touching `CreateFrame`, `C_Item`, `GameTooltip`,
  `UIDropDownMenu_*`, or other live WoW APIs is WoW-API-dependent —
  verified live, not unit-tested, matching every prior UI-file change in
  this project.
- Every `.lua` file under `Where2Go/Core` or `Where2Go/UI` must be
  referenced in `Where2Go/Where2Go.toc`, enforced by
  `tests/toc_spec.lua`'s completeness sweep (which also `loadfile`-parse-checks
  every referenced file — a real syntax error in any file this plan
  touches will fail the suite, not just a missing-file check).
- Run the full suite with:
  `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
- Locked-in decisions from the spec (do not re-derive/re-litigate; see the
  spec's "Scope recap" section for full context): client-locale-detected
  UI chrome only (not item names/tooltips/dungeon-boss names); real
  `GameTooltip`, never a custom one; merged multi-select Source dropdown
  replacing separate Dungeon/Boss rows; icon+quality-name+summary item
  rows on both windows; Staged and Preferred as two separate visible
  browser panels; spec selector next to the eligible-only checkbox;
  Recommendation panel gets item-row-only changes, nothing structural.

## Plan-time corrections to the spec's code sketches

Two small, deliberate fixes to the design doc's illustrative code, found
while turning it into an exact implementation (both explained in their
task below, not re-litigating the design):

1. **`Locale.lua`'s locale detection must not call `GetLocale()`
   unconditionally at module load time** — `GetLocale` is a WoW API global
   that does not exist in the plain-Lua test harness, so the spec's literal
   sketch would make `dofile("Where2Go/Core/Locale.lua")` error immediately
   in any test. Guarded with `type(GetLocale) == "function"`, matching
   `Core/SpecEligibilityScan.lua`'s existing `if CreateFrame then ... end`
   pattern for the same class of problem.
2. **`Locale.lua`'s string tables are exposed as `Where2GoLocale.STRINGS`/`Where2GoLocale.SLOT_LABELS`
   (public fields), not `local` (as sketched)** — needed so
   `tests/locale_spec.lua` can write an enUS/koKR coverage cross-check,
   the same public-data-table pattern `Sources.lua`/`ItemStats.lua`
   already use for their own coverage tests.

---

## Task 1: `Where2Go/Core/Locale.lua`

**Files:**
- Create: `Where2Go/Core/Locale.lua`
- Modify: `Where2Go/Where2Go.toc`
- Create: `tests/locale_spec.lua`
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Produces: `Where2GoLocale.L(key) -> string`, `Where2GoLocale.SlotLabel(slot) -> string`,
  `Where2GoLocale.STRINGS` / `Where2GoLocale.SLOT_LABELS` (public tables,
  `{ enUS = {...}, koKR = {...} }`), consumed by Task 4 and Task 5.

- [ ] **Step 1: Write the failing tests**

Create `tests/locale_spec.lua`:

```lua
dofile("Where2Go/Core/Locale.lua")

assert(type(Where2GoLocale) == "table", "Where2GoLocale should be a table")
assert(type(Where2GoLocale.L) == "function", "Where2GoLocale.L should be a function")
assert(type(Where2GoLocale.SlotLabel) == "function", "Where2GoLocale.SlotLabel should be a function")

-- The plain-Lua test harness has no GetLocale global, so Locale.lua's
-- module-load-time locale detection falls back to enUS -- these
-- assertions exercise the enUS table and the fallback logic directly,
-- not live locale detection (which is WoW-API-dependent, verified live).
assert(Where2GoLocale.L("BROWSE_BUTTON") == "Browse", "L() should return the enUS string by default in this harness")
assert(Where2GoLocale.SlotLabel("HEAD") == "Head", "SlotLabel() should return the enUS label by default")
assert(Where2GoLocale.L("NONEXISTENT_KEY_XYZ") == "NONEXISTENT_KEY_XYZ", "L() should fall back to the key itself when missing from every table")

-- Coverage: every enUS key must have a koKR counterpart, so a forgotten
-- translation doesn't silently ship English-only for Korean players.
local coverageCount = 0
for key in pairs(Where2GoLocale.STRINGS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.STRINGS.koKR[key] ~= nil, "koKR STRINGS is missing a translation for '" .. key .. "'")
end
for key in pairs(Where2GoLocale.SLOT_LABELS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.SLOT_LABELS.koKR[key] ~= nil, "koKR SLOT_LABELS is missing a translation for '" .. key .. "'")
end

print("locale_spec: OK, " .. coverageCount .. " string(s) cross-checked between enUS and koKR")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
(This test file isn't registered in `run_tests.lua` yet, so run it
directly first: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/locale_spec.lua`)
Expected: FAIL — `Where2Go/Core/Locale.lua` does not exist yet
(`cannot open Where2Go/Core/Locale.lua`).

- [ ] **Step 3: Create `Where2Go/Core/Locale.lua`**

```lua
-- Addon UI chrome localization: detects the WoW client's locale once via
-- GetLocale() and matches the addon's OWN strings (button labels,
-- headers, slot names) to it. Item names, the real GameTooltip, and
-- dungeon/boss names (Sources.lua, addon-owned data) are explicitly NOT
-- covered here -- item names/tooltips already match the client's
-- language with zero addon work, and dungeon/boss name translation is
-- separate future data-prep work (see
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md).
--
-- STRINGS/SLOT_LABELS are public (not local) so tests/locale_spec.lua can
-- cross-check enUS/koKR coverage, the same pattern Sources.lua/ItemStats.lua
-- use for their own coverage tests.

Where2GoLocale = {}

Where2GoLocale.STRINGS = {
    enUS = {
        BROWSER_TITLE = "Where2Go - Item Browser",
        PANEL_TITLE = "Where2Go",
        MODE_DROP = "Drop",
        MODE_VOIDCORE = "Voidcore",
        BROWSE_BUTTON = "Browse",
        NO_SPEC_SELECTED = "Where2Go: no specialization selected.",
        SOURCE_DROPDOWN_ALL = "All Sources",
        SOURCE_DROPDOWN_N_SELECTED = "%d selected",
        SOURCE_GROUP_DUNGEONS = "Dungeons",
        ELIGIBLE_ONLY = "Selected spec eligible only",
        RESULTS_HEADER = "Results",
        STAGED_HEADER = "Staged",
        PREFERRED_HEADER = "Preferred",
        ADD_SELECTED = "Add selected",
        CLEAR_SELECTION = "Clear selection",
        CLEAR_ALL = "Clear All",
        CLEAR_PREFERRED_CONFIRM = "Remove every preferred item from the current list?",
        CLEAR_BUTTON = "Clear",
        CANCEL_BUTTON = "Cancel",
    },
    koKR = {
        BROWSER_TITLE = "Where2Go - 아이템 탐색기",
        PANEL_TITLE = "Where2Go",
        MODE_DROP = "드랍",
        MODE_VOIDCORE = "보이드코어",
        BROWSE_BUTTON = "탐색",
        NO_SPEC_SELECTED = "Where2Go: 전문화가 선택되지 않았습니다.",
        SOURCE_DROPDOWN_ALL = "모든 출처",
        SOURCE_DROPDOWN_N_SELECTED = "%d개 선택됨",
        SOURCE_GROUP_DUNGEONS = "던전",
        ELIGIBLE_ONLY = "선택한 전문화만 표시",
        RESULTS_HEADER = "결과",
        STAGED_HEADER = "임시 선택",
        PREFERRED_HEADER = "선호 아이템",
        ADD_SELECTED = "선택 추가",
        CLEAR_SELECTION = "선택 해제",
        CLEAR_ALL = "전체 삭제",
        CLEAR_PREFERRED_CONFIRM = "현재 목록의 모든 선호 아이템을 삭제할까요?",
        CLEAR_BUTTON = "삭제",
        CANCEL_BUTTON = "취소",
    },
}

Where2GoLocale.SLOT_LABELS = {
    enUS = {
        HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back",
        CHEST = "Chest", WRIST = "Wrist", HANDS = "Hands", WAIST = "Waist",
        LEGS = "Legs", FEET = "Feet", FINGER = "Finger", TRINKET = "Trinket",
        MAINHAND = "Main Hand", OFFHAND = "Off Hand",
    },
    koKR = {
        HEAD = "머리", NECK = "목", SHOULDER = "어깨", BACK = "등",
        CHEST = "가슴", WRIST = "손목", HANDS = "손", WAIST = "허리",
        LEGS = "다리", FEET = "발", FINGER = "손가락", TRINKET = "장신구",
        MAINHAND = "주 무기", OFFHAND = "보조 무기",
    },
}

-- Guarded: GetLocale is a WoW API global, absent in the plain-Lua test
-- harness. Falls back to enUS there rather than erroring at load time.
local activeLocale = (type(GetLocale) == "function" and GetLocale() == "koKR") and "koKR" or "enUS"

-- Falls back to enUS for any key missing in the active table, then to
-- the key itself if even enUS is missing it (never shows a blank string).
function Where2GoLocale.L(key)
    return Where2GoLocale.STRINGS[activeLocale][key] or Where2GoLocale.STRINGS.enUS[key] or key
end

function Where2GoLocale.SlotLabel(slot)
    return Where2GoLocale.SLOT_LABELS[activeLocale][slot] or Where2GoLocale.SLOT_LABELS.enUS[slot] or slot
end
```

- [ ] **Step 4: Register in the TOC**

In `Where2Go/Where2Go.toc`, insert `Core\Locale.lua` immediately after
`Core\Constants.lua` (first file, load-order-critical per
`tests/toc_spec.lua`) and before every other file:

```
Core\Constants.lua
Core\Locale.lua
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

- [ ] **Step 5: Register the test in the runner**

In `tests/run_tests.lua`, add `"tests/locale_spec.lua"` right after
`"tests/constants_spec.lua"`:

```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/locale_spec.lua",
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

- [ ] **Step 6: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`, including `locale_spec.lua` and `toc_spec.lua`
(confirms `Locale.lua` is on disk, TOC-referenced, and parses).

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/Locale.lua Where2Go/Where2Go.toc tests/locale_spec.lua tests/run_tests.lua
git commit -m "feat: add Where2GoLocale enUS/koKR UI-chrome string table"
```

---

## Task 2: `Where2Go/UI/ItemRow.lua`

**Files:**
- Create: `Where2Go/UI/ItemRow.lua`
- Modify: `Where2Go/Where2Go.toc`

**Interfaces:**
- Consumes: `Where2GoItemStats.STATS` (existing), `ITEM_QUALITY_COLORS`
  (WoW global), `C_Item.GetItemInfo`/`GetItemIcon` (WoW API),
  `GameTooltip` (WoW global).
- Produces: `Where2GoItemRow.CreateWidgets(row, iconSize, leftOffset)`,
  `Where2GoItemRow.Populate(row, itemId, ilvl)` — consumed by Task 4 and
  Task 5.

**Plan-time refinement over the spec's sketch:** `CreateWidgets` gains a
third parameter, `leftOffset` (defaults to `0`), not present in the design
doc's illustrative code. Reason: the browser's Results rows need the icon
to start to the right of a checkbox, while Staged/Preferred rows and the
Recommendation panel's card rows have no checkbox and want the icon flush
left. The design doc's own "Not yet decided" list already deferred "exact
pixel layout beyond what the mockup shows" to implementation — this is
that deferred decision, resolved here.

- [ ] **Step 1: Create `Where2Go/UI/ItemRow.lua`**

```lua
-- Shared item-row rendering: icon + quality-colored name + a compact
-- "ilvl · secondary-stat" summary line, with a real GameTooltip on hover.
-- Used by both UI/BrowserPanel.lua (Results/Staged/Preferred rows) and
-- UI/Panel.lua (expanded card item rows) so both windows render items
-- identically. See
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md.
--
-- WoW-API-dependent (CreateTexture/CreateFontString/C_Item/GameTooltip)
-- -- not unit-tested, verified live, matching this project's convention
-- for UI-layer code.

Where2GoItemRow = {}

Where2GoItemRow.STAT_ABBREV = {
    CRIT_RATING = "Crit", HASTE_RATING = "Haste",
    MASTERY_RATING = "Mastery", VERSATILITY = "Vers",
}

-- Builds the icon+name+summary sub-widgets on a fresh row frame. Callers
-- create one row per pooled slot (matching this project's existing
-- pooled-row pattern) and call this once at row creation, then call
-- Populate on every refresh. `leftOffset` shifts the icon right of any
-- caller-owned control (e.g. a checkbox) that occupies the row's own
-- left edge; 0 (or omitted) means the icon starts flush at the row's
-- left edge.
function Where2GoItemRow.CreateWidgets(row, iconSize, leftOffset)
    leftOffset = leftOffset or 0

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", leftOffset, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.summary:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.summary:SetJustifyH("LEFT")
    row.summary:SetWordWrap(false)
end

-- Fills an already-built row's widgets for one item and wires hover ->
-- real GameTooltip. `ilvl` is the caller-computed effective item level
-- for this item's source (nil is fine -- the summary line just omits it,
-- used by Staged/Preferred rows which don't carry a single fixed
-- source). Cold-item-cache items show a placeholder icon/name and
-- self-heal the same way this project's existing name lookups already
-- do (the browser's GET_ITEM_INFO_RECEIVED watcher triggers a rebuild).
function Where2GoItemRow.Populate(row, itemId, ilvl)
    local name, _, quality = C_Item.GetItemInfo(itemId)
    local icon = C_Item.GetItemIcon(itemId)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local color = quality and ITEM_QUALITY_COLORS[quality]
    local hex = color and color.hex or "|cffffffff"
    row.name:SetText(hex .. (name or ("Item #" .. itemId)) .. "|r")

    local statLabels = {}
    local itemStats = Where2GoItemStats.STATS[itemId]
    if itemStats then
        for _, stat in ipairs(itemStats.secondaryStats) do
            table.insert(statLabels, Where2GoItemRow.STAT_ABBREV[stat] or stat)
        end
    end
    local statText = #statLabels > 0 and table.concat(statLabels, "/") or ""
    if ilvl and statText ~= "" then
        row.summary:SetText(ilvl .. " · " .. statText)
    elseif ilvl then
        row.summary:SetText(tostring(ilvl))
    else
        row.summary:SetText(statText)
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemId)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
```

- [ ] **Step 2: Register in the TOC**

In `Where2Go/Where2Go.toc`, insert `UI\ItemRow.lua` before `UI\Panel.lua`
(the last two lines become):

```
UI\ItemRow.lua
UI\Panel.lua
UI\BrowserPanel.lua
```

- [ ] **Step 3: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]` (`toc_spec.lua` confirms `ItemRow.lua` is present,
TOC-referenced, and parses — this file has no other automated coverage,
matching the WoW-API-dependent-code convention).

- [ ] **Step 4: Commit**

```bash
git add Where2Go/UI/ItemRow.lua Where2Go/Where2Go.toc
git commit -m "feat: add shared Where2GoItemRow icon/quality-name/tooltip row renderer"
```

---

## Task 3: `Where2GoItemBrowser` gains `sourceKey`-based filtering

**Files:**
- Modify: `Where2Go/Core/ItemBrowser.lua`
- Test: `tests/itembrowser_spec.lua`

**Interfaces:**
- Produces: every `Where2GoItemBrowser.BuildItemPool()` entry gains a
  `sourceKey` field (`"dungeon:"..instanceId` for dungeon entries,
  `"boss:"..bossId` for raid entries — reusing
  `Where2GoDirectDrop.BuildContentList()`'s exact id scheme).
  `Where2GoItemBrowser.FilterItems`'s `filters` table drops
  `dungeonName`/`bossName` in favor of `filters.sources = { [sourceKey] = true, ... }`
  (empty/nil = no filter). Consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

Open `tests/itembrowser_spec.lua`. Replace the fixture pool (adds
`sourceKey` to every entry):

```lua
-- Fixture pool: 4 items across 2 dungeon bosses (same dungeon) and 1 raid boss
local function fixturePool()
    return {
        { itemId = 100, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 101, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 200, bossId = 2, bossName = "Boss B", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 300, bossId = 3, bossName = "Boss C", contentName = "Raid One", raidName = "Raid One", kind = "raid", sourceKey = "boss:3" },
    }
end
```

Replace the `"FilterItems: dungeon filter"` and `"FilterItems: boss
filter"` blocks with:

```lua
-- FilterItems: a dungeon source key selects that whole dungeon's items,
-- regardless of which of its bosses dropped them (dungeons are a
-- whole-run unit, not filtered per-boss)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true } }, fixtureContext())
    assert(#results == 3, "dungeon:1 source key should return all 3 Dungeon One items across both its bosses")
end

-- FilterItems: a raid boss source key selects only that boss's item
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["boss:3"] = true } }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 300, "boss:3 source key should isolate the raid boss's item")
end

-- FilterItems: multiple selected source keys union together (OR, not AND)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true, ["boss:3"] = true } }, fixtureContext())
    assert(#results == 4, "selecting a dungeon key and a boss key together should return the union of both")
end

-- FilterItems: empty sources table means no filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = {} }, fixtureContext())
    assert(#results == 4, "an empty sources table should not filter anything out")
end
```

Replace the `"FilterItems: combined filters (AND logic)"` block:

```lua
-- FilterItems: combined filters (AND logic)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true }, slot = "TRINKET" }, fixtureContext())
    assert(#results == 2, "combined source+slot filter should AND together")
end
```

Replace the `"FilterItems: no matches"` block:

```lua
-- FilterItems: no matches
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:999"] = true } }, fixtureContext())
    assert(#results == 0, "an impossible source key should return an empty (not nil) array")
end
```

Add a new assertion inside the existing real-pool structural check at the
bottom of the file (after the `bossName`/`contentName` assertions, before
the final `print`):

```lua
    assert(type(entry.sourceKey) == "string" and entry.sourceKey:match("^dungeon:%d+$") or entry.sourceKey:match("^boss:%d+$"),
        "every pool entry's sourceKey should match 'dungeon:<id>' or 'boss:<id>', got " .. tostring(entry.sourceKey))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/itembrowser_spec.lua` (the new assertions fail —
`entry.sourceKey` is `nil`, the `sources` filter isn't implemented yet so
old `dungeonName`/`bossName`-keyed filter calls with `sources` passed in
are silently ignored, returning all 4 items unfiltered where the tests
expect 3, 1, or 0).

- [ ] **Step 3: Update `Where2Go/Core/ItemBrowser.lua`**

Replace `BuildItemPool`:

```lua
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
                    sourceKey = "dungeon:" .. dungeon.instanceId,
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
                    sourceKey = "boss:" .. encounter.bossId,
                })
            end
        end
    end
    return pool
end
```

Replace `matchesFilters`'s dungeon/boss check:

```lua
    if filters.dungeonName and entry.contentName ~= filters.dungeonName then
        return false
    end
    if filters.bossName and entry.bossName ~= filters.bossName then
        return false
    end
```

with:

```lua
    if filters.sources and next(filters.sources) ~= nil and not filters.sources[entry.sourceKey] then
        return false
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`.

- [ ] **Step 5: Commit**

```bash
git add Where2Go/Core/ItemBrowser.lua tests/itembrowser_spec.lua
git commit -m "feat: replace dungeonName/bossName filter with sourceKey-based multi-select"
```

---

## Task 4: `Where2Go/UI/BrowserPanel.lua` rebuild

**Depends on Tasks 1-3** (consumes `Where2GoLocale`, `Where2GoItemRow`,
and `filters.sources`/`entry.sourceKey`).

**Files:**
- Modify: `Where2Go/UI/BrowserPanel.lua` (full-file replacement — the
  restructuring touches nearly every function; a sequence of small diffs
  would risk drifting out of sync with itself across steps, so this task
  replaces the whole file in one step instead)

**Interfaces:**
- Consumes: `Where2GoLocale.L`/`SlotLabel` (Task 1), `Where2GoItemRow.CreateWidgets`/`Populate`
  (Task 2), `filters.sources`/`entry.sourceKey` (Task 3),
  `Where2GoRaidRanks.GetMythicPlusIlvl()`/`GetRaidIlvl(bossId)` (existing,
  same functions `Core/DirectDrop.lua` already uses), everything else
  unchanged from before (`Where2GoItemBrowser.FilterItems`/`SortItems`,
  `Where2GoDirectDrop.IsEligibleForSpec`/`GetItemNames`/`GetCurrentSpecIdAndName`,
  `Where2GoCharDB.preferredItems`).
- Produces: `Where2GoBrowserPanel.Toggle()` — same public signature as
  before; `Where2Go/Core/Init.lua`'s `"browse"` subcommand calls this
  unchanged, no changes needed there.

**Plan-time refinements over the spec's sketch** (both already flagged
by the spec itself as deferred pixel/behavior details, resolved here):
- Column widths concretely fixed at Results 360px / Staged 200px /
  Preferred 260px with 8px gaps and 12px margins — sums to exactly 860px
  (`12+360+8+200+8+260+12=860`), a small adjustment from the spec's
  illustrative 380/200/260 (which summed short of fitting cleanly).
- The old per-row `"[preferred]"` green-text marker in Results rows is
  dropped: the new Preferred column is now the visible answer to "what's
  preferred," so the inline marker is redundant clutter the spec's own
  "no boss-name clutter" item-row goal argues against. This is a
  deliberate UX simplification, not an oversight — flag it in code review
  if it should be reconsidered.
- `slotRow`'s vertical spacing to the row below it now uses
  `CreateToggleButtonRow`'s actual returned height (previously computed
  but discarded, replaced with a hardcoded guess) instead of a fixed `-56`
  magic number — a small correctness fix made while already rewriting
  this exact code path, not a new feature.

- [ ] **Step 1: Replace the entire file**

Replace `Where2Go/UI/BrowserPanel.lua`'s full contents with:

```lua
local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { sources = {}, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil, specId = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit
local specDropdown
local sourceDropdown

-- True once the player has explicitly picked a spec from the dropdown
-- (set inside SelectSpec below). Until then, filters.specId tracks the
-- player's actual current spec (re-derived on every panel show by
-- SyncDefaultSpec), so it follows respecs and picks up a spec chosen
-- after the panel was first created with none selected. Once the player
-- picks explicitly, that choice sticks for the rest of the session.
local userSelectedSpec = false

-- Forward declarations (same pattern UI/Panel.lua uses for `Layout`).
local RebuildFilteredResults
local RefreshStagedRows
local RefreshPreferredRows

local slotButtons = {}
local statCheckboxes = {}

local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }
local STAT_LABELS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Versatility" }

local ROW_HEIGHT = 34
local ICON_SIZE = 26
local RESULTS_WIDTH, STAGED_WIDTH, PREFERRED_WIDTH = 360, 200, 260
local VISIBLE_ROWS, STAGED_VISIBLE_ROWS, PREFERRED_VISIBLE_ROWS = 10, 10, 10

local function GetItemSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

local function GetItemEligible(itemId)
    if not filters.specId then
        return true
    end
    return Where2GoDirectDrop.IsEligibleForSpec(filters.specId)(itemId)
end

local function GetItemName(itemId)
    return Where2GoDirectDrop.GetItemNames({ itemId })[itemId]
end

-- Individual items don't carry a fixed ilvl in Sources.lua -- gear scales
-- with the player's current Mythic+/raid track, the same way
-- Core/DirectDrop.lua's BuildContentList already computes it per content.
local function GetEntryIlvl(entry)
    if entry.kind == "dungeon" then
        local ilvl = Where2GoRaidRanks.GetMythicPlusIlvl()
        return ilvl
    end
    local ilvl = Where2GoRaidRanks.GetRaidIlvl(entry.bossId)
    return ilvl
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

-- A row of mutually-exclusive toggle buttons (only one active at a time,
-- or none). `onSelect` is called with the selected value (or nil if the
-- currently-active button is clicked again, deselecting it). Returns the
-- button table and the row's actual total height (including wrapping),
-- so callers can space the next row by the real height instead of a
-- guessed constant.
local function CreateToggleButtonRow(parent, values, labelFn, onSelect, maxWidth)
    local buttons = {}
    local selectedValue = nil
    local x, y = 0, 0
    for _, value in ipairs(values) do
        if maxWidth and x + 90 > maxWidth then
            x = 0
            y = y - 24
        end
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(90, 20)
        button:SetPoint("TOPLEFT", x, y)
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
    local totalHeight = (-y) + 20
    return buttons, totalHeight
end

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
            Where2GoItemRow.Populate(row, entry.itemId, GetEntryIlvl(entry))
            row.checkbox:SetChecked(stagedSelection[entry.itemId] == true)
        elseif row then
            row:Hide()
            row.entry = nil
        end
    end
end

RebuildFilteredResults = function()
    if not itemPool then
        return
    end
    local unsorted = Where2GoItemBrowser.FilterItems(itemPool, filters, BuildContext())
    filteredResults = Where2GoItemBrowser.SortItems(unsorted, nil, BuildContext())
    ClampScrollOffset()
    RefreshVisibleRows()
    RefreshStagedRows()
end

local stagedRows = {}

RefreshStagedRows = function()
    local items = {}
    for itemId in pairs(stagedSelection) do
        table.insert(items, itemId)
    end
    table.sort(items)
    for i = 1, STAGED_VISIBLE_ROWS do
        local row = stagedRows[i]
        local itemId = items[i]
        if itemId and row then
            row:Show()
            row.itemId = itemId
            Where2GoItemRow.Populate(row, itemId, nil)
        elseif row then
            row:Hide()
            row.itemId = nil
        end
    end
end

local preferredRows = {}

RefreshPreferredRows = function()
    local items = {}
    for itemId in pairs(Where2GoCharDB.preferredItems[currentMode]) do
        table.insert(items, itemId)
    end
    table.sort(items)
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = preferredRows[i]
        local itemId = items[i]
        if itemId and row then
            row:Show()
            row.itemId = itemId
            Where2GoItemRow.Populate(row, itemId, nil)
        elseif row then
            row:Hide()
            row.itemId = nil
        end
    end
end

-- Re-derives filters.specId (and the dropdown's displayed text) from
-- the player's actual current spec. Called once at panel creation, and
-- again on every panel show (Where2GoBrowserPanel.Toggle) as long as the
-- player hasn't explicitly picked a spec from the dropdown -- see
-- userSelectedSpec above.
local function SyncDefaultSpec()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    filters.specId = specId
    if specId and specDropdown then
        UIDropDownMenu_SetText(specDropdown, specName)
    end
end

local function UpdateSourceDropdownText()
    local count = 0
    for _ in pairs(filters.sources) do
        count = count + 1
    end
    if count == 0 then
        UIDropDownMenu_SetText(sourceDropdown, Where2GoLocale.L("SOURCE_DROPDOWN_ALL"))
    else
        UIDropDownMenu_SetText(sourceDropdown, string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count))
    end
end

local function CreateBrowserPanel()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(860, 720)
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
    title:SetText(Where2GoLocale.L("BROWSER_TITLE"))

    -- Drop/Voidcore mode toggle
    local dropButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dropButton:SetSize(80, 20)
    dropButton:SetPoint("TOPLEFT", 12, -36)
    dropButton:SetText(Where2GoLocale.L("MODE_DROP"))
    local voidcoreButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    voidcoreButton:SetSize(80, 20)
    voidcoreButton:SetPoint("LEFT", dropButton, "RIGHT", 6, 0)
    voidcoreButton:SetText(Where2GoLocale.L("MODE_VOIDCORE"))
    local function SetMode(mode)
        if mode == currentMode then
            return
        end
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
        RefreshPreferredRows()
    end
    dropButton:SetScript("OnClick", function() SetMode("DROP") end)
    voidcoreButton:SetScript("OnClick", function() SetMode("VOIDCORE") end)

    -- Merged multi-select "Source" dropdown (replaces the old separate
    -- Dungeon/Boss toggle-button rows). Reuses UIDropDownMenuTemplate's
    -- native checkbox-item support (isNotRadio + keepShownOnClick) --
    -- the same dropdown mechanism this file already uses for the
    -- single-select spec dropdown below, just configured for multi-select.
    sourceDropdown = CreateFrame("Frame", "Where2GoBrowserSourceDropdown", frame, "UIDropDownMenuTemplate")
    sourceDropdown:SetPoint("LEFT", voidcoreButton, "RIGHT", 20, -2)
    UIDropDownMenu_SetWidth(sourceDropdown, 160)

    UIDropDownMenu_Initialize(sourceDropdown, function(_self, level)
        local function AddGroupHeader(text)
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.isTitle, info.notCheckable = text, true, true
            UIDropDownMenu_AddButton(info, level)
        end
        local function AddSourceOption(key, text)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = filters.sources[key] == true
            info.func = function()
                filters.sources[key] = (filters.sources[key] == true) and nil or true
                UpdateSourceDropdownText()
                RebuildFilteredResults()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        AddGroupHeader(Where2GoLocale.L("SOURCE_GROUP_DUNGEONS"))
        for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
            AddSourceOption("dungeon:" .. dungeon.instanceId, dungeon.name)
        end
        for _, raid in ipairs(Where2GoSources.RAIDS) do
            AddGroupHeader(raid.name)
            for _, encounter in ipairs(raid.encounters) do
                AddSourceOption("boss:" .. encounter.bossId, encounter.name)
            end
        end
    end)
    UpdateSourceDropdownText()

    -- Slot row
    local slotRow = CreateFrame("Frame", nil, frame)
    slotRow:SetPoint("TOPLEFT", 12, -72)
    slotRow:SetSize(836, 20)
    local slotRowHeight
    slotButtons, slotRowHeight = CreateToggleButtonRow(slotRow, SLOT_ORDER, Where2GoLocale.SlotLabel, function(selected)
        filters.slot = selected
        RebuildFilteredResults()
    end, 820)

    -- Stat checkbox row (multi-select)
    local statRow = CreateFrame("Frame", nil, frame)
    statRow:SetPoint("TOPLEFT", slotRow, "BOTTOMLEFT", 0, -(slotRowHeight + 10))
    statRow:SetSize(836, 20)
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

    -- Spec-eligible-only checkbox, paired with the spec selector dropdown
    -- directly next to it (moved here from its old spot near the mode
    -- toggle, per the locked-in "these two controls work as a pair"
    -- decision).
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("TOPLEFT", statRow, "BOTTOMLEFT", 0, -26)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText(Where2GoLocale.L("ELIGIBLE_ONLY"))
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

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

    specDropdown = CreateFrame("Frame", "Where2GoBrowserSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("LEFT", eligibleLabel, "RIGHT", 12, -2)
    UIDropDownMenu_SetWidth(specDropdown, 130)

    local function SelectSpec(specId, specName)
        userSelectedSpec = true
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

    SyncDefaultSpec()

    -- Search box
    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", eligibleCheckbox, "BOTTOMLEFT", 4, -26)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        filters.searchText = self:GetText()
        RebuildFilteredResults()
    end)

    -- Three-column list area: Results | Staged | Preferred
    local resultsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultsHeader:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -16)
    resultsHeader:SetText(Where2GoLocale.L("RESULTS_HEADER"))

    local stagedHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stagedHeader:SetPoint("TOPLEFT", resultsHeader, "TOPLEFT", RESULTS_WIDTH + 8, 0)
    stagedHeader:SetText(Where2GoLocale.L("STAGED_HEADER"))

    local preferredHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preferredHeader:SetPoint("TOPLEFT", stagedHeader, "TOPLEFT", STAGED_WIDTH + 8, 0)
    preferredHeader:SetText(Where2GoLocale.L("PREFERRED_HEADER"))

    local listHeight = VISIBLE_ROWS * ROW_HEIGHT

    local resultsFrame = CreateFrame("Frame", nil, frame)
    resultsFrame:SetPoint("TOPLEFT", resultsHeader, "BOTTOMLEFT", 4, -6)
    resultsFrame:SetSize(RESULTS_WIDTH, listHeight)
    resultsFrame:EnableMouseWheel(true)
    resultsFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollOffset = scrollOffset - delta
        ClampScrollOffset()
        RefreshVisibleRows()
    end)

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, resultsFrame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)

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
                RefreshStagedRows()
            end
        end)

        Where2GoItemRow.CreateWidgets(row, ICON_SIZE, 24)
        row.name:SetWidth(RESULTS_WIDTH - 24 - ICON_SIZE - 8)
        row.summary:SetWidth(RESULTS_WIDTH - 24 - ICON_SIZE - 8)

        row.checkbox = checkbox
        resultRows[i] = row
    end

    local function CreateSideListRow(parent, width, onRemove)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_HEIGHT)

        local removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        removeButton:SetSize(16, 16)
        removeButton:SetPoint("RIGHT", 0, 0)
        removeButton:SetScript("OnClick", function()
            if row.itemId then
                onRemove(row.itemId)
            end
        end)

        Where2GoItemRow.CreateWidgets(row, ICON_SIZE, 0)
        row.name:SetWidth(width - ICON_SIZE - 16 - 8)
        row.summary:SetWidth(width - ICON_SIZE - 16 - 8)
        return row
    end

    local stagedFrame = CreateFrame("Frame", nil, frame)
    stagedFrame:SetPoint("TOPLEFT", stagedHeader, "BOTTOMLEFT", 0, -6)
    stagedFrame:SetSize(STAGED_WIDTH, listHeight)
    for i = 1, STAGED_VISIBLE_ROWS do
        local row = CreateSideListRow(stagedFrame, STAGED_WIDTH, function(itemId)
            stagedSelection[itemId] = nil
            RefreshStagedRows()
            RefreshVisibleRows()
        end)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", stagedFrame, "RIGHT", 0, 0)
        stagedRows[i] = row
    end

    local preferredFrame = CreateFrame("Frame", nil, frame)
    preferredFrame:SetPoint("TOPLEFT", preferredHeader, "BOTTOMLEFT", 0, -6)
    preferredFrame:SetSize(PREFERRED_WIDTH, listHeight)
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = CreateSideListRow(preferredFrame, PREFERRED_WIDTH, function(itemId)
            Where2GoCharDB.preferredItems[currentMode][itemId] = nil
            RefreshPreferredRows()
        end)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", preferredFrame, "RIGHT", 0, 0)
        preferredRows[i] = row
    end

    local addSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSelectedButton:SetSize(140, 22)
    addSelectedButton:SetPoint("TOPLEFT", stagedFrame, "BOTTOMLEFT", 0, -12)
    addSelectedButton:SetText(Where2GoLocale.L("ADD_SELECTED"))
    addSelectedButton:SetScript("OnClick", function()
        for itemId in pairs(stagedSelection) do
            Where2GoCharDB.preferredItems[currentMode][itemId] = true
        end
        stagedSelection = {}
        RebuildFilteredResults()
        RefreshPreferredRows()
    end)

    local clearSelectionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearSelectionButton:SetSize(140, 22)
    clearSelectionButton:SetPoint("TOPLEFT", addSelectedButton, "BOTTOMLEFT", 0, -6)
    clearSelectionButton:SetText(Where2GoLocale.L("CLEAR_SELECTION"))
    clearSelectionButton:SetScript("OnClick", function()
        stagedSelection = {}
        RefreshStagedRows()
        RefreshVisibleRows()
    end)

    local clearAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearAllButton:SetSize(140, 22)
    clearAllButton:SetPoint("TOPLEFT", preferredFrame, "BOTTOMLEFT", 0, -12)
    clearAllButton:SetText(Where2GoLocale.L("CLEAR_ALL"))
    clearAllButton:SetScript("OnClick", function()
        StaticPopup_Show("WHERE2GO_CLEAR_PREFERRED")
    end)

    frame.searchBox = searchBox
    SetMode("DROP")
    frame:Hide()
    return frame
end

StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"] = {
    text = Where2GoLocale.L("CLEAR_PREFERRED_CONFIRM"),
    button1 = Where2GoLocale.L("CLEAR_BUTTON"),
    button2 = Where2GoLocale.L("CANCEL_BUTTON"),
    OnAccept = function()
        Where2GoCharDB.preferredItems[currentMode] = {}
        RebuildFilteredResults()
        RefreshPreferredRows()
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
        if not userSelectedSpec then
            SyncDefaultSpec()
        end
        RebuildFilteredResults()
        RefreshPreferredRows()
        browserFrame:Show()
    end
end
```

- [ ] **Step 2: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]` (`toc_spec.lua` confirms the file still parses —
this file has no dedicated unit test, WoW-API-dependent, verified live in
Task 6).

- [ ] **Step 3: Commit**

```bash
git add Where2Go/UI/BrowserPanel.lua
git commit -m "feat: rebuild item browser with Source dropdown, locale, and Staged/Preferred columns"
```

---

## Task 5: `Where2Go/UI/Panel.lua` — item row treatment

**Depends on Task 2** (consumes `Where2GoItemRow`).

**Files:**
- Modify: `Where2Go/UI/Panel.lua`

**Interfaces:**
- Consumes: `Where2GoItemRow.CreateWidgets`/`Populate` (Task 2).
- Produces: no change to `Where2Go_TogglePanel`'s public behavior — card
  expand/collapse, tabs, and `Layout` are untouched; only `CreateCard`'s
  per-item rows change shape internally.

- [ ] **Step 1: Replace `CreateCard`'s item-row construction**

In `Where2Go/UI/Panel.lua`, replace:

```lua
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
```

with:

```lua
    local ITEM_ROW_HEIGHT = 32
    local ITEM_ICON_SIZE = 24
    local ITEM_ROW_WIDTH = 324

    local itemRows = {}
    local rowY = -18
    for _, itemId in ipairs(result.targetItemIds) do
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetSize(ITEM_ROW_WIDTH, ITEM_ROW_HEIGHT)
        Where2GoItemRow.CreateWidgets(row, ITEM_ICON_SIZE, 0)
        row.name:SetWidth(ITEM_ROW_WIDTH - ITEM_ICON_SIZE - 4)
        row.summary:SetWidth(ITEM_ROW_WIDTH - ITEM_ICON_SIZE - 4)
        Where2GoItemRow.Populate(row, itemId, result.ilvl)
        table.insert(itemRows, row)
        rowY = rowY - ITEM_ROW_HEIGHT
    end

    local cardData = {
        frame = card,
        expanded = true,
        collapsedHeight = 18,
        expandedHeight = 18 + (#itemRows * ITEM_ROW_HEIGHT),
    }
```

`itemRows` entries are now `Frame`s instead of `FontString`s — the
existing `header:SetScript("OnClick", ...)` handler below this block
already only calls `row:Show()`/`row:Hide()` on each, which both widget
types support identically, so that handler needs no change.

- [ ] **Step 2: Run the full suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/UI/Panel.lua
git commit -m "feat: apply shared item-row treatment to recommendation panel cards"
```

---

## Task 6: Manual live verification

**Files:** none — this task runs the built addon in a live WoW client.
No code changes.

- [ ] **Step 1: Load the addon in-game and open the item browser**

Run `/where2go browse`. Confirm:
- Window is wider (~860px) with three visible columns: Results, Staged,
  Preferred, each with its own header.
- The old separate Dungeon/Boss button rows are gone, replaced by a
  single "Source" dropdown.
- Opening the Source dropdown shows a "Dungeons" group listing every
  dungeon, then one group per raid listing that raid's bosses, each with
  a checkbox (not a radio dot).
- Selecting multiple entries (e.g. two dungeons, or a dungeon and a raid
  boss) keeps the dropdown open on each click and narrows the Results
  list to the union of selected sources; the dropdown's own button text
  updates to "All Sources" / "N selected" correctly.
- Slot filter buttons show friendly names ("Head", "Trinket", etc.), not
  raw ids.
- The spec dropdown sits directly next to the "eligible only" checkbox.

- [ ] **Step 2: Verify item rows**

For a Results row, a Staged row (after checking a box), and a Preferred
row (after "Add selected"): confirm each shows an icon, a
quality-colored name, and an `ilvl · stat` summary line; hovering shows
the real Blizzard item tooltip (not a custom one); the Staged/Preferred
`×` buttons remove just that one item without affecting the others.

- [ ] **Step 3: Verify localization**

If possible, test with a koKR client (or temporarily hardcode
`activeLocale = "koKR"` in `Locale.lua` for this check only, then revert):
confirm every label defined in `Where2GoLocale.STRINGS`/`SLOT_LABELS`
shows Korean text, while item names/tooltips and dungeon/boss names stay
in whatever language the client is actually set to (unaffected by this
override).

- [ ] **Step 4: Verify the Recommendation panel**

Run `/where2go` (or `/w2g`). Confirm the existing card/expand-collapse
behavior is unchanged, and expanded cards now show the same
icon+quality-name+summary item rows as the browser (with real tooltips
on hover), sized correctly within each card without overlapping the next
card.

- [ ] **Step 5: Run the full suite one final time**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all `[PASS]`.
