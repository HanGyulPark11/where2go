-- Exercise real selection, saved-variable transactions, filters and UI handlers.
-- Only the external WoW boundary is replaced; expected item sets are literal.
local WowUI = dofile("tests/helpers/wow_ui.lua")
local env = WowUI.New()
local saved = {}
for key, value in pairs(_G) do saved[key] = value end
env:InstallGlobals()

local function run()
    StaticPopupDialogs, UISpecialFrames = {}, {}
    GetLocale = function() return "enUS" end
    GetNumSpecializations = function() return 1 end
    GetSpecialization = function() return 1 end
    GetSpecializationInfo = function() return 71, "Arms" end
    local cold = true
    C_Item = {
        GetItemInfo = function(id)
            if id == 15 and cold then return nil end
            return string.format("Gear %02d", id), nil, 4
        end,
        GetItemInfoInstant = function(id) return id, nil, nil, "INVTYPE_HEAD" end,
        GetItemIconByID = function() return 134400 end,
        RequestLoadItemDataByID = function() end,
        IsEquippableItem = function() return true end,
        GetItemSpecInfo = function() return { 71 } end,
        GetDetailedItemLevelInfo = function() return nil end,
    }
    C_Container = {
        GetContainerNumSlots = function() return 0 end,
        GetContainerItemInfo = function() return nil end,
    }
    GetInventoryItemID = function() return nil end
    GetInventoryItemLink = function() return nil end
    ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }
    local popup
    StaticPopup_Show = function(key, _, _, data) popup = { key = key, data = data } end
    Where2GoCharDB = {
        voidcoreObtainedItems = {},
        preferredItems = { DROP = { [2] = true }, VOIDCORE = { [14] = true } },
        preferredItemSources = { DROP = { [2] = 12843 }, VOIDCORE = { [14] = 13848 } },
    }
    dofile("Where2Go/Core/Constants.lua")
    dofile("Where2Go/Core/Tracks.lua")
    dofile("Where2Go/Core/Equipment.lua")
    dofile("Where2Go/Core/Locale.lua")
    dofile("Where2Go/Core/Selection.lua")
    dofile("Where2Go/Core/Preferences.lua")
    dofile("Where2Go/Core/ItemBrowser.lua")
    dofile("Where2Go/Core/DirectDrop.lua")
    Where2GoSpecEligibilityData = { BY_SPEC = { [71] = {} } }
    local ids = {}
    Where2GoItemStats = { STATS = {} }
    for id = 1, 15 do
        ids[#ids + 1] = id
        Where2GoSpecEligibilityData.BY_SPEC[71][id] = true
        Where2GoItemStats.STATS[id] = { secondaryStats = id == 3 and {}
            or (id == 1 and { "HASTE_RATING", "CRIT_RATING" } or { "HASTE_RATING" }) }
    end
    Where2GoSources = { DUNGEONS = {
        { instanceId = 1, name = "Voidscar Arena", encounters = {
            { bossId = 1, name = "Taz'Rah", itemIds = ids },
            { bossId = 2, name = "Atroxus", itemIds = { 1 } },
        } },
    }, RAIDS = {} }
    Where2GoRaidRanks = {
        MYTH_FINAL_BONUS_ID = 13848,
        MYTH_FINAL_ILVL = 344,
        MYTH_FINAL_RANK = 9,
        GetMythicPlusIlvl = function() return 311, "HERO", 3, 12843 end,
    }
    dofile("Where2Go/UI/Theme.lua")
    dofile("Where2Go/Core/ItemLinkBonuses.lua")
    dofile("Where2Go/UI/ItemRow.lua")
    dofile("Where2Go/UI/BrowserPanel.lua")
    assert(type(Where2GoBrowserPanel.Show) == "function", "management must show rather than toggle")
    Where2GoBrowserPanel.Show("DROP")
    local browser = assert(env:GetFrame("Where2GoBrowser"))
    assert(browser.modeButtons.DROP:GetText() == "Drop", "new action buttons must initialize their button text")
    local function preferredRow(id)
        for _, candidate in ipairs(env.frames) do
            if rawget(candidate, "parent") == browser.preferredList and rawget(candidate, "itemId") == id then return candidate end
        end
        error("visible preferred row missing: " .. id)
    end
    local function resultRow(id)
        for _, candidate in ipairs(env.frames) do
            local entry = rawget(candidate, "entry")
            if rawget(candidate, "parent") == browser.resultList and entry and entry.itemId == id then return candidate end
        end
        error("visible result missing: " .. id)
    end
    assert(resultRow(1).summary:GetText() == "Head · 311 · Haste/Crit",
        "browser result rows must show localized slot, item level, and all fixed secondary stats in data order")
    assert(resultRow(3).summary:GetText() == "Head · 311",
        "browser result rows must omit the secondary-stat segment when none are fixed")
    assert(preferredRow(2).summary:GetText() == "Head · 311 · Haste",
        "preferred rows must recover item level from their stored track bonus")
    GameTooltip = {
        lines = {},
        SetOwner = function() end,
        SetHyperlink = function(self, link) self.link = link; self.lines = {} end,
        SetItemByID = function() end,
        AddLine = function(self, text) table.insert(self.lines, text) end,
        Show = function() end,
        Hide = function() end,
    }
    C_TooltipInfo = { GetHyperlink = function()
        return { lines = { { leftText = "Item Level 311" }, { leftText = "Hero 3/6" } } }
    end }
    strsplit = function(separator, value)
        local fields = {}
        for field in (value .. separator):gmatch("(.-)" .. separator) do table.insert(fields, field) end
        return unpack(fields)
    end
    env:RunScript(resultRow(1), "OnEnter")
    assert(GameTooltip.link == "item:1:0:0:0:0:0:0:0:0:0:0:0:1:12843",
        "browser result hovers must use their calculated track-only synthetic link")
    GetLocale = function() return "koKR" end
    dofile("Where2Go/Core/Locale.lua")
    Where2GoBrowserPanel.Show("DROP")
    env:RunScript(resultRow(1), "OnEnter")
    assert(GameTooltip.lines[#GameTooltip.lines] == "공허흉터 투기장",
        "browser result hovers should localize addon-owned dungeon source names on koKR clients")
    GetLocale = function() return "enUS" end
    dofile("Where2Go/Core/Locale.lua")
    dofile("Where2Go/Core/Ranking.lua")
    local snapshotCalls = 0
    local actualHasOwnedAtLeast = Where2GoEquipment.HasOwnedAtLeast
    Where2GoEquipment.GetOwnedSnapshot = function()
        snapshotCalls = snapshotCalls + 1
        return {}
    end
    Where2GoEquipment.HasOwnedAtLeast = function(_, itemId)
        return itemId == 2
    end
    local ownedResults = Where2GoDirectDrop.GetRankedResults()
    assert(snapshotCalls == 1, "direct ranking snapshots owned inventory once per result calculation")
    assert(ownedResults[1].eligibleCount == 15 and ownedResults[1].targetCount == 0,
        "owned preferred items leave the eligible denominator unchanged")
    Where2GoEquipment.HasOwnedAtLeast = actualHasOwnedAtLeast
    Where2GoEquipment.SetOwnershipMode("SLOT")
    Where2GoEquipment.GetOwnedSnapshot = function()
        return { [16] = { { itemId = 16, ilvl = 318, track = { order = 3 } } } }
    end
    local olderGearResults = Where2GoDirectDrop.GetRankedResults()
    assert(olderGearResults[1].eligibleCount == 15 and olderGearResults[1].targetCount == 0,
        "usable older gear outside the season eligibility table suppresses a same-slot target")
    dofile("Where2Go/Core/VoidcoreDrop.lua")
    Where2GoCharDB.voidcoreObtainedItems[1] = true
    local voidcoreOwnedResults = Where2GoVoidcoreDrop.GetRankedResults()
    assert(voidcoreOwnedResults[1].eligibleCount == 14 and voidcoreOwnedResults[1].targetCount == 0,
        "Voidcore keeps obtained exclusions in its denominator while ownership removes only targets")
    Where2GoCharDB.voidcoreObtainedItems[1] = nil
    Where2GoEquipment.GetOwnedSnapshot = function() return {} end
    Where2GoEquipment.SetOwnershipMode("ITEM")
    PVEFrame = env:CreateFrame("Frame", "PVEFrame", UIParent)
    PVEFrame:Hide()
    dofile("Where2Go/UI/Panel.lua")
    PVEFrame:Show()
    local recommendation = env:GetFrame("Where2GoPanelCard1")
    assert(recommendation.countsText:GetText() == "1 targets / 15 eligible items", "real ranking starts from the saved list")
    local function savedCount(mode)
        local n = 0
        for _, value in pairs(Where2GoCharDB.preferredItems[mode]) do if value then n = n + 1 end end
        return n
    end
    assert(browser:IsShown() and browser.resultTitle:GetText() == "Items · 15", "deduplicate multiple sources")
    assert(not resultRow(2).add:IsEnabled() and not resultRow(2).checkbox:IsEnabled(), "saved rows cannot be re-added")
    env:Click(browser.selectAll)
    assert(browser.selectAll:GetChecked(), "all unsaved results selected, including offscreen")
    env:Click(resultRow(3).checkbox)
    assert(browser.selectAll.partial:IsShown(), "exceptions must show partial selection")
    env:RunScript(browser.resultList, "OnMouseWheel", -2)
    env:Click(resultRow(13).checkbox)
    cold = false
    env:FireEvent("GET_ITEM_INFO_RECEIVED", 15, true)
    assert(browser.addSelected:GetText() == "Add selected · 12", "loading and scrolling must retain two exceptions")
    env:Click(browser.addSelected)
    assert(savedCount("DROP") == 13, "batch must add offscreen selections exactly once")
    assert(not Where2GoCharDB.preferredItems.DROP[3] and not Where2GoCharDB.preferredItems.DROP[13], "excluded items must stay absent")
    assert(Where2GoCharDB.preferredItems.DROP[15], "offscreen last result must be added")
    assert(Where2GoCharDB.preferredItemSources.DROP[2] == 12843, "existing source must survive bulk add")
    assert(recommendation.countsText:GetText() == "13 targets / 15 eligible items", "batch changes must immediately update the open recommendation panel")
    env:Click(browser.undo)
    assert(savedCount("DROP") == 1 and Where2GoCharDB.preferredItems.DROP[2], "undo only this batch")
    assert(recommendation.countsText:GetText() == "1 targets / 15 eligible items", "undo must immediately restore recommendation counts")
    browser.search:SetText("Gear 01")
    env:Click(resultRow(1).add)
    assert(savedCount("DROP") == 2 and Where2GoCharDB.preferredItems.DROP[1], "single add commits immediately")
    env:Click(browser.undo)
    assert(not Where2GoCharDB.preferredItems.DROP[1], "single add is undoable")
    browser.search:SetText("Gear")
    env:Click(browser.selectAll)
    browser.search:SetText("Gear 03")
    assert(not browser.addSelected:IsEnabled(), "filter changes clear hidden selections")
    assert(browser.preferredTitle:GetText() == "Preferred · 1", "preferred list ignores search filter")
    env:Click(browser.selectAll)
    env:Click(browser.modeButtons.VOIDCORE)
    assert(not browser.addSelected:IsEnabled(), "mode change clears transient selection")
    assert(preferredRow(14).summary:GetText() == "Head · 344 · Haste",
        "preferred rows must recover the special Myth 9/6 item level from the stored bonus")
    env:Click(resultRow(3).add)
    assert(Where2GoCharDB.preferredItems.VOIDCORE[3] and not Where2GoCharDB.preferredItems.DROP[3], "mode lists stay independent")
    env:Click(browser.modeButtons.DROP)
    env:Click(browser.clearPreferred)
    env:Click(browser.modeButtons.VOIDCORE)
    StaticPopupDialogs[popup.key].OnAccept({}, popup.data)
    assert(savedCount("DROP") == 0 and savedCount("VOIDCORE") == 2, "clear confirmation retains its original mode")
    env:Click(browser.modeButtons.DROP)
    env:Click(browser.undo)
    assert(Where2GoCharDB.preferredItems.DROP[2], "clear-all restores original list")
    env:Click(browser.resetFilters)
    assert(browser.resultTitle:GetText() == "Items · 15", "reset restores the full pool")
    local framesBefore = env:CountFrames()
    for _ = 1, 30 do Where2GoBrowserPanel.Show("DROP") end
    assert(browser:IsShown() and env:CountFrames() == framesBefore, "reopening must reuse rows and stay open")
    browser.search:SetText("not present")
    assert(browser.resultEmpty:IsShown() and not browser.selectAll:IsEnabled(), "empty results are explained and cannot be selected")
    PVEFrame:Hide()
    assert(browser:IsShown(), "closing the finder must not hide independent item management")
end

local ok, err = pcall(run)
for key in pairs(_G) do if saved[key] == nil then _G[key] = nil end end
for key, value in pairs(saved) do _G[key] = value end
assert(ok, err)
print("browserpanel_spec: OK")
