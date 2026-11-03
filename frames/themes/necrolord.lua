local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/necrolord.lua
--  Authentic Necrolord & Maldraxxus Theme Definition
--  Bespoke carved bone-plate chitin, horned beast skull crest,
--  ribbed vertebrae spine pillars, toxic necrotic slime green (#59d98c), and bone ivory.
-- ══════════════════════════════════════════════════════════════════════════════

local NECROLORD_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\necrolord\\"

function sfui.theme.IsNecrolordBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "necrolordBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.necrolordBackdrop ~= nil then
        return SfuiDB.theme.necrolordBackdrop == true
    end
    return SfuiDB and SfuiDB.themeNecrolordBackdrop == true
end

function sfui.theme.SetNecrolordBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeNecrolordBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.necrolordBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "necrolordBackdrop", enabled and true or false)
    end
end

-- Slices matching sculpted high-definition border suite
local FRAME_SLICES = {
    TL = { tex = "char_frame_border.png", cx = -17, cy = 25,  map = { 68, 68, 0, 0.229, 0, 0.232 } },
    T  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 379, 160, 0.229, 0.771, 0, 0.232 } },
    TR = { tex = "char_frame_border.png", cx = 17,  cy = 25,  map = { 160, 160, 0.771, 1.0, 0, 0.232 } },
    R  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 160, 371, 0.771, 1.0, 0.232, 0.768 } },
    BR = { tex = "char_frame_border.png", cx = 17,  cy = -25, map = { 160, 160, 0.771, 1.0, 0.768, 1.0 } },
    B  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 379, 160, 0.229, 0.771, 0.768, 1.0 } },
    BL = { tex = "char_frame_border.png", cx = -17, cy = -25, map = { 160, 160, 0, 0.229, 0.768, 1.0 } },
    L  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 160, 371, 0, 0.229, 0.232, 0.768 } },
}

local PAPER_SLICES = {
    TL = { tex = "paperdoll_border.png", cx = -7, cy = 3,  map = { 20, 20, 0, 0.139, 0, 0.144 } },
    T  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 339, 65, 0.139, 0.861, 0, 0.144 } },
    TR = { tex = "paperdoll_border.png", cx = 4,  cy = 3,  map = { 65, 65, 0.861, 1.0, 0, 0.144 } },
    R  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 65, 322, 0.861, 1.0, 0.144, 0.856 } },
    BR = { tex = "paperdoll_border.png", cx = 4,  cy = -3, map = { 65, 65, 0.861, 1.0, 0.856, 1.0 } },
    B  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 339, 65, 0.139, 0.861, 0.856, 1.0 } },
    BL = { tex = "paperdoll_border.png", cx = -7, cy = -3, map = { 65, 65, 0, 0.139, 0.856, 1.0 } },
    L  = { tex = "paperdoll_border.png", cx = 0,  cy = 0,  map = { 65, 322, 0, 0.139, 0.144, 0.856 } },
}

local STATS_SLICES = {
    TL = { tex = "stats_border.png", cx = -3, cy = 0, map = { 15, 15, 0, 0.119, 0, 0.118 } },
    T  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 288, 45, 0.119, 0.881, 0, 0.118 } },
    TR = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 45, 0.881, 1.0, 0, 0.118 } },
    R  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 291, 0.881, 1.0, 0.118, 0.882 } },
    BR = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 45, 0.881, 1.0, 0.882, 1.0 } },
    B  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 288, 45, 0.119, 0.881, 0.882, 1.0 } },
    BL = { tex = "stats_border.png", cx = -3, cy = 0, map = { 45, 45, 0, 0.119, 0.882, 1.0 } },
    L  = { tex = "stats_border.png", cx = 0,  cy = 0, map = { 45, 291, 0.119, 0.118, 0.882 } },
}

local necrolordTheme = {
    id   = "necrolord",
    name = "necrolord",
    desc = "carved bone-plate chitin, toxic necrotic slime green (#59d98c), horned bone skull crest, and bone ivory.",
    clientTag = "any",
    isAvailable = function()
        return true
    end,
    colors = {
        id             = "necrolord",
        name           = "necrolord",
        highlightColor = { 0.25, 0.65, 0.40, 1.0 },
        accentColor    = { 0.35, 0.85, 0.55, 1.0 }, -- #59d98c necrotic slime green
        headerColor    = { 0.88, 0.85, 0.75, 1.0 }, -- bone ivory
        backdropColor  = { 0.04, 0.06, 0.04, 0.95 }, -- deep crypt moss obsidian
        borderColor    = { 0.22, 0.45, 0.28, 1.0 },
        containerColor = { 0.06, 0.09, 0.06, 0.85 },
        tabNormal      = { 0.72, 0.78, 0.70, 1.0 },
        tabSelected    = { 0.35, 0.85, 0.55, 1.0 },
        dimTextColor   = { 0.48, 0.55, 0.48, 1.0 },
    },
    window = {
        style = "bespoke_necrolord",
    },
    header = {
        style  = "accent_bar",
        height = 24,
    },
    closeButton = {
        style = "flat_cross",
    },
    lootfeed = {
        style = "minimal_flat",
    },
    bars = {
        style      = "thin",
        texture    = "Flat",
        sparkColor = { 0.35, 0.85, 0.55, 1.0 },
        castbar    = {
            sparkColor = { 0.35, 0.85, 0.55, 1.0 },
        },
    },
}

sfui.theme.AttachSliceTheme(necrolordTheme, {
    mediaPath        = NECROLORD_MEDIA,
    layerKey         = "sfuiNecrolordLayers",
    containerKey     = "sfuiNecrolordContainer",
    headerKey        = "sfuiNecrolordHeader",
    isBackdropActive = sfui.theme.IsNecrolordBackdropActive,
    backdropAlpha    = 1.0,
    frameSlices      = FRAME_SLICES,
    paperSlices      = PAPER_SLICES,
    statsSlices      = STATS_SLICES,
    topOverlay       = { w = 410, h = 82, y = 23 },
    sideMode         = "proportional",
    aliases          = { "necrolords", "maldraxxus" },
})
