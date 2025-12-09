sfui = sfui or {}
sfui.minimap = {}

-- Set up the addon's frame
local addonName, addon = ...
local frame = CreateFrame("Frame", addonName)

local zoom_timer = nil
local DEFAULT_ZOOM = 0
local custom_border = nil
local button_bar = nil

-- Store original minimap size
local original_width = Minimap:GetWidth()
local original_height = Minimap:GetHeight()

function sfui.minimap.SetSquareMinimap(isSquare)
    if isSquare then
        -- Hide default borders
        if MinimapBorder then MinimapBorder:Hide() end
        if MinimapBackdrop then MinimapBackdrop:Hide() end

        -- Create custom border if it doesn't exist
        if not custom_border then
            custom_border = CreateFrame("Frame", "sfui_minimap_border", Minimap, "BackdropTemplate")
            custom_border:SetAllPoints(Minimap)
        end
        
        -- Configure backdrop
        local cfg = sfui.config.minimap.border
        custom_border:SetBackdrop({
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = cfg.size,
        })
        custom_border:SetBackdropBorderColor(cfg.color[1], cfg.color[2], cfg.color[3], cfg.color[4])
        custom_border:Show()
        
        Minimap:SetMaskTexture("Interface/Buttons/WHITE8X8")
        Minimap:SetSize(sfui.config.minimap.default_size, sfui.config.minimap.default_size)
    else
        -- Show default borders and hide custom one
        if MinimapBorder then MinimapBorder:Show() end
        if MinimapBackdrop then MinimapBackdrop:Show() end
        if custom_border then
            custom_border:Hide()
        end
        
        Minimap:SetMaskTexture("Interface/Minimap/Minimap-Circle-Mask")
        Minimap:SetSize(original_width, original_height)
    end
end

function sfui.minimap.CollectButtons()
    local ldbi = LibStub("LibDBIcon-1.0")
    if not ldbi then return end

    if not button_bar then
        button_bar = CreateFrame("Frame", "sfui_minimap_button_bar", Minimap)
        button_bar:SetPoint("TOP", Minimap, "TOP", 0, 20)
        button_bar:SetSize(sfui.config.minimap.default_size, 30)
    end

    local function ArrangeAllButtons()
        local buttons = ldbi:GetButtonList()
        local lastButton = nil
        for _, buttonName in ipairs(buttons) do
            local button = _G[buttonName]
            if button then
                button:SetParent(button_bar)
                button:ClearAllPoints()
                if not lastButton then
                    button:SetPoint("LEFT", button_bar, "LEFT", 5, 0)
                else
                    button:SetPoint("LEFT", lastButton, "RIGHT", 5, 0)
                end
                lastButton = button
            end
        end
    end

    ArrangeAllButtons()

    frame.OnButtonCreated = ArrangeAllButtons
    ldbi:RegisterCallback(frame, "LibDBIcon_IconCreated", "OnButtonCreated")
end

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
    
    -- Initialize square minimap setting
    SfuiDB.minimap_square = SfuiDB.minimap_square or false
    sfui.minimap.SetSquareMinimap(SfuiDB.minimap_square)

    -- Collect minimap buttons
    sfui.minimap.CollectButtons()

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