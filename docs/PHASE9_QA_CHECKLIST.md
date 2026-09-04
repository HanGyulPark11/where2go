# Phase 9 UI Overhaul — Manual QA Checklist

Phase 9 (item browser / recommendation panel UI overhaul) is code-complete,
merged to `master`, and passed every automated check available outside a
live client (unit tests, three independent code reviews). Nobody has
opened it in an actual WoW client yet. Follow these steps in order — later
sections assume the addon is already loaded and the browser is already
open from an earlier step. Full context: `docs/superpowers/specs/2026-09-04-phase9-ui-overhaul-design.md`
(what was designed) and `docs/superpowers/plans/2026-09-04-phase9-ui-overhaul.md`
(how it was built) — you don't need to read either to run this checklist,
they're just there if something looks wrong and you want to check intent.

## 0. Setup

1. Confirm `AddOns\Where2Go` is a junction pointing at this repo's
   `Where2Go\` folder (see `docs/RELEASE_CHECKLIST.md` step 6 for how to
   check) — for this dev pass you're testing the live source directly, no
   packaging needed.
2. Launch WoW (or `/reload` if already running). **Check for Lua errors on
   load** — if `!BugGrabber`/`BugSack` or the default error UI is
   enabled, a load-time syntax error would show immediately. If nothing
   appears, that's a pass — this doesn't fully confirm success, just rules
   out the most obvious failure.

## 1. Item Browser — open it and check the frame itself

Run `/where2go browse` (or `/w2g browse`).

- [ ] Window opens, roughly 860px wide, three visible list columns side
      by side with their own headers: **Results | Staged | Preferred**.
- [ ] The old separate "Dungeon" and "Boss" button rows are **gone** —
      replaced by a single dropdown labeled "Source" area (button reads
      "All Sources" by default).
- [ ] Window is draggable by its title bar / chrome (not by hovering an
      item row — see § 6 "Known issues" below, this is expected).

## 2. Source dropdown (multi-select)

- [ ] Click the Source dropdown. It opens a list with a **"Dungeons"**
      group header, followed by every dungeon, then one group header per
      raid (the raid's own name), followed by that raid's bosses.
- [ ] Each entry has a **checkbox**, not a radio dot.
- [ ] Click one dungeon entry: the menu **stays open** (does not
      auto-close), the entry shows checked, and the Results list narrows
      to just that dungeon's items — including items from *both* of that
      dungeon's bosses (dungeons are a whole-run filter, not per-boss).
- [ ] Click a second entry (e.g. a raid boss) while the first is still
      checked: both stay checked, Results shows the **union** of both
      (not just the second one, not empty).
- [ ] Close the dropdown. Its own button text now reads "2 selected" (or
      the correct count).
- [ ] Uncheck both entries (reopen, click each again): Results returns to
      showing everything, button text returns to "All Sources".

## 3. Slot / stat / eligible / search filters (should behave as before)

- [ ] Slot buttons show **friendly names** ("Head", "Trinket", "Main
      Hand", etc.), not raw ids like `HEAD`/`TRINKET`.
- [ ] Clicking a slot button narrows Results to that slot; clicking it
      again clears the filter.
- [ ] Stat checkboxes (Crit/Haste/Mastery/Versatility) narrow Results to
      items with **all** checked stats (not just any one).
- [ ] The **spec dropdown now sits directly next to** the "Selected spec
      eligible only" checkbox (previously it was up near the Drop/
      Voidcore buttons — confirm it moved).
- [ ] Checking "eligible only" narrows Results to items your currently
      selected spec can use.
- [ ] There's a small label above/near the search box (new — previously
      unlabeled). Typing in the search box narrows Results by item name,
      live as you type.

## 4. Item rows — icon, name, tooltip

Look at a handful of rows in the **Results** column.

- [ ] Each row shows: an icon, an item name colored by quality (white/
      green/blue/purple — matches the item's actual rarity), and a
      second line like `344 · Crit/Haste` (item level and secondary
      stats).
- [ ] Hover a row: the **real Blizzard item tooltip** appears (not a
      custom-drawn one) — full stats, "Binds when equipped," etc., exactly
      like hovering the item anywhere else in the game.
- [ ] **New in this pass:** below the normal tooltip content, there's an
      extra gray line naming the source — either a dungeon name, or
      `<Raid Name> - <Boss Name>` for raid items. This replaces the old
      inline "Dungeon / Boss: Item Name" row text (which is intentionally
      gone from the row itself — check the tooltip, not the row text).

## 5. Staged panel

- [ ] Check a checkbox on 2-3 Results rows. Each checked item
      **immediately appears** in the Staged column (icon/name/summary,
      same treatment as Results, no checkbox — instead a small `×` on the
      right).
- [ ] Click the `×` on one Staged row: it disappears from Staged, **and**
      its checkbox back in Results unchecks itself.
- [ ] Stage more than 10 items (check enough Results rows). **New in
      this pass:** scroll the mouse wheel over the Staged column — it
      should scroll to reveal the rest rather than silently cutting off
      at 10.
- [ ] Click "Add selected": staged items move into the Preferred column
      (see next section), and the Staged column empties.
- [ ] Stage a few more items, click "Clear selection": Staged empties
      without adding anything to Preferred.

## 6. Preferred panel

- [ ] After "Add selected" above, the added items appear in the
      **Preferred** column (this list did not exist as a visible list
      before this phase — previously the only way to see what was
      preferred was scattered checkmarks while re-browsing).
- [ ] Click the `×` on one Preferred row: just that item is removed,
      nothing else changes.
- [ ] Add more than 10 preferred items total. **New in this pass:**
      scroll the mouse wheel over the Preferred column to reach the rest
      — this is the important one to check carefully, since before this
      fix, anything past #10 was only removable via "Clear All" or the
      `/where2go pref remove <itemId> <drop|voidcore>` slash command.
- [ ] Click "Clear All": a confirmation popup appears ("Remove every
      preferred item from the current list?"). Confirm it, and the whole
      Preferred list empties. Cancel it once too, to confirm cancel
      actually cancels.
- [ ] Switch the Drop/Voidcore mode toggle (top of window): Preferred
      column switches to show that mode's own preferred list (they're
      separate lists per mode).

## 7. Recommendation panel

Close the browser, run `/where2go` (or `/w2g`) to open the main panel.

- [ ] Existing behavior unchanged: cards per dungeon/boss, click a card
      header to expand/collapse, Drop/Voidcore tabs switch views.
- [ ] Expanded card item rows now use the **same icon + quality-colored
      name + ilvl/stat summary** treatment as the browser (previously
      plain text lines).
- [ ] Hover an item row inside an expanded card: real tooltip appears
      (same as § 4). No extra source line expected here — the card's own
      header already names the dungeon/boss, so this is intentional, not
      a gap.
- [ ] Cards resize correctly when expanded/collapsed with the new taller
      rows (no overlapping rows, no visible gap/cutoff).

## 8. Localization (only if you can test with a koKR client)

If you have a Korean-client character to log into, repeat a pass over
§§ 1-3 and 7 on it and confirm:

- [ ] Item Browser title, Drop/Voidcore labels, Source dropdown group/
      button text, "eligible only" label, all three column headers, all
      four browser buttons, and the Clear-All confirmation popup are all
      in Korean.
- [ ] Slot filter buttons show Korean slot names.
- [ ] The Recommendation panel's title, Drop/Voidcore tabs, and Browse
      button are **also in Korean** — new in this pass, previously only
      the browser was localized. This is one of the three gaps the final
      review caught and fixed, worth double-checking specifically.
- [ ] Item names and tooltips are in Korean too — but that's the WoW
      client doing it automatically, not this addon; if it's wrong, it's
      not a Phase 9 bug.
- [ ] Dungeon/boss/raid names stay in **English** regardless of client
      language — this is a known, accepted limitation (translating them
      is separate, unscoped future work), not something to report as a
      bug.

If you don't have a koKR client available, skip this section — it's not
blocking, just nice to confirm when possible.

## 9. Known rough edges to specifically double-check

These were flagged during code review as likely-but-unconfirmed issues.
Look for them specifically rather than assuming they're fine:

- [ ] **Search box label may overlap the stat-checkbox row above it.**
      Look at the area right above the search box — if the new "Search..."
      label text collides with the Crit/Haste/Mastery/Versatility row,
      that's a known, pre-flagged pixel issue, not a surprise. Minor fix
      if so (just needs its anchor offset adjusted).
- [ ] **Results list is not sorted** — items display in raw
      dungeon-then-raid pool order, not alphabetically or by item level.
      This was a deliberate (if under-discussed) choice carried through
      from the design; flag it if it feels wrong in practice, since it's
      an easy follow-up to add alphabetical/ilvl sorting later.
- [ ] **Dragging the window by an item row doesn't work** — item rows now
      capture mouse input (needed for tooltips), so you can only drag by
      the title bar or empty chrome, not by clicking-and-dragging on top
      of a row. Expected, not a bug, but worth confirming it doesn't feel
      broken in practice.
- [ ] **Cold item cache on first open** — if you open the browser or
      recommendation panel very soon after login (before the client has
      cached item data), some icons may briefly show a question-mark
      placeholder and names may show "Item #12345" instead of the real
      name. The browser self-heals automatically within a few seconds
      (re-renders as data arrives); the Recommendation panel does **not**
      auto-refresh — if you catch it mid-cold-cache there, closing and
      reopening the panel should show the correct data. Confirm this
      self-heal actually happens in the browser rather than getting stuck.

## 10. Reporting results

If everything above checks out: Phase 9 is fully done, nothing further
needed. If anything fails: note which numbered item, what you saw vs.
expected, and whether it matches one of the § 9 known rough edges or is a
new surprise — that determines whether it's a quick follow-up fix or
needs a fresh look.
