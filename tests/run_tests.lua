local specs = {
    "tests/constants_spec.lua",
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
