local tocPath = "Where2Go/Where2Go.toc"
local tocFile = assert(io.open(tocPath, "r"), "could not open " .. tocPath)

local referencedFiles = {}
for line in tocFile:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^##") then
        table.insert(referencedFiles, trimmed)
    end
end
tocFile:close()

assert(#referencedFiles > 0, "toc should list at least one Lua file to load")

for _, relPath in ipairs(referencedFiles) do
    local fsPath = "Where2Go/" .. relPath:gsub("\\", "/")
    local f = io.open(fsPath, "r")
    assert(f ~= nil, string.format("toc references %s but no file was found at %s", relPath, fsPath))
    if f then
        f:close()
    end
end

print("toc_spec: OK, " .. #referencedFiles .. " file(s) verified")
