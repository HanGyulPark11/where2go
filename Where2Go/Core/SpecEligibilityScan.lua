-- Scans the "Nebulous Voidcache" tooltip for each of the player's own
-- class's specializations to build an authoritative
-- Where2GoCharDB.specEligibility table, consumed by
-- Core/DirectDrop.lua's IsEligibleForSpec. See
-- docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md.
--
-- ParseTooltipLines below is pure (no WoW API) and unit-tested in
-- tests/specEligibilityScan_spec.lua. The scan state machine that calls
-- it is WoW-API-dependent like Core/VoidcoreDrop.lua/VoidcoreHistory.lua
-- -- not unit-tested, verified live instead.

Where2GoSpecEligibilityScan = {}

-- Item-name lines in a Nebulous Voidcache tooltip start at this index
-- (1-based) and are each prefixed "- ". Fewer lines than this means the
-- tooltip hasn't finished loading yet.
local MIN_LINES = 7

local function StripColorCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Pure function: parses tooltip line data (shaped like
-- C_TooltipInfo.GetItemByID(...).lines, an array of { leftText = "..." })
-- into a { [itemName] = true } set. Returns nil if there are fewer than
-- MIN_LINES lines (tooltip not fully loaded yet).
function Where2GoSpecEligibilityScan.ParseTooltipLines(lines)
    if not lines or #lines < MIN_LINES then
        return nil
    end
    local items = {}
    for i, lineData in ipairs(lines) do
        if i >= MIN_LINES then
            local text = lineData.leftText
            if text then
                local clean = StripColorCodes(text)
                if clean:sub(1, 2) == "- " then
                    local itemName = clean:sub(3):match("^(.-)%s*$")
                    if itemName and itemName ~= "" then
                        items[itemName] = true
                    end
                end
            end
        end
    end
    return items
end
