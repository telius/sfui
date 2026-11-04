local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.recipe_catalog or g.recipes or g.professions or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/sources.lua
--  Unified Recipe Source Resolution Engine (Camelot / Classic Forever)
--
--  Resolves exact trainer, vendor, drop, and quest sources for any recipe
--  by spellID, recipe scroll itemID, or crafted output itemID.
--  Merges the comprehensive static baseline (sfui.recipes_camelot) with
--  live player discoveries (SfuiDB.contacts & SfuiDB.recipe_finds).
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

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
    if not copper or type(copper) ~= "number" or copper <= 0 then return nil end
    if common and common.SafeGetCoinTextureString then
        return common.SafeGetCoinTextureString(copper)
    end
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
    if not copper or type(copper) ~= "number" or copper <= 0 then return nil end
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
    [5642]  = true, -- recipe: free action potion
    [5643]  = true, -- recipe: great rage potion
    [6053]  = true, -- recipe: holy protection potion
    [6054]  = true, -- recipe: shadow protection potion
    [6055]  = true, -- recipe: fire protection potion
    [6056]  = true, -- recipe: frost protection potion
    [6057]  = true, -- recipe: nature protection potion
    [6068]  = true, -- recipe: shadow oil
    [9300]  = true, -- recipe: potion of demon slaying
    [9301]  = true, -- recipe: elixir of shadow power
    [9302]  = true, -- recipe: ghost dye
    [12958] = true, -- recipe: transmute arcanite
    [13477] = true, -- recipe: superior mana potion
    [13478] = true, -- recipe: elixir of superior defense
    [14634] = true, -- recipe: frost oil

    -- tailoring
    [4346]  = true, -- pattern: heavy woolen cloak
    [4355]  = true, -- pattern: icy cloak
    [5771]  = true, -- pattern: red linen bag
    [5772]  = true, -- pattern: red woolen bag
    [6270]  = true, -- pattern: blue linen vest
    [6275]  = true, -- pattern: greater adept's robe
    [6401]  = true, -- pattern: dark silk shirt
    [7087]  = true, -- pattern: crimson silk cloak
    [7088]  = true, -- pattern: crimson silk robe
    [7089]  = true, -- pattern: azure silk cloak
    [10300] = true, -- pattern: red mageweave vest
    [10301] = true, -- pattern: white bandit mask
    [10302] = true, -- pattern: red mageweave pants
    [10311] = true, -- pattern: orange martial shirt
    [10314] = true, -- pattern: lavender mageweave shirt
    [10317] = true, -- pattern: pink mageweave shirt
    [10320] = true, -- pattern: red mageweave headband
    [10321] = true, -- pattern: tuxedo shirt
    [10323] = true, -- pattern: tuxedo pants
    [10325] = true, -- pattern: white wedding dress
    [10326] = true, -- pattern: tuxedo jacket
    [14468] = true, -- pattern: runecloth bag
    [14469] = true, -- pattern: runecloth robe
    [14472] = true, -- pattern: runecloth cloak
    [14481] = true, -- pattern: runecloth gloves
    [14483] = true, -- pattern: felcloth pants
    [14488] = true, -- pattern: runecloth boots
    [14526] = true, -- pattern: mooncloth
    [14630] = true, -- pattern: enchanter's cowl
    [22308] = true, -- pattern: enchanted runecloth bag

    -- blacksmithing
    [6047]  = true, -- plans: golden scale coif
    [7995]  = true, -- plans: mithril plate bracers
    [12162] = true, -- plans: hardened iron shortsword
    [12163] = true, -- plans: moonsteel broadsword
    [12164] = true, -- plans: massive iron axe

    -- engineering
    [4408]  = true, -- schematic: mechanical squirrel
    [4409]  = true, -- schematic: small seaforium charge
    [4410]  = true, -- schematic: shadow goggles
    [4411]  = true, -- schematic: flame deflector
    [4412]  = true, -- schematic: moonsight rifle
    [4413]  = true, -- schematic: discombobulator ray
    [4414]  = true, -- schematic: portable bronze mortar
    [4416]  = true, -- schematic: goblin land mine
    [4417]  = true, -- schematic: large seaforium charge
    [7560]  = true, -- schematic: gnomish universal remote
    [7561]  = true, -- schematic: goblin jumper cables
    [7742]  = true, -- schematic: gnomish cloaking device
    [10601] = true, -- schematic: bright-eye goggles
    [10602] = true, -- schematic: deadly scope
    [10607] = true, -- schematic: deepdive helmet
    [10609] = true, -- schematic: mithril mechanical dragonling
    [13308] = true, -- schematic: ice deflector
    [13309] = true, -- schematic: lovingly crafted boomstick
    [13310] = true, -- schematic: accurate scope
    [13311] = true, -- schematic: mechanical dragonling
    [16041] = true, -- schematic: thorium grenade
    [16042] = true, -- schematic: thorium widget
    [16046] = true, -- schematic: masterwork target dummy
    [16050] = true, -- schematic: delicate arcanite converter
    [18652] = true, -- schematic: gyrofreeze ice reflector
    [18656] = true, -- schematic: powerful seaforium charge

    -- leatherworking
    [7288]  = true, -- pattern: rugged leather pants
    [7289]  = true, -- pattern: black whelp cloak
    [8409]  = true, -- pattern: nightscape shoulders
    [15725] = true, -- pattern: wicked leather gauntlets
    [15726] = true, -- pattern: green dragonscale breastplate
    [15734] = true, -- pattern: living shoulders
    [15735] = true, -- pattern: ironfeather shoulders
    [15740] = true, -- pattern: frostsaber boots
    [15741] = true, -- pattern: stormshroud pants
    [15756] = true, -- pattern: runic leather headband
    [15758] = true, -- pattern: devilsaur gauntlets

    -- enchanting
    [6349]  = true, -- formula: enchant 2h weapon - lesser intellect
    [6375]  = true, -- formula: enchant bracer - lesser spirit
    [6377]  = true, -- formula: enchant boots - minor agility
    [11038] = true, -- formula: enchant 2h weapon - lesser spirit
    [11039] = true, -- formula: enchant cloak - minor agility
    [11101] = true, -- formula: enchant bracer - lesser strength
    [11163] = true, -- formula: enchant bracer - lesser deflection
    [11164] = true, -- formula: enchant weapon - lesser beastslayer
    [11165] = true, -- formula: enchant weapon - lesser elemental slayer
    [16217] = true, -- formula: enchant shield - greater stamina
    [16221] = true, -- formula: enchant chest - major health
    [16224] = true, -- formula: enchant cloak - superior defense
    [16243] = true, -- formula: runed arcanite rod
}

--- Curated drop locations and creatures for iconic Classic / Vanilla recipes
sfui.recipes.CURATED_DROP_SOURCES = {
    -- Enchanting
    [20034] = { mob = "scarlet spellbinder", zone = "western plaguelands", mapID = 1422, x = 0.440, y = 0.150 }, -- formula: enchant weapon - crusader
    [20032] = { mob = "spectral researcher", zone = "scholomance", mapID = 1422 }, -- formula: enchant weapon - lifestealing
    [20033] = { mob = "thuzadin shadowcaster", zone = "stratholme", mapID = 1423 }, -- formula: enchant weapon - unholy weapon
    [22749] = { mob = "bosses", zone = "molten core" }, -- formula: enchant weapon - spell power
    [22750] = { mob = "bosses", zone = "molten core" }, -- formula: enchant weapon - healing power
    [13943] = { mob = "spirestone warlord", zone = "blackrock spire", mapID = 1428 }, -- formula: enchant weapon - greater striking
    [20030] = { mob = "blackhand elite", zone = "blackrock spire", mapID = 1428 }, -- formula: enchant 2h weapon - superior impact
    [20031] = { mob = "spirestone butcher", zone = "blackrock spire", mapID = 1428 }, -- formula: enchant weapon - superior striking
    [20011] = { mob = "world drop (level 50-60)", zone = "world drop" }, -- formula: enchant bracer - superior stamina
    [13933] = { mob = "plugger spazzring", zone = "blackrock depths", mapID = 1428 }, -- formula: enchant shield - frost resistance

    -- Cooking
    [8238]  = { mob = "deviate beasts", zone = "the barrens", mapID = 1413 }, -- recipe: savory deviate delight
    [22761] = { mob = "pusillin", zone = "dire maul", mapID = 1444 }, -- recipe: runn tum tuber surprise
    [25659] = { mob = "the scepter of the shifting sands quest chain", zone = "tanaris", mapID = 1446 }, -- recipe: dirge's kickin' chimaerok chops

    -- Blacksmithing
    [16729] = { mob = "world / raid bosses (level 60+)", zone = "world drop" }, -- plans: lionheart helm
    [16741] = { mob = "world drop (level 58-60 elites)", zone = "world drop" }, -- plans: stronghold gauntlets
    [27829] = { mob = "world / raid (level 60+)", zone = "world drop" }, -- plans: titanic leggings
    [22757] = { mob = "bosses", zone = "molten core" }, -- plans: elemental sharpening stone
    [16655] = { mob = "firebrand invoker", zone = "blackrock spire", mapID = 1428 }, -- plans: fiery plate gauntlets
    [16990] = { mob = "goraluk anvilcrack", zone = "blackrock spire", mapID = 1428 }, -- plans: arcanite champion
    [16991] = { mob = "quartermaster zigris", zone = "blackrock spire", mapID = 1428 }, -- plans: annihilator
    [16988] = { mob = "maleki the pallid", zone = "stratholme", mapID = 1423 }, -- plans: hammer of the titans

    -- Alchemy
    [17571] = { mob = "jadefire / legashi satyrs", zone = "felwood / azshara", mapID = 1448 }, -- recipe: elixir of the mongoose
    [17572] = { mob = "world drop (level 50-60)", zone = "world drop" }, -- recipe: purification potion
    [17574] = { mob = "firebrand pyromancer", zone = "blackrock spire", mapID = 1428 }, -- recipe: greater fire protection potion
    [17575] = { mob = "frostmaul giant", zone = "winterspring", mapID = 1452, x = 0.582, y = 0.674 }, -- recipe: greater frost protection potion
    [17577] = { mob = "cobalt mageweaver", zone = "winterspring", mapID = 1452, x = 0.540, y = 0.544 }, -- recipe: greater arcane protection potion
    [17578] = { mob = "dark adept / shadowmage", zone = "eastern plaguelands", mapID = 1423 }, -- recipe: greater shadow protection potion
    [17576] = { mob = "rotting behemoth / decaying horror", zone = "western plaguelands", mapID = 1422 }, -- recipe: greater nature protection potion
    [17580] = { mob = "darkmaster gandling", zone = "scholomance", mapID = 1422 }, -- recipe: major mana potion
    [17635] = { mob = "general drakkisath", zone = "blackrock spire", mapID = 1428 }, -- recipe: flask of the titans
    [17637] = { mob = "ras frostwhisper", zone = "scholomance", mapID = 1422 }, -- recipe: flask of supreme power
    [17636] = { mob = "balnazzar", zone = "stratholme", mapID = 1423 }, -- recipe: flask of distilled wisdom
    [17638] = { mob = "gyth", zone = "blackrock spire", mapID = 1428 }, -- recipe: flask of chromatic resistance
    [17634] = { mob = "world drop (level 55-60)", zone = "world drop" }, -- recipe: flask of petrification
    [26277] = { mob = "dark iron geologists / stumblers", zone = "searing gorge", mapID = 1427 }, -- recipe: elixir of holy power (greater firepower)
    [8240]  = { mob = "deviate beasts / world drop", zone = "the barrens", mapID = 1413 }, -- recipe: elixir of giant growth

    -- Tailoring
    [18458] = { mob = "darkmaster gandling", zone = "scholomance", mapID = 1422 }, -- pattern: robe of the void
    [18457] = { mob = "firebrand pyromancer", zone = "blackrock spire", mapID = 1428 }, -- pattern: robe of the archmage
    [18456] = { mob = "balnazzar", zone = "stratholme", mapID = 1423 }, -- pattern: truefaith vestments
    [18455] = { mob = "world drop (level 58-60 elites)", zone = "world drop" }, -- pattern: bottomless bag
    [18453] = { mob = "world drop (level 55+)", zone = "felwood / winterspring" }, -- pattern: felcloth shoulders
    [22866] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1444 }, -- pattern: belt of the archmage

    -- Engineering
    [19831] = { mob = "world drop (level 50-60)", zone = "world drop" }, -- schematic: arcane bomb
    [19819] = { mob = "crimson inquisitor", zone = "stratholme", mapID = 1423 }, -- schematic: voice amplification modulator
    [22704] = { mob = "floor schematic near golem lord argelmach", zone = "blackrock depths", mapID = 1428 }, -- schematic: field repair bot 74a
    [23081] = { mob = "solakar flamewreath", zone = "blackrock spire", mapID = 1428 }, -- schematic: hyper-radiant flame reflector
    [23082] = { mob = "crimson inquisitor", zone = "stratholme", mapID = 1423 }, -- schematic: ultra-flash shadow reflector

    -- Leatherworking
    [22927] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1444 }, -- pattern: hide of the wild
    [22921] = { mob = "knot thimblejack's cache", zone = "dire maul", mapID = 1444 }, -- pattern: girdle of insight
    [19097] = { mob = "cloning / primal oozes", zone = "un'goro crater", mapID = 1449 }, -- pattern: devilsaur leggings
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
    [5642] = { -- Recipe: Free Action Potion
        { name = "kor'jus", zone = "the barrens", mapID = 1413, x = 0.522, y = 0.318, faction = "horde" },
        { name = "ulthir", zone = "darnassus", mapID = 1457, x = 0.560, y = 0.246, faction = "alliance" },
        { name = "soolie berryfizz", zone = "ironforge", mapID = 1455, x = 0.666, y = 0.544, faction = "alliance" },
    },
    [5643] = { -- Recipe: Great Rage Potion
        { name = "hagrus", zone = "orgrimmar", mapID = 1454, x = 0.468, y = 0.460, faction = "horde" },
        { name = "ulthir", zone = "darnassus", mapID = 1457, x = 0.560, y = 0.246, faction = "alliance" },
    },
    [9301] = { -- Recipe: Elixir of Shadow Power
        { name = "algernon", zone = "undercity", mapID = 1458, x = 0.518, y = 0.746, faction = "horde" },
        { name = "maria lumere", zone = "stormwind city", mapID = 1453, x = 0.556, y = 0.858, faction = "alliance" },
    },
    [9302] = { -- Recipe: Ghost Dye
        { name = "bronk", zone = "feralas", mapID = 1444, x = 0.760, y = 0.434, faction = "horde" },
        { name = "logannas", zone = "feralas", mapID = 1444, x = 0.326, y = 0.438, faction = "alliance" },
    },
    [12958] = { -- Recipe: Transmute Arcanite
        { name = "alchemist pestlezugg", zone = "tanaris", mapID = 1446, x = 0.508, y = 0.270, faction = "neutral" },
    },
    [13477] = { -- Recipe: Superior Mana Potion
        { name = "algernon", zone = "undercity", mapID = 1458, x = 0.518, y = 0.746, faction = "horde" },
        { name = "ulthir", zone = "darnassus", mapID = 1457, x = 0.560, y = 0.246, faction = "alliance" },
    },
    [13478] = { -- Recipe: Elixir of Greater Defense (Elixir of Superior Defense)
        { name = "soolie berryfizz", zone = "ironforge", mapID = 1455, x = 0.666, y = 0.544, faction = "alliance" },
        { name = "kor'jus", zone = "the barrens", mapID = 1413, x = 0.522, y = 0.318, faction = "horde" },
    },
    [14634] = { -- Recipe: Frost Oil
        { name = "bro'kin", zone = "alterac mountains", mapID = 1416, x = 0.384, y = 0.388, faction = "neutral" },
    },

    -- Tailoring
    [4346] = { -- Pattern: Heavy Woolen Cloak
        { name = "banalash", zone = "swamp of sorrows", mapID = 1435, x = 0.446, y = 0.566, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [5771] = { -- Pattern: Red Linen Bag
        { name = "ralen", zone = "the barrens", mapID = 1413, x = 0.450, y = 0.594, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [5772] = { -- Pattern: Red Woolen Bag
        { name = "ralen", zone = "the barrens", mapID = 1413, x = 0.450, y = 0.594, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [6270] = { -- Pattern: Blue Linen Vest
        { name = "ralen", zone = "the barrens", mapID = 1413, x = 0.450, y = 0.594, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [6275] = { -- Pattern: Greater Adept's Robe
        { name = "mahu", zone = "thunder bluff", mapID = 1456, x = 0.438, y = 0.446, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [6401] = { -- Pattern: Dark Silk Shirt
        { name = "mallory", zone = "silverpine forest", mapID = 1421, x = 0.432, y = 0.408, faction = "horde" },
        { name = "sherman femmel", zone = "duskwood", mapID = 1431, x = 0.758, y = 0.460, faction = "alliance" },
    },
    [7087] = { -- Pattern: Crimson Silk Cloak
        { name = "mahu", zone = "thunder bluff", mapID = 1456, x = 0.438, y = 0.446, faction = "horde" },
        { name = "jennabink powerseam", zone = "wetlands", mapID = 1437, x = 0.080, y = 0.558, faction = "alliance" },
    },
    [7088] = { -- Pattern: Crimson Silk Robe
        { name = "super-seller 680", zone = "desolace", mapID = 1443, x = 0.406, y = 0.792, faction = "neutral" },
    },
    [7089] = { -- Pattern: Azure Silk Cloak
        { name = "jun'ha", zone = "arathi highlands", mapID = 1417, x = 0.728, y = 0.364, faction = "horde" },
        { name = "borya", zone = "orgrimmar", mapID = 1454, x = 0.630, y = 0.512, faction = "horde" },
        { name = "alexandra bolero", zone = "stormwind city", mapID = 1453, x = 0.534, y = 0.816, faction = "alliance" },
    },
    [10300] = { -- Pattern: Red Mageweave Vest
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
    },
    [10301] = { -- Pattern: White Bandit Mask
        { name = "muuran", zone = "desolace", mapID = 1443, x = 0.556, y = 0.566, faction = "horde" },
        { name = "xizk goodstitch", zone = "stranglethorn vale", mapID = 1434, x = 0.286, y = 0.768, faction = "neutral" },
    },
    [10302] = { -- Pattern: Red Mageweave Pants
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
    },
    [10311] = { -- Pattern: Orange Martial Shirt
        { name = "mahu", zone = "thunder bluff", mapID = 1456, x = 0.438, y = 0.446, faction = "horde" },
        { name = "alexandra bolero", zone = "stormwind city", mapID = 1453, x = 0.534, y = 0.816, faction = "alliance" },
    },
    [10314] = { -- Pattern: Lavender Mageweave Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "borya", zone = "orgrimmar", mapID = 1454, x = 0.630, y = 0.512, faction = "horde" },
    },
    [10317] = { -- Pattern: Pink Mageweave Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "borya", zone = "orgrimmar", mapID = 1454, x = 0.630, y = 0.512, faction = "horde" },
    },
    [10320] = { -- Pattern: Red Mageweave Headband
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
    },
    [10321] = { -- Pattern: Tuxedo Shirt
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "millie gregorian", zone = "undercity", mapID = 1458, x = 0.706, y = 0.302, faction = "horde" },
    },
    [10323] = { -- Pattern: Tuxedo Pants
        { name = "outfitter eric", zone = "ironforge", mapID = 1455, x = 0.432, y = 0.290, faction = "alliance" },
        { name = "millie gregorian", zone = "undercity", mapID = 1458, x = 0.706, y = 0.302, faction = "horde" },
    },
    [10325] = { -- Pattern: White Wedding Dress
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
    [14469] = { -- Pattern: Runecloth Robe
        { name = "darnall", zone = "moonglade", mapID = 1450, x = 0.516, y = 0.332, faction = "neutral" },
    },
    [14472] = { -- Pattern: Runecloth Cloak
        { name = "darnall", zone = "moonglade", mapID = 1450, x = 0.516, y = 0.332, faction = "neutral" },
    },
    [14481] = { -- Pattern: Runecloth Gloves
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14483] = { -- Pattern: Felcloth Pants
        { name = "lorelae wintersong", zone = "moonglade", mapID = 1450, x = 0.482, y = 0.402, faction = "neutral" },
    },
    [14488] = { -- Pattern: Runecloth Boots
        { name = "darnall", zone = "moonglade", mapID = 1450, x = 0.516, y = 0.332, faction = "neutral" },
    },
    [14526] = { -- Pattern: Mooncloth
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [14630] = { -- Pattern: Enchanter's Cowl
        { name = "xizk goodstitch", zone = "stranglethorn vale", mapID = 1434, x = 0.286, y = 0.768, faction = "neutral" },
    },
    [22308] = { -- Pattern: Enchanted Runecloth Bag
        { name = "vi'el", zone = "winterspring", mapID = 1452, x = 0.588, y = 0.598, faction = "neutral" },
    },

    -- Blacksmithing
    [6047] = { -- Plans: Golden Scale Coif
        { name = "krinkle goodsteel", zone = "tanaris", mapID = 1446, x = 0.514, y = 0.288, faction = "neutral" },
    },
    [7995] = { -- Plans: Mithril Scale Bracers
        { name = "harggan", zone = "the hinterlands", mapID = 1425, x = 0.134, y = 0.440, faction = "alliance" },
        { name = "gharash", zone = "swamp of sorrows", mapID = 1435, x = 0.470, y = 0.546, faction = "horde" },
    },
    [12162] = { -- Plans: Hardened Iron Shortsword
        { name = "kzixx", zone = "duskwood", mapID = 1431, x = 0.818, y = 0.198, faction = "neutral" },
        { name = "jaquilina dramet", zone = "stranglethorn vale", mapID = 1434, x = 0.358, y = 0.106, faction = "neutral" },
    },
    [12163] = { -- Plans: Moonsteel Broadsword
        { name = "zarena cromwind", zone = "stranglethorn vale", mapID = 1434, x = 0.276, y = 0.778, faction = "neutral" },
    },
    [12164] = { -- Plans: Massive Iron Axe
        { name = "vharr", zone = "stranglethorn vale", mapID = 1434, x = 0.322, y = 0.278, faction = "horde" },
        { name = "jaquilina dramet", zone = "stranglethorn vale", mapID = 1434, x = 0.358, y = 0.106, faction = "neutral" },
    },

    -- Engineering
    [7560] = { -- Schematic: Gnomish Universal Remote
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [7561] = { -- Schematic: Goblin Jumper Cables
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
        { name = "gnaz blunderflame", zone = "stranglethorn vale", mapID = 1434, x = 0.510, y = 0.352, faction = "neutral" },
    },
    [7742] = { -- Schematic: Gnomish Cloaking Device
        { name = "zan shivsproket", zone = "alterac mountains", mapID = 1416, x = 0.858, y = 0.806, faction = "neutral" },
    },
    [10602] = { -- Schematic: Deadly Scope
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [10607] = { -- Schematic: Deepdive Helmet
        { name = "jabbey", zone = "tanaris", mapID = 1446, x = 0.670, y = 0.224, faction = "neutral" },
    },
    [10609] = { -- Schematic: Mithril Mechanical Dragonling
        { name = "ruppo zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.344, y = 0.378, faction = "neutral" },
    },
    [13308] = { -- Schematic: Ice Deflector
        { name = "kireena", zone = "desolace", mapID = 1443, x = 0.510, y = 0.534, faction = "horde" },
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
    },
    [13309] = { -- Schematic: Lovingly Crafted Boomstick
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [13310] = { -- Schematic: Accurate Scope
        { name = "mazk snipeshot", zone = "stranglethorn vale", mapID = 1434, x = 0.284, y = 0.752, faction = "neutral" },
    },
    [13311] = { -- Schematic: Mechanical Dragonling
        { name = "gnaz blunderflame", zone = "stranglethorn vale", mapID = 1434, x = 0.510, y = 0.352, faction = "neutral" },
    },
    [16041] = { -- Schematic: Thorium Grenade
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [16042] = { -- Schematic: Thorium Widget
        { name = "gearcutter cogspinner", zone = "ironforge", mapID = 1455, x = 0.678, y = 0.430, faction = "alliance" },
        { name = "sovik", zone = "orgrimmar", mapID = 1454, x = 0.756, y = 0.252, faction = "horde" },
    },
    [16046] = { -- Schematic: Masterwork Target Dummy
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },
    [16050] = { -- Schematic: Delicate Arcanite Converter
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },
    [18652] = { -- Schematic: Gyrofreeze Ice Reflector
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },
    [18656] = { -- Schematic: Powerful Seaforium Charge
        { name = "xizzer fizzbolt", zone = "winterspring", mapID = 1452, x = 0.608, y = 0.386, faction = "neutral" },
    },

    -- Leatherworking
    [7289] = { -- Pattern: Black Whelp Cloak
        { name = "bliztik", zone = "duskwood", mapID = 1431, x = 0.180, y = 0.544, faction = "neutral" },
    },
    [8409] = { -- Pattern: Nightscape Shoulders
        { name = "jandia", zone = "thousand needles", mapID = 1441, x = 0.460, y = 0.514, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },
    [15725] = { -- Pattern: Wicked Leather Gauntlets
        { name = "leonard porter", zone = "western plaguelands", mapID = 1422, x = 0.430, y = 0.844, faction = "alliance" },
        { name = "werg thickblade", zone = "tirisfal glades", mapID = 1420, x = 0.832, y = 0.686, faction = "horde" },
    },
    [15726] = { -- Pattern: Green Dragonscale Breastplate
        { name = "masat t'andr", zone = "swamp of sorrows", mapID = 1435, x = 0.264, y = 0.316, faction = "neutral" },
    },
    [15734] = { -- Pattern: Living Shoulders
        { name = "jangdor swiftstrider", zone = "feralas", mapID = 1444, x = 0.744, y = 0.428, faction = "horde" },
        { name = "pratt mcgrubben", zone = "feralas", mapID = 1444, x = 0.306, y = 0.428, faction = "alliance" },
    },
    [15735] = { -- Pattern: Ironfeather Shoulders
        { name = "gigget zipcoil", zone = "the hinterlands", mapID = 1425, x = 0.346, y = 0.384, faction = "neutral" },
    },
    [15740] = { -- Pattern: Frostsaber Boots
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [15741] = { -- Pattern: Stormshroud Pants
        { name = "leonard porter", zone = "western plaguelands", mapID = 1422, x = 0.430, y = 0.844, faction = "alliance" },
        { name = "werg thickblade", zone = "tirisfal glades", mapID = 1420, x = 0.832, y = 0.686, faction = "horde" },
    },
    [15756] = { -- Pattern: Runic Leather Headband
        { name = "jase farlane", zone = "eastern plaguelands", mapID = 1423, x = 0.748, y = 0.518, faction = "neutral" },
    },
    [15758] = { -- Pattern: Devilsaur Gauntlets
        { name = "nergul", zone = "un'goro crater", mapID = 1449, x = 0.434, y = 0.080, faction = "neutral" },
    },

    -- Enchanting
    [6349] = { -- Formula: Enchant 2H Weapon - Lesser Intellect
        { name = "kithas", zone = "orgrimmar", mapID = 1454, x = 0.538, y = 0.380, faction = "horde" },
        { name = "lilly", zone = "silverpine forest", mapID = 1421, x = 0.430, y = 0.508, faction = "horde" },
        { name = "tharynn bouden", zone = "elwynn forest", mapID = 1429, x = 0.420, y = 0.672, faction = "alliance" },
    },
    [6375] = { -- Formula: Enchant Bracer - Lesser Spirit
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [6377] = { -- Formula: Enchant Boots - Minor Agility
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [11038] = { -- Formula: Enchant 2H Weapon - Lesser Spirit
        { name = "hula'mahi", zone = "the barrens", mapID = 1413, x = 0.514, y = 0.302, faction = "horde" },
        { name = "mythrin'dir", zone = "darnassus", mapID = 1457, x = 0.606, y = 0.190, faction = "alliance" },
    },
    [11039] = { -- Formula: Enchant Cloak - Minor Agility
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [11101] = { -- Formula: Enchant Bracer - Lesser Strength
        { name = "kulwia", zone = "stonetalon mountains", mapID = 1442, x = 0.454, y = 0.594, faction = "horde" },
        { name = "dalria", zone = "ashenvale", mapID = 1440, x = 0.350, y = 0.520, faction = "alliance" },
    },
    [11163] = { -- Formula: Enchant Bracer - Lesser Deflection
        { name = "keena", zone = "arathi highlands", mapID = 1417, x = 0.740, y = 0.326, faction = "horde" },
        { name = "drovnar strongbrew", zone = "arathi highlands", mapID = 1417, x = 0.464, y = 0.470, faction = "alliance" },
    },
    [11164] = { -- Formula: Enchant Weapon - Lesser Beastslayer
        { name = "tunkk", zone = "arathi highlands", mapID = 1417, x = 0.748, y = 0.344, faction = "horde" },
        { name = "hammon karwn", zone = "arathi highlands", mapID = 1417, x = 0.464, y = 0.474, faction = "alliance" },
    },
    [11165] = { -- Formula: Enchant Weapon - Lesser Elemental Slayer
        { name = "tunkk", zone = "arathi highlands", mapID = 1417, x = 0.748, y = 0.344, faction = "horde" },
        { name = "hammon karwn", zone = "arathi highlands", mapID = 1417, x = 0.464, y = 0.474, faction = "alliance" },
    },
    [16217] = { -- Formula: Enchant Shield - Greater Stamina
        { name = "daniel bartlett", zone = "undercity", mapID = 1458, x = 0.642, y = 0.376, faction = "horde" },
        { name = "mythrin'dir", zone = "darnassus", mapID = 1457, x = 0.606, y = 0.190, faction = "alliance" },
    },
    [16221] = { -- Formula: Enchant Chest - Major Health
        { name = "qia", zone = "winterspring", mapID = 1452, x = 0.612, y = 0.372, faction = "neutral" },
    },
    [16224] = { -- Formula: Enchant Cloak - Superior Defense
        { name = "lorelae wintersong", zone = "moonglade", mapID = 1450, x = 0.484, y = 0.400, faction = "neutral" },
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
    id = tonumber(id) or id
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
                        local trSp = trainer.spells[spellID] or (recipe.name and (trainer.spells[recipe.name:lower()] or trainer.spells[recipe.name]))
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
                    local nameKey = v.name and ("vendor_name:" .. v.name:lower()) or nil
                    if not seenKeys[key] and (not nameKey or not seenKeys[nameKey]) then
                        seenKeys[key] = true
                        if nameKey then seenKeys[nameKey] = true end
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
        local isLimItem = (recipe.recipeItemID and sfui.recipes.LIMITED_RECIPE_ITEMS and sfui.recipes.LIMITED_RECIPE_ITEMS[recipe.recipeItemID]) and true or nil
        for _, s in ipairs(recipe.sources) do
            local isGenericDrop = (s.type == "drop") and ((not s.name) or s.name == "world / creature drop")
            local isHostile = sfui.recipes.IsSourceHostile(s)
            local isGenericVendorWithCurated = (s.type == "vendor") and ((not s.name) or s.name == "vendor") and (#result.sources > 0)
            if not isHostile and not (isGenericDrop and #result.sources > 0) and not isGenericVendorWithCurated then
                local key = (s.type or "other") .. ":" .. tostring(s.npcID or s.questID or s.name or s.desc)
                local nameKey = (s.type == "vendor" and s.name) and ("vendor_name:" .. s.name:lower()) or nil
                if not seenKeys[key] and (not nameKey or not seenKeys[nameKey]) then
                    seenKeys[key] = true
                    if nameKey then seenKeys[nameKey] = true end
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
                        limited  = s.limited or (s.type == "vendor" and isLimItem) or nil,
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

--- Return the first non-hostile source for a recipe record (trainers, vendors, quests, drops)
--- @param r table
--- @return table? source
function sfui.recipes.GetFirstNonHostileSource(r)
    local list = sfui.recipes.GetAllNonHostileSources and sfui.recipes.GetAllNonHostileSources(r)
    return list and list[1] or nil
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
    local targetName = s.name or s.desc or "recipe source"
    local zoneName = s.zone or ("map " .. tostring(s.mapID))
    local xPct = math_floor(s.x * 1000 + 0.5) / 10
    local yPct = math_floor(s.y * 1000 + 0.5) / 10
    local label = string.format("%s in %s (%.1f, %.1f)", targetName, zoneName, xPct, yPct)

    if sfui.map and sfui.map.SetUserWaypoint then
        return sfui.map.SetUserWaypoint(s.mapID, s.x, s.y, label)
    end

    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return false
    end

    local point = UiMapPoint.CreateFromCoordinates(s.mapID, s.x, s.y)
    local ok = pcall(C_Map.SetUserWaypoint, point)
    if ok then
        if sfui.map and sfui.map.SetSuperTrackedUserWaypoint then
            sfui.map.SetSuperTrackedUserWaypoint(true)
        elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        local printFn = (common and common.print) or print
        printFn("waypoint set for " .. label)
        return true
    end
    return false
end

-- ─── Profession Mapping Helpers ───────────────────────────────────────────────
local SKILL_ID_TO_CANONICAL_NAME = {
    [171] = "alchemy",
    [164] = "blacksmithing",
    [185] = "cooking",
    [333] = "enchanting",
    [202] = "engineering",
    [129] = "first aid",
    [165] = "leatherworking",
    [197] = "tailoring",
}

--- Get canonical profession name from skillLine ID
--- @param skillID number
--- @return string? name
function sfui.recipes.GetProfessionName(skillID)
    skillID = tonumber(skillID)
    return skillID and SKILL_ID_TO_CANONICAL_NAME[skillID] or nil
end

