local specs = {
    "tests/docs_spec.lua",
    "tests/constants_spec.lua",
    "tests/locale_spec.lua",
    "tests/toc_spec.lua",
    "tests/tracks_spec.lua",
    "tests/compare_spec.lua",
    "tests/equipment_spec.lua",
    "tests/sources_spec.lua",
    "tests/voidcacheids_spec.lua",
    "tests/specEligibilityData_spec.lua",
    "tests/itemstats_spec.lua",
    "tests/itemlinkbonuses_spec.lua",
    "tests/itemLinkBonusScan_spec.lua",
    "tests/raidranks_spec.lua",
    "tests/ranking_spec.lua",
    "tests/voidcorehistory_spec.lua",
    "tests/voidcoredrop_spec.lua",
    "tests/specEligibilityScan_spec.lua",
    "tests/itembrowser_spec.lua",
    "tests/selection_spec.lua",
    "tests/preferences_spec.lua",
    "tests/panel_spec.lua",
    "tests/browserpanel_spec.lua",
}

local failureCount = 0

for _, path in ipairs(specs) do
    local ok, err = pcall(dofile, path)
    if ok then
        print(string.format("[PASS] %s", path))
    else
        failureCount = failureCount + 1
        print(string.format("[FAIL] %s: %s", path, tostring(err)))
    end
end

print(string.format("\n%d spec file(s), %d failure(s)", #specs, failureCount))

if failureCount > 0 then
    os.exit(1)
end
