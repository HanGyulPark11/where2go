# Phase 8: Precomputed All-Class Spec-Eligibility Data — Design

**Status:** Approved design (brainstormed 2026-09-04, locked-in decisions
confirmed by user). This doc resolves the remaining open implementation
details and is ready for an implementation plan.

## Problem

Phase 7 (`docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`) shipped a
per-character live scan: every player's own client runs
`SpecEligibilityScan.Start()` automatically the first time a Where2Go
panel opens, tooltip-scanning 17 Voidcache items across that character's
own class specs (~40 seconds), and caches the result in
`Where2GoCharDB.specEligibility`. This works, but every single player of
every class pays that one-time cost themselves, and the addon changes
their real loot-specialization setting (reversibly, but still a visible
side effect) to do it.

The user wants to eliminate this entirely for regular players: precompute
spec-eligibility data for **every class/spec in the game**, once, and
ship it as committed static data — the same distribution model this
project already uses for `Sources.lua` and `ItemStats.lua`. No shipped
addon client should ever need to run the live scan.

## Scope decision (recap, locked in)

- **Coverage**: all classes in the game, not just the classes the user
  currently plays. The user is willing to roll throwaway characters
  purely to scan classes they don't otherwise have, since
  `C_TooltipInfo.GetItemByID` is level/gear-independent — only needs a
  chosen spec, not a geared, max-level character.
- **Consumption**: full replacement, not a hybrid. `IsEligibleForSpec`
  stops reading `Where2GoCharDB.specEligibility` (Phase 7's per-character
  cache) entirely and instead consults the new committed data file
  directly. No player-side scan trigger remains.
- **Scan engine reuse**: `Core/SpecEligibilityScan.lua`'s tooltip
  read/retry/stabilize loop, combat-abort guard, and cold-cache
  empty-result guard are unchanged and reused as-is — only *what* it
  writes to and *what triggers it* change.

## Data schema: `Where2Go/Core/SpecEligibilityData.lua`

New committed, static data file, following the `Sources.lua`/
`ItemStats.lua` convention (header comment forbidding hand-edits,
regenerate-from-source only):

```lua
Where2GoSpecEligibilityData = {}

Where2GoSpecEligibilityData.BY_SPEC = {
    [specId] = { [itemId] = true, ... },
    ...
}
```

Flat across every class — the same shape Phase 7's
`Where2GoCharDB.specEligibility.bySpec` already used, just promoted from
a per-character runtime cache to a committed global table covering every
spec in the game, not just one character's class. No `seasonVersion`
field inside the file itself: like `Sources.lua`/`ItemStats.lua`, this
file's freshness is a data-prep workflow concern tracked in
`docs/SEASON_CHECKLIST.md`, not a runtime staleness check — there is no
player-facing scan to trigger a re-check against, so a version field
would have no reader.

## Generation workflow (maintainer-only)

### Where the scan writes: `Where2GoDB.specEligibilityExport`

The scan engine's write target moves from
`Where2GoCharDB.specEligibility` (per-character, overwritten wholesale
each scan) to `Where2GoDB.specEligibilityExport` (account-wide,
**merged/accumulated** across scans):

```lua
Where2GoDB.specEligibilityExport = {
    seasonVersion = "<Where2GoConstants.SEASON_LABEL at first scan of this table>",
    bySpec = { [specId] = { [itemId] = true, ... }, ... },
}
```

`FinalizeScan` in `SpecEligibilityScan.lua` changes its write from
replacing `Where2GoCharDB.specEligibility` to merging into
`Where2GoDB.specEligibilityExport.bySpec[specId]` (adding entries, never
clearing existing ones for specs not scanned this pass) — so scanning
Warrior today and Mage tomorrow both accumulate in the same growing
table across sessions/characters. The existing cold-cache empty-result
guard (refuse to persist a spec's result if real tooltip names were
parsed but none resolved to a known item ID) applies unchanged, now
guarding the merge instead of the per-character overwrite.

**Stale-season guard**: when a scan run starts, compare
`Where2GoDB.specEligibilityExport.seasonVersion` (if the table already
exists from a prior season) against the current
`Where2GoConstants.SEASON_LABEL`. On mismatch, print a warning
(`"Where2Go: existing export data is from a previous season (%s) -- run '/where2go genspec reset' first or it will be merged with the new season's data."`)
and abort the new scan rather than silently merging two seasons' data
together. A companion `/where2go genspec reset` subcommand clears
`Where2GoDB.specEligibilityExport` entirely (with a confirmation print,
since this discards accumulated progress) so the maintainer can
deliberately start the new season's generation pass clean.

### Trigger: `/where2go genspec` slash command

Replaces Phase 7's automatic `EnsureScanned()` trigger. New subcommand in
`Where2Go/Core/Init.lua`'s `SlashCmdList["WHERE2GO"]` handler:

- `/where2go genspec` — before starting, prints the current character's
  class and the specs about to be scanned (e.g.
  `"Where2Go: scanning 3 specs for Warrior (Arms, Fury, Protection) -- make sure this is a throwaway/safe character, this will change your loot specialization during the scan."`),
  then calls `SpecEligibilityScan.Start()` exactly as Phase 7 did, except
  `FinalizeScan` now targets `Where2GoDB.specEligibilityExport` (see
  above). Progress is printed to chat via the same
  `SetProgressCallback` mechanism Phase 7's UI panels used, registered
  under a `"genspec"` name — no dedicated UI panel needed since this is a
  maintainer-only, no-audience command (`"Where2Go: scanning... 5/51 (Fury)"`
  every step would be too noisy; instead print only on spec-boundary
  changes and on completion).
- `/where2go genspec reset` — clears `Where2GoDB.specEligibilityExport`
  after a confirmation print, as described above.
- Combat-abort and manual-loot-spec-change-abort behave exactly as Phase
  7 already built them (unchanged engine internals).

Because `Start()` already scans **all of the current character's class
specs in one pass** (Phase 7's existing behavior), covering every class
in the game means running `/where2go genspec` once per class — i.e. the
maintainer logs into (or creates) one character per class, runs the
command, waits ~40 seconds, and moves to the next class across as many
sessions as needed, since the export table accumulates rather than
resets.

### Manual export step: SavedVariables to committed file

No new export UI or file-write command — WoW addons cannot write files
directly. Same manual process as `Sources.lua`/`ItemStats.lua`'s
data-prep scripts, but by hand instead of a Python script (no API
involved here, unlike those two):

1. Log out (SavedVariables only flush to disk on logout/reload) so
   `WTF/Account/<acct>/SavedVariables/Where2Go.lua` reflects the latest
   `Where2GoDB.specEligibilityExport`.
2. Open that file and copy the `specEligibilityExport.bySpec` table.
3. **Before pasting into the committed file**, eyeball it: does every
   expected spec have a plausible non-empty item count (roughly in the
   same ballpark across specs of the same class, never zero for a spec
   that was actually scanned)? This is the human mitigation for the
   cold-cache-at-export-step risk flagged during brainstorming — a
   silently-empty spec baked into committed data would incorrectly mark
   that spec ineligible for everything, for every player, until the next
   regeneration.
4. Hand-merge into `Where2Go/Core/SpecEligibilityData.lua`'s
   `BY_SPEC` table (adding/replacing entries per `specId`), matching this
   project's established "human reviews the diff, never auto-overwrite"
   convention for committed data files.

## Consumption: `Where2GoDirectDrop.IsEligibleForSpec`

`Where2Go/Core/DirectDrop.lua`'s `IsEligibleForSpec` changes its primary
check from Phase 7's `Where2GoCharDB.specEligibility.bySpec` to the new
committed `Where2GoSpecEligibilityData.BY_SPEC`:

```lua
function Where2GoDirectDrop.IsEligibleForSpec(specId)
    return function(itemId)
        local bySpec = Where2GoSpecEligibilityData.BY_SPEC[specId]
        if bySpec and next(bySpec) ~= nil then
            return bySpec[itemId] == true
        end
        -- unchanged fallback: IsEquippableItem + GetItemSpecInfo heuristic
        ...
    end
end
```

Precedence order for any given spec: committed data first (authoritative
Blizzard-computed loot table, whenever this spec has been generated and
committed) → old heuristic last (covers any spec not yet regenerated for
the current season, or a mid-season item addition not yet re-scanned).
No per-character live-scan tier remains in this function at all — that
whole code path is deleted, not just bypassed.

## UI changes: remove the automatic-scan trigger

`Where2Go/UI/Panel.lua` and `Where2Go/UI/BrowserPanel.lua` both currently
call `Where2GoSpecEligibilityScan.SetProgressCallback(...)` and
`EnsureScanned()` when shown, and render a `scanStatusText` progress row
("Where2Go: scanning spec eligibility... n/total (spec)"). All of this
gets removed from both files — no shipped-client scan, so nothing to
show progress for. `EnsureScanned()` itself (the function that decided
whether the per-character cache was stale) is deleted from
`SpecEligibilityScan.lua`, since nothing calls it anymore; `Start()` and
`FinalizeScan` stay, now only reachable via `/where2go genspec`.

## `docs/SEASON_CHECKLIST.md` update

New step (inserted after the existing step 4, "Refresh
`Where2Go/Core/VoidcacheIds.lua`", since this data depends on that file's
item IDs being current for the new season):

> **4a. Regenerate `Where2Go/Core/SpecEligibilityData.lua`.** Run
> `/where2go genspec reset` once to clear any leftover data from the
> previous season, then run `/where2go genspec` once per class (log into
> or create one character per class), following the eyeball-check and
> hand-merge steps in
> `docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md`'s
> Generation Workflow section. This is the slowest step in this checklist
> (one full pass per class, ~40 seconds of scanning each, spread across
> as many sessions as needed) — start it early rather than last.

## Non-goals (explicitly out of scope)

- Not building a separate companion addon/tool for generation (like
  VoidcoreAdvisor's "VoidcoreAdvisorGen") — reuses
  `SpecEligibilityScan.lua` in-place via a new slash command, per the
  locked-in decision.
- Not adding any in-game export/file-write mechanism — WoW addons can't
  write files; the manual SavedVariables-copy step is unavoidable and
  matches this project's existing data-prep convention.
- Not adding a runtime staleness/version check inside
  `SpecEligibilityData.lua` itself — freshness is a `SEASON_CHECKLIST.md`
  workflow concern, not something `IsEligibleForSpec` checks at read
  time, matching `Sources.lua`/`ItemStats.lua`.
- Not touching `VoidcoreHistory.lua`'s obtained-item tracking or
  `VoidcoreDrop.lua`'s own consumption of `IsEligibleForSpec` beyond what
  the changed function signature/behavior already covers for free.

## Testing

- `tests/specEligibilityScan_spec.lua` (Phase 7's existing tooltip-parse
  tests) stays unchanged — the pure parsing function isn't touched.
- New coverage test for `SpecEligibilityData.lua`, same pattern as
  `ItemStats.lua`'s `Sources.lua`-coverage test: for every class/spec
  `GetSpecializationInfo`-style ID currently in the game (a small static
  list of known spec IDs, since this file can't call live WoW APIs in
  the plain-Lua test harness), assert `BY_SPEC[specId]` exists and is
  non-empty. Catches a forgotten class during a season regeneration
  before it ships silently broken.
- `IsEligibleForSpec`'s modified precedence order is WoW-API-dependent
  (like before) — not unit-tested, verified live instead: one item known
  eligible via committed data, one item known only via the fallback
  heuristic (a spec not yet in `BY_SPEC`).
- The `/where2go genspec` / `genspec reset` command handlers: thin
  argument-parsing wrappers around already-tested/live-verified engine
  code, same testing tier as the existing `/where2go pref`/`compare`
  handlers (not unit-tested, manual verification).
