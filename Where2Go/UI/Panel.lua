local panelFrame
local contentFrame
local cardFrames = {}
local Layout
local currentView = "DROP"

local HEADER_HEIGHT = 62

-- Same palette as UI/BrowserPanel.lua, ported from the Phase 9 design
-- mockup's CSS (dark stone/parchment + gold trim). Duplicated locally
-- rather than shared since both files' copies are a one-time port from
-- the same fixed mockup values, not something expected to drift.
local COLORS = {
    windowBg = { 0.078, 0.055, 0.031 },      -- #140e08
    windowBorder = { 0.478, 0.353, 0.173 },  -- #7a5a2c
    gold = { 0.941, 0.831, 0.533 },          -- #f0d488
    mutedTan = { 0.541, 0.459, 0.314 },      -- #8a7550
    cardBg = { 0.063, 0.043, 0.024 },        -- #100b06
    cardBorder = { 0.251, 0.192, 0.102 },    -- #40311a
    cardHeadBg = { 0.102, 0.075, 0.035 },    -- #1a1309
}

local function BuildHeaderText(result, expanded)
    local mark = expanded and "[-]" or "[+]"
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    return string.format("%s %s%s   %d/%d  |cffffffff%d|r |cff9d9d9d(%s %d/6)|r",
        mark, prefix, result.name, result.targetCount, result.eligibleCount,
        result.ilvl, Where2GoLocale.TrackLabel(result.trackKey), result.trackRank)
end

local function CreateCard(parent, result)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("LEFT", parent, "LEFT", 0, 0)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    card:SetBackdropColor(unpack(COLORS.cardBg))
    card:SetBackdropBorderColor(unpack(COLORS.cardBorder))

    local header = CreateFrame("Button", nil, card, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    header:SetHeight(18)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    header:SetBackdropColor(unpack(COLORS.cardHeadBg))

    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", 4, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWidth(332)
    headerText:SetTextColor(unpack(COLORS.gold))

    local ITEM_ROW_HEIGHT = 32
    local ITEM_ICON_SIZE = 24
    local ITEM_ROW_WIDTH = 324

    local itemRows = {}
    local rowY = -18
    for _, itemId in ipairs(result.targetItemIds) do
        local row = CreateFrame("Frame", nil, card)
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetSize(ITEM_ROW_WIDTH, ITEM_ROW_HEIGHT)
        Where2GoItemRow.CreateWidgets(row, ITEM_ICON_SIZE, 0)
        row.name:SetWidth(ITEM_ROW_WIDTH - ITEM_ICON_SIZE - 4)
        row.summary:SetWidth(ITEM_ROW_WIDTH - ITEM_ICON_SIZE - 4)
        Where2GoItemRow.Populate(row, itemId, result.ilvl)
        table.insert(itemRows, row)
        rowY = rowY - ITEM_ROW_HEIGHT
    end

    local cardData = {
        frame = card,
        expanded = true,
        collapsedHeight = 18,
        expandedHeight = 18 + (#itemRows * ITEM_ROW_HEIGHT),
    }
    headerText:SetText(BuildHeaderText(result, cardData.expanded))

    header:SetScript("OnClick", function()
        cardData.expanded = not cardData.expanded
        for _, row in ipairs(itemRows) do
            if cardData.expanded then
                row:Show()
            else
                row:Hide()
            end
        end
        headerText:SetText(BuildHeaderText(result, cardData.expanded))
        Layout()
    end)

    return cardData
end

Layout = function()
    local y = 0
    for _, cardData in ipairs(cardFrames) do
        cardData.frame:ClearAllPoints()
        cardData.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, y)
        cardData.frame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
        local height = cardData.expanded and cardData.expandedHeight or cardData.collapsedHeight
        cardData.frame:SetHeight(height)
        y = y - height - 6
    end
    local totalHeight = -y
    contentFrame:SetHeight(totalHeight)
    panelFrame:SetHeight(HEADER_HEIGHT + totalHeight + 12)
end

local function GetRankedResultsForCurrentView()
    if currentView == "VOIDCORE" then
        return Where2GoVoidcoreDrop.GetRankedResults()
    end
    return Where2GoDirectDrop.GetRankedResults()
end

local function RefreshContent()
    for _, cardData in ipairs(cardFrames) do
        cardData.frame:Hide()
        cardData.frame:SetParent(nil)
    end
    cardFrames = {}

    local results = GetRankedResultsForCurrentView()
    if not results then
        local msgFrame = CreateFrame("Frame", nil, contentFrame)
        msgFrame:SetPoint("TOPLEFT", 0, 0)
        local text = msgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetText(Where2GoLocale.L("NO_SPEC_SELECTED"))
        msgFrame:SetHeight(18)
        contentFrame:SetHeight(18)
        panelFrame:SetHeight(HEADER_HEIGHT + 18 + 12)
        return
    end

    for _, result in ipairs(results) do
        table.insert(cardFrames, CreateCard(contentFrame, result))
    end
    Layout()
end

local tabButtons = {}

local function UpdateTabStyles()
    for _, tab in ipairs(tabButtons) do
        if tab.view == currentView then
            tab.bg:SetColorTexture(unpack(COLORS.cardHeadBg))
            tab.text:SetTextColor(unpack(COLORS.gold))
        else
            tab.bg:SetColorTexture(unpack(COLORS.windowBg))
            tab.text:SetTextColor(unpack(COLORS.mutedTan))
        end
    end
end

local function CreateTab(parent, label, view, x)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(80, 20)
    tab:SetPoint("TOPLEFT", x, -34)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label)

    tab.view = view
    tab.bg = bg
    tab.text = text
    table.insert(tabButtons, tab)

    tab:SetScript("OnClick", function()
        currentView = view
        UpdateTabStyles()
        RefreshContent()
    end)

    return tab
end

local function CreatePanel()
    local frame = CreateFrame("Frame", "Where2GoPanel", UIParent, "BackdropTemplate")
    frame:SetSize(380, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(unpack(COLORS.windowBg))
    frame:SetBackdropBorderColor(unpack(COLORS.windowBorder))

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(Where2GoConstants.ADDON_NAME)
    title:SetTextColor(unpack(COLORS.gold))

    CreateTab(frame, Where2GoLocale.L("MODE_DROP"), "DROP", 12)
    CreateTab(frame, Where2GoLocale.L("MODE_VOIDCORE"), "VOIDCORE", 96)
    UpdateTabStyles()

    local browseButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    browseButton:SetSize(70, 20)
    browseButton:SetPoint("TOPRIGHT", -28, -34)
    browseButton:SetText(Where2GoLocale.L("BROWSE_BUTTON"))
    browseButton:SetScript("OnClick", function()
        Where2GoBrowserPanel.Toggle()
    end)

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 12, -HEADER_HEIGHT)
    contentFrame:SetPoint("RIGHT", frame, "RIGHT", -12, 0)

    frame:Hide()
    return frame
end

function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        RefreshContent()
        panelFrame:Show()
    end
end
