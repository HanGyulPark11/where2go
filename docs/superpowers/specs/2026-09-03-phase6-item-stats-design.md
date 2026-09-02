# Phase 6, Sub-project A: Item Stat Metadata — Design

Status: approved
Scope: fetch and store per-item stat metadata (primary stat, secondary
stat types) for every item currently referenced in `Where2Go/Core/Sources.lua`,
so Sub-project B's item browser can filter/group items by stat. This
sub-project produces data only — no UI.

## Background

The user wants a real item-browsing experience (Phase 6, Sub-project B)
where a player can filter the full dungeon/raid item pool by stat type
(e.g. "show me everything with Haste"). `Sources.lua` only has item IDs;
it has no stat information. Per
[[vault knowledge]] `wow-item-level-bonus-id-system`, Battle.net's
`/data/wow/item/{id}` endpoint's `preview_item.stats` field reports an
item's stat *types* (primary stat, and which secondary stats it rolls —
Crit/Haste/Mastery/Versatility) accurately regardless of bonus ID/upgrade
track, because stat type composition is fixed per item and doesn't change
with item level scaling. This makes it safe to pre-fetch once per season
rather than needing a live in-client lookup.

## Decisions

- **Fetch once per season, store as a static Lua data file** — matching
  Sub-project 1 (Phase 5)'s pattern for `Sources.lua`: a Python script
  under `tools/data-prep/` calls the Battle.net API and generates Lua,
  diffed and reviewed by a human before replacing the committed file, not
  auto-overwritten.
- **Scope: only items in `Sources.lua`** — not the entire game's item
  database. The script reads `Where2Go/Core/Sources.lua` (or receives the
  same item ID set some other simple way) to know which items to fetch
  stats for, rather than maintaining a second independent ID list that
  could drift out of sync.
- **Slot information is NOT part of this dataset** — `Where2Go/Core/Equipment.lua`
  already resolves an item's normalized slot live in-client via
  `C_Item.GetItemInfoInstant(itemId)` + `Where2GoConstants.EQUIPLOC_TO_SLOT`.
  Sub-project B's browser reuses this existing live lookup instead of
  duplicating slot data in this new static file.
- **Data shape**: for each item ID, record the primary stat (Strength/
  Agility/Intellect, or none for e.g. a pure-stamina trinket) and the set
  of secondary stats it carries (any subset of Crit/Haste/Mastery/
  Versatility) plus whether each is the *negated* (inactive) option for
  armor with multiple possible primary stats, matching the API's own
  `is_negated` flag noted in the vault knowledge.
- **Re-run cadence**: this is a new step added to the existing
  `docs/SEASON_CHECKLIST.md` (Phase 5, Sub-project 1) season-changeover
  procedure, not a separate standalone process a maintainer has to
  remember independently.

## Architecture

```
tools/data-prep/generate_item_stats.py   NEW: reads Where2Go/Core/Sources.lua's
                                          item IDs, calls Battle.net API per
                                          item, writes staged output to
                                          tools/data-prep/scratch/ItemStats.lua.new
                                          and diffs against the committed file
                                          -- mirrors generate_sources.py's
                                          fetch -> render -> diff -> stage flow

Where2Go/Core/ItemStats.lua               NEW: Where2GoItemStats.STATS[itemId] =
                                          { primaryStat = "AGILITY" | "STRENGTH" |
                                            "INTELLECT" | nil,
                                            secondaryStats = { "CRIT_RATING",
                                            "HASTE_RATING", ... } }
```

## Components

- **`tools/data-prep/generate_item_stats.py`** (new): reuses
  `generate_sources.py`'s existing `get_token()`/`api_get()` pattern (the
  two scripts can share logic by importing from `generate_sources.py`, or
  duplicate the small amount of shared code — decided during
  implementation planning, not here, since it's a small enough amount of
  code that either is reasonable). Parses `Where2Go/Core/Sources.lua`
  with a simple regex/text scan to collect every distinct item ID
  referenced (dungeons + raids), calls `/data/wow/item/{id}` for each,
  extracts `preview_item.stats`, and renders a `Where2GoItemStats.STATS`
  Lua table. Writes to `tools/data-prep/scratch/ItemStats.lua.new` and
  prints a diff against `Where2Go/Core/ItemStats.lua`, same review-gate
  pattern as `generate_sources.py`.
- **`Where2Go/Core/ItemStats.lua`** (new, committed): pure static data,
  no WoW API dependency — unit-testable the same way `Sources.lua` is
  (a structural spec asserting every item referenced in `Sources.lua`
  also has an entry here, and vice versa is not required since not every
  fetched item necessarily has stats — e.g. some quest-reward-shaped
  entries might have none).

## Data flow

1. Developer runs `tools/data-prep/generate_item_stats.py` (added as a
   new step in `docs/SEASON_CHECKLIST.md`).
2. Script reads every item ID out of the committed `Sources.lua`, fetches
   each item's `preview_item.stats` from Battle.net, and renders
   `Where2GoItemStats.STATS`.
3. Diff reviewed by a human, then copied over `Where2Go/Core/ItemStats.lua`
   manually — same manual-replace safety gate as `Sources.lua`.
4. Sub-project B's browser code requires this file (`Where2GoItemStats`)
   at runtime to filter/group by stat; an item with no entry (or an entry
   with an empty `secondaryStats`) is simply not matched by any
   stat-based filter, not treated as an error.

## Testing

- A new spec (`tests/itemstats_spec.lua`, style matching `sources_spec.lua`)
  asserts `Where2GoItemStats.STATS` is a non-empty table and that every
  entry's `primaryStat` (if present) and `secondaryStats` entries (if any)
  are one of the known valid stat-name strings — catches a malformed
  generation run without needing the live API.
- `generate_item_stats.py` itself gets no automated test, matching
  `generate_sources.py`'s precedent (low-frequency, human-supervised
  tool; the diff-review step is the real safety net).

## Error handling

- Same posture as `generate_sources.py`: missing/invalid credentials or a
  bad item ID surface as an uncaught exception with the failing request
  visible, not swallowed.
- An item whose API response has no `stats` field at all (should be rare,
  but not impossible for some item types) is recorded with an empty/nil
  entry rather than the whole run failing.

## Acceptance check

- Running the script against the current `Sources.lua` item set and
  reviewing the diff against a freshly-generated `Where2Go/Core/ItemStats.lua`
  produces stat data for the large majority of real gear items (some
  non-armor "items" in the pool, if any, may legitimately have no stats).
- `tests/itemstats_spec.lua` passes.

## Out of scope

- Item icons, item names (already resolved elsewhere via `C_Item.GetItemInfo`).
- Slot data (already resolved live via `C_Item.GetItemInfoInstant`, per
  the Decisions section above).
- BiS (best-in-slot) curated rankings per spec — a real Sub-project B
  feature request, explicitly deferred; recorded in `TODO.md` as future
  work once a data source/collection process is designed.
