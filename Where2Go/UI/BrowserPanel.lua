-- Independent item management. Transient selection never changes preferences
-- until committed; preference transactions refresh both windows immediately.
Where2GoBrowserPanel = {}
local T, L = Where2GoTheme, Where2GoLocale.L
local frame, pool, selection
local currentMode = "DROP"
local filters = { sources = {}, slots = {}, stats = {}, specIds = {}, specEligibleOnly = true }
local results, preferredIds, resultRows, preferredRows = {}, {}, {}, {}
local resultOffset, preferredOffset = 0, 0
local ROW_HEIGHT, ROWS, RESULT_WIDTH, PREFERRED_WIDTH = 36, 11, 568, 344
local dropdownUpdates, pendingItems = {}, {}
local refreshing = false
local Refresh, UpdateActions, RefreshRows
local SLOT_ORDER = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND" }
local STAT_ORDER = { "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY" }

local function AvailableSpecs()
    local specs = {}
    for i = 1, GetNumSpecializations() do
        local id, name = GetSpecializationInfo(i)
        if id then table.insert(specs, { id = id, name = name }) end
    end
    return specs
end

local function ResetFiltersToDefaults()
    filters = { sources = {}, slots = {}, stats = {}, specIds = {}, specEligibleOnly = true }
    local currentSpec = GetSpecialization and GetSpecialization()
    if currentSpec then
        local specId = GetSpecializationInfo(currentSpec)
        if specId then filters.specIds[specId] = true end
    end
end

local function ItemName(id) return C_Item.GetItemInfo(id) or ("Item #" .. id) end

local function ContentName(name)
    return Where2GoLocale.ContentName(name)
end

local function ItemEligible(id)
    local explicit = next(filters.specIds) ~= nil
    for _, spec in ipairs(AvailableSpecs()) do
        if (not explicit or filters.specIds[spec.id]) and Where2GoDirectDrop.IsEligibleForSpec(spec.id)(id) then return true end
    end
    return false
end

local function EntryLevel(entry)
    if entry.kind == "dungeon" then
        if currentMode == "VOIDCORE" then return Where2GoRaidRanks.GetVoidcoreDungeonIlvl() end
        return Where2GoRaidRanks.GetMythicPlusIlvl()
    end
    if currentMode == "VOIDCORE" then return Where2GoRaidRanks.GetVoidcoreRaidIlvl(entry.bossId) end
    return Where2GoRaidRanks.GetRaidIlvl(entry.bossId)
end

local function Clamp(offset, count) return math.max(0, math.min(offset, math.max(0, count - ROWS))) end

local function Feedback(key, count)
    frame.feedback:SetText(count and string.format(L(key), count) or L(key))
    UpdateActions()
end

local function NormalizePreferredSources(preferred, sources)
    if currentMode ~= "VOIDCORE" or not pool then return end
    local _, _, _, directDungeonBonus = Where2GoRaidRanks.GetMythicPlusIlvl()
    for _, entry in ipairs(pool) do
        if entry.kind == "dungeon" and preferred[entry.itemId] == true
                and (sources[entry.itemId] == nil or sources[entry.itemId] == directDungeonBonus) then
            local _, _, _, voidcoreBonus = Where2GoRaidRanks.GetVoidcoreDungeonIlvl()
            if type(voidcoreBonus) == "number" then
                sources[entry.itemId] = voidcoreBonus
            end
        end
    end
end

local function Add(items)
    local count = Where2GoPreferences.Add(currentMode, items)
    if count > 0 then Feedback("ADDED_FEEDBACK", count) end
end

local function Remove(id)
    local count = Where2GoPreferences.Remove(currentMode, id)
    if count > 0 then Feedback("REMOVED_FEEDBACK", count) end
end

UpdateActions = function()
    local selected, available = selection:GetCounts()
    frame.selectAll:SetEnabled(available > 0)
    frame.selectAll:SetChecked(available > 0 and selected == available)
    frame.selectAll.partial:SetShown(selected > 0 and selected < available)
    frame.selectionCount:SetText(string.format(L("SELECTED_COUNT"), selected, available))
    frame.addSelected:SetText(string.format(L("ADD_COUNT"), selected))
    frame.addSelected:SetEnabled(selected > 0)
    frame.clearSelection:SetEnabled(selected > 0)
    frame.clearPreferred:SetEnabled(#preferredIds > 0)
    frame.undo:SetEnabled(Where2GoPreferences.HasUndo(currentMode))
end

local function SyncScrollbar(slider, count, offset)
    slider:SetMinMaxValues(0, math.max(0, count - ROWS))
    slider:SetValue(offset)
    slider:SetShown(count > ROWS)
end

RefreshRows = function()
    local preferred, sources = Where2GoPreferences.Get(currentMode)
    local selected = selection:GetSelected()
    for i, row in ipairs(resultRows) do
        local entry = results[resultOffset + i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local source = entry.raidName and (ContentName(entry.raidName) .. " - " .. ContentName(entry.bossName))
                or ContentName(entry.contentName)
            Where2GoItemRow.Populate(row, entry.itemId, entry.ilvl, source, entry.bonusId,
                entry.trackKey, entry.trackRank)
            local saved = preferred[entry.itemId] == true
            row.checkbox:SetEnabled(not saved)
            row.checkbox:SetChecked(selected[entry.itemId] ~= nil)
            row.selectedBg:SetShown(selected[entry.itemId] ~= nil)
            row.add:SetText(saved and L("SAVED") or L("ADD_ONE"))
            row.add:SetEnabled(not saved)
        end
    end
    for i, row in ipairs(preferredRows) do
        local id = preferredIds[preferredOffset + i]
        row.itemId = id
        row:SetShown(id ~= nil)
        if id then
            local ilvl, trackKey, trackRank = Where2GoItemRow.GetLevelFromBonus(sources[id])
            Where2GoItemRow.Populate(row, id, ilvl, nil, sources[id], trackKey, trackRank)
        end
    end
    SyncScrollbar(frame.resultScroll, #results, resultOffset)
    SyncScrollbar(frame.preferredScroll, #preferredIds, preferredOffset)
end

Refresh = function(resetSelection)
    if not frame or not pool or refreshing then return end
    refreshing = true
    local preferred, sources = Where2GoPreferences.Get(currentMode)
    NormalizePreferredSources(preferred, sources)
    local context = {
        getSlot = function(id)
            local _, _, _, loc = C_Item.GetItemInfoInstant(id)
            return Where2GoConstants.EQUIPLOC_TO_SLOT[loc]
        end,
        getItemName = ItemName, isEligible = ItemEligible,
    }
    local filtered = Where2GoItemBrowser.FilterItems(pool, filters, context)
    filtered = Where2GoItemBrowser.SortItems(filtered, "NAME", context)
    results = {}
    local seen = {}
    for _, entry in ipairs(filtered) do
        if not seen[entry.itemId] then
            seen[entry.itemId] = true
            local ilvl, trackKey, trackRank, bonusId = EntryLevel(entry)
            entry.ilvl, entry.trackKey, entry.trackRank, entry.bonusId = ilvl, trackKey, trackRank, bonusId
            table.insert(results, entry)
        end
    end
    selection:SetResults(results, preferred, resetSelection == true)
    preferredIds = {}
    for id, saved in pairs(preferred) do if saved then table.insert(preferredIds, id) end end
    table.sort(preferredIds, function(a, b)
        local an, bn = ItemName(a), ItemName(b)
        if an == bn then return a < b end
        return an < bn
    end)
    resultOffset = Clamp(resetSelection and 0 or resultOffset, #results)
    preferredOffset = Clamp(preferredOffset, #preferredIds)
    frame.resultTitle:SetText(string.format(L("RESULTS_COUNT"), #results))
    frame.preferredTitle:SetText(string.format(L("PREFERRED_COUNT"), #preferredIds))
    frame.resultEmpty:SetText(L(next(pendingItems) and "LOADING_ITEMS" or "EMPTY_RESULTS"))
    frame.resultEmpty:SetShown(#results == 0)
    frame.preferredEmpty:SetShown(#preferredIds == 0)
    RefreshRows()
    UpdateActions()
    refreshing = false
end

local function FiltersChanged()
    frame.feedback:SetText("")
    Refresh(true)
end

local function SetMode(mode)
    mode = mode == "VOIDCORE" and "VOIDCORE" or "DROP"
    local changed = currentMode ~= mode
    currentMode = mode
    for key, button in pairs(frame.modeButtons) do
        T.Box(button, key == mode and "selected" or "surface")
        button:GetFontString():SetTextColor(unpack(T.colors[key == mode and "accent" or "text"]))
    end
    if changed then
        frame.feedback:SetText("")
        preferredOffset = 0
        Refresh(true)
    end
end

local function MakeScrollbar(parent, height, onChange)
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetSize(10, height)
    slider:SetPoint("TOPRIGHT", -5, -6)
    T.Box(slider, "surface")
    slider:SetOrientation("VERTICAL")
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetMinMaxValues(0, 0)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    slider:GetThumbTexture():SetSize(8, 28)
    slider:GetThumbTexture():SetVertexColor(unpack(T.colors.muted))
    slider:SetScript("OnValueChanged", function(_, value)
        if not refreshing then onChange(math.floor(value + 0.5)) end
    end)
    return slider
end

local function EmptyLabel(parent, width, text)
    local label = T.Text(parent, "GameFontHighlight", text)
    label:SetPoint("TOPLEFT", 22, -36)
    label:SetWidth(width - 44)
    label:SetJustifyH("CENTER")
    label:SetTextColor(unpack(T.colors.muted))
    return label
end

local function TextFits(label, text)
    label:SetText(text)
    if label.GetStringWidth and label:GetStringWidth() > label:GetWidth() then
        return false
    end
    return true
end

local function FormatDropdownText(dropdown, defaultKey, labels)
    if #labels == 0 then return L(defaultKey) end
    if #labels == 1 then return labels[1] end

    local twoLabel = labels[1] .. ", " .. labels[2]
    if #labels == 2 and TextFits(dropdown.displayText, twoLabel) then
        return twoLabel
    end

    local twoPlus = twoLabel .. " +" .. (#labels - 2)
    if #labels > 2 and TextFits(dropdown.displayText, twoPlus) then
        return twoPlus
    end

    return string.format(L("FILTER_MORE"), labels[1], #labels - 1)
end

local function CreateDropdown(parent, x, y, width, defaultKey, getOptions, isSelected, toggle, enabled)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    dropdown:SetSize(width, 28)
    dropdown.styleFrame = dropdown
    if dropdown.SetHitRectInsets then dropdown:SetHitRectInsets(0, 0, 0, 0) end
    dropdown.displayText = T.Text(dropdown, "GameFontHighlightSmall", "")
    dropdown.displayText:SetPoint("LEFT", 14, 0)
    dropdown.displayText:SetWidth(width - 40)
    dropdown.displayText:SetJustifyV("MIDDLE")
    dropdown.displayText:SetWordWrap(false)
    local function Update()
        local labels = {}
        for _, option in ipairs(getOptions()) do
            if option.id and isSelected(option.id) then table.insert(labels, option.name) end
        end
        dropdown.displayText:SetText(FormatDropdownText(dropdown, defaultKey, labels))
        T.Box(dropdown.styleFrame, "surface")
        dropdown.styleFrame:SetBackdropBorderColor(unpack(#labels > 0 and T.colors.selectedBorder or T.colors.border))
        dropdown.displayText:SetTextColor(unpack(T.colors.text))
        if enabled then dropdown:SetEnabled(enabled()) end
    end
    dropdown:SetupMenu(function(_, root)
        for _, option in ipairs(getOptions()) do
            local id, name = option.id, option.name
            if id then
                root:CreateCheckbox(name, function() return isSelected(id) end, function()
                    toggle(id); Update(); FiltersChanged()
                end)
            else root:CreateTitle(name) end
        end
    end)
    table.insert(dropdownUpdates, Update)
    Update()
    return dropdown
end

local function ToggleMap(map, id) map[id] = not map[id] or nil end

local function BuildFilters()
    local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 16, -100)
    bar:SetSize(928, 82)
    T.Box(bar, "surface")
    frame.sourceDropdown = CreateDropdown(bar, 8, -8, 320, "FILTER_SOURCE", function()
        local options = { { name = L("SOURCE_GROUP_DUNGEONS") } }
        for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
            table.insert(options, { id = "dungeon:" .. dungeon.instanceId, name = ContentName(dungeon.name) })
        end
        for _, raid in ipairs(Where2GoSources.RAIDS) do
            table.insert(options, { name = ContentName(raid.name) })
            for _, boss in ipairs(raid.encounters) do
                table.insert(options, { id = "boss:" .. boss.bossId, name = ContentName(boss.name) })
            end
        end
        return options
    end, function(id) return filters.sources[id] == true end, function(id) ToggleMap(filters.sources, id) end)
    frame.slotDropdown = CreateDropdown(bar, 340, -8, 150, "FILTER_SLOT", function()
        local options = {}
        for _, id in ipairs(SLOT_ORDER) do table.insert(options, { id = id, name = Where2GoLocale.SlotLabel(id) }) end
        return options
    end, function(id) return filters.slots[id] == true end, function(id) ToggleMap(filters.slots, id) end)
    local function HasStat(id)
        for _, stat in ipairs(filters.stats) do if stat == id then return true end end
        return false
    end
    frame.statDropdown = CreateDropdown(bar, 502, -8, 182, "FILTER_STAT", function()
        local options = {}
        for _, id in ipairs(STAT_ORDER) do table.insert(options, { id = id, name = Where2GoLocale.StatLabel(id) }) end
        return options
    end, HasStat, function(id)
        if HasStat(id) then
            for i, stat in ipairs(filters.stats) do if stat == id then table.remove(filters.stats, i); break end end
        else table.insert(filters.stats, id) end
    end)
    frame.resetFilters = T.Button(bar, L("FILTER_RESET"), 110, 28, function()
        ResetFiltersToDefaults()
        frame.eligible:SetChecked(true)
        frame.search:SetText("")
        for _, update in ipairs(dropdownUpdates) do update() end
        FiltersChanged()
    end)
    frame.specDropdown = CreateDropdown(bar, 696, -8, 224, "FILTER_SPEC", AvailableSpecs,
        function(id) return filters.specIds[id] == true end,
        function(id) ToggleMap(filters.specIds, id) end,
        function() return filters.specEligibleOnly end)
    frame.resetFilters:SetPoint("TOPRIGHT", -8, -46)
    frame.eligible = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    frame.eligible:SetSize(24, 24)
    frame.eligible:SetPoint("TOPLEFT", 8, -48)
    frame.eligible:SetChecked(true)
    local eligibleText = T.Text(bar, "GameFontHighlightSmall", L("ELIGIBLE_ONLY"))
    eligibleText:SetPoint("LEFT", frame.eligible, "RIGHT", 2, 0)
    eligibleText:SetWidth(250)
    frame.eligible:SetScript("OnClick", function(self)
        filters.specEligibleOnly = self:GetChecked() and true or false
        for _, update in ipairs(dropdownUpdates) do update() end
        FiltersChanged()
    end)
    frame.specDropdown:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("BROWSER_SPEC_HINT"))
        GameTooltip:Show()
    end)
    frame.specDropdown:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local searchLabel = T.Text(bar, "GameFontHighlightSmall", L("SEARCH_LABEL"))
    searchLabel:SetPoint("TOPLEFT", 320, -52)
    frame.search = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
    frame.search:SetPoint("TOPLEFT", 424, -48)
    frame.search:SetSize(370, 26)
    T.Box(frame.search, "inset")
    frame.search:SetFontObject("GameFontHighlightSmall")
    frame.search:SetTextColor(unpack(T.colors.text))
    frame.search:SetTextInsets(10, 10, 0, 0)
    frame.search:SetAutoFocus(false)
    frame.search:SetScript("OnEditFocusGained", function(self)
        local text = self:GetText() or ""
        self:SetBackdropBorderColor(unpack(text ~= "" and T.colors.selectedBorder or T.colors.border))
    end)
    frame.search:SetScript("OnEditFocusLost", function(self)
        local text = self:GetText() or ""
        self:SetBackdropBorderColor(unpack(text ~= "" and T.colors.selectedBorder or T.colors.border))
    end)
    frame.search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        filters.searchText = text
        self:SetBackdropBorderColor(unpack(text ~= "" and T.colors.selectedBorder or T.colors.border))
        FiltersChanged()
    end)
    frame.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end

local function BuildLists()
    frame.resultTitle = T.Text(frame, "GameFontHighlight", "")
    frame.resultTitle:SetPoint("TOPLEFT", 16, -194)
    frame.preferredTitle = T.Text(frame, "GameFontHighlight", "")
    frame.preferredTitle:SetPoint("TOPLEFT", 600, -194)
    frame.selectAll = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.selectAll:SetSize(24, 24)
    frame.selectAll:SetPoint("TOPLEFT", 404, -188)
    frame.selectAll.partial = T.Text(frame.selectAll, "GameFontHighlight", "−")
    frame.selectAll.partial:SetPoint("CENTER", 0, 0)
    frame.selectAll.partial:Hide()
    local allText = T.Text(frame, "GameFontHighlightSmall", L("SELECT_RESULTS"))
    allText:SetPoint("LEFT", frame.selectAll, "RIGHT", 2, 0)
    frame.selectAll:SetScript("OnClick", function()
        local n, total = selection:GetCounts()
        selection:SelectAll(n ~= total); RefreshRows(); UpdateActions()
    end)
    frame.selectAll:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("SELECTION_HINT")); GameTooltip:Show()
    end)
    frame.selectAll:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 16, -218)
    list:SetSize(RESULT_WIDTH, ROW_HEIGHT * ROWS + 12)
    T.Box(list, "inset")
    frame.resultList = list
    frame.resultEmpty = EmptyLabel(list, RESULT_WIDTH, "")
    frame.resultScroll = MakeScrollbar(list, ROW_HEIGHT * ROWS, function(value)
        local offset = Clamp(value, #results)
        if resultOffset ~= offset then resultOffset = offset; RefreshRows() end
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        resultOffset = Clamp(resultOffset - delta * 3, #results); RefreshRows()
    end)
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(RESULT_WIDTH - 26, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_HEIGHT)
        row.selectedBg = row:CreateTexture(nil, "BACKGROUND")
        row.selectedBg:SetAllPoints()
        row.selectedBg:SetColorTexture(unpack(T.colors.selected))
        row.selectedBg:Hide()
        row.checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.checkbox:SetSize(24, 24)
        row.checkbox:SetPoint("LEFT", 0, 0)
        row.checkbox:SetScript("OnClick", function()
            if row.entry then selection:Toggle(row.entry.itemId); RefreshRows(); UpdateActions() end
        end)
        Where2GoItemRow.CreateWidgets(row, 28, 28)
        row.name:SetFontObject("GameFontHighlight")
        row.name:SetWidth(RESULT_WIDTH - 158)
        row.summary:SetWidth(RESULT_WIDTH - 158)
        row.add = T.Button(row, L("ADD_ONE"), 64, 24, function()
            if row.entry then Add({ [row.entry.itemId] = row.entry.bonusId or true }) end
        end)
        row.add:SetPoint("RIGHT", -2, 0)
        resultRows[i] = row
    end
    local savedList = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    savedList:SetPoint("TOPLEFT", 600, -218)
    savedList:SetSize(PREFERRED_WIDTH, ROW_HEIGHT * ROWS + 12)
    T.Box(savedList, "inset")
    frame.preferredList = savedList
    frame.preferredEmpty = EmptyLabel(savedList, PREFERRED_WIDTH, L("EMPTY_PREFERRED"))
    frame.preferredScroll = MakeScrollbar(savedList, ROW_HEIGHT * ROWS, function(value)
        local offset = Clamp(value, #preferredIds)
        if preferredOffset ~= offset then preferredOffset = offset; RefreshRows() end
    end)
    savedList:EnableMouseWheel(true)
    savedList:SetScript("OnMouseWheel", function(_, delta)
        preferredOffset = Clamp(preferredOffset - delta * 3, #preferredIds); RefreshRows()
    end)
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, savedList)
        row:SetSize(PREFERRED_WIDTH - 26, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_HEIGHT)
        Where2GoItemRow.CreateWidgets(row, 28, 2)
        row.name:SetFontObject("GameFontHighlight")
        row.name:SetWidth(PREFERRED_WIDTH - 92)
        row.summary:SetWidth(PREFERRED_WIDTH - 92)
        row.remove = T.Button(row, "×", 22, 24, function() if row.itemId then Remove(row.itemId) end end)
        row.remove:SetPoint("RIGHT", -2, 0)
        row.remove:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L("REMOVE_ONE")); GameTooltip:Show()
        end)
        row.remove:HookScript("OnLeave", function() GameTooltip:Hide() end)
        preferredRows[i] = row
    end
end

local function CreateBrowser()
    frame = CreateFrame("Frame", "Where2GoBrowser", UIParent, "BackdropTemplate")
    frame:SetSize(960, 718)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    T.Box(frame)
    table.insert(UISpecialFrames, "Where2GoBrowser")
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", -40, 0)
    titleBar:SetHeight(60)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local title = T.Text(titleBar, "GameFontNormalLarge", L("BROWSER_TITLE"))
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetTextColor(unpack(T.colors.accent))
    local subtitle = T.Text(titleBar, "GameFontHighlightSmall", L("BROWSER_SUBTITLE"))
    subtitle:SetPoint("TOPLEFT", 16, -42)
    subtitle:SetTextColor(unpack(T.colors.muted))
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.modeButtons = {}
    for i, mode in ipairs({ "DROP", "VOIDCORE" }) do
        local button = T.Button(frame, L("MODE_" .. mode), 112, 28, function() SetMode(mode) end)
        button:SetPoint("TOPLEFT", 16 + (i - 1) * 120, -64)
        frame.modeButtons[mode] = button
    end
    BuildFilters()
    BuildLists()
    frame.selectionCount = T.Text(frame, "GameFontHighlightSmall", "")
    frame.selectionCount:SetPoint("TOPLEFT", 16, -646)
    frame.selectionCount:SetWidth(232)
    frame.clearSelection = T.Button(frame, L("CLEAR_SELECTION"), 104, 28, function()
        selection:SelectAll(false); RefreshRows(); UpdateActions()
    end)
    frame.clearSelection:SetPoint("TOPLEFT", 264, -636)
    frame.addSelected = T.Button(frame, "", 200, 28, function() Add(selection:GetSelected()) end)
    frame.addSelected:SetPoint("TOPLEFT", 384, -636)
    frame.addSelected:GetFontString():SetTextColor(unpack(T.colors.accent))
    frame.clearPreferred = T.Button(frame, L("CLEAR_ALL"), 100, 28, function()
        StaticPopup_Show("WHERE2GO_CLEAR_PREFERRED", nil, nil, currentMode)
    end)
    frame.clearPreferred:SetPoint("TOPLEFT", 844, -636)
    frame.feedback = T.Text(frame, "GameFontHighlightSmall", "")
    frame.feedback:SetPoint("TOPLEFT", 16, -685)
    frame.feedback:SetWidth(806)
    frame.feedback:SetTextColor(unpack(T.colors.muted))
    frame.undo = T.Button(frame, L("UNDO"), 100, 26, function()
        if Where2GoPreferences.Undo(currentMode) > 0 then Feedback("UNDONE_FEEDBACK") end
    end)
    frame.undo:SetPoint("TOPRIGHT", -16, -676)
    frame:Hide()
    SetMode(currentMode)
end

StaticPopupDialogs["WHERE2GO_CLEAR_PREFERRED"] = {
    text = L("CLEAR_PREFERRED_CONFIRM"),
    button1 = L("CLEAR_BUTTON"), button2 = L("CANCEL_BUTTON"),
    OnAccept = function(self, data)
        local mode = data or self.data
        if mode ~= "DROP" and mode ~= "VOIDCORE" then return end
        local count = Where2GoPreferences.Clear(mode)
        if frame and currentMode == mode and count > 0 then Feedback("REMOVED_FEEDBACK", count) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Where2GoBrowserPanel.Show(mode)
    if not frame then
        selection = Where2GoSelection.New()
        pool = Where2GoItemBrowser.BuildItemPool()
        ResetFiltersToDefaults()
        CreateBrowser()
        for _, entry in ipairs(pool) do
            if not pendingItems[entry.itemId] and not C_Item.GetItemInfo(entry.itemId) then
                pendingItems[entry.itemId] = true
                C_Item.RequestLoadItemDataByID(entry.itemId)
            end
        end
    end
    if mode then SetMode(mode) end
    Refresh(false)
    frame:Show()
end

function Where2GoBrowserPanel.Toggle()
    if frame and frame:IsShown() then frame:Hide()
    else Where2GoBrowserPanel.Show() end
end

Where2GoPreferences.Subscribe("browser", function()
    if frame then Refresh(false) end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
watcher:SetScript("OnEvent", function(_, _, itemId)
    if pendingItems[itemId] then
        pendingItems[itemId] = nil
        if frame and frame:IsShown() then Refresh(false) end
    end
end)
