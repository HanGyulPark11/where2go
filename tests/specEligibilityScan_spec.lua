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

-- MergeBySpec: adds new specs, preserves untouched existing specs,
-- fully replaces any spec this pass actually scanned.
local merged1 = Where2GoSpecEligibilityScan.MergeBySpec(nil, { [71] = { [100] = true } })
assert(merged1[71][100] == true, "should merge into a nil existing table")

local existingBySpec = { [71] = { [100] = true }, [72] = { [200] = true } }
local merged2 = Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, { [73] = { [300] = true } })
assert(merged2[71][100] == true, "should preserve untouched existing spec 71")
assert(merged2[72][200] == true, "should preserve untouched existing spec 72")
assert(merged2[73][300] == true, "should add new spec 73")

local replaced = Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, { [71] = { [999] = true } })
assert(replaced[71][999] == true, "should replace spec 71 wholesale with the new scan's result")
assert(replaced[71][100] == nil, "should not keep spec 71's stale old item after a full re-scan of that spec")
assert(replaced[72][200] == true, "should still preserve untouched spec 72")

-- CheckExportSeasonStale: nil export or matching season is never stale;
-- a season mismatch is stale.
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale(nil, "S2") == false, "nil export is never stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S2" }, "S2") == false, "matching season is not stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S1" }, "S2") == true, "mismatched season is stale")

print("specEligibilityScan_spec: OK")
