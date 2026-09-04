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

Where2GoItemRow.STAT_ABBREV = {
    CRIT_RATING = "Crit", HASTE_RATING = "Haste",
    MASTERY_RATING = "Mastery", VERSATILITY = "Vers",
}

-- Builds the icon+name+summary sub-widgets on a fresh row frame. Callers
-- create one row per pooled slot (matching this project's existing
-- pooled-row pattern) and call this once at row creation, then call
-- Populate on every refresh. `leftOffset` shifts the icon right of any
-- caller-owned control (e.g. a checkbox) that occupies the row's own
-- left edge; 0 (or omitted) means the icon starts flush at the row's
-- left edge.
function Where2GoItemRow.CreateWidgets(row, iconSize, leftOffset)
    leftOffset = leftOffset or 0

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
end

-- Fills an already-built row's widgets for one item and wires hover ->
-- real GameTooltip. `ilvl` is the caller-computed effective item level
-- for this item's source (nil is fine -- the summary line just omits it,
-- used by Staged/Preferred rows which don't carry a single fixed
-- source). `sourceLabel` (optional) is appended as an extra tooltip line
-- -- e.g. which dungeon or raid boss drops this item -- kept out of the
-- visible row text per this project's "no boss-name clutter" item-row
-- goal, but still available on hover (see
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md).
-- Cold-item-cache items show a placeholder icon/name; only
-- UI/BrowserPanel.lua's Results rows self-heal automatically (its
-- GET_ITEM_INFO_RECEIVED watcher triggers a rebuild) -- UI/Panel.lua's
-- cards populate once per card build and refresh only when the panel is
-- next reopened, matching this file's pre-existing behavior.
function Where2GoItemRow.Populate(row, itemId, ilvl, sourceLabel)
    local name, _, quality = C_Item.GetItemInfo(itemId)
    local icon = C_Item.GetItemIcon(itemId)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local color = quality and ITEM_QUALITY_COLORS[quality]
    local hex = color and color.hex or "|cffffffff"
    row.name:SetText(hex .. (name or ("Item #" .. itemId)) .. "|r")

    local statLabels = {}
    local itemStats = Where2GoItemStats.STATS[itemId]
    if itemStats then
        for _, stat in ipairs(itemStats.secondaryStats) do
            table.insert(statLabels, Where2GoItemRow.STAT_ABBREV[stat] or stat)
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
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemId)
        if sourceLabel then
            GameTooltip:AddLine(sourceLabel, 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
