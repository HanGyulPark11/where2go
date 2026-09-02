dofile("Where2Go/Core/Tracks.lua")

local expectedOrder = { VETERAN = 1, CHAMPION = 2, HERO = 3, MYTH = 4 }

local seenOrders = {}
for key, expectedOrderValue in pairs(expectedOrder) do
    local track = Where2GoTracks.UPGRADE_TRACKS[key]
    assert(type(track) == "table", key .. " should exist in UPGRADE_TRACKS")
    assert(track.order == expectedOrderValue, key .. ".order should be " .. expectedOrderValue)
    assert(type(track.label) == "string" and #track.label > 0, key .. ".label should be a non-empty string")
    assert(type(track.bonusIdStart) == "number" and track.bonusIdStart > 0 and track.bonusIdStart % 1 == 0,
        key .. ".bonusIdStart should be a positive integer")
    assert(type(track.ilvls) == "table" and #track.ilvls == 6, key .. ".ilvls should have exactly 6 entries")
    for i = 2, 6 do
        assert(track.ilvls[i] > track.ilvls[i - 1], key .. ".ilvls should be strictly increasing")
    end
    assert(not seenOrders[track.order], "duplicate order value: " .. track.order)
    seenOrders[track.order] = true
end

print("tracks_spec: OK, 4 track(s) verified")
