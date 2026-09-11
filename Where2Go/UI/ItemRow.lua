-- Shared item-row rendering: icon + quality-colored name + a compact
-- "slot · ilvl · secondary-stat" summary line, with a real GameTooltip on hover.
-- luacheck: globals C_TooltipInfo TooltipUtil
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
-- on-equip-effect variant) intact. Encounter Journal links may be returned
-- at a lower rank than the recommendation for either dungeon or raid loot,
-- so both use the caller's calculated track bonus ID.
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
    local trailingFields = {}
    for i = 15 + numBonusIds, #fields do
        table.insert(trailingFields, fields[i])
    end
    local replaced = prefix .. ":" .. #keptBonusIds .. ":" .. table.concat(keptBonusIds, ":")
    if #trailingFields > 0 then
        replaced = replaced .. ":" .. table.concat(trailingFields, ":")
    end
    return replaced
end

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- itemId -> requested track bonus ID -> validated real link or false for a
-- definitive metadata conflict, cached for the session.
-- EJ_SelectInstance/EJ_SelectEncounter/EJ_SetLootFilter/EJ_SetDifficulty
-- all mutate GLOBAL shared Encounter Journal state (see
-- reference_ai_vault_addon_knowledge) -- if the player has the real
-- Encounter Journal window open, driving these could make it visibly
-- jump to a different boss. Successful lookups are cached per requested
-- track, so another rank cannot reuse the first rank's link. Missing EJ data
-- is not cached because the client can populate it between two hovers.
local liveLinkCache = {}
local hoveredRows = setmetatable({}, { __mode = "k" })

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
local function TooltipMatchesRequestedLevel(link, ilvl, trackKey, trackRank)
    if not ilvl or not trackKey or not trackRank then return false end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok or not data or not data.lines then
        return nil
    end
    if TooltipUtil and TooltipUtil.SurfaceArgs then
        ok = pcall(TooltipUtil.SurfaceArgs, data)
        if not ok then return nil end
    end
    local trackLabel = Where2GoLocale.TrackLabel(trackKey)
    local sawIlvl, sawTrack, sawAnyTrack = false, false, false
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            if tonumber(text:match("(%d+)")) == ilvl then sawIlvl = true end
            if text:find(trackLabel, 1, true) and text:find(trackRank .. "/", 1, true) then sawTrack = true end
            for candidateKey in pairs(Where2GoTracks.UPGRADE_TRACKS) do
                local candidateLabel = Where2GoLocale.TrackLabel(candidateKey)
                if text:find(candidateLabel, 1, true) and text:find("%d+/%d+") then
                    sawAnyTrack = true
                    break
                end
            end
        end
    end
    local track = Where2GoTracks.UPGRADE_TRACKS[trackKey]
    local regularRankCount = track and track.ilvls and #track.ilvls or 6
    if sawIlvl and (sawTrack or trackRank > regularRankCount) then return true end
    if sawAnyTrack then return false end
    return nil
end

local function FetchLiveItemLink(itemId, trackBonusId, ilvl, trackKey, trackRank)
    if not ilvl or not trackKey or not trackRank then
        return nil
    end
    local itemCache = liveLinkCache[itemId]
    if itemCache and itemCache[trackBonusId] ~= nil then
        return itemCache[trackBonusId] or nil
    end

    local source = GetItemSource(itemId)
    if not source then
        return nil
    end

    EnsureEncounterJournalLoaded()
    if not EJ_SetDifficulty or not EJ_SelectInstance or not EJ_SelectEncounter
        or not EJ_SetLootFilter or not EJ_GetNumLoot or not C_EncounterJournal
        or not C_EncounterJournal.GetLootInfoByIndex then
        return nil
    end
    EJ_SelectInstance(source.instanceId)
    EJ_SetDifficulty(source.isRaid and EJ_MYTHIC_RAID_DIFFICULTY or EJ_MYTHIC_KEYSTONE_DIFFICULTY)
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

    if link then
        link = ReplaceTrackBonusId(link, trackBonusId)
        local validation = TooltipMatchesRequestedLevel(link, ilvl, trackKey, trackRank)
        if validation then
            itemCache = itemCache or {}
            itemCache[trackBonusId] = link
            liveLinkCache[itemId] = itemCache
        elseif validation == false then
            itemCache = itemCache or {}
            itemCache[trackBonusId] = false
            liveLinkCache[itemId] = itemCache
            link = nil
        else
            link = nil
        end
    end
    return link
end

function Where2GoItemRow.GetLevelFromBonus(bonusId)
    if type(bonusId) ~= "number" then
        return
    end
    if bonusId == Where2GoRaidRanks.MYTH_FINAL_BONUS_ID then
        return Where2GoRaidRanks.MYTH_FINAL_ILVL, "MYTH", Where2GoRaidRanks.MYTH_FINAL_RANK
    end
    for trackKey, track in pairs(Where2GoTracks.UPGRADE_TRACKS) do
        local rank = bonusId and bonusId - track.bonusIdStart + 1
        if rank and rank >= 1 and rank <= #track.ilvls then
            return track.ilvls[rank], trackKey, rank
        end
    end
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
function Where2GoItemRow.Populate(row, itemId, ilvl, sourceLabel, bonusId, trackKey, trackRank)
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
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    local slot = Where2GoConstants and Where2GoConstants.EQUIPLOC_TO_SLOT
        and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
    local summaryParts = {}
    if slot then table.insert(summaryParts, Where2GoLocale.SlotLabel(slot)) end
    if ilvl then table.insert(summaryParts, tostring(ilvl)) end
    if statText ~= "" then table.insert(summaryParts, statText) end
    row.summary:SetText(table.concat(summaryParts, " · "))

    local function ShowTooltip(self)
        self.highlight:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local liveLink = bonusId and FetchLiveItemLink(itemId, bonusId, ilvl, trackKey, trackRank)
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
    end

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        hoveredRows[self] = true
        ShowTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        hoveredRows[self] = nil
        self.highlight:Hide()
        GameTooltip:Hide()
    end)
    local tooltipVisible = hoveredRows[row]
    if GameTooltip and GameTooltip.IsOwned then tooltipVisible = GameTooltip:IsOwned(row) end
    if tooltipVisible then ShowTooltip(row) end
end
