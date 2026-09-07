-- Shared item-row rendering: icon + quality-colored name + a compact
-- "ilvl · secondary-stat" summary line, with a real GameTooltip on hover.
-- Used by both UI/BrowserPanel.lua (Results/Staged/Preferred rows) and
-- UI/Panel.lua (expanded card item rows) so both windows render items
-- identically. See
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md.
--
-- WoW-API-dependent (CreateTexture/CreateFontString/C_Item/GameTooltip)
-- -- not unit-tested, verified live, matching this project's convention
-- for UI-layer code.

Where2GoItemRow = {}

local EJ_MYTHIC_KEYSTONE_DIFFICULTY = 8
local EJ_MYTHIC_RAID_DIFFICULTY = 16

-- itemId -> {instanceId, bossId, isRaid}, built once from Where2GoSources
-- and cached. Recovers which encounter/instance tracks a given item even
-- when the caller only has a flattened item list with no per-boss
-- attribution (e.g. Core/DirectDrop.lua's dungeon content entries, which
-- intentionally drop it for display -- see
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md).
-- Sources.lua itself still has the real per-boss structure, so it can
-- always be recovered here.
local itemSourceLookup
local function GetItemSource(itemId)
    if not itemSourceLookup then
        itemSourceLookup = {}
        for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
            for _, encounter in ipairs(dungeon.encounters) do
                for _, id in ipairs(encounter.itemIds) do
                    itemSourceLookup[id] = { instanceId = dungeon.instanceId, bossId = encounter.bossId, isRaid = false }
                end
            end
        end
        for _, raid in ipairs(Where2GoSources.RAIDS) do
            for _, encounter in ipairs(raid.encounters) do
                for _, id in ipairs(encounter.itemIds) do
                    itemSourceLookup[id] = { instanceId = raid.instanceId, bossId = encounter.bossId, isRaid = true }
                end
            end
        end
    end
    return itemSourceLookup[itemId]
end

-- Every bonus ID that represents an ilvl-upgrade-track rank (Where2GoTracks'
-- 4 tracks x 6 ranks each, plus RaidRanks' special Myth-final bonus ID).
-- Mythic+ has no single fixed item level -- confirmed by searching
-- Gethe/wow-ui-source that Blizzard's own Encounter Journal UI code never
-- calls C_EncounterJournal.SetPreviewMythicPlusLevel anywhere, so the
-- live link fetched for a dungeon item below reflects whatever (if any)
-- key-level context EJ defaults to internally, not this addon's key+10
-- assumption (Where2GoRaidRanks.GetMythicPlusIlvl). ReplaceTrackBonusId
-- swaps out just the track-range bonus ID for the caller's own
-- correctly-computed one, keeping any other real bonus ID (e.g. an
-- on-equip-effect variant) intact. Raid items skip this entirely --
-- Mythic raid difficulty is a single fixed tier with no such ambiguity,
-- so their live link's bonus ID is trusted as-is.
local function GetKnownTrackBonusIds()
    local known = {}
    for _, track in pairs(Where2GoTracks.UPGRADE_TRACKS) do
        for i = 0, 5 do
            known[track.bonusIdStart + i] = true
        end
    end
    known[Where2GoRaidRanks.MYTH_FINAL_BONUS_ID] = true
    return known
end

local function ReplaceTrackBonusId(link, trackBonusId)
    local itemString = link:match("|H(item:[^|]+)|h") or link:match("^(item:.+)$")
    local fields = itemString and { strsplit(":", itemString) }
    if not fields or #fields < 14 then
        return link
    end

    local knownTrackBonusIds = GetKnownTrackBonusIds()
    local numBonusIds = tonumber(fields[14]) or 0
    local keptBonusIds = {}
    for i = 1, numBonusIds do
        local bonusId = tonumber(fields[14 + i])
        if bonusId and not knownTrackBonusIds[bonusId] then
            table.insert(keptBonusIds, bonusId)
        end
    end
    table.insert(keptBonusIds, trackBonusId)

    local prefix = table.concat(
        { "item", fields[2], fields[3], fields[4], fields[5], fields[6], fields[7], fields[8], fields[9], fields[10], fields[11], fields[12], fields[13] },
        ":")
    return prefix .. ":" .. #keptBonusIds .. ":" .. table.concat(keptBonusIds, ":")
end

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- itemId -> real link (or false if unavailable), cached for the session.
-- EJ_SelectInstance/EJ_SelectEncounter/EJ_SetLootFilter/EJ_SetDifficulty
-- all mutate GLOBAL shared Encounter Journal state (see
-- reference_ai_vault_addon_knowledge) -- if the player has the real
-- Encounter Journal window open, driving these could make it visibly
-- jump to a different boss. Caching per itemId means this only happens
-- once per item for the whole session, not on every hover.
local liveLinkCache = {}

-- Fetches itemId's REAL item link at its own source's correct difficulty
-- via a live Encounter Journal query (C_EncounterJournal.GetLootInfoByIndex's
-- own `link` field), rather than hand-building a synthetic one. A
-- synthetic link with only our computed track bonus ID (the previous
-- approach) fixes the shown item level but silently discards any OTHER
-- bonus ID the item needs -- e.g. an on-equip-effect variant -- since a
-- plain C_Item.GetItemInfo(itemId) cache never carries bonus IDs at all
-- (confirmed: itemId-only lookups always return the bonus-ID-less base
-- form). Blizzard's own EJ link for this exact instance/boss/difficulty
-- has no such gap. Confirmed live on Ula'tek's Aqirbane Reliquary (268265)
-- and The Coiled Altar's item, both of which lost their on-equip effect
-- description in our addon's tooltip specifically (not in the real
-- Encounter Journal) before this fix.
local function FetchLiveItemLink(itemId, trackBonusId)
    if liveLinkCache[itemId] ~= nil then
        return liveLinkCache[itemId] or nil
    end

    local source = GetItemSource(itemId)
    if not source or not EJ_SelectInstance or not C_EncounterJournal then
        liveLinkCache[itemId] = false
        return nil
    end

    EnsureEncounterJournalLoaded()
    EJ_SetDifficulty(source.isRaid and EJ_MYTHIC_RAID_DIFFICULTY or EJ_MYTHIC_KEYSTONE_DIFFICULTY)
    EJ_SelectInstance(source.instanceId)
    EJ_SelectEncounter(source.bossId)
    EJ_SetLootFilter(0, 0)

    local link
    local numLoot = EJ_GetNumLoot() or 0
    for i = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID == itemId then
            link = info.link
            break
        end
    end

    if link and not source.isRaid then
        link = ReplaceTrackBonusId(link, trackBonusId)
    end

    liveLinkCache[itemId] = link or false
    return link
end

-- Builds the icon+name+summary sub-widgets on a fresh row frame. Callers
-- create one row per pooled slot (matching this project's existing
-- pooled-row pattern) and call this once at row creation, then call
-- Populate on every refresh. `leftOffset` shifts the icon right of any
-- caller-owned control (e.g. a checkbox) that occupies the row's own
-- left edge; 0 (or omitted) means the icon starts flush at the row's
-- left edge.
function Where2GoItemRow.CreateWidgets(row, iconSize, leftOffset)
    leftOffset = leftOffset or 0

    -- Hover highlight (mockup's ".w2g-row:hover" treatment) -- shown/hidden
    -- alongside the tooltip in Populate's OnEnter/OnLeave below, so every
    -- row using this shared widget set gets the same "row you're looking
    -- at" feedback.
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(unpack(Where2GoTheme.colors.hover))
    row.highlight:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetPoint("LEFT", leftOffset, 0)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 6)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.summary:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.summary:SetJustifyH("LEFT")
    row.summary:SetWordWrap(false)
    row.summary:SetTextColor(unpack(Where2GoTheme.colors.muted))
end

-- Fills an already-built row's widgets for one item and wires hover ->
-- real GameTooltip. `ilvl` is the caller-computed effective item level
-- for this item's source (nil is fine -- the summary line just omits it,
-- used by Preferred rows which don't carry a single fixed
-- source). `sourceLabel` (optional) is appended as an extra tooltip line
-- -- e.g. which dungeon or raid boss drops this item -- kept out of the
-- visible row text per this project's "no boss-name clutter" item-row
-- goal, but still available on hover (see
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md).
-- `bonusId` (optional, from Where2GoRaidRanks.GetRaidIlvl/GetMythicPlusIlvl)
-- is the item's real upgrade-track bonus ID for this source -- when known,
-- the tooltip is built from a synthetic tracked link (SetHyperlink) instead
-- of the item's cached base-form data (SetItemByID), which otherwise shows
-- whatever level happened to be cached (e.g. an untracked base ilvl like
-- 219 for gear that's actually dropping on a much higher upgrade track) --
-- see docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md and
-- the wow-item-level-bonus-id-system vault page's "SetHyperlink vs
-- SetItemByID" note. Falls back to SetItemByID when bonusId is nil
-- (for saved preferences without a recorded source/track).
--
-- Cold-item-cache items show a placeholder icon/name. Both windows refresh
-- their existing rows after relevant item-cache events while visible.
function Where2GoItemRow.Populate(row, itemId, ilvl, sourceLabel, bonusId)
    local name, _, quality = C_Item.GetItemInfo(itemId)
    local icon = C_Item.GetItemIconByID(itemId)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local color = quality and ITEM_QUALITY_COLORS[quality]
    local hex = color and color.hex or "|cffffffff"
    row.name:SetText(hex .. (name or ("Item #" .. itemId)) .. "|r")

    local statLabels = {}
    local itemStats = Where2GoItemStats.STATS[itemId]
    if itemStats then
        for _, stat in ipairs(itemStats.secondaryStats) do
            table.insert(statLabels, Where2GoLocale.StatAbbrev(stat))
        end
    end
    local statText = #statLabels > 0 and table.concat(statLabels, "/") or ""
    if ilvl and statText ~= "" then
        row.summary:SetText(ilvl .. " · " .. statText)
    elseif ilvl then
        row.summary:SetText(tostring(ilvl))
    else
        row.summary:SetText(statText)
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local liveLink = bonusId and FetchLiveItemLink(itemId, bonusId)
        if liveLink then
            GameTooltip:SetHyperlink(liveLink)
        elseif bonusId then
            -- Fallback: a live EJ lookup wasn't possible (item not in
            -- Sources.lua, or the Encounter Journal API isn't available)
            -- -- a fully-synthetic link still fixes the shown item level,
            -- it just can't preserve any other real bonus ID.
            GameTooltip:SetHyperlink(string.format("item:%d:0:0:0:0:0:0:0:0:0:0:0:1:%d", itemId, bonusId))
        else
            GameTooltip:SetItemByID(itemId)
        end
        if sourceLabel then
            GameTooltip:AddLine(sourceLabel, 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)
end
