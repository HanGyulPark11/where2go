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

-- The final two Venomous Abyss bosses (Mythic difficulty only) drop a
-- special Myth 9/6 track above the normal 6-rank crest cap. Ported from
-- codex/pre-restart-backup's MYTHIC_FINAL_BOSS_IDS/MYTH_FINAL_BONUS_ID --
-- confirmed via /where2go scanbonus on Ula'tek's Janthrazet the Soul Fang
-- (item 271092): bonus ID 13848 -> ilvl 344.
Where2GoRaidRanks.MYTH_FINAL_BOSS_IDS = { [2883] = true, [2895] = true }
Where2GoRaidRanks.MYTH_FINAL_ILVL = 344
Where2GoRaidRanks.MYTH_FINAL_RANK = 9
Where2GoRaidRanks.MYTH_FINAL_BONUS_ID = 13848

-- Returns (ilvl, trackKey, rank, bonusId) for a Venomous-Abyss-style raid
-- boss at Mythic difficulty. The final two bosses (see MYTH_FINAL_BOSS_IDS
-- above) are special-cased to the Myth 9/6 ilvl 344 track above the normal
-- 1-4 rank cap. Unlisted boss IDs default to rank 1. trackKey is the raw
-- Where2GoTracks.UPGRADE_TRACKS key (e.g. "MYTH") rather than a display
-- string -- callers localize via Where2GoLocale.TrackLabel(trackKey) at
-- the UI layer, keeping this Core module locale-agnostic. bonusId is the
-- real upgrade-track bonus ID for this ilvl/rank -- callers use it to
-- build a synthetic item link (see UI/ItemRow.lua) so GameTooltip shows
-- the item's real tracked level instead of its cached base-form level.
function Where2GoRaidRanks.GetRaidIlvl(bossId)
    if Where2GoRaidRanks.MYTH_FINAL_BOSS_IDS[bossId] then
        return Where2GoRaidRanks.MYTH_FINAL_ILVL, "MYTH", Where2GoRaidRanks.MYTH_FINAL_RANK, Where2GoRaidRanks.MYTH_FINAL_BONUS_ID
    end
    local rank = Where2GoRaidRanks.RAID_BOSS_RANK[bossId] or 1
    local track = Where2GoTracks.UPGRADE_TRACKS.MYTH
    return track.ilvls[rank], "MYTH", rank, track.bonusIdStart + rank - 1
end

-- Returns (ilvl, trackKey, rank, bonusId) for the fixed Mythic+ key+10
-- assumption. See GetRaidIlvl's comment above re: trackKey/bonusId.
function Where2GoRaidRanks.GetMythicPlusIlvl()
    local trackKey = Where2GoRaidRanks.MYTHIC_PLUS_TRACK_KEY
    local track = Where2GoTracks.UPGRADE_TRACKS[trackKey]
    local rank = Where2GoRaidRanks.MYTHIC_PLUS_TRACK_RANK
    return track.ilvls[rank], trackKey, rank, track.bonusIdStart + rank - 1
end
