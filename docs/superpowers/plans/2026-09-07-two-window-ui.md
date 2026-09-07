# Two-window UI implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Execute
> continuously under the user's approval to start development.

**Goal:** Separate fast content decisions from comfortable item-list management.

**Architecture:** Shared pure preference and selection models drive two native
WoW windows. A small common theme provides consistent surfaces and controls.
Preference notifications refresh both windows without resetting scroll or cards.

**Tech Stack:** Lua 5.1, WoW CreateFrame and native dropdown/tooltip APIs.

**Spec:** `docs/superpowers/specs/2026-09-07-two-window-ui-design.md`

## Global constraints

- Players choose items; preserve ranking math and independent modes.
- Keep saved-variable compatibility; English code/docs, enUS and koKR UI.
- No addon dependencies; no live-client success claims from mocked tests.

## Task 1: Selection and persisted preference transactions

Files: `Core/Selection.lua`, `Core/Preferences.lua`, `tests/selection_spec.lua`,
`tests/preferences_spec.lua`.

Interfaces: `Where2GoSelection.New()` produces an object with
`SetResults(entries, preferred, reset)`, `SelectAll(selected)`, `Toggle(itemId)`,
`GetCounts()` (selected, available), and `GetSelected()` (itemId -> bonusId/true).
`Where2GoPreferences` exposes `Get(mode)`, `Add(mode, items)`, `Remove(mode,id)`,
`Clear(mode)`, `Undo(mode)`, `HasUndo(mode)`, `Subscribe(key, callback)`, and
`Notify(mode)`. Get returns preferred and source maps. Mutations return counts.

- [x] Write failing behavior tests for select-all excluding duplicates/saved
  items, exclusion after all, scrolling-independent selection and filter reset.
- [x] Test Add/Remove/Clear/Undo against a literal two-mode saved DB; assert that
  undo changes only the last edit and not the other mode or existing sources.
- [x] Implement the two pure modules and run their tests under Lua 5.1.

## Task 2: Recommendation panel lifecycle and layout

Files: `UI/Panel.lua`, `tests/panel_spec.lua`, `tests/helpers/wow_ui.lua`.
Consumes Preferences.Subscribe and existing ranking/ItemRow modules.
Produces `Where2GoPanel.Refresh()`, `Where2GoPanel.SetMode(mode)`, and retains
`Where2Go_TogglePanel()`. Calls `Where2GoBrowserPanel.Show(mode)` to manage.

- [x] Test finder show/hide hooks, late availability, persisted whole collapse,
  and preference-driven refresh through a WoW boundary double.
- [x] Implement bounded scrolling card layout, separated headers, current-spec
  context, separate whole-panel collapse and preserved card expansion.
- [x] Cover nil/empty ranked data without leaking frames or stale messages.

## Task 3: Two-column browser and shared theme

Files: `UI/Theme.lua`, `UI/BrowserPanel.lua`, `UI/ItemRow.lua`, `Core/Locale.lua`,
`Core/Init.lua`, `Core/VoidcoreHistory.lua`, `Where2Go.toc`, `.luacheckrc`,
`tests/run_tests.lua`, `tests/browserpanel_spec.lua`.

Theme interface: `Where2GoTheme.colors` with bg/surface/inset/border/text/muted/
accent/hover/selected RGB values; `Box(frame, colorKey)` styles a backdrop;
`Text(parent, template, text)` creates a font string; `Button(parent,text,w,h,fn)`
creates a native action button. Theme loads before both windows and ItemRow.

- [x] Wire new modules in TOC and tests in runner. Exercise whole UI entry point
  with the frame double and assert DB outcomes for individual and batch actions.
- [x] Rebuild browser as 960x718 two-column window, wide results and preferred
  list, native filters, counts, partial select-all, footer actions and undo.
- [x] Preserve mousewheel selection, clear transient selection only on explicit
  filter/mode edits, deduplicate item IDs, and refresh on relevant cache events.
- [x] Route slash-command preference writes through Preferences; notify panel
  when Voidcore history changes. Add enUS/koKR strings and lint declarations.

## Task 4: Review and validation

- [x] Run `C:/ProgramData/chocolatey/lib/lua51/tools/lua5.1.exe tests/run_tests.lua`.
- [x] Run `tools/lint.ps1` and `git diff --check`.
- [x] Review the changes against the spec, fix material findings and rerun only
  affected checks before a final suite run.
- [x] Record live QA steps: finder open/close, panel collapse/reopen, manage
  without finder, single/all-minus-exceptions registration, scrolling, duplicate
  sources, undo, mode separation, long koKR names and multiple UI scales.

## Progress and review ledger

Baseline: 18d1d3e; 14 specs passing at checkpoint, lint 154 warnings / 0 errors.
Task 1 -> Task 3 shares Selection/Preferences contracts; exact signatures above.
Task 1 -> Task 2 shares Subscribe callback(mode); panel may ignore other modes.
Task 2 -> Task 3 shares Theme and Browser.Show(mode); parent owns shared files.
Ruling: independent modules/panel may be delegated while browser integration is
implemented locally; no two workers edit the same file. All interfaces above
are the integration contract. User already authorized development; no extra
design approval checkpoint is needed.

Task 1: complete. Direct red/green tests verified; Selection and Preferences
integrated without changing saved-variable shapes or ranking math.
Task 2: complete. Parent finished row constraints and removed test-only UI tags
after worker interruption. Tests use real Theme, ItemRow and Preferences.
Task 3: complete. Browser integration exercises real ranking and both windows;
single/batch writes and undo immediately refresh the open panel.
Task 4: complete for automated validation. 18 spec files pass; 23 addon Lua
files lint with zero warnings/errors. Packaged TOC smoke check passes.

Final review: no confirmed blockers. Button text initialization hardened with
a failing/passing control test. Stale ItemRow cache-refresh comment corrected.
Cold-slot rendering and real-client layout/secure-frame checks remain explicit
live QA items; model tests cover new results becoming available without silently
selecting them. See `docs/UI_REDESIGN_QA.md`.

Ruling: browser height is 718 rather than the draft 700, reserving a separate
feedback/undo row without crowding the batch action bar. Recommendation headers
use a third muted detail line for source/track information.
