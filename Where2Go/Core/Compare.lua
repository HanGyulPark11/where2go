-- Pure comparison logic -- no WoW API references, testable standalone. See
-- docs/superpowers/specs/2026-09-02-phase2-preferred-items-design.md for
-- the "track beats item level" rationale.

Where2GoCompare = {}

function Where2GoCompare.IsBetterCandidate(candidate, equipped)
    if candidate.track and equipped.track and candidate.track.order ~= equipped.track.order then
        return candidate.track.order > equipped.track.order
    end
    return (candidate.ilvl or 0) > (equipped.ilvl or 0)
end
