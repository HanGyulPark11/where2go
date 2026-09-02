# Phase 1: Foundations — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 1 only (addon manifest, initialization,
saved-variable schema, test harness, fixture data, static panel).

## Decisions carried into this design

- Target client: Midnight patch 12.1 (`Interface: 120100`), Season 2 ("한밤
  시즌2").
- Fixture content: the Season 2 raid (all encounters) plus one arbitrary
  Mythic+ dungeon.
- Addon identifier: `Where2Go` (folder name, TOC Title, SavedVariables
  prefix).
- Panel placement: a standalone frame, not anchored into Blizzard's Dungeon
  and Raid Finder UI. Anchoring into Blizzard frames is deferred until a
  later phase that can budget time for taint/anchor verification.
- UI framework: plain FrameXML/Lua. No Ace3, no vendored libraries. Revisit
  only if a later phase's UI needs (e.g. scroll lists, tabs) can't be met
  reasonably with `CreateFrame`.
- Test runtime: Lua 5.1 installed locally via `choco install lua51`, matching
  the WoW client's Lua version.

## Reference material

- `docs/DECISIONS.md` and `docs/DEVELOPMENT_PLAN.md` in this repo — product
  rules and phase acceptance checks.
- `C:\Users\hangy\ai\vault\wiki\wow-item-level-bonus-id-system.md` and
  `wiki/wow-addon-dev-research-workflow.md` — item level/bonus ID system,
  `C_Item.GetItemSpecInfo` spec-fitness API, Encounter Journal API hazards,
  AceGUI pitfalls (not used in Phase 1 since we're not using Ace3, but
  relevant if a future phase revisits that choice).
- `rolferik12/VoidcoreAdvisor` (GitHub) — closest prior art for a dual-intent
  (direct-drop / Voidcore) loot advisor. Referenced for its `Core`/`UI`/
  `Locales` folder split, not copied directly since it depends on AceGUI.
- `EllesmereGaming/EllesmereUI` (GitHub) — example of an addon that dropped
  Ace3 for a custom lightweight framework and vendors only small libraries
  via `.pkgmeta` externals. Confirms plain FrameXML is a reasonable choice
  for an addon this size; we skip even the small-libs layer since Phase 1
  needs no cross-addon data sharing or event batching.

## Architecture

```
Where2Go/                        (addon folder — loaded by the client)
├── Where2Go.toc                 Interface: 120100, SavedVariables decls
├── Core/
│   ├── Constants.lua            patch/season constants (pure data, no WoW API)
│   ├── Fixtures.lua             Season 2 raid + one M+ dungeon fixture (pure data)
│   └── Init.lua                 ADDON_LOADED handling, SavedVariables defaults,
│                                 slash command registration
└── UI/
    └── Panel.lua                standalone frame (not anchored to Blizzard UI)

tests/                           (repo root — dev-only, not shipped in the addon)
└── run_tests.lua                run via `lua tests/run_tests.lua`
```

## Components

- **`Core/Constants.lua`, `Core/Fixtures.lua`**: pure Lua tables with no WoW
  API references, so they can be `dofile`'d outside the game client for
  testing.
- **`Core/Init.lua`**: initializes `Where2GoDB` (account-wide) and
  `Where2GoCharDB` (per-character) SavedVariables with defaults if absent;
  registers `/where2go` to toggle the panel. Guards its `ADDON_LOADED`
  handler to only act when the event's `addonName` argument is `"Where2Go"`.
- **`UI/Panel.lua`**: a `CreateFrame`-based standalone, movable frame with a
  close button. Renders the fixture data as one compact line per
  dungeon/encounter (content label, target/pool estimate, recommended loot
  spec) using the fixture's placeholder numbers. Item-row rendering is out
  of scope here — `docs/DEVELOPMENT_PLAN.md` places full item-row rendering
  in Phase 3 alongside real ranking math, and this spec's earlier wording
  overstated Phase 1's rendering scope.

## Data flow

1. `Init.lua` reacts to `ADDON_LOADED` for `"Where2Go"`, seeds SavedVariables
   defaults.
2. `/where2go` toggles `UI/Panel.lua`.
3. `Panel.lua` reads `Core/Fixtures.lua` tables directly and renders one card
   per fixture entry (dungeon, each raid encounter). No live game-state
   reads and no ranking computation in this phase.

## Testing

- `choco install lua51` provides a Lua 5.1 interpreter matching the client.
- `tests/run_tests.lua` loads `Core/Fixtures.lua` via `dofile` and asserts
  the fixture data contract: the dungeon fixture has a name and a pool size;
  the raid fixture has a name and a list of encounters, each with its own
  name and pool size.
- `Init.lua` and `Panel.lua` depend on WoW globals and are out of scope for
  this harness — they're verified live in-client per the acceptance check
  below.

## Error handling

- `ADDON_LOADED` handler checks the event's addon name argument before
  acting. No other defensive code is warranted at this scope (YAGNI) —
  there's no user input, network call, or cross-addon interaction yet.

## Acceptance check (from `docs/DEVELOPMENT_PLAN.md`)

- The addon loads without errors after `/reload`.
- The panel is visible (via `/where2go`) and removable (close button or
  `/where2go` again) without changing any game state (no CVars, no
  Blizzard frame mutation).

## Out of scope for Phase 1

- Real drop-rate/pool ranking math (Phase 3).
- Preferred items, equipment comparison (Phase 2).
- Voidcore history (Phase 4).
- Anchoring into Blizzard's Dungeon and Raid Finder frame (deferred; may
  never happen if the standalone frame proves sufficient).
- Ace3 or any vendored library (deferred; only revisit if plain FrameXML
  becomes a real bottleneck).
