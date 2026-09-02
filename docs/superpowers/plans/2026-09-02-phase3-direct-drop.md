# Phase 3: Direct-Drop Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank every Season 2 Mythic+ dungeon and raid boss encounter by the
equal-outcome probability model (`docs/DECISIONS.md`), using real item
pools, and show the ranked results as expandable cards in the live panel —
matching `docs/DEVELOPMENT_PLAN.md` Phase 3's acceptance check (a fixture
with known pool sizes produces the expected ordering; the live panel shows
expandable cards).

**Architecture:** Four new pure files (`Sources.lua`, `RaidRanks.lua`,
`Ranking.lua` — all real unit tests) plus one new WoW-API-dependent file
(`DirectDrop.lua`, no unit test) replace `Fixtures.lua`'s role entirely.
`UI/Panel.lua` is rewritten to render `DirectDrop`'s real ranked results as
collapsible cards instead of static fixture data.

**Tech Stack:** Plain FrameXML/Lua, no Ace3, no vendored libraries
(unchanged). Lua 5.1 via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"`.

**Spec:** `docs/superpowers/specs/2026-09-02-phase3-direct-drop-design.md`

## Global Constraints

- `Core/Sources.lua`, `Core/RaidRanks.lua`, and `Core/Ranking.lua` must
  never reference WoW API globals — pure Lua, testable standalone.
- `Core/Sources.lua` is a byte-faithful port of the cited source's item
  pools, including two encounters (`Dazar, The First King` and `Avatar of
  Sethraliss`) whose raw `itemIds` arrays contain duplicate item IDs (an
  artifact of the source's own generation, not a transcription error — do
  not "clean up" the data by hand-removing them). Correctness for
  duplicates is `Ranking.lua`'s job, not `Sources.lua`'s: **`Ranking.lua`
  must deduplicate item IDs within a single content entry before counting
  eligibility/preference** — the same item ID must never be counted twice
  toward `eligibleCount` or `targetCount` for one entry.
- Ranking sort order (exact, do not deviate): `ratio` descending, then
  `targetCount` descending, then `name` ascending.
- `eligibleCount == 0` must produce `ratio == 0`, never a division error or
  `nil`.
- Mythic+ content is one entry per dungeon (pool = the union of ALL its
  encounters' `itemIds`, flattened). Raid content is one entry per boss
  encounter (pool = that boss's `itemIds` only), each carrying its parent
  raid's name in a `raidName` field for display context. Dungeons have
  `raidName = nil`.
- Raid item level/track is fixed at Mythic difficulty via
  `RaidRanks.GetRaidIlvl(bossId)`. Mythic+ item level/track is fixed at the
  key+10 floor via `RaidRanks.GetMythicPlusIlvl()`. No difficulty/key-level
  selection UI.
- Loot specialization eligibility uses the player's current active spec
  only (`GetSpecialization()`/`GetSpecializationInfo()`), checked per item
  via `C_Item.GetItemSpecInfo`. `nil` from that call means no restriction
  (eligible); a non-nil table not containing the current spec ID means not
  eligible.
- All cards render expanded by default (per the `docs/DECISIONS.md` update
  made during this phase's planning) but must support individual collapse.
- `tests/toc_spec.lua` (built in Phase 1) checks both directions — every
  task that adds, removes, or renames a file must update the TOC in the
  same task, or the suite goes red for a reason unrelated to that task.
- Tests run via `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua` from the repository root.
- Source code, comments, and commit messages are English.

---

## File Structure

```
Where2Go/
├── Where2Go.toc                  MODIFY across Tasks 1-5 (see each task)
├── Core/
│   ├── Constants.lua              unchanged
│   ├── Tracks.lua                 unchanged
│   ├── Sources.lua                 CREATE (Task 1): real item pools (pure)
│   ├── RaidRanks.lua               CREATE (Task 2): boss rank/ilvl (pure)
│   ├── Ranking.lua                 CREATE (Task 3): ranking math (pure)
│   ├── DirectDrop.lua              CREATE (Task 4): content assembly + live
│   │                              eligibility (WoW-API, no unit test)
│   ├── Compare.lua                unchanged
│   ├── Equipment.lua              unchanged
│   ├── Fixtures.lua               DELETE (Task 5)
│   └── Init.lua                   unchanged
└── UI/
    └── Panel.lua                  REWRITE (Tasks 5-6): real ranked cards

DELETE: tests/fixtures_spec.lua (Task 5)

tests/
├── run_tests.lua                  MODIFY across Tasks 1-3, 5
├── sources_spec.lua                CREATE (Task 1)
├── raidranks_spec.lua              CREATE (Task 2)
└── ranking_spec.lua                CREATE (Task 3)
```

**Final TOC order after Task 5** (matches the design spec's Architecture
section): `Core\Constants.lua`, `Core\Tracks.lua`, `Core\Sources.lua`,
`Core\RaidRanks.lua`, `Core\Ranking.lua`, `Core\DirectDrop.lua`,
`Core\Compare.lua`, `Core\Equipment.lua`, `Core\Init.lua`, `UI\Panel.lua`.

---

### Task 1: Core/Sources.lua

**Files:**
- Create: `Where2Go/Core/Sources.lua`
- Test: `tests/sources_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/sources_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\Sources.lua` after
  `Core\Tracks.lua`, before `Core\Fixtures.lua`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Where2GoSources.DUNGEONS` (array of 8
  `{instanceId, name, encounters}`) and `Where2GoSources.RAIDS` (array of 2
  `{instanceId, name, encounters}`), each encounter
  `{bossId, name, itemIds}`. `Core/DirectDrop.lua` (Task 4) reads both.

- [ ] **Step 1: Write the failing test**

`tests/sources_spec.lua`:
```lua
dofile("Where2Go/Core/Sources.lua")

local function assertNonEmptyArray(t, label)
    assert(type(t) == "table", label .. " should be a table")
    assert(#t > 0, label .. " should be non-empty")
end

assertNonEmptyArray(Where2GoSources.DUNGEONS, "Where2GoSources.DUNGEONS")
assertNonEmptyArray(Where2GoSources.RAIDS, "Where2GoSources.RAIDS")

local function checkInstance(instance, kind, index)
    local label = kind .. "[" .. index .. "]"
    assert(type(instance.name) == "string" and #instance.name > 0, label .. ".name should be a non-empty string")
    assertNonEmptyArray(instance.encounters, label .. ".encounters")
    for i, encounter in ipairs(instance.encounters) do
        local encLabel = label .. ".encounters[" .. i .. "]"
        assert(type(encounter.name) == "string" and #encounter.name > 0, encLabel .. ".name should be a non-empty string")
        assert(type(encounter.bossId) == "number", encLabel .. ".bossId should be a number")
        assertNonEmptyArray(encounter.itemIds, encLabel .. ".itemIds")
        for _, itemId in ipairs(encounter.itemIds) do
            assert(type(itemId) == "number", encLabel .. ".itemIds should contain only numbers")
        end
    end
end

for i, dungeon in ipairs(Where2GoSources.DUNGEONS) do
    checkInstance(dungeon, "DUNGEONS", i)
end
for i, raid in ipairs(Where2GoSources.RAIDS) do
    checkInstance(raid, "RAIDS", i)
end

-- Spot-check the real Venomous Abyss boss count this design corrects
-- Phase 1's fixture data against (see the design spec's provenance note).
local venomousAbyss = Where2GoSources.RAIDS[2]
assert(venomousAbyss.name == "The Venomous Abyss", "RAIDS[2] should be The Venomous Abyss")
assert(#venomousAbyss.encounters == 8, "The Venomous Abyss should have exactly 8 encounters")

print("sources_spec: OK, " .. #Where2GoSources.DUNGEONS .. " dungeon(s), " .. #Where2GoSources.RAIDS .. " raid(s) verified")
```

- [ ] **Step 2: Update the harness**

Append `"tests/sources_spec.lua"` to the `specs` list in `tests/run_tests.lua`.

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/sources_spec.lua: ...` (file doesn't exist yet).

- [ ] **Step 4: Implement Sources.lua**

`Where2Go/Core/Sources.lua`:
```lua
-- Real per-dungeon/per-boss item pools for Season 2 (Midnight patch 12.1),
-- ported verbatim from codex/pre-restart-backup's Data/Sources.lua, which
-- was itself generated from the Battle.net Game Data API Journal
-- endpoints. See
-- docs/superpowers/specs/2026-09-02-phase3-direct-drop-design.md for full
-- provenance. Do not hand-edit -- if the data needs correcting, regenerate
-- from the same source. Two encounters below (Dazar, The First King;
-- Avatar of Sethraliss) contain duplicate item IDs in their raw itemIds
-- lists -- this is an artifact of the source's own generation, left as-is
-- here; Core/Ranking.lua deduplicates before counting.

Where2GoSources = {}

Where2GoSources.DUNGEONS = {
    {
        instanceId = 1322,
        name = "Altar of Fangs",
        encounters = {
            { bossId = 2878, name = "Rav'i", itemIds = { 273796, 273795, 273785, 273775, 273777, 273780, 273793 } },
            { bossId = 2879, name = "The Writhing Coil", itemIds = { 273781, 273794, 273786, 273774, 273787, 273782, 273783, 273779 } },
            { bossId = 2880, name = "Zul'jan", itemIds = { 273792, 273797, 273773, 273791, 273789, 273776, 273778, 273784, 270900, 275070, 279211, 276804 } },
        },
    },
    {
        instanceId = 1311,
        name = "Den of Nalorakk",
        encounters = {
            { bossId = 2776, name = "The Hoardmonger", itemIds = { 250248, 251148, 251147, 251146, 251145, 251144, 251143 } },
            { bossId = 2777, name = "Sentinel of Winter", itemIds = { 251154, 251153, 251152, 251155, 251151, 251150, 251149, 250244, 271681 } },
            { bossId = 2778, name = "Nalorakk", itemIds = { 256737, 251160, 250229, 251159, 251158, 251156, 251173, 251214, 251173, 264332 } },
        },
    },
    {
        instanceId = 1304,
        name = "Murder Row",
        encounters = {
            { bossId = 2679, name = "Kystia Manaheart", itemIds = { 250243, 251127, 251124, 251125, 251126, 251123, 271680 } },
            { bossId = 2680, name = "Zaen Bladesorrow", itemIds = { 250215, 251129, 251132, 251130, 251131, 251133, 251128 } },
            { bossId = 2681, name = "Xathuux the Annihilator", itemIds = { 250228, 251136, 251137, 251135, 251134 } },
            { bossId = 2682, name = "Lithiel Cinderfury", itemIds = { 250255, 251142, 251139, 251140, 251141, 251138, 263238, 256640, 258487, 258518, 256746, 258045 } },
        },
    },
    {
        instanceId = 1309,
        name = "The Blinding Vale",
        encounters = {
            { bossId = 2769, name = "Lightblossom Trinity", itemIds = { 251185, 251183, 251184, 251182, 251180, 251181, 250254 } },
            { bossId = 2770, name = "Ikuzz the Light Hunter", itemIds = { 251190, 251189, 251187, 251186, 251188, 250238 } },
            { bossId = 2771, name = "Lightwarden Ruia", itemIds = { 250214, 251194, 251191, 251193, 251192, 251165 } },
            { bossId = 2772, name = "Ziekket", itemIds = { 251199, 251198, 251200, 251197, 251196, 251195, 250259, 256652, 256642, 253451, 268728 } },
        },
    },
    {
        instanceId = 1313,
        name = "Voidscar Arena",
        encounters = {
            { bossId = 2791, name = "Taz'Rah", itemIds = { 250225, 251219, 251222, 251223, 251220, 251221, 251218 } },
            { bossId = 2792, name = "Atroxus", itemIds = { 250245, 251227, 251226, 251228, 251229, 251225, 251224, 252258 } },
            { bossId = 2793, name = "Charonus", itemIds = { 250224, 251234, 251232, 251235, 251233, 251230, 251231, 256721, 264336 } },
        },
    },
    {
        instanceId = 1041,
        name = "Kings' Rest",
        encounters = {
            { bossId = 2165, name = "The Golden Serpent", itemIds = { 159137, 159234, 159413, 159304, 159617, 159369, 159412, 159313 } },
            { bossId = 2171, name = "Mchimba the Embalmer", itemIds = { 159618, 159459, 159667, 160213, 159312, 159642, 159409 } },
            { bossId = 2170, name = "The Council of Tribes", itemIds = { 160216, 159300, 159136, 159643, 159288, 159243, 159371, 159418 } },
            { bossId = 2172, name = "Dazar, The First King", itemIds = { 159921, 158344, 159236, 159422, 159423, 159645, 158355, 159303, 159368, 159301, 159644, 239047, 239045, 239048, 239046, 239049, 239050, 239051, 278245, 239045, 239047, 239050, 239051, 239046, 239048, 239049, 273649 } },
        },
    },
    {
        instanceId = 1202,
        name = "Ruby Life Pools",
        encounters = {
            { bossId = 2488, name = "Melidrussa Chillworn", itemIds = { 193759, 193758, 193761, 193757, 193728 } },
            { bossId = 2485, name = "Kokia Blazehoof", itemIds = { 193762, 193765, 193767, 193763, 193764, 193766 } },
            { bossId = 2503, name = "Kyrakka and Erkhart Stormvein", itemIds = { 193756, 193752, 193691, 193750, 193754, 193755, 193751, 193748, 198059, 198058, 198056, 193753, 256428 } },
        },
    },
    {
        instanceId = 1030,
        name = "Temple of Sethraliss",
        encounters = {
            { bossId = 2142, name = "Adderis and Aspix", itemIds = { 159317, 159380, 158370, 159259, 159425, 159329, 159636, 159388, 159263, 159435 } },
            { bossId = 2143, name = "Merektha", itemIds = { 159637, 159327, 159437, 159375, 162544, 158367, 158714, 159255, 160832, 159437 } },
            { bossId = 2144, name = "Galvazzt", itemIds = { 159247, 159442, 158374, 158366, 158369, 159664 } },
            { bossId = 2145, name = "Avatar of Sethraliss", itemIds = { 159374, 158373, 159254, 159318, 158368, 159370, 159424, 159337, 159257, 159439, 239032, 239031, 239033, 239034, 239035, 239036, 239037, 278982, 239035, 159374, 239031, 159254, 239033, 159318, 239034, 159370, 239036, 159424, 239032, 159257, 239037, 159439 } },
        },
    },
}

Where2GoSources.RAIDS = {
    {
        instanceId = 1317,
        name = "The Tidebound Grotto",
        encounters = {
            { bossId = 2849, name = "Nymrissa Wavecaller", itemIds = { 279112, 270167, 268199, 268221, 268238, 268226, 268263, 268262, 268232, 268247, 268217, 268244, 268266 } },
        },
    },
    {
        instanceId = 1320,
        name = "The Venomous Abyss",
        encounters = {
            { bossId = 2888, name = "Nek'zali the Soulcoiler", itemIds = { 279115, 281227, 268230, 280305, 270162, 268203, 268236, 268235, 268229, 268245, 268208, 270930, 268248, 268218, 268240, 268216 } },
            { bossId = 2874, name = "Entombed Sentinels", itemIds = { 270913, 270912, 270911, 270910, 264716, 268250, 270165, 268204, 268198, 268224, 268228, 268219, 268197 } },
            { bossId = 2894, name = "The Lost Explorers", itemIds = { 279118, 270925, 270924, 270923, 270922, 270164, 270160, 268210, 268200, 268227, 268242, 268258, 268239, 268196 } },
            { bossId = 2882, name = "Vashnik the Malignant", itemIds = { 270929, 270928, 270927, 270926, 272361, 268249, 268246, 268254, 268260, 268214, 270166, 270161, 268205 } },
            { bossId = 2871, name = "Sszorak", itemIds = { 244343, 270921, 270920, 270919, 270918, 270163, 270174, 268206, 268201, 268257, 268234, 268233, 268252 } },
            { bossId = 2887, name = "The Twin Fangs", itemIds = { 279122, 270917, 270916, 270915, 270914, 270171, 270170, 268251, 268264, 268241, 268261, 268223, 268220, 273070 } },
            { bossId = 2883, name = "The Coiled Altar", itemIds = { 268225, 268231, 279131, 268209, 270173, 268243, 270169, 268237, 268222, 268213, 268253, 268255, 268256, 268259, 268211, 275937, 275938 } },
            { bossId = 2895, name = "Ula'tek", itemIds = { 279125, 279127, 279129, 279500, 270909, 268202, 268215, 270168, 270175, 268207, 268265, 271874, 271875, 271876, 271878, 271093, 271092, 275658 } },
        },
    },
}
```

- [ ] **Step 5: Update the manifest**

Insert `Core\Sources.lua` immediately after `Core\Tracks.lua` and before
`Core\Fixtures.lua` in `Where2Go/Where2Go.toc`.

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (6 spec files; `toc_spec` now verifies 8
files), exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/Sources.lua tests/sources_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: add real Season 2 dungeon/raid item pool data"
```

---

### Task 2: Core/RaidRanks.lua

**Files:**
- Create: `Where2Go/Core/RaidRanks.lua`
- Test: `tests/raidranks_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/raidranks_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\RaidRanks.lua` after
  `Core\Sources.lua`, before `Core\Fixtures.lua`)

**Interfaces:**
- Consumes: `Where2GoTracks.UPGRADE_TRACKS` (existing, from Phase 2).
- Produces: `Where2GoRaidRanks.RAID_BOSS_RANK` (bossId → 1-4),
  `Where2GoRaidRanks.GetRaidIlvl(bossId)` → `(ilvl, trackLabel, rank)`,
  `Where2GoRaidRanks.GetMythicPlusIlvl()` → `(ilvl, trackLabel, rank)`.
  `Core/DirectDrop.lua` (Task 4) calls both functions.

- [ ] **Step 1: Write the failing test**

`tests/raidranks_spec.lua`:
```lua
dofile("Where2Go/Core/Tracks.lua")
dofile("Where2Go/Core/RaidRanks.lua")

local MYTH = Where2GoTracks.UPGRADE_TRACKS.MYTH

local expectedRank = {
    [2888] = 1, [2874] = 2, [2894] = 2, [2882] = 3,
    [2871] = 3, [2887] = 3, [2883] = 4, [2895] = 4,
}

for bossId, rank in pairs(expectedRank) do
    local ilvl, label, actualRank = Where2GoRaidRanks.GetRaidIlvl(bossId)
    assert(actualRank == rank, "bossId " .. bossId .. " should be rank " .. rank)
    assert(ilvl == MYTH.ilvls[rank], "bossId " .. bossId .. " ilvl should match MYTH.ilvls[" .. rank .. "]")
    assert(label == MYTH.label, "bossId " .. bossId .. " track label should be " .. MYTH.label)
end

-- An unlisted boss ID defaults to rank 1 (single-boss raids like The
-- Tidebound Grotto's Nymrissa Wavecaller, bossId 2849).
local ilvl, label, rank = Where2GoRaidRanks.GetRaidIlvl(2849)
assert(rank == 1, "unlisted bossId should default to rank 1")
assert(ilvl == MYTH.ilvls[1], "unlisted bossId's ilvl should be MYTH.ilvls[1]")

local mplusIlvl, mplusLabel, mplusRank = Where2GoRaidRanks.GetMythicPlusIlvl()
local HERO = Where2GoTracks.UPGRADE_TRACKS.HERO
assert(mplusRank == 3, "Mythic+ should be fixed at rank 3")
assert(mplusIlvl == HERO.ilvls[3], "Mythic+ ilvl should be HERO.ilvls[3]")
assert(mplusLabel == HERO.label, "Mythic+ track label should be " .. HERO.label)

print("raidranks_spec: OK")
```

- [ ] **Step 2: Update the harness**

Append `"tests/raidranks_spec.lua"` to the `specs` list.

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/raidranks_spec.lua: ...`.

- [ ] **Step 4: Implement RaidRanks.lua**

`Where2Go/Core/RaidRanks.lua`:
```lua
-- Boss rank (1-4) within Mythic-difficulty The Venomous Abyss, ported from
-- codex/pre-restart-backup's Core/Constants.lua RAID_BOSS_RANK --
-- independently verified against the real boss IDs in Core/Sources.lua
-- (exact match). Bosses not listed default to rank 1 (single-boss raids
-- like The Tidebound Grotto). See
-- docs/superpowers/specs/2026-09-02-phase3-direct-drop-design.md.

Where2GoRaidRanks = {}

Where2GoRaidRanks.RAID_BOSS_RANK = {
    [2888] = 1, -- Nek'zali the Soulcoiler
    [2874] = 2, -- Entombed Sentinels
    [2894] = 2, -- The Lost Explorers
    [2882] = 3, -- Vashnik the Malignant
    [2871] = 3, -- Sszorak
    [2887] = 3, -- The Twin Fangs
    [2883] = 4, -- The Coiled Altar
    [2895] = 4, -- Ula'tek
}

-- Mythic+ is fixed at the key+10 floor, confirmed in-client to drop Hero
-- rank 3/6 gear -- see the design spec's provenance note. This replaces
-- the source branch's own per-key-level ilvl table, which was marked
-- "approximate, refine when better data exists" and is deliberately not
-- ported.
Where2GoRaidRanks.MYTHIC_PLUS_TRACK_KEY = "HERO"
Where2GoRaidRanks.MYTHIC_PLUS_TRACK_RANK = 3

-- Returns (ilvl, trackLabel, rank) for a Venomous-Abyss-style raid boss at
-- Mythic difficulty. Unlisted boss IDs default to rank 1.
function Where2GoRaidRanks.GetRaidIlvl(bossId)
    local rank = Where2GoRaidRanks.RAID_BOSS_RANK[bossId] or 1
    local track = Where2GoTracks.UPGRADE_TRACKS.MYTH
    return track.ilvls[rank], track.label, rank
end

-- Returns (ilvl, trackLabel, rank) for the fixed Mythic+ key+10 assumption.
function Where2GoRaidRanks.GetMythicPlusIlvl()
    local track = Where2GoTracks.UPGRADE_TRACKS[Where2GoRaidRanks.MYTHIC_PLUS_TRACK_KEY]
    local rank = Where2GoRaidRanks.MYTHIC_PLUS_TRACK_RANK
    return track.ilvls[rank], track.label, rank
end
```

- [ ] **Step 5: Update the manifest**

Insert `Core\RaidRanks.lua` immediately after `Core\Sources.lua` and before
`Core\Fixtures.lua`.

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (7 spec files; `toc_spec` now verifies 9
files), exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/RaidRanks.lua tests/raidranks_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: add raid boss rank and Mythic+ ilvl assumptions"
```

---

### Task 3: Core/Ranking.lua

**Files:**
- Create: `Where2Go/Core/Ranking.lua`
- Test: `tests/ranking_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/ranking_spec.lua"`)
- Modify: `Where2Go/Where2Go.toc` (insert `Core\Ranking.lua` after
  `Core\RaidRanks.lua`, before `Core\Fixtures.lua`)

**Interfaces:**
- Consumes: nothing (deliberately zero dependencies — takes plain data and
  injected predicate functions).
- Produces: `Where2GoRanking.RankContent(content, isEligible, isPreferred)`.
  `content` is an array of tables each containing at least `name` (string)
  and `itemIds` (array of numbers) — any other fields (e.g. `id`, `kind`,
  `raidName`, `ilvl`, `trackLabel`, `trackRank`) pass through unchanged
  into the corresponding result. Returns an array of results, each the
  input entry's fields plus `eligibleCount`, `targetCount`, `ratio`, and
  `targetItemIds` (array of the eligible-and-preferred item IDs, in
  first-occurrence order), sorted per the Global Constraints' exact order.
  `Core/DirectDrop.lua` (Task 4) calls this.

- [ ] **Step 1: Write the failing test**

`tests/ranking_spec.lua`:
```lua
dofile("Where2Go/Core/Ranking.lua")

local content = {
    { id = "alpha", name = "Alpha", kind = "test", itemIds = { 101, 102 } },
    { id = "beta", name = "Beta", kind = "test", itemIds = { 201, 202, 203, 204 } },
    { id = "gamma", name = "Gamma", kind = "test", itemIds = { 301, 301, 302 } },
    { id = "delta", name = "Delta", kind = "test", itemIds = { 401, 402 } },
    { id = "epsilon", name = "Epsilon", kind = "test", itemIds = { 501 } },
}

-- 204 is deliberately NOT eligible (simulates a wrong-armor-type item);
-- 501 is deliberately NOT eligible at all (Epsilon's only item).
local eligible = {
    [101] = true, [102] = true,
    [201] = true, [202] = true, [203] = true,
    [301] = true, [302] = true,
    [401] = true, [402] = true,
}
local preferred = {
    [101] = true, [102] = true,
    [201] = true, [202] = true, [203] = true,
    [301] = true,
}

local function isEligible(itemId) return eligible[itemId] == true end
local function isPreferred(itemId) return preferred[itemId] == true end

local results = Where2GoRanking.RankContent(content, isEligible, isPreferred)

assert(#results == 5, "should return all 5 entries")

local byName = {}
for _, r in ipairs(results) do
    byName[r.name] = r
end

-- Eligibility filtering: Beta's item 204 is not eligible, so its pool is 3, not 4.
assert(byName.Beta.eligibleCount == 3, "Beta's eligibleCount should exclude the non-eligible item 204")
assert(byName.Beta.targetCount == 3, "Beta's targetCount should be 3")
assert(byName.Beta.ratio == 1.0, "Beta's ratio should be 1.0")

-- Dedup: Gamma's duplicate item 301 must only count once.
assert(byName.Gamma.eligibleCount == 2, "Gamma's duplicate item 301 must not be double-counted in eligibleCount")
assert(byName.Gamma.targetCount == 1, "Gamma's duplicate item 301 must not be double-counted in targetCount")
assert(#byName.Gamma.targetItemIds == 1, "Gamma's targetItemIds must not contain the duplicate")

-- Zero-eligible-pool edge case must not divide by zero or error.
assert(byName.Epsilon.eligibleCount == 0, "Epsilon should have zero eligible items")
assert(byName.Epsilon.ratio == 0, "Epsilon's ratio should be 0 when eligibleCount is 0")

-- Extra fields pass through unchanged.
assert(byName.Alpha.kind == "test", "extra fields like kind should pass through to the result")
assert(byName.Alpha.id == "alpha", "extra fields like id should pass through to the result")

-- Full sort order: Beta (ratio 1.0, targetCount 3) > Alpha (ratio 1.0,
-- targetCount 2) > Gamma (ratio 0.5) > Delta (ratio 0, targetCount 0,
-- wins the name tiebreak) > Epsilon (ratio 0, targetCount 0).
local order = {}
for i, r in ipairs(results) do
    order[i] = r.name
end
assert(order[1] == "Beta", "1st should be Beta (highest ratio, then highest targetCount)")
assert(order[2] == "Alpha", "2nd should be Alpha (same ratio as Beta, lower targetCount)")
assert(order[3] == "Gamma", "3rd should be Gamma (ratio 0.5)")
assert(order[4] == "Delta", "4th should be Delta (ratio 0, wins the name tiebreak over Epsilon)")
assert(order[5] == "Epsilon", "5th should be Epsilon (ratio 0, loses the name tiebreak to Delta)")

print("ranking_spec: OK")
```

- [ ] **Step 2: Update the harness**

Append `"tests/ranking_spec.lua"` to the `specs` list.

- [ ] **Step 3: Run and verify it fails**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `[FAIL] tests/ranking_spec.lua: ...`.

- [ ] **Step 4: Implement Ranking.lua**

`Where2Go/Core/Ranking.lua`:
```lua
-- Pure equal-outcome ranking math (docs/DECISIONS.md's "Equal-outcome
-- probability model"): for each content entry, counts how many of its
-- items are eligible (per an injected predicate) and how many of those
-- are also preferred, then ranks by that ratio. No WoW API references --
-- isEligible/isPreferred are injected so this is testable with synthetic
-- data instead of live game state.

Where2GoRanking = {}

function Where2GoRanking.RankContent(content, isEligible, isPreferred)
    local results = {}
    for _, entry in ipairs(content) do
        local eligibleCount = 0
        local targetItemIds = {}
        local seen = {}
        for _, itemId in ipairs(entry.itemIds) do
            if not seen[itemId] then
                seen[itemId] = true
                if isEligible(itemId) then
                    eligibleCount = eligibleCount + 1
                    if isPreferred(itemId) then
                        table.insert(targetItemIds, itemId)
                    end
                end
            end
        end
        local targetCount = #targetItemIds
        local ratio = eligibleCount > 0 and (targetCount / eligibleCount) or 0

        local result = {}
        for key, value in pairs(entry) do
            result[key] = value
        end
        result.eligibleCount = eligibleCount
        result.targetCount = targetCount
        result.ratio = ratio
        result.targetItemIds = targetItemIds
        table.insert(results, result)
    end

    table.sort(results, function(a, b)
        if a.ratio ~= b.ratio then
            return a.ratio > b.ratio
        end
        if a.targetCount ~= b.targetCount then
            return a.targetCount > b.targetCount
        end
        return a.name < b.name
    end)

    return results
end
```

- [ ] **Step 5: Update the manifest**

Insert `Core\Ranking.lua` immediately after `Core\RaidRanks.lua` and before
`Core\Fixtures.lua`.

- [ ] **Step 6: Run and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (8 spec files; `toc_spec` now verifies 10
files), exit code `0`.

- [ ] **Step 7: Commit**

```bash
git add Where2Go/Core/Ranking.lua tests/ranking_spec.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: add equal-outcome content ranking engine"
```

---

### Task 4: Core/DirectDrop.lua

**Files:**
- Create: `Where2Go/Core/DirectDrop.lua`
- Modify: `Where2Go/Where2Go.toc` (insert `Core\DirectDrop.lua` after
  `Core\Ranking.lua`, before `Core\Fixtures.lua`)

**Interfaces:**
- Consumes: `Where2GoSources.DUNGEONS`/`.RAIDS` (Task 1),
  `Where2GoRaidRanks.GetRaidIlvl`/`GetMythicPlusIlvl` (Task 2),
  `Where2GoRanking.RankContent` (Task 3), `Where2GoCharDB.preferredItems.DROP`
  (existing, Phase 2), `C_Item.GetItemSpecInfo`/`GetItemInfo`,
  `GetSpecialization`/`GetSpecializationInfo` (WoW API).
- Produces: `Where2GoDirectDrop.GetRankedResults()` →
  `(results, specName)` on success or `(nil, "unsupported_spec")` if no
  spec is chosen; `Where2GoDirectDrop.GetItemNames(itemIds)` → a table
  mapping each item ID to its display name (or `"Item #<id>"` if not yet
  cached). `UI/Panel.lua` (Task 5) calls both.

No unit test — WoW-API-dependent (`C_Item.*`, `GetSpecialization`).
Correctness signal is the rest of the suite staying green.

- [ ] **Step 1: Implement DirectDrop.lua**

`Where2Go/Core/DirectDrop.lua`:
```lua
-- Assembles the real ranked direct-drop content list: current-spec
-- detection, live C_Item.GetItemSpecInfo eligibility, item name lookup,
-- and calls Where2GoRanking.RankContent. WoW-API-dependent; not
-- unit-tested (Where2GoRanking carries the pure ranking math this feeds).

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

local function BuildContentList()
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

local function GetCurrentSpecIdAndName()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil, nil
    end
    local specId, specName = GetSpecializationInfo(specIndex)
    return specId, specName
end

local function IsEligibleForSpec(specId)
    return function(itemId)
        local specTable = C_Item.GetItemSpecInfo(itemId)
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
    local specId, specName = GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = BuildContentList()
    local results = Where2GoRanking.RankContent(content, IsEligibleForSpec(specId), IsPreferred)
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

- [ ] **Step 2: Update the manifest**

Insert `Core\DirectDrop.lua` immediately after `Core\Ranking.lua` and
before `Core\Fixtures.lua`.

- [ ] **Step 3: Run the automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 8 spec files; `toc_spec` now verifies
11 files), exit code `0`.

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/DirectDrop.lua Where2Go/Where2Go.toc
git commit -m "feat: assemble live direct-drop content and eligibility"
```

---

### Task 5: Rewrite UI/Panel.lua (static ranked cards) and remove Fixtures

**Files:**
- Modify (full rewrite): `Where2Go/UI/Panel.lua`
- Delete: `Where2Go/Core/Fixtures.lua`, `tests/fixtures_spec.lua`
- Modify: `tests/run_tests.lua` (remove `"tests/fixtures_spec.lua"` from
  `specs`)
- Modify: `Where2Go/Where2Go.toc` (remove the `Core\Fixtures.lua` line
  entirely)

**Interfaces:**
- Consumes: `Where2GoDirectDrop.GetRankedResults()`/`GetItemNames` (Task 4),
  `Where2GoConstants.ADDON_NAME` (existing).
- Produces: global function `Where2Go_TogglePanel()` (same name/contract
  as Phase 1 — `Core/Init.lua` is unchanged and keeps calling it).

This task's code is WoW-API-dependent and not unit-tested. This is the
first of two Panel.lua tasks: this one renders every ranked result as a
card, always fully expanded (no collapse interactivity yet — that's
Task 6). Do not implement collapse/expand in this task.

- [ ] **Step 1: Delete the fixture files**

```bash
git rm Where2Go/Core/Fixtures.lua tests/fixtures_spec.lua
```

- [ ] **Step 2: Remove fixtures_spec from the harness**

Remove the `"tests/fixtures_spec.lua"` line from the `specs` list in
`tests/run_tests.lua`.

- [ ] **Step 3: Remove Fixtures.lua from the manifest**

Delete the `Core\Fixtures.lua` line from `Where2Go/Where2Go.toc`. The file
list section should now read exactly (in this order):
```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\RaidRanks.lua
Core\Ranking.lua
Core\DirectDrop.lua
Core\Compare.lua
Core\Equipment.lua
Core\Init.lua
UI\Panel.lua
```

- [ ] **Step 4: Rewrite Panel.lua**

Replace the full contents of `Where2Go/UI/Panel.lua` with:
```lua
local panelFrame
local contentFrame
local cardFrames = {}

local function ClearCards()
    for _, card in ipairs(cardFrames) do
        card:Hide()
        card:SetParent(nil)
    end
    cardFrames = {}
end

local function CreateCard(parent, y, result)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local headerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("TOPLEFT", 0, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWidth(336)
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    headerText:SetText(string.format("%s%s   %d/%d  |cff9d9d9d(%s %d/6)|r",
        prefix, result.name, result.targetCount, result.eligibleCount, result.trackLabel, result.trackRank))

    local rowY = -18
    local itemNames = Where2GoDirectDrop.GetItemNames(result.targetItemIds)
    for _, itemId in ipairs(result.targetItemIds) do
        local row = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetJustifyH("LEFT")
        row:SetWidth(324)
        row:SetText(itemNames[itemId])
        rowY = rowY - 14
    end

    card:SetHeight(-rowY + 4)
    return card
end

local function RefreshContent()
    ClearCards()

    local results = Where2GoDirectDrop.GetRankedResults()
    if not results then
        local card = CreateFrame("Frame", nil, contentFrame)
        card:SetPoint("TOPLEFT", 0, 0)
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetText("Where2Go: no specialization selected.")
        card:SetHeight(18)
        table.insert(cardFrames, card)
        contentFrame:SetHeight(18)
        return
    end

    local y = 0
    for _, result in ipairs(results) do
        local card = CreateCard(contentFrame, y, result)
        table.insert(cardFrames, card)
        y = y - card:GetHeight() - 6
    end
    contentFrame:SetHeight(-y)
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

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 12, -40)
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

Note: `Where2GoDirectDrop.GetRankedResults()` returns two values
(`results, specNameOrError`); this step's code only uses the first
(`results`), which is `nil` on failure regardless of the second value —
correct for this step's purposes (Task 6 doesn't need the second value
either, since the fallback message doesn't display `specNameOrError`).

Known limitation, acceptable for this task (per the design spec's
out-of-scope list): if the ranked list is tall enough to exceed the
panel's fixed 500px height, cards render past the visible backdrop rather
than scrolling or clipping. Not fixed in this phase.

- [ ] **Step 5: Run the full automated suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (7 spec files — `fixtures_spec` is gone;
`toc_spec` now verifies exactly 10 files matching the File Structure's
final order), exit code `0`.

- [ ] **Step 6: Commit**

```bash
git add -A Where2Go/UI/Panel.lua tests/run_tests.lua Where2Go/Where2Go.toc
git commit -m "feat: render real ranked direct-drop cards, remove fixtures"
```

---

### Task 6: Add collapse/expand interactivity to Panel.lua

**Files:**
- Modify: `Where2Go/UI/Panel.lua`

**Interfaces:**
- No new global interfaces — `Where2Go_TogglePanel()` keeps the same
  contract. Internally, cards are now clickable and track their own
  expanded state (default `true`, per `docs/DECISIONS.md`'s updated card
  default-state rule).

Not unit-tested (WoW-API-dependent). Verified live in Task 7.

- [ ] **Step 1: Replace Panel.lua's card/layout logic**

Replace the full contents of `Where2Go/UI/Panel.lua` with:
```lua
local panelFrame
local contentFrame
local cardFrames = {}
local Layout

local function BuildHeaderText(result, expanded)
    local mark = expanded and "[-]" or "[+]"
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    return string.format("%s %s%s   %d/%d  |cff9d9d9d(%s %d/6)|r",
        mark, prefix, result.name, result.targetCount, result.eligibleCount, result.trackLabel, result.trackRank)
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
    panelFrame:SetHeight(40 + totalHeight + 12)
end

local function RefreshContent()
    for _, cardData in ipairs(cardFrames) do
        cardData.frame:Hide()
        cardData.frame:SetParent(nil)
    end
    cardFrames = {}

    local results = Where2GoDirectDrop.GetRankedResults()
    if not results then
        local msgFrame = CreateFrame("Frame", nil, contentFrame)
        msgFrame:SetPoint("TOPLEFT", 0, 0)
        local text = msgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetText("Where2Go: no specialization selected.")
        msgFrame:SetHeight(18)
        contentFrame:SetHeight(18)
        panelFrame:SetHeight(40 + 18 + 12)
        return
    end

    for _, result in ipairs(results) do
        table.insert(cardFrames, CreateCard(contentFrame, result))
    end
    Layout()
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

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 12, -40)
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

Note the `local Layout` forward declaration at the top: `CreateCard`'s
`OnClick` closure references `Layout` before it's assigned later in the
file. This works because the closure captures the upvalue by reference,
not its value at closure-creation time — by the time a player actually
clicks a header (well after the whole file has loaded), `Layout` has been
assigned. Do not reorder `Layout`'s assignment above `CreateCard`'s
definition or below `RefreshContent`'s — this exact order (declare, define
`CreateCard`, define `Layout`, define `RefreshContent`) is intentional and
must be preserved.

- [ ] **Step 2: Run the full automated suite to confirm nothing regressed**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: all specs `[PASS]` (still 7 spec files, no test touches
`Panel.lua`), exit code `0`.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/UI/Panel.lua
git commit -m "feat: add collapse/expand toggle to recommendation cards"
```

---

### Task 7: Manual live-client verification

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — verify real ranked cards live**

This step cannot be run by an agent — it requires the WoW client. Whoever
executes this task should do the following themselves and report the
result back before Phase 3 is considered done:

1. `/reload` and confirm no Lua error appears.
2. Run `/where2go` (or `/w2g`). Confirm the panel shows one card per
   Mythic+ dungeon (8) and one card per raid boss encounter (9 total: 1
   Tidebound Grotto + 8 Venomous Abyss), each showing a `target/pool`
   ratio and an `(TrackLabel rank/6)` item level, all expanded by default.
3. Add one or two real item IDs you know exist in a specific boss's pool
   (check `Where2Go/Core/Sources.lua` for real IDs, or use one you already
   know is BiS for your spec) via `/where2go pref add <itemID> drop`, then
   close and reopen the panel (`/where2go` twice, or once if it was
   closed) — confirm that boss's card now shows a non-zero target count
   and lists the item's name in its expanded row.
4. Click a card's header — confirm it collapses (item rows disappear, `[-]`
   becomes `[+]`, cards below it shift up to fill the gap) and expands
   again on a second click.
5. Confirm the ranking order looks sensible by eye: cards with a higher
   target/pool ratio appear above cards with a lower one.
6. `/where2go pref remove <itemID> drop` and reopen the panel — confirm
   the target count for that boss/dungeon returns to what it was before
   step 3.
7. Immediately after a fresh `/reload` (cold item cache), open the panel
   and note whether the ranking order looks unusually different from a
   second open a minute or two later after browsing some items/tooltips
   (which warms the client's item cache). A shift between the two is the
   known, accepted cold-cache limitation described in the design spec's
   out-of-scope list — not a bug to report, just something to be aware of.

This satisfies `docs/DEVELOPMENT_PLAN.md` Phase 3's acceptance check
(`ranking_spec.lua` already covers "a fixture with known pool sizes
produces the expected ordering" automatically; this step covers "the
first results are expanded by default in the live panel" — now "all
results," per the updated `docs/DECISIONS.md` rule).

---

## Done

Phase 3 is complete when all seven tasks' commits exist and the Task 7
manual checkpoint has been confirmed in a live client. Phase 4 (Voidcore
recommendations) starts a new plan built on this foundation.
