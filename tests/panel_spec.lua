local WowUI = dofile("tests/helpers/wow_ui.lua")
local savedGlobals = {}
for key, value in pairs(_G) do savedGlobals[key] = value end

local function run()

local STRINGS = {
    PANEL_TITLE = "Where2Go",
    MODE_DROP = "Drop",
    MODE_VOIDCORE = "Voidcore",
    MANAGE_BUTTON = "Manage items",
    PANEL_SPEC_CONTEXT = "Ranking for: %s",
    PANEL_COUNT_SUMMARY = "%d preferred items · %d destinations",
    PANEL_CARD_COUNTS = "%d targets / %d eligible items",
    PANEL_NO_PREFERRED = "Choose the items you want to see where to go next.",
    PANEL_NO_MATCHES = "No matching targets for your current specialization.",
    NO_SPEC_SELECTED = "Where2Go: no specialization selected.",
}

local function result(id, name, targets, eligible)
    return {
        id = id,
        name = name,
        raidName = nil,
        targetItemIds = targets,
        targetCount = #targets,
        eligibleCount = eligible,
        ilvl = 250,
        trackKey = "HERO",
        trackRank = 2,
        bonusId = 9001,
    }
end

local function newScenario(options)
    options = options or {}
    local env = WowUI.New()
    env:InstallGlobals()

    Where2GoPanel = nil
    Where2GoCharDB = options.charDB or {
        preferredItems = { DROP = { [101] = true }, VOIDCORE = {} },
        preferredItemSources = { DROP = {}, VOIDCORE = {} },
        voidcoreObtainedItems = {},
    }
    Where2GoConstants = { ADDON_NAME = "Where2Go" }
    GetLocale = nil
    dofile("Where2Go/Core/Locale.lua")
    dofile("Where2Go/Core/Preferences.lua")

    local directResults = options.directResults or {
        result("dungeon:1", "Ruby Halls", { 101 }, 5),
        result("dungeon:2", "Azure Vault", {}, 4),
    }
    local directSpec = options.directSpec or "Restoration"
    local voidResults = options.voidResults or {}
    local voidSpec = options.voidSpec or "Restoration"
    local rankCalls = { DROP = 0, VOIDCORE = 0 }

    Where2GoDirectDrop = {
        GetRankedResults = function()
            rankCalls.DROP = rankCalls.DROP + 1
            return directResults, directSpec
        end,
    }
    Where2GoVoidcoreDrop = {
        GetRankedResults = function()
            rankCalls.VOIDCORE = rankCalls.VOIDCORE + 1
            return voidResults, voidSpec
        end,
    }

    dofile("Where2Go/UI/Theme.lua")
    Where2GoSources = { DUNGEONS = {}, RAIDS = {} }
    Where2GoTracks = { UPGRADE_TRACKS = {} }
    Where2GoRaidRanks = { MYTH_FINAL_BONUS_ID = 9999 }
    Where2GoItemStats = { STATS = {} }
    C_Item = {
        GetItemInfo = function(itemId)
            return "Item " .. itemId, nil, 1
        end,
        GetItemIconByID = function()
            return "Interface\\Icons\\INV_Misc_QuestionMark"
        end,
    }
    ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
    dofile("Where2Go/UI/ItemRow.lua")

    local browserShows = {}
    Where2GoBrowserPanel = {
        Show = function(mode)
            table.insert(browserShows, mode)
        end,
    }

    if options.pveFrame then
        PVEFrame = env:CreateFrame("Frame", "PVEFrame", UIParent)
        if options.pveShown == false then
            PVEFrame:Hide()
        end
    else
        PVEFrame = nil
    end

    dofile("Where2Go/UI/Panel.lua")

    return {
        env = env,
        subscriptions = {
            panel = function(mode)
                Where2GoPreferences.Notify(mode)
            end,
        },
        browserShows = browserShows,
        rankCalls = rankCalls,
        setDirectResults = function(results, specName)
            directResults = results
            directSpec = specName
        end,
        setVoidResults = function(results, specName)
            voidResults = results
            voidSpec = specName
        end,
    }
end

-- Break caught: binding only at file load misses Blizzard's later-created PVEFrame,
-- or SetScript replaces Blizzard's own finder lifecycle handler.
do
    local scenario = newScenario()
    local env = scenario.env
    PVEFrame = env:CreateFrame("Frame", "PVEFrame", UIParent)
    PVEFrame:Hide()
    local blizzardShows, blizzardHides = 0, 0
    PVEFrame:SetScript("OnShow", function() blizzardShows = blizzardShows + 1 end)
    PVEFrame:SetScript("OnHide", function() blizzardHides = blizzardHides + 1 end)

    env:FireEvent("ADDON_LOADED", "Blizzard_GroupFinder")
    PVEFrame:Show()

    local panel = env:GetFrame("Where2GoPanel")
    assert(panel and panel:IsShown(), "late PVEFrame show should automatically show the recommendation panel")
    assert(blizzardShows == 1, "panel integration must preserve Blizzard's existing OnShow script")
    assert(panel.parent == UIParent and panel.clampedToScreen == true,
        "panel should be parented to UIParent and clamped to the screen")
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == PVEFrame and anchor[3] == "TOPRIGHT",
        "panel should anchor its left edge beside PVEFrame's right edge")

    PVEFrame:Hide()
    assert(not panel:IsShown(), "finder hide should hide the recommendation panel")
    assert(blizzardHides == 1, "panel integration must preserve Blizzard's existing OnHide script")

    env:FireEvent("PLAYER_LOGIN")
    PVEFrame:Show()
    assert(blizzardShows == 2, "rebinding checks must not duplicate PVEFrame hooks")
end

-- Break caught: collapse state is stored account-wide/in memory only, or body
-- visibility and fixed expanded viewport are lost after refresh.
do
    local scenario = newScenario({
        pveFrame = true,
        pveShown = true,
        charDB = {
            preferredItems = { DROP = { [101] = true }, VOIDCORE = {} },
            preferredItemSources = { DROP = {}, VOIDCORE = {} },
            voidcoreObtainedItems = {},
            ui = { panelCollapsed = true },
        },
    })
    scenario.env:FireEvent("PLAYER_LOGIN")
    local panel = scenario.env:GetFrame("Where2GoPanel")
    local body = scenario.env:GetFrame("Where2GoPanelBody")
    assert(panel:IsShown() and not body:IsShown(), "persisted collapse should show only the title strip")
    local collapsedHeight = panel:GetHeight()

    scenario.env:Click(panel.collapseButton)
    assert(Where2GoCharDB.ui.panelCollapsed == false, "collapse button should persist expansion per character")
    assert(body:IsShown() and panel:GetHeight() > collapsedHeight,
        "expanding should restore the bounded recommendation viewport")
    local expandedHeight = panel:GetHeight()

    Where2GoPanel.Refresh()
    assert(panel:GetHeight() == expandedHeight and body:IsShown(),
        "content refresh should preserve whole-panel expansion and viewport height")
end

-- Break caught: refresh destroys and reallocates all cards/rows, resets a card's
-- expansion, or hides the panel when preferences change outside this window.
do
    local scenario = newScenario({
        pveFrame = true,
        pveShown = false,
        charDB = {
            preferredItems = { DROP = { [101] = true, [102] = true }, VOIDCORE = {} },
            preferredItemSources = { DROP = {}, VOIDCORE = {} },
            voidcoreObtainedItems = {},
        },
        directResults = {
            result("dungeon:1", "Ruby Halls", { 101 }, 5),
            result("dungeon:2", "Azure Vault", { 102 }, 4),
        },
    })
    PVEFrame:Show()
    local env = scenario.env
    local panel = env:GetFrame("Where2GoPanel")
    local firstCard = env:GetFrame("Where2GoPanelCard1")
    assert(firstCard and firstCard:IsShown(), "matching ranked content should render a visible card")
    assert(firstCard:GetHeight() > 42, "recommendation cards should initially be expanded")
    assert(firstCard.nameText:GetText() == "Ruby Halls",
        "the first card header line should clearly identify its content")
    assert(firstCard.countsText:GetText():match("1 targets / 5 eligible items"),
        "the second card header line should separately explain target and eligible-pool counts")
    assert(panel.specText:GetText() == "Ranking for: Restoration",
        "the panel should state the active specialization used for ranking")
    local firstRow = env:GetFrame("Where2GoPanelCard1Row1")
    assert(firstRow.name:GetWidth() > 0 and firstRow.name:GetWidth() <= firstRow:GetWidth() - 28
            and firstRow.summary:GetWidth() <= firstRow:GetWidth() - 28,
        "panel item rows should bound long item names and summaries to the card width")

    env:Click("Where2GoPanelCard1Header")
    local collapsedCardHeight = firstCard:GetHeight()
    local viewportHeight = env:GetFrame("Where2GoPanelScrollFrame"):GetHeight()
    local warmedFrameCount = env:CountFrames()

    scenario.setDirectResults({
        result("dungeon:2", "Azure Vault", { 102 }, 4),
        result("dungeon:1", "Ruby Halls", { 101 }, 5),
    }, "Restoration")
    scenario.subscriptions.panel("DROP")
    assert(panel:IsShown(), "external preference refresh should not hide an open panel")
    assert(env:GetFrame("Where2GoPanelCard1") == firstCard,
        "refresh should reuse the existing card pool")
    assert(firstCard:GetHeight() > collapsedCardHeight
            and env:GetFrame("Where2GoPanelCard2"):GetHeight() == collapsedCardHeight,
        "refresh should preserve expansion by content ID when ranking order changes")
    assert(env:GetFrame("Where2GoPanelScrollFrame"):GetHeight() == viewportHeight,
        "card expansion and refresh should not grow the bounded viewport")

    scenario.subscriptions.panel("DROP")
    assert(env:CountFrames() == warmedFrameCount,
        "repeated refresh with the same content should not allocate additional frames")
end

-- Break caught: mode changes route management to the wrong list, or a preference
-- update for the inactive mode causes unnecessary ranking work.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    PVEFrame:Show()
    local dropCalls = scenario.rankCalls.DROP
    Where2GoPanel.SetMode("VOIDCORE")
    scenario.env:Click(scenario.env:GetFrame("Where2GoPanel").manageButton)
    assert(scenario.browserShows[1] == "VOIDCORE", "Manage should open the browser in the panel's current mode")

    local voidCalls = scenario.rankCalls.VOIDCORE
    scenario.subscriptions.panel("DROP")
    assert(scenario.rankCalls.VOIDCORE == voidCalls,
        "inactive-mode preference notifications should not refresh the current ranking")
    assert(scenario.rankCalls.DROP == dropCalls, "SetMode should not refresh the old mode")

    scenario.subscriptions.panel("VOIDCORE")
    assert(scenario.rankCalls.VOIDCORE == voidCalls + 1,
        "active-mode preference notifications should refresh the current ranking")
end

-- Break caught: nil/empty data leaves stale cards or merges all empty conditions
-- into one misleading explanation.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    PVEFrame:Show()
    local env = scenario.env
    assert(env:GetFrame("Where2GoPanelCard1"):IsShown(), "fixture should begin with one recommendation")

    scenario.setDirectResults(nil, "unsupported_spec")
    env:GetFrame("Where2GoPanelScrollFrame"):SetVerticalScroll(500)
    Where2GoPanel.Refresh()
    assert(not env:GetFrame("Where2GoPanelCard1"):IsShown(), "no-spec refresh should hide stale recommendation cards")
    assert(env:GetFrame("Where2GoPanel").emptyText:GetText() == STRINGS.NO_SPEC_SELECTED,
        "missing specialization should explain why ranking is unavailable")
    assert(env:GetFrame("Where2GoPanel").specText:GetText() == "",
        "a failure reason is not a specialization name")
    assert(env:GetFrame("Where2GoPanelScrollFrame"):GetVerticalScroll() == 0,
        "empty-state guidance must remain visible after a long list shrinks")

    Where2GoCharDB.preferredItems.DROP = {}
    scenario.setDirectResults({}, "Restoration")
    Where2GoPanel.Refresh()
    assert(env:GetFrame("Where2GoPanel").emptyText:GetText() == STRINGS.PANEL_NO_PREFERRED,
        "an empty preferred list should invite the player to manage preferences")

    Where2GoCharDB.preferredItems.DROP = { [999] = true }
    scenario.setDirectResults({ result("dungeon:9", "No Target Place", {}, 6) }, "Restoration")
    Where2GoPanel.Refresh()
    assert(env:GetFrame("Where2GoPanel").emptyText:GetText() == STRINGS.PANEL_NO_MATCHES,
        "preferred items with no eligible source should have a distinct no-match explanation")
end

-- Break caught: changing active spec or receiving item cache data leaves stale
-- recommendation names/counts until the panel is manually reopened.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    PVEFrame:Show()
    local initialCalls = scenario.rankCalls.DROP
    scenario.env:FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    scenario.env:FireEvent("GET_ITEM_INFO_RECEIVED", 101, true)
    assert(scenario.rankCalls.DROP == initialCalls + 2,
        "spec and item-cache events should each refresh the visible panel")
end

end
local ok, err = pcall(run)
for key in pairs(_G) do if savedGlobals[key] == nil then _G[key] = nil end end
for key, value in pairs(savedGlobals) do _G[key] = value end
assert(ok, err)
print("panel_spec: OK")
