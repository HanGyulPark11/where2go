-- Reads real equipped/bag items and determines their upgrade track by
-- matching bonus IDs against Where2GoTracks.UPGRADE_TRACKS. Ported from
-- the pre-restart implementation's Core/Equipment.lua -- see
-- docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md for
-- provenance. WoW-API-dependent; not unit-tested (Core/Compare.lua carries
-- the pure comparison logic this feeds).

Where2GoEquipment = {}

local function ilvlForLink(link)
    if not link then
        return nil
    end
    return C_Item.GetDetailedItemLevelInfo(link)
end

-- Manual bonus-ID parse: WoW has no official "get bonus IDs from a link"
-- API. itemString field layout (Blizzard item-link spec, 1-indexed):
-- 1=item, 2=itemID, 3=enchantID, 4-7=gem1-4, 8=suffixID, 9=uniqueID,
-- 10=linkLevel, 11=specializationID, 12=upgradeTypeID,
-- 13=instanceDifficultyID/context, 14=numBonusIDs,
-- 15..14+numBonusIDs=the bonus IDs themselves.
local function parseBonusIds(link)
    if not link then
        return {}
    end
    local itemString = link:match("item[%-?%d:]+")
    if not itemString then
        return {}
    end
    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = field
    end
    local numBonus = tonumber(fields[14]) or 0
    local ids = {}
    for i = 1, numBonus do
        local id = tonumber(fields[14 + i])
        if id then
            table.insert(ids, id)
        end
    end
    return ids
end

-- Returns { order, ilvl, label, rank } for the highest-order upgrade track
-- found among an item link's bonus IDs, or nil if none match (e.g. crafted
-- gear, which uses an unrelated bonus-ID scheme).
function Where2GoEquipment.GetTrackInfo(link)
    local ids = parseBonusIds(link)
    local best
    for _, id in ipairs(ids) do
        for _, track in pairs(Where2GoTracks.UPGRADE_TRACKS) do
            if id >= track.bonusIdStart and id < track.bonusIdStart + 6 then
                local rank = id - track.bonusIdStart + 1
                if not best or track.order > best.order then
                    best = { order = track.order, ilvl = track.ilvls[rank], label = track.label, rank = rank }
                end
            end
        end
    end
    return best
end

local function infoForInvSlotName(invSlotName)
    local slotId = GetInventorySlotInfo(invSlotName)
    if not slotId then
        return { itemId = nil, ilvl = nil, track = nil }
    end
    local link = GetInventoryItemLink("player", slotId)
    return {
        itemId = GetInventoryItemID("player", slotId),
        ilvl = ilvlForLink(link),
        track = Where2GoEquipment.GetTrackInfo(link),
    }
end

-- Returns { {itemId=, ilvl=, track=}, ... } for a normalized slot id.
-- Single-entry for most slots, two entries for FINGER/TRINKET.
function Where2GoEquipment.GetEquipped(slotId)
    if slotId == "FINGER" then
        local out = {}
        for _, invSlot in ipairs(Where2GoConstants.FINGER_SLOTS) do
            table.insert(out, infoForInvSlotName(invSlot))
        end
        return out
    elseif slotId == "TRINKET" then
        local out = {}
        for _, invSlot in ipairs(Where2GoConstants.TRINKET_SLOTS) do
            table.insert(out, infoForInvSlotName(invSlot))
        end
        return out
    end

    local invSlot = Where2GoConstants.SLOT_TO_INVSLOT[slotId]
    if not invSlot then
        return {}
    end
    return { infoForInvSlotName(invSlot) }
end

-- Best (highest track, then highest ilvl) equipped entry for a normalized
-- slot id -- the comparison baseline for FINGER/TRINKET's two physical
-- slots, and simply the one entry otherwise. Never returns nil.
function Where2GoEquipment.GetBestEquipped(slotId)
    local entries = Where2GoEquipment.GetEquipped(slotId)
    local best = { itemId = nil, ilvl = nil, track = nil }
    for _, entry in ipairs(entries) do
        if Where2GoCompare.IsBetterCandidate(entry, best) then
            best = entry
        end
    end
    return best
end

-- Which normalized slot a bare item ID belongs in, or nil if it isn't
-- equippable gear (e.g. a consumable) or its equip loc isn't mapped.
function Where2GoEquipment.GetNormalizedSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

-- The first real item link found for itemId: checks all 19 equipped slots,
-- then bags 0-4. Returns nil if the player has no real instance of it
-- right now.
function Where2GoEquipment.FindItemLink(itemId)
    for slot = 1, 19 do
        if GetInventoryItemID("player", slot) == itemId then
            return GetInventoryItemLink("player", slot)
        end
    end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId then
                return info.hyperlink
            end
        end
    end
    return nil
end
