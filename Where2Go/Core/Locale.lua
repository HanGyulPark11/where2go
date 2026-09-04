-- Addon UI chrome localization: detects the WoW client's locale once via
-- GetLocale() and matches the addon's OWN strings (button labels,
-- headers, slot names) to it. Item names, the real GameTooltip, and
-- dungeon/boss names (Sources.lua, addon-owned data) are explicitly NOT
-- covered here -- item names/tooltips already match the client's
-- language with zero addon work, and dungeon/boss name translation is
-- separate future data-prep work (see
-- docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md).
--
-- STRINGS/SLOT_LABELS are public (not local) so tests/locale_spec.lua can
-- cross-check enUS/koKR coverage, the same pattern Sources.lua/ItemStats.lua
-- use for their own coverage tests.

Where2GoLocale = {}

Where2GoLocale.STRINGS = {
    enUS = {
        BROWSER_TITLE = "Where2Go - Item Browser",
        PANEL_TITLE = "Where2Go",
        MODE_DROP = "Drop",
        MODE_VOIDCORE = "Voidcore",
        BROWSE_BUTTON = "Browse",
        NO_SPEC_SELECTED = "Where2Go: no specialization selected.",
        SOURCE_DROPDOWN_ALL = "All Sources",
        SOURCE_DROPDOWN_N_SELECTED = "%d selected",
        SOURCE_GROUP_DUNGEONS = "Dungeons",
        ELIGIBLE_ONLY = "Selected spec eligible only",
        RESULTS_HEADER = "Results",
        STAGED_HEADER = "Staged",
        PREFERRED_HEADER = "Preferred",
        ADD_SELECTED = "Add selected",
        CLEAR_SELECTION = "Clear selection",
        CLEAR_ALL = "Clear All",
        CLEAR_PREFERRED_CONFIRM = "Remove every preferred item from the current list?",
        CLEAR_BUTTON = "Clear",
        CANCEL_BUTTON = "Cancel",
    },
    koKR = {
        BROWSER_TITLE = "Where2Go - 아이템 탐색기",
        PANEL_TITLE = "Where2Go",
        MODE_DROP = "드랍",
        MODE_VOIDCORE = "보이드코어",
        BROWSE_BUTTON = "탐색",
        NO_SPEC_SELECTED = "Where2Go: 전문화가 선택되지 않았습니다.",
        SOURCE_DROPDOWN_ALL = "모든 출처",
        SOURCE_DROPDOWN_N_SELECTED = "%d개 선택됨",
        SOURCE_GROUP_DUNGEONS = "던전",
        ELIGIBLE_ONLY = "선택한 전문화만 표시",
        RESULTS_HEADER = "결과",
        STAGED_HEADER = "임시 선택",
        PREFERRED_HEADER = "선호 아이템",
        ADD_SELECTED = "선택 추가",
        CLEAR_SELECTION = "선택 해제",
        CLEAR_ALL = "전체 삭제",
        CLEAR_PREFERRED_CONFIRM = "현재 목록의 모든 선호 아이템을 삭제할까요?",
        CLEAR_BUTTON = "삭제",
        CANCEL_BUTTON = "취소",
    },
}

Where2GoLocale.SLOT_LABELS = {
    enUS = {
        HEAD = "Head", NECK = "Neck", SHOULDER = "Shoulder", BACK = "Back",
        CHEST = "Chest", WRIST = "Wrist", HANDS = "Hands", WAIST = "Waist",
        LEGS = "Legs", FEET = "Feet", FINGER = "Finger", TRINKET = "Trinket",
        MAINHAND = "Main Hand", OFFHAND = "Off Hand",
    },
    koKR = {
        HEAD = "머리", NECK = "목", SHOULDER = "어깨", BACK = "등",
        CHEST = "가슴", WRIST = "손목", HANDS = "손", WAIST = "허리",
        LEGS = "다리", FEET = "발", FINGER = "손가락", TRINKET = "장신구",
        MAINHAND = "주 무기", OFFHAND = "보조 무기",
    },
}

-- Guarded: GetLocale is a WoW API global, absent in the plain-Lua test
-- harness. Falls back to enUS there rather than erroring at load time.
local activeLocale = (type(GetLocale) == "function" and GetLocale() == "koKR") and "koKR" or "enUS"

-- Falls back to enUS for any key missing in the active table, then to
-- the key itself if even enUS is missing it (never shows a blank string).
function Where2GoLocale.L(key)
    return Where2GoLocale.STRINGS[activeLocale][key] or Where2GoLocale.STRINGS.enUS[key] or key
end

function Where2GoLocale.SlotLabel(slot)
    return Where2GoLocale.SLOT_LABELS[activeLocale][slot] or Where2GoLocale.SLOT_LABELS.enUS[slot] or slot
end
