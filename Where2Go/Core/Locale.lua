-- Addon UI chrome localization: detects the WoW client's locale once via
-- GetLocale() and matches the addon's OWN strings (button labels,
-- headers, slot names, and addon-owned dungeon/boss names) to it. Item
-- names and the real GameTooltip already match the client's language
-- with zero addon work.
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
        SELECT_ALL_FILTERED = "Select All",
        CLEAR_SELECTION = "Clear selection",
        CLEAR_ALL = "Clear All",
        CLEAR_PREFERRED_CONFIRM = "Remove every preferred item from the current list?",
        CLEAR_BUTTON = "Clear",
        CANCEL_BUTTON = "Cancel",
        SEARCH_PLACEHOLDER = "Search...",
        SLOT_DROPDOWN_ALL = "All Slots",
        STAT_DROPDOWN_ALL = "All Stats",
        SPEC_DROPDOWN_ALL = "All Specs",
        MANAGE_BUTTON = "Manage items",
        PANEL_SPEC_CONTEXT = "Ranking for: %s",
        PANEL_COUNT_SUMMARY = "%d preferred items · %d destinations",
        PANEL_CARD_COUNTS = "%d targets / %d eligible items",
        PANEL_OWNERSHIP_ITEM = "Exclude: Same item",
        PANEL_OWNERSHIP_SLOT = "Exclude: Slot",
        PANEL_OWNERSHIP_HELP = "Excludes preferred gear when an equipped or regular-bag item is equal or better. Same item compares upgrade track first, then item level; Slot applies that comparison to compatible gear in the same slot.",
        PANEL_SOURCE_ALL = "Source: All",
        PANEL_SOURCE_DUNGEONS = "Source: Dungeons",
        PANEL_SOURCE_RAIDS = "Source: Raids",
        PANEL_NO_PREFERRED = "Choose the items you want to see where to go next.",
        PANEL_NO_MATCHES = "No matching targets remain for the selected source, specialization, and owned-gear filtering.",
        PANEL_ESTIMATE_HELP = "Ranked by the share of your preferred items in the eligible loot pool, treating each item equally. This is not a measured drop rate or a time-per-run estimate.",
        BROWSER_SUBTITLE = "Choose your goals. Where2Go finds the places to run.",
        BROWSER_SPEC_HINT = "Browse by specialization. Recommendations use your active specialization.",
        FILTER_RESET = "Reset filters",
        FILTER_SOURCE = "Source",
        FILTER_SLOT = "Slot",
        FILTER_STAT = "Stats",
        FILTER_SPEC = "Specs",
        FILTER_MORE = "%s +%d",
        RESULTS_COUNT = "Items · %d",
        PREFERRED_COUNT = "Preferred · %d",
        SELECT_RESULTS = "Select results",
        SELECTED_COUNT = "%d of %d available selected",
        ADD_COUNT = "Add selected · %d",
        ADD_ONE = "Add",
        SAVED = "Saved",
        REMOVE_ONE = "Remove",
        PARTIAL_SELECTION = "Partly selected",
        EMPTY_RESULTS = "No items match your filters. Try clearing a filter or changing your search.",
        LOADING_ITEMS = "Loading item information…",
        EMPTY_PREFERRED = "Your goals go here.\n\nAdd one item directly, or select results and uncheck the items you do not want.",
        ADDED_FEEDBACK = "Added %d preferred item(s).",
        REMOVED_FEEDBACK = "Removed %d preferred item(s).",
        UNDO = "Undo",
        UNDONE_FEEDBACK = "Last change undone.",
        SEARCH_LABEL = "Search items",
        SELECTION_HINT = "Select results, uncheck exceptions, then add.",
    },
    koKR = {
        BROWSER_TITLE = "Where2Go - 아이템 탐색기",
        PANEL_TITLE = "Where2Go",
        MODE_DROP = "드랍",
        MODE_VOIDCORE = "공허핵",
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
        SELECT_ALL_FILTERED = "전체 선택",
        CLEAR_SELECTION = "선택 해제",
        CLEAR_ALL = "전체 삭제",
        CLEAR_PREFERRED_CONFIRM = "현재 목록의 모든 선호 아이템을 삭제할까요?",
        CLEAR_BUTTON = "삭제",
        CANCEL_BUTTON = "취소",
        SEARCH_PLACEHOLDER = "검색...",
        SLOT_DROPDOWN_ALL = "모든 부위",
        STAT_DROPDOWN_ALL = "모든 스탯",
        SPEC_DROPDOWN_ALL = "모든 전문화",
        MANAGE_BUTTON = "선호 아이템 관리",
        PANEL_SPEC_CONTEXT = "추천 기준: %s",
        PANEL_COUNT_SUMMARY = "선호 아이템 %d개 · 추천 콘텐츠 %d곳",
        PANEL_CARD_COUNTS = "목표 %d개 / 획득 대상 %d개",
        PANEL_OWNERSHIP_ITEM = "제외 기준: 동일 아이템",
        PANEL_OWNERSHIP_SLOT = "제외 기준: 부위",
        PANEL_OWNERSHIP_HELP = "착용 장비나 일반 가방에 같은 등급 이상 장비가 있으면 선호 아이템을 제외합니다. 동일 아이템은 등급(영웅·신화 등)을 먼저, 같은 등급이면 아이템 레벨을 비교합니다. 부위는 현재 전문화에 맞는 같은 부위 장비에 적용합니다.",
        PANEL_SOURCE_ALL = "출처: 전체",
        PANEL_SOURCE_DUNGEONS = "출처: 던전",
        PANEL_SOURCE_RAIDS = "출처: 레이드",
        PANEL_NO_PREFERRED = "원하는 아이템을 등록하면 갈 곳을 추천해 드립니다.",
        PANEL_NO_MATCHES = "선택한 출처, 전문화, 보유 장비 제외 기준을 적용한 뒤 남은 목표 아이템이 없습니다.",
        PANEL_ESTIMATE_HELP = "획득 대상 중 선호 아이템의 비중으로 순위를 매깁니다. 모든 아이템을 동일하게 계산하며, 실제 드랍 확률이나 소요 시간을 반영한 값은 아닙니다.",
        BROWSER_SUBTITLE = "원하는 아이템을 고르면, 어디로 갈지 알려드립니다.",
        BROWSER_SPEC_HINT = "탐색할 전문화를 선택하세요. 콘텐츠 추천은 현재 활성 전문화 기준입니다.",
        FILTER_RESET = "필터 초기화",
        FILTER_SOURCE = "출처",
        FILTER_SLOT = "부위",
        FILTER_STAT = "능력치",
        FILTER_SPEC = "전문화",
        FILTER_MORE = "%s +%d",
        RESULTS_COUNT = "검색 결과 · %d개",
        PREFERRED_COUNT = "선호 아이템 · %d개",
        SELECT_RESULTS = "결과 전체 선택",
        SELECTED_COUNT = "%d개 선택 / 추가 가능 %d개",
        ADD_COUNT = "선택한 %d개 추가",
        ADD_ONE = "추가",
        SAVED = "등록됨",
        REMOVE_ONE = "삭제",
        PARTIAL_SELECTION = "일부 선택됨",
        EMPTY_RESULTS = "조건에 맞는 아이템이 없습니다.\n필터를 초기화하거나 검색어를 바꿔보세요.",
        LOADING_ITEMS = "아이템 정보를 불러오는 중…",
        EMPTY_PREFERRED = "원하는 아이템을 모아보세요.\n\n하나씩 바로 추가하거나, 전체 선택 후 원하지 않는 아이템을 제외할 수 있습니다.",
        ADDED_FEEDBACK = "선호 아이템 %d개를 추가했습니다.",
        REMOVED_FEEDBACK = "선호 아이템 %d개를 삭제했습니다.",
        UNDO = "실행 취소",
        UNDONE_FEEDBACK = "마지막 변경을 취소했습니다.",
        SEARCH_LABEL = "아이템 검색",
        SELECTION_HINT = "전체 선택 후 제외할 아이템을 해제하고 추가하세요.",
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

-- STAT_LABELS: full-ish name for filter UI (the stat dropdown's option
-- text). STAT_ABBREV: short form for the compact item-row summary line
-- ("344 · Crit/Haste"). Korean stat names are already short in common
-- usage, so both tables use the same koKR text -- only enUS shortens
-- further for the summary line ("Versatility" -> "Vers").
Where2GoLocale.STAT_LABELS = {
    enUS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Versatility" },
    koKR = { CRIT_RATING = "치명타", HASTE_RATING = "가속", MASTERY_RATING = "특화", VERSATILITY = "유연성" },
}

Where2GoLocale.STAT_ABBREV = {
    enUS = { CRIT_RATING = "Crit", HASTE_RATING = "Haste", MASTERY_RATING = "Mastery", VERSATILITY = "Vers" },
    koKR = { CRIT_RATING = "치명타", HASTE_RATING = "가속", MASTERY_RATING = "특화", VERSATILITY = "유연성" },
}

-- Gear upgrade-track names (Core/Tracks.lua's UPGRADE_TRACKS keys), shown
-- next to a recommendation card's ilvl (e.g. "(Hero 3/6)"). Korean terms
-- confirmed against the pre-restart branch's own previously-shipped
-- Constants.lua (C.UPGRADE_TRACKS[*].label), consistent with general
-- Korean WoW community usage for these track names.
Where2GoLocale.TRACK_LABELS = {
    enUS = { VETERAN = "Veteran", CHAMPION = "Champion", HERO = "Hero", MYTH = "Myth" },
    koKR = { VETERAN = "숙련", CHAMPION = "챔피언", HERO = "영웅", MYTH = "신화" },
}

-- Regenerated by tools/data-prep/generate_content_locale.py from the
-- Battle.net Game Data API Journal endpoints. Do not hand-edit this table;
-- regenerate and review the staged table instead.
Where2GoLocale.CONTENT_NAMES = {
    enUS = {
        ["Adderis and Aspix"] = "Adderis and Aspix",
        ["Altar of Fangs"] = "Altar of Fangs",
        ["Atroxus"] = "Atroxus",
        ["Avatar of Sethraliss"] = "Avatar of Sethraliss",
        ["Charonus"] = "Charonus",
        ["Dazar, The First King"] = "Dazar, The First King",
        ["Den of Nalorakk"] = "Den of Nalorakk",
        ["Entombed Sentinels"] = "Entombed Sentinels",
        ["Galvazzt"] = "Galvazzt",
        ["Ikuzz the Light Hunter"] = "Ikuzz the Light Hunter",
        ["Kings' Rest"] = "Kings' Rest",
        ["Kokia Blazehoof"] = "Kokia Blazehoof",
        ["Kyrakka and Erkhart Stormvein"] = "Kyrakka and Erkhart Stormvein",
        ["Kystia Manaheart"] = "Kystia Manaheart",
        ["Lightblossom Trinity"] = "Lightblossom Trinity",
        ["Lightwarden Ruia"] = "Lightwarden Ruia",
        ["Lithiel Cinderfury"] = "Lithiel Cinderfury",
        ["Mchimba the Embalmer"] = "Mchimba the Embalmer",
        ["Melidrussa Chillworn"] = "Melidrussa Chillworn",
        ["Merektha"] = "Merektha",
        ["Murder Row"] = "Murder Row",
        ["Nalorakk"] = "Nalorakk",
        ["Nek'zali the Soulcoiler"] = "Nek'zali the Soulcoiler",
        ["Nymrissa Wavecaller"] = "Nymrissa Wavecaller",
        ["Rav'i"] = "Rav'i",
        ["Ruby Life Pools"] = "Ruby Life Pools",
        ["Sentinel of Winter"] = "Sentinel of Winter",
        ["Sszorak"] = "Sszorak",
        ["Taz'Rah"] = "Taz'Rah",
        ["Temple of Sethraliss"] = "Temple of Sethraliss",
        ["The Blinding Vale"] = "The Blinding Vale",
        ["The Coiled Altar"] = "The Coiled Altar",
        ["The Council of Tribes"] = "The Council of Tribes",
        ["The Golden Serpent"] = "The Golden Serpent",
        ["The Hoardmonger"] = "The Hoardmonger",
        ["The Lost Explorers"] = "The Lost Explorers",
        ["The Tidebound Grotto"] = "The Tidebound Grotto",
        ["The Twin Fangs"] = "The Twin Fangs",
        ["The Venomous Abyss"] = "The Venomous Abyss",
        ["The Writhing Coil"] = "The Writhing Coil",
        ["Ula'tek"] = "Ula'tek",
        ["Vashnik the Malignant"] = "Vashnik the Malignant",
        ["Voidscar Arena"] = "Voidscar Arena",
        ["Xathuux the Annihilator"] = "Xathuux the Annihilator",
        ["Zaen Bladesorrow"] = "Zaen Bladesorrow",
        ["Ziekket"] = "Ziekket",
        ["Zul'jan"] = "Zul'jan",
    },
    koKR = {
        ["Adderis and Aspix"] = "애더리스와 아스픽스",
        ["Altar of Fangs"] = "송곳니의 제단",
        ["Atroxus"] = "아트로서스",
        ["Avatar of Sethraliss"] = "세스랄리스의 화신",
        ["Charonus"] = "차로누스",
        ["Dazar, The First King"] = "초대 왕 다자르",
        ["Den of Nalorakk"] = "날로라크의 소굴",
        ["Entombed Sentinels"] = "매장된 파수꾼",
        ["Galvazzt"] = "갈바즈트",
        ["Ikuzz the Light Hunter"] = "빛 사냥꾼 이쿠즈",
        ["Kings' Rest"] = "왕들의 안식처",
        ["Kokia Blazehoof"] = "코키아 블레이즈후프",
        ["Kyrakka and Erkhart Stormvein"] = "카이락카와 에크하트 스톰베인",
        ["Kystia Manaheart"] = "키스티아 마나하트",
        ["Lightblossom Trinity"] = "빛송이 삼위일체",
        ["Lightwarden Ruia"] = "빛의 감시자 루이아",
        ["Lithiel Cinderfury"] = "리시엘 신더퓨리",
        ["Mchimba the Embalmer"] = "장의사 음침바",
        ["Melidrussa Chillworn"] = "멜리드루사 칠원",
        ["Merektha"] = "메레크타",
        ["Murder Row"] = "죽음의 골목",
        ["Nalorakk"] = "날로라크",
        ["Nek'zali the Soulcoiler"] = "영혼살무사 네크잘리",
        ["Nymrissa Wavecaller"] = "님리사 웨이브콜러",
        ["Rav'i"] = "라비",
        ["Ruby Life Pools"] = "루비 생명의 웅덩이",
        ["Sentinel of Winter"] = "겨울의 파수꾼",
        ["Sszorak"] = "스조라크",
        ["Taz'Rah"] = "타즈라",
        ["Temple of Sethraliss"] = "세스랄리스 사원",
        ["The Blinding Vale"] = "눈부신 골짜기",
        ["The Coiled Altar"] = "똬리의 제단",
        ["The Council of Tribes"] = "부족 의회",
        ["The Golden Serpent"] = "황금 날뱀",
        ["The Hoardmonger"] = "비축광",
        ["The Lost Explorers"] = "길 잃은 탐험가",
        ["The Tidebound Grotto"] = "해일결속 동굴",
        ["The Twin Fangs"] = "쌍둥이 송곳니",
        ["The Venomous Abyss"] = "맹독 심연",
        ["The Writhing Coil"] = "격동하는 똬리",
        ["Ula'tek"] = "울라텍",
        ["Vashnik the Malignant"] = "악성의 바쉬니크",
        ["Voidscar Arena"] = "공허흉터 투기장",
        ["Xathuux the Annihilator"] = "파멸자 자투스",
        ["Zaen Bladesorrow"] = "자엔 블레이드소로우",
        ["Ziekket"] = "지케트",
        ["Zul'jan"] = "줄잔",
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

function Where2GoLocale.StatLabel(stat)
    return Where2GoLocale.STAT_LABELS[activeLocale][stat] or Where2GoLocale.STAT_LABELS.enUS[stat] or stat
end

function Where2GoLocale.StatAbbrev(stat)
    return Where2GoLocale.STAT_ABBREV[activeLocale][stat] or Where2GoLocale.STAT_ABBREV.enUS[stat] or stat
end

function Where2GoLocale.TrackLabel(trackKey)
    return Where2GoLocale.TRACK_LABELS[activeLocale][trackKey] or Where2GoLocale.TRACK_LABELS.enUS[trackKey] or trackKey
end

function Where2GoLocale.ContentName(name)
    return Where2GoLocale.CONTENT_NAMES[activeLocale][name] or Where2GoLocale.CONTENT_NAMES.enUS[name] or name
end
