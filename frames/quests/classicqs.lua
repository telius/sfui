--[[
    SFUI Classic Quest Extension (Vanilla / Classic Forever Edition)
    frames/quests/classicqs.lua

    Modular extension that hooks into the core quests.lua engine on
    World of Warcraft: Forever (Camelot) and Classic Era.

    Responsibilities:
      - Dynamic Zone Section Engine: Converts tracked quests into collapsible zone sections
      - Current Zone Prioritization: Floats active zone to top with cyan accent
      - Difficulty-Colored Brackets: Prepends [14], [18D], [15+] colored by player level
      - Quest Log Capacity Tracker: Computes active quest count vs cap ([16/20])
      - Usable Quest Item Provider: Detects and uses special quest items (GetQuestLogSpecialItemInfo)
]]

local addonName, addon = ...
sfui = sfui or {}

-- ─────────────────────────────────────────────────────────
--  CLIENT GUARD: Only active on Classic Forever / Classic Era
-- ─────────────────────────────────────────────────────────
local isClassicForever = (sfui.compat and ((sfui.compat.has and (sfui.compat.has.wow_forever or sfui.compat.has.classic_era)) or sfui.compat.is_wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
    or (sfui.version and (sfui.version.wow_forever or sfui.version.classic_era or not sfui.version.retail))

if not isClassicForever then
    return
end

sfui.classicqs = sfui.classicqs or {}
local ClassicQS = sfui.classicqs

-- Localize Globals & APIs
local _G = _G
local UnitLevel = _G.UnitLevel
local UnitEffectiveLevel = _G.UnitEffectiveLevel or _G.UnitLevel
local GetZoneText = _G.GetZoneText
local GetRealZoneText = _G.GetRealZoneText
local GetNumQuestLogEntries = _G.GetNumQuestLogEntries
local GetQuestLogTitle = _G.GetQuestLogTitle
local GetQuestLogSpecialItemInfo = _G.GetQuestLogSpecialItemInfo
local C_QuestLog = _G.C_QuestLog
local ipairs, pairs, type = _G.ipairs, _G.pairs, _G.type
local table_insert, table_sort = _G.table.insert, _G.table.sort
local string_format = string.format

-- ─────────────────────────────────────────────────────────
--  DIFFICULTY COLOR ENGINE
-- ─────────────────────────────────────────────────────────
local function GetDifficultyColorCode(questLevel)
    local playerLevel = UnitEffectiveLevel("player") or UnitLevel("player") or 1
    local levelDiff = questLevel - playerLevel

    if _G.DifficultyUtil and _G.DifficultyUtil.GetRelativeDifficultyColor then
        local c = _G.DifficultyUtil.GetRelativeDifficultyColor(playerLevel, questLevel)
        if c then
            return string_format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
    end

    if levelDiff >= 5 then
        return "|cffff2020" -- Red (impossible)
    elseif levelDiff >= 3 then
        return "|cffff8020" -- Orange (very difficult)
    elseif levelDiff >= -2 then
        return "|cffffff20" -- Yellow (fair / normal)
    elseif levelDiff >= -6 then
        return "|cff40c040" -- Green (easy)
    else
        return "|cff808080" -- Gray (trivial, no XP)
    end
end

ClassicQS.GetDifficultyColorCode = GetDifficultyColorCode

-- ─────────────────────────────────────────────────────────
--  TITLE FORMATTER: [LevelTag] Title
-- ─────────────────────────────────────────────────────────
function ClassicQS.FormatTitle(entry, rawTitle)
    if not entry then return rawTitle end

    local qLevel = entry.level
    if (not qLevel or qLevel <= 0) and entry.questID and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        qLevel = C_QuestLog.GetQuestDifficultyLevel(entry.questID)
    end
    if not qLevel or qLevel <= 0 then
        return rawTitle
    end

    -- Determine Type Tag: + (Elite), D (Dungeon), R (Raid), G# (Group)
    local tag = ""
    local sGroup = entry.suggestedGroup
    if (not sGroup or sGroup <= 1) and entry.questLogIndex and C_QuestLog and C_QuestLog.GetInfo then
        local qInfo = C_QuestLog.GetInfo(entry.questLogIndex)
        if qInfo then sGroup = qInfo.suggestedGroup end
    end

    if sGroup and sGroup > 1 then
        tag = "G" .. sGroup
    elseif entry.isDungeon or entry.questTag == "Dungeon" then
        tag = "D"
    elseif entry.isRaid or entry.questTag == "Raid" then
        tag = "R"
    elseif entry.isElite or entry.questTag == "Elite" then
        tag = "+"
    elseif entry.questID and C_QuestLog and C_QuestLog.GetQuestTagInfo then
        local tagInfo = C_QuestLog.GetQuestTagInfo(entry.questID)
        if tagInfo then
            local tID = tagInfo.tagID
            local eq = _G.Enum and _G.Enum.QuestTag
            if eq and (tID == eq.Dungeon) then
                tag = "D"
            elseif eq and (tID == eq.Raid or tID == eq.Raid10 or tID == eq.Raid25) then
                tag = "R"
            elseif eq and (tID == eq.Group) then
                tag = "+"
            end
        end
    end

    local diffColor = GetDifficultyColorCode(qLevel)
    local bracket = string_format("%s[%d%s]|r", diffColor, qLevel, tag)
    return bracket .. " " .. rawTitle
end

-- ─────────────────────────────────────────────────────────
--  DYNAMIC ZONE CLASSIFICATION
-- ─────────────────────────────────────────────────────────
function ClassicQS.GetQuestSectionID(info, questID, zoneName)
    local zName = zoneName
    if not zName or zName == "" then
        if sfui.questlog and sfui.questlog.providers and sfui.questlog.providers.GetQuestZoneName then
            zName = sfui.questlog.providers.GetQuestZoneName(questID, false)
        end
    end
    if (not zName or zName == "") and info and info.questLogIndex and C_QuestLog and C_QuestLog.GetHeaderIndexForQuest then
        local hIdx = C_QuestLog.GetHeaderIndexForQuest(questID)
        if hIdx and C_QuestLog.GetInfo then
            local hInfo = C_QuestLog.GetInfo(hIdx)
            if hInfo and hInfo.title and hInfo.title ~= "" then
                zName = hInfo.title
            end
        end
    end
    if not zName or zName == "" then
        zName = "Miscellaneous"
    end

    return "zone_" .. zName, zName
end

-- ─────────────────────────────────────────────────────────
--  DYNAMIC ZONE SECTION DEFINITIONS
-- ─────────────────────────────────────────────────────────
local dynamicZoneDefs = {}

function ClassicQS.GetZoneSectionDefs(sectionLists)
    for k in pairs(dynamicZoneDefs) do
        dynamicZoneDefs[k] = nil
    end

    local currentZone = (GetRealZoneText and GetRealZoneText())
        or (GetZoneText and GetZoneText())
        or ""

    for sID, list in pairs(sectionLists) do
        if sID:sub(1, 5) == "zone_" and list and #list > 0 then
            local zName = sID:sub(6)
            local isCur = (currentZone ~= "" and zName:lower() == currentZone:lower())
            local color = isCur and { 0.00, 1.00, 1.00 } or { 1.00, 1.00, 1.00 }
            local badgeTag = isCur and " [Zone]" or ""

            table_insert(dynamicZoneDefs, {
                id            = sID,
                label         = zName:lower() .. badgeTag,
                zoneName      = zName,
                color         = color,
                isZone        = true,
                isCurrentZone = isCur,
            })
        end
    end

    -- Priority sort: Active player zone first, then alphabetical
    table_sort(dynamicZoneDefs, function(a, b)
        if a.isCurrentZone ~= b.isCurrentZone then
            return a.isCurrentZone
        end
        return a.zoneName < b.zoneName
    end)

    return dynamicZoneDefs
end

-- ─────────────────────────────────────────────────────────
--  CAPACITY TRACKER
-- ─────────────────────────────────────────────────────────
function ClassicQS.GetCapacityInfo()
    local numQuests = 0
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0

    for i = 1, numEntries do
        local isHeader = false
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then isHeader = info.isHeader end
        elseif GetQuestLogTitle then
            local _, _, _, tHeader = GetQuestLogTitle(i)
            isHeader = tHeader
        end
        if not isHeader then
            numQuests = numQuests + 1
        end
    end

    local maxQuests = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 20
    local color = "|cffffffff"
    if numQuests >= maxQuests then
        color = "|cffff2020" -- Full!
    elseif numQuests >= (maxQuests - 2) then
        color = "|cffff9900" -- Near cap
    end

    local formatted = string_format("%s[%d/%d]|r", color, numQuests, maxQuests)
    return numQuests, maxQuests, formatted
end

-- ─────────────────────────────────────────────────────────
--  USABLE QUEST ITEM HELPER
-- ─────────────────────────────────────────────────────────
function ClassicQS.GetSpecialItemInfo(questLogIndex)
    if not questLogIndex or not GetQuestLogSpecialItemInfo then return nil end
    local link, itemTex, charges, showItemWhenComplete = GetQuestLogSpecialItemInfo(questLogIndex)
    if itemTex then
        return {
            link      = link,
            texture   = itemTex,
            charges   = charges,
            showWhenComplete = showItemWhenComplete,
        }
    end
    return nil
end
