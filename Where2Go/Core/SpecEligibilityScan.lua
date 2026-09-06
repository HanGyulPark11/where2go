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
-- cold-item-cache step at all. It also scans a whole dungeon/raid's
-- combined loot per class/spec (EJ_SelectInstance only, no
-- EJ_SelectEncounter) rather than per boss, since BY_SPEC has no
-- per-boss grouping to preserve -- see CollectSourceItemIds below. See
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

-- Pure: given the item IDs Where2GoSources.lua tracks for one source
-- (`knownItemIds`, a plain array) and the item IDs the Encounter
-- Journal's CURRENT unfiltered (no class/spec filter) loot list actually
-- contains for that source (`realItemIds`, `{[itemId]=true,...}`),
-- returns the known item IDs that are NOT in the real list -- i.e. items
-- Sources.lua still tracks that the live Encounter Journal no longer
-- lists as droppable at all here, regardless of spec. This is a stronger
-- signal than a spec-eligibility gap: an item missing from realItemIds
-- can never match any spec because it just isn't real loot right now
-- (Sources.lua itself needs correcting), versus an item present in
-- realItemIds but still unmatched by every spec scanned, which is a
-- genuine per-spec attribution question instead.
function Where2GoSpecEligibilityScan.FindStaleItemIds(knownItemIds, realItemIds)
    local stale = {}
    for _, itemId in ipairs(knownItemIds) do
        if not realItemIds[itemId] then
            table.insert(stale, itemId)
        end
    end
    return stale
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

-- EJ difficulty IDs the Encounter Journal scopes its loot list to --
-- EJ_SelectInstance alone does not imply a difficulty, and
-- GetLootInfoByIndex reads whatever difficulty EJ_SetDifficulty last set,
-- which otherwise carries over unset/stale between calls. Confirmed
-- against a published addon's own working EJ call sequence
-- (Tercioo/Details-Framework's ejournal.lua, which always calls
-- EJ_SetDifficulty before EJ_SelectInstance, and separately selects a
-- different EJ tier for Mythic+ dungeons vs raids) and against Warcraft
-- Wiki's DifficultyID list. Dungeons need Mythic Keystone specifically
-- (not e.g. Heroic) since Where2GoSources.lua's dungeon item pools are
-- the M+-track items; raids need Mythic for the same reason.
local EJ_MYTHIC_KEYSTONE_DIFFICULTY = 8
local EJ_MYTHIC_RAID_DIFFICULTY = 16

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

-- Every item ID any of `source`'s encounters tracks, flattened into one
-- array. BY_SPEC has no per-boss grouping at all (just
-- `[specId][itemId] = true`), so the scan never needs to know which
-- specific boss an item came from -- only whether the whole
-- dungeon/raid's loot, filtered to one spec, includes it. Selecting the
-- instance without selecting any encounter (EJ_SelectInstance alone, no
-- EJ_SelectEncounter) mirrors what the real Encounter Journal UI does
-- when a player clicks a dungeon/raid's title without picking a boss --
-- confirmed by reading Blizzard's own EncounterJournal_DisplayInstance,
-- which sets `encounterID = nil` and calls EJ_GetNumLoot/GetLootInfoByIndex
-- directly, aggregating every encounter's loot in one combined list.
local function CollectSourceItemIds(source)
    local ids = {}
    for _, encounter in ipairs(source.encounters) do
        for _, itemId in ipairs(encounter.itemIds) do
            table.insert(ids, itemId)
        end
    end
    return ids
end

-- Scans one dungeon/raid entry at the given EJ difficulty, merging
-- matched items for every class/spec in the game into `bySpec`. Factored
-- out of RunFullScan so dungeons (Mythic Keystone difficulty) and raids
-- (Mythic raid difficulty) share the same per-source/per-spec loop while
-- each selects the correct EJ difficulty for their category first.
-- Returns this source's stale item IDs (see FindStaleItemIds above).
local function ScanSourceIntoBySpec(source, difficultyId, bySpec, numClasses, sex)
    EJ_SetDifficulty(difficultyId)
    -- EJ_SelectEncounter selects a boss WITHIN the currently selected
    -- instance -- it needs EJ_SelectInstance called first, or it
    -- silently selects nothing (EJ_GetNumLoot then returns 0 for every
    -- boss, which would make every tracked item look stale). This
    -- selection gets overwritten again below by the whole-instance
    -- reselect once the per-encounter loop is done.
    EJ_SelectInstance(source.instanceId)

    -- Stale-item check: per encounter (EJ_SelectEncounter), NOT the
    -- whole-instance aggregate view used below for BY_SPEC. Confirmed
    -- live that the no-encounter-selected aggregate view doesn't
    -- reliably honor EJ_SetDifficulty for every boss in a multi-boss
    -- instance -- a Normal-only item (Merektha's Fangproof Gauntlets,
    -- Temple of Sethraliss) still showed up as "real" loot through the
    -- aggregate view at Mythic Keystone difficulty, and only stopped
    -- appearing once queried per-encounter. One extra EJ_SelectEncounter
    -- call per boss (37 total across the whole scan) is negligible next
    -- to the ~40-spec loop below, and this check only runs once per
    -- source regardless.
    local realItemIds = {}
    for _, encounter in ipairs(source.encounters) do
        EJ_SelectEncounter(encounter.bossId)
        EJ_SetLootFilter(0, 0)
        for itemId in pairs(CollectCurrentLootItemIds()) do
            realItemIds[itemId] = true
        end
    end

    -- BY_SPEC matching stays on the whole-instance aggregate view
    -- (EJ_SelectInstance alone, no EJ_SelectEncounter) -- Phase 8b's
    -- per-instance-not-per-boss optimization, unaffected by the
    -- per-encounter stale check above since BY_SPEC has no per-boss
    -- grouping to begin with.
    EJ_SelectInstance(source.instanceId)
    local sourceItemIds = CollectSourceItemIds(source)
    local staleItemIds = Where2GoSpecEligibilityScan.FindStaleItemIds(sourceItemIds, realItemIds)

    for classIndex = 1, numClasses do
        local _, _, classId = GetClassInfo(classIndex)
        if classId then
            -- `or 0` and the specId nil-check below are defensive:
            -- neither API is expected to return nil for a real
            -- class/spec index on current retail (class IDs 1-13
            -- are contiguous), but if one ever did, skipping just
            -- that class/spec is safer than letting a `for` loop
            -- raise "'for' limit must be a number" and having the
            -- pcall in Start() abort the whole scan.
            local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId) or 0
            for specIndex = 1, numSpecs do
                local specId = GetSpecializationInfoForClassID(classId, specIndex, sex)
                if specId then
                    EJ_SetLootFilter(classId, specId)
                    local filtered = CollectCurrentLootItemIds()
                    local matched = Where2GoSpecEligibilityScan.FilterKnownItemIds(filtered, sourceItemIds)
                    -- Every spec actually scanned gets a bySpec entry
                    -- regardless of whether anything matched here, so
                    -- a spec that now matches nothing ends up with an
                    -- empty {} (per MergeBySpec's contract above)
                    -- instead of silently keeping a prior pass's
                    -- stale entry.
                    local existing = bySpec[specId] or {}
                    for itemId in pairs(matched) do
                        existing[itemId] = true
                    end
                    bySpec[specId] = existing
                end
            end
        end
    end

    return staleItemIds
end

-- The actual scan: for every tracked dungeon/raid, for every class/spec
-- in the game, ask the Encounter Journal which of that instance's known
-- items (across all its bosses at once, see CollectSourceItemIds) this
-- spec can receive. Runs synchronously (no C_Timer chunking) since every
-- call here is local client data with no server round-trip, unlike the
-- old tooltip-read/SetLootSpecialization flow. Wrapped in pcall by
-- Start() below, so any error here still leaves _running reset
-- correctly. Returns bySpec plus staleItems -- a maintainer-facing
-- diagnostic list of Sources.lua item IDs the live Encounter Journal no
-- longer lists as droppable for their instance at all (see
-- FindStaleItemIds), one entry per source that has any, so a single
-- genspec run can flag Sources.lua data-quality drift instead of it only
-- surfacing as an unexplained spec-eligibility gap.
local function RunFullScan()
    local bySpec = {}
    local staleItems = {}
    local numClasses = GetNumClasses()
    local sex = UnitSex("player")

    local function scanAndRecordStale(source, difficultyId)
        local staleItemIds = ScanSourceIntoBySpec(source, difficultyId, bySpec, numClasses, sex)
        if #staleItemIds > 0 then
            table.insert(staleItems, {
                instanceId = source.instanceId,
                instanceName = source.name,
                itemIds = staleItemIds,
            })
        end
    end

    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        scanAndRecordStale(dungeon, EJ_MYTHIC_KEYSTONE_DIFFICULTY)
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        scanAndRecordStale(raid, EJ_MYTHIC_RAID_DIFFICULTY)
    end

    EJ_SetLootFilter(0, 0)
    return bySpec, staleItems
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
    if not EJ_SelectInstance or not C_EncounterJournal then
        return false, "EJ_LOAD_FAILED"
    end

    _running = true
    local ok, bySpecResult, staleItemsResult = pcall(RunFullScan)
    _running = false

    if not ok then
        -- Surface the actual error via WoW's global error handler (the
        -- standard addon idiom -- routes to whatever error-display
        -- addon/console the player has, same as an unhandled Lua error
        -- would), rather than swallowing it silently.
        geterrorhandler()(bySpecResult)
        NotifyProgress(nil, nil, nil, "ABORTED_ERROR")
        return false, "ERROR"
    end

    Where2GoDB.specEligibilityExport = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        bySpec = Where2GoSpecEligibilityScan.MergeBySpec(
            Where2GoDB.specEligibilityExport and Where2GoDB.specEligibilityExport.bySpec,
            bySpecResult),
        -- Always a full overwrite, never merged with a prior run's
        -- staleItems -- unlike bySpec (which Phase 8b's own design allows
        -- scanning incrementally spec-by-spec across multiple sessions),
        -- every RunFullScan pass already covers every tracked source in
        -- one go, so a prior pass's staleItems entry can never be more
        -- current than this one.
        staleItems = staleItemsResult,
    }
    NotifyProgress(nil, nil, nil, "COMPLETE")
    return true
end
