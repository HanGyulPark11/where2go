Where2GoTracks = {
    UPGRADE_TRACKS = {
        HERO = { order = 3, bonusIdStart = 12841, ilvls = { 305, 308, 311, 315, 318, 321 } },
        MYTH = { order = 4, bonusIdStart = 12849, ilvls = { 318, 321, 324, 328, 331, 334 } },
    },
}

local equipped = {}
local bags = {}
local levels = {}
local requested = {}

GetInventoryItemID = function(_, slot) return equipped[slot] and equipped[slot].itemId end
GetInventoryItemLink = function(_, slot) return equipped[slot] and equipped[slot].link end
C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
    GetContainerItemInfo = function(bag, slot) return bags[bag] and bags[bag][slot] end,
}
C_Item = {
    IsEquippableItem = function() return true end,
    GetDetailedItemLevelInfo = function(link) return levels[link] end,
    GetItemInfo = function(itemId) return levels[itemId] and "cached" end,
    RequestLoadItemDataByID = function(itemId) requested[itemId] = (requested[itemId] or 0) + 1 end,
    GetItemInfoInstant = function(itemId)
        return itemId, nil, nil, itemId == 300 and "INVTYPE_HEAD" or "INVTYPE_FINGER"
    end,
    GetItemSpecInfo = function(itemId)
        if itemId == 301 then return { 71 } end
        return {}
    end,
}

dofile("Where2Go/Core/Constants.lua")
dofile("Where2Go/Core/Equipment.lua")
dofile("Where2Go/Core/DirectDrop.lua")

local ownedUsable = Where2GoDirectDrop.IsOwnedUsableForSpec(71)
assert(not ownedUsable(300), "ambiguous empty spec metadata must not treat armor as usable")
assert(ownedUsable(100), "empty spec metadata remains usable for universal ring equipment")
assert(ownedUsable(301), "explicit current-spec metadata makes off-pool gear usable")

local heroOne = "item:100:0:0:0:0:0:0:0:0:0:0:0:1:12841"
local heroTwo = "item:100:0:0:0:0:0:0:0:0:0:0:0:1:12842"
local mythOne = "item:100:0:0:0:0:0:0:0:0:0:0:0:1:12849"
levels[heroOne], levels[heroTwo], levels[mythOne] = 305, 308, 318
equipped[1] = { itemId = 100, link = heroOne }
bags[0] = { { itemID = 100, hyperlink = mythOne } }

local snapshot = Where2GoEquipment.GetOwnedSnapshot()
assert(#snapshot[100] == 2, "snapshot keeps every equipped and bag copy of the same item")
assert(Where2GoEquipment.HasOwnedAtLeast(snapshot, 100, { ilvl = 315, trackKey = "HERO" }),
    "a higher owned track suppresses the candidate")
assert(Where2GoEquipment.HasOwnedAtLeast(snapshot, 100, { ilvl = 318, trackKey = "MYTH" }),
    "an equal owned item level on the same track suppresses the candidate")
assert(not Where2GoEquipment.HasOwnedAtLeast(snapshot, 100, { ilvl = 321, trackKey = "MYTH" }),
    "a lower owned item level on the same track does not suppress the candidate")
assert(not Where2GoEquipment.HasOwnedAtLeast({ [100] = { snapshot[100][1] } }, 100, { ilvl = 321, trackKey = "MYTH" }),
    "a lower-track owned item does not suppress a higher-track candidate")

levels[mythOne] = nil
snapshot = Where2GoEquipment.GetOwnedSnapshot()
assert(Where2GoEquipment.HasOwnedAtLeast(snapshot, 100, { ilvl = nil, trackKey = "HERO" }),
    "a recognized higher track proves ownership dominance even without item levels")
assert(not Where2GoEquipment.HasOwnedAtLeast(snapshot, 100, { ilvl = nil, trackKey = "MYTH" }),
    "equal-track unknown item levels remain eligible conservatively")
assert(requested[100] == 1, "missing gear metadata requests one cache load per item ID")
Where2GoEquipment.GetOwnedSnapshot()
assert(requested[100] == 1, "a pending cache load is not re-requested on a refresh")

equipped[2] = { itemId = 101, link = nil }
local coldLinkSnapshot = Where2GoEquipment.GetOwnedSnapshot()
assert(not coldLinkSnapshot[101] and requested[101] == 1,
    "a known equipped gear ID without a hyperlink requests data once without inferring ownership quality")
Where2GoEquipment.GetOwnedSnapshot()
assert(requested[101] == 1, "a missing hyperlink does not cause a refresh request loop")
levels[mythOne] = 318
equipped[2].link = mythOne
local resolvedLinkSnapshot = Where2GoEquipment.GetOwnedSnapshot()
assert(Where2GoEquipment.HasOwnedAtLeast(resolvedLinkSnapshot, 101, { ilvl = 318, trackKey = "MYTH" }),
    "the same item suppresses its source candidate once its hyperlink resolves")

Where2GoCharDB = {}
assert(Where2GoEquipment.GetOwnershipMode() == "ITEM", "missing mode defaults to item matching")
Where2GoEquipment.SetOwnershipMode("SLOT")
assert(Where2GoEquipment.GetOwnershipMode() == "SLOT" and Where2GoCharDB.ownershipFilterMode == "SLOT",
    "slot mode persists without replacing character data")

local slotSnapshot = {
    [201] = { { itemId = 201, ilvl = 318, track = { order = 3 } } },
    [202] = { { itemId = 202, ilvl = 318, track = { order = 3 } } },
}
assert(not Where2GoEquipment.HasOwnedAtLeast(slotSnapshot, 200, { ilvl = 318, trackKey = "HERO" }, "ITEM"),
    "item mode retains different item IDs")
assert(Where2GoEquipment.HasOwnedAtLeast(slotSnapshot, 200, { ilvl = 318, trackKey = "HERO" }, "SLOT", function() return true end),
    "two usable distinct rings suppress a same-slot ring candidate")
assert(not Where2GoEquipment.HasOwnedAtLeast({ [201] = slotSnapshot[201] }, 200,
    { ilvl = 318, trackKey = "HERO" }, "SLOT", function() return true end),
    "one strong ring cannot fill both finger slots")
assert(not Where2GoEquipment.HasOwnedAtLeast(slotSnapshot, 200, { ilvl = 318, trackKey = "HERO" }, "SLOT", function(id) return id == 201 end),
    "items unusable by the current spec do not suppress a slot candidate")

print("equipment_spec: OK")
