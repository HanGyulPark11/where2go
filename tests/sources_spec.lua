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
