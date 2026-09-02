local panelFrame
local contentFrame
local cardFrames = {}
local Layout
local currentView = "DROP"

local HEADER_HEIGHT = 62

local function BuildHeaderText(result, expanded)
    local mark = expanded and "[-]" or "[+]"
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    return string.format("%s %s%s   %d/%d  |cffffffff%d|r |cff9d9d9d(%s %d/6)|r",
        mark, prefix, result.name, result.targetCount, result.eligibleCount,
        result.ilvl, result.trackLabel, result.trackRank)
end

local function CreateCard(parent, result)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("LEFT", parent, "LEFT", 0, 0)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local header = CreateFrame("Button", nil, card)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    header:SetHeight(18)

    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", 0, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWidth(336)

    local itemRows = {}
    local itemNames = Where2GoDirectDrop.GetItemNames(result.targetItemIds)
    local rowY = -18
    for _, itemId in ipairs(result.targetItemIds) do
        local row = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetJustifyH("LEFT")
        row:SetWidth(324)
        row:SetText(itemNames[itemId])
        table.insert(itemRows, row)
        rowY = rowY - 14
    end

    local cardData = {
        frame = card,
        expanded = true,
        collapsedHeight = 18,
        expandedHeight = 18 + (#itemRows * 14),
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
        text:SetText("Where2Go: no specialization selected.")
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

local function CreateTab(parent, label, view, x)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(80, 20)
    tab:SetPoint("TOPLEFT", x, -34)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    text:SetText(label)

    tab:SetScript("OnClick", function()
        currentView = view
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
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(Where2GoConstants.ADDON_NAME)

    CreateTab(frame, "Drop", "DROP", 12)
    CreateTab(frame, "Voidcore", "VOIDCORE", 96)

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
