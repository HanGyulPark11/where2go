Where2GoPanel = {}

local PANEL_WIDTH = 390
local EXPANDED_HEIGHT = 510
local COLLAPSED_HEIGHT = 38
local TITLE_HEIGHT = 38
local CONTROLS_HEIGHT = 108
local VIEWPORT_HEIGHT = EXPANDED_HEIGHT - TITLE_HEIGHT - CONTROLS_HEIGHT - 16
local CARD_HEADER_HEIGHT = 60
local ITEM_ROW_HEIGHT = 32
local CARD_GAP = 6
local PANEL_GAP = 8
local SOURCE_FILTER_KINDS = { DUNGEONS = "dungeon", RAIDS = "raid" }

local panelFrame
local bodyFrame
local scrollFrame
local contentFrame
local emptyText
local specText
local summaryText
local collapseButton
local ownershipButton
local sourceFilterButton
local modeButtons = {}
local cardPool = {}
local expansionByContent = {}
local currentMode = "DROP"
local currentSourceFilter = "ALL"
local hookedPVEFrame

local LayoutCards

local function L(key)
    return Where2GoLocale.L(key)
end

local function CountPreferred(preferred)
    local count = 0
    for _, selected in pairs(preferred or {}) do
        if selected == true then
            count = count + 1
        end
    end
    return count
end

local function EnsureCharacterUI()
    Where2GoCharDB = Where2GoCharDB or {}
    Where2GoCharDB.ui = Where2GoCharDB.ui or {}
    if Where2GoCharDB.ui.panelCollapsed == nil then
        Where2GoCharDB.ui.panelCollapsed = false
    end
    local position = Where2GoCharDB.ui.panelPosition
    if type(position) ~= "table" or type(position.x) ~= "number" or type(position.y) ~= "number"
        or position.x ~= position.x or position.y ~= position.y
        or position.x == math.huge or position.x == -math.huge
        or position.y == math.huge or position.y == -math.huge then
        Where2GoCharDB.ui.panelPosition = nil
    end
    return Where2GoCharDB.ui
end

local function SetModeButtonStyles()
    for mode, button in pairs(modeButtons) do
        Where2GoTheme.Box(button, mode == currentMode and "selected" or "surface")
    end
end

local function UpdateCollapsedState()
    if not panelFrame then
        return
    end
    local collapsed = EnsureCharacterUI().panelCollapsed == true
    bodyFrame:SetShown(not collapsed)
    panelFrame:SetHeight(collapsed and COLLAPSED_HEIGHT or EXPANDED_HEIGHT)
    collapseButton:SetText(collapsed and "+" or "-")
end

local function ContentKey(result)
    return result.id or ((result.raidName or result.kind or "content") .. ":" .. tostring(result.name))
end

local function ContentName(name)
    return Where2GoLocale.ContentName(name)
end

local function EnsureItemRow(card, index)
    local row = card.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", string.format("Where2GoPanelCard%dRow%d", card.index, index), card.frame)
    row:SetSize(PANEL_WIDTH - 70, ITEM_ROW_HEIGHT)
    Where2GoItemRow.CreateWidgets(row, 24, 0)
    row.name:SetWidth(PANEL_WIDTH - 98)
    row.summary:SetWidth(PANEL_WIDTH - 98)
    card.rows[index] = row
    return row
end

local function ApplyCardExpansion(card)
    card.expanded = expansionByContent[card.contentKey] ~= false
    for index, row in ipairs(card.rows) do
        row:SetShown(card.expanded and index <= card.rowCount)
    end
    card.frame:SetHeight(card.expanded and card.expandedHeight or CARD_HEADER_HEIGHT)
end

local function CreateCard(index)
    local frame = CreateFrame("Frame", "Where2GoPanelCard" .. index, contentFrame, "BackdropTemplate")
    Where2GoTheme.Box(frame, "surface")

    local header = CreateFrame("Button", "Where2GoPanelCard" .. index .. "Header", frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(CARD_HEADER_HEIGHT)
    Where2GoTheme.Box(header, "inset")

    local nameText = Where2GoTheme.Text(header, "GameFontHighlight", "")
    nameText:SetPoint("TOPLEFT", 8, -6)
    nameText:SetPoint("TOPRIGHT", -28, -6)
    nameText:SetWordWrap(false)

    local toggleText = Where2GoTheme.Text(header, "GameFontHighlight", "−")
    toggleText:SetPoint("TOPRIGHT", -8, -6)

    local countsText = Where2GoTheme.Text(header, "GameFontDisableSmall", "")
    countsText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    countsText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    countsText:SetTextColor(unpack(Where2GoTheme.colors.muted))
    countsText:SetWordWrap(false)
    local detailText = Where2GoTheme.Text(header, "GameFontHighlightSmall", "")
    detailText:SetPoint("TOPLEFT", 8, -40)
    detailText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    detailText:SetWordWrap(false)
    detailText:SetTextColor(unpack(Where2GoTheme.colors.muted))
    frame.nameText, frame.countsText = nameText, countsText

    local card = {
        index = index,
        frame = frame,
        header = header,
        nameText = nameText,
        countsText = countsText,
        detailText = detailText,
        toggleText = toggleText,
        rows = {},
        rowCount = 0,
        expandedHeight = CARD_HEADER_HEIGHT,
    }

    header:SetScript("OnClick", function()
        if not card.contentKey then
            return
        end
        expansionByContent[card.contentKey] = not card.expanded
        ApplyCardExpansion(card)
        card.toggleText:SetText(card.expanded and "−" or "+")
        LayoutCards()
    end)

    return card
end

local function EnsureCard(index)
    if not cardPool[index] then
        cardPool[index] = CreateCard(index)
    end
    return cardPool[index]
end

local function PopulateCard(card, result)
    card.contentKey = ContentKey(result)
    card.rowCount = #(result.targetItemIds or {})
    card.expandedHeight = CARD_HEADER_HEIGHT + (card.rowCount * ITEM_ROW_HEIGHT)

    local displayName = ContentName(result.name or "")
    local displayRaidName = result.raidName and ContentName(result.raidName) or ""
    card.nameText:SetText(displayName)

    local counts = string.format(L("PANEL_CARD_COUNTS"), result.targetCount or card.rowCount,
        result.eligibleCount or 0)
    local detail = displayRaidName
    if result.ilvl then
        local track = result.trackKey and Where2GoLocale.TrackLabel(result.trackKey) or nil
        local level
        if track and result.trackRank then
            level = string.format("%d · %s %d/6", result.ilvl, track, result.trackRank)
        else
            level = tostring(result.ilvl)
        end
        detail = detail ~= "" and (detail .. " · " .. level) or level
    end
    card.countsText:SetText(counts)
    card.detailText:SetText(detail)
    card.header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(displayName)
        GameTooltip:AddLine(detail, 0.7, 0.75, 0.8, true)
        GameTooltip:AddLine(counts, 1, 1, 1, true)
        GameTooltip:AddLine(L("PANEL_ESTIMATE_HELP"), 0.7, 0.75, 0.8, true)
        GameTooltip:Show()
    end)
    card.header:SetScript("OnLeave", function() GameTooltip:Hide() end)

    for index, itemId in ipairs(result.targetItemIds or {}) do
        local row = EnsureItemRow(card, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card.frame, "TOPLEFT", 14, -CARD_HEADER_HEIGHT - ((index - 1) * ITEM_ROW_HEIGHT))
        Where2GoItemRow.Populate(row, itemId, result.ilvl, displayName, result.bonusId,
            result.trackKey, result.trackRank)
    end

    for index = card.rowCount + 1, #card.rows do
        card.rows[index]:Hide()
    end

    if expansionByContent[card.contentKey] == nil then
        expansionByContent[card.contentKey] = true
    end
    ApplyCardExpansion(card)
    card.toggleText:SetText(card.expanded and "−" or "+")
    card.frame:Show()
end

LayoutCards = function()
    local y = 0
    for _, card in ipairs(cardPool) do
        if card.frame:IsShown() then
            card.frame:ClearAllPoints()
            card.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, y)
            card.frame:SetPoint("RIGHT", contentFrame, "RIGHT", 0, 0)
            card.frame:SetHeight(card.expanded and card.expandedHeight or CARD_HEADER_HEIGHT)
            y = y - card.frame:GetHeight() - CARD_GAP
        end
    end
    local height = math.max(VIEWPORT_HEIGHT, -y)
    contentFrame:SetHeight(height)
    scrollFrame:SetVerticalScroll(math.min(scrollFrame:GetVerticalScroll(), height - VIEWPORT_HEIGHT))
end

local function ShowEmpty(message)
    for _, card in ipairs(cardPool) do
        card.frame:Hide()
    end
    emptyText:SetText(message)
    emptyText:Show()
    contentFrame:SetHeight(VIEWPORT_HEIGHT)
    scrollFrame:SetVerticalScroll(0)
end

local function GetRankedResults()
    if currentMode == "VOIDCORE" then
        return Where2GoVoidcoreDrop.GetRankedResults()
    end
    return Where2GoDirectDrop.GetRankedResults()
end

local function OwnershipMode()
    local mode = Where2GoEquipment.GetOwnershipMode()
    return mode == "SLOT" and "SLOT" or "ITEM"
end

local function UpdateOwnershipButton()
    if ownershipButton then
        ownershipButton:SetText(L(OwnershipMode() == "SLOT" and "PANEL_OWNERSHIP_SLOT" or "PANEL_OWNERSHIP_ITEM"))
    end
end

local function UpdateSourceFilterButton()
    if sourceFilterButton then
        sourceFilterButton:SetText(L("PANEL_SOURCE_" .. currentSourceFilter))
        Where2GoTheme.Box(sourceFilterButton, "surface")
        sourceFilterButton:GetFontString():SetTextColor(unpack(Where2GoTheme.colors.text))
    end
end

local function MatchesSourceFilter(ranked)
    return currentSourceFilter == "ALL" or ranked.kind == SOURCE_FILTER_KINDS[currentSourceFilter]
end

local function CycleSourceFilter()
    if currentSourceFilter == "ALL" then
        currentSourceFilter = "DUNGEONS"
    elseif currentSourceFilter == "DUNGEONS" then
        currentSourceFilter = "RAIDS"
    else
        currentSourceFilter = "ALL"
    end
    UpdateSourceFilterButton()
    Where2GoPanel.Refresh()
end

local function AnchorStandalone()
    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function RaiderIOTooltip()
    local tooltip = _G.RaiderIO_ProfileTooltip
    if tooltip and tooltip:IsShown() then
        return tooltip
    end
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function ScreenBounds(frame)
    local scale = frame:GetEffectiveScale()
    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    if not IsFiniteNumber(scale) or scale <= 0
        or not IsFiniteNumber(left) or not IsFiniteNumber(right)
        or not IsFiniteNumber(bottom) or not IsFiniteNumber(top) then
        return
    end
    return left * scale, right * scale, bottom * scale, top * scale
end

local function HasRoomToRight(frame)
    local _, tooltipRight = ScreenBounds(frame)
    local _, screenRight = ScreenBounds(UIParent)
    local scale = panelFrame:GetEffectiveScale()
    if not tooltipRight or not screenRight or not IsFiniteNumber(scale) or scale <= 0 then
        return
    end
    return tooltipRight + ((PANEL_WIDTH + PANEL_GAP) * scale) <= screenRight
end

local function RectanglesIntersect(firstLeft, firstRight, firstBottom, firstTop,
        secondLeft, secondRight, secondBottom, secondTop)
    return firstLeft < secondRight and firstRight > secondLeft
        and firstBottom < secondTop and firstTop > secondBottom
end

local function LeftPlacementIntersects(frame, other)
    local frameLeft, _, _, frameTop = ScreenBounds(frame)
    local secondLeft, secondRight, secondBottom, secondTop = ScreenBounds(other)
    local scale = panelFrame:GetEffectiveScale()
    local width, height = panelFrame:GetWidth(), panelFrame:GetHeight()
    if not frameLeft or not frameTop or not secondLeft
        or not IsFiniteNumber(scale) or scale <= 0
        or not IsFiniteNumber(width) or not IsFiniteNumber(height) then
        return false
    end
    local candidateRight = frameLeft - (PANEL_GAP * scale)
    local candidateLeft = candidateRight - (width * scale)
    local candidateTop = frameTop
    local candidateBottom = candidateTop - (height * scale)
    return RectanglesIntersect(candidateLeft, candidateRight, candidateBottom, candidateTop,
        secondLeft, secondRight, secondBottom, secondTop)
end

local function RightPlacementIntersects(frame, other)
    local _, frameRight, _, frameTop = ScreenBounds(frame)
    local secondLeft, secondRight, secondBottom, secondTop = ScreenBounds(other)
    local scale = panelFrame:GetEffectiveScale()
    local width, height = panelFrame:GetWidth(), panelFrame:GetHeight()
    if not frameRight or not frameTop or not secondLeft
        or not IsFiniteNumber(scale) or scale <= 0
        or not IsFiniteNumber(width) or not IsFiniteNumber(height) then
        return false
    end
    local candidateLeft = frameRight + (PANEL_GAP * scale)
    local candidateRight = candidateLeft + (width * scale)
    local candidateTop = frameTop
    local candidateBottom = candidateTop - (height * scale)
    return RectanglesIntersect(candidateLeft, candidateRight, candidateBottom, candidateTop,
        secondLeft, secondRight, secondBottom, secondTop)
end

local function LeftmostFrame(first, second)
    local firstLeft = ScreenBounds(first)
    local secondLeft = ScreenBounds(second)
    return firstLeft <= secondLeft and first or second
end

local function RightmostFrame(first, second)
    local _, firstRight = ScreenBounds(first)
    local _, secondRight = ScreenBounds(second)
    return firstRight >= secondRight and first or second
end

local function AnchorBeside(frame, rightSide)
    if not panelFrame or not frame then
        return
    end
    panelFrame:ClearAllPoints()
    if rightSide == nil then
        rightSide = HasRoomToRight(frame)
        if rightSide == nil then
            rightSide = true
        end
    end
    if rightSide then
        panelFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", PANEL_GAP, 0)
    else
        panelFrame:SetPoint("TOPRIGHT", frame, "TOPLEFT", -PANEL_GAP, 0)
    end
end

local function AnchorAutomatic()
    local tooltip = RaiderIOTooltip()
    if tooltip then
        local rightFrame = tooltip
        if PVEFrame and PVEFrame:IsShown() and RightPlacementIntersects(tooltip, PVEFrame) then
            rightFrame = RightmostFrame(tooltip, PVEFrame)
        end
        local roomToRight = HasRoomToRight(rightFrame)
        if roomToRight ~= false then
            AnchorBeside(rightFrame, true)
        else
            local leftFrame = tooltip
            if PVEFrame and PVEFrame:IsShown() and LeftPlacementIntersects(tooltip, PVEFrame) then
                leftFrame = LeftmostFrame(tooltip, PVEFrame)
            end
            AnchorBeside(leftFrame, false)
        end
    elseif PVEFrame and PVEFrame:IsShown() then
        AnchorBeside(PVEFrame)
    else
        AnchorStandalone()
    end
end

local function AnchorSavedPosition()
    local position = EnsureCharacterUI().panelPosition
    if not position then
        return false
    end
    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", position.x, position.y)
    return true
end

local function ApplyPlacement()
    if not AnchorSavedPosition() then
        AnchorAutomatic()
    end
end

local function SaveManualPosition()
    local left, _, _, top = ScreenBounds(panelFrame)
    local parentLeft, _, _, parentTop = ScreenBounds(UIParent)
    local scale = UIParent:GetEffectiveScale()
    if not left or not top or not parentLeft or not parentTop
        or not IsFiniteNumber(scale) or scale <= 0 then
        return false
    end
    EnsureCharacterUI().panelPosition = {
        x = (left - parentLeft) / scale,
        y = (top - parentTop) / scale,
    }
    return true
end

local function CreatePanel()
    local frame = CreateFrame("Frame", "Where2GoPanel", UIParent, "BackdropTemplate")
    frame:SetSize(PANEL_WIDTH, EXPANDED_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    Where2GoTheme.Box(frame, "bg")

    local titleBar = CreateFrame("Button", "Where2GoPanelTitleBar", frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", -40, 0)
    titleBar:SetHeight(TITLE_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:RegisterForClicks("RightButtonUp")
    titleBar:SetScript("OnDragStart", function()
        frame.dragging = true
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame.dragging = nil
        if SaveManualPosition() then
            AnchorSavedPosition()
        end
    end)
    titleBar:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            EnsureCharacterUI().panelPosition = nil
            ApplyPlacement()
        end
    end)
    frame.titleBar = titleBar

    local title = Where2GoTheme.Text(titleBar, "GameFontNormalLarge", L("PANEL_TITLE"))
    title:SetPoint("LEFT", titleBar, "LEFT", 12, 0)

    collapseButton = Where2GoTheme.Button(frame, "-", 24, 22, function()
        local ui = EnsureCharacterUI()
        ui.panelCollapsed = not ui.panelCollapsed
        UpdateCollapsedState()
    end)
    frame.collapseButton = collapseButton
    collapseButton:SetPoint("TOPRIGHT", -8, -8)

    bodyFrame = CreateFrame("Frame", "Where2GoPanelBody", frame)
    bodyFrame:SetPoint("TOPLEFT", 10, -TITLE_HEIGHT)
    bodyFrame:SetPoint("BOTTOMRIGHT", -10, 10)

    modeButtons.DROP = Where2GoTheme.Button(bodyFrame, L("MODE_DROP"), 82, 24, function()
        Where2GoPanel.SetMode("DROP")
    end)
    modeButtons.DROP:SetPoint("TOPLEFT", 0, 0)

    modeButtons.VOIDCORE = Where2GoTheme.Button(bodyFrame, L("MODE_VOIDCORE"), 92, 24, function()
        Where2GoPanel.SetMode("VOIDCORE")
    end)
    modeButtons.VOIDCORE:SetPoint("LEFT", modeButtons.DROP, "RIGHT", 6, 0)

    local manageButton = Where2GoTheme.Button(bodyFrame, L("MANAGE_BUTTON"), 130, 24, function()
        Where2GoBrowserPanel.Show(currentMode)
    end)
    frame.manageButton = manageButton
    manageButton:SetPoint("TOPRIGHT", 0, 0)

    specText = Where2GoTheme.Text(bodyFrame, "GameFontHighlightSmall", "")
    specText:SetPoint("TOPLEFT", 0, -32)
    specText:SetPoint("RIGHT", bodyFrame, "RIGHT", 0, 0)
    frame.specText = specText

    summaryText = Where2GoTheme.Text(bodyFrame, "GameFontDisableSmall", "")
    ownershipButton = Where2GoTheme.Button(bodyFrame, "", 190, 22, function()
        local nextMode = OwnershipMode() == "ITEM" and "SLOT" or "ITEM"
        Where2GoEquipment.SetOwnershipMode(nextMode)
        UpdateOwnershipButton()
        Where2GoPanel.Refresh()
    end)
    ownershipButton:SetPoint("TOPLEFT", 0, -52)
    ownershipButton:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L("PANEL_OWNERSHIP_HELP"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ownershipButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    frame.ownershipButton = ownershipButton
    UpdateOwnershipButton()

    sourceFilterButton = Where2GoTheme.Button(bodyFrame, "", 174, 22, CycleSourceFilter)
    sourceFilterButton:SetPoint("LEFT", ownershipButton, "RIGHT", 6, 0)
    frame.sourceFilterButton = sourceFilterButton
    UpdateSourceFilterButton()

    summaryText:SetPoint("TOPLEFT", 0, -78)
    summaryText:SetPoint("RIGHT", bodyFrame, "RIGHT", 0, 0)
    summaryText:SetTextColor(unpack(Where2GoTheme.colors.muted))

    scrollFrame = CreateFrame("ScrollFrame", "Where2GoPanelScrollFrame", bodyFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -CONTROLS_HEIGHT)
    scrollFrame:SetSize(PANEL_WIDTH - 42, VIEWPORT_HEIGHT)

    contentFrame = CreateFrame("Frame", "Where2GoPanelContent", scrollFrame)
    contentFrame:SetWidth(PANEL_WIDTH - 42)
    contentFrame:SetHeight(VIEWPORT_HEIGHT)
    scrollFrame:SetScrollChild(contentFrame)

    emptyText = Where2GoTheme.Text(contentFrame, "GameFontDisable", "")
    frame.emptyText = emptyText
    emptyText:SetTextColor(unpack(Where2GoTheme.colors.muted))
    emptyText:SetPoint("TOPLEFT", 10, -16)
    emptyText:SetPoint("RIGHT", contentFrame, "RIGHT", -10, 0)
    emptyText:SetWordWrap(true)

    panelFrame = frame
    frame:SetScript("OnHide", function()
        frame:StopMovingOrSizing()
        frame.dragging = nil
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        local elapsedTotal = (rawget(frame, "placementElapsed") or 0) + elapsed
        frame.placementElapsed = elapsedTotal
        if elapsedTotal < 0.1 or rawget(frame, "dragging") or EnsureCharacterUI().panelPosition then
            return
        end
        frame.placementElapsed = 0
        AnchorAutomatic()
    end)
    SetModeButtonStyles()
    UpdateCollapsedState()
    frame:Hide()
    return frame
end

local function EnsurePanel()
    return panelFrame or CreatePanel()
end

function Where2GoPanel.Refresh()
    EnsurePanel()

    local results, specName = GetRankedResults()
    local preferred = Where2GoPreferences.Get(currentMode)
    local preferredCount = CountPreferred(preferred)
    specText:SetText(results and specName and string.format(L("PANEL_SPEC_CONTEXT"), specName) or "")

    if not results then
        summaryText:SetText("")
        ShowEmpty(L("NO_SPEC_SELECTED"))
        return
    end

    local matches = {}
    local visiblePreferredCount = 0
    for _, ranked in ipairs(results) do
        if (ranked.targetCount or 0) > 0 and MatchesSourceFilter(ranked) then
            table.insert(matches, ranked)
            visiblePreferredCount = visiblePreferredCount + ranked.targetCount
        end
    end
    summaryText:SetText(string.format(L("PANEL_COUNT_SUMMARY"), visiblePreferredCount, #matches))

    if preferredCount == 0 then
        ShowEmpty(L("PANEL_NO_PREFERRED"))
        return
    elseif #matches == 0 then
        ShowEmpty(L("PANEL_NO_MATCHES"))
        return
    end

    emptyText:Hide()
    for index, ranked in ipairs(matches) do
        PopulateCard(EnsureCard(index), ranked)
    end
    for index = #matches + 1, #cardPool do
        cardPool[index].frame:Hide()
    end
    LayoutCards()
end

function Where2GoPanel.SetMode(mode)
    assert(mode == "DROP" or mode == "VOIDCORE", "invalid panel mode: " .. tostring(mode))
    if currentMode == mode then
        return
    end
    currentMode = mode
    SetModeButtonStyles()
    Where2GoPanel.Refresh()
end

function Where2Go_TogglePanel()
    local frame = EnsurePanel()
    if frame:IsShown() then
        frame:Hide()
        return
    end

    if PVEFrame and PVEFrame:IsShown() then
        ApplyPlacement()
    elseif not AnchorSavedPosition() then
        AnchorStandalone()
    end
    Where2GoPanel.Refresh()
    frame:Show()
end

local function BindPVEFrame()
    if not PVEFrame or hookedPVEFrame == PVEFrame then
        return
    end

    hookedPVEFrame = PVEFrame
    PVEFrame:HookScript("OnShow", function()
        local frame = EnsurePanel()
        ApplyPlacement()
        Where2GoPanel.Refresh()
        frame:Show()
    end)
    PVEFrame:HookScript("OnHide", function()
        if panelFrame then
            panelFrame:Hide()
        end
    end)

    if PVEFrame:IsShown() then
        local frame = EnsurePanel()
        ApplyPlacement()
        Where2GoPanel.Refresh()
        frame:Show()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        BindPVEFrame()
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        local unit = ...
        if unit and unit ~= "player" then
            return
        end
    end
    if panelFrame and panelFrame:IsShown() then
        Where2GoPanel.Refresh()
    end
end)

Where2GoPreferences.Subscribe("panel", function(mode)
    if mode == currentMode and panelFrame then
        Where2GoPanel.Refresh()
    end
end)

BindPVEFrame()
