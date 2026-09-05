# Phase 8b: Encounter-Journal-Based `genspec` Rescan — Design

**Status:** Approved design (brainstormed 2026-09-05, locked-in decisions
confirmed by user). This doc resolves the remaining open implementation
details and is ready for an implementation plan.

## Problem

Phase 8 (`docs/superpowers/specs/2026-09-04-phase8-precomputed-spec-data-design.md`)
shipped `Core/SpecEligibilityData.lua`'s `BY_SPEC` table and a
maintainer-only `/where2go genspec` command that generates it by reusing
Phase 7's scan engine (`Core/SpecEligibilityScan.lua`): read the
"Nebulous Voidcache" item's tooltip once per loot-spec setting
(`SetLootSpecialization`), which reflects Blizzard's own correctly
filtered loot list for that spec.

That mechanism only works for the *scanning character's own class* —
`GetNumSpecializations()`/`SetLootSpecialization()` are both scoped to
the logged-in character. Covering every class in the game (Phase 8's
locked-in coverage target) requires logging into (or rolling) one
character per class, and the scan itself takes ~40 seconds per class
(tooltip reads with retry/stabilize delays), spread across as many
sessions as needed.

A live spike (2026-09-05, throwaway `Where2Go/Core/EJDiagnostic.lua`)
found and confirmed a better mechanism: Blizzard's Encounter Journal
loot filter (`EJ_SetLootFilter(classID, specID)` +
`C_EncounterJournal.GetLootInfoByIndex`) is **class-agnostic** — its own
UI (`Blizzard_ClassMenu.lua`'s `ClassMenu.InitClassSpecDropdown`)
enumerates every class via `GetNumClasses()`/`GetClassInfo(index)` and
every spec of any chosen class via
`C_SpecializationInfo.GetNumSpecializationsForClassID(classID)` /
`GetSpecializationInfoForClassID(classID, index)` — none of these three
calls are restricted to the player's own class. The user live-tested
this against Zul'jan (Altar of Fangs, 12 items) filtered by all 4 Druid
specs and confirmed it correctly: excludes every non-leather item across
the board, includes every stat-agnostic universal item across the board,
and correctly splits same-armor-type/different-primary-stat items (an
intellect item shown only to Balance/Restoration, not Feral/Guardian) —
at least the precision the old heuristic needed and Phase 7 was built to
fix. `GetLootInfoByIndex(i).itemID` also returns the real numeric item ID
directly, unlike the Voidcache tooltip's name-only text, removing the
old mechanism's cold-item-cache name-resolution risk entirely.

This lets a single character generate `BY_SPEC` data for every class in
the game, and removes the alt-per-class requirement Phase 8's original
design accepted as a real cost.

## Scope decision (locked in)

- **Coverage/trigger model**: `/where2go genspec` becomes a single
  command that scans **every class and spec in the game in one run**,
  from whichever character runs it — not "run once per class you have a
  character of." No per-class argument (e.g. `/where2go genspec 7`) is
  added; simplicity over the marginal convenience of a partial rescan,
  since a full rescan is expected to be fast (see Performance below).
- **`Core/VoidcacheIds.lua` is KEPT, not deleted**, even though this
  redesign removes its only current consumer
  (`SpecEligibilityScan.lua`). See "Why VoidcacheIds.lua survives" below.
- **Non-gear pollution**: the redesigned scan never trusts
  `C_EncounterJournal.GetLootInfoByIndex`'s per-boss loot list as the
  source of truth for "what items exist" (a boss's raw EJ loot list can
  include mounts/pets/toys/quest items/crafting reagents mixed in with
  real gear — see `EncounterJournal_LootUpdate`'s own
  `veryRareLoot`/`extremelyRareLoot`/`perPlayerLoot` bucketing, which
  hints at this). It only ever tests **membership** of itemIds
  `Where2GoSources.lua` already tracks for that specific encounter.
  Since non-gear items were never in `Sources.lua` to begin with, they
  structurally cannot appear in `BY_SPEC`.
- **Output format, export mechanism, and hand-merge workflow are
  unchanged from Phase 8**: `Core/SpecEligibilityData.lua`'s
  `BY_SPEC = { [specId] = { [itemId] = true } }`,
  `Where2GoDB.specEligibilityExport = { seasonVersion, bySpec }`, the
  season-staleness guard, `/where2go genspec reset`, and the manual
  logout-and-hand-copy-into-committed-file step all stay as Phase 8
  shipped them — kept as a safety net even though a full run now
  finishes in one pass, in case a run is interrupted mid-way or a future
  partial rescan is added.

## Why `VoidcacheIds.lua` survives

While brainstorming this redesign, the user asked whether the Voidcache
item IDs are still needed for a *different*, unrelated purpose: tracking
which items a character has already obtained via a real Voidcore bonus
roll, so they're excluded from future recommendations.

Investigation confirmed this is a real, already-known, separate gap:
`Core/VoidcoreHistory.lua` marks an item obtained purely by listening for
the live `BONUS_ROLL_RESULT` game event, which means it can only ever
know about items obtained *from the moment the addon was first
installed onward* — it cannot retroactively know a player's Voidcore
history from before they installed Where2Go. The Phase 4 design doc
(`docs/superpowers/specs/2026-09-02-phase4-voidcore-design.md`) already
named the fix and explicitly deferred it: reading the real Nebulous
Voidcache tooltip live "reflects Blizzard's own server-side state
directly (accurate even for pre-addon-install history)."

`Core/VoidcoreDrop.lua`'s recommendation logic is
`specEligible(itemId) and not IsObtained(itemId)` — `specEligible` comes
from `BY_SPEC` (what this redesign generates), `IsObtained` comes from
the install-onward-only history above. These are independent; this
redesign's `BY_SPEC` generation mechanism cannot help fix the
obtained-item gap, because `EJ_SetLootFilter` is pure static reference
data with zero per-character state — only the real Voidcache tooltip,
read live on a player's own character, reflects their personal
already-obtained/remaining pool.

If that gap is ever closed, the fix needs exactly the same dungeon/boss
→ real Voidcache item ID mapping `VoidcacheIds.lua` already contains (to
know which real item's tooltip to read for a given piece of content).
Deleting it now would mean re-sourcing all 17 entries from Wowhead again
later. **Decision: keep `Core/VoidcacheIds.lua` and
`tests/voidcacheids_spec.lua` unchanged; only remove
`SpecEligibilityScan.lua`'s dependency on it.** This backlog item
(personal obtained-item backfill scan) is filed separately and is
explicitly **not** part of this redesign's scope.

## Architecture: `Core/SpecEligibilityScan.lua` rewrite

Rewritten in place — same file, same public API surface
(`Where2GoSpecEligibilityScan.Start()`, `.SetProgressCallback(name, fn)`,
`.IsRunning()`), so `Init.lua`'s `/where2go genspec` command wiring needs
minimal changes.

**Removed** (all existed only to support the Voidcache-tooltip
mechanism):
- `ParseTooltipLines`, `CollectVoidcacheItemList`, `BuildNameToItemId`,
  `CollectAllPoolItemIds`'s `RequestLoadItemDataByID` warm-up.
- The async step state machine (`ScanStep`, `RETRY_DELAY`, `MAX_RETRIES`,
  `SPEC_CHANGE_DELAY`, `STEP_DELAY`, `_state.retries`,
  `_state.specSwitchDone`).
- The combat-lockdown event frame and "manual loot-spec-change aborts
  the scan" handler (`_combatFrame`, `PLAYER_REGEN_DISABLED`/
  `PLAYER_LOOT_SPEC_UPDATED` listeners) — `EJ_SetLootFilter` doesn't
  touch the character's real loot specialization at all, so there is no
  real gameplay state change to protect during combat or interrupt via a
  manual spec change.
- `FinalizeScan`'s cold-item-cache empty-result guard — `GetLootInfoByIndex`
  returns the real `itemID` directly (confirmed live, see Problem above),
  so there is no name-to-itemId resolution step left to fail on a cold
  cache.

**Added**, replacing `Start()`'s body:

```lua
function Where2GoSpecEligibilityScan.Start()
    if InCombatLockdown() then
        return false, "COMBAT"
    end
    if Where2GoSpecEligibilityScan.CheckExportSeasonStale(Where2GoDB.specEligibilityExport, Where2GoConstants.SEASON_LABEL) then
        return false, "STALE_SEASON"
    end

    EnsureEncounterJournalLoaded()
    if not EJ_SelectInstance or not EJ_SelectEncounter or not C_EncounterJournal then
        return false, "EJ_LOAD_FAILED"
    end

    local bySpec = {}
    for _, source in ipairs(AllTrackedSources()) do          -- Sources.lua DUNGEONS ++ RAIDS
        for _, encounter in ipairs(source.encounters) do
            EJ_SelectInstance(source.instanceId)
            EJ_SelectEncounter(encounter.bossId)
            for classIndex = 1, GetNumClasses() do
                local _, _, classId = GetClassInfo(classIndex)
                local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
                for specIndex = 1, numSpecs do
                    local specId = GetSpecializationInfoForClassID(classId, specIndex)
                    EJ_SetLootFilter(classId, specId)
                    local filtered = CollectCurrentLootItemIds()   -- EJ_GetNumLoot / GetLootInfoByIndex(i).itemID
                    for _, itemId in ipairs(encounter.itemIds) do
                        if filtered[itemId] then
                            bySpec[specId] = bySpec[specId] or {}
                            bySpec[specId][itemId] = true
                        end
                    end
                end
            end
        end
    end
    EJ_SetLootFilter(0, 0)

    Where2GoDB.specEligibilityExport = {
        seasonVersion = Where2GoConstants.SEASON_LABEL,
        bySpec = Where2GoSpecEligibilityScan.MergeBySpec(
            Where2GoDB.specEligibilityExport and Where2GoDB.specEligibilityExport.bySpec,
            bySpec),
    }
    NotifyProgress(nil, nil, nil, "COMPLETE")
    return true
end
```

(Illustrative — exact helper names/boundaries are an implementation-plan
detail, not locked here.)

Runs as a single synchronous pass — no `C_Timer.After` chunking — since
every call involved (`EJ_SelectInstance`/`EJ_SelectEncounter`/
`EJ_SetLootFilter`/`GetLootInfoByIndex`) is local client data with no
server round-trip, unlike the old tooltip-read/`SetLootSpecialization`
flow. `MergeBySpec` and `CheckExportSeasonStale` are reused unchanged
(already pure, already tested).

**Progress reporting**: `SetProgressCallback`'s public shape is kept so
`Init.lua`'s existing `HandleGenspecProgress` print handler keeps
working, but it's called far less often than the old per-tooltip-read
cadence — once at start and once on completion is enough for a run
expected to take well under the old ~40-seconds-per-class figure (see
Performance below); the implementation plan may add a once-per-class
progress print if live timing turns out slower than expected.

## Performance and safety (verify live, not assumed)

Rough combinatorics: ~37 tracked encounters (28 dungeon + 9 raid boss, current
`Sources.lua`) × ~40 total specs across 13 classes ≈ 1,500
`EJ_SetLootFilter`/`GetLootInfoByIndex` calls, each pure local-data
lookups with no network or async wait. This is expected to run in well
under a second, but has not been measured live. The implementation
plan's manual-verification task must time an actual `/where2go genspec`
run and confirm it does not trip WoW's "script ran too long" watchdog —
if it does, the fix is a minimal `C_Timer.After(0, ...)` yield every N
encounters, not a return to the old retry/stabilize state machine.

Combat handling: kept as a cheap defensive `InCombatLockdown()` guard
even though `EJ_SetLootFilter` doesn't touch real gameplay state (unlike
the old `SetLootSpecialization`-based reason for blocking in combat) —
whether Encounter Journal API calls are actually combat-restricted at
all is unverified; the guard costs nothing to keep either way.

## `docs/SEASON_CHECKLIST.md` updates

- **Step 4** ("Refresh `Where2Go/Core/VoidcacheIds.lua`"): no longer a
  dependency of spec-eligibility regeneration. Reword to note it's
  currently unused by any shipped feature (kept only for the
  not-yet-built personal obtained-item backfill feature) and can be
  skipped during a season changeover unless/until that feature exists.
- **Step 5** ("Regenerate `Where2Go/Core/SpecEligibilityData.lua`"):
  replace "for every class in the game, log into (or create a throwaway)
  character of that class and run `/where2go genspec`... spread across
  as many sessions as needed" with "log into any one character and run
  `/where2go genspec` once — it now scans every class/spec in the game
  in a single pass." The eyeball-check-before-hand-merge step is
  unchanged.

## Testing

- `tests/specEligibilityScan_spec.lua`: the Voidcache tooltip-parsing
  tests (`ParseTooltipLines`) are deleted along with the code they
  cover. `MergeBySpec`/`CheckExportSeasonStale` tests are kept unchanged.
  New pure-function coverage if the rewrite factors out a testable
  "does `Sources.lua`'s encounter itemId list intersect this filtered
  id set" helper (likely, given it's plain table logic).
- The EJ-API-driven scan loop itself is WoW-API-only, like the mechanism
  it replaces — not unit-tested, verified live instead (this is what the
  Performance section's manual-timing task and a real `/where2go genspec`
  run against a known encounter/class/spec combination are for).
- `tests/voidcacheids_spec.lua`: unchanged (file survives).
- `tests/toc_spec.lua`'s parse check automatically covers the rewritten
  file; no test changes needed there.
- `Where2Go/Core/EJDiagnostic.lua` (the throwaway spike script) and its
  `Init.lua`/TOC wiring are deleted once the real implementation lands —
  its job was answering "does this work," not shipping.

## Non-goals (explicitly out of scope)

- Personal Voidcore obtained-item history backfill (reading a player's
  own live Voidcache tooltip to correct pre-addon-install history) — a
  separate, unstarted backlog item; see "Why VoidcacheIds.lua survives"
  above. Not designed here.
- A partial/single-class `/where2go genspec <classId>` rescan option —
  deliberately not added; see Scope decision above.
- Any change to `Core/DirectDrop.lua`'s `IsEligibleForSpec` consumption
  order, `VoidcoreDrop.lua`, or the UI — Phase 8 already wired
  `BY_SPEC` as the primary source with the old heuristic as fallback;
  this redesign only changes *how* `BY_SPEC` gets generated.
