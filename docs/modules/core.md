# Core contracts

`Constants.lua` defines addon/season constants, slot mappings, and database defaults. `Preferences.lua` owns separate `DROP` and `VOIDCORE` preferred lists, one-level undo, stored item-source bonuses, and keyed subscribers. Successful add, remove, clear, and undo operations notify subscribers so both windows can refresh.

`Ranking.lua` ranks each content target by preferred eligible items divided by its eligible pool. `DirectDrop.GetRankedResults()` and `VoidcoreDrop.GetRankedResults()` return separate ranked data sets; the UI renders them. `ItemBrowser.lua` supplies pure pool, filter, and sort logic, while `Selection.New()` owns temporary selection and resets it when results or filters change.

`SpecEligibilityScan.Start()` scans Encounter Journal data into `Where2GoDB.specEligibilityExport`; a developer then hand-merges that export into checked-in `SpecEligibilityData.lua`. The scan loop requires live-client QA. `Compare.lua`, `Equipment.lua`, and `Tracks.lua` compare candidates with equipped items using upgrade tracks and item level.
