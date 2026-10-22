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

local THEMES = {
    {
        id = "maw", name = "maw", layout = "TooltipMawLayout", fillInset = 4,
        desc = "jagged grey stone with an icy soul-chill glow and jagged crest from the maw.",
        overlayTopAtlas = "Maw-tooltip-topper",
        overlayTopScale = 0.80,
        overlayTopYOffset = 6,
        palette = {
            highlight = { 0.40, 0.65, 0.75, 1.0 },
            accent    = { 0.40, 0.90, 0.95, 1.0 }, -- #65e6f2 soul-chill blue
            header    = { 0.85, 0.95, 1.00, 1.0 },
            backdrop  = { 0.04, 0.05, 0.06, 0.95 },
            border    = { 0.22, 0.32, 0.38, 1.0 },
            container = { 0.07, 0.09, 0.11, 0.85 },
            tabNormal = { 0.70, 0.80, 0.85, 1.0 },
            dim       = { 0.48, 0.55, 0.60, 1.0 },
        },
    },
    {
        id = "necrolord", name = "necrolord", layout = "Necrolord", fillInset = 4,
        desc = "chitinous bone plates and necrotic slime green from maldraxxus.",
        overlayTopAtlas = "CovenantChoice-Offering-Sigil-Necrolord",
        overlayTopScale = 0.65,
        overlayTopYOffset = 8,
        palette = {
            highlight = { 0.30, 0.68, 0.45, 1.0 },
            accent    = { 0.35, 0.85, 0.55, 1.0 }, -- #59d98c necrotic slime green
            header    = { 0.84, 0.82, 0.73, 1.0 }, -- bone ivory
            backdrop  = { 0.04, 0.06, 0.04, 0.95 }, -- deep crypt moss obsidian
            border    = { 0.20, 0.42, 0.28, 1.0 },
            container = { 0.06, 0.09, 0.06, 0.85 },
            tabNormal = { 0.70, 0.75, 0.68, 1.0 },
            dim       = { 0.45, 0.55, 0.45, 1.0 },
        },
    },
}

local ENABLE_NINESLICE_THEMES = true

if ENABLE_NINESLICE_THEMES then
    for i = 1, #THEMES do
        register_nineslice_theme(THEMES[i])
    end

    local regThemes, _ = sfui.theme.GetRegisteredThemes()
    if regThemes and regThemes["necrolord"] then
        regThemes["necrolords"] = regThemes["necrolord"]
        regThemes["maldraxxus"] = regThemes["necrolord"]
        if sfui.theme.palettes then
            sfui.theme.palettes["necrolords"] = regThemes["necrolord"].colors
            sfui.theme.palettes["maldraxxus"] = regThemes["necrolord"].colors
        end
    end
end
