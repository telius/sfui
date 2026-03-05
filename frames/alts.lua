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
local table = table
local wipe = wipe
local C_Timer = C_Timer

-- Configuration & Data Tables
local CATEGORIES = {}
local CURRENCIES = {
    { id = 3383, label = "Adventurer", icon = 7639517 }, -- Adventurer's Dawncrest
    { id = 3341, label = "Veteran",    icon = 7639525 }, -- Veteran Dawncrest
    { id = 3343, label = "Champ",      icon = 7639519 }, -- Champion Dawncrest
    { id = 3345, label = "Hero",       icon = 7639521 }, -- Hero Dawncrest
    { id = 3347, label = "Myth",       icon = 7639523 }, -- Gilded Dawncrest
    { id = 3212, label = "Spark",      icon = 7551418 }, -- Spark of Fortune
    { id = 3378, label = "Catalyst",   icon = 4622294 }, -- Catalyst Charges
}

local BASE_CATEGORIES = {
    { name = "GENERAL",       label = "Character",     type = "header" },
    { name = "ILVL",          label = "Level / iLvl",  type = "stat",      key = "iLvl",     format = "%.1f" },
    { name = "RATING",        label = "M+ Rating",     type = "stat",      key = "rating" },
    { name = "KEystone",      label = "Current Key",   type = "keystone" },

    { name = "PREY_HEADER",   label = "Prey Hunt",     type = "header" },
    { name = "PREY",          label = "Hunt Progress", type = "prey" },

    { name = "VAULT_HEADER",  label = "Great Vault",   type = "header" },
    { name = "VAULT_RAID",    label = "Raid",          type = "vault_row", group = "raid" },
    { name = "VAULT_DUNGEON", label = "Dungeon",       type = "vault_row", group = "dungeon" },
    { name = "VAULT_WORLD",   label = "World/Delve",   type = "vault_row", group = "world" },

    { name = "RAID_HEADER",   label = "Raid Progress", type = "header" },
    { name = "RAID_M",        label = "Mythic",        type = "raid_grid", difficulty = 16 },
    { name = "RAID_H",        label = "Heroic",        type = "raid_grid", difficulty = 15 },
    { name = "RAID_N",        label = "Normal",        type = "raid_grid", difficulty = 14 },
}

function sfui.alts.RefreshDynamicCategories()
    -- Initialize with base categories
    wipe(CATEGORIES)
    for i, cat in ipairs(BASE_CATEGORIES) do
        CATEGORIES[i] = cat
    end

    -- Add Dungeons dynamically
    local maps = C_ChallengeMode.GetMapTable()
    if maps and #maps > 0 then
        table.insert(CATEGORIES, { name = "DUNGEONS_HEADER", label = "Dungeons", type = "header" })
        table.insert(CATEGORIES, { name = "M0_GRID", label = "Mythic 0", type = "m0_grid" })
        for _, mapID in ipairs(maps) do
            local name = C_ChallengeMode.GetMapUIInfo(mapID)
            if name then
                table.insert(CATEGORIES, {
                    name = "DUNGEON_" .. mapID,
                    label = name,
                    type = "dungeon",
                    mapID = mapID
                })
            end
        end
    end

    -- Add Currencies from hardcoded list
    table.insert(CATEGORIES, { name = "CURRENCY_HEADER", label = "Currency", type = "header" })
    for _, currencyDef in ipairs(CURRENCIES) do
        table.insert(CATEGORIES, {
            name = "CURRENCY_" .. currencyDef.id,
            label = currencyDef.label,
            type = "currency",
            id = currencyDef.id,
            icon = currencyDef.icon
        })
    end
end

-- Frame Pooling
local columnPool = {}
local cellPool = {}

local function AcquireColumn(parent)
    local f = table.remove(columnPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
    else
        f:SetParent(parent)
        f:Show()
    end
    return f
end

local function ReleaseColumn(f)
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    table.insert(columnPool, f)
end

local function AcquireCell(parent)
    local f = table.remove(cellPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("CENTER")
    else
        f:SetParent(parent)
        f:Show()
        if f.text then
            f.text:Show()
            f.text:SetText("")
            f.text:SetTextColor(1, 1, 1)
            f.text:SetFontObject("GameFontHighlightSmall")
            f.text:SetPoint("CENTER")
        end
        -- Hide any extra textures/buttons that might have been added
        local regions = { f:GetRegions() }
        for _, r in ipairs(regions) do
            if r:IsObjectType("Texture") then r:Hide() end
        end
        local children = { f:GetChildren() }
        for _, c in ipairs(children) do
            c:Hide()
        end
    end
    return f
end

local function ReleaseCell(f)
    f:Hide()
    f:SetParent(nil)
    f:ClearAllPoints()
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    table.insert(cellPool, f)
end

-- Character data collection
local function GetCurrentCharacterGUID()
    return UnitGUID("player")
end

local syncTimer = nil
local needsSync = false

function sfui.alts.SyncCurrentCharacter()
    if InCombatLockdown() then
        needsSync = true
        return
    end

    if syncTimer then return end
    syncTimer = C_Timer.After(1.0, function()
        syncTimer = nil
        sfui.alts.PerformSync()
    end)
end

function sfui.alts.PerformSync()
    sfui.alts.RefreshDynamicCategories()
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

    -- Mythic+ Dungeon Best Scores
    data.dungeons = data.dungeons or {}
    data.m0 = data.m0 or {}
    local maps = C_ChallengeMode.GetMapTable()
    local m0Maps = { 557, 558, 559, 560, 561, 562, 563, 564 } -- MIDNIGHT S1 PRESEASON OVERRIDE

    local seasonDungeonNames = {}
    if maps and #maps > 0 then
        for _, mID in ipairs(maps) do
            local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mID)
            local bestLevel = 0
            if intimeInfo then bestLevel = intimeInfo.level end
            if overtimeInfo and overtimeInfo.level > bestLevel then bestLevel = overtimeInfo.level end

            data.dungeons[mID] = { level = bestLevel }
        end
    end

    -- Cross-reference current expansion M0s using Encounter Journal
    local currentTier = EJ_GetCurrentTier()
    EJ_SelectTier(currentTier)
    local ejNames = {}
    local index = 1
    while true do
        local instanceID, name = EJ_GetInstanceByIndex(index, false)
        if not instanceID then break end
        ejNames[name] = instanceID
        data.m0[instanceID] = false -- Default available
        index = index + 1
    end

    -- M0 Lockouts
    local numSaved = GetNumSavedInstances()
    for i = 1, numSaved do
        local name, _, _, difficulty, locked, _, _, isRaid = GetSavedInstanceInfo(i)
        if difficulty == 23 and locked and not isRaid then
            local instanceID = ejNames[name]
            if instanceID then
                data.m0[instanceID] = true
            end
        end
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
        if currencyDef.id == 248242 then -- Vault Tokens are items, not currencies in C_CurrencyInfo
            local count = C_Item.GetItemCount(currencyDef.id, true) or 0
            data.currencies[currencyDef.id] = count
        else
            local info = C_CurrencyInfo.GetCurrencyInfo(currencyDef.id)
            if info then
                data.currencies[currencyDef.id] = {
                    val = info.quantity,
                    earned = info.quantityEarnedThisWeek,
                    max = info.maxWeeklyQuantity,
                    maxQuantity = info.maxQuantity,
                    totalEarned = info.totalEarned,
                    useTotalEarned = info.useTotalEarnedForMaxQty
                }
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
    local huntNormal = {
        91098, 91099, 91096, 91104, 91105, 91106, 91107, 91108, 91109, 91110,
        91111, 91112, 91113, 91114, 91115, 91116, 91117, 91118, 91119, 91120,
        91121, 91122, 91123, 91124, 91095, 91097, 91100, 91101, 91102, 91103
    }
    local huntHard = {
        91210, 91212, 91214, 91216, 91218, 91220, 91222, 91224, 91226, 91228,
        91230, 91232, 91234, 91236, 91238, 91240, 91242, 91243, 91244, 91245,
        91246, 91247, 91248, 91249, 91250, 91251, 91252, 91253, 91254, 91255
    }
    local huntMythic = {
        91211, 91213, 91215, 91217, 91219, 91221, 91223, 91225, 91227, 91229,
        91231, 91233, 91235, 91237, 91239, 91241, 91256, 91257, 91258, 91259,
        91260, 91261, 91262, 91263, 91264, 91265, 91266, 91267, 91268, 91269
    }

    data.prey.normal = 0
    data.prey.hard = 0
    data.prey.mythic = 0
    for _, qID in ipairs(huntNormal) do
        if C_QuestLog.IsQuestFlaggedCompleted(qID) then
            data.prey.normal = data.prey
                .normal + 1
        end
    end
    for _, qID in ipairs(huntHard) do if C_QuestLog.IsQuestFlaggedCompleted(qID) then data.prey.hard = data.prey.hard + 1 end end
    for _, qID in ipairs(huntMythic) do
        if C_QuestLog.IsQuestFlaggedCompleted(qID) then
            data.prey.mythic = data.prey
                .mythic + 1
        end
    end
    data.prey.weekly = data.prey.normal + data.prey.hard + data.prey.mythic
    -- Active Hunt Progress using Remnant of Anguish (ID 3392)
    local remnants = C_CurrencyInfo.GetCurrencyInfo(3392)
    if remnants and remnants.quantity then
        data.prey.activeHuntProgress = remnants.quantity
    else
        data.prey.activeHuntProgress = 0
    end

    -- Active Hunt Quests
    local questID = C_QuestLog.GetActivePreyQuest()
    data.prey.isQuestActive = false
    if questID then
        data.prey.title = C_QuestLog.GetTitleForQuestID(questID)
        data.prey.activeHuntProgress = C_TaskQuest.GetQuestProgressBarInfo(questID) or 0
        data.prey.isQuestActive = true
    end

    data.prey.lastUpdate = GetServerTime()

    if frame and frame:IsVisible() then
        sfui.alts.UpdateUI(true)
    end
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
    frame:SetFrameStrata("DIALOG")
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

    -- Sort Dropdown
    local sortOptions = {
        { text = "Name (A-Z)", value = "name" },
        { text = "Item Level", value = "ilvl" },
        { text = "M+ Rating",  value = "rating" },
    }
    local sortDropdown = sfui.common.create_dropdown(frame, 24, sortOptions, function(val)
        SfuiDB.altsSort = val
        sfui.alts.UpdateUI()
    end, SfuiDB.altsSort or "name", "≣")
    sortDropdown:SetPoint("TOPRIGHT", close, "TOPLEFT", -5, 0)

    -- Character Manager Dropdown
    local function populateManagerOptions()
        local options = {}
        for guid, data in pairs(SfuiDB.alts) do
            table.insert(options, {
                guid = guid,
                data = data,
                keepOpen = true,
                onRender = function(parent, opt)
                    local name = opt.data.name or "Unknown"
                    local classColor = RAID_CLASS_COLORS[opt.data.class] or NORMAL_FONT_COLOR

                    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    t:SetPoint("LEFT", 5, 0)
                    t:SetText(string.format("|c%s%s|r", classColor.colorStr, name))

                    -- Remove button [X]
                    local xBtn = sfui.common.create_flat_button(parent, "X", 18, 16)
                    xBtn:SetPoint("RIGHT", -5, 0)
                    xBtn:SetScript("OnClick", function()
                        StaticPopup_Show("SFUI_ALTS_REMOVE_CHARACTER", name, nil, { guid = opt.guid })
                    end)

                    -- Hide button [H]
                    local hStatus = opt.data.isHidden and "|cff00ff00H|r" or "|cffccccccH|r"
                    local hBtn = sfui.common.create_flat_button(parent, hStatus, 18, 16)
                    hBtn:SetPoint("RIGHT", xBtn, "LEFT", -2, 0)
                    hBtn:SetScript("OnClick", function()
                        opt.data.isHidden = not opt.data.isHidden
                        sfui.alts.UpdateUI()
                        hBtn:GetFontString():SetText(opt.data.isHidden and "|cff00ff00H|r" or "|cffccccccH|r")
                    end)
                end
            })
        end
        return options
    end

    local managerDropdown = sfui.common.create_dropdown(frame, 24, populateManagerOptions, nil, nil, "=", 200)
    managerDropdown:SetPoint("RIGHT", sortDropdown, "LEFT", -5, 0)

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

function sfui.alts.UpdateUI(force)
    if not frame or (not force and not frame:IsVisible()) then return end

    -- Release existing content to pools
    if not frame.content then return end
    local columns = { frame.content:GetChildren() }
    for _, col in ipairs(columns) do
        local cells = { col:GetChildren() }
        for _, cell in ipairs(cells) do
            ReleaseCell(cell)
        end
        ReleaseColumn(col)
    end

    local alts = {}
    for guid, data in pairs(SfuiDB.alts) do
        if not data.isHidden then
            table.insert(alts, { guid = guid, data = data })
        end
    end

    local sortMethod = SfuiDB.altsSort or "name"
    table.sort(alts, function(a, b)
        if sortMethod == "ilvl" then
            local aLevel = a.data.level or 0
            local bLevel = b.data.level or 0
            local aILvl = a.data.iLvl or 0
            local bILvl = b.data.iLvl or 0

            -- Sort by Level first if one is not max (90)
            if aLevel ~= bLevel then
                return aLevel > bLevel
            end

            -- If both same level, sort by iLvl
            if aILvl ~= bILvl then
                return aILvl > bILvl
            end
        elseif sortMethod == "rating" then
            local aRating = a.data.rating or 0
            local bRating = b.data.rating or 0
            if aRating ~= bRating then
                return aRating > bRating
            end
        end

        -- Fallback to Name (A-Z)
        return (a.data.name or "") < (b.data.name or "")
    end)

    local xOffset = 0
    for i, alt in ipairs(alts) do
        local col = AcquireColumn(frame.content)
        col:SetSize(cfg.columnWidth, #CATEGORIES * cfg.rowHeight)
        col:SetPoint("TOPLEFT", xOffset, 0)

        local classColor = RAID_CLASS_COLORS[alt.data.class] or NORMAL_FONT_COLOR

        local y = 0
        for _, cat in ipairs(CATEGORIES) do
            local cell = AcquireCell(col)
            cell:SetSize(cfg.columnWidth, cfg.rowHeight)
            cell:SetPoint("TOPLEFT", 0, -y)

            local text = cell.text
            text:Show()

            if cat.type == "header" then
                if cat.name == "GENERAL" then
                    text:SetFontObject("GameFontNormal")
                    text:SetText(alt.data.name)
                    text:SetTextColor(classColor.r, classColor.g, classColor.b)

                    -- Remove Button on Character Header
                    cell:EnableMouse(true)
                    local del = cell.del or CreateFrame("Button", nil, cell)
                    cell.del = del
                    del:Show()
                    del:SetSize(14, 14)
                    del:SetPoint("TOPRIGHT", -2, -2)
                    del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                    del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
                    del:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")

                    del:SetScript("OnClick", function()
                        alt.data.isHidden = true
                        sfui.alts.UpdateUI()
                    end)

                    -- Always visible but low alpha until hover
                    del:SetAlpha(0.2)
                    local function onEnter() del:SetAlpha(1) end
                    local function onLeave() del:SetAlpha(0.2) end
                    cell:SetScript("OnEnter", onEnter)
                    cell:SetScript("OnLeave", onLeave)
                    del:SetScript("OnEnter", onEnter)
                    del:SetScript("OnLeave", onLeave)
                else
                    text:Hide()
                    -- Divider underline
                    local line = cell.line or cell:CreateTexture(nil, "BACKGROUND")
                    cell.line = line
                    line:Show()
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
                    if alt.data.keystone.level >= 12 then
                        text:SetTextColor(1, 0.5, 0) -- Orange for 12+
                    elseif color then
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
                    local normal = alt.data.prey.normal or 0
                    local hard = alt.data.prey.hard or 0
                    local mythic = alt.data.prey.mythic or 0
                    local activeProgress = alt.data.prey.activeHuntProgress or 0
                    local isQuestActive = alt.data.prey.isQuestActive
                    local rank = alt.data.prey.rank or 1
                    local rankProgress = alt.data.prey.rankProgress or 0

                    local progressStr = isQuestActive and string.format("%d%%", activeProgress) or
                        tostring(activeProgress)
                    text:SetText(string.format("%d/%d/%d (%s)", normal, hard, mythic, progressStr))

                    if (normal + hard + mythic) >= 4 then
                        text:SetTextColor(0, 1, 0) -- Completed weekly goal (at least 4 hunts of any diff)
                    elseif isQuestActive and activeProgress >= 100 then
                        text:SetTextColor(1, 0, 1) -- Ready for confrontation
                    else
                        text:SetTextColor(0, 1, 1)
                    end

                    -- Add tooltip for more details
                    cell:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Prey Hunt Progress")
                        GameTooltip:AddDoubleLine("Normal:", string.format("%d / 4", normal), 1, 1, 1, 1, 1, 1)
                        GameTooltip:AddDoubleLine("Hard:", string.format("%d / 4", hard), 1, 1, 1, 1, 1, 1)
                        GameTooltip:AddDoubleLine("Mythic:", string.format("%d / 4", mythic), 1, 1, 1, 1, 1, 1)
                        if alt.data.prey.title then
                            GameTooltip:AddDoubleLine("Active Hunt:", alt.data.prey.title, 1, 1, 1, 1, 1, 1)
                        end
                        GameTooltip:AddDoubleLine(isQuestActive and "Hunt Progress:" or "Remnants of Anguish:",
                            progressStr, 1, 1, 1, 1, 1, 1)
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine("Renown Rank:", string.format("%d (%d%%)", rank, rankProgress), 1, 1,
                            1, 1, 1, 1)
                        GameTooltip:Show()
                    end)
                    cell:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            elseif cat.type == "dungeon" then
                local best = alt.data.dungeons and alt.data.dungeons[cat.mapID]
                if best and best.level > 0 then
                    text:SetText(tostring(best.level))
                    local color = C_ChallengeMode.GetKeystoneLevelRarityColor(best.level)
                    if best.level >= 12 then
                        text:SetTextColor(1, 0.5, 0) -- Orange for 12+
                    elseif color then
                        text:SetTextColor(color.r, color.g, color.b)
                    end
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            elseif cat.type == "currency" then
                local cData = alt.data.currencies[cat.id]
                local val = cData and (type(cData) == "table" and cData.val or cData) or 0
                local displayVal
                if val >= 1000 then
                    displayVal = string.format("%.1fk", val / 1000)
                else
                    displayVal = tostring(val)
                end
                text:SetText(string.format("|T%d:12:12:0:0|t %s", cat.icon, displayVal))

                -- Check weekly cap
                local isCapped = false
                if cData and type(cData) == "table" then
                    if cData.max and cData.max > 0 and cData.earned and cData.earned >= cData.max then
                        isCapped = true
                    elseif cData.maxQuantity and cData.maxQuantity > 0 then
                        if cData.useTotalEarned and cData.totalEarned and cData.totalEarned >= cData.maxQuantity then
                            isCapped = true
                        elseif not cData.useTotalEarned and cData.val and cData.val >= cData.maxQuantity then
                            isCapped = true
                        end
                    end
                end

                if isCapped then
                    text:SetTextColor(1, 0, 0) -- Red when maxed
                else
                    text:SetTextColor(1, 1, 1) -- White
                end

                -- Add tooltip for currency
                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if cat.id == 248242 then
                        GameTooltip:SetItemByID(cat.id)
                    else
                        GameTooltip:SetCurrencyByID(cat.id)
                        -- Add weekly progress info
                        if cData and type(cData) == "table" then
                            GameTooltip:AddLine(" ")
                            if cData.max and cData.max > 0 then
                                GameTooltip:AddDoubleLine("Weekly Earned:",
                                    string.format("%d / %d", cData.earned or 0, cData.max), 1, 1, 1, 1, 1, 1)
                            elseif cData.maxQuantity and cData.maxQuantity > 0 then
                                local currentAmount = cData.useTotalEarned and cData.totalEarned or cData.val
                                GameTooltip:AddDoubleLine("Season Earned:",
                                    string.format("%d / %d", currentAmount or 0, cData.maxQuantity), 1, 1, 1, 1, 1, 1)
                            end
                            if isCapped then
                                GameTooltip:AddLine("Season/Weekly cap reached!", 1, 0, 0)
                            end
                        end
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
                    local rect = cell["rect" .. slotIdx] or cell:CreateTexture(nil, "ARTWORK")
                    cell["rect" .. slotIdx] = rect
                    rect:Show()
                    rect:SetSize(squareSize - 4, cfg.rowHeight - 12)
                    rect:SetPoint("LEFT", (slotIdx - 1) * squareSize + 5, 0)

                    local vData = alt.data.vault and alt.data.vault[group] and alt.data.vault[group][slotIdx]
                    if vData and vData.progress >= vData.threshold and vData.threshold > 0 then
                        rect:SetColorTexture(0, 1, 0, 0.8)       -- Green
                    else
                        rect:SetColorTexture(0.2, 0.2, 0.2, 0.5) -- Gray
                    end
                end

                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Great Vault: " .. cat.label)
                    local vGroup = alt.data.vault and alt.data.vault[group]
                    for idx = 1, 3 do
                        local v = vGroup and vGroup[idx]
                        if v and v.threshold > 0 then
                            local status = v.progress >= v.threshold and "|cff00ff00Unlocked|r" or
                                string.format("%d/%d", v.progress, v.threshold)
                            local levelStr = v.level > 0 and string.format(" (Level: %d)", v.level) or ""
                            GameTooltip:AddDoubleLine("Slot " .. idx .. ":", status .. levelStr, 1, 1, 1, 1, 1, 1)
                        end
                    end
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            elseif cat.type == "m0_grid" then
                text:Hide()
                local m0Data = alt.data.m0

                -- Dynamic Encounter Journal query for M0s
                local currentTier = EJ_GetCurrentTier()
                EJ_SelectTier(currentTier)
                local ejInstances = {}
                local index = 1
                while true do
                    local instanceID, name = EJ_GetInstanceByIndex(index, false)
                    if not instanceID then break end
                    table.insert(ejInstances, { id = instanceID, name = name })
                    index = index + 1
                end

                local numDungeons = #ejInstances > 0 and #ejInstances or 8
                local squareSize = (cfg.columnWidth - 10) / numDungeons

                for bIdx, inst in ipairs(ejInstances) do
                    local rect = cell["m0Rect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
                    cell["m0Rect" .. bIdx] = rect
                    rect:Show()
                    rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
                    rect:SetPoint("LEFT", (bIdx - 1) * squareSize + 5, 0)

                    if m0Data and m0Data[inst.id] then
                        rect:SetColorTexture(0, 1, 1, 0.8) -- #00ffff completed
                    else
                        rect:SetColorTexture(0, 0, 0, 0.5) -- black (available)
                    end
                end

                cell:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Mythic 0 Lockouts")
                    for _, inst in ipairs(ejInstances) do
                        local isLocked = m0Data and m0Data[inst.id]
                        local status = isLocked and "|cff00ffffCompleted|r" or "|cff888888Available|r"
                        GameTooltip:AddDoubleLine(inst.name, status, 1, 1, 1, 1, 1, 1)
                    end
                    GameTooltip:Show()
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            elseif cat.type == "raid_grid" then
                text:Hide()
                local difficulty = cat.difficulty
                local bossData = alt.data.raids and alt.data.raids[difficulty]
                local numBosses = 8 -- Hardcoded for current raid context
                local squareSize = (cfg.columnWidth - 10) / numBosses

                local r, g, b = 1, 0.8, 0      -- Default gold
                if difficulty == 16 then
                    r, g, b = 0.64, 0.21, 0.93 -- Mythic Purple
                elseif difficulty == 15 then
                    r, g, b = 0, 0.44, 1       -- Heroic Blue
                elseif difficulty == 14 then
                    r, g, b = 0.12, 1, 0       -- Normal Green
                end

                for bIdx = 1, numBosses do
                    local rect = cell["raidRect" .. bIdx] or cell:CreateTexture(nil, "ARTWORK")
                    cell["raidRect" .. bIdx] = rect
                    rect:Show()
                    rect:SetSize(squareSize - 2, cfg.rowHeight - 12)
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

function sfui.alts.Toggle()
    sfui.alts.RefreshDynamicCategories()
    if not frame then
        frame = sfui.alts.CreateFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.initialize()
    sfui.alts.RefreshDynamicCategories()
    sfui.alts.SyncCurrentCharacter()

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    eventFrame:RegisterEvent("UPDATE_UI_WIDGET")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if needsSync then
                needsSync = false
                sfui.alts.SyncCurrentCharacter()
            end
        else
            sfui.alts.SyncCurrentCharacter()
        end
    end)

    SlashCmdList["SFUIALTS"] = function() sfui.alts.Toggle() end
    SLASH_SFUIALTS1 = "/alts"
end
