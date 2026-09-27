--[[
    SFUI Tracker Helper: Find Group (LFG)
    frames/quests/helpers/findgroup.lua

    Handles LFG/Group Finder eye icon creation, setup, and click handling
    for quests and world quests that support Group Finder through the API.
]]

local addonName, addon = ...
sfui = sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local FindGroup = {}
sfui.tracker.helpers.findgroup = FindGroup

local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local pcall = _G.pcall
local table_insert, table_remove = _G.table.insert, _G.table.remove

local buttonPool = {}

function FindGroup.CanFindGroup(questID)
    if not questID or questID <= 0 then return false end

    -- Classic / Classic Era / Forever / Camelot do not support Group Finder for quests
    local isCamelot = sfui.isClassic or sfui.isForever or (sfui.compat and (sfui.compat.is_classic or sfui.compat.is_wow_forever or sfui.compat.is_classic_era))
    if isCamelot then return false end

    -- ZERO INTERACTION RULE (methods.md 3.7.5):
    -- Never call QuestUtil.CanCreateQuestGroup or C_LFGList.CanCreateQuestGroup during tracker loops.
    -- Doing so taints Blizzard's g_createQuestGroupCache -> QuestDataProvider -> Button:SetPassThroughButtons().
    -- Instead, inspect static quest log fields.
    if _G.C_QuestLog then
        if _G.C_QuestLog.GetInfo then
            local info = _G.C_QuestLog.GetInfo(questID)
            if info and info.suggestedGroup and info.suggestedGroup > 1 then
                return true
            end
        end
        if _G.C_QuestLog.GetQuestTagInfo then
            local tagInfo = _G.C_QuestLog.GetQuestTagInfo(questID)
            if tagInfo and (tagInfo.isElite or (tagInfo.suggestedGroup and tagInfo.suggestedGroup > 1)) then
                return true
            end
        end
    end

    return false
end

function FindGroup.CreateFindGroupButton(parent)
    local btn = table_remove(buttonPool)
    if btn then
        btn:SetParent(parent)
        btn:ClearAllPoints()
        return btn
    end

    -- Create pure custom button, NEVER using Blizzard's QuestObjectiveFindGroupButtonTemplate
    -- which pulls in QuestObjectiveFindGroupButtonMixin and taints GameTooltip / LFG execution paths.
    btn = CreateFrame("Button", nil, parent)
    local eyeIcon = btn:CreateTexture(nil, "ARTWORK")
    eyeIcon:SetSize(14, 14)
    eyeIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    eyeIcon:SetAtlas("socialqueuing-icon-eye")
    eyeIcon:SetVertexColor(0.85, 0.85, 0.85, 0.85)
    btn.EyeIcon = eyeIcon

    btn:SetScript("OnEnter", function(self)
        if self.EyeIcon then self.EyeIcon:SetVertexColor(1, 1, 1, 1) end
        local tip = _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        tip:AddLine(_G.TOOLTIP_TRACKER_FIND_GROUP_BUTTON or "Find Group", 1, 1, 1)
        if self.questTitle then
            tip:AddLine(self.questTitle, 0.20, 0.85, 0.95)
        end
        tip:AddLine("Click to search for or create a group in Group Finder.", 0.7, 0.7, 0.7, true)
        tip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        if self.EyeIcon then self.EyeIcon:SetVertexColor(0.85, 0.85, 0.85, 0.85) end
        local tip = _G.GameTooltip
        if tip then tip:Hide() end
    end)
    btn:SetScript("OnClick", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        if _G.LFGListUtil_FindQuestGroup and self.questID then
            _G.LFGListUtil_FindQuestGroup(self.questID)
        elseif _G.PVEFrame_ShowFrame and _G.LFGListPVEStub then
            _G.PVEFrame_ShowFrame("GroupFinderFrame", _G.LFGListPVEStub)
        end
    end)

    btn:SetSize(18, 18)
    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", function(self, delta)
        if sfui.tracker and sfui.tracker.OnMouseWheel then
            sfui.tracker.OnMouseWheel(self, delta)
        end
    end)

    btn:Hide()
    return btn
end

function FindGroup.SetupFindGroupButton(btn, questID, questTitle)
    if not btn or not questID then return end

    btn.questID = questID
    btn.questTitle = questTitle

    btn:Show()
end

function FindGroup.ReleaseFindGroupButton(btn)
    if not btn then return end
    btn:Hide()
    btn:ClearAllPoints()
    btn.questID = nil
    btn.questTitle = nil
    table_insert(buttonPool, btn)
end

return FindGroup
