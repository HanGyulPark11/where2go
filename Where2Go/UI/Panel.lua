local panelFrame

local function AddRow(frame, y, text)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetPoint("TOPLEFT", 12, y)
    line:SetJustifyH("LEFT")
    line:SetWidth(336)
    line:SetText(text)
end

local function AddCardLine(frame, y, entry)
    local text = string.format("%s   %d/%d  |cff9d9d9d(%s)|r",
        entry.name, entry.targetCount, entry.poolSize, entry.recommendedLootSpec)
    AddRow(frame, y, text)
end

local function CreatePanel()
    local frame = CreateFrame("Frame", "Where2GoPanel", UIParent, "BackdropTemplate")
    frame:SetSize(380, 340)
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

    local y = -40
    AddRow(frame, y, "|cffffd200Mythic+|r")
    y = y - 18
    AddCardLine(frame, y, Where2GoFixtures.dungeon)
    y = y - 24

    AddRow(frame, y, "|cffffd200" .. Where2GoFixtures.raid.name .. "|r")
    y = y - 18
    for _, encounter in ipairs(Where2GoFixtures.raid.encounters) do
        AddCardLine(frame, y, encounter)
        y = y - 18
    end

    return frame
end

function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        panelFrame:Show()
    end
end
