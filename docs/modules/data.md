# Data contracts

`Sources.lua` exports non-empty `DUNGEONS` and `RAIDS`; each encounter has a name, numeric `bossId`, and non-empty numeric `itemIds`, enforced by `sources_spec.lua`. `ItemStats.lua`, `SpecEligibilityData.lua`, `VoidcacheIds.lua`, `RaidRanks.lua`, and `ItemLinkBonuses.lua` are season data consumed by ranking and UI. `ItemLinkBonuses.lua` contains curated non-track effect/context bonuses for Aqirbane Reliquary (268265), Silken Voodoo Drape (268253), and Awoken Dreadfang Cuirass (271876); `ItemRow.lua` appends the calculated track bonus when it builds a synthetic tooltip link.

Use `docs/SEASON_CHECKLIST.md` and `tools/data-prep/README.md` for refresh procedures. Structural tests verify data shape, not live-game correctness.
