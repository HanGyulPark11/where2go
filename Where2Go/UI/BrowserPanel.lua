local browserFrame
local currentMode = "DROP"  -- "DROP" | "VOIDCORE"
local itemPool
local filters = { sources = {}, slots = {}, stats = {}, specEligibleOnly = true, searchText = nil, specIds = {} }
local filteredResults = {}
local stagedSelection = {}  -- itemId -> bonusId (real track bonus ID, for the tooltip -- see UI/ItemRow.lua), cleared on "clear selection" or after commit
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
-- Returns (ilvl, bonusId) -- bonusId lets ItemRow.Populate build a real
-- tracked tooltip link instead of showing the item's cached base ilvl.
local function GetEntryIlvl(entry)
    if entry.kind == "dungeon" then
        local ilvl, _trackKey, _rank, bonusId = Where2GoRaidRanks.GetMythicPlusIlvl()
        return ilvl, bonusId
    end
    local ilvl, _trackKey, _rank, bonusId = Where2GoRaidRanks.GetRaidIlvl(entry.bossId)
    return ilvl, bonusId
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
            local ilvl, bonusId = GetEntryIlvl(entry)
            row.bonusId = bonusId
            Where2GoItemRow.Populate(row, entry.itemId, ilvl, GetEntrySourceLabel(entry), bonusId)
            row.checkbox:SetChecked(stagedSelection[entry.itemId] ~= nil)
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
            Where2GoItemRow.Populate(row, itemId, nil, nil, stagedSelection[itemId])
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
            Where2GoItemRow.Populate(row, itemId, nil, nil, Where2GoCharDB.preferredItemSources[currentMode][itemId])
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

-- Colors ported directly from the Phase 9 design mockup's CSS (dark
-- stone/parchment + gold trim, WoW's own item-quality-adjacent palette).
-- See docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md's
-- mockup link. {r, g, b}, 0-1 floats for SetBackdropColor/SetTextColor.
local COLORS = {
    windowBg = { 0.078, 0.055, 0.031 },      -- #140e08
    windowBorder = { 0.478, 0.353, 0.173 },  -- #7a5a2c
    gold = { 0.941, 0.831, 0.533 },          -- #f0d488
    mutedTan = { 0.541, 0.459, 0.314 },      -- #8a7550
    toolbarBg = { 0.082, 0.059, 0.031 },     -- #150f08
    toolbarBorder = { 0.251, 0.192, 0.102 }, -- #40311a
    headerBg = { 0.110, 0.078, 0.035 },      -- #1c1409
    panelBg = { 0.063, 0.043, 0.024 },       -- #100b06
}

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
        edgeSize = 2,
    })
    frame:SetBackdropColor(unpack(COLORS.windowBg))
    frame:SetBackdropBorderColor(unpack(COLORS.windowBorder))

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(Where2GoLocale.L("BROWSER_TITLE"))
    title:SetTextColor(unpack(COLORS.gold))

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
            dropButton:GetFontString():SetTextColor(unpack(COLORS.gold))
            voidcoreButton:GetFontString():SetTextColor(1, 1, 1)
        else
            voidcoreButton:LockHighlight()
            dropButton:UnlockHighlight()
            voidcoreButton:GetFontString():SetTextColor(unpack(COLORS.gold))
            dropButton:GetFontString():SetTextColor(1, 1, 1)
        end
        stagedSelection = {}
        RebuildFilteredResults()
        RefreshPreferredRows()
    end
    dropButton:SetScript("OnClick", function() SetMode("DROP") end)
    voidcoreButton:SetScript("OnClick", function() SetMode("VOIDCORE") end)

    -- Filter toolbar: Source/Slot/Stat dropdowns grouped into one bordered
    -- bar (matches the mockup's single "toolbar" box) instead of floating
    -- independently at their own frame-relative anchors -- the layout
    -- complaint this task fixes ("필터 버튼들의 위치가 너무 중구난방").
    local toolbarFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    toolbarFrame:SetPoint("TOPLEFT", dropButton, "BOTTOMLEFT", 0, -8)
    toolbarFrame:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    toolbarFrame:SetHeight(34)
    toolbarFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    toolbarFrame:SetBackdropColor(unpack(COLORS.toolbarBg))
    toolbarFrame:SetBackdropBorderColor(unpack(COLORS.toolbarBorder))

    -- Merged multi-select "Source" dropdown (replaces the old separate
    -- Dungeon/Boss toggle-button rows). Built on Blizzard's current
    -- Menu system (CreateCheckbox) rather than the deprecated
    -- UIDropDownMenuTemplate -- the legacy dropdown's click-time
    -- checkmark state proved unreliable for multi-select checkboxes in
    -- this client version (items couldn't be unchecked, and checking
    -- one item visually cleared others). CreateCheckbox's isSelected/
    -- setSelected callbacks read and write filters.sources directly.
    -- IMPORTANT: do NOT call :SetResponder() again on the returned
    -- description -- MenuTemplates.CreateCheckbox already wires the
    -- setSelected function passed in as the ONLY responder via
    -- SetResponder(onSelect) and separately forces SetResponse(
    -- MenuResponse.Refresh); calling SetResponder a second time (an
    -- earlier version of this file did) REPLACES that real handler with
    -- whatever the second call passes, silently turning every click into
    -- a no-op -- confirmed live (this was the "선택이 안 돼" bug).
    -- The button's own label is set directly on dropdown.Text
    -- (SetDefaultText/SetSelectionText looked documented but are nil on
    -- a plain CreateFrame-built DropdownButton in this client -- also
    -- confirmed live) and updated manually on every state change, same
    -- as the pre-migration pattern.
    -- See docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md.
    sourceDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSourceDropdown", toolbarFrame, "WowStyle1FilterDropdownTemplate")
    sourceDropdown:SetPoint("LEFT", toolbarFrame, "LEFT", 8, 0)
    sourceDropdown:SetWidth(220)

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
            rootDescription:CreateCheckbox(text,
                function() return filters.sources[key] == true end,
                function()
                    if filters.sources[key] == true then
                        filters.sources[key] = nil
                    else
                        filters.sources[key] = true
                    end
                    UpdateSourceDropdownText()
                    RebuildFilteredResults()
                end)
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

    -- Slot filter dropdown (multi-select, OR semantics -- an item needs
    -- ANY checked slot, empty = no filter -- same shape as Source/Stat/
    -- Spec below, matching the user's explicit request that Slot behave
    -- like the other multi-select filters rather than a single-pick
    -- radio group).
    slotDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSlotDropdown", toolbarFrame, "WowStyle1FilterDropdownTemplate")
    slotDropdown:SetPoint("LEFT", sourceDropdown, "RIGHT", 10, 0)
    slotDropdown:SetWidth(130)

    local function UpdateSlotDropdownText()
        local count = CountSelected(filters.slots)
        if count == 0 then
            slotDropdown.Text:SetText(Where2GoLocale.L("SLOT_DROPDOWN_ALL"))
        else
            slotDropdown.Text:SetText(NSelectedText(count))
        end
    end

    slotDropdown:SetupMenu(function(_owner, rootDescription)
        for _, slot in ipairs(SLOT_ORDER) do
            rootDescription:CreateCheckbox(Where2GoLocale.SlotLabel(slot),
                function() return filters.slots[slot] == true end,
                function()
                    if filters.slots[slot] == true then
                        filters.slots[slot] = nil
                    else
                        filters.slots[slot] = true
                    end
                    UpdateSlotDropdownText()
                    RebuildFilteredResults()
                end)
        end
    end)
    UpdateSlotDropdownText()

    -- Stat filter dropdown (multi-select, AND semantics preserved -- an
    -- item must have ALL checked stats, see Core/ItemBrowser.lua's
    -- matchesFilters, unchanged by this task).
    statDropdown = CreateFrame("DropdownButton", "Where2GoBrowserStatDropdown", toolbarFrame, "WowStyle1FilterDropdownTemplate")
    statDropdown:SetPoint("LEFT", slotDropdown, "RIGHT", 10, 0)
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
            rootDescription:CreateCheckbox(Where2GoLocale.StatLabel(stat),
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
        end
    end)
    UpdateStatDropdownText()

    -- Second filter row: Spec dropdown + "eligible only" checkbox + search
    -- box, all in one row directly below the toolbar (mockup's "subrow") --
    -- the search box stretches to fill the remaining width instead of
    -- sitting in a narrow fixed-width box off to the side.
    --
    -- Multi-select spec dropdown: nothing checked means "any spec of my
    -- class" (GetItemEligible's own fallback above), not "my current
    -- active spec only".
    specDropdown = CreateFrame("DropdownButton", "Where2GoBrowserSpecDropdown", frame, "WowStyle1FilterDropdownTemplate")
    specDropdown:SetPoint("TOPLEFT", toolbarFrame, "BOTTOMLEFT", 0, -10)
    specDropdown:SetWidth(160)

    -- Spec-eligible-only checkbox (defaults to checked), paired with the
    -- spec dropdown directly next to it since the two controls work as a
    -- pair (which spec, and whether to actually filter by it).
    local eligibleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    eligibleCheckbox:SetSize(20, 20)
    eligibleCheckbox:SetPoint("LEFT", specDropdown, "RIGHT", 16, 0)
    eligibleCheckbox:SetChecked(true)
    local eligibleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eligibleLabel:SetPoint("LEFT", eligibleCheckbox, "RIGHT", 2, 0)
    eligibleLabel:SetText(Where2GoLocale.L("ELIGIBLE_ONLY"))
    eligibleCheckbox:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        RebuildFilteredResults()
    end)

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
            rootDescription:CreateCheckbox(spec.specName,
                function() return filters.specIds[spec.specId] == true end,
                function()
                    if filters.specIds[spec.specId] == true then
                        filters.specIds[spec.specId] = nil
                    else
                        filters.specIds[spec.specId] = true
                    end
                    UpdateSpecDropdownText()
                    RebuildFilteredResults()
                end)
        end
    end)
    UpdateSpecDropdownText()

    -- Search box: label + box share the row with Spec/Eligible, box
    -- stretches to the window's right edge instead of a narrow fixed box.
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", eligibleLabel, "RIGHT", 16, 0)
    searchLabel:SetText(Where2GoLocale.L("SEARCH_PLACEHOLDER"))

    local searchBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchBox:SetHeight(20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    searchBox:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        filters.searchText = self:GetText()
        RebuildFilteredResults()
    end)

    -- Three-column list area: Results | Staged | Preferred. Each column
    -- gets its own bordered/backgrounded header bar and list box (mockup's
    -- boxed columns) instead of a bare FontString + unbordered frame.
    local function CreateColumnHeader(anchorTo, anchorPoint, xOfs, yOfs, width, text)
        local headerFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        headerFrame:SetPoint("TOPLEFT", anchorTo, anchorPoint, xOfs, yOfs)
        headerFrame:SetSize(width, 20)
        headerFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        headerFrame:SetBackdropColor(unpack(COLORS.headerBg))
        local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        headerText:SetPoint("LEFT", 6, 0)
        headerText:SetTextColor(unpack(COLORS.mutedTan))
        headerText:SetText(text)
        return headerFrame
    end

    local resultsHeader = CreateColumnHeader(specDropdown, "BOTTOMLEFT", 0, -14, RESULTS_WIDTH, Where2GoLocale.L("RESULTS_HEADER"))
    local stagedHeader = CreateColumnHeader(resultsHeader, "TOPLEFT", RESULTS_WIDTH + 8, 0, STAGED_WIDTH, Where2GoLocale.L("STAGED_HEADER"))
    local preferredHeader = CreateColumnHeader(stagedHeader, "TOPLEFT", STAGED_WIDTH + 8, 0, PREFERRED_WIDTH, Where2GoLocale.L("PREFERRED_HEADER"))

    local listHeight = VISIBLE_ROWS * ROW_HEIGHT

    local resultsFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    resultsFrame:SetPoint("TOPLEFT", resultsHeader, "BOTTOMLEFT", 0, -4)
    resultsFrame:SetSize(RESULTS_WIDTH, listHeight)
    resultsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    resultsFrame:SetBackdropColor(unpack(COLORS.panelBg))
    resultsFrame:SetBackdropBorderColor(unpack(COLORS.toolbarBorder))
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
                    stagedSelection[r.entry.itemId] = r.bonusId
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

    local stagedFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    stagedFrame:SetPoint("TOPLEFT", stagedHeader, "BOTTOMLEFT", 0, -4)
    stagedFrame:SetSize(STAGED_WIDTH, listHeight)
    stagedFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    stagedFrame:SetBackdropColor(unpack(COLORS.panelBg))
    stagedFrame:SetBackdropBorderColor(unpack(COLORS.toolbarBorder))
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

    local preferredFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    preferredFrame:SetPoint("TOPLEFT", preferredHeader, "BOTTOMLEFT", 0, -4)
    preferredFrame:SetSize(PREFERRED_WIDTH, listHeight)
    preferredFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    preferredFrame:SetBackdropColor(unpack(COLORS.panelBg))
    preferredFrame:SetBackdropBorderColor(unpack(COLORS.toolbarBorder))
    preferredFrame:EnableMouseWheel(true)
    preferredFrame:SetScript("OnMouseWheel", function(self, delta)
        preferredScrollOffset = preferredScrollOffset - delta
        RefreshPreferredRows()
    end)
    for i = 1, PREFERRED_VISIBLE_ROWS do
        local row = CreateSideListRow(preferredFrame, PREFERRED_WIDTH, function(itemId)
            Where2GoCharDB.preferredItems[currentMode][itemId] = nil
            Where2GoCharDB.preferredItemSources[currentMode][itemId] = nil
            RefreshPreferredRows()
        end)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", preferredFrame, "RIGHT", 0, 0)
        preferredRows[i] = row
    end

    local selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllButton:SetSize(140, 22)
    selectAllButton:SetPoint("TOPLEFT", resultsFrame, "BOTTOMLEFT", 0, -12)
    selectAllButton:SetText(Where2GoLocale.L("SELECT_ALL_FILTERED"))
    selectAllButton:SetScript("OnClick", function()
        for _, entry in ipairs(filteredResults) do
            local _, bonusId = GetEntryIlvl(entry)
            stagedSelection[entry.itemId] = bonusId
        end
        RefreshStagedRows()
        RefreshVisibleRows()
    end)

    local addSelectedButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addSelectedButton:SetSize(140, 22)
    addSelectedButton:SetPoint("TOPLEFT", stagedFrame, "BOTTOMLEFT", 0, -12)
    addSelectedButton:SetText(Where2GoLocale.L("ADD_SELECTED"))
    addSelectedButton:SetScript("OnClick", function()
        for itemId, bonusId in pairs(stagedSelection) do
            Where2GoCharDB.preferredItems[currentMode][itemId] = true
            Where2GoCharDB.preferredItemSources[currentMode][itemId] = bonusId
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
        Where2GoCharDB.preferredItemSources[currentMode] = {}
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
