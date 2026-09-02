-- Boss rank (1-4) within Mythic-difficulty The Venomous Abyss, ported from
-- codex/pre-restart-backup's Core/Constants.lua RAID_BOSS_RANK --
-- independently verified against the real boss IDs in Core/Sources.lua
-- (exact match). Bosses not listed default to rank 1 (single-boss raids
-- like The Tidebound Grotto). See
-- docs/superpowers/specs/2026-09-02-phase3-direct-drop-design.md.

Where2GoRaidRanks = {}

Where2GoRaidRanks.RAID_BOSS_RANK = {
    [2888] = 1, -- Nek'zali the Soulcoiler
    [2874] = 2, -- Entombed Sentinels
    [2894] = 2, -- The Lost Explorers
    [2882] = 3, -- Vashnik the Malignant
    [2871] = 3, -- Sszorak
    [2887] = 3, -- The Twin Fangs
    [2883] = 4, -- The Coiled Altar
    [2895] = 4, -- Ula'tek
}

-- Mythic+ is fixed at the key+10 floor, confirmed in-client to drop Hero
-- rank 3/6 gear -- see the design spec's provenance note. This replaces
-- the source branch's own per-key-level ilvl table, which was marked
-- "approximate, refine when better data exists" and is deliberately not
-- ported.
Where2GoRaidRanks.MYTHIC_PLUS_TRACK_KEY = "HERO"
Where2GoRaidRanks.MYTHIC_PLUS_TRACK_RANK = 3

-- Returns (ilvl, trackLabel, rank) for a Venomous-Abyss-style raid boss at
-- Mythic difficulty. Unlisted boss IDs default to rank 1.
function Where2GoRaidRanks.GetRaidIlvl(bossId)
    local rank = Where2GoRaidRanks.RAID_BOSS_RANK[bossId] or 1
    local track = Where2GoTracks.UPGRADE_TRACKS.MYTH
    return track.ilvls[rank], track.label, rank
end

-- Returns (ilvl, trackLabel, rank) for the fixed Mythic+ key+10 assumption.
function Where2GoRaidRanks.GetMythicPlusIlvl()
    local track = Where2GoTracks.UPGRADE_TRACKS[Where2GoRaidRanks.MYTHIC_PLUS_TRACK_KEY]
    local rank = Where2GoRaidRanks.MYTHIC_PLUS_TRACK_RANK
    return track.ilvls[rank], track.label, rank
end
