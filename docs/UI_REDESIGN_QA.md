# Two-window UI verification

## Automated coverage

- Pure selection: duplicate item sources, registered-item exclusion, select all
  then uncheck exceptions, cache reconciliation and explicit filter resets.
- Preferences: mode separation, no-op edits, source preservation, add/remove/
  clear undo and subscriber notifications.
- Frame-boundary integration: deferred PVEFrame hooks preserving Blizzard
  scripts, show/hide, saved collapse, bounded viewport, card reuse after
  reranking, distinct empty states and active specialization/cache refresh.
- Browser interaction: real filter/selection/preference modules, full-pool batch
  selection across scrolling, unchecking exceptions, cache updates, immediate
  single add, undo, filter reset and a clear confirmation surviving mode changes.

These tests use a strict WoW frame double. They do not prove actual rendering,
secure-frame behavior or API/template compatibility in a running client.

## Live-client acceptance checklist

1. Open the dungeon finder, raid finder and premade-group tabs. The small panel
   appears beside the finder; closing the finder hides the panel without closing
   the independent browser. Reopen, collapse and expand, then `/reload` and
   confirm the panel's collapse preference survives.
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

## Scope and carried limitations

- No live-client acceptance checks were performed by the automated tests.
- The existing ItemRow link lookup can change Encounter Journal selection and
  filters on first hover; missing links are cached for the session. This comes
  from checkpoint `18d1d3e` and is not altered by the layout redesign.
- Voidcore reward-event compatibility still needs a real roll verification as
  recorded in the existing TODO. The UI does not claim complete historical data.
- Existing source names remain data-owned English strings. Addon labels are
  localized; native item names and tooltips use the client's language.
