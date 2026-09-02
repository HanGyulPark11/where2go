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
      the same generation process each season) is still open for Phase 5.
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
- [ ] Validate the first end-to-end recommendation in the live WoW client.

Do not start a later item until the earlier item has a documented acceptance
check and the preceding item is verified.
