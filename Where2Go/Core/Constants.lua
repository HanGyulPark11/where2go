Where2GoConstants = {}

Where2GoConstants.ADDON_NAME = "Where2Go"
Where2GoConstants.INTERFACE_VERSION = 120100
Where2GoConstants.SEASON_LABEL = "Midnight Season 2"

function Where2GoConstants.BuildDefaultAccountDB()
    return {
        panelShown = false,
    }
end

function Where2GoConstants.BuildDefaultCharDB()
    return {
        preferredItems = {},
    }
end
