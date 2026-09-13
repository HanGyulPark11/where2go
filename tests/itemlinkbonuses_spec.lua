-- Breaks caught: generated full-link templates omit a tracked item, retain
-- character-specific level/spec fields, or lose Encounter Journal context and
-- modifiers needed to reproduce the item's tooltip variant.
dofile("Where2Go/Core/Sources.lua")
dofile("Where2Go/Core/ItemLinkBonuses.lua")

local data = assert(Where2GoItemLinkBonuses, "item-link template data should be exported")
local templates = assert(data.TEMPLATES, "full item-link templates should be exported")

local tracked = {}
for _, group in ipairs({ Where2GoSources.DUNGEONS, Where2GoSources.RAIDS }) do
    for _, source in ipairs(group) do
        for _, encounter in ipairs(source.encounters) do
            for _, itemId in ipairs(encounter.itemIds) do
                tracked[itemId] = true
            end
        end
    end
end

local templateCount = 0
for itemId, template in pairs(templates) do
    templateCount = templateCount + 1
    assert(tracked[itemId], "template item must exist in Sources.lua: " .. tostring(itemId))
    assert(type(template) == "string" and template:match("^item:" .. itemId .. ":"),
        "template must be a raw item string for its item ID")
    assert(template:match("^item:%d+:0:0:0:0:0:0:0:0:0:0:"),
        "template must zero character-specific item-link fields")
end
for itemId in pairs(tracked) do
    assert(templates[itemId], "tracked item must have a full-link template: " .. itemId)
end
assert(templateCount == 329, "every current tracked item must have exactly one template")

local expectedRaidTemplate = "item:%d:0:0:0:0:0:0:0:0:0:0:6:1:3524:1:28:7362:::::"
for _, itemId in ipairs({ 268265, 268253, 271876 }) do
    assert(templates[itemId] == expectedRaidTemplate:format(itemId),
        "special-effect item must preserve its live Encounter Journal context and modifier: " .. itemId)
end

print("itemlinkbonuses_spec: OK")
