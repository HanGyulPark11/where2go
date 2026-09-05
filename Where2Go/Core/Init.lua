local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, _event, loadedAddonName)
    if loadedAddonName ~= Where2GoConstants.ADDON_NAME then
        return
    end

    Where2GoDB = Where2GoDB or Where2GoConstants.BuildDefaultAccountDB()
    Where2GoCharDB = Where2GoCharDB or Where2GoConstants.BuildDefaultCharDB()

    Where2GoCharDB.preferredItems = Where2GoCharDB.preferredItems or {}
    Where2GoCharDB.preferredItems.DROP = Where2GoCharDB.preferredItems.DROP or {}
    Where2GoCharDB.preferredItems.VOIDCORE = Where2GoCharDB.preferredItems.VOIDCORE or {}
    Where2GoCharDB.preferredItemSources = Where2GoCharDB.preferredItemSources or {}
    Where2GoCharDB.preferredItemSources.DROP = Where2GoCharDB.preferredItemSources.DROP or {}
    Where2GoCharDB.preferredItemSources.VOIDCORE = Where2GoCharDB.preferredItemSources.VOIDCORE or {}
    Where2GoCharDB.voidcoreObtainedItems = Where2GoCharDB.voidcoreObtainedItems or {}

    self:UnregisterEvent("ADDON_LOADED")
end)

local function SplitArgs(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    return args
end

local function NormalizePurpose(raw)
    if not raw then
        return nil
    end
    local upper = raw:upper()
    if upper == "DROP" or upper == "VOIDCORE" then
        return upper
    end
    return nil
end

local function HandlePrefCommand(args)
    local action = args[2]
    if action == "add" or action == "remove" then
        local itemId = tonumber(args[3])
        local purpose = NormalizePurpose(args[4])
        if not itemId or itemId % 1 ~= 0 or itemId <= 0 or not purpose then
            print("Usage: /where2go pref add|remove <itemID> <drop|voidcore>")
            return
        end
        if action == "add" then
            Where2GoCharDB.preferredItems[purpose][itemId] = true
            print(string.format("Where2Go: added item %d to %s preferred items.", itemId, purpose))
        else
            Where2GoCharDB.preferredItems[purpose][itemId] = nil
            Where2GoCharDB.preferredItemSources[purpose][itemId] = nil
            print(string.format("Where2Go: removed item %d from %s preferred items.", itemId, purpose))
        end
    elseif action == "list" then
        local purpose = NormalizePurpose(args[3])
        if not purpose then
            print("Usage: /where2go pref list <drop|voidcore>")
            return
        end
        local ids = {}
        for itemId in pairs(Where2GoCharDB.preferredItems[purpose]) do
            table.insert(ids, itemId)
        end
        table.sort(ids)
        print(string.format("Where2Go: %s preferred items: %s", purpose,
            #ids > 0 and table.concat(ids, ", ") or "(none)"))
    else
        print("Usage: /where2go pref add|remove|list ...")
    end
end

local function DescribeCandidate(candidateInfo, equipped)
    local isBetter = Where2GoCompare.IsBetterCandidate(candidateInfo, equipped)
    local function describeSide(info)
        if not info.ilvl then
            return "(empty)"
        end
        if info.track then
            return string.format("ilvl %d (%s %d/6)", info.ilvl, info.track.label, info.track.rank)
        end
        return string.format("ilvl %d (no recognized track)", info.ilvl)
    end
    return string.format("%s vs equipped %s -> %s",
        describeSide(candidateInfo), describeSide(equipped), isBetter and "UPGRADE" or "not an upgrade")
end

local function HandleCompareCommand()
    local anyFound = false
    for _, purpose in ipairs({ "DROP", "VOIDCORE" }) do
        for itemId in pairs(Where2GoCharDB.preferredItems[purpose]) do
            local link = Where2GoEquipment.FindItemLink(itemId)
            if link then
                anyFound = true
                local candidateInfo = { ilvl = C_Item.GetDetailedItemLevelInfo(link), track = Where2GoEquipment.GetTrackInfo(link) }
                local slotId = Where2GoEquipment.GetNormalizedSlot(itemId)
                local equipped = slotId and Where2GoEquipment.GetWeakestEquipped(slotId) or { itemId = nil, ilvl = nil, track = nil }
                print(string.format("Where2Go [%s] %s: %s", purpose, link, DescribeCandidate(candidateInfo, equipped)))
            end
        end
    end
    if not anyFound then
        print("Where2Go: no preferred items found in bags or equipped.")
    end
end

local _lastGenspecSpecName

local function HandleGenspecProgress(specName, _current, _total, finishedReason)
    if finishedReason then
        _lastGenspecSpecName = nil
        if finishedReason == "COMPLETE" then
            print("Where2Go: genspec scan complete -- log out to flush SavedVariables, then hand-merge Where2GoDB.specEligibilityExport into Core/SpecEligibilityData.lua.")
        elseif finishedReason == "ABORTED_ERROR" then
            print("Where2Go: genspec scan aborted due to an error -- see the error log.")
        end
        return
    end
    if specName ~= _lastGenspecSpecName then
        _lastGenspecSpecName = specName
        print(string.format("Where2Go: genspec scanning %s...", specName or "?"))
    end
end

local function HandleGenspecCommand(args)
    local action = args[2]

    if action == "reset" then
        if not Where2GoDB.specEligibilityExport then
            print("Where2Go: no genspec export data to reset.")
            return
        end
        Where2GoDB.specEligibilityExport = nil
        print("Where2Go: genspec export data cleared.")
        return
    end

    if action then
        print("Usage: /where2go genspec [reset]")
        return
    end

    print("Where2Go: scanning every class/spec in the game via the Encounter Journal -- this does not change your loot specialization and should finish quickly.")

    Where2GoSpecEligibilityScan.SetProgressCallback("genspec", HandleGenspecProgress)
    local ok, reason = Where2GoSpecEligibilityScan.Start()
    if ok then
        return
    end

    if reason == "STALE_SEASON" then
        print(string.format(
            "Where2Go: existing export data is from a previous season (%s) -- run '/where2go genspec reset' first, or it will be merged with the new season's data.",
            Where2GoDB.specEligibilityExport.seasonVersion))
    elseif reason == "RUNNING" then
        print("Where2Go: a genspec scan is already running.")
    elseif reason == "COMBAT" then
        print("Where2Go: cannot start a genspec scan while in combat.")
    elseif reason == "EJ_LOAD_FAILED" then
        print("Where2Go: genspec could not load the Blizzard_EncounterJournal addon -- try opening the in-game Dungeon Journal (default key: Shift+J) once, then run this again.")
    elseif reason == "ERROR" then
        print("Where2Go: genspec scan aborted due to an error -- see the error log.")
    end
end

SLASH_WHERE2GO1 = "/where2go"
SLASH_WHERE2GO2 = "/w2g"
SlashCmdList["WHERE2GO"] = function(msg)
    local args = SplitArgs(msg)
    local subcommand = args[1]
    if subcommand == "pref" then
        HandlePrefCommand(args)
    elseif subcommand == "compare" then
        HandleCompareCommand()
    elseif subcommand == "browse" then
        Where2GoBrowserPanel.Toggle()
    elseif subcommand == "genspec" then
        HandleGenspecCommand(args)
    elseif not subcommand or subcommand == "" then
        Where2Go_TogglePanel()
    else
        print("Where2Go: unknown command. Usage: /where2go, /where2go pref add|remove|list ..., /where2go compare, /where2go browse, /where2go genspec [reset]")
    end
end
