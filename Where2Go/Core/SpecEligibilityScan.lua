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
local _progressCallbacks = {}

-- Registry keyed by an arbitrary caller-chosen name (e.g. "panel",
-- "browser") rather than a single slot, so multiple UI panels can each
-- register their own callback without one overwriting another's -- both
-- stay in sync regardless of which panel triggered the scan or which is
-- currently visible. Registering under the same name again (e.g. every
-- time a panel is shown) simply overwrites that caller's own entry, so
-- it's safe to call on every show.
function Where2GoSpecEligibilityScan.SetProgressCallback(name, fn)
    _progressCallbacks[name] = fn
end

local function NotifyProgress(specName, current, total, finishedReason)
    for _, fn in pairs(_progressCallbacks) do
        fn(specName, current, total, finishedReason)
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
-- cached yet at scan time is silently skipped for this scan. Unlike
-- Core/DirectDrop.lua's own cold-cache limitation -- which is
-- recomputed on every render and so self-heals naturally as the item
-- cache warms up during normal play -- this scan's result is written
-- once to Where2GoCharDB.specEligibility (persistent SavedVariables)
-- and isn't revisited until the next season's SEASON_LABEL bump, so a
-- cold-cache failure here does NOT self-heal the same way. The actual
-- mitigation is FinalizeScan's empty-result guard below, which refuses
-- to persist a scan whose name resolution came back empty rather than
-- silently writing bad (all-ineligible) data.
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

    -- Built here rather than at Start() time: by the time the full scan
    -- (all specs/items, ~40 seconds) has finished, the
    -- RequestLoadItemDataByID calls issued in Start() have had plenty of
    -- time to resolve, so this name cache is built against a warm item
    -- cache instead of the cold one that's present the instant Start()
    -- is called.
    local nameToItemId = BuildNameToItemId()

    local bySpec = {}
    local coldCacheFailure = false
    for _, specEntry in ipairs(_state.specs) do
        local nameSet = _state.results[specEntry.specId] or {}
        local itemSet = {}
        for name in pairs(nameSet) do
            local itemId = nameToItemId[name]
            if itemId then
                itemSet[itemId] = true
            end
        end
        -- Cold-cache failure signature: real tooltip data came back
        -- (parsed item names were collected) but none of those names
        -- resolved to a known item ID, meaning the item cache was cold
        -- during BuildNameToItemId. Persisting this would permanently
        -- mark this spec ineligible for everything with no recovery
        -- path (see CollectAllPoolItemIds's comment above).
        if next(nameSet) ~= nil and next(itemSet) == nil then
            coldCacheFailure = true
        end
        bySpec[specEntry.specId] = itemSet
    end

    if not coldCacheFailure then
        Where2GoCharDB.specEligibility = {
            seasonVersion = Where2GoConstants.SEASON_LABEL,
            scannedAt = time(),
            bySpec = bySpec,
        }
    end
    -- else: leave Where2GoCharDB.specEligibility untouched -- any
    -- previous (stale but non-empty) scan keeps being used, or if there
    -- was none, IsEligibleForSpec correctly falls through to the old
    -- heuristic. seasonVersion won't have been written/updated, so the
    -- next EnsureScanned() call (next panel open) will retry the scan.

    if _combatFrame then
        _combatFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        _combatFrame:UnregisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    end
    SetLootSpecialization(_state.originalLootSpec or 0)
    NotifyProgress(nil, nil, nil, coldCacheFailure and "ABORTED_NAME_RESOLUTION" or "COMPLETE")
    _state = nil
end

local ScanStep
ScanStep = function()
    if not _state or not _state.running then
        return
    end

    local ok, err = pcall(function()
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
    end)

    if not ok then
        -- Surface the actual error via WoW's global error handler (the
        -- standard addon idiom -- routes to whatever error-display
        -- addon/console the player has, same as an unhandled Lua error
        -- would) so a live failure here is diagnosable instead of
        -- silently retrying on every subsequent panel open. This only
        -- runs from inside C_Timer.After callbacks, a WoW-only API, so
        -- it never executes under the plain-Lua test harness.
        geterrorhandler()(err)
        AbortScan("ABORTED_ERROR")
    end
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
