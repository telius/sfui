local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/nineslice_themes.lua
--  Native Blizzard frame themes built from NineSliceLayouts (Blizzard_SharedXML).
--  Each theme only shows up as selectable when every atlas of its layout exists
--  on the running client (see sfui.theme.HasNineSliceLayout / IsThemeAvailable).
-- ══════════════════════════════════════════════════════════════════════════════

-- Ensure NineSliceLayouts has the Necrolord covenant layout defined if missing
_G.NineSliceLayouts = _G.NineSliceLayouts or {}
if not _G.NineSliceLayouts.Necrolord then
    _G.NineSliceLayouts.Necrolord = {
        TopRightCorner    = { atlas = "Necrolord-NineSlice-CornerTopRight" },
        TopLeftCorner     = { atlas = "Necrolord-NineSlice-CornerTopLeft" },
        BottomLeftCorner  = { atlas = "Necrolord-NineSlice-CornerBottomLeft" },
        BottomRightCorner = { atlas = "Necrolord-NineSlice-CornerBottomRight" },
        TopEdge           = { atlas = "_Necrolord-NineSlice-EdgeTop" },
        BottomEdge        = { atlas = "_Necrolord-NineSlice-EdgeBottom" },
        LeftEdge          = { atlas = "!Necrolord-NineSlice-EdgeLeft" },
        RightEdge         = { atlas = "!Necrolord-NineSlice-EdgeRight" },
        Center            = { atlas = "Necrolord-NineSlice-Center" },
    }
end

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
            style             = "nineslice",
            layout            = def.layout,
            fillInset         = def.fillInset or 4,
            overlayTopAtlas   = def.overlayTopAtlas,
            overlayTopScale   = def.overlayTopScale,
            overlayTopXOffset = def.overlayTopXOffset,
            overlayTopYOffset = def.overlayTopYOffset,
        },
        header      = { style = "accent_bar", height = 20 },
        closeButton = { style = "flat_cross" },
        lootfeed    = { style = "minimal_flat" },
        bars        = {
            style         = "thin",
            texture       = "Flat",
            sparkColor    = def.palette.accent,
            castbar       = {
                sparkColor = def.palette.accent,
            },
        },
    })
end

local THEMES = {}

local ENABLE_NINESLICE_THEMES = false

if ENABLE_NINESLICE_THEMES then
    for i = 1, #THEMES do
        register_nineslice_theme(THEMES[i])
    end
end

