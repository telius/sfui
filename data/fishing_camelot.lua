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
D.ZONE_SKILL = {
    [1411] = 25,  -- Durotar
    [1412] = 25,  -- Mulgore
    [1413] = 75,  -- The Barrens
    [1416] = 225,  -- Alterac Mountains
    [1417] = 225,  -- Arathi Highlands
    [1419] = 300,  -- Blasted Lands
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
    [1459] = 300,  -- Alterac Valley
    [2482] = 425,  -- Mount Hyjal
    [2521] = 25,  -- Zephras Isle
    [2548] = 225,  -- Riverglades
    [2652] = 300,  -- Shen'dralas
    [100718] = 25,  -- Wailing Caverns
    [100719] = 75,  -- Blackfathom Deeps
    [100796] = 150,  -- Scarlet Monastery
    [101477] = 205,  -- Sunken Temple
    [101977] = 330,  -- Zul'Gurub
    [102017] = 330,  -- Stratholme
    [102057] = 330,  -- Scholomance
    [102100] = 205,  -- Maraudon
    [102557] = 330,  -- Dire Maul
}

-- Sub-areas requiring higher skill than the surrounding zone
D.ZONE_SKILL_PARTS = {
    [1434] = { skill = 300, area = "jaguero isle" },
    [1444] = { skill = 425, area = "jademir lake" },
    [1447] = { skill = 425, area = "bay of storms / scalebeard" },
}

-- Trainer milestone reminders (ordered by progression tier)
D.MILESTONES = {
    { tier = "apprentice", reqSkill = 0, reqLevel = 5, capBefore = 0, maxRank = 75, text = "learn apprentice fishing from any fishing trainer (unlocks 75 cap)." },
    { tier = "journeyman", reqSkill = 50, reqLevel = 10, capBefore = 75, maxRank = 150, text = "learn journeyman fishing from any fishing trainer at skill 50 / level 10 (unlocks 150 cap)." },
    { tier = "expert", reqSkill = 125, reqLevel = 20, capBefore = 150, maxRank = 225, text = "buy 'expert fishing - the bass and you' from old man heming in booty bay at skill 125 / level 20 (unlocks 225 cap)." },
    { tier = "artisan", reqSkill = 225, reqLevel = 35, capBefore = 225, maxRank = 300, text = "complete 'nat pagle, angler extreme' in dustwallow marsh at skill 225 / level 35 (unlocks 300 cap)." },
}

-- ─── 3. Zone Loot Tables (Wowhead Forever Empirical Drop Rates) ──────────────
-- Mapping: [mapID] = { { itemID, sharePercent, kind }, ... }
-- kind: "f" = fish, "c" = container / trunk / chest / clam, "q" = quest, "t" = trophy
D.ZONE_FISH = {
    [1411] = { { 6303, 59.7, "f" }, { 6291, 22.2, "f" }, { 6289, 15.5, "f" }, { 6356, 1.2, "c" }, { 6308, 0.6, "f" }, { 6292, 0.3, "t" }, { 6294, 0.1, "t" }, { 6643, 0.1, "c" } }, -- Durotar
    [1412] = { { 6291, 59.8, "f" }, { 6289, 38.2, "f" }, { 6292, 0.7, "t" }, { 6294, 0.4, "t" }, { 6643, 0.1, "c" }, { 6295, 0.1, "t" } }, -- Mulgore
    [1413] = { { 6522, 26.6, "f" }, { 6358, 18.3, "f" }, { 6289, 17.9, "f" }, { 6361, 8.0, "f" }, { 6308, 6.4, "f" }, { 6303, 5.5, "f" }, { 6291, 5.1, "f" }, { 20708, 4.9, "c" }, { 6359, 0.6, "f" }, { 21150, 0.4, "c" }, { 6309, 0.1, "t" }, { 6353, 0.1, "c" }, { 6351, 0.1, "c" }, { 6307, 0.1, "c" }, { 6310, 0.1, "t" } }, -- The Barrens
    [1420] = { { 6291, 45.4, "f" }, { 6289, 29.0, "f" }, { 6299, 14.8, "f" }, { 6303, 1.3, "f" }, { 8365, 1.2, "f" }, { 6308, 0.8, "f" }, { 6292, 0.6, "t" }, { 6294, 0.4, "t" }, { 6295, 0.1, "t" }, { 6643, 0.1, "c" } }, -- Tirisfal Glades
    [1421] = { { 6358, 36.4, "f" }, { 6361, 18.7, "f" }, { 6303, 12.4, "f" }, { 20708, 8.0, "c" }, { 21071, 5.4, "f" }, { 6289, 5.2, "f" }, { 6308, 1.9, "f" }, { 6291, 1.3, "f" }, { 6299, 0.9, "f" }, { 6351, 0.2, "c" }, { 6307, 0.2, "c" }, { 6353, 0.1, "c" } }, -- Silverpine Forest
    [1424] = { { 21071, 25.0, "f" }, { 6358, 16.1, "f" }, { 6308, 13.4, "f" }, { 6361, 12.3, "f" }, { 6359, 11.9, "f" }, { 6289, 7.4, "f" }, { 21113, 6.7, "c" }, { 6354, 0.1, "c" }, { 6352, 0.1, "c" }, { 6307, 0.1, "c" } }, -- Hillsbrad Foothills
    [1426] = { { 6291, 59.9, "f" }, { 6289, 38.1, "f" }, { 6292, 0.7, "t" }, { 6294, 0.4, "t" }, { 6295, 0.1, "t" }, { 6643, 0.1, "c" } }, -- Dun Morogh
    [1429] = { { 6291, 58.9, "f" }, { 6289, 37.1, "f" }, { 6292, 0.7, "t" }, { 6294, 0.4, "t" }, { 6643, 0.1, "c" }, { 6295, 0.1, "t" } }, -- Elwynn Forest
    [1431] = { { 6308, 47.2, "f" }, { 6289, 30.3, "f" }, { 13889, 5.2, "f" }, { 19975, 4.5, "q" }, { 6291, 3.4, "f" }, { 13759, 2.2, "f" }, { 13760, 2.1, "f" }, { 13890, 2.1, "f" }, { 13757, 1.2, "f" }, { 13758, 0.7, "f" }, { 6310, 0.2, "t" }, { 6309, 0.1, "t" }, { 6292, 0.1, "t" }, { 6294, 0.1, "t" } }, -- Duskwood
    [1432] = { { 6289, 30.0, "f" }, { 6317, 21.7, "f" }, { 21071, 21.4, "f" }, { 6308, 11.6, "f" }, { 6291, 8.7, "f" }, { 20708, 2.9, "c" }, { 6309, 0.1, "t" }, { 6310, 0.1, "t" } }, -- Loch Modan
    [1433] = { { 6308, 63.9, "f" }, { 6289, 35.2, "f" }, { 1467, 7.1, "q" }, { 6310, 0.2, "t" }, { 6309, 0.2, "t" }, { 6311, 0.1, "t" }, { 251524, 2.5, "f" } }, -- Redridge Mountains
    [1436] = { { 6358, 41.1, "f" }, { 6361, 20.3, "f" }, { 6303, 13.9, "f" }, { 20708, 8.4, "c" }, { 6289, 4.3, "f" }, { 6308, 1.7, "f" }, { 6291, 1.2, "f" }, { 6353, 0.2, "c" }, { 6307, 0.2, "c" }, { 6351, 0.2, "c" }, { 19975, 0.2, "q" } }, -- Westfall
    [1437] = { { 6361, 48.8, "f" }, { 6358, 24.4, "f" }, { 6359, 17.0, "f" }, { 21113, 3.0, "c" }, { 6308, 1.7, "f" }, { 6289, 1.0, "f" }, { 6352, 0.4, "c" }, { 6354, 0.4, "c" }, { 6307, 0.4, "c" } }, -- Wetlands
    [1438] = { { 6303, 56.2, "f" }, { 6291, 25.5, "f" }, { 6289, 16.2, "f" }, { 6356, 1.2, "c" }, { 6292, 0.3, "t" }, { 6294, 0.2, "t" }, { 6643, 0.1, "c" } }, -- Teldrassil
    [1439] = { { 12238, 29.6, "f" }, { 6361, 19.1, "f" }, { 6358, 16.3, "f" }, { 6303, 13.1, "f" }, { 6289, 9.9, "f" }, { 6718, 4.6, "q" }, { 6717, 4.0, "q" }, { 6308, 3.5, "f" }, { 6291, 2.8, "f" }, { 20708, 2.5, "c" }, { 6307, 0.2, "c" }, { 6353, 0.2, "c" }, { 6351, 0.2, "c" }, { 6309, 0.1, "t" } }, -- Darkshore
    [1440] = { { 6308, 39.2, "f" }, { 6289, 21.3, "f" }, { 6361, 19.3, "f" }, { 6358, 7.8, "f" }, { 21071, 5.6, "f" }, { 6359, 3.2, "f" }, { 13758, 0.8, "f" }, { 21113, 0.5, "c" }, { 13759, 0.2, "f" }, { 13760, 0.2, "f" }, { 8365, 0.2, "f" }, { 6307, 0.2, "c" }, { 6352, 0.1, "c" }, { 6354, 0.1, "c" }, { 6310, 0.1, "t" }, { 6309, 0.1, "t" }, { 6522, 0.1, "f" } }, -- Ashenvale
    [1442] = { { 6308, 48.9, "f" }, { 6289, 27.3, "f" }, { 6359, 8.7, "f" }, { 21071, 6.8, "f" }, { 21113, 3.3, "c" }, { 6458, 0.2, "f" }, { 6310, 0.2, "t" }, { 6309, 0.1, "t" } }, -- Stonetalon Mountains
    [1453] = { { 6289, 59.9, "f" }, { 6308, 21.9, "f" }, { 6291, 17.1, "f" }, { 6309, 0.3, "t" }, { 6310, 0.2, "t" } }, -- Stormwind City
    [1454] = { { 6289, 59.8, "f" }, { 6308, 22.3, "f" }, { 6291, 16.9, "f" }, { 6309, 0.3, "t" }, { 6310, 0.1, "t" } }, -- Orgrimmar
    [1455] = { { 6289, 59.4, "f" }, { 6308, 23.3, "f" }, { 6291, 16.0, "f" }, { 6309, 0.4, "t" }, { 19975, 0.3, "q" }, { 6311, 0.1, "t" } }, -- Ironforge
    [1456] = { { 6289, 60.0, "f" }, { 6308, 21.9, "f" }, { 6291, 17.0, "f" }, { 6309, 0.3, "t" }, { 6310, 0.2, "t" } }, -- Thunder Bluff
    [1457] = { { 6289, 59.9, "f" }, { 6308, 22.0, "f" }, { 6291, 17.0, "f" }, { 6309, 0.4, "t" }, { 6310, 0.1, "t" } }, -- Darnassus
    [1458] = { { 6289, 41.7, "f" }, { 6299, 15.2, "f" }, { 6308, 15.0, "f" }, { 6291, 11.7, "f" }, { 6309, 0.2, "t" }, { 6310, 0.1, "t" } }, -- Undercity
    [2521] = { { 6291, 43.0, "f" }, { 6289, 37.0, "f" }, { 6303, 17.5, "f" }, { 251524, 2.5, "f" } }, -- Zephras Isle
}

-- Higher-level zones (Level 30+) and endgame waters
D.ZONE_FISH_CLASSIC = {
    [1416] = { { 21153, 50.0, "f" }, { 8365, 23.4, "f" }, { 6308, 12.4, "f" }, { 21150, 8.4, "c" }, { 6310, 0.1, "t" }, { 6309, 0.1, "t" } }, -- Alterac Mountains
    [1417] = { { 8365, 46.2, "f" }, { 6308, 25.6, "f" }, { 6362, 8.8, "f" }, { 6359, 6.4, "f" }, { 6358, 5.3, "f" }, { 4603, 3.2, "f" }, { 21150, 2.1, "c" }, { 6289, 0.2, "f" }, { 6310, 0.1, "t" }, { 6309, 0.1, "t" }, { 6357, 0.1, "c" }, { 6311, 0.1, "t" }, { 6355, 0.1, "c" } }, -- Arathi Highlands
    [1419] = { { 6289, 33.3, "f" }, { 19975, 30.3, "q" }, { 6522, 12.1, "f" }, { 6291, 9.1, "f" }, { 6308, 9.1, "f" }, { 13760, 3.0, "f" }, { 13889, 3.0, "f" } }, -- Blasted Lands
    [1422] = { { 13758, 50.3, "f" }, { 13759, 20.0, "f" }, { 8365, 10.1, "f" }, { 6358, 10.0, "f" }, { 13760, 7.7, "f" }, { 13757, 0.9, "f" }, { 13885, 0.2, "t" }, { 13886, 0.2, "t" }, { 13882, 0.1, "t" } }, -- Western Plaguelands
    [1423] = { { 13889, 37.4, "f" }, { 13759, 19.0, "f" }, { 13890, 16.2, "f" }, { 13760, 10.9, "f" }, { 13757, 7.6, "f" }, { 13758, 6.9, "f" }, { 8365, 0.5, "f" }, { 6358, 0.5, "f" }, { 13901, 0.1, "t" }, { 13902, 0.1, "t" } }, -- Eastern Plaguelands
    [1425] = { { 13758, 24.2, "f" }, { 4603, 21.5, "f" }, { 13759, 10.0, "f" }, { 13754, 5.6, "f" }, { 6359, 5.3, "f" }, { 6362, 5.3, "f" }, { 13422, 5.1, "f" }, { 6358, 4.8, "f" }, { 8365, 4.7, "f" }, { 7973, 4.1, "c" }, { 13760, 3.2, "f" }, { 13755, 2.9, "f" }, { 13756, 2.0, "f" }, { 13757, 0.4, "f" }, { 13875, 0.2, "c" }, { 13876, 0.1, "t" }, { 13874, 0.1, "c" }, { 13885, 0.1, "t" }, { 13877, 0.1, "t" }, { 13886, 0.1, "t" } }, -- The Hinterlands
    [1428] = { { 13889, 34.6, "f" }, { 13757, 20.5, "f" }, { 13760, 17.9, "f" }, { 13759, 11.5, "f" }, { 13890, 6.4, "f" }, { 13758, 5.1, "f" } }, -- Burning Steppes
    [1430] = { { 13889, 40.1, "f" }, { 13759, 19.0, "f" }, { 13890, 16.6, "f" }, { 13760, 10.7, "f" }, { 13757, 7.8, "f" }, { 13758, 4.8, "f" }, { 13901, 0.1, "t" }, { 13902, 0.1, "t" } }, -- Deadwind Pass
    [1434] = { { 6362, 18.4, "f" }, { 6359, 17.8, "f" }, { 6358, 15.7, "f" }, { 4603, 7.3, "f" }, { 19807, 6.8, "q" }, { 21153, 5.2, "f" }, { 21228, 5.1, "c" }, { 21150, 4.9, "c" }, { 13422, 4.9, "f" }, { 8365, 2.8, "f" }, { 6308, 1.5, "f" }, { 19975, 0.6, "q" }, { 13889, 0.4, "f" }, { 16969, 0.3, "q" }, { 13759, 0.2, "f" }, { 13754, 0.2, "f" }, { 6355, 0.2, "c" }, { 13890, 0.2, "f" }, { 6357, 0.1, "c" }, { 7973, 0.1, "c" }, { 13760, 0.1, "f" }, { 13755, 0.1, "f" }, { 13757, 0.1, "f" }, { 13758, 0.1, "f" } }, -- Stranglethorn Vale
    [1435] = { { 6362, 49.0, "f" }, { 4603, 17.5, "f" }, { 6359, 10.4, "f" }, { 6358, 10.3, "f" }, { 8365, 7.5, "f" }, { 16970, 6.7, "q" }, { 6308, 4.0, "f" }, { 6357, 0.4, "c" }, { 6355, 0.4, "c" }, { 13758, 0.1, "f" } }, -- Swamp of Sorrows
    [1441] = { { 8365, 62.8, "f" }, { 6308, 35.0, "f" }, { 6289, 0.5, "f" }, { 6522, 0.4, "f" }, { 6291, 0.3, "f" }, { 6310, 0.3, "t" }, { 6309, 0.1, "t" }, { 6311, 0.1, "t" } }, -- Thousand Needles
    [1443] = { { 8365, 26.5, "f" }, { 6362, 17.5, "f" }, { 6359, 14.8, "f" }, { 6308, 14.4, "f" }, { 6358, 11.0, "f" }, { 4603, 6.4, "f" }, { 21150, 4.2, "c" }, { 16968, 2.2, "q" }, { 13758, 1.0, "f" }, { 13759, 0.3, "f" }, { 13760, 0.3, "f" }, { 6357, 0.1, "c" }, { 6355, 0.1, "c" }, { 6310, 0.1, "t" }, { 6309, 0.1, "t" } }, -- Desolace
    [1444] = { { 13758, 31.8, "f" }, { 13759, 12.1, "f" }, { 6358, 9.3, "f" }, { 4603, 9.0, "f" }, { 8365, 6.3, "f" }, { 13760, 5.7, "f" }, { 6359, 5.3, "f" }, { 13422, 5.0, "f" }, { 21228, 2.4, "c" }, { 13754, 2.2, "f" }, { 6362, 2.2, "f" }, { 7973, 1.9, "c" }, { 13755, 1.7, "f" }, { 13757, 0.9, "f" }, { 13889, 0.7, "f" }, { 13756, 0.5, "f" }, { 13890, 0.3, "f" }, { 16967, 0.3, "q" }, { 13885, 0.1, "t" }, { 13886, 0.1, "t" }, { 13875, 0.1, "c" }, { 13876, 0.1, "t" } }, -- Feralas
    [1445] = { { 6362, 27.1, "f" }, { 8365, 23.6, "f" }, { 6308, 12.9, "f" }, { 6359, 10.9, "f" }, { 4603, 10.0, "f" }, { 6358, 9.9, "f" }, { 21150, 2.7, "c" }, { 6357, 0.3, "c" }, { 6355, 0.2, "c" }, { 6310, 0.1, "t" }, { 6309, 0.1, "t" } }, -- Dustwallow Marsh
    [1446] = { { 4603, 27.4, "f" }, { 6359, 14.3, "f" }, { 13422, 13.6, "f" }, { 6358, 7.7, "f" }, { 6362, 7.0, "f" }, { 13754, 6.5, "f" }, { 21228, 6.0, "c" }, { 7973, 5.9, "c" }, { 13755, 5.3, "f" }, { 13756, 1.6, "f" }, { 13875, 0.2, "c" }, { 13876, 0.2, "t" }, { 13874, 0.1, "c" }, { 13877, 0.1, "t" } }, -- Tanaris
    [1447] = { { 13888, 26.1, "f" }, { 13755, 13.6, "f" }, { 13422, 11.8, "f" }, { 4603, 11.1, "f" }, { 7973, 7.9, "c" }, { 13893, 5.4, "f" }, { 13758, 4.1, "f" }, { 6359, 3.3, "f" }, { 13754, 2.4, "f" }, { 6362, 2.3, "f" }, { 6358, 1.7, "f" }, { 21228, 1.5, "c" }, { 13759, 1.4, "f" }, { 13756, 1.1, "f" }, { 8365, 0.8, "f" }, { 13760, 0.8, "f" }, { 13918, 0.6, "c" }, { 13874, 0.3, "c" }, { 13907, 0.1, "t" }, { 13757, 0.1, "f" }, { 13908, 0.1, "t" }, { 13875, 0.1, "c" }, { 13876, 0.1, "t" }, { 13909, 0.1, "t" } }, -- Azshara
    [1448] = { { 13758, 50.6, "f" }, { 13759, 18.7, "f" }, { 8365, 9.9, "f" }, { 6358, 9.6, "f" }, { 13760, 8.8, "f" }, { 13757, 1.4, "f" }, { 13885, 0.2, "t" }, { 13886, 0.2, "t" }, { 13882, 0.1, "t" } }, -- Felwood
    [1449] = { { 13758, 49.5, "f" }, { 13759, 21.6, "f" }, { 8365, 10.2, "f" }, { 6358, 10.0, "f" }, { 13760, 6.3, "f" }, { 13757, 0.9, "f" }, { 13885, 0.2, "t" }, { 13886, 0.1, "t" }, { 13882, 0.1, "t" } }, -- Un'Goro Crater
    [1450] = { { 13758, 50.2, "f" }, { 13759, 21.8, "f" }, { 8365, 10.0, "f" }, { 6358, 10.0, "f" }, { 13760, 6.2, "f" }, { 13757, 0.7, "f" }, { 13885, 0.2, "t" }, { 13886, 0.2, "t" }, { 13882, 0.1, "t" } }, -- Moonglade
    [1451] = { { 13889, 37.3, "f" }, { 13760, 21.9, "f" }, { 13757, 13.3, "f" }, { 13890, 11.1, "f" }, { 13759, 6.1, "f" }, { 13758, 4.1, "f" }, { 19975, 3.6, "q" }, { 6522, 0.6, "f" }, { 6289, 0.4, "f" }, { 6308, 0.3, "f" }, { 6291, 0.2, "f" }, { 13902, 0.1, "t" } }, -- Silithus
    [1452] = { { 13889, 39.4, "f" }, { 13759, 19.8, "f" }, { 13890, 17.4, "f" }, { 13760, 10.6, "f" }, { 13757, 6.8, "f" }, { 13758, 5.0, "f" }, { 13901, 0.1, "t" }, { 13902, 0.1, "t" } }, -- Winterspring
    [1459] = { { 13889, 39.4, "f" }, { 13759, 15.9, "f" }, { 13890, 15.1, "f" }, { 13760, 14.0, "f" }, { 13757, 9.5, "f" }, { 13758, 5.0, "f" }, { 13902, 0.1, "t" }, { 13901, 0.1, "t" } }, -- Alterac Valley
    [2482] = { { 13889, 42.5, "f" }, { 13759, 21.0, "f" }, { 13760, 19.5, "f" }, { 13758, 12.0, "f" }, { 13757, 3.8, "f" }, { 21150, 1.2, "c" } }, -- Mount Hyjal
    [2548] = { { 8365, 34.0, "f" }, { 4603, 22.5, "f" }, { 6308, 15.0, "f" }, { 6362, 12.0, "f" }, { 21153, 7.5, "f" }, { 6359, 4.5, "f" }, { 6358, 2.5, "f" }, { 7973, 1.2, "c" }, { 21228, 0.8, "c" } }, -- Riverglades
    [2652] = { { 13758, 32.0, "f" }, { 4603, 24.0, "f" }, { 13759, 16.0, "f" }, { 13760, 16.0, "f" }, { 13422, 7.0, "f" }, { 13754, 5.0, "f" } }, -- Shen'dralas
    [100718] = { { 6522, 45.0, "f" }, { 6291, 25.0, "f" }, { 6289, 20.0, "f" }, { 6303, 10.0, "f" } }, -- Wailing Caverns
    [100719] = { { 6308, 38.0, "f" }, { 6358, 25.0, "f" }, { 6289, 20.0, "f" }, { 6361, 17.0, "f" } }, -- Blackfathom Deeps
    [100796] = { { 6308, 42.0, "f" }, { 8365, 35.0, "f" }, { 6358, 13.0, "f" }, { 6359, 10.0, "f" } }, -- Scarlet Monastery
    [101477] = { { 8365, 38.0, "f" }, { 13758, 30.0, "f" }, { 13759, 16.0, "f" }, { 13760, 16.0, "f" } }, -- Sunken Temple
    [101977] = { { 19975, 25.0, "q" }, { 4603, 24.0, "f" }, { 13759, 16.0, "f" }, { 13760, 16.0, "f" }, { 13754, 10.0, "f" }, { 13756, 9.0, "f" } }, -- Zul'Gurub
    [102017] = { { 13758, 36.0, "f" }, { 13759, 22.0, "f" }, { 13760, 22.0, "f" }, { 13889, 15.0, "f" }, { 13757, 5.0, "f" } }, -- Stratholme
    [102057] = { { 13758, 38.0, "f" }, { 13759, 22.0, "f" }, { 13760, 22.0, "f" }, { 13889, 18.0, "f" } }, -- Scholomance
    [102100] = { { 8365, 35.0, "f" }, { 13758, 28.0, "f" }, { 13759, 15.0, "f" }, { 13760, 15.0, "f" }, { 13422, 7.0, "f" } }, -- Maraudon
    [102557] = { { 13758, 38.0, "f" }, { 13759, 22.0, "f" }, { 13760, 22.0, "f" }, { 13889, 18.0, "f" } }, -- Dire Maul
}

-- Authoritative lowercase species names (fallback before client item cache resolves)
D.SPECIES_NAMES = {
    [1467] = "spotted sunfish",
    [4603] = "raw spotted yellowtail",
    [6289] = "raw longjaw mud snapper",
    [6291] = "raw brilliant smallfish",
    [6292] = "10 pound mud snapper",
    [6294] = "12 pound mud snapper",
    [6295] = "15 pound mud snapper",
    [6299] = "sickly looking fish",
    [6303] = "raw slitherskin mackerel",
    [6307] = "message in a bottle",
    [6308] = "raw bristle whisker catfish",
    [6309] = "17 pound catfish",
    [6310] = "19 pound catfish",
    [6311] = "22 pound catfish",
    [6317] = "raw loch frenzy",
    [6351] = "dented crate",
    [6352] = "waterlogged crate",
    [6353] = "small chest",
    [6354] = "small locked chest",
    [6355] = "sturdy locked chest",
    [6356] = "battered chest",
    [6357] = "sealed crate",
    [6358] = "oily blackmouth",
    [6359] = "firefin snapper",
    [6361] = "raw rainbow fin albacore",
    [6362] = "raw rockscale cod",
    [6458] = "oil covered fish",
    [6522] = "deviate fish",
    [6643] = "bloated brilliant smallfish",
    [6717] = "gaffer jack",
    [6718] = "electropeller",
    [7973] = "big-mouth clam",
    [8365] = "raw mithril head trout",
    [8366] = "bloated mithril head trout",
    [12238] = "darkshore grouper",
    [13422] = "stonescale eel",
    [13754] = "raw glossy mightfish",
    [13755] = "raw winter squid",
    [13756] = "raw summer bass",
    [13757] = "lightning eel",
    [13758] = "raw redgill",
    [13759] = "raw nightfin snapper",
    [13760] = "raw sunscale salmon",
    [13874] = "heavy crate",
    [13875] = "ironbound locked chest",
    [13876] = "40 pound yellowtail",
    [13877] = "47 pound yellowtail",
    [13882] = "42 pound redgill",
    [13885] = "34 pound redgill",
    [13886] = "37 pound redgill",
    [13888] = "darkclaw lobster",
    [13889] = "raw whitescale salmon",
    [13890] = "raw plated armorfish",
    [13893] = "large raw mightfish",
    [13901] = "15 pound salmon",
    [13902] = "18 pound salmon",
    [13907] = "7 pound lobster",
    [13908] = "9 pound lobster",
    [13909] = "12 pound lobster",
    [13918] = "reinforced locked chest",
    [16967] = "feralas ahi",
    [16968] = "sar'theris striker",
    [16969] = "savage coast blue sailfin",
    [16970] = "misty reed mahi mahi",
    [19807] = "speckled tastyfish",
    [19975] = "zulian mudskunk",
    [20708] = "tightly sealed trunk",
    [21071] = "raw sagefish",
    [21113] = "watertight trunk",
    [21150] = "iron bound trunk",
    [21153] = "raw greater sagefish",
    [21228] = "mithril bound trunk",
    [21243] = "bloated glossy mightfish",
    [251524] = "whimsyfin",
}

-- Water habitat classification per species ('coastal' = ocean, 'inland' = lake/river, 'oasis' = Barrens oasis)
D.SPECIES_HABITAT = {
    [1467] = "inland",
    [4603] = "coastal",
    [6289] = "inland",
    [6291] = "inland",
    [6292] = "inland",
    [6294] = "inland",
    [6295] = "inland",
    [6299] = "inland",
    [6303] = "coastal",
    [6308] = "inland",
    [6309] = "inland",
    [6310] = "inland",
    [6311] = "inland",
    [6317] = "inland",
    [6358] = "coastal",
    [6359] = "coastal",
    [6361] = "coastal",
    [6362] = "coastal",
    [6458] = "inland",
    [6522] = "oasis",
    [6643] = "inland",
    [6717] = "inland",
    [6718] = "inland",
    [7973] = "coastal",
    [8365] = "inland",
    [12238] = "coastal",
    [13422] = "coastal",
    [13754] = "coastal",
    [13755] = "coastal",
    [13756] = "coastal",
    [13757] = "inland",
    [13758] = "inland",
    [13759] = "inland",
    [13760] = "inland",
    [13876] = "coastal",
    [13877] = "coastal",
    [13882] = "inland",
    [13885] = "inland",
    [13886] = "inland",
    [13888] = "coastal",
    [13889] = "inland",
    [13890] = "inland",
    [13893] = "coastal",
    [13901] = "inland",
    [13902] = "inland",
    [13907] = "coastal",
    [13908] = "coastal",
    [13909] = "coastal",
    [16967] = "inland",
    [16968] = "coastal",
    [16969] = "coastal",
    [16970] = "coastal",
    [19807] = "coastal",
    [19975] = "inland",
    [21071] = "inland",
    [21153] = "inland",
    [251524] = "inland",
}

-- Zones containing both coastal (ocean) and inland (lake/river/oasis) waters
D.MIXED_ZONES = {
    [1411] = true, -- Durotar
    [1413] = true, -- The Barrens
    [1417] = true, -- Arathi Highlands
    [1421] = true, -- Silverpine Forest
    [1424] = true, -- Hillsbrad Foothills
    [1425] = true, -- The Hinterlands
    [1434] = true, -- Stranglethorn Vale
    [1435] = true, -- Swamp of Sorrows
    [1436] = true, -- Westfall
    [1437] = true, -- Wetlands
    [1438] = true, -- Teldrassil
    [1439] = true, -- Darkshore
    [1440] = true, -- Ashenvale
    [1443] = true, -- Desolace
    [1444] = true, -- Feralas
    [1445] = true, -- Dustwallow Marsh
    [1447] = true, -- Azshara
    [2521] = true, -- Zephras Isle
    [2548] = true, -- Riverglades
}

-- Authoritative lowercase zone names (fallback when C_Map.GetMapInfo is unavailable)
D.ZONE_NAMES = {
    [1411] = "durotar",
    [1412] = "mulgore",
    [1413] = "the barrens",
    [1416] = "alterac mountains",
    [1417] = "arathi highlands",
    [1418] = "badlands",
    [1419] = "blasted lands",
    [1420] = "tirisfal glades",
    [1421] = "silverpine forest",
    [1422] = "western plaguelands",
    [1423] = "eastern plaguelands",
    [1424] = "hillsbrad foothills",
    [1425] = "the hinterlands",
    [1426] = "dun morogh",
    [1427] = "searing gorge",
    [1428] = "burning steppes",
    [1429] = "elwynn forest",
    [1430] = "deadwind pass",
    [1431] = "duskwood",
    [1432] = "loch modan",
    [1433] = "redridge mountains",
    [1434] = "stranglethorn vale",
    [1435] = "swamp of sorrows",
    [1436] = "westfall",
    [1437] = "wetlands",
    [1438] = "teldrassil",
    [1439] = "darkshore",
    [1440] = "ashenvale",
    [1441] = "thousand needles",
    [1442] = "stonetalon mountains",
    [1443] = "desolace",
    [1444] = "feralas",
    [1445] = "dustwallow marsh",
    [1446] = "tanaris",
    [1447] = "azshara",
    [1448] = "felwood",
    [1449] = "un'goro crater",
    [1450] = "moonglade",
    [1451] = "silithus",
    [1452] = "winterspring",
    [1453] = "stormwind city",
    [1454] = "orgrimmar",
    [1455] = "ironforge",
    [1456] = "thunder bluff",
    [1457] = "darnassus",
    [1458] = "undercity",
    [1459] = "alterac valley",
    [2482] = "mount hyjal",
    [2521] = "zephras isle",
    [2548] = "riverglades",
    [2652] = "shen'dralas",
    [100209] = "shadowfang keep",
    [100491] = "razorfen kraul",
    [100717] = "the stockade",
    [100718] = "wailing caverns",
    [100719] = "blackfathom deeps",
    [100721] = "gnomeregan",
    [100722] = "razorfen downs",
    [100796] = "scarlet monastery",
    [101176] = "zul'farrak",
    [101337] = "uldaman",
    [101477] = "sunken temple",
    [101581] = "the deadmines",
    [101583] = "blackrock spire",
    [101584] = "blackrock depths",
    [101977] = "zul'gurub",
    [102017] = "stratholme",
    [102057] = "scholomance",
    [102100] = "maraudon",
    [102437] = "ragefire chasm",
    [102557] = "dire maul",
    [102677] = "blackwing lair",
    [102717] = "molten core",
    [103428] = "temple of ahn'qiraj",
    [103429] = "ruins of ahn'qiraj",
    [103456] = "naxxramas",
    [116544] = "city of dalaran",
    [116550] = "the drowned city",
    [116554] = "blackmaw hold",
    [116611] = "ruins of lordaeron",
    [116620] = "alcaz prison",
    [116732] = "excavation site: wetlands",
    [116842] = "krol'dok stronghold",
    [116919] = "hall of thanes",
}

-- Reverse lookup from lowercase zone/dungeon name to numeric mapID (for instance & custom zone resolution)
D.ZONE_NAME_TO_ID = {
    ["alcaz prison"] = 116620,
    ["alterac mountains"] = 1416,
    ["alterac valley"] = 1459,
    ["arathi highlands"] = 1417,
    ["ashenvale"] = 1440,
    ["azshara"] = 1447,
    ["badlands"] = 1418,
    ["barrens"] = 1413,
    ["blackfathom deeps"] = 100719,
    ["blackmaw hold"] = 116554,
    ["blackrock depths"] = 101584,
    ["blackrock spire"] = 101583,
    ["blackwing lair"] = 102677,
    ["blasted lands"] = 1419,
    ["burning steppes"] = 1428,
    ["city of dalaran"] = 116544,
    ["darkshore"] = 1439,
    ["darnassus"] = 1457,
    ["deadmines"] = 101581,
    ["deadwind pass"] = 1430,
    ["desolace"] = 1443,
    ["dire maul"] = 102557,
    ["drowned city"] = 116550,
    ["dun morogh"] = 1426,
    ["durotar"] = 1411,
    ["duskwood"] = 1431,
    ["dustwallow marsh"] = 1445,
    ["eastern plaguelands"] = 1423,
    ["elwynn forest"] = 1429,
    ["excavation site: wetlands"] = 116732,
    ["felwood"] = 1448,
    ["feralas"] = 1444,
    ["gnomeregan"] = 100721,
    ["hall of thanes"] = 116919,
    ["hillsbrad foothills"] = 1424,
    ["hinterlands"] = 1425,
    ["ironforge"] = 1455,
    ["krol'dok stronghold"] = 116842,
    ["loch modan"] = 1432,
    ["maraudon"] = 102100,
    ["molten core"] = 102717,
    ["moonglade"] = 1450,
    ["mount hyjal"] = 2482,
    ["mulgore"] = 1412,
    ["naxxramas"] = 103456,
    ["orgrimmar"] = 1454,
    ["ragefire chasm"] = 102437,
    ["razorfen downs"] = 100722,
    ["razorfen kraul"] = 100491,
    ["redridge mountains"] = 1433,
    ["riverglades"] = 2548,
    ["ruins of ahn'qiraj"] = 103429,
    ["ruins of lordaeron"] = 116611,
    ["scarlet monastery"] = 100796,
    ["scholomance"] = 102057,
    ["searing gorge"] = 1427,
    ["shadowfang keep"] = 100209,
    ["shen'dralas"] = 2652,
    ["silithus"] = 1451,
    ["silverpine forest"] = 1421,
    ["stockade"] = 100717,
    ["stonetalon mountains"] = 1442,
    ["stormwind city"] = 1453,
    ["stranglethorn vale"] = 1434,
    ["stratholme"] = 102017,
    ["sunken temple"] = 101477,
    ["swamp of sorrows"] = 1435,
    ["tanaris"] = 1446,
    ["teldrassil"] = 1438,
    ["temple of ahn'qiraj"] = 103428,
    ["temple of atal'hakkar"] = 101477,
    ["the alcaz prison"] = 116620,
    ["the alterac mountains"] = 1416,
    ["the alterac valley"] = 1459,
    ["the arathi highlands"] = 1417,
    ["the ashenvale"] = 1440,
    ["the azshara"] = 1447,
    ["the badlands"] = 1418,
    ["the barrens"] = 1413,
    ["the blackfathom deeps"] = 100719,
    ["the blackmaw hold"] = 116554,
    ["the blackrock depths"] = 101584,
    ["the blackrock spire"] = 101583,
    ["the blackwing lair"] = 102677,
    ["the blasted lands"] = 1419,
    ["the burning steppes"] = 1428,
    ["the city of dalaran"] = 116544,
    ["the darkshore"] = 1439,
    ["the darnassus"] = 1457,
    ["the deadmines"] = 101581,
    ["the deadwind pass"] = 1430,
    ["the desolace"] = 1443,
    ["the dire maul"] = 102557,
    ["the drowned city"] = 116550,
    ["the dun morogh"] = 1426,
    ["the durotar"] = 1411,
    ["the duskwood"] = 1431,
    ["the dustwallow marsh"] = 1445,
    ["the eastern plaguelands"] = 1423,
    ["the elwynn forest"] = 1429,
    ["the excavation site: wetlands"] = 116732,
    ["the felwood"] = 1448,
    ["the feralas"] = 1444,
    ["the gnomeregan"] = 100721,
    ["the hall of thanes"] = 116919,
    ["the hillsbrad foothills"] = 1424,
    ["the hinterlands"] = 1425,
    ["the ironforge"] = 1455,
    ["the krol'dok stronghold"] = 116842,
    ["the loch modan"] = 1432,
    ["the maraudon"] = 102100,
    ["the molten core"] = 102717,
    ["the moonglade"] = 1450,
    ["the mount hyjal"] = 2482,
    ["the mulgore"] = 1412,
    ["the naxxramas"] = 103456,
    ["the orgrimmar"] = 1454,
    ["the ragefire chasm"] = 102437,
    ["the razorfen downs"] = 100722,
    ["the razorfen kraul"] = 100491,
    ["the redridge mountains"] = 1433,
    ["the riverglades"] = 2548,
    ["the ruins of ahn'qiraj"] = 103429,
    ["the ruins of lordaeron"] = 116611,
    ["the scarlet monastery"] = 100796,
    ["the scholomance"] = 102057,
    ["the searing gorge"] = 1427,
    ["the shadowfang keep"] = 100209,
    ["the shen'dralas"] = 2652,
    ["the silithus"] = 1451,
    ["the silverpine forest"] = 1421,
    ["the stockade"] = 100717,
    ["the stonetalon mountains"] = 1442,
    ["the stormwind city"] = 1453,
    ["the stranglethorn vale"] = 1434,
    ["the stratholme"] = 102017,
    ["the sunken temple"] = 101477,
    ["the swamp of sorrows"] = 1435,
    ["the tanaris"] = 1446,
    ["the teldrassil"] = 1438,
    ["the temple of ahn'qiraj"] = 103428,
    ["the temple of atal'hakkar"] = 101477,
    ["the thousand needles"] = 1441,
    ["the thunder bluff"] = 1456,
    ["the tirisfal glades"] = 1420,
    ["the uldaman"] = 101337,
    ["the un'goro crater"] = 1449,
    ["the undercity"] = 1458,
    ["the wailing caverns"] = 100718,
    ["the western plaguelands"] = 1422,
    ["the westfall"] = 1436,
    ["the wetlands"] = 1437,
    ["the winterspring"] = 1452,
    ["the zephras isle"] = 2521,
    ["the zul'farrak"] = 101176,
    ["the zul'gurub"] = 101977,
    ["thousand needles"] = 1441,
    ["thunder bluff"] = 1456,
    ["tirisfal glades"] = 1420,
    ["uldaman"] = 101337,
    ["un'goro crater"] = 1449,
    ["undercity"] = 1458,
    ["wailing caverns"] = 100718,
    ["western plaguelands"] = 1422,
    ["westfall"] = 1436,
    ["wetlands"] = 1437,
    ["winterspring"] = 1452,
    ["zephras isle"] = 2521,
    ["zul'farrak"] = 101176,
    ["zul'gurub"] = 101977,
}

-- Authoritative continent classification per zone ('eastern_kingdoms' vs 'kalimdor')
D.ZONE_CONTINENT = {
    [1411] = "kalimdor",
    [1412] = "kalimdor",
    [1413] = "kalimdor",
    [1416] = "eastern_kingdoms",
    [1417] = "eastern_kingdoms",
    [1418] = "eastern_kingdoms",
    [1419] = "eastern_kingdoms",
    [1420] = "eastern_kingdoms",
    [1421] = "eastern_kingdoms",
    [1422] = "eastern_kingdoms",
    [1423] = "eastern_kingdoms",
    [1424] = "eastern_kingdoms",
    [1425] = "eastern_kingdoms",
    [1426] = "eastern_kingdoms",
    [1427] = "eastern_kingdoms",
    [1428] = "eastern_kingdoms",
    [1429] = "eastern_kingdoms",
    [1430] = "eastern_kingdoms",
    [1431] = "eastern_kingdoms",
    [1432] = "eastern_kingdoms",
    [1433] = "eastern_kingdoms",
    [1434] = "eastern_kingdoms",
    [1435] = "eastern_kingdoms",
    [1436] = "eastern_kingdoms",
    [1437] = "eastern_kingdoms",
    [1438] = "kalimdor",
    [1439] = "kalimdor",
    [1440] = "kalimdor",
    [1441] = "kalimdor",
    [1442] = "kalimdor",
    [1443] = "kalimdor",
    [1444] = "kalimdor",
    [1445] = "kalimdor",
    [1446] = "kalimdor",
    [1447] = "kalimdor",
    [1448] = "kalimdor",
    [1449] = "kalimdor",
    [1450] = "kalimdor",
    [1451] = "kalimdor",
    [1452] = "kalimdor",
    [1453] = "eastern_kingdoms",
    [1454] = "kalimdor",
    [1455] = "eastern_kingdoms",
    [1456] = "kalimdor",
    [1457] = "kalimdor",
    [1458] = "eastern_kingdoms",
    [1459] = "eastern_kingdoms",
    [2482] = "kalimdor",
    [2521] = "kalimdor",
    [2548] = "eastern_kingdoms",
    [2652] = "kalimdor",
    [100209] = "eastern_kingdoms",
    [100491] = "kalimdor",
    [100717] = "eastern_kingdoms",
    [100718] = "kalimdor",
    [100719] = "kalimdor",
    [100721] = "eastern_kingdoms",
    [100722] = "kalimdor",
    [100796] = "eastern_kingdoms",
    [101176] = "kalimdor",
    [101337] = "eastern_kingdoms",
    [101477] = "eastern_kingdoms",
    [101581] = "eastern_kingdoms",
    [101583] = "eastern_kingdoms",
    [101584] = "eastern_kingdoms",
    [101977] = "eastern_kingdoms",
    [102017] = "eastern_kingdoms",
    [102057] = "eastern_kingdoms",
    [102100] = "kalimdor",
    [102437] = "kalimdor",
    [102557] = "kalimdor",
    [102677] = "eastern_kingdoms",
    [102717] = "eastern_kingdoms",
    [103428] = "kalimdor",
    [103429] = "kalimdor",
    [103456] = "eastern_kingdoms",
    [116544] = "eastern_kingdoms",
    [116550] = "kalimdor",
    [116554] = "kalimdor",
    [116611] = "eastern_kingdoms",
    [116620] = "kalimdor",
    [116732] = "eastern_kingdoms",
    [116842] = "eastern_kingdoms",
    [116919] = "eastern_kingdoms",
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
                        name = D.SPECIES_NAMES[itemID],
                        habitat = D.SPECIES_HABITAT[itemID],
                        kind = kind,
                        isContainer = (kind == "c"),
                        zones = {},
                        minSkill = 9999,
                        minSkillAny = 9999,
                    }
                    speciesCatalog[itemID] = item
                end

                local reqSkill = D.ZONE_SKILL[mapID] or 0
                if reqSkill > 0 then
                    if reqSkill < item.minSkillAny then
                        item.minSkillAny = reqSkill
                    end
                    if (share or 0) >= 1.5 and reqSkill < item.minSkill then
                        item.minSkill = reqSkill
                    end
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

    -- Merge any newly caught in-game species from SfuiDB.fishing.species not yet in static tables
    local savedSpecies = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.species
    if type(savedSpecies) == "table" then
        for itemID, sData in pairs(savedSpecies) do
            local id = tonumber(itemID)
            if id and not speciesCatalog[id] and type(sData) == "table" and (sData.n or 0) > 0 then
                local zID = sData.lz or sData.fz
                local zReq = (zID and D.ZONE_SKILL[zID]) or 0
                speciesCatalog[id] = {
                    itemID = id,
                    kind = "f",
                    isContainer = false,
                    habitat = D.SPECIES_HABITAT[id],
                    minSkill = zReq,
                    zones = zID and { { mapID = zID, share = 0, reqSkill = zReq, isClassicOnly = false } } or {},
                }
            end
        end
    end

    -- Sort zones per fish by highest drop percentage
    for _, item in pairs(speciesCatalog) do
        if item.minSkill == 9999 then item.minSkill = item.minSkillAny end
        if item.minSkill == 9999 then item.minSkill = 0 end
        item.minSkillAny = nil
        table_sort(item.zones, function(a, b)
            return (a.share or 0) > (b.share or 0)
        end)
    end

    return speciesCatalog
end

function D.InvalidateSpeciesCatalog()
    speciesCatalog = nil
end

-- ─── 5. Public Query API ─────────────────────────────────────────────────────

--- Returns the fallback lowercase name for a species itemID
--- @param itemID number
--- @return string|nil
function D.GetSpeciesName(itemID)
    return itemID and D.SPECIES_NAMES[itemID] or nil
end

--- Resolves lowercase display text (colored link or plain name) and icon texture for a species
--- @param itemID number
--- @param preferLink boolean|nil
--- @return string displayText, string|number|nil texture, string|nil itemName, string|nil itemLink, number|nil quality
function D.GetSpeciesDisplay(itemID, preferLink)
    local common = sfui.common
    local name, link, quality, _, _, _, _, _, _, texture
    if common and common.get_item_info then
        name, link, quality, _, _, _, _, _, _, texture = common.get_item_info(itemID)
    end
    local lowerLink = (preferLink ~= false and link) and link:gsub("%b[]", string.lower) or nil
    local lowerName = (name and name:lower()) or (itemID and D.SPECIES_NAMES[itemID]) or ("item:" .. tostring(itemID or 0))
    return (lowerLink or lowerName), texture, lowerName, lowerLink, quality
end

--- Returns the lowercase name for a zone mapID
--- @param mapID number
--- @return string|nil
function D.GetZoneName(mapID)
    if not mapID then return nil end
    if D.ZONE_NAMES[mapID] then return D.ZONE_NAMES[mapID] end
    local savedZ = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.zones and _G.SfuiDB.fishing.zones[mapID]
    if type(savedZ) == "table" and type(savedZ.name) == "string" and savedZ.name ~= "" then return savedZ.name:lower() end
    local name = sfui.common and sfui.common.get_map_name and sfui.common.get_map_name(mapID)
    return name and name:lower() or nil
end

--- Resolves a zone or dungeon name (e.g. from GetRealZoneText inside an instance) to a numeric mapID
--- @param zoneText string|nil
--- @return number
function D.ResolveZoneNameID(zoneText)
    if type(zoneText) ~= "string" or zoneText == "" then return 0 end
    local low = zoneText:lower()
    if D.ZONE_NAME_TO_ID[low] then return D.ZONE_NAME_TO_ID[low] end
    local stripped = low:gsub("^the%s+", "")
    if D.ZONE_NAME_TO_ID[stripped] then return D.ZONE_NAME_TO_ID[stripped] end
    local h = 0
    for i = 1, #low do
        h = (h * 31 + low:byte(i)) % 89999
    end
    local dynID = 200000 + h
    D.ZONE_NAMES[dynID] = low
    D.ZONE_NAME_TO_ID[low] = dynID
    return dynID
end

--- Returns the continent key ('eastern_kingdoms' | 'kalimdor') and display label for a zone mapID
--- @param mapID number
--- @return string continentKey, string continentLabel
function D.GetZoneContinent(mapID)
    local key = mapID and D.ZONE_CONTINENT[mapID]
    if not key and mapID and sfui.common and sfui.common.get_map_info then
        local info = sfui.common.get_map_info(mapID)
        local parentID = info and info.parentMapID
        if parentID == 1414 then key = "kalimdor"
        elseif parentID == 1415 then key = "eastern_kingdoms"
        end
    end
    key = key or "eastern_kingdoms"
    return key, (key == "kalimdor") and "kalimdor" or "eastern kingdoms"
end

--- Evaluates a milestone tier against the player's current rank, maxRank, and level
--- @param m table
--- @param rank number
--- @param maxRank number
--- @param playerLevel number|nil
--- @return string state ('learned' | 'capped' | 'available' | 'level_locked' | 'locked')
function D.GetMilestoneStatus(m, rank, maxRank, playerLevel)
    rank = rank or 0
    maxRank = maxRank or 0
    if maxRank >= (m.maxRank or 0) then
        return "learned"
    end
    if (m.capBefore or 0) > 0 and rank >= m.capBefore then
        return "capped"
    end
    if rank >= (m.reqSkill or 0) then
        if playerLevel and m.reqLevel and playerLevel < m.reqLevel then
            return "level_locked"
        end
        return "available"
    end
    return "locked"
end

--- Returns the next actionable trainer milestone (if currently capped or available)
--- @param rank number
--- @param maxRank number
--- @param playerLevel number|nil
--- @return table|nil milestone, string|nil state
function D.GetActiveMilestone(rank, maxRank, playerLevel)
    for _, m in ipairs(D.MILESTONES) do
        local st = D.GetMilestoneStatus(m, rank, maxRank, playerLevel)
        if st == "capped" or st == "available" or st == "level_locked" then
            return m, st
        end
    end
    return nil, nil
end

--- Returns the required fishing skill for a given mapID
--- @param mapID number
--- @return number requiredSkill, table|nil subAreaHint
function D.GetZoneRequirement(mapID)
    if not mapID or mapID <= 0 then return nil end
    local req = D.ZONE_SKILL[mapID]
    local sub = D.ZONE_SKILL_PARTS[mapID]
    return req, sub
end

--- Returns water habitat ('coastal' | 'inland' | 'oasis' | nil) and formatted badge for a species
--- @param itemID number
--- @param mapID number|nil
--- @return string|nil habitat, string|nil badge
function D.GetSpeciesHabitat(itemID, mapID)
    local hab = itemID and D.SPECIES_HABITAT[itemID]
    if not hab then return nil, nil end
    if mapID and not D.MIXED_ZONES[mapID] and hab ~= "oasis" then
        return hab, nil
    end
    if hab == "coastal" then
        return hab, "|cff44bbff[coast]|r"
    elseif hab == "oasis" then
        return hab, "|cffffcc44[oasis]|r"
    elseif hab == "inland" then
        return hab, "|cff66dd88[inland]|r"
    end
    return hab, nil
end

local COASTAL_KEYWORDS = {
    "coast", "strand", "shore", "beach", "bay", "cove", "harbor", "port", "dock",
    "anchorage", "isle", "island", "reef", "ratchet", "northwatch", "southshore",
    "menethil", "auberdine", "zoram", "booty bay", "theramore", "feathermoon",
    "sar'theris", "shadowprey", "revantusk", "faldir", "rut'theran", "longshore",
    "lighthouse", "sen'jin", "tiragarde", "sardor", "alcaz", "steamwheedle",
    "powderfuse", "valanaar",
}

local INLAND_KEYWORDS = {
    "lake", "river", "loch", "pond", "falls", "stream", "creek", "marsh",
    "mystral", "falfarren", "iris", "nazferiti", "verdantis", "mennar",
    "lordamere", "darrowmere", "tarren mill", "valorwind", "kurzen", "southfury",
    "meadowsbrook", "turner", "shen'dar", "nordrassil",
}

--- Resolves live sub-zone skill requirement and active water habitat ('coastal' | 'inland' | 'oasis')
--- @param mapID number
--- @param subZoneText string|nil
--- @return number|nil reqSkill, table|nil subAreaHint, string|nil activeHabitat, string|nil matchedSubArea, boolean isMixed
function D.ResolveSubZone(mapID, subZoneText)
    if not mapID or mapID <= 0 then return nil, nil, nil, nil, false end
    local req = D.ZONE_SKILL[mapID]
    local sub = D.ZONE_SKILL_PARTS[mapID]
    local isMixed = D.MIXED_ZONES[mapID] == true
    local sz = (type(subZoneText) == "string" and subZoneText ~= "") and subZoneText:lower() or nil
    if not sz then
        return req, sub, nil, nil, isMixed
    end

    -- 1. Check high-skill sub-area overrides
    if mapID == 1434 and sz:find("jaguero", 1, true) then
        return 300, sub, "coastal", "jaguero isle", isMixed
    elseif mapID == 1444 and sz:find("jademir", 1, true) then
        return 425, sub, "inland", "jademir lake", isMixed
    elseif mapID == 1447 and (sz:find("bay of storms", 1, true) or sz:find("scalebeard", 1, true) or sz:find("hetaera", 1, true) or sz:find("jagged reef", 1, true)) then
        return 425, sub, "coastal", sz, isMixed
    end

    -- 2. Check Barrens Oases
    if mapID == 1413 and (sz:find("oasis", 1, true) or sz:find("forgotten pools", 1, true) or sz:find("lushwater", 1, true) or sz:find("stagnant", 1, true) or sz:find("wailing caverns", 1, true)) then
        return req, sub, "oasis", sz, isMixed
    end

    -- 3. Check Coastal vs Inland water keywords in mixed zones
    if isMixed then
        for _, kw in ipairs(COASTAL_KEYWORDS) do
            if sz:find(kw, 1, true) then
                return req, sub, "coastal", sz, isMixed
            end
        end
        for _, kw in ipairs(INLAND_KEYWORDS) do
            if sz:find(kw, 1, true) then
                return req, sub, "inland", sz, isMixed
            end
        end
    end

    return req, sub, nil, nil, isMixed
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

--- Returns all known fishing zones with their requirement and continent
--- @return table array of { mapID, reqSkill, continent, sub }
function D.GetAllWaters()
    local waters = {}
    local seen = {}
    for mapID, req in pairs(D.ZONE_SKILL) do
        seen[mapID] = true
        local contKey = D.GetZoneContinent(mapID)
        waters[#waters + 1] = {
            mapID = mapID,
            reqSkill = req,
            continent = contKey,
            sub = D.ZONE_SKILL_PARTS[mapID],
        }
    end
    local savedZones = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.zones
    if type(savedZones) == "table" then
        for mKey, zData in pairs(savedZones) do
            local mID = tonumber(mKey)
            if mID and mID > 0 and not seen[mID] and type(zData) == "table" and (zData.catches or 0) > 0 then
                seen[mID] = true
                waters[#waters + 1] = {
                    mapID = mID,
                    reqSkill = 225,
                    continent = D.GetZoneContinent(mID),
                }
            end
        end
    end
    table_sort(waters, function(a, b)
        if a.reqSkill ~= b.reqSkill then
            return a.reqSkill < b.reqSkill
        end
        return a.mapID < b.mapID
    end)
    return waters
end

-- ─── Lure Detection & Memoized Bag Cache ─────────────────────────────────────
local cachedLure = nil
local cachedLureRank = nil
local lureCacheDirty = true

function D.InvalidateLureCache()
    lureCacheDirty = true
end

--- Returns best bag lure that the player can use given their current skill rank
--- @param skillRank number
--- @return table|nil { itemID, bonus, bag, slot, link, count }
function D.FindBestLureInBags(skillRank)
    skillRank = skillRank or 0
    if not lureCacheDirty and cachedLureRank == skillRank then
        return cachedLure
    end

    local common = sfui.common
    if not common or not common.for_each_bag_item then return nil end

    local bestItemID, bestName, bestBonus, bestSkill, bestBag, bestSlot, bestLink, bestCount = nil, nil, -1, 0, nil, nil, nil, 0
    local C_Container = _G.C_Container

    common.for_each_bag_item(function(bag, slot, itemID, itemLink)
        if itemID and D.LURE_ITEM_IDS[itemID] then
            local lureDef = D.LURE_ITEM_IDS[itemID]
            if skillRank >= lureDef.skill then
                if lureDef.bonus > bestBonus then
                    local count = 1
                    if C_Container and C_Container.GetContainerItemInfo then
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        if info and info.stackCount then count = info.stackCount end
                    elseif _G.GetContainerItemInfo then
                        local _, c = _G.GetContainerItemInfo(bag, slot)
                        if c and c > 0 then count = c end
                    end
                    bestItemID = itemID
                    bestName = lureDef.name
                    bestBonus = lureDef.bonus
                    bestSkill = lureDef.skill
                    bestBag = bag
                    bestSlot = slot
                    bestLink = itemLink
                    bestCount = count
                end
            end
        end
    end, false, true, false)

    if bestItemID then
        if not cachedLure then cachedLure = {} end
        cachedLure.itemID = bestItemID
        cachedLure.name = bestName
        cachedLure.bonus = bestBonus
        cachedLure.skill = bestSkill
        cachedLure.bag = bestBag
        cachedLure.slot = bestSlot
        cachedLure.link = bestLink
        cachedLure.count = bestCount
    else
        cachedLure = nil
    end

    cachedLureRank = skillRank
    lureCacheDirty = false
    return cachedLure
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", D.InvalidateLureCache)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", D.InvalidateLureCache)
    sfui.events.RegisterEvent("SKILL_LINES_CHANGED", D.InvalidateLureCache)
end
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", function(_, itemID)
        if itemID and speciesCatalog and not speciesCatalog[itemID] then
            speciesCatalog = nil
        end
    end)
end

