local addonName, addon = ...
sfui = sfui or {}
sfui.zonelevels = sfui.zonelevels or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/zonelevels.lua
--  World Map Zone Level Ranges & Fishing Skill Requirements (Camelot / Classic)
--
--  Hooks the WorldMapFrame area label's SetText via hooksecurefunc (zero OnUpdate,
--  zero Blizzard frame mutations) to render zone level ranges on continent maps
--  and zone/sub-zone fishing skill thresholds on both continent and zone maps.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G                     = _G
local CreateFrame            = _G.CreateFrame
local C_Map                  = _G.C_Map
local C_AddOns               = _G.C_AddOns
local C_Spell                = _G.C_Spell
local Enum                   = _G.Enum
local UnitLevel              = _G.UnitLevel
local GetQuestDifficultyColor = _G.GetQuestDifficultyColor
local hooksecurefunc         = _G.hooksecurefunc
local pairs                  = _G.pairs
local math_floor             = _G.math.floor
local math_max               = _G.math.max
local string_format          = _G.string.format
local string_lower           = _G.string.lower

local issecretvalue = sfui.common.issecretvalue
    or (sfui.safety and sfui.safety.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local NO_GETAWAY    = 95
local FISHING_SPELL = 7620

-- uiMapID -> { minLevel, maxLevel }
local LEVELS = {
    -- Eastern Kingdoms
    [1426] = { 1, 10 },   -- Dun Morogh
    [1429] = { 1, 10 },   -- Elwynn Forest
    [1420] = { 1, 10 },   -- Tirisfal Glades
    [1432] = { 10, 20 },  -- Loch Modan
    [1436] = { 10, 20 },  -- Westfall
    [1421] = { 10, 20 },  -- Silverpine Forest
    [1433] = { 15, 25 },  -- Redridge Mountains
    [1431] = { 18, 30 },  -- Duskwood
    [1437] = { 20, 30 },  -- Wetlands
    [1424] = { 20, 30 },  -- Hillsbrad Foothills
    [1416] = { 30, 40 },  -- Alterac Mountains
    [1417] = { 30, 40 },  -- Arathi Highlands
    [1434] = { 30, 45 },  -- Stranglethorn Vale
    [1418] = { 35, 45 },  -- Badlands
    [1435] = { 35, 45 },  -- Swamp of Sorrows
    [1425] = { 40, 50 },  -- The Hinterlands
    [1427] = { 43, 50 },  -- Searing Gorge
    [1419] = { 45, 55 },  -- Blasted Lands
    [1428] = { 50, 58 },  -- Burning Steppes
    [1422] = { 51, 58 },  -- Western Plaguelands
    [1423] = { 53, 60 },  -- Eastern Plaguelands
    [1430] = { 55, 60 },  -- Deadwind Pass
    [2548] = { 35, 45 },  -- Riverglades (Forever)
    -- Kalimdor
    [1411] = { 1, 10 },   -- Durotar
    [1412] = { 1, 10 },   -- Mulgore
    [1438] = { 1, 10 },   -- Teldrassil
    [1439] = { 10, 20 },  -- Darkshore
    [1413] = { 10, 25 },  -- The Barrens
    [1442] = { 15, 27 },  -- Stonetalon Mountains
    [1440] = { 18, 30 },  -- Ashenvale
    [1441] = { 25, 35 },  -- Thousand Needles
    [1443] = { 30, 40 },  -- Desolace
    [1445] = { 35, 45 },  -- Dustwallow Marsh
    [1444] = { 40, 50 },  -- Feralas
    [1446] = { 40, 50 },  -- Tanaris
    [1447] = { 45, 55 },  -- Azshara
    [1448] = { 48, 55 },  -- Felwood
    [1449] = { 48, 55 },  -- Un'Goro Crater
    [1451] = { 55, 60 },  -- Silithus
    [1452] = { 55, 60 },  -- Winterspring
    [2482] = { 55, 60 },  -- Mount Hyjal (Forever)
    [2652] = { 35, 45 },  -- Shen'dralas (Forever)
    -- Elsewhere
    [2521] = { 1, 12 },   -- Zephras Isle (Forever)
}

-- Fallback 0%-getaway fishing skill caps if sfui.fishing_data is absent.
local FALLBACK_FISHING_CAPS = {
    [1426] = 25,  [1429] = 25,  [1420] = 25,
    [1432] = 75,  [1436] = 75,  [1421] = 75,
    [1433] = 150, [1431] = 150, [1437] = 150, [1424] = 150,
    [1416] = 225, [1417] = 225, [1434] = 225, [1435] = 225,
    [1425] = 300, [1422] = 300,
    [1423] = 425, [1428] = 425, [1430] = 425,
    [1453] = 75,  [1455] = 75,  [1458] = 75,
    [1411] = 25,  [1412] = 25,  [1438] = 25,
    [1439] = 75,  [1413] = 75,
    [1442] = 150, [1440] = 150,
    [1441] = 225, [1443] = 225, [1445] = 225,
    [1444] = 300, [1446] = 300, [1447] = 300, [1448] = 300, [1449] = 300, [1450] = 300,
    [1451] = 425, [1452] = 425,
    [1454] = 75,  [1456] = 75,  [1457] = 75,
    [2482] = 425, [2521] = 25,  [2548] = 225, [2652] = 300,
}

local byName
local holder, levelText, fishText, areaName
local hooked = false
local hookAttempted = false
local waiter

local function HexColor(r, g, b)
    return string_format("|cff%02x%02x%02x", math_floor((r or 1) * 255 + 0.5), math_floor((g or 1) * 255 + 0.5), math_floor((b or 1) * 255 + 0.5))
end

local function IsLevelsEnabled()
    return _G.SfuiDB == nil or _G.SfuiDB.mapShowZoneLevels ~= false
end

local function IsFishingEnabled()
    return _G.SfuiDB == nil or _G.SfuiDB.mapShowZoneFishing ~= false
end

local function GetFishingSpellLower()
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FISHING_SPELL)
    if n and n ~= "" then return string_lower(n) end
    return "fishing"
end

local function GetPlayerFishingSkill()
    if _G.GetProfessions and _G.GetProfessionInfo then
        local _, _, _, fishIdx = _G.GetProfessions()
        if fishIdx then
            local _, _, rank, _, _, _, _, modifier = _G.GetProfessionInfo(fishIdx)
            return (rank or 0) + (modifier or 0)
        end
    end
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local target = GetFishingSpellLower()
        for i = 1, _G.GetNumSkillLines() do
            local name, isHeader, _, rank, _, tempMod = _G.GetSkillLineInfo(i)
            if not isHeader and name and string_lower(name) == target then
                return (rank or 0) + (tempMod or 0)
            end
        end
    end
    return nil
end

local function GetZoneFishingCap(zoneID, subArea)
    local fd = sfui.fishing_data
    local parts = fd and fd.ZONE_SKILL_PARTS
    if parts and parts[zoneID] and subArea and subArea ~= "" then
        local subLower = string_lower(subArea)
        local part = parts[zoneID]
        if part.area and subLower:find(part.area, 1, true) then
            return part.skill
        end
    end
    if fd and fd.ZONE_SKILL and fd.ZONE_SKILL[zoneID] then
        return fd.ZONE_SKILL[zoneID]
    end
    return FALLBACK_FISHING_CAPS[zoneID]
end

local function FormatLevelsText(lv)
    local lo, hi = lv[1], lv[2]
    local level = UnitLevel("player") or 1
    local c
    if level < lo and GetQuestDifficultyColor then
        c = GetQuestDifficultyColor(lo)
    elseif level > hi and GetQuestDifficultyColor then
        c = GetQuestDifficultyColor(hi - 2)
    else
        c = (_G.QuestDifficultyColors and _G.QuestDifficultyColors["difficult"]) or { r = 1, g = 0.82, b = 0 }
    end
    return HexColor(c.r, c.g, c.b) .. string_format("(%d-%d)|r", lo, hi)
end

local function FormatFishingText(cap)
    local low = math_max(1, cap - NO_GETAWAY)
    local high = cap
    local r, g, b = 1, 1, 1
    local skill = GetPlayerFishingSkill()
    if skill then
        if skill < low then
            r, g, b = 1, 0.25, 0.25
        elseif skill < high then
            r, g, b = 1, 0.82, 0
        else
            r, g, b = 0.25, 1, 0.25
        end
    end
    return HexColor(r, g, b) .. string_format("%s %d (%d)|r", GetFishingSpellLower(), low, high)
end

local function OnLabelName(_, name)
    if not holder then return end
    if issecretvalue(name) then return end

    local showLevels = IsLevelsEnabled()
    local showFish = IsFishingEnabled()
    if not (showLevels or showFish) then
        levelText:Hide()
        fishText:Hide()
        return
    end

    local zone, onContinent
    if name and name ~= "" and _G.WorldMapFrame then
        local mapID = _G.WorldMapFrame:GetMapID()
        local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local mapTypes = Enum and Enum.UIMapType
        if info and mapTypes then
            if info.mapType == mapTypes.Continent then
                zone = byName and byName[name]
                onContinent = true
            elseif info.mapType == mapTypes.Zone then
                zone = mapID
            end
        end
    end

    local lv = showLevels and onContinent and zone and LEVELS[zone]
    local fishCap = showFish and zone and GetZoneFishingCap(zone, onContinent and nil or name)
    if not (lv or fishCap) then
        levelText:Hide()
        fishText:Hide()
        return
    end

    levelText:SetShown(lv ~= nil)
    if lv then
        levelText:SetText(FormatLevelsText(lv))
    end

    fishText:SetShown(fishCap ~= nil)
    if fishCap then
        fishText:SetText(FormatFishingText(fishCap))
        fishText:ClearAllPoints()
        if lv then
            fishText:SetPoint("TOP", levelText, "BOTTOM", 0, -2)
        else
            fishText:SetPoint("TOP", areaName, "BOTTOM", 0, -6)
        end
    end
end

local function FindAreaLabel()
    local wmf = _G.WorldMapFrame
    if not (wmf and wmf.dataProviders) then return nil end
    for provider in pairs(wmf.dataProviders) do
        local label = provider.Label
        if label and label.Name and label.labelInfoByType then
            return label
        end
    end
    return nil
end

local function PopulateZoneLookup()
    byName = {}
    if not (C_Map and C_Map.GetMapInfo) then return end
    local function addMap(id)
        local info = C_Map.GetMapInfo(id)
        if info and info.name then
            byName[info.name] = id
        end
    end
    for id in pairs(LEVELS) do addMap(id) end
    for id in pairs(FALLBACK_FISHING_CAPS) do addMap(id) end
    local zSkill = sfui.fishing_data and sfui.fishing_data.ZONE_SKILL
    if zSkill then
        for id in pairs(zSkill) do addMap(id) end
    end
end

local function TryBuild()
    if hooked then return true end
    local wmf = _G.WorldMapFrame
    if not wmf or not wmf.ScrollContainer then return false end
    local label = FindAreaLabel()
    if not label then
        if not hookAttempted then
            hookAttempted = true
            wmf:HookScript("OnShow", TryBuild)
        end
        return false
    end

    hooked = true
    PopulateZoneLookup()

    holder = CreateFrame("Frame", nil, wmf.ScrollContainer)
    holder:SetAllPoints()
    holder:SetFrameStrata("HIGH")

    areaName = label.Name
    levelText = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    fishText = holder:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")

    local font, size, flags = areaName:GetFont()
    if font and size then
        levelText:SetFont(font, math_floor(size * 0.7 + 0.5), flags)
        fishText:SetFont(font, math_max(9, math_floor(size * 0.42 + 0.5)), flags)
    end
    levelText:SetShadowOffset(1, -1)
    levelText:SetShadowColor(0, 0, 0, 1)
    fishText:SetShadowOffset(1, -1)
    fishText:SetShadowColor(0, 0, 0, 1)

    levelText:SetPoint("TOP", areaName, "BOTTOM", 0, -6)
    levelText:Hide()
    fishText:Hide()

    label:HookScript("OnShow", function()
        if holder then holder:Show() end
    end)
    label:HookScript("OnHide", function()
        if holder then holder:Hide() end
    end)
    hooksecurefunc(label.Name, "SetText", OnLabelName)
    return true
end

function sfui.zonelevels.Refresh()
    local any = IsLevelsEnabled() or IsFishingEnabled()
    if hooked then
        if not any then
            if levelText then levelText:Hide() end
            if fishText then fishText:Hide() end
        elseif areaName and areaName.GetText then
            OnLabelName(areaName, areaName:GetText())
        end
        return
    end
    if not any then
        if waiter then waiter:UnregisterEvent("ADDON_LOADED") end
        return
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
        TryBuild()
        return
    end
    if not waiter then
        waiter = CreateFrame("Frame")
        waiter:SetScript("OnEvent", function(self, _, name)
            if name == "Blizzard_WorldMap" then
                self:UnregisterEvent("ADDON_LOADED")
                TryBuild()
            end
        end)
    end
    waiter:RegisterEvent("ADDON_LOADED")
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    sfui.zonelevels.Refresh()
end)
