local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName ~= Where2GoConstants.ADDON_NAME then
        return
    end

    Where2GoDB = Where2GoDB or Where2GoConstants.BuildDefaultAccountDB()
    Where2GoCharDB = Where2GoCharDB or Where2GoConstants.BuildDefaultCharDB()

    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_WHERE2GO1 = "/where2go"
SlashCmdList["WHERE2GO"] = function()
    Where2Go_TogglePanel()
end
