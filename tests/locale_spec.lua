dofile("Where2Go/Core/Locale.lua")

assert(type(Where2GoLocale) == "table", "Where2GoLocale should be a table")
assert(type(Where2GoLocale.L) == "function", "Where2GoLocale.L should be a function")
assert(type(Where2GoLocale.SlotLabel) == "function", "Where2GoLocale.SlotLabel should be a function")
assert(type(Where2GoLocale.StatLabel) == "function", "Where2GoLocale.StatLabel should be a function")
assert(type(Where2GoLocale.StatAbbrev) == "function", "Where2GoLocale.StatAbbrev should be a function")
assert(type(Where2GoLocale.TrackLabel) == "function", "Where2GoLocale.TrackLabel should be a function")
assert(type(Where2GoLocale.ContentName) == "function", "Where2GoLocale.ContentName should be a function")

-- The plain-Lua test harness has no GetLocale global, so Locale.lua's
-- module-load-time locale detection falls back to enUS -- these
-- assertions exercise the enUS table and the fallback logic directly,
-- not live locale detection (which is WoW-API-dependent, verified live).
assert(Where2GoLocale.L("BROWSE_BUTTON") == "Browse", "L() should return the enUS string by default in this harness")
assert(Where2GoLocale.SlotLabel("HEAD") == "Head", "SlotLabel() should return the enUS label by default")
assert(Where2GoLocale.StatLabel("CRIT_RATING") == "Crit", "StatLabel() should return the enUS label by default")
assert(Where2GoLocale.StatAbbrev("VERSATILITY") == "Vers", "StatAbbrev() should return the enUS abbreviation by default")
assert(Where2GoLocale.TrackLabel("HERO") == "Hero", "TrackLabel() should return the enUS label by default")
assert(Where2GoLocale.ContentName("The Venomous Abyss") == "The Venomous Abyss",
    "ContentName() should return the enUS content name by default")
assert(Where2GoLocale.L("PANEL_SOURCE_ALL") == "Source: All", "the recommendation source filter should default to the All label")
assert(Where2GoLocale.L("PANEL_SOURCE_DUNGEONS") == "Source: Dungeons", "the recommendation source filter should expose the Dungeons label")
assert(Where2GoLocale.L("PANEL_SOURCE_RAIDS") == "Source: Raids", "the recommendation source filter should expose the Raids label")
assert(Where2GoLocale.L("PANEL_NO_MATCHES") == "No matching targets remain for the selected source, specialization, and owned-gear filtering.",
    "the no-match guidance should account for the selected source filter")
assert(Where2GoLocale.STRINGS.koKR.PANEL_SOURCE_ALL == "출처: 전체", "the Korean All source label should match the approved wording")
assert(Where2GoLocale.STRINGS.koKR.PANEL_SOURCE_DUNGEONS == "출처: 던전", "the Korean Dungeons source label should match the approved wording")
assert(Where2GoLocale.STRINGS.koKR.PANEL_SOURCE_RAIDS == "출처: 레이드", "the Korean Raids source label should match the approved wording")
assert(Where2GoLocale.STRINGS.koKR.MODE_VOIDCORE == "공허핵", "the Korean Voidcore mode label should use the approved wording")
assert(Where2GoLocale.CONTENT_NAMES.koKR["The Venomous Abyss"] == "맹독 심연",
    "the Korean raid display name should be stored in addon-owned localization")
assert(Where2GoLocale.CONTENT_NAMES.koKR["Nek'zali the Soulcoiler"] == "영혼살무사 네크잘리",
    "the Korean boss display name should be stored in addon-owned localization")
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
for key in pairs(Where2GoLocale.STAT_LABELS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.STAT_LABELS.koKR[key] ~= nil, "koKR STAT_LABELS is missing a translation for '" .. key .. "'")
end
for key in pairs(Where2GoLocale.STAT_ABBREV.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.STAT_ABBREV.koKR[key] ~= nil, "koKR STAT_ABBREV is missing a translation for '" .. key .. "'")
end
for key in pairs(Where2GoLocale.TRACK_LABELS.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.TRACK_LABELS.koKR[key] ~= nil, "koKR TRACK_LABELS is missing a translation for '" .. key .. "'")
end
for key in pairs(Where2GoLocale.CONTENT_NAMES.enUS) do
    coverageCount = coverageCount + 1
    assert(Where2GoLocale.CONTENT_NAMES.koKR[key] ~= nil, "koKR CONTENT_NAMES is missing a translation for '" .. key .. "'")
end

GetLocale = function() return "koKR" end
dofile("Where2Go/Core/Locale.lua")
assert(Where2GoLocale.L("MODE_VOIDCORE") == "공허핵", "koKR clients should label Voidcore as 공허핵")
assert(Where2GoLocale.ContentName("Voidscar Arena") == "공허흉터 투기장",
    "koKR clients should localize addon-owned dungeon names")
assert(Where2GoLocale.ContentName("Unknown Source") == "Unknown Source",
    "ContentName() should fall back to the canonical source name when no translation exists")

print("locale_spec: OK, " .. coverageCount .. " string(s) cross-checked between enUS and koKR")
