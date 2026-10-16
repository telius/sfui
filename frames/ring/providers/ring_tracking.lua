local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local C_Minimap           = _G.C_Minimap
local GetNumTrackingTypes = _G.GetNumTrackingTypes
local GetTrackingInfo     = _G.GetTrackingInfo
local SetTracking         = _G.SetTracking

local function get_tracking_info(index)
    if C_Minimap and C_Minimap.GetTrackingInfo then
        local res = C_Minimap.GetTrackingInfo(index)
        if type(res) == "table" then
            return res.name, res.texture, res.active, res.spellID
        elseif res ~= nil then
            local name, texture, active = C_Minimap.GetTrackingInfo(index)
            return name, texture, active, nil
        end
    end
    if GetTrackingInfo then
        local name, texture, active = GetTrackingInfo(index)
        return name, texture, active, nil
    end
    return nil, nil, false, nil
end

local function toggle_tracking(index, currentActive)
    if C_Minimap and C_Minimap.SetTracking then
        C_Minimap.SetTracking(index, not currentActive)
    elseif SetTracking then
        SetTracking(index)
    end
end

sfui.ring.register_provider("tracking", {
    name   = "minimap tracking",
    title  = "minimap tracking",
    events = { "MINIMAP_UPDATE_TRACKING", "PLAYER_ENTERING_WORLD" },
    build  = function(out)
        local count = (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes())
                      or (GetNumTrackingTypes and GetNumTrackingTypes())
                      or 0

        for i = 1, count do
            local name, texture, active = get_tracking_info(i)
            if name and name ~= "" then
                local trackingIndex = i
                local isActive = not not active
                out[#out + 1] = {
                    id                    = "tracking_" .. i,
                    label                 = (isActive and "|cff00ff00" or "|cff888888") .. name:lower() .. "|r",
                    icon                  = texture or "Interface\\Minimap\\Tracking\\None",
                    color                 = isActive and { 1.0, 1.0, 1.0 } or { 0.45, 0.45, 0.45 },
                    active                = isActive,
                    allow_combat_insecure = true,
                    insecure_func         = function()
                        toggle_tracking(trackingIndex, isActive)
                        if sfui.ring and sfui.ring.rebuild then
                            sfui.ring.rebuild("tracking")
                        end
                    end,
                }
            end
        end
    end,
})
