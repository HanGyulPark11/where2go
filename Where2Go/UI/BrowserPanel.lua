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
local function CreateToggleButtonRow(parent, values, labelFn, onSelect)
    local buttons = {}
    local selectedValue = nil
    local x = 0
    for _, value in ipairs(values) do
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(90, 20)
        button:SetPoint("TOPLEFT", x, 0)
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
    return buttons
end

-- Task 3 Step 1 reassigns this to also refresh the visible rows.
RebuildFilteredResults = function()
    local unsorted = Where2GoItemBrowser.FilterItems(itemPool, filters, BuildContext())
    filteredResults = Where2GoItemBrowser.SortItems(unsorted, nil, BuildContext())
end

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
    end)
    RebuildFilteredResults()
end

local function CreateBrowserPanel()
    local frame = CreateFrame("Frame", "Where2GoBrowserPanel", UIParent, "BackdropTemplate")
    frame:SetSize(520, 480)
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
    bossRow:SetPoint("TOPLEFT", dungeonRow, "BOTTOMLEFT", 0, -26)
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
    end)

    -- Slot row
    local slotRow = CreateFrame("Frame", nil, frame)
    slotRow:SetPoint("TOPLEFT", bossRow, "BOTTOMLEFT", 0, -26)
    slotRow:SetSize(496, 20)
    slotButtons = CreateToggleButtonRow(slotRow, SLOT_ORDER, function(s) return s end, function(selected)
        filters.slot = selected
        RebuildFilteredResults()
    end)

    -- Stat checkbox row (multi-select)
    local statRow = CreateFrame("Frame", nil, frame)
    statRow:SetPoint("TOPLEFT", slotRow, "BOTTOMLEFT", 0, -26)
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

    frame.dungeonRow = dungeonRow
    frame.bossRow = bossRow
    frame.searchBox = searchBox
    frame:Hide()
    return frame
end
