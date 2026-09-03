local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { dungeonName = nil, bossName = nil, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit

-- Forward declaration (same pattern UI/Panel.lua uses for `Layout`):
-- Task 2 Step 3 assigns a filter-only stub; Task 3 Step 1 replaces that
-- assignment with the real version that also refreshes the visible rows.
-- Every caller below (RebuildBossButtons, the mode toggle, every filter
-- control's OnClick) calls it by this same upvalue, so whichever body is
-- currently assigned is the one that runs -- no redefinition ambiguity.
local RebuildFilteredResults

local dungeonButtons = {}
local bossButtons = {}
local slotButtons = {}
local statCheckboxes = {}

local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }
local STAT_LABELS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Versatility" }

local function GetItemSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

local function GetItemEligible(itemId)
    local specId = select(1, Where2GoDirectDrop.GetCurrentSpecIdAndName())
    if not specId then
        return true
    end
    return Where2GoDirectDrop.IsEligibleForSpec(specId)(itemId)
end

local function GetItemName(itemId)
    return Where2GoDirectDrop.GetItemNames({ itemId })[itemId]
end

local function BuildContext()
    return {
        getSlot = GetItemSlot,
        isEligible = GetItemEligible,
        getItemName = GetItemName,
    }
end

local function IsPreferred(itemId)
    return Where2GoCharDB.preferredItems[currentMode][itemId] == true
end

-- A row of mutually-exclusive toggle buttons (only one active at a time,
-- or none). `onSelect` is called with the selected value (or nil if the
-- currently-active button is clicked again, deselecting it).
local function CreateToggleButtonRow(parent, values, labelFn, onSelect, maxWidth)
    local buttons = {}
    local selectedValue = nil
    local x, y = 0, 0
    for _, value in ipairs(values) do
        if maxWidth and x + 90 > maxWidth then
            x = 0
            y = y - 24
        end
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(90, 20)
        button:SetPoint("TOPLEFT", x, y)
        button:SetText(labelFn(value))
        button:SetScript("OnClick", function()
            if selectedValue == value then
                selectedValue = nil
            else
                selectedValue = value
            end
            for v, btn in pairs(buttons) do
                if v == selectedValue then
                    btn:LockHighlight()
                else
                    btn:UnlockHighlight()
                end
            end
            onSelect(selectedValue)
        end)
        buttons[value] = button
        x = x + 94
    end
    local totalHeight = (-y) + 20
    return buttons, totalHeight
end

-- KNOWN LIMITATION: creates new button frames on every call rather than
-- pooling/reusing them (unlike the result row list, which does pool).
-- WoW frames are never destroyed, so this grows slowly with repeated
-- dungeon/raid clicks over a long session. Deliberately left as-is:
-- fixing it safely requires reworking this row's per-click
-- closure/highlight logic, and the real-world growth rate is slow
-- (~9 frames per click) relative to that risk. Revisit if it's ever
-- actually observed to matter.
local function RebuildBossButtons(parent, dungeonOrRaid)
    for _, btn in pairs(bossButtons) do
        btn:Hide()
    end
    bossButtons = {}
    if not dungeonOrRaid then
        RebuildFilteredResults()
        return
    end
    local bossNames = {}
    for _, encounter in ipairs(dungeonOrRaid.encounters) do
        table.insert(bossNames, encounter.name)
    end
    bossButtons = CreateToggleButtonRow(parent, bossNames, function(v) return v end, function(selected)
        filters.bossName = selected
        RebuildFilteredResults()
    end, 660)
    RebuildFilteredResults()
end

local ROW_HEIGHT = 20
local VISIBLE_ROWS = 12
local resultRows = {}
local scrollOffset = 0

local function ClampScrollOffset()
    local maxOffset = math.max(0, #filteredResults - VISIBLE_ROWS)
    if scrollOffset < 0 then
        scrollOffset = 0
    elseif scrollOffset > maxOffset then
        scrollOffset = maxOffset
    end
end

local function RefreshVisibleRows()
    for i = 1, VISIBLE_ROWS do
        local row = resultRows[i]
        local entry = filteredResults[scrollOffset + i]
        if entry and row then
            row:Show()
            row.entry = entry
            local prefix = entry.raidName and (entry.raidName .. " - ") or ""
            local name = GetItemName(entry.itemId) or ("Item #" .. entry.itemId)
            local preferredMark = IsPreferred(entry.itemId) and "|cff00ff00[preferred]|r " or ""
            row.text:SetText(preferredMark .. prefix .. entry.contentName .. " / " .. entry.bossName .. ": " .. name)
            row.checkbox:SetChecked(stagedSelection[entry.itemId] == true)
        elseif row then
            row:Hide()
            row.entry = nil
        end
    end
end

RebuildFilteredResults = function()
    if not itemPool then
        return
    end
    local unsorted = Where2GoItemBrowser.FilterItems(itemPool, filters, BuildContext())
    filteredResults = Where2GoItemBrowser.SortItems(unsorted, nil, BuildContext())
    ClampScrollOffset()
    RefreshVisibleRows()
end

local function CreateBrowserPanel()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(700, 720)
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
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Where2Go - Item Browser")

    -- Drop/Voidcore mode toggle
    local dropButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dropButton:SetSize(80, 20)
    dropButton:SetPoint("TOPLEFT", 12, -36)
    dropButton:SetText("Drop")
    local voidcoreButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    voidcoreButton:SetSize(80, 20)
    voidcoreButton:SetPoint("LEFT", dropButton, "RIGHT", 6, 0)
    voidcoreButton:SetText("Voidcore")
    local function SetMode(mode)
        if mode == currentMode then
            return
        end
        currentMode = mode
        if mode == "DROP" then
            dropButton:LockHighlight()
            voidcoreButton:UnlockHighlight()
        else
            voidcoreButton:LockHighlight()
            dropButton:UnlockHighlight()
        end
        stagedSelection = {}
        RebuildFilteredResults()
    end
    dropButton:SetScript("OnClick", function() SetMode("DROP") end)
    voidcoreButton:SetScript("OnClick", function() SetMode("VOIDCORE") end)

    -- Dungeon/raid row. `bossRow` is declared before `dungeonButtons` is
    -- built, since dungeonButtons' OnClick closures capture it by
    -- reference (a Lua local is only visible to code compiled after its
    -- declaration -- declaring bossRow later would make those closures
    -- silently resolve it as an undeclared global instead).
    local dungeonRow = CreateFrame("Frame", nil, frame)
    dungeonRow:SetPoint("TOPLEFT", 12, -64)
    dungeonRow:SetSize(496, 20)

    -- Boss row (populated once a dungeon/raid is selected)
    local bossRow = CreateFrame("Frame", nil, frame)
    bossRow:SetPoint("TOPLEFT", dungeonRow, "BOTTOMLEFT", 0, -56)
    bossRow:SetSize(496, 20)

    local dungeonAndRaidEntries = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(dungeonAndRaidEntries, dungeon)
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        table.insert(dungeonAndRaidEntries, raid)
    end
    dungeonButtons = CreateToggleButtonRow(dungeonRow, dungeonAndRaidEntries, function(d) return d.name end, function(selected)
        filters.dungeonName = selected and selected.name or nil
        filters.bossName = nil
        RebuildBossButtons(bossRow, selected)
    end, 660)

    -- Slot row
    local slotRow = CreateFrame("Frame", nil, frame)
    slotRow:SetPoint("TOPLEFT", bossRow, "BOTTOMLEFT", 0, -56)
    slotRow:SetSize(496, 20)
    slotButtons = CreateToggleButtonRow(slotRow, SLOT_ORDER, function(s) return s end, function(selected)
        filters.slot = selected
        RebuildFilteredResults()
    end, 660)

    -- Stat checkbox row (multi-select)
    local statRow = CreateFrame("Frame", nil, frame)
    statRow:SetPoint("TOPLEFT", slotRow, "BOTTOMLEFT", 0, -56)
    statRow:SetSize(496, 20)
    local statX = 0
    for _, stat in ipairs(STAT_ORDER) do
        local checkbox = CreateFrame("CheckButton", nil, statRow, "UICheckButtonTemplate")
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("TOPLEFT", statX, 0)
        local label = statRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
        label:SetText(STAT_LABELS[stat])
        checkbox:SetScript("OnClick", function(self)
            filters.stats = filters.stats or {}
            if self:GetChecked() then
                table.insert(filters.stats, stat)
            else
                for i, s in ipairs(filters.stats) do
                    if s == stat then
                        table.remove(filters.stats, i)
                        break
                    end
                end
            end
            RebuildFilteredResults()
        end)
        statCheckboxes[stat] = checkbox
        statX = statX + 90
    end

    -- Spec-eligible-only checkbox
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("TOPLEFT", statRow, "BOTTOMLEFT", 0, -26)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText("Current spec eligible only")
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

    -- Search box
    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", eligibleCheckbox, "BOTTOMLEFT", 4, -26)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        filters.searchText = self:GetText()
        RebuildFilteredResults()
    end)

    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -12)
    listFrame:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    listFrame:SetHeight(VISIBLE_ROWS * ROW_HEIGHT)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollOffset = scrollOffset - delta
        ClampScrollOffset()
        RefreshVisibleRows()
    end)

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, listFrame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", listFrame, "RIGHT", 0, 0)

        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("LEFT", 0, 0)
        checkbox:SetScript("OnClick", function(self)
            local r = self:GetParent()
            if r.entry then
                if self:GetChecked() then
                    stagedSelection[r.entry.itemId] = true
                else
                    stagedSelection[r.entry.itemId] = nil
                end
            end
        end)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)

        row.checkbox = checkbox
        row.text = text
        resultRows[i] = row
    end

    local addSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSelectedButton:SetSize(140, 22)
    addSelectedButton:SetPoint("TOPLEFT", listFrame, "BOTTOMLEFT", 4, -12)
    addSelectedButton:SetText("Add selected")
    addSelectedButton:SetScript("OnClick", function()
        for itemId in pairs(stagedSelection) do
            Where2GoCharDB.preferredItems[currentMode][itemId] = true
        end
        stagedSelection = {}
        RebuildFilteredResults()
    end)

    local clearSelectionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearSelectionButton:SetSize(140, 22)
    clearSelectionButton:SetPoint("LEFT", addSelectedButton, "RIGHT", 8, 0)
    clearSelectionButton:SetText("Clear selection")
    clearSelectionButton:SetScript("OnClick", function()
        stagedSelection = {}
        RefreshVisibleRows()
    end)

    local clearPreferredButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearPreferredButton:SetSize(160, 22)
    clearPreferredButton:SetPoint("LEFT", clearSelectionButton, "RIGHT", 8, 0)
    clearPreferredButton:SetText("Clear preferred list")
    clearPreferredButton:SetScript("OnClick", function()
        StaticPopup_Show("WHERE2GO_CLEAR_PREFERRED")
    end)

    frame.dungeonRow = dungeonRow
    frame.bossRow = bossRow
    frame.searchBox = searchBox
    SetMode("DROP")
    frame:Hide()
    return frame
end

StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"] = {
    text = "Remove every preferred item from the current list?",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        Where2GoCharDB.preferredItems[currentMode] = {}
        RebuildFilteredResults()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

Where2GoBrowserPanel = {}

function Where2GoBrowserPanel.Toggle()
    if not browserFrame then
        browserFrame = CreateBrowserPanel()
        itemPool = Where2GoItemBrowser.BuildItemPool()
        for _, entry in ipairs(itemPool) do
            C_Item.RequestLoadItemDataByID(entry.itemId)
        end
        local itemLoadWatcher = CreateFrame("Frame")
        itemLoadWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        itemLoadWatcher:SetScript("OnEvent", function()
            if browserFrame and browserFrame:IsShown() then
                RebuildFilteredResults()
            end
        end)
        RebuildFilteredResults()
    end
    if browserFrame:IsShown() then
        browserFrame:Hide()
    else
        RebuildFilteredResults()
        browserFrame:Show()
    end
end
