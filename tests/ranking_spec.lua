dofile("Where2Go/Core/Ranking.lua")

local content = {
    { id = "alpha", name = "Alpha", kind = "test", itemIds = { 101, 102 } },
    { id = "beta", name = "Beta", kind = "test", itemIds = { 201, 202, 203, 204 } },
    { id = "gamma", name = "Gamma", kind = "test", itemIds = { 301, 301, 302 } },
    { id = "delta", name = "Delta", kind = "test", itemIds = { 401, 402 } },
    { id = "epsilon", name = "Epsilon", kind = "test", itemIds = { 501 } },
}

-- 204 is deliberately NOT eligible (simulates a wrong-armor-type item);
-- 501 is deliberately NOT eligible at all (Epsilon's only item).
local eligible = {
    [101] = true, [102] = true,
    [201] = true, [202] = true, [203] = true,
    [301] = true, [302] = true,
    [401] = true, [402] = true,
}
local preferred = {
    [101] = true, [102] = true,
    [201] = true, [202] = true, [203] = true,
    [301] = true,
}

local function isEligible(itemId) return eligible[itemId] == true end
local function isPreferred(itemId) return preferred[itemId] == true end

local results = Where2GoRanking.RankContent(content, isEligible, isPreferred)

assert(#results == 5, "should return all 5 entries")

local byName = {}
for _, r in ipairs(results) do
    byName[r.name] = r
end

-- Eligibility filtering: Beta's item 204 is not eligible, so its pool is 3, not 4.
assert(byName.Beta.eligibleCount == 3, "Beta's eligibleCount should exclude the non-eligible item 204")
assert(byName.Beta.targetCount == 3, "Beta's targetCount should be 3")
assert(byName.Beta.ratio == 1.0, "Beta's ratio should be 1.0")

-- Dedup: Gamma's duplicate item 301 must only count once.
assert(byName.Gamma.eligibleCount == 2, "Gamma's duplicate item 301 must not be double-counted in eligibleCount")
assert(byName.Gamma.targetCount == 1, "Gamma's duplicate item 301 must not be double-counted in targetCount")
assert(#byName.Gamma.targetItemIds == 1, "Gamma's targetItemIds must not contain the duplicate")

-- Zero-eligible-pool edge case must not divide by zero or error.
assert(byName.Epsilon.eligibleCount == 0, "Epsilon should have zero eligible items")
assert(byName.Epsilon.ratio == 0, "Epsilon's ratio should be 0 when eligibleCount is 0")

-- Extra fields pass through unchanged.
assert(byName.Alpha.kind == "test", "extra fields like kind should pass through to the result")
assert(byName.Alpha.id == "alpha", "extra fields like id should pass through to the result")

-- Full sort order: Beta (ratio 1.0, targetCount 3) > Alpha (ratio 1.0,
-- targetCount 2) > Gamma (ratio 0.5) > Delta (ratio 0, targetCount 0,
-- wins the name tiebreak) > Epsilon (ratio 0, targetCount 0).
local order = {}
for i, r in ipairs(results) do
    order[i] = r.name
end
assert(order[1] == "Beta", "1st should be Beta (highest ratio, then highest targetCount)")
assert(order[2] == "Alpha", "2nd should be Alpha (same ratio as Beta, lower targetCount)")
assert(order[3] == "Gamma", "3rd should be Gamma (ratio 0.5)")
assert(order[4] == "Delta", "4th should be Delta (ratio 0, wins the name tiebreak over Epsilon)")
assert(order[5] == "Epsilon", "5th should be Epsilon (ratio 0, loses the name tiebreak to Delta)")

print("ranking_spec: OK")
