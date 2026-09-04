local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { sources = {}, slot = nil, stats = {}, specEligibleOnly = true, searchText = nil, specIds = {} }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> true, cleared on "clear selection" or after commit
local specDropdown
local sourceDropdown
local slotDropdown
local statDropdown

-- Forward declarations (same pattern UI/Panel.lua uses for `Layout`).
local RebuildFilteredResults
local RefreshStagedRows
local RefreshPreferredRows

local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }

local ROW_HEIGHT = 34
local ICON_SIZE = 26
local RESULTS_WIDTH, STAGED_WIDTH, PREFERRED_WIDTH = 360, 200, 260
local VISIBLE_ROWS, STAGED_VISIBLE_ROWS, PREFERRED_VISIBLE_ROWS = 10, 10, 10

local function GetItemSlot(itemId)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemId)
    return equipLoc and Where2GoConstants.EQUIPLOC_TO_SLOT[equipLoc]
end

-- The player's own class's specs (GetSpecialization's own scoping) --
-- used both by the multi-select spec dropdown and by GetItemEligible's
-- "nothing explicitly selected" fallback below.
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

-- An item is eligible if AT LEAST ONE relevant spec can use it (union,
-- not intersection). "Relevant" is the player's explicit spec selection
-- if any is checked, otherwise every spec of the player's own class --
-- so leaving the dropdown untouched shows anything any of your specs
-- could use, not just your currently active one.
local function GetItemEligible(itemId)
    local specIds = filters.specIds
    if specIds and next(specIds) ~= nil then
        for specId in pairs(specIds) do
            if Where2GoDirectDrop.IsEligibleForSpec(specId)(itemId) then
                return true
            end
        end
        return false
    end
    for _, spec in ipairs(GetAvailableSpecs()) do
        if Where2GoDirectDrop.IsEligibleForSpec(spec.specId)(itemId) then
            return true
        end
    end
    return false
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

local function GetEntrySourceLabel(entry)
    if entry.raidName then
        return entry.raidName .. " - " .. entry.bossName
    end
    return entry.contentName
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

local resultRows = {}
local scrollOffset = 0
local stagedScrollOffset = 0
local preferredScrollOffset = 0

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
            Where2GoItemRow.Populate(row, entry.itemId, GetEntryIlvl(entry), GetEntrySourceLabel(entry))
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
    local maxOffset = math.max(0, #items - STAGED_VISIBLE_ROWS)
    if stagedScrollOffset < 0 then
        stagedScrollOffset = 0
    elseif stagedScrollOffset > maxOffset then
        stagedScrollOffset = maxOffset
    end
    for i = 1, STAGED_VISIBLE_ROWS do
        local row = stagedRows[i]
        local itemId = items[stagedScrollOffset + i]
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
    local maxOffset = math.max(0, #items - PREFERRED_VISIBLE_ROWS)
    if preferredScrollOffset < 0 then
        preferredScrollOffset = 0
    elseif preferredScrollOffset > maxOffset then
        preferredScrollOffset = maxOffset
    end
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = preferredRows[i]
        local itemId = items[preferredScrollOffset + i]
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
                -- UIDropDownMenu's own click-time checkmark toggling is
                -- unreliable across repeated clicks on the same open
                -- menu (WoW-client-version-dependent) -- force a redraw
                -- from the real source of truth (filters.sources) every
                -- time instead of trusting the button's own internal
                -- toggle state.
                UIDropDownMenu_Refresh(sourceDropdown)
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

    -- Slot filter dropdown (single-select, replaces the old multi-row
    -- toggle-button grid).
    slotDropdown = CreateFrame("Frame", "Where2GoBrowserSlotDropdown", frame, "UIDropDownMenuTemplate")
    slotDropdown:SetPoint("TOPLEFT", -4, -72)
    UIDropDownMenu_SetWidth(slotDropdown, 130)

    local function UpdateSlotDropdownText()
        if filters.slot then
            UIDropDownMenu_SetText(slotDropdown, Where2GoLocale.SlotLabel(filters.slot))
        else
            UIDropDownMenu_SetText(slotDropdown, Where2GoLocale.L("SLOT_DROPDOWN_ALL"))
        end
    end

    UIDropDownMenu_Initialize(slotDropdown, function(_self, level)
        local allInfo = UIDropDownMenu_CreateInfo()
        allInfo.text = Where2GoLocale.L("SLOT_DROPDOWN_ALL")
        allInfo.checked = (filters.slot == nil)
        allInfo.func = function()
            filters.slot = nil
            UpdateSlotDropdownText()
            RebuildFilteredResults()
        end
        UIDropDownMenu_AddButton(allInfo, level)

        for _, slot in ipairs(SLOT_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Where2GoLocale.SlotLabel(slot)
            info.checked = (filters.slot == slot)
            info.func = function()
                filters.slot = slot
                UpdateSlotDropdownText()
                RebuildFilteredResults()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UpdateSlotDropdownText()

    -- Stat filter dropdown (multi-select, AND semantics preserved -- an
    -- item must have ALL checked stats, see Core/ItemBrowser.lua's
    -- matchesFilters, unchanged by this task).
    statDropdown = CreateFrame("Frame", "Where2GoBrowserStatDropdown", frame, "UIDropDownMenuTemplate")
    statDropdown:SetPoint("LEFT", slotDropdown, "RIGHT", 20, 0)
    UIDropDownMenu_SetWidth(statDropdown, 130)

    local function IsStatSelected(stat)
        for _, s in ipairs(filters.stats) do
            if s == stat then
                return true
            end
        end
        return false
    end

    local function UpdateStatDropdownText()
        local count = #filters.stats
        if count == 0 then
            UIDropDownMenu_SetText(statDropdown, Where2GoLocale.L("STAT_DROPDOWN_ALL"))
        else
            UIDropDownMenu_SetText(statDropdown, string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count))
        end
    end

    UIDropDownMenu_Initialize(statDropdown, function(_self, level)
        for _, stat in ipairs(STAT_ORDER) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Where2GoLocale.StatLabel(stat)
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = IsStatSelected(stat)
            info.func = function()
                if IsStatSelected(stat) then
                    for i, s in ipairs(filters.stats) do
                        if s == stat then
                            table.remove(filters.stats, i)
                            break
                        end
                    end
                else
                    table.insert(filters.stats, stat)
                end
                UpdateStatDropdownText()
                RebuildFilteredResults()
                UIDropDownMenu_Refresh(statDropdown)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UpdateStatDropdownText()

    -- Spec-eligible-only checkbox (defaults to checked), paired with the
    -- multi-select spec dropdown directly next to it (moved here from
    -- its old spot near the mode toggle, per the locked-in "these two
    -- controls work as a pair" decision).
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("TOPLEFT", slotDropdown, "BOTTOMLEFT", 16, -16)
    eligibleCheckbox:SetChecked(true)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText(Where2GoLocale.L("ELIGIBLE_ONLY"))
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

    -- Multi-select spec dropdown: nothing checked means "any spec of my
    -- class" (GetItemEligible's own fallback above), not "my current
    -- active spec only".
    specDropdown = CreateFrame("Frame", "Where2GoBrowserSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("LEFT", eligibleLabel, "RIGHT", 12, -2)
    UIDropDownMenu_SetWidth(specDropdown, 130)

    local function UpdateSpecDropdownText()
        local count = 0
        for _ in pairs(filters.specIds) do
            count = count + 1
        end
        if count == 0 then
            UIDropDownMenu_SetText(specDropdown, Where2GoLocale.L("SPEC_DROPDOWN_ALL"))
        else
            UIDropDownMenu_SetText(specDropdown, string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count))
        end
    end

    UIDropDownMenu_Initialize(specDropdown, function(_self, level)
        for _, spec in ipairs(GetAvailableSpecs()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = spec.specName
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.checked = filters.specIds[spec.specId] == true
            info.func = function()
                filters.specIds[spec.specId] = (filters.specIds[spec.specId] == true) and nil or true
                UpdateSpecDropdownText()
                RebuildFilteredResults()
                UIDropDownMenu_Refresh(specDropdown)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UpdateSpecDropdownText()

    -- Search box
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("BOTTOMLEFT", eligibleCheckbox, "TOPLEFT", 4, 30)
    searchLabel:SetText(Where2GoLocale.L("SEARCH_PLACEHOLDER"))

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
    stagedFrame:EnableMouseWheel(true)
    stagedFrame:SetScript("OnMouseWheel", function(self, delta)
        stagedScrollOffset = stagedScrollOffset - delta
        RefreshStagedRows()
    end)
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
    preferredFrame:EnableMouseWheel(true)
    preferredFrame:SetScript("OnMouseWheel", function(self, delta)
        preferredScrollOffset = preferredScrollOffset - delta
        RefreshPreferredRows()
    end)
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
        RebuildFilteredResults()
        RefreshPreferredRows()
        browserFrame:Show()
    end
end
