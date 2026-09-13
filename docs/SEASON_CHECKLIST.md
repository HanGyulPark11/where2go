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

4. **Regenerate localized content names.** Run the content-locale generator
   against the same `SEASON_INSTANCES` used for `Sources.lua`:
   ```
   python tools/data-prep/generate_content_locale.py
   ```
   Review `tools/data-prep/scratch/ContentNames.lua.new`, then copy only the
   generated `Where2GoLocale.CONTENT_NAMES` table into
   `Where2Go/Core/Locale.lua`. The generator matches by API instance and
   encounter IDs, so it avoids hand-translating raid and boss names from the
   English canonical keys.

5. **Refresh `Where2Go/Core/VoidcacheIds.lua` (optional — currently
   unused by any shipped feature).** No API endpoint exists for this
   data (see
   `docs/superpowers/specs/2026-09-03-phase7-spec-eligibility-design.md`'s
   Data Sourcing section) — it's a manual per-entry Wowhead lookup. As of
   Phase 8b, this file is no longer a dependency of step 8's
   spec-eligibility regeneration (that now drives the Encounter Journal
   directly off `Sources.lua`'s own `instanceId`/`bossId` fields). It's
   kept only for a separate, not-yet-built feature (backfilling a
   player's own pre-addon-install Voidcore obtained-item history — see
   `docs/superpowers/specs/2026-09-05-phase8b-ej-loot-filter-genspec-design.md`'s
   "Why VoidcacheIds.lua survives" section). **Skip this step during a
   normal season changeover** unless that feature has since been built —
   in which case refresh it the same way as before: for every dungeon in
   the just-updated `Sources.lua` `DUNGEONS` list and every raid boss in
   `RAIDS`, search Wowhead for `"Nebulous Voidcache: <exact dungeon or
   boss name>"` and note the item ID from the result page's URL
   (`wowhead.com/item=<id>`). Update
   `Where2GoVoidcacheIds.DUNGEONS`/`RAID_BOSSES` with the new
   `[instanceId or bossId] = itemId` entries, replacing stale ones for
   content that rotated out.

6. **Re-measure `Where2Go/Core/RaidRanks.lua` in-client.** This file has
   no API equivalent. Determine each boss's relative item-level rank and any
   above-cap final-boss track. Update `RAID_BOSS_RANK`,
   `MYTH_FINAL_BOSS_IDS`, `MYTH_FINAL_ILVL`, `MYTH_FINAL_RANK`, and
   `MYTH_FINAL_BONUS_ID`; re-confirm the Mythic+ key+10-floor assumption.

7. **Check `Where2Go/Core/Tracks.lua`.** Confirm each upgrade track's
   `bonusIdStart` and `ilvls` array, since the next scan removes every bonus
   ID these tables define.

8. **Update `Where2GoConstants.SEASON_LABEL`.** Set the new season label
   before generating either SavedVariables export, so both converters reject
   stale prior-season output.

9. **Regenerate `Where2Go/Core/SpecEligibilityData.lua`.** Run
   `/where2go genspec reset` unconditionally, then `/where2go genspec` once
   on any character. The reset discards any old export, so updating the season
   label first is safe. A mid-season `Sources.lua` edit also requires this
   step. Log out, review `Where2GoDB.specEligibilityExport.bySpec` for
   plausible non-empty per-spec coverage, then hand-merge it into
   `Where2Go/Core/SpecEligibilityData.lua`.

10. **Regenerate `Where2Go/Core/ItemLinkBonuses.lua`.** First run
   `/w2g genlinks reset`, then `/w2g genlinks` on any character out of combat.
   The scan prewarms tracked item IDs, then sets EJ difficulty and selects the
   instance once per source before selecting each tracked encounter at Mythic
   Keystone (dungeons, difficulty 8) or Mythic raid (raids, difficulty 16),
   clearing the loot filter and reading full Encounter Journal item links.
   Wait for zero conflicts, unresolved-full-link diagnostics, and missing-item
   diagnostics, then log out fully. From the repository root, run:
   ```
   python tools/data-prep/convert_item_link_bonuses.py "C:\path\to\WTF\Account\<account>\SavedVariables\Where2Go.lua"
   ```
   The converter validates the season and schema, rejects conflicts,
   unresolved full links, and incomplete/suspicious coverage, and writes only
   `tools/data-prep/scratch/ItemLinkBonuses.lua.new`. Review the printed diff
   and staged file before manually copying it into
   `Where2Go/Core/ItemLinkBonuses.lua`. It normalizes character-specific fields
   while preserving item context, residual-bonus order, modifiers, and the
   remaining full-link tail for each tracked item; differing normalized links
   for one item are a conflict. Do not apply a
   diagnostic export; fix the source/EJ issue and rerun the scan.

11. **Re-run the item-stats data-prep script.** Once `Sources.lua` is
   updated, its item IDs may have changed, so `Where2Go/Core/ItemStats.lua`
   needs regenerating too. See `tools/data-prep/README.md` for credential
   setup (same as step 2). From the repo root:
   ```
   $env:BLIZZARD_CLIENT_ID="<id>"; $env:BLIZZARD_CLIENT_SECRET="<secret>"; python tools/data-prep/generate_item_stats.py
   ```
   Review the printed diff. If it looks correct, copy
   `tools/data-prep/scratch/ItemStats.lua.new`'s content into
   `Where2Go/Core/ItemStats.lua`.

12. **Update `tests/sources_spec.lua`'s season-specific assertions.** The
    check near the bottom of the file (currently asserting `RAIDS[2]` is
    "The Venomous Abyss" with exactly 8 encounters) is Season-2-specific.
    Replace it with an equivalent spot-check for the new season's actual
    raid content, or remove it if no longer meaningful.

13. **Run the full test suite and commit.**
    ```
    "C:\ProgramData\chocolatey\lib\lua51\tools\lua5.1.exe" tests/run_tests.lua
    ```
    Confirm all specs pass before committing the updated `Sources.lua`,
   `ItemStats.lua`, `ItemLinkBonuses.lua`, `RaidRanks.lua`, `Tracks.lua`,
   `Constants.lua`, `Where2Go/Core/Locale.lua`,
   `Where2Go/Core/SpecEligibilityData.lua`, `sources_spec.lua`, and (only
    if step 5 was actually performed this season) `Where2Go/Core/VoidcacheIds.lua`
    together.
