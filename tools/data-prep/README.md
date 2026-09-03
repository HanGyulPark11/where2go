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
$env:BLIZZARD_CLIENT_ID="<your id>"; $env:BLIZZARD_CLIENT_SECRET="<your secret>"; python tools/data-prep/generate_sources.py
```

Review the printed diff. If it looks correct, copy
`tools/data-prep/scratch/Sources.lua.new`'s content into
`Where2Go/Core/Sources.lua`.

## `generate_item_stats.py`

`generate_item_stats.py` fetches per-item stat metadata (primary and
secondary stat types) for every item that `Sources.lua` references, from
the Battle.net Game Data API. Like `generate_sources.py`, it never writes
`Where2Go/Core/ItemStats.lua` directly — it stages its output at
`scratch/ItemStats.lua.new` and prints a diff for you to review.

It depends on `Sources.lua` already being up to date, since it reads item
IDs out of that file. Run `generate_sources.py` first if you're doing a
season changeover. Using the same credentials as the "One-time setup"
section above, from the repo root:

```
python tools/data-prep/generate_item_stats.py
```

Review the printed diff. If it looks correct, copy
`tools/data-prep/scratch/ItemStats.lua.new`'s content into
`Where2Go/Core/ItemStats.lua`.

See `docs/SEASON_CHECKLIST.md` for the full season-changeover procedure,
covering both scripts above plus the manual steps for `Tracks.lua` and
`RaidRanks.lua` that neither script covers.
