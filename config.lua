sfui = sfui or {}

sfui.config = {
    -- addon metadata
    title = "|cff6600ffst|r fui - frameworks",
    version = "0.1.0",

    -- general appearance
    font = "GameFontNormal",
    font_small = "GameFontNormalSmall",
    font_large = "GameFontNormalLarge",
    font_highlight = "GameFontHighlight",
    header_color = { 1, 1, 1 },
    textures = {
        white = "Interface/Buttons/WHITE8X8",
        tooltip = "Interface/Tooltips/UI-Tooltip-Background",
        gold_icon = "Interface\\MoneyFrame\\UI-GoldIcon",
    },

    -- addon-wide color palette
    colors = {
        purple = { 0.4, 0, 1 }, -- #6600FF
        cyan = { 0, 1, 1 },     -- #00FFFF
        magenta = { 1, 0, 1 },  -- #FF00FF
        white = { 1, 1, 1 },
        black = { 0, 0, 0 },
        gray = { 0.2, 0.2, 0.2 }, -- Dark gray for borders
    },

    -- shared settings for icon bars
    widget_bar = {
        icon_size = 40,
        icon_spacing = 5,
        label_offset_y = -2,
        label_color = { 1, 1, 1 },
    },

    -- custom spec colors (for example, to override defaults or add new ones)
    spec_colors = {
        -- Death Knight
        [250] = { r = 0.77, g = 0.12, b = 0.23 },  -- Blood
        [251] = { r = 0.0, g = 1.0, b = 1.0 },     -- Frost
        [252] = { r = 0.0, g = 1.0, b = 0.0 },     -- Unholy
        -- Demon Hunter
        [577] = { r = 0.64, g = 0.19, b = 0.79 },  -- Havoc
        [581] = { r = 0.64, g = 0.19, b = 0.79 },  -- Vengeance
        [1480] = { r = 0.4, g = 0, b = 1 },        -- Devourer
        -- Druid
        [102] = { r = 1.00, g = 0.49, b = 0.04 },  -- Balance
        [103] = { r = 1.00, g = 0.49, b = 0.04 },  -- Feral
        [104] = { r = 1.00, g = 0.49, b = 0.04 },  -- Guardian
        [105] = { r = 1.00, g = 0.49, b = 0.04 },  -- Restoration
        -- Evoker
        [1467] = { r = 0.20, g = 0.58, b = 0.50 }, -- Devastation
        [1468] = { r = 0.20, g = 0.58, b = 0.50 }, -- Preservation
        [1473] = { r = 0.20, g = 0.58, b = 0.50 }, -- Augmentation
        -- Hunter
        [253] = { r = 0.67, g = 0.83, b = 0.45 },  -- Beast Mastery
        [254] = { r = 0.67, g = 0.83, b = 0.45 },  -- Marksmanship
        [255] = { r = 0.67, g = 0.83, b = 0.45 },  -- Survival
        -- Mage
        [62] = { r = 0.25, g = 0.78, b = 0.92 },   -- Arcane
        [63] = { r = 0.25, g = 0.78, b = 0.92 },   -- Fire
        [64] = { r = 0.25, g = 0.78, b = 0.92 },   -- Frost
        -- Monk
        [268] = { r = 0.00, g = 1.00, b = 0.59 },  -- Brewmaster
        [269] = { r = 0.00, g = 1.00, b = 0.59 },  -- Mistweaver
        [270] = { r = 0.00, g = 1.00, b = 0.59 },  -- Windwalker
        -- Paladin
        [65] = { r = 0.96, g = 0.55, b = 0.73 },   -- Holy
        [66] = { r = 0.96, g = 0.55, b = 0.73 },   -- Protection
        [70] = { r = 0.96, g = 0.55, b = 0.73 },   -- Retribution
        -- Priest
        [256] = { r = 1.00, g = 1.00, b = 1.00 },  -- Discipline
        [257] = { r = 1.00, g = 1.00, b = 1.00 },  -- Holy
        [258] = { r = 0.40, g = 0.00, b = 1.00 },  -- Shadow
        -- Rogue
        [259] = { r = 1.00, g = 0.96, b = 0.41 },  -- Assassination
        [260] = { r = 1.00, g = 0.96, b = 0.41 },  -- Outlaw
        [261] = { r = 1.00, g = 0.96, b = 0.41 },  -- Subtlety
        -- Shaman
        [262] = { r = 0.00, g = 0.44, b = 0.87 },  -- Elemental
        [263] = { r = 0.00, g = 0.44, b = 0.87 },  -- Enhancement
        [264] = { r = 0.00, g = 0.44, b = 0.87 },  -- Restoration
        -- Warlock
        [265] = { r = 0.53, g = 0.53, b = 0.93 },  -- Affliction
        [266] = { r = 0.53, g = 0.53, b = 0.93 },  -- Demonology
        [267] = { r = 0.635, g = 1.0, b = 0.0 },   -- Destruction
        -- Warrior
        [71] = { r = 1.00, g = 0.00, b = 0.00 },   -- Arms
        [72] = { r = 1.00, g = 0.00, b = 0.00 },   -- Fury
        [73] = { r = 1.00, g = 0.00, b = 0.00 },   -- Protection
    },

    -- options panel specific settings
    options_panel = {
        width = 500,
        height = 500,
        backdrop_color = { r = 0.05, g = 0.05, b = 0.05, a = 0.8 },
        tabs = {
            width = 100,
            height = 30,
            color = { r = 0.4, g = 0.0, b = 1.0 },           -- 6600ff for unselected tabs
            selected_color = { r = 0.9, g = 0.9, b = 0.9 },  -- Off-white for selected tab
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
        button_bar = {
            spacing = 5,
            button_size = 20,
            defaultX = 0,
            defaultY = 35,
        },
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
    },
}
