# Data contracts

`Sources.lua` exports non-empty `DUNGEONS` and `RAIDS`; each encounter has a name, numeric `bossId`, and non-empty numeric `itemIds`, enforced by `sources_spec.lua`. `ItemStats.lua`, `SpecEligibilityData.lua`, `VoidcacheIds.lua`, and `RaidRanks.lua` are season data consumed by ranking and UI.

Use `docs/SEASON_CHECKLIST.md` and `tools/data-prep/README.md` for refresh procedures. Structural tests verify data shape, not live-game correctness.
