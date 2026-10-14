local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local TARGET_MARKER_DEFS = {
    { id = "skull",    label = "skull",    marker = 8, coords = { 0.75, 1.00, 0.25, 0.50 }, color = { 1.0, 1.0, 1.0 } },
    { id = "cross",    label = "cross",    marker = 7, coords = { 0.50, 0.75, 0.25, 0.50 }, color = { 1.0, 0.2, 0.2 } },
    { id = "square",   label = "square",   marker = 6, coords = { 0.25, 0.50, 0.25, 0.50 }, color = { 0.2, 0.6, 1.0 } },
    { id = "moon",     label = "moon",     marker = 5, coords = { 0.00, 0.25, 0.25, 0.50 }, color = { 0.9, 0.9, 0.9 } },
    { id = "triangle", label = "triangle", marker = 4, coords = { 0.75, 1.00, 0.00, 0.25 }, color = { 0.2, 1.0, 0.2 } },
    { id = "diamond",  label = "diamond",  marker = 3, coords = { 0.50, 0.75, 0.00, 0.25 }, color = { 0.8, 0.3, 1.0 } },
    { id = "circle",   label = "circle",   marker = 2, coords = { 0.25, 0.50, 0.00, 0.25 }, color = { 1.0, 0.6, 0.1 } },
    { id = "star",     label = "star",     marker = 1, coords = { 0.00, 0.25, 0.00, 0.25 }, color = { 1.0, 1.0, 0.2 } },
    { id = "clear",    label = "clear",    marker = 0, icon = CLEAR_ICON, coords = { 0, 1, 0, 1 }, color = { 0.8, 0.8, 0.8 }, action = "clear" },
}

sfui.ring.register_provider("targetmarkers", {
    name   = "target markers",
    title  = "target markers",
    events = { "PLAYER_ENTERING_WORLD" },
    build  = function(out)
        for i = 1, #TARGET_MARKER_DEFS do
            local def = TARGET_MARKER_DEFS[i]
            out[#out + 1] = {
                id        = def.id,
                label     = def.label,
                icon      = def.icon or RAID_ICON_TEXTURE,
                texCoords = def.coords,
                color     = def.color,
                attrs     = {
                    type      = "macro",
                    macrotext = "/tm [@mouseover,exists][] " .. def.marker,
                },
            }
        end
    end,
})
