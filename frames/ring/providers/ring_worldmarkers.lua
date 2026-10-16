local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local WORLD_MARKER_DEFS = {
    { id = "skull",    label = "skull flare",    marker = 8, coords = { 0.75, 1.00, 0.25, 0.50 }, color = { 1.0, 1.0, 1.0 } },
    { id = "cross",    label = "cross flare",    marker = 4, coords = { 0.50, 0.75, 0.25, 0.50 }, color = { 1.0, 0.2, 0.2 } },
    { id = "square",   label = "square flare",   marker = 1, coords = { 0.25, 0.50, 0.25, 0.50 }, color = { 0.2, 0.6, 1.0 } },
    { id = "moon",     label = "moon flare",     marker = 7, coords = { 0.00, 0.25, 0.25, 0.50 }, color = { 0.9, 0.9, 0.9 } },
    { id = "triangle", label = "triangle flare", marker = 2, coords = { 0.75, 1.00, 0.00, 0.25 }, color = { 0.2, 1.0, 0.2 } },
    { id = "diamond",  label = "diamond flare",  marker = 3, coords = { 0.50, 0.75, 0.00, 0.25 }, color = { 0.8, 0.3, 1.0 } },
    { id = "circle",   label = "circle flare",   marker = 6, coords = { 0.25, 0.50, 0.00, 0.25 }, color = { 1.0, 0.6, 0.1 } },
    { id = "star",     label = "star flare",     marker = 5, coords = { 0.00, 0.25, 0.00, 0.25 }, color = { 1.0, 1.0, 0.2 } },
    { id = "clear",    label = "clear flares",   marker = 0, icon = CLEAR_ICON, coords = { 0, 1, 0, 1 }, color = { 0.8, 0.8, 0.8 }, action = "clear" },
}

sfui.ring.register_provider("worldmarkers", {
    name   = "world markers",
    title  = "world markers",
    events = { "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE" },
    build  = function(out)
        local isMarkerActive = _G.IsRaidMarkerActive
        for i = 1, #WORLD_MARKER_DEFS do
            local def = WORLD_MARKER_DEFS[i]
            local isActive = (def.marker > 0 and isMarkerActive and isMarkerActive(def.marker))
            out[#out + 1] = {
                id             = def.id,
                label          = def.label,
                icon           = def.icon or RAID_ICON_TEXTURE,
                texCoords      = def.coords,
                color          = def.color,
                selectionColor = def.color,
                active         = isActive,
                attrs          = {
                    type   = "worldmarker",
                    action = def.action or "toggle",
                    marker = def.marker,
                },
            }
        end
    end,
})
