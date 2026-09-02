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
