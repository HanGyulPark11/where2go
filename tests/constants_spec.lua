dofile("Where2Go/Core/Constants.lua")

assert(Where2GoConstants.ADDON_NAME == "Where2Go", "ADDON_NAME should be Where2Go")
assert(Where2GoConstants.INTERFACE_VERSION == 120100, "INTERFACE_VERSION should match the TOC")
assert(type(Where2GoConstants.SEASON_LABEL) == "string" and #Where2GoConstants.SEASON_LABEL > 0,
    "SEASON_LABEL should be a non-empty string")

local accountDB = Where2GoConstants.BuildDefaultAccountDB()
assert(type(accountDB) == "table", "BuildDefaultAccountDB should return a table")
assert(accountDB.panelShown == false, "panelShown should default to false")

local charDB = Where2GoConstants.BuildDefaultCharDB()
assert(type(charDB) == "table", "BuildDefaultCharDB should return a table")
assert(type(charDB.preferredItems) == "table", "preferredItems should default to a table")
assert(#charDB.preferredItems == 0, "preferredItems should default to empty")

-- Regression guard: each call must return an independent table. If the
-- builder ever returns a shared table by reference, one character's saved
-- data would leak into every other character's.
local secondCharDB = Where2GoConstants.BuildDefaultCharDB()
table.insert(charDB.preferredItems, 12345)
assert(#secondCharDB.preferredItems == 0,
    "BuildDefaultCharDB must return an independent table on each call")

print("constants_spec: OK")
