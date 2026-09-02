# Phase 1: Foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Where2Go addon skeleton — manifest, SavedVariables init, a fixture data set for one Season 2 raid and one Mythic+ dungeon, a local Lua test harness for the pure-data modules, and a static recommendation panel — matching `docs/DEVELOPMENT_PLAN.md` Phase 1's acceptance check (loads cleanly after `/reload`; panel shows and hides without changing game state).

**Architecture:** Two kinds of files. `Core/Constants.lua` and `Core/Fixtures.lua` are pure Lua tables/functions with zero WoW API references, so they run standalone under `lua` and get real unit tests. `Core/Init.lua` and `UI/Panel.lua` use WoW globals (`CreateFrame`, `SlashCmdList`, events) and can only be verified by loading the addon in the live client — those steps are manual checkpoints in this plan, not automated tests.

**Tech Stack:** Plain FrameXML/Lua (no Ace3, no vendored libraries). Lua 5.1 (`choco install lua51`) as the local test runtime, matching the WoW client's Lua version.

**Spec:** `docs/superpowers/specs/2026-09-02-phase1-foundations-design.md`

## Global Constraints

- Interface version: `120100` (Midnight patch 12.1).
- Addon identifier is `Where2Go` everywhere: folder name, TOC `Title`, and the `Where2GoDB` / `Where2GoCharDB` SavedVariables names.
- No Ace3, no vendored third-party libraries — plain FrameXML/Lua only.
- `Core/Constants.lua` and `Core/Fixtures.lua` must never reference WoW API globals (`CreateFrame`, `C_*`, event names, etc.) — that's what keeps them testable with a standalone `lua` interpreter.
- Tests run via `lua tests/run_tests.lua` from the repository root (not the `Where2Go/` addon folder).
- Source code, comments, and commit messages are English (per `README.md`'s repository language rule). Player-facing strings (fixture display names, panel labels) may be Korean.
- The panel is a standalone frame — it must not anchor into or mutate any Blizzard frame (e.g. `PVEFrame`, `EncounterJournal`).
- Lua's `assert()`/`error()` prepend a `file:line:` prefix to string error messages. Every `[FAIL] ...: <message>` line shown as "Expected" output below will actually appear with that prefix (e.g. `tests/toc_spec.lua:12: could not open ...`) — that prefix is normal and doesn't indicate anything is wrong; match on the message content, not the exact string.

---

## File Structure

```
where2go/
├── Where2Go/
│   ├── Where2Go.toc
│   ├── Core/
│   │   ├── Constants.lua      addon name, interface version, default-DB builders (pure)
│   │   ├── Fixtures.lua       Season 2 raid + one M+ dungeon fixture data (pure)
│   │   └── Init.lua           ADDON_LOADED handling, SavedVariables init, slash command
│   └── UI/
│       └── Panel.lua          standalone frame, renders fixture data, Where2Go_TogglePanel()
└── tests/
    ├── run_tests.lua          harness: dofiles each spec, reports pass/fail, exits 1 on failure
    ├── constants_spec.lua
    ├── fixtures_spec.lua
    └── toc_spec.lua
```

---

### Task 1: Lua 5.1 test runtime and harness scaffold

**Files:**
- Create: `tests/run_tests.lua`

**Interfaces:**
- Consumes: nothing yet (spec list starts empty).
- Produces: a `specs` list convention — later tasks append `"tests/<name>_spec.lua"` entries to the list in this file. Each spec file is a plain Lua script that raises a Lua error (e.g. via `assert`) on failure and returns normally on success.

- [ ] **Step 1: Install the Lua 5.1 interpreter**

Run: `choco install lua51 -y`

- [ ] **Step 2: Verify the interpreter is on PATH and is 5.1**

Run: `lua -v`
Expected: output starts with `Lua 5.1`

- [ ] **Step 3: Create the test harness**

`tests/run_tests.lua`:
```lua
local specs = {
}

local failureCount = 0

for _, path in ipairs(specs) do
    local ok, err = pcall(dofile, path)
    if ok then
        print(string.format("[PASS] %s", path))
    else
        failureCount = failureCount + 1
        print(string.format("[FAIL] %s: %s", path, tostring(err)))
    end
end

print(string.format("\n%d spec file(s), %d failure(s)", #specs, failureCount))

if failureCount > 0 then
    os.exit(1)
end
```

- [ ] **Step 4: Run the empty harness to confirm it works end to end**

Run: `lua tests/run_tests.lua`
Expected:
```
0 spec file(s), 0 failure(s)
```
Expected exit code: `0`

- [ ] **Step 5: Commit**

```bash
git add tests/run_tests.lua
git commit -m "test: add Lua test harness scaffold"
```

---

### Task 2: Core/Constants.lua

**Files:**
- Create: `Where2Go/Core/Constants.lua`
- Test: `tests/constants_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/constants_spec.lua"` to `specs`)

**Interfaces:**
- Consumes: nothing.
- Produces: global table `Where2GoConstants` with fields `ADDON_NAME` (string), `INTERFACE_VERSION` (number), `SEASON_LABEL` (string), and functions `BuildDefaultAccountDB()` / `BuildDefaultCharDB()`, each returning a fresh table (no shared references across calls). `Core/Init.lua` (Task 5) calls these two functions.

- [ ] **Step 1: Write the failing test**

`tests/constants_spec.lua`:
```lua
dofile("Where2Go/Core/Constants.lua")

assert(Where2GoConstants.ADDON_NAME == "Where2Go", "ADDON_NAME should be Where2Go")
assert(Where2GoConstants.INTERFACE_VERSION == 120100, "INTERFACE_VERSION should match the TOC")
assert(type(Where2GoConstants.SEASON_LABEL) == "string" and #Where2GoConstants.SEASON_LABEL > 0,
    "SEASON_LABEL should be a non-empty string")

local accountDB = Where2GoConstants.BuildDefaultAccountDB()
assert(type(accountDB) == "table", "BuildDefaultAccountDB should return a table")
assert(accountDB.panelShown == false, "panelShown should default to false")

local charDB = Where2GoConstants.BuildDefaultCharDB()
assert(type(charDB) == "table", "BuildDefaultCharDB should return a table")
assert(type(charDB.preferredItems) == "table", "preferredItems should default to a table")
assert(#charDB.preferredItems == 0, "preferredItems should default to empty")

-- Regression guard: each call must return an independent table. If the
-- builder ever returns a shared table by reference, one character's saved
-- data would leak into every other character's.
local secondCharDB = Where2GoConstants.BuildDefaultCharDB()
table.insert(charDB.preferredItems, 12345)
assert(#secondCharDB.preferredItems == 0,
    "BuildDefaultCharDB must return an independent table on each call")

print("constants_spec: OK")
```

- [ ] **Step 2: Update the harness to include this spec**

In `tests/run_tests.lua`, change:
```lua
local specs = {
}
```
to:
```lua
local specs = {
    "tests/constants_spec.lua",
}
```

- [ ] **Step 3: Run and verify it fails**

Run: `lua tests/run_tests.lua`
Expected: `[FAIL] tests/constants_spec.lua: ...` (the require'd file doesn't exist yet), exit code `1`.

- [ ] **Step 4: Implement Constants.lua**

`Where2Go/Core/Constants.lua`:
```lua
Where2GoConstants = {}

Where2GoConstants.ADDON_NAME = "Where2Go"
Where2GoConstants.INTERFACE_VERSION = 120100
Where2GoConstants.SEASON_LABEL = "Midnight Season 2"

function Where2GoConstants.BuildDefaultAccountDB()
    return {
        panelShown = false,
    }
end

function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {},
    }
end
```

- [ ] **Step 5: Run and verify it passes**

Run: `lua tests/run_tests.lua`
Expected:
```
[PASS] tests/constants_spec.lua

1 spec file(s), 0 failure(s)
```
Expected exit code: `0`

- [ ] **Step 6: Commit**

```bash
git add Where2Go/Core/Constants.lua tests/constants_spec.lua tests/run_tests.lua
git commit -m "feat: add Where2Go constants and default-DB builders"
```

---

### Task 3: Core/Fixtures.lua

**Files:**
- Create: `Where2Go/Core/Fixtures.lua`
- Test: `tests/fixtures_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/fixtures_spec.lua"` to `specs`)

**Interfaces:**
- Consumes: nothing.
- Produces: global table `Where2GoFixtures` with:
  - `Where2GoFixtures.dungeon`: a "card" table (see shape below).
  - `Where2GoFixtures.raid.name` (string) and `Where2GoFixtures.raid.encounters` (array of card tables).
  - Card table shape: `{ name = string, poolSize = number > 0, targetCount = number >= 0 and <= poolSize, recommendedLootSpec = string, items = array of strings, #items == targetCount }`.
  `UI/Panel.lua` (Task 6) reads this table directly to render rows.

- [ ] **Step 1: Write the failing test**

`tests/fixtures_spec.lua`:
```lua
dofile("Where2Go/Core/Fixtures.lua")

local function assertCard(card, label)
    assert(type(card.name) == "string" and #card.name > 0, label .. ": name must be a non-empty string")
    assert(type(card.poolSize) == "number" and card.poolSize > 0, label .. ": poolSize must be a positive number")
    assert(type(card.targetCount) == "number" and card.targetCount >= 0, label .. ": targetCount must be >= 0")
    assert(card.targetCount <= card.poolSize, label .. ": targetCount cannot exceed poolSize")
    assert(type(card.recommendedLootSpec) == "string" and #card.recommendedLootSpec > 0,
        label .. ": recommendedLootSpec must be a non-empty string")
    assert(type(card.items) == "table", label .. ": items must be a table")
    assert(#card.items == card.targetCount, label .. ": items count must match targetCount")
end

assert(type(Where2GoFixtures) == "table", "Where2GoFixtures must be a table")

assert(type(Where2GoFixtures.dungeon) == "table", "Where2GoFixtures.dungeon must be a table")
assertCard(Where2GoFixtures.dungeon, "dungeon")

assert(type(Where2GoFixtures.raid) == "table", "Where2GoFixtures.raid must be a table")
assert(type(Where2GoFixtures.raid.name) == "string" and #Where2GoFixtures.raid.name > 0,
    "raid.name must be a non-empty string")
assert(type(Where2GoFixtures.raid.encounters) == "table", "raid.encounters must be a table")
assert(#Where2GoFixtures.raid.encounters > 0, "raid.encounters must have at least one entry")

for i, encounter in ipairs(Where2GoFixtures.raid.encounters) do
    assertCard(encounter, "raid.encounters[" .. i .. "]")
end

print("fixtures_spec: OK, " .. #Where2GoFixtures.raid.encounters .. " encounter(s) verified")
```

- [ ] **Step 2: Update the harness to include this spec**

In `tests/run_tests.lua`, change:
```lua
local specs = {
    "tests/constants_spec.lua",
}
```
to:
```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/fixtures_spec.lua",
}
```

- [ ] **Step 3: Run and verify it fails**

Run: `lua tests/run_tests.lua`
Expected: `[FAIL] tests/fixtures_spec.lua: ...`, exit code `1`.

- [ ] **Step 4: Implement Fixtures.lua**

`Where2Go/Core/Fixtures.lua`:
```lua
-- Fixture data for Phase 1 (docs/DEVELOPMENT_PLAN.md).
--
-- Provenance and known limits:
-- * dungeon: a placeholder name. The season's real Mythic+ dungeon pool is
--   an open decision (see TODO.md) -- any dungeon works for Phase 1 since
--   this only verifies the panel's rendering shape.
-- * raid: "The Venomous Abyss" and its 9 encounters, sourced from
--   ai/vault/wiki/midnight-season2-raid.md, which is itself built from an
--   automated transcript of a pre-release Mythic test stream (patch 12.1).
--   Treat encounter names as a snapshot, not confirmed Encounter Journal
--   data -- Phase 5 replaces this with a real seasonal data source.
-- * poolSize / targetCount / recommendedLootSpec / items are ALL
--   placeholder values so the panel has something to render. Phase 3
--   computes real pool/target numbers; Phase 5 sources real item pools.

Where2GoFixtures = {
    dungeon = {
        name = "Sample Mythic+ Dungeon",
        poolSize = 8,
        targetCount = 2,
        recommendedLootSpec = "Elemental",
        items = { "Sample Item A", "Sample Item B" },
    },
    raid = {
        name = "The Venomous Abyss",
        encounters = {
            { name = "님리사 웨이브콜러", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item C" } },
            { name = "영혼살무사 네크잘리", poolSize = 6, targetCount = 1, recommendedLootSpec = "Restoration", items = { "Sample Item D" } },
            { name = "매장된 파수꾼", poolSize = 6, targetCount = 0, recommendedLootSpec = "Elemental", items = {} },
            { name = "길 잃은 탐험가", poolSize = 6, targetCount = 1, recommendedLootSpec = "Enhancement", items = { "Sample Item E" } },
            { name = "악성의 바쉬니크", poolSize = 6, targetCount = 2, recommendedLootSpec = "Elemental", items = { "Sample Item F", "Sample Item G" } },
            { name = "스조라크", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item H" } },
            { name = "쌍둥이 송곳니", poolSize = 6, targetCount = 0, recommendedLootSpec = "Restoration", items = {} },
            { name = "똬리의 제단", poolSize = 6, targetCount = 1, recommendedLootSpec = "Elemental", items = { "Sample Item I" } },
            { name = "울라텍", poolSize = 9, targetCount = 2, recommendedLootSpec = "Elemental", items = { "Sample Item J", "Sample Item K" } },
        },
    },
}
```

- [ ] **Step 5: Run and verify it passes**

Run: `lua tests/run_tests.lua`
Expected:
```
[PASS] tests/constants_spec.lua
[PASS] tests/fixtures_spec.lua

2 spec file(s), 0 failure(s)
```
Expected exit code: `0`

- [ ] **Step 6: Commit**

```bash
git add Where2Go/Core/Fixtures.lua tests/fixtures_spec.lua tests/run_tests.lua
git commit -m "feat: add Season 2 raid and dungeon fixture data"
```

---

### Task 4: Where2Go.toc manifest

**Files:**
- Create: `Where2Go/Where2Go.toc`
- Test: `tests/toc_spec.lua`
- Modify: `tests/run_tests.lua` (append `"tests/toc_spec.lua"` to `specs`)

**Interfaces:**
- Consumes: `Where2Go/Core/Constants.lua`, `Where2Go/Core/Fixtures.lua` (must already exist on disk from Tasks 2-3).
- Produces: the addon's load order — `Core/Constants.lua`, `Core/Fixtures.lua`, `Core/Init.lua`, `UI/Panel.lua` — which Tasks 5-6 depend on for their files to actually load in-client.

- [ ] **Step 1: Write the failing test**

`tests/toc_spec.lua`:
```lua
local tocPath = "Where2Go/Where2Go.toc"
local tocFile = assert(io.open(tocPath, "r"), "could not open " .. tocPath)

local referencedFiles = {}
for line in tocFile:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^##") then
        table.insert(referencedFiles, trimmed)
    end
end
tocFile:close()

assert(#referencedFiles > 0, "toc should list at least one Lua file to load")

for _, relPath in ipairs(referencedFiles) do
    local fsPath = "Where2Go/" .. relPath:gsub("\\", "/")
    local f = io.open(fsPath, "r")
    assert(f ~= nil, string.format("toc references %s but no file was found at %s", relPath, fsPath))
    if f then
        f:close()
    end
end

print("toc_spec: OK, " .. #referencedFiles .. " file(s) verified")
```

- [ ] **Step 2: Update the harness to include this spec**

In `tests/run_tests.lua`, change:
```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/fixtures_spec.lua",
}
```
to:
```lua
local specs = {
    "tests/constants_spec.lua",
    "tests/fixtures_spec.lua",
    "tests/toc_spec.lua",
}
```

- [ ] **Step 3: Run and verify it fails**

Run: `lua tests/run_tests.lua`
Expected: `[FAIL] tests/toc_spec.lua: could not open Where2Go/Where2Go.toc`, exit code `1`.

- [ ] **Step 4: Create the manifest**

`Where2Go/Where2Go.toc`:
```
## Interface: 120100
## Title: Where2Go
## Notes: Recommends the most efficient next Mythic+ dungeon or raid encounter for a player's preferred items.
## Author: HanGyulPark11
## Version: 0.1.0
## SavedVariables: Where2GoDB
## SavedVariablesPerCharacter: Where2GoCharDB

Core\Constants.lua
Core\Fixtures.lua
Core\Init.lua
UI\Panel.lua
```

Note: this step references `Core\Init.lua` and `UI\Panel.lua`, which don't exist until Tasks 5-6. That's expected — `toc_spec.lua` only runs after Task 6 creates those files (see Step 5 below); running it right after this step would still fail on those two paths.

- [ ] **Step 5: Run and verify it still fails on the not-yet-created files**

Run: `lua tests/run_tests.lua`
Expected: `[FAIL] tests/toc_spec.lua: toc references Core\Init.lua but no file was found at Where2Go/Core/Init.lua`, exit code `1`. This confirms the check is real (Steps 1-4 alone don't satisfy it) — Task 5 and Task 6 close the gap.

- [ ] **Step 6: Commit**

```bash
git add Where2Go/Where2Go.toc tests/toc_spec.lua tests/run_tests.lua
git commit -m "feat: add Where2Go.toc manifest and load-order contract test"
```

---

### Task 5: Core/Init.lua

**Files:**
- Create: `Where2Go/Core/Init.lua`

**Interfaces:**
- Consumes: `Where2GoConstants.ADDON_NAME`, `Where2GoConstants.BuildDefaultAccountDB()`, `Where2GoConstants.BuildDefaultCharDB()` (Task 2). Calls `Where2Go_TogglePanel()` (produced by Task 6 — not yet defined when this task lands, but not called until the user types the slash command after full load, so load order is safe).
- Produces: globals `Where2GoDB` (account-wide SavedVariables) and `Where2GoCharDB` (per-character SavedVariables), populated on `ADDON_LOADED`. Registers the `/where2go` slash command.

This task's logic is WoW-API-dependent (`CreateFrame`, `RegisterEvent`, `SlashCmdList`) and cannot run under the standalone `lua` interpreter — it is verified live in-client in Step 3 below.

- [ ] **Step 1: Implement Init.lua**

`Where2Go/Core/Init.lua`:
```lua
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName ~= Where2GoConstants.ADDON_NAME then
        return
    end

    Where2GoDB = Where2GoDB or Where2GoConstants.BuildDefaultAccountDB()
    Where2GoCharDB = Where2GoCharDB or Where2GoConstants.BuildDefaultCharDB()

    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_WHERE2GO1 = "/where2go"
SlashCmdList["WHERE2GO"] = function()
    Where2Go_TogglePanel()
end
```

- [ ] **Step 2: Run the automated suite to confirm nothing regressed**

Run: `lua tests/run_tests.lua`
Expected: `toc_spec` still fails (Step 5 of Task 4's expectation), now on `UI\Panel.lua` specifically:
```
[FAIL] tests/toc_spec.lua: toc references UI\Panel.lua but no file was found at Where2Go/UI/Panel.lua
```
This is expected — Task 6 closes the last gap.

- [ ] **Step 3: Commit**

```bash
git add Where2Go/Core/Init.lua
git commit -m "feat: initialize Where2Go SavedVariables and slash command"
```

---

### Task 6: UI/Panel.lua and full manual acceptance check

**Files:**
- Create: `Where2Go/UI/Panel.lua`

**Interfaces:**
- Consumes: `Where2GoConstants.ADDON_NAME` (Task 2), `Where2GoFixtures.dungeon` / `Where2GoFixtures.raid` (Task 3).
- Produces: global function `Where2Go_TogglePanel()`, called by `Core/Init.lua`'s slash command handler (Task 5).

- [ ] **Step 1: Implement Panel.lua**

`Where2Go/UI/Panel.lua`:
```lua
local panelFrame

local function AddRow(frame, y, text)
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line:SetPoint("TOPLEFT", 12, y)
    line:SetJustifyH("LEFT")
    line:SetWidth(336)
    line:SetText(text)
end

local function AddCardLine(frame, y, entry)
    local text = string.format("%s   %d/%d  |cff9d9d9d(%s)|r",
        entry.name, entry.targetCount, entry.poolSize, entry.recommendedLootSpec)
    AddRow(frame, y, text)
end

local function CreatePanel()
    local frame = CreateFrame("Frame", "Where2GoPanel", UIParent, "BackdropTemplate")
    frame:SetSize(380, 340)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(Where2GoConstants.ADDON_NAME)

    local y = -40
    AddRow(frame, y, "|cffffd200Mythic+|r")
    y = y - 18
    AddCardLine(frame, y, Where2GoFixtures.dungeon)
    y = y - 24

    AddRow(frame, y, "|cffffd200" .. Where2GoFixtures.raid.name .. "|r")
    y = y - 18
    for _, encounter in ipairs(Where2GoFixtures.raid.encounters) do
        AddCardLine(frame, y, encounter)
        y = y - 18
    end

    return frame
end

function Where2Go_TogglePanel()
    if not panelFrame then
        panelFrame = CreatePanel()
    end

    if panelFrame:IsShown() then
        panelFrame:Hide()
    else
        panelFrame:Show()
    end
end
```

- [ ] **Step 2: Run the full automated suite**

Run: `lua tests/run_tests.lua`
Expected:
```
[PASS] tests/constants_spec.lua
[PASS] tests/fixtures_spec.lua
[PASS] tests/toc_spec.lua

3 spec file(s), 0 failure(s)
```
Expected exit code: `0`

- [ ] **Step 3: Commit**

```bash
git add Where2Go/UI/Panel.lua
git commit -m "feat: render static Where2Go recommendation panel"
```

- [ ] **Step 4: MANUAL CHECKPOINT — link the addon into the WoW client and verify live**

This step cannot be run by an agent — it requires the WoW client, which nothing in this session can launch. Whoever executes this task should do the following themselves and report the result back before Phase 1 is considered done:

1. Link (don't copy, so future edits show up immediately) the `Where2Go/` folder into the retail client's AddOns directory, e.g. from an elevated/Developer Mode PowerShell:
   ```powershell
   New-Item -ItemType SymbolicLink -Path "<WoW install path>\_retail_\Interface\AddOns\Where2Go" -Target "C:\Users\hangy\ai\where2go\Where2Go"
   ```
   (substitute the real `<WoW install path>`; a plain folder copy also works if symlink creation isn't available, but then edits require re-copying).
2. Launch the client, log in to a character, and run `/reload`.
3. Confirm no Lua error popup appears (check `/console scriptErrors 1` beforehand if error popups are suppressed).
4. Run `/where2go` — confirm the panel appears, is titled "Where2Go", and lists the Mythic+ dungeon row followed by "The Venomous Abyss" and its 9 encounter rows.
5. Drag the panel by its body — confirm it moves.
6. Click the close button (or run `/where2go` again) — confirm it hides.
7. Run `/reload` again — confirm the addon still loads cleanly and no persistent game state changed (no new CVars, no altered Blizzard frames).

This satisfies `docs/DEVELOPMENT_PLAN.md` Phase 1's acceptance check: "the addon loads without errors after `/reload`, and the panel is visible and removable without changing game state."

---

## Done

Phase 1 is complete when all six tasks' commits exist and the Task 6 Step 4 manual checkpoint has been confirmed in a live client. Phase 2 (preferred items and equipment comparison) starts a new plan built on this foundation.
