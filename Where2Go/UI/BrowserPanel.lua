local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { sources = {}, slot = nil, stats = {}, specEligibleOnly = false, searchText = nil, specId = nil }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit
local specDropdown
local sourceDropdown

-- True once the player has explicitly picked a spec from the dropdown
-- (set inside SelectSpec below). Until then, filters.specId tracks the
-- player's actual current spec (re-derived on every panel show by
-- SyncDefaultSpec), so it follows respecs and picks up a spec chosen
-- after the panel was first created with none selected. Once the player
-- picks explicitly, that choice sticks for the rest of the session.
local userSelectedSpec = false

-- Forward declarations (same pattern UI/Panel.lua uses for `Layout`).
local RebuildFilteredResults
local RefreshStagedRows
local RefreshPreferredRows

local slotButtons = {}
local statCheckboxes = {}

local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }
local STAT_LABELS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Versatility" }

local ROW_HEIGHT = 34
local ICON_SIZE = 26
local RESULTS_WIDTH, STAGED_WIDTH, PREFERRED_WIDTH = 360, 200, 260
local VISIBLE_ROWS, STAGED_VISIBLE_ROWS, PREFERRED_VISIBLE_ROWS = 10, 10, 10

local function GetItemSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

local function GetItemEligible(itemId)
    if not filters.specId then
        return true
    end
    return Where2GoDirectDrop.IsEligibleForSpec(filters.specId)(itemId)
end

local function GetItemName(itemId)
    return Where2GoDirectDrop.GetItemNames({ itemId })[itemId]
end

-- Individual items don't carry a fixed ilvl in Sources.lua -- gear scales
-- with the player's current Mythic+/raid track, the same way
-- Core/DirectDrop.lua's BuildContentList already computes it per content.
local function GetEntryIlvl(entry)
    if entry.kind == "dungeon" then
        local ilvl = Where2GoRaidRanks.GetMythicPlusIlvl()
        return ilvl
    end
    local ilvl = Where2GoRaidRanks.GetRaidIlvl(entry.bossId)
    return ilvl
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
-- currently-active button is clicked again, deselecting it). Returns the
-- button table and the row's actual total height (including wrapping),
-- so callers can space the next row by the real height instead of a
-- guessed constant.
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
            Where2GoItemRow.Populate(row, entry.itemId, GetEntryIlvl(entry))
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
    RefreshStagedRows()
end

local stagedRows = {}

RefreshStagedRows = function()
    local items = {}
    for itemId in pairs(stagedSelection) do
        table.insert(items, itemId)
    end
    table.sort(items)
    for i = 1, STAGED_VISIBLE_ROWS do
        local row = stagedRows[i]
        local itemId = items[i]
        if itemId and row then
            row:Show()
            row.itemId = itemId
            Where2GoItemRow.Populate(row, itemId, nil)
        elseif row then
            row:Hide()
            row.itemId = nil
        end
    end
end

local preferredRows = {}

RefreshPreferredRows = function()
    local items = {}
    for itemId in pairs(Where2GoCharDB.preferredItems[currentMode]) do
        table.insert(items, itemId)
    end
    table.sort(items)
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = preferredRows[i]
        local itemId = items[i]
        if itemId and row then
            row:Show()
            row.itemId = itemId
            Where2GoItemRow.Populate(row, itemId, nil)
        elseif row then
            row:Hide()
            row.itemId = nil
        end
    end
end

-- Re-derives filters.specId (and the dropdown's displayed text) from
-- the player's actual current spec. Called once at panel creation, and
-- again on every panel show (Where2GoBrowserPanel.Toggle) as long as the
-- player hasn't explicitly picked a spec from the dropdown -- see
-- userSelectedSpec above.
local function SyncDefaultSpec()
    local specId, specName = Where2GoDirectDrop.GetCurrentSpecIdAndName()
    filters.specId = specId
    if specId and specDropdown then
        UIDropDownMenu_SetText(specDropdown, specName)
    end
end

local function UpdateSourceDropdownText()
    local count = 0
    for _ in pairs(filters.sources) do
        count = count + 1
    end
    if count == 0 then
        UIDropDownMenu_SetText(sourceDropdown, Where2GoLocale.L("SOURCE_DROPDOWN_ALL"))
    else
        UIDropDownMenu_SetText(sourceDropdown, string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count))
    end
end

local function CreateBrowserPanel()
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(860, 720)
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
    title:SetText(Where2GoLocale.L("BROWSER_TITLE"))

    -- Drop/Voidcore mode toggle
    local dropButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    dropButton:SetSize(80, 20)
    dropButton:SetPoint("TOPLEFT", 12, -36)
    dropButton:SetText(Where2GoLocale.L("MODE_DROP"))
    local voidcoreButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    voidcoreButton:SetSize(80, 20)
    voidcoreButton:SetPoint("LEFT", dropButton, "RIGHT", 6, 0)
    voidcoreButton:SetText(Where2GoLocale.L("MODE_VOIDCORE"))
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
        RefreshPreferredRows()
    end
    dropButton:SetScript("OnClick", function() SetMode("DROP") end)
    voidcoreButton:SetScript("OnClick", function() SetMode("VOIDCORE") end)

    -- Merged multi-select "Source" dropdown (replaces the old separate
    -- Dungeon/Boss toggle-button rows). Reuses UIDropDownMenuTemplate's
    -- native checkbox-item support (isNotRadio + keepShownOnClick) --
    -- the same dropdown mechanism this file already uses for the
    -- single-select spec dropdown below, just configured for multi-select.
    sourceDropdown = CreateFrame("Frame", "Where2GoBrowserSourceDropdown", frame, "UIDropDownMenuTemplate")
    sourceDropdown:SetPoint("LEFT", voidcoreButton, "RIGHT", 20, -2)
    UIDropDownMenu_SetWidth(sourceDropdown, 160)

    UIDropDownMenu_Initialize(sourceDropdown, function(_self, level)
        local function AddGroupHeader(text)
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.isTitle, info.notCheckable = text, true, true
            UIDropDownMenu_AddButton(info, level)
        end
        local function AddSourceOption(key, text)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = filters.sources[key] == true
            info.func = function()
                filters.sources[key] = (filters.sources[key] == true) and nil or true
                UpdateSourceDropdownText()
                RebuildFilteredResults()
            end
            UIDropDownMenu_AddButton(info, level)
        end

        AddGroupHeader(Where2GoLocale.L("SOURCE_GROUP_DUNGEONS"))
        for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
            AddSourceOption("dungeon:" .. dungeon.instanceId, dungeon.name)
        end
        for _, raid in ipairs(Where2GoSources.RAIDS) do
            AddGroupHeader(raid.name)
            for _, encounter in ipairs(raid.encounters) do
                AddSourceOption("boss:" .. encounter.bossId, encounter.name)
            end
        end
    end)
    UpdateSourceDropdownText()

    -- Slot row
    local slotRow = CreateFrame("Frame", nil, frame)
    slotRow:SetPoint("TOPLEFT", 12, -72)
    slotRow:SetSize(836, 20)
    local slotRowHeight
    slotButtons, slotRowHeight = CreateToggleButtonRow(slotRow, SLOT_ORDER, Where2GoLocale.SlotLabel, function(selected)
        filters.slot = selected
        RebuildFilteredResults()
    end, 820)

    -- Stat checkbox row (multi-select)
    local statRow = CreateFrame("Frame", nil, frame)
    statRow:SetPoint("TOPLEFT", slotRow, "BOTTOMLEFT", 0, -(slotRowHeight + 10))
    statRow:SetSize(836, 20)
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

    -- Spec-eligible-only checkbox, paired with the spec selector dropdown
    -- directly next to it (moved here from its old spot near the mode
    -- toggle, per the locked-in "these two controls work as a pair"
    -- decision).
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("TOPLEFT", statRow, "BOTTOMLEFT", 0, -26)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText(Where2GoLocale.L("ELIGIBLE_ONLY"))
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

    local function GetAvailableSpecs()
        local specs = {}
        for i = 1, GetNumSpecializations() do
            local specId, specName = GetSpecializationInfo(i)
            if specId then
                table.insert(specs, { specId = specId, specName = specName })
            end
        end
        return specs
    end

    specDropdown = CreateFrame("Frame", "Where2GoBrowserSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("LEFT", eligibleLabel, "RIGHT", 12, -2)
    UIDropDownMenu_SetWidth(specDropdown, 130)

    local function SelectSpec(specId, specName)
        userSelectedSpec = true
        filters.specId = specId
        UIDropDownMenu_SetText(specDropdown, specName)
        RebuildFilteredResults()
    end

    UIDropDownMenu_Initialize(specDropdown, function(_self, level)
        for _, spec in ipairs(GetAvailableSpecs()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spec.specName
            info.func = function() SelectSpec(spec.specId, spec.specName) end
            info.checked = (filters.specId == spec.specId)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    SyncDefaultSpec()

    -- Search box
    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", eligibleCheckbox, "BOTTOMLEFT", 4, -26)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        filters.searchText = self:GetText()
        RebuildFilteredResults()
    end)

    -- Three-column list area: Results | Staged | Preferred
    local resultsHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    resultsHeader:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -4, -16)
    resultsHeader:SetText(Where2GoLocale.L("RESULTS_HEADER"))

    local stagedHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stagedHeader:SetPoint("TOPLEFT", resultsHeader, "TOPLEFT", RESULTS_WIDTH + 8, 0)
    stagedHeader:SetText(Where2GoLocale.L("STAGED_HEADER"))

    local preferredHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    preferredHeader:SetPoint("TOPLEFT", stagedHeader, "TOPLEFT", STAGED_WIDTH + 8, 0)
    preferredHeader:SetText(Where2GoLocale.L("PREFERRED_HEADER"))

    local listHeight = VISIBLE_ROWS * ROW_HEIGHT

    local resultsFrame = CreateFrame("Frame", nil, frame)
    resultsFrame:SetPoint("TOPLEFT", resultsHeader, "BOTTOMLEFT", 4, -6)
    resultsFrame:SetSize(RESULTS_WIDTH, listHeight)
    resultsFrame:EnableMouseWheel(true)
    resultsFrame:SetScript("OnMouseWheel", function(self, delta)
        scrollOffset = scrollOffset - delta
        ClampScrollOffset()
        RefreshVisibleRows()
    end)

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Frame", nil, resultsFrame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)

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
                RefreshStagedRows()
            end
        end)

        Where2GoItemRow.CreateWidgets(row, ICON_SIZE, 24)
        row.name:SetWidth(RESULTS_WIDTH - 24 - ICON_SIZE - 8)
        row.summary:SetWidth(RESULTS_WIDTH - 24 - ICON_SIZE - 8)

        row.checkbox = checkbox
        resultRows[i] = row
    end

    local function CreateSideListRow(parent, width, onRemove)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_HEIGHT)

        local removeButton = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        removeButton:SetSize(16, 16)
        removeButton:SetPoint("RIGHT", 0, 0)
        removeButton:SetScript("OnClick", function()
            if row.itemId then
                onRemove(row.itemId)
            end
        end)

        Where2GoItemRow.CreateWidgets(row, ICON_SIZE, 0)
        row.name:SetWidth(width - ICON_SIZE - 16 - 8)
        row.summary:SetWidth(width - ICON_SIZE - 16 - 8)
        return row
    end

    local stagedFrame = CreateFrame("Frame", nil, frame)
    stagedFrame:SetPoint("TOPLEFT", stagedHeader, "BOTTOMLEFT", 0, -6)
    stagedFrame:SetSize(STAGED_WIDTH, listHeight)
    for i = 1, STAGED_VISIBLE_ROWS do
        local row = CreateSideListRow(stagedFrame, STAGED_WIDTH, function(itemId)
            stagedSelection[itemId] = nil
            RefreshStagedRows()
            RefreshVisibleRows()
        end)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", stagedFrame, "RIGHT", 0, 0)
        stagedRows[i] = row
    end

    local preferredFrame = CreateFrame("Frame", nil, frame)
    preferredFrame:SetPoint("TOPLEFT", preferredHeader, "BOTTOMLEFT", 0, -6)
    preferredFrame:SetSize(PREFERRED_WIDTH, listHeight)
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = CreateSideListRow(preferredFrame, PREFERRED_WIDTH, function(itemId)
            Where2GoCharDB.preferredItems[currentMode][itemId] = nil
            RefreshPreferredRows()
        end)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", preferredFrame, "RIGHT", 0, 0)
        preferredRows[i] = row
    end

    local addSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSelectedButton:SetSize(140, 22)
    addSelectedButton:SetPoint("TOPLEFT", stagedFrame, "BOTTOMLEFT", 0, -12)
    addSelectedButton:SetText(Where2GoLocale.L("ADD_SELECTED"))
    addSelectedButton:SetScript("OnClick", function()
        for itemId in pairs(stagedSelection) do
            Where2GoCharDB.preferredItems[currentMode][itemId] = true
        end
        stagedSelection = {}
        RebuildFilteredResults()
        RefreshPreferredRows()
    end)

    local clearSelectionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearSelectionButton:SetSize(140, 22)
    clearSelectionButton:SetPoint("TOPLEFT", addSelectedButton, "BOTTOMLEFT", 0, -6)
    clearSelectionButton:SetText(Where2GoLocale.L("CLEAR_SELECTION"))
    clearSelectionButton:SetScript("OnClick", function()
        stagedSelection = {}
        RefreshStagedRows()
        RefreshVisibleRows()
    end)

    local clearAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearAllButton:SetSize(140, 22)
    clearAllButton:SetPoint("TOPLEFT", preferredFrame, "BOTTOMLEFT", 0, -12)
    clearAllButton:SetText(Where2GoLocale.L("CLEAR_ALL"))
    clearAllButton:SetScript("OnClick", function()
        StaticPopup_Show("WHERE2GO_CLEAR_PREFERRED")
    end)

    frame.searchBox = searchBox
    SetMode("DROP")
    frame:Hide()
    return frame
end

StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"] = {
    text = Where2GoLocale.L("CLEAR_PREFERRED_CONFIRM"),
    button1 = Where2GoLocale.L("CLEAR_BUTTON"),
    button2 = Where2GoLocale.L("CANCEL_BUTTON"),
    OnAccept = function()
        Where2GoCharDB.preferredItems[currentMode] = {}
        RebuildFilteredResults()
        RefreshPreferredRows()
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
        if not userSelectedSpec then
            SyncDefaultSpec()
        end
        RebuildFilteredResults()
        RefreshPreferredRows()
        browserFrame:Show()
    end
end
