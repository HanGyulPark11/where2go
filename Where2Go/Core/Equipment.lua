-- Reads real equipped/bag items and determines their upgrade track by
-- matching bonus IDs against Where2GoTracks.UPGRADE_TRACKS. Ported from
-- the pre-restart implementation's Core/Equipment.lua -- see
-- docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md for
-- provenance. WoW-API-dependent; inventory behavior is covered by
-- tests/equipment_spec.lua.

Where2GoEquipment = {}

local OWNERSHIP_MODE_ITEM = "ITEM"
local OWNERSHIP_MODE_SLOT = "SLOT"
local pendingItemLoads = {}

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

function Where2GoEquipment.GetOwnershipMode()
    local mode = Where2GoCharDB and Where2GoCharDB.ownershipFilterMode
    if mode == OWNERSHIP_MODE_SLOT then
        return mode
    end
    return OWNERSHIP_MODE_ITEM
end

function Where2GoEquipment.SetOwnershipMode(mode)
    assert(mode == OWNERSHIP_MODE_ITEM or mode == OWNERSHIP_MODE_SLOT, "invalid ownership mode")
    Where2GoCharDB = Where2GoCharDB or {}
    Where2GoCharDB.ownershipFilterMode = mode
end

local function entryForLink(itemId, link)
    if not itemId then
        return nil
    end
    if not link then
        if not pendingItemLoads[itemId] and Where2GoEquipment.GetNormalizedSlot(itemId) then
            pendingItemLoads[itemId] = true
            C_Item.RequestLoadItemDataByID(itemId)
        end
        return nil
    end
    local ilvl = ilvlForLink(link)
    if not ilvl then
        if C_Item.GetItemInfo(itemId) then
            pendingItemLoads[itemId] = nil
        elseif not pendingItemLoads[itemId] and Where2GoEquipment.GetNormalizedSlot(itemId) then
            pendingItemLoads[itemId] = true
            C_Item.RequestLoadItemDataByID(itemId)
        end
    end
    return { itemId = itemId, ilvl = ilvl, track = Where2GoEquipment.GetTrackInfo(link) }
end

-- Reads equipped slots and ordinary bags exactly once for a ranking pass.
-- Each item ID maps to every real instance, because the strongest copy may
-- appear after a weaker equipped or bag copy.
function Where2GoEquipment.GetOwnedSnapshot()
    local owned = {}
    local function add(itemId, link)
        local entry = entryForLink(itemId, link)
        if entry then
            owned[itemId] = owned[itemId] or {}
            table.insert(owned[itemId], entry)
        end
    end
    for slot = 1, 19 do
        add(GetInventoryItemID("player", slot), GetInventoryItemLink("player", slot))
    end
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                add(info.itemID, info.hyperlink)
            end
        end
    end
    return owned
end

local function candidateTrack(candidate)
    if not candidate or not candidate.trackKey then
        return nil
    end
    return Where2GoTracks.UPGRADE_TRACKS[candidate.trackKey]
end

local function dominates(owned, candidate)
    local targetTrack = candidateTrack(candidate)
    if owned.track and targetTrack and owned.track.order ~= targetTrack.order then
        return owned.track.order > targetTrack.order
    end
    return owned.ilvl ~= nil and candidate and candidate.ilvl ~= nil and owned.ilvl >= candidate.ilvl
end

local function equipFamily(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
        return "ONEHAND_MAIN"
    elseif equipLoc == "INVTYPE_2HWEAPON" then
        return "TWOHAND"
    elseif equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
        return "RANGED"
    elseif equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return "OFFHAND_WEAPON"
    elseif equipLoc == "INVTYPE_HOLDABLE" then
        return "HOLDABLE"
    elseif equipLoc == "INVTYPE_SHIELD" then
        return "SHIELD"
    end
    return equipLoc
end

local function sameSlotFamily(candidateItemId, ownedItemId)
    local candidateSlot = Where2GoEquipment.GetNormalizedSlot(candidateItemId)
    local ownedSlot = Where2GoEquipment.GetNormalizedSlot(ownedItemId)
    if not candidateSlot or candidateSlot ~= ownedSlot then
        return false
    end
    if candidateSlot ~= "MAINHAND" and candidateSlot ~= "OFFHAND" then
        return true
    end
    return equipFamily(candidateItemId) == equipFamily(ownedItemId)
end

-- Returns true only when a real owned instance is known to be equal or
-- better than this source-specific candidate. `isUsable` is supplied by the
-- ranking caller so SLOT mode counts only items usable by the current spec.
function Where2GoEquipment.HasOwnedAtLeast(snapshot, itemId, candidate, mode, isUsable)
    local sameItem = snapshot[itemId] or {}
    for _, owned in ipairs(sameItem) do
        if dominates(owned, candidate) then
            return true
        end
    end
    if mode ~= OWNERSHIP_MODE_SLOT then
        return false
    end

    local slot = Where2GoEquipment.GetNormalizedSlot(itemId)
    if not slot then
        return false
    end
    local qualifyingIds = {}
    for ownedItemId, entries in pairs(snapshot) do
        if ownedItemId ~= itemId and sameSlotFamily(itemId, ownedItemId)
            and (not isUsable or isUsable(ownedItemId)) then
            for _, owned in ipairs(entries) do
                if dominates(owned, candidate) then
                    qualifyingIds[ownedItemId] = true
                    break
                end
            end
        end
    end
    if slot == "FINGER" or slot == "TRINKET" then
        local count = 0
        for _ in pairs(qualifyingIds) do count = count + 1 end
        return count >= 2
    end
    return next(qualifyingIds) ~= nil
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

-- Weakest (most replaceable) equipped entry for a normalized slot id --
-- the comparison baseline for FINGER/TRINKET's two physical slots (a
-- candidate is judged against the one you'd actually swap out, not
-- against the stronger of the pair you'd keep either way), and simply the
-- one entry otherwise. An empty slot counts as the weakest possible entry,
-- so it wins this comparison over any real item. Never returns nil.
--
-- KNOWN LIMITATION (not yet handled -- revisit when Phase 3 builds the
-- ranking engine): a Unique-Equipped item can only occupy one physical
-- slot at a time, so when the candidate shares an item ID with one of the
-- two currently-equipped entries, the correct baseline is that SAME
-- equipped instance, not whichever of the pair is weakest. Example: Hero
-- item A and Champion item B are equipped in the two trinket slots; a new,
-- higher-track A drops. It can only ever replace the existing A (you can't
-- wear two Unique-Equipped A's), so it should be compared against the
-- equipped A specifically -- comparing against B (today's behavior, since
-- B is weaker) can produce a misleading verdict. Fixing this needs an
-- itemId-aware variant of this function that callers (Init.lua's
-- HandleCompareCommand) pass the candidate's itemId into.
function Where2GoEquipment.GetWeakestEquipped(slotId)
    local entries = Where2GoEquipment.GetEquipped(slotId)
    if #entries == 0 then
        return { itemId = nil, ilvl = nil, track = nil }
    end
    local weakest = entries[1]
    for i = 2, #entries do
        if Where2GoCompare.IsBetterCandidate(weakest, entries[i]) then
            weakest = entries[i]
        end
    end
    return weakest
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
