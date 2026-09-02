-- Assembles the real ranked direct-drop content list: current-spec
-- detection, live C_Item.GetItemSpecInfo eligibility, item name lookup,
-- and calls Where2GoRanking.RankContent. WoW-API-dependent; not
-- unit-tested (Where2GoRanking carries the pure ranking math this feeds).

Where2GoDirectDrop = {}

local function FlattenItemIds(encounters)
    local ids = {}
    for _, encounter in ipairs(encounters) do
        for _, itemId in ipairs(encounter.itemIds) do
            table.insert(ids, itemId)
        end
    end
    return ids
end

local function BuildContentList()
    local content = {}

    local mplusIlvl, mplusTrackLabel, mplusRank = Where2GoRaidRanks.GetMythicPlusIlvl()
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(content, {
            id = "dungeon:" .. dungeon.instanceId,
            name = dungeon.name,
            kind = "dungeon",
            raidName = nil,
            itemIds = FlattenItemIds(dungeon.encounters),
            ilvl = mplusIlvl,
            trackLabel = mplusTrackLabel,
            trackRank = mplusRank,
        })
    end

    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            local ilvl, trackLabel, rank = Where2GoRaidRanks.GetRaidIlvl(encounter.bossId)
            table.insert(content, {
                id = "boss:" .. encounter.bossId,
                name = encounter.name,
                kind = "raid",
                raidName = raid.name,
                itemIds = encounter.itemIds,
                ilvl = ilvl,
                trackLabel = trackLabel,
                trackRank = rank,
            })
        end
    end

    return content
end

local function GetCurrentSpecIdAndName()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil, nil
    end
    local specId, specName = GetSpecializationInfo(specIndex)
    return specId, specName
end

local function IsEligibleForSpec(specId)
    return function(itemId)
        local specTable = C_Item.GetItemSpecInfo(itemId)
        if not specTable then
            return true
        end
        for _, id in ipairs(specTable) do
            if id == specId then
                return true
            end
        end
        return false
    end
end

local function IsPreferred(itemId)
    return Where2GoCharDB.preferredItems.DROP[itemId] == true
end

-- Returns (results, specName) on success, or (nil, "unsupported_spec") if
-- the player has no specialization chosen. `results` is
-- Where2GoRanking.RankContent's output, ranked best-first.
function Where2GoDirectDrop.GetRankedResults()
    local specId, specName = GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = BuildContentList()
    local results = Where2GoRanking.RankContent(content, IsEligibleForSpec(specId), IsPreferred)
    return results, specName
end

-- Resolves display names for a list of item IDs, falling back to a
-- placeholder for anything not yet cached by the client.
function Where2GoDirectDrop.GetItemNames(itemIds)
    local names = {}
    for _, itemId in ipairs(itemIds) do
        local name = C_Item.GetItemInfo(itemId)
        names[itemId] = name or ("Item #" .. itemId)
    end
    return names
end
