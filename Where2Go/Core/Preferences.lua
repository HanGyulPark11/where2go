Where2GoPreferences = {}

local MODES = { "DROP", "VOIDCORE" }
local validModes = { DROP = true, VOIDCORE = true }
local subscribers = {}
local undoByMode = {}

local function AssertMode(mode)
    assert(validModes[mode], "invalid preference mode: " .. tostring(mode))
end

local function EnsureSavedVariables()
    if type(Where2GoCharDB) ~= "table" then
        Where2GoCharDB = {}
    end
    if type(Where2GoCharDB.preferredItems) ~= "table" then
        Where2GoCharDB.preferredItems = {}
    end
    if type(Where2GoCharDB.preferredItemSources) ~= "table" then
        Where2GoCharDB.preferredItemSources = {}
    end
    for _, mode in ipairs(MODES) do
        if type(Where2GoCharDB.preferredItems[mode]) ~= "table" then
            Where2GoCharDB.preferredItems[mode] = {}
        end
        if type(Where2GoCharDB.preferredItemSources[mode]) ~= "table" then
            Where2GoCharDB.preferredItemSources[mode] = {}
        end
    end
end

local function CopyMap(values)
    local copy = {}
    for key, value in pairs(values) do
        copy[key] = value
    end
    return copy
end

local function RestoreMap(target, saved)
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(saved) do
        target[key] = value
    end
end

local function CountPreferred(preferred)
    local count = 0
    for _, value in pairs(preferred) do
        if value == true then
            count = count + 1
        end
    end
    return count
end

local function SaveUndo(mode, preferred, sources, count)
    undoByMode[mode] = {
        preferred = CopyMap(preferred),
        sources = CopyMap(sources),
        count = count,
    }
end

local function ForEachItem(items, callback)
    if type(items) ~= "table" then
        return
    end
    if items.itemId ~= nil then
        callback(items.itemId, items.bonusId)
        return
    end
    for key, value in pairs(items) do
        if type(value) == "table" and value.itemId ~= nil then
            callback(value.itemId, value.bonusId)
        elseif type(key) == "number" then
            callback(key, value)
        end
    end
end

function Where2GoPreferences.Get(mode)
    AssertMode(mode)
    EnsureSavedVariables()
    return Where2GoCharDB.preferredItems[mode], Where2GoCharDB.preferredItemSources[mode]
end

function Where2GoPreferences.Subscribe(key, callback)
    if callback == nil then
        subscribers[key] = nil
    else
        assert(type(callback) == "function", "preference subscriber must be a function")
        subscribers[key] = callback
    end
end

function Where2GoPreferences.Notify(mode)
    AssertMode(mode)
    for _, callback in pairs(subscribers) do
        callback(mode)
    end
end

function Where2GoPreferences.Add(mode, items)
    local preferred, sources = Where2GoPreferences.Get(mode)
    local additions = {}

    ForEachItem(items, function(itemId, bonusId)
        if preferred[itemId] ~= true and additions[itemId] == nil then
            additions[itemId] = bonusId == nil and true or bonusId
        end
    end)

    local count = 0
    for _ in pairs(additions) do
        count = count + 1
    end
    if count == 0 then
        return 0
    end

    SaveUndo(mode, preferred, sources, count)
    for itemId, bonusId in pairs(additions) do
        preferred[itemId] = true
        if sources[itemId] == nil and type(bonusId) == "number" then
            sources[itemId] = bonusId
        end
    end
    Where2GoPreferences.Notify(mode)
    return count
end

function Where2GoPreferences.Remove(mode, itemId)
    local preferred, sources = Where2GoPreferences.Get(mode)
    if preferred[itemId] ~= true then
        return 0
    end

    SaveUndo(mode, preferred, sources, 1)
    preferred[itemId] = nil
    sources[itemId] = nil
    Where2GoPreferences.Notify(mode)
    return 1
end

function Where2GoPreferences.Clear(mode)
    local preferred, sources = Where2GoPreferences.Get(mode)
    if next(preferred) == nil and next(sources) == nil then
        return 0
    end

    local count = CountPreferred(preferred)
    SaveUndo(mode, preferred, sources, count)
    RestoreMap(preferred, {})
    RestoreMap(sources, {})
    Where2GoPreferences.Notify(mode)
    return count
end

function Where2GoPreferences.Undo(mode)
    AssertMode(mode)
    local transaction = undoByMode[mode]
    if not transaction then
        return 0
    end

    local preferred, sources = Where2GoPreferences.Get(mode)
    undoByMode[mode] = nil
    RestoreMap(preferred, transaction.preferred)
    RestoreMap(sources, transaction.sources)
    Where2GoPreferences.Notify(mode)
    return transaction.count
end

function Where2GoPreferences.HasUndo(mode)
    AssertMode(mode)
    return undoByMode[mode] ~= nil
end
