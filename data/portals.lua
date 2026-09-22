-- data/portals.lua
-- SFUI Portals & Hearthstones Database
-- All portal/wormhole spell and toy IDs. Edit here to add new portals.
-- Availability is checked at runtime in portals.lua:
--   Spells: C_SpellBook.IsSpellInSpellBook(spellID)
--   Toys:   PlayerHasToy(toyID)
--
-- Names use GetRealZoneText(instance) automatically when instance is set.
-- Set name="" to force instance-based name lookup.

local isRetail = (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)
if not isRetail then return end

sfui = sfui or {}
sfui.portals_db = {}

-- ========================
-- Expansion Definitions (0-indexed per WoW API: LE_EXPANSION_*)
-- 0 = Classic, 1 = TBC, 2 = WotLK, 3 = Cata, 4 = MoP, 5 = WoD,
-- 6 = Legion, 7 = BfA, 8 = SL, 9 = DF, 10 = TWW, 11 = Midnight
-- ========================
sfui.portals_db.EXPANSIONS = {
    [0]  = { name = "Classic",               short = "Classic",  aliases = { "classic", "vanilla" } },
    [1]  = { name = "The Burning Crusade",   short = "TBC",      aliases = { "burning crusade", "the burning crusade", "tbc", "bc", "outland" } },
    [2]  = { name = "Wrath of the Lich King", short = "WotLK",   aliases = { "wrath of the lich king", "wotlk", "wrath", "northrend" } },
    [3]  = { name = "Cataclysm",             short = "Cata",     aliases = { "cataclysm", "cata", "maelstrom" } },
    [4]  = { name = "Mists of Pandaria",     short = "MoP",      aliases = { "mists of pandaria", "mop", "pandaria" } },
    [5]  = { name = "Warlords of Draenor",   short = "WoD",      aliases = { "warlords of draenor", "wod", "warlords", "draenor" } },
    [6]  = { name = "Legion",                short = "Legion",   aliases = { "legion", "broken isles", "argus" } },
    [7]  = { name = "Battle for Azeroth",    short = "BfA",      aliases = { "battle for azeroth", "bfa", "zandalar", "kul tiras", "kultiras" } },
    [8]  = { name = "Shadowlands",           short = "SL",       aliases = { "shadowlands", "sl" } },
    [9]  = { name = "Dragonflight",          short = "DF",       aliases = { "dragonflight", "df", "dragon isles" } },
    [10] = { name = "The War Within",        short = "TWW",      aliases = { "the war within", "war within", "tww", "khaz algar" } },
    [11] = { name = "Midnight",              short = "Midnight", aliases = { "midnight", "mid", "quel'thalas", "quelthalas" } },
}

-- ========================
-- Current M+ Season Portals ("Path of the ...")
-- Midnight Season 2 (12.1) spell IDs
-- ========================
-- ========================
-- Cosmetic Hearthstone Skins
-- All items that share spell 8690 (plain Hearthstone — returns to your home inn).
-- These are purely visual overrides; they do NOT change destination.
-- Detected via GetItemSpell(toyID) == 8690, but maintained as a list since
-- iterating the full toybox is expensive and async. Add new skins as patches land.
-- ========================
sfui.portals_db.COSMETIC_HEARTHSTONES = {
    -- Verified against OPie CommonHearth ring and Wowhead.
    -- All items share spell 8690 (standard Hearthstone — returns to your home inn).
    -- Classic / TCG / Promo
    54452,  -- Ethereal Portal (WoW TCG / UDE Points)
    64488,  -- The Innkeeper's Daughter (Archaeology - Dwarf)
    93672,  -- Dark Portal (WoW TCG)
    142542, -- Tome of Town Portal (Diablo 20th Anniversary)
    206195, -- Path of the Naaru (Promo)
    209035, -- Hearthstone of the Flame (BlizzCon / Promo)
    210455, -- Draenic Hologem (Promo)
    212337, -- Stone of the Hearth (Hearthstone 10th Anniversary)

    -- World Events / Holidays
    162973, -- Greatfather Winter's Hearthstone (Feast of Winter Veil)
    163045, -- Headless Horseman's Hearthstone (Hallow's End)
    165669, -- Lunar Elder's Hearthstone (Lunar Festival)
    165670, -- Peddlefeet's Lovely Hearthstone (Love is in the Air)
    165802, -- Noble Gardener's Hearthstone (Noblegarden)
    166746, -- Fire Eater's Hearthstone (Midsummer Fire Festival)
    166747, -- Brewfest Reveler's Hearthstone (Brewfest)

    -- BfA / Shadowlands
    168907, -- Holographic Digitalization Hearthstone (Mechagon / Engineering)
    172179, -- Eternal Traveler's Hearthstone (Shadowlands Heroic/Epic)
    180290, -- Night Fae Hearthstone (Shadowlands Covenant)
    182773, -- Necrolord Hearthstone (Shadowlands Covenant)
    183716, -- Venthyr Sinstone (Shadowlands Covenant)
    184353, -- Kyrian Hearthstone (Shadowlands Covenant)
    188952, -- Dominated Hearthstone (Torghast)
    190196, -- Enlightened Hearthstone (Zereth Mortis)
    190237, -- Broker Translocation Matrix (Tazavesh)

    -- Dragonflight
    193588, -- Timewalker's Hearthstone (Timewalking)
    200630, -- Ohn'ir Windsage's Hearthstone (Maruuk Centaur Renown)

    -- The War Within
    208704, -- Deepdweller's Earthen Hearthstone (Earthen / Khaz Algar)
    228940, -- Notorious Thread's Hearthstone (Severed Threads Renown)
    235016, -- Redeployment Module (Undermine / 11.1)
    236687, -- Explosive Hearthstone (Undermine / 11.1)
    245970, -- P.O.S.T. Master's Express Hearthstone (Khaz Algar)
    246565, -- Cosmic Hearthstone (TWW)

    -- Midnight (12.x)
    257736, -- Lightcalled Hearthstone
    263489, -- Naaru's Enfold
    263933, -- Preyseeker's Hearthstone
    264367, -- Mycomancer's Hearthspore
    265100, -- Corewarden's Hearthstone
}


sfui.portals_db.SEASON_PORTALS = {
    { spell = 1286812, name = "Altar of Fangs",        instance = 2993, expansion = 11 }, -- Path of Venomous Evolution / Path of the Vicious
    { spell = 1286807, name = "Den of Nalorakk",        instance = 2825, expansion = 11 }, -- Path of the Savage God
    { spell = 1286831, name = "Kings' Rest",           instance = 1762, expansion = 7  }, -- Path of the Slumbering Conqueror / Path of the Ancient Kings
    { spell = 1286809, name = "Murder Row",            instance = 2813, expansion = 11 }, -- Path of the Devious Smuggler / Path of the Murderer
    { spell = 393256,  name = "Ruby Life Pools",       instance = 2521, expansion = 9  }, -- Path of the Clutch Defender
    { spell = 1286828, name = "Temple of Sethraliss",  instance = 1877, expansion = 7  }, -- Path of the Sacred Temple
    { spell = 1286801, name = "The Blinding Vale",      instance = 2859, expansion = 11 }, -- Path of the Blooming Verdure
    { spell = 1286804, name = "Voidscar Arena",        instance = 2923, expansion = 11 }, -- Path of the Brutal Combatant / Path of the Voidscarred
}

-- ========================
-- Midnight Expansion Portals
-- Midnight expansion dungeon portals
-- ========================
sfui.portals_db.MIDNIGHT_PORTALS = {
    { spell = 1286812, name = "Altar of Fangs",        instance = 2993, expansion = 11 },
    { spell = 1286807, name = "Den of Nalorakk",        instance = 2825, expansion = 11 },
    { spell = 1254572, name = "Magisters' Terrace",      instance = 2811, expansion = 11 },
    { spell = 1254559, name = "Maisara Caverns",         instance = 2874, expansion = 11 },
    { spell = 1286809, name = "Murder Row",            instance = 2813, expansion = 11 },
    { spell = 1254563, name = "Nexus-Point Xenas",       instance = 2915, expansion = 11 },
    { spell = 1286801, name = "The Blinding Vale",      instance = 2859, expansion = 11 },
    { spell = 1286804, name = "Voidscar Arena",        instance = 2923, expansion = 11 },
    { spell = 1254400, name = "Windrunner Spire",        instance = 2805, expansion = 11 },
}

-- ========================
-- Personal / Class Portals
-- Shown only if the player knows the spell (IsSpellInSpellBook)
-- Includes: mage teleports, DK/Monk/Druid class abilities, race abilities
-- ========================
sfui.portals_db.PERSONAL_PORTALS = {
    { spell = 50977,   name = "Acherus (Death Knight)",              expansion = 2  },
    { spell = 281403,  portal = 281400, name = "Boralus",                          expansion = 7  },
    { spell = 120145,  portal = 120146, name = "Dalaran (Crater)",                 expansion = 0  },
    { spell = 224869,  portal = 224871, name = "Dalaran (Legion)",                 expansion = 6  },
    { spell = 53140,   portal = 53142,  name = "Dalaran (Northrend)",              expansion = 2  },
    { spell = 3565,    portal = 11419,  name = "Darnassus",                        expansion = 0  },
    { spell = 281404,  portal = 281402, name = "Dazar'alor",                       expansion = 7  },
    { spell = 446540,  portal = 446534, name = "Dornogal",                         expansion = 10 },
    { spell = 193753,  name = "Dreamwalk (Druid)",                    expansion = 6  },
    { spell = 32271,   portal = 32266,  name = "Exodar",                           expansion = 1  },
    { spell = 193759,  name = "Hall of the Guardian (Mage)",          expansion = 6  },
    { spell = 3562,    portal = 11416,  name = "Ironforge",                        expansion = 0  },
    { spell = 265225,  name = "Mole Machine (Dark Iron Dwarf)",       expansion = 7  },
    { spell = 18960,   name = "Moonglade (Druid)",                    expansion = 0  },
    { spell = 344587,  portal = 344597, name = "Oribos",                           expansion = 8  },
    { spell = 3567,    portal = 11417,  name = "Orgrimmar",                        expansion = 0  },
    { spell = 1238686, name = "Rootwalking (Haranir)",                expansion = 11 },
    { spell = 35715,   portal = 35717,  name = "Shattrath (A)",                   expansion = 1  },
    { spell = 33690,   portal = 33691,  name = "Shattrath (H)",                   expansion = 1  },
    { spell = 32272,   portal = 32267,  name = "Silvermoon",                       expansion = 1  },
    { spell = 1259190, portal = 1259194,name = "Silvermoon City (Midnight)",       expansion = 11 },
    { spell = 49358,   portal = 49361,  name = "Stonard",                          expansion = 0  },
    { spell = 176248,  portal = 176246, name = "Stormshield",                      expansion = 5  },
    { spell = 3561,    portal = 10059,  name = "Stormwind",                        expansion = 0  },
    { spell = 49359,   portal = 49360,  name = "Theramore",                        expansion = 0  },
    { spell = 3566,    portal = 11420,  name = "Thunder Bluff",                    expansion = 0  },
    { spell = 88342,   portal = 88345,  name = "Tol Barad (A)",                   expansion = 3  },
    { spell = 88344,   portal = 88346,  name = "Tol Barad (H)",                   expansion = 3  },
    { spell = 3563,    portal = 11418,  name = "Undercity",                        expansion = 0  },
    { spell = 395277,  portal = 395289, name = "Valdrakken",                       expansion = 9  },
    { spell = 132621,  portal = 132620, name = "Vale of Eternal Blossoms (A)",     expansion = 4  },
    { spell = 132627,  portal = 132626, name = "Vale of Eternal Blossoms (H)",     expansion = 4  },
    { spell = 176242,  portal = 176244, name = "Warspear",                         expansion = 5  },
    { spell = 126892,  name = "Zen Pilgrimage (Monk)",                expansion = 4  },
}

-- ========================
-- Engineering Wormhole Toys
-- Checked via PlayerHasToy() AND is_engineer() at runtime
-- ========================
sfui.portals_db.WORMHOLE_TOYS = {
    { toy = 248485, name = "Wormhole Generator: Quel'Thalas",         expansion = 11 }, -- Midnight (11)
    { toy = 221966, name = "Wormhole Generator: Khaz Algar",          expansion = 10 }, -- The War Within (10)
    { toy = 198156, name = "Wyrmhole Generator: Dragon Isles",        expansion = 9  }, -- Dragonflight (9)
    { toy = 172924, name = "Wormhole Generator: Shadowlands",         expansion = 8  }, -- Shadowlands (8)
    { toy = 168808, name = "Wormhole Generator: Zandalar",            expansion = 7  }, -- Battle for Azeroth (7)
    { toy = 168807, name = "Wormhole Generator: Kul Tiras",           expansion = 7  }, -- Battle for Azeroth (7)
    { toy = 151652, name = "Wormhole Generator: Argus",               expansion = 6  }, -- Legion (6)
    { toy = 112059, name = "Wormhole Centrifuge: Draenor",            expansion = 5  }, -- Warlords of Draenor (5)
    { toy = 87215,  name = "Wormhole Generator: Pandaria",            expansion = 4  }, -- Mists of Pandaria (4)
    { toy = 48933,  name = "Wormhole Generator: Northrend",           expansion = 2  }, -- Wrath of the Lich King (2)
    { toy = 30544,  name = "Ultrasafe Transporter: Toshley's Station",expansion = 1  }, -- The Burning Crusade (1)
    { toy = 30542,  name = "Dimensional Ripper: Area 52",             expansion = 1  }, -- The Burning Crusade (1)
    { toy = 18986,  name = "Ultrasafe Transporter: Gadgetzan",        expansion = 0  }, -- Classic (0)
    { toy = 18984,  name = "Dimensional Ripper: Everlook",            expansion = 0  }, -- Classic (0)
}

-- ========================
-- Travel Toys
-- Shown in a dedicated vertical column on the right side of the portal panel.
-- Sorted by expansion, latest at the top.
-- Checked via PlayerHasToy(toyID) at runtime.
-- altToy: faction-specific counterpart (e.g. Alliance vs Horde)
sfui.portals_db.TRAVEL_TOYS = {
    { toy = 266370, name = "Dundun's Abundant Travel Method", abbr = "DUNDUN", expansion = 11 }, -- Midnight (11)
    { toy = 253629, name = "Personal Key to the Arcantina",   abbr = "ARCA",   expansion = 11 }, -- Midnight (11)
    { toy = 243056, name = "Delver's Mana-Bound Ethergate",   abbr = "ETHER",  expansion = 10 }, -- The War Within (10)
    { toy = 230850, name = "Delve-O-Bot 7001",                 abbr = "BOT",    expansion = 10 }, -- The War Within (10)
    { toy = 151016, name = "Fractured Necrolyte Skull",       abbr = "SKULL",  expansion = 6  }, -- Legion (6)
    { toy = 140192, name = "Dalaran Hearthstone",             abbr = "DALA",   expansion = 6  }, -- Legion (6)
    { toy = 110560, name = "Garrison Hearthstone",            abbr = "GARR",   expansion = 5  }, -- WoD (5)
    { toy = 64457,  name = "The Last Relic of Argus",         abbr = "ARGUS",  expansion = 3  }, -- Cataclysm (3)
}

-- ========================
-- Legacy Dungeon Portals — grouped by expansion for dropdowns
-- Spells shown only if IsSpellInSpellBook is true (player has the spell)
-- ========================
sfui.portals_db.LEGACY_GROUPS = {
    {
        label = "Khaz Algar",
        expansion = 10,
        portals = {
            { spell = 445417,  name = "Ara-Kara"                     },
            { spell = 445440,  name = "Cinderbrew Meadery"           },
            { spell = 445416,  name = "City of Threads"              },
            { spell = 445441,  name = "Darkflame Cleft"              },
            { spell = 1237215, name = "Eco-Dome Al'dani"             },
            { spell = 1226482, name = "Liberation of Undermine"      },
            { spell = 1239155, name = "Manaforge Omega"              },
            { spell = 1216786, name = "Operation: Floodgate"         },
            { spell = 445444,  name = "Priory of the Sacred Flame"   },
            { spell = 445269,  name = "Stonevault"                   },
            { spell = 445414,  name = "The Dawnbreaker"              },
            { spell = 445443,  name = "The Rookery"                  },
        },
    },
    {
        label = "Dragon Isles",
        expansion = 9,
        portals = {
            { spell = 432257, name = "Aberrus"                       },
            { spell = 393273, name = "Algeth'ar Academy"             },
            { spell = 432258, name = "Amirdrassil"                   },
            { spell = 393267, name = "Brackenhide Hollow"            },
            { spell = 424197, name = "Dawn of the Infinite"          },
            { spell = 393283, name = "Halls of Infusion"             },
            { spell = 393276, name = "Neltharus"                     },
            { spell = 393256, name = "Ruby Life Pools"               },
            { spell = 393279, name = "The Azure Vault"               },
            { spell = 393262, name = "The Nokhud Offensive"          },
            { spell = 432254, name = "Vault of the Incarnates"       },
        },
    },
    {
        label = "Shadowlands",
        expansion = 8,
        portals = {
            { spell = 354468, name = "De Other Side"                 },
            { spell = 354465, name = "Halls of Atonement"            },
            { spell = 354464, name = "Mists of Tirna Scithe"         },
            { spell = 354462, name = "Necrotic Wake"                 },
            { spell = 354463, name = "Plaguefall"                    },
            { spell = 373191, name = "Sanctum of Domination"         },
            { spell = 354469, name = "Sanguine Depths"               },
            { spell = 373192, name = "Sepulcher of the First Ones"   },
            { spell = 354466, name = "Spires of Ascension"           },
            { spell = 367416, name = "Tazavesh the Veiled Market"    },
            { spell = 354467, name = "Theater of Pain"               },
        },
    },
    {
        label = "Kul Tiras",
        expansion = 7,
        portals = {
            { spell = 410071, name = "Freehold"                      },
            { spell = 373274, name = "Operation: Mechagon"           },
            { spell = 445418, name = "Siege of Boralus"              },
            { spell = 464256, name = "Siege of Boralus (S2)"         },
            { spell = 424167, name = "Waycrest Manor"                },
        },
    },
    {
        label = "Zandalar",
        expansion = 7,
        portals = {
            { spell = 424187,  name = "Atal'Dazar"                    },
            { spell = 1286831, name = "Kings' Rest"                   },
            { spell = 1286828, name = "Temple of Sethraliss"          },
            { spell = 467553,  name = "The MOTHERLODE!! (A)"          },
            { spell = 467555,  name = "The MOTHERLODE!! (H)"          },
            { spell = 410074,  name = "The Underrot"                  },
        },
    },
    {
        label = "Broken Isles",
        expansion = 6,
        portals = {
            { spell = 424153, name = "Black Rook Hold"               },
            { spell = 393766, name = "Court of Stars"                },
            { spell = 424163, name = "Darkheart Thicket"             },
            { spell = 393764, name = "Halls of Valor"                },
            { spell = 410078, name = "Neltharion's Lair"             },
            { spell = 1254551, name = "Seat of the Triumvirate"      },
        },
    },
    {
        label = "Draenor",
        expansion = 5,
        portals = {
            { spell = 159897, name = "Auchindoun"                    },
            { spell = 159895, name = "Bloodmaul Slag Mines"          },
            { spell = 159900, name = "Grimrail Depot"                },
            { spell = 159896, name = "Iron Docks"                    },
            { spell = 159899, name = "Shadowmoon Burial Grounds"     },
            { spell = 159898, name = "Skyreach"                     },
            { spell = 1254557, name = "Skyreach (New)"               },
            { spell = 159901, name = "The Everbloom"                 },
        },
    },
    {
        label = "Pandaria",
        expansion = 4,
        portals = {
            { spell = 131225, name = "Gate of the Setting Sun"       },
            { spell = 131222, name = "Mogu'shan Palace"              },
            { spell = 131206, name = "Shado-Pan Monastery"           },
            { spell = 131228, name = "Siege of Niuzao Temple"        },
            { spell = 131205, name = "Stormstout Brewery"            },
            { spell = 131204, name = "Temple of the Jade Serpent"    },
        },
    },
    {
        label = "Northrend",
        expansion = 2,
        portals = {
            { spell = 1254555, name = "Pit of Saron"                 },
        },
    },
    {
        label = "Maelstrom",
        expansion = 3,
        portals = {
            { spell = 424142, name = "Throne of the Tides"           },
        },
    },
    {
        label = "Kalimdor",
        portals = {
            { spell = 410080, name = "The Vortex Pinnacle",    expansion = 3 },
            { spell = 393222, name = "Uldaman: Legacy of Tyr", expansion = 9 },
        },
    },
    {
        label = "Eastern Kingdoms",
        portals = {
            { spell = 373190, name = "Castle Nathria",         expansion = 8 },
            { spell = 445424, name = "Grim Batol",             expansion = 3 },
            { spell = 373262, name = "Karazhan",               expansion = 6 },
            { spell = 131231, name = "Scarlet Halls",          expansion = 4 },
            { spell = 131229, name = "Scarlet Monastery",      expansion = 4 },
            { spell = 131232, name = "Scholomance",            expansion = 4 },
            { spell = 159902, name = "Upper Blackrock Spire",  expansion = 5 },
        },
    },
}

-- ========================
-- Global UI Name Abbreviations
-- Consumed by sfui.common.get_short_string()
-- ========================
sfui.portals_db.SHORT_STRINGS = {
    ["Ara-Kara, City of Echoes"] = "ARA",
    ["City of Threads"] = "COT",
    ["The Stonevault"] = "SV",
    ["The Dawnbreaker"] = "DB",
    ["Mists of Tirna Scithe"] = "MISTS",
    ["The Necrotic Wake"] = "NW",
    ["Siege of Boralus"] = "SIEGE",
    ["Grim Batol"] = "GB",
    ["Darkflame Cleft"] = "DFC",
    ["Cinderbrew Meadery"] = "CM",
    ["Priory of the Sacred Flame"] = "PSF",
    ["The Rookery"] = "ROOK",
    ["Operation: Floodgate"] = "FLOOD",
    ["Liberation of Undermine"] = "LOU",
    ["Darkmoon"] = "DM",
    ["Theater of Pain"] = "TOP",
    ["Ruby Life Pools"] = "RLP",
    ["The Nokhud Offensive"] = "TNO",
    ["Algeth'ar Academy"] = "AA",
    ["Halls of Infusion"] = "HOI",
    ["Neltharus"] = "NELT",
    ["Brackenhide Hollow"] = "BH",
    ["Uldaman: Legacy of Tyr"] = "ULD",
    ["Operation: Mechagon - Junkyard"] = "JUNK",
    ["Operation: Mechagon - Workshop"] = "WORK",
    ["Return to Karazhan: Lower"] = "LOW",
    ["Return to Karazhan: Upper"] = "UPP",
    ["Stonevault"] = "SV",
    ["Ara-Kara"] = "ARA",
    ["Necrotic Wake"] = "NW",
    ["Operation: Mechagon"] = "MECH",
    ["Siege of Boralus (S2)"] = "SIEGE",
    ["Eco-Dome Al'dani"] = "ECO",
    ["Manaforge Omega"] = "OMEGA",
    ["Pit of Saron"] = "POS",
    ["Magisters' Terrace"] = "MGT",
    ["Seat of the Triumvirate"] = "SEAT",
    ["Maisara Cavern"] = "MAIS",
    ["Maisara Caverns"] = "MAIS",
    ["Nexus Point Xenas"] = "NPX",
    ["Nexus-Point Xenas"] = "NPX",
    ["Windrunner Spire"] = "SPIRE",
    ["Skyreach"] = "SKY",
    ["Skyreach (New)"] = "SKY",
    ["Altar of Fangs"] = "AOF",
    ["Murder Row"] = "MR",
    ["Den of Nalorakk"] = "DON",
    ["The Blinding Vale"] = "BV",
    ["Voidscar Arena"] = "VA",
    ["Kings' Rest"] = "KR",
    ["King's Rest"] = "KR",
    ["Temple of Sethraliss"] = "TOS",
    -- Travel Toys
    ["Dundun's Abundant Travel Method"] = "DUNDUN",
    ["Personal Key to the Arcantina"] = "ARCA",
    ["Delver's Mana-Bound Ethergate"] = "ETHER",
    ["Delve-O-Bot 7001"] = "BOT",
    ["Fractured Necrolyte Skull"] = "SKULL",
    ["Dalaran Hearthstone"] = "DALA",
    ["Garrison Hearthstone"] = "GARR",
    ["The Last Relic of Argus"] = "ARGUS",
    ["Hearthstone"] = "HEARTH",
    ["Teleport to Plot"] = "PLOT",
}

