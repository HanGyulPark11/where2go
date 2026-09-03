dofile("Where2Go/Core/ItemStats.lua")
dofile("Where2Go/Core/Sources.lua")

assert(type(Where2GoItemStats) == "table", "Where2GoItemStats should be a table")
assert(type(Where2GoItemStats.STATS) == "table", "Where2GoItemStats.STATS should be a table")

local count = 0
for _ in pairs(Where2GoItemStats.STATS) do
    count = count + 1
end
assert(count > 0, "Where2GoItemStats.STATS should be non-empty")

local VALID_SECONDARY = {
    CRIT_RATING = true, HASTE_RATING = true, MASTERY_RATING = true, VERSATILITY = true,
}

for itemId, stats in pairs(Where2GoItemStats.STATS) do
    assert(type(itemId) == "number", "item stat keys should be numeric item IDs")
    assert(type(stats.secondaryStats) == "table", "secondaryStats should be a table for item " .. itemId)
    for _, stat in ipairs(stats.secondaryStats) do
        assert(VALID_SECONDARY[stat], "unexpected secondary stat '" .. tostring(stat) .. "' for item " .. itemId)
    end
end

-- Cross-check that every item Sources.lua references has a corresponding
-- entry here, so a future season changeover that regenerates Sources.lua
-- can't silently leave ItemStats.lua stale.
local sourceItemIds = {}
local function collectItemIds(instances)
    for _, instance in ipairs(instances) do
        for _, encounter in ipairs(instance.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                sourceItemIds[itemId] = true
            end
        end
    end
end
collectItemIds(Where2GoSources.DUNGEONS)
collectItemIds(Where2GoSources.RAIDS)

local coverageCount = 0
for itemId in pairs(sourceItemIds) do
    assert(
        Where2GoItemStats.STATS[itemId] ~= nil,
        "Where2GoItemStats.STATS is missing an entry for item " .. itemId .. " referenced in Sources.lua"
    )
    coverageCount = coverageCount + 1
end

print("itemstats_spec: OK, " .. count .. " item(s) with stat data, " .. coverageCount .. " item(s) cross-checked against Sources.lua")
