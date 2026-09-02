# Phase 2: Preferred Items & Equipment Comparison — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 2 only (preferred-item storage,
upgrade-track/item-level comparison against equipped gear). Builds on the
Phase 1 addon skeleton (`docs/superpowers/specs/2026-09-02-phase1-foundations-design.md`).

## Decisions carried into this design

- **Item registration UI**: a slash command, `/where2go pref add|remove|list
  <itemID> <drop|voidcore>`. Purpose is a required argument, not defaulted,
  to avoid silent misfiling. A real search/select UI is Phase 3's job; this
  is verification tooling for Phase 2.
- **"Purpose" in `docs/DEVELOPMENT_PLAN.md`'s "per character and per
  purpose"** means direct-drop vs. Voidcore, matching `docs/DECISIONS.md`'s
  "Separate player intents" rule. Each purpose gets its own preferred-item
  set; neither may read or mutate the other's.
- **Upgrade-track data provenance**: ported from `codex/pre-restart-backup`
  (the pre-restart implementation), specifically its `Core/Constants.lua`
  `UPGRADE_TRACKS` table and `Core/Equipment.lua`'s bonus-ID-parsing/track-
  detection logic. This is reused as *empirically measured fact about the
  current game season* (bonus ID → item level ranges, confirmed in-client
  via `/where2go scanbonus` against real items), not as inherited
  implementation — `docs/DECISIONS.md`'s "previous implementation is not
  the new baseline" is about architecture and features, not about
  re-measuring facts that haven't changed. Verified same `Interface: 120100`
  and a same-day commit, so it's current, not stale.
- **Verification surface**: `/where2go compare` prints one chat line per
  preferred item currently found in the player's bags or equipped,
  reporting whether that real instance (real bonus IDs) is an upgrade over
  the corresponding equipped slot(s). No new UI widget — Phase 3 owns the
  real recommendation panel.
- **Track-over-item-level semantics**: when both the candidate and the
  equipped item resolve to a recognized upgrade track, the higher track
  always wins regardless of nominal item level (tracks overlap by design —
  see Reference material). Item level is only the tiebreaker within the
  same track, or the fallback when either side has no recognized track
  (e.g. crafted gear, which uses an unrelated bonus-ID scheme).

## Reference material

- `docs/DEVELOPMENT_PLAN.md` Phase 2 bullets and acceptance check.
- `docs/DECISIONS.md`'s "Separate player intents" and "Preferred items and
  ownership" sections.
- `codex/pre-restart-backup` branch, `Core/Constants.lua` (`UPGRADE_TRACKS`,
  `SLOT_TO_INVSLOT`, `FINGER_SLOTS`, `TRINKET_SLOTS`) and `Core/Equipment.lua`
  (bonus-ID parsing, `GetTrackInfo`, `GetEquipped`) — source of the ported
  track data and comparison approach.
- `C:\Users\hangy\ai\vault\wiki\wow-item-level-bonus-id-system.md` — the
  general bonus-ID/item-link-field-layout knowledge this data instantiates
  for the current season; explains *why* tracks overlap by design.

## Architecture

```
Where2Go/
├── Where2Go.toc                 add Tracks, Compare, Equipment (see load order)
├── Core/
│   ├── Constants.lua            EXTEND: add SLOT_TO_INVSLOT, FINGER_SLOTS,
│   │                             TRINKET_SLOTS; change BuildDefaultCharDB's
│   │                             preferredItems shape (see Data flow)
│   ├── Tracks.lua                NEW, pure data: UPGRADE_TRACKS (4 tracks:
│   │                             Veteran/Champion/Hero/Myth, each
│   │                             bonusIdStart + 6 ranks' ilvls)
│   ├── Fixtures.lua             unchanged
│   ├── Compare.lua               NEW, pure function: IsBetterCandidate
│   ├── Equipment.lua             NEW, WoW-API-dependent: bonus-ID parsing,
│   │                             GetTrackInfo, GetEquipped (slot-aware,
│   │                             FINGER/TRINKET return 2 entries)
│   └── Init.lua                 EXTEND: route `/where2go pref ...` and
│                                 `/where2go compare` subcommands
└── UI/
    └── Panel.lua                 unchanged

tests/
├── run_tests.lua                 EXTEND: add tracks_spec, compare_spec
├── tracks_spec.lua                NEW
├── compare_spec.lua               NEW
└── (constants_spec.lua updated for the new preferredItems default shape)
```

**TOC load order**: `Core\Constants.lua`, `Core\Tracks.lua`,
`Core\Fixtures.lua`, `Core\Compare.lua`, `Core\Equipment.lua`,
`Core\Init.lua`, `UI\Panel.lua`. Constants and Tracks must precede
Equipment (which reads both); Compare has zero dependencies so its
position is flexible, placed with the other pure files before the
WoW-API-dependent ones, matching Phase 1's pure-data-first convention.

## Components

- **`Core/Tracks.lua`** (pure data): `Where2GoTracks.UPGRADE_TRACKS`, a
  table of 4 tracks (`VETERAN`, `CHAMPION`, `HERO`, `MYTH`), each
  `{ order, label, bonusIdStart, ilvls = {6 numbers} }`. Isolated from
  `Constants.lua` because these exact numbers are the one thing a future
  season's restart will need to re-measure and replace wholesale — keeping
  them in their own file makes that a one-file change.
- **`Core/Constants.lua`** (pure data, extended): adds
  `SLOT_TO_INVSLOT` (11 single-instance slots → `GetInventorySlotInfo`
  name), `FINGER_SLOTS`/`TRINKET_SLOTS` (2-element arrays, the two ring/
  trinket inventory slot names). These are stable WoW API slot names, not
  season-specific, so they belong with the other durable constants rather
  than with the season-specific track data.
- **`Core/Compare.lua`** (pure function): `Where2GoCompare.IsBetterCandidate(candidate, equipped)`
  where both arguments are `{ track = {order=N,...} or nil, ilvl = number or nil }`.
  Algorithm: if both sides have a recognized track and the orders differ,
  the higher order wins outright (item level is not even consulted — this
  is what makes a rank-1 item on a higher track beat a maxed rank-6 item on
  a lower track despite a lower nominal item level). If both have a track
  and the same order, or if either side lacks a track, fall back to a
  strict item-level comparison. No WoW API references — testable standalone.
- **`Core/Equipment.lua`** (WoW-API-dependent, not unit-tested): ports the
  pre-restart branch's item-link bonus-ID parser (manual itemString field
  split — WoW has no official "get bonus IDs from a link" API) and
  `GetTrackInfo(link)` (matches bonus IDs against `Where2GoTracks.UPGRADE_TRACKS`
  ranges). `GetEquipped(slotId)` returns one entry per physical slot
  (2 entries for `FINGER`/`TRINKET`, 1 otherwise), each
  `{ itemId, ilvl, track }`.
- **`Core/Init.lua`** (extended): `/where2go pref add <itemID> <drop|voidcore>`,
  `remove`, and `list` mutate/read `Where2GoCharDB.preferredItems[purpose]`.
  `/where2go compare` iterates both purposes' preferred-item sets, and for
  each item ID found as a real link in bags (`Core/Equipment.lua`-level bag
  scan) or equipped, resolves that instance's track/ilvl, compares against
  the relevant equipped slot(s) via `Where2GoCompare.IsBetterCandidate`, and
  prints one chat line per match.

## Data flow

1. Player runs `/where2go pref add 271483 drop` → `Where2GoCharDB.preferredItems.DROP[271483] = true`.
2. Player runs `/where2go compare`.
3. For each purpose, for each preferred item ID present as a set key: scan
   bags and equipped slots for a real item link matching that ID (if none
   found, skip — nothing to compare yet).
4. For each match: `Core/Equipment.lua` parses the link's bonus IDs,
   resolves track+rank+ilvl via `Where2GoTracks.UPGRADE_TRACKS`.
5. Determine the relevant equipped slot(s) for that item (via its
   `GetItemInfo`-reported equip slot, mapped through
   `Where2GoConstants.SLOT_TO_INVSLOT`/`FINGER_SLOTS`/`TRINKET_SLOTS`), read
   the currently-equipped item(s) there the same way.
6. `Where2GoCompare.IsBetterCandidate` decides upgrade/not; print a chat
   line naming the item, its track/rank/ilvl, the equipped comparison
   point, and the verdict.

## Testing

- `tracks_spec.lua`: asserts `UPGRADE_TRACKS` has all 4 expected keys, each
  `bonusIdStart` is a positive integer, each `ilvls` has exactly 6 entries
  in strictly increasing order, and `order` values are 1-4 with no
  duplicates (a data-integrity contract, not a re-verification of the
  numbers' real-world accuracy — that provenance is the ported source).
- `compare_spec.lua`: deterministic table-driven tests covering — same
  track, higher ilvl wins; same track, equal ilvl is not better; higher
  track wins despite lower nominal ilvl (the overlap case, the one
  genuinely non-obvious rule this module exists to encode); candidate has
  no track vs. equipped does → falls back to ilvl; neither has a track →
  falls back to ilvl.
- `Core/Equipment.lua` and the extended `Core/Init.lua` are WoW-API-
  dependent and not unit-tested, same as Phase 1's `Init.lua`/`Panel.lua` —
  verified live in-client per the acceptance check below.
- `constants_spec.lua` is updated in place for `BuildDefaultCharDB`'s new
  `preferredItems = { DROP = {}, VOIDCORE = {} }` shape (still asserting
  the independent-table regression guard from Phase 1, now for both
  purpose tables).

## Error handling

- `/where2go pref add/remove` validate the purpose argument is exactly
  `drop` or `voidcore` (case-insensitive) and the item ID argument is a
  positive integer; on failure, print a one-line usage message rather than
  erroring. No further validation (e.g. checking the item ID exists) —
  out of scope, YAGNI.
- `Core/Equipment.lua`'s bonus-ID parser returns an empty ID list for a nil
  or malformed link rather than erroring, matching the ported code's
  existing behavior.

## Acceptance check (from `docs/DEVELOPMENT_PLAN.md`)

- Deterministic tests cover the comparison rules (`compare_spec.lua`).
- A live-client check confirms one higher-track candidate is shown: add a
  preferred item via `/where2go pref add`, have a real instance of it on a
  higher track than the equipped item in that slot (in bags or equipped),
  run `/where2go compare`, and confirm the chat output correctly reports it
  as an upgrade.

## Out of scope for Phase 2

- The real recommendation panel / expandable cards (Phase 3).
- Direct-drop pool ranking math and Encounter Journal integration (Phase 3).
- Voidcore history and its separate pool-exclusion rules (Phase 4).
- A real item search/picker UI for registering preferred items (Phase 3+;
  the slash command is verification tooling only).
- General ownership/ever-looted history (`docs/DECISIONS.md` explicitly
  says this must not suppress a candidate on its own — Phase 2's instance-
  based, bonus-ID-aware comparison already satisfies this by construction,
  since it never keys off "have I ever owned this item ID" at all).
