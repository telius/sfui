local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.alts = sfui.alts or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.version and sfui.version.retail
if isRetail == nil then
    local projectID = _G.WOW_PROJECT_ID or 1
    local _, _, _, tocVersionNum = _G.GetBuildInfo()
    tocVersionNum = tonumber(tocVersionNum) or 0
    local isForever = (tocVersionNum >= 16000 and tocVersionNum < 20000)
    isRetail = (projectID == 1) and not isForever
end

if isRetail then
    return
end

local cfg = sfui.config.alts or {}

-- Localized APIs
local table = table
local math = math
local math_floor = math.floor
local math_max = math.max
local wipe = _G.wipe or table.wipe
local unpack = _G.unpack or table.unpack
local tostring = tostring
local tonumber = tonumber
local string = string
local ipairs = ipairs
local pairs = pairs
local next = next
local type = type
local GameTooltip = _G.GameTooltip
local UnitLevel = _G.UnitLevel
local UnitXP = _G.UnitXP
local UnitXPMax = _G.UnitXPMax
local GetXPExhaustion = _G.GetXPExhaustion
local IsResting = _G.IsResting
local GetAverageItemLevel = _G.GetAverageItemLevel
local GetServerTime = _G.GetServerTime
local RequestRaidInfo = _G.RequestRaidInfo
local GetNumSavedInstances = _G.GetNumSavedInstances
local GetSavedInstanceInfo = _G.GetSavedInstanceInfo
local GetNumSkillLines = _G.GetNumSkillLines
local GetSkillLineInfo = _G.GetSkillLineInfo
local GetItemCount = _G.GetItemCount
local UnitPVPRank = _G.UnitPVPRank
local GetPVPRankProgress = _G.GetPVPRankProgress
local GetPVPLifetimeStats = _G.GetPVPLifetimeStats
local GetPVPThisWeekStats = _G.GetPVPThisWeekStats
local C_QuestLog = _G.C_QuestLog
local C_CurrencyInfo = _G.C_CurrencyInfo
local GetCurrencyInfo = _G.GetCurrencyInfo
local IsModifiedClick = _G.IsModifiedClick
local ChatEdit_InsertLink = _G.ChatEdit_InsertLink

local AcquireTable = sfui.alts.AcquireTable
local ReleaseTable = sfui.alts.ReleaseTable

-- PvP Rank Data for Classic
local ALLIANCE_RANKS = {
    [1] = "Private",
    [2] = "Corporal",
    [3] = "Sergeant",
    [4] = "Master Sergeant",
    [5] = "Sergeant Major",
    [6] = "Knight",
    [7] = "Knight-Lieutenant",
    [8] = "Knight-Captain",
    [9] = "Knight-Champion",
    [10] = "Lieutenant Commander",
    [11] = "Commander",
    [12] = "Marshal",
    [13] = "Field Marshal",
    [14] = "Grand Marshal",
}

local HORDE_RANKS = {
    [1] = "Scout",
    [2] = "Grunt",
    [3] = "Sergeant",
    [4] = "Senior Sergeant",
    [5] = "First Sergeant",
    [6] = "Stone Guard",
    [7] = "Blood Guard",
    [8] = "Legionnaire",
    [9] = "Centurion",
    [10] = "Champion",
    [11] = "Lieutenant General",
    [12] = "General",
    [13] = "Warlord",
    [14] = "High Warlord",
}

local PRIMARY_PROF_IDS = {
    [171] = "Alchemy",
    [164] = "Blacksmithing",
    [333] = "Enchanting",
    [202] = "Engineering",
    [182] = "Herbalism",
    [165] = "Leatherworking",
    [186] = "Mining",
    [393] = "Skinning",
    [197] = "Tailoring",
}

local SECONDARY_PROF_IDS = {
    [129] = "firstAid",
    [185] = "cooking",
    [356] = "fishing",
}

local PRIMARY_PROFS = {
    ["Alchemy"] = true,
    ["Blacksmithing"] = true,
    ["Enchanting"] = true,
    ["Engineering"] = true,
    ["Leatherworking"] = true,
    ["Tailoring"] = true,
    ["Mining"] = true,
    ["Herbalism"] = true,
    ["Skinning"] = true,
}

local SECONDARY_PROFS = {
    ["Cooking"] = "cooking",
    ["First Aid"] = "firstAid",
    ["Fishing"] = "fishing",
}

local PROF_SHORT_NAMES = {
    ["Blacksmithing"] = "bs",
    ["Leatherworking"] = "lw",
    ["Tailoring"] = "tailor",
    ["Engineering"] = "engi",
    ["Enchanting"] = "enchant",
    ["Alchemy"] = "alch",
    ["Herbalism"] = "herb",
    ["Mining"] = "mining",
    ["Skinning"] = "skin",
}

local CLASSIC_RAIDS = {
    { key = "Onyxia", label = "Onyxia", match = "Onyxia", resetDays = 5 },
    { key = "MC",     label = "Molten Core", match = "Molten Core", resetDays = 7 },
    { key = "BWL",    label = "Blackwing Lair", match = "Blackwing Lair", resetDays = 7 },
    { key = "ZG",     label = "Zul'Gurub", match = "Zul'Gurub", resetDays = 3 },
    { key = "AQ20",   label = "Ruins of AQ", match = "Ruins of Ahn'Qiraj", resetDays = 3 },
    { key = "AQ40",   label = "Temple of AQ", match = "Temple of Ahn'Qiraj", resetDays = 7 },
    { key = "Naxx",   label = "Naxxramas", match = "Naxxramas", resetDays = 7 },
}

local CURRENCIES = {
    {
        id = 3402,
        label = "merchant's favor",
        icon = "Interface\\Icons\\racial_dwarf_findtreasure",
        desc = "Worth a considerable amount of gold and thus used as an interim currency among high-traffic merchant organizations. Members of the Durotar Supply and Logistics or Azeroth Commerce Authority would be willing to trade for this.",
    },
}

local CATEGORIES = {
    { name = "GENERAL",           label = "character",         type = "header" },
    { name = "LEVEL_XP",          label = "level / xp",        type = "classic_level_xp" },
    { name = "ILVL",              label = "item level",        type = "stat", key = "iLvl", format = "%.1f" },

    { name = "PVP_HEADER",        label = "pvp & honor",       type = "header" },
    { name = "PVP_RANK",          label = "rank",              type = "classic_pvp_rank" },
    { name = "PVP_HONOR",         label = "weekly honor",      type = "classic_pvp_honor" },
    { name = "PVP_MARKS",         label = "bg marks",          type = "classic_pvp_marks" },

    { name = "LOCKOUTS_HEADER",   label = "raid lockouts",     type = "header" },
    { name = "LOCKOUTS_GRID",     label = "raids (reset)",     type = "classic_lockout_grid" },

    { name = "ATTUNEMENTS_HEADER",label = "attunements & keys",type = "header" },
    { name = "ATTUNEMENTS_GRID",  label = "access / keys",     type = "classic_attunement_grid" },

    { name = "CURRENCIES_HEADER", label = "currencies",        type = "header" },
    { name = "CURRENCY_3402",     label = "merchant's favor",  type = "classic_currency", id = 3402 },

    { name = "PROFESSION_HEADER", label = "professions",       type = "header" },
    { name = "PROF_PRIMARY_1",    label = "prof 1",            type = "classic_prof", slot = 1 },
    { name = "PROF_PRIMARY_2",    label = "prof 2",            type = "classic_prof", slot = 2 },
    { name = "PROF_FIRST_AID",    label = "first aid",         type = "classic_prof_named", profKey = "firstAid" },
    { name = "PROF_FISHING",      label = "fishing",           type = "classic_prof_named", profKey = "fishing" },
    { name = "PROF_COOKING",      label = "cooking",           type = "classic_prof_named", profKey = "cooking" },
}

local function FormatTimeLeft(seconds)
    if not seconds or seconds <= 0 then return "-" end
    local d = math_floor(seconds / 86400)
    local h = math_floor((seconds % 86400) / 3600)
    local m = math_floor((seconds % 3600) / 60)
    if d > 0 then
        return string.format("%dd %dh", d, h)
    elseif h > 0 then
        return string.format("%dh %dm", h, m)
    else
        return string.format("%dm", m)
    end
end

local function GetPVPRankName(rankNum, isHorde)
    if not rankNum or rankNum < 1 then return "Unranked" end
    local ranks = isHorde and HORDE_RANKS or ALLIANCE_RANKS
    return ranks[rankNum] or ("Rank " .. rankNum)
end

local function PerformSync(data, isLogout)
    local now = GetServerTime()

    -- 1. Level & Rested XP
    local lvl = UnitLevel("player") or 1
    data.level = lvl
    data.xp = UnitXP("player") or 0
    data.xpMax = UnitXPMax("player") or 1
    data.restedXP = (GetXPExhaustion and GetXPExhaustion()) or 0
    data.isResting = (IsResting and IsResting()) and true or false

    -- 2. PvP Stats
    data.pvp = data.pvp or {}
    local rawRank = UnitPVPRank and UnitPVPRank("player") or 0
    -- In Classic UnitPVPRank returns 0 for unranked, internal 1-4 for sub-ranks, 5-18 for visual ranks 1-14
    local rankNumber = (rawRank and rawRank > 4) and (rawRank - 4) or 0
    data.pvp.rank = rankNumber
    data.pvp.rankProgress = (GetPVPRankProgress and GetPVPRankProgress()) or 0

    local isHorde = (data.race == "Orc" or data.race == "Troll" or data.race == "Tauren" or data.race == "Scourge" or data.race == "Undead")
    data.pvp.rankName = GetPVPRankName(rankNumber, isHorde)

    if GetPVPLifetimeStats then
        local hk, highestRank = GetPVPLifetimeStats()
        data.pvp.lifetimeHK = hk or 0
        data.pvp.highestRank = highestRank or 0
    end

    if GetPVPThisWeekStats then
        local hk, honor = GetPVPThisWeekStats()
        data.pvp.thisWeekHK = hk or 0
        data.pvp.thisWeekHonor = honor or 0
    end

    -- BG Marks
    data.pvp.marks = data.pvp.marks or {}
    if GetItemCount then
        data.pvp.marks.wsg = GetItemCount(20558, true) or 0 -- Warsong Gulch Mark of Honor
        data.pvp.marks.ab  = GetItemCount(20559, true) or 0 -- Arathi Basin Mark of Honor
        data.pvp.marks.av  = GetItemCount(20560, true) or 0 -- Alterac Valley Mark of Honor
    end

    -- 4. Raid Lockouts
    data.lockouts = data.lockouts or {}
    wipe(data.lockouts)
    local numSaved = GetNumSavedInstances and GetNumSavedInstances() or 0
    for i = 1, numSaved do
        local name, id, reset, difficulty, locked, extended, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        if locked and reset and reset > 0 then
            for _, rDef in ipairs(CLASSIC_RAIDS) do
                if name and string.find(name, rDef.match) then
                    data.lockouts[rDef.key] = {
                        resetTime = now + reset,
                        progress = encounterProgress or 0,
                        total = numEncounters or 0,
                        name = name,
                    }
                    break
                end
            end
        end
    end

    -- 5. Attunements & Keys
    data.attunements = data.attunements or {}
    -- Molten Core: Quest 7848 (Attunement to the Core)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        data.attunements.mc = C_QuestLog.IsQuestFlaggedCompleted(7848)
        data.attunements.bwl = C_QuestLog.IsQuestFlaggedCompleted(7761)
        data.attunements.naxx = C_QuestLog.IsQuestFlaggedCompleted(9121) or C_QuestLog.IsQuestFlaggedCompleted(9122) or C_QuestLog.IsQuestFlaggedCompleted(9123)
        if not isHorde then
            data.attunements.ony = C_QuestLog.IsQuestFlaggedCompleted(6502) or (GetItemCount and GetItemCount(16309, true) > 0)
        else
            data.attunements.ony = C_QuestLog.IsQuestFlaggedCompleted(6602) or C_QuestLog.IsQuestFlaggedCompleted(6584) or (GetItemCount and GetItemCount(16309, true) > 0) or false
        end
    else
        data.attunements.ony = (GetItemCount and GetItemCount(16309, true) > 0) or false
    end

    -- Keys (check bags/bank/keyring)
    if GetItemCount then
        data.attunements.skeleton = GetItemCount(13704, true) > 0    -- Skeleton Key (Scholomance)
        data.attunements.city = GetItemCount(12382, true) > 0        -- Key to the City (Stratholme)
        data.attunements.shadowforge = GetItemCount(11000, true) > 0 -- Shadowforge Key (BRD)
        data.attunements.crescent = GetItemCount(18249, true) > 0    -- Crescent Key (Dire Maul)
    end

    -- 6. Classic Professions
    data.professions = data.professions or {}
    wipe(data.professions)
    data.professions.primaries = {}

    local function recordSkill(name, rank, maxRank, modifier, isPrimary, skillID)
        if not name or name == "" then return end

        -- Dedup: if we already recorded this profession by name, update it instead of adding again
        if data.professions[name] then
            local existing = data.professions[name]
            existing.rank = rank or existing.rank
            existing.maxRank = maxRank or existing.maxRank
            existing.modifier = modifier or existing.modifier
            if skillID then existing.skillID = skillID end
            return
        end

        local entry = {
            name = name,
            rank = rank or 0,
            maxRank = maxRank or 300,
            modifier = modifier or 0,
            skillID = skillID,
            isPrimary = isPrimary,
        }

        local secKey = (skillID and SECONDARY_PROF_IDS[skillID]) or SECONDARY_PROFS[name]
        if secKey then
            data.professions[secKey] = entry
            data.professions[name] = entry
        elseif isPrimary then
            table.insert(data.professions.primaries, entry)
            data.professions[name] = entry
        else
            data.professions[name] = entry
        end
    end

    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local numSkills = C_SkillInfo.GetNumSkillLines()
        for i = 1, numSkills do
            local info = C_SkillInfo.GetSkillLineInfo(i)
            if info and not info.isHeader and info.name then
                local isPrimary = (info.isAbandonable == true) or (PRIMARY_PROF_IDS[info.skillID] ~= nil) or (PRIMARY_PROFS[info.name] == true)
                recordSkill(info.name, info.rank, info.maxRank, info.modifier, isPrimary, info.skillID)
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        local numSkills = GetNumSkillLines()
        for i = 1, numSkills do
            local skillName, isHeader, _, skillRank, _, skillModifier, skillMaxRank, isAbandonable = GetSkillLineInfo(i)
            if not isHeader and skillName then
                local isPrimary = (isAbandonable == true) or (PRIMARY_PROFS[skillName] == true)
                recordSkill(skillName, skillRank, skillMaxRank, skillModifier, isPrimary, nil)
            end
        end
    end

    -- Direct ID lookup fallback for secondary skills in Camelot
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        if not data.professions.firstAid then
            local info = C_SkillInfo.GetSkillLineInfoByID(129)
            if info and info.rank and info.rank > 0 then
                recordSkill(info.name or "First Aid", info.rank, info.maxRank, info.modifier, false, 129)
            end
        end
        if not data.professions.cooking then
            local info = C_SkillInfo.GetSkillLineInfoByID(185)
            if info and info.rank and info.rank > 0 then
                recordSkill(info.name or "Cooking", info.rank, info.maxRank, info.modifier, false, 185)
            end
        end
        if not data.professions.fishing then
            local info = C_SkillInfo.GetSkillLineInfoByID(356)
            if info and info.rank and info.rank > 0 then
                recordSkill(info.name or "Fishing", info.rank, info.maxRank, info.modifier, false, 356)
            end
        end
    end

    table.sort(data.professions.primaries, function(a, b) return (a.name or "") < (b.name or "") end)

    -- 7. Currencies
    data.currencies = data.currencies or {}
    for _, cDef in ipairs(CURRENCIES) do
        local curr = data.currencies[cDef.id] or {}
        local info
        if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            info = C_CurrencyInfo.GetCurrencyInfo(cDef.id)
        elseif sfui.common and sfui.common.get_currency_info then
            info = sfui.common.get_currency_info(cDef.id)
        end

        local count = (info and info.quantity) or 0
        if count == 0 and GetItemCount then
            local itemCount = GetItemCount("Merchant's Favor", true) or 0
            if itemCount > 0 then
                count = itemCount
            end
        end

        curr.val = count
        curr.max = (info and info.maxQuantity) or 0
        curr.totalEarned = (info and info.totalEarned) or 0
        curr.name = (info and info.name) or cDef.label
        curr.icon = (info and info.iconFileID and info.iconFileID > 0 and info.iconFileID) or cDef.icon

        data.currencies[cDef.id] = curr
    end

    if sfui.recipes and sfui.recipes.InvalidateCache then
        sfui.recipes.InvalidateCache()
    end
end

local function RenderCell(cell, cat, altData, classColor, col)
    local text = cell.text
    if not text then return false end

    local now = GetServerTime()

    if cat.type == "classic_level_xp" then
        local lvl = altData.level or 1
        if lvl >= 60 then
            text:SetText("60")
            text:SetTextColor(1, 0.82, 0) -- Gold
            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("level 60 (max level)", 1, 0.82, 0)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            local xp = altData.xp or 0
            local xpMax = altData.xpMax or 1
            local pct = math_floor((xp / xpMax) * 100)
            local restedXP = altData.restedXP or 0
            local restedPct = math_floor((restedXP / xpMax) * 100)

            if restedXP > 0 then
                text:SetText(string.format("%d (%d%%) |cff00ffff+%d%%|r", lvl, pct, restedPct))
            else
                text:SetText(string.format("%d (%d%%)", lvl, pct))
            end
            text:SetTextColor(unpack(sfui.config.colors.white))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(string.format("level %d progress", lvl), 1, 1, 1)
                GameTooltip:AddDoubleLine("current xp:", string.format("%d / %d (%d%%)", xp, xpMax, pct), 1, 1, 1, 1, 0.82, 0)
                GameTooltip:AddDoubleLine("remaining xp:", string.format("%d", xpMax - xp), 1, 1, 1, 1, 1, 1)
                if restedXP > 0 then
                    local bars = (restedXP / xpMax) * 20
                    GameTooltip:AddDoubleLine("rested xp:", string.format("%d (%.1f bars / %d%%)", restedXP, bars, restedPct), 1, 1, 1, 0, 1, 1)
                else
                    GameTooltip:AddDoubleLine("rested xp:", "none", 1, 1, 1, 0.6, 0.6, 0.6)
                end
                if altData.isResting then
                    GameTooltip:AddLine("currently in a rest area (gaining 4x rested xp)", 0.2, 1.0, 0.4)
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return true

    elseif cat.type == "classic_pvp_rank" then
        local pvp = altData.pvp
        if pvp and pvp.rank and pvp.rank > 0 then
            local rankNum = pvp.rank
            local rankTitle = pvp.rankName or ("Rank " .. rankNum)
            local progress = math_floor((pvp.rankProgress or 0) * 100)

            -- Color rank by bracket
            if rankNum >= 11 then
                text:SetTextColor(1, 0.5, 0) -- Commander / Warlord (Epic Orange)
            elseif rankNum >= 7 then
                text:SetTextColor(0.64, 0.21, 0.93) -- Knight-Lt / Blood Guard (Rare Purple)
            else
                text:SetTextColor(0, 0.6, 1) -- Private to Knight (Blue)
            end

            text:SetText(string.format("R%d (%d%%)", rankNum, progress))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(string.format("Rank %d: %s", rankNum, rankTitle), 1, 1, 1)
                GameTooltip:AddDoubleLine("Rank Progress:", string.format("%d%% to Rank %d", progress, rankNum + 1), 1, 1, 1, 1, 0.82, 0)
                if pvp.lifetimeHK then
                    GameTooltip:AddDoubleLine("Lifetime HKs:", tostring(pvp.lifetimeHK), 1, 1, 1, 1, 1, 1)
                end
                if pvp.highestRank and pvp.highestRank > 0 then
                    GameTooltip:AddDoubleLine("Highest Rank Attained:", "Rank " .. pvp.highestRank, 1, 1, 1, 0.8, 0.8, 0.8)
                end
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:SetText("unranked")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "classic_pvp_honor" then
        local pvp = altData.pvp
        if pvp and (pvp.thisWeekHonor and pvp.thisWeekHonor > 0 or pvp.thisWeekHK and pvp.thisWeekHK > 0) then
            local honorStr = pvp.thisWeekHonor >= 1000 and string.format("%.1fk", pvp.thisWeekHonor / 1000) or tostring(pvp.thisWeekHonor or 0)
            text:SetText(string.format("%s (%d HK)", honorStr, pvp.thisWeekHK or 0))
            text:SetTextColor(unpack(sfui.config.colors.white))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("this week's pvp standing", 1, 1, 1)
                GameTooltip:AddDoubleLine("estimated honor:", tostring(pvp.thisWeekHonor or 0), 1, 1, 1, 1, 0.82, 0)
                GameTooltip:AddDoubleLine("honorable kills:", tostring(pvp.thisWeekHK or 0), 1, 1, 1, 1, 1, 1)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "classic_pvp_marks" then
        local marks = altData.pvp and altData.pvp.marks
        if marks then
            local wsg = marks.wsg or 0
            local ab  = marks.ab or 0
            local av  = marks.av or 0
            text:SetText(string.format("|cff33ff33%d|r / |cffffaa00%d|r / |cff00aaff%d|r", wsg, ab, av))
            text:SetTextColor(unpack(sfui.config.colors.white))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("battleground marks of honor", 1, 1, 1)
                GameTooltip:AddDoubleLine("|cff33ff33warsong gulch:|r", tostring(wsg), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("|cffffaa00arathi basin:|r", tostring(ab), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddDoubleLine("|cff00aaffalterac valley:|r", tostring(av), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("counts items across bags and bank.", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "classic_lockout_grid" then
        text:Hide()
        local lockouts = altData.lockouts or {}
        local numRaids = #CLASSIC_RAIDS
        local squareSize = (cfg.columnWidth - 10) / numRaids

        for bIdx, rDef in ipairs(CLASSIC_RAIDS) do
            local rect = cell["lockRect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
            cell["lockRect" .. bIdx] = rect
            rect:Show()
            rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
            rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

            local lock = lockouts[rDef.key]
            local isLocked = lock and lock.resetTime and (lock.resetTime > now)

            if isLocked then
                rect:SetColorTexture(1.0, 0.25, 0.25, 0.85) -- Red / locked
            else
                rect:SetColorTexture(0.06, 0.06, 0.07, 0.60) -- Available / gray
            end
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("classic raid lockouts", 1, 1, 1)
            for _, rDef in ipairs(CLASSIC_RAIDS) do
                local lock = lockouts[rDef.key]
                local isLocked = lock and lock.resetTime and (lock.resetTime > now)
                if isLocked then
                    local timeLeft = FormatTimeLeft(lock.resetTime - now)
                    GameTooltip:AddDoubleLine(rDef.label, string.format("|cffff4444locked (%s)|r", timeLeft), 1, 1, 1, 1, 1, 1)
                else
                    GameTooltip:AddDoubleLine(rDef.label, "|cff00ff00available|r", 1, 1, 1, 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true

    elseif cat.type == "classic_attunement_grid" then
        text:Hide()
        local att = altData.attunements or {}
        local items = {
            { key = "mc",          label = "Molten Core" },
            { key = "ony",         label = "Onyxia's Lair" },
            { key = "bwl",         label = "Blackwing Lair" },
            { key = "naxx",        label = "Naxxramas" },
            { key = "skeleton",    label = "Scholomance (Skeleton Key)" },
            { key = "city",        label = "Stratholme (Key to the City)" },
            { key = "shadowforge", label = "BRD (Shadowforge Key)" },
            { key = "crescent",    label = "Dire Maul (Crescent Key)" },
        }
        local numItems = #items
        local squareSize = (cfg.columnWidth - 10) / numItems

        for bIdx, itm in ipairs(items) do
            local rect = cell["attRect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
            cell["attRect" .. bIdx] = rect
            rect:Show()
            rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
            rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

            local unlocked = att[itm.key] == true
            if unlocked then
                rect:SetColorTexture(0.2, 0.9, 0.2, 0.85) -- Green: Unlocked
            else
                rect:SetColorTexture(0.06, 0.06, 0.07, 0.60) -- Dark: Locked
            end
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("attunements & dungeon keys", 1, 1, 1)
            for _, itm in ipairs(items) do
                local unlocked = att[itm.key] == true
                local status = unlocked and "|cff00ff00unlocked|r" or "|cffff4444locked|r"
                GameTooltip:AddDoubleLine(itm.label, status, 1, 1, 1, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return true

    elseif cat.type == "classic_prof" then
        local p
        if altData.professions and altData.professions.primaries then
            p = altData.professions.primaries[cat.slot]
        elseif altData.professions then
            local profs = {}
            local seen = {}
            for _, entry in pairs(altData.professions) do
                if type(entry) == "table" and entry.isPrimary and entry.name and not seen[entry.name] then
                    seen[entry.name] = true
                    table.insert(profs, entry)
                end
            end
            table.sort(profs, function(a, b) return (a.name or "") < (b.name or "") end)
            p = profs[cat.slot]
        end

        if p and p.rank then
            local shortName = PROF_SHORT_NAMES[p.name] or p.name:lower()
            local isMax = p.rank >= (p.maxRank or 300)
            local rankColor = isMax and "|cff00ff00" or "|cffffffff"
            text:ClearAllPoints()
            text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:SetText(string.format("%s %s%d/%d|r", shortName, rankColor, p.rank, p.maxRank or 300))
            text:SetTextColor(unpack(sfui.config.colors.white))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(p.name:lower(), 1, 0.82, 0)
                local rankStr = string.format("%d / %d", p.rank, p.maxRank or 300)
                if p.modifier and p.modifier > 0 then
                    rankStr = string.format("%d (+%d) / %d", p.rank, p.modifier, p.maxRank or 300)
                end
                GameTooltip:AddDoubleLine("skill level:", rankStr, 1, 1, 1, 1, 1, 1)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:ClearAllPoints()
            text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "classic_prof_named" then
        local p
        if altData.professions then
            p = altData.professions[cat.profKey] or altData.professions[cat.label]
            if not p then
                for _, entry in pairs(altData.professions) do
                    if type(entry) == "table" and entry.name and (entry.name == cat.label or (cat.profKey and entry.name:lower():find(cat.profKey:lower()))) then
                        p = entry
                        break
                    end
                end
            end
        end

        if p and p.rank then
            local isMax = p.rank >= (p.maxRank or 300)
            local rankColor = isMax and "|cff00ff00" or "|cffffffff"
            text:ClearAllPoints()
            text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:SetText(string.format("%s%d/%d|r", rankColor, p.rank, p.maxRank or 300))
            text:SetTextColor(unpack(sfui.config.colors.white))

            cell:EnableMouse(true)
            cell:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine((p.name or cat.label):lower(), 1, 0.82, 0)
                local rankStr = string.format("%d / %d", p.rank, p.maxRank or 300)
                if p.modifier and p.modifier > 0 then
                    rankStr = string.format("%d (+%d) / %d", p.rank, p.modifier, p.maxRank or 300)
                end
                GameTooltip:AddDoubleLine("skill level:", rankStr, 1, 1, 1, 1, 1, 1)
                GameTooltip:Show()
            end)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            text:ClearAllPoints()
            text:SetPoint("CENTER", cell, "CENTER", 0, 0)
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:SetText("-")
            text:SetTextColor(0.5, 0.5, 0.5)
            cell:SetScript("OnEnter", nil)
            cell:SetScript("OnLeave", nil)
        end
        return true

    elseif cat.type == "classic_currency" then
        local cDef = nil
        for _, def in ipairs(CURRENCIES) do
            if def.id == cat.id then
                cDef = def
                break
            end
        end
        cDef = cDef or { id = cat.id, label = cat.label, icon = cat.icon, desc = cat.desc }

        local cData = altData.currencies and altData.currencies[cat.id]
        local val = 0
        local maxQty = 0
        local icon = cDef.icon or "Interface\\Icons\\racial_dwarf_findtreasure"
        local name = cDef.label

        if type(cData) == "table" then
            val = cData.val or 0
            maxQty = cData.max or 0
            if cData.icon and cData.icon ~= 0 then icon = cData.icon end
            if cData.name and cData.name ~= "" then name = cData.name end
        elseif type(cData) == "number" then
            val = cData
        end

        text:ClearAllPoints()
        text:SetPoint("CENTER", cell, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetWidth(0)

        local iconStr
        if type(icon) == "number" then
            iconStr = string.format("|T%d:12:12:0:0|t", icon)
        else
            iconStr = string.format("|T%s:12:12:0:0|t", tostring(icon))
        end

        if val > 0 then
            local valStr
            if val >= 1000 then
                valStr = string.format("%.1fk", val / 1000)
            else
                valStr = tostring(val)
            end
            text:SetText(string.format("%s %s", iconStr, valStr))
            text:SetTextColor(unpack(sfui.config.colors.white))
        else
            text:SetText(string.format("%s |cff7777770|r", iconStr))
            text:SetTextColor(0.5, 0.5, 0.5)
        end

        cell:EnableMouse(true)
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(string.format("%s %s", iconStr, name), 1, 0.82, 0)
            if maxQty and maxQty > 0 then
                GameTooltip:AddDoubleLine("total:", string.format("%d / %d", val, maxQty), 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddDoubleLine("total:", tostring(val), 1, 1, 1, 1, 1, 1)
            end

            local desc = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyDescription and C_CurrencyInfo.GetCurrencyDescription(cat.id))
            if not desc or desc == "" then
                desc = cDef.desc
            end
            if desc and desc ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(desc, 0.9, 0.9, 0.9, true)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

        cell:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and IsModifiedClick and IsModifiedClick("CHATLINK") then
                local link = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(cat.id, val))
                if link and ChatEdit_InsertLink then
                    ChatEdit_InsertLink(link)
                end
            end
        end)
        return true
    end

    return false
end

-- Register Classic / Camelot Provider
sfui.alts.RegisterProvider({
    name = "camelot",
    GetCategories = function() return CATEGORIES end,
    RefreshDynamicCategories = function() end,
    PerformSync = PerformSync,
    CheckWeeklyResets = function() return nil end,
    RenderCell = RenderCell,
    sortOptions = {
        { text = "Name (A-Z)",  value = "name" },
        { text = "Level / XP",  value = "level" },
        { text = "Item Level",  value = "ilvl" },
        { text = "PvP Rank",    value = "pvp_rank" },
        { text = "Time Played", value = "timeplayed" },
    },
    SortAlts = function(a, b, sortKey)
        if sortKey == "level" then
            local lA = a.data.level or 0
            local lB = b.data.level or 0
            if lA ~= lB then return lA > lB end
            return (a.data.xp or 0) > (b.data.xp or 0)
        elseif sortKey == "pvp_rank" then
            local rA = (a.data.pvp and a.data.pvp.rank) or 0
            local rB = (b.data.pvp and b.data.pvp.rank) or 0
            if rA ~= rB then return rA > rB end
            return ((a.data.pvp and a.data.pvp.rankProgress) or 0) > ((b.data.pvp and b.data.pvp.rankProgress) or 0)
        end
    end,
    OnFrameShow = function()
        if RequestRaidInfo then RequestRaidInfo() end
    end,
    RegisterEvents = function()
        local function on_sync()
            sfui.alts.PerformSync()
            if SfuiAltsFrame and SfuiAltsFrame:IsShown() then
                sfui.alts.UpdateUI(true)
            end
        end
        sfui.events.RegisterEvent("UPDATE_INSTANCE_INFO",          on_sync)
        sfui.events.RegisterEvent("SKILL_LINES_CHANGED",           on_sync)
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP",               on_sync)
        sfui.events.RegisterEvent("PLAYER_XP_UPDATE",              on_sync)
        sfui.events.RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE",  on_sync)
        sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED",     on_sync)
        sfui.events.RegisterEvent("CURRENCY_DISPLAY_UPDATE",       on_sync)
        sfui.events.RegisterEvent("BAG_UPDATE",                     on_sync)
    end,
})
