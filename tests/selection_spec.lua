dofile("Where2Go/Core/Selection.lua")

local selection = Where2GoSelection.New()

-- A regression that includes a saved item or repeated pool entry would make
-- select-all over-count and could stage an item that cannot be added.
local selectedCount, availableCount = selection:SetResults({
    { itemId = 101, bonusId = 9101 },
    { itemId = 101, bonusId = 9999 },
    { itemId = 102 },
    { itemId = 103, bonusId = 9103 },
}, { [103] = true }, true)
assert(selectedCount == 0 and availableCount == 2,
    "SetResults should count unique unsaved item IDs")

selectedCount, availableCount = selection:SelectAll(true)
assert(selectedCount == 2 and availableCount == 2,
    "SelectAll(true) should select every unique unsaved result")
local selected = selection:GetSelected()
assert(selected[101] == 9101, "duplicate result IDs should retain the first entry's bonus ID")
assert(selected[102] == true, "a result without a bonus ID should use true as its selection value")
assert(selected[103] == nil, "already preferred results should not be selectable")

-- Unchecking one item after select-all must retain the other selected IDs.
selectedCount, availableCount = selection:Toggle(101)
assert(selectedCount == 1 and availableCount == 2,
    "Toggle should exclude one item without clearing the rest of select-all")
assert(selection:GetSelected()[102] == true and selection:GetSelected()[101] == nil,
    "the exception should be represented by item ID, independently of visible rows")

-- A cache refresh recreates result entries. Membership should survive while
-- current bonus metadata is adopted, and IDs no longer eligible are dropped.
selection:Toggle(101)
selectedCount, availableCount = selection:SetResults({
    { itemId = 101, bonusId = 9201 },
    { itemId = 104, bonusId = 9204 },
}, {}, false)
assert(selectedCount == 1 and availableCount == 2,
    "a non-reset refresh should preserve only selected IDs still in the results")
selected = selection:GetSelected()
assert(selected[101] == 9201, "a retained selection should use refreshed bonus metadata")
assert(selected[102] == nil, "a selected ID that is no longer eligible should be reconciled away")

-- Explicit filter and mode edits pass reset=true and must clear transient state.
selectedCount, availableCount = selection:SetResults({
    { itemId = 101, bonusId = 9201 },
    { itemId = 104, bonusId = 9204 },
}, {}, true)
assert(selectedCount == 0 and availableCount == 2,
    "SetResults(..., true) should clear selection for an explicit filter or mode change")

selectedCount, availableCount = selection:Toggle(999)
assert(selectedCount == 0 and availableCount == 2,
    "toggling an unavailable item should be a no-op with consistent counts")

selection:SelectAll(true)
selectedCount, availableCount = selection:SelectAll(false)
assert(selectedCount == 0 and availableCount == 2,
    "SelectAll(false) should clear all transient selections and return both counts")

local selectedCopy = selection:GetSelected()
selectedCopy[101] = true
assert(selection:GetCounts() == 0,
    "GetSelected should return a copy that cannot mutate model state")

print("selection_spec: OK")
