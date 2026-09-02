# Phase 2: Preferred Items & Equipment Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a player register preferred item IDs per character and per
purpose (direct-drop vs. Voidcore), and compare a real instance of one
against currently-equipped gear by upgrade track first, then item level —
matching `docs/DEVELOPMENT_PLAN.md` Phase 2's acceptance check (deterministic
comparison-rule tests, plus a live-client check that a higher-track
candidate is correctly flagged).

**Architecture:** Same pure/WoW-API split as Phase 1. `Core/Tracks.lua`
(new) and the `Core/Compare.lua` (new) module are pure Lua — no WoW API,
real unit tests. `Core/Equipment.lua` (new) and the extended `Core/Init.lua`
read real game state (`CreateFrame`, `GetInventoryItemLink`,
`C_Item.GetDetailedItemLevelInfo`, `C_Container.*`) and are verified live
in-client, same as Phase 1's `Init.lua`/`Panel.lua`.

**Tech Stack:** Plain FrameXML/Lua, no Ace3, no vendored libraries (unchanged
from Phase 1). Lua 5.1 via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"`
as the local test runtime.

**Spec:** `docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md`

## Global Constraints

- `Core/Tracks.lua` and `Core/Compare.lua` must never reference WoW API
  globals — that's what keeps them testable with a standalone `lua5.1`
  interpreter.
- Track-comparison semantics (from the spec, do not deviate): if both sides
  have a recognized track and the orders differ, the **higher order wins
  outright — item level is not consulted at all** in that case. Only when
  both sides share a track order, or either side lacks a recognized track,
  does the comparison fall back to a strict item-level comparison.
- Purpose keys are exactly the strings `"DROP"` and `"VOIDCORE"` (uppercase)
  everywhere — `Where2GoCharDB.preferredItems.DROP` /
  `.preferredItems.VOIDCORE`. Preferred-item sets are keyed by item ID with
  a `true` value (`preferredItems.DROP[271483] = true`), not an array — use
  `next(t) == nil` to test emptiness, never `#t`.
- `docs/DECISIONS.md`'s ownership rule: comparisons are always based on the
  real, current instance's bonus IDs — never on "have I ever owned this
  item ID before." No new task in this plan introduces an ownership-history
  table; if you find yourself adding one, stop, that's out of scope (Phase 3/4).
- Tests run via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
  from the repository root. Lua's `assert()`/`error()` prepend a
  `file:line:` prefix to string error messages — expected, not a bug.
- Source code, comments, and commit messages are English. Player-facing
  chat output (the `/where2go compare` lines) may be English too here —
  Phase 1's Korean raid/boss names came from a verified in-game source;
  the upgrade-track *labels* ported alongside the empirically-measured
  bonus-ID/ilvl numbers were informal, unverified translations in the
  source branch, so this plan uses English track labels (`"Veteran"`,
  `"Champion"`, `"Hero"`, `"Myth"`) instead of carrying over unverified
  Korean guesses. Revisit with proper localization once there's a
  verification path (same Blizzard API method as `wiki/wow-glossary.md`).
- `tests/toc_spec.lua` (built in Phase 1) checks both directions: every TOC
  entry must exist on disk, and every `.lua` file on disk under
  `Where2Go/Core`/`Where2Go/UI` must appear in the TOC. Every task that adds
  a new file must add its TOC line **in the same task**, or the suite goes
  red for a reason unrelated to that task's own logic.

---

## File Structure

```
Where2Go/
├── Where2Go.toc                  MODIFY: insert Core\Tracks.lua (Task 1),
│                                  Core\Compare.lua (Task 2), Core\Equipment.lua (Task 4)
├── Core/
│   ├── Constants.lua              MODIFY (Task 3): add SLOT_TO_INVSLOT,
│   │                              FINGER_SLOTS, TRINKET_SLOTS,
│   │                              EQUIPLOC_TO_SLOT; change BuildDefaultCharDB
│   ├── Tracks.lua                 CREATE (Task 1): UPGRADE_TRACKS (pure data)
│   ├── Fixtures.lua                unchanged
│   ├── Compare.lua                 CREATE (Task 2): IsBetterCandidate (pure)
│   ├── Equipment.lua               CREATE (Task 4): bonus-ID parsing, track
│   │                              detection, equipped/bag item lookup
│   └── Init.lua                    MODIFY (Task 5): `/where2go pref ...`
│                                  and `/where2go compare` subcommands
└── UI/
    └── Panel.lua                   unchanged

tests/
├── run_tests.lua                   MODIFY: append tracks_spec, compare_spec
├── tracks_spec.lua                 CREATE (Task 1)
├── compare_spec.lua                CREATE (Task 2)
├── constants_spec.lua              MODIFY (Task 3)
├── fixtures_spec.lua                unchanged
└── toc_spec.lua                     unchanged (already checks both directions)
```

---

### Task 1: Core/Tracks.lua

**Files:**
- Create: `Where2Go/Core/Tracks.lua`
- Test: `tests/tracks_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/tracks_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\Tracks.lua` right after
  `Core\Constants.lua`, before `Core\Fixtures.lua`)

**Interfaces:**
- Consumes: nothing.
- Produces: global table `Where2GoTracks.UPGRADE_TRACKS` with keys
  `VETERAN`, `CHAMPION`, `HERO`, `MYTH`, each
  `{ order = 1|2|3|4, label = string, bonusIdStart = number, ilvls = {6 numbers, strictly increasing} }`.
  `Core/Equipment.lua` (Task 4) reads this to classify real items by bonus ID.

- [ ] **Step 1: Write the failing test**

`tests/tracks_spec.lua`:
```lua
dofile("Where2Go/Core/Tracks.lua")

local expectedOrder = { VETERAN = 1, CHAMPION = 2, HERO = 3, MYTH = 4 }

local seenOrders = {}
for key, expectedOrderValue in pairs(expectedOrder) do
    local track = Where2GoTracks.UPGRADE_TRACKS[key]
    assert(type(track) == "table", key .. " should exist in UPGRADE_TRACKS")
    assert(track.order == expectedOrderValue, key .. ".order should be " .. expectedOrderValue)
    assert(type(track.label) == "string" and #track.label > 0, key .. ".label should be a non-empty string")
    assert(type(track.bonusIdStart) == "number" and track.bonusIdStart > 0 and track.bonusIdStart % 1 == 0,
        key .. ".bonusIdStart should be a positive integer")
    assert(type(track.ilvls) == "table" and #track.ilvls == 6, key .. ".ilvls should have exactly 6 entries")
    for i = 2, 6 do
        assert(track.ilvls[i] > track.ilvls[i - 1], key .. ".ilvls should be strictly increasing")
    end
    assert(not seenOrders[track.order], "duplicate order value: " .. track.order)
    seenOrders[track.order] = true
end

print("tracks_spec: OK, 4 track(s) verified")
```

- [ ] **Step 2: Update the harness**

In `tests/run_tests.lua`, add `"tests/tracks_spec.lua"` to the `specs` list
(append after the existing entries, before the closing `}`).

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/tracks_spec.lua: ...` (file doesn't exist yet).

- [ ] **Step 4: Implement Tracks.lua**

`Where2Go/Core/Tracks.lua`:
```lua
-- Season 2 (Midnight patch 12.1) upgrade-track bonus IDs and per-rank item
-- levels. Ported from the pre-restart implementation
-- (codex/pre-restart-backup branch, Core/Constants.lua's UPGRADE_TRACKS) as
-- empirically measured game fact -- confirmed in-client via
-- /where2go scanbonus against real items, same Interface: 120100, same-day
-- commit. See docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md
-- for full provenance.
--
-- Each track is exactly 6 consecutive bonus IDs (rank 1/6 through 6/6). A
-- track's rank 5-6 item level deliberately overlaps the next track's rank
-- 1-2 (smooth catch-up by design, not a measurement error) -- see
-- Core/Compare.lua for why track order is compared before item level.

Where2GoTracks = {}

Where2GoTracks.UPGRADE_TRACKS = {
    VETERAN = { order = 1, label = "Veteran", bonusIdStart = 12825, ilvls = { 279, 282, 285, 289, 292, 295 } },
    CHAMPION = { order = 2, label = "Champion", bonusIdStart = 12833, ilvls = { 292, 295, 298, 302, 305, 308 } },
    HERO = { order = 3, label = "Hero", bonusIdStart = 12841, ilvls = { 305, 308, 311, 315, 318, 321 } },
    MYTH = { order = 4, label = "Myth", bonusIdStart = 12849, ilvls = { 318, 321, 324, 328, 331, 334 } },
}
```

- [ ] **Step 5: Update the manifest**

In `Where2Go/Where2Go.toc`, insert a new line `Core\Tracks.lua` immediately
after `Core\Constants.lua` and before `Core\Fixtures.lua`. The file list
section should read:
```
Core\Constants.lua
Core\Tracks.lua
Core\Fixtures.lua
Core\Init.lua
UI\Panel.lua
```

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]`, including `tracks_spec` and `toc_spec` (the
TOC now references 5 files, all of which exist — `toc_spec`'s completeness
sweep also passes since `Tracks.lua` is both on disk and in the TOC).
Exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/Tracks.lua tests/tracks_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: add Season 2 upgrade-track data"
```

---

### Task 2: Core/Compare.lua

**Files:**
- Create: `Where2Go/Core/Compare.lua`
- Test: `tests/compare_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/compare_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\Compare.lua` right after
  `Core\Fixtures.lua`, before `Core\Init.lua`)

**Interfaces:**
- Consumes: nothing (deliberately zero dependencies — takes plain tables).
- Produces: global function
  `Where2GoCompare.IsBetterCandidate(candidate, equipped)` where both
  arguments are `{ track = {order=number} or nil, ilvl = number or nil }`,
  returning a boolean. `Core/Equipment.lua` (Task 4) and `Core/Init.lua`
  (Task 5) call this.

- [ ] **Step 1: Write the failing test**

`tests/compare_spec.lua`:
```lua
dofile("Where2Go/Core/Compare.lua")

local HERO = { order = 3 }
local MYTH = { order = 4 }

-- Same track, higher ilvl wins.
assert(Where2GoCompare.IsBetterCandidate(
    { track = HERO, ilvl = 315 },
    { track = HERO, ilvl = 308 }
) == true, "same track, higher ilvl should be better")

-- Same track, equal ilvl is not an upgrade.
assert(Where2GoCompare.IsBetterCandidate(
    { track = HERO, ilvl = 308 },
    { track = HERO, ilvl = 308 }
) == false, "same track, equal ilvl should not be better")

-- Higher track wins despite a lower nominal ilvl (tracks overlap by design --
-- see Core/Tracks.lua's header comment).
assert(Where2GoCompare.IsBetterCandidate(
    { track = MYTH, ilvl = 318 },  -- Myth rank 1/6
    { track = HERO, ilvl = 321 }   -- Hero rank 6/6, nominally higher ilvl
) == true, "higher track should win even with a lower nominal ilvl")

-- Candidate has no recognized track (e.g. crafted gear); equipped does --
-- falls back to a plain ilvl comparison.
assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 320 },
    { track = HERO, ilvl = 308 }
) == true, "no-track candidate with higher ilvl should win the ilvl fallback")

assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 300 },
    { track = HERO, ilvl = 308 }
) == false, "no-track candidate with lower ilvl should lose the ilvl fallback")

-- Neither side has a recognized track -- falls back to ilvl.
assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 320 },
    { track = nil, ilvl = 310 }
) == true, "neither side has a track: higher ilvl should win")

print("compare_spec: OK")
```

- [ ] **Step 2: Update the harness**

In `tests/run_tests.lua`, add `"tests/compare_spec.lua"` to the `specs`
list.

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/compare_spec.lua: ...` (file doesn't exist yet).

- [ ] **Step 4: Implement Compare.lua**

`Where2Go/Core/Compare.lua`:
```lua
-- Pure comparison logic -- no WoW API references, testable standalone. See
-- docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md for
-- the "track beats item level" rationale.

Where2GoCompare = {}

function Where2GoCompare.IsBetterCandidate(candidate, equipped)
    if candidate.track and equipped.track and candidate.track.order ~= equipped.track.order then
        return candidate.track.order > equipped.track.order
    end
    return (candidate.ilvl or 0) > (equipped.ilvl or 0)
end
```

- [ ] **Step 5: Update the manifest**

In `Where2Go/Where2Go.toc`, insert `Core\Compare.lua` immediately after
`Core\Fixtures.lua` and before `Core\Init.lua`. The file list section
should now read:
```
Core\Constants.lua
Core\Tracks.lua
Core\Fixtures.lua
Core\Compare.lua
Core\Init.lua
UI\Panel.lua
```

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (5 spec files now), exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/Compare.lua tests/compare_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: add track-then-ilvl comparison logic"
```

---

### Task 3: Extend Core/Constants.lua

**Files:**
- Modify: `Where2Go/Core/Constants.lua`
- Modify: `tests/constants_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces (new, in addition to Phase 1's `ADDON_NAME`/`INTERFACE_VERSION`/
  `SEASON_LABEL`/`BuildDefaultAccountDB`): `Where2GoConstants.SLOT_TO_INVSLOT`
  (table, 12 keys: `HEAD`, `NECK`, `SHOULDER`, `BACK`, `CHEST`, `WRIST`,
  `HANDS`, `WAIST`, `LEGS`, `FEET`, `MAINHAND`, `OFFHAND` → WoW inventory
  slot name strings), `Where2GoConstants.FINGER_SLOTS` /
  `Where2GoConstants.TRINKET_SLOTS` (2-element arrays of slot name strings),
  `Where2GoConstants.EQUIPLOC_TO_SLOT` (table, WoW `itemEquipLoc` string →
  one of the normalized slot ids above, `"FINGER"`, or `"TRINKET"`).
  **Changes** (breaking, no migration needed — Phase 1 never shipped real
  user data in this shape): `Where2GoConstants.BuildDefaultCharDB()` now
  returns `{ preferredItems = { DROP = {}, VOIDCORE = {} } }` instead of
  `{ preferredItems = {} }`. `Core/Equipment.lua` (Task 4) and `Core/Init.lua`
  (Task 5) consume all of these.

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

-- Regression guard: each call must return independent tables at every
-- level. If the builder ever returns a shared table by reference, one
-- character's saved data would leak into every other character's.
local secondCharDB = Where2GoConstants.BuildDefaultCharDB()
charDB.preferredItems.DROP[12345] = true
charDB.preferredItems.VOIDCORE[54321] = true
assert(next(secondCharDB.preferredItems.DROP) == nil,
    "BuildDefaultCharDB must return an independent DROP table on each call")
assert(next(secondCharDB.preferredItems.VOIDCORE) == nil,
    "BuildDefaultCharDB must return an independent VOIDCORE table on each call")

print("constants_spec: OK")
```

- [ ] **Step 2: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/constants_spec.lua: ...` (new fields/shape don't
exist in `Constants.lua` yet — the old `preferredItems = {}` shape means
`preferredItems.DROP` is `nil`, not a table).

- [ ] **Step 3: Implement the Constants.lua changes**

Replace the full contents of `Where2Go/Core/Constants.lua` with:
```lua
Where2GoConstants = {}

Where2GoConstants.ADDON_NAME = "Where2Go"
Where2GoConstants.INTERFACE_VERSION = 120100
Where2GoConstants.SEASON_LABEL = "Midnight Season 2"

-- WoW equip-slot name (for GetInventorySlotInfo) per normalized slot id.
-- FINGER/TRINKET have two physical slots each -- see FINGER_SLOTS/
-- TRINKET_SLOTS below, handled specially by Core/Equipment.lua.
Where2GoConstants.SLOT_TO_INVSLOT = {
    HEAD = "HeadSlot",
    NECK = "NeckSlot",
    SHOULDER = "ShoulderSlot",
    BACK = "BackSlot",
    CHEST = "ChestSlot",
    WRIST = "WristSlot",
    HANDS = "HandsSlot",
    WAIST = "WaistSlot",
    LEGS = "LegsSlot",
    FEET = "FeetSlot",
    MAINHAND = "MainHandSlot",
    OFFHAND = "SecondaryHandSlot",
}
Where2GoConstants.FINGER_SLOTS = { "Finger0Slot", "Finger1Slot" }
Where2GoConstants.TRINKET_SLOTS = { "Trinket0Slot", "Trinket1Slot" }

-- Maps a WoW itemEquipLoc string (the 4th return of
-- C_Item.GetItemInfoInstant) to our normalized slot id, so a bare item ID
-- can be routed to the right equipped-slot comparison. Only the equip
-- locations relevant to current classes/gear are listed (YAGNI -- no
-- ammo/relic/thrown/etc. slots, which no longer exist on live characters).
Where2GoConstants.EQUIPLOC_TO_SLOT = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
    INVTYPE_WEAPONMAINHAND = "MAINHAND",
    INVTYPE_2HWEAPON = "MAINHAND",
    INVTYPE_WEAPON = "MAINHAND",
    INVTYPE_RANGED = "MAINHAND",
    INVTYPE_RANGEDRIGHT = "MAINHAND",
    INVTYPE_WEAPONOFFHAND = "OFFHAND",
    INVTYPE_HOLDABLE = "OFFHAND",
    INVTYPE_SHIELD = "OFFHAND",
}

function Where2GoConstants.BuildDefaultAccountDB()
    return {
        panelShown = false,
    }
end

function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {
            DROP = {},
            VOIDCORE = {},
        },
    }
end
```

- [ ] **Step 4: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]`, exit code `0`.

- [ ] **Step 5: Commit**

```bash
git add Where2Go/Core/Constants.lua tests/constants_spec.lua
git commit -m "feat: add slot/equip-loc constants and purpose-scoped preferred items"
```

---

### Task 4: Core/Equipment.lua

**Files:**
- Create: `Where2Go/Core/Equipment.lua`
- Modify: `Where2Go/Where2Go.toc` (insert `Core\Equipment.lua` right after
  `Core\Compare.lua`, before `Core\Init.lua`)

**Interfaces:**
- Consumes: `Where2GoTracks.UPGRADE_TRACKS` (Task 1),
  `Where2GoConstants.SLOT_TO_INVSLOT` / `FINGER_SLOTS` / `TRINKET_SLOTS` /
  `EQUIPLOC_TO_SLOT` (Task 3), `Where2GoCompare.IsBetterCandidate` (Task 2).
- Produces: `Where2GoEquipment.GetTrackInfo(link)` →
  `{ order, ilvl, label, rank } or nil`; `Where2GoEquipment.GetEquipped(slotId)`
  → array of `{ itemId, ilvl, track }` (1 entry normally, 2 for `"FINGER"`/
  `"TRINKET"`); `Where2GoEquipment.GetBestEquipped(slotId)` → the single best
  `{ itemId, ilvl, track }` (never nil — an empty slot yields
  `{ itemId = nil, ilvl = nil, track = nil }`); `Where2GoEquipment.FindItemLink(itemId)`
  → a real item link or `nil`; `Where2GoEquipment.GetNormalizedSlot(itemId)`
  → one of `SLOT_TO_INVSLOT`'s keys, `"FINGER"`, `"TRINKET"`, or `nil`.
  `Core/Init.lua` (Task 5) calls all of these for `/where2go compare`.

This task's code is WoW-API-dependent (`GetInventoryItemLink`,
`C_Item.GetDetailedItemLevelInfo`, `C_Container.*`) and cannot run under
the standalone `lua5.1` interpreter — verified live in-client in Task 6.

- [ ] **Step 1: Implement Equipment.lua**

`Where2Go/Core/Equipment.lua`:
```lua
-- Reads real equipped/bag items and determines their upgrade track by
-- matching bonus IDs against Where2GoTracks.UPGRADE_TRACKS. Ported from
-- the pre-restart implementation's Core/Equipment.lua -- see
-- docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md for
-- provenance. WoW-API-dependent; not unit-tested (Core/Compare.lua carries
-- the pure comparison logic this feeds).

Where2GoEquipment = {}

local function ilvlForLink(link)
    if not link then
        return nil
    end
    return C_Item.GetDetailedItemLevelInfo(link)
end

-- Manual bonus-ID parse: WoW has no official "get bonus IDs from a link"
-- API. itemString field layout (Blizzard item-link spec, 1-indexed):
-- 1=item, 2=itemID, 3=enchantID, 4-7=gem1-4, 8=suffixID, 9=uniqueID,
-- 10=linkLevel, 11=specializationID, 12=upgradeTypeID,
-- 13=instanceDifficultyID/context, 14=numBonusIDs,
-- 15..14+numBonusIDs=the bonus IDs themselves.
local function parseBonusIds(link)
    if not link then
        return {}
    end
    local itemString = link:match("item[%-?%d:]+")
    if not itemString then
        return {}
    end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local numBonus = tonumber(fields[14]) or 0
    local ids = {}
    for i = 1, numBonus do
        local id = tonumber(fields[14 + i])
        if id then
            table.insert(ids, id)
        end
    end
    return ids
end

-- Returns { order, ilvl, label, rank } for the highest-order upgrade track
-- found among an item link's bonus IDs, or nil if none match (e.g. crafted
-- gear, which uses an unrelated bonus-ID scheme).
function Where2GoEquipment.GetTrackInfo(link)
    local ids = parseBonusIds(link)
    local best
    for _, id in ipairs(ids) do
        for _, track in pairs(Where2GoTracks.UPGRADE_TRACKS) do
            if id >= track.bonusIdStart and id < track.bonusIdStart + 6 then
                local rank = id - track.bonusIdStart + 1
                if not best or track.order > best.order then
                    best = { order = track.order, ilvl = track.ilvls[rank], label = track.label, rank = rank }
                end
            end
        end
    end
    return best
end

local function infoForInvSlotName(invSlotName)
    local slotId = GetInventorySlotInfo(invSlotName)
    if not slotId then
        return { itemId = nil, ilvl = nil, track = nil }
    end
    local link = GetInventoryItemLink("player", slotId)
    return {
        itemId = GetInventoryItemID("player", slotId),
        ilvl = ilvlForLink(link),
        track = Where2GoEquipment.GetTrackInfo(link),
    }
end

-- Returns { {itemId=, ilvl=, track=}, ... } for a normalized slot id.
-- Single-entry for most slots, two entries for FINGER/TRINKET.
function Where2GoEquipment.GetEquipped(slotId)
    if slotId == "FINGER" then
        local out = {}
        for _, invSlot in ipairs(Where2GoConstants.FINGER_SLOTS) do
            table.insert(out, infoForInvSlotName(invSlot))
        end
        return out
    elseif slotId == "TRINKET" then
        local out = {}
        for _, invSlot in ipairs(Where2GoConstants.TRINKET_SLOTS) do
            table.insert(out, infoForInvSlotName(invSlot))
        end
        return out
    end

    local invSlot = Where2GoConstants.SLOT_TO_INVSLOT[slotId]
    if not invSlot then
        return {}
    end
    return { infoForInvSlotName(invSlot) }
end

-- Best (highest track, then highest ilvl) equipped entry for a normalized
-- slot id -- the comparison baseline for FINGER/TRINKET's two physical
-- slots, and simply the one entry otherwise. Never returns nil.
function Where2GoEquipment.GetBestEquipped(slotId)
    local entries = Where2GoEquipment.GetEquipped(slotId)
    local best = { itemId = nil, ilvl = nil, track = nil }
    for _, entry in ipairs(entries) do
        if Where2GoCompare.IsBetterCandidate(entry, best) then
            best = entry
        end
    end
    return best
end

-- Which normalized slot a bare item ID belongs in, or nil if it isn't
-- equippable gear (e.g. a consumable) or its equip loc isn't mapped.
function Where2GoEquipment.GetNormalizedSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

-- The first real item link found for itemId: checks all 19 equipped slots,
-- then bags 0-4. Returns nil if the player has no real instance of it
-- right now.
function Where2GoEquipment.FindItemLink(itemId)
    for slot = 1, 19 do
        if GetInventoryItemID("player", slot) == itemId then
            return GetInventoryItemLink("player", slot)
        end
    end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId then
                return info.hyperlink
            end
        end
    end
    return nil
end
```

- [ ] **Step 2: Update the manifest**

In `Where2Go/Where2Go.toc`, insert `Core\Equipment.lua` immediately after
`Core\Compare.lua` and before `Core\Init.lua`. The file list section should
now read:
```
Core\Constants.lua
Core\Tracks.lua
Core\Fixtures.lua
Core\Compare.lua
Core\Equipment.lua
Core\Init.lua
UI\Panel.lua
```

- [ ] **Step 3: Run the automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (`toc_spec` now verifies 7 files — Constants,
Tracks, Fixtures, Compare, Equipment, Init, Panel — all present and none
extra), exit code `0`. `Equipment.lua` itself has no unit test — this only
confirms the manifest/other specs are still consistent.

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/Equipment.lua Where2Go/Where2Go.toc
git commit -m "feat: read equipped/bag items and detect upgrade track"
```

---

### Task 5: Extend Core/Init.lua

**Files:**
- Modify: `Where2Go/Core/Init.lua`

**Interfaces:**
- Consumes: `Where2GoCharDB.preferredItems.DROP`/`.VOIDCORE` (Task 3),
  `Where2GoEquipment.FindItemLink`/`GetTrackInfo`/`GetNormalizedSlot`/
  `GetBestEquipped` (Task 4), `Where2GoCompare.IsBetterCandidate` (Task 2),
  `C_Item.GetDetailedItemLevelInfo` (WoW API).
- Produces: extends the existing `/where2go` slash command with
  subcommands `pref add <itemID> <drop|voidcore>`, `pref remove <itemID> <drop|voidcore>`,
  `pref list <drop|voidcore>`, and `compare`. Calling `/where2go` with no
  arguments keeps Phase 1's behavior (toggles the panel).

This task's code is WoW-API-dependent and not unit-tested — verified live
in-client in Task 6.

- [ ] **Step 1: Implement the Init.lua changes**

Replace the full contents of `Where2Go/Core/Init.lua` with:
```lua
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName ~= Where2GoConstants.ADDON_NAME then
        return
    end

    Where2GoDB = Where2GoDB or Where2GoConstants.BuildDefaultAccountDB()
    Where2GoCharDB = Where2GoCharDB or Where2GoConstants.BuildDefaultCharDB()

    self:UnregisterEvent("ADDON_LOADED")
end)

local function SplitArgs(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    return args
end

local function NormalizePurpose(raw)
    if not raw then
        return nil
    end
    local upper = raw:upper()
    if upper == "DROP" or upper == "VOIDCORE" then
        return upper
    end
    return nil
end

local function HandlePrefCommand(args)
    local action = args[2]
    if action == "add" or action == "remove" then
        local itemId = tonumber(args[3])
        local purpose = NormalizePurpose(args[4])
        if not itemId or itemId % 1 ~= 0 or itemId <= 0 or not purpose then
            print("Usage: /where2go pref add|remove <itemID> <drop|voidcore>")
            return
        end
        if action == "add" then
            Where2GoCharDB.preferredItems[purpose][itemId] = true
            print(string.format("Where2Go: added item %d to %s preferred items.", itemId, purpose))
        else
            Where2GoCharDB.preferredItems[purpose][itemId] = nil
            print(string.format("Where2Go: removed item %d from %s preferred items.", itemId, purpose))
        end
    elseif action == "list" then
        local purpose = NormalizePurpose(args[3])
        if not purpose then
            print("Usage: /where2go pref list <drop|voidcore>")
            return
        end
        local ids = {}
        for itemId in pairs(Where2GoCharDB.preferredItems[purpose]) do
            table.insert(ids, itemId)
        end
        table.sort(ids)
        print(string.format("Where2Go: %s preferred items: %s", purpose,
            #ids > 0 and table.concat(ids, ", ") or "(none)"))
    else
        print("Usage: /where2go pref add|remove|list ...")
    end
end

local function DescribeCandidate(candidateInfo, equipped)
    local isBetter = Where2GoCompare.IsBetterCandidate(candidateInfo, equipped)
    local function describeSide(info)
        if not info.ilvl then
            return "(empty)"
        end
        if info.track then
            return string.format("ilvl %d (%s %d/6)", info.ilvl, info.track.label, info.track.rank)
        end
        return string.format("ilvl %d (no recognized track)", info.ilvl)
    end
    return string.format("%s vs equipped %s -> %s",
        describeSide(candidateInfo), describeSide(equipped), isBetter and "UPGRADE" or "not an upgrade")
end

local function HandleCompareCommand()
    local anyFound = false
    for _, purpose in ipairs({ "DROP", "VOIDCORE" }) do
        for itemId in pairs(Where2GoCharDB.preferredItems[purpose]) do
            local link = Where2GoEquipment.FindItemLink(itemId)
            if link then
                anyFound = true
                local candidateInfo = { ilvl = C_Item.GetDetailedItemLevelInfo(link), track = Where2GoEquipment.GetTrackInfo(link) }
                local slotId = Where2GoEquipment.GetNormalizedSlot(itemId)
                local equipped = slotId and Where2GoEquipment.GetBestEquipped(slotId) or { itemId = nil, ilvl = nil, track = nil }
                print(string.format("Where2Go [%s] %s: %s", purpose, link, DescribeCandidate(candidateInfo, equipped)))
            end
        end
    end
    if not anyFound then
        print("Where2Go: no preferred items found in bags or equipped.")
    end
end

SLASH_WHERE2GO1 = "/where2go"
SlashCmdList["WHERE2GO"] = function(msg)
    local args = SplitArgs(msg)
    local subcommand = args[1]
    if subcommand == "pref" then
        HandlePrefCommand(args)
    elseif subcommand == "compare" then
        HandleCompareCommand()
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare")
    end
end
```

- [ ] **Step 2: Run the automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]`, exit code `0` (no automated test touches
`Init.lua` itself, but this confirms nothing else broke).

- [ ] **Step 3: Commit**

```bash
git add Where2Go/Core/Init.lua
git commit -m "feat: add pref and compare slash subcommands"
```

---

### Task 6: Manual live-client verification

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — verify the pref command and comparison live**

This step cannot be run by an agent — it requires the WoW client. Whoever
executes this task should do the following themselves and report the
result back before Phase 2 is considered done:

1. `/reload` and confirm no Lua error appears (same check as Phase 1).
2. Pick a real item you can get a link for (in bags or equipped) and note
   its item ID — item 268265 was the one used during this phase's
   brainstorming and is a convenient default if you still have it.
3. Run `/where2go pref add 268265 drop`, then `/where2go pref list drop` —
   confirm it echoes back `268265`.
4. Run `/where2go compare`. Confirm one line prints for item 268265 showing
   its candidate ilvl/track, the equipped comparison point for its slot,
   and an UPGRADE / not-an-upgrade verdict that matches what you'd expect
   by eye (check the item's actual track/ilvl against what's equipped in
   that slot).
5. Run `/where2go pref remove 268265 drop`, then `/where2go pref list drop` —
   confirm it now reports `(none)`.
6. Optional faster-iteration alternative to re-typing `pref add` every
   time: with the character fully logged out (character-select screen or
   the client closed — **not** just `/reload`, since `/reload` flushes the
   current in-memory SavedVariables to disk first and would overwrite a
   pre-edited file before it's ever read), directly edit
   `WTF/Account/<account>/<realm>/<character>/SavedVariables/Where2Go.lua`
   to pre-seed `Where2GoCharDB.preferredItems.DROP[268265] = true`, then
   log back in — `/where2go compare` should immediately show it without
   running `pref add` first.
7. `/where2go` with no arguments still toggles the Phase 1 panel — confirm
   this still works (regression check on the subcommand dispatch change).

This satisfies `docs/DEVELOPMENT_PLAN.md` Phase 2's acceptance check: "a
live-client check confirms one higher-track candidate is shown."

---

## Done

Phase 2 is complete when all six tasks' commits exist and the Task 6
manual checkpoint has been confirmed in a live client. Phase 3 (direct-drop
recommendations) starts a new plan built on this foundation.
