dofile("Where2Go/Core/Tracks.lua")
dofile("Where2Go/Core/RaidRanks.lua")

local MYTH = Where2GoTracks.UPGRADE_TRACKS.MYTH

local expectedRank = {
    [2888] = 1, [2874] = 2, [2894] = 2, [2882] = 3,
    [2871] = 3, [2887] = 3,
}

for bossId, rank in pairs(expectedRank) do
    local ilvl, trackKey, actualRank, bonusId = Where2GoRaidRanks.GetRaidIlvl(bossId)
    assert(actualRank == rank, "bossId " .. bossId .. " should be rank " .. rank)
    assert(ilvl == MYTH.ilvls[rank], "bossId " .. bossId .. " ilvl should match MYTH.ilvls[" .. rank .. "]")
    assert(trackKey == "MYTH", "bossId " .. bossId .. " track key should be MYTH")
    assert(bonusId == MYTH.bonusIdStart + rank - 1, "bossId " .. bossId .. " bonusId should match MYTH's bonusIdStart + rank - 1")
end

-- The final two Venomous Abyss bosses drop a special Myth 9/6 track at
-- ilvl 344, above the normal 1-4 rank cap (see RaidRanks.lua's
-- MYTH_FINAL_BOSS_IDS).
local coiledAltarIlvl, coiledAltarTrackKey, coiledAltarRank, coiledAltarBonusId = Where2GoRaidRanks.GetRaidIlvl(2883)
assert(coiledAltarIlvl == 344, "The Coiled Altar (2883) should be the special Myth 9/6 ilvl 344")
assert(coiledAltarRank == 9, "The Coiled Altar (2883) should be rank 9")
assert(coiledAltarTrackKey == "MYTH", "The Coiled Altar (2883) track key should still be MYTH")
assert(coiledAltarBonusId == 13848, "The Coiled Altar (2883) should use the confirmed Myth-final bonus ID 13848")

local ulatekIlvl, ulatekTrackKey, ulatekRank, ulatekBonusId = Where2GoRaidRanks.GetRaidIlvl(2895)
assert(ulatekIlvl == 344, "Ula'tek (2895) should be the special Myth 9/6 ilvl 344")
assert(ulatekRank == 9, "Ula'tek (2895) should be rank 9")
assert(ulatekTrackKey == "MYTH", "Ula'tek (2895) track key should still be MYTH")
assert(ulatekBonusId == 13848, "Ula'tek (2895) should use the confirmed Myth-final bonus ID 13848")

-- An unlisted boss ID defaults to rank 1 (single-boss raids like The
-- Tidebound Grotto's Nymrissa Wavecaller, bossId 2849).
local ilvl, trackKey, rank, bonusId = Where2GoRaidRanks.GetRaidIlvl(2849)
assert(rank == 1, "unlisted bossId should default to rank 1")
assert(ilvl == MYTH.ilvls[1], "unlisted bossId's ilvl should be MYTH.ilvls[1]")
assert(bonusId == MYTH.bonusIdStart, "unlisted bossId's bonusId should be MYTH's bonusIdStart (rank 1)")

local mplusIlvl, mplusTrackKey, mplusRank, mplusBonusId = Where2GoRaidRanks.GetMythicPlusIlvl()
local HERO = Where2GoTracks.UPGRADE_TRACKS.HERO
assert(mplusRank == 3, "Mythic+ should be fixed at rank 3")
assert(mplusIlvl == HERO.ilvls[3], "Mythic+ ilvl should be HERO.ilvls[3]")
assert(mplusTrackKey == "HERO", "Mythic+ track key should be HERO")
assert(mplusBonusId == HERO.bonusIdStart + 2, "Mythic+ bonusId should be HERO's bonusIdStart + 2 (rank 3)")

-- Voidcore raid rewards follow the equivalent Great Vault level rather
-- than the direct boss-drop level. Bosses 1-6 award fully upgraded Myth
-- gear; the final two keep their special Myth 9/6 level.
for bossId in pairs(expectedRank) do
    local voidIlvl, voidTrackKey, voidRank, voidBonusId = Where2GoRaidRanks.GetVoidcoreRaidIlvl(bossId)
    assert(voidIlvl == MYTH.ilvls[6], "Voidcore bossId " .. bossId .. " should be Myth 6/6")
    assert(voidTrackKey == "MYTH", "Voidcore raid track should be MYTH")
    assert(voidRank == 6, "Voidcore bossId " .. bossId .. " should be rank 6")
    assert(voidBonusId == MYTH.bonusIdStart + 5, "Voidcore Myth 6/6 should use the rank-6 bonus ID")
end

local voidFinalIlvl, voidFinalTrackKey, voidFinalRank, voidFinalBonusId = Where2GoRaidRanks.GetVoidcoreRaidIlvl(2883)
assert(voidFinalIlvl == 344 and voidFinalTrackKey == "MYTH" and voidFinalRank == 9 and voidFinalBonusId == 13848,
    "Voidcore final bosses should remain Myth 9/6 ilvl 344")

print("raidranks_spec: OK")
