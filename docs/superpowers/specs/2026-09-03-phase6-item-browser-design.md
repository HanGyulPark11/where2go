# Phase 6, Sub-project B: Item Browser & Preferred-List Management — Design

Status: approved
Scope: a new, separate window where a player browses the full dungeon/raid
item pool (grouped/filtered by dungeon-boss, slot, stat, spec-eligibility),
sees which items are already in their preferred list, and adds/removes
items — replacing the current slash-command-only (`/where2go pref add|remove|list`)
workflow with a real browsing UI. Depends on Sub-project A
(`Where2Go/Core/ItemStats.lua`) for stat-based filtering.

## Background / problem

Today, adding a preferred item requires the player to already know its
exact numeric item ID and type `/where2go pref add <id> <drop|voidcore>`
by hand — there is no way to discover candidate items from inside the
addon at all. The player explicitly wants to browse "all the items" and
narrow down by dungeon/boss, gear slot, stat type, or current-spec
eligibility, then add several at once.

## Decisions

- **Separate window, not a new tab on the recommendation panel.** The
  recommendation panel is meant to stay lightweight/glanceable; browsing
  and preference management is a heavier, occasional task — the same
  distinction most addons draw between their main display and their
  options/config window. Opened via a button on the main panel (a small
  icon/button near the existing tabs) and/or a new slash command
  (`/where2go browse`).
- **Drop/Voidcore is a toggle at the top of the browser**, not two
  separate checkboxes per item. Whichever mode is active determines which
  preferred list an item's checked/unchecked state reflects and which
  list "add selected" commits into. Switching modes re-renders the list
  against the other preferred list.
- **Preferred-list viewing is integrated into the browse list itself**,
  not a separate "my list" screen — an item already in the active mode's
  preferred list is visually marked (e.g. highlighted row / checkmark)
  directly in the same scrollable list Sub-project B renders for
  browsing. No separate tab needed for this.
- **Two distinct, separately-labeled bulk actions** (do not conflate
  these — they were explicitly called out as different concepts):
  1. **선택 항목 추가 ("Add selected")** — commits every currently
     checked-but-not-yet-committed row into the active mode's preferred
     list in one action. This is about a *staging selection* the player
     builds while browsing (e.g. checking 8 items while scrolling through
     a raid's boss list), separate from each item's already-saved
     preferred status.
  2. **선택 해제 ("Clear selection")** — clears the *staging* checkboxes
     only (the ones not yet committed), independent of anything already
     saved to the preferred list.
  3. **선호 목록 전체 삭제 ("Clear preferred list")** — a third, separate
     action that empties the *entire saved* preferred list for the
     active mode (Drop or Voidcore, whichever is currently toggled) —
     effectively a reset, used when the player wants to start over. This
     is NOT the same as "선택 해제" and must be visually distinguished
     (e.g. a confirmation step, since it's destructive to existing data)
     from the two staging-related buttons.
- **Filter/group combinations for v1** (multi-select where sensible,
  combined with AND logic — an item must match every active filter):
  1. **던전/레이드 + 보스** — pick a dungeon or raid, optionally narrow to
     one boss within it. Reuses `Sources.lua`'s existing structure
     directly (no new data needed).
  2. **슬롯** (head/chest/weapon/trinket/etc.) — reuses
     `Where2GoConstants.EQUIPLOC_TO_SLOT` + `C_Item.GetItemInfoInstant`,
     the exact same live-lookup `Equipment.lua` already does elsewhere.
  3. **스탯** (Crit/Haste/Mastery/Versatility, primary stat) — reads
     Sub-project A's `Where2GoItemStats.STATS`.
  4. **현재 전문화 적합 여부** — reuses `Where2GoDirectDrop.IsEligibleForSpec`
     (the exact same eligibility check the Drop tab's ranking already
     uses), as a toggle to show/hide spec-ineligible items rather than a
     hard filter, so a player can still deliberately browse off-spec
     items if they want to.
  - Additional filter/sort ideas worth having in v1 given how cheap they
    are on top of data we already have, proposed during design and
    accepted implicitly by not being pushed back on — confirm during spec
    review, not blocking implementation if trimmed: **text search by item
    name** (needs `C_Item.GetItemInfo`, already used elsewhere), and
    **sort by item level / name / dungeon order**.
  - **BiS (best-in-slot) per spec**: explicitly discussed and deferred —
    recorded in `TODO.md` as future work, not part of this sub-project.
    No `.pkgmeta`-style scaffolding needed for it; it simply isn't built
    yet, since it needs an as-yet-undesigned curated-data collection
    process (see Sub-project A's "Out of scope").
- **Large list needs virtualized/recycled rows, not one frame per item.**
  The combined dungeon+raid item pool is in the hundreds; creating a
  persistent Frame/FontString set per item (the way the recommendation
  panel's small, bounded card list currently does) would not scale.
  Standard WoW-addon pattern: a fixed small number of row frames (enough
  to cover the visible scroll area) that get their content/visibility
  updated and repositioned as the list scrolls, rather than one frame per
  underlying data row. This needs to be an explicit part of the
  implementation plan, not an afterthought — it changes how `BrowserPanel.lua`
  is structured from the start.

## Architecture

```
Where2Go/Core/ItemBrowser.lua        NEW: pure filtering/grouping logic --
                                      given the full Sources.lua item pool,
                                      a filter-state table, and (WoW-API-
                                      dependent, passed in as a parameter
                                      rather than called directly, so the
                                      core matching logic stays pure and
                                      unit-testable) a slot-lookup function
                                      and a spec-eligibility function,
                                      returns the filtered/sorted list of
                                      {itemId, name-source info, dungeon/
                                      boss context} entries to render.

Where2Go/UI/BrowserPanel.lua         NEW: the separate browser window --
                                      filter controls, virtualized scroll
                                      list, checkboxes, the three action
                                      buttons, Drop/Voidcore toggle.
                                      WoW-API-dependent, not unit-tested
                                      (matches Panel.lua's precedent).

Where2Go/UI/Panel.lua                MODIFY: add a small button that opens
                                      BrowserPanel (and/or Init.lua adds a
                                      new slash subcommand).

Where2Go/Core/Init.lua               MODIFY: `/where2go browse` subcommand
                                      (or equivalent) to open the browser
                                      window directly without going through
                                      the main panel.
```

## Components

- **`Where2Go/Core/ItemBrowser.lua`** (new, pure, unit-tested): the
  filtering/grouping brain. Takes the assembled item pool (built the same
  way `Where2GoDirectDrop.BuildContentList()` already assembles it, reused
  rather than duplicated), a `filters` table (selected dungeon/boss, slot,
  stat set, spec-eligibility-only flag, search text, sort mode), and
  returns a flat, ordered list of matching items with enough context
  (which dungeon/boss they came from) to render. Slot lookup and spec
  eligibility are WoW-API-dependent facts this module needs but must not
  call directly itself — the caller (`BrowserPanel.lua`) resolves those
  live and passes the results in, keeping `ItemBrowser.lua` a pure
  function of its inputs and therefore testable with fixture data the
  same way `Ranking.lua` is.
- **`Where2Go/UI/BrowserPanel.lua`** (new): owns the actual frame,
  filter widgets, the virtualized scroll list (fixed pool of row frames,
  repositioned/repopulated on scroll — the concrete row-recycling
  mechanism is worked out during implementation planning against real
  WoW scroll-frame APIs, not finalized here), staging-selection state
  (which currently-visible-or-previously-checked items are pending
  commit), and the three action buttons' logic (add selected / clear
  selection / clear entire preferred list, the last requiring an
  explicit confirmation step since it's destructive).
- **`Where2Go/UI/Panel.lua`** (modified): a small button (e.g. a gear/
  cog icon or a text button near the existing Drop/Voidcore tabs) that
  opens `BrowserPanel`.
- **`Where2Go/Core/Init.lua`** (modified): a new slash subcommand to open
  the browser directly (exact command name decided during implementation
  — `/where2go browse` is the working name).

## Data flow

1. Player opens the browser (button or slash command).
2. `BrowserPanel.lua` builds the full item pool once (reusing
   `Where2GoDirectDrop.BuildContentList()`), resolves each item's slot
   live (`C_Item.GetItemInfoInstant` + `EQUIPLOC_TO_SLOT`) and current
   spec eligibility (`Where2GoDirectDrop.IsEligibleForSpec`), and reads
   stat tags from `Where2GoItemStats.STATS`.
3. Player adjusts filters (dungeon/boss, slot, stat, spec-eligible-only,
   search) → `Where2GoItemBrowser`'s pure filter function re-derives the
   matching list → `BrowserPanel.lua` re-renders the (virtualized) visible
   rows against the new list.
4. Player checks boxes on candidate rows (staging selection, independent
   of saved preferred state) while possibly changing filters in between
   (staged selections persist across filter changes within one browser
   session).
5. Player clicks "선택 항목 추가" → every staged item ID is written into
   the active mode's (Drop or Voidcore) `Where2GoCharDB.preferredItems[mode]`,
   staging is cleared, and the list re-renders showing those items now
   marked as saved-preferred.
6. Player can instead click "선택 해제" to abandon staged checks without
   saving, or "선호 목록 전체 삭제" (with confirmation) to wipe the active
   mode's entire saved preferred list.
7. Closing the browser and reopening the main recommendation panel (or
   switching its Drop/Voidcore tab) reflects the updated preferred list
   immediately, the same way it already does after a `/where2go pref add`
   slash command today.

## Testing

- `tests/itembrowser_spec.lua` (new): unit tests for
  `Where2GoItemBrowser`'s pure filter/sort function against fixture data
  (a small fabricated item pool + fabricated slot/eligibility results
  passed in) — covering each filter dimension alone and combined with
  another (AND logic), empty-result cases, and sort ordering.
- `Where2Go/UI/BrowserPanel.lua` is WoW-API-dependent and not unit-tested,
  consistent with `Panel.lua`'s existing precedent — verified live in a
  manual checkpoint.

## Error handling

- An item with no stat entry in `Where2GoItemStats.STATS` (Sub-project A
  may not have data for every item) is simply excluded from any active
  stat filter rather than erroring — same "absence is not failure"
  posture as `DirectDrop.lua`'s existing eligibility ambiguity handling.
- Clearing the entire preferred list is irreversible from the addon's own
  perspective (no undo) — requires an explicit confirmation step in the
  UI before it takes effect, given the Global Constraints precedent this
  project has for destructive actions.

## Acceptance check

- A player can open the browser, filter down to a specific raid boss's
  drop list, check several items, click "선택 항목 추가," and see those
  items appear in the main panel's Drop (or Voidcore) tab targets on the
  next refresh.
- Filtering by slot and by stat both work and combine correctly (e.g.
  "trinkets with Haste" returns only items that are both).
- "선택 해제" clears staged-but-uncommitted checks without touching the
  saved preferred list; "선호 목록 전체 삭제" empties the saved list for
  the active mode only, after confirmation, and does not affect the other
  mode's list.
- Verified live in a real WoW client (manual checkpoint, per this
  project's established pattern for all WoW-API-dependent UI).

## Out of scope

- BiS (best-in-slot) curated collections per spec — deferred, tracked in
  `TODO.md`.
- Any change to the ranking/recommendation logic itself (`Ranking.lua`,
  `DirectDrop.lua`, `VoidcoreDrop.lua`) — this sub-project only changes
  how preferred items get added/removed and viewed, not how content gets
  ranked.
- Icon art / tooltips-on-hover polish beyond what's needed for basic
  usability — can be refined later if the plain-text row rendering proves
  insufficient once actually seen live.
