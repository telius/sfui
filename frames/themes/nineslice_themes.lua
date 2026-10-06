local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/nineslice_themes.lua
--  Native Blizzard frame themes built from NineSliceLayouts (Blizzard_SharedXML).
--  Each theme only shows up as selectable when every atlas of its layout exists
--  on the running client (see sfui.theme.HasNineSliceLayout / IsThemeAvailable).
--  status: parked. only the maw and corrupted sets are kept, and registration is
--  disabled (ENABLE_NINESLICE_THEMES) so none are shown in the theme picker.
-- ══════════════════════════════════════════════════════════════════════════════

local function make_palette(id, name, p)
    return {
        id             = id,
        name           = name,
        highlightColor = p.highlight,
        accentColor    = p.accent,
        headerColor    = p.header,
        backdropColor  = p.backdrop,
        borderColor    = p.border or { 0, 0, 0, 1 },
        containerColor = p.container,
        tabSelected    = p.accent,
        tabNormal      = p.tabNormal or { 0.85, 0.85, 0.85, 1.0 },
        dimTextColor   = p.dim or { 0.60, 0.60, 0.60, 1.0 },
    }
end

local function register_nineslice_theme(def)
    sfui.theme.RegisterTheme({
        id          = def.id,
        name        = def.name,
        desc        = def.desc,
        clientTag   = "any",
        isAvailable = function()
            return sfui.theme.HasNineSliceLayout(def.layout)
        end,
        colors      = make_palette(def.id, def.name, def.palette),
        window      = {
            style     = "nineslice",
            layout    = def.layout,
            fillInset = def.fillInset or 4,
        },
        header      = { style = "accent_bar", height = 20 },
        closeButton = { style = "flat_cross" },
        lootfeed    = { style = "minimal_flat" },
        bars        = { style = "thin" },
    })
end

local THEMES = {
    {
        id = "maw", name = "maw", layout = "TooltipMawLayout", fillInset = 3,
        desc = "jagged grey stone with an icy glow from the maw.",
        palette = {
            highlight = { 0.40, 0.55, 0.60, 1.0 },
            accent    = { 0.65, 0.90, 0.95, 1.0 },
            header    = { 0.85, 0.95, 1.00, 1.0 },
            backdrop  = { 0.04, 0.05, 0.06, 0.95 },
            container = { 0.07, 0.09, 0.10, 0.85 },
            tabNormal = { 0.75, 0.82, 0.85, 1.0 },
            dim       = { 0.52, 0.58, 0.60, 1.0 },
        },
    },
    {
        id = "corrupted", name = "corrupted", layout = "TooltipCorruptedLayout", fillInset = 3,
        desc = "black void frame with swirling purple corruption.",
        palette = {
            highlight = { 0.50, 0.20, 0.80, 1.0 },
            accent    = { 0.80, 0.50, 1.00, 1.0 },
            header    = { 0.92, 0.82, 1.00, 1.0 },
            backdrop  = { 0.05, 0.03, 0.07, 0.95 },
            container = { 0.08, 0.04, 0.11, 0.85 },
            tabNormal = { 0.82, 0.74, 0.90, 1.0 },
            dim       = { 0.58, 0.50, 0.66, 1.0 },
        },
    },
}

-- decommissioned: the nine-slice theme infrastructure stays in the engine, but no
-- themes are offered to users for now. flip to true to register the sets above.
local ENABLE_NINESLICE_THEMES = false

if ENABLE_NINESLICE_THEMES then
    for i = 1, #THEMES do
        register_nineslice_theme(THEMES[i])
    end
end
