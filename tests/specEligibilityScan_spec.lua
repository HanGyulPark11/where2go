dofile("Where2Go/Core/SpecEligibilityScan.lua")

-- Too few lines (or none) -> nil
assert(Where2GoSpecEligibilityScan.ParseTooltipLines(nil) == nil, "nil lines should return nil")
assert(Where2GoSpecEligibilityScan.ParseTooltipLines({}) == nil, "empty lines should return nil")

local shortLines = {}
for i = 1, 6 do
    shortLines[i] = { leftText = "Line " .. i }
end
assert(Where2GoSpecEligibilityScan.ParseTooltipLines(shortLines) == nil, "fewer than 7 lines should return nil")

-- A realistic tooltip: 6 header lines, then item lines starting at index 7.
local fullLines = {
    { leftText = "Nebulous Voidcache: Altar of Fangs" }, -- 1
    { leftText = "Item Level 200" },                      -- 2
    { leftText = "Binds when picked up" },                -- 3
    { leftText = "Unique" },                               -- 4
    { leftText = "Use: Open to receive one of the following items:" }, -- 5
    { leftText = "Requires a Loot Specialization" },      -- 6
    { leftText = "- Sample Sword" },                       -- 7
    { leftText = "- Sample Ring" },                        -- 8
    { leftText = "|cffffffff- Colored Item Name|r" },      -- 9
}
local parsed = Where2GoSpecEligibilityScan.ParseTooltipLines(fullLines)
assert(parsed ~= nil, "7+ lines should parse successfully")
assert(parsed["Sample Sword"] == true, "should extract 'Sample Sword'")
assert(parsed["Sample Ring"] == true, "should extract 'Sample Ring'")
assert(parsed["Colored Item Name"] == true, "should strip color codes before extracting the name")

local count = 0
for _ in pairs(parsed) do count = count + 1 end
assert(count == 3, "should extract exactly 3 item names, got " .. count)

-- A non-prefixed line at index >= 7 should be ignored, not mistaken for an item.
local withNoise = {
    { leftText = "H1" }, { leftText = "H2" }, { leftText = "H3" },
    { leftText = "H4" }, { leftText = "H5" }, { leftText = "H6" },
    { leftText = "Not an item line" },
    { leftText = "- Real Item" },
}
local parsedNoise = Where2GoSpecEligibilityScan.ParseTooltipLines(withNoise)
assert(parsedNoise["Real Item"] == true, "should extract the prefixed item line")
local noiseCount = 0
for _ in pairs(parsedNoise) do noiseCount = noiseCount + 1 end
assert(noiseCount == 1, "should ignore non-prefixed lines, got " .. noiseCount .. " entries")

print("specEligibilityScan_spec: OK")
