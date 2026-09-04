dofile("Where2Go/Core/SpecEligibilityData.lua")

assert(type(Where2GoSpecEligibilityData) == "table", "Where2GoSpecEligibilityData should be a table")
assert(type(Where2GoSpecEligibilityData.BY_SPEC) == "table", "Where2GoSpecEligibilityData.BY_SPEC should be a table")

local specCount = 0
for specId, itemSet in pairs(Where2GoSpecEligibilityData.BY_SPEC) do
    specCount = specCount + 1
    assert(type(specId) == "number", "BY_SPEC keys should be numeric spec IDs")
    assert(type(itemSet) == "table", "BY_SPEC[" .. tostring(specId) .. "] should be a table of item IDs")
    for itemId, value in pairs(itemSet) do
        assert(type(itemId) == "number", "BY_SPEC[" .. specId .. "] keys should be numeric item IDs")
        assert(value == true, "BY_SPEC[" .. specId .. "][" .. tostring(itemId) .. "] should be exactly `true`")
    end
end

-- Deliberately no "every class must be covered" assertion here: this
-- file starts empty and fills in gradually across many
-- `/where2go genspec` sessions per docs/SEASON_CHECKLIST.md, so a hard
-- coverage gate here would fail the whole suite for as long as that
-- generation work is in progress. Only structural correctness (numeric
-- keys, `true` values) is enforced unconditionally.
print("specEligibilityData_spec: OK, " .. specCount .. " spec(s) currently populated (structural check only)")
