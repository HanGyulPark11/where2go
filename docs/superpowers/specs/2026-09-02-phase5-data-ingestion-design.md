# Phase 5, Sub-project 1: Seasonal Data Ingestion and Validation — Design

Status: approved
Scope: `docs/DEVELOPMENT_PLAN.md` Phase 5's first bullet only ("Define
seasonal data ingestion and validation"). Phase 5's other two bullets
("automated syntax and contract checks," "packaging/smoke test/release
checklist") are separate sub-projects with their own design cycles.

## Decisions carried into this design

- **Credentials**: reuses the developer's existing Battle.net Developer API
  client ID/secret (already held from the pre-restart implementation).
  Never hardcoded — read from `BLIZZARD_CLIENT_ID`/`BLIZZARD_CLIENT_SECRET`
  environment variables, same convention as
  `codex/pre-restart-backup`'s `tools/data-prep/fetch_token.py`.
- **Runtime**: Python (already installed at `C:\Python313\python.exe`, no
  new tooling install required). Not Node.js/JS — this keeps the fetch
  logic in the same language the pre-restart branch already proved working
  against the real Battle.net OAuth + Journal API flow.
- **Automation level**: full regeneration of `Sources.lua`'s data plus an
  automatic diff against the committed file, not a lighter validate-only
  tool. The developer's manual step is limited to (a) supplying this
  season's dungeon/raid instance IDs (the API has no "what's current
  season" endpoint) and (b) reviewing the diff before replacing the file.
- **Never auto-overwrite**: the script never writes directly to
  `Where2Go/Core/Sources.lua`. It writes a staged file and prints a diff;
  a human copies it over deliberately. Real player-facing game data
  deserves a manual review gate, not blind trust in script output.
- **Scope of automation**: only `Sources.lua` (dungeon/raid/encounter item
  pools) is fetched from the Battle.net Journal API, because that's the
  only one of the three season-dependent data files with an API this
  addon can query. `Tracks.lua` (upgrade-track bonus ID ranges) and
  `RaidRanks.lua` (per-boss ilvl rank, empirically measured in-client via
  commands like `/where2go scanbonus`) have no equivalent public API and
  stay manual — this design instead documents the exact manual procedure
  for updating them each season, in one checklist alongside the automated
  step, so a future season-changeover is a single documented walk rather
  than three separately-remembered procedures.

## Reference material

- `codex/pre-restart-backup` branch, `tools/data-prep/fetch_token.py` and
  `fetch_full_loot_tables.py`: the proven OAuth client-credentials flow and
  Journal API traversal pattern (instance → encounters → item lists),
  reused in spirit (re-derived into one script, not copied verbatim, since
  this design outputs a different Lua schema than the old branch's
  per-spec files).
- `Where2Go/Core/Sources.lua`: the exact target schema
  (`Where2GoSources.DUNGEONS`/`.RAIDS`, each
  `{instanceId, name, encounters = {{bossId, name, itemIds}}}`) the
  generated output must match byte-for-byte in structure.
- `Where2Go/Core/RaidRanks.lua`: documents in its own comments how Season
  2's boss ranks and the Myth-9/6 final-boss track were originally
  measured in-client — the season checklist below points back to this
  file's comment style as the pattern to repeat.
- `tests/sources_spec.lua`: the existing structural test this design does
  not replace; line 35-37's `RAIDS[2]` / "exactly 8 encounters" assertion
  is Season-2-specific and is called out explicitly in the checklist as a
  required per-season edit.

## Architecture

```
tools/data-prep/
├── generate_sources.py    NEW: single script — season instance-ID config,
│                           OAuth token fetch, Journal API traversal, Lua
│                           generation, diff-against-current output
├── scratch/                NEW, gitignored: token cache, raw API JSON,
│                           the generated Sources.lua.new staging file
└── README.md               NEW: credential setup + how to run each season

docs/
└── SEASON_CHECKLIST.md     NEW: the full per-season procedure, covering
                            both the automated step (this sub-project) and
                            the manual Tracks.lua/RaidRanks.lua/
                            sources_spec.lua updates

.gitignore                  MODIFY: add tools/data-prep/scratch/
```

## Components

- **`tools/data-prep/generate_sources.py`** (new): a single script, run
  manually once per season change.
  - A `SEASON_INSTANCES` constant near the top of the file:
    `{ dungeons = {instanceId, ...}, raids = {instanceId, ...} }`. Hand-
    edited each season before running — the Battle.net API has no
    "current season" endpoint, so the developer must supply this list
    (same limitation the pre-restart branch's own script had, per its
    "Confirmed Season 2 content, cross-checked against wiki" comment).
  - `get_token()`: OAuth client-credentials request to
    `https://oauth.battle.net/token` using the two environment variables;
    caches the token to `scratch/token.json` for the run.
  - `fetch_instance(instance_id)`: `GET /data/wow/journal-instance/{id}`,
    then for each returned encounter, `GET
    /data/wow/journal-encounter/{id}` to collect `{bossId, name,
    itemIds}`. Raw responses are also written to `scratch/` for
    troubleshooting.
  - `render_lua(dungeons, raids)`: produces a string matching
    `Where2Go/Core/Sources.lua`'s exact table shape (same field names,
    same nesting, same header-comment convention), written to
    `scratch/Sources.lua.new`.
  - `diff_against_current()`: reads the committed
    `Where2Go/Core/Sources.lua`, computes a unified diff (Python's
    `difflib.unified_diff`) against `scratch/Sources.lua.new`, and prints
    it directly to the terminal — no separate diff step or tool needed.
  - Structural sanity checks, printed as warnings (not fatal, since the
    developer reviews the diff regardless): an encounter with an empty
    `itemIds` list, or two encounters in the same instance sharing a
    `bossId`. These catch the kind of mistake easy to miss while skimming
    a large diff.
  - Any HTTP error (bad credentials, wrong instance ID, etc.) propagates
    as an uncaught exception with Python's normal traceback, which
    includes the failing URL — no retry logic, no swallowed errors. This
    is an interactively-run developer tool, not an unattended job.

- **`docs/SEASON_CHECKLIST.md`** (new): an ordered, step-by-step procedure
  for a full season changeover, covering all three season-dependent data
  files so the person doing it never has to reconstruct the process from
  memory or from scattered code comments:
  1. Look up the new season's Mythic+ dungeon rotation and raid instance
     IDs (e.g. from wowhead/wiki), update `SEASON_INSTANCES` in
     `generate_sources.py`.
  2. Set `BLIZZARD_CLIENT_ID`/`BLIZZARD_CLIENT_SECRET`, run
     `python tools/data-prep/generate_sources.py`.
  3. Review the printed diff. If it looks right, copy
     `tools/data-prep/scratch/Sources.lua.new`'s content into
     `Where2Go/Core/Sources.lua`.
  4. Re-measure `RaidRanks.lua`'s boss-ID-to-rank map and any
     final-boss special track in-client (pointing to the method already
     documented in that file's own comments — e.g. checking a known
     boss's dropped item's bonus ID against its ilvl) and update the file
     by hand.
  5. Check whether `Tracks.lua`'s upgrade-track bonus ID ranges changed
     this season (Blizzard sometimes shifts these) and update by hand if
     so.
  6. Update `tests/sources_spec.lua`'s season-specific assertions (the
     `RAIDS[2]` / "exactly 8 encounters" check) to match the new season's
     actual content, or remove them if no longer applicable.
  7. Run the full test suite
     (`"C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe"
     tests/run_tests.lua`) and confirm all specs pass before committing.

## Data flow

1. Developer edits `SEASON_INSTANCES` in `generate_sources.py` with the
   new season's instance IDs.
2. Developer runs the script with Battle.net credentials in the
   environment.
3. Script authenticates, walks the Journal API for every listed instance,
   collects encounter/item data, and renders it into the same Lua shape
   `Sources.lua` already uses.
4. Script diffs the newly generated data against the committed file and
   prints the diff for review — nothing is written into
   `Where2Go/Core/Sources.lua` automatically.
5. Developer reviews the diff, copies the new content over the real file
   if it looks correct, then proceeds through `SEASON_CHECKLIST.md`'s
   remaining manual steps (`RaidRanks.lua`, `Tracks.lua`,
   `sources_spec.lua`) before running tests and committing.

## Testing

- No new automated tests are added for `generate_sources.py` itself: it's
  a low-frequency (roughly once-per-season), interactively-run developer
  tool whose correctness is checked by the diff-review step (a human
  reading real output against real committed data), not by a mocked unit
  test suite. Building HTTP-mocking test infrastructure for a script run
  a few times a year is not worth the maintenance cost (YAGNI).
- The existing `tests/sources_spec.lua` continues to be the structural
  check on the final `Sources.lua` output, run as the last step of
  `SEASON_CHECKLIST.md` before committing. This design does not modify
  that test's logic, only flags (in the checklist) that its two
  season-specific assertions need a per-season edit.

## Error handling

- Missing `BLIZZARD_CLIENT_ID`/`BLIZZARD_CLIENT_SECRET`: `os.environ[...]`
  raises an uncaught `KeyError` naming the missing variable before any
  network request is made. Invalid (wrong but present) credentials instead
  reach Battle.net and fail the OAuth request with an HTTP error. Either
  way the script lets the exception propagate rather than catching and
  re-wrapping it — the underlying error message is already clear enough.
- Wrong/decommissioned instance ID in `SEASON_INSTANCES`: the Journal API
  returns 404; same uncaught-exception behavior, with the failing
  instance ID visible in the URL inside the traceback.
- Structural anomalies in successfully-fetched data (empty `itemIds`,
  duplicate `bossId`) are non-fatal warnings printed alongside the diff,
  not exceptions — they're exactly the kind of thing the human review step
  exists to catch, and don't need to halt the script.

## Acceptance check

- Running `generate_sources.py` against the current (Season 2) instance
  IDs reproduces `Sources.lua`'s existing data closely enough that the
  printed diff is empty or explainable (e.g. minor wording differences in
  item names that don't affect item IDs) — this proves the generation
  logic is correct by validating it against already-known-good data
  before ever using it for a real season change.
- `docs/SEASON_CHECKLIST.md` exists and covers all three season-dependent
  files (`Sources.lua`, `Tracks.lua`, `RaidRanks.lua`) plus the
  `sources_spec.lua` test-assertion update, so a future season changeover
  has one document to follow rather than three.

## Out of scope for this sub-project

- Automated syntax/contract checking tooling (Phase 5's second bullet) —
  separate design.
- Packaging, clean-install smoke test, release checklist (Phase 5's third
  bullet) — separate design.
- Any API-based automation for `Tracks.lua` or `RaidRanks.lua` — no public
  API exists for either; they remain manual, in-client-measured
  procedures, only newly documented here rather than newly automated.
- Actually running a season changeover for a real new season — this
  design only builds and validates the tooling/checklist against the
  current, already-known Season 2 data.
