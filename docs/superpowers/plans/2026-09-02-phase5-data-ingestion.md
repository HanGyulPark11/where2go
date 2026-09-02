# Phase 5, Sub-project 1: Seasonal Data Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single Python script that regenerates `Where2Go/Core/Sources.lua`'s
dungeon/raid item-pool data from the Battle.net Journal API, with a manual
diff-review gate instead of auto-overwriting, plus a season-changeover
checklist document covering the two other season-dependent files that have
no API (`Tracks.lua`, `RaidRanks.lua`).

**Architecture:** One script (`tools/data-prep/generate_sources.py`)
authenticates via OAuth client-credentials, walks the Journal API for a
hand-maintained list of this-season instance IDs, renders the result into
`Where2GoSources`'s exact existing Lua schema, writes it to a gitignored
staging file, and prints a diff against the committed `Sources.lua` for a
human to review before manually replacing the file.

**Tech Stack:** Python 3.13 (already installed at `C:\Python313\python.exe`,
on PATH as `python`), standard library only (`urllib`, `json`, `difflib`,
`base64`, `os`) — no pip dependencies.

**Spec:** `docs/superpowers/specs/2026-09-02-phase5-data-ingestion-design.md`

## Global Constraints

- Python standard library only — no `pip install`, no `requirements.txt`.
  Keeps the tool runnable with zero setup beyond the two credential
  environment variables.
- Credentials come only from `BLIZZARD_CLIENT_ID` / `BLIZZARD_CLIENT_SECRET`
  environment variables. Never write them to a file, never print them,
  never hardcode them.
- The script must never write to `Where2Go/Core/Sources.lua` directly. All
  generated output goes to `tools/data-prep/scratch/Sources.lua.new`; a
  human copies it over deliberately.
- `tools/data-prep/scratch/` must be gitignored before the script can ever
  produce output there.
- No automated unit tests for this script (per the design's explicit
  decision) — it's an interactively-run, roughly-once-per-season developer
  tool. Verification instead happens via (a) a manual byte-level check of
  the Lua-rendering logic against real data already in the repo (Task 3),
  and (b) a live dry run against real Season 2 data as the final manual
  checkpoint (Task 7).
- `SEASON_INSTANCES`'s initial value must be the current Season 2 instance
  IDs, copied verbatim from the already-committed `Where2Go/Core/Sources.lua`
  (not re-derived or guessed): dungeons `1322, 1311, 1304, 1309, 1313,
  1041, 1202, 1030`; raids `1317, 1320`.
- Match `Where2Go/Core/Sources.lua`'s exact existing indentation and
  brace-spacing style in all generated Lua (4-space instance indent,
  8-space field indent, 12-space encounter-row indent, single space inside
  `{ ... }` on both sides) — Task 3's manual check below is the
  byte-comparison that enforces this.

---

## File Structure

```
tools/data-prep/
├── generate_sources.py    NEW — the whole script
├── scratch/                 NEW at runtime, gitignored — never committed
└── README.md               NEW — credential setup + run instructions

docs/
└── SEASON_CHECKLIST.md     NEW — full season-changeover procedure

.gitignore                  MODIFY — add tools/data-prep/scratch/
```

---

### Task 1: Gitignore the scratch directory and scaffold the tool directory

**Files:**
- Modify: `.gitignore`
- Create: `tools/data-prep/` (directory, via a placeholder that Task 2 fills)

**Interfaces:**
- Produces: an ignored `tools/data-prep/scratch/` path that Task 2's script
  writes into.

- [ ] **Step 1: Add the scratch directory to .gitignore**

Read the current `.gitignore` (it currently contains only `.worktrees/`).
Add a new line:

```
tools/data-prep/scratch/
```

- [ ] **Step 2: Verify the ignore rule works**

Run: `mkdir -p tools/data-prep/scratch && touch tools/data-prep/scratch/test.txt && git status --porcelain`
Expected: no output mentioning `tools/data-prep/scratch/test.txt` (the
directory itself may or may not show depending on git version, but the
file inside must not appear as untracked).

Then remove the test file: `rm tools/data-prep/scratch/test.txt`

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore tools/data-prep/scratch/"
```

---

### Task 2: Implement OAuth token fetch, API GET helper, and Journal API traversal

**Files:**
- Create: `tools/data-prep/generate_sources.py`

**Interfaces:**
- Produces: `get_token()` → `str` (access token); `api_get(token, path,
  namespace="static-us", locale="en_US")` → `dict` (parsed JSON);
  `fetch_instance(token, instance_id)` → `dict` shaped
  `{"instanceId": int, "name": str, "encounters": [{"bossId": int, "name":
  str, "itemIds": [int, ...]}, ...]}`; `check_structural_warnings(label,
  instances)` → `None` (prints warnings, does not raise).
- Consumes: nothing from earlier tasks (this is the first code task).

- [ ] **Step 1: Write the file's header, imports, and constants**

```python
"""Regenerate Where2Go/Core/Sources.lua's dungeon/raid item-pool data from
the Battle.net Game Data API Journal endpoints for the current season.

Usage:
    BLIZZARD_CLIENT_ID=... BLIZZARD_CLIENT_SECRET=... python tools/data-prep/generate_sources.py

Never writes Where2Go/Core/Sources.lua directly -- it stages output at
tools/data-prep/scratch/Sources.lua.new and prints a diff for review.
See docs/SEASON_CHECKLIST.md for the full season-changeover procedure.
"""

import base64
import difflib
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SCRATCH = os.path.join(HERE, "scratch")
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SOURCES_LUA_PATH = os.path.join(REPO_ROOT, "Where2Go", "Core", "Sources.lua")

REGION_HOST = "https://us.api.blizzard.com"

# Update this each season -- see docs/SEASON_CHECKLIST.md step 1. The
# Battle.net API has no "current season" endpoint, so these instance IDs
# must be looked up by hand (e.g. wowhead/wiki) and filled in here.
SEASON_INSTANCES = {
    "dungeons": [1322, 1311, 1304, 1309, 1313, 1041, 1202, 1030],
    "raids": [1317, 1320],
}
```

- [ ] **Step 2: Add the OAuth token fetch**

```python
def get_token():
    client_id = os.environ["BLIZZARD_CLIENT_ID"]
    client_secret = os.environ["BLIZZARD_CLIENT_SECRET"]
    auth = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    req = urllib.request.Request(
        "https://oauth.battle.net/token",
        data=b"grant_type=client_credentials",
        headers={"Authorization": f"Basic {auth}"},
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        data = json.load(resp)
    os.makedirs(SCRATCH, exist_ok=True)
    with open(os.path.join(SCRATCH, "token.json"), "w", encoding="utf-8") as f:
        json.dump(data, f)
    return data["access_token"]
```

- [ ] **Step 3: Add the generic API GET helper**

```python
def api_get(token, path, namespace="static-us", locale="en_US"):
    url = f"{REGION_HOST}{path}?namespace={namespace}&locale={locale}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)
```

- [ ] **Step 4: Add the per-instance Journal API traversal**

```python
def fetch_instance(token, instance_id):
    instance = api_get(token, f"/data/wow/journal-instance/{instance_id}")
    encounters = []
    for enc_ref in instance.get("encounters", []):
        enc_id = enc_ref["id"]
        detail = api_get(token, f"/data/wow/journal-encounter/{enc_id}")
        item_ids = [item["item"]["id"] for item in detail.get("items", [])]
        encounters.append({
            "bossId": enc_id,
            "name": detail["name"],
            "itemIds": item_ids,
        })
    return {"instanceId": instance_id, "name": instance["name"], "encounters": encounters}
```

- [ ] **Step 5: Add the structural sanity-check warnings**

```python
def check_structural_warnings(label, instances):
    for instance in instances:
        seen_boss_ids = set()
        for encounter in instance["encounters"]:
            if not encounter["itemIds"]:
                print(
                    f"WARNING: {label} '{instance['name']}' encounter "
                    f"'{encounter['name']}' (bossId {encounter['bossId']}) has no items"
                )
            if encounter["bossId"] in seen_boss_ids:
                print(
                    f"WARNING: {label} '{instance['name']}' has duplicate "
                    f"bossId {encounter['bossId']}"
                )
            seen_boss_ids.add(encounter["bossId"])
```

- [ ] **Step 6: Verify the file compiles**

Run: `python -m py_compile tools/data-prep/generate_sources.py`
Expected: no output, exit code 0 (this only checks syntax — the network
functions are exercised for real in Task 7's live checkpoint, since they
need real credentials this task doesn't have).

- [ ] **Step 7: Commit**

```bash
git add tools/data-prep/generate_sources.py
git commit -m "feat: add Battle.net auth and Journal API traversal for data-prep"
```

---

### Task 3: Implement Lua rendering and verify it byte-matches the existing file

**Files:**
- Modify: `tools/data-prep/generate_sources.py`

**Interfaces:**
- Consumes: the `{"instanceId", "name", "encounters"}` shape produced by
  Task 2's `fetch_instance`.
- Produces: `lua_str(s)` → `str` (quoted Lua string literal);
  `render_instance(instance)` → `str` (one instance's Lua block, no
  trailing newline); `render_lua(dungeons, raids)` → `str` (the complete
  file content, matching `Where2GoSources.DUNGEONS`/`.RAIDS` shape).

- [ ] **Step 1: Add the Lua string-escaping helper**

```python
def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
```

- [ ] **Step 2: Add the per-instance renderer**

```python
def render_instance(instance):
    lines = ["    {"]
    lines.append(f"        instanceId = {instance['instanceId']},")
    lines.append(f"        name = {lua_str(instance['name'])},")
    lines.append("        encounters = {")
    for encounter in instance["encounters"]:
        item_ids_str = ", ".join(str(i) for i in encounter["itemIds"])
        lines.append(
            f"            {{ bossId = {encounter['bossId']}, "
            f"name = {lua_str(encounter['name'])}, "
            f"itemIds = {{ {item_ids_str} }} }},"
        )
    lines.append("        },")
    lines.append("    },")
    return "\n".join(lines)
```

- [ ] **Step 3: Add the whole-file renderer**

```python
def render_lua(dungeons, raids):
    lines = [
        "-- Regenerated by tools/data-prep/generate_sources.py from the Battle.net",
        "-- Game Data API Journal endpoints. Do not hand-edit -- if the data needs",
        "-- correcting, regenerate from the same source. See docs/SEASON_CHECKLIST.md.",
        "",
        "Where2GoSources = {}",
        "",
        "Where2GoSources.DUNGEONS = {",
    ]
    for instance in dungeons:
        lines.append(render_instance(instance))
    lines.append("}")
    lines.append("")
    lines.append("Where2GoSources.RAIDS = {")
    for instance in raids:
        lines.append(render_instance(instance))
    lines.append("}")
    lines.append("")
    return "\n".join(lines)
```

- [ ] **Step 4: Manually verify the renderer byte-matches the real file's style**

This substitutes for a unit test (per the design's no-automated-tests
decision): exercise `render_instance` against the real "Altar of Fangs"
data already committed in `Where2Go/Core/Sources.lua` (lines 15-23) and
confirm the output matches character-for-character except the outer
`Where2GoSources.DUNGEONS = {` / trailing comma context.

Run:
```bash
python -c "
import sys
sys.path.insert(0, 'tools/data-prep')
from generate_sources import render_instance

instance = {
    'instanceId': 1322,
    'name': \"Altar of Fangs\",
    'encounters': [
        {'bossId': 2878, 'name': \"Rav'i\", 'itemIds': [273796, 273795, 273785, 273775, 273777, 273780, 273793]},
        {'bossId': 2879, 'name': 'The Writhing Coil', 'itemIds': [273781, 273794, 273786, 273774, 273787, 273782, 273783, 273779]},
        {'bossId': 2880, 'name': \"Zul'jan\", 'itemIds': [273792, 273797, 273773, 273791, 273789, 273776, 273778, 273784, 270900, 275070, 279211, 276804]},
    ],
}
print(render_instance(instance))
"
```

Expected output (must match exactly, including indentation and spacing):
```
    {
        instanceId = 1322,
        name = "Altar of Fangs",
        encounters = {
            { bossId = 2878, name = "Rav'i", itemIds = { 273796, 273795, 273785, 273775, 273777, 273780, 273793 } },
            { bossId = 2879, name = "The Writhing Coil", itemIds = { 273781, 273794, 273786, 273774, 273787, 273782, 273783, 273779 } },
            { bossId = 2880, name = "Zul'jan", itemIds = { 273792, 273797, 273773, 273791, 273789, 273776, 273778, 273784, 270900, 275070, 279211, 276804 } },
        },
    },
```

Compare this against `Where2Go/Core/Sources.lua` lines 15-23 directly (`sed -n '15,23p' Where2Go/Core/Sources.lua`, or open the file) — every line must match. If it doesn't, fix `render_instance`/`lua_str` until it does before proceeding.

- [ ] **Step 5: Commit**

```bash
git add tools/data-prep/generate_sources.py
git commit -m "feat: add Lua rendering for generated Sources.lua data"
```

---

### Task 4: Implement diff-against-current and wire up main()

**Files:**
- Modify: `tools/data-prep/generate_sources.py`

**Interfaces:**
- Consumes: `SEASON_INSTANCES` (Task 2), `get_token`/`fetch_instance`/
  `check_structural_warnings` (Task 2), `render_lua` (Task 3).
- Produces: `diff_against_current(new_content)` → `str` (the diff text,
  also printed); `main()` → `None`; the `if __name__ == "__main__":` entry
  point.

- [ ] **Step 1: Add the diff function**

```python
def diff_against_current(new_content):
    if os.path.exists(SOURCES_LUA_PATH):
        with open(SOURCES_LUA_PATH, "r", encoding="utf-8") as f:
            current_content = f.read()
    else:
        current_content = ""
    diff = difflib.unified_diff(
        current_content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile="Where2Go/Core/Sources.lua (current)",
        tofile="scratch/Sources.lua.new (generated)",
    )
    diff_text = "".join(diff)
    print(diff_text if diff_text else "No differences from the current Sources.lua.")
    return diff_text
```

- [ ] **Step 2: Add main() and the entry point**

```python
def main():
    token = get_token()
    dungeons = [fetch_instance(token, iid) for iid in SEASON_INSTANCES["dungeons"]]
    raids = [fetch_instance(token, iid) for iid in SEASON_INSTANCES["raids"]]

    check_structural_warnings("DUNGEONS", dungeons)
    check_structural_warnings("RAIDS", raids)

    new_content = render_lua(dungeons, raids)

    os.makedirs(SCRATCH, exist_ok=True)
    staged_path = os.path.join(SCRATCH, "Sources.lua.new")
    with open(staged_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Staged output written to {staged_path}")

    diff_against_current(new_content)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Verify the file compiles**

Run: `python -m py_compile tools/data-prep/generate_sources.py`
Expected: no output, exit code 0.

- [ ] **Step 4: Commit**

```bash
git add tools/data-prep/generate_sources.py
git commit -m "feat: wire up generate_sources.py's diff-and-stage entry point"
```

---

### Task 5: Write the data-prep README

**Files:**
- Create: `tools/data-prep/README.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write the README**

```markdown
# Where2Go data-prep tooling

`generate_sources.py` regenerates `Where2Go/Core/Sources.lua`'s dungeon and
raid item-pool data from the Battle.net Game Data API's Journal endpoints.
It never writes `Sources.lua` directly — it stages its output at
`scratch/Sources.lua.new` and prints a diff for you to review.

## One-time setup

You need a Battle.net Developer API client ID and secret
(https://develop.battle.net — a free client-credentials app). Do not commit
these anywhere; they're read only from environment variables.

## Running it

Each season, first update `SEASON_INSTANCES` at the top of
`generate_sources.py` with the current season's dungeon and raid instance
IDs (the API has no "current season" endpoint — look these up by hand).
Then, from the repo root:

```
BLIZZARD_CLIENT_ID=<your id> BLIZZARD_CLIENT_SECRET=<your secret> python tools/data-prep/generate_sources.py
```

Review the printed diff. If it looks correct, copy
`tools/data-prep/scratch/Sources.lua.new`'s content into
`Where2Go/Core/Sources.lua`.

See `docs/SEASON_CHECKLIST.md` for the full season-changeover procedure,
including the manual steps for `Tracks.lua` and `RaidRanks.lua` that this
script does not cover.
```

- [ ] **Step 2: Commit**

```bash
git add tools/data-prep/README.md
git commit -m "docs: add data-prep tooling README"
```

---

### Task 6: Write the season changeover checklist

**Files:**
- Create: `docs/SEASON_CHECKLIST.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Write the checklist**

```markdown
# Season Changeover Checklist

Follow these steps in order whenever a new WoW season starts and
Where2Go's data needs updating. Do not skip ahead — later steps assume
earlier ones are done.

1. **Look up this season's content.** Find the new Mythic+ dungeon
   rotation and raid instance IDs (e.g. via wowhead or the official patch
   notes). Update the `SEASON_INSTANCES` constant at the top of
   `tools/data-prep/generate_sources.py` with the new instance IDs.

2. **Run the data-prep script.** See `tools/data-prep/README.md` for
   credential setup. From the repo root:
   ```
   BLIZZARD_CLIENT_ID=<id> BLIZZARD_CLIENT_SECRET=<secret> python tools/data-prep/generate_sources.py
   ```

3. **Review the diff.** The script prints a diff between the current
   `Where2Go/Core/Sources.lua` and the freshly generated data. Read it
   carefully — look especially at the structural warnings the script
   prints above the diff (empty item lists, duplicate boss IDs). If it
   looks correct, copy `tools/data-prep/scratch/Sources.lua.new`'s
   content into `Where2Go/Core/Sources.lua`.

4. **Re-measure `Where2Go/Core/RaidRanks.lua` in-client.** This file has
   no API equivalent. For the new raid, determine each boss's relative
   item-level rank (1-4) and whether any boss drops a special
   above-normal-cap track (like Season 2's Myth-9/6 final bosses), the
   same way `RaidRanks.lua`'s own comments describe doing it for Season 2
   (e.g. checking a known dropped item's bonus ID against its item level
   via `/where2go scanbonus` or an equivalent in-client check). Update
   `RAID_BOSS_RANK`, `MYTH_FINAL_BOSS_IDS`, `MYTH_FINAL_ILVL`, and
   `MYTH_FINAL_RANK` by hand to match.

5. **Check `Where2Go/Core/Tracks.lua`.** Confirm whether the upgrade-track
   bonus ID ranges (Veteran/Champion/Hero/Myth) changed this season —
   Blizzard sometimes shifts these between seasons. Update by hand if so.

6. **Update `tests/sources_spec.lua`'s season-specific assertions.** The
   check near the bottom of the file (currently asserting `RAIDS[2]` is
   "The Venomous Abyss" with exactly 8 encounters) is Season-2-specific.
   Replace it with an equivalent spot-check for the new season's actual
   raid content, or remove it if no longer meaningful.

7. **Run the full test suite and commit.**
   ```
   "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
   ```
   Confirm all specs pass before committing the updated `Sources.lua`,
   `RaidRanks.lua`, `Tracks.lua`, and `sources_spec.lua` together.
```

- [ ] **Step 2: Commit**

```bash
git add docs/SEASON_CHECKLIST.md
git commit -m "docs: add season changeover checklist"
```

---

### Task 7: Manual live checkpoint — run the script against real Season 2 data

**Files:** none (verification only).

- [ ] **Step 1: MANUAL CHECKPOINT — run generate_sources.py for real**

This step cannot be run by an agent — it requires real Battle.net
Developer API credentials, which must never be typed into this
conversation or run through a shared/logged shell (to avoid the secret
ever appearing in a transcript). Whoever executes this task should run it
themselves, in their own terminal, and report the result back:

1. In your own terminal (not through the assistant), `cd` to the repo
   root and run (PowerShell):
   ```
   $env:BLIZZARD_CLIENT_ID="<your id>"; $env:BLIZZARD_CLIENT_SECRET="<your secret>"; python tools/data-prep/generate_sources.py
   ```
2. Confirm the script completes without an uncaught exception.
3. Read the structural warnings (if any) printed above the diff — none
   are expected against current, already-correct Season 2 data.
4. Read the diff itself. Per this design's acceptance check, it should be
   empty or explainable (e.g. minor item-name wording differences that
   don't change any item ID) — since this run targets the same Season 2
   content already committed in `Where2Go/Core/Sources.lua`. A diff that
   changes item IDs, adds/removes encounters, or reorders instances
   unexpectedly means something in the generation logic is wrong and
   should be reported back rather than blindly accepted.
5. Do not copy the staged output over the real `Sources.lua` as part of
   this checkpoint — this run is validating the tool, not performing an
   actual season change. Leave `Sources.lua` untouched.

This satisfies `docs/superpowers/specs/2026-09-02-phase5-data-ingestion-design.md`'s
acceptance check.

---

## Done

This sub-project is complete when all six code/doc tasks' commits exist
and Task 7's manual checkpoint has confirmed a real run against current
Season 2 data produces an empty/explainable diff. Phase 5's remaining two
sub-projects (automated syntax/contract checks; packaging and release
readiness) each start a new brainstorm/design/plan cycle built on this
foundation.
