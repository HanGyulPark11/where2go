# Historical delivery record and open live QA

This file retains prior discovery and delivery notes. Use
`docs/CURRENT_STATE.md` for current status and `docs/CODEMAP.md` for source and
test routing. The open live work is `docs/UI_REDESIGN_QA.md` and real Voidcore
`BONUS_ROLL_RESULT` confirmation. Historical statements below do not supersede
current source or tests.

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

## Phase 6: Item Browser & Preferred-List Management (complete)

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
- [x] Sub-project B (item browser UI): `docs/superpowers/specs/2026-09-03-phase6-item-browser-design.md`
      + `docs/superpowers/plans/2026-09-03-phase6-item-browser.md`. Delivered
      `Where2Go/Core/ItemBrowser.lua` (pure pool/filter/sort logic,
      `tests/itembrowser_spec.lua`) and `Where2Go/UI/BrowserPanel.lua` (the
      window: dungeon/boss/slot/stat/spec-eligibility/search filters, a
      recycled-row result list, staged selection, and the three action
      buttons), wired via a "Browse" button and `/where2go browse`.
      Implemented the cache pre-warm design note below: `Toggle()` calls
      `C_Item.RequestLoadItemDataByID` over the whole pool on first open
      and refreshes the list as `GET_ITEM_INFO_RECEIVED` fires (guarded to
      only run while the browser is actually shown).
      **Live checkpoint rounds 1-3 found 4 real issues; 3 fixed and
      confirmed live, 1 accepted as a known limitation deferred to Phase 7
      (see below)** — full test suite green, 10 specs, 0 failures:
      1. Non-equipment loot (housing decor, crafting recipes, trophies,
         a consumable/reagent — 60 of 378 pool items, confirmed via a live
         Battle.net API classification scan) was showing up in the
         browser. Fixed: `ItemBrowser.lua`'s `matchesFilters` now
         unconditionally excludes any item with no resolvable equip slot.
      2. The stat filter was union (OR: matches any selected stat).
         Changed to intersection (AND: must match every selected stat)
         per explicit product decision after live comparison of both
         behaviors.
      3. **Confirmed bug in already-merged Phase 3 code**, not introduced
         by this branch: `Where2Go/Core/DirectDrop.lua`'s
         `IsEligibleForSpec` treats `C_Item.GetItemSpecInfo` returning an
         *empty* table `{}` as "restricted, no spec matches" instead of
         "no restriction data" — because `{}` is truthy in Lua, the
         function's existing `if not specTable then return true end`
         check doesn't catch it, so execution falls through to an empty
         `ipairs` loop and returns `false` (ineligible). Confirmed via a
         live in-game `/dump C_Item.GetItemSpecInfo(...)` on a necklace,
         which returned `{}`. This affects every feature using
         `IsEligibleForSpec` — `DirectDrop.lua`'s own ranking and
         `VoidcoreDrop.lua`, not just this browser — and has likely been
         silently misclassifying universally-usable neck/ring items as
         ineligible since Phase 3 shipped. Fixed:
         `if not specTable or #specTable == 0 then return true end`.
      4. **Round-1 fix #3 above was too broad, and the follow-up attempt
         did not fix it either — this remains a known, open limitation.**
         Treating an empty `GetItemSpecInfo` as always-eligible also
         makes wrong-weapon/armor-type items (e.g. a bow) show as
         eligible for classes that cannot equip that item type at all
         (confirmed live: a bow showed eligible for a Shaman).
         `GetItemSpecInfo` alone can't distinguish "no restriction,
         universal item" from "not applicable, wrong item type for this
         class." Tried gating on `C_Item.IsEquippableItem(itemId) == false`
         (a live client API expected to check class/weapon/armor-type
         equippability) before consulting `GetItemSpecInfo` — **confirmed
         live that this did NOT fix the reported case**; `IsEquippableItem`
         does not reliably answer this question for our purposes (left in
         place as a real-but-currently-ineffective-for-this-case gate,
         since it doesn't hurt and may help other cases). Also confirmed,
         via research, that neither a hand-maintained class→weapon/armor-
         type table (web sources gave directly contradictory data — see
         [[feedback-verify-with-live-diagnostics-before-deciding]]) nor
         the Battle.net Web API (checked the full raw item response and
         `/data/wow/playable-class/{id}` — neither exposes weapon/armor
         proficiency data) can solve this cheaply.
         **The real fix requires bigger infrastructure — see
         `docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`**,
         a new design doc (not planned/implemented yet) proposing the
         technique the real `VoidcoreAdvisor` addon uses: scan the
         "Nebulous Voidcache" tooltip per loot-spec-setting (Blizzard's
         own server-computed, correctly-filtered loot list for that spec),
         which Where2Go's own Voidcore system may share (open question in
         that doc, needs live confirmation first). Deliberately scoped as
         its own future phase, not a Sub-project B follow-up — it changes
         a real user setting (loot specialization) as a side effect and
         needs its own data-storage design (per-character, not global).
         **Until Phase 7 exists, "Current spec eligible only" has a known
         false-positive: wrong-weapon/armor-type items may still appear
         as eligible.** This applies to DirectDrop's and VoidcoreDrop's
         existing recommendations too, not just this browser.
      **Fixes 3 and 4 touch already-shipped Phase 3 behavior**, not just
      this branch's new code — direct-drop and Voidcore recommendations
      were re-verified live post-merge to now correctly count previously-
      hidden universal neck/ring items as eligible (fix 3 confirmed
      working). Fix 4's wrong-type false-positive remains a known,
      accepted limitation, not something to re-test as if it were fixed.
      **Known follow-ups, deliberately not fixed** (both cosmetic/low-
      impact, found during final review, unrelated to the live-checkpoint
      issues above):
      - The Drop/Voidcore mode buttons never show a pressed highlight on
        the browser's first open (an interaction between two otherwise-
        correct fixes: an initial `SetMode("DROP")` call and `SetMode`'s
        no-op guard for `mode == currentMode`, since `currentMode`
        already defaults to `"DROP"`). Filtering is unaffected — clicking
        Voidcore then Drop again does show the highlight correctly.
      - `RebuildBossButtons` (`Where2Go/UI/BrowserPanel.lua`) creates new
        button frames on every dungeon/raid click rather than pooling
        them like the result list does — WoW frames are never destroyed,
        so this grows slowly (~9 frames/click) over a long session. Left
        as a documented code comment rather than fixed, since a correct
        pooling fix means reworking that row's per-click closure/
        highlight logic and the real-world growth rate is slow.

**Deferred from this phase**: browsing/filtering by a curated per-spec
BiS (best-in-slot) list — would need new curated data collected per spec
from an external source (e.g. Icy Veins), same effort as the existing
[[demonology-warlock]]-style vault ingest, currently only done for one
spec. Revisit once there's an appetite for that data-collection work
across the specs actually being played.
