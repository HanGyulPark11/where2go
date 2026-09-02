local panelFrame
local contentFrame
local cardFrames = {}

local function ClearCards()
    for _, card in ipairs(cardFrames) do
        card:Hide()
        card:SetParent(nil)
    end
    cardFrames = {}
end

local function CreateCard(parent, y, result)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 0, y)
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local headerText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("TOPLEFT", 0, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetWidth(336)
    local prefix = result.raidName and (result.raidName .. " - ") or ""
    headerText:SetText(string.format("%s%s   %d/%d  |cff9d9d9d(%s %d/6)|r",
        prefix, result.name, result.targetCount, result.eligibleCount, result.trackLabel, result.trackRank))

    local rowY = -18
    local itemNames = Where2GoDirectDrop.GetItemNames(result.targetItemIds)
    for _, itemId in ipairs(result.targetItemIds) do
        local row = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 12, rowY)
        row:SetJustifyH("LEFT")
        row:SetWidth(324)
        row:SetText(itemNames[itemId])
        rowY = rowY - 14
    end

    card:SetHeight(-rowY + 4)
    return card
end

local function RefreshContent()
    ClearCards()

    local results = Where2GoDirectDrop.GetRankedResults()
    if not results then
        local card = CreateFrame("Frame", nil, contentFrame)
        card:SetPoint("TOPLEFT", 0, 0)
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", 0, 0)
        text:SetText("Where2Go: no specialization selected.")
        card:SetHeight(18)
        table.insert(cardFrames, card)
        contentFrame:SetHeight(18)
        return
    end

    local y = 0
    for _, result in ipairs(results) do
        local card = CreateCard(contentFrame, y, result)
        table.insert(cardFrames, card)
        y = y - card:GetHeight() - 6
    end
    contentFrame:SetHeight(-y)
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

    contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", 12, -40)
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
