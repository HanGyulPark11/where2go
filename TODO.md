# Restart Checklist

- [x] Confirm the first supported WoW client version and season. Midnight
      patch 12.1 (`Interface: 120100`), Season 2. See
      `docs/superpowers/specs/2026-09-02-phase1-foundations-design.md`.
- [x] Define the minimum supported classes and specializations. No
      restriction by design: eligibility is computed live via
      `C_Item.GetItemSpecInfo` against the player's own current
      specialization (Phase 3's `Core/DirectDrop.lua`), not a hardcoded
      per-class list — works for any class/spec without extra work.
- [x] Choose the data source and refresh procedure for instance, encounter,
      and item-pool data. Real per-dungeon/per-boss item pools ported from
      `codex/pre-restart-backup`'s Battle.net-Journal-API-generated data
      (Phase 3, `Where2Go/Core/Sources.lua`). Refresh procedure (re-running
      the same generation process each season) is now implemented in Phase
      5 via `tools/data-prep/generate_sources.py` and
      `docs/SEASON_CHECKLIST.md`.
- [x] Create a thin addon shell that can render a static recommendation card.
      Verified live in-client (Phase 1). Deviates from "in the Dungeon and
      Raid Finder": renders in a standalone frame instead, to avoid
      Blizzard-frame anchoring/taint risk this early — see the Phase 1
      design spec's Panel placement decision. Revisit anchoring in a later
      phase if the standalone frame proves insufficient.
- [x] Add the direct-drop ranking engine with deterministic test fixtures.
      `Where2Go/Core/Ranking.lua` + `tests/ranking_spec.lua` (Phase 3),
      verified live in-client with real ranked, expandable cards.
- [x] Add the independent Voidcore ranking engine and history model.
      `Where2Go/Core/VoidcoreHistory.lua` + `Where2Go/Core/VoidcoreDrop.lua`
      (Phase 4), tabbed panel and independence from Direct-drop confirmed
      live in-client. One check remains open: whether `BONUS_ROLL_RESULT`
      actually fires for the current Voidcore system has NOT been
      confirmed yet — the player is saving their Voidcore for other use,
      so the real-roll test in
      `docs/superpowers/plans/2026-09-02-phase4-voidcore.md` (Task 6, step
      5) is deferred until one is available to spend on testing. Until
      then, do not assume the event fires; if it turns out not to,
      `docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md`'s
      deferred tooltip-scanning approach becomes required.
- [x] Validate the first end-to-end recommendation in the live WoW client.
      Confirmed during Phase 3's live checkpoint: real ranked, expandable
      dungeon/boss cards rendered from actual `Sources.lua` data against
      the player's live specialization, first result expanded by default.
      Reconfirmed structurally (not just via the dev symlink) by Phase 5's
      packaging sub-project, which loaded a real packaged zip in a
      separate `AddOns` location successfully.

Restart Checklist complete. `docs/DEVELOPMENT_PLAN.md`'s full Phase 1-5
delivery sequence is now implemented and merged, including Phase 5's data
refresh tooling (`tools/data-prep/`), lint checks (`tools/lint.ps1`), and
packaging/release readiness (`tools/package.ps1`, `tools/smoke-test.ps1`,
`docs/RELEASE_CHECKLIST.md`). The one open item carried over from above:
`BONUS_ROLL_RESULT` firing for a real Voidcore roll is still unconfirmed
(see the Voidcore item above) — report back once verified.

Do not start a later item until the earlier item has a documented acceptance
check and the preceding item is verified.

## Phase 6: Item Browser & Preferred-List Management (Sub-project A complete, B not yet implemented)

- [x] Sub-project A (item stat metadata): `docs/superpowers/specs/2026-09-03-phase6-item-stats-design.md`
      + `docs/superpowers/plans/2026-09-03-phase6-item-stats.md`. Delivered
      `tools/data-prep/generate_item_stats.py`, `Where2Go/Core/ItemStats.lua`
      (378 items, real Battle.net data, `secondaryStats` only), and
      `tests/itemstats_spec.lua` (including a Sources.lua-coverage check).
      Documented in `docs/SEASON_CHECKLIST.md` and `tools/data-prep/README.md`.
      **`primaryStats` was researched and deliberately dropped, not
      shipped.** The generated data was confirmed biased toward INTELLECT
      (a scan of all 378 items found 149 flex items where the API's
      unparameterized `/data/wow/item/{id}` response happened to show a
      non-negated INTELLECT reading alongside negated STRENGTH/AGILITY
      options, and 61 items where the API returned *only* negated primary
      entries with no active reading present at all — e.g. item 158367
      returns solely `STRENGTH (is_negated=true)`). Root cause: the
      current Game Data API has no supported way to force a specific
      class/spec context (the old Community API's `bl=<bonusIds>`
      parameter has no Game Data API equivalent), so a single
      unparameterized call cannot reliably recover an item's full
      class-flex stat set. Surveyed alternatives: Class Codex (curated
      per-spec BiS scrape from Icy Veins/Archon/Wowhead — matches the
      "Deferred from this phase" curated-BiS item below, and note its own
      pipeline is now abandoned) and SimulationCraft's DBC-extracted data
      (`simulationcraft/simc`, `midnight` branch — ground-truth data
      exists as committed `.inc` files, e.g. `engine/dbc/generated/item_data.inc`,
      but in an undocumented raw-C++-struct format needing its own parser
      and ongoing upkeep against SimC's internal schema). Neither is a
      quick add-on to this sub-project; revisit only if a primary-stat
      filter or BiS feature is actually built, and budget it as its own
      small project rather than a follow-up task.
- [ ] Sub-project B (item browser UI): `docs/superpowers/specs/2026-09-03-phase6-item-browser-design.md`
      + `docs/superpowers/plans/2026-09-03-phase6-item-browser.md` — a separate
      browser window: filter the full item pool by dungeon/boss, slot, stat,
      spec-eligibility, and name; stage multiple picks; commit them to the
      active (Drop/Voidcore) preferred list in one action; view/clear the
      preferred list from the same screen. Ready to execute now that
      Sub-project A is merged.
      **Design note for the "spec eligible only" filter**: the plan's
      `GetItemEligible()` calls `Where2GoDirectDrop.IsEligibleForSpec()`
      live, per item, at filter time — `C_Item.GetItemSpecInfo`'s
      already-documented cold-cache ambiguity (`DirectDrop.lua:71-79`,
      nil meaning either "unrestricted" or "not yet cached") is a bigger
      risk here than in DirectDrop's single-card use case, since the
      browser evaluates the whole ~378-item pool at once and most of it
      may be uncached on a fresh session. Fix by calling
      `C_Item.RequestLoadItemDataByID` for the full pool proactively at
      `PLAYER_LOGIN` (the pool is already known statically from
      `Sources.lua`), well before the player is likely to open the
      browser, rather than sourcing eligibility from external data —
      add a brief loading state for the cold-open case.

**Deferred from this phase**: browsing/filtering by a curated per-spec
BiS (best-in-slot) list — would need new curated data collected per spec
from an external source (e.g. Icy Veins), same effort as the existing
[[demonology-warlock]]-style vault ingest, currently only done for one
spec. Revisit once there's an appetite for that data-collection work
across the specs actually being played.
