-- TEMPORARY diagnostic tool, not a shipped feature. Verifies whether
-- Blizzard's Encounter Journal loot filter (EJ_SetLootFilter(classID,
-- specID)) can replace SpecEligibilityScan.lua's Voidcache/
-- SetLootSpecialization approach -- specifically, whether it (a) is
-- callable for any class/spec regardless of the logged-in character's
-- own class, and (b) actually narrows a boss's loot list correctly per
-- spec, the same precision problem Phase 7 needed VoidcacheIds.lua/the
-- tooltip scan to solve. See project memory
-- project_phase8_precomputed_spec_data.md's 2026-09-05 update for the
-- source-code research (Gethe/wow-ui-source) that motivated this test.
--
-- Usage: /where2go ejtest [bossId] [classId]
--   bossId  - a Where2GoSources.lua bossId (defaults to 2880, Zul'jan in
--             Altar of Fangs -- picked for a bigger, more varied loot
--             table (12 items) than Rav'i's 7, which turned out too
--             sparse to show Druid's stat split usefully)
--   classId - a WoW classID (1 Warrior .. 13 Evoker; defaults to 11,
--             Druid, since it has two agility specs (Feral/Guardian) and
--             two intellect specs (Balance/Restoration) all sharing the
--             same leather armor type -- the exact "same armor type,
--             different stat" ambiguity the old heuristic couldn't
--             resolve.
--
-- Delete this file (and its TOC line, and Init.lua's "ejtest" dispatch)
-- once the redesign decision is made either way.

Where2GoEJDiagnostic = {}

local function EnsureEncounterJournalLoaded()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
end

local function FindBossEntry(bossId)
    for _, dungeon in ipairs(Where2GoSources.DUNGEONS) do
        for _, encounter in ipairs(dungeon.encounters) do
            if encounter.bossId == bossId then
                return dungeon, encounter
            end
        end
    end
    for _, raid in ipairs(Where2GoSources.RAIDS) do
        for _, encounter in ipairs(raid.encounters) do
            if encounter.bossId == bossId then
                return raid, encounter
            end
        end
    end
    return nil, nil
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

local function SetToSortedString(idSet)
    local sorted = {}
    for id in pairs(idSet) do
        table.insert(sorted, id)
    end
    table.sort(sorted)
    return table.concat(sorted, ", ")
end

local function ListToSet(list)
    local set = {}
    for _, id in ipairs(list) do
        set[id] = true
    end
    return set
end

function Where2GoEJDiagnostic.TestBoss(bossId, classId)
    bossId = bossId or 2880
    classId = classId or 11

    EnsureEncounterJournalLoaded()

    if not EJ_SelectInstance or not EJ_SelectEncounter or not C_EncounterJournal then
        print("Where2Go ejtest: Blizzard_EncounterJournal failed to load -- EJ_ globals not available.")
        return
    end

    local source, encounter = FindBossEntry(bossId)
    if not encounter then
        print(string.format("Where2Go ejtest: bossId %d not found in Sources.lua", bossId))
        return
    end

    EJ_SelectInstance(source.instanceId)
    EJ_SelectEncounter(bossId)

    EJ_SetLootFilter(0, 0)
    local unfiltered = CollectCurrentLootItemIds()

    print(string.format("Where2Go ejtest: %s / %s (bossId %d, instanceId %d)",
        source.name, encounter.name, bossId, source.instanceId))
    print("  Sources.lua itemIds  : " .. SetToSortedString(ListToSet(encounter.itemIds)))
    print("  EJ unfiltered itemIds: " .. SetToSortedString(unfiltered))

    local classInfo = C_CreatureInfo.GetClassInfo(classId)
    local className = classInfo and classInfo.className or tostring(classId)
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId) or 0
    local sex = UnitSex("player")

    for i = 1, numSpecs do
        local specId, specName = GetSpecializationInfoForClassID(classId, i, sex)
        if specId then
            EJ_SetLootFilter(classId, specId)
            local filtered = CollectCurrentLootItemIds()
            print(string.format("  [%s / %s] itemIds: %s", className, specName, SetToSortedString(filtered)))
        end
    end

    EJ_SetLootFilter(0, 0)
    print("Where2Go ejtest: done (loot filter reset to unfiltered).")
end
