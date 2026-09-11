-- Break caught: a static effect/context variant is missing, reordered, or
-- includes the calculated upgrade-track bonus that ItemRow must append.
dofile("Where2Go/Core/ItemLinkBonuses.lua")

local bonuses = assert(Where2GoItemLinkBonuses, "item-link bonus data should be exported")

local function assertBonusList(itemId, expected)
    local actual = bonuses.EXTRA_BONUSES[itemId]
    assert(actual and #actual == #expected, "expected the static bonus count for item " .. itemId)
    for i, bonusId in ipairs(expected) do
        assert(actual[i] == bonusId,
            string.format("expected item %d static bonus %d at position %d, got %s", itemId, bonusId, i,
                tostring(actual[i])))
    end
end

assertBonusList(268265, { 13335, 13668, 13987 })
assertBonusList(271876, { 13335, 13846 })
assertBonusList(268253, { 6652, 13662, 13334, 13696 })
assert(bonuses.EXTRA_BONUSES[270164] == nil, "ordinary items must not gain invented static bonuses")
assert(bonuses.EXTRA_BONUSES[268258] == nil, "ordinary items must remain track-only")
local entryCount = 0
for _ in pairs(bonuses.EXTRA_BONUSES) do entryCount = entryCount + 1 end
assert(entryCount == 3, "only the three curated static effect/context variants may be declared")

print("itemlinkbonuses_spec: OK")
