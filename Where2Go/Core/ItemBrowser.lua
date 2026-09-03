-- Pure per-boss item pool/filter/sort logic for the item browser. No WoW
-- API dependency -- callers pass in slot/eligibility/name lookups via a
-- `context` table rather than this module calling live APIs itself, so
-- it can be unit-tested with fixture data the same way Ranking.lua is.

Where2GoItemBrowser = {}

function Where2GoItemBrowser.BuildItemPool()
    local pool = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        for _, encounter in ipairs(dungeon.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                table.insert(pool, {
                    itemId = itemId,
                    bossId = encounter.bossId,
                    bossName = encounter.name,
                    contentName = dungeon.name,
                    raidName = nil,
                    kind = "dungeon",
                })
            end
        end
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                table.insert(pool, {
                    itemId = itemId,
                    bossId = encounter.bossId,
                    bossName = encounter.name,
                    contentName = raid.name,
                    raidName = raid.name,
                    kind = "raid",
                })
            end
        end
    end
    return pool
end

local function matchesFilters(entry, filters, context)
    if filters.dungeonName and entry.contentName ~= filters.dungeonName then
        return false
    end
    if filters.bossName and entry.bossName ~= filters.bossName then
        return false
    end
    if filters.slot and context.getSlot(entry.itemId) ~= filters.slot then
        return false
    end
    if filters.stats and #filters.stats > 0 then
        local itemStats = Where2GoItemStats.STATS[entry.itemId]
        if not itemStats then
            return false
        end
        local matchesAny = false
        for _, wantedStat in ipairs(filters.stats) do
            for _, s in ipairs(itemStats.secondaryStats) do
                if s == wantedStat then
                    matchesAny = true
                end
            end
        end
        if not matchesAny then
            return false
        end
    end
    if filters.specEligibleOnly and not context.isEligible(entry.itemId) then
        return false
    end
    if filters.searchText and filters.searchText ~= "" then
        local name = context.getItemName(entry.itemId)
        if not name or not name:lower():find(filters.searchText:lower(), 1, true) then
            return false
        end
    end
    return true
end

function Where2GoItemBrowser.FilterItems(pool, filters, context)
    local results = {}
    for _, entry in ipairs(pool) do
        if matchesFilters(entry, filters, context) then
            table.insert(results, entry)
        end
    end
    return results
end

function Where2GoItemBrowser.SortItems(items, sortMode, context)
    local sorted = {}
    for _, item in ipairs(items) do
        table.insert(sorted, item)
    end
    if sortMode == "NAME" then
        table.sort(sorted, function(a, b)
            return (context.getItemName(a.itemId) or "") < (context.getItemName(b.itemId) or "")
        end)
    end
    return sorted
end
