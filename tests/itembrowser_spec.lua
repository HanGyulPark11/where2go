-- Fixture pool: 4 items across 2 dungeon bosses (same dungeon) and 1 raid boss
local function fixturePool()
    return {
        { itemId = 100, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 101, bossId = 1, bossName = "Boss A", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 200, bossId = 2, bossName = "Boss B", contentName = "Dungeon One", raidName = nil, kind = "dungeon", sourceKey = "dungeon:1" },
        { itemId = 300, bossId = 3, bossName = "Boss C", contentName = "Raid One", raidName = "Raid One", kind = "raid", sourceKey = "boss:3" },
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

-- FilterItems: a dungeon source key selects that whole dungeon's items,
-- regardless of which of its bosses dropped them (dungeons are a
-- whole-run unit, not filtered per-boss)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true } }, fixtureContext())
    assert(#results == 3, "dungeon:1 source key should return all 3 Dungeon One items across both its bosses")
end

-- FilterItems: a raid boss source key selects only that boss's item
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["boss:3"] = true } }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 300, "boss:3 source key should isolate the raid boss's item")
end

-- FilterItems: multiple selected source keys union together (OR, not AND)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true, ["boss:3"] = true } }, fixtureContext())
    assert(#results == 4, "selecting a dungeon key and a boss key together should return the union of both")
end

-- FilterItems: empty sources table means no filter
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = {} }, fixtureContext())
    assert(#results == 4, "an empty sources table should not filter anything out")
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

-- FilterItems: multiple selected stats require ALL of them (AND, not OR/union)
do
    local savedItemStats = Where2GoItemStats
    Where2GoItemStats = { STATS = {
        [100] = { secondaryStats = { "CRIT_RATING" } },
        [101] = { secondaryStats = { "HASTE_RATING" } },
        [200] = { secondaryStats = { "CRIT_RATING", "HASTE_RATING" } },
    } }
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { stats = { "HASTE_RATING", "CRIT_RATING" } }, fixtureContext())
    assert(#results == 1 and results[1].itemId == 200, "selecting two stats should require an item to have BOTH, matching only item 200")
    Where2GoItemStats = savedItemStats
end

-- FilterItems: combined filters (AND logic)
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:1"] = true }, slot = "TRINKET" }, fixtureContext())
    assert(#results == 2, "combined source+slot filter should AND together")
end

-- FilterItems: no matches
do
    local results = Where2GoItemBrowser.FilterItems(fixturePool(), { sources = { ["dungeon:999"] = true } }, fixtureContext())
    assert(#results == 0, "an impossible source key should return an empty (not nil) array")
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
    assert(type(entry.sourceKey) == "string" and entry.sourceKey:match("^dungeon:%d+$") or entry.sourceKey:match("^boss:%d+$"),
        "every pool entry's sourceKey should match 'dungeon:<id>' or 'boss:<id>', got " .. tostring(entry.sourceKey))
end
print("itembrowser_spec: OK, " .. #realPool .. " real pool entries")
