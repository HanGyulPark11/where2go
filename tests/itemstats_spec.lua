dofile("Where2Go/Core/ItemStats.lua")

assert(type(Where2GoItemStats) == "table", "Where2GoItemStats should be a table")
assert(type(Where2GoItemStats.STATS) == "table", "Where2GoItemStats.STATS should be a table")

local count = 0
for _ in pairs(Where2GoItemStats.STATS) do
    count = count + 1
end
assert(count > 0, "Where2GoItemStats.STATS should be non-empty")

local VALID_PRIMARY = { STRENGTH = true, AGILITY = true, INTELLECT = true }
local VALID_SECONDARY = {
    CRIT_RATING = true, HASTE_RATING = true, MASTERY_RATING = true, VERSATILITY = true,
}

for itemId, stats in pairs(Where2GoItemStats.STATS) do
    assert(type(itemId) == "number", "item stat keys should be numeric item IDs")
    assert(type(stats.primaryStats) == "table", "primaryStats should be a table for item " .. itemId)
    assert(type(stats.secondaryStats) == "table", "secondaryStats should be a table for item " .. itemId)
    for _, stat in ipairs(stats.primaryStats) do
        assert(VALID_PRIMARY[stat], "unexpected primary stat '" .. tostring(stat) .. "' for item " .. itemId)
    end
    for _, stat in ipairs(stats.secondaryStats) do
        assert(VALID_SECONDARY[stat], "unexpected secondary stat '" .. tostring(stat) .. "' for item " .. itemId)
    end
end

print("itemstats_spec: OK, " .. count .. " item(s) with stat data")
