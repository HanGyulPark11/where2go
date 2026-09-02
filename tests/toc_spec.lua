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

-- Order assertion: Core/Constants.lua must load before Fixtures.lua, Init.lua,
-- and Panel.lua, all of which reference Where2GoConstants.
assert(referencedFiles[1] == "Core\\Constants.lua",
    string.format("expected Core\\Constants.lua to be the first TOC entry (load order), got %s",
        tostring(referencedFiles[1])))

-- Completeness sweep: every .lua file actually present under Where2Go/Core
-- and Where2Go/UI must be referenced somewhere in the TOC. This catches the
-- case where a file was added on disk but never wired into the TOC, which
-- would otherwise silently never load in-client while this suite stays green.
local function normalize(path)
    return path:gsub("/", "\\")
end

local normalizedReferenced = {}
for _, relPath in ipairs(referencedFiles) do
    normalizedReferenced[normalize(relPath)] = true
end

local function listLuaFiles(subdir)
    local files = {}
    local cmd = string.format('dir /b "Where2Go\\%s\\*.lua"', subdir)
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            local trimmedLine = line:match("^%s*(.-)%s*$")
            if trimmedLine ~= "" then
                table.insert(files, subdir .. "\\" .. trimmedLine)
            end
        end
        handle:close()
    end
    return files
end

local filesystemFiles = {}
for _, f in ipairs(listLuaFiles("Core")) do
    table.insert(filesystemFiles, f)
end
for _, f in ipairs(listLuaFiles("UI")) do
    table.insert(filesystemFiles, f)
end

assert(#filesystemFiles > 0, "expected to find at least one .lua file under Where2Go/Core or Where2Go/UI")

for _, fsRelPath in ipairs(filesystemFiles) do
    local key = normalize(fsRelPath)
    assert(normalizedReferenced[key],
        string.format("found %s on disk but it is not referenced in %s", fsRelPath, tocPath))
end

print("toc_spec: OK, " .. #referencedFiles .. " file(s) verified, " ..
    #filesystemFiles .. " filesystem file(s) confirmed present in TOC, load order OK")
