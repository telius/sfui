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

local MAP_TEX_PREFIX = "Interface\\AddOns\\sfui_dungeon_maps\\media\\"
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
        f = { { "@AlcazPrisonMap", 1, 0.666992, "main unit" }, { "@AlcazPrisonMap2", 1, 0.666992, "maximum security unit" } },
        e = { { 1, 0.353, 0.16, 180, "entrance" } },
        b = {
            { 1, "Overseer Wrex", 0.642, 0.338, "50", 255391, 7914, false },
            { 1, "The Questioner", 0.247, 0.173, "51", 256236, 140092, false },
            { 1, "Tidemistress Ca'zass", 0.355, 0.714, "50", 255997, 4973, false },
            { 2, "Katerina the Cleaner", 0.39, 0.715, "52", 257016, 2317, false },
            { 2, "Blazeroar", 0.661, 0.714, "53", 255702, 6374, false },
        },
        t = { { 1, 0.33, 0.552, nil, "open with wrex's keyring for floor 2", 2 } },
    },
    blackfathom_deeps = {
        f = {
            { nil, nil, nil, nil, 221, { 447578, 447582, 447583, 447584, 447585, 447586, 447587, 447588, 447589, 447579, 447580, 447581 } },
            { nil, nil, nil, nil, 222, { 447590, 447594, 447595, 447596, 447597, 447598, 447599, 447600, 447601, 447591, 447592, 447593 } },
            { nil, nil, nil, nil, 223, { 447602, 447606, 447607, 447608, 447609, 447610, 447611, 447612, 447613, 447603, 447604, 447605 } },
        },
        e = { { 1, 0.455, 0.085, -20, "entrance" } },
        b = {
            { 1, "Ghamoo-ra", 0.325, 0.605, "25", 4887, 5027, false },
            { 1, "Lady Sarevess", 0.11, 0.385, "25", 4359, 4979, false },
            { 1, "Gelihast", 0.54, 0.575, "26", 4353, 1773, false },
            { 2, "Lorgus Jett", 0.325, 0.7, "26", 12902, 12822, false },
            { 2, "Lorgus Jett", 0.385, 0.194, "26", 12902, 12822, false, nil, true },
            { 2, "Lorgus Jett", 0.442, 0.231, "26", 12902, 12822, false, nil, true },
            { 2, "Baron Aquanis", 0.42, 0.72, "28", 12876, 12876, false },
            { 2, "Twilight Lord Kelris", 0.525, 0.81, "27", 4400, 4939, false },
            { 2, "Aku'mai", 0.855, 0.86, "28", 4401, 2837, false },
            { 3, "Old Serra'kis", 0.585, 0.29, "26", 4360, 1816, false },
        },
        t = { { 1, 0.615, 0.7, nil, nil, 2 }, { 2, 0.47, 0.7, nil, "swim underwater to next level", 3 } },
    },
    blackmaw_hold = {
        f = {
            { "@BlackmawHoldGroveMap", 1, 0.666992, "blackmaw grove" },
            { "@BlackmawHoldFesteringGrottoMap", 1, 0.666992, "festering grotto" },
            { "@BlackmawHoldFallenGroveMap", 1, 0.666992, "depths of the fallen grove" },
            { "@BlackmawHoldEldersMap", 1, 0.666992, "depths of the elders" },
            { "@BlackmawHoldBurrowMap", 1, 0.666992, "depths of the burrow" },
            { "@BlackmawHoldForbiddenMagicMap", 1, 0.666992, "depths of forbidden magic" },
        },
        e = { { 1, 0.183, 0.74, 90, "entrance" } },
    },
    blackrock_depths = {
        f = {
            { nil, nil, nil, nil, 242, { 447638, 447642, 447643, 447644, 447645, 447646, 447647, 447648, 447649, 447639, 447640, 447641 } },
            { nil, nil, nil, nil, 243, { 447650, 447654, 447655, 447656, 447657, 447658, 447659, 447660, 447661, 447651, 447652, 447653 } },
        },
        e = { { 1, 0.329, 0.794, 0, "entrance" } },
        b = {
            { 1, "High Interrogator Gerstahn", 0.474, 0.922, "52", 9018, 8761, false },
            { 1, "Lord Roccor", 0.556, 0.67, "53", 9025, 5781, false },
            { 1, "Houndmaster Grebmar", 0.535, 0.573, "54", 9319, 9212, false },
            { 1, "Bael'Gar", 0.251, 0.534, "56", 9016, 12162, false },
            { 1, "Lord Incendius", 0.564, 0.311, "55", 9017, 1204, false },
            { 1, "Fineous Darkvire", 0.635, 0.211, "55", 9056, 8704, false },
            { 2, "Gorosh the Dervish", 0.53, 0.868, "54", 9031, 3004, "Ring of Law" },
            { 2, "Grizzle", 0.547, 0.883, "54", 9031, 3004, "Ring of Law" },
            { 2, "Eviscerator", 0.547, 0.913, "54", 9031, 3004, "Ring of Law" },
            { 2, "Ok'thor the Breaker", 0.53, 0.928, "54", 9031, 3004, "Ring of Law" },
            { 2, "Anub'shiah", 0.513, 0.913, "54", 9031, 3004, "Ring of Law" },
            { 2, "Hedrum the Creeper", 0.513, 0.883, "54", 9031, 3004, "Ring of Law" },
            { 2, "Pyromancer Loregrain", 0.549, 0.948, "54", 9024, 8762, false },
            { 2, "Warder Stilgiss", 0.602, 0.659, "55", 9041, 9089, false },
            { 2, "General Angerforge", 0.363, 0.823, "57", 8983, 8759, false },
            { 2, "Golem Lord Argelmach", 0.364, 0.651, "57", 8929, 8705, false },
            { 2, "Hurley Blackbreath", 0.505, 0.704, "56", 9537, 8658, false },
            { 2, "Plugger Spazzring", 0.477, 0.657, "56", 9499, 8652, false },
            { 2, "Phalanx", 0.458, 0.564, "56", 9502, 8177, false },
            { 2, "Ambassador Flamelash", 0.538, 0.485, "57", 9156, 8329, false },
            { 2, "The Seven", 0.538, 0.247, "57", 9938, 12162, false },
            { 2, "Magmus", 0.796, 0.118, "57", 9938, 12162, false },
            { 2, "Princess Moira Bronzebeard", 0.92, 0.11, "58", 8929, 8705, false },
            { 2, "Emperor Dagran Thaurissan", 0.909, 0.118, "59", 8929, 8705, false },
        },
    },
    city_of_dalaran = {
        f = { { "@DalaranUnderbellyMap", 1, 0.666504 }, { "@DalaranCityMap", 1, 0.666504 } },
        e = { { 1, 0.19, 0.838, 0, "entrance" } },
        b = {
            { 1, "Atrexis the Grave Knight", 0.535, 0.505, "29", 247126, 145787, false },
            { 1, "Lyn the Ignored", 0.68, 0.177, "32", 247032, 130235, false },
            { 2, "Mana Devourer", 0.416, 0.73, "31", 246008, 129895, false },
            { 2, "Fel Ancient", 0.513, 0.549, "32", 246003, 129894, false },
            { 2, "Unstable Sentinel", 0.614, 0.413, "31", 246017, 129954, false },
            { 2, "Arcanic Enigma", 0.669, 0.503, "30", 246016, 129900, false },
            { 2, "Arcane Anomaly", 0.527, 0.843, "30", 245999, 129891, false },
            { 2, "Shade of the Archmage", 0.52, 0.24, "33", 246020, 130061, false },
        },
        t = { { 1, 0.778, 0.564, nil, nil, 2 } },
    },
    dire_maul_east = {
        f = {
            { nil, nil, nil, nil, 240, { 449568, 449572, 449573, 449574, 449575, 449576, 449577, 449578, 449579, 449569, 449570, 449571 } },
            { nil, nil, nil, nil, 239, { 449556, 449560, 449561, 449562, 449563, 449564, 449565, 449566, 449567, 449557, 449558, 449559 } },
        },
        e = { { 1, 0.281, 0.554, 180, "entrance" } },
        b = {
            { 2, "Lethtendris", 0.438, 0.481, "57", 14327, 14378, false },
            { 1, "Zevrim Thornhoof", 0.575, 0.743, "57", 11490, 11335, false },
            { 1, "Hydrospawn", 0.536, 0.715, "57", 13280, 5489, false },
            { 1, "Alzzin the Wildshaper", 0.566, 0.288, "58", 11492, 14416, false },
        },
    },
    dire_maul_north = {
        f = { { nil, nil, nil, nil, 235, { 449508, 449512, 449513, 449514, 449515, 449516, 449517, 449518, 449519, 449509, 449510, 449511 } } },
        e = { { 1, 0.717, 0.924, 0, "entrance" } },
        b = {
            { 1, "Guard Mol'dar", 0.695, 0.76, "59", 14326, 11561, false },
            { 1, "Stomper Kreeg", 0.612, 0.692, "59", 14322, 11545, false },
            { 1, "Guard Fengus", 0.494, 0.78, "59", 14321, 11561, false },
            { 1, "Guard Slip'kik", 0.266, 0.571, "59", 14323, 11561, false },
            { 1, "Captain Kromcrush", 0.318, 0.506, "61", 14325, 11564, false },
            { 1, "Cho'Rush the Observer", 0.3, 0.29, "60", 11501, 11583, "King Gordok & Cho'Rush" },
            { 1, "King Gordok", 0.319, 0.229, "62", 11501, 11583, "King Gordok & Cho'Rush" },
        },
    },
    dire_maul_west = {
        f = {
            { nil, nil, nil, nil, 236, { 449520, 449524, 449525, 449526, 449527, 449528, 449529, 449530, 449531, 449521, 449522, 449523 } },
            { nil, nil, nil, nil, 237, { 449532, 449536, 449537, 449538, 449539, 449540, 449541, 449542, 449543, 449533, 449534, 449535 } },
            { nil, nil, nil, nil, 238, { 449544, 449548, 449549, 449550, 449551, 449552, 449553, 449554, 449555, 449545, 449546, 449547 } },
        },
        e = { { 1, 0.935, 0.507, 180, "entrance" } },
        b = {
            { 1, "Tendris Warpwood", 0.336, 0.536, "60", 11489, 14383, false },
            { 1, "Illyanna Ravenoak", 0.203, 0.776, "60", 11488, 11270, false },
            { 2, "Magister Kalendris", 0.338, 0.45, "60", 11487, 14384, false },
            { 2, "Tsu'zee", 0.322, 0.143, "59", 11467, 11250, false },
            { 3, "Immol'thar", 0.349, 0.575, "61", 11496, 14173, false },
            { 3, "Prince Tortheldrin", 0.622, 0.231, "61", 11486, 11256, false },
        },
    },
    excavation_site_wetlands = {
        f = { { "@ExcavationSiteMap", 1, 0.666992 } },
        e = { { 1, 0.888, 0.258, 180, "entrance" } },
        b = {
            { 1, "Saltspine", 0.55, 0.361, "28", 260322, 144209, false },
            { 1, "Shadetooth", 0.305, 0.484, "29", 260325, 144210, false },
            { 1, "Relic Guardian", 0.324, 0.687, "31", 260326, 144224, false },
            { 1, "Highland Horror", 0.082, 0.405, "28", 260808, 9010, false, 95646 },
        },
        ti = { { 1, 0.262, 0.668, "Ardin Grassman" }, { 1, 0.074, 0.497, "Daewyn Songblade" } },
    },
    gnomeregan = {
        f = {
            { nil, nil, nil, nil, 226, { 449580, 449584, 449585, 449586, 449587, 449588, 449589, 449590, 449627, 449581, 449582, 449583 } },
            { nil, nil, nil, nil, 227, { 449628, 449632, 449633, 449634, 449635, 449636, 449637, 449638, 449639, 449629, 449630, 449631 } },
            { nil, nil, nil, nil, 228, { 449640, 449644, 449645, 449646, 449647, 449648, 449649, 449650, 449651, 449641, 449642, 449643 } },
            { nil, nil, nil, nil, 229, { 449652, 449656, 449657, 449658, 449659, 449660, 449661, 449662, 449663, 449653, 449654, 449655 } },
        },
        e = { { 1, 0.642, 0.278, 0, "entrance" } },
        b = {
            { 1, "Grubbis", 0.776, 0.671, "32", 7361, 6533, false },
            { 2, "Viscous Fallout", 0.76, 0.469, "30", 7079, 5497, false },
            { 2, "Electrocutioner 6000", 0.245, 0.684, "32", 6235, 6915, false },
            { 3, "Crowd Pummeler 9-60", 0.434, 0.883, "32", 6229, 6774, false },
            { 4, "Mekgineer Thermaplugg", 0.315, 0.299, "34", 7800, 6980, false },
        },
        t = { { 1, 0.545, 0.409, nil, "jump down to floor 2", 2 }, { 1, 0.487, 0.877, nil, nil, 2 }, { 2, 0.435, 0.813, nil, nil, 3 }, { 3, 0.37, 0.72, nil, nil, 4 }, { 4, 0.44, 0.726, nil, nil, 3 } },
    },
    hall_of_thanes = {
        f = { { "@HallOfThanesMap", 1, 0.666992 } },
        e = { { 1, 0.51, 0.944, 0, "entrance" } },
        b = {
            { 1, "Faldrim Anvilmar", 0.509, 0.668, "16", 261306, 142826, false },
            { 1, "Magmatus", 0.748, 0.478, "16", 261316, 1070, false },
            { 1, "Plunder", 0.51, 0.515, "16", 261311, 142840, false },
            { 1, "Durgen Dirgehammer", 0.509, 0.17, "16", 261319, 142837, false },
        },
    },
    kroldok_stronghold = {
        f = { { "@KroldokMap", 1, 0.666992 } },
        e = { { 1, 0.205, 0.807, 180, "entrance" } },
        b = {
            { 1, "Slavecrusher Grox", 0.331, 0.703, "42", 258966, 141217, false },
            { 1, "Twilight Commander Zarmok", 0.392, 0.734, "43", 258972, 141219, false },
            { 1, "War Handler Ashka", 0.621, 0.527, "43", 259281, 141443, false },
            { 1, "Nar'gurk", 0.381, 0.526, "44", 258964, 141215, false },
            { 1, "Bossman Toof", 0.617, 0.432, "42", 264773, 14424, false },
            { 1, "Overlord Mugg", 0.688, 0.242, "45", 258968, 141218, false },
            { 1, "Tunk", 0.691, 0.493, nil, 259256, 144671, false, { 94981, 94974 } },
            { 1, "Zalfan Moonshadow", 0.43, 0.495, nil, 268423, 145448, false, 96771 },
        },
    },
    lower_blackrock_spire = {
        f = {
            { nil, nil, nil, "tazz'alor", 250, { 447662, 447666, 447667, 447668, 447669, 447670, 447671, 447672, 447673, 447663, 447664, 447665 } },
            { nil, nil, nil, "skitterweb tunnels", 251, { 447674, 447678, 447679, 447680, 447681, 447682, 447683, 447684, 447685, 447675, 447676, 447677 } },
            { nil, nil, nil, "hordemar city", 252, { 447686, 447690, 447691, 447692, 447693, 447694, 447695, 447696, 447697, 447687, 447688, 447689 } },
            { nil, nil, nil, "hall of blackhand", 253, { 447698, 447702, 447703, 447704, 447705, 447706, 447707, 447708, 447709, 447699, 447700, 447701 } },
            { nil, nil, nil, "halycon's lair", 254, { 447710, 447714, 447715, 447716, 447717, 447718, 447719, 447720, 447721, 447711, 447712, 447713 } },
            { nil, nil, nil, "chamber of battle", 255, { 447722, 447726, 447727, 447728, 447729, 447730, 447731, 447732, 447733, 447723, 447724, 447725 } },
        },
        b = {
            { 1, "War Master Voone", 0.5246, 0.5451, "59", 9237, 9733, false },
            { 2, "Shadow Hunter Vosh'gajin", 0.5533, 0.6926, "58", 9236, 9732, false },
            { 2, "Mother Smolderweb", 0.6207, 0.7414, "59", 10596, 9929, false },
            { 3, "Highlord Omokk", 0.3866, 0.5902, "58", 9196, 11565, false },
            { 4, "Urok Doomhowl", 0.4549, 0.5574, "60", 10584, 11583, false },
            { 5, "Quartermaster Zigris", 0.5396, 0.8443, "59", 9736, 9738, false },
            { 5, "Halycon", 0.3798, 0.8402, "58", 10220, 9567, false },
            { 5, "Gizrul the Slavener", 0.3948, 0.793, "59", 10268, 9564, false },
            { 6, "Overlord Wyrmthalak", 0.5751, 0.6004, "60", 9568, 8711, false },
        },
    },
    maraudon = {
        f = {
            { nil, nil, nil, nil, 280, { 449676, 449680, 449681, 449682, 449683, 449684, 449685, 449686, 449687, 449677, 449678, 449679 } },
            { nil, nil, nil, nil, 281, { 449688, 449692, 449693, 449694, 449695, 449696, 449697, 449698, 449699, 449689, 449690, 449691 } },
        },
        e = { { 1, 0.618, 0.281, 0, "orange crystal entrance", { 1, 0.55, 0.1 } }, { 1, 0.764, 0.659, 0, "purple crystal entrance", { 0.78, 0.45, 1 } } },
        b = {
            { 1, "Noxxion", 0.362, 0.098, "48", 13280, 5489, false },
            { 1, "Razorlash", 0.166, 0.344, "48", 12258, 12389, false },
            { 1, "Lord Vyletongue", 0.378, 0.704, "47", 12236, 12334, false },
            { 1, "Meshlok the Harvester", 0.246, 0.874, "48", 12237, 9014, false },
            { 2, "Celebras the Cursed", 0.245, 0.143, "49", 12225, 12350, false },
            { 2, "Landslide", 0.408, 0.487, "50", 12203, 12293, false },
            { 2, "Tinkerer Gizlock", 0.484, 0.686, "50", 13601, 7125, false },
            { 2, "Rotgrip", 0.413, 0.817, "50", 13596, 13589, false },
            { 2, "Princess Theradras", 0.258, 0.788, "51", 12201, 12292, false },
        },
        ti = { { 2, 0.245, 0.143, "Celebras the Redeemed" } },
    },
    ragefire_chasm = {
        f = { { nil, nil, nil, nil, 213, { 449736, 449740, 449741, 449742, 449743, 449744, 449745, 449746, 449747, 449737, 449738, 449739 } } },
        e = { { 1, 0.61, 0.075, 200, "entrance" } },
        b = {
            { 1, "Oggleflint", 0.561, 0.378, "16", 4887, 5027, false },
            { 1, "Taragaman the Hungerer", 0.405, 0.57, "16", 4936, 7970, false },
            { 1, "Jergosh the Invoker", 0.34, 0.815, "16", 4938, 11429, false },
            { 1, "Bazzalan", 0.422, 0.842, "16", 4939, 2007, false },
        },
    },
    razorfen_downs = {
        f = { { nil, nil, nil, nil, 300, { 448094, 448098, 448099, 448100, 448101, 448102, 448103, 448104, 448105, 448095, 448096, 448097 } } },
        e = { { 1, 0.234, 0.185, 90, "entrance" } },
        b = {
            { 1, "Tuten'kash", 0.589, 0.342, "40", 7355, 7845, false },
            { 1, "Mordresh Fire Eye", 0.86, 0.467, "39", 7358, 7971, false },
            { 1, "Glutton", 0.345, 0.664, "40", 8567, 7864, false },
            { 1, "Amnennar the Coldbringer", 0.455, 0.582, "41", 7358, 7971, false },
        },
    },
    razorfen_kraul = {
        f = { { nil, nil, nil, nil, 301, { 448106, 448110, 448111, 448112, 448113, 448114, 448115, 448116, 448117, 448107, 448108, 448109 } } },
        e = { { 1, 0.714, 0.84, 180, "entrance" } },
        b = {
            { 1, "Roogug", 0.646, 0.43, "28", 6168, 6168, false },
            { 1, "Aggem Thorncurse", 0.808, 0.521, "30", 6166, 6097, false },
            { 1, "Death Speaker Jargba", 0.876, 0.419, "30", 6765, 4644, false },
            { 1, "Earthcaller Halmgar", 0.498, 0.473, "32", 4842, 6102, false },
            { 1, "Overlord Ramtusk", 0.576, 0.313, "32", 6168, 6168, false },
            { 1, "Charlga Razorflank", 0.221, 0.313, "33", 4421, 4642, false },
            { 1, "Agathelos the Raging", 0.082, 0.686, "33", 6510, 2450, false },
        },
        t = { { 1, 0.626, 0.562, nil, "jump on this vine to reach roogug", nil, true } },
    },
    ruins_of_lordaeron = {
        f = { { "@RuinsOfLordaeronMap", 1, 0.666992 } },
        e = { { 1, 0.612, 0.214, 180, "entrance" } },
        b = {
            { 1, "Witherfang", 0.668, 0.36, "17", 250483, 144189, false },
            { 1, "The Baron", 0.615, 0.65, "17", 250660, 144188, false },
            { 1, "Viktor the Vile", 0.437, 0.788, "19", 256035, 144170, false },
            { 1, "The Abandoned", 0.395, 0.665, "18", 250631, 144175, false },
            { 1, "Bjork", 0.345, 0.22, "19", 256097, 144170, false },
            { 1, "Rath'mael", 0.52, 0.6, "20", 250657, 144175, false },
            { 1, "Lordaeron Captain", 0.5, 0.3, "19", 255699, 144188, false },
        },
        ti = { { 1, 0.612, 0.272, "Captain Truman" } },
    },
    scarlet_monastery_armory = {
        f = { { nil, nil, nil, nil, 304, { 449784, 449788, 449789, 449790, 449791, 449792, 449793, 449794, 449795, 449785, 449786, 449787 } } },
        e = { { 1, 0.61, 0.945, 0, "entrance" } },
        b = {
            { 1, "Herod", 0.785, 0.118, "40", 3975, 2041, false },
        },
    },
    scarlet_monastery_cathedral = {
        f = { { nil, nil, nil, nil, 305, { 449796, 449800, 449801, 449802, 449803, 449804, 449805, 449806, 449807, 449797, 449798, 449799 } } },
        e = { { 1, 0.618, 0.915, 0, "entrance" } },
        b = {
            { 1, "High Inquisitor Fairbanks", 0.555, 0.25, "40", 4542, 2605, false },
            { 1, "Scarlet Commander Mograine", 0.49, 0.285, "42", 3976, 2042, false },
            { 1, "High Inquisitor Whitemane", 0.49, 0.165, "42", 3977, 2043, false },
        },
    },
    scarlet_monastery_graveyard = {
        f = { { nil, nil, nil, nil, 302, { 449760, 449764, 449765, 449766, 449767, 449768, 449769, 449770, 449771, 449761, 449762, 449763 } } },
        e = { { 1, 0.841, 0.831, 180, "entrance" } },
        b = {
            { 1, "Interrogator Vishas", 0.724, 0.6, "32", 3983, 2044, false },
            { 1, "Bloodmage Thalnos", 0.246, 0.566, "34", 4543, 11396, false },
        },
    },
    scarlet_monastery_library = {
        f = { { nil, nil, nil, nil, 303, { 449772, 449776, 449777, 449778, 449779, 449780, 449781, 449782, 449783, 449773, 449774, 449775 } } },
        b = {
            { 1, "Houndmaster Loksey", 0.302, 0.846, "34", 3974, 2040, false },
            { 1, "Arcanist Doan", 0.835, 0.74, "37", 6487, 5266, false },
        },
    },
    scholomance = {
        f = {
            { nil, nil, nil, "the reliquary", 306, { 448178, 448182, 448183, 448184, 448185, 448186, 448187, 448188, 448189, 448179, 448180, 448181 } },
            { nil, nil, nil, "chamber of summoning", 307, { 448190, 448194, 448195, 448196, 448197, 448198, 448199, 448200, 448201, 448191, 448192, 448193 } },
            { nil, nil, nil, "the upper study", 308, { 448202, 448206, 448207, 448208, 448209, 448210, 448211, 448212, 448213, 448203, 448204, 448205 } },
            { nil, nil, nil, "headmaster's study", 309, { 448214, 448218, 448219, 448220, 448221, 448222, 448223, 448224, 448225, 448215, 448216, 448217 } },
        },
        e = { { 1, 0.39, 0.652, 0, "entrance" } },
        b = {
            { 2, "Kirtonos the Herald", 0.495, 0.043, "60", 10506, 7534, false },
            { 2, "Marduk Blackpool", 0.444, 0.639, "58", 10433, 10248, false },
            { 2, "Vectus", 0.482, 0.662, "60", 10432, 2606, false },
            { 3, "Rattlegore", 0.313, 0.646, "60", 11622, 12073, false },
            { 3, "Instructor Malicia", 0.721, 0.706, "60", 10505, 11069, false },
            { 3, "Doctor Theolen Krastinov", 0.889, 0.462, "60", 11261, 10901, false },
            { 3, "Lorekeeper Polkelt", 0.72, 0.225, "60", 10901, 11492, false },
            { 4, "Ras Frostwhisper", 0.406, 0.884, "60", 10508, 7919, false },
            { 4, "The Ravenian", 0.675, 0.521, "60", 10507, 10433, false },
            { 4, "Lord Alexei Barov", 0.844, 0.308, "60", 10504, 11072, false },
            { 4, "Lady Illucia Barov", 0.67, 0.061, "60", 10502, 11835, false },
            { 4, "Darkmaster Gandling", 0.682, 0.302, "61", 1853, 11070, false },
        },
    },
    shadowfang_keep = {
        f = {
            { nil, nil, nil, nil, 310, { 448226, 448230, 448231, 448232, 448233, 448234, 448235, 448236, 448237, 448227, 448228, 448229 } },
            { nil, nil, nil, nil, 316, { 448298, 448302, 448303, 448304, 448305, 448306, 448307, 448308, 448309, 448299, 448300, 448301 } },
            { nil, nil, nil, nil, 315, { 448286, 448290, 448291, 448292, 448293, 448294, 448295, 448296, 448297, 448287, 448288, 448289 } },
        },
        e = { { 1, 0.705, 0.605, 0, "entrance" } },
        b = {
            { 1, "Rethilgore", 0.67, 0.715, "20", 3914, 524, false },
            { 1, "Fel Steed / Shadow Charger", 0.345, 0.635, "19-21", 3864, 1951, false },
            { 1, "Razorclaw the Butcher", 0.327, 0.447, "22", 3886, 524, false },
            { 1, "Baron Silverlaine", 0.162, 0.807, "24", 3887, 3222, false },
            { 2, "Deathsworn Captain", 0.63, 0.525, "25", 3872, 3224, false },
            { 2, "Odo the Blindwatcher", 0.583, 0.828, "24", 4279, 522, false },
            { 3, "Fenrus the Devourer", 0.546, 0.627, "25", 4274, 2352, false },
            { 3, "Arugal's Voidwalker", 0.492, 0.71, "24-25", 4627, 1131, false },
            { 3, "Wolf Master Nandos", 0.59, 0.533, "25", 3927, 11179, false },
            { 3, "Archmage Arugal", 0.685, 0.334, "24", 4275, 2353, false },
        },
        t = { { 1, 0.145, 0.864, "up", nil, 2 }, { 2, 0.515, 0.915, "up", nil, 3 } },
        ti = { { 1, 0.558, 0.622, "Deathstalker Vincent" } },
    },
    shapers_terrace = {
        f = { { "@ShapersTerraceMap", 1, 0.666992, "shaper's terrace" }, { "@PrismaticTalusMap", 0.978516, 0.652344, "prismatic talus" } },
    },
    stratholme_main = {
        f = {
            { nil, nil, nil, "crusaders' square (living)", 317, { 448322, 448326, 448327, 448328, 448329, 448330, 448331, 448332, 448333, 448323, 448324, 448325 } },
            { nil, nil, nil, "the gauntlet (undead)", 318, { 448334, 448338, 448339, 448340, 448341, 448342, 448343, 448344, 448345, 448335, 448336, 448337 } },
        },
        e = { { 1, 0.675, 0.877, 0, "main gate entrance" }, { 2, 0.658, 0.902, 0, "service gate entrance" } },
        b = {
            { 1, "Skul", 0.574, 0.652, "58", 10393, 2606, false },
            { 1, "Hearthsinger Forresten", 0.605, 0.327, "57", 10558, 10482, false },
            { 1, "The Unforgiven", 0.734, 0.204, "57", 10516, 10771, false },
            { 1, "Timmy the Cruel", 0.495, 0.18, "58", 10808, 571, false },
            { 1, "Postmaster Malown", 0.558, 0.684, "60", 11143, 10669, false },
            { 1, "Cannon Master Willey", 0.042, 0.51, "60", 10997, 10674, "Willey Hopebreaker" },
            { 1, "Archivist Galford", 0.272, 0.75, "60", 10811, 10544, "Instructor Galford" },
            { 1, "Balnazzar", 0.204, 0.818, "62", 10813, 10691, false },
            { 2, "Magistrate Barthilas", 0.566, 0.161, "58", 10435, 10433, false },
            { 2, "Stonespine", 0.649, 0.489, "60", 10809, 7856, false },
            { 2, "Nerub'enkan", 0.572, 0.461, "60", 10437, 9793, false },
            { 2, "Baroness Anastari", 0.745, 0.469, "59", 10436, 10698, false },
            { 2, "Maleki the Pallid", 0.674, 0.227, "61", 10438, 10546, false },
            { 2, "Ramstein the Gorger", 0.456, 0.198, "61", 10439, 12818, false },
            { 2, "Baron Rivendare", 0.372, 0.199, "62", 10440, 10440, false },
        },
    },
    sunken_temple = {
        f = { { "@SunkenTempleMap", 1, 0.666992 } },
        e = { { 1, 0.499, 0.13, 0, "entrance" } },
        b = {
            { 1, "Atal'alarion", 0.499, 0.455, "53", 8580, 7873, false },
            { 1, "Avatar of Hakkar", 0.24, 0.453, "55", 8443, 8053, false },
            { 1, "Jammal'an the Prophet", 0.76, 0.454, "54", 5710, 6708, false },
            { 1, "Ogom the Wretched", 0.79, 0.395, "53", 5711, 6709, false },
            { 1, "Dreamscythe & Weaver", 0.5, 0.383, "54", 5721, 7553, false },
            { 1, "Morphaz & Hazzas", 0.498, 0.865, "54", 5720, 6375, false },
            { 1, "Shade of Eranikus", 0.666, 0.873, "55", 5709, 7806, false },
        },
        m = {
            { 1, 1, 0.4985, 0.5908, true, false, "statue 1 of 6 - south", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
            { 1, 2, 0.4985, 0.3094, true, false, "statue 2 of 6 - north", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
            { 1, 3, 0.4207, 0.5234, true, true,  "statue 3 of 6 - southwest", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
            { 1, 4, 0.5763, 0.5234, true, false, "statue 4 of 6 - southeast", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
            { 1, 5, 0.4207, 0.3887, true, true,  "statue 5 of 6 - northwest", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
            { 1, 6, 0.5763, 0.3887, true, false, "statue 6 of 6 - northeast", "use the six statues in this order, 1 to 6: atal'alarion then appears in the pit below.", "Atal'alarion" },
        },
    },
    the_deadmines = {
        f = {
            { nil, nil, nil, nil, 291, { 449591, 449595, 449596, 449597, 449598, 449599, 449600, 449601, 449602, 449592, 449593, 449594 } },
            { nil, nil, nil, nil, 292, { 449603, 449607, 449608, 449609, 449610, 449611, 449612, 449613, 449614, 449604, 449605, 449606 } },
        },
        e = { { 1, 0.295, 0.135, -15, "entrance" } },
        b = {
            { 1, "Rhahk'Zor", 0.365, 0.61, "19", 644, 14403, false },
            { 1, "Miner Johnson", 0.535, 0.52, "19", 3586, 556, false },
            { 1, "Sneed's Shredder", 0.475, 0.865, "20", 642, 1269, false },
            { 1, "Sneed", 0.535, 0.865, "20", 643, 7125, false },
            { 2, "Gilnid", 0.122, 0.755, "20", 643, 7125, false },
            { 2, "Mr. Smite", 0.515, 0.17, "20", 646, 2026, false },
            { 2, "Captain Greenskin", 0.575, 0.35, "20", 647, 7113, false },
            { 2, "Edwin VanCleef", 0.605, 0.452, "21", 639, 2029, false },
            { 2, "Cookie", 0.665, 0.43, "20", 645, 1305, false },
        },
        t = { { 1, 0.615, 0.61, nil, nil, 2 } },
    },
    the_drowned_city = {
        f = { { "@DrownedCityMap", 1, 0.666992, "the drowned city" }, { "@DrownedCityAtalByzalMap", 1, 0.666992, "atal'byzal" } },
        e = { { 1, 0.846, 0.521, 0, "entrance" } },
        b = {
            { 1, "Zul'Alai", 0.697, 0.572, "38", 258905, 144475, false },
            { 2, "Primeval Elemental", 0.667, 0.55, "38", 270887, 129945, false },
            { 1, "Umbra", 0.545, 0.829, "38", 264172, 144022, false },
            { 1, "\"Pyromancer\" Braxton", 0.495, 0.368, "38", 260468, 142457, false },
            { 1, "Var'Taka", 0.514, 0.689, "38", 258924, 144487, false },
            { 1, "Captain Dreadrise", 0.546, 0.344, "39", 260042, 142144, false },
            { 1, "Deathless Marrow", 0.349, 0.536, "39", 270885, 142245, false },
            { 1, "Min'loth the Serpent", 0.196, 0.539, "40", 260274, 142322, false },
        },
        t = {
            { 1, 0.575, 0.599, nil, "swim underwater here for atal'byzal (floor 2)", 2 },
            { 1, 0.59, 0.837, nil, "swim underwater here for atal'byzal (floor 2)", 2 },
            { 2, 0.679, 0.113, "up", "shark exit (danger) — go to floor 1", 1, nil, { 1.0, 0.25, 0.2 }, "shark exit" },
            { 2, 0.262, 0.792, "up", "safe exit — go to floor 1", 1, nil, nil, "safe exit" },
        },
    },
    the_stockade = {
        f = { { nil, nil, nil, nil, 225, { 455959, 455963, 455964, 455965, 455966, 455967, 455968, 455969, 455970, 455960, 455961, 455962 } } },
        e = { { 1, 0.5, 0.815, 0, "entrance" } },
        b = {
            { 1, "Targorr the Dread", 0.44, 0.445, "24", 1696, 517, false },
            { 1, "Targorr the Dread", 0.499, 0.205, "24", 1696, 517, false, nil, true },
            { 1, "Targorr the Dread", 0.31, 0.413, "24", 1696, 517, false, nil, true },
            { 1, "Targorr the Dread", 0.569, 0.544, "24", 1696, 517, false, nil, true },
            { 1, "Kam Deepfury", 0.692, 0.288, "24", 1666, 825, false },
            { 1, "Hamhock", 0.78, 0.457, "25", 1717, 3250, false },
            { 1, "Bazil Thredd", 0.864, 0.527, "26", 1716, 1621, false },
            { 1, "Dextren Ward", 0.215, 0.261, "26", 1715, 2149, false },
            { 1, "Bruegal Ironknuckle", 0.291, 0.444, "26", 1720, 2142, false },
        },
    },
    uldaman = {
        f = {
            { nil, nil, nil, nil, 230, { 448430, 448434, 448435, 448436, 448437, 448438, 448439, 448440, 448441, 448431, 448432, 448433 } },
            { nil, nil, nil, nil, 231, { 448442, 448446, 448447, 448448, 448449, 448450, 448451, 448452, 448453, 448443, 448444, 448445 } },
        },
        e = { { 1, 0.679, 0.725, 0, "entrance" } },
        b = {
            { 1, "The Lost Dwarves", 0.584, 0.92, "41", 6906, 5710, false },
            { 1, "Revelosh", 0.534, 0.725, "40", 6910, 5945, false },
            { 1, "Ironaya", 0.372, 0.739, "40", 7228, 6089, false },
            { 1, "Ancient Stone Keeper", 0.475, 0.44, "44", 7206, 10798, false },
            { 1, "Galgann Firehammer", 0.267, 0.327, "45", 7291, 6059, false },
            { 1, "Grimlok", 0.219, 0.256, "45", 4854, 11165, false },
            { 2, "Archaedas", 0.553, 0.504, "47", 2748, 5988, false },
        },
    },
    upper_blackrock_spire = {
        f = { { "@UpperBlackrockSpireMap", 1, 0.666992 } },
        e = { { 1, 0.186, 0.855, 0, "entrance" } },
        l = {
            { 1, 0.104, 0.605, 2, 90 },
            { 1, 0.125, 0.16, 1, 0 },
            { 1, 0.128, 0.506, 4, 270, { 0.3, 0.6, 1.0 } },
            { 1, 0.345, 0.585, 3, 45, { 0.3, 0.6, 1.0 } },
        },
        b = {
            { 1, "Pyroguard Emberseer", 0.131, 0.289, "60", 9816, 2172, false },
            { 1, "Solakar Flamewreath", 0.226, 0.416, "60", 10264, 9581, false },
            { 1, "Jed Runewatcher", 0.479, 0.438, "60", 10509, 9686, false },
            { 1, "Goraluk Anvilcrack", 0.43, 0.438, "60", 10899, 10222, false },
            { 1, "Gyth", 0.615, 0.394, "60", 10339, 9806, false },
            { 1, "Warchief Rend Blackhand", 0.615, 0.433, "60", 10429, 9778, false },
            { 1, "The Beast", 0.794, 0.506, "60", 10430, 10193, false },
            { 1, "Lord Valthalak", 0.807, 0.564, "62", 16042, 14308, false },
            { 1, "General Drakkisath", 0.459, 0.73, "62", 10363, 10115, false },
        },
    },
    wailing_caverns = {
        f = { { "@WailingCavernsFull", 0.978516, 0.652344, nil, 279 } },
        e = { { 1, 0.465, 0.59, 200, "entrance" } },
        b = {
            { 1, "Lady Anacondra", 0.31, 0.43, "20", 3671, 4313, false },
            { 1, "Kresh", 0.385, 0.35, "20", 3653, 5126, false },
            { 1, "Lord Cobrahn", 0.155, 0.57, "20", 3669, 4213, false },
            { 1, "Lord Pythas", 0.856, 0.289, "21", 3670, 4214, false },
            { 1, "Skum", 0.927, 0.792, "21", 3674, 4203, false },
            { 1, "Deviate Faerie Dragon", 0.58, 0.6, "20", 5912, 1267, false },
            { 1, "Lord Serpentis", 0.615, 0.535, "21", 3673, 4215, false },
            { 1, "Verdan the Everliving", 0.545, 0.46, "21", 5775, 4256, false },
            { 1, "Mutanus the Devourer", 0.345, 0.13, "22", 3654, 4088, false },
        },
    },
    zulfarrak = {
        sp = true,
        f = { { "@ZulFarrakMap", 1, 0.666992 } },
        e = { { 1, 0.552, 0.88, 0, "entrance" } },
        b = {
            { 1, "Antu'sul", 0.646, 0.276, "48", 8127, 7353, false },
            { 1, "Witch Doctor Zum'rah", 0.442, 0.176, "46", 7271, 6434, false },
            { 1, "Shadowpriest Sezz'ziz", 0.296, 0.174, "47", 7275, 6441, false },
            { 1, "Sergeant Bly", 0.31, 0.16, "45", 7604, 6433, false },
            { 1, "Theka the Martyr", 0.528, 0.269, "46", 7272, 6696, false },
            { 1, "Hydromancer Velratha", 0.289, 0.366, "46", 7795, 6685, false },
            { 1, "Gahz'rilla", 0.312, 0.414, "46", 7273, 7271, false },
            { 1, "Zerillis", 0.548, 0.401, "45", 10082, 9293, false },
            { 1, "Sandarr Dunereaver", 0.524, 0.428, "45", 10080, 9291, false },
            { 1, "Chief Ukorz Sandscalp", 0.422, 0.329, "48", 7267, 6439, false },
            { 1, "Ruuzlu", 0.423, 0.329, "46", 7797, 6687, false },
        },
    },
}

local function decode_map(raw)
    if not raw then return nil end
    local floors = {}
    for i, f in ipairs(raw.f or {}) do
        floors[i] = { texture = resolve_tex(f[1]), texRight = f[2], texBottom = f[3], name = f[4], uiMapID = f[5], tiles = f[6] }
    end
    local entrances = {}
    for i, e in ipairs(raw.e or {}) do
        entrances[i] = { floor = e[1], x = e[2], y = e[3], angle = e[4], label = e[5], color = e[6] }
    end
    local bosses = {}
    for i, b in ipairs(raw.b or {}) do
        local tn = (b[8] == false) and b[2] or b[8]
        bosses[i] = { floor = b[1], name = b[2], x = b[3], y = b[4], level = b[5], npcID = b[6], displayId = b[7], targetName = tn, quest = b[9], alt = (b[10] == true) and true or nil }
    end
    local transitions = {}
    for i, tr in ipairs(raw.t or {}) do
        transitions[i] = { floor = tr[1], x = tr[2], y = tr[3], dir = tr[4], label = tr[5], to = tr[6], note = tr[7], color = tr[8], caption = tr[9] }
    end
    local links = {}
    for i, lk in ipairs(raw.l or {}) do
        links[i] = { floor = lk[1], x = lk[2], y = lk[3], to = lk[4], angle = lk[5], color = lk[6] }
    end
    local turnins = {}
    for i, ti in ipairs(raw.ti or {}) do
        turnins[i] = { floor = ti[1], x = ti[2], y = ti[3], npc = ti[4] }
    end
    local markers = {}
    for i, mk in ipairs(raw.m or {}) do
        markers[i] = { floor = mk[1], n = mk[2], x = mk[3], y = mk[4], statue = mk[5], flip = mk[6], title = mk[7], body = mk[8], boss = mk[9] }
    end
    return {
        floors = floors,
        entrances = entrances,
        bosses = bosses,
        transitions = transitions,
        links = links,
        turnins = turnins,
        markers = markers,
        spreadPins = (raw.sp == true) and true or nil,
    }
end

sfui.dj_camelot.maps = setmetatable({}, {
    __index = function(t, k)
        local raw = RAW_MAPS[k]
        if not raw then return nil end
        local d = decode_map(raw)
        t[k] = d
        RAW_MAPS[k] = nil
        return d
    end,
})

local RAW_QUEST_PINS = {
    blackfathom_deeps = {
        { 1, 0.329, 0.412, { { "Pitted Iron Chest", { { 971, "Knowledge in the Deeps", nil, { "loot" }, "blackfathom_deeps", 5359, "Lorgalis Manuscript", "MAP_OBJ_BFD_CHEST" } } } } },
        { 1, 0.208, 0.753, { { "Argent Guard Thaelrid", { { 1198, "In Search of Thaelrid", nil, { "end" }, "blackfathom_deeps" }, { 1200, "Blackfathom Villainy", nil, { "start" }, "blackfathom_deeps" }, { 6561, "Blackfathom Villainy", nil, { "start" }, "blackfathom_deeps" } } } } },
        { 2, 0.406, 0.804, { { "Fathom Stone", { { 6921, "Amongst the Ruins", nil, { "loot" }, "blackfathom_deeps", 16762, "Fathom Core", "MAP_OBJ_BFD_FATHOM" } } } } },
    },
    blackrock_depths = {
        { 1, 0.509, 0.844, { { "Commander Gor'shak", { { 3982, "What Is Going On?", nil, { "start", "end" }, "blackrock_depths" }, { 3981, "Commander Gor'shak", 3982, { "end" }, "blackrock_depths" }, { 4001, "What Is Going On?", 4003, { "start" }, "blackrock_depths" } } }, { "Kharan Mighthammer", { { 4341, "Kharan Mighthammer", 4362, { "end" }, "blackrock_depths" }, { 4342, "Kharan's Tale", 4362, { "start", "end" }, "blackrock_depths" }, { 4361, "The Bearer of Bad News", 4362, { "start" }, "blackrock_depths" } } } } },
        { 1, 0.532, 0.928, { { "Marshal Windsor", { { 4322, "Jail Break!", nil, { "start" }, "blackrock_depths" }, { 4241, "Marshal Windsor", 4322, { "end" }, "blackrock_depths" }, { 4242, "Abandoned Hope", 4322, { "start" }, "blackrock_depths" }, { 4264, "A Crumpled Up Note", 4322, { "end" }, "blackrock_depths" }, { 4282, "A Shred of Hope", 4322, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.551, 0.331, { { "Spectral Chalice", { { 4083, "The Spectral Chalice", nil, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.693, 0.37, { { "Core Fragment", { { 7848, "Attunement to the Core", nil, { "loot" }, "blackrock_depths", 18412, "Core Fragment" } } } } },
        { 2, 0.514, 0.591, { { "Mistress Nagmara", { { 4201, "The Love Potion", nil, { "start", "end" }, "blackrock_depths" } } }, { "Lokhtos Darkbargainer", { { 7604, "A Binding Contract", nil, { "end" }, "blackrock_depths" } } }, { "Private Rocknot", { { 4295, "Rocknot's Ale", nil, { "start", "end" }, "blackrock_depths" } } } } },
        { 2, 0.632, 0.732, { { "Heart of the Mountain", { { 4123, "The Heart of the Mountain", nil, { "loot" }, "blackrock_depths", 11309, "The Heart of the Mountain" } } }, { "Dark Coffer", { { 4083, "The Spectral Chalice", nil, { "loot" }, "blackrock_depths", 7910, "Star Ruby" } } } } },
        { 2, 0.615, 0.95, { { "Monument of Franclorn Forgewright", { { 3802, "Dark Iron Legacy", nil, { "end" }, "blackrock_depths" } } } } },
    },
    dire_maul_north = {
        { 1, 0.217, 0.526, { { "Ogre Tannin Basket", { { 5518, "The Gordok Ogre Suit", nil, { "loot" }, "dire_maul_north", 18240, "Ogre Tannin" } } } } },
        { 1, 0.321, 0.599, { { "Knot Thimblejack", { { 5525, "Free Knot!", nil, { "start", "end" }, "dire_maul_north" }, { 5518, "The Gordok Ogre Suit", nil, { "start", "end" }, "dire_maul_north" } } } } },
    },
    dire_maul_west = {
        { 1, 0.484, 0.538, { { "Shen'dralar Ancient", { { 7461, "The Madness Within", nil, { "start", "end" }, "dire_maul_west" } } } } },
        { 3, 0.747, 0.113, { { "Lorekeeper Javon", { { 7506, "The Emerald Dream...", nil, { "end" }, "dire_maul_west" }, { 7504, "Holy Bologna: What the Light Won't Tell You", nil, { "end" }, "dire_maul_west" }, { 7505, "Frost Shock and You", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.802, 0.114, { { "Lorekeeper Mykos", { { 7503, "The Greatest Race of Hunters", nil, { "end" }, "dire_maul_west" }, { 7501, "The Light and How To Swing It", nil, { "end" }, "dire_maul_west" }, { 7502, "Harnessing Shadows", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.737, 0.171, { { "Lorekeeper Lydros", { { 7463, "Arcane Refreshment", nil, { "start", "end" }, "dire_maul_west" }, { 7507, "Nostro's Compendium", nil, { "end" }, "dire_maul_west" }, { 7483, "Libram of Rapidity", nil, { "start", "end" }, "dire_maul_west" }, { 7484, "Libram of Focus", nil, { "start", "end" }, "dire_maul_west" }, { 7485, "Libram of Protection", nil, { "start", "end" }, "dire_maul_west" } } } } },
        { 3, 0.845, 0.23, { { "Lorekeeper Kildrath", { { 7500, "The Arcanist's Cookbook", nil, { "end" }, "dire_maul_west" }, { 7498, "Garona: A Study on Stealth and Treachery", nil, { "end" }, "dire_maul_west" }, { 7499, "Codex of Defense", nil, { "end" }, "dire_maul_west" } } } } },
        { 3, 0.573, 0.276, { { "The Prince's Chest", { { 7703, "Unfinished Gordok Business", nil, { "loot" }, "dire_maul_west", 18336, "Gauntlet of Gordok Might" } } } } },
    },
    excavation_site_wetlands = {
        { 1, 0.262, 0.668, { { "Ardin Grassman", { { 95647, "Lost in the Thicket Things", 95809, { "end" }, "excavation_site_wetlands" }, { 95809, "Heartwoven", nil, { "start" }, "excavation_site_wetlands" } } } } },
        { 1, 0.074, 0.497, { { "Daewyn Songblade", { { 95772, "Songblade Search", nil, { "end" }, "excavation_site_wetlands" }, { 95795, "Fallen in the Fen", nil, { "start" }, "excavation_site_wetlands" } } } } },
    },
    gnomeregan = {
        { 1, 0.427, 0.66, { { "The Sparklematic 5200", { { 2951, "The Sparklematic 5200!", nil, { "start", "end" }, "gnomeregan" }, { 2945, "Grime-Encrusted Ring", 2948, { "end" }, "gnomeregan" }, { 2947, "Return of the Ring", 2948, { "start" }, "gnomeregan" }, { 2949, "Return of the Ring", 2950, { "start" }, "gnomeregan" } } } } },
        { 4, 0.354, 0.177, { { "Thermaplugg's Safe", { { 2841, "Rig Wars", nil, { "loot" }, "gnomeregan", 9153, "Rig Blueprints" } } } } },
    },
    ragefire_chasm = {
        { 1, 0.618, 0.387, { { "Maur Grimtotem", { { 5724, "Returning the Lost Satchel", nil, { "start" }, "ragefire_chasm" }, { 5722, "Searching for the Lost Satchel", 5724, { "end" }, "ragefire_chasm" } } } } },
    },
    razorfen_downs = {
        { 1, 0.775, 0.152, { { "Belnistrasz", { { 3525, "Extinguishing the Idol", nil, { "start", "end" }, "razorfen_downs" }, { 3523, "Scourge of the Downs", 3525, { "start", "end" }, "razorfen_downs" } } } } },
        { 1, 0.469, 0.223, { { "Belnistrasz's Brazier", { { 3525, "Extinguishing the Idol", nil, { "end" }, "razorfen_downs" } } } } },
    },
    razorfen_kraul = {
        { 1, 0.364, 0.324, { { "Willix the Importer", { { 1144, "Willix the Importer", nil, { "start", "end" }, "razorfen_kraul" } } }, { "Heralath Fallowbrook", { { 1142, "Mortality Wanes", nil, { "start" }, "razorfen_kraul" } } } } },
    },
    ruins_of_lordaeron = {
        { 1, 0.612, 0.272, { { "Captain Truman", { { 95250, "Abominable Creatures", nil, { "start", "end" }, "ruins_of_lordaeron" } } } } },
    },
    scarlet_monastery_graveyard = {
        { 1, 0.719, 0.514, { { "Vorrel Sengutz", { { 1051, "Vorrel's Revenge", nil, { "start" }, "scarlet_monastery_graveyard" } } } } },
    },
    scarlet_monastery_library = {
        { 1, 0.593, 0.122, { { "Mythology of the Titans", { { 1050, "Mythology of the Titans", nil, { "loot" }, "scarlet_monastery_library", 5536, "Mythology of the Titans" } } } } },
        { 1, 0.822, 0.14, { { "Compendium of the Fallen", { { 1049, "Compendium of the Fallen", nil, { "loot" }, "scarlet_monastery_library", 5535, "Compendium of the Fallen" } } } } },
        { 1, 0.454, 0.322, { { "Beginnings of the Undead Threat", { { 1160, "Test of Lore", 1394, { "loot" }, "scarlet_monastery_library", 5861, "Beginnings of the Undead Threat" } } } } },
    },
    shadowfang_keep = {
        { 1, 0.336, 0.55, { { "Jordan's Hammer", { { 1654, "The Test of Righteousness", 1806, { "loot" }, "shadowfang_keep", 6895, "Jordan's Smithing Hammer" } } } } },
        { 1, 0.558, 0.622, { { "Deathstalker Vincent", { { 1098, "Deathstalkers in Shadowfang", nil, { "end" }, "shadowfang_keep" } } } } },
        { 3, 0.472, 0.793, { { "The Book of Ur", { { 1013, "The Book of Ur", nil, { "loot" }, "shadowfang_keep", 6283, "The Book of Ur" } } } } },
    },
    stratholme_main = {
        { 1, 0.31, 0.408, { { "Malor's Strongbox", { { 5122, "The Medallion of Faith", nil, { "loot" }, "stratholme_main", 12845, "Medallion of Faith" } } } } },
        { 1, 0.307, 0.818, { { "Scarlet Archive", { { 5251, "The Archivist", nil, { "use" }, "stratholme_main" } } }, { "Unfinished Painting", { { 5848, "Of Love and Family", nil, { "loot" }, "stratholme_main", 14679, "Of Love and Family" } } } } },
        { 2, 0.695, 0.146, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.414, 0.258, { { "Menethil's Gift", { { 5463, "Menethil's Gift", nil, { "end" }, "stratholme_main" } } } } },
        { 2, 0.803, 0.463, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.53, 0.52, { { "Scourge Data", { { 5213, "The Active Agent", nil, { "loot" }, "stratholme_main", 13176, "Scourge Data" } } } } },
        { 2, 0.678, 0.729, { { "Aurius", { { 5122, "The Medallion of Faith", 5125, { "start", "end" }, "stratholme_main" }, { 5125, "Aurius' Reckoning", nil, { "start", "end" }, "stratholme_main" } } } } },
    },
    sunken_temple = {
        { 1, 0.501, 0.358, { { "Altar of Hakkar", { { 3446, "Into the Depths", nil, { "end" }, "sunken_temple" } } } } },
        { 1, 0.501, 0.477, { { "Idol of Hakkar", { { 3447, "Secret of the Circle", nil, { "end" }, "sunken_temple" } } } } },
        { 1, 0.719, 0.803, { { "Essence Font", { { 3373, "The Essence of Eranikus", nil, { "end" }, "sunken_temple" } } } } },
    },
    uldaman = {
        { 1, 0.207, 0.341, { { "Tablet of Will", { { 1139, "The Lost Tablets of Will", nil, { "loot" }, "uldaman", 5824, "Tablet of Will" } } }, { "Shadowforge Cache", { { 2201, "Find the Gems", nil, { "loot" }, "uldaman", 7669, "Shattered Necklace Ruby" }, { 2339, "Find the Gems and Power Source", nil, { "loot" }, "uldaman", 7669, "Shattered Necklace Ruby" } } } } },
        { 1, 0.533, 0.638, { { "Remains of a Paladin", { { 2200, "Back to Uldaman", nil, { "end" }, "uldaman" }, { 2201, "Find the Gems", nil, { "start" }, "uldaman" }, { 2284, "Necklace Recovery, Take 2", nil, { "end" }, "uldaman" }, { 2318, "Translating the Journal", 2339, { "start" }, "uldaman" } } } } },
        { 1, 0.316, 0.719, { { nil, { { 2240, "The Hidden Chamber", nil, { "explore" }, "uldaman" } } } } },
        { 1, 0.638, 0.948, { { "Baelog", { { 2398, "The Lost Dwarves", nil, { "end" }, "uldaman" }, { 2240, "The Hidden Chamber", nil, { "start" }, "uldaman" } } }, { "Conspicuous Urn", { { 2201, "Find the Gems", nil, { "loot" }, "uldaman", 7671, "Shattered Necklace Topaz" }, { 2339, "Find the Gems and Power Source", nil, { "loot" }, "uldaman", 7671, "Shattered Necklace Topaz" } } } } },
        { 2, 0.501, 0.331, { { "The Discs of Norgannon", { { 2278, "The Platinum Discs", nil, { "start", "end" }, "uldaman" }, { 2279, "The Platinum Discs", nil, { "start" }, "uldaman" }, { 2280, "The Platinum Discs", nil, { "start" }, "uldaman" } } } } },
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
        RAW_QUEST_PINS[k] = nil
        return d
    end,
})

sfui.dj_camelot.turninSpots = {
    { label = "General Marcus Jonathan — Valley of Heroes, Stormwind", mapID = 1453, targetName = "General Marcus Jonathan", x = 0.69, y = 0.828 },
    { label = "Lady Dena Kennedy — Stormwind Keep, Stormwind", mapID = 1453, targetName = "Lady Dena Kennedy", x = 0.692, y = 0.277 },
    { label = "Orphan Matron Nightingale — Cathedral Square, Stormwind", mapID = 1453, targetName = "Orphan Matron Nightingale", x = 0.562, y = 0.54 },
    { label = "Oran Snakewrithe — Magic Quarter, Undercity", mapID = 1458, targetName = "Oran Snakewrithe", x = 0.733, y = 0.326 },
}

local RAW_ROUTES = {
    hall_of_thanes = {
        faction = "Horde",
        title = "Horde Route to Hall of Thanes",
        subtitle = "Horde route",
        steps = { { map = { detail = "The Undercity zeppelin docks at the tower outside Orgrimmar. Ask Frezza if you're unsure which one it is.", label = "Zeppelin to Undercity", mapID = 1411, markerType = "location", x = 0.508, y = 0.135 }, title = "If you're not Undead, take the Zeppelin from Orgrimmar to Undercity", unnumbered = true }, { text = "Travel south from Undercity through Tirisfal Glades and Silverpine Forest, then continue into Hillsbrad Foothills until you reach Tarren Mill.", title = "Undercity -> Silverpine Forest -> Tarren Mill" }, { text = "Ride east along the road into Arathi Highlands, then follow it south toward the big stone bridge.", title = "Tarren Mill -> Arathi Highlands" }, { text = "This huge bridge crosses the gorge into the Wetlands, and it is your gateway into Alliance territory.", title = "Thandol Span (Arathi Highlands / Wetlands border)" }, { text = "Stay on the main road heading south-east. The road is the safest path, so stick to it all the way.", title = "Wetlands" }, { text = "This mountain pass leads into Loch Modan. Alliance guards stand at the checkpoint, so keep running and let your speed carry you through.", title = "Dun Algaz (Wetlands / Loch Modan border)" }, { text = "Head west to the tunnel that connects Loch Modan to Dun Morogh. Keep moving through the gate and continue west toward Ironforge.", title = "Loch Modan -> Dun Morogh" }, { text = "Take off your gear. Guards will likely kill you a few times, and unequipped gear takes no durability damage.", title = "Before entering Ironforge (Dun Morogh)" }, { text = "Head to the High Seat, King Magni's throne room. As you walk in, take the spiderweb-covered corridor on your left, at coordinates 43.5, 52.0.", title = "Ironforge" }, { text = "The Spirit Healer is right outside the city, so each death means a short run back. Resurrect in quiet corners out of the guards' sight so you gain ground every time.", title = "Corpse Running" }, { text = "Follow the winding stairs and stone paths downward. The path ends at a bridge over lava with the quest giver Thom Filch and the dungeon portal.", title = "Old Ironforge" } },
        mapID = 1415,
        waypoints = { { icon = "flightpath", mapID = 1424, textKey = "ROUTE_FP_TARREN_MILL_TEXT", titleKey = "ROUTE_FP_TARREN_MILL", x = 0.6063, y = 0.2028 } },
        pts = "1420:0.6173:0.6594;1420:0.6184:0.646;1420:0.6196:0.6325;1420:0.6203:0.6175:1;1420:0.6113:0.6223;1420:0.6023:0.6291;1420:0.5933:0.6357;1420:0.5843:0.6416;1420:0.5753:0.6465;1420:0.5675:0.6534;1420:0.5613:0.6639;1420:0.5572:0.6774;1420:0.5544:0.6909;1420:0.5525:0.7043;1420:0.5491:0.7168;1420:0.5446:0.7291;1421:0.6712:0.0457;1421:0.6672:0.0575;1421:0.6602:0.0678;1421:0.6522:0.0754;1421:0.6442:0.0817;1421:0.6358:0.0885;1421:0.6287:0.0976;1421:0.6203:0.1052;1421:0.6113:0.1106;1421:0.6023:0.1146;1421:0.5933:0.1178;1421:0.5843:0.1214;1421:0.5753:0.1265;1421:0.5674:0.1346;1421:0.5605:0.1445;1421:0.5545:0.1549;1421:0.549:0.1669;1421:0.5437:0.1789;1421:0.5377:0.1909;1421:0.5314:0.2028;1421:0.5252:0.2148;1421:0.5189:0.2268;1421:0.5134:0.2388;1421:0.5083:0.2507;1421:0.503:0.2627;1421:0.4989:0.2762;1421:0.4974:0.2897;1421:0.4979:0.3044;1421:0.5059:0.3097;1421:0.5115:0.3181;1421:0.5125:0.3316;1421:0.5104:0.3459;1421:0.5104:0.36;1421:0.515:0.3735;1421:0.5209:0.3855;1421:0.5259:0.3975;1421:0.5281:0.4109;1421:0.5284:0.4244;1421:0.5284:0.4379;1421:0.528:0.4513;1421:0.5269:0.4648;1421:0.5244:0.4783;1421:0.5213:0.4918;1421:0.5198:0.5052;1421:0.5206:0.5187;1421:0.523:0.5322;1421:0.5256:0.5457;1421:0.5283:0.5591;1421:0.5306:0.5726;1421:0.533:0.5861;1421:0.5361:0.5996;1421:0.5395:0.613;1421:0.5412:0.6265;1421:0.5414:0.64;1421:0.5411:0.6534;1421:0.5406:0.6669;1421:0.5399:0.6804;1421:0.5391:0.6939;1421:0.5384:0.7073;1421:0.5375:0.7208;1421:0.5392:0.7343;1421:0.5443:0.7463;1421:0.5505:0.7562;1421:0.5584:0.7651;1421:0.5664:0.7717;1421:0.5753:0.7771;1421:0.5843:0.7801;1421:0.5933:0.7819;1421:0.6023:0.7831;1421:0.6113:0.7845;1421:0.6203:0.7852;1421:0.6292:0.7855;1421:0.6382:0.7873;1421:0.6472:0.7906;1421:0.6562:0.7957;1421:0.6652:0.8014;1421:0.6771:0.8046;1424:0.1402:0.4573;1424:0.1492:0.461;1424:0.1582:0.4618;1424:0.1672:0.4616;1424:0.1761:0.4608;1424:0.1851:0.4603;1424:0.1941:0.4603;1424:0.2031:0.461;1424:0.2121:0.4627;1424:0.2211:0.4648;1424:0.23:0.4675;1424:0.239:0.4702;1424:0.248:0.4727;1424:0.257:0.4749;1424:0.266:0.4784;1424:0.275:0.4848;1424:0.2829:0.491;1424:0.2919:0.4952;1424:0.3009:0.4975;1424:0.3099:0.4998;1424:0.3189:0.5008;1424:0.3278:0.4988;1424:0.3368:0.4959;1424:0.3458:0.4933;1424:0.3548:0.4898;1424:0.3638:0.4852;1424:0.3728:0.4802;1424:0.3817:0.4755;1424:0.3907:0.4703;1424:0.3997:0.4649;1424:0.4087:0.4586;1424:0.4167:0.4521;1424:0.4247:0.4456;1424:0.4326:0.4389;1424:0.4406:0.4315;1424:0.4486:0.4242;1424:0.4566:0.4161;1424:0.4646:0.4075;1424:0.4726:0.4002;1424:0.4815:0.3955;1424:0.4905:0.3928;1424:0.4995:0.3915;1424:0.5085:0.3912;1424:0.5175:0.3894;1424:0.5264:0.3862;1424:0.5354:0.3821;1424:0.5444:0.3771;1424:0.5529:0.372;1424:0.5604:0.366:1;1424:0.5641:0.3587;1424:0.56:0.3466;1424:0.5607:0.3331;1424:0.562:0.3196;1424:0.5611:0.3061;1424:0.5589:0.2927;1424:0.5573:0.2792;1424:0.5563:0.2657;1424:0.5561:0.2522;1424:0.5564:0.2388;1424:0.5564:0.2253;1424:0.5564:0.2118;1424:0.5596:0.1995;1424:0.5684:0.1961;1424:0.5773:0.1956;1424:0.586:0.2008;1424:0.5935:0.2087;1424:0.6025:0.2091;1424:0.6063:0.2028:1;1424:0.5992:0.2099;1424:0.5907:0.2058;1424:0.5832:0.1982;1424:0.5744:0.1956;1424:0.5654:0.1963;1424:0.5576:0.2034;1424:0.5564:0.2178;1424:0.5564:0.2313;1424:0.5563:0.2448;1424:0.5561:0.2582;1424:0.5567:0.2717;1424:0.558:0.2852;1424:0.5599:0.2987;1424:0.562:0.3121;1424:0.5617:0.3256;1424:0.56:0.3391;1424:0.5612:0.3525;1424:0.5654:0.3643;1424:0.5604:0.366:1;1424:0.5694:0.366;1424:0.5783:0.3691;1424:0.5863:0.3762;1424:0.5943:0.3855;1424:0.6023:0.3952;1424:0.6103:0.4043;1424:0.6183:0.4115;1424:0.6272:0.4163;1424:0.6362:0.4182;1424:0.6452:0.4197;1424:0.6542:0.4247;1424:0.6621:0.4329;1424:0.6696:0.4432;1424:0.6771:0.4523;1424:0.6861:0.4587;1424:0.6951:0.4635;1424:0.7041:0.4686;1424:0.7131:0.4745;1424:0.7221:0.4811;1424:0.73:0.4874;1424:0.738:0.4944;1424:0.746:0.5024;1424:0.754:0.5115;1424:0.762:0.5209;1424:0.77:0.53;1424:0.7779:0.5375;1424:0.7869:0.543;1424:0.7959:0.5476;1424:0.8049:0.5531;1424:0.8139:0.5576;1417:0.2131:0.3046;1417:0.2161:0.3166;1417:0.2218:0.3286;1417:0.2258:0.3421;1417:0.2274:0.3555;1417:0.228:0.369;1417:0.2282:0.3825;1417:0.2292:0.396;1417:0.2313:0.4094;1417:0.2341:0.4229;1417:0.2384:0.4349;1417:0.2441:0.4454;1417:0.2502:0.4558;1417:0.2558:0.4678;1417:0.2606:0.4798;1417:0.2666:0.491;1417:0.275:0.4987;1417:0.2839:0.5022;1417:0.2929:0.5058;1417:0.3019:0.5106;1417:0.3109:0.5164;1417:0.3199:0.5197;1417:0.3288:0.5206;1417:0.3378:0.5221;1417:0.3468:0.5238;1417:0.3558:0.5248;1417:0.3648:0.5265;1417:0.3738:0.5302;1417:0.3827:0.5362;1417:0.3907:0.5427;1417:0.3997:0.5482;1417:0.4087:0.5501;1417:0.4177:0.5501;1417:0.4266:0.5511;1417:0.4347:0.5575;1417:0.4413:0.5681;1417:0.4471:0.5793;1417:0.4496:0.5876:1;1417:0.4524:0.601;1417:0.4508:0.6145;1417:0.4473:0.628;1417:0.4432:0.6415;1417:0.4389:0.6549;1417:0.4348:0.6684;1417:0.4309:0.6819;1417:0.428:0.6954;1417:0.4273:0.7088;1417:0.4298:0.7223;1417:0.434:0.7343;1417:0.4383:0.7463;1417:0.4418:0.7597;1417:0.4438:0.7732;1417:0.4469:0.7859;1417:0.4495:0.7987;1417:0.4481:0.8121;1417:0.4468:0.8256;1417:0.4451:0.8391;1417:0.4449:0.8525;1417:0.4478:0.8654;1417:0.4543:0.8758;1417:0.461:0.8848;1417:0.4639:0.8982;1417:0.464:0.9123;1417:0.461:0.925;1417:0.4562:0.9379;1417:0.4563:0.9513;1417:0.4573:0.9648;1417:0.4568:0.9783;1417:0.4576:0.9888;1437:0.5155:0.0606;1437:0.5118:0.0741;1437:0.5122:0.0876;1437:0.513:0.101;1437:0.5112:0.1143;1437:0.5075:0.1269;1437:0.5057:0.14;1437:0.5074:0.1534;1437:0.5075:0.1669;1437:0.5067:0.1804;1437:0.5066:0.1939;1437:0.5055:0.2073;1437:0.5038:0.2208;1437:0.5021:0.2343;1437:0.5007:0.2478;1437:0.4966:0.2597;1437:0.4914:0.2717;1437:0.4898:0.2852;1437:0.4905:0.2987;1437:0.4911:0.3121;1437:0.4925:0.3256;1437:0.4984:0.3369;1437:0.5033:0.3496;1437:0.5047:0.3633;1437:0.5111:0.3747;1437:0.5186:0.384;1437:0.5263:0.3925;1437:0.531:0.4049;1437:0.5328:0.4183;1437:0.5404:0.4264;1437:0.5477:0.4364;1437:0.5542:0.4476;1437:0.5607:0.4575;1437:0.5671:0.4674;1437:0.5713:0.4801;1437:0.5705:0.4948;1437:0.5694:0.5082;1437:0.569:0.5217;1437:0.5709:0.5352;1437:0.5734:0.5481;1437:0.5749:0.5622;1437:0.5782:0.5756;1437:0.5805:0.5891;1437:0.58:0.6025;1437:0.5802:0.616;1437:0.5839:0.6295;1437:0.5873:0.643;1437:0.5867:0.6564;1437:0.5851:0.6699;1437:0.5819:0.6834;1437:0.5761:0.6939;1437:0.5684:0.7009;1437:0.5594:0.7064;1437:0.5536:0.7167;1437:0.5507:0.7298;1437:0.5514:0.7373;1432:0.256:0.0876;1432:0.2562:0.1004;1432:0.2547:0.1145;1432:0.2556:0.128;1432:0.2575:0.1415;1432:0.2596:0.1549;1432:0.2603:0.1684;1432:0.26:0.1819;1432:0.2606:0.1954;1432:0.2628:0.2088;1432:0.2651:0.2227;1432:0.263:0.2253:1;1432:0.255:0.2191;1432:0.247:0.2097;1432:0.239:0.2013;1432:0.231:0.1946;1432:0.2231:0.1882;1432:0.2151:0.1816;1432:0.2071:0.1754;1432:0.1981:0.1726;1432:0.1889:0.173;1432:0.1851:0.1684;1426:0.8438:0.3001;1426:0.847:0.3121;1426:0.8446:0.3252;1426:0.8413:0.3378;1426:0.8371:0.3504;1426:0.8349:0.3641;1426:0.8384:0.3768;1426:0.8391:0.3899;1426:0.8338:0.4023;1426:0.8277:0.4139;1426:0.8189:0.4205;1426:0.8101:0.4269;1426:0.8048:0.4381;1426:0.8022:0.4511;1426:0.7973:0.4624;1426:0.792:0.4738;1426:0.7874:0.4856;1426:0.7809:0.4948;1426:0.772:0.4987;1426:0.763:0.496;1426:0.754:0.4939;1426:0.745:0.4965;1426:0.736:0.4986;1426:0.727:0.4985;1426:0.7181:0.4985;1426:0.7096:0.5035;1426:0.7011:0.5092;1426:0.6921:0.5117;1426:0.6835:0.5157;1426:0.6741:0.5197;1426:0.6642:0.5183;1426:0.6552:0.5135;1426:0.6462:0.5118;1426:0.6372:0.517;1426:0.6283:0.5206;1426:0.6235:0.5311;1426:0.6203:0.5437;1426:0.6122:0.5496;1426:0.6033:0.5475;1426:0.5953:0.5394;1426:0.5873:0.5327;1426:0.5788:0.5282;1426:0.5729:0.5172;1426:0.5716:0.5037;1426:0.5694:0.4903;1426:0.5645:0.4787;1426:0.5574:0.4697;1426:0.5496:0.4627;1426:0.5411:0.4568;1426:0.5314:0.4594;1426:0.5238:0.4669;1426:0.5154:0.4727;1426:0.5055:0.4713;1426:0.4965:0.4655;1426:0.4885:0.4589;1426:0.4795:0.4524;1426:0.4722:0.4432;1426:0.4693:0.4305;1426:0.4737:0.4184;1426:0.4825:0.4134;1426:0.4915:0.4087;1426:0.5005:0.4034;1426:0.5084:0.3957;1426:0.5144:0.384;1426:0.5184:0.3705;1426:0.5218:0.3577;1426:0.527:0.3455;1426:0.5364:0.3391;1455:0.1896:0.8234;1455:0.2275:0.7754;1455:0.2695:0.7545;1455:0.3174:0.744;1455:0.3593:0.7246;1455:0.3922:0.6856;1455:0.4162:0.6362;1455:0.4291:0.5868;1455:0.4351:0.5389;1455:0.4351:0.5195",
    },
    ruins_of_lordaeron = {
        faction = "Alliance",
        title = "Alliance Route to Ruins of Lordaeron",
        subtitle = "Alliance route",
        steps = { { map = { detail = "The Auberdine ship leaves from the southernmost dock, Dock 1, in Stormwind Harbor.", label = "Auberdine Ship, Stormwind Harbor", mapID = 1453, markerType = "location", x = 0.228, y = 0.56 }, text = "Head to Stormwind Harbor and take the boat to Auberdine. Once you arrive, go to the opposite side of the Auberdine docks and board the ship to Menethil Harbor. Do not get off at Menethil Harbor, stay on the same ship and it will continue to Southshore in Hillsbrad Foothills.", title = "Go to Stormwind Harbor" }, { showRoute = true, text = "Leave Southshore and follow the road toward Hillsbrad Fields. From there, continue north toward Dalaran.", title = "Follow the road from Southshore" }, { text = "Continue north and go around Dalaran until you reach Lordamere Lake. You do not need to enter Dalaran.", title = "Pass around Dalaran" }, { text = "Swim north across Lordamere Lake, passing from the Silverpine area into Tirisfal Glades.", title = "Swim north through Lordamere Lake" }, { text = "Once you reach Tirisfal Glades, follow the road toward Undercity. Once you enter Undercity, turn left and go upstairs, there's the dungeon entrance.", title = "Follow the road to Undercity" } },
        mapID = 1415,
        pts = "1424:0.5045:0.6175;1424:0.5063:0.604;1424:0.506:0.5906;1424:0.5051:0.5771;1424:0.5052:0.5636;1424:0.5065:0.5546:1;1424:0.491:0.5203;1424:0.4859:0.509;1424:0.4809:0.4978;1424:0.4758:0.4865;1424:0.4591:0.4491:1;1424:0.4441:0.4154;1424:0.4391:0.4042;1424:0.4341:0.393;1424:0.4291:0.3817;1424:0.4242:0.3705;1424:0.4092:0.3368:1;1424:0.3935:0.3003;1424:0.3882:0.2882;1424:0.383:0.276;1424:0.3673:0.2395:1;1424:0.3518:0.2028;1424:0.3466:0.1905;1424:0.3293:0.1497;1416:0.2754:0.7605;1416:0.2685:0.7171;1416:0.2615:0.6737:1;1416:0.2545:0.6362;1416:0.2475:0.5988:1;1416:0.2375:0.5704;1416:0.2275:0.5419:1;1416:0.2161:0.5254;1416:0.2046:0.509;1421:0.7715:0.3982;1421:0.7647:0.3582;1421:0.7624:0.3448;1421:0.7601:0.3315;1421:0.7579:0.3181;1421:0.7548:0.3003;1421:0.7518:0.2825;1421:0.7488:0.2648;1421:0.7458:0.247;1421:0.7427:0.2292;1421:0.7397:0.2114;1421:0.7367:0.1936;1421:0.7337:0.1758;1421:0.7307:0.158;1421:0.7284:0.1447;1421:0.7261:0.1313;1421:0.7186:0.0868:1;1421:0.7046:0.0719;1421:0.6906:0.0569:1;1421:0.6806:0.0509;1421:0.6707:0.0449;1420:0.5461:0.7237;1420:0.5508:0.7123;1420:0.5533:0.6984;1420:0.5555:0.6849;1420:0.5585:0.6714;1420:0.5631:0.6584;1420:0.5705:0.6492;1420:0.5791:0.6434;1420:0.5866:0.636;1420:0.5953:0.6342;1420:0.6043:0.6276;1420:0.6128:0.6213;1420:0.6203:0.6175:1;1420:0.6196:0.631;1420:0.6186:0.6445;1420:0.6173:0.6594:1;1420:0.63:0.669;1420:0.644:0.675",
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
        RAW_ROUTES[k] = nil
        return d
    end,
})

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
    [3001] = "shapers_terrace",
    [2970] = "the_drowned_city",
    [3039] = "kroldok_stronghold",
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

local SUBZONE_TO_FLOOR = {
    -- Alcaz Prison
    ["main unit"]                 = { id = "alcaz_prison", floor = 1 },
    ["maximum security unit"]     = { id = "alcaz_prison", floor = 2 },
    -- The Drowned City
    ["the drowned city"]          = { id = "the_drowned_city", floor = 1 },
    ["drowned city"]              = { id = "the_drowned_city", floor = 1 },
    ["sunken hollow"]             = { id = "the_drowned_city", floor = 1 },
    ["atal'byzal"]                = { id = "the_drowned_city", floor = 2 },
    -- Blackmaw Hold
    ["blackmaw grove"]            = { id = "blackmaw_hold", floor = 1 },
    ["festering grotto"]          = { id = "blackmaw_hold", floor = 2 },
    ["depths of the fallen grove"]= { id = "blackmaw_hold", floor = 3 },
    ["depths of the elders"]      = { id = "blackmaw_hold", floor = 4 },
    ["depths of the burrow"]      = { id = "blackmaw_hold", floor = 5 },
    ["depths of forbidden magic"] = { id = "blackmaw_hold", floor = 6 },
    -- Scholomance
    ["the reliquary"]             = { id = "scholomance", floor = 1 },
    ["chamber of summoning"]      = { id = "scholomance", floor = 2 },
    ["the chamber of summoning"]  = { id = "scholomance", floor = 2 },
    ["the upper study"]           = { id = "scholomance", floor = 3 },
    ["upper study"]               = { id = "scholomance", floor = 3 },
    ["great ossuary"]             = { id = "scholomance", floor = 3 },
    ["the great ossuary"]         = { id = "scholomance", floor = 3 },
    ["hall of secrets"]           = { id = "scholomance", floor = 3 },
    ["hall of the damned"]        = { id = "scholomance", floor = 3 },
    ["the coven"]                 = { id = "scholomance", floor = 3 },
    ["headmaster's study"]        = { id = "scholomance", floor = 4 },
    ["the headmaster's study"]    = { id = "scholomance", floor = 4 },
    ["ras frostwhisper's chamber"]= { id = "scholomance", floor = 4 },
    ["vault of the ravenian"]     = { id = "scholomance", floor = 4 },
    ["barov family vault"]        = { id = "scholomance", floor = 4 },
    -- Stratholme
    ["crusaders' square"]         = { id = "stratholme_main", floor = 1 },
    ["king's square"]             = { id = "stratholme_main", floor = 1 },
    ["market row"]                = { id = "stratholme_main", floor = 1 },
    ["festival lane"]             = { id = "stratholme_main", floor = 1 },
    ["the scarlet bastion"]       = { id = "stratholme_main", floor = 1 },
    ["the hall of lights"]        = { id = "stratholme_main", floor = 1 },
    ["the hoard"]                 = { id = "stratholme_main", floor = 1 },
    ["the crimson throne"]        = { id = "stratholme_main", floor = 1 },
    ["the gauntlet"]              = { id = "stratholme_main", floor = 2 },
    ["elders' square"]            = { id = "stratholme_main", floor = 2 },
    ["slaughter square"]          = { id = "stratholme_main", floor = 2 },
    ["slaughterhouse"]            = { id = "stratholme_main", floor = 2 },
    ["the slaughter house"]       = { id = "stratholme_main", floor = 2 },
    -- Lower Blackrock Spire
    ["tazz'alor"]                 = { id = "lower_blackrock_spire", floor = 1 },
    ["tazz'alaor"]                = { id = "lower_blackrock_spire", floor = 1 },
    ["skitterweb tunnels"]        = { id = "lower_blackrock_spire", floor = 2 },
    ["hordemar city"]             = { id = "lower_blackrock_spire", floor = 3 },
    ["halycon's lair"]            = { id = "lower_blackrock_spire", floor = 5 },
    ["chamber of battle"]         = { id = "lower_blackrock_spire", floor = 6 },
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
        if SUBZONE_TO_FLOOR[low] then
            local hit = SUBZONE_TO_FLOOR[low]
            return hit.id, hit.floor
        end
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
