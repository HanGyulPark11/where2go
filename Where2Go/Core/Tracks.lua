-- Season 2 (Midnight patch 12.1) upgrade-track bonus IDs and per-rank item
-- levels. Ported from the pre-restart implementation
-- (codex/pre-restart-backup branch, Core/Constants.lua's UPGRADE_TRACKS) as
-- empirically measured game fact -- confirmed in-client via
-- /where2go scanbonus against real items, same Interface: 120100, same-day
-- commit. See docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md
-- for full provenance.
--
-- Each track is exactly 6 consecutive bonus IDs (rank 1/6 through 6/6). A
-- track's rank 5-6 item level deliberately overlaps the next track's rank
-- 1-2 (smooth catch-up by design, not a measurement error) -- see
-- Core/Compare.lua for why track order is compared before item level.

Where2GoTracks = {}

Where2GoTracks.UPGRADE_TRACKS = {
    VETERAN = { order = 1, label = "Veteran", bonusIdStart = 12825, ilvls = { 279, 282, 285, 289, 292, 295 } },
    CHAMPION = { order = 2, label = "Champion", bonusIdStart = 12833, ilvls = { 292, 295, 298, 302, 305, 308 } },
    HERO = { order = 3, label = "Hero", bonusIdStart = 12841, ilvls = { 305, 308, 311, 315, 318, 321 } },
    MYTH = { order = 4, label = "Myth", bonusIdStart = 12849, ilvls = { 318, 321, 324, 328, 331, 334 } },
}
