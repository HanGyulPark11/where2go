-- Voidcore-specific ranked results: reuses Where2GoDirectDrop's content
-- assembly and spec detection, but filters out items already obtained via
-- Voidcore (Where2GoCharDB.voidcoreObtainedItems) and ranks against the
-- separate preferredItems.VOIDCORE list instead of .DROP. WoW-API-
-- dependent; not unit-tested (Where2GoRanking carries the pure ranking
-- math this feeds).

Where2GoVoidcoreDrop = {}

local function IsObtained(itemId)
    return Where2GoCharDB.voidcoreObtainedItems[itemId] == true
end

local function IsPreferredVoidcore(itemId)
    return Where2GoCharDB.preferredItems.VOIDCORE[itemId] == true
end

-- Voidcore rolls match Great Vault-equivalent reward levels, which differ
-- from direct drops. Copy entries before applying those levels so the Drop
-- view remains unchanged.
function Where2GoVoidcoreDrop.BuildContentList()
    local content = {}
    for _, sourceEntry in ipairs(Where2GoDirectDrop.BuildContentList()) do
        local entry = {}
        for key, value in pairs(sourceEntry) do
            entry[key] = value
        end
        if entry.kind == "dungeon" then
            entry.ilvl, entry.trackKey, entry.trackRank, entry.bonusId =
                Where2GoRaidRanks.GetVoidcoreDungeonIlvl()
        elseif entry.kind == "raid" then
            local bossId = tonumber(string.match(entry.id or "", "^boss:(%d+)$"))
            if bossId then
                entry.ilvl, entry.trackKey, entry.trackRank, entry.bonusId =
                    Where2GoRaidRanks.GetVoidcoreRaidIlvl(bossId)
            end
        end
        table.insert(content, entry)
    end
    return content
end

-- Returns (results, specName) on success, or (nil, "unsupported_spec") --
-- same contract as Where2GoDirectDrop.GetRankedResults().
function Where2GoVoidcoreDrop.GetRankedResults()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = Where2GoVoidcoreDrop.BuildContentList()
    local specEligible = Where2GoDirectDrop.IsEligibleForSpec(specId)
    local ownedUsable = Where2GoDirectDrop.IsOwnedUsableForSpec(specId)
    local owned = Where2GoEquipment.GetOwnedSnapshot()
    local mode = Where2GoEquipment.GetOwnershipMode()
    local function isEligible(itemId)
        return specEligible(itemId) and not IsObtained(itemId)
    end
    local function isPreferred(itemId, entry)
        return IsPreferredVoidcore(itemId)
            and not Where2GoEquipment.HasOwnedAtLeast(owned, itemId, entry, mode, ownedUsable)
    end
    local results = Where2GoRanking.RankContent(content, isEligible, isPreferred)
    return results, specName
end
