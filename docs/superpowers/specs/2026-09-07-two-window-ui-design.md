# Two-window UI redesign

Status: User approved implementation in conversation on 2026-09-07.

## Product contract

Players choose their own preferred items. Where2Go ranks content against those
items; it does not recommend items, assess DPS, or automatically remove equipped
items. Preserve independent DROP and VOIDCORE lists and current ranking math.

## Small recommendation panel

Automatically show beside the dungeon/group finder (`PVEFrame`) and hide when
that frame closes. Hook existing scripts without replacing Blizzard handlers;
support the finder loading after the addon. Keep `/w2g` standalone access.
Persist whole-panel collapse per character; collapsed form is a title strip.
Individual content expansion is separate and preserved during refreshes, with
all cards initially expanded as previously agreed. Use a bounded scrolling
viewport, clear content names, a separate target/pool explanation line, and a
muted source/track detail line so long raid names do not crowd the main label.
Show the current active specialization as the ranking context. A manage button
opens the independent large browser in the same DROP/VOIDCORE mode.

## Large browser

An independent, movable, screen-clamped window with two columns: wide searchable
item results and an always-visible preferred list. Use neutral dark surfaces,
gold active/action accents, readable muted text, and native item quality colors
and tooltips. Keep source/slot/stat/spec/search filters, their existing AND/OR
semantics, and multi-spec browsing. Distinguish browsing specs from active-spec
ranking. A filter reset clears explicit filters and retains eligible-only default.

Single add: an inline Add button commits immediately. Registered entries show
Saved and cannot be re-added. Batch add: select all filtered *unique unsaved*
items, uncheck exceptions, then commit with a selected-count button. Selection
is independent of scrolling. All/partial/none state is visible in the header.
Changing a filter or mode clears transient selection; cache refreshes do not.
New results arriving from the item cache remain unselected until explicitly
selected; select-all applies to results available at the moment it is clicked.
Preferred items remain visible regardless of filters. Per-item removal and
confirmed clear-all support one-level undo per mode, as do single/batch adds.
Provide counts, empty states, visible scrollbars, success feedback and Undo.
The preferred list updates the open recommendation panel immediately.

## Scope and validation

No ranking formula, loot-spec setting, tooltip-link engine, or data-prep redesign.
Keep existing saved-variable compatibility. Add pure tests for batch selection,
deduplication, exceptions, persisted changes, undo and mode independence. Use a
small WoW frame test double for event/lifecycle integration, not visual claims.
Run the entire Lua 5.1 suite and lint. Live client QA remains required for real
PVEFrame anchoring, secure/combat behavior, fonts, tooltips and UI scale.

API reference inspected: https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_GroupFinder/Mainline/PVEFrame.lua

## Implementation rulings

- Keep the browser's class-spec union filter and label the recommendation's
  current-spec context; changing ranking semantics is outside this UI work.
- Opening management shows it deterministically rather than toggling it closed.
- Undo remains available until another edit in that mode or session end; avoid
  a timeout that makes it hard to undo after navigating the long list.
- Use the existing supported client templates and no external addon dependency.
