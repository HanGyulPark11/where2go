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

-- Returns (results, specName) on success, or (nil, "unsupported_spec") --
-- same contract as Where2GoDirectDrop.GetRankedResults().
function Where2GoVoidcoreDrop.GetRankedResults()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    if not specId then
        return nil, "unsupported_spec"
    end
    local content = Where2GoDirectDrop.BuildContentList()
    local specEligible = Where2GoDirectDrop.IsEligibleForSpec(specId)
    local function isEligible(itemId)
        return specEligible(itemId) and not IsObtained(itemId)
    end
    local results = Where2GoRanking.RankContent(content, isEligible, IsPreferredVoidcore)
    return results, specName
end
