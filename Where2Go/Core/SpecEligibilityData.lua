-- Precomputed all-class spec-eligibility data: for every class/spec in
-- the game, which of Where2Go's tracked dungeon/raid items that spec can
-- actually receive as loot, per Blizzard's own server-computed loot
-- table (built via Core/SpecEligibilityScan.lua's Encounter Journal
-- loot-filter scan). See
-- docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md.
-- Do not hand-edit item/spec entries directly -- regenerate via
-- `/where2go genspec` (see docs/SEASON_CHECKLIST.md) and hand-merge the
-- reviewed result here, the same convention as Sources.lua/ItemStats.lua.
--
-- Starts empty until the first `/where2go genspec` generation pass --
-- which scans every class and spec in the game in a single run -- is
-- performed and hand-merged in. Core/DirectDrop.lua's IsEligibleForSpec
-- falls back to its own heuristic for any spec with no entry here yet.

Where2GoSpecEligibilityData = {}

Where2GoSpecEligibilityData.BY_SPEC = {
    -- [specId] = { [itemId] = true, ... },
}
