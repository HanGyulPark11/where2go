-- Generates Core/SpecEligibilityData.lua's BY_SPEC precomputed data: for
-- every class/spec in the game, which of Where2GoSources.lua's tracked
-- dungeon/raid items that spec can actually receive as loot.
-- Maintainer-only, triggered by `/where2go genspec`, merging its result
-- into the account-wide Where2GoDB.specEligibilityExport table for
-- manual hand-merging into the committed Core/SpecEligibilityData.lua
-- (consumed by Core/DirectDrop.lua's IsEligibleForSpec).
--
-- As of Phase 8b this drives Blizzard's own Encounter Journal loot
-- filter (EJ_SetLootFilter(classId, specId) + C_EncounterJournal.GetLootInfoByIndex)
-- instead of Phase 7/8's original Nebulous-Voidcache-tooltip +
-- SetLootSpecialization technique -- the Encounter Journal filter is
-- class-agnostic (works from a single character for every class/spec in
-- the game, not just the scanning character's own class) and returns
-- real numeric item IDs directly, with no tooltip-name-resolution/
-- cold-item-cache step at all. See
-- docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md.
-- Core/VoidcacheIds.lua is intentionally NOT used here anymore (kept in
-- the codebase for a separate, unstarted backlog feature -- see that
-- design doc's "Why VoidcacheIds.lua survives" section).
--
-- FilterKnownItemIds, MergeBySpec, and CheckExportSeasonStale below are
-- pure (no WoW API) and unit-tested in tests/specEligibilityScan_spec.lua.
-- The scan loop that calls them is WoW-API-dependent like
-- Core/VoidcoreDrop.lua/VoidcoreHistory.lua -- not unit-tested, verified
-- live instead.

Where2GoSpecEligibilityScan = {}

-- Pure: given the set of item IDs a loot filter currently returns
-- (`filteredIds`, `{[itemId]=true,...}`) and the list of item IDs
-- Where2GoSources.lua already tracks for one encounter (`knownItemIds`,
-- a plain array), returns only the intersection as a set. This is the
-- mechanism that keeps non-gear Encounter Journal loot (mounts, pets,
-- toys, quest items, crafting reagents) out of BY_SPEC entirely: an
-- item ID never appears in the result unless it was already in
-- `knownItemIds`, regardless of what else `filteredIds` contains.
function Where2GoSpecEligibilityScan.FilterKnownItemIds(filteredIds, knownItemIds)
    local matched = {}
    for _, itemId in ipairs(knownItemIds) do
        if filteredIds[itemId] then
            matched[itemId] = true
        end
    end
    return matched
end

-- Pure: merges a scan pass's per-spec results into the existing export
-- table's bySpec, replacing any spec entries this pass actually scanned
-- (a full re-scan of a spec supersedes its old result entirely, so a
-- since-removed item can't linger) while leaving every other spec's
-- previously accumulated entries untouched. Does not mutate either
-- argument.
function Where2GoSpecEligibilityScan.MergeBySpec(existingBySpec, newBySpec)
    local merged = {}
    for specId, itemSet in pairs(existingBySpec or {}) do
        merged[specId] = itemSet
    end
    for specId, itemSet in pairs(newBySpec or {}) do
        merged[specId] = itemSet
    end
    return merged
end

-- Pure: true if `export` (Where2GoDB.specEligibilityExport) carries data
-- from a season other than `currentSeasonLabel`. A nil export, or one
-- with no seasonVersion yet, is never stale (nothing to conflict with).
function Where2GoSpecEligibilityScan.CheckExportSeasonStale(export, currentSeasonLabel)
    return export ~= nil and export.seasonVersion ~= nil and export.seasonVersion ~= currentSeasonLabel
end

local _running = false
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
    return _running
end

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

-- Every dungeon/raid entry Where2GoSources.lua tracks, in one flat list,
-- each still carrying its own `encounters` array -- the scan loop below
-- iterates this directly rather than DUNGEONS/RAIDS separately, since
-- both need identical treatment (select instance, then per-encounter
-- work).
local function AllTrackedSources()
    local all = {}
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        table.insert(all, dungeon)
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        table.insert(all, raid)
    end
    return all
end

local function CollectCurrentLootItemIds()
    local ids = {}
    local numLoot = EJ_GetNumLoot() or 0
    for i = 1, numLoot do
        local info = C_EncounterJournal.GetLootInfoByIndex(i)
        if info and info.itemID then
            ids[info.itemID] = true
        end
    end
    return ids
end

-- The actual scan: for every tracked encounter, for every class/spec in
-- the game, ask the Encounter Journal which of that encounter's known
-- items this spec can receive. Runs synchronously (no C_Timer chunking)
-- since every call here is local client data with no server round-trip,
-- unlike the old tooltip-read/SetLootSpecialization flow. Wrapped in
-- pcall by Start() below, so any error here still leaves _running reset
-- correctly.
local function RunFullScan()
    local bySpec = {}
    local numClasses = GetNumClasses()
    local sex = UnitSex("player")

    for _, source in ipairs(AllTrackedSources()) do
        for _, encounter in ipairs(source.encounters) do
            EJ_SelectInstance(source.instanceId)
            EJ_SelectEncounter(encounter.bossId)

            for classIndex = 1, numClasses do
                local _, _, classId = GetClassInfo(classIndex)
                local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
                for specIndex = 1, numSpecs do
                    local specId = GetSpecializationInfoForClassID(classId, specIndex, sex)
                    if specId then
                        EJ_SetLootFilter(classId, specId)
                        local filtered = CollectCurrentLootItemIds()
                        local matched = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, encounter.itemIds)
                        if next(matched) ~= nil then
                            local existing = bySpec[specId] or {}
                            for itemId in pairs(matched) do
                                existing[itemId] = true
                            end
                            bySpec[specId] = existing
                        end
                    end
                end
            end
        end
        NotifyProgress(source.name, nil, nil, nil)
    end

    EJ_SetLootFilter(0, 0)
    return bySpec
end

function Where2GoSpecEligibilityScan.Start()
    if Where2GoSpecEligibilityScan.IsRunning() then
        return false, "RUNNING"
    end
    if InCombatLockdown() then
        return false, "COMBAT"
    end
    if Where2GoSpecEligibilityScan.CheckExportSeasonStale(Where2GoDB.specEligibilityExport, Where2GoConstants.SEASON_LABEL) then
        return false, "STALE_SEASON"
    end

    EnsureEncounterJournalLoaded()
    if not EJ_SelectInstance or not EJ_SelectEncounter or not C_EncounterJournal then
        return false, "EJ_LOAD_FAILED"
    end

    _running = true
    local ok, result = pcall(RunFullScan)
    _running = false

    if not ok then
        -- Surface the actual error via WoW's global error handler (the
        -- standard addon idiom -- routes to whatever error-display
        -- addon/console the player has, same as an unhandled Lua error
        -- would), rather than swallowing it silently.
        geterrorhandler()(result)
        NotifyProgress(nil, nil, nil, "ABORTED_ERROR")
        return false, "ERROR"
    end

    Where2GoDB.specEligibilityExport = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        bySpec = Where2GoSpecEligibilityScan.MergeBySpec(
            Where2GoDB.specEligibilityExport and Where2GoDB.specEligibilityExport.bySpec,
            result),
    }
    NotifyProgress(nil, nil, nil, "COMPLETE")
    return true
end
