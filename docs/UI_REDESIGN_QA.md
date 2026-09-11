# Two-window UI verification

## Automated coverage

- Pure selection: duplicate item sources, registered-item exclusion, select all
  then uncheck exceptions, cache reconciliation and explicit filter resets.
- Preferences: mode separation, no-op edits, source preservation, add/remove/
  clear undo and subscriber notifications.
- Ownership: all carried copies, source-specific track/level comparisons,
  same-item versus slot filtering, off-pool usable gear, conservative unknown
  data, unchanged drop denominators, and independent Voidcore history.
- Frame-boundary integration: deferred PVEFrame hooks preserving Blizzard
  scripts, show/hide, saved collapse, bounded viewport, card reuse after
  reranking, distinct empty states and active specialization/cache refresh.
- Browser interaction: real filter/selection/preference modules, full-pool batch
  selection across scrolling, unchecking exceptions, cache updates, immediate
  single add, undo, filter reset and a clear confirmation surviving mode changes.

These tests use a strict WoW frame double. They do not prove actual rendering,
secure-frame behavior or API/template compatibility in a running client.

## Live-client acceptance checklist

Status: the original checklist was passed by user confirmation on 2026-09-11. Targeted live-client QA for the static synthetic tooltip behavior was passed by user confirmation on 2026-09-12.

1. Open the dungeon finder, raid finder and premade-group tabs. The small panel
   appears beside the finder; closing the finder hides the panel without closing
   the independent browser. With a visible Raider.IO profile tooltip, confirm
   the panel clears its full bounds and chooses the left side when the right
   edge has no room. Drag only the title bar, reopen and `/reload` to confirm
   the manual position persists, then right-click the title bar to restore
   automatic placement. Also confirm the collapse preference survives.
2. Use `/w2g` without the finder and confirm standalone recommendations. Use
   Manage items in each mode and verify the browser opens in that mode even
   when it is already visible.
3. Search/filter for more than eleven unsaved items. Select all, scroll, uncheck
   two items and add. Only those two must be excluded; no duplicated item IDs
   should be registered. Confirm the small panel updates while still open.
4. Add one item, undo it, remove one, undo it, and clear all with confirmation.
   Undo must preserve existing entries and their stored tooltip source bonuses.
   Switching modes must never edit the other mode's list.
5. Change source/slot/stat/spec/search filters. Confirm temporary selection is
   cleared, but preferences remain visible. Inspect the partial select-all
   marker, disabled Saved rows, empty state, filter reset and scroll thumbs.
6. Cold-cache login: open each window and confirm placeholders resolve without
   losing selection. Change active spec and check recommendation context updates.
7. Check long item/boss names in enUS and koKR at several UI scales. Text must
   stay within rows; all actions and scrollbars must remain reachable. Verify
   native item tooltips and header explanations.
8. Open/close the finder in and out of combat with script errors enabled; check
   for blocked actions/taint and confirm Blizzard's normal finder still works.
9. In both Drop and Voidcore, use Same item filtering and save a preferred item with an equal-or-better
   version equipped or in ordinary bags. Confirm it is absent from targets but
   remains saved and still contributes to the eligible pool (unless excluded by
   Voidcore history). Check multiple copies, including a stronger bag copy, and
   confirm higher-version sources and different same-slot items still appear.
   Move/equip/remove the owned copy with the panel open and confirm refresh.
   Repeat after `/reload` with cold item data and ensure there are no errors or
   permanent false exclusions. Bank/warband-only ownership is not included.
10. Switch to Slot filtering and confirm an equal-or-better usable item in the
    same slot suppresses an unrelated preferred item; switch back and confirm
    it returns. Confirm the selected rule survives reopening and `/reload`
    and applies in both recommendation modes. For rings/trinkets, one strong
    unrelated item must leave the second-slot upgrade visible; two distinct
    usable equal-or-better items may suppress it. Check compatible weapon
    types and unavailable item data without false exclusions.
11. Hover the five reported examples in recommendation rows: Ferocious
    Scaleboots from Sszorak, Silken Voodoo Drape (item 268253) from The Coiled
    Altar, the mail waist item from Atroxus in Voidscar Arena, Gebbo's
    Bottomless Bag (item 270164), and Boots of the Reckless Wayfarer (item
    268258). Confirm the last two show Myth 2/6 at item level 321 rather than
    Champion 2/6.
    Confirm each tooltip matches the row's calculated track and level rather
    than a stale Champion 3/6 link. For Silken Voodoo Drape, Aqirbane
    Reliquary (268265), and Awoken Dreadfang Cuirass (271876), confirm the
    effect/context tooltip text remains present when their static synthetic
    variants validate. Aqirbane Reliquary may report item level 344 and
    `Mythic` without a numeric `9/6`; confirm that exact final-rank case keeps
    the full static link. When tooltip metadata is unavailable or conflicts,
    confirm the canonical track-only tooltip remains correct.
    Confirm hovering never changes the open Encounter Journal's selection or
    loot view. In Drop mode, Mythic raid bosses 1–6 must
    retain their direct 1/6, 2/6, or 3/6 levels and the final two must show
    Myth 9/6 (344). In Voidcore mode, bosses 1–6 must show Myth 6/6 (334) and
    the final two must show Myth 9/6 (344). Re-hover after a cold-cache miss
    and confirm the canonical synthetic link remains correct.
    Verify the browser results, saved preferences, and recommendation-card rows
    show localized slot · item level · fixed secondary stats; rows with no
    fixed secondary stats must end after item level.

## Scope and carried limitations

- Automated tests do not perform live-client acceptance checks; the original
  checklist and the targeted static-tooltip checks in item 11 were completed
  separately in the running client and confirmed by the user.
- ItemRow uses a canonical synthetic link from the calculated track bonus. Only
  the three static effect/context variants in `ItemLinkBonuses.lua` can add
  non-track bonuses, after `C_TooltipInfo` confirms the requested level and
  track metadata, including the documented final-rank exception. This behavior
  passed targeted live-client verification on 2026-09-12.
- Voidcore reward-event compatibility still needs a real roll verification as
  recorded in the existing TODO. The UI does not claim complete historical data.
- Existing source names remain data-owned English strings. Addon labels are
  localized; native item names and tooltips use the client's language.
