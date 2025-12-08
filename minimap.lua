-- Set up the addon's frame
local addonName, addon = ...
local frame = CreateFrame("Frame", addonName)

local zoom_timer = nil
local DEFAULT_ZOOM = 0

-- Function to set the minimap to the default zoom level
local function set_default_zoom()
    if zoom_timer then
        zoom_timer:Cancel()
        zoom_timer = nil
    end
    Minimap:SetZoom(DEFAULT_ZOOM)
end

-- Register for events
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("MINIMAP_UPDATE_ZOOM")

-- Define the event handler
frame:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    -- SfuiDB is guaranteed to be loaded here. Initialize if it doesn't exist.
    SfuiDB.minimap_auto_zoom = SfuiDB.minimap_auto_zoom or false
    if SfuiDB.minimap_auto_zoom then
        set_default_zoom()
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD") -- Only need this once
    return
  end
  
  if not SfuiDB.minimap_auto_zoom then
    if zoom_timer then
        zoom_timer:Cancel()
        zoom_timer = nil
    end
    return 
  end

  if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
    -- Any change in state resets to default zoom
    set_default_zoom()
  elseif event == "MINIMAP_UPDATE_ZOOM" then
    if Minimap:GetZoom() ~= DEFAULT_ZOOM then
        -- User manually changed zoom, start a timer to revert
        if zoom_timer then
            zoom_timer:Cancel()
        end
        zoom_timer = C_Timer.NewTimer(5, set_default_zoom)
    end
  end
end)