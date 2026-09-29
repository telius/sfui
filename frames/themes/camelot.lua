local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/camelot.lua
--  Camelot Heavy Bronze Theme Definition
-- ══════════════════════════════════════════════════════════════════════════════

sfui.theme.RegisterTheme({
    id             = "camelot",
    name           = "Camelot Heavy Bronze",
    desc           = "Sculpted cast-bronze metalwork, ornate corner brackets, warm charcoal slate, and cream gold.",
    clientTag      = "classic",
    autoDetect     = function()
        -- Auto-detect selects Camelot on Classic Forever / Camelot beta
        return sfui.isForever or (sfui.compat and sfui.compat.is_wow_forever)
    end,
    colors         = {
        id             = "camelot",
        name           = "Camelot Heavy Bronze",
        highlightColor = { 0.82, 0.65, 0.32, 1.0 }, -- Burnished Gold (#D1A652)
        accentColor    = { 0.95, 0.85, 0.55, 1.0 }, -- Warm Radiant Gold (#F2D98C)
        headerColor    = { 1.00, 0.90, 0.62, 1.0 }, -- Ornate Cream Gold
        backdropColor  = { 0.08, 0.07, 0.06, 0.94 }, -- Dark Warm Charcoal Slate
        borderColor    = { 0.00, 0.00, 0.00, 0.0 },  -- Borderless (No flat golden lines!)
        metalBottomColor = { 0.82, 0.65, 0.32, 1.0 }, -- Burnished Antique Bronze for bottom bar
        containerColor = { 0.06, 0.05, 0.04, 0.88 }, -- Deep Inset Bronze Brown
        tabSelected    = { 0.95, 0.85, 0.55, 1.0 },  -- Radiant Gold
        tabNormal      = { 0.78, 0.70, 0.55, 1.0 },  -- Muted Parchment Tan
        dimTextColor   = { 0.65, 0.58, 0.45, 1.0 },  -- Warm Muted Umber
    },
    atlases        = {
        frameBorderNative   = "heavybronze-frame-basic",
        frameBackdropNative = "heavybronze-frame-background",
        cornerTLNative      = "heavybronze-horz-cornerbracket-TL",
        cornerTRNative      = "heavybronze-horz-cornerbracket-TR",
        cornerBLNative      = "heavybronze-horz-cornerbracket-BL",
        cornerBRNative      = "heavybronze-horz-cornerbracket-BR",
        cornerTLFallback    = "RecruitAFriend_RewardPane_CornerBracket_LeftTop",
        cornerTRFallback    = "RecruitAFriend_RewardPane_CornerBracket_RightTop",
        cornerBLFallback    = "RecruitAFriend_RewardPane_CornerBracket_LeftBottom",
        cornerBRFallback    = "RecruitAFriend_RewardPane_CornerBracket_RightBottom",
        headerBanner        = "UI-Character-Info-Title",
        closeNormal         = "RedButton-Exit",
        closePressed        = "RedButton-exit-pressed",
        closeDisabled       = "RedButton-Exit-Disabled",
        closeHighlight      = "RedButton-Highlight",
        closeMini           = "RedButton-MiniCondense",
        closeMiniPress      = "RedButton-MiniCondense-pressed",
        closeMiniDis        = "RedButton-MiniCondense-disabled",
    },
    window         = {
        style       = "bronze",
    },
    header         = {
        style       = "banner",
        bannerAtlas = "UI-Character-Info-Title",
        height      = 24,
    },
    closeButton    = {
        style       = "atlas",
        atlas       = "RedButton-Exit",
    },
})
