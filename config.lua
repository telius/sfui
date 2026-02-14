local addonName, addon = ...
sfui = sfui or {}
SfuiDB = SfuiDB or {}
SfuiDecorDB = SfuiDecorDB or {}

sfui.config = {
    -- addon metadata
    title = "|cff6600FFSF|rui |cff6600FFGFY|r edition",
    version = "0.0.0", -- Set dynamically from TOC during ADDON_LOADED

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
        gray = { 0.2, 0.2, 0.2 }, -- Dark gray for borders
    },

    -- shared settings for icon bars
    widget_bar = {
        icon_size = 50,
        icon_spacing = 5,
        label_offset_y = -2,
        label_color = { 1, 1, 1 },
    },

    -- custom spec colors (for example, to override defaults or add new ones)
    spec_colors = {
        -- Death Knight
        [250] = { r = 0.77, g = 0.12, b = 0.23 },     -- Blood
        [251] = { r = 0.0, g = 1.0, b = 1.0 },        -- Frost
        [252] = { r = 0.0, g = 1.0, b = 0.0 },        -- Unholy
        -- Demon Hunter
        [577] = { r = 0.635, g = 1.0, b = 0.0 },      -- Havoc
        [581] = { r = 0.64, g = 0.19, b = 0.79 },     -- Vengeance
        [1480] = { r = 0.788, g = 0.259, b = 0.992 }, -- Devourer (Official Blizzard UI Color)
        -- Druid
        [102] = { r = 1.00, g = 0.49, b = 0.04 },     -- Balance
        [103] = { r = 1.00, g = 0.49, b = 0.04 },     -- Feral
        [104] = { r = 1.00, g = 0.49, b = 0.04 },     -- Guardian
        [105] = { r = 1.00, g = 0.49, b = 0.04 },     -- Restoration
        -- Evoker
        [1467] = { r = 0.20, g = 0.58, b = 0.50 },    -- Devastation
        [1468] = { r = 0.20, g = 0.58, b = 0.50 },    -- Preservation
        [1473] = { r = 0.20, g = 0.58, b = 0.50 },    -- Augmentation
        -- Hunter
        [253] = { r = 0.67, g = 0.83, b = 0.45 },     -- Beast Mastery
        [254] = { r = 0.67, g = 0.83, b = 0.45 },     -- Marksmanship
        [255] = { r = 0.67, g = 0.83, b = 0.45 },     -- Survival
        -- Mage
        [62] = { r = 0.25, g = 0.78, b = 0.92 },      -- Arcane
        [63] = { r = 0.25, g = 0.78, b = 0.92 },      -- Fire
        [64] = { r = 0.25, g = 0.78, b = 0.92 },      -- Frost
        -- Monk
        [268] = { r = 0.00, g = 1.00, b = 0.59 },     -- Brewmaster
        [269] = { r = 0.00, g = 1.00, b = 0.59 },     -- Mistweaver
        [270] = { r = 0.00, g = 1.00, b = 0.59 },     -- Windwalker
        -- Paladin
        [65] = { r = 0.96, g = 0.55, b = 0.73 },      -- Holy
        [66] = { r = 1.00, g = 0.75, b = 0.20 },      -- Protection
        [70] = { r = 0.96, g = 0.55, b = 0.73 },      -- Retribution
        -- Priest
        [256] = { r = 1.00, g = 1.00, b = 1.00 },     -- Discipline
        [257] = { r = 1.00, g = 1.00, b = 1.00 },     -- Holy
        [258] = { r = 0.40, g = 0.00, b = 1.00 },     -- Shadow
        -- Rogue
        [259] = { r = 1.00, g = 0.96, b = 0.41 },     -- Assassination
        [260] = { r = 1.00, g = 0.96, b = 0.41 },     -- Outlaw
        [261] = { r = 1.00, g = 0.96, b = 0.41 },     -- Subtlety
        -- Shaman
        [262] = { r = 0.00, g = 0.44, b = 0.87 },     -- Elemental
        [263] = { r = 0.00, g = 0.44, b = 0.87 },     -- Enhancement
        [264] = { r = 0.00, g = 0.44, b = 0.87 },     -- Restoration
        -- Warlock
        [265] = { r = 0.53, g = 0.53, b = 0.93 },     -- Affliction
        [266] = { r = 0.53, g = 0.53, b = 0.93 },     -- Demonology
        [267] = { r = 0.635, g = 1.0, b = 0.0 },      -- Destruction
        -- Warrior
        [71] = { r = 1.00, g = 0.00, b = 0.00 },      -- Arms
        [72] = { r = 1.00, g = 0.00, b = 0.00 },      -- Fury
        [73] = { r = 1.00, g = 0.00, b = 0.00 },      -- Protection
    },

    -- Default panel settings for tracked icons
    cooldown_panel_defaults = {
        left = {
            name = "Left",
            anchor = "topleft",
            growthH = "Right",
            growthV = "Down",
            x = -425,
            y = 295,
            size = 40,
            spacing = 2,
            columns = 4,
            enabled = true,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 },
        },
        right = {
            name = "Right",
            anchor = "topright",
            growthH = "Left",
            growthV = "Down",
            x = 425,
            y = 295,
            size = 40,
            spacing = 2,
            columns = 4,
            enabled = true,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 },
        },
        center = {
            name = "CENTER",
            anchor = "center",
            growthH = "Center",
            growthV = "Down",
            x = 0,
            y = -92,
            size = 50,
            spacing = 1,
            columns = 10,
            enabled = true,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 },
            anchorTo = "Health Bar",
        },
        utility = {
            name = "UTILITY",
            anchor = "top", -- Anchors top of this panel to bottom of target
            growthH = "Center",
            growthV = "Down",
            x = 0,
            y = -2, -- 2px spacing below target
            size = 32,
            spacing = 1,
            columns = 9,
            enabled = true,
            textEnabled = true,
            textColor = { r = 1, g = 1, b = 1 },
            anchorTo = "CENTER",
        },
        -- Glow duration limit (seconds)
        glow_max_duration = 5.0,
    },

    -- Global defaults for icon panels (can be overridden per-panel or per-icon)
    -- These provide fallback values for all visual effect settings
    icon_panel_global_defaults = {
        -- Ready Glow (when spell is off cooldown/available)
        readyGlow = true,                    -- Enable glow when ready
        glowType = "pixel",                  -- Options: pixel, autocast, proc, button
        glowColor = { r = 1, g = 1, b = 0 }, -- Yellow by default
        glowScale = 1.0,
        glowIntensity = 1.0,
        glowSpeed = 1.0,         -- Changed from 0.25 to 1.0 per user request
        glowLines = 4,           -- Pixel glow: number of particles
        glowThickness = 1,       -- Pixel glow: line thickness
        glowParticles = 4,       -- Autocast glow: particle count
        glow_max_duration = 5.0, -- Max seconds to show glow

        -- Cooldown Visual State
        cooldownDesat = true,    -- Desaturate while on cooldown
        alphaOnCooldown = 1.0,   -- Alpha transparency while on cooldown (1.0 = Opaque)
        useResourceCheck = true, -- Enable mana/power based tinting
        showBackground = true,   -- Show a semi-transparent black background behind panels
        backgroundAlpha = 0.5,   -- 50% transparency for the background

        -- Text Display
        textEnabled = true,                  -- Show countdown numbers on icons
        textColor = { r = 1, g = 1, b = 1 }, -- White text
    },

    -- options panel specific settings
    options_panel = {
        width = 500,
        height = 500,
        backdrop_color = { r = 0.05, g = 0.05, b = 0.05, a = 0.8 },
        tabs = {
            width = 100,
            height = 30,
            color = { r = 0.4, g = 0.0, b = 1.0 },           -- #6600FF for unselected tabs
            selected_color = { r = 0, g = 1, b = 1 },        -- #00FFFF for selected tab
            highlight_color = { r = 0.6, g = 0.6, b = 0.6 }, -- Medium gray for hover
        }
    },

    -- currency frame settings
    currency_frame = {
        width = 200,
        height = 70,
    },

    -- item frame settings
    item_frame = {
        width = 200,
        height = 70,
    },

    -- CVars to set on addon load
    cvars_on_load = {
        { name = "autoLootDefault", value = 1 },
    },

    -- Power Bar settings
    powerBar = {
        enabled = true,
        width = 300,
        height = 10,
        useClassColor = true,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
        hiddenSpecs = {
            [1467] = true, -- Devastation Evoker
            [1473] = true, -- Augmentation Evoker
            [265] = true,  -- Affliction Warlock
            [266] = true,  -- Demonology Warlock
            [267] = true,  -- Destruction Warlock
            [63] = true,   -- Fire Mage
            [64] = true,   -- Frost Mage
            [269] = true,  -- Windwalker Monk
            [70] = true,   -- Retribution Paladin

        },
    },

    -- Cast Bar settings
    castBar = {
        enabled = true,
        width = 300,
        height = 15,
        pos = { x = 0, y = 110 },
        color = { 0.133, 0.133, 0.133 },   -- #222222
        channelColor = { 0, 1, 0 },        -- Green for channels
        empoweredColor = { 0.4, 0, 1 },    -- Default/Fallback Purple
        empoweredStageColors = {
            [1] = { 0.133, 0.133, 0.133 }, -- #222222
            [2] = { 0, 1, 1 },             -- Cyan (Charging Stage 2)
            [3] = { 0.4, 0, 1 },           -- Purple (Charging Stage 3)
            [4] = { 1, 0, 1 },             -- Magenta (Charging Stage 4)
        },
        interruptedColor = { 1, 0, 0 },    -- Red for interrupted
        gcdColor = { 0.5, 0.5, 0.5 },      -- Gray for GCD
        updateThrottle = 0.05,             -- Text update throttle (~20fps)
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
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

    -- Instant Cast Bar (GCD Bar) settings
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

    -- Health Bar settings
    healthBar = {
        enabled = true,
        width = 300,
        height = 20,
        color = { 0.2, 0.2, 0.2 }, -- Dark Grey
        defaultX = 0,
        defaultY = 300,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 }, -- Black/Transparent
        },
    },

    -- Secondary Power Bar settings
    secondaryPowerBar = {
        enabled = true,
        width = 240,
        height = 15,
        useClassColor = true,
        fontSize = 18,
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
        hiddenSpecs = {
            [258] = true, -- Shadow Priest
            [270] = true, -- Mistweaver Monk
        },
    },

    -- Vigor Bar settings
    vigorBar = {
        enabled = true,
        width = 240,
        height = 15,
        color = { 0.4, 0, 1 },
        backdrop = {
            padding = 2,
            color = { 0, 0, 0, 0.5 },
        },
    },

    -- Mount Speed Bar settings
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

    barTextures = {
        { text = "Default",           value = "Interface/TargetingFrame/UI-StatusBar" },
        { text = "Raid Bar",          value = "Interface/RaidFrame/Raid-Bar-Hp-Fill" },
        { text = "Casting Bar Spark", value = "Interface/CastingBar/UI-CastingBar-Spark" },
        { text = "Flat",              value = "Interface/Buttons/WHITE8X8" },
    },

    absorbBarColor = { r = 0.4, g = 0.0, b = 1.0, a = 0.75 },

    minimap = {
        default_size = 220,
        defaultZoom = 0, -- Default zoom level
        button_bar = {
            spacing = 5,
            button_size = 20,
            defaultX = 0,
            defaultY = 35,
        },
    },

    -- Reminders (Buffs/Debuffs)
    reminders = {
        icon_size = 32,
        spacing = 4,
        group_spacing = 12,
        pos = { x = 250, y = 220 }, -- Default if not saved
        backdrop = {
            padding = 4,
            color = { 0, 0, 0, 0.5 },
        },
        disableConsumablesSolo = true,
        enableConsumables = true,
        buffThreshold = 600, -- 10 minutes in seconds
    },

    -- Warnings
    warnings = {
        pet = {
            enabled = true,
            text = "** FU PET **",
            priority = 10,
            color = "magenta",
        },
        rune = {
            enabled = true,
            text = "** USE YOUR RUNE IDIOT **",
            priority = 5,
            color = "magenta",
        }
    },

    -- Bar Layout Settings
    barLayout = {
        spacing = 1,
    },

    -- Vehicle UI settings
    vehicle = {
        enabled = true,
        width = 300,
        height = 60,
        anchor = { point = "BOTTOM", x = 0, y = 200 },
        button_size = 40,
        button_spacing = 5,
        leave_button_size = 30,
    },

    -- Merchant Frame settings
    merchant = {
        -- Grid layout
        grid = {
            rows = 7,
            cols = 4,
            item_width = 190,
            item_height = 45,
            spacing_x = 195,
            spacing_y = 50,
            offset_x = 20,
            offset_y = -40,
        },
        -- Frame dimensions
        frame = {
            width = 840,  -- 4 cols * 200 + 40
            height = 450, -- 7 rows * 50 + 100
        },
        -- Utility bar
        utility_bar = {
            height = 30,
            bottom_offset = 2,
            button_height = 22,
            button_small = 80,  -- buyback, filter buttons (Increased from 60)
            button_medium = 70, -- sell greys
            button_large = 110, -- housing filter (Increased from 90)
            spacing = 5,
        },
        -- Scrollbar
        scrollbar = {
            height = 6,
            bottom_offset = 35,
        },
        -- Currency display
        currency = {
            height = 20,
            bottom_offset = 8,
        },
        -- Button colors (references to colors table)
        button_colors = {
            filter_active = "purple",
            filter_inactive = "white",
            filter_hover = "cyan",
            decor_hide_owned = "magenta",
            decor_hide_storage = "purple",
            decor_show_all = "white",
        },
        lootFilterState = 0,
    },

    -- automation settings
    automation = {
        auto_role_check = true,
        auto_sign_lfg = true,
    },


    -- Tracked Bars (Custom Cooldown Tracker)
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
        icon_size = 20,
        icon_offset = -5, -- Space between bar and icon
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
            [9039] = { maxStacks = 12 },   -- Bone Shield (Death Knight)
            [18469] = { maxStacks = 100 }, -- Ignore Pain (Warrior)
        },
        -- Default visibility settings
        hideOOC = false,     -- Hide all bars when out of combat
        hideInactive = true, -- Hide bars when cooldowns are inactive
        -- Default bar configuration per cooldown ID
        defaults = {
            [18469] = {                                -- Ignore Pain (Warrior)
                stackAboveHealth = true,               -- Attach to healthbar (secondary position)
                color = { r = 1, g = 0.533, b = 0 },   -- Orange
                showStacksText = true,                 -- Show stack count as duration text
            },
            [9039] = {                                 -- Bone Shield (Death Knight)
                stackAboveHealth = true,               -- Attach to healthbar
                stackMode = true,                      -- Use stack count as bar value
                color = { r = 0, g = 0.8, b = 0.067 }, -- Green
                showName = false,                      -- Hide name
            },
        },
    },

    -- Tracked Options Window
    trackedOptionsWindow = {
        width = 800,
        height = 500,
    },

    -- Master's Hammer Specialization Nodes
    -- Organised by expansion version keys.
    masterHammer = {
        requiredRank = 26, -- Required trait rank for repair perks
        defaultPosition = { x = 880, y = -430 },
        defaultColor = "00FFFF",
        [225660] = { -- Earthen Master's Hammer (TWW)
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
                -- Weapon SubClassIDs (Class 2)
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
        [238020] = { -- Thalassian Master Repair Hammer (Midnight)
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
    }
}
