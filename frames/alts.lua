local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.alts = {}

local cfg = sfui.config.alts
-- SfuiDB is global, do not shadow it locally

-- Localized APIs
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitLevel = UnitLevel
local GetAverageItemLevel = GetAverageItemLevel
local GetServerTime = GetServerTime
local GetMoney = GetMoney
local AbbreviateLargeNumbers = AbbreviateLargeNumbers

-- Configuration & Data Tables
local CURRENCIES = {
    { id = 3383, label = "Adventurer", icon = 7639517 }, -- Adventurer's Dawncrest
    { id = 3341, label = "Veteran",    icon = 7639525 }, -- Veteran Dawncrest
    { id = 3343, label = "Champ",      icon = 7639519 }, -- Champion Dawncrest
    { id = 3345, label = "Hero",       icon = 7639521 }, -- Hero Dawncrest
    { id = 3212, label = "Spark",      icon = 7551418 }, -- Spark of Fortune
    { id = 3378, label = "Catalyst",   icon = 4622294 }, -- Catalyst Charges
}

local CATEGORIES = {
    { name = "GENERAL",         label = "Character",           type = "header" },
    { name = "ILVL",            label = "Level / iLvl",        type = "stat",      key = "iLvl",     format = "%.1f" },
    { name = "RATING",          label = "M+ Rating",           type = "stat",      key = "rating" },
    { name = "KEystone",        label = "Current Key",         type = "keystone" },

    { name = "PREY_HEADER",     label = "Prey Hunt",           type = "header" },
    { name = "PREY",            label = "Hunt Progress",       type = "prey" },

    { name = "VAULT_HEADER",    label = "Great Vault",         type = "header" },
    { name = "VAULT_RAID",      label = "Raid",                type = "vault_row", group = "raid" },
    { name = "VAULT_DUNGEON",   label = "Dungeon",             type = "vault_row", group = "dungeon" },
    { name = "VAULT_WORLD",     label = "World/Delve",         type = "vault_row", group = "world" },

    { name = "RAID_HEADER",     label = "Raid Progress",       type = "header" },
    { name = "RAID_M",          label = "Mythic",              type = "raid_grid", difficulty = 16 },
    { name = "RAID_H",          label = "Heroic",              type = "raid_grid", difficulty = 15 },
    { name = "RAID_N",          label = "Normal",              type = "raid_grid", difficulty = 14 },

    { name = "DUNGEONS_HEADER", label = "Dungeons",            type = "header" },
    { name = "DUNGEON_1",       label = "Magister's Terrace",  type = "dungeon",   mapID = 501 },
    { name = "DUNGEON_2",       label = "Maisara Caverns",     type = "dungeon",   mapID = 502 },
    { name = "DUNGEON_3",       label = "Nexus-Point Xenas",   type = "dungeon",   mapID = 503 },
    { name = "DUNGEON_4",       label = "Windrunner Spire",    type = "dungeon",   mapID = 504 },
    { name = "DUNGEON_5",       label = "Algeth'ar Academy",   type = "dungeon",   mapID = 505 },
    { name = "DUNGEON_6",       label = "Pit of Saron",        type = "dungeon",   mapID = 506 },
    { name = "DUNGEON_7",       label = "Seat of Triumvirate", type = "dungeon",   mapID = 507 },
    { name = "DUNGEON_8",       label = "Skyreach",            type = "dungeon",   mapID = 508 },

    { name = "CURRENCY_HEADER", label = "Currency",            type = "header" },
}

-- Insert Currencies into Categories
for _, currencyDef in ipairs(CURRENCIES) do
    table.insert(CATEGORIES, {
        name = "CURRENCY_" .. (type(currencyDef.id) == "string" and currencyDef.id:upper() or currencyDef.id),
        label = currencyDef.label,
        type = "currency",
        id = currencyDef.id,
        icon = currencyDef.icon
    })
end

-- Character data collection
local function GetCurrentCharacterGUID()
    return UnitGUID("player")
end

function sfui.alts.SyncCurrentCharacter()
    local guid = GetCurrentCharacterGUID()
    if not guid then return end

    SfuiDB.alts = SfuiDB.alts or {}
    SfuiDB.alts[guid] = SfuiDB.alts[guid] or {}
    local data = SfuiDB.alts[guid]

    local name, realm = UnitName("player")
    data.name = name
    data.realm = realm or GetRealmName()

    local _, class = UnitClass("player")
    data.class = class

    local _, race = UnitRace("player")
    data.race = race

    data.level = UnitLevel("player")

    local _, avgItemLevelEquipped = GetAverageItemLevel()
    data.iLvl = avgItemLevelEquipped

    data.lastUpdate = GetServerTime()

    -- Mythic+ Rating and Keystone
    local rating = C_ChallengeMode.GetOverallDungeonScore()
    data.rating = rating

    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    if mapID and level then
        data.keystone = { mapID = mapID, level = level }
    end

    -- Great Vault Progress
    data.vault = data.vault or {}
    local activities = C_WeeklyRewards.GetActivities()
    data.vault.raid = {}
    data.vault.dungeon = {}
    data.vault.world = {}

    for _, activity in ipairs(activities) do
        local group = "world"
        if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
            group = "raid"
        elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
            group = "dungeon"
        end

        if activity.index >= 1 and activity.index <= 3 then
            data.vault[group][activity.index] = {
                progress = activity.progress or 0,
                threshold = activity.threshold or 0,
                level = activity.level or 0
            }
        end
    end

    -- Raid Progress (Boss Kills)
    data.raids = data.raids or {}
    local difficulties = { 14, 15, 16 } -- Normal, Heroic, Mythic
    for _, diff in ipairs(difficulties) do
        data.raids[diff] = {}
    end

    local numSaved = GetNumSavedInstances()
    for i = 1, numSaved do
        local name, _, _, difficulty, _, _, _, _, _, _, numEncounters = GetSavedInstanceInfo(i)
        -- Only track difficulties 14, 15, 16 (Normal, Heroic, Mythic)
        if difficulty >= 14 and difficulty <= 16 then
            for q = 1, numEncounters do
                local _, _, isKilled = GetSavedInstanceEncounterInfo(i, q)
                data.raids[difficulty][q] = isKilled
            end
        end
    end

    -- PvP and Expansion Currencies
    data.currencies = data.currencies or {}
    for _, currencyDef in ipairs(CURRENCIES) do
        local key = currencyDef.id
        if type(key) == "number" then
            -- Vault Tokens (248242) are items, not currencies in the C_CurrencyInfo sense
            if key == 248242 then
                local count = C_Item.GetItemCount(key, true) or 0
                data.currencies[key] = count
            else
                local info = C_CurrencyInfo.GetCurrencyInfo(key)
                if info then data.currencies[key] = info.quantity end
            end
        end
    end

    -- Prey tracking (Midnight expansion)
    data.prey = data.prey or {}

    -- Season 1 Progress (ID 2764 from HomeworkTracker)
    local progInfo = C_MajorFactions.GetMajorFactionData(2764)
    if progInfo then
        data.prey.rank = progInfo.renownLevel
        if progInfo.renownLevelThreshold and progInfo.renownLevelThreshold > 0 then
            data.prey.rankProgress = math.floor((progInfo.renownReputationEarned or 0) / progInfo.renownLevelThreshold *
                100)
        else
            data.prey.rankProgress = 0
        end
    end

    -- Weekly Hunts (x/4) using specific completion quest IDs for Midnight Prey
    local huntQuests = {
        -- Normal
        91098, 91099, 91096, 91104, 91105, 91106, 91107, 91108, 91109, 91110,
        91111, 91112, 91113, 91114, 91115, 91116, 91117, 91118, 91119, 91120,
        91121, 91122, 91123, 91124, 91095, 91097, 91100, 91101, 91102, 91103,
        -- Hard
        91210, 91212, 91214, 91216, 91218, 91220, 91222, 91224, 91226, 91228,
        91230, 91232, 91234, 91236, 91238, 91240, 91242, 91243, 91244, 91245,
        91246, 91247, 91248, 91249, 91250, 91251, 91252, 91253, 91254, 91255,
        -- Nightmare
        91211, 91213, 91215, 91217, 91219, 91221, 91223, 91225, 91227, 91229,
        91231, 91233, 91235, 91237, 91239, 91241, 91256, 91257, 91258, 91259,
        91260, 91261, 91262, 91263, 91264, 91265, 91266, 91267, 91268, 91269
    }
    local weeklyHunts = 0
    for _, qID in ipairs(huntQuests) do
        if C_QuestLog.IsQuestFlaggedCompleted(qID) then
            weeklyHunts = weeklyHunts + 1
        end
    end
    data.prey.weekly = weeklyHunts

    -- Active Hunt Progress using Remnant of Anguish (ID 3392)
    local remnants = C_CurrencyInfo.GetCurrencyInfo(3392)
    if remnants and remnants.quantity then
        data.prey.activeHuntProgress = remnants.quantity
    else
        data.prey.activeHuntProgress = 0
    end

    -- Active Hunt Quests
    local questID = C_QuestLog.GetActivePreyQuest()
    if questID then
        data.prey.title = C_QuestLog.GetTitleForQuestID(questID)
        data.prey.activeHuntProgress = C_TaskQuest.GetQuestProgressBarInfo(questID) or 0
    end

    data.prey.lastUpdate = GetServerTime()
end

-- Confirmation Dialog for Removing Characters
StaticPopupDialogs["SFUI_ALTS_REMOVE_CHARACTER"] = {
    text =
    "Are you sure you want to remove |cff9966ff%s|r from the Alts list? This will delete all saved data for this character.",
    button1 = "Remove",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if SfuiDB.alts and data.guid then
            SfuiDB.alts[data.guid] = nil
            sfui.alts.UpdateUI()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- UI Implementation
local frame = nil

function sfui.alts.CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "SfuiAltsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(cfg.width, cfg.height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(cfg.backdropColor))
    frame:SetBackdropBorderColor(unpack(cfg.borderColor))

    local CreateFlatButton = sfui.common.create_flat_button

    local close = CreateFlatButton(frame, "X", 24, 24)
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Sidebar for row labels
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 10, -35)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(140)
    frame.sidebar = sidebar

    local y = 0
    for _, cat in ipairs(CATEGORIES) do
        local row = CreateFrame("Frame", nil, sidebar)
        row:SetSize(140, cfg.rowHeight)
        row:SetPoint("TOPLEFT", 0, -y)

        local text = row:CreateFontString(nil, "OVERLAY",
            cat.type == "header" and "GameFontNormal" or "GameFontHighlightSmall")
        text:SetPoint("LEFT", 5, 0)
        text:SetText(cat.label)
        if cat.type == "header" then
            text:SetTextColor(0.4, 0, 1) -- Purple
        end

        y = y + cfg.rowHeight
    end

    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    frame.content:SetPoint("BOTTOMRIGHT", -10, 0)

    frame:Hide()
    return frame
end

function sfui.alts.Toggle()
    if not frame then sfui.alts.CreateFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        sfui.alts.UpdateUI()
        frame:Show()
    end
end

function sfui.alts.UpdateUI()
    if not frame then return end

    -- Clear previous content
    local children = { frame.content:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide(); child:SetParent(nil)
    end

    local alts = {}
    for guid, data in pairs(SfuiDB.alts) do
        table.insert(alts, { guid = guid, data = data })
    end

    table.sort(alts, function(a, b)
        if a.data.level ~= b.data.level then return a.data.level > b.data.level end
        return a.data.name < b.data.name
    end)

    local xOffset = 0
    for i, alt in ipairs(alts) do
        local col = CreateFrame("Frame", nil, frame.content)
        col:SetSize(cfg.columnWidth, #CATEGORIES * cfg.rowHeight)
        col:SetPoint("TOPLEFT", xOffset, 0)

        local classColor = RAID_CLASS_COLORS[alt.data.class] or NORMAL_FONT_COLOR

        local y = 0
        for _, cat in ipairs(CATEGORIES) do
            local cell = CreateFrame("Frame", nil, col)
            cell:SetSize(cfg.columnWidth, cfg.rowHeight)
            cell:SetPoint("TOPLEFT", 0, -y)

            local text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("CENTER")

            if cat.type == "header" then
                if cat.name == "GENERAL" then
                    text:SetFontObject("GameFontNormal")
                    text:SetText(alt.data.name)
                    text:SetTextColor(classColor.r, classColor.g, classColor.b)

                    -- Remove Button on Character Header
                    cell:EnableMouse(true)
                    local del = CreateFrame("Button", nil, cell)
                    del:SetSize(12, 12)
                    del:SetPoint("TOPRIGHT", -2, -2)
                    del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                    del:SetScript("OnClick", function()
                        StaticPopup_Show("SFUI_ALTS_REMOVE_CHARACTER", alt.data.name, nil, { guid = alt.guid })
                    end)
                    del:Hide()
                    cell:SetScript("OnEnter", function() del:Show() end)
                    cell:SetScript("OnLeave", function() del:Hide() end)
                else
                    -- Divider underline
                    local line = cell:CreateTexture(nil, "BACKGROUND")
                    line:SetHeight(1)
                    line:SetPoint("LEFT", 5, -5)
                    line:SetPoint("RIGHT", -5, -5)
                    line:SetColorTexture(0.2, 0.2, 0.2, 0.5)
                end
            elseif cat.type == "stat" then
                local val = alt.data[cat.key] or 0
                if cat.key == "iLvl" and (alt.data.level or 0) < 90 then
                    text:SetText(alt.data.level or "-")
                    text:SetTextColor(1, 1, 1) -- White for level
                else
                    text:SetText(cat.format and string.format(cat.format, val) or val)
                    if cat.key == "rating" and val > 0 then
                        local color = C_ChallengeMode.GetDungeonScoreRarityColor(val)
                        if color then
                            text:SetTextColor(color.r, color.g, color.b)
                        end
                    end
                end
            elseif cat.type == "keystone" then
                if alt.data.keystone then
                    text:SetText(string.format("%d", alt.data.keystone.level))
                    local color = C_ChallengeMode.GetKeystoneLevelRarityColor(alt.data.keystone.level)
                    if color then
                        text:SetTextColor(color.r, color.g, color.b)
                    else
                        text:SetTextColor(1, 1, 1)
                    end
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            elseif cat.type == "prey" then
                if alt.data.prey then
                    local weekly = alt.data.prey.weekly or 0
                    local activeProgress = alt.data.prey.activeHuntProgress or 0
                    local rank = alt.data.prey.rank or 1
                    local rankProgress = alt.data.prey.rankProgress or 0

                    -- Show Weekly Hunts (x/4) and overall Rank progress
                    text:SetText(string.format("%d/4 |cff9966ffR%d|r (%d%%)", weekly, rank, rankProgress))

                    if weekly >= 4 then
                        text:SetTextColor(0, 1, 0) -- Completed weekly goal
                    elseif activeProgress >= 100 then
                        text:SetTextColor(1, 0, 1) -- Ready for confrontation
                    else
                        text:SetTextColor(0, 1, 1)
                    end
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            elseif cat.type == "dungeon" then
                -- Search vault or M+ score for this mapID
                -- Simplifying for now: just showing a dot if any score exists
                text:SetText("-")
                text:SetTextColor(0.5, 0.5, 0.5)
            elseif cat.type == "currency" then
                local val = alt.data.currencies[cat.id] or 0
                local displayVal
                displayVal = val >= 1000 and string.format("%.1fK", val / 1000) or val
                text:SetText(string.format("|T%d:12:12:0:0|t %s", cat.icon, displayVal))

                -- Add tooltip for currency
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if cat.id == 248242 then
                        GameTooltip:SetItemByID(cat.id)
                    else
                        GameTooltip:SetCurrencyByID(cat.id)
                    end
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            elseif cat.type == "vault_row" then
                text:Hide()
                local group = cat.group
                local squareSize = (cfg.columnWidth - 10) / 3
                for slotIdx = 1, 3 do
                    local rect = cell:CreateTexture(nil, "ARTWORK")
                    rect:SetSize(squareSize - 4, cfg.rowHeight - 6)
                    local xPos = (slotIdx - 1) * squareSize + 5
                    rect:SetPoint("LEFT", xPos, 0)

                    local slotData = alt.data.vault and alt.data.vault[group] and alt.data.vault[group][slotIdx]
                    if slotData and slotData.progress >= slotData.threshold and slotData.threshold > 0 then
                        local level = slotData.level or 0
                        local color = C_ChallengeMode.GetKeystoneLevelRarityColor(level)
                        if color and level > 0 then
                            rect:SetColorTexture(color.r, color.g, color.b, 0.8)
                        else
                            rect:SetColorTexture(0, 1, 1, 0.8) -- Default Teal
                        end
                    else
                        rect:SetColorTexture(0, 0, 0, 0.5) -- Black (Not completed)
                    end
                end
            elseif cat.type == "raid_grid" then
                text:Hide()
                local diff = cat.difficulty
                local bossData = alt.data.raids and alt.data.raids[diff]
                local numBosses = 8 -- Hardcoded for current raid context
                local squareSize = (cfg.columnWidth - 10) / numBosses

                local r, g, b = 0.2, 0.2, 0.2  -- Default blackish
                if diff == 16 then
                    r, g, b = 0.64, 0.21, 0.93 -- Mythic Purple
                elseif diff == 15 then
                    r, g, b = 0, 0.44, 0.87    -- Heroic Blue
                elseif diff == 14 then
                    r, g, b = 0.12, 1, 0       -- Normal Green
                end

                for bIdx = 1, numBosses do
                    local rect = cell:CreateTexture(nil, "ARTWORK")
                    rect:SetSize(squareSize - 2, cfg.rowHeight - 6)
                    rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

                    if bossData and bossData[bIdx] then
                        rect:SetColorTexture(r, g, b, 0.8)
                    else
                        rect:SetColorTexture(0, 0, 0, 0.5)
                    end
                end
            end

            y = y + cfg.rowHeight
        end

        xOffset = xOffset + cfg.columnWidth
    end

    -- Adjust frame size to fit content
    local totalWidth = 140 + 20 + xOffset + 10                  -- sidebar + padding + columns + padding
    local totalHeight = 35 + (#CATEGORIES * cfg.rowHeight) + 10 -- padding + rows + padding
    frame:SetSize(totalWidth, totalHeight)
end

function sfui.alts.initialize()
    sfui.alts.SyncCurrentCharacter()

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")

    eventFrame:SetScript("OnEvent", function(self, event)
        sfui.alts.SyncCurrentCharacter()
    end)

    SlashCmdList["SFUIALTS"] = function() sfui.alts.Toggle() end
    SLASH_SFUIALTS1 = "/alts"
end
