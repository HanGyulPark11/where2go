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
