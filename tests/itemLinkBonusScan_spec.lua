-- Breaks caught: malformed or decorated Encounter Journal links losing their
-- item/bonus data; upgrade-track bonuses leaking into committed static data;
-- nondeterministic aggregation; or a conflicting/missing scan being exported
-- as though it were safe to apply.
dofile("Where2Go/Core/Tracks.lua")
dofile("Where2Go/Core/RaidRanks.lua")
dofile("Where2Go/Core/ItemLinkBonusScan.lua")

local scan = assert(Where2GoItemLinkBonusScan, "item-link bonus scanner should be exported")

local itemId, bonuses = scan.ParseItemLink(
    "|cffa335ee|Hitem:268265:0:0:0:0:0:0:0:0:0:0:0:4:12843:13335:13848:13668|h[Aqirbane Reliquary]|h|r")
assert(itemId == 268265, "should parse the item ID from a decorated full item link")
assert(#bonuses == 4 and bonuses[1] == 12843 and bonuses[4] == 13668,
    "should parse every bonus ID from the item-string bonus segment")

local malformedItemId, malformedBonuses = scan.ParseItemLink("not an item link")
assert(malformedItemId == nil and #malformedBonuses == 0,
    "malformed links must produce no item or bonus IDs")

local stripped = scan.StripTrackBonuses({ 13848, 13668, 12825, 12830, 13335, 12841, 13668 })
assert(#stripped == 2 and stripped[1] == 13668 and stripped[2] == 13335,
    "should remove every configured upgrade-track and Myth-final bonus while preserving first-seen residual order")

local export = scan.BuildExport("Midnight Season 2", {
    { itemId = 200, bonuses = { 13668, 12843, 13335 }, rawLink = "item:200:first" },
    { itemId = 100, bonuses = { 12825, 6652 }, rawLink = "item:100:only" },
    { itemId = 200, bonuses = { 13335, 13668, 12843 }, rawLink = "item:200:second" },
    { itemId = 999, bonuses = { 7777 } },
}, { 300, 200, 100 })
assert(export.schemaVersion == 2 and export.seasonVersion == "Midnight Season 2",
    "should mark the export with the expected schema and season")
assert(export.trackedItemCount == 3 and export.observedItemCount == 2,
    "should count only known tracked items that appeared in the scan")
assert(#export.byItem[100] == 1 and export.byItem[100][1] == 6652,
    "should retain only static residual bonuses for known items")
assert(export.byItem[200] == nil and #export.conflicts[200] == 2,
    "should treat residual lists with different order as a conflict rather than choosing one")
assert(export.conflicts[200][1][1] == 13668 and export.conflicts[200][2][1] == 13335,
    "should preserve each conflicting Encounter Journal residual order")
assert(export.byItem[999] == nil, "untracked item IDs must never enter the export")
assert(#export.rawLinks[100] == 1 and export.rawLinks[100][1] == "item:100:only",
    "should preserve the exact Encounter Journal link for each tracked item")
assert(#export.rawLinks[200] == 2 and export.rawLinks[200][1] == "item:200:first"
    and export.rawLinks[200][2] == "item:200:second",
    "should retain distinct raw links in first-observed order for diagnosis")
assert(#export.missingItems == 1 and export.missingItems[1] == 300,
    "should diagnose each tracked item that was not observed")

local exactDuplicate = scan.BuildExport("Midnight Season 2", {
    { itemId = 100, bonuses = { 12825, 6652, 7777 }, rawLink = "item:100:same" },
    { itemId = 100, bonuses = { 12825, 6652, 7777 }, rawLink = "item:100:same" },
}, { 100 })
assert(#exactDuplicate.byItem[100] == 2 and exactDuplicate.byItem[100][1] == 6652,
    "should collapse only exact duplicate ordered residual lists")
assert(#exactDuplicate.rawLinks[100] == 1,
    "should collapse exact duplicate raw links")

local conflicted = scan.BuildExport("Midnight Season 2", {
    { itemId = 100, bonuses = { 12825, 6652 } },
    { itemId = 100, bonuses = { 12825, 7777 } },
}, { 100 })
assert(conflicted.byItem[100] == nil, "conflicting residual lists must never be chosen silently")
assert(#conflicted.conflicts[100] == 2,
    "should retain every distinct normalized residual list for review")
assert(conflicted.conflicts[100][1][1] == 6652 and conflicted.conflicts[100][2][1] == 7777,
    "should export conflicting alternatives in first-observed encounter order")

local diagnosed = scan.BuildExport("Midnight Season 2", {
    { itemId = 100, bonuses = { 12825, 6652 } },
}, { 300, 200, 100 }, { [100] = true, [200] = true }, { [200] = true })
assert(diagnosed.observedItemCount == 2 and #diagnosed.missingItems == 1 and diagnosed.missingItems[1] == 300,
    "should count item IDs present in EJ separately from truly absent tracked items")
assert(#diagnosed.unresolvedLinkItems == 1 and diagnosed.unresolvedLinkItems[1] == 200,
    "should deterministically diagnose tracked item IDs whose EJ entry lacked a usable full link")

local sequence = {}
local source = {
    instanceId = 77,
    name = "Test source",
    encounters = {
        { bossId = 701, name = "First" },
        { bossId = 702, name = "Second" },
    },
}
scan.ScanSources({ source }, 16, {}, {}, { current = 0, total = 2 }, {
    setDifficulty = function(difficulty) table.insert(sequence, "difficulty:" .. difficulty) end,
    selectInstance = function(instanceId) table.insert(sequence, "instance:" .. instanceId) end,
    selectEncounter = function(bossId) table.insert(sequence, "encounter:" .. bossId) end,
    clearLootFilter = function() table.insert(sequence, "filter") end,
    collect = function() table.insert(sequence, "collect") end,
    notify = function() end,
})
assert(table.concat(sequence, ",") == "difficulty:16,instance:77,encounter:701,filter,collect,encounter:702,filter,collect",
    "should select the difficulty and instance once per source before its encounter loop")

local created = {}
local callbacks = {}
local timeout
local completed = 0
Item = {
    CreateFromItemID = function(_, itemId)
        table.insert(created, itemId)
        return { ContinueOnItemLoad = function(_, callback) table.insert(callbacks, callback) end }
    end,
}
C_Timer = { After = function(_, callback) timeout = callback end }
scan.WarmKnownItemIds({ 200, 100 }, function() completed = completed + 1 end)
callbacks[1]()
timeout()
callbacks[2]()
assert(#created == 2 and completed == 1,
    "should finish item-cache warmup exactly once when its timeout races item-load callbacks")
Item = nil
C_Timer = nil

-- Breaks caught: a synchronous failure while gathering tracked IDs or setting
-- up the item-cache warmup leaves the scan permanently marked as running, or
-- reports the same failed scan more than once.
local savedGlobals = {
    C_AddOns = C_AddOns,
    LoadAddOn = LoadAddOn,
    EJ_SelectInstance = EJ_SelectInstance,
    EJ_SelectEncounter = EJ_SelectEncounter,
    EJ_SetDifficulty = EJ_SetDifficulty,
    EJ_SetLootFilter = EJ_SetLootFilter,
    EJ_GetNumLoot = EJ_GetNumLoot,
    C_EncounterJournal = C_EncounterJournal,
    InCombatLockdown = InCombatLockdown,
    Where2GoDB = Where2GoDB,
    Where2GoConstants = Where2GoConstants,
    Where2GoSources = Where2GoSources,
    geterrorhandler = geterrorhandler,
    Item = Item,
    C_Timer = C_Timer,
}

local function configureStartTest()
    Where2GoSources = {
        DUNGEONS = {
            {
                instanceId = 1,
                name = "Test dungeon",
                encounters = { { bossId = 1, name = "Test boss", itemIds = { 100 } } },
            },
        },
        RAIDS = {},
    }
    Where2GoDB = {}
    Where2GoConstants = { SEASON_LABEL = "Test season" }
    InCombatLockdown = function() return false end
    EJ_SetDifficulty = function() end
    EJ_SelectInstance = function() end
    EJ_SelectEncounter = function() end
    EJ_SetLootFilter = function() end
    EJ_GetNumLoot = function() return 0 end
    C_EncounterJournal = { GetLootInfoByIndex = function() return nil end }
    C_AddOns = nil
    LoadAddOn = nil
end

local function assertSynchronousWarmupFailure(label, configureFailure)
    configureStartTest()
    local errorCount = 0
    local abortCount = 0
    geterrorhandler = function()
        return function() errorCount = errorCount + 1 end
    end
    scan.SetProgressCallback("warmup-error", function(_, _, _, _, reason)
        if reason == "ABORTED_ERROR" then
            abortCount = abortCount + 1
        end
    end)
    configureFailure()

    local ok, reason = scan.Start()
    assert(ok == false and reason == "ERROR", label .. " should fail Start synchronously")
    assert(scan.IsRunning() == false, label .. " should clear the running state")
    assert(errorCount == 1 and abortCount == 1, label .. " should report one abort through each channel")
end

assertSynchronousWarmupFailure("tracked item collection", function()
    Where2GoSources.DUNGEONS = nil
end)

assertSynchronousWarmupFailure("item creation", function()
    Item = { CreateFromItemID = function() error("create failed") end }
    C_Timer = { After = function() end }
end)

assertSynchronousWarmupFailure("item load callback registration", function()
    Item = {
        CreateFromItemID = function()
            return { ContinueOnItemLoad = function() error("continue failed") end }
        end,
    }
    C_Timer = { After = function() end }
end)

assertSynchronousWarmupFailure("warmup timeout scheduling", function()
    Item = {
        CreateFromItemID = function()
            return { ContinueOnItemLoad = function() end }
        end,
    }
    C_Timer = { After = function() error("timer failed") end }
end)

configureStartTest()
local reentrantErrorCount = 0
local reentrantAbortCount = 0
local reentrantCompleteCount = 0
geterrorhandler = function()
    return function() reentrantErrorCount = reentrantErrorCount + 1 end
end
scan.SetProgressCallback("warmup-error", function(_, _, _, _, reason)
    if reason == "ABORTED_ERROR" then
        reentrantAbortCount = reentrantAbortCount + 1
    elseif reason == "COMPLETE" then
        reentrantCompleteCount = reentrantCompleteCount + 1
    end
end)
Item = {
    CreateFromItemID = function()
        return { ContinueOnItemLoad = function(_, callback) callback() end }
    end,
}
C_Timer = { After = function() error("timer failed after synchronous item load") end }
local reentrantOk, reentrantReason = scan.Start()
assert(reentrantOk == false and reentrantReason == "ERROR",
    "a warmup setup error after a synchronous callback should fail Start")
assert(scan.IsRunning() == false and reentrantErrorCount == 1 and reentrantAbortCount == 1
    and reentrantCompleteCount == 0,
    "a warmup setup error after a synchronous callback should abort without completing")

configureStartTest()
local completeCount = 0
local synchronousTimeoutCalls = 0
geterrorhandler = function() return function() error("unexpected scanner error") end end
scan.SetProgressCallback("warmup-error", function(_, _, _, _, reason)
    if reason == "COMPLETE" then
        completeCount = completeCount + 1
    end
end)
Item = {
    CreateFromItemID = function()
        return { ContinueOnItemLoad = function(_, callback) callback() end }
    end,
}
C_Timer = {
    After = function(_, callback)
        synchronousTimeoutCalls = synchronousTimeoutCalls + 1
        callback()
    end,
}
local completedOk, completedReason = scan.Start()
assert(completedOk == true and completedReason == "COMPLETE",
    "synchronous warmup completion should return COMPLETE instead of WARMING")
assert(scan.IsRunning() == false and completeCount == 1 and synchronousTimeoutCalls == 1,
    "synchronous item and timeout completions should emit COMPLETE exactly once")

scan.SetProgressCallback("warmup-error", nil)
for _, name in ipairs({
    "C_AddOns", "LoadAddOn", "EJ_SelectInstance", "EJ_SelectEncounter",
    "EJ_SetDifficulty", "EJ_SetLootFilter", "EJ_GetNumLoot", "C_EncounterJournal",
    "InCombatLockdown", "Where2GoDB", "Where2GoConstants", "Where2GoSources",
    "geterrorhandler", "Item", "C_Timer",
}) do
    _G[name] = savedGlobals[name]
end

print("itemLinkBonusScan_spec: OK")
