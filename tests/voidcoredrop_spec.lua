Where2GoDirectDrop = {
    BuildContentList = function()
        return {
            { id = "dungeon:1", kind = "dungeon", ilvl = 311, trackKey = "HERO", trackRank = 3, bonusId = 12843 },
            { id = "boss:2888", kind = "raid", ilvl = 318, trackKey = "MYTH", trackRank = 1, bonusId = 12849 },
            { id = "boss:2883", kind = "raid", ilvl = 344, trackKey = "MYTH", trackRank = 9, bonusId = 13848 },
        }
    end,
}

Where2GoRaidRanks = {
    GetVoidcoreRaidIlvl = function(bossId)
        if bossId == 2883 then return 344, "MYTH", 9, 13848 end
        return 334, "MYTH", 6, 12854
    end,
}

dofile("Where2Go/Core/VoidcoreDrop.lua")

local content = Where2GoVoidcoreDrop.BuildContentList()
assert(content[1].ilvl == 311 and content[1].trackRank == 3,
    "Voidcore dungeon reward metadata should remain unchanged")
assert(content[2].ilvl == 334 and content[2].trackRank == 6 and content[2].bonusId == 12854,
    "Voidcore standard Mythic raid bosses should use Myth 6/6 reward metadata")
assert(content[3].ilvl == 344 and content[3].trackRank == 9 and content[3].bonusId == 13848,
    "Voidcore final Mythic raid bosses should use Myth 9/6 reward metadata")

local direct = Where2GoDirectDrop.BuildContentList()
assert(direct[2].ilvl == 318 and direct[2].trackRank == 1,
    "building Voidcore content must not mutate direct-drop reward metadata")

print("voidcoredrop_spec: OK")
