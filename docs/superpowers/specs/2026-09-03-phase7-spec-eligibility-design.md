# Phase 7: Accurate Spec-Eligibility via Voidcache Tooltip Scanning — Design

**Status:** Approved design. Both open questions from the original draft
(whether Where2Go's Voidcore tooltip behaves like Nebulous Voidcache, and
how to source per-dungeon/per-boss Voidcache item IDs without copying an
unlicensed third-party data file) are now resolved. Next step is an
implementation plan.

## Problem

`Where2Go/Core/DirectDrop.lua`'s `IsEligibleForSpec` (used by DirectDrop's
own ranking, `VoidcoreDrop.lua`, and Phase 6 Sub-project B's item browser)
has gone through two live-checkpoint-driven fixes that both turned out
incomplete:

1. **Original code**: `C_Item.GetItemSpecInfo(itemId)` returning an empty
   table `{}` was treated as "restricted, no spec matches" — but an empty
   table is also what Blizzard returns for universally-usable items
   (confirmed live: a necklace's `/dump C_Item.GetItemSpecInfo(...)`
   printed `[1]={ }`), so genuinely universal neck/ring items were
   silently marked ineligible. Fixed by treating empty the same as `nil`
   (eligible).
2. **That fix over-corrected**: an empty spec table is *also* what
   Blizzard returns for items the class cannot equip *at all* (wrong
   weapon type, e.g. a bow for a Shaman) — `GetItemSpecInfo` cannot tell
   "no restriction" apart from "not applicable." Tried gating on
   `C_Item.IsEquippableItem(itemId) == false` first, on the theory that
   this API authoritatively checks class/weapon/armor-type equippability.
   **Confirmed live: this did not fix the reported case** — the same
   wrong-weapon-type item still showed as eligible. `IsEquippableItem`'s
   actual behavior does not reliably do what its name suggests for this
   purpose (unverified why — possibly it only checks generic
   equippability like level/binding, not class/weapon-type proficiency).

Two Battle.net Web API endpoints were also checked and confirmed to have
no relevant data: `/data/wow/item/{id}`'s full raw response (no
class/spec-restriction field anywhere) and `/data/wow/playable-class/{id}`
(specializations/races/power-types only, no weapon/armor proficiency
data).

**Conclusion: there is no live or web API shortcut for "can this class,
in this spec, actually use this item." Blizzard doesn't expose the
computation directly — only the client's own rendering of it.**

## The reference technique: tooltip-scanning a per-content Voidcache item

`rolferik12/VoidcoreAdvisor` (GitHub) solves the same problem for its own
purposes. Its `Core/VoidcacheScan.lua` was fetched and read directly (via
`gh api repos/rolferik12/VoidcoreAdvisor/contents/...`) to confirm the
actual mechanism, since the technique matters but the repo carries **no
LICENSE file** — its code and data tables are not being reused verbatim
here, only the technique, which is independently reimplemented, plus a
handful of facts (item IDs) independently re-verified against Wowhead
rather than copied from their files.

Confirmed mechanism:

1. **The "Voidcache" is not one shared item** — Blizzard has a distinct
   item per dungeon and per raid boss, each literally named
   `"Nebulous Voidcache: <content name>"` (confirmed live on Wowhead for
   all 17 of Where2Go's own dungeons/bosses — see Data Sourcing below).
2. `C_TooltipInfo.GetItemByID(voidcacheItemId, ...)` is a pure data call
   — it does not require holding the item, being in the dungeon, or being
   near anything. This removes an entire class of feasibility concern the
   original draft of this doc worried about.
3. To read a given content's tooltip *for a specific spec*, call
   `SetLootSpecialization(specID)` first (a real, low-stakes, fully
   reversible player setting — not an actual respec), wait ~1.2s for it
   to take effect, then read the tooltip. Its item-name lines (from line
   7 onward, each prefixed `"- "`) list exactly what that spec can
   receive from that content — Blizzard's own server-computed,
   correctly-filtered loot table.
4. Tooltip reads need a retry/stabilize loop: too few lines on the first
   read means the data hasn't arrived yet; even once enough lines arrive,
   re-read until two consecutive reads return the same line count, since
   `C_TooltipInfo` data can still be settling.
5. Match parsed item **names** (tooltips give no IDs) against a
   name→itemID cache built from the addon's own known item pool.
6. On combat entry (`PLAYER_REGEN_DISABLED`) or a manual loot-spec change
   during the scan, abort cleanly and restore the player's original loot
   specialization.

**Confirmed live 2026-09-03** (this doc's original open question): the
Voidcore item's tooltip content actually changes when loot specialization
is switched between specs with different stat/weapon-type needs —
Where2Go's own Voidcore system behaves the same way as Nebulous
Voidcache, so this technique transfers directly.

## Data sourcing: per-dungeon/per-boss Voidcache item IDs

VoidcoreAdvisor's own committed `SeasonData.lua` happens to track the
exact same season's content as Where2Go's `Sources.lua` — its
`dungeonVoidcacheIDs`/`raidEncounterCacheIDs` instance/boss IDs are a
1:1 match against `Sources.lua`'s 8 dungeons and the 9 raid bosses
across `Sources.lua`'s two raid instances (The Tidebound Grotto: 1 boss;
The Venomous Abyss: 8 bosses). Since that repo has no license, its ID
table was used only as a **candidate list to verify independently**, not
copied. Verification: fetched every one of the 17 candidate item pages
directly from Wowhead (`wowhead.com/item=<id>`) and confirmed the name
against the matching `Sources.lua` dungeon/boss name for all 17 —
Blizzard's naming pattern is `"Nebulous Voidcache: <content name>"` for
both dungeons and raid bosses, and it held without exception:

| `Sources.lua` name | instanceId/bossId | Voidcache itemId | Confirmed Wowhead name |
|---|---|---|---|
| Altar of Fangs | 1322 | 279618 | Nebulous Voidcache: Altar of Fangs |
| Den of Nalorakk | 1311 | 279620 | Nebulous Voidcache: Den of Nalorakk |
| Murder Row | 1304 | 279623 | Nebulous Voidcache: Murder Row |
| The Blinding Vale | 1309 | 279619 | Nebulous Voidcache: The Blinding Vale |
| Voidscar Arena | 1313 | 279625 | Nebulous Voidcache: Voidscar Arena |
| Kings' Rest | 1041 | 279621 | Nebulous Voidcache: Kings' Rest |
| Ruby Life Pools | 1202 | 279622 | Nebulous Voidcache: Ruby Life Pools |
| Temple of Sethraliss | 1030 | 279624 | Nebulous Voidcache: Temple of Sethraliss |
| Nymrissa Wavecaller | 2849 | 274708 | Nebulous Voidcache: Nymrissa Wavecaller |
| Nek'zali the Soulcoiler | 2888 | 278285 | Nebulous Voidcache: Soulcoiler Nek'zali |
| Entombed Sentinels | 2874 | 278283 | Nebulous Voidcache: Entombed Sentinels |
| The Lost Explorers | 2894 | 278286 | Nebulous Voidcache: Tortollan Explorers |
| Vashnik the Malignant | 2882 | 278287 | Nebulous Voidcache: Vashnik |
| Sszorak | 2871 | 278288 | Nebulous Voidcache: Sszorak |
| The Twin Fangs | 2887 | 278289 | Nebulous Voidcache: The Twin Fangs |
| The Coiled Altar | 2883 | 278290 | Nebulous Voidcache: The Coiled Altar |
| Ula'tek | 2895 | 278284 | Nebulous Voidcache: Ula'tek |

All 17 dungeon/boss Voidcache item IDs Where2Go needs are independently
confirmed — no lookups remain for the implementation plan to defer.

**Decision: commit this mapping as a new static data file,
`Where2Go/Core/VoidcacheIds.lua`**, in the same spirit as `Sources.lua`
— `{ [instanceId] = voidcacheItemId }` for dungeons, `{ [bossId] =
voidcacheItemId }` for raid bosses. Refreshed each season via a
documented manual lookup procedure (added to `docs/SEASON_CHECKLIST.md`
alongside the existing `Sources.lua`/`ItemStats.lua` refresh steps), not
automated scraping — this only changes once per season and the lookup is
a simple named search per dungeon/boss.

## Design

### Scope decision: per-character scan, all of the player's own specs

Rejected the idea of a global, crowdsourced, all-classes data file like
VoidcoreAdvisor's `SeasonData.lua` `bySpec` tables (which span specs
across many different classes — that addon aggregates scans from many
contributors' characters). Where2Go is scoped to what a single player's
own characters can use, so per-character storage covering just that
character's class specs is the right size, matching `GetSpecialization`'s
own scoping and everything else `IsEligibleForSpec` already does.

**Decided (superseding this doc's earlier per-spec-lazy sketch):** scan
**all of the player's class's specs in one pass**, not one spec at a
time on demand. A class typically has 3-4 specs; scanning all of them
against the 17 known dungeon/boss Voidcache items in one background pass
is not much heavier than scanning one, and produces a complete,
stable per-character "database" — switching the item browser's spec
selector (see below) afterward never needs to wait on a fresh scan.

### Components

- **`Where2Go/Core/VoidcacheIds.lua`** (new, committed, static) — the
  data-sourcing section's mapping, plus a `SEASON_VERSION` string bumped
  whenever this file is regenerated for a new season.
- **`Where2Go/Core/SpecEligibilityScan.lua`** (new) — the scan engine.
  Public surface: `Start()` (kicks off a scan of all the player's current
  class specs across every `VoidcacheIds` entry, no-op if already
  running or already scanned for the current `SEASON_VERSION`),
  `IsRunning()`, a progress-callback registration (mirrors
  `VoidcacheScan.SetProgressCallback`). Internally: reimplements the
  tooltip read/retry/stabilize loop and the combat-abort
  (`PLAYER_REGEN_DISABLED`) guard described above, independently written
  against Where2Go's own module conventions (not copied from
  VoidcoreAdvisor). The tooltip-line-parsing step (raw tooltip lines →
  `{ [itemName] = true }`) is a pure function, unit-testable the same way
  `VoidcoreHistory.ParseItemIdFromLink` is.
- **`Where2GoCharDB.specEligibility`** (new per-character saved field):
  ```
  {
    seasonVersion = "<VoidcacheIds.SEASON_VERSION at scan time>",
    scannedAt = <epoch>,
    bySpec = { [specId] = { [itemId] = true, ... }, ... },
  }
  ```
  A version mismatch against `VoidcacheIds.SEASON_VERSION` marks the
  whole table stale and triggers a fresh full re-scan next time it's
  needed — no partial/incremental invalidation.
- **`Where2GoDirectDrop.IsEligibleForSpec(specId)`** (modified): if
  `Where2GoCharDB.specEligibility` exists and its `seasonVersion` matches
  current, consult `bySpec[specId]` directly (authoritative — no more
  `GetItemSpecInfo`/`IsEquippableItem` ambiguity for scanned specs).
  Otherwise, unchanged fallback to today's heuristic. This means
  DirectDrop's and VoidcoreDrop's existing panels get more accurate for
  free once a scan exists, with no changes to their own code beyond this
  function.
- **`Where2Go/UI/BrowserPanel.lua`** (modified): a new spec-selector
  dropdown, defaulting to the player's current active spec, listing all
  of the player's class specs (`GetSpecializationInfo`). The existing
  "current spec eligible only" checkbox filters against whichever spec is
  selected, via the same `IsEligibleForSpec(selectedSpecId)`. This
  dropdown is **browser-only** — DirectDrop's and VoidcoreDrop's own
  ranked-card panels keep using only the character's actual current
  active spec, matching their existing "what should I do right now"
  purpose; no spec-selector added there.

### Trigger

No manual button or slash command. Whenever DirectDrop's or VoidcoreDrop's
ranked panel is shown, or the item browser is opened — whichever happens
first in a session — check `Where2GoCharDB.specEligibility`; if missing
or its `seasonVersion` is stale, and the player is not in combat, start
`SpecEligibilityScan.Start()` in the background. The panel/browser
renders immediately using the existing fallback heuristic regardless, and
silently refreshes once the scan completes. A small, unobtrusive "스캔
중… (n/17 · specName)"-style progress row is shown wherever the
triggering panel is visible while a scan is in flight, since the scan
does briefly touch the player's real loot-specialization setting and a
silent, unexplained setting change would be confusing.

If combat starts mid-scan: abort, restore the original loot spec, and
don't retry automatically within the same session — the next panel/
browser open after combat ends will see the still-missing/stale data and
retry.

### Non-goals (explicitly out of scope for this phase)

- Not touching `VoidcoreHistory.lua`'s obtained-item tracking
  (`BONUS_ROLL_RESULT` listener) — a separate, already-shipped feature
  this phase does not modify.
- Not building a global, multi-class, crowdsourced data file — scan
  results stay per-character, covering only that character's own class.
- Not adding a spec-selector to DirectDrop's or VoidcoreDrop's main
  ranked-card panels — only the item browser gets one.

### Testing

- `SpecEligibilityScan.lua`'s tooltip-line-parsing function: pure,
  unit-tested in a new `tests/specEligibilityScan_spec.lua` (line-count
  threshold, `"- "` prefix stripping, color-code stripping, empty/short
  tooltip handling) — same pattern as `VoidcoreHistory.ParseItemIdFromLink`.
- `VoidcacheIds.lua`: a coverage test asserting every `Sources.lua`
  dungeon `instanceId` and raid `bossId` has a corresponding entry, same
  pattern as `ItemStats.lua`'s `Sources.lua`-coverage test.
- The scan state machine itself (combat-abort, retry/stabilize timing,
  `SetLootSpecialization` sequencing) is WoW-API-dependent like
  `VoidcoreDrop.lua`/`VoidcoreHistory.lua`'s event wiring — not
  unit-tested, verified live instead.

## Why this is its own phase, not a Sub-project B follow-up

This is materially bigger than anything else in Sub-project B: it
changes a real user-visible setting (loot specialization) as a side
effect, needs combat-safety and retry machinery, needs a new
per-character data storage story with its own staleness/versioning, and
adds new UI (the browser's spec selector). It also isn't
item-browser-specific — it improves DirectDrop's and VoidcoreDrop's
existing recommendation panels equally, for free, via the shared
`IsEligibleForSpec` function. Budgeted as a full brainstorm → spec → plan
→ subagent-driven-development cycle like every other phase.
