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

## `generate_content_locale.py`

`generate_content_locale.py` fetches the same season instances as
`generate_sources.py` from the Battle.net Game Data API Journal endpoints in
both `en_US` and `ko_KR`. It matches instances and encounters by API ID, then
stages a replacement `Where2GoLocale.CONTENT_NAMES` table so English
`Sources.lua` names remain canonical keys while Korean clients can show
official localized dungeon, raid, and boss names.

Run it after `SEASON_INSTANCES` is current:

```
python tools/data-prep/generate_content_locale.py
```

Review `tools/data-prep/scratch/ContentNames.lua.new`. If it looks correct,
copy only the generated `Where2GoLocale.CONTENT_NAMES` table into
`Where2Go/Core/Locale.lua`, leaving the rest of the file intact.

For generator development, run:

```
python tools/data-prep/test_generate_content_locale.py
```

## `convert_item_link_bonuses.py`

`convert_item_link_bonuses.py` turns the reviewed account-wide export produced
by `/w2g genlinks` into committed full item-link templates. It uses only
the Python standard library, reads the SavedVariables file supplied as its
argument, and writes only `scratch/ItemLinkBonuses.lua.new`; it never edits
`Where2Go/Core/ItemLinkBonuses.lua`.

First run `/w2g genlinks reset`, then `/w2g genlinks` in a live client. The
scan prewarms its tracked item IDs, then selects EJ difficulty and the instance
once per source before its encounter loop. Let it finish without conflicts,
unresolved-full-link diagnostics, or missing-item diagnostics and log out fully
so WoW flushes SavedVariables. From the repository root, run:

```
python tools/data-prep/convert_item_link_bonuses.py "C:\path\to\WTF\Account\<account>\SavedVariables\Where2Go.lua"
```

The converter rejects a stale season or unsupported schema, any conflict,
unresolved full link, missing or incomplete tracked-item coverage, remaining
upgrade-track IDs, duplicate bonus IDs, and conflicting templates for one item.
It zeros character-specific link fields while preserving each Encounter
Journal item context, residual-bonus order, modifier list, and trailing fields.
At runtime `ItemRow` inserts the requested upgrade-track bonus into that
template. Review the printed diff and
`tools/data-prep/scratch/ItemLinkBonuses.lua.new`; only then manually copy its
contents into `Where2Go/Core/ItemLinkBonuses.lua`, run the Lua tests and lint,
and complete the live-client checklist.

For converter development, run its standard-library test suite from the
repository root:

```
python tools/data-prep/test_convert_item_link_bonuses.py
```
