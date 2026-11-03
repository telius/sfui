local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/oldgod.lua
--  Authentic Old Gods Theme Definition (inspired by Chonky Character Sheet)
--  Sculpted blackened void alloy, coiling tentacles, glowing void eye crest,
--  side tentacle pillars, razor-sharp crystal containers, and cosmic nebula.
-- ══════════════════════════════════════════════════════════════════════════════

local OLDGOD_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\oldgod\\"

function sfui.theme.IsOldGodBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "oldGodBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.oldGodBackdrop ~= nil then
        return SfuiDB.theme.oldGodBackdrop == true
    end
    return SfuiDB and SfuiDB.themeOldGodBackdrop == true
end

function sfui.theme.SetOldGodBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeOldGodBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.oldGodBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "oldGodBackdrop", enabled and true or false)
    end
end

-- Slice definitions matching Chonky themesdb
local FRAME_SLICES = {
    TL = { tex = "char_frame_border.png", cx = -22, cy = 32,  map = { 95, 95, 0, 0.28, 0, 0.284 } },
    T  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 299, 190, 0.28, 0.72, 0, 0.284 } },
    TR = { tex = "char_frame_border.png", cx = 22,  cy = 32,  map = { 95, 95, 0.72, 1.0, 0, 0.284 } },
    R  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 190, 289, 0.72, 1.0, 0.284, 0.716 } },
    BR = { tex = "char_frame_border.png", cx = 22,  cy = -32, map = { 95, 95, 0.72, 1.0, 0.716, 1.0 } },
    B  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 299, 190, 0.28, 0.72, 0.716, 1.0 } },
    BL = { tex = "char_frame_border.png", cx = -22, cy = -32, map = { 95, 95, 0, 0.28, 0.716, 1.0 } },
    L  = { tex = "char_frame_border.png", cx = 0,   cy = 0,   map = { 190, 289, 0, 0.28, 0.284, 0.716 } },
}

local PAPER_SLICES = {
    TL = { tex = "paperdoll_border.png", cx = -10, cy = 6,  map = { 35, 35, 0, 0.15, 0, 0.155 } },
    T  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 328, 70, 0.15, 0.85, 0, 0.155 } },
    TR = { tex = "paperdoll_border.png", cx = 4,   cy = 6,  map = { 35, 35, 0.85, 1.0, 0, 0.155 } },
    R  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 70, 312, 0.85, 1.0, 0.155, 0.845 } },
    BR = { tex = "paperdoll_border.png", cx = 4,   cy = -3, map = { 35, 35, 0.85, 1.0, 0.845, 1.0 } },
    B  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 328, 70, 0.15, 0.85, 0.845, 1.0 } },
    BL = { tex = "paperdoll_border.png", cx = -10, cy = -3, map = { 35, 35, 0, 0.15, 0.845, 1.0 } },
    L  = { tex = "paperdoll_border.png", cx = 0,   cy = 0,  map = { 70, 312, 0, 0.15, 0.155, 0.845 } },
}

local STATS_SLICES = {
    TL = { tex = "stats_border.png", cx = -3, cy = 0,  map = { 15, 15, 0, 0.118, 0, 0.118 } },
    T  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 290, 45, 0.118, 0.882, 0, 0.118 } },
    TR = { tex = "stats_border.png", cx = 1,  cy = 0,  map = { 15, 15, 0.882, 1.0, 0, 0.118 } },
    R  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 45, 290, 0.882, 1.0, 0.118, 0.882 } },
    BR = { tex = "stats_border.png", cx = 1,  cy = 0,  map = { 15, 15, 0.882, 1.0, 0.882, 1.0 } },
    B  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 290, 45, 0.118, 0.882, 0.882, 1.0 } },
    BL = { tex = "stats_border.png", cx = -3, cy = 0,  map = { 15, 15, 0, 0.118, 0.882, 1.0 } },
    L  = { tex = "stats_border.png", cx = 0,  cy = 0,  map = { 45, 290, 0, 0.118, 0.118, 0.882 } },
}

local oldGodTheme = {
    id             = "oldgod",
    name           = "Old Gods",
    desc           = "authentic chonky old gods theme: sculpted blackened void alloy, curling tentacles, glowing void eye crest, side tentacle pillars, and soft void amethyst.",
    clientTag      = "any",
    barTexture     = "Flat",
    isAvailable    = function()
        return true
    end,
    colors         = {
        id             = "oldgod",
        name           = "Old Gods",
        highlightColor = { 0.56, 0.26, 0.72, 1.0 }, -- Subtle Voidglow Violet (#8F43B7)
        accentColor    = { 0.78, 0.48, 1.00, 1.0 }, -- Luminous Void Indigo / Violet (#C77AFF)
        headerColor    = { 0.92, 0.82, 1.00, 1.0 }, -- Pale Eldritch Violet (#EBD1FF)
        backdropColor  = { 0.05, 0.03, 0.08, 0.94 }, -- Deep Void Black / Abyssal (#0D0814)
        borderColor    = { 0.22, 0.16, 0.30, 1.0 },  -- Soft Void Amethyst (#38294C)
        containerColor = { 0.09, 0.06, 0.14, 0.88 }, -- Blackened Void Alloy Inset (#170F24)
        tabSelected    = { 0.82, 0.52, 1.00, 1.0 },  -- Radiant Void Glow
        tabNormal      = { 0.65, 0.55, 0.78, 1.0 },  -- Muted Amethyst Slate
        dimTextColor   = { 0.50, 0.42, 0.60, 1.0 },  -- Dim Voidshadow Slate (#806B99)
    },
    atlases        = {
        headerBanner        = "Nzoth-tooltip-topper",
        lootCard            = "LootToast-Nzoth",
        corruptedOverlay    = "Nzoth-charactersheet-item-glow",
        eyeIcon             = "Nzoth-charactersheet-icon",
        eyeGlow             = "Nzoth-charactersheet-icon-glow",
    },
    window         = {
        style       = "oldgod_custom",
    },
    header         = {
        style       = "accent_bar",
        height      = 24,
    },
    closeButton    = {
        style       = "flat_cross",
    },
    lootfeed       = {
        style       = "minimal_flat",
    },
    bars           = {
        style         = "thin",
        texture       = "Flat",
        backdropColor = { 0.06, 0.04, 0.10, 0.85 },
        borderColor   = { 0.28, 0.18, 0.40, 1.0 },
        sparkColor    = { 0.85, 0.45, 1.00, 1.0 },
        castbar       = {
            iconBorderColor = { 0.35, 0.20, 0.50, 1.0 },
            sparkColor      = { 0.85, 0.45, 1.00, 1.0 },
        },
    },
}

sfui.theme.AttachSliceTheme(oldGodTheme, {
    mediaPath        = OLDGOD_MEDIA,
    layerKey         = "sfuiOldGodLayers",
    containerKey     = "sfuiOldGodContainer",
    headerKey        = "sfuiOldGodHeader",
    isBackdropActive = sfui.theme.IsOldGodBackdropActive,
    backdropAlpha    = 0.85,
    frameSlices      = FRAME_SLICES,
    paperSlices      = PAPER_SLICES,
    statsSlices      = STATS_SLICES,
    topOverlay       = { w = 400, h = 80.17, y = 18 },
    sideMode         = "oldgod",
    aliases          = { "oldgods" },
})
