-- Pure equal-outcome ranking math (docs/DECISIONS.md's "Equal-outcome
-- probability model"): for each content entry, counts how many of its
-- items are eligible (per an injected predicate) and how many of those
-- are also preferred, then ranks by that ratio. No WoW API references --
-- isEligible/isPreferred are injected so this is testable with synthetic
-- data instead of live game state.

Where2GoRanking = {}

function Where2GoRanking.RankContent(content, isEligible, isPreferred)
    local results = {}
    for _, entry in ipairs(content) do
        local eligibleCount = 0
        local targetItemIds = {}
        local seen = {}
        for _, itemId in ipairs(entry.itemIds) do
            if not seen[itemId] then
                seen[itemId] = true
                if isEligible(itemId) then
                    eligibleCount = eligibleCount + 1
                    if isPreferred(itemId) then
                        table.insert(targetItemIds, itemId)
                    end
                end
            end
        end
        local targetCount = #targetItemIds
        local ratio = eligibleCount > 0 and (targetCount / eligibleCount) or 0

        local result = {}
        for key, value in pairs(entry) do
            result[key] = value
        end
        result.eligibleCount = eligibleCount
        result.targetCount = targetCount
        result.ratio = ratio
        result.targetItemIds = targetItemIds
        table.insert(results, result)
    end

    table.sort(results, function(a, b)
        if a.ratio ~= b.ratio then
            return a.ratio > b.ratio
        end
        if a.targetCount ~= b.targetCount then
            return a.targetCount > b.targetCount
        end
        return a.name < b.name
    end)

    return results
end
