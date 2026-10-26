local addonName, addon = ...
sfui = sfui or {}
sfui.fishing_data = sfui.fishing_data or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/data/fishing_camelot.lua
--  Authoritative Fishing Data for Camelot & Classic Forever
--
--  Synchronized automatically from Wowhead Forever endpoints.
--  Zone skill thresholds, classic lures, and empirical zone loot tables.
-- ══════════════════════════════════════════════════════════════════════════════

local D = sfui.fishing_data
local pairs, ipairs, tonumber = pairs, ipairs, tonumber
local table_sort = table.sort

-- ─── 1. Classic Lures ────────────────────────────────────────────────────────
-- Ordered best first. skill = required fishing rank, bonus = added fishing skill.
D.LURES = {
    { itemID = 6533, skill = 100, bonus = 100, name = "aquadynamic fish attractor" },
    { itemID = 6532, skill = 100, bonus = 75, name = "bright baubles" },
    { itemID = 7307, skill = 100, bonus = 75, name = "flesh eating worm" },
    { itemID = 6530, skill = 50, bonus = 50, name = "nightcrawlers" },
    { itemID = 6811, skill = 50, bonus = 50, name = "aquadynamic fish lens" },
    { itemID = 6529, skill = 0, bonus = 25, name = "shiny bauble" },
}

-- Fast lookup of known lure item IDs
D.LURE_ITEM_IDS = {}
for _, lure in ipairs(D.LURES) do
    D.LURE_ITEM_IDS[lure.itemID] = lure
end

-- ─── 2. Zone Skill Requirements ──────────────────────────────────────────────
-- Minimum fishing skill (base + lure + gear) needed for 0% escape rate by classic UiMap ID.
-- Calculation: CMaNGOS classic-db base_level + 95.
D.ZONE_SKILL = {
    [1411] = 25,  -- Durotar
    [1412] = 25,  -- Mulgore
    [1413] = 75,  -- The Barrens
    [1416] = 225,  -- Arathi Highlands
    [1417] = 225,  -- Badlands
    [1420] = 25,  -- Tirisfal Glades
    [1421] = 75,  -- Silverpine Forest
    [1422] = 300,  -- Western Plaguelands
    [1423] = 425,  -- Eastern Plaguelands
    [1424] = 150,  -- Hillsbrad Foothills
    [1425] = 300,  -- The Hinterlands
    [1426] = 25,  -- Dun Morogh
    [1428] = 425,  -- Burning Steppes
    [1429] = 25,  -- Elwynn Forest
    [1430] = 425,  -- Deadwind Pass
    [1431] = 150,  -- Duskwood
    [1432] = 75,  -- Loch Modan
    [1433] = 150,  -- Redridge Mountains
    [1434] = 225,  -- Stranglethorn Vale
    [1435] = 225,  -- Swamp of Sorrows
    [1436] = 75,  -- Westfall
    [1437] = 150,  -- Wetlands
    [1438] = 25,  -- Teldrassil
    [1439] = 75,  -- Darkshore
    [1440] = 150,  -- Ashenvale
    [1441] = 225,  -- Thousand Needles
    [1442] = 150,  -- Stonetalon Mountains
    [1443] = 225,  -- Desolace
    [1444] = 300,  -- Feralas
    [1445] = 225,  -- Dustwallow Marsh
    [1446] = 300,  -- Tanaris
    [1447] = 300,  -- Azshara
    [1448] = 300,  -- Felwood
    [1449] = 300,  -- Un'Goro Crater
    [1450] = 300,  -- Moonglade
    [1451] = 425,  -- Silithus
    [1452] = 425,  -- Winterspring
    [1453] = 75,  -- Stormwind City
    [1454] = 75,  -- Orgrimmar
    [1455] = 75,  -- Ironforge
    [1456] = 75,  -- Thunder Bluff
    [1457] = 75,  -- Darnassus
    [1458] = 75,  -- Undercity
    [2521] = 25,  -- Zephras Isle
}

-- Sub-areas requiring higher skill than the surrounding zone
D.ZONE_SKILL_PARTS = {
    [1434] = { skill = 300, area = "jaguero isle" },
    [1444] = { skill = 425, area = "jademir lake" },
    [1447] = { skill = 425, area = "bay of storms / scalebeard" },
}

-- Trainer milestone reminders
D.MILESTONES = {
    [75] = { from = 50, text = "learn journeyman fishing from a fishing trainer." },
    [150] = { from = 125, text = "buy 'expert fishing - the bass and you' from old man heming in booty bay." },
    [225] = { from = 225, text = "complete the quest 'nat pagle, angler extreme' (dustwallow marsh) for artisan." },
}

-- ─── 3. Zone Loot Tables ─────────────────────────────────────────────────────
-- Mapping: [mapID] = { { itemID, sharePercent, kind }, ... }
-- kind: "f" = fish, "c" = container / trunk / chest / clam, "q" = quest, "t" = trophy
D.ZONE_FISH = {
    [1411] = { { 6303, 98.0, "f" }, { 6356, 2.0, "c" } }, -- Durotar
    [1412] = { { 6291, 59.4, "f" }, { 6289, 40.4, "f" }, { 6643, 0.2, "c" } }, -- Mulgore
    [1413] = { { 6361, 50.0, "f" }, { 6303, 33.5, "f" }, { 6358, 15.0, "f" }, { 6307, 0.5, "c" }, { 6351, 0.5, "c" }, { 6353, 0.5, "c" } }, -- The Barrens
    [1420] = { { 6289, 66.7, "f" }, { 6299, 33.3, "f" } }, -- Tirisfal Glades
    [1421] = { { 6289, 66.7, "f" }, { 6299, 33.3, "f" } }, -- Silverpine Forest
    [1424] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Hillsbrad Foothills
    [1426] = { { 6291, 59.4, "f" }, { 6289, 40.4, "f" }, { 6643, 0.2, "c" } }, -- Dun Morogh
    [1429] = { { 6291, 59.4, "f" }, { 6289, 40.4, "f" }, { 6643, 0.2, "c" } }, -- Elwynn Forest
    [1431] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Duskwood
    [1432] = { { 6317, 37.7, "f" }, { 6289, 31.7, "f" }, { 6308, 19.0, "f" }, { 6291, 11.4, "f" }, { 6645, 0.2, "c" } }, -- Loch Modan
    [1433] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Redridge Mountains
    [1436] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Westfall
    [1437] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Wetlands
    [1438] = { { 6291, 59.4, "f" }, { 6289, 40.4, "f" }, { 6643, 0.2, "c" } }, -- Teldrassil
    [1439] = { { 6361, 33.2, "f" }, { 12238, 33.3, "f" }, { 6303, 20.6, "f" }, { 6358, 11.1, "f" }, { 6307, 0.6, "c" }, { 6351, 0.6, "c" }, { 6353, 0.6, "c" } }, -- Darkshore
    [1440] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Ashenvale
    [1442] = { { 6308, 64.2, "f" }, { 6289, 35.5, "f" }, { 6647, 0.3, "c" } }, -- Stonetalon Mountains
    [1453] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Stormwind City
    [1454] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Orgrimmar
    [1455] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Ironforge
    [1456] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Thunder Bluff
    [1457] = { { 6289, 50.9, "f" }, { 6308, 30.5, "f" }, { 6291, 18.3, "f" }, { 6645, 0.3, "c" } }, -- Darnassus
    [1458] = { { 6289, 48.3, "f" }, { 6299, 18.1, "f" }, { 6308, 18.1, "f" }, { 6291, 15.1, "f" }, { 6645, 0.4, "c" } }, -- Undercity
    [2521] = { { 6291, 53.6, "f" }, { 6289, 46.4, "f" } }, -- Zephras Isle
}

-- Higher-level zones (Level 30+) and contested waters
D.ZONE_FISH_CLASSIC = {
    [1416] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Arathi Highlands
    [1417] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Badlands
    [1422] = { { 13758, 36.0, "f" }, { 13759, 18.2, "f" }, { 13760, 18.2, "f" }, { 6358, 10.1, "f" }, { 8365, 10.1, "f" }, { 13757, 7.1, "f" }, { 13881, 0.3, "c" } }, -- Western Plaguelands
    [1423] = { { 13889, 30.8, "f" }, { 13759, 17.2, "f" }, { 13760, 17.2, "f" }, { 13890, 17.2, "f" }, { 13757, 12.1, "f" }, { 13758, 5.1, "f" }, { 13891, 0.4, "c" } }, -- Eastern Plaguelands
    [1425] = { { 13758, 36.0, "f" }, { 13759, 18.2, "f" }, { 13760, 18.2, "f" }, { 6358, 10.1, "f" }, { 8365, 10.1, "f" }, { 13757, 7.1, "f" }, { 13881, 0.3, "c" } }, -- The Hinterlands
    [1428] = { { 13889, 30.8, "f" }, { 13759, 17.2, "f" }, { 13760, 17.2, "f" }, { 13890, 17.2, "f" }, { 13757, 12.1, "f" }, { 13758, 5.1, "f" }, { 13891, 0.4, "c" } }, -- Burning Steppes
    [1430] = { { 13757, 100.0, "f" } }, -- Deadwind Pass
    [1434] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Stranglethorn Vale
    [1435] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Swamp of Sorrows
    [1441] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Thousand Needles
    [1443] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Desolace
    [1444] = { { 8365, 34.7, "f" }, { 6308, 20.3, "f" }, { 13758, 17.9, "f" }, { 13759, 9.1, "f" }, { 13760, 9.1, "f" }, { 6358, 5.1, "f" }, { 13757, 3.5, "f" }, { 13881, 0.2, "c" }, { 8366, 0.1, "c" } }, -- Feralas
    [1445] = { { 8365, 59.2, "f" }, { 6308, 40.5, "f" }, { 8366, 0.3, "c" } }, -- Dustwallow Marsh
    [1446] = { { 4603, 21.1, "f" }, { 13756, 21.0, "f" }, { 13422, 12.6, "f" }, { 13754, 12.6, "f" }, { 6359, 8.4, "f" }, { 6362, 8.4, "f" }, { 13755, 8.4, "f" }, { 7973, 6.7, "c" }, { 13874, 0.4, "c" }, { 13875, 0.4, "c" } }, -- Tanaris
    [1447] = { { 13758, 29.8, "f" }, { 13759, 15.2, "f" }, { 13760, 15.2, "f" }, { 6358, 8.4, "f" }, { 8365, 8.4, "f" }, { 13755, 8.4, "f" }, { 13756, 8.4, "f" }, { 13757, 5.9, "f" }, { 13881, 0.3, "c" } }, -- Azshara
    [1448] = { { 13758, 36.0, "f" }, { 13759, 18.2, "f" }, { 13760, 18.2, "f" }, { 6358, 10.1, "f" }, { 8365, 10.1, "f" }, { 13757, 7.1, "f" }, { 13881, 0.3, "c" } }, -- Felwood
    [1449] = { { 13758, 36.0, "f" }, { 13759, 18.2, "f" }, { 13760, 18.2, "f" }, { 6358, 10.1, "f" }, { 8365, 10.1, "f" }, { 13757, 7.1, "f" }, { 13881, 0.3, "c" } }, -- Un'Goro Crater
    [1450] = { { 13758, 36.0, "f" }, { 13759, 18.2, "f" }, { 13760, 18.2, "f" }, { 6358, 10.1, "f" }, { 8365, 10.1, "f" }, { 13757, 7.1, "f" }, { 13881, 0.3, "c" } }, -- Moonglade
    [1451] = { { 13889, 30.8, "f" }, { 13759, 17.2, "f" }, { 13760, 17.2, "f" }, { 13890, 17.2, "f" }, { 13757, 12.1, "f" }, { 13758, 5.1, "f" }, { 13891, 0.4, "c" } }, -- Silithus
    [1452] = { { 13889, 30.8, "f" }, { 13759, 17.2, "f" }, { 13760, 17.2, "f" }, { 13890, 17.2, "f" }, { 13757, 12.1, "f" }, { 13758, 5.1, "f" }, { 13891, 0.4, "c" } }, -- Winterspring
}

-- ─── 4. Pre-Indexed Catalog of All Species ───────────────────────────────────
local speciesCatalog = nil

local function BuildSpeciesCatalog()
    if speciesCatalog then return speciesCatalog end
    speciesCatalog = {}

    local function add_list(list, isClassic)
        for mapID, fishEntries in pairs(list) do
            for _, entry in ipairs(fishEntries) do
                local itemID = entry[1]
                local share = entry[2]
                local kind = entry[3]

                local item = speciesCatalog[itemID]
                if not item then
                    item = {
                        itemID = itemID,
                        kind = kind,
                        isContainer = (kind == "c"),
                        zones = {},
                        minSkill = 9999,
                    }
                    speciesCatalog[itemID] = item
                end

                local reqSkill = D.ZONE_SKILL[mapID] or 0
                if reqSkill > 0 and reqSkill < item.minSkill then
                    item.minSkill = reqSkill
                end

                table.insert(item.zones, {
                    mapID = mapID,
                    share = share,
                    isClassic = isClassic,
                    reqSkill = reqSkill,
                })
            end
        end
    end

    add_list(D.ZONE_FISH, false)
    add_list(D.ZONE_FISH_CLASSIC, true)

    -- Sort zones per fish by highest drop percentage
    for _, item in pairs(speciesCatalog) do
        if item.minSkill == 9999 then item.minSkill = 0 end
        table_sort(item.zones, function(a, b)
            return (a.share or 0) > (b.share or 0)
        end)
    end

    return speciesCatalog
end

-- ─── 5. Public Query API ─────────────────────────────────────────────────────

--- Returns the required fishing skill for a given mapID
--- @param mapID number
--- @return number requiredSkill, string|nil subAreaHint
function D.GetZoneRequirement(mapID)
    if not mapID or mapID <= 0 then return nil end
    local req = D.ZONE_SKILL[mapID]
    local sub = D.ZONE_SKILL_PARTS[mapID]
    return req, sub
end

--- Returns loot table entries for a specific zone
--- @param mapID number
--- @return table|nil entries, boolean isClassicOnly
function D.GetZoneLoot(mapID)
    if not mapID or mapID <= 0 then return nil, false end
    if D.ZONE_FISH[mapID] then
        return D.ZONE_FISH[mapID], false
    elseif D.ZONE_FISH_CLASSIC[mapID] then
        return D.ZONE_FISH_CLASSIC[mapID], true
    end
    return nil, false
end

--- Returns catalog item for a specific fish/container itemID
--- @param itemID number
--- @return table|nil
function D.GetSpeciesInfo(itemID)
    local catalog = BuildSpeciesCatalog()
    return catalog and catalog[itemID]
end

--- Returns the full list of all cataloged species
--- @return table
function D.GetAllSpecies()
    return BuildSpeciesCatalog()
end

--- Returns all known fishing zones with their requirement
--- @return table array of { mapID, reqSkill, sub }
function D.GetAllWaters()
    local waters = {}
    for mapID, req in pairs(D.ZONE_SKILL) do
        waters[#waters + 1] = {
            mapID = mapID,
            reqSkill = req,
            sub = D.ZONE_SKILL_PARTS[mapID],
        }
    end
    table_sort(waters, function(a, b)
        if a.reqSkill ~= b.reqSkill then
            return a.reqSkill < b.reqSkill
        end
        return a.mapID < b.mapID
    end)
    return waters
end

--- Returns best bag lure that the player can use given their current skill rank
--- @param skillRank number
--- @return table|nil { itemID, bonus, bag, slot, link, count }
function D.FindBestLureInBags(skillRank)
    skillRank = skillRank or 0
    local best = nil

    local common = sfui.common
    if not common or not common.for_each_bag_item then return nil end

    local C_Container = _G.C_Container
    common.for_each_bag_item(function(bag, slot, itemID, itemLink)
        if itemID and D.LURE_ITEM_IDS[itemID] then
            local lureDef = D.LURE_ITEM_IDS[itemID]
            if skillRank >= lureDef.skill then
                if not best or lureDef.bonus > best.bonus then
                    local count = 1
                    if C_Container and C_Container.GetContainerItemInfo then
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.stackCount then count = info.stackCount end
                    elseif _G.GetContainerItemInfo then
                        local _, c = _G.GetContainerItemInfo(bag, slot)
                        if c and c > 0 then count = c end
                    end
                    best = {
                        itemID = itemID,
                        name = lureDef.name,
                        bonus = lureDef.bonus,
                        skill = lureDef.skill,
                        bag = bag,
                        slot = slot,
                        link = itemLink,
                        count = count,
                    }
                end
            end
        end
    end, false, true, false)

    return best
end

