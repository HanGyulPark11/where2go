# Restart Checklist

- [x] Confirm the first supported WoW client version and season. Midnight
      patch 12.1 (`Interface: 120100`), Season 2. See
      `docs/superpowers/specs/2026-09-02-phase1-foundations-design.md`.
- [ ] Define the minimum supported classes and specializations.
- [ ] Choose the data source and refresh procedure for instance, encounter,
      and item-pool data.
- [x] Create a thin addon shell that can render a static recommendation card.
      Verified live in-client (Phase 1). Deviates from "in the Dungeon and
      Raid Finder": renders in a standalone frame instead, to avoid
      Blizzard-frame anchoring/taint risk this early — see the Phase 1
      design spec's Panel placement decision. Revisit anchoring in a later
      phase if the standalone frame proves insufficient.
- [ ] Add the direct-drop ranking engine with deterministic test fixtures.
- [ ] Add the independent Voidcore ranking engine and history model.
- [ ] Validate the first end-to-end recommendation in the live WoW client.

Do not start a later item until the earlier item has a documented acceptance
check and the preceding item is verified.
