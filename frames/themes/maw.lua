local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/maw.lua
--  Authentic Maw & Torghast Spire Theme Definition
--  Bespoke sculpted saronite/obsidian Maw stone, horned domination crown crest,
--  frost-rimmed soul-chains, icy soul-chill blue anima (#65e6f2), and dark soul-slate.
-- ══════════════════════════════════════════════════════════════════════════════

local MAW_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\maw\\"

function sfui.theme.IsMawBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "mawBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.mawBackdrop ~= nil then
        return SfuiDB.theme.mawBackdrop == true
    end
    return SfuiDB and SfuiDB.themeMawBackdrop == true
end

function sfui.theme.SetMawBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeMawBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.mawBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "mawBackdrop", enabled and true or false)
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

local mawTheme = {
    id   = "maw",
    name = "maw",
    desc = "jagged saronite maw spikes, soul-chill blue anima glow (#65e6f2), domination crown crest, and dark soul-slate.",
    clientTag = "any",
    isAvailable = function()
        return true
    end,
    colors = {
        id             = "maw",
        name           = "maw",
        highlightColor = { 0.30, 0.55, 0.70, 1.0 },
        accentColor    = { 0.40, 0.90, 0.95, 1.0 }, -- #65e6f2 soul-chill blue
        headerColor    = { 0.85, 0.95, 1.00, 1.0 },
        backdropColor  = { 0.04, 0.05, 0.07, 0.95 },
        borderColor    = { 0.20, 0.32, 0.40, 1.0 },
        containerColor = { 0.06, 0.08, 0.11, 0.85 },
        tabNormal      = { 0.70, 0.80, 0.85, 1.0 },
        tabSelected    = { 0.40, 0.90, 0.95, 1.0 },
        dimTextColor   = { 0.45, 0.55, 0.62, 1.0 },
    },
    window = {
        style = "bespoke_maw",
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
        sparkColor = { 0.40, 0.90, 0.95, 1.0 },
        castbar    = {
            sparkColor = { 0.40, 0.90, 0.95, 1.0 },
        },
    },
}

sfui.theme.AttachSliceTheme(mawTheme, {
    mediaPath        = MAW_MEDIA,
    layerKey         = "sfuiMawLayers",
    containerKey     = "sfuiMawContainer",
    headerKey        = "sfuiMawHeader",
    isBackdropActive = sfui.theme.IsMawBackdropActive,
    backdropAlpha    = 1.0,
    frameSlices      = FRAME_SLICES,
    paperSlices      = PAPER_SLICES,
    statsSlices      = STATS_SLICES,
    topOverlay       = { w = 410, h = 82, y = 23 },
    sideMode         = "proportional",
    aliases          = { "the_maw", "themaw" },
})
