--[[
    SFUI Tracker Module: Camelot Character Skills (Weapons, Professions, Secondary)
    frames/quests/modules/q_camelot_skills.lua

    Pluggable tracker module for Warcraft Forever (Camelot) & Classic Era.
    Supports Shift-clicking weapon skills, primary professions, and secondary skills
    from the Character Panel (SkillsFrame) to display as progress bars in the objective tracker.
--]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = sfui.isRetail
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

local _G = _G
local C_SkillInfo = _G.C_SkillInfo
local UnitDefenseSkill = _G.UnitDefenseSkill
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local GetRealmName = _G.GetRealmName
local IsShiftKeyDown = _G.IsShiftKeyDown
local PlaySound = _G.PlaySound
local SOUNDKIT = _G.SOUNDKIT
local ToggleCharacter = _G.ToggleCharacter
local hooksecurefunc = _G.hooksecurefunc
local CreateFrame = _G.CreateFrame
local EventRegistry = _G.EventRegistry
local ScrollBoxConstants = _G.ScrollBoxConstants

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local table_insert, table_sort = _G.table.insert, _G.table.sort
local string_format = string.format
local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- ─────────────────────────────────────────────────────────
--  SKILL DEFINITIONS & CATEGORIES
-- ─────────────────────────────────────────────────────────
local DEFENSE_SKILL_ID = 95

-- Weapon Skill IDs (Matches Blizzard WEAPON_SKILL_LINES)
local WEAPON_SKILL_IDS = {
    [43]   = true, -- Swords
    [44]   = true, -- Axes
    [45]   = true, -- Bows
    [46]   = true, -- Guns
    [54]   = true, -- Maces
    [55]   = true, -- Two-Handed Swords
    [95]   = true, -- Defense
    [136]  = true, -- Staves
    [160]  = true, -- Two-Handed Maces
    [162]  = true, -- Fist Weapons / Unarmed
    [172]  = true, -- Two-Handed Axes
    [173]  = true, -- Daggers
    [176]  = true, -- Thrown
    [226]  = true, -- Crossbows
    [228]  = true, -- Wands
    [229]  = true, -- Polearms
    [3014] = true, -- Feral Combat
}

-- Primary Professions
local PRIMARY_PROFESSION_IDS = {
    [171] = true, -- Alchemy
    [164] = true, -- Blacksmithing
    [333] = true, -- Enchanting
    [202] = true, -- Engineering
    [182] = true, -- Herbalism
    [165] = true, -- Leatherworking
    [186] = true, -- Mining
    [393] = true, -- Skinning
    [197] = true, -- Tailoring
}

-- Secondary Skills
local SECONDARY_SKILL_IDS = {
    [185] = true, -- Cooking
    [129] = true, -- First Aid
    [356] = true, -- Fishing
    [762] = true, -- Riding
}

local function GetSkillCategoryInfo(skillID)
    if WEAPON_SKILL_IDS[skillID] then
        return "Weapon Skills", 1, { 1.00, 0.85, 0.40 } -- Gold
    elseif PRIMARY_PROFESSION_IDS[skillID] then
        return "Professions", 2, { 0.45, 0.85, 1.00 } -- Cyan/Ice
    elseif SECONDARY_SKILL_IDS[skillID] then
        return "Secondary Skills", 3, { 1.00, 0.72, 0.35 } -- Amber
    else
        return "Skills", 4, { 0.85, 0.85, 0.85 } -- Light gray
    end
end

-- ─────────────────────────────────────────────────────────
--  STORAGE / PERSISTENCE
-- ─────────────────────────────────────────────────────────
local function GetPlayerKey()
    if UnitGUID then
        local guid = UnitGUID("player")
        if guid and guid ~= "" then return guid end
    end
    local name = UnitName and UnitName("player") or "player"
    local realm = GetRealmName and GetRealmName() or ""
    return name .. "-" .. realm
end

local function GetTrackedSkills()
    SfuiDB = SfuiDB or {}
    SfuiDB.characterSkills = SfuiDB.characterSkills or {}
    local key = GetPlayerKey()
    if not SfuiDB.characterSkills[key] then
        SfuiDB.characterSkills[key] = {}
    end
    return SfuiDB.characterSkills[key]
end

local function IsSkillTracked(skillID)
    if not skillID then return false end
    local tracked = GetTrackedSkills()
    return tracked[skillID] == true
end

-- ─────────────────────────────────────────────────────────
--  SKILL DATA QUERIES
-- ─────────────────────────────────────────────────────────
local function GetSkillInfo(skillID)
    if not skillID then return nil end
    local info = nil
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        info = C_SkillInfo.GetSkillLineInfoByID(skillID)
    end
    if not info and C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        for idx = 1, C_SkillInfo.GetNumSkillLines() do
            local line = C_SkillInfo.GetSkillLineInfo(idx)
            if line and line.skillID == skillID then
                info = line
                break
            end
        end
    end
    if info and info.skillID == DEFENSE_SKILL_ID and UnitDefenseSkill then
        local _, defModifier = UnitDefenseSkill("player")
        if defModifier then
            info.modifier = defModifier
        end
    end
    return info
end

local function OpenSkillInUI(skillID)
    if InCombatLockdown and InCombatLockdown() then return end
    if ToggleCharacter then
        ToggleCharacter("SkillsFrame")
        if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
            for idx = 1, C_SkillInfo.GetNumSkillLines() do
                local info = C_SkillInfo.GetSkillLineInfo(idx)
                if info and info.skillID == skillID then
                    C_SkillInfo.SetSelectedSkill(idx)
                    if EventRegistry and EventRegistry.TriggerEvent then
                        EventRegistry:TriggerEvent("SkillsFrame.NewSkillLineSelected")
                    end
                    local skillsFrame = _G.SkillsFrame
                    if skillsFrame and skillsFrame.ScrollBox and skillsFrame.ScrollBox.ScrollToElementDataIndex then
                        skillsFrame.ScrollBox:ScrollToElementDataIndex(idx, ScrollBoxConstants and ScrollBoxConstants.AlignNearest)
                    end
                    break
                end
            end
        end
    end
end

-- Forward declaration
local UpdateEntryTrackingVisual
local UpdateDetailFrameCheckbox

local function ToggleTrackedSkill(skillID)
    if not skillID then return end
    local tracked = GetTrackedSkills()
    local isTracked = not tracked[skillID]
    tracked[skillID] = isTracked and true or nil

    if PlaySound and SOUNDKIT then
        if isTracked then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
        end
    end

    sfui.tracker.RequestRefresh(0.01)
    return isTracked
end

-- ─────────────────────────────────────────────────────────
--  SKILLSFRAME HOOKS & VISUALS
-- ─────────────────────────────────────────────────────────
UpdateEntryTrackingVisual = function(entry)
    if not entry or not entry.Content then return end
    local elementData = entry.elementData
    if not elementData or elementData.isHeader then
        if entry.Content.sfuiTrackIcon then
            entry.Content.sfuiTrackIcon:Hide()
        end
        return
    end

    local skillID = elementData.skillID
    local isTracked = skillID and IsSkillTracked(skillID)

    if not entry.Content.sfuiTrackIcon then
        local icon = entry.Content:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", entry.Content, "LEFT", 2, 0)
        icon:SetAtlas("checkmark-minimal")
        icon:SetVertexColor(1.0, 0.85, 0.25, 1.0)
        entry.Content.sfuiTrackIcon = icon
    end

    if isTracked then
        entry.Content.sfuiTrackIcon:Show()
        entry.Content.Name:ClearAllPoints()
        entry.Content.Name:SetPoint("LEFT", entry.Content, "LEFT", 18, 0)
        entry.Content.Name:SetPoint("RIGHT", entry.Content.SkillsBar, "LEFT", -10, 0)
    else
        entry.Content.sfuiTrackIcon:Hide()
        entry.Content.Name:ClearAllPoints()
        entry.Content.Name:SetPoint("LEFT", entry.Content, "LEFT", 2, 0)
        entry.Content.Name:SetPoint("RIGHT", entry.Content.SkillsBar, "LEFT", -10, 0)
    end
end

UpdateDetailFrameCheckbox = function(detailFrame)
    if not detailFrame then return end
    local skillInfo = detailFrame.GetSelectedSkillInfo and detailFrame:GetSelectedSkillInfo()
    if not skillInfo or not skillInfo.skillID then
        if detailFrame.sfuiTrackCheckbox then
            detailFrame.sfuiTrackCheckbox:Hide()
        end
        return
    end

    if not detailFrame.sfuiTrackCheckbox then
        local cb = CreateFrame("CheckButton", nil, detailFrame)
        cb:SetSize(22, 22)
        cb:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -12, -6)

        local nt = cb:CreateTexture(nil, "ARTWORK")
        nt:SetAtlas("checkbox-minimal", true)
        nt:SetAllPoints()
        cb:SetNormalTexture(nt)

        local pt = cb:CreateTexture(nil, "ARTWORK")
        pt:SetAtlas("checkbox-minimal", true)
        pt:SetAllPoints()
        cb:SetPushedTexture(pt)

        local ct = cb:CreateTexture(nil, "OVERLAY")
        ct:SetAtlas("checkmark-minimal", true)
        ct:SetAllPoints()
        cb:SetCheckedTexture(ct)

        local dt = cb:CreateTexture(nil, "OVERLAY")
        dt:SetAtlas("checkmark-minimal-disabled", true)
        dt:SetAllPoints()
        cb:SetDisabledCheckedTexture(dt)

        local label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("RIGHT", cb, "LEFT", -4, 0)
        label:SetText("Track in Objectives")
        cb.Label = label

        cb:SetScript("OnClick", function(button)
            local curInfo = detailFrame:GetSelectedSkillInfo()
            if curInfo and curInfo.skillID then
                local tracked = ToggleTrackedSkill(curInfo.skillID)
                button:SetChecked(tracked)
                local skillsFrame = _G.SkillsFrame
                if skillsFrame and skillsFrame.ScrollBox and skillsFrame.ScrollBox.ForEachFrame then
                    skillsFrame.ScrollBox:ForEachFrame(function(entry)
                        if entry.elementData and entry.elementData.skillID == curInfo.skillID then
                            UpdateEntryTrackingVisual(entry)
                        end
                    end)
                end
            end
        end)

        cb:SetScript("OnEnter", function(button)
            local tip = _G.GameTooltip
            if tip then
                tip:SetOwner(button, "ANCHOR_RIGHT")
                tip:ClearLines()
                tip:AddLine("Track Skill", 1, 1, 1)
                tip:AddLine("Displays this skill as a progress bar in the objective tracker.", 0.85, 0.85, 0.85, true)
                tip:Show()
            end
        end)
        cb:SetScript("OnLeave", function()
            local tip = _G.GameTooltip
            if tip then tip:Hide() end
        end)

        detailFrame.sfuiTrackCheckbox = cb
    end

    detailFrame.sfuiTrackCheckbox:Show()
    detailFrame.sfuiTrackCheckbox:SetChecked(IsSkillTracked(skillInfo.skillID))
end

local _hooksInstalled = false
local function SetupSkillsFrameHooks()
    if _hooksInstalled then return end

    local SkillsEntryMixin = _G.SkillsEntryMixin
    if SkillsEntryMixin and SkillsEntryMixin.OnClick and SkillsEntryMixin.Initialize then
        hooksecurefunc(SkillsEntryMixin, "Initialize", function(self, elementData)
            UpdateEntryTrackingVisual(self)
        end)

        hooksecurefunc(SkillsEntryMixin, "OnClick", function(self, button)
            if IsShiftKeyDown and IsShiftKeyDown() then
                if self.elementData and not self.elementData.isHeader and self.elementData.skillID then
                    ToggleTrackedSkill(self.elementData.skillID)
                    UpdateEntryTrackingVisual(self)
                    local skillsFrame = _G.SkillsFrame
                    if skillsFrame and skillsFrame.SkillDetailFrame then
                        UpdateDetailFrameCheckbox(skillsFrame.SkillDetailFrame)
                    end
                end
            end
        end)

        hooksecurefunc(SkillsEntryMixin, "OnEnter", function(self)
            if not self.elementData or self.elementData.isHeader then return end
            local tip = _G.GameTooltip
            if not tip then return end
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:ClearLines()
            local name = self.elementData.name or "Skill"
            local isTracked = IsSkillTracked(self.elementData.skillID)
            local catName, _, catColor = GetSkillCategoryInfo(self.elementData.skillID)
            tip:AddLine(name, catColor[1], catColor[2], catColor[3])
            if catName then
                tip:AddLine(catName, 0.70, 0.70, 0.70)
            end
            local rankText = string_format("Rank: %d / %d", self.elementData.rank or 0, self.elementData.maxRank or 0)
            if self.elementData.modifier and self.elementData.modifier ~= 0 then
                rankText = rankText .. string_format(" (%+d modifier)", self.elementData.modifier)
            end
            tip:AddLine(rankText, 1, 1, 1)
            if self.elementData.description and self.elementData.description ~= "" then
                tip:AddLine(" ")
                tip:AddLine(self.elementData.description, 0.85, 0.85, 0.85, true)
            end
            tip:AddLine(" ")
            if isTracked then
                tip:AddLine("|cffff8800Shift-Click to untrack from Objective Tracker|r", 1, 1, 1)
            else
                tip:AddLine("|cff00ff00Shift-Click to track in Objective Tracker|r", 1, 1, 1)
            end
            tip:Show()
        end)

        hooksecurefunc(SkillsEntryMixin, "OnLeave", function(self)
            local tip = _G.GameTooltip
            if tip and tip:GetOwner() == self then
                tip:Hide()
            end
        end)
    end

    local SkillDetailFrameMixin = _G.SkillDetailFrameMixin
    if SkillDetailFrameMixin and SkillDetailFrameMixin.Refresh then
        hooksecurefunc(SkillDetailFrameMixin, "Refresh", function(self)
            UpdateDetailFrameCheckbox(self)
        end)
    end

    local skillsFrame = _G.SkillsFrame
    if skillsFrame and skillsFrame.SkillDetailFrame and skillsFrame.SkillDetailFrame.RankBar then
        local rankBar = skillsFrame.SkillDetailFrame.RankBar
        if not rankBar._sfuiHooked then
            rankBar._sfuiHooked = true
            rankBar:EnableMouse(true)
            rankBar:HookScript("OnMouseUp", function(bar, btn)
                if IsShiftKeyDown and IsShiftKeyDown() then
                    local detail = skillsFrame.SkillDetailFrame
                    local info = detail and detail.GetSelectedSkillInfo and detail:GetSelectedSkillInfo()
                    if info and info.skillID then
                        ToggleTrackedSkill(info.skillID)
                        UpdateDetailFrameCheckbox(detail)
                        if skillsFrame.ScrollBox and skillsFrame.ScrollBox.ForEachFrame then
                            skillsFrame.ScrollBox:ForEachFrame(function(entry)
                                if entry.elementData and entry.elementData.skillID == info.skillID then
                                    UpdateEntryTrackingVisual(entry)
                                end
                            end)
                        end
                    end
                end
            end)
        end
    end

    if SkillsEntryMixin and SkillDetailFrameMixin then
        _hooksInstalled = true
    end
end

-- ─────────────────────────────────────────────────────────
--  OBJECTIVE TRACKER MODULE
-- ─────────────────────────────────────────────────────────
local CamelotSkillsModule = {
    id       = "skills",
    priority = 1,
    events   = {
        "SKILL_LINES_CHANGED",
        "CHAT_MSG_SKILL",
        "PLAYER_ENTERING_WORLD",
        "ADDON_LOADED",
    },
}

function CamelotSkillsModule:Init(engine)
    self.engine = engine
    SetupSkillsFrameHooks()
end

function CamelotSkillsModule:IsEnabled()
    return true
end

function CamelotSkillsModule:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_UIPanels_Game" or _G.SkillsFrame then
            SetupSkillsFrameHooks()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        SetupSkillsFrameHooks()
    end

    self:MarkDirty(0.02)
    sfui.tracker.RequestRefresh(0.02)
end

function CamelotSkillsModule:BuildBlocks(container)
    local tracked = GetTrackedSkills()
    if not tracked or not next(tracked) then
        return nil
    end

    local skillList = {}
    for skillID, isTracked in pairs(tracked) do
        if isTracked then
            local info = GetSkillInfo(skillID)
            if info and info.name then
                table_insert(skillList, info)
            end
        end
    end

    if #skillList == 0 then
        return nil
    end

    -- Sort: Weapon Skills -> Professions -> Secondary -> Alphabetical
    table_sort(skillList, function(a, b)
        local _, rankA = GetSkillCategoryInfo(a.skillID)
        local _, rankB = GetSkillCategoryInfo(b.skillID)
        if rankA ~= rankB then
            return rankA < rankB
        end
        return (a.name or "") < (b.name or "")
    end)

    local blocks = {}
    for _, skill in ipairs(skillList) do
        local skillID = skill.skillID
        local catName, _, catColor = GetSkillCategoryInfo(skillID)
        local rank = skill.rank or 0
        local maxRank = (skill.maxRank and skill.maxRank > 0) and skill.maxRank or 1
        local modifier = skill.modifier or 0
        local isMaxed = (rank >= maxRank)

        local progressText
        if modifier > 0 then
            progressText = string_format("%d (+%d) / %d", rank, modifier, maxRank)
        elseif modifier < 0 then
            progressText = string_format("%d (%d) / %d", rank, modifier, maxRank)
        else
            progressText = string_format("%d / %d", rank, maxRank)
        end

        local barColor = isMaxed and { 0.20, 0.85, 0.30, 0.90 } or { 0.22, 0.58, 0.98, 0.90 }

        table_insert(blocks, {
            id          = "skill_" .. tostring(skillID),
            title       = skill.name,
            titleColor  = catColor,
            progressBar = {
                min   = 0,
                max   = maxRank,
                value = rank,
                text  = progressText,
                color = barColor,
            },
            OnClick = function(block, btn)
                if btn == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
                    ToggleTrackedSkill(skillID)
                    local skillsFrame = _G.SkillsFrame
                    if skillsFrame and skillsFrame:IsShown() then
                        if skillsFrame.SkillDetailFrame then
                            UpdateDetailFrameCheckbox(skillsFrame.SkillDetailFrame)
                        end
                        if skillsFrame.ScrollBox and skillsFrame.ScrollBox.ForEachFrame then
                            skillsFrame.ScrollBox:ForEachFrame(function(entry)
                                if entry.elementData and entry.elementData.skillID == skillID then
                                    UpdateEntryTrackingVisual(entry)
                                end
                            end)
                        end
                    end
                    return
                end
                OpenSkillInUI(skillID)
            end,
            tooltip = function(tip, owner, bData)
                tip:AddLine(skill.name, catColor[1], catColor[2], catColor[3])
                if catName then
                    tip:AddLine(catName, 0.70, 0.70, 0.70)
                end
                local rankDesc = string_format("Rank: %d / %d", rank, maxRank)
                if modifier ~= 0 then
                    rankDesc = rankDesc .. string_format(" (%+d modifier)", modifier)
                end
                tip:AddLine(rankDesc, 1, 1, 1)
                if skill.description and skill.description ~= "" then
                    tip:AddLine(" ")
                    tip:AddLine(skill.description, 0.85, 0.85, 0.85, true)
                end
                tip:AddLine(" ")
                tip:AddLine("|cff888888Left-click: Open Skills panel|r", 1, 1, 1)
                tip:AddLine("|cff888888Shift-click or Right-click: Untrack skill|r", 1, 1, 1)
            end,
        })
    end

    if #blocks > 0 then
        return {
            {
                id           = "skills",
                title        = "skills",
                color        = { 1.0, 0.82, 0.35 }, -- Gold/Amber
                count        = #blocks,
                blocks       = blocks,
                OnShiftClick = function()
                    local t = GetTrackedSkills()
                    wipe(t)
                    if PlaySound and SOUNDKIT then
                        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
                    end
                    local skillsFrame = _G.SkillsFrame
                    if skillsFrame and skillsFrame:IsShown() then
                        if skillsFrame.SkillDetailFrame then
                            UpdateDetailFrameCheckbox(skillsFrame.SkillDetailFrame)
                        end
                        if skillsFrame.ScrollBox and skillsFrame.ScrollBox.ForEachFrame then
                            skillsFrame.ScrollBox:ForEachFrame(function(entry)
                                UpdateEntryTrackingVisual(entry)
                            end)
                        end
                    end
                    sfui.tracker.RequestRefresh(0.01)
                end,
            }
        }
    end

    return nil
end

sfui.tracker.RegisterModule(CamelotSkillsModule)
return CamelotSkillsModule
