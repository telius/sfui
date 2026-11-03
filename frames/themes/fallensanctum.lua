local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/fallensanctum.lua
--  Authentic Fallen Sanctum Theme Definition (inspired by Chonky Character Sheet)
--  Sculpted Torghast domination crypt stone, horned gargoyle skull crest,
--  hanging soul chains, blood crimson crypt iron, and soul-fire teal (#1df2c6).
-- ══════════════════════════════════════════════════════════════════════════════

local FALLENSANCTUM_MEDIA = "Interface\\AddOns\\sfui\\frames\\themes\\media\\fallensanctum\\"

function sfui.theme.IsFallenSanctumBackdropActive()
    if sfui.db and sfui.db.Get then
        local v = sfui.db.Get("theme", "fallenSanctumBackdrop")
        if v ~= nil then return v == true end
    end
    if SfuiDB and SfuiDB.theme and SfuiDB.theme.fallenSanctumBackdrop ~= nil then
        return SfuiDB.theme.fallenSanctumBackdrop == true
    end
    return SfuiDB and SfuiDB.themeFallenSanctumBackdrop == true
end

function sfui.theme.SetFallenSanctumBackdrop(enabled)
    SfuiDB = SfuiDB or {}
    SfuiDB.themeFallenSanctumBackdrop = enabled and true or false
    SfuiDB.theme = SfuiDB.theme or {}
    SfuiDB.theme.fallenSanctumBackdrop = enabled and true or false
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "fallenSanctumBackdrop", enabled and true or false)
    end
end

-- Slice definitions matching Chonky themesdb
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

local fallenSanctumTheme = {
    id             = "fallensanctum",
    name           = "Fallen Sanctum",
    desc           = "bespoke torghast crypt stone: horned gargoyle crest, hanging soul chains, blood crimson crypt iron, and soul-fire teal.",
    clientTag      = "any",
    barTexture     = "Flat",
    isAvailable    = function()
        return true
    end,
    colors         = {
        id             = "fallensanctum",
        name           = "Fallen Sanctum",
        highlightColor = { 0.67, 0.20, 0.17, 1.0 }, -- Blood Crimson (#AB332B)
        accentColor    = { 0.114, 0.949, 0.776, 1.0 }, -- Soul-Fire Teal (#1DF2C6)
        headerColor    = { 0.96, 0.78, 0.78, 1.0 }, -- Pale Crypt Ivory (#F5C7C7)
        backdropColor  = { 0.05, 0.03, 0.04, 0.95 }, -- Deep Charred Crypt Stone
        borderColor    = { 0.47, 0.11, 0.11, 1.0 },  -- Blood Crimson Crypt Iron (#791B1D)
        containerColor = { 0.12, 0.04, 0.05, 0.88 }, -- Crimson-Shadowed Inset
        tabSelected    = { 0.95, 0.25, 0.25, 1.0 },  -- Blazing Crimson Red
        tabNormal      = { 0.78, 0.60, 0.60, 1.0 },  -- Crypt Ash Slate
        dimTextColor   = { 0.55, 0.42, 0.42, 1.0 },  -- Dim Charred Crypt Stone
    },
    atlases        = {
        headerBanner        = "Maw-tooltip-topper",
        lootCard            = "LootToast-Maw",
        corruptedOverlay    = nil,
    },
    window         = {
        style       = "fallensanctum_custom",
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
        backdropColor = { 0.06, 0.03, 0.04, 0.85 },
        borderColor   = { 0.45, 0.12, 0.12, 1.0 },
        sparkColor    = { 0.114, 0.949, 0.776, 1.0 },
        castbar       = {
            iconBorderColor = { 0.55, 0.15, 0.15, 1.0 },
            sparkColor      = { 0.114, 0.949, 0.776, 1.0 },
        },
    },
}

sfui.theme.AttachSliceTheme(fallenSanctumTheme, {
    mediaPath        = FALLENSANCTUM_MEDIA,
    layerKey         = "sfuiFallenSanctumLayers",
    containerKey     = "sfuiFallenSanctumContainer",
    headerKey        = "sfuiFallenSanctumHeader",
    isBackdropActive = sfui.theme.IsFallenSanctumBackdropActive,
    backdropAlpha    = 0.88,
    frameSlices      = FRAME_SLICES,
    paperSlices      = PAPER_SLICES,
    statsSlices      = STATS_SLICES,
    topOverlay       = { w = 410, h = 82, y = 23 },
    sideMode         = "fallensanctum",
    aliases          = { "sanctum", "torghast" },
})
