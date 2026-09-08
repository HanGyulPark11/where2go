# Where2Go

Where2Go is a World of Warcraft addon for choosing which dungeon or raid boss
to run for the items you want. You choose preferred items yourself; the addon
ranks content rather than recommending gear.

## Using the addon

- Open the dungeon/group finder to see the compact recommendation panel beside
  it. The panel hides with the finder and remembers whether you collapsed it.
- Use **Manage items** or `/w2g browse` to open the independent item browser.
  Filter/search the left list and manage saved preferences on the right.
- Add one item directly, or select all filtered results, uncheck exceptions,
  then add the selected items. Selection covers offscreen results and excludes
  items already saved. Changing filters or mode clears temporary selection.
- Additions, removals and confirmed clear-all support one-level Undo in each
  mode. The recommendation panel refreshes immediately when preferences change.
- Drop and Voidcore have independent preferred lists. Browsing can include
  multiple specs of your class; content ranking uses your active specialization.
- `/w2g` still toggles standalone access to the recommendation panel.

The ranking compares the share of preferred items in the eligible pool under
an equal-outcome assumption. It is not a measured drop rate or time-per-run
estimate and does not automatically exclude items based on equipped gear.

See [current state](docs/CURRENT_STATE.md) for verified status and open live
work, [code map](docs/CODEMAP.md) for source/test navigation, and [UI
verification](docs/UI_REDESIGN_QA.md) for the two-window UI checklist.

## Product goal

Help a player choose the most efficient next dungeon, raid boss, or Voidcore
roll objective for their own preferred items. The product should explain the
recommendation clearly enough that the player can act on it immediately.

Development references:

- `docs/DEVELOPMENT_PLAN.md` for scope, delivery order, and acceptance checks.
- `docs/DECISIONS.md` for product rules that have already been agreed.
- `TODO.md` for the next planning and discovery tasks.
- `docs/SEASON_CHECKLIST.md` for the season-changeover procedure.
- `tools/LINT_README.md` for the Lua syntax/lint checking setup.
- `docs/RELEASE_CHECKLIST.md` for the packaging/release procedure.
- `AGENTS.md` for repository workflow and completion evidence.

## Repository language

All source code, code comments, documentation, commit messages, and developer
tool output must be written in English. Player-facing addon text may be
localized, including Korean.
