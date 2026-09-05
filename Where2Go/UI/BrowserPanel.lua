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

-- Shared by every multi-select dropdown's button-label text (Source,
-- Stat, Spec): count how many keys/entries are truthy in a filters
-- table, and format the "%d selected" label.
local function CountSelected(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

local function NSelectedText(count)
    return string.format(Where2GoLocale.L("SOURCE_DROPDOWN_N_SELECTED"), count)
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
    -- Dungeon/Boss toggle-button rows). Built on Blizzard's current
    -- Menu system (CreateCheckbox) rather than the deprecated
    -- UIDropDownMenuTemplate -- the legacy dropdown's click-time
    -- checkmark state proved unreliable for multi-select checkboxes in
    -- this client version (items couldn't be unchecked, and checking
    -- one item visually cleared others). CreateCheckbox's isSelected/
    -- setSelected callbacks read and write filters.sources directly,
    -- and forcing MenuResponse.Refresh after every click regenerates
    -- the whole menu from that live state, so displayed checkmarks can
    -- never drift from filters.sources. The button's own label is set
    -- directly on dropdown.Text (SetDefaultText/SetSelectionText looked
    -- documented but are nil on a plain CreateFrame-built DropdownButton
    -- in this client -- confirmed live, not just theorized) and updated
    -- manually on every state change, same as the pre-migration pattern.
    -- See docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md.
    sourceDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSourceDropdown", frame, "WowStyle1FilterDropdownTemplate")
    sourceDropdown:SetPoint("LEFT", voidcoreButton, "RIGHT", 20, -2)
    sourceDropdown:SetWidth(160)

    local function UpdateSourceDropdownText()
        local count = CountSelected(filters.sources)
        if count == 0 then
            sourceDropdown.Text:SetText(Where2GoLocale.L("SOURCE_DROPDOWN_ALL"))
        else
            sourceDropdown.Text:SetText(NSelectedText(count))
        end
    end

    sourceDropdown:SetupMenu(function(_owner, rootDescription)
        local function AddSourceOption(key, text)
            local checkbox = rootDescription:CreateCheckbox(text,
                function() return filters.sources[key] == true end,
                function()
                    filters.sources[key] = (filters.sources[key] == true) and nil or true
                    UpdateSourceDropdownText()
                    RebuildFilteredResults()
                end)
            checkbox:SetResponder(function() return MenuResponse.Refresh end)
        end

        rootDescription:CreateTitle(Where2GoLocale.L("SOURCE_GROUP_DUNGEONS"))
        for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
            AddSourceOption("dungeon:" .. dungeon.instanceId, dungeon.name)
        end
        for _, raid in ipairs(Where2GoSources.RAIDS) do
            rootDescription:CreateTitle(raid.name)
            for _, encounter in ipairs(raid.encounters) do
                AddSourceOption("boss:" .. encounter.bossId, encounter.name)
            end
        end
    end)
    UpdateSourceDropdownText()

    -- Slot filter dropdown (single-select "radio" group, replaces the
    -- old multi-row toggle-button grid). Same Menu-system migration
    -- rationale as the Source dropdown above.
    slotDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSlotDropdown", frame, "WowStyle1FilterDropdownTemplate")
    slotDropdown:SetPoint("TOPLEFT", -4, -72)
    slotDropdown:SetWidth(130)

    local function UpdateSlotDropdownText()
        slotDropdown.Text:SetText(filters.slot and Where2GoLocale.SlotLabel(filters.slot) or Where2GoLocale.L("SLOT_DROPDOWN_ALL"))
    end

    slotDropdown:SetupMenu(function(_owner, rootDescription)
        rootDescription:CreateRadio(Where2GoLocale.L("SLOT_DROPDOWN_ALL"),
            function() return filters.slot == nil end,
            function()
                filters.slot = nil
                UpdateSlotDropdownText()
                RebuildFilteredResults()
            end)
        for _, slot in ipairs(SLOT_ORDER) do
            rootDescription:CreateRadio(Where2GoLocale.SlotLabel(slot),
                function() return filters.slot == slot end,
                function()
                    filters.slot = slot
                    UpdateSlotDropdownText()
                    RebuildFilteredResults()
                end)
        end
    end)
    UpdateSlotDropdownText()

    -- Stat filter dropdown (multi-select, AND semantics preserved -- an
    -- item must have ALL checked stats, see Core/ItemBrowser.lua's
    -- matchesFilters, unchanged by this task).
    statDropdown = CreateFrame("DropdownButton", "Where2GoBrowserStatDropdown", frame, "WowStyle1FilterDropdownTemplate")
    statDropdown:SetPoint("LEFT", slotDropdown, "RIGHT", 20, 0)
    statDropdown:SetWidth(130)

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
            statDropdown.Text:SetText(Where2GoLocale.L("STAT_DROPDOWN_ALL"))
        else
            statDropdown.Text:SetText(NSelectedText(count))
        end
    end

    statDropdown:SetupMenu(function(_owner, rootDescription)
        for _, stat in ipairs(STAT_ORDER) do
            local checkbox = rootDescription:CreateCheckbox(Where2GoLocale.StatLabel(stat),
                function() return IsStatSelected(stat) end,
                function()
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
                end)
            checkbox:SetResponder(function() return MenuResponse.Refresh end)
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
    specDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSpecDropdown", frame, "WowStyle1FilterDropdownTemplate")
    specDropdown:SetPoint("LEFT", eligibleLabel, "RIGHT", 12, -2)
    specDropdown:SetWidth(130)

    local function UpdateSpecDropdownText()
        local count = CountSelected(filters.specIds)
        if count == 0 then
            specDropdown.Text:SetText(Where2GoLocale.L("SPEC_DROPDOWN_ALL"))
        else
            specDropdown.Text:SetText(NSelectedText(count))
        end
    end

    specDropdown:SetupMenu(function(_owner, rootDescription)
        for _, spec in ipairs(GetAvailableSpecs()) do
            local checkbox = rootDescription:CreateCheckbox(spec.specName,
                function() return filters.specIds[spec.specId] == true end,
                function()
                    filters.specIds[spec.specId] = (filters.specIds[spec.specId] == true) and nil or true
                    UpdateSpecDropdownText()
                    RebuildFilteredResults()
                end)
            checkbox:SetResponder(function() return MenuResponse.Refresh end)
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
