-- Scans the "Nebulous Voidcache" tooltip for each of the player's own
-- class's specializations to build an authoritative
-- Where2GoCharDB.specEligibility table, consumed by
-- Core/DirectDrop.lua's IsEligibleForSpec. See
-- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md.
--
-- ParseTooltipLines below is pure (no WoW API) and unit-tested in
-- tests/specEligibilityScan_spec.lua. The scan state machine that calls
-- it is WoW-API-dependent like Core/VoidcoreDrop.lua/VoidcoreHistory.lua
-- -- not unit-tested, verified live instead.

Where2GoSpecEligibilityScan = {}

-- Item-name lines in a Nebulous Voidcache tooltip start at this index
-- (1-based) and are each prefixed "- ". Fewer lines than this means the
-- tooltip hasn't finished loading yet.
local MIN_LINES = 7

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Pure function: parses tooltip line data (shaped like
-- C_TooltipInfo.GetItemByID(...).lines, an array of { leftText = "..." })
-- into a { [itemName] = true } set. Returns nil if there are fewer than
-- MIN_LINES lines (tooltip not fully loaded yet).
function Where2GoSpecEligibilityScan.ParseTooltipLines(lines)
    if not lines or #lines < MIN_LINES then
        return nil
    end
    local items = {}
    for i, lineData in ipairs(lines) do
        if i >= MIN_LINES then
            local text = lineData.leftText
            if text then
                local clean = StripColorCodes(text)
                if clean:sub(1, 2) == "- " then
                    local itemName = clean:sub(3):match("^(.-)%s*$")
                    if itemName and itemName ~= "" then
                        items[itemName] = true
                    end
                end
            end
        end
    end
    return items
end

local RETRY_DELAY = 0.35
local STEP_DELAY = 0.5
local SPEC_CHANGE_DELAY = 1.2
local MAX_RETRIES = 5

local _state = nil
local _progressCallback = nil

function Where2GoSpecEligibilityScan.SetProgressCallback(fn)
    _progressCallback = fn
end

local function NotifyProgress(specName, current, total, finishedReason)
    if _progressCallback then
        _progressCallback(specName, current, total, finishedReason)
    end
end

function Where2GoSpecEligibilityScan.IsRunning()
    return _state ~= nil and _state.running == true
end

local function CollectVoidcacheItemList()
    local items = {}
    for _, itemId in pairs(Where2GoVoidcacheIds.DUNGEONS) do
        table.insert(items, itemId)
    end
    for _, itemId in pairs(Where2GoVoidcacheIds.RAID_BOSSES) do
        table.insert(items, itemId)
    end
    return items
end

-- Every item ID Sources.lua tracks -- the pool a scanned item name needs
-- to resolve against to recover its numeric item ID (tooltips only give
-- names). Requires the item cache to be warm; an item whose name isn't
-- cached yet at scan time is silently skipped for this scan, the same
-- accepted limitation Core/DirectDrop.lua's own header already notes
-- for a cold item cache.
local function CollectAllPoolItemIds()
    local ids = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        for _, encounter in ipairs(dungeon.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                ids[itemId] = true
            end
        end
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                ids[itemId] = true
            end
        end
    end
    return ids
end

local function BuildNameToItemId()
    local nameToItemId = {}
    for itemId in pairs(CollectAllPoolItemIds()) do
        local name = C_Item.GetItemInfo(itemId)
        if name and name ~= "" then
            nameToItemId[name] = itemId
        end
    end
    return nameToItemId
end

local _combatFrame
if CreateFrame then
    _combatFrame = CreateFrame("Frame")
end

local function AbortScan(reason)
    if not _state then
        return
    end
    _state.running = false
    if _combatFrame then
        _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end
    if _state.originalLootSpec ~= nil then
        SetLootSpecialization(_state.originalLootSpec)
    end
    NotifyProgress(nil, nil, nil, reason)
    _state = nil
end

local function FinalizeScan()
    if not _state then
        return
    end
    local bySpec = {}
    for _, specEntry in ipairs(_state.specs) do
        local nameSet = _state.results[specEntry.specId] or {}
        local itemSet = {}
        for name in pairs(nameSet) do
            local itemId = _state.nameToItemId[name]
            if itemId then
                itemSet[itemId] = true
            end
        end
        bySpec[specEntry.specId] = itemSet
    end

    Where2GoCharDB.specEligibility = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        scannedAt = time(),
        bySpec = bySpec,
    }

    if _combatFrame then
        _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end
    SetLootSpecialization(_state.originalLootSpec or 0)
    NotifyProgress(nil, nil, nil, "COMPLETE")
    _state = nil
end

local ScanStep
ScanStep = function()
    if not _state or not _state.running then
        return
    end

    if _state.specIdx > #_state.specs then
        FinalizeScan()
        return
    end

    local specEntry = _state.specs[_state.specIdx]
    local voidcacheItemId = _state.items[_state.itemIdx]

    -- Switch loot spec once at the start of each spec's pass (first
    -- item, no retries yet), then wait for it to take effect.
    -- expectingSpecChange tells the PLAYER_LOOT_SPEC_UPDATED handler
    -- below that this particular change came from the scan itself, not
    -- the player manually changing loot spec mid-scan (which would
    -- otherwise silently attribute the rest of this pass's tooltip
    -- reads to the wrong spec).
    if _state.itemIdx == 1 and _state.retries == 0 and not _state.specSwitchDone then
        _state.expectingSpecChange = true
        SetLootSpecialization(specEntry.specId)
        _state.specSwitchDone = true
        C_Timer.After(SPEC_CHANGE_DELAY, ScanStep)
        return
    end
    _state.expectingSpecChange = false

    local tooltipData = C_TooltipInfo.GetItemByID(voidcacheItemId)
    local lines = tooltipData and tooltipData.lines
    local parsed = Where2GoSpecEligibilityScan.ParseTooltipLines(lines)

    if not parsed then
        _state.retries = _state.retries + 1
        if _state.retries <= MAX_RETRIES then
            C_Timer.After(RETRY_DELAY, ScanStep)
            return
        end
        parsed = {}
    end

    local specNames = _state.results[specEntry.specId] or {}
    for name in pairs(parsed) do
        specNames[name] = true
    end
    _state.results[specEntry.specId] = specNames

    _state.retries = 0
    _state.itemIdx = _state.itemIdx + 1
    if _state.itemIdx > #_state.items then
        _state.itemIdx = 1
        _state.specIdx = _state.specIdx + 1
        _state.specSwitchDone = false
    end

    local completedSteps = (_state.specIdx - 1) * #_state.items + (_state.itemIdx == 1 and 0 or _state.itemIdx - 1)
    NotifyProgress(specEntry.specName, completedSteps, #_state.specs * #_state.items, nil)

    C_Timer.After(STEP_DELAY, ScanStep)
end

function Where2GoSpecEligibilityScan.Start()
    if Where2GoSpecEligibilityScan.IsRunning() then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end

    local numSpecs = GetNumSpecializations()
    local specs = {}
    for i = 1, numSpecs do
        local specId, specName = GetSpecializationInfo(i)
        if specId then
            table.insert(specs, { specId = specId, specName = specName })
        end
    end
    if #specs == 0 then
        return false, "NO_SPECS"
    end

    local items = CollectVoidcacheItemList()
    if #items == 0 then
        return false, "NO_ITEMS"
    end

    for itemId in pairs(CollectAllPoolItemIds()) do
        C_Item.RequestLoadItemDataByID(itemId)
    end

    _state = {
        running = true,
        specs = specs,
        items = items,
        specIdx = 1,
        itemIdx = 1,
        retries = 0,
        specSwitchDone = false,
        expectingSpecChange = false,
        results = {},
        nameToItemId = BuildNameToItemId(),
        originalLootSpec = GetLootSpecialization(),
    }

    if _combatFrame then
        _combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end

    NotifyProgress(specs[1].specName, 0, #specs * #items, nil)
    C_Timer.After(0, ScanStep)
    return true
end

function Where2GoSpecEligibilityScan.EnsureScanned()
    local cache = Where2GoCharDB.specEligibility
    if cache and cache.seasonVersion == Where2GoConstants.SEASON_LABEL then
        return
    end
    if Where2GoSpecEligibilityScan.IsRunning() then
        return
    end
    if InCombatLockdown() then
        return
    end
    Where2GoSpecEligibilityScan.Start()
end

if _combatFrame then
    _combatFrame:SetScript("OnEvent", function(_self, event)
        if not _state or not _state.running then
            return
        end
        if event == "PLAYER_REGEN_DISABLED" then
            AbortScan("ABORTED_COMBAT")
        elseif event == "PLAYER_LOOT_SPEC_UPDATED" then
            if not _state.expectingSpecChange then
                AbortScan("ABORTED_MANUAL_SPEC_CHANGE")
            end
        end
    end)
end
