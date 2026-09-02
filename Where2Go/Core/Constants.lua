Where2GoConstants = {}

Where2GoConstants.ADDON_NAME = "Where2Go"
Where2GoConstants.INTERFACE_VERSION = 120100
Where2GoConstants.SEASON_LABEL = "Midnight Season 2"

-- WoW equip-slot name (for GetInventorySlotInfo) per normalized slot id.
-- FINGER/TRINKET have two physical slots each -- see FINGER_SLOTS/
-- TRINKET_SLOTS below, handled specially by Core/Equipment.lua.
Where2GoConstants.SLOT_TO_INVSLOT = {
    HEAD = "HeadSlot",
    NECK = "NeckSlot",
    SHOULDER = "ShoulderSlot",
    BACK = "BackSlot",
    CHEST = "ChestSlot",
    WRIST = "WristSlot",
    HANDS = "HandsSlot",
    WAIST = "WaistSlot",
    LEGS = "LegsSlot",
    FEET = "FeetSlot",
    MAINHAND = "MainHandSlot",
    OFFHAND = "SecondaryHandSlot",
}
Where2GoConstants.FINGER_SLOTS = { "Finger0Slot", "Finger1Slot" }
Where2GoConstants.TRINKET_SLOTS = { "Trinket0Slot", "Trinket1Slot" }

-- Maps a WoW itemEquipLoc string (the 4th return of
-- C_Item.GetItemInfoInstant) to our normalized slot id, so a bare item ID
-- can be routed to the right equipped-slot comparison. Only the equip
-- locations relevant to current classes/gear are listed (YAGNI -- no
-- ammo/relic/thrown/etc. slots, which no longer exist on live characters).
Where2GoConstants.EQUIPLOC_TO_SLOT = {
    INVTYPE_HEAD = "HEAD",
    INVTYPE_NECK = "NECK",
    INVTYPE_SHOULDER = "SHOULDER",
    INVTYPE_CLOAK = "BACK",
    INVTYPE_CHEST = "CHEST",
    INVTYPE_ROBE = "CHEST",
    INVTYPE_WRIST = "WRIST",
    INVTYPE_HAND = "HANDS",
    INVTYPE_WAIST = "WAIST",
    INVTYPE_LEGS = "LEGS",
    INVTYPE_FEET = "FEET",
    INVTYPE_FINGER = "FINGER",
    INVTYPE_TRINKET = "TRINKET",
    INVTYPE_WEAPONMAINHAND = "MAINHAND",
    INVTYPE_2HWEAPON = "MAINHAND",
    INVTYPE_WEAPON = "MAINHAND",
    INVTYPE_RANGED = "MAINHAND",
    INVTYPE_RANGEDRIGHT = "MAINHAND",
    INVTYPE_WEAPONOFFHAND = "OFFHAND",
    INVTYPE_HOLDABLE = "OFFHAND",
    INVTYPE_SHIELD = "OFFHAND",
}

function Where2GoConstants.BuildDefaultAccountDB()
    return {
        panelShown = false,
    }
end

function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {
            DROP = {},
            VOIDCORE = {},
        },
        voidcoreObtainedItems = {},
    }
end
