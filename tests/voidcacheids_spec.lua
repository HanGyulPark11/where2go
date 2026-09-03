dofile("Where2Go/Core/VoidcacheIds.lua")
dofile("Where2Go/Core/Sources.lua")

assert(type(Where2GoVoidcacheIds) == "table", "Where2GoVoidcacheIds should be a table")
assert(type(Where2GoVoidcacheIds.DUNGEONS) == "table", "Where2GoVoidcacheIds.DUNGEONS should be a table")
assert(type(Where2GoVoidcacheIds.RAID_BOSSES) == "table", "Where2GoVoidcacheIds.RAID_BOSSES should be a table")

local dungeonCount = 0
for instanceId, itemId in pairs(Where2GoVoidcacheIds.DUNGEONS) do
    assert(type(instanceId) == "number", "DUNGEONS keys should be numeric instance IDs")
    assert(type(itemId) == "number", "DUNGEONS values should be numeric item IDs")
    dungeonCount = dungeonCount + 1
end
assert(dungeonCount > 0, "Where2GoVoidcacheIds.DUNGEONS should be non-empty")

local bossCount = 0
for bossId, itemId in pairs(Where2GoVoidcacheIds.RAID_BOSSES) do
    assert(type(bossId) == "number", "RAID_BOSSES keys should be numeric boss IDs")
    assert(type(itemId) == "number", "RAID_BOSSES values should be numeric item IDs")
    bossCount = bossCount + 1
end
assert(bossCount > 0, "Where2GoVoidcacheIds.RAID_BOSSES should be non-empty")

-- Cross-check every Sources.lua dungeon/boss has a corresponding
-- Voidcache item ID, so a season changeover that regenerates Sources.lua
-- can't silently leave VoidcacheIds.lua stale.
for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
    assert(
        Where2GoVoidcacheIds.DUNGEONS[dungeon.instanceId] ~= nil,
        "Where2GoVoidcacheIds.DUNGEONS is missing an entry for instance " .. dungeon.instanceId .. " (" .. dungeon.name .. ")"
    )
end

for _, raid in ipairs(Where2GoSources.RAIDS) do
    for _, encounter in ipairs(raid.encounters) do
        assert(
            Where2GoVoidcacheIds.RAID_BOSSES[encounter.bossId] ~= nil,
            "Where2GoVoidcacheIds.RAID_BOSSES is missing an entry for boss " .. encounter.bossId .. " (" .. encounter.name .. ")"
        )
    end
end

print("voidcacheids_spec: OK, " .. dungeonCount .. " dungeon(s), " .. bossCount .. " raid boss(es), all cross-checked against Sources.lua")
