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
    barTexture     = "Blizzard Nameplate",
    autoDetect     = function()
        -- Auto-detect selects Camelot on Camelot beta / Classic
        return (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot)) and sfui.theme.IsCamelotSupported()
    end,
    isSupported    = function()
        return sfui.theme.IsCamelotSupported()
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
        lootCard            = "UI-Character-Info-OutfitCard",
        lootCardHover       = "UI-Character-Info-OutfitCard-Hover",
        lootIconFrame       = "UI-Character-Info-OutfitIcon-Frame",
        lootGearSlot        = "UI-Character-Info-GearSlot",
        lootBankSlot        = "bank-frame-item-slotframe",
        buttonNormal        = "common-dropdown-c-button",
        buttonHover         = "common-dropdown-c-button-hover-1",
        buttonPressed       = "common-dropdown-c-button-pressed-1",
        buttonPressedHover  = "common-dropdown-c-button-pressedhover-1",
        buttonDisabled      = "common-dropdown-c-button-disabled",
        buttonFallback      = "common-dropdown-c-button",
        buttonHoverFallback = "common-dropdown-c-button-hover-1",
        buttonPressedFallback = "common-dropdown-c-button-pressed-1",
        buttonAHNormal      = "auctionhouse-nav-button",
        buttonAHSelected    = "auctionhouse-nav-button-select",
        buttonAHHighlight   = "auctionhouse-nav-button-highlight",
    },
    textures       = {
        buttonAHBgFile      = "Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg",
        buttonAHHighlightFile = "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight",
    },
    button         = {
        style       = "auctionhouse", -- Default Auction House beveled buttons with blue hover glow and gold selection outline
        options     = { "auctionhouse", "flat" },
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
    lootfeed       = {
        style       = "outfit_card",
    },
    -- ─── Bar / StatusBar Theming ───────────────────────────────────────────────
    -- Each key matches a "barType" string used by sfui.theme.RegisterBar / ApplyStatusBarStyle.
    -- Colors follow the Camelot Heavy Bronze palette:
    --   • backdropColor  : deep warm charcoal (near-black, slight amber warmth)
    --   • borderColor    : burnished bronze, 1-pixel edge
    bars           = {
        style      = "castbar", -- default bar style for Camelot: "inset" (Dark Inset Well) | "bezel" | "darkbronze" | "castbar" | "heavy" | "thin" | "glow"
        texture    = "Blizzard Nameplate",
        health     = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 }, -- Near-black charcoal, very slight amber
            borderColor   = { 0.14, 0.10, 0.06, 0.98 }, -- Dark antique bronze / deep charcoal
            borderSize    = 1,
            cornerSize    = 8,
        },
        power      = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 6,
        },
        secondary  = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 6,
        },
        rune       = {
            backdropColor = { 0.06, 0.05, 0.04, 0.90 },
            borderColor   = { 0.14, 0.10, 0.06, 0.95 },
            borderSize    = 1,
            cornerSize    = 5,
        },
        vigor      = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 6,
        },
        mountspeed = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 6,
        },
        threat     = {
            backdropColor = { 0.06, 0.04, 0.03, 0.92 },
            borderColor   = { 0.16, 0.11, 0.07, 0.98 },
            borderSize    = 1,
            cornerSize    = 4,
        },
        castbar    = {
            backdropColor    = { 0.05, 0.04, 0.03, 0.92 },
            borderColor      = { 0.14, 0.10, 0.06, 0.98 },
            borderSize       = 1,
            cornerSize       = 8,
            iconBorderColor  = { 0.28, 0.20, 0.10, 1.0 },
            sparkColor       = { 1.0,  0.85, 0.55, 1.0  }, -- Radiant gold spark
        },
        swing      = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 5,
        },
        target     = {
            backdropColor = { 0.05, 0.04, 0.03, 0.92 },
            borderColor   = { 0.14, 0.10, 0.06, 0.98 },
            borderSize    = 1,
            cornerSize    = 6,
        },
    },
})
