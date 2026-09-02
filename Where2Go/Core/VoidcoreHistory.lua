-- Tracks items obtained via a Voidcore bonus roll for this character.
-- Ported in spirit from codex/pre-restart-backup's Core/VoidcoreHistory.lua
-- -- listens for BONUS_ROLL_RESULT and marks the rewarded item ID obtained
-- in Where2GoCharDB.voidcoreObtainedItems. This only tracks items obtained
-- from the moment the addon is installed onward -- see
-- docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md for the
-- deferred tooltip-scanning alternative that wouldn't have this limit.

Where2GoVoidcoreHistory = {}

-- Pure string parse, no WoW API -- extracts the numeric item ID from a
-- real item link string. Returns nil for a non-string or unparseable
-- input. Testable standalone (see tests/voidcorehistory_spec.lua).
function Where2GoVoidcoreHistory.ParseItemIdFromLink(itemLink)
    if type(itemLink) ~= "string" then
        return nil
    end
    return tonumber(itemLink:match("item:(%d+)"))
end

-- The event registration below is WoW-API-dependent (CreateFrame doesn't
-- exist outside the game client). Guarded so this file can still be
-- dofile'd by the standalone test harness to exercise the pure function
-- above without crashing on a missing global -- this is deliberate, not
-- a workaround to "clean up."
if CreateFrame then
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
    eventFrame:SetScript("OnEvent", function(self, event, typeIdentifier, itemLink)
        if event ~= "BONUS_ROLL_RESULT" or typeIdentifier ~= "item" then
            return
        end
        local itemId = Where2GoVoidcoreHistory.ParseItemIdFromLink(itemLink)
        if itemId then
            Where2GoCharDB.voidcoreObtainedItems[itemId] = true
        end
    end)
end
