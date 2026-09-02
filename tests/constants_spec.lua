dofile("Where2Go/Core/Constants.lua")

assert(Where2GoConstants.ADDON_NAME == "Where2Go", "ADDON_NAME should be Where2Go")
assert(Where2GoConstants.INTERFACE_VERSION == 120100, "INTERFACE_VERSION should match the TOC")
assert(type(Where2GoConstants.SEASON_LABEL) == "string" and #Where2GoConstants.SEASON_LABEL > 0,
    "SEASON_LABEL should be a non-empty string")

local expectedSlots = {
    "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST",
    "HANDS", "WAIST", "LEGS", "FEET", "MAINHAND", "OFFHAND",
}
assert(type(Where2GoConstants.SLOT_TO_INVSLOT) == "table", "SLOT_TO_INVSLOT should be a table")
for _, slot in ipairs(expectedSlots) do
    assert(type(Where2GoConstants.SLOT_TO_INVSLOT[slot]) == "string",
        "SLOT_TO_INVSLOT should map " .. slot .. " to an inventory slot name")
end

assert(type(Where2GoConstants.FINGER_SLOTS) == "table" and #Where2GoConstants.FINGER_SLOTS == 2,
    "FINGER_SLOTS should have exactly 2 entries")
assert(type(Where2GoConstants.TRINKET_SLOTS) == "table" and #Where2GoConstants.TRINKET_SLOTS == 2,
    "TRINKET_SLOTS should have exactly 2 entries")

assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_HEAD == "HEAD", "EQUIPLOC_TO_SLOT should map INVTYPE_HEAD to HEAD")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_FINGER == "FINGER", "EQUIPLOC_TO_SLOT should map INVTYPE_FINGER to FINGER")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_TRINKET == "TRINKET", "EQUIPLOC_TO_SLOT should map INVTYPE_TRINKET to TRINKET")
assert(Where2GoConstants.EQUIPLOC_TO_SLOT.INVTYPE_WEAPONMAINHAND == "MAINHAND", "EQUIPLOC_TO_SLOT should map INVTYPE_WEAPONMAINHAND to MAINHAND")

local accountDB = Where2GoConstants.BuildDefaultAccountDB()
assert(type(accountDB) == "table", "BuildDefaultAccountDB should return a table")
assert(accountDB.panelShown == false, "panelShown should default to false")

local charDB = Where2GoConstants.BuildDefaultCharDB()
assert(type(charDB) == "table", "BuildDefaultCharDB should return a table")
assert(type(charDB.preferredItems) == "table", "preferredItems should default to a table")
assert(type(charDB.preferredItems.DROP) == "table", "preferredItems.DROP should default to a table")
assert(type(charDB.preferredItems.VOIDCORE) == "table", "preferredItems.VOIDCORE should default to a table")
assert(next(charDB.preferredItems.DROP) == nil, "preferredItems.DROP should default to empty")
assert(next(charDB.preferredItems.VOIDCORE) == nil, "preferredItems.VOIDCORE should default to empty")

-- Regression guard: each call must return independent tables at every
-- level. If the builder ever returns a shared table by reference, one
-- character's saved data would leak into every other character's.
local secondCharDB = Where2GoConstants.BuildDefaultCharDB()
charDB.preferredItems.DROP[12345] = true
charDB.preferredItems.VOIDCORE[54321] = true
assert(next(secondCharDB.preferredItems.DROP) == nil,
    "BuildDefaultCharDB must return an independent DROP table on each call")
assert(next(secondCharDB.preferredItems.VOIDCORE) == nil,
    "BuildDefaultCharDB must return an independent VOIDCORE table on each call")

print("constants_spec: OK")
