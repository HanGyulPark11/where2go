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
    PANEL_OWNERSHIP_ITEM = "Exclude: Same item",
    PANEL_OWNERSHIP_SLOT = "Exclude: Slot",
    PANEL_OWNERSHIP_HELP = "Exclude preferred gear you already own in equipped slots or regular bags. Same item compares its upgrade track first, then item level; Slot applies this to any item in the same slot.",
    PANEL_NO_PREFERRED = "Choose the items you want to see where to go next.",
    PANEL_NO_MATCHES = "No matching targets remain after specialization and owned-gear filtering.",
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
    RaiderIO_ProfileTooltip = nil
    Where2GoCharDB = options.charDB or {
        preferredItems = { DROP = { [101] = true }, VOIDCORE = {} },
        preferredItemSources = { DROP = {}, VOIDCORE = {} },
        voidcoreObtainedItems = {},
    }
    Where2GoConstants = { ADDON_NAME = "Where2Go", EQUIPLOC_TO_SLOT = { INVTYPE_HEAD = "HEAD" } }
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

    local ownershipMode = options.ownershipMode or "ITEM"
    local ownershipModeChanges = {}
    Where2GoEquipment = {
        GetOwnershipMode = function()
            return ownershipMode
        end,
        SetOwnershipMode = function(mode)
            ownershipMode = mode
            table.insert(ownershipModeChanges, mode)
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
        GetItemInfoInstant = function(itemId)
            return itemId, nil, nil, "INVTYPE_HEAD"
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
        ownershipModeChanges = ownershipModeChanges,
        getOwnershipMode = function()
            return ownershipMode
        end,
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

-- Break caught: hovering a row can mutate Encounter Journal selection, ordinary
-- item links can inherit effect bonuses, static effect variants can omit or
-- reorder their bonuses, or a pooled hovered row can retain its old tooltip.
do
    local env = WowUI.New()
    env:InstallGlobals()
    Where2GoTheme = { colors = { hover = { 1, 1, 1 }, muted = { 1, 1, 1 } } }
    Where2GoLocale = {
        SlotLabel = function(slot) return slot end,
        StatAbbrev = function(stat) return stat end,
        TrackLabel = function(trackKey)
            return ({ MYTH = "Myth", HERO = "Hero", CHAMPION = "Champion" })[trackKey] or trackKey
        end,
    }
    Where2GoConstants = { EQUIPLOC_TO_SLOT = { INVTYPE_HEAD = "HEAD" } }
    Where2GoItemStats = { STATS = {} }
    Where2GoTracks = { UPGRADE_TRACKS = {
        CHAMPION = { bonusIdStart = 12833 },
        HERO = { bonusIdStart = 12841 },
        MYTH = { bonusIdStart = 12849, ilvls = { 318, 321, 324, 328, 331, 334 } },
    } }
    Where2GoRaidRanks = { MYTH_FINAL_BONUS_ID = 13848, MYTH_FINAL_ILVL = 344, MYTH_FINAL_RANK = 9 }
    C_Item = {
        GetItemInfo = function(itemId) return "Item " .. itemId, nil, 1 end,
        GetItemInfoInstant = function(itemId) return itemId, nil, nil, "INVTYPE_HEAD" end,
        GetItemIconByID = function() return 1 end,
    }
    ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" } }
    strsplit = function(separator, value)
        local fields = {}
        for field in (value .. separator):gmatch("(.-)" .. separator) do
            table.insert(fields, field)
        end
        return unpack(fields)
    end
    GameTooltip = {
        SetOwner = function() end,
        SetHyperlink = function(self, link) self.link = link end,
        SetItemByID = function() end,
        AddLine = function() end,
        Show = function() end,
        Hide = function() end,
    }

    local function forbiddenEJCall()
        error("ItemRow must never call Encounter Journal APIs")
    end
    EJ_SetDifficulty = forbiddenEJCall
    EJ_SelectInstance = forbiddenEJCall
    EJ_SelectEncounter = forbiddenEJCall
    EJ_SetLootFilter = forbiddenEJCall
    EJ_GetNumLoot = forbiddenEJCall
    C_EncounterJournal = { GetLootInfoByIndex = forbiddenEJCall }
    C_AddOns = { LoadAddOn = forbiddenEJCall }
    LoadAddOn = forbiddenEJCall

    dofile("Where2Go/Core/ItemLinkBonuses.lua")
    Where2GoItemLinkBonuses.TEMPLATES = {}
    for _, itemId in ipairs({ 270164, 268258, 268253, 268265, 271876 }) do
        Where2GoItemLinkBonuses.TEMPLATES[itemId] = string.format(
            "item:%d:0:0:0:0:0:0:0:0:0:0:6:1:3524:1:28:7362:::::", itemId)
    end
    dofile("Where2Go/UI/ItemRow.lua")
    C_TooltipInfo = {
        GetHyperlink = function(link)
            if link:find("item:270164:", 1, true) or link:find("item:268258:", 1, true) then
                return { lines = {
                    { args = { "Item Level 321" } },
                    { args = { "Myth 2/6" } },
                } }
            end
            if link:find("item:268253:", 1, true) then
                return { lines = {
                    { args = { "Item Level 344" } },
                    { args = { "Myth 9/6" } },
                } }
            end
            if link:find("item:268265:", 1, true) then
                return { lines = {
                    { args = { "Item Level 344" } },
                    { args = { "Mythic" } },
                } }
            end
            if link:find("item:271876:", 1, true) then
                return { lines = {
                    { args = { "Item Level 344" } },
                    { args = { "Myth 9/6" } },
                } }
            end
            return { lines = {
                { leftText = "Item Level 321" },
                { leftText = "Champion 2/6" },
            } }
        end,
    }
    local surfaceCalls = 0
    TooltipUtil = {
        SurfaceArgs = function(data)
            surfaceCalls = surfaceCalls + 1
            for _, line in ipairs(data.lines) do
                if line.args then line.leftText = line.args[1] end
            end
        end,
    }
    local function itemRow(itemId, bonusId, ilvl, trackKey, trackRank)
        local row = env:CreateFrame("Button", nil, UIParent)
        Where2GoItemRow.CreateWidgets(row, 24, 0)
        Where2GoItemRow.Populate(row, itemId, ilvl, nil, bonusId, trackKey, trackRank)
        return row
    end
    local function hover(itemId, bonusId, ilvl, trackKey, trackRank)
        local row = itemRow(itemId, bonusId, ilvl, trackKey, trackRank)
        env:RunScript(row, "OnEnter")
        return GameTooltip.link
    end

    local function contextualLink(itemId, bonusId)
        return string.format("item:%d:0:0:0:0:0:0:0:0:0:0:6:2:3524:%d:1:28:7362:::::", itemId, bonusId)
    end
    assert(hover(270164, 12850, 321, "MYTH", 2) == contextualLink(270164, 12850),
        "ordinary Gebbo tooltip must retain its Encounter Journal context with the requested Myth rank")
    assert(hover(268258, 12850, 321, "MYTH", 2) == contextualLink(268258, 12850),
        "ordinary Boots tooltip must retain its Encounter Journal context with the requested Myth rank")
    assert(hover(268253, 13848, 344, "MYTH", 9) == contextualLink(268253, 13848),
        "the final-boss item must combine its Encounter Journal context with the production Myth 9/6 track")
    assert(hover(268265, 13848, 344, "MYTH", 9) == contextualLink(268265, 13848),
        "a special Myth 9/6 item must retain its Encounter Journal context")
    assert(hover(271876, 13848, 344, "MYTH", 9) == contextualLink(271876, 13848),
        "Awoken Dreadfang Cuirass must retain its Encounter Journal context")
    assert(surfaceCalls > 0, "tooltip validation must surface structured C_TooltipInfo line arguments")

    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "Item Level 308" }, { leftText = "Champion 2/6" },
    } } end
    assert(hover(268253, 13848, 344, "MYTH", 9) == "item:268253:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a static variant with conflicting tooltip metadata must fall back to its canonical track-only link")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "Item Level 344" }, { leftText = "Myth 9/6" }, { leftText = "Champion 2/6" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "any explicit conflicting numeric track must override a matching final-rank line")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "Item Level 344" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a final-rank static variant without plain Mythic metadata must use the canonical track-only link")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "Item Level 344" }, { leftText = "Heroic" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a final-rank static variant with the wrong plain track metadata must use the canonical track-only link")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "344 Armor" }, { leftText = "Mythic" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a final-rank static variant must reject an unrelated matching number without item-level metadata")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "Item Level 344" }, { leftText = "Myth 8/6" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a final-rank static variant with the same track at the wrong numeric rank must use the canonical track-only link")
    C_TooltipInfo.GetHyperlink = function() return nil end
    assert(hover(268265, 12850, 321, "MYTH", 2) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:12850",
        "a static variant with unavailable tooltip metadata must fall back to its canonical track-only link")

    ITEM_LEVEL = "아이템 레벨 %d"
    Where2GoLocale.TrackLabel = function(trackKey)
        return ({ MYTH = "신화", HERO = "영웅", CHAMPION = "챔피언" })[trackKey] or trackKey
    end
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "아이템 레벨 344" }, { leftText = "신화" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == contextualLink(268265, 13848),
        "a Korean final-rank tooltip with exact item level and plain Myth metadata must retain the contextual link")
    C_TooltipInfo.GetHyperlink = function() return { lines = {
        { leftText = "아이템 레벨 344" }, { leftText = "챔피언 2/6" },
    } } end
    assert(hover(268265, 13848, 344, "MYTH", 9) == "item:268265:0:0:0:0:0:0:0:0:0:0:0:1:13848",
        "a Korean final-rank tooltip with an explicit Champion conflict must use the canonical track-only link")
    ITEM_LEVEL = nil
    Where2GoLocale.TrackLabel = function(trackKey)
        return ({ MYTH = "Myth", HERO = "Hero", CHAMPION = "Champion" })[trackKey] or trackKey
    end

    C_TooltipInfo.GetHyperlink = function(link)
        return { lines = { { leftText = "Item Level 321" }, { leftText = "Myth 2/6" } } }
    end
    local reusedRow = itemRow(270164, 12850, 321, "MYTH", 2)
    env:RunScript(reusedRow, "OnEnter")
    Where2GoItemRow.Populate(reusedRow, 268258, 321, nil, 12850, "MYTH", 2)
    assert(GameTooltip.link == contextualLink(268258, 12850),
        "repopulating a hovered pooled row must immediately replace the old item's visible tooltip")
end

-- Break caught: the ownership exclusion control either changes only one
-- recommendation source, fails to persist through Equipment, or lets an
-- inventory update leave the visible ranking stale.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    PVEFrame:Show()
    local toggle = env:GetFrame("Where2GoPanel").ownershipButton
    assert(toggle:GetText() == STRINGS.PANEL_OWNERSHIP_ITEM,
        "new panels should default the ownership exclusion criterion to the same item")
    local viewportHeight = env:GetFrame("Where2GoPanelScrollFrame"):GetHeight()
    assert(viewportHeight > 0 and viewportHeight < env:GetFrame("Where2GoPanel"):GetHeight() - 100,
        "the fixed recommendation panel should reserve a bounded control row for ownership filtering")

    local dropCalls = scenario.rankCalls.DROP
    env:Click(toggle)
    assert(scenario.getOwnershipMode() == "SLOT" and scenario.ownershipModeChanges[1] == "SLOT",
        "clicking the shared control should persist SLOT exclusion through Equipment")
    assert(toggle:GetText() == STRINGS.PANEL_OWNERSHIP_SLOT,
        "the control should show the active exclusion criterion")
    assert(scenario.rankCalls.DROP == dropCalls + 1,
        "changing ownership exclusion should immediately refresh the active Drop ranking")

    Where2GoPanel.SetMode("VOIDCORE")
    assert(env:GetFrame("Where2GoPanel").ownershipButton == toggle
            and toggle:GetText() == STRINGS.PANEL_OWNERSHIP_SLOT,
        "Drop and Voidcore should share one persisted ownership exclusion setting")
    env:Click(toggle)
    assert(scenario.getOwnershipMode() == "ITEM" and scenario.ownershipModeChanges[2] == "ITEM",
        "a second click should restore ITEM exclusion for both recommendation modes")

    local voidCalls = scenario.rankCalls.VOIDCORE
    env:FireEvent("BAG_UPDATE_DELAYED")
    env:FireEvent("PLAYER_EQUIPMENT_CHANGED", 1, true)
    assert(scenario.rankCalls.VOIDCORE == voidCalls + 2,
        "bag and equipment events should each refresh the visible active ranking")
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

-- Break caught: left-side candidate collision math compares source coordinate
-- systems directly even though UIParent, Raider.IO, the finder, and the panel can differ.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    local tooltip = env:CreateFrame("Frame", "RaiderIO_ProfileTooltip", UIParent)
    RaiderIO_ProfileTooltip = tooltip
    UIParent.effectiveScale = 0.8
    PVEFrame.effectiveScale = 0.8
    PVEFrame.left, PVEFrame.right, PVEFrame.bottom, PVEFrame.top = 1300, 1650, 375, 1125
    tooltip.effectiveScale = 0.5
    tooltip.left, tooltip.right, tooltip.bottom, tooltip.top = 2800, 3000, 700, 1800
    tooltip:Show()

    PVEFrame:Show()
    local panel = env:GetFrame("Where2GoPanel")
    panel.effectiveScale = 0.5
    env:RunScript(panel, "OnUpdate", 0.2)
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPRIGHT" and anchor[2] == PVEFrame and anchor[3] == "TOPLEFT",
        "mixed effective scales should still detect a left-side panel candidate intersecting the finder")
end

-- Break caught: Raider.IO can be visible before its layout has produced usable
-- coordinates, which must not interrupt the finder lifecycle hook.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    local tooltip = env:CreateFrame("Frame", "RaiderIO_ProfileTooltip", UIParent)
    RaiderIO_ProfileTooltip = tooltip
    tooltip.GetRight = function() return nil end
    tooltip:Show()

    local ok, err = pcall(PVEFrame.Show, PVEFrame)
    assert(ok, "incomplete Raider.IO geometry should not raise an error: " .. tostring(err))
    local panel = env:GetFrame("Where2GoPanel")
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == tooltip and anchor[3] == "TOPRIGHT",
        "incomplete Raider.IO geometry should use the stable default side until coordinates settle")
end

-- Break caught: a right-side recommendation candidate can overlap a finder
-- positioned immediately to the right of Raider.IO.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    local tooltip = env:CreateFrame("Frame", "RaiderIO_ProfileTooltip", UIParent)
    RaiderIO_ProfileTooltip = tooltip
    PVEFrame.left, PVEFrame.right, PVEFrame.bottom, PVEFrame.top = 750, 1310, 300, 920
    tooltip.left, tooltip.right, tooltip.bottom, tooltip.top = 400, 700, 350, 880
    tooltip:Show()

    PVEFrame:Show()
    local panel = env:GetFrame("Where2GoPanel")
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == PVEFrame and anchor[3] == "TOPRIGHT",
        "a right-side panel candidate that intersects the finder should move beyond the finder")
end

-- Break caught: the recommendation panel ignores the visible Raider.IO profile
-- tooltip, keeps covering it after its dimensions settle, or chooses the wrong
-- side when the right screen edge has no room.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    local tooltip = env:CreateFrame("Frame", "RaiderIO_ProfileTooltip", UIParent)
    RaiderIO_ProfileTooltip = tooltip
    tooltip:SetSize(280, 420)
    tooltip.left, tooltip.right, tooltip.top = 900, 1180, 900
    tooltip:Show()

    PVEFrame:Show()
    local panel = env:GetFrame("Where2GoPanel")
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == tooltip and anchor[3] == "TOPRIGHT",
        "a visible Raider.IO tooltip with room on the right should place recommendations beyond its actual bounds")

    tooltip.left, tooltip.right = 1500, 1780
    env:RunScript(panel, "OnUpdate", 0.2)
    anchor = panel.points[1]
    assert(anchor[1] == "TOPRIGHT" and anchor[2] == tooltip and anchor[3] == "TOPLEFT",
        "a delayed Raider.IO size or position change that removes right-side room should move recommendations to its left")

    PVEFrame.left, PVEFrame.right, PVEFrame.bottom, PVEFrame.top = 1000, 1560, 300, 920
    tooltip.left, tooltip.right, tooltip.bottom, tooltip.top = 1400, 1820, 350, 880
    env:RunScript(panel, "OnUpdate", 0.2)
    anchor = panel.points[1]
    assert(anchor[1] == "TOPRIGHT" and anchor[2] == PVEFrame and anchor[3] == "TOPLEFT",
        "when the finder intersects an edge-constrained Raider.IO tooltip, fallback should clear the combined windows")

    PVEFrame.left, PVEFrame.right = 900, 1300
    tooltip.left, tooltip.right = 1450, 1780
    env:RunScript(panel, "OnUpdate", 0.2)
    anchor = panel.points[1]
    assert(anchor[1] == "TOPRIGHT" and anchor[2] == PVEFrame and anchor[3] == "TOPLEFT",
        "a left-side panel candidate that intersects the finder should move beyond the finder")
end

-- Break caught: dragging outside the title bar moves the panel, a manual
-- position is lost on reopen, or reset cannot return to automatic placement.
do
    local scenario = newScenario({ pveFrame = true, pveShown = false })
    local env = scenario.env
    PVEFrame:Show()
    local panel = env:GetFrame("Where2GoPanel")
    local titleBar = env:GetFrame("Where2GoPanelTitleBar")
    assert(titleBar.dragButtons[1] == "LeftButton", "only the title bar should register left-button dragging")

    env:RunScript(titleBar, "OnDragStart")
    assert(panel.moving == true, "title-bar drag should begin moving the recommendation panel")
    local automaticAnchor = panel.points[1]
    env:RunScript(panel, "OnUpdate", 0.2)
    assert(panel.points[1] == automaticAnchor and panel.moving == true,
        "automatic placement should not change the panel's anchor while the player is dragging it")
    panel:Hide()
    assert(panel.moving == false, "hiding the panel during a title-bar drag should stop movement")
    Where2Go_TogglePanel()

    env:RunScript(titleBar, "OnDragStart")
    UIParent.effectiveScale, panel.effectiveScale = 0.8, 0.8
    panel.left, panel.top = 120, 760
    panel:ClearAllPoints()
    panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 120, 100)
    env:RunScript(titleBar, "OnDragStop")
    assert(panel.moving == false and Where2GoCharDB.ui.panelPosition,
        "ending a title-bar drag should stop movement and persist a manual position")
    assert(Where2GoCharDB.ui.panelPosition.x == 120 and Where2GoCharDB.ui.panelPosition.y == -320,
        "manual coordinates should remain in UIParent space when the interface scale is not one")
    local savedAnchor = panel.points[1]
    assert(savedAnchor[1] == "TOPLEFT" and savedAnchor[2] == UIParent and savedAnchor[3] == "TOPLEFT"
            and savedAnchor[4] == 120 and savedAnchor[5] == -320,
        "drag stop should normalize the live anchor to the saved top-left coordinates")

    panel:Hide()
    Where2Go_TogglePanel()
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == UIParent,
        "a persisted manual position should win when the recommendation panel reopens")

    env:Click(titleBar, "RightButton")
    assert(Where2GoCharDB.ui.panelPosition == nil, "right-clicking the title bar should clear the manual position")
    anchor = panel.points[1]
    assert(anchor[2] == PVEFrame and anchor[3] == "TOPRIGHT",
        "resetting the position should immediately restore automatic placement")
end

-- Break caught: a saved title-bar drag position is ignored after the addon
-- reloads and constructs a new recommendation panel.
do
    local charDB = {
        preferredItems = { DROP = { [101] = true }, VOIDCORE = {} },
        preferredItemSources = { DROP = {}, VOIDCORE = {} },
        voidcoreObtainedItems = {},
        ui = { panelPosition = { x = 120, y = -320 } },
    }
    local scenario = newScenario({ charDB = charDB, pveFrame = true, pveShown = false })
    PVEFrame:Show()
    local panel = scenario.env:GetFrame("Where2GoPanel")
    local anchor = panel.points[1]
    assert(anchor[1] == "TOPLEFT" and anchor[2] == UIParent and anchor[4] == 120 and anchor[5] == -320,
        "a valid saved position should be restored when the panel is recreated after reload")
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
    assert(firstRow.summary:GetText() == "Head · 250",
        "recommendation rows must omit the secondary-stat segment when an item has no fixed secondary stats")
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
