dofile("Where2Go/Core/Fixtures.lua")

local function assertCard(card, label)
    assert(type(card.name) == "string" and #card.name > 0, label .. ": name must be a non-empty string")
    assert(type(card.poolSize) == "number" and card.poolSize > 0, label .. ": poolSize must be a positive number")
    assert(type(card.targetCount) == "number" and card.targetCount >= 0, label .. ": targetCount must be >= 0")
    assert(card.targetCount <= card.poolSize, label .. ": targetCount cannot exceed poolSize")
    assert(type(card.recommendedLootSpec) == "string" and #card.recommendedLootSpec > 0,
        label .. ": recommendedLootSpec must be a non-empty string")
    assert(type(card.items) == "table", label .. ": items must be a table")
    assert(#card.items == card.targetCount, label .. ": items count must match targetCount")
end

assert(type(Where2GoFixtures) == "table", "Where2GoFixtures must be a table")

assert(type(Where2GoFixtures.dungeon) == "table", "Where2GoFixtures.dungeon must be a table")
assertCard(Where2GoFixtures.dungeon, "dungeon")

assert(type(Where2GoFixtures.raid) == "table", "Where2GoFixtures.raid must be a table")
assert(type(Where2GoFixtures.raid.name) == "string" and #Where2GoFixtures.raid.name > 0,
    "raid.name must be a non-empty string")
assert(type(Where2GoFixtures.raid.encounters) == "table", "raid.encounters must be a table")
assert(#Where2GoFixtures.raid.encounters > 0, "raid.encounters must have at least one entry")

for i, encounter in ipairs(Where2GoFixtures.raid.encounters) do
    assertCard(encounter, "raid.encounters[" .. i .. "]")
end

print("fixtures_spec: OK, " .. #Where2GoFixtures.raid.encounters .. " encounter(s) verified")
