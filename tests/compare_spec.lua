dofile("Where2Go/Core/Compare.lua")

local HERO = { order = 3 }
local MYTH = { order = 4 }

-- Same track, higher ilvl wins.
assert(Where2GoCompare.IsBetterCandidate(
    { track = HERO, ilvl = 315 },
    { track = HERO, ilvl = 308 }
) == true, "same track, higher ilvl should be better")

-- Same track, equal ilvl is not an upgrade.
assert(Where2GoCompare.IsBetterCandidate(
    { track = HERO, ilvl = 308 },
    { track = HERO, ilvl = 308 }
) == false, "same track, equal ilvl should not be better")

-- Higher track wins despite a lower nominal ilvl (tracks overlap by design --
-- see Core/Tracks.lua's header comment).
assert(Where2GoCompare.IsBetterCandidate(
    { track = MYTH, ilvl = 318 },  -- Myth rank 1/6
    { track = HERO, ilvl = 321 }   -- Hero rank 6/6, nominally higher ilvl
) == true, "higher track should win even with a lower nominal ilvl")

-- Candidate has no recognized track (e.g. crafted gear); equipped does --
-- falls back to a plain ilvl comparison.
assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 320 },
    { track = HERO, ilvl = 308 }
) == true, "no-track candidate with higher ilvl should win the ilvl fallback")

assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 300 },
    { track = HERO, ilvl = 308 }
) == false, "no-track candidate with lower ilvl should lose the ilvl fallback")

-- Neither side has a recognized track -- falls back to ilvl.
assert(Where2GoCompare.IsBetterCandidate(
    { track = nil, ilvl = 320 },
    { track = nil, ilvl = 310 }
) == true, "neither side has a track: higher ilvl should win")

print("compare_spec: OK")
