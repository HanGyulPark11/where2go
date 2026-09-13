local WowUI = {}

local function newRegion(kind, name, parent)
    local region = {
        kind = kind,
        name = name,
        parent = parent,
        shown = true,
        points = {},
    }

    local methods = {}

    function methods:SetPoint(...)
        table.insert(self.points, { ... })
    end

    function methods:ClearAllPoints()
        self.points = {}
    end

    function methods:SetAllPoints(...)
        self.allPoints = { ... }
    end

    function methods:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function methods:SetWidth(width)
        self.width = width
    end

    function methods:SetHeight(height)
        self.height = height
    end

    function methods:GetWidth()
        return self.width
    end

    function methods:GetHeight()
        return self.height
    end

    function methods:SetText(text)
        self.text = text
    end

    function methods:GetText()
        return self.text
    end

    function methods:GetStringWidth()
        local text = self.text or ""
        local width = 0
        for i = 1, #text do
            local byte = string.byte(text, i)
            width = width + (byte and byte >= 128 and 6 or 7)
        end
        return width
    end

    function methods:SetTextColor(...)
        self.textColor = { ... }
    end

    function methods:SetColorTexture(...)
        self.colorTexture = { ... }
    end

    function methods:SetTexture(texture)
        self.texture = texture
    end

    function methods:SetVertexColor(...)
        self.vertexColor = { ... }
    end

    function methods:SetJustifyH(value)
        self.justifyH = value
    end

    function methods:SetJustifyV(value)
        self.justifyV = value
    end

    function methods:SetWordWrap(value)
        self.wordWrap = value
    end

    function methods:SetFontObject(value)
        self.fontObject = value
    end

    function methods:SetAlpha(value)
        self.alpha = value
    end

    function methods:Show()
        self.shown = true
    end

    function methods:Hide()
        self.shown = false
    end

    function methods:IsShown()
        return self.shown
    end

    function methods:SetShown(value)
        self.shown = value and true or false
    end

    return setmetatable(region, {
        __index = function(_, key)
            local method = methods[key]
            if method then
                return method
            end
            error(string.format("unsupported %s method: %s", kind, tostring(key)), 2)
        end,
    })
end

function WowUI.New()
    local env = {
        frames = {},
        namedFrames = {},
    }

    local frameMethods = {}

    local function runHandlers(frame, script, ...)
        local handler = frame.scripts[script]
        if handler then
            handler(frame, ...)
        end
        local hooks = frame.scriptHooks[script]
        if hooks then
            for _, hook in ipairs(hooks) do
                hook(frame, ...)
            end
        end
    end

    function frameMethods:SetPoint(...)
        table.insert(self.points, { ... })
    end

    function frameMethods:ClearAllPoints()
        self.points = {}
    end

    function frameMethods:SetAllPoints(...)
        self.allPoints = { ... }
    end

    function frameMethods:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frameMethods:SetWidth(width)
        self.width = width
    end

    function frameMethods:SetHeight(height)
        self.height = height
    end

    function frameMethods:GetWidth()
        return rawget(self, "width")
    end

    function frameMethods:GetHeight()
        return rawget(self, "height")
    end

    function frameMethods:GetLeft()
        return rawget(self, "left") or 0
    end

    function frameMethods:GetRight()
        return rawget(self, "right") or (self:GetLeft() + (self:GetWidth() or 0))
    end

    function frameMethods:GetTop()
        return rawget(self, "top") or (self:GetBottom() + (self:GetHeight() or 0))
    end

    function frameMethods:GetBottom()
        return rawget(self, "bottom") or 0
    end

    function frameMethods:GetEffectiveScale()
        return rawget(self, "effectiveScale") or 1
    end

    function frameMethods:GetPoint(index)
        local point = self.points[index or 1]
        if point then
            return unpack(point)
        end
    end

    function frameMethods:SetParent(parent)
        self.parent = parent
    end

    function frameMethods:GetParent()
        return self.parent
    end

    function frameMethods:SetClampedToScreen(value)
        self.clampedToScreen = value
    end

    function frameMethods:SetMovable(value)
        self.movable = value
    end

    function frameMethods:EnableMouse(value)
        self.mouseEnabled = value
    end

    function frameMethods:EnableMouseWheel(value)
        self.mouseWheelEnabled = value
    end

    function frameMethods:RegisterForDrag(...)
        self.dragButtons = { ... }
    end

    function frameMethods:RegisterForClicks(...)
        self.clickButtons = { ... }
    end

    function frameMethods:RegisterEvent(event)
        self.events[event] = true
    end

    function frameMethods:UnregisterEvent(event)
        self.events[event] = nil
    end

    function frameMethods:SetScript(script, handler)
        self.scripts[script] = handler
    end

    function frameMethods:GetScript(script)
        return self.scripts[script]
    end

    function frameMethods:HookScript(script, handler)
        self.scriptHooks[script] = self.scriptHooks[script] or {}
        table.insert(self.scriptHooks[script], handler)
    end

    function frameMethods:Show()
        if not self.shown then
            self.shown = true
            runHandlers(self, "OnShow")
        end
    end

    function frameMethods:Hide()
        if self.shown then
            self.shown = false
            runHandlers(self, "OnHide")
        end
    end

    function frameMethods:IsShown()
        return self.shown
    end

    function frameMethods:SetShown(value)
        if value then
            self:Show()
        else
            self:Hide()
        end
    end

    function frameMethods:SetBackdrop(backdrop)
        self.backdrop = backdrop
    end

    function frameMethods:SetBackdropColor(...)
        self.backdropColor = { ... }
    end

    function frameMethods:SetBackdropBorderColor(...)
        self.backdropBorderColor = { ... }
    end

    function frameMethods:SetTextInsets(...)
        self.textInsets = { ... }
    end

    function frameMethods:SetTextColor(...)
        self.textColor = { ... }
    end

    function frameMethods:SetFontObject(value)
        self.fontObject = value
    end

    function frameMethods:SetText(text)
        self.text = text
        local fontString = rawget(self, "fontString")
        if fontString then
            fontString:SetText(text)
        end
        if rawget(self, "frameType") == "EditBox" then
            runHandlers(self, "OnTextChanged", true)
        end
    end

    function frameMethods:GetText()
        return rawget(self, "text")
    end

    function frameMethods:SetFontString(fontString)
        self.fontString = fontString
    end

    function frameMethods:GetFontString()
        return rawget(self, "fontString")
    end

    function frameMethods:SetEnabled(value)
        self.enabled = value and true or false
        runHandlers(self, self.enabled and "OnEnable" or "OnDisable")
    end

    function frameMethods:IsEnabled()
        return rawget(self, "enabled") ~= false
    end

    function frameMethods:SetAlpha(value)
        self.alpha = value
    end

    function frameMethods:SetHitRectInsets(...)
        self.hitRectInsets = { ... }
    end

    function frameMethods:SetFrameStrata(value)
        self.frameStrata = value
    end

    function frameMethods:SetScrollChild(child)
        self.scrollChild = child
    end

    function frameMethods:SetVerticalScroll(value)
        self.verticalScroll = value
    end

    function frameMethods:GetVerticalScroll()
        return rawget(self, "verticalScroll") or 0
    end

    function frameMethods:SetMinMaxValues(minimum, maximum)
        self.minValue = minimum
        self.maxValue = maximum
    end

    function frameMethods:GetMinMaxValues()
        return rawget(self, "minValue"), rawget(self, "maxValue")
    end

    function frameMethods:SetValue(value)
        local previous = rawget(self, "value")
        self.value = value
        if previous ~= value then
            runHandlers(self, "OnValueChanged", value)
        end
    end

    function frameMethods:GetValue()
        return rawget(self, "value")
    end

    function frameMethods:SetValueStep(value)
        self.valueStep = value
    end

    function frameMethods:SetObeyStepOnDrag(value)
        self.obeyStepOnDrag = value
    end

    function frameMethods:SetOrientation(value)
        self.orientation = value
    end

    function frameMethods:SetThumbTexture(texture)
        if type(texture) == "table" then
            self.thumbTexture = texture
        else
            self.thumbTexture = rawget(self, "thumbTexture") or self:CreateTexture(nil, "ARTWORK")
            self.thumbTexture:SetTexture(texture)
        end
    end

    function frameMethods:GetThumbTexture()
        return rawget(self, "thumbTexture")
    end

    function frameMethods:SetChecked(value)
        self.checked = value and true or false
    end

    function frameMethods:GetChecked()
        return rawget(self, "checked") == true
    end

    function frameMethods:SetAutoFocus(value)
        self.autoFocus = value
    end

    function frameMethods:ClearFocus()
        self.focused = false
    end

    function frameMethods:SetupMenu(callback)
        self.menuGenerator = callback
    end

    function frameMethods:CreateFontString(name, layer, template)
        local region = newRegion("FontString", name, self)
        region.layer = layer
        region.template = template
        table.insert(self.regions, region)
        if name then
            env.namedFrames[name] = region
        end
        return region
    end

    function frameMethods:CreateTexture(name, layer)
        local region = newRegion("Texture", name, self)
        region.layer = layer
        table.insert(self.regions, region)
        if name then
            env.namedFrames[name] = region
        end
        return region
    end

    function frameMethods:StartMoving()
        self.moving = true
    end

    function frameMethods:StopMovingOrSizing()
        self.moving = false
    end

    function env:CreateFrame(frameType, name, parent, template)
        local frame = {
            frameType = frameType,
            name = name,
            parent = parent,
            template = template,
            shown = true,
            points = {},
            scripts = {},
            scriptHooks = {},
            events = {},
            regions = {},
            enabled = true,
        }
        setmetatable(frame, {
            __index = function(_, key)
                local method = frameMethods[key]
                if method then
                    return method
                end
                error("unsupported Frame method: " .. tostring(key), 2)
            end,
        })
        table.insert(self.frames, frame)
        if name then
            self.namedFrames[name] = frame
        end
        if type(template) == "string" and template:find("WowStyle1FilterDropdownTemplate", 1, true) then
            frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            frame.dropdownArrow = frame:CreateTexture(nil, "ARTWORK")
            frame.dropdownArrow:SetTexture("Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up")
            frame.dropdownBorder = frame:CreateTexture(nil, "BACKGROUND")
            frame.dropdownBorder:SetTexture("Interface\Buttons\UI-Silver-Button-Up")
        end
        return frame
    end

    env.UIParent = env:CreateFrame("Frame", "UIParent", nil)
    env.UIParent:SetSize(1920, 1080)

    function env:InstallGlobals()
        if not self.savedGlobals then
            self.savedGlobals = {
                CreateFrame = CreateFrame,
                UIParent = UIParent,
            }
        end
        CreateFrame = function(...)
            return self:CreateFrame(...)
        end
        UIParent = self.UIParent
    end


    function env:RestoreGlobals()
        assert(self.savedGlobals, "InstallGlobals must be called before RestoreGlobals")
        CreateFrame = self.savedGlobals.CreateFrame
        UIParent = self.savedGlobals.UIParent
        self.savedGlobals = nil
    end

    function env:GetFrame(name)
        local named = self.namedFrames[name]
        if named then
            return named
        end
        for _, frame in ipairs(self.frames) do
            if rawget(frame, "name") == name or rawget(frame, "wowUIName") == name then
                return frame
            end
            for _, region in ipairs(frame.regions) do
                if rawget(region, "name") == name or rawget(region, "wowUIName") == name then
                    return region
                end
            end
        end
        return nil
    end

    function env:RunScript(frameOrName, script, ...)
        local frame = type(frameOrName) == "string" and self:GetFrame(frameOrName) or frameOrName
        assert(frame, "frame does not exist: " .. tostring(frameOrName))
        runHandlers(frame, script, ...)
    end

    function env:Click(frameOrName, ...)
        local frame = type(frameOrName) == "string" and self:GetFrame(frameOrName) or frameOrName
        assert(frame, "frame does not exist: " .. tostring(frameOrName))
        if not frame:IsEnabled() then
            return
        end
        if rawget(frame, "frameType") == "CheckButton" then
            frame:SetChecked(not frame:GetChecked())
        end
        self:RunScript(frame, "OnClick", ...)
    end

    function env:FireEvent(event, ...)
        local snapshot = {}
        for i, frame in ipairs(self.frames) do
            snapshot[i] = frame
        end
        for _, frame in ipairs(snapshot) do
            if frame.events[event] then
                runHandlers(frame, "OnEvent", event, ...)
            end
        end
    end

    function env:CountFrames(frameType)
        local count = 0
        for _, frame in ipairs(self.frames) do
            if not frameType or frame.frameType == frameType then
                count = count + 1
            end
        end
        return count
    end

    return env
end

return WowUI
