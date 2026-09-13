dofile("Where2Go/Core/Sources.lua")
dofile("Where2Go/Core/Locale.lua")

local function assertNonEmptyArray(t, label)
    assert(type(t) == "table", label .. " should be a table")
    assert(#t > 0, label .. " should be non-empty")
end

assertNonEmptyArray(Where2GoSources.DUNGEONS, "Where2GoSources.DUNGEONS")
assertNonEmptyArray(Where2GoSources.RAIDS, "Where2GoSources.RAIDS")

local function checkInstance(instance, kind, index)
    local label = kind .. "[" .. index .. "]"
    assert(type(instance.name) == "string" and #instance.name > 0, label .. ".name should be a non-empty string")
    assert(Where2GoLocale.CONTENT_NAMES.enUS[instance.name] ~= nil,
        label .. ".name should have an enUS content-name entry")
    assert(Where2GoLocale.CONTENT_NAMES.koKR[instance.name] ~= nil,
        label .. ".name should have a koKR content-name entry")
    assertNonEmptyArray(instance.encounters, label .. ".encounters")
    for i, encounter in ipairs(instance.encounters) do
        local encLabel = label .. ".encounters[" .. i .. "]"
        assert(type(encounter.name) == "string" and #encounter.name > 0, encLabel .. ".name should be a non-empty string")
        assert(Where2GoLocale.CONTENT_NAMES.enUS[encounter.name] ~= nil,
            encLabel .. ".name should have an enUS content-name entry")
        assert(Where2GoLocale.CONTENT_NAMES.koKR[encounter.name] ~= nil,
            encLabel .. ".name should have a koKR content-name entry")
        assert(type(encounter.bossId) == "number", encLabel .. ".bossId should be a number")
        assertNonEmptyArray(encounter.itemIds, encLabel .. ".itemIds")
        for _, itemId in ipairs(encounter.itemIds) do
            assert(type(itemId) == "number", encLabel .. ".itemIds should contain only numbers")
        end
    end
end

for i, dungeon in ipairs(Where2GoSources.DUNGEONS) do
    checkInstance(dungeon, "DUNGEONS", i)
end
for i, raid in ipairs(Where2GoSources.RAIDS) do
    checkInstance(raid, "RAIDS", i)
end

-- Spot-check the real Venomous Abyss boss count this design corrects
-- Phase 1's fixture data against (see the design spec's provenance note).
local venomousAbyss = Where2GoSources.RAIDS[2]
assert(venomousAbyss.name == "The Venomous Abyss", "RAIDS[2] should be The Venomous Abyss")
assert(#venomousAbyss.encounters == 8, "The Venomous Abyss should have exactly 8 encounters")

local NON_GEAR_OR_COSMETIC_ITEMS = {
    [270900] = "Pattern: Snakeskin Lining",
    [279211] = "Pillar of the Fanged Altar",
    [264332] = "Amani Ritual Altar",
    [263238] = "Illicit Long Table",
    [256640] = "Pattern: Row Walker's Insurance",
    [258487] = "Plans: Murder Row Fleet Feet",
    [258518] = "Plans: Murder Row Fishhook",
    [256746] = "Formula: Smuggler's Enchanted Edge",
    [278245] = "Royal Attendant's Coffin",
    [256428] = "Valdrakken Hanging Lamp",
    [278982] = "Hatchery of Hissing Eggs",
    [279112] = "Clumped Asteroidea",
    [279115] = "Soulcoiler's Ritual Candle",
    [281227] = "Soulcoiler's Rush'kah",
    [280305] = "Soulcoil Remnant",
    [279118] = "Lost Explorers' Mailbox",
    [279122] = "Venom-Fanged Font",
    [279131] = "Pillar of the Coiled Isle",
    [275937] = "Hex Lord's Visage",
    [275938] = "Hex Lord's Gaze",
    [279125] = "The Venomous Abyss Aureate Trophy",
    [279127] = "The Venomous Abyss Argent Trophy",
    [279129] = "The Venomous Abyss Gleaming Trophy",
    [279500] = "\"Rage of the Shackled\" Mural",
    [275658] = "Primeval Skyfriend",
}
for _, group in ipairs({ Where2GoSources.DUNGEONS, Where2GoSources.RAIDS }) do
    for _, source in ipairs(group) do
        for _, encounter in ipairs(source.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                assert(not NON_GEAR_OR_COSMETIC_ITEMS[itemId],
                    "Sources.lua should exclude non-gear/cosmetic Journal rewards: " .. itemId)
            end
        end
    end
end

print("sources_spec: OK, " .. #Where2GoSources.DUNGEONS .. " dungeon(s), " .. #Where2GoSources.RAIDS .. " raid(s) verified")
