# Phase 7: Accurate Spec-Eligibility via Voidcore Tooltip Scanning — Design

**Status:** Design only — not planned or implemented. Written to capture a
concrete finding from Phase 6 Sub-project B's live checkpoint before
starting implementation elsewhere. Do not build from this doc without
first writing an implementation plan and confirming the open questions
below.

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

## The reference: VoidcoreAdvisor's tooltip-scanning approach

Already examined once before, for a different purpose — see
`docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md`'s Decisions
section, which deferred it for Phase 4's obtained-item tracking. This is
the SAME technique, proposed here for a different purpose: item-list
*filtering* by spec (Phase 6 Sub-project B's "spec eligible only"
checkbox and DirectDrop/VoidcoreDrop's own ranking), not obtained-item
history.

`rolferik12/VoidcoreAdvisor`, `Core/VoidcacheScan.lua` (828 lines) +
`Core/SpecInfo.lua` + `Core/SeasonData.lua`. Mechanism:

1. For each of the player's own class's specializations (typically 3-4,
   enumerated via `GetSpecializationInfo`), call `SetLootSpecialization(specID)`
   — this changes only the player's *loot specialization preference*, a
   real but low-stakes, fully reversible setting (no actual respec).
2. Wait `SPEC_CHANGE_DELAY` (1.2s in the reference) for the change to
   take effect, then read the **"Nebulous Voidcache" item's tooltip**
   (via `C_TooltipInfo`) for a given dungeon/encounter. Blizzard's own
   tooltip rendering for this bonus-roll currency item lists exactly the
   items that spec can receive from that content — already correctly
   filtered by weapon type, armor type, and role, since it's Blizzard's
   own server-computed loot table for that spec.
3. Parse the tooltip's item-name lines (retrying up to `MAX_RETRIES` times
   if the tooltip returns too few lines — `C_TooltipInfo` data can arrive
   incompletely on the first read) into a `{ [itemName] = true }` set.
4. Match names against a name→itemID cache (built from the addon's own
   known item pool, since the tooltip only gives names, not IDs) to
   produce `{ [specID] = { itemID, itemID, ... } }` per dungeon/encounter.
5. Repeat across every dungeon/raid encounter and every one of the
   player's specs, assembling `SeasonData.dungeons`/`SeasonData.raids`,
   each keyed `[instanceOrEncounterID].bySpec[difficultyID][specID] = { itemIDs }`.
6. Restore the player's original loot specialization setting when the
   scan finishes.

This only ever covers the scanning player's own class (matching
`GetItemSpecInfo`'s own scoping, and matching what this addon actually
needs — Where2Go has never tried to answer "which of all 40 specs across
the game can use this," only "can *my* current character use this").

## Open question — must be resolved before writing an implementation plan

**Does Where2Go's own Voidcore system use the same "Nebulous Voidcache"
item, or an equivalent per-spec-filtered tooltip?** `Where2Go/Core/VoidcoreDrop.lua`
and `VoidcoreHistory.lua` already track a Voidcore bonus-roll system, and
the reference addon is literally named after it — strongly suggesting
they're the same or a closely related in-game feature — but this has not
been confirmed. If Where2Go's Voidcore item's tooltip does NOT show a
per-spec-filtered item list the way Nebulous Voidcache does, this whole
approach doesn't transfer and needs rethinking (possibly scanning a
different tooltip, or the Encounter Journal's own loot-spec filter
instead — the Encounter Journal also respects `SetLootSpecialization`
for its "show loot for spec" toggle, which might be a viable alternative
scan target if Voidcore's own tooltip doesn't work this way).

**Verify this first, live in-game, before scoping an implementation
plan**: set loot specialization to a spec that couldn't use the currently
active spec's stat allocation (e.g. switch between a Balance Druid's
loot spec and a Feral Druid's loot spec), then check whether the
Voidcore item's tooltip content actually changes to reflect a different,
spec-appropriate item list.

## Sketch of what an implementation would need (not scoped as tasks yet)

- A new module, e.g. `Where2Go/Core/SpecEligibilityScan.lua`, holding the
  scan state machine (spec iteration, tooltip read/retry, combat-abort
  handling — `VoidcacheScan.lua`'s `_combatFrame` pattern is directly
  relevant, since a scan interrupted by combat must abort cleanly and
  restore loot spec).
- A precomputed data shape, e.g. `Where2Go/Core/SpecEligibility.lua`, in
  the same spirit as `ItemStats.lua`/`Sources.lua` — but note this data
  is **per-player-class**, not global like `ItemStats.lua`: it can only
  ever be scanned by a player of a given class, so unlike Sub-project A's
  Battle.net-API-driven generation, this cannot be pre-generated by one
  maintainer for all classes at once. Likely needs to live in
  `Where2GoCharDB` (per-character saved data, already used for preferred
  items) rather than a committed data file, OR be re-scanned each season
  by whoever plays each class — this changes the "regenerate each season"
  story from Sub-project A's model substantially and needs its own design
  decision.
- A trigger and UI for running the scan (a slash command or a button,
  plus a progress indicator — `VoidcoreAdvisor`'s progress-callback
  pattern is directly reusable) — this is a real, few-minutes-long,
  user-initiated action, not something to run silently on every login.
- Update `Where2GoDirectDrop.IsEligibleForSpec` (and by extension
  `VoidcoreDrop.lua` and the item browser) to consult this scanned data
  first when available, falling back to the current (known-imperfect)
  `GetItemSpecInfo`/`IsEquippableItem`-based logic when no scan has been
  run yet for the player's class — so the feature degrades gracefully
  rather than requiring the scan before anything works at all.

## Why this is its own phase, not a Sub-project B follow-up

This is materially bigger than anything else in Sub-project B: it
changes a real user-visible setting (loot specialization) as a side
effect, needs combat-safety and retry machinery, needs a new per-
character (not global) data storage story, and needs a scan-trigger UI.
It also isn't item-browser-specific — it would benefit DirectDrop's and
VoidcoreDrop's existing recommendation panels equally. Budget it as a
full brainstorm → spec → plan → subagent-driven-development cycle like
every other phase, once the open question above is confirmed.
