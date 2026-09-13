-- Shared native-window styling. Item quality colors remain Blizzard-owned.
Where2GoTheme = {}

Where2GoTheme.colors = {
    bg = { 0.055, 0.063, 0.075 },
    surface = { 0.090, 0.102, 0.118 },
    inset = { 0.039, 0.047, 0.059 },
    border = { 0.220, 0.247, 0.282 },
    text = { 0.910, 0.925, 0.945 },
    muted = { 0.640, 0.690, 0.750 },
    accent = { 0.940, 0.790, 0.480 },
    hover = { 0.145, 0.173, 0.208 },
    selected = { 0.180, 0.165, 0.110 },
    selectedBorder = { 0.460, 0.390, 0.220 },
}

function Where2GoTheme.Box(frame, colorKey)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(Where2GoTheme.colors[colorKey or "bg"]))
    frame:SetBackdropBorderColor(unpack(Where2GoTheme.colors.border))
end

function Where2GoTheme.Text(parent, template, text)
    local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetTextColor(unpack(Where2GoTheme.colors.text))
    label:SetText(text or "")
    return label
end

function Where2GoTheme.Button(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    Where2GoTheme.Box(button, "surface")
    local label = Where2GoTheme.Text(button, "GameFontHighlightSmall", text)
    label:SetPoint("CENTER")
    button:SetFontString(label)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self:SetBackdropBorderColor(unpack(Where2GoTheme.colors.accent))
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(Where2GoTheme.colors.border))
    end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    return button
end
