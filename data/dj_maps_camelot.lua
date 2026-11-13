local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.dj_camelot = sfui.dj_camelot or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/data/dj_maps_camelot.lua
--  Self-contained Dungeon Maps, In-Dungeon Quest Pins, Travel Routes,
--  Turn-In Spots, and Verified Questgiver Coordinates for Camelot / Forever.
--  Packed with lazy metatable decoding for low load time and minimal Lua heap.
-- ══════════════════════════════════════════════════════════════════════════════

local MAP_TEX_PREFIX = "Interface\\AddOns\\sfui\\media\\dungeonmaps\\"
local tonumber = _G.tonumber
local setmetatable = _G.setmetatable
local pairs = _G.pairs
local ipairs = _G.ipairs
local string_gmatch = string.gmatch

local function resolve_tex(s)
    if s and s:sub(1, 1) == "@" then
        return MAP_TEX_PREFIX .. s:sub(2)
    end
    return s
end

local RAW_MAPS = {
    alcaz_prison = {
        f = { { "@AlcazPrisonMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.35299999999999998, 0.16, 180, "entrance" } },
    },
    blackfathom_deeps = {
        f = { { "@BlackFathomDeeps1", 0.97851600000000005, 0.65234400000000003, nil, 221 }, { "@BlackFathomDeeps2", 0.97851600000000005, 0.65234400000000003, nil, 222 }, { "@BlackFathomDeeps3", 0.97851600000000005, 0.65234400000000003, nil, 223 } },
        e = { { 1, 0.45500000000000002, 0.085000000000000006, -20, "entrance" } },
        b = {
            { 1, "Ghamoo-ra", 0.32500000000000001, 0.60499999999999998, "25", 4887, 5027, false },
            { 1, "Lady Sarevess", 0.11, 0.38500000000000001, "25", 4359, 4979, false },
            { 1, "Gelihast", 0.54000000000000004, 0.57499999999999996, "26", 4353, 1773, false },
            { 2, "Lorgus Jett", 0.32500000000000001, 0.69999999999999996, "26", 12902, 12822, false },
            { 2, "Baron Aquanis", 0.41999999999999998, 0.71999999999999997, "28", 12876, 12876, false },
            { 2, "Twilight Lord Kelris", 0.52500000000000002, 0.81000000000000005, "27", 4400, 4939, false },
            { 2, "Aku'mai", 0.85499999999999998, 0.85999999999999999, "28", 4401, 2837, false },
            { 3, "Old Serra'kis", 0.58499999999999996, 0.28999999999999998, "26", 4360, 1816, false },
        },
        t = { { 1, 0.61499999999999999, 0.69999999999999996, nil, nil, 2 }, { 2, 0.46999999999999997, 0.69999999999999996, nil, "swim underwater to next level", 3 } },
    },
    blackrock_depths = {
        f = { { "@BlackrockDepths1", 0.97851600000000005, 0.65234400000000003, nil, 242 }, { "@BlackrockDepths2", 0.97851600000000005, 0.65234400000000003, nil, 243 } },
        e = { { 1, 0.32900000000000001, 0.79400000000000004, 0, "entrance" } },
        b = {
            { 1, "High Interrogator Gerstahn", 0.47399999999999998, 0.92200000000000004, "52", 9018, 8761, false },
            { 1, "Lord Roccor", 0.55600000000000005, 0.67000000000000004, "53", 9025, 5781, false },
            { 1, "Houndmaster Grebmar", 0.53500000000000003, 0.57299999999999995, "54", 9319, 9212, false },
            { 1, "Bael'Gar", 0.251, 0.53400000000000003, "56", 9016, 12162, false },
            { 1, "Lord Incendius", 0.56399999999999995, 0.311, "55", 9017, 1204, false },
            { 1, "Fineous Darkvire", 0.63500000000000001, 0.21099999999999999, "55", 9056, 8704, false },
            { 2, "Gorosh the Dervish", 0.53000000000000003, 0.86799999999999999, "54", 9031, 3004, "Ring of Law" },
            { 2, "Grizzle", 0.54700000000000004, 0.88300000000000001, "54", 9031, 3004, "Ring of Law" },
            { 2, "Eviscerator", 0.54700000000000004, 0.91300000000000003, "54", 9031, 3004, "Ring of Law" },
            { 2, "Ok'thor the Breaker", 0.53000000000000003, 0.92800000000000005, "54", 9031, 3004, "Ring of Law" },
            { 2, "Anub'shiah", 0.51300000000000001, 0.91300000000000003, "54", 9031, 3004, "Ring of Law" },
            { 2, "Hedrum the Creeper", 0.51300000000000001, 0.88300000000000001, "54", 9031, 3004, "Ring of Law" },
            { 2, "Pyromancer Loregrain", 0.54900000000000004, 0.94799999999999995, "54", 9024, 8762, false },
            { 2, "Warder Stilgiss", 0.60199999999999998, 0.65900000000000003, "55", 9041, 9089, false },
            { 2, "General Angerforge", 0.36299999999999999, 0.82299999999999995, "57", 8983, 8759, false },
            { 2, "Golem Lord Argelmach", 0.36399999999999999, 0.65100000000000002, "57", 8929, 8705, false },
            { 2, "Hurley Blackbreath", 0.505, 0.70399999999999996, "56", 9537, 8658, false },
            { 2, "Plugger Spazzring", 0.47699999999999998, 0.65700000000000003, "56", 9499, 8652, false },
            { 2, "Phalanx", 0.45800000000000002, 0.56399999999999995, "56", 9502, 8177, false },
            { 2, "Ambassador Flamelash", 0.53800000000000003, 0.48499999999999999, "57", 9156, 8329, false },
            { 2, "The Seven", 0.53800000000000003, 0.247, "57", 9938, 12162, false },
            { 2, "Magmus", 0.79600000000000004, 0.11799999999999999, "57", 9938, 12162, false },
            { 2, "Princess Moira Bronzebeard", 0.92000000000000004, 0.11, "58", 8929, 8705, false },
            { 2, "Emperor Dagran Thaurissan", 0.90900000000000003, 0.11799999999999999, "59", 8929, 8705, false },
        },
    },
    city_of_dalaran = {
        f = { { "@DalaranUnderbellyMap", 1, 0.66650399999999999 }, { "@DalaranCityMap", 1, 0.66650399999999999 } },
        e = { { 1, 0.19, 0.83799999999999997, 0, "entrance" } },
        b = {
            { 1, "Atrexis the Grave Knight", 0.53500000000000003, 0.505, "29", 247126, 145787, false },
            { 1, "Lyn the Ignored", 0.68000000000000005, 0.17699999999999999, "32", 247032, 130235, false },
            { 2, "Mana Devourer", 0.41599999999999998, 0.72999999999999998, "31", 246008, 129895, false },
            { 2, "Fel Ancient", 0.51300000000000001, 0.54900000000000004, "32", 246003, 129894, false },
            { 2, "Unstable Sentinel", 0.61399999999999999, 0.41299999999999998, "31", 246017, 129954, false },
            { 2, "Arcanic Enigma", 0.66900000000000004, 0.503, "30", 246016, 129900, false },
            { 2, "Arcane Anomaly", 0.52700000000000002, 0.84299999999999997, "30", 245999, 129891, false },
            { 2, "Shade of the Archmage", 0.52000000000000002, 0.23999999999999999, "33", 246020, 130061, false },
        },
        t = { { 1, 0.77800000000000002, 0.56399999999999995, nil, nil, 2 } },
    },
    dire_maul_east = {
        f = { { "@DireMaul6", 0.97851600000000005, 0.65234400000000003, nil, 240 }, { "@DireMaul5", 0.97851600000000005, 0.65234400000000003, nil, 239 } },
        e = { { 1, 0.28100000000000003, 0.55400000000000005, 180, "entrance" } },
        b = {
            { 2, "Lethtendris", 0.438, 0.48099999999999998, "57", 14327, 14378, false },
            { 1, "Zevrim Thornhoof", 0.57499999999999996, 0.74299999999999999, "57", 11490, 11335, false },
            { 1, "Hydrospawn", 0.53600000000000003, 0.71499999999999997, "57", 13280, 5489, false },
            { 1, "Alzzin the Wildshaper", 0.56599999999999995, 0.28799999999999998, "58", 11492, 14416, false },
        },
    },
    dire_maul_north = {
        f = { { "@DireMaul1", 0.97851600000000005, 0.65234400000000003, nil, 235 } },
        e = { { 1, 0.71699999999999997, 0.92400000000000004, 0, "entrance" } },
        b = {
            { 1, "Guard Mol'dar", 0.69499999999999995, 0.76000000000000001, "59", 14326, 11561, false },
            { 1, "Stomper Kreeg", 0.61199999999999999, 0.69199999999999995, "59", 14322, 11545, false },
            { 1, "Guard Fengus", 0.49399999999999999, 0.78000000000000003, "59", 14321, 11561, false },
            { 1, "Guard Slip'kik", 0.26600000000000001, 0.57099999999999995, "59", 14323, 11561, false },
            { 1, "Captain Kromcrush", 0.318, 0.50600000000000001, "61", 14325, 11564, false },
            { 1, "Cho'Rush the Observer", 0.29999999999999999, 0.28999999999999998, "60", 11501, 11583, "King Gordok & Cho'Rush" },
            { 1, "King Gordok", 0.31900000000000001, 0.22900000000000001, "62", 11501, 11583, "King Gordok & Cho'Rush" },
        },
    },
    dire_maul_west = {
        f = { { "@DireMaul2", 0.97851600000000005, 0.65234400000000003, nil, 236 }, { "@DireMaul3", 0.97851600000000005, 0.65234400000000003, nil, 237 }, { "@DireMaul4", 0.97851600000000005, 0.65234400000000003, nil, 238 } },
        e = { { 1, 0.93500000000000005, 0.50700000000000001, 180, "entrance" } },
        b = {
            { 1, "Tendris Warpwood", 0.33600000000000002, 0.53600000000000003, "60", 11489, 14383, false },
            { 1, "Illyanna Ravenoak", 0.20300000000000001, 0.77600000000000002, "60", 11488, 11270, false },
            { 2, "Magister Kalendris", 0.33800000000000002, 0.45000000000000001, "60", 11487, 14384, false },
            { 2, "Tsu'zee", 0.32200000000000001, 0.14299999999999999, "59", 11467, 11250, false },
            { 3, "Immol'thar", 0.34899999999999998, 0.57499999999999996, "61", 11496, 14173, false },
            { 3, "Prince Tortheldrin", 0.622, 0.23100000000000001, "61", 11486, 11256, false },
        },
    },
    excavation_site_wetlands = {
        f = { { "@ExcavationSiteMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.88800000000000001, 0.25800000000000001, 180, "entrance" } },
        b = {
            { 1, "Saltspine", 0.55000000000000004, 0.36099999999999999, "28", 260322, 144209, false },
            { 1, "Shadetooth", 0.30499999999999999, 0.48399999999999999, "29", 260325, 144210, false },
            { 1, "Relic Guardian", 0.32400000000000001, 0.68700000000000006, "31", 260326, 144224, false },
            { 1, "Highland Horror", 0.082000000000000003, 0.40500000000000003, "28", 260808, 9010, false, 95646 },
        },
        ti = { { 1, 0.26200000000000001, 0.66800000000000004, "Ardin Grassman" }, { 1, 0.073999999999999996, 0.497, "Daewyn Songblade" } },
    },
    gnomeregan = {
        f = { { "@Gnomeregan1", 0.97851600000000005, 0.65234400000000003, nil, 226 }, { "@Gnomeregan2", 0.97851600000000005, 0.65234400000000003, nil, 227 }, { "@Gnomeregan3", 0.97851600000000005, 0.65234400000000003, nil, 228 }, { "@Gnomeregan4", 0.97851600000000005, 0.65234400000000003, nil, 229 } },
        e = { { 1, 0.64200000000000002, 0.27800000000000002, 0, "entrance" } },
        b = {
            { 1, "Grubbis", 0.77600000000000002, 0.67100000000000004, "32", 7361, 6533, false },
            { 2, "Viscous Fallout", 0.76000000000000001, 0.46899999999999997, "30", 7079, 5497, false },
            { 2, "Electrocutioner 6000", 0.245, 0.68400000000000005, "32", 6235, 6915, false },
            { 3, "Crowd Pummeler 9-60", 0.434, 0.88300000000000001, "32", 6229, 6774, false },
            { 4, "Mekgineer Thermaplugg", 0.315, 0.29899999999999999, "34", 7800, 6980, false },
        },
        t = { { 1, 0.54500000000000004, 0.40899999999999997, nil, "jump down to floor 2", 2 }, { 1, 0.48699999999999999, 0.877, nil, nil, 2 }, { 2, 0.435, 0.81299999999999994, nil, nil, 3 }, { 3, 0.37, 0.71999999999999997, nil, nil, 4 }, { 4, 0.44, 0.72599999999999998, nil, nil, 3 } },
    },
    hall_of_thanes = {
        f = { { "@HallOfThanesMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.51000000000000001, 0.94399999999999995, 0, "entrance" } },
        b = {
            { 1, "Faldrim Anvilmar", 0.50900000000000001, 0.66800000000000004, "16", 261306, 142826, false },
            { 1, "Magmatus", 0.748, 0.47799999999999998, "16", 261316, 1070, false },
            { 1, "Plunder", 0.51000000000000001, 0.51500000000000001, "16", 261311, 142840, false },
            { 1, "Durgen Dirgehammer", 0.50900000000000001, 0.17000000000000001, "16", 261319, 142837, false },
        },
    },
    kroldok_stronghold = {
        f = { { "@KroldokMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.20499999999999999, 0.80700000000000005, 180, "entrance" } },
    },
    maraudon = {
        f = { { "@Maraudon1", 0.97851600000000005, 0.65234400000000003, nil, 280 }, { "@Maraudon2", 0.97851600000000005, 0.65234400000000003, nil, 281 } },
        e = { { 1, 0.61799999999999999, 0.28100000000000003, 0, "orange crystal entrance", { 1, 0.55000000000000004, 0.10000000000000001 } }, { 1, 0.76400000000000001, 0.65900000000000003, 0, "purple crystal entrance", { 0.78000000000000003, 0.45000000000000001, 1 } } },
        b = {
            { 1, "Noxxion", 0.36199999999999999, 0.098000000000000004, "48", 13280, 5489, false },
            { 1, "Razorlash", 0.16600000000000001, 0.34399999999999997, "48", 12258, 12389, false },
            { 1, "Lord Vyletongue", 0.378, 0.70399999999999996, "47", 12236, 12334, false },
            { 1, "Meshlok the Harvester", 0.246, 0.874, "48", 12237, 9014, false },
            { 2, "Celebras the Cursed", 0.245, 0.14299999999999999, "49", 12225, 12350, false },
            { 2, "Landslide", 0.40799999999999997, 0.48699999999999999, "50", 12203, 12293, false },
            { 2, "Tinkerer Gizlock", 0.48399999999999999, 0.68600000000000005, "50", 13601, 7125, false },
            { 2, "Rotgrip", 0.41299999999999998, 0.81699999999999995, "50", 13596, 13589, false },
            { 2, "Princess Theradras", 0.25800000000000001, 0.78800000000000003, "51", 12201, 12292, false },
        },
        ti = { { 2, 0.245, 0.14299999999999999, "Celebras the Redeemed" } },
    },
    ragefire_chasm = {
        f = { { "@Ragefire1", 0.97851600000000005, 0.65234400000000003, nil, 213 } },
        e = { { 1, 0.60999999999999999, 0.074999999999999997, 200, "entrance" } },
        b = {
            { 1, "Oggleflint", 0.56100000000000005, 0.378, "16", 4887, 5027, false },
            { 1, "Taragaman the Hungerer", 0.40500000000000003, 0.56999999999999995, "16", 4936, 7970, false },
            { 1, "Jergosh the Invoker", 0.34000000000000002, 0.81499999999999995, "16", 4938, 11429, false },
            { 1, "Bazzalan", 0.42199999999999999, 0.84199999999999997, "16", 4939, 2007, false },
        },
    },
    razorfen_downs = {
        f = { { "@RazorfenDowns1", 0.97851600000000005, 0.65234400000000003, nil, 300 } },
        e = { { 1, 0.23400000000000001, 0.185, 90, "entrance" } },
        b = {
            { 1, "Tuten'kash", 0.58899999999999997, 0.34200000000000003, "40", 7355, 7845, false },
            { 1, "Mordresh Fire Eye", 0.85999999999999999, 0.46700000000000003, "39", 7358, 7971, false },
            { 1, "Glutton", 0.34499999999999997, 0.66400000000000003, "40", 8567, 7864, false },
            { 1, "Amnennar the Coldbringer", 0.45500000000000002, 0.58199999999999996, "41", 7358, 7971, false },
        },
    },
    razorfen_kraul = {
        f = { { "@RazorfenKraul1", 0.97851600000000005, 0.65234400000000003, nil, 301 } },
        e = { { 1, 0.71399999999999997, 0.83999999999999997, 180, "entrance" } },
        b = {
            { 1, "Roogug", 0.64600000000000002, 0.42999999999999999, "28", 6168, 6168, false },
            { 1, "Aggem Thorncurse", 0.80800000000000005, 0.52100000000000002, "30", 6166, 6097, false },
            { 1, "Death Speaker Jargba", 0.876, 0.41899999999999998, "30", 6765, 4644, false },
            { 1, "Earthcaller Halmgar", 0.498, 0.47299999999999998, "32", 4842, 6102, false },
            { 1, "Overlord Ramtusk", 0.57599999999999996, 0.313, "32", 6168, 6168, false },
            { 1, "Charlga Razorflank", 0.221, 0.313, "33", 4421, 4642, false },
            { 1, "Agathelos the Raging", 0.082000000000000003, 0.68600000000000005, "33", 6510, 2450, false },
        },
        t = { { 1, 0.60599999999999998, 0.72499999999999998, nil, "wall jump the gate to reach roogug", nil, true }, { 1, 0.626, 0.56200000000000006, nil, "jump on this vine to reach roogug", nil, true } },
    },
    ruins_of_lordaeron = {
        f = { { "@RuinsOfLordaeronMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.61199999999999999, 0.214, 180, "entrance" } },
        b = {
            { 1, "Witherfang", 0.66800000000000004, 0.35999999999999999, "17", 250483, 144189, false },
            { 1, "The Baron", 0.61499999999999999, 0.65000000000000002, "17", 250660, 144188, false },
            { 1, "Viktor the Vile", 0.437, 0.78800000000000003, "19", 256035, 144170, false },
            { 1, "The Abandoned", 0.39500000000000002, 0.66500000000000004, "18", 250631, 144175, false },
            { 1, "Bjork", 0.34499999999999997, 0.22, "19", 256097, 144170, false },
            { 1, "Rath'mael", 0.52000000000000002, 0.59999999999999998, "20", 250657, 144175, false },
            { 1, "Lordaeron Captain", 0.5, 0.29999999999999999, "19", 255699, 144188, false },
        },
        ti = { { 1, 0.61199999999999999, 0.27200000000000002, "Captain Truman" } },
    },
    scarlet_monastery_armory = {
        f = { { "@ScarletMonastery3", 0.97851600000000005, 0.65234400000000003, nil, 304 } },
        e = { { 1, 0.60999999999999999, 0.94499999999999995, 0, "entrance" } },
        b = {
            { 1, "Herod", 0.78500000000000003, 0.11799999999999999, "40", 3975, 2041, false },
        },
    },
    scarlet_monastery_cathedral = {
        f = { { "@ScarletMonastery4", 0.97851600000000005, 0.65234400000000003, nil, 305 } },
        e = { { 1, 0.61799999999999999, 0.91500000000000004, 0, "entrance" } },
        b = {
            { 1, "High Inquisitor Fairbanks", 0.55500000000000005, 0.25, "40", 4542, 2605, false },
            { 1, "Scarlet Commander Mograine", 0.48999999999999999, 0.28499999999999998, "42", 3976, 2042, false },
            { 1, "High Inquisitor Whitemane", 0.48999999999999999, 0.16500000000000001, "42", 3977, 2043, false },
        },
    },
    scarlet_monastery_graveyard = {
        f = { { "@ScarletMonastery1", 0.97851600000000005, 0.65234400000000003, nil, 302 } },
        e = { { 1, 0.84099999999999997, 0.83099999999999996, 180, "entrance" } },
        b = {
            { 1, "Interrogator Vishas", 0.72399999999999998, 0.59999999999999998, "32", 3983, 2044, false },
            { 1, "Bloodmage Thalnos", 0.246, 0.56599999999999995, "34", 4543, 11396, false },
        },
    },
    scarlet_monastery_library = {
        f = { { "@ScarletMonastery2", 0.97851600000000005, 0.65234400000000003, nil, 303 } },
        b = {
            { 1, "Houndmaster Loksey", 0.30199999999999999, 0.84599999999999997, "34", 3974, 2040, false },
            { 1, "Arcanist Doan", 0.83499999999999996, 0.73999999999999999, "37", 6487, 5266, false },
        },
    },
    shadowfang_keep = {
        f = { { "@ShadowfangKeep1", 0.97851600000000005, 0.65234400000000003, nil, 310 }, { "@ShadowfangKeep7", 0.97851600000000005, 0.65234400000000003, nil, 316 }, { "@ShadowfangKeep6", 0.97851600000000005, 0.65234400000000003, nil, 315 } },
        e = { { 1, 0.70499999999999996, 0.60499999999999998, 0, "entrance" } },
        b = {
            { 1, "Rethilgore", 0.67000000000000004, 0.71499999999999997, "20", 3914, 524, false },
            { 1, "Fel Steed / Shadow Charger", 0.34499999999999997, 0.63500000000000001, "19-21", 3864, 1951, false },
            { 1, "Razorclaw the Butcher", 0.32700000000000001, 0.44700000000000001, "22", 3886, 524, false },
            { 1, "Baron Silverlaine", 0.16200000000000001, 0.80700000000000005, "24", 3887, 3222, false },
            { 2, "Deathsworn Captain", 0.63, 0.52500000000000002, "25", 3872, 3224, false },
            { 2, "Odo the Blindwatcher", 0.58299999999999996, 0.82799999999999996, "24", 4279, 522, false },
            { 3, "Fenrus the Devourer", 0.54600000000000004, 0.627, "25", 4274, 2352, false },
            { 3, "Arugal's Voidwalker", 0.49199999999999999, 0.70999999999999996, "24-25", 4627, 1131, false },
            { 3, "Wolf Master Nandos", 0.58999999999999997, 0.53300000000000003, "25", 3927, 11179, false },
            { 3, "Archmage Arugal", 0.68500000000000005, 0.33400000000000002, "24", 4275, 2353, false },
        },
        t = { { 1, 0.14499999999999999, 0.86399999999999999, "up", nil, 2 }, { 2, 0.51500000000000001, 0.91500000000000004, "up", nil, 3 } },
        ti = { { 1, 0.55800000000000005, 0.622, "Deathstalker Vincent" } },
    },
    shapers_terrace = {
        f = { { "@ShapersTerraceMap", 1, 0.66699200000000003 } },
    },
    stratholme_main = {
        f = { { "@Stratholme1", 0.97851600000000005, 0.65234400000000003, "crusaders' square (living)", 317 }, { "@Stratholme2", 0.97851600000000005, 0.65234400000000003, "the gauntlet (undead)", 318 } },
        e = { { 1, 0.67500000000000004, 0.877, 0, "main gate entrance" }, { 2, 0.65800000000000003, 0.90200000000000002, 0, "service gate entrance" } },
        b = {
            { 1, "Skul", 0.57399999999999995, 0.65200000000000002, "58", 10393, 2606, false },
            { 1, "Hearthsinger Forresten", 0.60499999999999998, 0.32700000000000001, "57", 10558, 10482, false },
            { 1, "The Unforgiven", 0.73399999999999999, 0.20399999999999999, "57", 10516, 10771, false },
            { 1, "Timmy the Cruel", 0.495, 0.17999999999999999, "58", 10808, 571, false },
            { 1, "Postmaster Malown", 0.55800000000000005, 0.68400000000000005, "60", 11143, 10669, false },
            { 1, "Cannon Master Willey", 0.042000000000000003, 0.51000000000000001, "60", 10997, 10674, "Willey Hopebreaker" },
            { 1, "Archivist Galford", 0.27200000000000002, 0.75, "60", 10811, 10544, "Instructor Galford" },
            { 1, "Balnazzar", 0.20399999999999999, 0.81799999999999995, "62", 10813, 10691, false },
            { 2, "Magistrate Barthilas", 0.56599999999999995, 0.161, "58", 10435, 10433, false },
            { 2, "Stonespine", 0.64900000000000002, 0.48899999999999999, "60", 10809, 7856, false },
            { 2, "Nerub'enkan", 0.57199999999999995, 0.46100000000000002, "60", 10437, 9793, false },
            { 2, "Baroness Anastari", 0.745, 0.46899999999999997, "59", 10436, 10698, false },
            { 2, "Maleki the Pallid", 0.67400000000000004, 0.22700000000000001, "61", 10438, 10546, false },
            { 2, "Ramstein the Gorger", 0.45600000000000002, 0.19800000000000001, "61", 10439, 12818, false },
            { 2, "Baron Rivendare", 0.372, 0.19900000000000001, "62", 10440, 10440, false },
        },
    },
    sunken_temple = {
        f = { { "@TheTempleOfAtalHakkar1", 0.97851600000000005, 0.65234400000000003, nil, 220 } },
        b = {
            { 1, "Avatar of Hakkar", 0.24299999999999999, 0.45900000000000002, "55", 8443, 8053, false },
            { 1, "Jammal'an the Prophet", 0.76000000000000001, 0.37, "54", 5710, 6708, false },
            { 1, "Ogom the Wretched", 0.78000000000000003, 0.38500000000000001, "53", 5711, 6709, false },
            { 1, "Dreamscythe", 0.42999999999999999, 0.86499999999999999, "53", 5721, 7553, "Dreamscythe & Weaver" },
            { 1, "Weaver", 0.47799999999999998, 0.82999999999999996, "51", 5721, 7553, "Dreamscythe & Weaver" },
            { 1, "Morphaz", 0.46100000000000002, 0.84499999999999997, "52", 5720, 6375, "Morphaz & Hazzas" },
            { 1, "Hazzas", 0.44800000000000001, 0.85099999999999998, "53", 5720, 6375, "Morphaz & Hazzas" },
            { 1, "Shade of Eranikus", 0.68600000000000005, 0.874, "55", 5709, 7806, false },
        },
    },
    the_deadmines = {
        f = { { "@TheDeadmines1", 0.97851600000000005, 0.65234400000000003, nil, 291 }, { "@TheDeadmines2", 0.97851600000000005, 0.65234400000000003, nil, 292 } },
        e = { { 1, 0.29499999999999998, 0.13500000000000001, -15, "entrance" } },
        b = {
            { 1, "Rhahk'Zor", 0.36499999999999999, 0.60999999999999999, "19", 644, 14403, false },
            { 1, "Miner Johnson", 0.53500000000000003, 0.52000000000000002, "19", 3586, 556, false },
            { 1, "Sneed's Shredder", 0.47499999999999998, 0.86499999999999999, "20", 642, 1269, false },
            { 1, "Sneed", 0.53500000000000003, 0.86499999999999999, "20", 643, 7125, false },
            { 2, "Gilnid", 0.122, 0.755, "20", 643, 7125, false },
            { 2, "Mr. Smite", 0.51500000000000001, 0.17000000000000001, "20", 646, 2026, false },
            { 2, "Captain Greenskin", 0.57499999999999996, 0.34999999999999998, "20", 647, 7113, false },
            { 2, "Edwin VanCleef", 0.60499999999999998, 0.45200000000000001, "21", 639, 2029, false },
            { 2, "Cookie", 0.66500000000000004, 0.42999999999999999, "20", 645, 1305, false },
        },
        t = { { 1, 0.61499999999999999, 0.60999999999999999, nil, nil, 2 } },
    },
    the_drowned_city = {
        f = { { "@DrownedCityMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.84599999999999997, 0.52100000000000002, 0, "entrance" } },
    },
    the_stockade = {
        f = { { "@TheStockade1", 0.97851600000000005, 0.65234400000000003, nil, 225 } },
        e = { { 1, 0.5, 0.81499999999999995, 0, "entrance" } },
        b = {
            { 1, "Targorr the Dread", 0.44, 0.44500000000000001, "24", 1696, 517, false },
            { 1, "Kam Deepfury", 0.32000000000000001, 0.38, "27", 1666, 825, false },
            { 1, "Hamhock", 0.78000000000000003, 0.45500000000000002, "28", 1717, 3250, false },
            { 1, "Bazil Thredd", 0.215, 0.255, "29", 1716, 1621, false },
            { 1, "Dextren Ward", 0.73499999999999999, 0.57499999999999996, "26", 1715, 2149, false },
            { 1, "Bruegal Ironknuckle", 0.5, 0.19, "26", 1720, 2142, false },
        },
    },
    uldaman = {
        f = { { "@Uldaman1", 0.97851600000000005, 0.65234400000000003, nil, 230 }, { "@Uldaman2", 0.97851600000000005, 0.65234400000000003, nil, 231 } },
        e = { { 1, 0.67900000000000005, 0.72499999999999998, 0, "entrance" } },
        b = {
            { 1, "The Lost Dwarves", 0.58399999999999996, 0.92000000000000004, "41", 6906, 5710, false },
            { 1, "Revelosh", 0.53400000000000003, 0.72499999999999998, "40", 6910, 5945, false },
            { 1, "Ironaya", 0.372, 0.73899999999999999, "40", 7228, 6089, false },
            { 1, "Ancient Stone Keeper", 0.47499999999999998, 0.44, "44", 7206, 10798, false },
            { 1, "Galgann Firehammer", 0.26700000000000002, 0.32700000000000001, "45", 7291, 6059, false },
            { 1, "Grimlok", 0.219, 0.25600000000000001, "45", 4854, 11165, false },
            { 2, "Archaedas", 0.55300000000000005, 0.504, "47", 2748, 5988, false },
        },
    },
    wailing_caverns = {
        f = { { "@WailingCavernsFull", 0.97851600000000005, 0.65234400000000003, nil, 279 } },
        e = { { 1, 0.46500000000000002, 0.58999999999999997, 200, "entrance" } },
        b = {
            { 1, "Lady Anacondra", 0.31, 0.42999999999999999, "20", 3671, 4313, false },
            { 1, "Kresh", 0.38500000000000001, 0.34999999999999998, "20", 3653, 5126, false },
            { 1, "Lord Cobrahn", 0.155, 0.56999999999999995, "20", 3669, 4213, false },
            { 1, "Lord Pythas", 0.85599999999999998, 0.28899999999999998, "21", 3670, 4214, false },
            { 1, "Skum", 0.92700000000000005, 0.79200000000000004, "21", 3674, 4203, false },
            { 1, "Deviate Faerie Dragon", 0.57999999999999996, 0.59999999999999998, "20", 5912, 1267, false },
            { 1, "Lord Serpentis", 0.61499999999999999, 0.53500000000000003, "21", 3673, 4215, false },
            { 1, "Verdan the Everliving", 0.54500000000000004, 0.46000000000000002, "21", 5775, 4256, false },
            { 1, "Mutanus the Devourer", 0.34499999999999997, 0.13, "22", 3654, 4088, false },
        },
    },
    zulfarrak = {
        f = { { "@ZulFarrakMap", 1, 0.66699200000000003 } },
        e = { { 1, 0.55200000000000005, 0.88, 0, "entrance" } },
        b = {
            { 1, "Antu'sul", 0.64600000000000002, 0.27600000000000002, "48", 8127, 7353, false },
            { 1, "Witch Doctor Zum'rah", 0.442, 0.17599999999999999, "46", 7271, 6434, false },
            { 1, "Shadowpriest Sezz'ziz", 0.29599999999999999, 0.17399999999999999, "47", 7275, 6441, false },
            { 1, "Gahz'rilla", 0.312, 0.41399999999999998, "46", 7273, 7271, false },
            { 1, "Zerillis", 0.54800000000000004, 0.40100000000000002, "45", 10082, 9293, false },
            { 1, "Sandarr Dunereaver", 0.52400000000000002, 0.42799999999999999, "45", 10080, 9291, false },
            { 1, "Dustwraith", 0.31, 0.16, "45", 10081, 9292, false },
            { 1, "Chief Ukorz Sandscalp", 0.42199999999999999, 0.32900000000000001, "48", 7267, 6439, false },
        },
    },
}

local function decode_map(raw)
    if not raw then return nil end
    local floors = {}
    for i, f in ipairs(raw.f or {}) do
        floors[i] = { texture = resolve_tex(f[1]), texRight = f[2], texBottom = f[3], name = f[4], uiMapID = f[5] }
    end
    local entrances = {}
    for i, e in ipairs(raw.e or {}) do
        entrances[i] = { floor = e[1], x = e[2], y = e[3], angle = e[4], label = e[5], color = e[6] }
    end
    local bosses = {}
    for i, b in ipairs(raw.b or {}) do
        local tn = (b[8] == false) and b[2] or b[8]
        bosses[i] = { floor = b[1], name = b[2], x = b[3], y = b[4], level = b[5], npcID = b[6], displayId = b[7], targetName = tn, quest = b[9] }
    end
    local transitions = {}
    for i, tr in ipairs(raw.t or {}) do
        transitions[i] = { floor = tr[1], x = tr[2], y = tr[3], dir = tr[4], label = tr[5], to = tr[6], note = tr[7] }
    end
    local turnins = {}
    for i, ti in ipairs(raw.ti or {}) do
        turnins[i] = { floor = ti[1], x = ti[2], y = ti[3], npc = ti[4] }
    end
    return {
        floors = floors,
        entrances = entrances,
        bosses = bosses,
        transitions = transitions,
        turnins = turnins,
    }
end

sfui.dj_camelot.maps = setmetatable({}, {
    __index = function(t, k)
        local raw = RAW_MAPS[k]
        if not raw then return nil end
        local d = decode_map(raw)
        t[k] = d
        return d
    end,
})

local RAW_QUEST_PINS = {
    blackfathom_deeps = {
        { 1, 0.32900000000000001, 0.41199999999999998, { { "Pitted Iron Chest", { { 971, "Knowledge in the Deeps", nil, { "loot" }, "blackfathom_deeps", 5359, "Lorgalis Manuscript", "MAP_OBJ_BFD_CHEST" } } } } },
        { 1, 0.20799999999999999, 0.753, { { "Argent Guard Thaelrid", { { 1198, "In Search of Thaelrid", nil, { "end" }, "blackfathom_deeps" }, { 1200, "Blackfathom Villainy", nil, { "start" }, "blackfathom_deeps" }, { 6561, "Blackfathom Villainy", nil, { "start" }, "blackfathom_deeps" } } } } },
        { 2, 0.40600000000000003, 0.80400000000000005, { { "Fathom Stone", { { 6921, "Amongst the Ruins", nil, { "loot" }, "blackfathom_deeps", 16762, "Fathom Core", "MAP_OBJ_BFD_FATHOM" } } } } },
    },
    blackrock_depths = {
        { 1, 0.50900000000000001, 0.84399999999999997, { { "Commander Gor'shak", { { 3982, "What Is Going On?", nil, { "start", "end" }, "blackrock_depths" }, { 3981, "Commander Gor'shak", 3982, { "end" }, "blackrock_depths" }, { 4001, "What Is Going On?", 4003, { "start" }, "blackrock_depths" } } }, { "Kharan Mighthammer", { { 4341, "Kharan Mighthammer", 4362, { "end" }, "blackrock_depths" }, { 4342, "Kharan's Tale", 4362, { "start", "end" }, "blackrock_depths" }, { 4361, "The Bearer of Bad News", 4362, { "start" }, "blackrock_depths" } } } } },
        { 1, 0.53200000000000003, 0.92800000000000005, { { "Marshal Windsor", { { 4322, "Jail Break!", nil, { "start" }, "blackrock_depths" }, { 4241, "Marshal Windsor", 4322, { "end" }, "blackrock_depths" }, { 4242, "Abandoned Hope", 4322, { "start" }, "blackrock_depths" }, { 4264, "A Crumpled Up Note", 4322, { "end" }, "blackrock_depths" }, { 4282, "A Shred of Hope", 4322, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.55100000000000005, 0.33100000000000002, { { "Spectral Chalice", { { 4083, "The Spectral Chalice", nil, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.69299999999999995, 0.37, { { "Core Fragment", { { 7848, "Attunement to the Core", nil, { "loot" }, "blackrock_depths", 18412, "Core Fragment" } } } } },
        { 2, 0.51400000000000001, 0.59099999999999997, { { "Mistress Nagmara", { { 4201, "The Love Potion", nil, { "start", "end" }, "blackrock_depths" } } }, { "Lokhtos Darkbargainer", { { 7604, "A Binding Contract", nil, { "end" }, "blackrock_depths" } } }, { "Private Rocknot", { { 4295, "Rocknot's Ale", nil, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.63200000000000001, 0.73199999999999998, { { "Heart of the Mountain", { { 4123, "The Heart of the Mountain", nil, { "loot" }, "blackrock_depths", 11309, "The Heart of the Mountain" } } }, { "Dark Coffer", { { 4083, "The Spectral Chalice", nil, { "loot" }, "blackrock_depths", 7910, "Star Ruby" } } } } },
        { 2, 0.61499999999999999, 0.94999999999999996, { { "Monument of Franclorn Forgewright", { { 3802, "Dark Iron Legacy", nil, { "end" }, "blackrock_depths" } } } } },
    },
    dire_maul_north = {
        { 1, 0.217, 0.52600000000000002, { { "Ogre Tannin Basket", { { 5518, "The Gordok Ogre Suit", nil, { "loot" }, "dire_maul_north", 18240, "Ogre Tannin" } } } } },
        { 1, 0.32100000000000001, 0.59899999999999998, { { "Knot Thimblejack", { { 5525, "Free Knot!", nil, { "start", "end" }, "dire_maul_north" }, { 5518, "The Gordok Ogre Suit", nil, { "start", "end" }, "dire_maul_north" } } } } },
    },
    dire_maul_west = {
        { 1, 0.48399999999999999, 0.53800000000000003, { { "Shen'dralar Ancient", { { 7461, "The Madness Within", nil, { "start", "end" }, "dire_maul_west" } } } } },
        { 3, 0.747, 0.113, { { "Lorekeeper Javon", { { 7506, "The Emerald Dream...", nil, { "end" }, "dire_maul_west" }, { 7504, "Holy Bologna: What the Light Won't Tell You", nil, { "end" }, "dire_maul_west" }, { 7505, "Frost Shock and You", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.80200000000000005, 0.114, { { "Lorekeeper Mykos", { { 7503, "The Greatest Race of Hunters", nil, { "end" }, "dire_maul_west" }, { 7501, "The Light and How To Swing It", nil, { "end" }, "dire_maul_west" }, { 7502, "Harnessing Shadows", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.73699999999999999, 0.17100000000000001, { { "Lorekeeper Lydros", { { 7463, "Arcane Refreshment", nil, { "start", "end" }, "dire_maul_west" }, { 7507, "Nostro's Compendium", nil, { "end" }, "dire_maul_west" }, { 7483, "Libram of Rapidity", nil, { "start", "end" }, "dire_maul_west" }, { 7484, "Libram of Focus", nil, { "start", "end" }, "dire_maul_west" }, { 7485, "Libram of Protection", nil, { "start", "end" }, "dire_maul_west" } } } } },
        { 3, 0.84499999999999997, 0.23000000000000001, { { "Lorekeeper Kildrath", { { 7500, "The Arcanist's Cookbook", nil, { "end" }, "dire_maul_west" }, { 7498, "Garona: A Study on Stealth and Treachery", nil, { "end" }, "dire_maul_west" }, { 7499, "Codex of Defense", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.57299999999999995, 0.27600000000000002, { { "The Prince's Chest", { { 7703, "Unfinished Gordok Business", nil, { "loot" }, "dire_maul_west", 18336, "Gauntlet of Gordok Might" } } } } },
    },
    excavation_site_wetlands = {
        { 1, 0.26200000000000001, 0.66800000000000004, { { "Ardin Grassman", { { 95647, "Lost in the Thicket Things", 95809, { "end" }, "excavation_site_wetlands" }, { 95809, "Heartwoven", nil, { "start" }, "excavation_site_wetlands" } } } } },
        { 1, 0.073999999999999996, 0.497, { { "Daewyn Songblade", { { 95772, "Songblade Search", nil, { "end" }, "excavation_site_wetlands" }, { 95795, "Fallen in the Fen", nil, { "start" }, "excavation_site_wetlands" } } } } },
    },
    gnomeregan = {
        { 1, 0.42699999999999999, 0.66000000000000003, { { "The Sparklematic 5200", { { 2951, "The Sparklematic 5200!", nil, { "start", "end" }, "gnomeregan" }, { 2945, "Grime-Encrusted Ring", 2948, { "end" }, "gnomeregan" }, { 2947, "Return of the Ring", 2948, { "start" }, "gnomeregan" }, { 2949, "Return of the Ring", 2950, { "start" }, "gnomeregan" } } } } },
        { 4, 0.35399999999999998, 0.17699999999999999, { { "Thermaplugg's Safe", { { 2841, "Rig Wars", nil, { "loot" }, "gnomeregan", 9153, "Rig Blueprints" } } } } },
    },
    ragefire_chasm = {
        { 1, 0.61799999999999999, 0.38700000000000001, { { "Maur Grimtotem", { { 5724, "Returning the Lost Satchel", nil, { "start" }, "ragefire_chasm" }, { 5722, "Searching for the Lost Satchel", 5724, { "end" }, "ragefire_chasm" } } } } },
    },
    razorfen_downs = {
        { 1, 0.77500000000000002, 0.152, { { "Belnistrasz", { { 3525, "Extinguishing the Idol", nil, { "start", "end" }, "razorfen_downs" }, { 3523, "Scourge of the Downs", 3525, { "start", "end" }, "razorfen_downs" } } } } },
        { 1, 0.46899999999999997, 0.223, { { "Belnistrasz's Brazier", { { 3525, "Extinguishing the Idol", nil, { "end" }, "razorfen_downs" } } } } },
    },
    razorfen_kraul = {
        { 1, 0.36399999999999999, 0.32400000000000001, { { "Willix the Importer", { { 1144, "Willix the Importer", nil, { "start", "end" }, "razorfen_kraul" } } }, { "Heralath Fallowbrook", { { 1142, "Mortality Wanes", nil, { "start" }, "razorfen_kraul" } } } } },
    },
    ruins_of_lordaeron = {
        { 1, 0.61199999999999999, 0.27200000000000002, { { "Captain Truman", { { 95250, "Abominable Creatures", nil, { "start", "end" }, "ruins_of_lordaeron" } } } } },
    },
    scarlet_monastery_graveyard = {
        { 1, 0.71899999999999997, 0.51400000000000001, { { "Vorrel Sengutz", { { 1051, "Vorrel's Revenge", nil, { "start" }, "scarlet_monastery_graveyard" } } } } },
    },
    scarlet_monastery_library = {
        { 1, 0.59299999999999997, 0.122, { { "Mythology of the Titans", { { 1050, "Mythology of the Titans", nil, { "loot" }, "scarlet_monastery_library", 5536, "Mythology of the Titans" } } } } },
        { 1, 0.82199999999999995, 0.14000000000000001, { { "Compendium of the Fallen", { { 1049, "Compendium of the Fallen", nil, { "loot" }, "scarlet_monastery_library", 5535, "Compendium of the Fallen" } } } } },
        { 1, 0.45400000000000001, 0.32200000000000001, { { "Beginnings of the Undead Threat", { { 1160, "Test of Lore", 1394, { "loot" }, "scarlet_monastery_library", 5861, "Beginnings of the Undead Threat" } } } } },
    },
    shadowfang_keep = {
        { 1, 0.33600000000000002, 0.55000000000000004, { { "Jordan's Hammer", { { 1654, "The Test of Righteousness", 1806, { "loot" }, "shadowfang_keep", 6895, "Jordan's Smithing Hammer" } } } } },
        { 1, 0.55800000000000005, 0.622, { { "Deathstalker Vincent", { { 1098, "Deathstalkers in Shadowfang", nil, { "end" }, "shadowfang_keep" } } } } },
        { 3, 0.47199999999999998, 0.79300000000000004, { { "The Book of Ur", { { 1013, "The Book of Ur", nil, { "loot" }, "shadowfang_keep", 6283, "The Book of Ur" } } } } },
    },
    stratholme_main = {
        { 1, 0.31, 0.40799999999999997, { { "Malor's Strongbox", { { 5122, "The Medallion of Faith", nil, { "loot" }, "stratholme_main", 12845, "Medallion of Faith" } } } } },
        { 1, 0.307, 0.81799999999999995, { { "Scarlet Archive", { { 5251, "The Archivist", nil, { "use" }, "stratholme_main" } } }, { "Unfinished Painting", { { 5848, "Of Love and Family", nil, { "loot" }, "stratholme_main", 14679, "Of Love and Family" } } } } },
        { 2, 0.69499999999999995, 0.14599999999999999, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.41399999999999998, 0.25800000000000001, { { "Menethil's Gift", { { 5463, "Menethil's Gift", nil, { "end" }, "stratholme_main" } } } } },
        { 2, 0.80300000000000005, 0.46300000000000002, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.53000000000000003, 0.52000000000000002, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.67800000000000005, 0.72899999999999998, { { "Aurius", { { 5122, "The Medallion of Faith", 5125, { "start", "end" }, "stratholme_main" }, { 5125, "Aurius' Reckoning", nil, { "start", "end" }, "stratholme_main" } } } } },
    },
    sunken_temple = {
        { 1, 0.501, 0.35799999999999998, { { "Altar of Hakkar", { { 3446, "Into the Depths", nil, { "end" }, "sunken_temple" } } } } },
        { 1, 0.501, 0.47699999999999998, { { "Idol of Hakkar", { { 3447, "Secret of the Circle", nil, { "end" }, "sunken_temple" } } } } },
        { 1, 0.71899999999999997, 0.80300000000000005, { { "Essence Font", { { 3373, "The Essence of Eranikus", nil, { "end" }, "sunken_temple" } } } } },
    },
    uldaman = {
        { 1, 0.20699999999999999, 0.34100000000000003, { { "Tablet of Will", { { 1139, "The Lost Tablets of Will", nil, { "loot" }, "uldaman", 5824, "Tablet of Will" } } }, { "Shadowforge Cache", { { 2201, "Find the Gems", nil, { "loot" }, "uldaman", 7669, "Shattered Necklace Ruby" }, { 2339, "Find the Gems and Power Source", nil, { "loot" }, "uldaman", 7669, "Shattered Necklace Ruby" } } } } },
        { 1, 0.53300000000000003, 0.63800000000000001, { { "Remains of a Paladin", { { 2200, "Back to Uldaman", nil, { "end" }, "uldaman" }, { 2201, "Find the Gems", nil, { "start" }, "uldaman" }, { 2284, "Necklace Recovery, Take 2", nil, { "end" }, "uldaman" }, { 2318, "Translating the Journal", 2339, { "start" }, "uldaman" } } } } },
        { 1, 0.316, 0.71899999999999997, { { nil, { { 2240, "The Hidden Chamber", nil, { "explore" }, "uldaman" } } } } },
        { 1, 0.63800000000000001, 0.94799999999999995, { { "Baelog", { { 2398, "The Lost Dwarves", nil, { "end" }, "uldaman" }, { 2240, "The Hidden Chamber", nil, { "start" }, "uldaman" } } }, { "Conspicuous Urn", { { 2201, "Find the Gems", nil, { "loot" }, "uldaman", 7671, "Shattered Necklace Topaz" }, { 2339, "Find the Gems and Power Source", nil, { "loot" }, "uldaman", 7671, "Shattered Necklace Topaz" } } } } },
        { 2, 0.501, 0.33100000000000002, { { "The Discs of Norgannon", { { 2278, "The Platinum Discs", nil, { "start", "end" }, "uldaman" }, { 2279, "The Platinum Discs", nil, { "start" }, "uldaman" }, { 2280, "The Platinum Discs", nil, { "start" }, "uldaman" } } } } },
    },
}

local function decode_pins(rawList)
    if not rawList then return nil end
    local out = {}
    for i, p in ipairs(rawList) do
        local spots = {}
        for j, sp in ipairs(p[4] or {}) do
            local quests = {}
            for k, qit in ipairs(sp[2] or {}) do
                quests[k] = {
                    id = qit[1], name = qit[2], main = qit[3], acts = qit[4],
                    dungeon = qit[5], item = qit[6], itemName = qit[7], textKey = qit[8],
                }
            end
            spots[j] = { name = sp[1], quests = quests }
        end
        out[i] = { floor = p[1], x = p[2], y = p[3], spots = spots }
    end
    return out
end

sfui.dj_camelot.mapQuestPins = setmetatable({}, {
    __index = function(t, k)
        local raw = RAW_QUEST_PINS[k]
        if not raw then return nil end
        local d = decode_pins(raw)
        t[k] = d
        return d
    end,
})

sfui.dj_camelot.turninSpots = {
    { label = "General Marcus Jonathan — Valley of Heroes, Stormwind", mapID = 1453, targetName = "General Marcus Jonathan", x = 0.68999999999999995, y = 0.82799999999999996 },
    { label = "Lady Dena Kennedy — Stormwind Keep, Stormwind", mapID = 1453, targetName = "Lady Dena Kennedy", x = 0.69199999999999995, y = 0.27700000000000002 },
    { label = "Orphan Matron Nightingale — Cathedral Square, Stormwind", mapID = 1453, targetName = "Orphan Matron Nightingale", x = 0.56200000000000006, y = 0.54000000000000004 },
    { label = "Oran Snakewrithe — Magic Quarter, Undercity", mapID = 1458, targetName = "Oran Snakewrithe", x = 0.73299999999999998, y = 0.32600000000000001 },
}

local RAW_ROUTES = {
    hall_of_thanes = {
        faction = "Horde",
        title = "Horde Route to Hall of Thanes",
        subtitle = "Horde route",
        steps = { { map = { detail = "The Undercity zeppelin docks at the tower outside Orgrimmar. Ask Frezza if you're unsure which one it is.", label = "Zeppelin to Undercity", mapID = 1411, markerType = "location", x = 0.50800000000000001, y = 0.13500000000000001 }, title = "If you're not Undead, take the Zeppelin from Orgrimmar to Undercity", unnumbered = true }, { text = "Travel south from Undercity through Tirisfal Glades and Silverpine Forest, then continue into Hillsbrad Foothills until you reach Tarren Mill.", title = "Undercity -> Silverpine Forest -> Tarren Mill" }, { text = "Ride east along the road into Arathi Highlands, then follow it south toward the big stone bridge.", title = "Tarren Mill -> Arathi Highlands" }, { text = "This huge bridge crosses the gorge into the Wetlands, and it is your gateway into Alliance territory.", title = "Thandol Span (Arathi Highlands / Wetlands border)" }, { text = "Stay on the main road heading south-east. The road is the safest path, so stick to it all the way.", title = "Wetlands" }, { text = "This mountain pass leads into Loch Modan. Alliance guards stand at the checkpoint, so keep running and let your speed carry you through.", title = "Dun Algaz (Wetlands / Loch Modan border)" }, { text = "Head west to the tunnel that connects Loch Modan to Dun Morogh. Keep moving through the gate and continue west toward Ironforge.", title = "Loch Modan -> Dun Morogh" }, { text = "Take off your gear. Guards will likely kill you a few times, and unequipped gear takes no durability damage.", title = "Before entering Ironforge (Dun Morogh)" }, { text = "Head to the High Seat, King Magni's throne room. As you walk in, take the spiderweb-covered corridor on your left, at coordinates 43.5, 52.0.", title = "Ironforge" }, { text = "The Spirit Healer is right outside the city, so each death means a short run back. Resurrect in quiet corners out of the guards' sight so you gain ground every time.", title = "Corpse Running" }, { text = "Follow the winding stairs and stone paths downward. The path ends at a bridge over lava with the quest giver Thom Filch and the dungeon portal.", title = "Old Ironforge" } },
        mapID = 1415,
        waypoints = { { icon = "flightpath", mapID = 1424, textKey = "ROUTE_FP_TARREN_MILL_TEXT", titleKey = "ROUTE_FP_TARREN_MILL", x = 0.60629999999999995, y = 0.20280000000000001 } },
        pts = "1420:0.61729999999999996:0.65939999999999999;1420:0.61839999999999995:0.64600000000000002;1420:0.61960000000000004:0.63249999999999995;1420:0.62029999999999996:0.61750000000000005:1;1420:0.61129999999999995:0.62229999999999996;1420:0.60229999999999995:0.62909999999999999;1420:0.59330000000000005:0.63570000000000004;1420:0.58430000000000004:0.64159999999999995;1420:0.57530000000000003:0.64649999999999996;1420:0.5675:0.65339999999999998;1420:0.56130000000000002:0.66390000000000005;1420:0.55720000000000003:0.6774;1420:0.5544:0.69089999999999996;1420:0.55249999999999999:0.70430000000000004;1420:0.54910000000000003:0.71679999999999999;1420:0.54459999999999997:0.72909999999999997;1421:0.67120000000000002:0.045699999999999998;1421:0.66720000000000002:0.057500000000000002;1421:0.66020000000000001:0.067799999999999999;1421:0.6522:0.075399999999999995;1421:0.64419999999999999:0.081699999999999995;1421:0.63580000000000003:0.088499999999999995;1421:0.62870000000000004:0.097600000000000006;1421:0.62029999999999996:0.1052;1421:0.61129999999999995:0.1106;1421:0.60229999999999995:0.11459999999999999;1421:0.59330000000000005:0.1178;1421:0.58430000000000004:0.12139999999999999;1421:0.57530000000000003:0.1265;1421:0.56740000000000002:0.1346;1421:0.5605:0.14449999999999999;1421:0.55449999999999999:0.15490000000000001;1421:0.54900000000000004:0.16689999999999999;1421:0.54369999999999996:0.1789;1421:0.53769999999999996:0.19089999999999999;1421:0.53139999999999998:0.20280000000000001;1421:0.5252:0.21479999999999999;1421:0.51890000000000003:0.2268;1421:0.51339999999999997:0.23880000000000001;1421:0.50829999999999997:0.25069999999999998;1421:0.503:0.26269999999999999;1421:0.49890000000000001:0.2762;1421:0.49740000000000001:0.28970000000000001;1421:0.49790000000000001:0.3044;1421:0.50590000000000002:0.30969999999999998;1421:0.51149999999999995:0.31809999999999999;1421:0.51249999999999996:0.33160000000000001;1421:0.51039999999999996:0.34589999999999999;1421:0.51039999999999996:0.35999999999999999;1421:0.51500000000000001:0.3735;1421:0.52090000000000003:0.38550000000000001;1421:0.52590000000000003:0.39750000000000002;1421:0.52810000000000001:0.41089999999999999;1421:0.52839999999999998:0.4244;1421:0.52839999999999998:0.43790000000000001;1421:0.52800000000000002:0.45129999999999998;1421:0.52690000000000003:0.46479999999999999;1421:0.52439999999999998:0.4783;1421:0.52129999999999999:0.49180000000000001;1421:0.51980000000000004:0.50519999999999998;1421:0.52059999999999995:0.51870000000000005;1421:0.52300000000000002:0.53220000000000001;1421:0.52559999999999996:0.54569999999999996;1421:0.52829999999999999:0.55910000000000004;1421:0.53059999999999996:0.5726;1421:0.53300000000000003:0.58609999999999995;1421:0.53610000000000002:0.59960000000000002;1421:0.53949999999999998:0.61299999999999999;1421:0.54120000000000001:0.62649999999999995;1421:0.54139999999999999:0.64000000000000001;1421:0.54110000000000003:0.65339999999999998;1421:0.54059999999999997:0.66690000000000005;1421:0.53990000000000005:0.6804;1421:0.53910000000000002:0.69389999999999996;1421:0.53839999999999999:0.70730000000000004;1421:0.53749999999999998:0.7208;1421:0.53920000000000001:0.73429999999999995;1421:0.54430000000000001:0.74629999999999996;1421:0.55049999999999999:0.75619999999999998;1421:0.55840000000000001:0.7651;1421:0.56640000000000001:0.77170000000000005;1421:0.57530000000000003:0.77710000000000001;1421:0.58430000000000004:0.78010000000000002;1421:0.59330000000000005:0.78190000000000004;1421:0.60229999999999995:0.78310000000000002;1421:0.61129999999999995:0.78449999999999998;1421:0.62029999999999996:0.78520000000000001;1421:0.62919999999999998:0.78549999999999998;1421:0.63819999999999999:0.7873;1421:0.6472:0.79059999999999997;1421:0.65620000000000001:0.79569999999999996;1421:0.66520000000000001:0.8014;1421:0.67710000000000004:0.80459999999999998;1424:0.14019999999999999:0.45729999999999998;1424:0.1492:0.46100000000000002;1424:0.15820000000000001:0.46179999999999999;1424:0.16719999999999999:0.46160000000000001;1424:0.17610000000000001:0.46079999999999999;1424:0.18509999999999999:0.46029999999999999;1424:0.19409999999999999:0.46029999999999999;1424:0.2031:0.46100000000000002;1424:0.21210000000000001:0.4627;1424:0.22109999999999999:0.46479999999999999;1424:0.23000000000000001:0.46750000000000003;1424:0.23899999999999999:0.47020000000000001;1424:0.248:0.47270000000000001;1424:0.25700000000000001:0.47489999999999999;1424:0.26600000000000001:0.47839999999999999;1424:0.27500000000000002:0.48480000000000001;1424:0.28289999999999998:0.49099999999999999;1424:0.29189999999999999:0.49519999999999997;1424:0.3009:0.4975;1424:0.30990000000000001:0.49980000000000002;1424:0.31890000000000002:0.50080000000000002;1424:0.32779999999999998:0.49880000000000002;1424:0.33679999999999999:0.49590000000000001;1424:0.3458:0.49330000000000002;1424:0.3548:0.48980000000000001;1424:0.36380000000000001:0.48520000000000002;1424:0.37280000000000002:0.48020000000000002;1424:0.38169999999999998:0.47549999999999998;1424:0.39069999999999999:0.4703;1424:0.3997:0.46489999999999998;1424:0.40870000000000001:0.45860000000000001;1424:0.41670000000000001:0.4521;1424:0.42470000000000002:0.4456;1424:0.43259999999999998:0.43890000000000001;1424:0.44059999999999999:0.43149999999999999;1424:0.4486:0.42420000000000002;1424:0.45660000000000001:0.41610000000000003;1424:0.46460000000000001:0.40749999999999997;1424:0.47260000000000002:0.4002;1424:0.48149999999999998:0.39550000000000002;1424:0.49049999999999999:0.39279999999999998;1424:0.4995:0.39150000000000001;1424:0.50849999999999995:0.39119999999999999;1424:0.51749999999999996:0.38940000000000002;1424:0.52639999999999998:0.38619999999999999;1424:0.53539999999999999:0.3821;1424:0.5444:0.37709999999999999;1424:0.55289999999999995:0.372;1424:0.56040000000000001:0.36599999999999999:1;1424:0.56410000000000005:0.35870000000000002;1424:0.56000000000000005:0.34660000000000002;1424:0.56069999999999998:0.33310000000000001;1424:0.56200000000000006:0.3196;1424:0.56110000000000004:0.30609999999999998;1424:0.55889999999999995:0.29270000000000002;1424:0.55730000000000002:0.2792;1424:0.55630000000000002:0.26569999999999999;1424:0.55610000000000004:0.25219999999999998;1424:0.55640000000000001:0.23880000000000001;1424:0.55640000000000001:0.2253;1424:0.55640000000000001:0.21179999999999999;1424:0.55959999999999999:0.19950000000000001;1424:0.56840000000000002:0.1961;1424:0.57730000000000004:0.1956;1424:0.58599999999999997:0.20080000000000001;1424:0.59350000000000003:0.2087;1424:0.60250000000000004:0.20910000000000001;1424:0.60629999999999995:0.20280000000000001:1;1424:0.59919999999999995:0.2099;1424:0.5907:0.20580000000000001;1424:0.58320000000000005:0.19819999999999999;1424:0.57440000000000002:0.1956;1424:0.56540000000000001:0.1963;1424:0.55759999999999998:0.2034;1424:0.55640000000000001:0.21779999999999999;1424:0.55640000000000001:0.23130000000000001;1424:0.55630000000000002:0.24479999999999999;1424:0.55610000000000004:0.25819999999999999;1424:0.55669999999999997:0.2717;1424:0.55800000000000005:0.28520000000000001;1424:0.55989999999999995:0.29870000000000002;1424:0.56200000000000006:0.31209999999999999;1424:0.56169999999999998:0.3256;1424:0.56000000000000005:0.33910000000000001;1424:0.56120000000000003:0.35249999999999998;1424:0.56540000000000001:0.36430000000000001;1424:0.56040000000000001:0.36599999999999999:1;1424:0.56940000000000002:0.36599999999999999;1424:0.57830000000000004:0.36909999999999998;1424:0.58630000000000004:0.37619999999999998;1424:0.59430000000000005:0.38550000000000001;1424:0.60229999999999995:0.3952;1424:0.61029999999999995:0.40429999999999999;1424:0.61829999999999996:0.41149999999999998;1424:0.62719999999999998:0.4163;1424:0.63619999999999999:0.41820000000000002;1424:0.6452:0.41970000000000002;1424:0.6542:0.42470000000000002;1424:0.66210000000000002:0.43290000000000001;1424:0.66959999999999997:0.44319999999999998;1424:0.67710000000000004:0.45229999999999998;1424:0.68610000000000004:0.4587;1424:0.69510000000000005:0.46350000000000002;1424:0.70409999999999995:0.46860000000000002;1424:0.71309999999999996:0.47449999999999998;1424:0.72209999999999996:0.48110000000000003;1424:0.72999999999999998:0.4874;1424:0.73799999999999999:0.49440000000000001;1424:0.746:0.50239999999999996;1424:0.754:0.51149999999999995;1424:0.76200000000000001:0.52090000000000003;1424:0.77000000000000002:0.53000000000000003;1424:0.77790000000000004:0.53749999999999998;1424:0.78690000000000004:0.54300000000000004;1424:0.79590000000000005:0.54759999999999998;1424:0.80489999999999995:0.55310000000000004;1424:0.81389999999999996:0.55759999999999998;1417:0.21310000000000001:0.30459999999999998;1417:0.21609999999999999:0.31659999999999999;1417:0.2218:0.3286;1417:0.2258:0.34210000000000002;1417:0.22739999999999999:0.35549999999999998;1417:0.22800000000000001:0.36899999999999999;1417:0.22819999999999999:0.38250000000000001;1417:0.22919999999999999:0.39600000000000002;1417:0.23130000000000001:0.40939999999999999;1417:0.2341:0.4229;1417:0.2384:0.43490000000000001;1417:0.24410000000000001:0.44540000000000002;1417:0.25019999999999998:0.45579999999999998;1417:0.25580000000000003:0.46779999999999999;1417:0.2606:0.4798;1417:0.2666:0.49099999999999999;1417:0.27500000000000002:0.49869999999999998;1417:0.28389999999999999:0.50219999999999998;1417:0.29289999999999999:0.50580000000000003;1417:0.3019:0.51060000000000005;1417:0.31090000000000001:0.51639999999999997;1417:0.31990000000000002:0.51970000000000005;1417:0.32879999999999998:0.52059999999999995;1417:0.33779999999999999:0.52210000000000001;1417:0.3468:0.52380000000000004;1417:0.35580000000000001:0.52480000000000004;1417:0.36480000000000001:0.52649999999999997;1417:0.37380000000000002:0.5302;1417:0.38269999999999998:0.53620000000000001;1417:0.39069999999999999:0.54269999999999996;1417:0.3997:0.54820000000000002;1417:0.40870000000000001:0.55010000000000003;1417:0.41770000000000002:0.55010000000000003;1417:0.42659999999999998:0.55110000000000003;1417:0.43469999999999998:0.5575;1417:0.44130000000000003:0.56810000000000005;1417:0.4471:0.57930000000000004;1417:0.4496:0.58760000000000001:1;1417:0.45240000000000002:0.60099999999999998;1417:0.45079999999999998:0.61450000000000005;1417:0.44729999999999998:0.628;1417:0.44319999999999998:0.64149999999999996;1417:0.43890000000000001:0.65490000000000004;1417:0.43480000000000002:0.66839999999999999;1417:0.43090000000000001:0.68189999999999995;1417:0.42799999999999999:0.69540000000000002;1417:0.42730000000000001:0.70879999999999999;1417:0.42980000000000002:0.72230000000000005;1417:0.434:0.73429999999999995;1417:0.43830000000000002:0.74629999999999996;1417:0.44180000000000003:0.75970000000000004;1417:0.44379999999999997:0.7732;1417:0.44690000000000002:0.78590000000000004;1417:0.44950000000000001:0.79869999999999997;1417:0.4481:0.81210000000000004;1417:0.44679999999999997:0.8256;1417:0.4451:0.83909999999999996;1417:0.44490000000000002:0.85250000000000004;1417:0.44779999999999998:0.86539999999999995;1417:0.45429999999999998:0.87580000000000002;1417:0.46100000000000002:0.88480000000000003;1417:0.46389999999999998:0.8982;1417:0.46400000000000002:0.9123;1417:0.46100000000000002:0.92500000000000004;1417:0.45619999999999999:0.93789999999999996;1417:0.45629999999999998:0.95130000000000003;1417:0.45729999999999998:0.96479999999999999;1417:0.45679999999999998:0.97829999999999995;1417:0.45760000000000001:0.98880000000000001;1437:0.51549999999999996:0.060600000000000001;1437:0.51180000000000003:0.074099999999999999;1437:0.51219999999999999:0.087599999999999997;1437:0.51300000000000001:0.10100000000000001;1437:0.51119999999999999:0.1143;1437:0.50749999999999995:0.12690000000000001;1437:0.50570000000000004:0.14000000000000001;1437:0.50739999999999996:0.15340000000000001;1437:0.50749999999999995:0.16689999999999999;1437:0.50670000000000004:0.1804;1437:0.50660000000000005:0.19389999999999999;1437:0.50549999999999995:0.20730000000000001;1437:0.50380000000000003:0.2208;1437:0.50209999999999999:0.23430000000000001;1437:0.50070000000000003:0.24779999999999999;1437:0.49659999999999999:0.25969999999999999;1437:0.4914:0.2717;1437:0.48980000000000001:0.28520000000000001;1437:0.49049999999999999:0.29870000000000002;1437:0.49109999999999998:0.31209999999999999;1437:0.49249999999999999:0.3256;1437:0.49840000000000001:0.33689999999999998;1437:0.50329999999999997:0.34960000000000002;1437:0.50470000000000004:0.36330000000000001;1437:0.5111:0.37469999999999998;1437:0.51859999999999995:0.38400000000000001;1437:0.52629999999999999:0.39250000000000002;1437:0.53100000000000003:0.40489999999999998;1437:0.53280000000000005:0.41830000000000001;1437:0.54039999999999999:0.4264;1437:0.54769999999999996:0.43640000000000001;1437:0.55420000000000003:0.4476;1437:0.56069999999999998:0.45750000000000002;1437:0.56710000000000005:0.46739999999999998;1437:0.57130000000000003:0.48010000000000003;1437:0.57050000000000001:0.49480000000000002;1437:0.56940000000000002:0.50819999999999999;1437:0.56899999999999995:0.52170000000000005;1437:0.57089999999999996:0.53520000000000001;1437:0.57340000000000002:0.54810000000000003;1437:0.57489999999999997:0.56220000000000003;1437:0.57820000000000005:0.5756;1437:0.58050000000000002:0.58909999999999996;1437:0.57999999999999996:0.60250000000000004;1437:0.58020000000000005:0.61599999999999999;1437:0.58389999999999997:0.62949999999999995;1437:0.58730000000000004:0.64300000000000002;1437:0.5867:0.65639999999999998;1437:0.58509999999999995:0.66990000000000005;1437:0.58189999999999997:0.68340000000000001;1437:0.57609999999999995:0.69389999999999996;1437:0.56840000000000002:0.70089999999999997;1437:0.55940000000000001:0.70640000000000003;1437:0.55359999999999998:0.7167;1437:0.55069999999999997:0.7298;1437:0.5514:0.73729999999999996;1432:0.25600000000000001:0.087599999999999997;1432:0.25619999999999998:0.1004;1432:0.25469999999999998:0.1145;1432:0.25559999999999999:0.128;1432:0.25750000000000001:0.14149999999999999;1432:0.2596:0.15490000000000001;1432:0.26029999999999998:0.16839999999999999;1432:0.26000000000000001:0.18190000000000001;1432:0.2606:0.19539999999999999;1432:0.26279999999999998:0.20880000000000001;1432:0.2651:0.22270000000000001;1432:0.26300000000000001:0.2253:1;1432:0.255:0.21909999999999999;1432:0.247:0.2097;1432:0.23899999999999999:0.20130000000000001;1432:0.23100000000000001:0.1946;1432:0.22309999999999999:0.18820000000000001;1432:0.21510000000000001:0.18160000000000001;1432:0.20710000000000001:0.1754;1432:0.1981:0.1726;1432:0.18890000000000001:0.17299999999999999;1432:0.18509999999999999:0.16839999999999999;1426:0.84379999999999999:0.30009999999999998;1426:0.84699999999999998:0.31209999999999999;1426:0.84460000000000002:0.32519999999999999;1426:0.84130000000000005:0.33779999999999999;1426:0.83709999999999996:0.35039999999999999;1426:0.83489999999999998:0.36409999999999998;1426:0.83840000000000003:0.37680000000000002;1426:0.83909999999999996:0.38990000000000002;1426:0.83379999999999999:0.40229999999999999;1426:0.82769999999999999:0.41389999999999999;1426:0.81889999999999996:0.42049999999999998;1426:0.81010000000000004:0.4269;1426:0.80479999999999996:0.43809999999999999;1426:0.80220000000000002:0.4511;1426:0.79730000000000001:0.46239999999999998;1426:0.79200000000000004:0.4738;1426:0.78739999999999999:0.48559999999999998;1426:0.78090000000000004:0.49480000000000002;1426:0.77200000000000002:0.49869999999999998;1426:0.76300000000000001:0.496;1426:0.754:0.49390000000000001;1426:0.745:0.4965;1426:0.73599999999999999:0.49859999999999999;1426:0.72699999999999998:0.4985;1426:0.71809999999999996:0.4985;1426:0.70960000000000001:0.50349999999999995;1426:0.70109999999999995:0.50919999999999999;1426:0.69210000000000005:0.51170000000000004;1426:0.6835:0.51570000000000005;1426:0.67410000000000003:0.51970000000000005;1426:0.66420000000000001:0.51829999999999998;1426:0.6552:0.51349999999999996;1426:0.6462:0.51180000000000003;1426:0.63719999999999999:0.51700000000000002;1426:0.62829999999999997:0.52059999999999995;1426:0.62350000000000005:0.53110000000000002;1426:0.62029999999999996:0.54369999999999996;1426:0.61219999999999997:0.54959999999999998;1426:0.60329999999999995:0.54749999999999999;1426:0.59530000000000005:0.53939999999999999;1426:0.58730000000000004:0.53269999999999995;1426:0.57879999999999998:0.5282;1426:0.57289999999999996:0.51719999999999999;1426:0.5716:0.50370000000000004;1426:0.56940000000000002:0.49030000000000001;1426:0.5645:0.47870000000000001;1426:0.55740000000000001:0.46970000000000001;1426:0.54959999999999998:0.4627;1426:0.54110000000000003:0.45679999999999998;1426:0.53139999999999998:0.45939999999999998;1426:0.52380000000000004:0.46689999999999998;1426:0.51539999999999997:0.47270000000000001;1426:0.50549999999999995:0.4713;1426:0.4965:0.46550000000000002;1426:0.48849999999999999:0.45889999999999997;1426:0.47949999999999998:0.45240000000000002;1426:0.47220000000000001:0.44319999999999998;1426:0.46929999999999999:0.43049999999999999;1426:0.47370000000000001:0.41839999999999999;1426:0.48249999999999998:0.41339999999999999;1426:0.49149999999999999:0.40870000000000001;1426:0.50049999999999994:0.40339999999999998;1426:0.50839999999999996:0.3957;1426:0.51439999999999997:0.38400000000000001;1426:0.51839999999999997:0.3705;1426:0.52180000000000004:0.35770000000000002;1426:0.52700000000000002:0.34549999999999997;1426:0.53639999999999999:0.33910000000000001;1455:0.18959999999999999:0.82340000000000002;1455:0.22750000000000001:0.77539999999999998;1455:0.26950000000000002:0.75449999999999995;1455:0.31740000000000002:0.74399999999999999;1455:0.35930000000000001:0.72460000000000002;1455:0.39219999999999999:0.68559999999999999;1455:0.41620000000000001:0.63619999999999999;1455:0.42909999999999998:0.58679999999999999;1455:0.43509999999999999:0.53890000000000005;1455:0.43509999999999999:0.51949999999999996",
    },
    ruins_of_lordaeron = {
        faction = "Alliance",
        title = "Alliance Route to Ruins of Lordaeron",
        subtitle = "Alliance route",
        steps = { { map = { detail = "The Auberdine ship leaves from the southernmost dock, Dock 1, in Stormwind Harbor.", label = "Auberdine Ship, Stormwind Harbor", mapID = 1453, markerType = "location", x = 0.22800000000000001, y = 0.56000000000000005 }, text = "Head to Stormwind Harbor and take the boat to Auberdine. Once you arrive, go to the opposite side of the Auberdine docks and board the ship to Menethil Harbor. Do not get off at Menethil Harbor, stay on the same ship and it will continue to Southshore in Hillsbrad Foothills.", title = "Go to Stormwind Harbor" }, { showRoute = true, text = "Leave Southshore and follow the road toward Hillsbrad Fields. From there, continue north toward Dalaran.", title = "Follow the road from Southshore" }, { text = "Continue north and go around Dalaran until you reach Lordamere Lake. You do not need to enter Dalaran.", title = "Pass around Dalaran" }, { text = "Swim north across Lordamere Lake, passing from the Silverpine area into Tirisfal Glades.", title = "Swim north through Lordamere Lake" }, { text = "Once you reach Tirisfal Glades, follow the road toward Undercity. Once you enter Undercity, turn left and go upstairs, there's the dungeon entrance.", title = "Follow the road to Undercity" } },
        mapID = 1415,
        pts = "1424:0.50449999999999995:0.61750000000000005;1424:0.50629999999999997:0.60399999999999998;1424:0.50600000000000001:0.59060000000000001;1424:0.50509999999999999:0.57709999999999995;1424:0.50519999999999998:0.56359999999999999;1424:0.50649999999999995:0.55459999999999998:1;1424:0.49099999999999999:0.52029999999999998;1424:0.4859:0.50900000000000001;1424:0.48089999999999999:0.49780000000000002;1424:0.4758:0.48649999999999999;1424:0.45910000000000001:0.4491:1;1424:0.44409999999999999:0.41539999999999999;1424:0.43909999999999999:0.4042;1424:0.43409999999999999:0.39300000000000002;1424:0.42909999999999998:0.38169999999999998;1424:0.42420000000000002:0.3705;1424:0.40920000000000001:0.33679999999999999:1;1424:0.39350000000000002:0.30030000000000001;1424:0.38819999999999999:0.28820000000000001;1424:0.38300000000000001:0.27600000000000002;1424:0.36730000000000002:0.23949999999999999:1;1424:0.3518:0.20280000000000001;1424:0.34660000000000002:0.1905;1424:0.32929999999999998:0.1497;1416:0.27539999999999998:0.76049999999999995;1416:0.26850000000000002:0.71709999999999996;1416:0.26150000000000001:0.67369999999999997:1;1416:0.2545:0.63619999999999999;1416:0.2475:0.5988:1;1416:0.23749999999999999:0.57040000000000002;1416:0.22750000000000001:0.54190000000000005:1;1416:0.21609999999999999:0.52539999999999998;1416:0.2046:0.50900000000000001;1421:0.77149999999999996:0.3982;1421:0.76470000000000005:0.35820000000000002;1421:0.76239999999999997:0.3448;1421:0.7601:0.33150000000000002;1421:0.75790000000000002:0.31809999999999999;1421:0.75480000000000003:0.30030000000000001;1421:0.75180000000000002:0.28249999999999997;1421:0.74880000000000002:0.26479999999999998;1421:0.74580000000000002:0.247;1421:0.74270000000000003:0.22919999999999999;1421:0.73970000000000002:0.2114;1421:0.73670000000000002:0.19359999999999999;1421:0.73370000000000002:0.17580000000000001;1421:0.73070000000000002:0.158;1421:0.72840000000000005:0.1447;1421:0.72609999999999997:0.1313;1421:0.71860000000000002:0.086800000000000002:1;1421:0.7046:0.071900000000000006;1421:0.69059999999999999:0.056899999999999999:1;1421:0.68059999999999998:0.050900000000000001;1421:0.67069999999999996:0.044900000000000002;1420:0.54610000000000003:0.72370000000000001;1420:0.55079999999999996:0.71230000000000004;1420:0.55330000000000001:0.69840000000000002;1420:0.55549999999999999:0.68489999999999995;1420:0.5585:0.6714;1420:0.56310000000000004:0.65839999999999999;1420:0.57050000000000001:0.6492;1420:0.57909999999999995:0.64339999999999997;1420:0.58660000000000001:0.63600000000000001;1420:0.59530000000000005:0.63419999999999999;1420:0.60429999999999995:0.62760000000000005;1420:0.61280000000000001:0.62129999999999996;1420:0.62029999999999996:0.61750000000000005:1;1420:0.61960000000000004:0.63100000000000001;1420:0.61860000000000004:0.64449999999999996;1420:0.61729999999999996:0.65939999999999999:1;1420:0.63:0.66900000000000004;1420:0.64400000000000002:0.67500000000000004",
    },
}

local function decode_route(raw)
    if not raw then return nil end
    local pts = {}
    if raw.pts and raw.pts ~= "" then
        for seg in string_gmatch(raw.pts, "([^;]+)") do
            local m, x, y, c = seg:match("^([^:]+):([^:]+):([^:]+):?(.*)$")
            if m then
                pts[#pts + 1] = {
                    mapID = tonumber(m),
                    x = tonumber(x),
                    y = tonumber(y),
                    corner = (c == "1") and true or nil,
                }
            end
        end
    end
    return {
        faction = raw.faction,
        title = raw.title,
        subtitle = raw.subtitle,
        steps = raw.steps,
        mapRoute = {
            mapID = raw.mapID,
            waypoints = raw.waypoints,
            points = pts,
        },
    }
end

sfui.dj_camelot.routes = setmetatable({}, {
    __index = function(t, k)
        local raw = RAW_ROUTES[k]
        if not raw then return nil end
        local d = decode_route(raw)
        t[k] = d
        return d
    end,
})

local QUEST_START_UPDATES = {
    [1013] = { label = "Keeper Bel'dugur", mapID = 1458, x = 0.53700000000000003, y = 0.54500000000000004 },
    [1014] = { label = "Dalar Dawnweaver", mapID = 1421, x = 0.442, y = 0.39800000000000002 },
    [1048] = { label = "Varimathras — Undercity", mapID = 1458, targetName = "Varimathras", x = 0.56200000000000006, y = 0.92400000000000004 },
    [1049] = { label = "Sage Truthseeker — Thunder Bluff", mapID = 1456, targetName = "Sage Truthseeker", x = 0.34399999999999997, y = 0.47199999999999998 },
    [1050] = { label = "Librarian Mae Paledust — Ironforge", mapID = 1455, targetName = "Librarian Mae Paledust", x = 0.73999999999999999, y = 0.13400000000000001 },
    [1053] = { label = "Raleigh the Devout — Hillsbrad Foothills", mapID = 1424, targetName = "Raleigh the Devout", x = 0.51400000000000001, y = 0.58399999999999996 },
    [1098] = { label = "High Executor Hadrec", mapID = 1421, x = 0.434, y = 0.40899999999999997 },
    [1101] = { label = "Falfindel Waywarder — Thalanaar", mapID = 1444, targetName = "Falfindel Waywarder", x = 0.89000000000000001, y = 0.46000000000000002 },
    [1102] = { label = "Auld Stonespire — Thunder Bluff", mapID = 1456, targetName = "Auld Stonespire", x = 0.35999999999999999, y = 0.58999999999999997 },
    [1109] = { label = "Master Apothecary Faranell — Apothecarium", mapID = 1458, targetName = "Master Apothecary Faranell", x = 0.47999999999999998, y = 0.68999999999999995 },
    [1113] = { label = "Master Apothecary Faranell — Apothecarium", mapID = 1458, targetName = "Master Apothecary Faranell", x = 0.47999999999999998, y = 0.68999999999999995 },
    [1139] = { label = "Advisor Belgrum — Ironforge", mapID = 1455, targetName = "Advisor Belgrum", x = 0.76400000000000001, y = 0.108 },
    [1198] = { label = "Dawnwatcher Shaedlass", mapID = 1457, x = 0.55000000000000004, y = 0.23999999999999999 },
    [1199] = { label = "Argent Guard Manados", mapID = 1457, x = 0.55000000000000004, y = 0.23999999999999999 },
    [1221] = { label = "Mebok Mizzyrix — Ratchet", mapID = 1413, targetName = "Mebok Mizzyrix", x = 0.62, y = 0.37 },
    [1275] = { label = "Gershala Nightwhisper", mapID = 1439, x = 0.38300000000000001, y = 0.43099999999999999 },
    [132] = { detail = "Wiley the Black: Lakeshire inn, Redridge Mountains", label = "Wiley the Black — Redridge Mountains", mapID = 1433, targetName = "Wiley the Black", x = 0.214, y = 0.45400000000000001 },
    [135] = { detail = "Gryan Stoutmantle: Sentinel Hill, Westfall", label = "Gryan Stoutmantle — Westfall", mapID = 1436, targetName = "Gryan Stoutmantle", x = 0.56299999999999994, y = 0.47499999999999998 },
    [1360] = { label = "Krom Stoutarm — Ironforge", mapID = 1455, targetName = "Krom Stoutarm", x = 0.74199999999999999, y = 0.098000000000000004 },
    [1394] = { label = "Parqual Fintallas — Undercity", mapID = 1458, targetName = "Parqual Fintallas", x = 0.57399999999999995, y = 0.65400000000000003 },
    [141] = { detail = "Master Mathias Shaw: SI:7, Old Town, Stormwind", label = "Master Mathias Shaw — Stormwind", mapID = 1453, targetName = "Master Mathias Shaw", x = 0.78300000000000003, y = 0.70699999999999996 },
    [142] = { detail = "Gryan Stoutmantle: Sentinel Hill, Westfall", label = "Gryan Stoutmantle — Westfall", mapID = 1436, targetName = "Gryan Stoutmantle", x = 0.56299999999999994, y = 0.47499999999999998 },
    [1445] = { label = "Fel'zerul — Swamp of Sorrows", mapID = 1435, targetName = "Fel'zerul", x = 0.47999999999999998, y = 0.55000000000000004 },
    [1446] = { label = "Atal'ai Exile — The Hinterlands", mapID = 1425, targetName = "Atal'ai Exile", x = 0.33600000000000002, y = 0.752 },
    [1475] = { label = "Brohann Caskbelly — Stormwind", mapID = 1453, targetName = "Brohann Caskbelly", x = 0.66800000000000004, y = 0.434 },
    [1486] = { label = "Nalpak", mapID = 1413, x = 0.46600000000000003, y = 0.36299999999999999 },
    [1487] = { label = "Ebru", mapID = 1413, x = 0.46600000000000003, y = 0.35699999999999998 },
    [1489] = { detail = "Tonga Runetotem: The Crossroads, The Barrens", label = "Tonga Runetotem — The Barrens", mapID = 1413, targetName = "Tonga Runetotem", x = 0.52300000000000002, y = 0.31900000000000001 },
    [1490] = { detail = "Arch Druid Hamuul Runetotem: Elder Rise, Thunder Bluff", label = "Arch Druid Hamuul Runetotem — Thunder Bluff", mapID = 1456, targetName = "Arch Druid Hamuul Runetotem", x = 0.78600000000000003, y = 0.28599999999999998 },
    [1491] = { label = "Mebok Mizzyrix", mapID = 1413, x = 0.628, y = 0.36699999999999999 },
    [155] = { detail = "Defias Traitor: Sentinel Hill, Westfall", label = "Defias Traitor — Westfall", mapID = 1436, targetName = "Defias Traitor", x = 0.55700000000000005, y = 0.47499999999999998 },
    [1652] = { detail = "Daphne Stilwell: Stilwell farm, southern Westfall", label = "Daphne Stilwell — southern Westfall", mapID = 1436, targetName = "Daphne Stilwell", x = 0.41699999999999998, y = 0.89200000000000002 },
    [1653] = { detail = "Duthorian Rall: Cathedral of Light, Stormwind", label = "Duthorian Rall — Stormwind", mapID = 1453, targetName = "Duthorian Rall", x = 0.505, y = 0.47499999999999998 },
    [166] = { label = "Gryan Stoutmantle", mapID = 1436, x = 0.56399999999999995, y = 0.47499999999999998 },
    [167] = { label = "Wilder Thistlenettle", mapID = 1453, x = 0.66800000000000004, y = 0.438 },
    [168] = { label = "Wilder Thistlenettle", mapID = 1453, x = 0.66800000000000004, y = 0.438 },
    [17] = { label = "Ghak Healtouch — Loch Modan", mapID = 1432, targetName = "Ghak Healtouch", x = 0.37, y = 0.49199999999999999 },
    [1740] = { label = "Doan Karhan", mapID = 1413, x = 0.49299999999999999, y = 0.57199999999999995 },
    [1956] = { label = "Tabetha — Dustwallow Marsh", mapID = 1445, targetName = "Tabetha", x = 0.46000000000000002, y = 0.56999999999999995 },
    [2040] = { label = "Shoni the Shilent — Dwarven District, Stormwind", mapID = 1453, targetName = "Shoni the Shilent", x = 0.63, y = 0.34000000000000002 },
    [214] = { label = "Scout Riell", mapID = 1436, x = 0.56669999999999998, y = 0.47349999999999998 },
    [2200] = { label = "Talvash del Kissel — Ironforge", mapID = 1455, targetName = "Talvash del Kissel", x = 0.35999999999999999, y = 0.034000000000000002 },
    [2202] = { label = "Jarkal Mossmeld — Badlands", mapID = 1418, targetName = "Jarkal Mossmeld", x = 0.024, y = 0.46000000000000002 },
    [2283] = { label = "Dran Droffers — Orgrimmar", mapID = 1454, targetName = "Dran Droffers", x = 0.59399999999999997, y = 0.36799999999999999 },
    [2284] = { label = "Dran Droffers — Orgrimmar", mapID = 1454, targetName = "Dran Droffers", x = 0.59399999999999997, y = 0.36799999999999999 },
    [2339] = { label = "Jarkal Mossmeld — Badlands", mapID = 1418, targetName = "Jarkal Mossmeld", x = 0.024, y = 0.46000000000000002 },
    [2342] = { label = "Patrick Garrett — Undercity", mapID = 1458, targetName = "Patrick Garrett", x = 0.624, y = 0.48399999999999999 },
    [2398] = { label = "Prospector Stormpike — Ironforge", mapID = 1455, targetName = "Prospector Stormpike", x = 0.73799999999999999, y = 0.13 },
    [2418] = { label = "Rigglefuzz — Badlands", mapID = 1418, targetName = "Rigglefuzz", x = 0.42399999999999999, y = 0.52400000000000002 },
    [2768] = { label = "Chief Engineer Bilgewhizzle — Tanaris", mapID = 1446, targetName = "Chief Engineer Bilgewhizzle", x = 0.52400000000000002, y = 0.28399999999999997 },
    [2769] = { detail = "Klockmort Spannerspan: Tinker Town, Ironforge", label = "Klockmort Spannerspan — Ironforge", mapID = 1455, targetName = "Klockmort Spannerspan", x = 0.67900000000000005, y = 0.46100000000000002 },
    [2770] = { label = "Wizzle Brassbolts — Thousand Needles", mapID = 1441, targetName = "Wizzle Brassbolts", x = 0.78000000000000003, y = 0.77000000000000002 },
    [2841] = { label = "Nogg — Valley of Honor, Orgrimmar", mapID = 1454, targetName = "Nogg", x = 0.76000000000000001, y = 0.25 },
    [2843] = { label = "Scooty — Booty Bay", mapID = 1434, targetName = "Scooty", x = 0.28000000000000003, y = 0.77000000000000002 },
    [2846] = { label = "Tabetha — Dustwallow Marsh", mapID = 1445, targetName = "Tabetha", x = 0.46000000000000002, y = 0.56999999999999995 },
    [2864] = { detail = "Krazek: Booty Bay inn, upper floor", label = "Krazek — upper floor", mapID = 1434, targetName = "Krazek", x = 0.26900000000000002, y = 0.77200000000000002 },
    [2865] = { label = "Tran'rek — Tanaris", mapID = 1446, targetName = "Tran'rek", x = 0.51400000000000001, y = 0.26800000000000002 },
    [2922] = { label = "Tinkmaster Overspark — Tinker Town, Ironforge", mapID = 1455, targetName = "Tinkmaster Overspark", x = 0.68999999999999995, y = 0.5 },
    [2924] = { label = "Klockmort Spannerspan — Tinker Town, Ironforge", mapID = 1455, targetName = "Klockmort Spannerspan", x = 0.67000000000000004, y = 0.46000000000000002 },
    [2926] = { label = "Ozzie Togglevolt — Kharanos", mapID = 1426, targetName = "Ozzie Togglevolt", x = 0.45000000000000001, y = 0.48999999999999999 },
    [2928] = { label = "Shoni the Shilent — Dwarven District, Stormwind", mapID = 1453, targetName = "Shoni the Shilent", x = 0.63, y = 0.34000000000000002 },
    [2929] = { label = "High Tinker Mekkatorque — Tinker Town, Ironforge", mapID = 1455, targetName = "High Tinker Mekkatorque", x = 0.68000000000000005, y = 0.48999999999999999 },
    [2930] = { label = "Master Mechanic Castpipe — Tinker Town, Ironforge", mapID = 1455, targetName = "Master Mechanic Castpipe", x = 0.68999999999999995, y = 0.47999999999999998 },
    [2936] = { label = "Master Gadrin — Durotar", mapID = 1411, targetName = "Master Gadrin", x = 0.55800000000000005, y = 0.74399999999999999 },
    [2948] = { label = "Talvash del Kissel — Mystic Ward, Ironforge", mapID = 1455, targetName = "Talvash del Kissel", x = 0.35699999999999998, y = 0.040000000000000001 },
    [2950] = { label = "Nogg — Valley of Honor, Orgrimmar", mapID = 1454, targetName = "Nogg", x = 0.76000000000000001, y = 0.25 },
    [2962] = { label = "Ozzie Togglevolt — Kharanos", mapID = 1426, targetName = "Ozzie Togglevolt", x = 0.45000000000000001, y = 0.48999999999999999 },
    [2991] = { label = "Thadius Grimshade — Blasted Lands", mapID = 1419, targetName = "Thadius Grimshade", x = 0.67000000000000004, y = 0.19400000000000001 },
    [3042] = { label = "Trenton Lighthammer — Tanaris", mapID = 1446, targetName = "Trenton Lighthammer", x = 0.51400000000000001, y = 0.28599999999999998 },
    [3341] = { label = "Andrew Brownell — Undercity", mapID = 1458, targetName = "Andrew Brownell", x = 0.73999999999999999, y = 0.32400000000000001 },
    [3446] = { label = "Marvon Rivetseeker — Tanaris", mapID = 1446, targetName = "Marvon Rivetseeker", x = 0.52600000000000002, y = 0.45800000000000002 },
    [3447] = { label = "Marvon Rivetseeker — Tanaris", mapID = 1446, targetName = "Marvon Rivetseeker", x = 0.52600000000000002, y = 0.45800000000000002 },
    [3527] = { label = "Yeh'kinya — Tanaris", mapID = 1446, targetName = "Yeh'kinya", x = 0.67000000000000004, y = 0.224 },
    [3528] = { label = "Yeh'kinya — Tanaris", mapID = 1446, targetName = "Yeh'kinya", x = 0.67000000000000004, y = 0.224 },
    [3636] = { label = "Archbishop Benedictus — Stormwind", mapID = 1453, targetName = "Archbishop Benedictus", x = 0.496, y = 0.44800000000000001 },
    [3765] = { label = "Argos Nightwhisper — The Park", mapID = 1453, targetName = "Argos Nightwhisper", x = 0.36299999999999999, y = 0.67400000000000004 },
    [377] = { label = "Councilman Millstipe — Darkshire", mapID = 1431, x = 0.71999999999999997, y = 0.47799999999999998 },
    [378] = { label = "Motley Garmason — Dun Modr", mapID = 1437, x = 0.496, y = 0.182 },
    [386] = { label = "Guard Berton — Lakeshire", mapID = 1433, x = 0.21199999999999999, y = 0.46600000000000003 },
    [387] = { label = "Warden Thelwater — The Stockade", mapID = 1453, targetName = "Warden Thelwater", x = 0.51800000000000002, y = 0.69299999999999995 },
    [388] = { label = "Nikova Raskol — Old Town", mapID = 1453, patrol = { { 0.73399999999999999, 0.55400000000000005 }, { 0.76300000000000001, 0.60199999999999998 }, { 0.76100000000000001, 0.63700000000000001 }, { 0.73699999999999999, 0.622 }, { 0.72199999999999998, 0.60799999999999998 } }, targetName = "Nikova Raskol", x = 0.74399999999999999, y = 0.59999999999999998 },
    [3907] = { label = "Thunderheart — Badlands", mapID = 1418, targetName = "Thunderheart", x = 0.034000000000000002, y = 0.48199999999999998 },
    [391] = { label = "Warden Thelwater — The Stockade", mapID = 1453, targetName = "Warden Thelwater", x = 0.51800000000000002, y = 0.69299999999999995 },
    [3981] = { label = "Galamav the Marksman — Badlands", mapID = 1418, targetName = "Galamav the Marksman", x = 0.058000000000000003, y = 0.47399999999999998 },
    [4003] = { label = "Thrall — Orgrimmar", mapID = 1454, targetName = "Thrall", x = 0.32000000000000001, y = 0.378 },
    [4024] = { label = "Cyrus Therepentous — Burning Steppes", mapID = 1428, targetName = "Cyrus Therepentous", x = 0.94799999999999995, y = 0.316 },
    [4063] = { label = "Lotwil Veriatus — Badlands", mapID = 1418, targetName = "Lotwil Veriatus", x = 0.25800000000000001, y = 0.45000000000000001 },
    [4081] = { label = "WANTED poster — Kargath, Badlands", mapID = 1418, targetName = "WANTED", x = 0.037999999999999999, y = 0.47499999999999998 },
    [4082] = { label = "KILL ON SIGHT poster — Kargath, Badlands", mapID = 1418, targetName = "KILL ON SIGHT", x = 0.040000000000000001, y = 0.46800000000000003 },
    [4123] = { label = "Maxwort Uberglint — Burning Steppes", mapID = 1428, targetName = "Maxwort Uberglint", x = 0.65200000000000002, y = 0.23799999999999999 },
    [4126] = { label = "Ragnar Thunderbrew — Dun Morogh", mapID = 1426, targetName = "Ragnar Thunderbrew", x = 0.46800000000000003, y = 0.52400000000000002 },
    [4128] = { detail = "Enohar Thunderbrew: Nethergarde Keep, Blasted Lands", label = "Enohar Thunderbrew — Blasted Lands", mapID = 1419, targetName = "Enohar Thunderbrew", x = 0.63600000000000001, y = 0.20599999999999999 },
    [4132] = { label = "Warlord Goretooth — Badlands", mapID = 1418, targetName = "Warlord Goretooth", x = 0.029999999999999999, y = 0.47599999999999998 },
    [4133] = { detail = "Apothecary Zinge: The Apothecarium, Undercity", label = "Apothecary Zinge — Undercity", mapID = 1458, targetName = "Apothecary Zinge", x = 0.501, y = 0.68000000000000005 },
    [4134] = { label = "Shadowmage Vivian Lagrave — Badlands", mapID = 1418, targetName = "Shadowmage Vivian Lagrave", x = 0.029999999999999999, y = 0.47599999999999998 },
    [4136] = { label = "Yuka Screwspigot — Burning Steppes", mapID = 1428, targetName = "Yuka Screwspigot", x = 0.66000000000000003, y = 0.22 },
    [4143] = { label = "Gregan Brewspewer — Feralas", mapID = 1444, targetName = "Gregan Brewspewer", x = 0.45000000000000001, y = 0.254 },
    [4146] = { label = "Liv Rizzlefix — The Barrens", mapID = 1413, targetName = "Liv Rizzlefix", x = 0.624, y = 0.38600000000000001 },
    [4241] = { label = "Marshal Maxwell — Burning Steppes", mapID = 1428, targetName = "Marshal Maxwell", x = 0.84599999999999997, y = 0.68799999999999994 },
    [4263] = { label = "Jalinda Sprig — Burning Steppes", mapID = 1428, targetName = "Jalinda Sprig", x = 0.85399999999999998, y = 0.69999999999999996 },
    [4286] = { label = "Oralius — Burning Steppes", mapID = 1428, targetName = "Oralius", x = 0.84399999999999997, y = 0.68400000000000005 },
    [4324] = { detail = "Yorba Screwspigot: Steamwheedle Port, Tanaris", label = "Yorba Screwspigot — Tanaris", mapID = 1446, targetName = "Yorba Screwspigot", x = 0.67000000000000004, y = 0.23999999999999999 },
    [4362] = { label = "King Magni Bronzebeard — Ironforge", mapID = 1455, targetName = "King Magni Bronzebeard", x = 0.39400000000000002, y = 0.55800000000000005 },
    [4701] = { label = "Helendis Riverhorn — Burning Steppes", mapID = 1428, targetName = "Helendis Riverhorn", x = 0.85399999999999998, y = 0.68799999999999994 },
    [4724] = { label = "Galamav the Marksman — Badlands", mapID = 1418, targetName = "Galamav the Marksman", x = 0.058000000000000003, y = 0.47399999999999998 },
    [4729] = { label = "Kibler — Burning Steppes", mapID = 1428, targetName = "Kibler", x = 0.65800000000000003, y = 0.22 },
    [4734] = { label = "Tinkee Steamboil — Burning Steppes", mapID = 1428, targetName = "Tinkee Steamboil", x = 0.65200000000000002, y = 0.23799999999999999 },
    [4735] = { label = "Tinkee Steamboil — Burning Steppes", mapID = 1428, targetName = "Tinkee Steamboil", x = 0.65200000000000002, y = 0.23799999999999999 },
    [4764] = { label = "Mayara Brightwing — Burning Steppes", mapID = 1428, targetName = "Mayara Brightwing", x = 0.84799999999999998, y = 0.68999999999999995 },
    [4766] = { detail = "Count Remington Ridgewell: Stormwind Keep", label = "Count Remington Ridgewell — Stormwind Keep", mapID = 1453, targetName = "Count Remington Ridgewell", x = 0.76900000000000002, y = 0.47799999999999998 },
    [4768] = { label = "Shadowmage Vivian Lagrave — Badlands", mapID = 1418, targetName = "Shadowmage Vivian Lagrave", x = 0.029999999999999999, y = 0.47599999999999998 },
    [4769] = { detail = "Apothecary Zinge: The Apothecarium, Undercity", label = "Apothecary Zinge — Undercity", mapID = 1458, targetName = "Apothecary Zinge", x = 0.501, y = 0.68000000000000005 },
    [4771] = { label = "Betina Bigglezink — Eastern Plaguelands", mapID = 1423, targetName = "Betina Bigglezink", x = 0.73699999999999999, y = 0.505 },
    [4788] = { label = "Prospector Ironboot — Tanaris", mapID = 1446, targetName = "Prospector Ironboot", x = 0.66800000000000004, y = 0.23999999999999999 },
    [4862] = { label = "Kibler — Burning Steppes", mapID = 1428, targetName = "Kibler", x = 0.65800000000000003, y = 0.22 },
    [4866] = { label = "Ragged John — Burning Steppes", mapID = 1428, targetName = "Ragged John", x = 0.65000000000000002, y = 0.23599999999999999 },
    [4903] = { label = "Warlord Goretooth — Badlands", mapID = 1418, targetName = "Warlord Goretooth", x = 0.029999999999999999, y = 0.47599999999999998 },
    [4974] = { label = "Thrall — Orgrimmar", mapID = 1454, targetName = "Thrall", x = 0.32000000000000001, y = 0.378 },
    [5081] = { label = "Marshal Maxwell — Burning Steppes", mapID = 1428, targetName = "Marshal Maxwell", x = 0.84599999999999997, y = 0.68799999999999994 },
    [5102] = { label = "Marshal Maxwell — Burning Steppes", mapID = 1428, targetName = "Marshal Maxwell", x = 0.84599999999999997, y = 0.68799999999999994 },
    [5127] = { label = "Lorax — Winterspring", mapID = 1452, targetName = "Lorax", x = 0.63800000000000001, y = 0.73799999999999999 },
    [5212] = { label = "Betina Bigglezink — Eastern Plaguelands", mapID = 1423, targetName = "Betina Bigglezink", x = 0.73699999999999999, y = 0.505 },
    [5213] = { label = "Betina Bigglezink — Eastern Plaguelands", mapID = 1423, targetName = "Betina Bigglezink", x = 0.73699999999999999, y = 0.505 },
    [5214] = { label = "Smokey LaRue — Eastern Plaguelands", mapID = 1423, targetName = "Smokey LaRue", x = 0.72799999999999998, y = 0.49199999999999999 },
    [5243] = { label = "Leonid Barthalomew the Revered — Eastern Plaguelands", mapID = 1423, targetName = "Leonid Barthalomew the Revered", x = 0.73899999999999999, y = 0.48999999999999999 },
    [5247] = { label = "Aurora Skycaller — Eastern Plaguelands", mapID = 1423, targetName = "Aurora Skycaller", x = 0.47499999999999998, y = 0.16800000000000001 },
    [5250] = { detail = "Daryn Lightwind: Rut'theran Village, Teldrassil", label = "Daryn Lightwind — Teldrassil", mapID = 1438, targetName = "Daryn Lightwind", x = 0.55400000000000005, y = 0.92200000000000004 },
    [5251] = { label = "Duke Nicholas Zverenhoff — Eastern Plaguelands", mapID = 1423, targetName = "Duke Nicholas Zverenhoff", x = 0.73699999999999999, y = 0.50800000000000001 },
    [5263] = { label = "Duke Nicholas Zverenhoff — Eastern Plaguelands", mapID = 1423, targetName = "Duke Nicholas Zverenhoff", x = 0.73699999999999999, y = 0.50800000000000001 },
    [5281] = { label = "Caretaker Alen — Eastern Plaguelands", mapID = 1423, targetName = "Caretaker Alen", x = 0.71799999999999997, y = 0.54400000000000004 },
    [5282] = { label = "Egan — Eastern Plaguelands", mapID = 1423, targetName = "Egan", x = 0.109, y = 0.27200000000000002 },
    [5341] = { label = "Alexi Barov — Tirisfal Glades", mapID = 1420, targetName = "Alexi Barov", x = 0.82999999999999996, y = 0.71399999999999997 },
    [5343] = { label = "Weldon Barov — Western Plaguelands", mapID = 1422, targetName = "Weldon Barov", x = 0.434, y = 0.83399999999999996 },
    [5382] = { label = "Eva Sarkhoff — Western Plaguelands", mapID = 1422, targetName = "Eva Sarkhoff", x = 0.70199999999999996, y = 0.73799999999999999 },
    [5384] = { label = "Eva Sarkhoff — Western Plaguelands", mapID = 1422, targetName = "Eva Sarkhoff", x = 0.70199999999999996, y = 0.73799999999999999 },
    [5463] = { label = "Leonid Barthalomew the Revered — Eastern Plaguelands", mapID = 1423, targetName = "Leonid Barthalomew the Revered", x = 0.73899999999999999, y = 0.48999999999999999 },
    [5466] = { label = "Magistrate Marduke — Western Plaguelands", mapID = 1422, targetName = "Magistrate Marduke", x = 0.70399999999999996, y = 0.73999999999999999 },
    [5515] = { label = "Eva Sarkhoff — Western Plaguelands", mapID = 1422, targetName = "Eva Sarkhoff", x = 0.70199999999999996, y = 0.73799999999999999 },
    [5526] = { label = "Rabine Saturna — Moonglade", mapID = 1450, targetName = "Rabine Saturna", x = 0.51600000000000001, y = 0.44400000000000001 },
    [5529] = { label = "Betina Bigglezink — Eastern Plaguelands", mapID = 1423, targetName = "Betina Bigglezink", x = 0.73699999999999999, y = 0.505 },
    [5722] = { label = "Rahauro", mapID = 1456, x = 0.70399999999999996, y = 0.32200000000000001 },
    [5723] = { label = "Rahauro", mapID = 1456, x = 0.70399999999999996, y = 0.32200000000000001 },
    [5725] = { label = "Varimathras", mapID = 1458, x = 0.56200000000000006, y = 0.92600000000000005 },
    [5727] = { detail = "Thrall: Grommash Hold, Orgrimmar", label = "Thrall — Orgrimmar", mapID = 1454, targetName = "Thrall", x = 0.317, y = 0.378 },
    [5728] = { label = "Thrall", mapID = 1454, x = 0.32000000000000001, y = 0.378 },
    [5761] = { label = "Neeru Fireblade", mapID = 1454, x = 0.496, y = 0.50600000000000001 },
    [5848] = { label = "Artist Renfray — Western Plaguelands", mapID = 1422, targetName = "Artist Renfray", x = 0.65600000000000003, y = 0.754 },
    [5961] = { label = "Lady Sylvanas Windrunner — Undercity", mapID = 1458, targetName = "Lady Sylvanas Windrunner", x = 0.57999999999999996, y = 0.91600000000000004 },
    [6141] = { detail = "Brother Crowley: Cathedral of Light, Stormwind", label = "Brother Crowley — Stormwind", mapID = 1453, targetName = "Brother Crowley", x = 0.52600000000000002, y = 0.432 },
    [6163] = { label = "Nathanos Blightcaller — Eastern Plaguelands", mapID = 1423, targetName = "Nathanos Blightcaller", x = 0.222, y = 0.64300000000000002 },
    [6502] = { label = "Haleh — Winterspring", mapID = 1452, targetName = "Haleh", x = 0.54400000000000004, y = 0.51200000000000001 },
    [6521] = { label = "Varimathras — Royal Quarter, Undercity", mapID = 1458, x = 0.56200000000000006, y = 0.92600000000000005 },
    [6562] = { label = "Tsunaman — Sun Rock Retreat", mapID = 1442, x = 0.47199999999999998, y = 0.64200000000000002 },
    [6563] = { label = "Je'neu Sancrea", mapID = 1440, x = 0.12, y = 0.34000000000000002 },
    [6565] = { label = "Je'neu Sancrea", mapID = 1440, x = 0.12, y = 0.34000000000000002 },
    [6569] = { label = "Myranda the Hag — Western Plaguelands", mapID = 1422, targetName = "Myranda the Hag", x = 0.50800000000000001, y = 0.77800000000000002 },
    [6602] = { label = "Rexxar — Feralas", mapID = 1444, targetName = "Rexxar", x = 0.44800000000000001, y = 0.073999999999999996 },
    [6626] = { label = "Myriam Moonsinger — The Barrens", mapID = 1413, targetName = "Myriam Moonsinger", x = 0.48999999999999999, y = 0.94799999999999995 },
    [6921] = { label = "Je'neu Sancrea", mapID = 1440, x = 0.12, y = 0.34000000000000002 },
    [7028] = { label = "Willow — Desolace", mapID = 1443, targetName = "Willow", x = 0.62, y = 0.39400000000000002 },
    [7029] = { label = "Vark Battlescar — Desolace", mapID = 1443, targetName = "Vark Battlescar", x = 0.23200000000000001, y = 0.70199999999999996 },
    [704] = { label = "Prospector Ironband — Loch Modan", mapID = 1432, targetName = "Prospector Ironband", x = 0.65800000000000003, y = 0.65400000000000003 },
    [7041] = { label = "Talendria — Desolace", mapID = 1443, targetName = "Talendria", x = 0.68400000000000005, y = 0.087999999999999995 },
    [7044] = { detail = "Cavindra: Maraudon orange-side caverns, Desolace", label = "Cavindra — Desolace", mapID = 1443, targetName = "Cavindra", x = 0.32100000000000001, y = 0.64000000000000001 },
    [7064] = { label = "Selendra — Desolace", mapID = 1443, targetName = "Selendra", x = 0.26800000000000002, y = 0.77600000000000002 },
    [7065] = { label = "Keeper Marandis — Desolace", mapID = 1443, targetName = "Keeper Marandis", x = 0.63800000000000001, y = 0.106 },
    [7067] = { label = "Centaur Pariah — Desolace", mapID = 1443, targetName = "Centaur Pariah", x = 0.434, y = 0.84799999999999998 },
    [7068] = { label = "Uthel'nay — Orgrimmar", mapID = 1454, targetName = "Uthel'nay", x = 0.38800000000000001, y = 0.85399999999999998 },
    [707] = { label = "Prospector Stormpike — Ironforge", mapID = 1455, targetName = "Prospector Stormpike", x = 0.73799999999999999, y = 0.13 },
    [7070] = { label = "Archmage Tervosh — Dustwallow Marsh", mapID = 1445, targetName = "Archmage Tervosh", x = 0.45200000000000001, y = 0.24399999999999999 },
    [709] = { label = "Theldurin the Lost — Badlands", mapID = 1418, targetName = "Theldurin the Lost", x = 0.51400000000000001, y = 0.76400000000000001 },
    [7201] = { label = "Shadowmage Vivian Lagrave — Badlands", mapID = 1418, targetName = "Shadowmage Vivian Lagrave", x = 0.029999999999999999, y = 0.47599999999999998 },
    [721] = { label = "Prospector Ryedol — Badlands", mapID = 1418, targetName = "Prospector Ryedol", x = 0.53400000000000003, y = 0.432 },
    [722] = { detail = "Hammertoe is in the outer excavation caves, before the instance portal", label = "Hammertoe Grez — Uldaman excavation (outside the instance)", mapID = 1418, x = 0.443, y = 0.12 },
    [739] = { detail = "Battered Dwarven Skeleton: Agmond's End, Badlands", label = "Battered Dwarven Skeleton — Badlands", mapID = 1418, targetName = "Battered Dwarven Skeleton", x = 0.50900000000000001, y = 0.624 },
    [7441] = { label = "Azj'Tordin — Feralas", mapID = 1444, targetName = "Azj'Tordin", x = 0.76800000000000002, y = 0.374 },
    [7481] = { label = "Sage Korolusk — Feralas", mapID = 1444, targetName = "Sage Korolusk", x = 0.74399999999999999, y = 0.44 },
    [7482] = { label = "Scholar Runethorn — Feralas", mapID = 1444, targetName = "Scholar Runethorn", x = 0.31, y = 0.442 },
    [7488] = { label = "Latronicus Moonspear — Feralas", mapID = 1444, targetName = "Latronicus Moonspear", x = 0.30399999999999999, y = 0.46000000000000002 },
    [7489] = { label = "Talo Thornhoof — Feralas", mapID = 1444, targetName = "Talo Thornhoof", x = 0.76000000000000001, y = 0.438 },
    [7492] = { detail = "Harbinger Balthazad: Trade Quarter, Undercity (walks around)", label = "Harbinger Balthazad — Undercity (walks around)", mapID = 1458, targetName = "Harbinger Balthazad", x = 0.63900000000000001, y = 0.441 },
    [7494] = { detail = "Crier Goodman: Trade District, Stormwind (walks around)", label = "Crier Goodman — Stormwind (walks around)", mapID = 1453, targetName = "Crier Goodman", x = 0.56399999999999995, y = 0.74099999999999999 },
    [7629] = { label = "Gorzeeki Wildeyes — Burning Steppes", mapID = 1428, targetName = "Gorzeeki Wildeyes", x = 0.124, y = 0.314 },
    [7631] = { label = "Mor'zul Bloodbringer — Burning Steppes", mapID = 1428, targetName = "Mor'zul Bloodbringer", x = 0.126, y = 0.314 },
    [7643] = { label = "Lord Grayson Shadowbreaker — Stormwind", mapID = 1453, targetName = "Lord Grayson Shadowbreaker", x = 0.49399999999999999, y = 0.47599999999999998 },
    [7647] = { label = "Lord Grayson Shadowbreaker — Stormwind", mapID = 1453, targetName = "Lord Grayson Shadowbreaker", x = 0.49399999999999999, y = 0.47599999999999998 },
    [7668] = { label = "Sagorne Creststrider — Orgrimmar", mapID = 1454, targetName = "Sagorne Creststrider", x = 0.38400000000000001, y = 0.35999999999999999 },
    [8232] = { label = "Ogtinc — Azshara", mapID = 1447, targetName = "Ogtinc", x = 0.42399999999999999, y = 0.42599999999999999 },
    [8236] = { label = "Archmage Xylem — Azshara", mapID = 1447, targetName = "Archmage Xylem", x = 0.29199999999999998, y = 0.40200000000000002 },
    [8253] = { label = "Archmage Xylem — Azshara", mapID = 1447, targetName = "Archmage Xylem", x = 0.29199999999999998, y = 0.40200000000000002 },
    [8257] = { label = "Ogtinc — Azshara", mapID = 1447, targetName = "Ogtinc", x = 0.42399999999999999, y = 0.42599999999999999 },
    [8413] = { label = "Bath'rah the Windwatcher — Alterac Mountains", mapID = 1416, targetName = "Bath'rah the Windwatcher", x = 0.80400000000000005, y = 0.66800000000000004 },
    [8415] = { label = "Lord Grayson Shadowbreaker — Stormwind", mapID = 1453, targetName = "Lord Grayson Shadowbreaker", x = 0.49399999999999999, y = 0.47599999999999998 },
    [8418] = { label = "Commander Ashlam Valorfist — Western Plaguelands", mapID = 1422, targetName = "Commander Ashlam Valorfist", x = 0.42799999999999999, y = 0.83999999999999997 },
    [8422] = { label = "Impsy — Felwood", mapID = 1448, targetName = "Impsy", x = 0.41399999999999998, y = 0.44800000000000001 },
    [8425] = { label = "Fallen Hero of the Horde — Swamp of Sorrows", mapID = 1435, targetName = "Fallen Hero of the Horde", x = 0.34200000000000003, y = 0.66000000000000003 },
    [877] = { detail = "Tonga Runetotem: The Crossroads, The Barrens", label = "Tonga Runetotem — The Barrens", mapID = 1413, targetName = "Tonga Runetotem", x = 0.52300000000000002, y = 0.31900000000000001 },
    [880] = { detail = "Tonga Runetotem: The Crossroads, The Barrens", label = "Tonga Runetotem — The Barrens", mapID = 1413, targetName = "Tonga Runetotem", x = 0.52300000000000002, y = 0.31900000000000001 },
    [8945] = { detail = "Anthion Harmon: outside the Stratholme main gate (needs the Ghost Revealer)", label = "Anthion Harmon — outside the Stratholme main gate (needs the Ghost Revealer)", mapID = 1423, targetName = "Anthion Harmon", x = 0.26100000000000001, y = 0.113 },
    [9053] = { label = "Torwa Pathfinder — Un'Goro Crater", mapID = 1449, targetName = "Torwa Pathfinder", x = 0.71599999999999997, y = 0.76000000000000001 },
    [914] = { label = "Nara Wildmane", mapID = 1456, x = 0.753, y = 0.313 },
    [92401] = { label = "Tabitha Heartweaver — The Sepulcher", mapID = 1421, x = 0.44500000000000001, y = 0.42999999999999999 },
    [92421] = { label = "Morbin Lightbane — Royal Quarter", mapID = 1458, x = 0.57899999999999996, y = 0.89500000000000002 },
    [92422] = { label = "Deathguard Kristof — southeast of Brill", mapID = 1420, x = 0.65200000000000002, y = 0.60199999999999998 },
    [92456] = { label = "Shylamiir — Stormwind City", mapID = 1453, targetName = "Shylamiir", x = 0.314, y = 0.628 },
    [92457] = { label = "Image of Archmage Modera — Lordamere Lake near Dalaran", mapID = 1416, targetName = "Image of Archmage Modera", x = 0.091999999999999998, y = 0.59999999999999998 },
    [92458] = { label = "Image of Archmage Modera — Lordamere Lake near Dalaran", mapID = 1416, targetName = "Image of Archmage Modera", x = 0.091999999999999998, y = 0.59999999999999998 },
    [92489] = { label = "High Sorcerer Andromath — Stormwind", mapID = 1453, targetName = "High Sorcerer Andromath", x = 0.48799999999999999, y = 0.874 },
    [92749] = { detail = "Sprite Jumpsprocket: Dwarven District, Stormwind", label = "Sprite Jumpsprocket — Stormwind", mapID = 1453, targetName = "Sprite Jumpsprocket", x = 0.61899999999999999, y = 0.30599999999999999 },
    [92750] = { detail = "Sprite Jumpsprocket: Dwarven District, Stormwind", label = "Sprite Jumpsprocket — Stormwind", mapID = 1453, targetName = "Sprite Jumpsprocket", x = 0.61899999999999999, y = 0.30599999999999999 },
    [92751] = { detail = "Jasper Fel: SI:7, Old Town, Stormwind", label = "Jasper Fel — Stormwind", mapID = 1453, targetName = "Jasper Fel", x = 0.80300000000000005, y = 0.70099999999999996 },
    [92752] = { detail = "Sprite Jumpsprocket: Dwarven District, Stormwind", label = "Sprite Jumpsprocket — Stormwind", mapID = 1453, targetName = "Sprite Jumpsprocket", x = 0.61899999999999999, y = 0.30599999999999999 },
    [95216] = { label = "Theodore Griffs — Apothecarium", mapID = 1458, x = 0.46500000000000002, y = 0.71599999999999997 },
    [95646] = { label = "Rethiel the Greenwarden — Wetlands", mapID = 1437, targetName = "Rethiel the Greenwarden", x = 0.56200000000000006, y = 0.40400000000000003 },
    [95663] = { detail = "Start Dragonmaw Rumors here", label = "Zaruk — Hammerfall", mapID = 1417, targetName = "Zaruk", x = 0.73999999999999999, y = 0.35999999999999999 },
    [95682] = { label = "Deathstalker Agent — outside Excavation Site: Wetlands", mapID = 1437, targetName = "Deathstalker Agent", x = 0.47799999999999998, y = 0.56299999999999994 },
    [95697] = { label = "Borstan — Orgrimmar", mapID = 1454, targetName = "Borstan", x = 0.57399999999999995, y = 0.53400000000000003 },
    [95772] = { label = "Dorin Songblade — Redridge Mountains", mapID = 1433, targetName = "Dorin Songblade", x = 0.25600000000000001, y = 0.46400000000000002 },
    [959] = { label = "Crane Operator Bigglefuzz", mapID = 1413, x = 0.63900000000000001, y = 0.38300000000000001 },
    [962] = { detail = "Serpentbloom starts from Apothecary Zamah in the Pools of Vision beneath Spirit Rise", label = "Apothecary Zamah — Pools of Vision, Thunder Bluff", mapID = 1456, x = 0.23000000000000001, y = 0.20999999999999999 },
    [96393] = { label = "Earthseer Farsen — Gol'Bolar Quarry, Dun Morogh", mapID = 1426, targetName = "Earthseer Farsen", x = 0.64700000000000002, y = 0.58399999999999996 },
    [96394] = { detail = "Top of Old Ironforge, outside the dungeon", label = "Afadra Dunwall — top of Old Ironforge", mapID = 1455, targetName = "Afadra Dunwall", x = 0.33300000000000002, y = 0.48099999999999998 },
    [96403] = { label = "Thom Filch — Hall of Thanes portal, Ironforge", mapID = 1455, targetName = "Thom Filch", x = 0.435, y = 0.52000000000000002 },
    [96800] = { label = "Magus Olvek — Alterac Mountains", mapID = 1416, targetName = "Magus Olvek", x = 0.094, y = 0.626 },
    [96984] = { label = "Image of Archmage Modera — Lordamere Lake near Dalaran", mapID = 1416, targetName = "Image of Archmage Modera", x = 0.091999999999999998, y = 0.59999999999999998 },
    [96986] = { label = "Melisara — Hillsbrad Foothills", mapID = 1424, targetName = "Melisara", x = 0.624, y = 0.20399999999999999 },
    [96988] = { label = "Doctor Martin Felben — Undercity", mapID = 1458, targetName = "Doctor Martin Felben", x = 0.45800000000000002, y = 0.73199999999999998 },
    [971] = { label = "Gerrig Bonegrip", mapID = 1455, x = 0.50829999999999997, y = 0.056099999999999997 },
    [98815] = { label = "James Halloran — Wetlands", mapID = 1437, targetName = "James Halloran", x = 0.084000000000000005, y = 0.55800000000000005 },
    [98823] = { label = "Bashana Runetotem — Thunder Bluff", mapID = 1456, targetName = "Bashana Runetotem", x = 0.70199999999999996, y = 0.33600000000000002 },
    [98824] = { label = "Prospector Whelgar — Wetlands", mapID = 1437, targetName = "Prospector Whelgar", x = 0.38800000000000001, y = 0.52200000000000002 },
}

sfui.dj_camelot.questCoords = sfui.dj_camelot.questCoords or {}
for qid, loc in pairs(QUEST_START_UPDATES) do
    sfui.dj_camelot.questCoords[qid] = loc
end

-- ─── Instance & Subzone Detection for Dungeon Map & World Map (M) Overlay ───
sfui.dj_camelot.instanceToDungeon = {
    [389]  = "ragefire_chasm",
    [36]   = "the_deadmines",
    [43]   = "wailing_caverns",
    [33]   = "shadowfang_keep",
    [34]   = "the_stockade",
    [48]   = "blackfathom_deeps",
    [90]   = "gnomeregan",
    [47]   = "razorfen_kraul",
    [129]  = "razorfen_downs",
    [70]   = "uldaman",
    [209]  = "zulfarrak",
    [109]  = "sunken_temple",
    [289]  = "scholomance",
    [349]  = "maraudon",
    [230]  = "blackrock_depths",
    [329]  = "stratholme_main",
    [2999] = "ruins_of_lordaeron",
    [2959] = "city_of_dalaran",
    [2998] = "excavation_site_wetlands",
    [3065] = "hall_of_thanes",
    [2994] = "alcaz_prison",
    [2974] = "blackmaw_hold",
}

sfui.dj_camelot.scarletWingMaps = {
    [302] = "scarlet_monastery_graveyard",
    [303] = "scarlet_monastery_library",
    [304] = "scarlet_monastery_armory",
    [305] = "scarlet_monastery_cathedral",
}

sfui.dj_camelot.scarletWings = {
    { id = "scarlet_monastery_graveyard", short = "graveyard", name = "Scarlet Monastery: Graveyard" },
    { id = "scarlet_monastery_library",   short = "library",   name = "Scarlet Monastery: Library" },
    { id = "scarlet_monastery_armory",    short = "armory",    name = "Scarlet Monastery: Armory" },
    { id = "scarlet_monastery_cathedral", short = "cathedral", name = "Scarlet Monastery: Cathedral" },
}

local SUBZONE_TO_DUNGEON = {
    -- Scarlet Monastery
    ["chamber of atonement"]    = "scarlet_monastery_graveyard",
    ["forlorn cloister"]        = "scarlet_monastery_graveyard",
    ["honor's tomb"]            = "scarlet_monastery_graveyard",
    ["huntsman's cloister"]     = "scarlet_monastery_library",
    ["gallery of treasures"]    = "scarlet_monastery_library",
    ["athenaeum"]               = "scarlet_monastery_library",
    ["training grounds"]        = "scarlet_monastery_armory",
    ["footman's armory"]        = "scarlet_monastery_armory",
    ["crusader's armory"]       = "scarlet_monastery_armory",
    ["hall of champions"]       = "scarlet_monastery_armory",
    ["chapel gardens"]          = "scarlet_monastery_cathedral",
    ["crusader's chapel"]       = "scarlet_monastery_cathedral",
    -- Dire Maul
    ["warpwood quarter"]        = "dire_maul_east",
    ["the hidden reach"]        = "dire_maul_east",
    ["the conservatory"]        = "dire_maul_east",
    ["the shrine of eldretharr"]= "dire_maul_east",
    ["capital gardens"]         = "dire_maul_west",
    ["court of the highborne"]  = "dire_maul_west",
    ["prison of immol'thar"]    = "dire_maul_west",
    ["the athenaeum"]           = "dire_maul_west",
    ["gordok commons"]          = "dire_maul_north",
    ["the gordok commons"]      = "dire_maul_north",
    ["halls of destruction"]    = "dire_maul_north",
    -- Blackrock Spire
    ["hordemar city"]           = "lower_blackrock_spire",
    ["tazz'alaor"]              = "lower_blackrock_spire",
    ["skitterweb tunnels"]      = "lower_blackrock_spire",
    ["mok'doom"]                = "lower_blackrock_spire",
    ["the storehouse"]          = "lower_blackrock_spire",
    ["halycon's lair"]          = "lower_blackrock_spire",
    ["chamber of battle"]       = "lower_blackrock_spire",
    ["the burning shrine"]      = "lower_blackrock_spire",
    ["hall of binding"]         = "upper_blackrock_spire",
    ["the rookery"]             = "upper_blackrock_spire",
    ["hall of blackhand"]       = "upper_blackrock_spire",
    ["blackrock stadium"]       = "upper_blackrock_spire",
    ["dragonspire hall"]        = "upper_blackrock_spire",
    ["the beast's lair"]        = "upper_blackrock_spire",
    ["spire throne"]            = "upper_blackrock_spire",
}

local UIMAP_TO_DUNGEON = {}
for dID, mapData in pairs(RAW_MAPS) do
    for idxFloor, fl in ipairs(mapData.f or {}) do
        if fl[5] then
            UIMAP_TO_DUNGEON[fl[5]] = { id = dID, floor = idxFloor }
        end
    end
end

local function SafePlainString(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function SafePlainNumber(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    if type(v) == "number" then return v end
    return tonumber(v)
end

function sfui.dj_camelot.InScarletMonastery()
    if type(IsInInstance) == "function" and not IsInInstance() then return false end
    if type(GetInstanceInfo) ~= "function" then return false end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    if SafePlainNumber(id) == 189 then return true end
    local s = SafePlainString(name)
    return s ~= nil and s:lower():find("scarlet monastery", 1, true) ~= nil
end

function sfui.dj_camelot.SetScarletWing(wingID)
    if not wingID then return end
    SfuiDB = SfuiDB or {}
    SfuiDB.djScarletWing = wingID
end

function sfui.dj_camelot.GetCurrentInstanceDungeon()
    if type(IsInInstance) == "function" then
        local inside = IsInInstance()
        if not inside then return nil, nil end
    end

    -- 1. Check live uiMapID first (gives exact dungeon & floor when available)
    if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
        local uiMap = SafePlainNumber(C_Map.GetBestMapForUnit("player"))
        if uiMap and UIMAP_TO_DUNGEON[uiMap] then
            local hit = UIMAP_TO_DUNGEON[uiMap]
            return hit.id, hit.floor
        end
    end

    -- 2. Check subzone / minimap zone (disambiguates Scarlet Monastery, Dire Maul, BRS, Stratholme)
    local subZone = SafePlainString(type(GetSubZoneText) == "function" and GetSubZoneText() or nil)
        or SafePlainString(type(GetMinimapZoneText) == "function" and GetMinimapZoneText() or nil)
    if subZone then
        local low = subZone:lower()
        if SUBZONE_TO_DUNGEON[low] then
            if sfui.dj_camelot.InScarletMonastery() then
                SfuiDB = SfuiDB or {}
                SfuiDB.djScarletWing = SUBZONE_TO_DUNGEON[low]
            end
            return SUBZONE_TO_DUNGEON[low], nil
        end
        if sfui.dj_camelot.InScarletMonastery() then
            if low:find("graveyard", 1, true) then return "scarlet_monastery_graveyard", 1 end
            if low:find("library", 1, true) then return "scarlet_monastery_library", 1 end
            if low:find("armory", 1, true) then return "scarlet_monastery_armory", 1 end
            if low:find("cathedral", 1, true) or low:find("chapel", 1, true) then return "scarlet_monastery_cathedral", 1 end
        end
    end

    -- 3. Check Scarlet Monastery fallback to last chosen wing
    if sfui.dj_camelot.InScarletMonastery() then
        local saved = SfuiDB and SfuiDB.djScarletWing
        return saved or "scarlet_monastery_graveyard", 1
    end

    -- 4. Check numeric instanceID
    if type(GetInstanceInfo) == "function" then
        local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        local numID = SafePlainNumber(instanceID)
        if numID and sfui.dj_camelot.instanceToDungeon[numID] then
            return sfui.dj_camelot.instanceToDungeon[numID], nil
        end
        if numID == 429 then
            return "dire_maul_east", nil
        elseif numID == 229 then
            return "lower_blackrock_spire", nil
        end
        local sName = SafePlainString(name)
        if sName then
            local d = sfui.dj_camelot.GetDungeonByName(sName)
            if d then return d.id, nil end
        end
    end

    local realZone = SafePlainString(type(GetRealZoneText) == "function" and GetRealZoneText() or nil)
    if realZone then
        local d = sfui.dj_camelot.GetDungeonByName(realZone)
        if d then return d.id, nil end
    end

    return nil, nil
end
