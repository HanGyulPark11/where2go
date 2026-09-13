-- Shared item-row rendering: icon + quality-colored name + a compact
-- "slot · ilvl · secondary-stat" summary line, with a real GameTooltip on hover.
-- luacheck: globals C_TooltipInfo TooltipUtil ITEM_LEVEL Where2GoItemLinkBonuses
-- Used by both UI/BrowserPanel.lua (Results/Staged/Preferred rows) and
-- UI/Panel.lua (expanded card item rows) so both windows render items
-- identically. See
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md.
--
-- WoW-API-dependent (CreateTexture/CreateFontString/C_Item/GameTooltip).
-- Frame-double tests cover the shared behavior; live-client QA covers actual
-- Blizzard tooltip rendering and API compatibility.

Where2GoItemRow = {}

local hoveredRows = setmetatable({}, { __mode = "k" })

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
    local itemLevelLabel = ITEM_LEVEL and ITEM_LEVEL:gsub("%%d", "") or "Item Level"
    local trackLabel = Where2GoLocale.TrackLabel(trackKey)
    local sawIlvl, sawTrack, sawAnyTrack, sawConflictingTrack, sawPlainTrack = false, false, false, false, false
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if text then
            if text:find(itemLevelLabel, 1, true) and tonumber(text:match("(%d+)")) == ilvl then
                sawIlvl = true
            end
            if text:find(trackLabel, 1, true) and not text:find("%d+/%d+") then
                sawPlainTrack = true
            end
            for candidateKey in pairs(Where2GoTracks.UPGRADE_TRACKS) do
                local candidateLabel = Where2GoLocale.TrackLabel(candidateKey)
                if text:find(candidateLabel, 1, true) and text:find("%d+/%d+") then
                    sawAnyTrack = true
                    local candidateRank = tonumber(text:match("(%d+)/%d+"))
                    if candidateKey == trackKey and candidateRank == trackRank then
                        sawTrack = true
                    else
                        sawConflictingTrack = true
                    end
                    break
                end
            end
        end
    end
    if sawAnyTrack and (sawConflictingTrack or not sawTrack) then return false end
    if sawIlvl and sawTrack then return true end
    local track = Where2GoTracks.UPGRADE_TRACKS[trackKey]
    if sawIlvl and sawPlainTrack and track and track.ilvls and trackRank > #track.ilvls then
        return true
    end
    return nil
end

local function BuildSyntheticLink(itemId, trackBonusId, extraBonusIds)
    local bonusIds = {}
    if extraBonusIds then
        for _, bonusId in ipairs(extraBonusIds) do
            table.insert(bonusIds, bonusId)
        end
    end
    table.insert(bonusIds, trackBonusId)
    return string.format("item:%d:0:0:0:0:0:0:0:0:0:0:0:%d:%s", itemId, #bonusIds, table.concat(bonusIds, ":"))
end

local function BuildContextualLink(itemId, trackBonusId)
    local template = Where2GoItemLinkBonuses.TEMPLATES and Where2GoItemLinkBonuses.TEMPLATES[itemId]
    if type(template) ~= "string" then
        return nil
    end
    local fields = {}
    for field in (template .. ":"):gmatch("([^:]*):") do
        table.insert(fields, field)
    end
    local templateItemId = tonumber(fields[2])
    local bonusCount = tonumber(fields[14])
    if fields[1] ~= "item" or templateItemId ~= itemId or not bonusCount
        or bonusCount < 0 or bonusCount % 1 ~= 0 or #fields < 14 + bonusCount then
        return nil
    end

    local rebuilt = {}
    for index = 1, 14 do
        rebuilt[index] = fields[index]
    end
    rebuilt[14] = tostring(bonusCount + 1)
    for index = 1, bonusCount do
        rebuilt[14 + index] = fields[14 + index]
    end
    table.insert(rebuilt, trackBonusId)
    for index = 15 + bonusCount, #fields do
        table.insert(rebuilt, fields[index])
    end
    return table.concat(rebuilt, ":")
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

    local displayQuality = bonusId and 4 or quality
    local color = displayQuality and ITEM_QUALITY_COLORS[displayQuality]
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
        if bonusId then
            local canonicalLink = BuildSyntheticLink(itemId, bonusId)
            local fullLink = BuildContextualLink(itemId, bonusId)
            if fullLink and TooltipMatchesRequestedLevel(fullLink, ilvl, trackKey, trackRank) then
                GameTooltip:SetHyperlink(fullLink)
            else
                GameTooltip:SetHyperlink(canonicalLink)
            end
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
