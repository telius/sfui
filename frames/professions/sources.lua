local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.professions = sfui.professions or {}
sfui.recipes = sfui.recipes or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.professions or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/sources.lua
--  Unified Recipe Source Resolution Engine (Camelot / Classic Forever)
--
--  Resolves exact trainer, vendor, drop, and quest sources for any recipe
--  by spellID, recipe scroll itemID, or crafted output itemID.
--  Merges the comprehensive static baseline (sfui.recipes_camelot) with
--  live player discoveries (SfuiDB.contacts & SfuiDB.recipe_finds).
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

-- Localized APIs
local C_Map                   = _G.C_Map
local UiMapPoint              = _G.UiMapPoint
local C_SuperTrack            = _G.C_SuperTrack
local GetCoinTextureString    = _G.GetCoinTextureString
local print                   = _G.print
local pcall, type             = _G.pcall, _G.type
local tonumber, tostring      = _G.tonumber, _G.tostring
local pairs, ipairs           = _G.pairs, _G.ipairs
local math_floor              = math.floor
local table_insert            = table.insert

--- Format copper amount to coin icons or text
local function FormatMoney(copper)
    if not copper or copper <= 0 then return nil end
    if GetCoinTextureString then
        return GetCoinTextureString(copper)
    end
    local g = math_floor(copper / 10000)
    local s = math_floor(copper / 100) % 100
    local c = copper % 100
    local str = ""
    if g > 0 then str = str .. g .. "g " end
    if s > 0 then str = str .. s .. "s " end
    if c > 0 or str == "" then str = str .. c .. "c" end
    return str:gsub("%s+$", "")
end
sfui.recipes.FormatMoney = FormatMoney

--- Short text format for money (e.g. 1g 20s, 45s, 80c)
local function FormatMoneyShort(copper)
    if not copper or copper <= 0 then return nil end
    local g = math_floor(copper / 10000)
    local s = math_floor(copper / 100) % 100
    local c = copper % 100
    if g > 0 then
        if s > 0 then
            return string.format("%dg %ds", g, s)
        else
            return string.format("%dg", g)
        end
    elseif s > 0 then
        if c > 0 then
            return string.format("%ds %dc", s, c)
        else
            return string.format("%ds", s)
        end
    else
        return string.format("%dc", c)
    end
end
sfui.recipes.FormatMoneyShort = FormatMoneyShort

--- Curated set of known limited-stock vendor recipes (Classic / Camelot)
-- Note: Drops, quest rewards, and trainer recipes must NEVER be included here.
sfui.recipes.LIMITED_RECIPE_ITEMS = {
    -- alchemy
    [3831]  = true, -- recipe: frost oil
    [5642]  = true, -- recipe: free action potion
    [5643]  = true, -- recipe: great rage potion
    [9302]  = true, -- recipe: elixir of shadow power
    [12958] = true, -- recipe: transmute arcanite
    [13476] = true, -- recipe: superior mana potion
    [13477] = true, -- recipe: major healing potion
    [13478] = true, -- recipe: elixir of superior defense
    [13484] = true, -- recipe: elixir of greater water breathing

    -- tailoring
    [5771]  = true, -- pattern: red woolen bag
    [5772]  = true, -- pattern: heavy woolen cloak
    [5774]  = true, -- pattern: phoenix gloves
    [5775]  = true, -- pattern: phoenix pants
    [6401]  = true, -- pattern: blue linen vest
    [7084]  = true, -- pattern: crimson silk vest
    [7085]  = true, -- pattern: crimson silk shoulders
    [7086]  = true, -- pattern: crimson silk cloak
    [7087]  = true, -- pattern: crimson silk robe
    [7088]  = true, -- pattern: earthen silk belt
    [7089]  = true, -- pattern: crimson silk gloves
    [7090]  = true, -- pattern: green silk armor
    [10300] = true, -- pattern: red mageweave headband
    [10301] = true, -- pattern: red mageweave pants
    [10302] = true, -- pattern: red mageweave gloves
    [10314] = true, -- pattern: lavender mageweave shirt
    [10317] = true, -- pattern: pink mageweave shirt
    [10321] = true, -- pattern: tuxedo shirt
    [10323] = true, -- pattern: tuxedo pants
    [10326] = true, -- pattern: tuxedo jacket
    [14468] = true, -- pattern: runecloth bag
    [14476] = true, -- pattern: cindercloth vest
    [14478] = true, -- pattern: cindercloth gloves
    [14480] = true, -- pattern: wizardweave robe
    [14481] = true, -- pattern: wizardweave turbin
    [14482] = true, -- pattern: wizardweave leggings
    [14483] = true, -- pattern: mooncloth
    [14484] = true, -- pattern: runecloth cloak
    [14486] = true, -- pattern: runecloth robe
    [14493] = true, -- pattern: runecloth boots

    -- blacksmithing
    [3490]  = true, -- plans: hardened iron shortsword
    [3491]  = true, -- plans: massive iron axe
    [3492]  = true, -- plans: moonsteel broadsword
    [3493]  = true, -- plans: golden scale bracers
    [3494]  = true, -- plans: golden scale shoulders
    [3495]  = true, -- plans: golden scale coif
    [7990]  = true, -- plans: mithril scale shoulders
    [7991]  = true, -- plans: mithril scale bracers
    [7992]  = true, -- plans: mithril scale pants
    [7993]  = true, -- plans: heavy mithril pants
    [7995]  = true, -- plans: heavy mithril breastplate

    -- engineering
    [4408]  = true, -- schematic: mechanical dragonling
    [4410]  = true, -- schematic: small seaforium charge
    [4411]  = true, -- schematic: gyrochronatom
    [4412]  = true, -- schematic: iron grenade
    [4413]  = true, -- schematic: compact harvest reaper
    [4414]  = true, -- schematic: advanced target dummy
    [10601] = true, -- schematic: deepdive helmet
    [10602] = true, -- schematic: parachute cloak
    [10603] = true, -- schematic: deadly scope
    [10608] = true, -- schematic: large seaforium charge
    [10609] = true, -- schematic: mithril mechanical dragonling
    [13309] = true, -- schematic: mithril heavy-bore rifle
    [13310] = true, -- schematic: dark iron rifle
    [13311] = true, -- schematic: sniper scope
    [16041] = true, -- schematic: catseye ultra goggles
    [16042] = true, -- schematic: mithril gyro-shot
    [16043] = true, -- schematic: spellpower goggles xtreme
    [16044] = true, -- schematic: thorium widget
    [16045] = true, -- schematic: thorium rifle
    [16047] = true, -- schematic: master engineer's goggles
    [16048] = true, -- schematic: arcanite dragonling
    [16049] = true, -- schematic: delicate arcanite converter
    [16051] = true, -- schematic: masterwork target dummy

    -- leatherworking
    [7288]  = true, -- pattern: nimble leather gloves
    [8409]  = true, -- pattern: nightscape tunic
    [8410]  = true, -- pattern: nightscape headband
    [8411]  = true, -- pattern: nightscape boots
    [8412]  = true, -- pattern: nightscape pants

    -- enchanting
    [6375]  = true, -- formula: enchant 2h weapon - lesser spirit
    [6377]  = true, -- formula: enchant 2h weapon - lesser intellect
    [13378] = true, -- formula: enchant shield - minor stamina
    [13379] = true, -- formula: enchant cloak - minor agility
    [13380] = true, -- formula: enchant shield - lesser spirit
    [13538] = true, -- formula: enchant weapon - lesser elemental slayer
    [13635] = true, -- formula: enchant cloak - resistance
    [16243] = true, -- formula: runed arcanite rod
}

--- Curated drop locations and creatures for iconic Classic / Vanilla recipes
sfui.recipes.CURATED_DROP_SOURCES = {
    -- Enchanting
    [20034] = { mob = "scarlet spellbinder", zone = "western plaguelands", mapID = 1422, x = 0.440, y = 0.150 }, -- formula: enchant weapon - crusader
    [20032] = { mob = "spectral researcher", zone = "scholomance", mapID = 1422 }, -- formula: enchant weapon - lifestealing
    [20033] = { mob = "thuzadin shadowcaster", zone = "stratholme", mapID = 1423 }, -- formula: enchant weapon - unholy weapon
    [22749] = { mob = "bosses", zone = "molten core" }, -- formula: enchant weapon - spellpower
    [22750] = { mob = "bosses", zone = "molten core" }, -- formula: enchant weapon - healing power
    [13637] = { mob = "spirestone warlord", zone = "blackrock spire", mapID = 1428 }, -- formula: enchant weapon - greater striking
    [20031] = { mob = "deadwind warlock", zone = "deadwind pass", mapID = 1430 }, -- formula: enchant 2h weapon - superior impact
    [13933] = { mob = "shadowpriest vanders", zone = "stratholme", mapID = 1423 }, -- formula: enchant bracer - superior stamina

    -- Cooking
    [8213]  = { mob = "deviate beasts", zone = "the barrens", mapID = 1413 }, -- recipe: savory deviate delight
    [21175] = { mob = "carrion vultures / basilisks", zone = "badlands", mapID = 1418 }, -- recipe: crispy bat wing / spider sausage
    [22761] = { mob = "lord kazzak / azuregos / raid bosses", zone = "world drop" }, -- recipe: dirge's kickin' chimaerok chops

    -- Blacksmithing
    [16990] = { mob = "world / raid bosses (level 60+)", zone = "world drop" }, -- plans: lionheart helm
    [16991] = { mob = "world drop (level 58-60 elites)", zone = "world drop" }, -- plans: stronghold gauntlets
    [24177] = { mob = "world / raid (level 60+)", zone = "world drop" }, -- plans: titanic leggings
    [22754] = { mob = "bosses", zone = "molten core" }, -- plans: elemental sharpening stone
    [16963] = { mob = "blackhand elite", zone = "blackrock spire", mapID = 1428 }, -- plans: dark iron bracers
    [16988] = { mob = "firebrand invoker", zone = "blackrock spire", mapID = 1428 }, -- plans: fiery plate gauntlets
    [16989] = { mob = "spirestone battle lord", zone = "blackrock spire", mapID = 1428 }, -- plans: arcanite champion

    -- Alchemy
    [17572] = { mob = "jadefire / legashi satyrs", zone = "felwood / azshara", mapID = 1448 }, -- recipe: elixir of the mongoose
    [17574] = { mob = "firebrand pyromancer", zone = "blackrock spire", mapID = 1428 }, -- recipe: greater fire protection potion
    [17575] = { mob = "frostmaul giant", zone = "winterspring", mapID = 1452, x = 0.582, y = 0.674 }, -- recipe: greater frost protection potion
    [17576] = { mob = "cobalt mageweaver", zone = "winterspring", mapID = 1452, x = 0.540, y = 0.544 }, -- recipe: greater arcane protection potion
    [17577] = { mob = "shadow silk poacher", zone = "eastern plaguelands", mapID = 1423 }, -- recipe: greater shadow protection potion
    [17578] = { mob = "world drop (level 55-60)", zone = "western plaguelands / silithus" }, -- recipe: greater nature protection potion
    [17579] = { mob = "scarlet alchemist", zone = "eastern plaguelands", mapID = 1423 }, -- recipe: greater holy protection potion
    [17580] = { mob = "darkmaster gandling", zone = "scholomance", mapID = 1422 }, -- recipe: major mana potion
    [17634] = { mob = "general drakkisath", zone = "blackrock spire", mapID = 1428 }, -- recipe: flask of the titans
    [17635] = { mob = "ras frostwhisper", zone = "scholomance", mapID = 1422 }, -- recipe: flask of supreme power
    [17636] = { mob = "balnazzar", zone = "stratholme", mapID = 1423 }, -- recipe: flask of distilled wisdom
    [17638] = { mob = "gyth", zone = "blackrock spire", mapID = 1428 }, -- recipe: flask of chromatic resistance
    [17637] = { mob = "world drop (level 55-60)", zone = "world drop" }, -- recipe: flask of petrification
    [26276] = { mob = "dark iron geologists / stumblers", zone = "searing gorge", mapID = 1427 }, -- recipe: elixir of greater firepower
    [11478] = { mob = "syndicate mercenary / highwayman", zone = "alterac mountains", mapID = 1416 }, -- recipe: elixir of giant growth

    -- Tailoring
    [18456] = { mob = "darkmaster gandling", zone = "scholomance", mapID = 1422 }, -- pattern: robe of the void
    [18457] = { mob = "firebrand pyromancer", zone = "blackrock spire", mapID = 1428 }, -- pattern: robe of the archmage
    [18458] = { mob = "balnazzar", zone = "stratholme", mapID = 1423 }, -- pattern: truefaith vestments
    [18455] = { mob = "world drop (level 58-60 elites)", zone = "world drop" }, -- pattern: bottomless bag
    [18459] = { mob = "world drop (level 55+)", zone = "felwood / winterspring" }, -- pattern: felcloth shoulders
    [22921] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1449 }, -- pattern: hide of the wild
    [24699] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1449 }, -- pattern: belt of the archmage

    -- Engineering
    [19793] = { mob = "world drop (level 50-60)", zone = "world drop" }, -- schematic: arcane bomb
    [16046] = { mob = "world drop (level 50-60)", zone = "world drop" }, -- schematic: voice amplification modulator
    [22704] = { mob = "floor schematic near golem lord argelmach", zone = "blackrock depths", mapID = 1428 }, -- schematic: field repair bot 74a
    [18653] = { mob = "blackhand dreadweaver", zone = "blackrock spire", mapID = 1428 }, -- schematic: hyper-radiant flame reflector
    [18654] = { mob = "solakar flamewreath", zone = "blackrock spire", mapID = 1428 }, -- schematic: ultra-flash shadow reflector
    [18655] = { mob = "crimson inquisitor", zone = "stratholme", mapID = 1423 }, -- schematic: gyrofreeze ice reflector

    -- Leatherworking
    [24698] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1449 }, -- pattern: shifter's cloak
    [19047] = { mob = "nergal (vendor)", zone = "un'goro crater", mapID = 1449 }, -- pattern: devilsaur gauntlets
    [19048] = { mob = "nergal (vendor)", zone = "un'goro crater", mapID = 1449 }, -- pattern: devilsaur leggings
}

--- Get curated or discovered drop details for a recipe
--- @param spellID number
--- @return string? mob, string? zone, table? coords
function sfui.recipes.GetDropInfo(spellID)
    if not spellID then return nil, nil, nil end
    local c = sfui.recipes.CURATED_DROP_SOURCES and sfui.recipes.CURATED_DROP_SOURCES[spellID]
    if c then
        local loc = c.zone
        if c.mapID and c.x and c.y then
            loc = string.format("%s (%.1f, %.1f)", loc or "map", c.x * 100, c.y * 100)
        end
        return c.mob, loc, (c.mapID and c.x and c.y) and { mapID = c.mapID, x = c.x, y = c.y } or nil
    end
    return nil, nil, nil
end

--- Check if a source (vendor / trainer / quest) is hostile to the active player character
--- @param s table
--- @return boolean isHostile
function sfui.recipes.IsSourceHostile(s)
    if not s then return false end
    local myFaction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
    if not myFaction then return false end
    myFaction = myFaction:lower()

    -- 1. Explicit faction check on source
    local sFac = s.faction and tostring(s.faction):lower()
    if sFac then
        if sFac == "alliance" and myFaction ~= "alliance" then return true end
        if sFac == "horde" and myFaction ~= "horde" then return true end
    end

    -- 2. Known faction-exclusive major cities and racial starting territories
    local z = s.zone and tostring(s.zone):lower()
    if z then
        local hordeZones = {
            ["orgrimmar"]           = true,
            ["undercity"]           = true,
            ["thunder bluff"]       = true,
            ["durotar"]             = true,
            ["mulgore"]             = true,
            ["tirisfal glades"]     = true,
            ["silverpine forest"]   = true,
            ["the barrens"]         = true,
        }
        local allianceZones = {
            ["stormwind city"]      = true,
            ["ironforge"]           = true,
            ["darnassus"]           = true,
            ["westfall"]            = true,
            ["loch modan"]          = true,
            ["redridge mountains"]  = true,
            ["duskwood"]            = true,
            ["dun morogh"]          = true,
            ["darkshore"]           = true,
            ["teldrassil"]          = true,
        }
        if myFaction == "alliance" and hordeZones[z] then return true end
        if myFaction == "horde" and allianceZones[z] then return true end
    end

    -- 3. Contested town check
    local name = s.name and tostring(s.name):lower() or ""
    local desc = s.desc and tostring(s.desc):lower() or ""
    local fullText = (s.zone or "") .. " " .. name .. " " .. desc

    local hordeTowns = { "tarren mill", "brackenwall", "grom'gol", "camp mojache", "sun rock retreat", "freewind post", "shadowprey village", "bloodhoof village", "the bulwark", "stonard", "kargath", "revantusk" }
    local allianceTowns = { "southshore", "astranaar", "feathermoon", "chillwind", "menethil", "aerie peak", "goldshire", "lakeshire", "sentinel hill", "kharanos", "thelsamar", "refuge pointe" }

    if myFaction == "alliance" then
        for _, ht in ipairs(hordeTowns) do
            if fullText:find(ht) then return true end
        end
    elseif myFaction == "horde" then
        for _, at in ipairs(allianceTowns) do
            if fullText:find(at) then return true end
        end
    end

    return false
end

--- Curated authentic coordinates and faction affinities for limited stock recipe vendors
sfui.recipes.CURATED_LIMITED_VENDORS = {
    -- Alchemy
    [3831] = { -- Recipe: Frost Oil
        { name = "bro'kin", zone = "alterac mountains", mapID = 1416, x = 0.384, y = 0.388, faction = "neutral" },
    },
    [5642] = { -- Recipe: Free Action Potion
        { name = "kor'jus", zone = "the barrens", mapID = 1413, x = 0.522, y = 0.318, faction = "horde" },
        { name = "ulthir", zone = "darnassus", mapID = 1457, x = 0.560, y = 0.246, faction = "alliance" },
    },
    [5643] = { -- Recipe: Great Rage Potion
        { name = "hagrus", zone = "orgrimmar", mapID = 1454, x = 0.468, y = 0.460, faction = "horde" },
        { name = "ulthir", zone = "darnassus", mapID = 1457, x = 0.560, y = 0.246, faction = "alliance" },
    },
    [9302] = { -- Recipe: Ghost Dye
        { name = "algor", zone = "undercity", mapID = 1458, x = 0.674, y = 0.380, faction = "horde" },
        { name = "maria lumere", zone = "stormwind city", mapID = 1453, x = 0.556, y = 0.858, faction = "alliance" },
    },
    [12958] = { -- Recipe: Transmute Arcanite
        { name = "alchemist pestlezugg", zone = "tanaris", mapID = 1446, x = 0.508, y = 0.270, faction = "neutral" },
    },
    [13476] = { -- Recipe: Superior Mana Potion
        { name = "algor", zone = "undercity", mapID = 1458, x = 0.674, y = 0.380, faction = "horde" },
        { name = "maria lumere", zone = "stormwind city", mapID = 1453, x = 0.556, y = 0.858, faction = "alliance" },
    },
    [13477] = { -- Recipe: Major Healing Potion
        { name = "evie whirlbrew", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.378, faction = "neutral" },
    },
    [13478] = { -- Recipe: Elixir of Superior Defense
        { name = "soolie berryfizz", zone = "ironforge", mapID = 1455, x = 0.666, y = 0.544, faction = "alliance" },
        { name = "kor'jus", zone = "the barrens", mapID = 1413, x = 0.522, y = 0.318, faction = "horde" },
    },
    [13484] = { -- Recipe: Elixir of Greater Water Breathing
        { name = "gorbold steelhand", zone = "wetlands", mapID = 1437, x = 0.108, y = 0.604, faction = "alliance" },
        { name = "danielle zipstitch", zone = "dustwallow marsh", mapID = 1445, x = 0.366, y = 0.306, faction = "horde" },
    },

    -- Tailoring
    [5771] = { -- Pattern: Red Woolen Bag
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [5772] = { -- Pattern: Heavy Woolen Cloak
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [5774] = { -- Pattern: Phoenix Gloves
        { name = "alexandra bolero", zone = "stormwind city", mapID = 1453, x = 0.534, y = 0.816, faction = "alliance" },
        { name = "mahu", zone = "thunder bluff", mapID = 1456, x = 0.438, y = 0.446, faction = "horde" },
    },
    [5775] = { -- Pattern: Phoenix Pants
        { name = "alexandra bolero", zone = "stormwind city", mapID = 1453, x = 0.534, y = 0.816, faction = "alliance" },
        { name = "mahu", zone = "thunder bluff", mapID = 1456, x = 0.438, y = 0.446, faction = "horde" },
    },
    [6401] = { -- Pattern: Blue Linen Vest
        { name = "danielle zipstitch", zone = "dustwallow marsh", mapID = 1445, x = 0.366, y = 0.306, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7084] = { -- Pattern: Crimson Silk Vest
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7085] = { -- Pattern: Crimson Silk Shoulders
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7086] = { -- Pattern: Crimson Silk Cloak
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7087] = { -- Pattern: Crimson Silk Robe
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7088] = { -- Pattern: Earthen Silk Belt
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7089] = { -- Pattern: Crimson Silk Gloves
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [7090] = { -- Pattern: Green Silk Armor
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.106, y = 0.606, faction = "alliance" },
    },
    [10300] = { -- Pattern: Red Mageweave Headband
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "werg thickblade", zone = "tirisfal glades", mapID = 1420, x = 0.832, y = 0.686, faction = "horde" },
    },
    [10301] = { -- Pattern: Red Mageweave Pants
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "werg thickblade", zone = "tirisfal glades", mapID = 1420, x = 0.832, y = 0.686, faction = "horde" },
    },
    [10302] = { -- Pattern: Red Mageweave Gloves
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "werg thickblade", zone = "tirisfal glades", mapID = 1420, x = 0.832, y = 0.686, faction = "horde" },
    },
    [10314] = { -- Pattern: Lavender Mageweave Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
    },
    [10317] = { -- Pattern: Pink Mageweave Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "banalash", zone = "orgrimmar", mapID = 1454, x = 0.632, y = 0.504, faction = "horde" },
    },
    [10321] = { -- Pattern: Tuxedo Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "millie gregorian", zone = "undercity", mapID = 1458, x = 0.706, y = 0.302, faction = "horde" },
    },
    [10323] = { -- Pattern: Tuxedo Pants
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "millie gregorian", zone = "undercity", mapID = 1458, x = 0.706, y = 0.302, faction = "horde" },
    },
    [10326] = { -- Pattern: Tuxedo Jacket
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "millie gregorian", zone = "undercity", mapID = 1458, x = 0.706, y = 0.302, faction = "horde" },
    },
    [14468] = { -- Pattern: Runecloth Bag
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14476] = { -- Pattern: Cindercloth Vest
        { name = "vhan", zone = "desolace", mapID = 1443, x = 0.552, y = 0.562, faction = "horde" },
        { name = "mai'balir", zone = "tanaris", mapID = 1446, x = 0.528, y = 0.292, faction = "neutral" },
    },
    [14478] = { -- Pattern: Cindercloth Gloves
        { name = "vhan", zone = "desolace", mapID = 1443, x = 0.552, y = 0.562, faction = "horde" },
        { name = "mai'balir", zone = "tanaris", mapID = 1446, x = 0.528, y = 0.292, faction = "neutral" },
    },
    [14480] = { -- Pattern: Wizardweave Robe
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14481] = { -- Pattern: Wizardweave Turbin
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14482] = { -- Pattern: Wizardweave Leggings
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14483] = { -- Pattern: Mooncloth
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14484] = { -- Pattern: Runecloth Cloak
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14486] = { -- Pattern: Runecloth Robe
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14493] = { -- Pattern: Runecloth Boots
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },

    -- Blacksmithing
    [3490] = { -- Plans: Hardened Iron Shortsword
        { name = "kzixx", zone = "duskwood", mapID = 1431, x = 0.818, y = 0.198, faction = "neutral" },
    },
    [3491] = { -- Plans: Massive Iron Axe
        { name = "zarena cromwind", zone = "stranglethorn vale", mapID = 1434, x = 0.276, y = 0.778, faction = "neutral" },
    },
    [3492] = { -- Plans: Moonsteel Broadsword
        { name = "zarena cromwind", zone = "stranglethorn vale", mapID = 1434, x = 0.276, y = 0.778, faction = "neutral" },
    },
    [3493] = { -- Plans: Golden Scale Bracers
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [3494] = { -- Plans: Golden Scale Shoulders
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [3495] = { -- Plans: Golden Scale Coif
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [7990] = { -- Plans: Mithril Scale Shoulders
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [7991] = { -- Plans: Mithril Scale Bracers
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [7992] = { -- Plans: Mithril Scale Pants
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [7993] = { -- Plans: Heavy Mithril Pants
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [7995] = { -- Plans: Heavy Mithril Breastplate
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },

    -- Engineering
    [4408] = { -- Schematic: Mechanical Dragonling
        { name = "vrixx cowl", zone = "stonetalon mountains", mapID = 1442, x = 0.596, y = 0.628, faction = "neutral" },
    },
    [4410] = { -- Schematic: Small Seaforium Charge
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [4411] = { -- Schematic: Gyrochronatom
        { name = "ruppo zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.344, y = 0.378, faction = "neutral" },
    },
    [4412] = { -- Schematic: Iron Grenade
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [4413] = { -- Schematic: Compact Harvest Reaper
        { name = "knaz blunderfluff", zone = "stranglethorn vale", mapID = 1434, x = 0.282, y = 0.758, faction = "neutral" },
    },
    [4414] = { -- Schematic: Advanced Target Dummy
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [10601] = { -- Schematic: Deepdive Helmet
        { name = "jabbey", zone = "tanaris", mapID = 1446, x = 0.670, y = 0.224, faction = "neutral" },
    },
    [10602] = { -- Schematic: Parachute Cloak
        { name = "zan shivsproket", zone = "alterac mountains", mapID = 1416, x = 0.858, y = 0.806, faction = "neutral" },
    },
    [10603] = { -- Schematic: Deadly Scope
        { name = "knockment", zone = "ironforge", mapID = 1455, x = 0.682, y = 0.440, faction = "alliance" },
        { name = "mazk snipeshot", zone = "mulgore", mapID = 1412, x = 0.468, y = 0.604, faction = "horde" },
    },
    [10608] = { -- Schematic: Large Seaforium Charge
        { name = "knaz blunderfluff", zone = "stranglethorn vale", mapID = 1434, x = 0.282, y = 0.758, faction = "neutral" },
    },
    [10609] = { -- Schematic: Mithril Mechanical Dragonling
        { name = "ruppo zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.344, y = 0.378, faction = "neutral" },
    },
    [13309] = { -- Schematic: Mithril Heavy-Bore Rifle
        { name = "ruppo zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.344, y = 0.378, faction = "neutral" },
    },
    [13310] = { -- Schematic: Dark Iron Rifle
        { name = "lokhtos darkbargainer", zone = "blackrock depths", mapID = 1428, faction = "neutral" },
    },
    [13311] = { -- Schematic: Sniper Scope
        { name = "super-seller 680", zone = "desolace", mapID = 1443, x = 0.404, y = 0.792, faction = "neutral" },
    },
    [16041] = { -- Schematic: Catseye Ultra Goggles
        { name = "fizzfeather", zone = "tanaris", mapID = 1446, x = 0.526, y = 0.284, faction = "neutral" },
    },
    [16042] = { -- Schematic: Mithril Gyro-Shot
        { name = "ruppo zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.344, y = 0.378, faction = "neutral" },
    },
    [16043] = { -- Schematic: Spellpower Goggles Xtreme
        { name = "knaz blunderfluff", zone = "stranglethorn vale", mapID = 1434, x = 0.282, y = 0.758, faction = "neutral" },
    },
    [16044] = { -- Schematic: Thorium Widget
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [16045] = { -- Schematic: Thorium Rifle
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [16047] = { -- Schematic: Master Engineer's Goggles
        { name = "knaz blunderfluff", zone = "stranglethorn vale", mapID = 1434, x = 0.282, y = 0.758, faction = "neutral" },
    },
    [16048] = { -- Schematic: Arcanite Dragonling
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },
    [16049] = { -- Schematic: Delicate Arcanite Converter
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },
    [16051] = { -- Schematic: Masterwork Target Dummy
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },

    -- Leatherworking
    [7288] = { -- Pattern: Nimble Leather Gloves
        { name = "danielle zipstitch", zone = "dustwallow marsh", mapID = 1445, x = 0.366, y = 0.306, faction = "horde" },
        { name = "leonard porter", zone = "western plaguelands", mapID = 1422, x = 0.430, y = 0.844, faction = "alliance" },
    },
    [8409] = { -- Pattern: Nightscape Tunic
        { name = "jandia", zone = "thousand needles", mapID = 1441, x = 0.460, y = 0.514, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },
    [8410] = { -- Pattern: Nightscape Headband
        { name = "jandia", zone = "thousand needles", mapID = 1441, x = 0.460, y = 0.514, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },
    [8411] = { -- Pattern: Nightscape Boots
        { name = "jandia", zone = "thousand needles", mapID = 1441, x = 0.460, y = 0.514, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },
    [8412] = { -- Pattern: Nightscape Pants
        { name = "jandia", zone = "thousand needles", mapID = 1441, x = 0.460, y = 0.514, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },

    -- Enchanting
    [6375] = { -- Formula: Enchant 2H Weapon - Lesser Spirit
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [6377] = { -- Formula: Enchant 2H Weapon - Lesser Intellect
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [13378] = { -- Formula: Enchant Shield - Minor Stamina
        { name = "kithas", zone = "undercity", mapID = 1458, x = 0.628, y = 0.612, faction = "horde" },
        { name = "edna mullby", zone = "stormwind city", mapID = 1453, x = 0.444, y = 0.760, faction = "alliance" },
    },
    [13379] = { -- Formula: Enchant Cloak - Minor Agility
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [13380] = { -- Formula: Enchant Shield - Lesser Spirit
        { name = "bena winterhoof", zone = "thunder bluff", mapID = 1456, x = 0.468, y = 0.336, faction = "horde" },
        { name = "tharynn bouden", zone = "elwynn forest", mapID = 1429, x = 0.420, y = 0.672, faction = "alliance" },
    },
    [13538] = { -- Formula: Enchant Weapon - Lesser Elemental Slayer
        { name = "ghok'kah", zone = "dustwallow marsh", mapID = 1445, x = 0.356, y = 0.308, faction = "horde" },
        { name = "alyssa eva", zone = "duskwood", mapID = 1431, x = 0.738, y = 0.444, faction = "alliance" },
    },
    [13635] = { -- Formula: Enchant Cloak - Resistance
        { name = "kania", zone = "silithus", mapID = 1451, x = 0.520, y = 0.392, faction = "neutral" },
    },
    [16243] = { -- Formula: Runed Arcanite Rod
        { name = "lorelae wintersong", zone = "moonglade", mapID = 1450, x = 0.484, y = 0.400, faction = "neutral" },
    },
}

--- Check if a recipe scroll is limited stock
--- @param recipeItemID number
--- @param npcID number?
--- @return boolean isLimited, number? count
function sfui.recipes.IsLimitedStock(recipeItemID, npcID)
    if not recipeItemID then return false end
    if SfuiDB and SfuiDB.contacts and SfuiDB.contacts.vendors and npcID then
        local v = SfuiDB.contacts.vendors[npcID]
        if v and v.items and v.items[recipeItemID] then
            local it = v.items[recipeItemID]
            if it.limited ~= nil and it.limited ~= -1 then
                return true, (type(it.limited) == "number" and it.limited > 0) and it.limited or nil
            end
        end
    end
    if sfui.recipes.LIMITED_RECIPE_ITEMS[recipeItemID] then
        return true, nil
    end
    return false, nil
end

--- Resolve canonical recipe data by spellID, scroll itemID, or output itemID
--- @param id number
--- @return table? recipe
function sfui.recipes.GetRecipe(id)
    if not id then return nil end
    local db = sfui.recipes_camelot
    if not db or not db.recipes then return nil end

    -- 1. Direct spellID lookup
    if db.recipes[id] then
        return db.recipes[id]
    end

    -- 2. Recipe scroll itemID lookup
    if db.items and db.items[id] then
        local spellID = db.items[id]
        return db.recipes[spellID]
    end

    -- 3. Crafted output itemID lookup
    if db.outputs and db.outputs[id] then
        local spellID = db.outputs[id]
        return db.recipes[spellID]
    end

    -- 4. Dynamic fallback for uncataloged / newly added recipes
    local C_TradeSkillUI = _G.C_TradeSkillUI
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local rInfo = C_TradeSkillUI.GetRecipeInfo(id)
        if rInfo and rInfo.name then
            return {
                id        = id,
                name      = rInfo.name,
                skillID   = rInfo.categoryID,
                isDynamic = true,
            }
        end
    end

    local C_Spell = _G.C_Spell
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not spellName and _G.GetSpellInfo then
        spellName = _G.GetSpellInfo(id)
    end
    if spellName then
        return {
            id        = id,
            name      = spellName,
            isDynamic = true,
        }
    end

    local C_Item = _G.C_Item
    if C_Item and C_Item.GetItemInfoInstant then
        local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
        if itemID then
            local itemName = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (_G.GetItemInfo and _G.GetItemInfo(id))
            return {
                name         = itemName or ("item #" .. id),
                recipeItemID = (classID == 9) and id or nil,
                output       = (classID ~= 9) and id or nil,
                isDynamic    = true,
            }
        end
    end

    return nil
end

-- ── Live Contacts Reverse Indices (O(1) lookup optimization) ──────────────────
local itemToLiveVendors = nil
local spellToLiveTrainers = nil
local nameToLiveTrainers = nil
local isLiveIndexDirty = true

function sfui.recipes.InvalidateLiveIndices()
    isLiveIndexDirty = true
end

local function EnsureLiveIndices()
    if not isLiveIndexDirty and itemToLiveVendors and spellToLiveTrainers then
        return
    end

    itemToLiveVendors = {}
    spellToLiveTrainers = {}
    nameToLiveTrainers = {}

    if SfuiDB and SfuiDB.contacts then
        if SfuiDB.contacts.vendors then
            for npcID, vendor in pairs(SfuiDB.contacts.vendors) do
                if vendor.items then
                    for itemID in pairs(vendor.items) do
                        itemToLiveVendors[itemID] = itemToLiveVendors[itemID] or {}
                        table_insert(itemToLiveVendors[itemID], npcID)
                    end
                end
            end
        end

        if SfuiDB.contacts.trainers then
            for npcID, trainer in pairs(SfuiDB.contacts.trainers) do
                if trainer.spells then
                    for spellKey in pairs(trainer.spells) do
                        if type(spellKey) == "number" then
                            spellToLiveTrainers[spellKey] = spellToLiveTrainers[spellKey] or {}
                            table_insert(spellToLiveTrainers[spellKey], npcID)
                        elseif type(spellKey) == "string" then
                            local k = spellKey:lower()
                            nameToLiveTrainers[k] = nameToLiveTrainers[k] or {}
                            table_insert(nameToLiveTrainers[k], npcID)
                        end
                    end
                end
            end
        end
    end

    isLiveIndexDirty = false
end

--- Get all resolved source locations for a recipe
--- @param id number spellID, scroll itemID, or output itemID
--- @return table? result
function sfui.recipes.GetSource(id)
    local recipe = sfui.recipes.GetRecipe(id)
    if not recipe then return nil end

    local spellID = recipe.id or id
    local result = {
        recipeID     = spellID,
        name         = recipe.name,
        skillID      = recipe.skillID,
        minSkill     = recipe.minSkill,
        colors       = recipe.colors,
        output       = recipe.output,
        recipeItemID = recipe.recipeItemID,
        reagents     = recipe.reagents,
        spec         = recipe.spec,
        faction      = recipe.faction,
        standing     = recipe.standing,
        tokens       = recipe.tokens,
        isEvent      = recipe.isEvent,
        event        = recipe.event,
        sources      = {},
    }

    local seenKeys = {}

    -- 1. Prioritize Live Sightings (SfuiDB.contacts via reverse indices)
    if SfuiDB and SfuiDB.contacts then
        EnsureLiveIndices()

        -- Check Live Vendors (O(1) lookup)
        if recipe.recipeItemID and itemToLiveVendors and itemToLiveVendors[recipe.recipeItemID] then
            for _, npcID in ipairs(itemToLiveVendors[recipe.recipeItemID]) do
                local vendor = SfuiDB.contacts.vendors[npcID]
                if vendor and vendor.items and vendor.items[recipe.recipeItemID] then
                    local it = vendor.items[recipe.recipeItemID]
                    local vSource = {
                        type     = "vendor",
                        name     = vendor.name or "vendor",
                        npcID    = tonumber(npcID),
                        zone     = vendor.subzone or vendor.zone,
                        mapID    = vendor.mapID,
                        x        = vendor.x,
                        y        = vendor.y,
                        cost     = it.priceCopper,
                        limited  = it.limited,
                        faction  = it.faction or recipe.faction,
                        standing = it.standing or recipe.standing,
                        tokens   = it.tokens or recipe.tokens,
                        isLive   = true,
                    }
                    if not sfui.recipes.IsSourceHostile(vSource) then
                        local key = "vendor:" .. tostring(npcID)
                        if not seenKeys[key] then
                            seenKeys[key] = true
                            table_insert(result.sources, vSource)
                            if it.faction and not result.faction then result.faction = it.faction end
                            if it.standing and not result.standing then result.standing = it.standing end
                            if it.tokens and not result.tokens then result.tokens = it.tokens end
                            if it.spec and not result.spec then result.spec = it.spec end
                        end
                    end
                end
            end
        end

        -- Check Live Trainers (O(1) lookup)
        if spellToLiveTrainers then
            local trainerNpcIDs = spellToLiveTrainers[spellID]
            if not trainerNpcIDs and recipe.name and nameToLiveTrainers then
                trainerNpcIDs = nameToLiveTrainers[recipe.name:lower()]
            end
            if trainerNpcIDs then
                for _, npcID in ipairs(trainerNpcIDs) do
                    local trainer = SfuiDB.contacts.trainers[npcID]
                    if trainer and trainer.spells then
                        local trSp = trainer.spells[spellID] or (recipe.name and trainer.spells[recipe.name])
                        local key = "trainer:" .. tostring(npcID)
                        if not seenKeys[key] then
                            seenKeys[key] = true
                            table_insert(result.sources, {
                                type     = "trainer",
                                name     = trainer.name or "trainer",
                                npcID    = tonumber(npcID),
                                zone     = trainer.subzone or trainer.zone,
                                mapID    = trainer.mapID,
                                x        = trainer.x,
                                y        = trainer.y,
                                cost     = type(trSp) == "table" and trSp.cost or nil,
                                reqSkill = type(trSp) == "table" and trSp.reqSkill or recipe.minSkill,
                                isLive   = true,
                            })
                        end
                    end
                end
            end
        end
    end

    -- 2. Check Live Finds (Drops & Quests)
    if SfuiDB and SfuiDB.recipe_finds and recipe.name then
        local finds = SfuiDB.recipe_finds
        local rName = recipe.name

        if finds.drops and finds.drops[rName] then
            for _, drop in ipairs(finds.drops[rName]) do
                local key = "drop:" .. (drop.mob or "") .. ":" .. (drop.zone or "")
                if not seenKeys[key] then
                    seenKeys[key] = true
                    table_insert(result.sources, {
                        type   = "drop",
                        name   = drop.mob or "creature drop",
                        zone   = drop.zone,
                        mapID  = drop.mapID,
                        x      = drop.x,
                        y      = drop.y,
                        count  = drop.count,
                        isLive = true,
                    })
                end
            end
        end

        if finds.quests and finds.quests[rName] then
            for _, quest in ipairs(finds.quests[rName]) do
                local key = "quest:" .. tostring(quest.questID or quest.title)
                if not seenKeys[key] then
                    seenKeys[key] = true
                    table_insert(result.sources, {
                        type    = "quest",
                        name    = quest.title,
                        questID = quest.questID,
                        zone    = quest.zone,
                        isLive  = true,
                    })
                end
            end
        end
    end

    -- 2.5 Curated Classic Drop Sources
    local curatedDrop = sfui.recipes.CURATED_DROP_SOURCES and sfui.recipes.CURATED_DROP_SOURCES[spellID]
    if curatedDrop then
        local key = "drop:" .. (curatedDrop.mob or "") .. ":" .. (curatedDrop.zone or "")
        if not seenKeys[key] then
            seenKeys[key] = true
            table_insert(result.sources, {
                type   = "drop",
                name   = curatedDrop.mob,
                zone   = curatedDrop.zone,
                mapID  = curatedDrop.mapID,
                x      = curatedDrop.x,
                y      = curatedDrop.y,
                isLive = false,
            })
        end
    end

    -- 2.6 Curated Limited Stock Vendors (with exact map waypoints and faction safety)
    if recipe.recipeItemID and sfui.recipes.CURATED_LIMITED_VENDORS then
        local limVendors = sfui.recipes.CURATED_LIMITED_VENDORS[recipe.recipeItemID]
        if limVendors then
            for _, v in ipairs(limVendors) do
                if not sfui.recipes.IsSourceHostile(v) then
                    local key = "vendor:" .. (v.name or "") .. ":" .. (v.zone or "")
                    if not seenKeys[key] then
                        seenKeys[key] = true
                        table_insert(result.sources, {
                            type     = "vendor",
                            name     = v.name,
                            npcID    = v.npcID,
                            zone     = v.zone,
                            mapID    = v.mapID,
                            x        = v.x,
                            y        = v.y,
                            cost     = v.cost,
                            limited  = true,
                            faction  = v.faction,
                            isLive   = false,
                        })
                    end
                end
            end
        end
    end

    -- 3. Merge Static Baseline Database (sfui.recipes_camelot)
    if recipe.sources then
        for _, s in ipairs(recipe.sources) do
            local isGenericDrop = (s.type == "drop") and ((not s.name) or s.name == "world / creature drop")
            local isHostile = sfui.recipes.IsSourceHostile(s)
            local isGenericVendorWithCurated = (s.type == "vendor") and ((not s.name) or s.name == "vendor") and (#result.sources > 0)
            if not isHostile and not (isGenericDrop and #result.sources > 0) and not isGenericVendorWithCurated then
                local key = (s.type or "other") .. ":" .. tostring(s.npcID or s.questID or s.name or s.desc)
                if not seenKeys[key] then
                    seenKeys[key] = true
                    table_insert(result.sources, {
                        type     = s.type,
                        name     = s.name,
                        desc     = s.desc,
                        npcID    = s.npcID,
                        questID  = s.questID,
                        zone     = s.zone,
                        mapID    = s.mapID,
                        x        = s.x,
                        y        = s.y,
                        cost     = s.cost,
                        faction  = s.faction or recipe.faction,
                        standing = s.standing or recipe.standing,
                        tokens   = s.tokens or recipe.tokens,
                        reqSkill = s.reqSkill or recipe.minSkill,
                        isLive   = false,
                    })
                end
            end
        end
    end


    -- 4. Blizzard Engine Source Fallback (for uncataloged recipes or client database descriptions)
    if #result.sources == 0 and spellID and _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeSourceText then
        local srcText = _G.C_TradeSkillUI.GetRecipeSourceText(spellID)
        if srcText and srcText ~= "" then
            table_insert(result.sources, {
                type   = "blizzard",
                desc   = srcText,
                isLive = true,
            })
        end
    end

    return result
end

--- Return all non-hostile sources for a recipe record (trainers, vendors, quests, drops)
--- @param r table
--- @return table sources
function sfui.recipes.GetAllNonHostileSources(r)
    if not r then return {} end
    local sources = nil
    if sfui.recipes.GetSource and r.id then
        local res = sfui.recipes.GetSource(r.id)
        if res and res.sources and #res.sources > 0 then
            sources = res.sources
        end
    end
    if not sources or #sources == 0 then
        sources = r.sources
    end
    if not sources or #sources == 0 then
        return {}
    end

    local list = {}
    local seen = {}
    for _, s in ipairs(sources) do
        if not sfui.recipes.IsSourceHostile(s) then
            local key = (s.type or "") .. ":" .. (s.name or s.desc or "") .. ":" .. (s.zone or "") .. ":" .. tostring(s.x or "") .. ":" .. tostring(s.y or "")
            if not seen[key] then
                seen[key] = true
                table_insert(list, s)
            end
        end
    end
    return list
end


--- Format a single source entry for tooltip rendering (strictly lowercase)
--- @param s table
--- @param recipe table?
--- @return string line, boolean hasCoords
function sfui.recipes.FormatSourceLine(s, recipe)
    if not s then return "", false end

    local hasCoords = (s.mapID ~= nil and s.x ~= nil and s.y ~= nil)
    local locStr = s.zone or ""
    if hasCoords and s.x and s.y then
        locStr = string.format("%s (%.1f, %.1f)", locStr ~= "" and locStr or "map", s.x * 100, s.y * 100)
    end

    local st = s.type
    local line = ""

    if st == "trainer" then
        local nameStr = s.name
        local isGeneric = (not nameStr) or (nameStr:lower():find("trainer")) or (s.desc and s.desc:lower():find("trainer"))
        local moneyStr = s.cost and FormatMoney(s.cost)
        local costStr = moneyStr and (" - " .. moneyStr) or ""
        local reqStr = s.reqSkill and (" (requires " .. s.reqSkill .. ")") or ""
        if isGeneric then
            line = string.format("train: any major city%s%s", costStr, reqStr)
        else
            line = string.format("train: %s, %s%s%s", nameStr, locStr ~= "" and locStr or "any city", costStr, reqStr)
        end
    elseif st == "vendor" then
        local nameStr = s.name or s.desc
        local isGeneric = (not nameStr) or (nameStr:lower() == "vendor")
        local itemID = s.recipeItemID or (recipe and recipe.recipeItemID)

        local isLim, limCount = false, nil
        if s.limited ~= nil and s.limited ~= false and s.limited ~= -1 then
            isLim = true
            limCount = (type(s.limited) == "number" and s.limited > 0) and s.limited or nil
        elseif itemID then
            isLim, limCount = sfui.recipes.IsLimitedStock(itemID, s.npcID)
        end
        local limStr = isLim and (limCount and string.format(" (limited stock: %d)", limCount) or " (limited stock)") or ""

        local repFaction = s.faction or (recipe and recipe.faction)
        local repStanding = s.standing or (recipe and recipe.standing)
        local repTokens = s.tokens or (recipe and recipe.tokens)
        local repStr = ""
        if repFaction and repStanding then
            if repTokens then
                repStr = string.format(" (requires %s, %s with %s)", repTokens, repStanding, repFaction)
            else
                repStr = string.format(" (requires %s with %s)", repStanding, repFaction)
            end
        elseif repTokens then
            repStr = string.format(" (requires %s)", repTokens)
        end

        if isGeneric then
            if locStr ~= "" then
                line = string.format("sold by: vendor, %s%s%s", locStr, repStr, limStr)
            else
                line = string.format("sold by: vendor%s%s", repStr, limStr)
            end
        else
            if locStr ~= "" then
                line = string.format("sold by: %s, %s%s%s", nameStr, locStr, repStr, limStr)
            else
                line = string.format("sold by: %s%s%s", nameStr, repStr, limStr)
            end
        end
    elseif st == "object" then
        local nameStr = s.name or "chest / container"
        line = string.format("object: %s%s", nameStr, locStr ~= "" and (", " .. locStr) or "")
    elseif st == "pickpocket" then
        local nameStr = s.name or "lockbox"
        line = string.format("pickpocket: %s%s", nameStr, locStr ~= "" and (", " .. locStr) or "")
    elseif st == "container" then
        local nameStr = s.name or "container"
        line = string.format("container: %s%s", nameStr, locStr ~= "" and (", " .. locStr) or "")
    elseif st == "event" then
        local nameStr = s.name or s.desc or (recipe and recipe.event) or "seasonal event"
        line = string.format("event: %s%s", nameStr, locStr ~= "" and (", " .. locStr) or "")
    elseif st == "drop" then
        local nameStr = s.name or s.desc or "creature drop"
        line = string.format("drop: %s, %s", nameStr, locStr ~= "" and locStr or "world")
    elseif st == "quest" then
        local nameStr = s.name or ("quest #" .. tostring(s.questID))
        line = string.format("quest: %s%s", nameStr, locStr ~= "" and (", " .. locStr) or "")
    elseif st == "blizzard" then
        line = string.format("source: %s", s.desc or "unknown")
    else
        line = string.format("%s: %s", st or "source", s.name or s.desc or "unknown")
    end

    return line, hasCoords
end

--- Set a map pin / user waypoint for a recipe source
--- @param s table
--- @return boolean isSuccess
function sfui.recipes.SetWaypoint(s)
    if not s or not s.mapID or not s.x or not s.y then return false end
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false
    end

    local point = UiMapPoint.CreateFromCoordinates(s.mapID, s.x, s.y)
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        local targetName = s.name or s.desc or "recipe source"
        local zoneName = s.zone or ("map " .. tostring(s.mapID))
        local xPct = math_floor(s.x * 1000 + 0.5) / 10
        local yPct = math_floor(s.y * 1000 + 0.5) / 10
        print(string.format("|cff6600ffsf|rui: waypoint set for %s in %s (%.1f, %.1f)", targetName, zoneName, xPct, yPct))
        return true
    end
    return false
end
