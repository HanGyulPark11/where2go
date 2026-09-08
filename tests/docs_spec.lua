local map = assert(io.open("docs/CODEMAP.md", "r"), "could not open docs/CODEMAP.md")
local classes = {}
for line in map:lines() do
    local path, class = line:match("^| (Where2Go/[%w_%-]+/[%w_%-]+%.lua) | ([a-z%-]+) |")
    if path then
        assert(class == "pure" or class == "data" or class == "wow-api", "invalid class for " .. path)
        assert(not classes[path], "duplicate map row for " .. path)
        classes[path] = class
    end
end
map:close()

local toc = assert(io.open("Where2Go/Where2Go.toc", "r"), "could not open TOC")
local expected = 0
for line in toc:lines() do
    local path = line:match("^([%w_%-]+\\[%w_%-]+%.lua)$")
    if path then
        expected = expected + 1
        local normalized = "Where2Go/" .. path:gsub("\\", "/")
        assert(classes[normalized], "CODEMAP lacks " .. normalized)
        classes[normalized] = nil
    end
end
toc:close()

local remaining = 0
for path in pairs(classes) do
    remaining = remaining + 1
    error("CODEMAP path is not in TOC: " .. path)
end
assert(expected > 0, "TOC contains no Lua modules")
assert(remaining == 0, "CODEMAP has extra paths")
print("docs_spec: OK, " .. expected .. " mapped module(s)")
