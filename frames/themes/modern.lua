local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/modern.lua
--  Modern Minimalist Theme Definition
-- ══════════════════════════════════════════════════════════════════════════════

sfui.theme.RegisterTheme({
    id             = "modern",
    name           = "Modern Minimalist",
    desc           = "Crisp dark slate panels with solid black borders and electric cyan & purple accents.",
    clientTag      = "retail",
    barTexture     = "Flat",
    autoDetect     = function()
        -- Auto-detect selects Modern on Retail
        return not sfui.isForever and not (sfui.compat and sfui.compat.is_wow_forever)
    end,
    colors         = {
        id             = "modern",
        name           = "Modern Minimalist",
        highlightColor = { 0.40, 0.00, 1.00, 1.0 }, -- #6600FF Purple
        accentColor    = { 0.00, 1.00, 1.00, 1.0 }, -- #00FFFF Cyan
        headerColor    = { 1.00, 1.00, 1.00, 1.0 }, -- Pure White
        backdropColor  = { 0.05, 0.05, 0.05, 0.85 }, -- Dark Slate
        borderColor    = { 0.00, 0.00, 0.00, 1.0 },  -- Solid Black
        containerColor = { 0.05, 0.05, 0.05, 0.80 }, -- Subtle Inset Panel
        tabSelected    = { 0.40, 0.00, 1.00, 1.0 },  -- Purple Selection
        tabNormal      = { 1.00, 1.00, 1.00, 1.0 },  -- White
        dimTextColor   = { 0.60, 0.60, 0.60, 1.0 },  -- Dim Gray
    },
    window         = {
        style       = "flat_border",
        borderSize  = 1,
        borderColor = { 0, 0, 0, 1 },
    },
    header         = {
        style       = "accent_bar",
        height      = 20,
    },
    closeButton    = {
        style       = "flat_cross",
    },
    lootfeed       = {
        style       = "minimal_flat",
    },
    bars           = {
        style   = "thin",
        texture = "Flat",
    },
})
