local addonName, addon = ...
sfui = sfui or {}
sfui.gatherskill = sfui.gatherskill or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/gatherskill.lua
--  Gathering Skill Requirements & Difficulty Colors on Tooltips (Camelot / Classic)
--
--  * World object tooltips (Enum.TooltipDataType.Object):
--    Appends "(req)" to "Requires Herbalism" / "Requires Mining" and colors it
--    by skill-up probability (orange < 25, yellow < 50, green < 100, grey >= 100)
--    when the player meets the requirement.
--  * Minimap mouseover tooltips (Enum.TooltipDataType.MinimapMouseover):
--    Appends colored " (req)" beside hovered herb/ore node names (red if unable),
--    memoized up to 500 entries and invalidated on skill/equipment changes.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G           = _G
local CreateFrame  = _G.CreateFrame
local C_Item       = _G.C_Item
local C_Spell      = _G.C_Spell
local Enum         = _G.Enum
local pairs        = _G.pairs
local ipairs       = _G.ipairs
local table_concat = _G.table.concat
local table_wipe   = _G.wipe
local string_format = _G.string.format
local string_lower = _G.string.lower

local issecretvalue = sfui.common.issecretvalue
    or (sfui.safety and sfui.safety.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local HERBALISM, MINING = 182, 186
local HERBALISM_SPELL, MINING_SPELL = 2366, 2575
local MEMO_MAX = 500

-- Herb itemID -> required Herbalism skill (+ English name fallback before item cache loads)
local HERBS = {
    [765]   = { 1, "Silverleaf" },
    [2447]  = { 1, "Peacebloom" },
    [2449]  = { 15, "Earthroot" },
    [785]   = { 50, "Mageroyal" },
    [2450]  = { 70, "Briarthorn" },
    [3820]  = { 85, "Stranglekelp" },
    [2453]  = { 100, "Bruiseweed" },
    [3355]  = { 115, "Wild Steelbloom" },
    [3369]  = { 120, "Grave Moss" },
    [3356]  = { 125, "Kingsblood" },
    [3357]  = { 150, "Liferoot" },
    [3818]  = { 160, "Fadeleaf" },
    [3821]  = { 170, "Goldthorn" },
    [3358]  = { 185, "Khadgar's Whisker" },
    [3819]  = { 195, "Wintersbite" },
    [4625]  = { 205, "Firebloom" },
    [8831]  = { 210, "Purple Lotus" },
    [8836]  = { 220, "Arthas' Tears" },
    [8838]  = { 230, "Sungrass" },
    [8839]  = { 235, "Blindweed" },
    [8845]  = { 245, "Ghost Mushroom" },
    [8846]  = { 250, "Gromsblood" },
    [13464] = { 260, "Golden Sansam" },
    [13463] = { 270, "Dreamfoil" },
    [13465] = { 280, "Mountain Silversage" },
    [13466] = { 285, "Plaguebloom" },
    [13467] = { 290, "Icecap" },
    [13468] = { 300, "Black Lotus" },
}

-- Ore node name -> required Mining skill
local ORES = {
    ["Copper Vein"]                 = 1,
    ["Tin Vein"]                    = 65,
    ["Incendicite Mineral Vein"]    = 65,
    ["Silver Vein"]                 = 75,
    ["Ooze Covered Silver Vein"]    = 75,
    ["Lesser Bloodstone Deposit"]   = 75,
    ["Iron Deposit"]                = 125,
    ["Indurium Mineral Vein"]       = 150,
    ["Gold Vein"]                   = 155,
    ["Ooze Covered Gold Vein"]      = 155,
    ["Mithril Deposit"]             = 175,
    ["Ooze Covered Mithril Deposit"]= 175,
    ["Truesilver Deposit"]          = 230,
    ["Ooze Covered Truesilver Deposit"] = 230,
    ["Dark Iron Deposit"]           = 230,
    ["Small Thorium Vein"]          = 245,
    ["Ooze Covered Thorium Vein"]   = 245,
    ["Rich Thorium Vein"]           = 275,
    ["Ooze Covered Rich Thorium Vein"] = 275,
    ["Hakkari Thorium Vein"]        = 275,
    ["Small Obsidian Chunk"]        = 305,
    ["Large Obsidian Chunk"]        = 305,
}

local nodes, nodesLower
local missing = {}
local hooked = false
local memo, memoCount = {}, 0
local cachedSkill = {}
local events = CreateFrame("Frame")

local function Forget()
    if table_wipe then
        table_wipe(memo)
    else
        memo = {}
    end
    memoCount = 0
    cachedSkill[HERBALISM] = nil
    cachedSkill[MINING] = nil
end

local function RegisterNode(name, line, req)
    if not name or name == "" then return end
    local entry = { line, req }
    nodes[name] = entry
    nodesLower[string_lower(name)] = entry
end

local function AddHerb(itemID)
    local info = HERBS[itemID]
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name or name == "" then return false end
    RegisterNode(name, HERBALISM, info[1])
    return true
end

local function BuildNodes()
    nodes = {}
    nodesLower = {}
    for name, req in pairs(ORES) do
        RegisterNode(name, MINING, req)
    end
    for itemID, info in pairs(HERBS) do
        RegisterNode(info[2], HERBALISM, info[1])
        if not AddHerb(itemID) then
            missing[itemID] = true
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            end
        end
    end
    if next(missing) then
        events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    end
end

local function IsEnabled()
    return _G.SfuiDB == nil or _G.SfuiDB.tooltipGatherSkill ~= false
end

local function IsMinimapEnabled()
    return IsEnabled() and (_G.SfuiDB == nil or _G.SfuiDB.tooltipGatherMinimap ~= false)
end

local function GetSkill(line)
    local cached = cachedSkill[line]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local result = false
    if _G.GetProfessions and _G.GetProfessionInfo then
        for _, idx in ipairs({ _G.GetProfessions() }) do
            if idx then
                local _, _, rank, _, _, _, id, mod = _G.GetProfessionInfo(idx)
                if id == line then
                    result = (rank or 0) + (mod or 0)
                    break
                end
            end
        end
    end

    if result == false and _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local spellName = C_Spell and C_Spell.GetSpellName
            and C_Spell.GetSpellName(line == MINING and MINING_SPELL or HERBALISM_SPELL)
        local target = spellName and string_lower(spellName)
        if target then
            for i = 1, _G.GetNumSkillLines() do
                local name, isHeader, _, rank, _, tempMod = _G.GetSkillLineInfo(i)
                if not isHeader and name and string_lower(name) == target then
                    result = (rank or 0) + (tempMod or 0)
                    break
                end
            end
        end
    end

    cachedSkill[line] = result
    return result ~= false and result or nil
end

local function OddsColor(skill, need)
    local over = skill - need
    if over < 25 then return 1, 0.5, 0.25 end
    if over < 50 then return 1, 1, 0 end
    if over < 100 then return 0.25, 0.75, 0.25 end
    return 0.5, 0.5, 0.5
end

local function Hex(r, g, b)
    return string_format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function RewriteMinimapLine(text)
    local out, changed = {}, false
    for part in (text .. "\n"):gmatch("(.-)\n") do
        local formatted = part
        local name = part:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
        local node = nodes[name] or (name and nodesLower[string_lower(name)])
        if node then
            local skill = GetSkill(node[1])
            local color = (skill and skill >= node[2]) and Hex(OddsColor(skill, node[2])) or "|cffff2020"
            formatted = string_format("%s %s(%d)|r", part, color, node[2])
            changed = true
        end
        out[#out + 1] = formatted
    end
    return changed and table_concat(out, "\n") or false
end

local function OnMinimapTooltip(tooltip)
    if tooltip ~= _G.GameTooltip or not IsMinimapEnabled() then return end
    if not nodes then BuildNodes() end

    local changed = false
    for i = 1, tooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not issecretvalue(text) then
            local updated = memo[text]
            if updated == nil then
                updated = RewriteMinimapLine(text)
                if memoCount >= MEMO_MAX then Forget() end
                memo[text] = updated
                memoCount = memoCount + 1
            end
            if updated then
                fs:SetText(updated)
                changed = true
            end
        end
    end
    if changed then
        tooltip:Show()
    end
end

local function OnObjectTooltip(tooltip, data)
    if tooltip ~= _G.GameTooltip or not IsEnabled() then return end
    local lines = data and data.lines
    local title = lines and lines[1] and lines[1].leftText
    if not title or issecretvalue(title) then return end
    if not nodes then BuildNodes() end

    local node = nodes[title] or nodesLower[string_lower(title)]
    if not node then return end

    local skillName = C_Spell and C_Spell.GetSpellName
        and C_Spell.GetSpellName(node[1] == MINING and MINING_SPELL or HERBALISM_SPELL)
    if not skillName then return end

    for i = 2, tooltip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and not issecretvalue(text) and text:find(skillName, 1, true) then
            if not text:find("%(%d+%)") then
                fs:SetText(string_format("%s (%d)", text, node[2]))
            end
            local skill = GetSkill(node[1])
            if skill and skill >= node[2] then
                fs:SetTextColor(OddsColor(skill, node[2]))
            end
            tooltip:Show()
            return
        end
    end
end

events:SetScript("OnEvent", function(self, event, itemID, success)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        sfui.gatherskill.Refresh()
        return
    elseif event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        Forget()
        return
    elseif event == "ITEM_DATA_LOAD_RESULT" and missing[itemID] then
        if success and nodes then AddHerb(itemID) end
        missing[itemID] = nil
        Forget()
        if not next(missing) then
            self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        end
    end
end)
events:RegisterEvent("PLAYER_LOGIN")

function sfui.gatherskill.Refresh()
    Forget()
    if not IsEnabled() then
        events:UnregisterEvent("SKILL_LINES_CHANGED")
        events:UnregisterEvent("SPELLS_CHANGED")
        events:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
        return
    end

    events:RegisterEvent("SKILL_LINES_CHANGED")
    events:RegisterEvent("SPELLS_CHANGED")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

    if nodes and next(missing) then
        for itemID in pairs(missing) do
            if AddHerb(itemID) then missing[itemID] = nil end
        end
        if next(missing) then events:RegisterEvent("ITEM_DATA_LOAD_RESULT") end
    end

    if hooked then return end
    local dp = _G.TooltipDataProcessor
    local dt = Enum and Enum.TooltipDataType
    if dp and dp.AddTooltipPostCall and dt then
        hooked = true
        if dt.Object then
            dp.AddTooltipPostCall(dt.Object, OnObjectTooltip)
        end
        if dt.MinimapMouseover then
            dp.AddTooltipPostCall(dt.MinimapMouseover, OnMinimapTooltip)
        end
    end
end
