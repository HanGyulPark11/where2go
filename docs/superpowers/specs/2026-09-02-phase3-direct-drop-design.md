# Phase 3: Direct-Drop Recommendations — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 3 only (real per-content item pools,
equal-outcome ranking math, the live recommendation panel with expandable
cards). Builds on Phase 1 (addon skeleton, panel) and Phase 2 (preferred
items, upgrade-track data).

## Decisions carried into this design

- **Data source**: real per-dungeon/per-boss item pools ported from
  `codex/pre-restart-backup`'s `Data/Sources.lua` (generated from the
  Battle.net Game Data API Journal endpoints, patch 12.1 Season 2) — not an
  expanded fixture. This also corrects a real Phase 1 data error: the
  ASR-transcript-sourced fixture merged "Nymrissa Wavecaller" into a
  fictional 9-boss "Venomous Abyss," but the real data shows Nymrissa
  Wavecaller is the sole boss of a *different* single-boss raid, "The
  Tidebound Grotto." The Venomous Abyss is actually 8 bosses. `Fixtures.lua`
  and `fixtures_spec.lua` are deleted; nothing else depended on them.
- **Loot specialization scope**: the player's current active specialization
  only (via `GetSpecialization()`/`GetSpecializationInfo()`), not
  Blizzard's separate loot-spec-switching mechanic. Cross-spec loot
  targeting is deferred.
- **Raid difficulty**: fixed at Mythic for item level/track display. The
  boss→rank (1-4) mapping is ported from the same pre-restart branch
  (`RAID_BOSS_RANK`) — independently verified against `Sources.lua`'s real
  boss IDs and confirmed to match exactly (it was built against the correct
  8-boss Venomous Abyss, unlike the fixture data). Bosses not in the
  mapping (single-boss raids like The Tidebound Grotto) default to rank 1.
- **Mythic+ item level**: fixed at the key+10 floor, which the player
  confirmed in-client drops Hero rank 3/6 gear. No per-key-level table (the
  source branch's own step-function table was marked "approximate, refine
  when better data exists" — this fixed single point is more trustworthy
  than that guess, and simpler).
- **Content granularity** (already decided in `docs/DECISIONS.md`): Mythic+
  is ranked per dungeon (pool = the union of all its bosses' items). Raids
  are ranked per boss encounter (pool = that boss's items only), each
  carrying its raid's name for context.
- **Card default state**: all cards open by default (see `docs/DECISIONS.md`
  update superseding "first few open by default" — the player found a
  partially-collapsed list harder to scan). Cards still support individual
  collapse.
- **No content filtering**: every dungeon and raid encounter is ranked and
  shown, even ones with zero eligible items for the current spec (ratio 0,
  naturally sorting to the bottom). No arbitrary cutoff.

## Reference material

- `docs/DECISIONS.md`: equal-outcome probability model, content granularity,
  presentation (card fields, now-superseded default-open rule).
- `docs/DEVELOPMENT_PLAN.md` Phase 3 bullets and acceptance check.
- `codex/pre-restart-backup` branch: `Data/Sources.lua` (real item pools,
  ported as-is), `Core/Constants.lua`'s `RAID_BOSS_RANK` /
  `MYTHICPLUS_CONFIRMED_TRACK` (ported as empirically-confirmed facts, not
  the neighboring uncertain `MYTHICPLUS_ILVL_BY_KEY` table, which is NOT
  ported), `Core/Eligibility.lua`'s `MatchesSpec` (the `C_Item.GetItemSpecInfo`
  pattern, re-derived fresh rather than copied since our Phase 2 already
  established this exact pattern's use elsewhere).
- `C:\Users\hangy\ai\vault\wiki\wow-item-level-bonus-id-system.md`: the
  `C_Item.GetItemSpecInfo` reliability scope (player's own class only —
  satisfied here since loot spec is always same-class by construction).

## Architecture

```
Where2Go/
├── Where2Go.toc                  MODIFY: remove Core\Fixtures.lua, add
│                                  Core\Sources.lua, Core\RaidRanks.lua,
│                                  Core\Ranking.lua, Core\DirectDrop.lua
├── Core/
│   ├── Constants.lua              unchanged
│   ├── Tracks.lua                 unchanged
│   ├── Sources.lua                 NEW, pure data: real dungeon/raid/boss
│   │                              item pools, ported from Data/Sources.lua
│   ├── RaidRanks.lua               NEW, pure data + pure functions:
│   │                              boss→rank map, fixed M+ track assumption,
│   │                              GetRaidIlvl(bossId)/GetMythicPlusIlvl()
│   ├── Compare.lua                unchanged
│   ├── Ranking.lua                 NEW, pure function: RankContent(content,
│   │                              isEligible, isPreferred) -> sorted results
│   ├── Equipment.lua              unchanged
│   ├── DirectDrop.lua              NEW, WoW-API-dependent: current spec
│   │                              detection, C_Item.GetItemSpecInfo
│   │                              eligibility, item name lookup, assembles
│   │                              content and calls Ranking.lua
│   └── Init.lua                   unchanged (already toggles the panel;
│                                  the panel's content is what changes)
└── UI/
    └── Panel.lua                  REWRITE: renders real ranked results as
                                   expandable cards instead of Fixtures.lua

DELETE: Where2Go/Core/Fixtures.lua, tests/fixtures_spec.lua

tests/
├── run_tests.lua                  MODIFY: remove fixtures_spec, add
│                                  sources_spec, raidranks_spec, ranking_spec
├── sources_spec.lua                NEW
├── raidranks_spec.lua              NEW
└── ranking_spec.lua                NEW (the acceptance-check test: a small
                                   synthetic content set with known pool
                                   sizes must produce the expected order)
```

## Components

- **`Core/Sources.lua`** (pure data): `Where2GoSources.DUNGEONS` (array of
  `{instanceId, name, encounters = {{bossId, name, itemIds}}}`, 8 dungeons)
  and `Where2GoSources.RAIDS` (same shape, 2 raids: The Tidebound Grotto
  1 boss, The Venomous Abyss 8 bosses) — a verbatim port of the cited
  source's `ns.Sources.dungeons`/`.raids`.
- **`Core/RaidRanks.lua`** (pure data + functions): `RAID_BOSS_RANK` (bossId
  → 1-4), fixed `MYTHIC_PLUS_TRACK_KEY`/`_RANK` constants,
  `GetRaidIlvl(bossId)` → `(ilvl, trackLabel, rank)` via
  `Where2GoTracks.UPGRADE_TRACKS.MYTH`, `GetMythicPlusIlvl()` → the same
  triple via the fixed Hero-rank-3 assumption. No WoW API.
- **`Core/Ranking.lua`** (pure function): `RankContent(content, isEligible, isPreferred)`.
  `content` is an array of `{id, name, kind, raidName, itemIds, ilvl, trackLabel, trackRank}`
  (extra fields beyond `itemIds` pass through unchanged). For each entry,
  counts `eligibleCount` (items where `isEligible(itemId)` is true) and
  `targetItemIds`/`targetCount` (the eligible subset where `isPreferred(itemId)`
  is also true), computes `ratio = targetCount/eligibleCount` (`0` if
  `eligibleCount` is `0`), and returns all entries sorted by ratio desc,
  then `targetCount` desc, then `name` asc. `isEligible`/`isPreferred` are
  injected predicates — this is what keeps the module testable with
  synthetic data instead of live `C_Item.GetItemSpecInfo` calls.
- **`Core/DirectDrop.lua`** (WoW-API-dependent, not unit-tested): resolves
  the current spec via `GetSpecialization()`/`GetSpecializationInfo()`;
  builds the content list (one entry per dungeon with all its bosses'
  items flattened and the fixed M+ ilvl/track, one entry per raid boss
  with that boss's items and `RaidRanks.GetRaidIlvl(bossId)`); defines
  `isEligible` via `C_Item.GetItemSpecInfo` against the current spec ID
  (`nil` result or no matching spec ID in the returned table both count
  appropriately per the existing documented semantics — `nil` means no
  restriction, an empty table means restricted away from every spec of
  this class); defines `isPreferred` via
  `Where2GoCharDB.preferredItems.DROP[itemId]`; calls
  `Where2GoRanking.RankContent`; resolves target item names via
  `C_Item.GetItemInfo` (falling back to `"Item #<id>"` if not yet cached —
  no retry/caching logic, matching this phase's scope). Returns
  `(results, specName)` or `(nil, "unsupported_spec")`.
- **`UI/Panel.lua`** (rewrite): on show, calls `Where2GoDirectDrop.GetRankedResults()`
  and rebuilds the card list (the shell — title, close button, drag — is
  built once in `CreatePanel()` as before; the content region is rebuilt
  every time the panel is shown, since preferred items/loot spec can
  change between views). Each card: a header line (`name` — `raidName`
  prefix if present — `targetCount/eligibleCount` — `ilvl (trackLabel
  trackRank/6)`) with a click-to-collapse affordance, and — when
  expanded — one line per `targetItemIds` entry showing its resolved name.
  A `Layout()` function repositions all cards top-to-bottom and resizes
  the panel frame's height after any collapse/expand toggle or on initial
  build. No `ScrollFrame` — if the full list exceeds a comfortable height
  that's a known limitation for later polish, not blocking this phase.

## Data flow

1. Player opens the panel (`/where2go` or `/w2g`, no arguments).
2. `Where2Go_TogglePanel()` shows the panel and triggers a content rebuild:
   `Where2GoDirectDrop.GetRankedResults()`.
3. `DirectDrop` assembles the content list from `Sources`/`RaidRanks`,
   evaluates eligibility/preference live, calls `Ranking.RankContent`.
4. `Panel` renders one card per result in ranked order, all expanded by
   default, each showing its ratio, item level/track, and (when expanded)
   its target item names.
5. Clicking a card's header toggles that card's expanded state and
   triggers `Layout()` to reflow everything below it.

## Testing

- `sources_spec.lua`: contract test — both `DUNGEONS` and `RAIDS` are
  non-empty arrays; every dungeon/raid has a `name` and at least one
  encounter; every encounter has a `bossId` (raids) and a non-empty
  `itemIds` array of numbers. Does not re-verify the real-world accuracy
  of the ported data (that's the cited source's job) — this is a shape
  contract.
- `raidranks_spec.lua`: `GetRaidIlvl` for each of the 8 real Venomous Abyss
  boss IDs returns the expected rank/ilvl per `RAID_BOSS_RANK` and
  `Where2GoTracks.UPGRADE_TRACKS.MYTH`; an unlisted boss ID defaults to
  rank 1; `GetMythicPlusIlvl()` returns Hero rank 3's ilvl.
- `ranking_spec.lua` (the acceptance-check test): a small synthetic
  `content` array (2-3 entries with hand-picked `itemIds` and known
  eligible/preferred subsets via fake predicate closures) produces the
  exact expected `eligibleCount`/`targetCount`/`ratio` per entry and the
  exact expected sort order, including a tie broken by `targetCount` and a
  tie broken by `name`.
- `Core/DirectDrop.lua` and the rewritten `UI/Panel.lua` are WoW-API-
  dependent and not unit-tested — verified live in-client per the
  acceptance check below.

## Error handling

- `DirectDrop.GetRankedResults()` returns `(nil, "unsupported_spec")` if
  `GetSpecialization()` returns nothing (no spec chosen yet); `Panel.lua`
  shows a one-line message in that case instead of an empty/broken card
  list.
- Item name resolution falls back to `"Item #<id>"` rather than erroring
  or showing a blank line when `C_Item.GetItemInfo` hasn't cached the item
  yet.

## Acceptance check (from `docs/DEVELOPMENT_PLAN.md`)

- A fixture (synthetic content array) with known pool sizes produces the
  expected ordering — `ranking_spec.lua`.
- The live panel shows all results expanded by default (per the updated
  `docs/DECISIONS.md` default) and each is individually collapsible.

## Out of scope for Phase 3

- Cross-spec loot targeting (comparing against a different spec of the
  same class).
- Difficulty-tier selection UI (raid is fixed at Mythic, M+ fixed at the
  key+10 floor).
- Voidcore recommendations and history (Phase 4).
- Real per-key Mythic+ item level data beyond the single confirmed
  key+10 floor point (would need more in-client measurement — not
  blocking, since the fixed assumption is real, confirmed data, just for
  one key level).
- Scrolling/pagination for a long card list.
- Retrying/caching item name lookups that miss the client's cache on first
  request.
