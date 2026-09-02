# Phase 4: Voidcore Recommendations — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 4 only (Voidcore obtained-item
history, the independent Voidcore ranking view, a tabbed panel). Builds on
Phase 2 (preferred items, including the already-existing but so-far-unused
`preferredItems.VOIDCORE` list) and Phase 3 (real content pools, the
ranking engine, the ranked-cards panel).

## Decisions carried into this design

- **History-tracking approach**: a simple `BONUS_ROLL_RESULT` event
  listener (ported in spirit from `codex/pre-restart-backup`'s
  `Core/VoidcoreHistory.lua`) that marks an item ID as obtained the moment
  the player receives it via a Voidcore bonus roll. This only tracks
  obtained items from the point the addon is installed onward — it cannot
  retroactively discover items obtained before that.
  **Deferred to a later phase**: the real `VoidcoreAdvisor` addon
  (`rolferik12/VoidcoreAdvisor`, `Core/VoidcacheScan.lua`) instead scans
  the in-game "Nebulous Voidcache" tooltip per spec/per dungeon, which
  reflects Blizzard's own server-side state directly (accurate even for
  pre-addon-install history) but requires substantial additional
  machinery (tooltip-read retries, spec-switching waits, combat-interrupt
  handling). Explicitly out of scope for Phase 4; revisit if the simple
  event-based approach proves insufficient in practice.
- **Voidcore content scope**: both Mythic+ dungeons and raid encounters —
  the same real content pool Phase 3's `Core/Sources.lua` already
  provides, not a separate/smaller pool.
- **Exclusion semantics**: an item already obtained via Voidcore is
  removed from the Voidcore pool entirely (not merely deprioritized) — it
  does not count toward `eligibleCount` for any content entry containing
  it, matching `docs/DECISIONS.md`'s "remove only rewards already consumed
  by Voidcore from the Voidcore pool."
- **UI**: two tabs ("Drop" / "Voidcore") at the top of the existing panel,
  switching which ranked result set is rendered. Card rendering,
  expand/collapse, and `Layout()` are all reused unchanged from Phase 3 —
  only the data feeding them differs per tab.
- **Independence** (`docs/DECISIONS.md`'s "Separate player intents"):
  Direct-drop's ranking, preferred-item list, and eligibility logic are
  completely untouched by this phase. The Voidcore view reads its own
  preferred-item list (`preferredItems.VOIDCORE`, already defined in Phase
  2's schema but unused until now) and its own obtained-item history;
  neither view can affect the other's data or ranking.

## Reference material

- `docs/DECISIONS.md`: "Separate player intents," "Preferred items and
  ownership" (Voidcore history is separate from general ownership because
  a prior Voidcore reward changes that system's repeatable pool).
- `docs/DEVELOPMENT_PLAN.md` Phase 4 bullets and acceptance check.
- `codex/pre-restart-backup` branch, `Core/VoidcoreHistory.lua`: the
  `BONUS_ROLL_RESULT` event pattern and item-link-to-itemId parsing,
  reused in spirit (re-derived, not copied verbatim, since our schema and
  module boundaries differ).
- `rolferik12/VoidcoreAdvisor` (GitHub), `Core/VoidcacheScan.lua` /
  `Core/Detection.lua`: the more sophisticated tooltip-scanning and
  source-attributed detection approach, examined and explicitly deferred
  (see Decisions above).

## Architecture

```
Where2Go/
├── Where2Go.toc                  MODIFY: add Core\VoidcoreHistory.lua,
│                                  Core\VoidcoreDrop.lua
├── Core/
│   ├── Constants.lua              MODIFY: BuildDefaultCharDB adds
│   │                              voidcoreObtainedItems = {}
│   ├── DirectDrop.lua             MODIFY: promote three previously-local
│   │                              functions to public so VoidcoreDrop can
│   │                              reuse them: BuildContentList(),
│   │                              GetCurrentSpecIdAndName(),
│   │                              IsEligibleForSpec(specId)
│   ├── VoidcoreHistory.lua         NEW: BONUS_ROLL_RESULT listener +
│   │                              pure ParseItemIdFromLink(link) helper
│   ├── VoidcoreDrop.lua            NEW: Voidcore-specific ranked results,
│   │                              reusing DirectDrop's content/spec logic
│   │                              and Ranking.RankContent
│   └── (Compare.lua, Equipment.lua, Ranking.lua, RaidRanks.lua, Sources.lua,
│        Tracks.lua, Init.lua unchanged)
└── UI/
    └── Panel.lua                  MODIFY: add Drop/Voidcore tab buttons
                                   and a currentView state; RefreshContent
                                   dispatches to the right ranking function

tests/
├── run_tests.lua                  MODIFY: add constants_spec update,
│                                  voidcorehistory_spec
├── constants_spec.lua              MODIFY: cover voidcoreObtainedItems'
│                                  default shape and independence
└── voidcorehistory_spec.lua         NEW: tests ParseItemIdFromLink only
```

## Components

- **`Core/Constants.lua`** (extended): `BuildDefaultCharDB()` now returns
  `{ preferredItems = {DROP={}, VOIDCORE={}}, voidcoreObtainedItems = {} }`.
- **`Core/DirectDrop.lua`** (extended, still WoW-API-dependent): the same
  behavior as Phase 3, plus its three previously-`local` helper functions
  become public (`Where2GoDirectDrop.BuildContentList`,
  `.GetCurrentSpecIdAndName`, `.IsEligibleForSpec`) purely so
  `VoidcoreDrop.lua` can call them without duplicating the content-
  assembly/spec-detection logic. `GetRankedResults()`'s own behavior does
  not change.
- **`Core/VoidcoreHistory.lua`** (new): a pure helper
  `ParseItemIdFromLink(itemLink)` (string pattern match, no WoW API,
  unit-tested) plus a small event-registration block: on `BONUS_ROLL_RESULT`
  with `typeIdentifier == "item"`, parses the item ID from the reward link
  and sets `Where2GoCharDB.voidcoreObtainedItems[itemId] = true`.
- **`Core/VoidcoreDrop.lua`** (new, WoW-API-dependent, not unit-tested):
  `Where2GoVoidcoreDrop.GetRankedResults()` mirrors
  `DirectDrop.GetRankedResults()`'s shape (`(results, specName)` or
  `(nil, "unsupported_spec")`), but builds its eligibility predicate as
  "spec-eligible AND not in `voidcoreObtainedItems`" and reads
  `preferredItems.VOIDCORE` instead of `.DROP`.
- **`UI/Panel.lua`** (extended): a `currentView` local (`"DROP"` default)
  and two small tab buttons in `CreatePanel()`; `RefreshContent()` calls
  `Where2GoDirectDrop.GetRankedResults()` or
  `Where2GoVoidcoreDrop.GetRankedResults()` depending on `currentView`.
  Card creation, collapse/expand, and `Layout()` are unchanged — they
  operate on whichever `results` array they're given.

## Data flow

1. Player uses a Voidcore bonus roll and receives an item in-game.
   `VoidcoreHistory.lua`'s event handler fires, marks that item ID
   obtained in `Where2GoCharDB.voidcoreObtainedItems`.
2. Player opens the panel (defaults to the Drop tab, same as Phase 3) and
   clicks the Voidcore tab.
3. `RefreshContent()` calls `Where2GoVoidcoreDrop.GetRankedResults()`,
   which reuses `DirectDrop.BuildContentList()` for the same real
   dungeon/raid pools, filters eligibility through both the live spec
   check and the obtained-item exclusion, and ranks against
   `preferredItems.VOIDCORE` via the same `Where2GoRanking.RankContent`.
4. Cards render exactly as in the Drop tab, just fed the Voidcore result
   set.

## Testing

- `constants_spec.lua` (updated): asserts `voidcoreObtainedItems` defaults
  to an empty table and — like `preferredItems`'s sub-tables — is
  independent across separate `BuildDefaultCharDB()` calls.
- `voidcorehistory_spec.lua` (new): tests only
  `Where2GoVoidcoreHistory.ParseItemIdFromLink(link)` against a handful of
  real-shaped item link strings (valid link → correct numeric ID;
  malformed/nil input → `nil`, not an error). The event-registration
  half of the file is WoW-API-dependent and untested, consistent with
  `Equipment.lua`'s pattern in Phase 2.
- `Core/VoidcoreDrop.lua` and the extended `Panel.lua`/`DirectDrop.lua`
  are WoW-API-dependent and not unit-tested — verified live in-client per
  the acceptance check below. `Where2GoRanking.RankContent` itself is
  already fully covered by Phase 3's `ranking_spec.lua`, and this phase
  doesn't change its logic at all.

## Error handling

- Same `"unsupported_spec"` fallback as Phase 3's `DirectDrop.lua`,
  reused by `VoidcoreDrop.lua`'s identical-shaped return contract.
- `ParseItemIdFromLink` returns `nil` for a non-string or unparseable
  input rather than erroring, matching the `BONUS_ROLL_RESULT` handler's
  existing `if not itemId then return end`-style guard from the ported
  reference implementation.

## Acceptance check (from `docs/DEVELOPMENT_PLAN.md`)

- Adding a known Voidcore reward (i.e. calling `VoidcoreHistory`'s mark-
  obtained path, live or via a manual test) changes only the Voidcore
  tab's ranked result for the content containing that item — the Drop
  tab's ranking for the same content is unaffected. Verified live in
  Task N (manual checkpoint): register a preferred item on the Voidcore
  list, confirm it appears as a target on the Voidcore tab, mark it
  obtained (via a real bonus roll, or by directly setting
  `Where2GoCharDB.voidcoreObtainedItems[itemId] = true` and reopening the
  panel if a real bonus roll isn't available to test with), and confirm
  it drops out of the Voidcore tab's target count while the Drop tab
  (which never reads `voidcoreObtainedItems`) is unaffected.

## Out of scope for Phase 4

- Tooltip-scanning-based Voidcore pool discovery (VoidcoreAdvisor-style) —
  deferred; the simple event-based history has a real limitation
  (can't see pre-install history) accepted for this phase.
- Any UI for browsing/editing `voidcoreObtainedItems` directly (e.g. a
  "clear history" button) — not requested, not needed for the acceptance
  check.
- Changes to Direct-drop's own ranking, preferred-item list, or UI beyond
  adding the tab switcher.
