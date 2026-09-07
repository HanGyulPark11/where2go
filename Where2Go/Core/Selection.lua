Where2GoSelection = {}

local Selection = {}
Selection.__index = Selection

local function CountKeys(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function SelectionValue(entry)
    if entry.bonusId == nil then
        return true
    end
    return entry.bonusId
end

function Where2GoSelection.New()
    return setmetatable({
        available = {},
        selected = {},
        availableCount = 0,
    }, Selection)
end

function Selection:SetResults(entries, preferred, reset)
    local available = {}
    preferred = preferred or {}

    for _, entry in ipairs(entries or {}) do
        local itemId = entry.itemId
        if itemId ~= nil and preferred[itemId] ~= true and available[itemId] == nil then
            available[itemId] = SelectionValue(entry)
        end
    end

    local selected = {}
    if not reset then
        for itemId in pairs(self.selected) do
            if available[itemId] ~= nil then
                selected[itemId] = available[itemId]
            end
        end
    end

    self.available = available
    self.selected = selected
    self.availableCount = CountKeys(available)
    return self:GetCounts()
end

function Selection:SelectAll(selected)
    local nextSelected = {}
    if selected then
        for itemId, bonusId in pairs(self.available) do
            nextSelected[itemId] = bonusId
        end
    end
    self.selected = nextSelected
    return self:GetCounts()
end

function Selection:Toggle(itemId)
    if self.available[itemId] ~= nil then
        if self.selected[itemId] ~= nil then
            self.selected[itemId] = nil
        else
            self.selected[itemId] = self.available[itemId]
        end
    end
    return self:GetCounts()
end

function Selection:GetCounts()
    return CountKeys(self.selected), self.availableCount
end

function Selection:GetSelected()
    local selected = {}
    for itemId, bonusId in pairs(self.selected) do
        selected[itemId] = bonusId
    end
    return selected
end
