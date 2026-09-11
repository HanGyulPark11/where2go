-- Curated non-track bonuses for item effect/context variants.
-- Live-client QA confirms whether each current variant remains valid.
-- ItemRow appends the requested calculated upgrade-track bonus after these.
-- luacheck: globals Where2GoItemLinkBonuses

Where2GoItemLinkBonuses = {
    EXTRA_BONUSES = {
        [268265] = { 13335, 13668, 13987 },
        [268253] = { 6652, 13662, 13334, 13696 },
        [271876] = { 13335, 13846 },
    },
}
