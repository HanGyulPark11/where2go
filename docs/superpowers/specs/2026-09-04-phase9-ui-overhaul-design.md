# Phase 9: Item Browser / Recommendation Panel UI Overhaul — Design

**Status:** Approved design. Brainstormed and mockup-reviewed across several
rounds in an earlier session (visual reference:
https://claude.ai/code/artifact/0a2ea709-aa66-4e83-927d-df27f939fb14 — two
artboards, Item Browser and Recommendation Panel, styled in WoW's own UI
vocabulary). This doc locks in the visual/UX decisions already confirmed by
the user and resolves the remaining open implementation details (dropdown
mechanism, locale table, icon/tooltip APIs, layout numbers) so it's ready
for an implementation plan.

## Problem

`Where2Go/UI/Panel.lua` and `Where2Go/UI/BrowserPanel.lua` are plain
dev-verification-quality `CreateFrame` UIs — functional (every prior phase
built and tested through them) but never given a real user-facing design
pass: raw slot-id labels (`"HEAD"`, `"NECK"`), item rows that are bare text
lines with no icon or quality color, a "preferred items" list that's only
ever visible as scattered checkmarks (no way to review what's actually
saved without re-browsing), separate Dungeon/Boss filter rows that force
two clicks for something players think of as one unit ("run this dungeon"),
and zero localization even though the addon has koKR-speaking users. This
phase is a real user-facing pass on both windows, scoped down from a full
redesign to what the mockup rounds actually converged on.

## Scope recap: decisions locked in (do not re-litigate)

Confirmed across multiple mockup feedback rounds in the brainstorming
session; restated here only as context for the Design section below, which
is the actual source of truth for implementation.

1. **Localization**: no manual toggle. Detect `GetLocale()` once and match
   only the addon's own UI chrome (labels, buttons, headers) to it. Item
   names and the real Blizzard tooltip already match the client's language
   automatically and are explicitly not fought with a custom
   implementation. Dungeon/boss names (`Sources.lua`, addon-owned data)
   stay English-only — translating those is data-prep work, out of scope
   here (see Non-goals).
2. **Real tooltip, not custom**: hovering an item row shows the actual
   `GameTooltip`, not a hand-drawn one — chosen over a custom tooltip even
   though a custom one could in principle be independently localized.
3. **Filter model**: the item browser's separate Dungeon and Boss
   toggle-button rows merge into one multi-select "Source" dropdown listing
   every dungeon (as one whole-run unit) and every raid boss (individually,
   since raids are progressed boss-by-boss). Empty selection = no filter.
4. **Item row treatment** (both windows): icon + quality-colored name +
   compact `ilvl · secondary-stat` summary line, no boss-name clutter.
5. **Staged vs. Preferred are two separate, visible side-by-side panels**
   in the item browser — Staged (transient checkbox selections) and
   Preferred (the actually-saved list, previously invisible except via a
   blunt "clear everything" button) both get their own per-item list with
   per-item removal.
6. **Spec selector** moves to sit directly next to the "eligible only"
   checkbox (previously visually disconnected, up near the mode toggle).
7. **Recommendation panel** (`Panel.lua`) gets the smallest-scope
   treatment: keep its existing card/expand-collapse structure entirely
   unchanged, only upgrade the expanded item list's rows to the same
   icon+quality-name+summary treatment as the browser. It stays a compact
   "what to go get right now" panel, not a dashboard.

## Design

### 1. Locale table (`Where2Go/Core/Locale.lua`, new)

A small static table, following this project's existing
`Where2GoConstants`-style module convention (plain Lua table, no external
tooling):

```lua
Where2GoLocale = {}

local STRINGS = {
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
        SEARCH_PLACEHOLDER = "Search...",
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
        SEARCH_PLACEHOLDER = "검색...",
    },
}

local SLOT_LABELS = {
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

local activeLocale = (GetLocale() == "koKR") and "koKR" or "enUS"

-- Falls back to enUS for any key missing in the active table (keeps every
-- locale table safe to extend independently -- a missing koKR translation
-- never shows a blank string, just the English one).
function Where2GoLocale.L(key)
    return STRINGS[activeLocale][key] or STRINGS.enUS[key] or key
end

function Where2GoLocale.SlotLabel(slot)
    return SLOT_LABELS[activeLocale][slot] or SLOT_LABELS.enUS[slot] or slot
end
```

Both UI files replace their hardcoded English strings with `Where2GoLocale.L("KEY")`
calls, and `Where2Go/UI/BrowserPanel.lua`'s slot-button row (currently
labeling buttons with the raw `SLOT_ORDER` id like `"HEAD"`) switches to
`Where2GoLocale.SlotLabel(slot)`. Item names, tooltips, and dungeon/boss
names are untouched — they're not addon-controlled strings (item
names/tooltips) or explicitly out of scope (dungeon/boss names).

`Where2Go/Where2Go.toc`: add `Core\Locale.lua` after `Core\Constants.lua`
(first file, per `tests/toc_spec.lua`'s load-order assertion) and before
any file that references `Where2GoLocale`.

### 2. Merged multi-select "Source" dropdown

Replaces `BrowserPanel.lua`'s current `dungeonRow`/`bossRow`
(`CreateToggleButtonRow` pair, single-select each) entirely. Reuses the
exact mechanism this project already uses for the (single-select) spec
dropdown — `UIDropDownMenuTemplate` — since Blizzard's own dropdown
framework supports checkbox-style multi-select items natively via
`UIDropDownMenu_CreateInfo()`'s `isNotRadio`/`keepShownOnClick` fields; no
custom popup frame needed.

**Filter identity**: `Where2GoItemBrowser.BuildItemPool()`'s pool entries
gain a `sourceKey` field, reusing the exact id scheme
`Where2GoDirectDrop.BuildContentList()` already uses (`"dungeon:"..instanceId`,
`"boss:"..bossId`) so the two modules share one naming convention instead
of inventing a second one:

```lua
-- Where2GoItemBrowser.BuildItemPool(), each entry gains:
sourceKey = "dungeon:" .. dungeon.instanceId,  -- dungeon entries
sourceKey = "boss:" .. encounter.bossId,       -- raid entries
```

**Filter state**: `filters.sources = { [sourceKey] = true, ... }` (replaces
`filters.dungeonName`/`filters.bossName`). Empty/nil table = no filter,
matching every other multi-select filter this module already has
(`filters.stats`).

**`Where2GoItemBrowser.lua`'s `matchesFilters`**: replace the
`dungeonName`/`bossName` checks with:

```lua
if filters.sources and next(filters.sources) ~= nil and not filters.sources[entry.sourceKey] then
    return false
end
```

**Dropdown UI** (`BrowserPanel.lua`): one `UIDropDownMenuTemplate` frame
positioned where the old dungeon/boss rows were. `UIDropDownMenu_Initialize`
builds one non-clickable header entry per group
(`info.isTitle = true`, text = `Where2GoLocale.L("SOURCE_GROUP_DUNGEONS")`
then each raid's own name from `Where2GoSources.RAIDS`) followed by that
group's selectable entries:

```lua
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
```

Dropdown button text: `Where2GoLocale.L("SOURCE_DROPDOWN_ALL")` when
`filters.sources` is empty, else `string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count)`.
Consequence of the merge (already accepted): result rows no longer show
which specific boss within a dungeon drops an item (dungeons are a
whole-run unit); raid items keep their boss attribution via the existing
`raidName`/`bossName` fields, used only for the row's tooltip/summary line,
not as a filter dimension anymore.

### 3. Item row treatment (shared by both windows)

A new small shared helper, since both `BrowserPanel.lua`'s result/Staged/
Preferred rows and `Panel.lua`'s expanded card item rows need the identical
icon+quality-name+summary treatment:

**New file: `Where2Go/UI/ItemRow.lua`** — one function,
`Where2GoItemRow.Populate(row, itemId, ilvl)`, that a caller invokes on a
row frame built with a fixed sub-widget layout (`row.icon`, `row.name`,
`row.summary` — a texture and two font strings, created once per pooled
row the same way `BrowserPanel.lua` already pools its result rows).

```lua
Where2GoItemRow = {}

-- Builds the icon+name+summary sub-widgets on a fresh row frame. Callers
-- create one row per pool slot (matching this project's existing
-- pooled-row pattern in BrowserPanel.lua) and call this once at creation.
function Where2GoItemRow.CreateWidgets(row, iconSize)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", 0, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 6)
    row.name:SetJustifyH("LEFT")

    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.summary:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.summary:SetJustifyH("LEFT")
end

-- Fills an already-built row's widgets for one item. `ilvl` is the
-- caller-computed effective item level for this item's source (dungeon
-- Mythic+ track or raid boss track -- see callers), since individual
-- items don't carry a fixed ilvl in Sources.lua (gear scales with the
-- player's current track). Handles the cold-item-cache case the same way
-- GetItemNames already does elsewhere in this project: shows a
-- placeholder, self-heals on the next RebuildFilteredResults triggered by
-- GET_ITEM_INFO_RECEIVED.
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
    row.summary:SetText(ilvl and (ilvl .. (statText ~= "" and (" · " .. statText) or "")) or statText)

    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemId)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:EnableMouse(true)
end

Where2GoItemRow.STAT_ABBREV = {
    CRIT_RATING = "Crit", HASTE_RATING = "Haste",
    MASTERY_RATING = "Mastery", VERSATILITY = "Vers",
}
```

`ITEM_QUALITY_COLORS` is a real Blizzard global (`{hex = "|cffxxxxxx", ...}`
per quality index) — no addon-side color table needed, matching "WoW's
standard item-quality colors" from the locked-in decision.

**ilvl per entry**: callers compute it via the same functions
`Where2GoDirectDrop.BuildContentList()` already uses —
`Where2GoRaidRanks.GetMythicPlusIlvl()` for `kind == "dungeon"` pool
entries, `Where2GoRaidRanks.GetRaidIlvl(bossId)` for `kind == "raid"`
entries — so the row shows the item's actual effective level at the
player's current track, not a static number.

`Where2Go/Where2Go.toc`: add `UI\ItemRow.lua` before `UI\Panel.lua` and
`UI\BrowserPanel.lua` (both consume it).

### 4. Item browser layout: Results | Staged | Preferred

Window widens from the current 700px to **860px** (mockup's own width),
height stays 720px. Three side-by-side list columns replace the single
results list, left to right:

| Column | Width | Purpose |
|---|---|---|
| Results | 380px | `Where2GoItemBrowser.FilterItems`/`SortItems` output, unchanged filtering logic — checkbox + item row (icon/name/summary) per entry, same pooled-row pattern as today |
| Staged | 200px | Live view of `stagedSelection` (existing table, unchanged semantics) — one row per staged item, item row treatment, a `×` button per row that clears that one entry from `stagedSelection` and unchecks its Results row if visible |
| Preferred | 260px (roomier, per mockup) | **New.** Live view of `Where2GoCharDB.preferredItems[currentMode]` — one row per preferred item, item row treatment, a `×` button per row that removes just that item (`Where2GoCharDB.preferredItems[currentMode][itemId] = nil`) |

Both Staged and Preferred rebuild their visible rows whenever they could
have changed: Staged on every checkbox click and on "Clear selection"/"Add
selected"; Preferred on "Add selected", every per-item `×`, and "Clear
All". Both are small pooled-row lists (bounded by how many items a player
realistically stages/prefers at once — no scroll region needed at typical
list sizes; if either list's row count exceeds its visible height, reuse
the same `EnableMouseWheel`/`ClampScrollOffset` pattern the Results column
already has).

**"Clear preferred list" → "Clear All"**: same destructive-confirmation
`StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"]` stays (bulk-wipe still
warrants a confirm), relabeled via `Where2GoLocale.L("CLEAR_ALL")`. Per-item
`×` removal needs no confirmation, matching this project's existing
`/where2go pref remove` command (single-item removal is already
uncomfirmed there).

### 5. Spec selector relocation

`specDropdown` (existing `UIDropDownMenuTemplate`, unchanged internals)
moves from its current anchor (next to the Voidcore mode button) to sit
directly `LEFT`-anchored next to the "eligible only" checkbox, per the
locked-in decision that the two controls work as a pair. Purely a
`SetPoint` change plus reordering the row it's created in — no behavior
change.

### 6. Recommendation panel (`Panel.lua`)

Smallest-scope change: `CreateCard`'s per-item rows (currently a bare
`FontString` per `itemId` in `result.targetItemIds`) switch to pooled row
frames using `Where2GoItemRow.CreateWidgets`/`Populate`, same treatment as
the browser. `ilvl` for `Populate` is the card's own already-computed
`result.ilvl` (every item in a `DirectDrop`/`VoidcoreDrop` card already
shares one content-level ilvl, unlike the browser's per-entry lookup).
Card height math (`collapsedHeight`/`expandedHeight` in `CreateCard`)
updates from `14`px per single-line row to whatever the icon+name+summary
two-line row's actual height is (`iconSize` + row padding — a fixed
constant, not computed). Nothing else in `Panel.lua` changes: card
expand/collapse, `BuildHeaderText`, `Layout`, and the Drop/Voidcore tabs
are all untouched.

## Non-goals (explicitly out of scope for this phase)

- Translating dungeon/boss names (`Sources.lua`) into Korean. Real future
  work (Battle.net API's `locale=ko_KR` param, a data-prep script change),
  not scoped here — this phase only localizes the addon's own UI chrome
  and slot labels.
- A custom tooltip implementation — explicitly rejected in favor of the
  real `GameTooltip`.
- Any staging/preferred-list UI on the Recommendation panel — it stays a
  purely read-only ranked view.
- Scroll regions for the Staged/Preferred columns beyond reusing the
  existing mousewheel pattern if a list ever overflows its height — no new
  scrollbar widget/visual polish beyond that.
- Changing `Where2GoItemBrowser.lua`'s pure filter/sort logic beyond the
  `dungeonName`/`bossName` → `sourceKey` swap — everything else
  (slot/stat/eligible/search filtering) is unchanged.

## Testing

- `Where2GoItemBrowser.lua`'s `matchesFilters` `sourceKey` logic: pure,
  extends the existing (implicit, via `FilterItems`) test coverage —
  `tests/itembrowser_spec.lua` gets new fixture cases: empty
  `filters.sources` (no filter, matches everything), one dungeon key
  selected, one boss key selected, multiple keys across dungeons and raids
  at once.
- `Where2GoItemBrowser.BuildItemPool()`'s new `sourceKey` field: extend
  the existing pool-shape assertions in `tests/itembrowser_spec.lua` to
  check every entry's `sourceKey` matches the `"dungeon:"`/`"boss:"`
  pattern and, for a sample entry, the exact expected key.
- `Where2GoLocale.lua`: pure, unit-testable — `tests/locale_spec.lua`
  asserts `Where2GoLocale.L`/`SlotLabel` fall through to `enUS` for a key
  present only there, and that every key present in `enUS` also has a
  koKR counterpart (a coverage test, same pattern as `ItemStats.lua`'s
  `Sources.lua`-coverage check — catches a forgotten translation, not a
  missing feature). `GetLocale()` itself is a WoW API stub for this test
  (not called — `activeLocale` is computed at module load time from a
  live API, so the test only exercises the string tables and the fallback
  logic directly, not locale detection).
- `Where2GoItemRow.lua`: `Populate`'s icon/name/tooltip logic is
  WoW-API-dependent (`C_Item.GetItemInfo`, `GameTooltip`) — not
  unit-tested, verified live, matching this project's existing convention
  for WoW-API-touching code. The stat-abbreviation lookup
  (`STAT_ABBREV`) is a static table, no logic to test.
- `BrowserPanel.lua`/`Panel.lua` layout and dropdown wiring: WoW-API-
  dependent (`CreateFrame`, `UIDropDownMenu_*`) — verified live, same as
  every prior UI-file change in this project.

## Why this stays one phase, not split into sub-projects

The browser overhaul (dropdown, three-column layout, locale, item rows)
and the Recommendation panel's item-row upgrade share one new module
(`ItemRow.lua`) and one new module (`Locale.lua`), and the mockup/decision
round already treated both windows as one coherent visual pass. Splitting
into two specs would just duplicate the shared-module description twice.
The implementation plan can still sequence them as separable tasks
(`Locale.lua` → `ItemRow.lua` → browser dropdown/columns → Recommendation
panel row swap), the way Phase 6 split sub-projects within one plan.
