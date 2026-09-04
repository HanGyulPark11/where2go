dofile("Where2Go/Core/Locale.lua")

assert(type(Where2GoLocale) == "table", "Where2GoLocale should be a table")
assert(type(Where2GoLocale.L) == "function", "Where2GoLocale.L should be a function")
assert(type(Where2GoLocale.SlotLabel) == "function", "Where2GoLocale.SlotLabel should be a function")

-- The plain-Lua test harness has no GetLocale global, so Locale.lua's
-- module-load-time locale detection falls back to enUS -- these
-- assertions exercise the enUS table and the fallback logic directly,
-- not live locale detection (which is WoW-API-dependent, verified live).
assert(Where2GoLocale.L("BROWSE_BUTTON") == "Browse", "L() should return the enUS string by default in this harness")
assert(Where2GoLocale.SlotLabel("HEAD") == "Head", "SlotLabel() should return the enUS label by default")
assert(Where2GoLocale.L("NONEXISTENT_KEY_XYZ") == "NONEXISTENT_KEY_XYZ", "L() should fall back to the key itself when missing from every table")

-- Coverage: every enUS key must have a koKR counterpart, so a forgotten
-- translation doesn't silently ship English-only for Korean players.
local coverageCount = 0
for key in pairs(Where2GoLocale.STRINGS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.STRINGS.koKR[key] ~= nil, "koKR STRINGS is missing a translation for '" .. key .. "'")
end
for key in pairs(Where2GoLocale.SLOT_LABELS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.SLOT_LABELS.koKR[key] ~= nil, "koKR SLOT_LABELS is missing a translation for '" .. key .. "'")
end

print("locale_spec: OK, " .. coverageCount .. " string(s) cross-checked between enUS and koKR")
