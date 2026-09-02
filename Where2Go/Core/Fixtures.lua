-- Fixture data for Phase 1 (docs/DEVELOPMENT_PLAN.md).
--
-- Provenance and known limits:
-- * dungeon: a placeholder name. The season's real Mythic+ dungeon pool is
--   an open decision (see TODO.md) -- any dungeon works for Phase 1 since
--   this only verifies the panel's rendering shape.
-- * raid: "The Venomous Abyss" and its 9 encounters, sourced from
--   ai/vault/wiki/midnight-season2-raid.md, which is itself built from an
--   automated transcript of a pre-release Mythic test stream (patch 12.1).
--   Treat encounter names as a snapshot, not confirmed Encounter Journal
--   data -- Phase 5 replaces this with a real seasonal data source.
-- * poolSize / targetCount / recommendedLootSpec / items are ALL
--   placeholder values so the panel has something to render. Phase 3
--   computes real pool/target numbers; Phase 5 sources real item pools.

Where2GoFixtures = {
    dungeon = {
        name = "Sample Mythic+ Dungeon",
        poolSize = 8,
        targetCount = 2,
        recommendedLootSpec = "Elemental",
        items = { "Sample Item A", "Sample Item B" },
    },
    raid = {
        name = "The Venomous Abyss",
        encounters = {
            { name = "님리사 웨이브콜러", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item C" } },
            { name = "영혼살무사 네크잘리", poolSize = 6, targetCount = 1, recommendedLootSpec = "Restoration", items = { "Sample Item D" } },
            { name = "매장된 파수꾼", poolSize = 6, targetCount = 0, recommendedLootSpec = "Elemental", items = {} },
            { name = "길 잃은 탐험가", poolSize = 6, targetCount = 1, recommendedLootSpec = "Enhancement", items = { "Sample Item E" } },
            { name = "악성의 바쉬니크", poolSize = 6, targetCount = 2, recommendedLootSpec = "Elemental", items = { "Sample Item F", "Sample Item G" } },
            { name = "스조라크", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item H" } },
            { name = "쌍둥이 송곳니", poolSize = 6, targetCount = 0, recommendedLootSpec = "Restoration", items = {} },
            { name = "똬리의 제단", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item I" } },
            { name = "울라텍", poolSize = 9, targetCount = 2, recommendedLootSpec = "Elemental", items = { "Sample Item J", "Sample Item K" } },
        },
    },
}
