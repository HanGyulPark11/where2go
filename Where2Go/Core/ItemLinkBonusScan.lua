-- Generates a reviewed export of full Encounter Journal item-link templates.
-- `/where2go genlinks` writes only Where2GoDB.itemLinkBonusesExport; the
-- maintainer-side converter normalizes volatile fields and stages
-- Core/ItemLinkBonuses.lua for manual review.
--
-- The parsing and export helpers are pure and covered by
-- tests/itemLinkBonusScan_spec.lua. The Encounter Journal loop is live-client
-- behavior and requires the checklist QA before its output is applied.
-- luacheck: globals Where2GoItemLinkBonusScan Where2GoTracks Where2GoRaidRanks
-- luacheck: globals Where2GoSources Where2GoConstants Where2GoDB C_AddOns LoadAddOn
-- luacheck: globals EJ_SetDifficulty EJ_SelectInstance EJ_SelectEncounter EJ_SetLootFilter
-- luacheck: globals EJ_GetNumLoot C_EncounterJournal InCombatLockdown geterrorhandler Item C_Timer

Where2GoItemLinkBonusScan = {}

local EXPORT_SCHEMA_VERSION = 2
local EJ_MYTHIC_KEYSTONE_DIFFICULTY = 8
local EJ_MYTHIC_RAID_DIFFICULTY = 16
local ITEM_WARMUP_TIMEOUT_SECONDS = 5
local _running = false
local _progressCallbacks = {}

local function copyArray(values)
    local copied = {}
    for index, value in ipairs(values) do
        copied[index] = value
    end
    return copied
end

-- Encounter Journal's bonus order is significant when copied into a synthetic
-- link. Only an exactly identical ordered residual list is a duplicate; a
-- reordered list is a conflict that must never be selected silently.
local function listsEqual(left, right)
    if #left ~= #right then
        return false
    end
    for index, value in ipairs(left) do
        if right[index] ~= value then
            return false
        end
    end
    return true
end

-- Parses the complete item-string portion of either a raw `item:` string or
-- a decorated |Hitem:...|h link. The bonus count is field 14, followed by
-- exactly that many numeric bonus IDs; malformed or truncated links are
-- rejected rather than guessed at.
function Where2GoItemLinkBonusScan.ParseItemLink(link)
    if type(link) ~= "string" then
        return nil, {}
    end
    local itemString = link:match("|H(item:[^|]+)|h") or link:match("(item:[^|]+)")
    if not itemString then
        return nil, {}
    end

    local fields = {}
    for field in (itemString .. ":"):gmatch("([^:]*):") do
        table.insert(fields, field)
    end
    local itemId = tonumber(fields[2])
    local bonusCount = tonumber(fields[14])
    if not itemId or itemId <= 0 or itemId % 1 ~= 0
        or not bonusCount or bonusCount < 0 or bonusCount % 1 ~= 0
        or #fields < 14 + bonusCount then
        return nil, {}
    end

    local bonuses = {}
    for index = 1, bonusCount do
        local bonusId = tonumber(fields[14 + index])
        if not bonusId or bonusId % 1 ~= 0 then
            return nil, {}
        end
        table.insert(bonuses, bonusId)
    end
    return itemId, bonuses
end

function Where2GoItemLinkBonusScan.BuildTrackBonusSet()
    local trackBonuses = {}
    for _, track in pairs(Where2GoTracks.UPGRADE_TRACKS) do
        for rank = 1, #track.ilvls do
            trackBonuses[track.bonusIdStart + rank - 1] = true
        end
    end
    trackBonuses[Where2GoRaidRanks.MYTH_FINAL_BONUS_ID] = true
    return trackBonuses
end

-- Returns a de-duplicated list of only the static effect/context bonuses in
-- their original link order. All values that express an upgrade rank are
-- intentionally removed.
function Where2GoItemLinkBonusScan.StripTrackBonuses(bonuses)
    local trackBonuses = Where2GoItemLinkBonusScan.BuildTrackBonusSet()
    local residualSet = {}
    local residual = {}
    for _, bonusId in ipairs(bonuses or {}) do
        if not trackBonuses[bonusId] then
            if not residualSet[bonusId] then
                residualSet[bonusId] = true
                table.insert(residual, bonusId)
            end
        end
    end
    return residual
end

-- Builds a deterministic, conservative SavedVariables export. `observations`
-- contains parsed and raw links for every EJ entry, while `knownItemIds` is the tracked
-- Sources.lua pool. An item with two distinct residual lists appears only in
-- `conflicts`, never in `byItem`, so a maintainer must resolve it explicitly.
function Where2GoItemLinkBonusScan.BuildExport(seasonVersion, observations, knownItemIds, presentItemIds, unresolvedLinkItems)
    local known = {}
    for _, itemId in ipairs(knownItemIds or {}) do
        known[itemId] = true
    end

    local present = presentItemIds or {}
    for _, observation in ipairs(observations or {}) do
        if known[observation.itemId] then
            present[observation.itemId] = true
        end
    end

    local alternatives = {}
    local rawLinks = {}
    for _, observation in ipairs(observations or {}) do
        if known[observation.itemId] then
            local residual = Where2GoItemLinkBonusScan.StripTrackBonuses(observation.bonuses)
            alternatives[observation.itemId] = alternatives[observation.itemId] or {}
            local itemAlternatives = alternatives[observation.itemId]
            local duplicate = false
            for _, existing in ipairs(itemAlternatives) do
                if listsEqual(existing, residual) then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                table.insert(itemAlternatives, residual)
            end

            if type(observation.rawLink) == "string" then
                rawLinks[observation.itemId] = rawLinks[observation.itemId] or {}
                local itemRawLinks = rawLinks[observation.itemId]
                local rawDuplicate = false
                for _, existing in ipairs(itemRawLinks) do
                    if existing == observation.rawLink then
                        rawDuplicate = true
                        break
                    end
                end
                if not rawDuplicate then
                    table.insert(itemRawLinks, observation.rawLink)
                end
            end
        end
    end

    local trackedIds = {}
    for itemId in pairs(known) do
        table.insert(trackedIds, itemId)
    end
    table.sort(trackedIds)

    local byItem = {}
    local conflicts = {}
    local missingItems = {}
    local unresolvedItems = {}
    local observedItemCount = 0
    for _, itemId in ipairs(trackedIds) do
        local itemAlternatives = alternatives[itemId]
        if present[itemId] then
            observedItemCount = observedItemCount + 1
        end
        if unresolvedLinkItems and unresolvedLinkItems[itemId] and not itemAlternatives then
            table.insert(unresolvedItems, itemId)
        elseif not present[itemId] then
            table.insert(missingItems, itemId)
        else
            if #itemAlternatives == 1 then
                byItem[itemId] = copyArray(itemAlternatives[1])
            else
                conflicts[itemId] = itemAlternatives
            end
        end
    end

    return {
        schemaVersion = EXPORT_SCHEMA_VERSION,
        seasonVersion = seasonVersion,
        trackedItemCount = #trackedIds,
        observedItemCount = observedItemCount,
        byItem = byItem,
        rawLinks = rawLinks,
        conflicts = conflicts,
        missingItems = missingItems,
        unresolvedLinkItems = unresolvedItems,
    }
end

local function collectKnownItemIds()
    local known = {}
    local function addSources(sources)
        for _, source in ipairs(sources) do
            for _, encounter in ipairs(source.encounters) do
                for _, itemId in ipairs(encounter.itemIds) do
                    known[itemId] = true
                end
            end
        end
    end
    addSources(Where2GoSources.DUNGEONS)
    addSources(Where2GoSources.RAIDS)
    local itemIds = {}
    for itemId in pairs(known) do
        table.insert(itemIds, itemId)
    end
    table.sort(itemIds)
    return itemIds, known
end

local function countEncounters()
    local total = 0
    for _, sources in ipairs({ Where2GoSources.DUNGEONS, Where2GoSources.RAIDS }) do
        for _, source in ipairs(sources) do
            total = total + #source.encounters
        end
    end
    return total
end

local function notifyProgress(sourceName, encounterName, current, total, finishedReason, export)
    for _, callback in pairs(_progressCallbacks) do
        callback(sourceName, encounterName, current, total, finishedReason, export)
    end
end

local function ensureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

local function collectEncounterObservations(known, observations, presentItemIds, unresolvedLinkItems)
    local numLoot = EJ_GetNumLoot() or 0
    for index = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(index)
        local rawLink = info and (info.link or info.itemLink)
        local itemId, bonuses = Where2GoItemLinkBonusScan.ParseItemLink(rawLink)
        local infoItemId = info and info.itemID
        if infoItemId and known[infoItemId] then
            presentItemIds[infoItemId] = true
        end
        if itemId and infoItemId == itemId and known[itemId] then
            table.insert(observations, { itemId = itemId, bonuses = bonuses, rawLink = rawLink })
            unresolvedLinkItems[itemId] = nil
        elseif infoItemId and known[infoItemId] then
            unresolvedLinkItems[infoItemId] = true
        end
    end
end

function Where2GoItemLinkBonusScan.ScanSources(sources, difficultyId, known, observations, progress, api)
    api = api or {
        setDifficulty = EJ_SetDifficulty,
        selectInstance = EJ_SelectInstance,
        selectEncounter = EJ_SelectEncounter,
        clearLootFilter = function() EJ_SetLootFilter(0, 0) end,
        collect = function()
            collectEncounterObservations(known, observations, progress.presentItemIds, progress.unresolvedLinkItems)
        end,
        notify = notifyProgress,
    }
    for _, source in ipairs(sources) do
        -- Match the proven SpecEligibilityScan ordering: the difficulty and
        -- instance are selected once for each source, before its boss loop.
        api.setDifficulty(difficultyId)
        api.selectInstance(source.instanceId)
        for _, encounter in ipairs(source.encounters) do
            api.selectEncounter(encounter.bossId)
            api.clearLootFilter()
            api.collect()
            progress.current = progress.current + 1
            api.notify(source.name, encounter.name, progress.current, progress.total)
        end
    end
end

local function runFullScan()
    local knownItemIds, known = collectKnownItemIds()
    local observations = {}
    local progress = {
        current = 0,
        total = countEncounters(),
        presentItemIds = {},
        unresolvedLinkItems = {},
    }
    Where2GoItemLinkBonusScan.ScanSources(Where2GoSources.DUNGEONS, EJ_MYTHIC_KEYSTONE_DIFFICULTY, known, observations, progress)
    Where2GoItemLinkBonusScan.ScanSources(Where2GoSources.RAIDS, EJ_MYTHIC_RAID_DIFFICULTY, known, observations, progress)
    EJ_SetLootFilter(0, 0)
    return Where2GoItemLinkBonusScan.BuildExport(
        Where2GoConstants.SEASON_LABEL, observations, knownItemIds, progress.presentItemIds, progress.unresolvedLinkItems)
end

function Where2GoItemLinkBonusScan.WarmKnownItemIds(knownItemIds, completion)
    local completed = false
    local function finish()
        if not completed then
            completed = true
            completion()
        end
    end

    if not Item or type(Item.CreateFromItemID) ~= "function" then
        finish()
        return
    end

    local pending = #knownItemIds
    if pending == 0 then
        finish()
        return
    end

    for _, itemId in ipairs(knownItemIds) do
        local item = Item:CreateFromItemID(itemId)
        if not item or type(item.ContinueOnItemLoad) ~= "function" then
            finish()
            return
        end
        item:ContinueOnItemLoad(function()
            pending = pending - 1
            if pending == 0 then
                finish()
            end
        end)
    end

    if not C_Timer or type(C_Timer.After) ~= "function" then
        finish()
        return
    end
    C_Timer.After(ITEM_WARMUP_TIMEOUT_SECONDS, finish)
end

function Where2GoItemLinkBonusScan.SetProgressCallback(name, callback)
    _progressCallbacks[name] = callback
end

function Where2GoItemLinkBonusScan.IsRunning()
    return _running
end

function Where2GoItemLinkBonusScan.CheckExportSeasonStale(export, currentSeasonLabel)
    return export ~= nil and export.seasonVersion ~= nil and export.seasonVersion ~= currentSeasonLabel
end

function Where2GoItemLinkBonusScan.Start()
    if _running then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end
    if Where2GoItemLinkBonusScan.CheckExportSeasonStale(Where2GoDB.itemLinkBonusesExport, Where2GoConstants.SEASON_LABEL) then
        return false, "STALE_SEASON"
    end

    ensureEncounterJournalLoaded()
    if not EJ_SelectInstance or not EJ_SelectEncounter or not C_EncounterJournal then
        return false, "EJ_LOAD_FAILED"
    end

    _running = true
    local finished = false
    local succeeded = false
    local warmupStarted = false
    local completionRequested = false
    local function abort(errorMessage)
        if finished then
            return
        end
        finished = true
        _running = false
        geterrorhandler()(errorMessage)
        notifyProgress(nil, nil, nil, nil, "ABORTED_ERROR")
    end
    local function completeScan()
        if finished then
            return
        end
        local ok, export = pcall(runFullScan)
        if not ok then
            abort(export)
            return
        end

        finished = true
        succeeded = true
        _running = false
        Where2GoDB.itemLinkBonusesExport = export
        notifyProgress(nil, nil, nil, nil, "COMPLETE", export)
    end
    local function completeWarmup()
        if not warmupStarted then
            completionRequested = true
            return
        end
        completeScan()
    end

    local started, startupError = pcall(function()
        local knownItemIds = collectKnownItemIds()
        Where2GoItemLinkBonusScan.WarmKnownItemIds(knownItemIds, completeWarmup)
    end)
    if not started then
        abort(startupError)
    else
        warmupStarted = true
        if completionRequested then
            completeScan()
        end
    end
    if finished then
        if succeeded then
            return true, "COMPLETE"
        end
        return false, "ERROR"
    end
    return true, "WARMING"
end
