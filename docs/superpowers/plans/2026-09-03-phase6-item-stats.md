# Phase 6, Sub-project A: Item Stat Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a script that fetches every item in `Sources.lua`'s stat
metadata (primary stat(s), secondary stat types) from the Battle.net API
and stores it as `Where2Go/Core/ItemStats.lua`, so Sub-project B's item
browser can filter by stat.

**Architecture:** `tools/data-prep/generate_item_stats.py` reuses
`generate_sources.py`'s `get_token()`/`api_get()` (imported, not
duplicated), scans `Where2Go/Core/Sources.lua`'s text for every `itemIds`
array to collect the full set of item IDs in play, fetches each item's
`preview_item.stats` from `/data/wow/item/{id}`, and renders a
`Where2GoItemStats.STATS` Lua table — staged to `scratch/` and diffed
against the committed file, exactly like `generate_sources.py`.

**Tech Stack:** Python (stdlib only, plus importing from the existing
`generate_sources.py`), Lua (the generated data file + a new test spec).

**Spec:** `docs/superpowers/specs/2026-09-03-phase6-item-stats-design.md`

## Global Constraints

- No new pip dependency. Reuse `tools/data-prep/generate_sources.py`'s
  `get_token()` and `api_get()` functions via import rather than
  duplicating the OAuth flow.
- `tools/data-prep/scratch/` is already gitignored (Phase 5, Sub-project
  1) — no new `.gitignore` entry needed for this sub-project.
- Credentials come only from `BLIZZARD_CLIENT_ID`/`BLIZZARD_CLIENT_SECRET`
  environment variables (already the established convention) — never
  hardcoded, never printed.
- Never write `Where2Go/Core/ItemStats.lua` directly from the script —
  stage to `scratch/ItemStats.lua.new`, print a diff, human copies it
  over deliberately. Same rule as `Sources.lua`.
- A stat's `is_negated: true` entry in the API response means that stat
  option is inactive for this item's default reading and must be
  excluded — only non-negated stats count. A single item may legitimately
  have more than one non-negated primary stat (some armor/trinkets do) —
  store `primaryStats` as a list, not a single value, to avoid silently
  dropping a valid second option.
- `Where2Go/Core/ItemStats.lua` does not exist yet at all (this is a new
  file, unlike `Sources.lua` which already had real data before its
  Phase 5 tooling was built) — Task 3 (the manual live run) is
  necessarily NOT the last task in this plan, because Task 4's test spec
  needs the real committed file to exist first. This deliberately departs
  from the "manual checkpoint always last" pattern used elsewhere in this
  project; the dependency is real, not an oversight.

---

## File Structure

```
tools/data-prep/generate_item_stats.py   NEW — fetch + render + diff script
Where2Go/Core/ItemStats.lua               NEW — committed by the manual step (Task 3)
tests/itemstats_spec.lua                  NEW — structural test on the real file
tests/run_tests.lua                       MODIFY — register the new spec
```

---

### Task 1: Item ID extraction + per-item stat fetch

**Files:**
- Create: `tools/data-prep/generate_item_stats.py`

**Interfaces:**
- Produces: `extract_item_ids(sources_lua_text)` → `set[int]`;
  `fetch_item_stats(token, item_id)` → `dict` shaped
  `{"primaryStats": [str, ...], "secondaryStats": [str, ...]}`.
- Consumes: `get_token()` and `api_get(token, path, namespace=...,
  locale=...)` imported from `generate_sources.py` (same directory).

- [ ] **Step 1: Write the file's header and imports, importing the shared helpers**

```python
"""Fetch per-item stat metadata (primary/secondary stat types) for every
item referenced in Where2Go/Core/Sources.lua, from the Battle.net Game
Data API. Stages output at tools/data-prep/scratch/ItemStats.lua.new and
prints a diff against the committed Where2Go/Core/ItemStats.lua for
review -- never writes that file directly.

Usage:
    $env:BLIZZARD_CLIENT_ID="<your id>"; $env:BLIZZARD_CLIENT_SECRET="<your secret>"; python tools/data-prep/generate_item_stats.py

See docs/SEASON_CHECKLIST.md for the full season-changeover procedure.
"""

import difflib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_sources import get_token, api_get  # noqa: E402

SCRATCH = os.path.join(HERE, "scratch")
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Sources.lua")
ITEM_STATS_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "ItemStats.lua")

PRIMARY_STAT_TYPES = {"STRENGTH", "AGILITY", "INTELLECT"}
SECONDARY_STAT_TYPES = {"CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "VERSATILITY"}
```

- [ ] **Step 2: Add item ID extraction from Sources.lua's text**

```python
def extract_item_ids(sources_lua_text):
    item_ids = set()
    for match in re.finditer(r"itemIds\s*=\s*\{([^}]*)\}", sources_lua_text):
        for piece in match.group(1).split(","):
            piece = piece.strip()
            if piece:
                item_ids.add(int(piece))
    return item_ids
```

- [ ] **Step 3: Add the per-item stat fetch**

```python
def fetch_item_stats(token, item_id):
    data = api_get(token, f"/data/wow/item/{item_id}")
    preview = data.get("preview_item", {})
    stats = preview.get("stats", [])
    primary_stats = []
    secondary_stats = []
    for stat in stats:
        if stat.get("is_negated"):
            continue
        stat_type = stat.get("type", {}).get("type")
        if stat_type in PRIMARY_STAT_TYPES:
            primary_stats.append(stat_type)
        elif stat_type in SECONDARY_STAT_TYPES:
            secondary_stats.append(stat_type)
    return {"primaryStats": primary_stats, "secondaryStats": secondary_stats}
```

- [ ] **Step 4: Verify `extract_item_ids` against the real committed Sources.lua**

This substitutes for a unit test (no automated test suite for this
script, matching `generate_sources.py`'s precedent): run it against real
data already in the repo and sanity-check the count.

Run this from the repo root (the hyphen in `data-prep` makes it an
invalid Python package name, so import via `sys.path` instead of dotted
package notation):
```
python -c "import sys; sys.path.insert(0, 'tools/data-prep'); from generate_item_stats import extract_item_ids; text = open('Where2Go/Core/Sources.lua', encoding='utf-8').read(); ids = extract_item_ids(text); print(len(ids)); print(sorted(ids)[:5])"
```

Expected: a positive integer count (order of a few hundred, given 8
dungeons × 3-4 bosses × 7-12 items plus 9 raid bosses × ~13-18 items,
deduplicated) and no exception. Confirm by spot-checking that a couple of
real item IDs you can see in `Sources.lua` (e.g. `273796` from Altar of
Fangs' first boss) appear in the returned set.

- [ ] **Step 5: Verify the file compiles**

Run: `python -m py_compile tools/data-prep/generate_item_stats.py`
Expected: no output, exit code 0. (`fetch_item_stats` itself isn't
exercised here — it needs real credentials, verified for real in Task 3.)

- [ ] **Step 6: Commit**

```bash
git add tools/data-prep/generate_item_stats.py
git commit -m "feat: add item ID extraction and per-item stat fetch for data-prep"
```

---

### Task 2: Lua rendering, diff, and main()

**Files:**
- Modify: `tools/data-prep/generate_item_stats.py`

**Interfaces:**
- Consumes: `extract_item_ids`, `fetch_item_stats` (Task 1).
- Produces: `render_lua(item_stats)` → `str`; `diff_against_current(new_content)`
  → `str`; `main()`; the `if __name__ == "__main__":` entry point.

- [ ] **Step 1: Add the Lua renderer**

```python
def render_lua(item_stats):
    lines = [
        "-- Regenerated by tools/data-prep/generate_item_stats.py from the Battle.net",
        "-- Game Data API. Do not hand-edit -- if the data needs correcting, regenerate",
        "-- from the same source. See docs/SEASON_CHECKLIST.md.",
        "",
        "Where2GoItemStats = {}",
        "",
        "Where2GoItemStats.STATS = {",
    ]
    for item_id in sorted(item_stats.keys()):
        stats = item_stats[item_id]
        primary = ", ".join(f'"{s}"' for s in stats["primaryStats"])
        secondary = ", ".join(f'"{s}"' for s in stats["secondaryStats"])
        lines.append(
            f"    [{item_id}] = {{ primaryStats = {{ {primary} }}, "
            f"secondaryStats = {{ {secondary} }} }},"
        )
    lines.append("}")
    lines.append("")
    return "\n".join(lines)
```

- [ ] **Step 2: Add the diff function**

```python
def diff_against_current(new_content):
    if os.path.exists(ITEM_STATS_LUA_PATH):
        with open(ITEM_STATS_LUA_PATH, "r", encoding="utf-8") as f:
            current_content = f.read()
    else:
        current_content = ""
    diff = difflib.unified_diff(
        current_content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile="Where2Go/Core/ItemStats.lua (current)",
        tofile="scratch/ItemStats.lua.new (generated)",
    )
    diff_text = "".join(diff)
    print(diff_text if diff_text else "No differences from the current ItemStats.lua.")
    return diff_text
```

- [ ] **Step 3: Add main() and the entry point**

```python
def main():
    with open(SOURCES_LUA_PATH, "r", encoding="utf-8") as f:
        sources_text = f.read()
    item_ids = extract_item_ids(sources_text)

    token = get_token()
    item_stats = {}
    for item_id in sorted(item_ids):
        item_stats[item_id] = fetch_item_stats(token, item_id)

    new_content = render_lua(item_stats)

    os.makedirs(SCRATCH, exist_ok=True)
    staged_path = os.path.join(SCRATCH, "ItemStats.lua.new")
    with open(staged_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Staged output written to {staged_path}, {len(item_ids)} items fetched")

    diff_against_current(new_content)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Verify `render_lua` against fixture data**

Run:
```
python -c "
import sys
sys.path.insert(0, 'tools/data-prep')
from generate_item_stats import render_lua
print(render_lua({
    273796: {'primaryStats': ['AGILITY'], 'secondaryStats': ['CRIT_RATING', 'HASTE_RATING']},
    273795: {'primaryStats': [], 'secondaryStats': ['MASTERY_RATING']},
}))
"
```
Expected output (exact, including indentation and spacing):
```
-- Regenerated by tools/data-prep/generate_item_stats.py from the Battle.net
-- Game Data API. Do not hand-edit -- if the data needs correcting, regenerate
-- from the same source. See docs/SEASON_CHECKLIST.md.

Where2GoItemStats = {}

Where2GoItemStats.STATS = {
    [273795] = { primaryStats = {  }, secondaryStats = { "MASTERY_RATING" } },
    [273796] = { primaryStats = { "AGILITY" }, secondaryStats = { "CRIT_RATING", "HASTE_RATING" } },
}
```
Confirm this parses as valid Lua by saving the printed output to a
temporary file and syntax-checking it:
```
python -c "
import sys
sys.path.insert(0, 'tools/data-prep')
from generate_item_stats import render_lua
open('tools/data-prep/scratch/_verify.lua', 'w', encoding='utf-8').write(render_lua({
    273796: {'primaryStats': ['AGILITY'], 'secondaryStats': ['CRIT_RATING', 'HASTE_RATING']},
    273795: {'primaryStats': [], 'secondaryStats': ['MASTERY_RATING']},
}))
"
"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" -e "assert(loadfile('tools/data-prep/scratch/_verify.lua'))" && echo OK
rm tools/data-prep/scratch/_verify.lua
```

- [ ] **Step 5: Verify the file compiles**

Run: `python -m py_compile tools/data-prep/generate_item_stats.py`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add tools/data-prep/generate_item_stats.py
git commit -m "feat: add Lua rendering, diff, and entry point for item stats generator"
```

---

### Task 3: Manual live checkpoint — generate and commit the real ItemStats.lua

**Files:**
- Create: `Where2Go/Core/ItemStats.lua` (by the human, from the script's
  staged output — not by an agent).
- Modify: `Where2Go.toc` (add the new file to the load order, after
  `Sources.lua` since nothing depends on load order between them but
  keeping data files grouped together is consistent with the existing
  TOC's organization).

**Interfaces:**
- Produces: the real `Where2GoItemStats.STATS` table Task 4's test spec
  and Sub-project B's browser will both depend on.

- [ ] **Step 1: MANUAL CHECKPOINT — run generate_item_stats.py for real**

This cannot be done by an agent — it requires real Battle.net Developer
API credentials, which must never be typed into an AI coding assistant's
conversation or run through a shared/logged shell. Whoever executes this
task should, in their own terminal:

1. From the repo root:
   ```powershell
   $env:BLIZZARD_CLIENT_ID="<your id>"; $env:BLIZZARD_CLIENT_SECRET="<your secret>"; python tools/data-prep/generate_item_stats.py
   ```
   (If credentials are already set at the User environment-variable
   level, as they were for `generate_sources.py`, this can be run with no
   `$env:` prefix at all.)
2. This will take longer than `generate_sources.py` did — it makes one
   API call per unique item (several hundred), not one per dungeon/raid
   instance. Expect it to take a couple of minutes.
3. Since `Where2Go/Core/ItemStats.lua` doesn't exist yet, the printed
   diff will show the entire file as new content, not a small delta —
   that's expected for a first-ever run, not a bug.
4. Read through a sample of the output — confirm item IDs you recognize
   (e.g. weapons) show a sensible primary stat, and that not every single
   item has stats (some legitimately won't, e.g. non-armor curios) —
   this is expected per the spec's error-handling section, not a failure.
5. Copy `tools/data-prep/scratch/ItemStats.lua.new`'s content into a new
   file, `Where2Go/Core/ItemStats.lua`.

- [ ] **Step 2: Add the new file to Where2Go.toc**

Open `Where2Go/Where2Go.toc` and add `Core\ItemStats.lua` to the file
list, after `Core\Sources.lua`:

```
Core\Constants.lua
Core\Tracks.lua
Core\Sources.lua
Core\ItemStats.lua
Core\RaidRanks.lua
...
```

- [ ] **Step 3: Run the full test suite**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `toc_spec` still passes (it will now report 13 files instead of
12) — Task 4 hasn't added `itemstats_spec.lua` yet, so no new spec exists
to fail regardless of `ItemStats.lua`'s content shape at this point.

- [ ] **Step 4: Commit**

```bash
git add Where2Go/Core/ItemStats.lua Where2Go/Where2Go.toc
git commit -m "feat: add generated per-item stat metadata (ItemStats.lua)"
```

Report back to the controller once this is committed, including the
total item count fetched, so Task 4 can be dispatched against real data.

---

### Task 4: Write `tests/itemstats_spec.lua`

**Files:**
- Create: `tests/itemstats_spec.lua`
- Modify: `tests/run_tests.lua`

**Interfaces:**
- Consumes: the real, committed `Where2Go/Core/ItemStats.lua` from Task 3
  — this task cannot start until Task 3 is complete and reported back.

- [ ] **Step 1: Write the spec**

```lua
dofile("Where2Go/Core/ItemStats.lua")

assert(type(Where2GoItemStats) == "table", "Where2GoItemStats should be a table")
assert(type(Where2GoItemStats.STATS) == "table", "Where2GoItemStats.STATS should be a table")

local count = 0
for _ in pairs(Where2GoItemStats.STATS) do
    count = count + 1
end
assert(count > 0, "Where2GoItemStats.STATS should be non-empty")

local VALID_PRIMARY = { STRENGTH = true, AGILITY = true, INTELLECT = true }
local VALID_SECONDARY = {
    CRIT_RATING = true, HASTE_RATING = true, MASTERY_RATING = true, VERSATILITY = true,
}

for itemId, stats in pairs(Where2GoItemStats.STATS) do
    assert(type(itemId) == "number", "item stat keys should be numeric item IDs")
    assert(type(stats.primaryStats) == "table", "primaryStats should be a table for item " .. itemId)
    assert(type(stats.secondaryStats) == "table", "secondaryStats should be a table for item " .. itemId)
    for _, stat in ipairs(stats.primaryStats) do
        assert(VALID_PRIMARY[stat], "unexpected primary stat '" .. tostring(stat) .. "' for item " .. itemId)
    end
    for _, stat in ipairs(stats.secondaryStats) do
        assert(VALID_SECONDARY[stat], "unexpected secondary stat '" .. tostring(stat) .. "' for item " .. itemId)
    end
end

print("itemstats_spec: OK, " .. count .. " item(s) with stat data")
```

- [ ] **Step 2: Register the spec in run_tests.lua**

Read `tests/run_tests.lua` and add `"itemstats_spec"` to its list of spec
names, following the exact same pattern as the existing entries (e.g.
next to `"sources_spec"`).

- [ ] **Step 3: Run it and verify it passes**

Run: `"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua`
Expected: `itemstats_spec: OK, N item(s) with stat data` printed (N > 0),
all specs pass, `toc_spec` reports 13 files.

- [ ] **Step 4: Commit**

```bash
git add tests/itemstats_spec.lua tests/run_tests.lua
git commit -m "test: add itemstats_spec validating ItemStats.lua's structure"
```

---

## Done

This sub-project is complete when all four tasks' commits exist (Task 3's
manual step included) and the full test suite passes with
`itemstats_spec` registered and green. Sub-project B (the item browser
UI) depends on `Where2GoItemStats.STATS` existing and can begin once this
is done.
