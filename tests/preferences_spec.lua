dofile("Where2Go/Core/Preferences.lua")

-- Get must make a fresh or partially migrated SavedVariables table usable
-- without deleting unrelated character data.
Where2GoCharDB = nil
local preferred, sources = Where2GoPreferences.Get("DROP")
assert(type(Where2GoCharDB) == "table", "Get should initialize Where2GoCharDB")
assert(type(preferred) == "table" and type(sources) == "table",
    "Get should return preferred and source maps")
assert(type(Where2GoCharDB.preferredItems.VOIDCORE) == "table"
        and type(Where2GoCharDB.preferredItemSources.VOIDCORE) == "table",
    "Get should initialize both compatible preference modes")

Where2GoCharDB = {
    legacyFlag = "keep",
    preferredItems = {
        DROP = { [10] = true },
        VOIDCORE = { [20] = true },
    },
    preferredItemSources = {
        DROP = { [10] = 111, [99] = 999 },
        VOIDCORE = { [20] = 222 },
    },
    voidcoreObtainedItems = { [77] = true },
}

-- Reload to isolate transaction and subscription state from initialization.
dofile("Where2Go/Core/Preferences.lua")

local notified = {}
Where2GoPreferences.Subscribe("spec", function(mode)
    notified[#notified + 1] = mode
end)

-- Existing IDs are no-ops: their saved source metadata must remain unchanged.
local count = Where2GoPreferences.Add("DROP", {
    [10] = 444,
    [11] = 333,
    [12] = true,
})
assert(count == 2, "Add should return the number of newly preferred item IDs")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(preferred[10] and preferred[11] and preferred[12], "Add should persist every new item")
assert(sources[10] == 111, "duplicate Add should preserve an existing saved source")
assert(sources[11] == 333, "Add should persist a numeric source bonus ID")
assert(sources[12] == nil, "the true no-bonus sentinel should not be stored as source data")
assert(#notified == 1 and notified[1] == "DROP", "an actual Add should notify subscribers once")

count = Where2GoPreferences.Add("DROP", { [10] = 555, [11] = 666 })
assert(count == 0, "an Add containing only existing items should return zero")
assert(Where2GoPreferences.HasUndo("DROP"), "a duplicate Add should not erase the prior undo")
assert(#notified == 1, "a no-op Add should not publish a change")

count = Where2GoPreferences.Undo("DROP")
assert(count == 2, "Undo should return the number of items changed by the reverted edit")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(preferred[10] and not preferred[11] and not preferred[12],
    "Undo should revert only the last actual Add")
assert(sources[10] == 111 and sources[99] == 999,
    "Undo should preserve all source data that existed before the edit")
assert(not Where2GoPreferences.HasUndo("DROP"), "Undo should consume that mode's transaction")

count = Where2GoPreferences.Remove("DROP", 10)
assert(count == 1, "Remove should return one for an existing preferred item")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(preferred[10] == nil and sources[10] == nil, "Remove should delete the preference and its source")
assert(Where2GoPreferences.Remove("DROP", 404) == 0,
    "Remove should return zero for a missing preference")
assert(Where2GoPreferences.HasUndo("DROP"), "a missing Remove should not erase the prior undo")
assert(Where2GoPreferences.Undo("DROP") == 1, "Undo should restore the removed item")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(preferred[10] and sources[10] == 111, "Undo Remove should restore its saved source")

count = Where2GoPreferences.Clear("DROP")
assert(count == 1, "Clear should return the number of preferred items removed")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(next(preferred) == nil and next(sources) == nil,
    "Clear should empty both maps for its mode")
assert(Where2GoPreferences.Clear("DROP") == 0, "clearing an empty mode should be a no-op")
assert(Where2GoPreferences.HasUndo("DROP"), "a no-op Clear should not erase the clear transaction")
assert(Where2GoPreferences.Undo("DROP") == 1, "Undo Clear should report its restored item count")
preferred, sources = Where2GoPreferences.Get("DROP")
assert(preferred[10] and sources[10] == 111 and sources[99] == 999,
    "Undo Clear should restore the exact preferred and source maps")

-- Each mode owns its own one-level undo transaction.
assert(Where2GoPreferences.Add("DROP", { [30] = 330 }) == 1, "DROP setup Add should change one item")
assert(Where2GoPreferences.Add("VOIDCORE", { [40] = 440 }) == 1,
    "VOIDCORE setup Add should change one item")
assert(Where2GoPreferences.Undo("DROP") == 1, "DROP Undo should revert DROP's last edit")
local dropPreferred = Where2GoPreferences.Get("DROP")
local voidPreferred, voidSources = Where2GoPreferences.Get("VOIDCORE")
assert(not dropPreferred[30] and voidPreferred[20] and voidPreferred[40],
    "DROP Undo should not change VOIDCORE preferences")
assert(voidSources[20] == 222 and voidSources[40] == 440,
    "DROP Undo should not change VOIDCORE source data")
assert(Where2GoPreferences.Undo("VOIDCORE") == 1, "VOIDCORE should retain its independent undo")

-- Keyed subscription replacement avoids duplicate refresh callbacks, while
-- Notify supports history/cache changes that occur outside preference edits.
local replacementCalls = 0
Where2GoPreferences.Subscribe("spec", function(mode)
    replacementCalls = replacementCalls + 1
    assert(mode == "VOIDCORE", "Notify should pass its mode to the subscriber")
end)
Where2GoPreferences.Notify("VOIDCORE")
assert(replacementCalls == 1, "Subscribe should replace an existing callback with the same key")
Where2GoPreferences.Subscribe("spec", nil)
Where2GoPreferences.Notify("VOIDCORE")
assert(replacementCalls == 1, "Subscribe(key, nil) should unsubscribe that callback")

assert(Where2GoCharDB.legacyFlag == "keep" and Where2GoCharDB.voidcoreObtainedItems[77],
    "preference transactions should preserve unrelated saved character data")

print("preferences_spec: OK")
