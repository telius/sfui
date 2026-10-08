local addonName, addon = ...
sfui = sfui or {}

sfui.config = {
    -- addon metadata
    title = "|cff6600ffsf|rui |cff6600ffgfy|r edition",
    version = "0.0.0", -- Set dynamically from TOC during ADDON_LOADED
    prefix = "|cff6600ffsfui:|r",

    -- general appearance
    font = "GameFontNormal",
    font_small = "GameFontNormalSmall",
    font_large = "GameFontNormalLarge",
    font_highlight = "GameFontHighlight",
    header_color = { 1, 1, 1 },
    throttle = {
        health = 0.05,
        power = 0.05,
        absorb = 0.1,
        visibility = 0.1,
    },
    textures = {
        white = "Interface/Buttons/WHITE8X8",
        tooltip = "Interface/Tooltips/UI-Tooltip-Background",
        gold_icon = "Interface\\MoneyFrame\\UI-GoldIcon",
    },

    -- addon-wide color palette
    colors = {
        purple = { 0.4, 0, 1 }, -- #6600FF (Highlight Color)
        cyan = { 0, 1, 1 },     -- #00FFFF (Text Color)
        magenta = { 1, 0, 1 },  -- #FF00FF
        white = { 1, 1, 1 },
        black = { 0, 0, 0 },
        gray = { 0.2, 0.2, 0.2 }, -- Dark gray
        border = { 0, 0, 0 },     -- Black for borders
    },

    appearance = {
        highlightColor = { 0.4, 0.0, 1.0, 1 }, -- #6600FF
        accentColor = { 0, 1, 1, 1 },          -- #00FFFF
        white = { 1, 1, 1, 1 },
        backdropColor = { 0.05, 0.05, 0.05, 0.8 },
        borderColor = { 0, 0, 0, 1 },
        widgetBackdropColor = { 0.2, 0.2, 0.2, 1 }, -- For checkboxes/buttons
        editBoxColor = { 0.15, 0.15, 0.15, 1 },
        sliderBackdropColor = { 0.1, 0.1, 0.1, 1 },
        lockColor = { 0.5, 0, 0, 0.5 },
        errorColor = { 1, 0.2, 0.2, 1 },
        goldColor = { 1, 0.82, 0, 1 },
        dimTextColor = { 0.6, 0.6, 0.6, 1 },
        addonIcon = "Interface/AddOns/sfui/icon.png",
    },

    -- theme configuration
    theme = {
        mode = "auto", -- "auto" (detects Camelot on Forever/Classic, Modern on Retail), "camelot", "modern"
        cornerBrackets = true,
        texturedBackdrop = true,
        minimapArt = true,               -- Camelot only: preserve brass compass & day/night dial (modern theme does not touch minimap)
        lootfeedStyle = "architectural", -- Camelot only: "architectural" (Option A: charcoal slate & corner brackets) or "outfit_card" (Option B: sculpted card)
        barStyle = "castbar",            -- Camelot only: "inset" (Dark Inset Well), "bezel", "darkbronze", "castbar" (1:1 Black Replica), "heavy", "thin", "glow"
        buttonStyle = "auctionhouse",    -- Camelot only: "auctionhouse" (Default: Auction House beveled buttons with blue hover glow & gold selection outline) or "flat" (Option: clean flat dark buttons)
    },

    -- shared settings for icon bars
    widget_bar = {
        icon_size = 32,
        icon_spacing = 5,
        label_offset_y = -2,
        label_color = { 1, 1, 1 },
    },

    spec_colors = {
        -- Death Knight
        [250] = { 0.77, 0.12, 0.23, 1 },     -- Blood
        [251] = { 0.0, 1.0, 1.0, 1 },        -- Frost
        [252] = { 0.0, 1.0, 0.0, 1 },        -- Unholy
        -- Demon Hunter
        [577] = { 0.635, 1.0, 0.0, 1 },      -- Havoc
        [581] = { 0.635, 1.0, 0.0, 1 },      -- Vengeance
        [1480] = { 0.788, 0.259, 0.992, 1 }, -- Devourer
        -- Druid
        [102] = { 0.40, 0.75, 1.00, 1 },     -- Balance (Moonfire)
        [103] = { 1.00, 0.80, 0.15, 1 },     -- Feral (Cat Amber)
        [104] = { 0.85, 0.25, 0.25, 1 },     -- Guardian (Bear Crimson)
        [105] = { 0.20, 0.80, 0.20, 1 },     -- Restoration (Emerald Green)
        [1484] = { 1.00, 1.00, 1.00, 1 },    -- Classic / Vanilla Base Druid (Mana / Humanoid)
        [14841] = { 0.40, 0.75, 1.00, 1 },   -- Camelot Balance (Moonfire)
        [14842] = { 1.00, 0.80, 0.15, 1 },   -- Camelot Feral (Cat Amber)
        [14843] = { 0.20, 0.80, 0.20, 1 },   -- Camelot Restoration (Emerald Green)
        [14844] = { 0.85, 0.25, 0.25, 1 },   -- Camelot Guardian (Bear Crimson)
        -- Evoker
        [1467] = { 0.20, 0.58, 0.50, 1 },    -- Devastation
        [1468] = { 0.20, 0.58, 0.50, 1 },    -- Preservation
        [1473] = { 0.81, 0.54, 0.27, 1 },    -- Augmentation
        -- Hunter
        [253] = { 0.67, 0.83, 0.45, 1 },     -- Beast Mastery
        [254] = { 0.67, 0.83, 0.45, 1 },     -- Marksmanship
        [255] = { 0.67, 0.83, 0.45, 1 },     -- Survival
        [1485] = { 0.67, 0.83, 0.45, 1 },    -- Classic / Vanilla Base Hunter
        [14851] = { 0.67, 0.83, 0.45, 1 },   -- Camelot Beast Mastery
        [14852] = { 0.67, 0.83, 0.45, 1 },   -- Camelot Marksmanship
        [14853] = { 0.67, 0.83, 0.45, 1 },   -- Camelot Survival
        -- Mage
        [62] = { 0.25, 0.78, 0.92, 1 },      -- Arcane
        [63] = { 0.25, 0.78, 0.92, 1 },      -- Fire
        [64] = { 0.25, 0.78, 0.92, 1 },      -- Frost
        [1482] = { 0.25, 0.78, 0.92, 1 },    -- Classic / Vanilla Base Mage
        [14821] = { 0.25, 0.78, 0.92, 1 },   -- Camelot Arcane
        [14822] = { 0.25, 0.78, 0.92, 1 },   -- Camelot Fire
        [14823] = { 0.25, 0.78, 0.92, 1 },   -- Camelot Frost
        -- Monk
        [268] = { 0.90, 0.60, 0.15, 1 },     -- Brewmaster
        [269] = { 0.40, 0.80, 1.00, 1 },     -- Windwalker
        [270] = { 0.00, 1.00, 0.59, 1 },     -- Mistweaver
        -- Paladin
        [65] = { 0.96, 0.55, 0.73, 1 },      -- Holy
        [66] = { 1.00, 0.75, 0.20, 1 },      -- Protection
        [70] = { 0.96, 0.55, 0.73, 1 },      -- Retribution
        [1486] = { 0.96, 0.55, 0.73, 1 },    -- Classic / Vanilla Base Paladin
        [14861] = { 0.96, 0.55, 0.73, 1 },   -- Camelot Holy
        [14862] = { 1.00, 0.75, 0.20, 1 },   -- Camelot Protection
        [14863] = { 0.96, 0.55, 0.73, 1 },   -- Camelot Retribution
        -- Priest
        [256] = { 1.00, 1.00, 1.00, 1 },     -- Discipline
        [257] = { 1.00, 1.00, 1.00, 1 },     -- Holy
        [258] = { 0.40, 0.00, 1.00, 1 },     -- Shadow
        [1487] = { 1.00, 1.00, 1.00, 1 },    -- Classic / Vanilla Base Priest
        [14871] = { 1.00, 1.00, 1.00, 1 },   -- Camelot Discipline
        [14872] = { 1.00, 1.00, 1.00, 1 },   -- Camelot Holy
        [14873] = { 0.40, 0.00, 1.00, 1 },   -- Camelot Shadow
        -- Rogue
        [259] = { 1.00, 0.96, 0.41, 1 },     -- Assassination
        [260] = { 1.00, 0.96, 0.41, 1 },     -- Outlaw
        [261] = { 1.00, 0.96, 0.41, 1 },     -- Subtlety
        [1488] = { 1.00, 0.96, 0.41, 1 },    -- Classic / Vanilla Base Rogue
        [14881] = { 1.00, 0.96, 0.41, 1 },   -- Camelot Assassination
        [14882] = { 1.00, 0.96, 0.41, 1 },   -- Camelot Combat
        [14883] = { 1.00, 0.96, 0.41, 1 },   -- Camelot Subtlety
        -- Shaman
        [262] = { 0.00, 0.44, 0.87, 1 },     -- Elemental
        [263] = { 0.00, 0.44, 0.87, 1 },     -- Enhancement
        [264] = { 0.00, 0.44, 0.87, 1 },     -- Restoration
        [1489] = { 0.00, 0.44, 0.87, 1 },    -- Classic / Vanilla Base Shaman
        [14891] = { 0.00, 0.44, 0.87, 1 },   -- Camelot Elemental
        [14892] = { 0.00, 0.44, 0.87, 1 },   -- Camelot Enhancement
        [14893] = { 0.00, 0.44, 0.87, 1 },   -- Camelot Restoration
        -- Warlock
        [265] = { 0.53, 0.53, 0.93, 1 },     -- Affliction
        [266] = { 0.71, 0.26, 0.93, 1 },     -- Demonology
        [267] = { 0.635, 1.0, 0.0, 1 },      -- Destruction
        [1490] = { 0.53, 0.53, 0.93, 1 },    -- Classic / Vanilla Base Warlock
        [14901] = { 0.53, 0.53, 0.93, 1 },   -- Camelot Affliction
        [14902] = { 0.71, 0.26, 0.93, 1 },   -- Camelot Demonology
        [14903] = { 0.635, 1.0, 0.0, 1 },    -- Camelot Destruction
        -- Warrior
        [71] = { 1.00, 0.00, 0.00, 1 },      -- Arms
        [72] = { 1.00, 0.00, 0.00, 1 },      -- Fury
        [73] = { 1.00, 0.00, 0.00, 1 },      -- Protection
        [1491] = { 1.00, 0.00, 0.00, 1 },    -- Classic / Vanilla Base Warrior
        [14911] = { 1.00, 0.00, 0.00, 1 },   -- Camelot Arms
        [14912] = { 1.00, 0.00, 0.00, 1 },   -- Camelot Fury
        [14913] = { 1.00, 0.00, 0.00, 1 },   -- Camelot Protection
    },

    -- Secondary stat palette for loot & gear highlighting
    stat_colors = {
        haste       = { 0.2, 0.85, 0.3, 1.0 },
        crit        = { 1.0, 0.45, 0.1, 1.0 },
        mastery     = { 0.75, 0.4, 1.0, 1.0 },
        versatility = { 0.2, 0.65, 1.0, 1.0 },
    },

    -- Default panel settings for tracked icons
    cooldown_panel_defaults = {
        left = {
            name = "Left",
            anchorPoint = "TOPLEFT",
            growthH = "Right",
            growthV = "Down",
            x = -425,
            y = 295,
            size = 40,
            spacing = 0,
            columns = 4,
            enabled = true,
            hideMounted = true,
        },
        right = {
            name = "Right",
            anchorPoint = "TOPRIGHT",
            growthH = "Left",
            growthV = "Down",
            x = 425,
            y = 295,
            size = 40,
            spacing = 0,
            columns = 4,
            enabled = true,
            hideMounted = true,
        },
        center_panel = {
            name = "CENTER",
            enabled = true,
            showBackground = true,
            backgroundAlpha = 0.5,
            x = 0,
            y = 0,
            size = 50,
            columns = 7,
            spacing = 4,
            spanWidth = true,
            placement = "center",
            growthH = "Center",
            anchorPoint = "TOP",
            growthV = "Down",
            anchorTo = "Health Bar",
            hideOOC = true,
            hideInVehicle = true,
            hideMounted = true,
        },
        utility = {
            name = "UTILITY",
            enabled = true,
            anchorPoint = "TOP", -- Anchors top of this panel to bottom of target
            growthH = "Center",
            growthV = "Down",
            x = 0,
            y = 0, -- Default position
            size = 32,
            spacing = 0,
            columns = 9,
            placement = "center",
            anchorTo = "CENTER",
            hideMounted = true,
        },
        -- Glow duration limit (seconds)
        glow_max_duration = 5.0,
    },

    -- Global defaults for icon panels (can be overridden per-panel or per-icon)
    -- These provide fallback values for visual effect settings (like glows)
    icon_panel_global_defaults = {
        enableMasque = false,
        -- Visibility
        hideOOC = false,
        hideMounted = true,
        hideInVehicle = true,
        showTooltips = false, -- Default to false as per user request

        -- Ready Glow (when spell is off cooldown/available)
        readyGlow = true,           -- Enable glow when ready
        glowType = "autocast",      -- Options: pixel, autocast, proc, button
        useSpecColor = true,        -- Use specialization-based color for glows
        glowColor = { 1, 1, 0, 1 }, -- Yellow by default
        glowScale = 2.0,
        glowIntensity = 1.0,
        glowSpeed = 0.5,         -- User request: 0.5
        glowLines = 4,           -- Pixel glow: number of particles
        glowThickness = 1,       -- Pixel glow: line thickness
        glowParticles = 4,       -- Autocast glow: particle count
        glow_max_duration = 5.0, -- Max seconds to show glow

        -- Cooldown Visual State
        cooldownDesat = true,    -- Desaturate while on cooldown
        alphaOnCooldown = 1.0,   -- Alpha transparency while on cooldown (1.0 = Opaque)
        useResourceCheck = true, -- Enable mana/power based tinting
        showBackground = false,  -- Default backgrounds to OFF
        backgroundAlpha = 0.5,   -- 50% transparency for the background

        -- Text Display
        textEnabled = true,         -- Show countdown numbers on icons
        textColor = { 1, 1, 1, 1 }, -- White text

        -- Hotkey Display
        showHotkeys = false,       -- Show keybinding text on icons
        hotkeyFontSize = 12,       -- Font size for hotkey text
        hotkeyAnchor = "TOPLEFT",  -- Anchor point (TOPLEFT, TOPRIGHT, BOTTOMLEFT, BOTTOMRIGHT, CENTER)
        hotkeyOutline = "OUTLINE", -- Font outline (OUTLINE, THICKOUTLINE, or "")

        -- Icon Style
        showBorder = true,  -- Show 2px black border around icons
        squareIcons = true, -- Crop round icon edges to square

        -- Panel Visibility
        visibility = "always", -- "always", "combat", "noCombat"
    },

    options_panel = {
        width = 700,
        height = 700,
        backdrop_color = { 0.05, 0.05, 0.05, 0.8 },
        tabs = {
            width = 100,
            height = 30,
            color = { 0.4, 0.0, 1.0, 1 },           -- #6600FF for unselected tabs
            selected_color = { 0, 1, 1, 1 },        -- #00FFFF for selected tab
            highlight_color = { 0.6, 0.6, 0.6, 1 }, -- Medium gray for hover
        },
        icon_border_color = { 0, 0, 0, 1 },
    },

    tracked_options_layout = {
        ROW_HEIGHT = 30,
        COL_WIDTH = 135,
        PADDING = 5,
        HEADER_Y = 20,
    },

    currency_frame = {
        width = 200,
        height = 70,
    },

    gear = {
        updateDelay = 3,
        maxScaledILvl = 1000,
    },

    experience = {
        enabled = true,
        width = 460,
        height = 14,
        pos = {
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = 0,
            y = 4,
        },
        showRested = true,
        showQuestPreview = true,
        showTicks = true,
        tickCount = 20,
        showFloatingText = true,
        useClassColor = false,
        showDualBars = true,            -- Show both XP and Reputation bars stacked when tracking a faction
        repHeight = 12,                 -- Height of the stacked reputation bar
        repOnTop = true,                -- Dock reputation bar above XP bar
        showText = "MOUSEOVER",         -- "ALWAYS", "MOUSEOVER", "NEVER"
        textFormat = "PERCENT_CURRENT", -- "PERCENT_CURRENT", "PERCENT", "REMAINING", "FRACTION"
        showRate = true,
        showTTL = true,
        autoReputation = true, -- Switch to reputation if max level or tracking faction
        autoSwitchRepOnGain = false, -- Automatically activate and switch reputation bar when reputation is gained
        hideBlizzardBar = true,
        colors = {
            xp = { 0.58, 0.0, 0.82, 1.0 },             -- Fallback active xp color (purple)
            rested = { 0.0, 0.65, 0.90, 0.60 },        -- Rested bonus overlay (cyan/sky blue)
            questPreview = { 0.96, 0.65, 0.12, 0.70 }, -- Completed quest turn-in preview (amber/gold)
            reputation = { 0.0, 0.60, 0.35, 1.0 },     -- Fallback reputation green
        },
    },

    lootfeed = {
        enabled = true,
        width = 320,
        rowHeight = 34,
        maxRows = 10,
        displayDuration = 8.0,
        fadeDuration = 0.5,
        growDirection = "DOWN",  -- "DOWN" or "UP"
        minItemQuality = 0,      -- 0 = Poor, 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Epic (Player)
        partyMinItemQuality = 2, -- 0 = Poor, 1 = Common, 2 = Uncommon, 3 = Rare, 4 = Epic (Party Members)
        trackMoney = true,
        trackCurrency = true,
        trackXP = true,
        trackReputation = true,
        trackSkills = true,
        trackPartyLoot = true,
        showTotalCurrency = true,
        showTotalMoney = true,
        showSellPrice = true,
        pos = {
            point = "TOPRIGHT",
            relativePoint = "TOPRIGHT",
            x = -320,
            y = -200,
        },
    },

    item_frame = {
        width = 200,
        height = 70,
    },

    triage = {
        enabled = true,
        threshold = 1,                 -- Trigger when free regular slots <= threshold (0, 1, or 2)
        checkConsumables = true,       -- Evaluate consumables when no greys are found
        protectFoodWater = true,       -- Protect food/water matching player's level tier
        soundAlert = true,             -- Play sound when triage prompt appears
        deleteSoulShards = false,      -- Opt-in: show triage prompt for excess soul shards
        maxSoulShards = 20,            -- Maximum soul shards to keep (1 to 32)
        preserveSoulBag = true,        -- If true, preserve shards in dedicated soul bags and only prune regular bag spillover
        soulShardMode = "prompt",      -- "prompt" (triage prompt button) or hardware click / macro (/click SfuiPurgeSoulShards)
        soulShardChat = true,          -- Print consolidated single-line summary to chat when pruning finishes
        pos = {
            point = "BOTTOM",
            relativePoint = "BOTTOM",
            x = 0,
            y = 220,
        },
    },

    cvars_on_load = {
        { name = "autoLootDefault", value = 1 },
        { name = "turnspeed",       value = 300 },
    },

    powerBar = {
        enabled = true,
        width = 300,
        height = 10,
        pos = { x = 0, y = 285 },
        useClassColor = true,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
        -- Retail-only: Specs where primary mana bar is hidden because the spec uses alternative resources.
        -- In Camelot / Classic, the powerbar is never hidden on any spec.
        hiddenSpecs = {
            [1467] = true, -- Devastation Evoker
            [1473] = true, -- Augmentation Evoker
            [265] = true,  -- Affliction Warlock
            [266] = true,  -- Demonology Warlock
            [267] = true,  -- Destruction Warlock
            [63] = true,   -- Fire Mage
            [64] = true,   -- Frost Mage
            [70] = true,   -- Retribution Paladin
        },
    },

    castBar = {
        enabled = true,
        width = 300,
        height = 20,
        pos = { x = 0, y = 150 },
        color = { 1, 1, 1 },
        channelColor = { 0, 1, 0 },
        empoweredColor = { 0.4, 0, 1 },
        interruptedColor = { 1, 0, 0 },
        empoweredStageColors = {
            { 0, 1,   0 }, -- stage 1: green
            { 1, 1,   0 }, -- stage 2: yellow
            { 1, 0.5, 0 }, -- stage 3: orange
            { 1, 0,   0 }, -- stage 4: red
        },
        alpha = 1,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.7 },
        },
        updateThrottle = 0.05,
        spark = {
            width = 20,
            heightMultiplier = 2.5
        },
        iconSize = 24,
        icon = {
            offset = -5
        }
    },

    targetCastBar = {
        enabled = true,
        width = 300,
        height = 50,
        pos = { x = 0, y = 480 },
        color = { 1, 1, 1 },                       -- Interruptible (White)
        nonInterruptibleColor = { 0.2, 0.2, 0.2 }, -- Dark Grey
        interruptedColor = { 1, 0, 0 },
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
    },

    instantCastBar = {
        enabled = true,
        width = 300,
        height = 15,
        channelColor = { 0, 1, 0 }, -- Green for GCD
        iconSize = 19,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
    },

    targetBar = {
        enabled = true,
        width = 230,
        height = 13,
        powerHeight = 3,
        pos = { point = "TOP", x = 0, y = -35 },
        backdrop = {
            padding = 1,
            color = { 0, 0, 0, 0.5 },
        },
        auras = {
            size = 18,
            spacing = 2,
            maxBuffs = 8,
            maxDebuffs = 8,
        },
    },

    threatBar = {
        enabled = true,
        height = 4,
        backdrop = {
            padding = 1,
            color = { 0, 0, 0, 0.5 },
        },
    },

    healthBar = {
        enabled = true,
        width = 300,
        height = 20,
        color = { 0.2, 0.2, 0.2 }, -- Dark Grey
        pos = { x = 0, y = 300 },
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 }, -- Black/Transparent
        },
    },

    swingBar = {
        enabled = true,
        width = 300,
        height = 8,
        spacing = 2,
        colors = {
            mainHand = { 1, 1, 1, 1 },          -- Light Cyan/Blue
            offHand  = { 1.0, 0.65, 0.2, 1.0 }, -- Amber/Orange
            ranged   = { 0.3, 0.9, 0.4, 1.0 },  -- Green
            wand     = { 0.4, 0.0, 1.0, 1.0 },  -- #6600ff Purple (Warlock / Mage / Priest)
        },
        backdrop = {
            padding = 1,
            color = { 0, 0, 0, 0.6 },
        },
    },

    secondaryPowerBar = {
        enabled = true,
        width = 240,
        height = 15,
        comboPointHeight = 8,
        useClassColor = true,
        fontSize = 18,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
        -- Retail-only: Specs where secondary power bar is suppressed
        hiddenSpecs = {
            [258] = true, -- Shadow Priest
            [270] = true, -- Mistweaver Monk
            [262] = true, -- Elemental Shaman
        },
    },

    vigorBar = {
        enabled = true,
        width = 240,
        height = 15,
        color = { 0.4, 0, 1 },
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
        icons = {
            gap = 5,
            offsetY = -5,
            sideOffset = 5,
        },
    },

    mountSpeedBar = {
        enabled = true,
        width = 240,
        height = 10,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
    },

    trackedIcons = {
        left = { x = -200, y = 0 },
        right = { x = 200, y = 0 },
    },

    barTexture = "Interface/Buttons/WHITE8X8",

    blizzard_bar_textures = {
        ["Flat"]                             = "Interface/Buttons/WHITE8X8",
        ["Blizzard"]                         = "Interface/TargetingFrame/UI-StatusBar",
        ["Blizzard Nameplate"]               = "UI-HUD-CoolDownManager-Bar",
        ["Blizzard Player Health"]           = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health",
        ["Blizzard Player Mana"]             = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
        ["Blizzard Target Health"]           = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health",
        ["Blizzard Target Mana"]             = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana",
        ["Blizzard Party Health"]            = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health",
        ["Blizzard Raid Fill"]               = "RaidFrame-Hp-Fill",
        ["Blizzard Raid Resource"]           = "_RaidFrame-Resource-Fill",
        ["Blizzard Casting Bar"]             = "ui-castingbar-filling-standard",
        ["Blizzard Challenge Mode"]          = "ChallengeMode-TimerFill",
        ["Blizzard Honor Fill"]              = "_honorsystem-bar-fill",
        ["Blizzard Conquest Fill"]           = "_pvpqueue-conquestbar-fill-yellow",
        ["Blizzard Experience Fill"]         = "UI-HUD-ExperienceBar-Fill-Prediction",
        ["Blizzard Activities"]              = "activities-bar-fill",
        ["Blizzard Target Bar"]              = "Interface/TargetingFrame/UI-TargetingFrame-BarFill",
        ["Blizzard Character Skills Bar"]    = "Interface/PaperDollInfoFrame/UI-Character-Skills-Bar",
        ["Blizzard Raid Bar"]                = "Interface/RaidFrame/Raid-Bar-Hp-Fill",
        ["Blizzard Raid Resource (Classic)"] = "Interface/RaidFrame/Raid-Bar-Resource-Fill",
        ["Blizzard Raid Health (Classic)"]   = "Interface/RaidFrame/UI-RaidFrame-HealthBar",
        ["Blizzard Shield Fill"]             = "Interface/RaidFrame/Shield-Fill",
        ["Blizzard Absorb Fill"]             = "Interface/RaidFrame/Absorb-Fill",
        ["Blizzard Professions"]             = "Interface/Spellbook/Professions-Progress-Fill",
        ["Blizzard Archaeology"]             = "Interface/Archeology/Arch-Progress-Fill",
        ["Blizzard Reputation"]              = "Interface/PaperDollInfoFrame/UI-Character-ReputationBar",
        ["Blizzard PVP Honor (Classic)"]     = "Interface/PVPFrame/pvpqueue-sidebar-honorbar-fill",
    },

    barTextures = {
        { text = "Flat",                             value = "Interface/Buttons/WHITE8X8" },
        { text = "Blizzard Nameplate",               value = "UI-HUD-CoolDownManager-Bar" },
        { text = "Blizzard Player Health",           value = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health" },
        { text = "Blizzard Player Mana",             value = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana" },
        { text = "Blizzard Target Health",           value = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health" },
        { text = "Blizzard Target Mana",             value = "UI-HUD-UnitFrame-Target-PortraitOn-Bar-Mana" },
        { text = "Blizzard Party Health",            value = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health" },
        { text = "Blizzard Raid Fill",               value = "RaidFrame-Hp-Fill" },
        { text = "Blizzard Raid Resource",           value = "_RaidFrame-Resource-Fill" },
        { text = "Blizzard Casting Bar",             value = "ui-castingbar-filling-standard" },
        { text = "Blizzard Challenge Mode",          value = "ChallengeMode-TimerFill" },
        { text = "Blizzard Honor Fill",              value = "_honorsystem-bar-fill" },
        { text = "Blizzard Conquest Fill",           value = "_pvpqueue-conquestbar-fill-yellow" },
        { text = "Blizzard Experience Fill",         value = "UI-HUD-ExperienceBar-Fill-Prediction" },
        { text = "Blizzard Activities",              value = "activities-bar-fill" },
        { text = "Blizzard",                         value = "Interface/TargetingFrame/UI-StatusBar" },
        { text = "Blizzard Target Bar",              value = "Interface/TargetingFrame/UI-TargetingFrame-BarFill" },
        { text = "Blizzard Character Skills Bar",    value = "Interface/PaperDollInfoFrame/UI-Character-Skills-Bar" },
        { text = "Blizzard Raid Bar",                value = "Interface/RaidFrame/Raid-Bar-Hp-Fill" },
        { text = "Blizzard Raid Resource (Classic)", value = "Interface/RaidFrame/Raid-Bar-Resource-Fill" },
        { text = "Blizzard Raid Health (Classic)",   value = "Interface/RaidFrame/UI-RaidFrame-HealthBar" },
        { text = "Blizzard Shield Fill",             value = "Interface/RaidFrame/Shield-Fill" },
        { text = "Blizzard Absorb Fill",             value = "Interface/RaidFrame/Absorb-Fill" },
        { text = "Blizzard Professions",             value = "Interface/Spellbook/Professions-Progress-Fill" },
        { text = "Blizzard Archaeology",             value = "Interface/Archeology/Arch-Progress-Fill" },
        { text = "Blizzard Reputation",              value = "Interface/PaperDollInfoFrame/UI-Character-ReputationBar" },
        { text = "Blizzard PVP Honor (Classic)",     value = "Interface/PVPFrame/pvpqueue-sidebar-honorbar-fill" },
    },

    absorbBarColor = { 0.4, 0.0, 1.0, 0.75 },

    minimap = {
        default_size = 220,
        defaultZoom = 0,
        button_bar = {
            spacing = 8,
            pad_x = 24,
            button_size = 20,
            defaultX = 0,
            defaultY = -25,
        },
    },

    barLayout = {
        spacing = 1,
    },

    merchant = {
        -- Grid layout
        grid = {
            rows = 10,
            cols = 3,
            item_width = 190,
            item_height = 45,
            spacing_x = 195,
            spacing_y = 50,
            offset_x = 15,
            offset_y = -40,
        },
        -- Frame dimensions
        frame = {
            width = 615,  -- 3 cols * 195 + padding
            height = 620, -- 10 rows * 50 + header/footer
        },
        -- Utility bar
        utility_bar = {
            height = 30,
            bottom_offset = 2,
            button_height = 22,
            button_small = 75,  -- buyback, filter buttons
            button_medium = 70, -- sell greys
            button_large = 110, -- housing filter
            spacing = 4,
        },
        -- Scrollbar
        scrollbar = {
            width = 6,
            right_offset = 5,
        },
        -- Currency display
        currency = {
            height = 20,
            bottom_offset = 35,
        },
        -- Button colors (references to colors table)
        button_colors = {
            filter_active = "purple",
            filter_inactive = "white",
            filter_hover = "cyan",
        },
        lootFilterState = 0,
    },

    automation = {
        auto_role_check = true,
        auto_sign_lfg = true,
        tooltip_alt_ids = true,
    },


    trackedBars = {
        -- Position anchor
        anchor = {
            point = "BOTTOM",
            x = -300,
            y = 300,
        },
        -- Visual settings
        width = 200,
        height = 20,
        attachedWidthMultiplier = 0.8, -- Multiplier for Health Bar width when acting as secondary bar
        attachedHeight = 20,           -- Standard height for attached bars
        icon_size = 20,
        icon_offset = -5,              -- Space between bar and icon
        spacing = 5,
        backdrop = {
            padding = 1,
            color = { 0, 0, 0, 0.5 },
        },
        -- Stack/Segment settings
        maxSegments = 10, -- Maximum number of stack segments to create
        defaultMaxStacks = 10,
        -- Font settings
        fonts = {
            standard = "GameFontNormalSmall",
            stackModeDurationSize = 14, -- Larger size for stack mode duration text
        },
        -- Performance settings
        updateThrottle = 0.05, -- OnUpdate throttle interval (~20fps)
        -- Special case overrides (by cooldownID)
        specialCases = {
            [9039] = { maxStacks = 12, spellID = 195181 },   -- Bone Shield (Death Knight)
            [18469] = { maxStacks = 100, spellID = 190456 }, -- Ignore Pain (Warrior)
        },
        -- Default visibility settings
        hideOOC = false,      -- Hide all bars when out of combat
        hideMounted = false,  -- Default to false for bars
        hideInVehicle = true, -- Hide all bars when in vehicle UI
        hideInactive = true,  -- Hide bars when cooldowns are inactive
        -- Default bar configuration per cooldown ID
        defaults = {
            [18469] = {                     -- Ignore Pain (Warrior)
                specID = 73,                -- Protection Warrior
                stackAboveHealth = true,    -- Attach to healthbar (secondary position)
                color = { 1, 0.533, 0, 1 }, -- Orange
                showStacksText = true,      -- Show stack count as duration text
            },
            [9039] = {                      -- Bone Shield (Death Knight)
                specID = 250,               -- Blood DK
                spellID = 195181,
                maxStacks = 12,
                stackAboveHealth = true,      -- Attach to healthbar
                stackMode = true,             -- Use stack count as bar value
                color = { 0, 0.8, 0.067, 1 }, -- Green
                showName = false,             -- Hide name
            },
        },
    },

    -- Demon Hunter Soul Fragments HUD
    soulFragments = {
        enabled = true,
        height = 18,
        cellGap = 1,
        fontSize = 14,
        showText = true,
        hideOOC = false,
        hideEmpty = false,
    },

    trackedOptionsWindow = {
        width = 800,
        height = 500,
    },

    -- Master's Hammer Specialization Nodes
    -- Organised by expansion version keys.
    masterHammer = {
        requiredRank = 26, -- Required trait rank for repair perks (Milestone 5 is unlocked at rank 26, 0 counts as a step too)
        defaultPosition = { x = 0, y = 0 },
        defaultColor = "00FFFF",
        [225660] = { -- Earthen Master's Hammer (The War Within)
            expansion = 10,
            expansionName = "The War Within",
            nodes = {
                ["HEAD"] = 99233,
                ["SHOULDER"] = 99232,
                ["CHEST"] = 99237,
                ["WRIST"] = 99228,
                ["HANDS"] = 99227,
                ["WAIST"] = 99229,
                ["LEGS"] = 99236,
                ["FEET"] = 99231,
                ["SHIELD"] = 99235,
                [0] = 99447,
                [1] = 99447,
                [6] = 99447, -- Axes/Polearms
                [4] = 99448,
                [5] = 99448, -- Maces
                [7] = 99450,
                [8] = 99450,
                [9] = 99450, -- Long Blades
                [15] = 99451,
                [13] = 99451 -- Short Blades
            }
        },
        [198254] = { -- Master's Hammer (Dragonflight)
            expansion = 9,
            expansionName = "Dragonflight",
            universalNode = 82244,
            nodes = {} -- Universal Hammer Control
        },
        [238020] = {   -- Thalassian Master Repair Hammer (Midnight)
            expansion = 11,
            expansionName = "Midnight",
            nodes = {
                ["HEAD"] = 104570,
                ["SHOULDER"] = 104569,
                ["CHEST"] = 104574,
                ["WRIST"] = 104565,
                ["HANDS"] = 104564,
                ["WAIST"] = 104566,
                ["LEGS"] = 104573,
                ["FEET"] = 104568,
                ["SHIELD"] = 104572,
                [0] = 104627,
                [1] = 104627,
                [6] = 104627, -- Axes/Polearms
                [4] = 104628,
                [5] = 104628, -- Maces
                [7] = 104630,
                [8] = 104630,
                [9] = 104630, -- Long Blades
                [15] = 104631,
                [13] = 104631 -- Short Blades
            }
        },
    },
    alts = {
        width = 1000,
        height = 650,
        columnWidth = 140,
        rowHeight = 25,
        headerHeight = 40,
        backdropColor = { 0.05, 0.05, 0.05, 0.9 },
        borderColor = { 0, 0, 0, 1 },
        highlightColor = { 0.4, 0, 1, 1 }, -- Purple
        expansion = {
            preyFactionID = 2764,          -- Midnight Season 2 Progress
            activeHuntCurrencyID = 3392,   -- Remnant of Anguish
        },
        showM0Dungeons = true,
        statusColors = {
            completed = { 0, 1, 1, 0.8 },      -- Cyan
            inProgress = { 0, 0.2, 0.2, 0.8 }, -- Dark Teal (Strict)
            available = { 0, 0, 0, 0.5 },      -- Black (Available)
            textCompleted = "|cff00ffff",
            textInProgress = "|cff003333",     -- Matching 0, 0.2, 0.2 hex approximately
            textAvailable = "|cff888888",
        },
    },

    worldevents = {
        enabled              = true,
        show_reminders_only  = true, -- only show events where a reminder is set
        show_ongoing         = false,
        max_upcoming_minutes = 60,
        max_events           = 5,
        show_time_left       = true,
    },

    questlog = {
        enabled = true,
        width = 280,
        posX = -4,
        posY = -4,
        sectionHeight = 20,
        questHeight = 20,
        objectiveHeight = 13,
        itemSize = 32,
        throttle = 0.35,
        defaultHidden = false,
        maxScreenHeight = 0.50,
        sections = {
            { id = "scenario",     label = "world event",  color = { 1.00, 0.60, 0.10 } },
            { id = "events",       label = "events",       color = { 0.90, 0.45, 0.90 } },
            { id = "important",    label = "important",    color = { 1.00, 0.40, 0.35 } },
            { id = "campaign",     label = "campaign",     color = { 0.90, 0.75, 0.10 } },
            { id = "meta",         label = "meta",         color = { 0.00, 1.00, 1.00 } },
            { id = "world",        label = "world quests", color = { 0.20, 0.85, 0.95 } },
            { id = "activities",   label = "activities",   color = { 0.35, 0.90, 0.40 } },
            { id = "zone",         label = "quests",       color = { 1.00, 1.00, 1.00 } },
            { id = "achievements", label = "achievements", color = { 0.85, 0.65, 0.35 } },
        },
    },

    -- ─── Mythic+ HUD ──────────────────────────────────────
    -- Settings for the native M+ timer/objectives frame (frames/quests/mythic.lua).
    -- Runtime overrides are stored in SfuiDB to survive UI reloads.
    mythic = {
        enabled = true, -- master toggle (user can opt-out in Options > objectives)
        width   = 280,  -- HUD frame width in pixels
        posX    = -4,   -- default TOPRIGHT x-offset from UIParent (matches quest log tracker)
        posY    = -4,   -- default TOPRIGHT y-offset from UIParent (matches quest log tracker)
    },

    -- ─── Vehicle Bar ──────────────────────────────────────
    -- Settings for the vehicle/override/possess bar (frames/bars/vehicle.lua).
    vehicle = {
        enabled = true,
        posX    = 0,  -- default horizontal offset (centered at bottom)
        posY    = 50, -- default vertical offset (+50px from bottom)
    },

    -- ─── Dungeon Portal Popup ────────────────────────────
    -- Settings for the group-filled teleport popup (frames/portals/portal_popup.lua).
    portalPopup = {
        enabled         = true,
        onlyWhenFull    = true, -- true: notify only when group reaches 5/5; false: also on join
        autoHideSecs    = 45,
        defaultPosition = { x = 0, y = 180 },
    },

    -- ─── Fishing Automation ──────────────────────────────
    -- Settings for single-key & double-click fishing (frames/automation/fishing.lua).
    fishing = {
        enabled             = true,
        doubleClick         = true,
        doubleClickSpeed    = 0.4,
        doubleClickForce    = false, -- allow when mounted
        enhanceSounds       = true,
        enhanceSoundsScale  = 1.0,
        softTarget          = true,
        recastOnDoubleClick = false,
        overrideLunker      = false,
    },

    -- ─── Companion Pet Manager ────────────────────────────
    -- Settings for companion pet auto-summon & rotation (frames/automation/pets.lua).
    pets = {
        enabled       = true,
        autoResummon  = true,
        rotationTimer = 720, -- Seconds (12 mins, 0 to disable)
        historySize   = 4,
    },

    -- ─── Hide & Mouseover Settings ────────────────────────
    -- Settings for action bars mouseover fading and Blizzard unitframe hiding (frames/hide.lua).
    hide = {
        actionbars_mouseover_enabled = true,
        actionbars_resting_alpha     = 0.0,
        actionbars_active_alpha      = 1.0,
        actionbars_fade_duration     = 0.2,

        -- Per-bar mouseover toggles
        actionbars_bar_main          = true,
        actionbars_bar_bar2          = true,
        actionbars_bar_bar3          = true,
        actionbars_bar_bar4          = true,
        actionbars_bar_bar5          = true,
        actionbars_bar_bar6          = true,
        actionbars_bar_bar7          = true,
        actionbars_bar_bar8          = true,
        actionbars_bar_pet           = true,
        actionbars_bar_stance        = true,
        actionbars_bar_possess       = true,

        -- Unit and HUD frame permanent hiding
        hide_player_frame            = false,
        hide_target_frame            = false,
        hide_pet_frame               = false,
        hide_focus_frame             = false,
        hide_micromenu               = false,
        hide_bagsbar                 = false,
        hide_totem_bar               = false,
    },

    -- ─── Totem Bar (Vanilla / Camelot only) ─────────────────────────
    -- Dedicated tracking bar for shaman totems (frames/bars/totembar.lua).
    totembar = {
        enabled         = true,
        size            = 36,
        spacing         = 4,
        colorByElement  = true,
        showTimerText      = true,
        showGlow           = true,
        castOrder          = { "Earth", "Fire", "Water", "Air" },
        resetTimer         = 15,
        showSequenceButton = false,
        pos                = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 88 },
        selectedTotems  = {
            Earth = "Stoneskin Totem",
            Fire  = "Searing Totem",
            Water = "Healing Stream Totem",
            Air   = "Windfury Totem",
        },
    },
}
