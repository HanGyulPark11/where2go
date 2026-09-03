-- Fixture pool: 4 items across 2 dungeon bosses and 1 raid boss
local function fixturePool()
    return {
        { itemId = 100, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 101, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 200, bossId = 2, bossName = "Boss B", contentName = "Dungeon One", raidName = nil, kind = "dungeon" },
        { itemId = 300, bossId = 3, bossName = "Boss C", contentName = "Raid One", raidName = "Raid One", kind = "raid" },
    }
end

local function fixtureContext()
    local slots = { [100] = "HEAD", [101] = "TRINKET", [200] = "TRINKET", [300] = "WEAPON" }
    local eligible = { [100] = true, [101] = true, [200] = false, [300] = true }
    local names = { [100] = "Helm of Testing", [101] = "Trinket Alpha", [200] = "Trinket Beta", [300] = "Sword of Fixtures" }
    return {
        getSlot = function(itemId) return slots[itemId] end,
        isEligible = function(itemId) return eligible[itemId] end,
        getItemName = function(itemId) return names[itemId] end,
    }
end

dofile("Where2Go/Core/ItemBrowser.lua")

-- BuildItemPool: reads real Where2GoSources -- exercised in Step 4's
-- structural check below, not with fixtures (it has no parameters to
-- inject fixture data through).

-- FilterItems: dungeon filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Raid One" }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 300, "dungeonName filter should isolate the raid boss's item")
end

-- FilterItems: boss filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { bossName = "Boss A" }, fixtureContext())
    assert(#results == 2, "bossName filter should return both Boss A items")
end

-- FilterItems: slot filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { slot = "TRINKET" }, fixtureContext())
    assert(#results == 2, "slot filter should return both trinkets (101, 200)")
end

-- FilterItems: specEligibleOnly filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { specEligibleOnly = true }, fixtureContext())
    assert(#results == 3, "specEligibleOnly should exclude itemId 200 (ineligible)")
end

-- FilterItems: searchText filter (case-insensitive substring)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { searchText = "trinket" }, fixtureContext())
    assert(#results == 2, "searchText 'trinket' should match both trinket names")
end

-- FilterItems: stat filter
do
    local savedItemStats = Where2GoItemStats
    Where2GoItemStats = { STATS = {
        [100] = { secondaryStats = { "CRIT_RATING" } },
        [101] = { secondaryStats = { "HASTE_RATING" } },
    } }
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { stats = { "HASTE_RATING" } }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 101, "stat filter should match only item 101's Haste")
    Where2GoItemStats = savedItemStats
end

-- FilterItems: combined filters (AND logic)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Dungeon One", slot = "TRINKET" }, fixtureContext())
    assert(#results == 2, "combined dungeon+slot filter should AND together")
end

-- FilterItems: no matches
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { dungeonName = "Nonexistent" }, fixtureContext())
    assert(#results == 0, "an impossible filter should return an empty (not nil) array")
end

-- FilterItems: items with no resolvable slot (non-equipment loot) are always excluded
do
    local poolWithNonEquip = fixturePool()
    table.insert(poolWithNonEquip, { itemId = 400, bossId = 3, bossName = "Boss C", contentName = "Raid One", raidName = "Raid One", kind = "raid" })
    local context = fixtureContext()
    -- itemId 400 has no entry in fixtureContext()'s slots table, so getSlot(400) returns nil
    local results = Where2GoItemBrowser.FilterItems(poolWithNonEquip, {}, context)
    local found400 = false
    for _, entry in ipairs(results) do
        if entry.itemId == 400 then found400 = true end
    end
    assert(not found400, "an item with no resolvable equip slot should never appear, even with no filters applied")
    assert(#results == 4, "the 4 original fixture items (all of which have slots) should still all pass with no filters")
end

-- SortItems: by name
do
    local sorted = Where2GoItemBrowser.SortItems(fixturePool(), "NAME", fixtureContext())
    assert(sorted[1].itemId == 100, "sorted by name, 'Helm of Testing' should sort before the others alphabetically")
end

-- SortItems: default (dungeon/boss order), does not mutate the input
do
    local original = fixturePool()
    local sorted = Where2GoItemBrowser.SortItems(original, nil, fixtureContext())
    assert(sorted ~= original, "SortItems should return a new array, not mutate the input in place")
    assert(sorted[1].contentName == "Dungeon One" and sorted[#sorted].contentName == "Raid One",
        "default sort should keep dungeon-before-raid pool order")
end

print("itembrowser_spec: OK")

dofile("Where2Go/Core/Sources.lua")
local realPool = Where2GoItemBrowser.BuildItemPool()
assert(#realPool > 0, "BuildItemPool() should return a non-empty pool against real Sources.lua")
for _, entry in ipairs(realPool) do
    assert(type(entry.itemId) == "number", "every pool entry should have a numeric itemId")
    assert(type(entry.bossName) == "string" and #entry.bossName > 0, "every pool entry should have a bossName")
    assert(type(entry.contentName) == "string" and #entry.contentName > 0, "every pool entry should have a contentName")
end
print("itembrowser_spec: OK, " .. #realPool .. " real pool entries")
