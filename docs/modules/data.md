# Data contracts

`Sources.lua` exports non-empty `DUNGEONS` and `RAIDS`; each encounter has a name, numeric `bossId`, and non-empty numeric `itemIds`, enforced by `sources_spec.lua`. `ItemStats.lua`, `SpecEligibilityData.lua`, `VoidcacheIds.lua`, `RaidRanks.lua`, and `ItemLinkBonuses.lua` are season data consumed by ranking and UI. `ItemLinkBonuses.lua` contains one generated, locale-independent Encounter Journal link template per tracked item. Each template keeps item context and modifiers but omits character-specific fields and upgrade-track bonuses; `ItemRow.lua` inserts the calculated track bonus when it builds a tooltip link.

Use `docs/SEASON_CHECKLIST.md` and `tools/data-prep/README.md` for refresh procedures. Structural tests verify data shape, not live-game correctness.
