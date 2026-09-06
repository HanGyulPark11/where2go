dofile("Where2Go/Core/SpecEligibilityScan.lua")

-- FilterKnownItemIds: only ever returns item IDs present in BOTH the
-- filtered set and the known/tracked list -- this is the mechanism that
-- keeps non-gear Encounter Journal loot (mounts, pets, toys, quest
-- items, crafting reagents) out of BY_SPEC even if EJ's raw per-boss
-- loot list includes them.
local filtered = { [100] = true, [200] = true, [999] = true }
local known = { 100, 200, 300 }
local matched = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, known)
assert(matched[100] == true, "100 is in both filtered and known -- should match")
assert(matched[200] == true, "200 is in both filtered and known -- should match")
assert(matched[300] == nil, "300 is known but not in the filtered result -- should not match")
assert(matched[999] == nil, "999 is in the filtered result but NOT in the known/tracked list -- must never leak an untracked item")

local emptyFiltered = Where2GoSpecEligibilityScan.FilterKnownItemIds({}, known)
assert(next(emptyFiltered) == nil, "empty filtered set should produce an empty match set")

local emptyKnown = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, {})
assert(next(emptyKnown) == nil, "empty known list should produce an empty match set")

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

-- FindStaleItemIds: known items missing from the current unfiltered EJ
-- loot list are flagged stale (Sources.lua tracks them but the live
-- Encounter Journal no longer lists them as droppable at all); known
-- items present in the real list are never flagged, regardless of spec
-- attribution.
local knownItems = { 100, 200, 300 }
local realItems = { [100] = true, [300] = true }
local stale = Where2GoSpecEligibilityScan.FindStaleItemIds(knownItems, realItems)
assert(#stale == 1, "exactly one known item (200) is missing from the real list")
assert(stale[1] == 200, "the missing item should be 200")

local noneStale = Where2GoSpecEligibilityScan.FindStaleItemIds(knownItems, { [100] = true, [200] = true, [300] = true })
assert(#noneStale == 0, "every known item present in the real list -- nothing stale")

local allStale = Where2GoSpecEligibilityScan.FindStaleItemIds(knownItems, {})
assert(#allStale == 3, "empty real list -- every known item is stale")

-- CheckExportSeasonStale: nil export or matching season is never stale;
-- a season mismatch is stale.
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale(nil, "S2") == false, "nil export is never stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S2" }, "S2") == false, "matching season is not stale")
assert(Where2GoSpecEligibilityScan.CheckExportSeasonStale({ seasonVersion = "S1" }, "S2") == true, "mismatched season is stale")

print("specEligibilityScan_spec: OK")
