# Season Changeover Checklist

Follow these steps in order whenever a new WoW season starts and
Where2Go's data needs updating. Do not skip ahead — later steps assume
earlier ones are done.

1. **Look up this season's content.** Find the new Mythic+ dungeon
   rotation and raid instance IDs (e.g. via wowhead or the official patch
   notes). Update the `SEASON_INSTANCES` constant at the top of
   `tools/data-prep/generate_sources.py` with the new instance IDs.

2. **Run the data-prep script.** See `tools/data-prep/README.md` for
   credential setup. From the repo root (PowerShell):
   ```
   $env:BLIZZARD_CLIENT_ID="<id>"; $env:BLIZZARD_CLIENT_SECRET="<secret>"; python tools/data-prep/generate_sources.py
   ```

3. **Review the diff.** The script prints a diff between the current
   `Where2Go/Core/Sources.lua` and the freshly generated data. Read it
   carefully — look especially at the structural warnings the script
   prints above the diff (empty item lists, duplicate boss IDs). If it
   looks correct, copy `tools/data-prep/scratch/Sources.lua.new`'s
   content into `Where2Go/Core/Sources.lua`. Also update the generator's
   `SEASON_LABEL` constant (near the top of `generate_sources.py`) to
   match this season, and review whether any data-quality notes in
   `Sources.lua`'s hand-written header (e.g. the note about specific
   encounters with duplicate item IDs) still apply or need updating —
   the generator's own header does not carry forward every note from the
   committed file automatically.

4. **Re-measure `Where2Go/Core/RaidRanks.lua` in-client.** This file has
   no API equivalent. For the new raid, determine each boss's relative
   item-level rank (1-4) and whether any boss drops a special
   above-normal-cap track (like Season 2's Myth-9/6 final bosses), the
   same way `RaidRanks.lua`'s own comments describe doing it for Season 2
   (e.g. checking a known dropped item's bonus ID against its item level
   via `/where2go scanbonus` or an equivalent in-client check). Update
   `RAID_BOSS_RANK`, `MYTH_FINAL_BOSS_IDS`, `MYTH_FINAL_ILVL`, and
   `MYTH_FINAL_RANK` by hand to match. Also re-confirm the Mythic+
   key+10-floor assumption (`MYTHIC_PLUS_TRACK_KEY` and
   `MYTHIC_PLUS_TRACK_RANK`, documented in that file as an empirical
   in-client measurement) still holds, and update those two by hand if
   not.

5. **Check `Where2Go/Core/Tracks.lua`.** Confirm whether the upgrade-track
   bonus ID ranges (Veteran/Champion/Hero/Myth) changed this season —
   Blizzard sometimes shifts these between seasons. Also check each
   track's `ilvls = { ... }` array (the per-rank item levels), which
   changes essentially every season. Update by hand if so.

6. **Update `Where2GoConstants.SEASON_LABEL`.** In
   `Where2Go/Core/Constants.lua`, update the `SEASON_LABEL` string (e.g.
   `"Midnight Season 2"`) to name the new season. This is a simple
   hand-edit, like the `RaidRanks.lua`/`Tracks.lua` steps above — there is
   no API for it.

7. **Update `tests/sources_spec.lua`'s season-specific assertions.** The
   check near the bottom of the file (currently asserting `RAIDS[2]` is
   "The Venomous Abyss" with exactly 8 encounters) is Season-2-specific.
   Replace it with an equivalent spot-check for the new season's actual
   raid content, or remove it if no longer meaningful.

8. **Run the full test suite and commit.**
   ```
   "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
   ```
   Confirm all specs pass before committing the updated `Sources.lua`,
   `RaidRanks.lua`, `Tracks.lua`, `Constants.lua`, and `sources_spec.lua`
   together.
