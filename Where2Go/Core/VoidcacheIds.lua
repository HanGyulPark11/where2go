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
--
-- Any edit to this file (or to Sources.lua's item pools), including a
-- mid-season correction, requires bumping Where2GoConstants.SEASON_LABEL
-- in Core/Constants.lua to force a re-scan. Where2GoCharDB.specEligibility's
-- staleness check only compares against SEASON_LABEL, and absence from a
-- cached bySpec[specId] means "ineligible" (not "unknown") -- so without
-- a SEASON_LABEL bump, a newly-added item would show as ineligible for
-- the rest of the season until the next full season bump.

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
