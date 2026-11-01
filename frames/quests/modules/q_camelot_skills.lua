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
    local isCamelot = (tocVersionNum >= 16000 and tocVersionNum < 20000) or (projectID == 18)
    isRetail = (projectID == 1) and not isCamelot
end

if isRetail then
    return
end

local _G = _G
local C_SkillInfo = _G.C_SkillInfo
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
local InCombatLockdown = _G.InCombatLockdown

local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local next = _G.next
local math_floor = math.floor
local table_insert, table_sort, table_concat = _G.table.insert, _G.table.sort, _G.table.concat
local string_format, string_lower, string_match = string.format, string.lower, string.match
local GetTime = _G.GetTime
local UnitClass = _G.UnitClass
local C_Timer = _G.C_Timer
local wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- ─────────────────────────────────────────────────────────
--  SKILL DEFINITIONS & CATEGORIES
-- ─────────────────────────────────────────────────────────
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
    [185]  = true, -- Cooking
    [129]  = true, -- First Aid
    [356]  = true, -- Fishing
    [762]  = true, -- Riding
    [3012] = true, -- Comprehension
}

local SKILL_ID_TO_PROF_NAME = {
    [171]  = "Alchemy",
    [164]  = "Blacksmithing",
    [333]  = "Enchanting",
    [202]  = "Engineering",
    [165]  = "Leatherworking",
    [197]  = "Tailoring",
    [185]  = "Cooking",
    [129]  = "First Aid",
    [3012] = "Comprehension",
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
local GetPlayerKey = sfui.common.get_player_unique_key

local function GetTrackedSkills()
    SfuiDB = SfuiDB or {}
    SfuiDB.characterSkills = SfuiDB.characterSkills or {}
    local key = GetPlayerKey()
    if not SfuiDB.characterSkills[key] then
        -- Check fallback name-realm key in case GUID was cached differently earlier
        local name = UnitName and UnitName("player") or "player"
        local realm = GetRealmName and GetRealmName() or ""
        local altKey = name .. "-" .. realm
        if altKey ~= key and SfuiDB.characterSkills[altKey] then
            SfuiDB.characterSkills[key] = SfuiDB.characterSkills[altKey]
        else
            SfuiDB.characterSkills[key] = {}
        end
    end
    return SfuiDB.characterSkills[key]
end

local function IsSkillTracked(skillID)
    skillID = tonumber(skillID) or skillID
    if not skillID then return false end
    local tracked = GetTrackedSkills()
    if tracked[skillID] ~= nil then
        return tracked[skillID] == true
    end
    if type(skillID) == "number" and tracked[tostring(skillID)] ~= nil then
        return tracked[tostring(skillID)] == true
    end
    return false
end

-- ─────────────────────────────────────────────────────────
--  SKILL DATA QUERIES
-- ─────────────────────────────────────────────────────────
local function GetSkillInfo(skillID)
    skillID = tonumber(skillID) or skillID
    if not skillID then return nil end
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and type(skillID) == "number" then
        local info = C_SkillInfo.GetSkillLineInfoByID(skillID)
        if info then return info end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        for idx = 1, C_SkillInfo.GetNumSkillLines() do
            local line = C_SkillInfo.GetSkillLineInfo(idx)
            if line and tonumber(line.skillID) == skillID then
                return line
            end
        end
    end
    return nil
end

local function OpenSkillInUI(skillID)
    if InCombatLockdown and InCombatLockdown() then return end
    skillID = tonumber(skillID) or skillID
    if not skillID then return end

    local skillsFrame = _G.SkillsFrame
    if not skillsFrame or not skillsFrame:IsShown() then
        if ToggleCharacter then
            ToggleCharacter("SkillsFrame")
        end
    end

    if C_SkillInfo and C_SkillInfo.GetNumSkillLines then
        for idx = 1, C_SkillInfo.GetNumSkillLines() do
            local info = C_SkillInfo.GetSkillLineInfo(idx)
            if info and tonumber(info.skillID) == skillID then
                C_SkillInfo.SetSelectedSkill(idx)
                if EventRegistry and EventRegistry.TriggerEvent then
                    EventRegistry:TriggerEvent("SkillsFrame.NewSkillLineSelected")
                end
                skillsFrame = _G.SkillsFrame
                if skillsFrame and skillsFrame.ScrollBox and skillsFrame.ScrollBox.ScrollToElementDataIndex then
                    skillsFrame.ScrollBox:ScrollToElementDataIndex(idx, ScrollBoxConstants and ScrollBoxConstants.AlignNearest)
                end
                break
            end
        end
    end
end

-- Forward declarations
local UpdateEntryTrackingVisual
local UpdateDetailFrameCheckbox
local UpdateAllSkillsVisuals
local ScheduleSkillsSyncBroadcast
local CamelotSkillsModule

local function GetLocalSpecColor()
    local sc = sfui.common and sfui.common.get_class_or_spec_color and sfui.common.get_class_or_spec_color()
    if sc then
        local r = tonumber(sc[1] or sc.r) or 0.22
        local g = tonumber(sc[2] or sc.g) or 0.58
        local b = tonumber(sc[3] or sc.b) or 0.98
        return { r, g, b, 0.90 }
    end
    return { 0.22, 0.58, 0.98, 0.90 }
end

local function ToggleTrackedSkill(skillID)
    skillID = tonumber(skillID) or skillID
    if not skillID then return end
    local tracked = GetTrackedSkills()
    local isTracked = not IsSkillTracked(skillID)
    tracked[skillID] = isTracked and true or nil
    if type(skillID) == "number" then
        tracked[tostring(skillID)] = nil
    end

    if PlaySound and SOUNDKIT then
        if isTracked then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857)
        end
    end

    if CamelotSkillsModule and CamelotSkillsModule.MarkDirty then
        CamelotSkillsModule:MarkDirty(0)
    end
    sfui.tracker.RequestRefresh(0)

    if UpdateAllSkillsVisuals then
        UpdateAllSkillsVisuals()
    end

    if ScheduleSkillsSyncBroadcast then
        ScheduleSkillsSyncBroadcast(true)
    end

    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_SKILL_TRACKING_CHANGED", skillID, isTracked)
    end

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
        label:SetText("track in objectives")
        cb.Label = label

        cb:SetScript("OnClick", function(button)
            local curInfo = detailFrame:GetSelectedSkillInfo()
            if curInfo and curInfo.skillID then
                local tracked = ToggleTrackedSkill(curInfo.skillID)
                button:SetChecked(tracked)
            end
        end)

        cb:SetScript("OnEnter", function(button)
            local tip = sfui.common.get_tooltip()
            if tip then
                tip:SetOwner(button, "ANCHOR_RIGHT")
                tip:ClearLines()
                tip:AddLine("track skill", 1, 1, 1)
                tip:AddLine("displays this skill as a progress bar in the objective tracker.", 0.85, 0.85, 0.85, true)
                tip:Show()
            end
        end)
        cb:SetScript("OnLeave", function()
            local tip = sfui.common.get_tooltip()
            if tip then tip:Hide() end
        end)

        detailFrame.sfuiTrackCheckbox = cb
    end

    detailFrame.sfuiTrackCheckbox:Show()
    detailFrame.sfuiTrackCheckbox:SetChecked(IsSkillTracked(skillInfo.skillID))
end

UpdateAllSkillsVisuals = function()
    local skillsFrame = _G.SkillsFrame
    if not skillsFrame or not skillsFrame:IsShown() then return end

    if skillsFrame.SkillDetailFrame then
        UpdateDetailFrameCheckbox(skillsFrame.SkillDetailFrame)
    end

    if skillsFrame.ScrollBox and skillsFrame.ScrollBox.ForEachFrame then
        skillsFrame.ScrollBox:ForEachFrame(function(entry)
            UpdateEntryTrackingVisual(entry)
        end)
    end
end

local _hooksInstalled = false
local function SetupSkillsFrameHooks()
    local skillsFrame = _G.SkillsFrame
    if skillsFrame and not skillsFrame._sfuiHooked then
        skillsFrame._sfuiHooked = true
        skillsFrame:HookScript("OnShow", function()
            UpdateAllSkillsVisuals()
        end)

        if skillsFrame.SkillDetailFrame and skillsFrame.SkillDetailFrame.RankBar then
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
                        end
                    end
                end)
            end
        end
    end

    if _hooksInstalled then return end

    local SkillsEntryMixin = _G.SkillsEntryMixin
    local SkillDetailFrameMixin = _G.SkillDetailFrameMixin

    if not SkillsEntryMixin or not SkillDetailFrameMixin then
        return
    end

    hooksecurefunc(SkillsEntryMixin, "Initialize", function(self, elementData)
        UpdateEntryTrackingVisual(self)
    end)

    hooksecurefunc(SkillsEntryMixin, "OnClick", function(self, button)
        if IsShiftKeyDown and IsShiftKeyDown() then
            if self.elementData and not self.elementData.isHeader and self.elementData.skillID then
                ToggleTrackedSkill(self.elementData.skillID)
            end
        end
    end)

    hooksecurefunc(SkillsEntryMixin, "OnEnter", function(self)
        if not self.elementData or self.elementData.isHeader then return end
        local tip = sfui.common.get_tooltip()
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
        tip:AddLine(rankText, 1, 1, 1)
        if self.elementData.description and self.elementData.description ~= "" then
            tip:AddLine(" ")
            tip:AddLine(self.elementData.description, 0.85, 0.85, 0.85, true)
        end
        tip:AddLine(" ")
        if isTracked then
            tip:AddLine("|cffff8800shift-click to untrack from objective tracker|r", 1, 1, 1)
        else
            tip:AddLine("|cff00ff00shift-click to track in objective tracker|r", 1, 1, 1)
        end
        tip:Show()
    end)

    hooksecurefunc(SkillsEntryMixin, "OnLeave", function(self)
        local tip = sfui.common.get_tooltip()
        if tip and tip:GetOwner() == self then
            tip:Hide()
        end
    end)

    hooksecurefunc(SkillDetailFrameMixin, "Refresh", function(self)
        UpdateDetailFrameCheckbox(self)
    end)

    _hooksInstalled = true
end

-- ─────────────────────────────────────────────────────────
--  CROSS-CLIENT SYNC (TRACKED SKILLS & SPEC COLORS)
-- ─────────────────────────────────────────────────────────
local remotePeerSkills      = {} -- [peerKey] = { name, class, spec, cr, cg, cb, list = { { id, name, r, m }, ... } }
local lastSentSkillsSig     = nil
local skillsBroadcastQueued = false

local function CleanPeerKey(name)
    if type(name) ~= "string" or name == "" then return "" end
    if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.CleanKey then
        return sfui.sync.multibox.CleanKey(name)
    end
    local short = string_match(name, "^([^%-]+)") or name
    return string_lower(short)
end

local function FormatColoredName(name, classToken)
    local clean = string_lower(string_match(tostring(name or "player"), "^([^%-]+)") or tostring(name or "player"))
    if classToken and sfui.common and sfui.common.class_color_name then
        return sfui.common.class_color_name(clean, classToken)
    end
    return clean
end

local function ResolvePeerSpecColor(peer)
    if not peer then return GetLocalSpecColor() end
    local specID = tonumber(peer.spec) or 0
    if SfuiDB and SfuiDB.useSpecColor ~= false and specID > 0 and SfuiDB.spec_colors and SfuiDB.spec_colors[specID] then
        local c = SfuiDB.spec_colors[specID]
        return { tonumber(c[1] or c.r) or 0.22, tonumber(c[2] or c.g) or 0.58, tonumber(c[3] or c.b) or 0.98, 0.90 }
    end
    if peer.cr and peer.cg and peer.cb then
        return { peer.cr / 255, peer.cg / 255, peer.cb / 255, 0.90 }
    end
    if specID > 0 and sfui.colors and sfui.colors.get_spec_color_table then
        local t = sfui.colors.get_spec_color_table(specID)
        if t then
            return { tonumber(t[1] or t.r) or 0.22, tonumber(t[2] or t.g) or 0.58, tonumber(t[3] or t.b) or 0.98, 0.90 }
        end
    end
    if peer.class and sfui.common and sfui.common.get_class_color then
        local r, g, b = sfui.common.get_class_color(peer.class)
        if r and g and b then
            return { r, g, b, 0.90 }
        end
    end
    return GetLocalSpecColor()
end

local function IsSyncActive()
    local sync = sfui.sync
    if not sync or not sync.GetSettings then return false end
    local s = sync.GetSettings()
    return (s and s.enabled == true) or false
end

local function IsPeerSkillsVisible(peerKey, peer)
    if not IsSyncActive() or not peer or type(peer.list) ~= "table" or #peer.list == 0 then
        return false
    end
    local myKey = CleanPeerKey((UnitName and UnitName("player")) or "")
    if peerKey == "" or peerKey == myKey then
        return false
    end
    local sync = sfui.sync
    if sync and sync.IsPeerOffline and sync.IsPeerOffline(peer.name) then
        return false
    end
    local mb = sync and sync.multibox
    if mb and mb.IsActiveSyncParty and mb.IsActiveSyncParty() then
        local unit = mb.FindPartyUnitByName and mb.FindPartyUnitByName(peer.name)
        if unit then return true end
    end
    return true
end

local function BroadcastTrackedSkills(force, isInit)
    if not IsSyncActive() then return end
    local sync = sfui.sync
    if not sync or not sync.Broadcast then return end

    local tracked = GetTrackedSkills()
    local ids = {}
    if tracked then
        for skillID, isTracked in pairs(tracked) do
            local numID = tonumber(skillID)
            if isTracked and numID then
                table_insert(ids, numID)
            end
        end
    end
    table_sort(ids)

    local items = {}
    local sigParts = {}
    for _, skillID in ipairs(ids) do
        local info = GetSkillInfo(skillID)
        if info and info.name then
            local r = tonumber(info.rank) or 0
            local m = (info.maxRank and info.maxRank > 0) and tonumber(info.maxRank) or 1
            table_insert(items, {
                id   = skillID,
                name = info.name,
                r    = r,
                m    = m,
            })
            table_insert(sigParts, string_format("%d:%d:%d", skillID, r, m))
        end
    end

    local sc = GetLocalSpecColor()
    local cr = math_floor((sc[1] or 0.22) * 255 + 0.5)
    local cg = math_floor((sc[2] or 0.58) * 255 + 0.5)
    local cb = math_floor((sc[3] or 0.98) * 255 + 0.5)
    local specID = (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()) or 0
    local _, classToken = UnitClass and UnitClass("player")

    local sig = string_format("%d:%d:%d:%d|%s", specID, cr, cg, cb, table_concat(sigParts, ","))
    if not force and sig == lastSentSkillsSig then
        return
    end
    lastSentSkillsSig = sig

    local s = sync.GetSettings and sync.GetSettings()
    sync.Broadcast("DELTA_TRACKED_SKILLS", {
        pass  = (s and s.passcode ~= "" and s.passcode) or nil,
        init  = isInit and 1 or nil,
        spec  = specID,
        class = classToken,
        cr    = cr,
        cg    = cg,
        cb    = cb,
        list  = items,
    }, true, false)
end

ScheduleSkillsSyncBroadcast = function(force, isInit)
    if not IsSyncActive() then return end
    if force then
        lastSentSkillsSig = nil
    end
    if skillsBroadcastQueued then return end
    skillsBroadcastQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.35, function()
            skillsBroadcastQueued = false
            BroadcastTrackedSkills(force, isInit)
        end)
    else
        skillsBroadcastQueued = false
        BroadcastTrackedSkills(force, isInit)
    end
end

local function RequestRemoteSkillUntrack(peerKey, skillID)
    skillID = tonumber(skillID)
    if not skillID then return end
    local peer = peerKey and remotePeerSkills[peerKey]
    if peer and type(peer.list) == "table" then
        for i = #peer.list, 1, -1 do
            if tonumber(peer.list[i].id) == skillID then
                table.remove(peer.list, i)
            end
        end
    end
    if IsSyncActive() and sfui.sync and sfui.sync.Broadcast then
        local s = sfui.sync.GetSettings and sfui.sync.GetSettings()
        sfui.sync.Broadcast("DELTA_SKILL_UNTRACK", {
            pass   = (s and s.passcode ~= "" and s.passcode) or nil,
            target = peer and peer.name or peerKey,
            id     = skillID,
        }, true, false)
    end
    if CamelotSkillsModule and CamelotSkillsModule.MarkDirty then
        CamelotSkillsModule:MarkDirty(0)
    end
    sfui.tracker.RequestRefresh(0)
end

local function HandleSkillsSyncMessage(sender, msgType, data)
    if type(data) ~= "table" then return end
    if msgType == "DELTA_TRACKED_SKILLS" then
        local peerKey = CleanPeerKey(sender)
        if peerKey == "" then return end
        local cleanList = {}
        if type(data.list) == "table" then
            for _, entry in ipairs(data.list) do
                local id = tonumber(entry and entry.id)
                if id and entry.name then
                    table_insert(cleanList, {
                        id   = id,
                        name = tostring(entry.name),
                        r    = tonumber(entry.r) or 0,
                        m    = math.max(1, tonumber(entry.m) or 1),
                    })
                end
            end
        end
        remotePeerSkills[peerKey] = {
            name      = sender,
            class     = data.class,
            spec      = tonumber(data.spec) or 0,
            cr        = tonumber(data.cr),
            cg        = tonumber(data.cg),
            cb        = tonumber(data.cb),
            list      = cleanList,
            updatedAt = (GetTime and GetTime()) or 0,
        }
        if CamelotSkillsModule and CamelotSkillsModule.MarkDirty then
            CamelotSkillsModule:MarkDirty(0)
        end
        sfui.tracker.RequestRefresh(0.02)

        if tonumber(data.init) == 1 then
            ScheduleSkillsSyncBroadcast(true, false)
        end
    elseif msgType == "DELTA_SKILL_UNTRACK" then
        local skillID = tonumber(data.id)
        if not skillID then return end
        local myKey = CleanPeerKey((UnitName and UnitName("player")) or "")
        local targetKey = data.target and CleanPeerKey(data.target) or ""
        if (targetKey == "" or targetKey == myKey) and IsSkillTracked(skillID) then
            ToggleTrackedSkill(skillID)
        end
    end
end

-- ─────────────────────────────────────────────────────────
--  OBJECTIVE TRACKER MODULE
-- ─────────────────────────────────────────────────────────
CamelotSkillsModule = {
    id       = "skills",
    priority = 1,
    events   = {
        "SKILL_LINES_CHANGED",
        "CHAT_MSG_SKILL",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "ADDON_LOADED",
    },
}

function CamelotSkillsModule:Init(engine)
    self.engine = engine
    SetupSkillsFrameHooks()

    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function()
            self:MarkDirty(0)
            sfui.tracker.RequestRefresh(0.02)
            ScheduleSkillsSyncBroadcast(true, false)
        end)
        sfui.events.RegisterMessage("SFUI_SPEC_COLORS_UPDATED", function()
            self:MarkDirty(0)
            sfui.tracker.RequestRefresh(0.02)
            ScheduleSkillsSyncBroadcast(true, false)
        end)
        sfui.events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", function(_, key)
            if key == "PACKET" then return end
            self:MarkDirty(0.02)
            sfui.tracker.RequestRefresh(0.02)
            ScheduleSkillsSyncBroadcast(true, false)
        end)
    end

    if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.RegisterPartySubmodule then
        sfui.sync.multibox.RegisterPartySubmodule({
            Enable = function()
                ScheduleSkillsSyncBroadcast(true, true)
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
            Disable = function()
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
            Refresh = function()
                ScheduleSkillsSyncBroadcast(false, false)
                self:MarkDirty(0.02)
                sfui.tracker.RequestRefresh(0.02)
            end,
        })
    end
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
        if C_Timer and C_Timer.After then
            C_Timer.After(2.0, function()
                ScheduleSkillsSyncBroadcast(true, true)
            end)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        ScheduleSkillsSyncBroadcast(true, true)
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        ScheduleSkillsSyncBroadcast(false, false)
    end

    self:MarkDirty(0.02)
    sfui.tracker.RequestRefresh(0.02)
end

function CamelotSkillsModule:BuildBlocks(container)
    local tracked = GetTrackedSkills()
    local entriesBySkill = {}
    local skillList = {}

    local localSpecColor = GetLocalSpecColor()
    local myName = (UnitName and UnitName("player")) or "player"
    local _, myClass = UnitClass and UnitClass("player")
    local myColoredName = FormatColoredName(myName, myClass)

    if tracked then
        for rawID, isTracked in pairs(tracked) do
            local skillID = tonumber(rawID)
            if isTracked and skillID then
                local info = GetSkillInfo(skillID)
                if info and info.name then
                    local rank = tonumber(info.rank) or 0
                    local maxRank = (info.maxRank and info.maxRank > 0) and tonumber(info.maxRank) or 1
                    local entry = {
                        skillID     = skillID,
                        name        = info.name,
                        description = info.description,
                        hasLocal    = true,
                        bars        = {
                            {
                                min          = 0,
                                max          = maxRank,
                                value        = rank,
                                text         = string_format("%d / %d", rank, maxRank),
                                color        = localSpecColor,
                                isLocal      = true,
                                ownerName    = myName,
                                coloredOwner = myColoredName,
                                rank         = rank,
                                maxRank      = maxRank,
                            },
                        },
                    }
                    entriesBySkill[skillID] = entry
                    table_insert(skillList, entry)
                end
            end
        end
    end

    if IsSyncActive() and next(remotePeerSkills) then
        local peerKeys = {}
        for k, peer in pairs(remotePeerSkills) do
            if IsPeerSkillsVisible(k, peer) then
                table_insert(peerKeys, k)
            end
        end
        table_sort(peerKeys)

        for _, peerKey in ipairs(peerKeys) do
            local peer = remotePeerSkills[peerKey]
            local peerColor = ResolvePeerSpecColor(peer)
            local peerColoredName = FormatColoredName(peer.name, peer.class)

            for _, remSkill in ipairs(peer.list) do
                local skillID = tonumber(remSkill.id)
                if skillID then
                    local rank = tonumber(remSkill.r) or 0
                    local maxRank = (remSkill.m and remSkill.m > 0) and tonumber(remSkill.m) or 1
                    local entry = entriesBySkill[skillID]
                    if not entry then
                        local localInfo = GetSkillInfo(skillID)
                        entry = {
                            skillID     = skillID,
                            name        = (localInfo and localInfo.name) or remSkill.name or ("Skill " .. tostring(skillID)),
                            description = localInfo and localInfo.description or nil,
                            hasLocal    = false,
                            bars        = {},
                        }
                        entriesBySkill[skillID] = entry
                        table_insert(skillList, entry)
                    end
                    table_insert(entry.bars, {
                        min          = 0,
                        max          = maxRank,
                        value        = rank,
                        text         = string_format("%d / %d", rank, maxRank),
                        color        = peerColor,
                        isLocal      = false,
                        peerKey      = peerKey,
                        ownerName    = peer.name,
                        coloredOwner = peerColoredName,
                        rank         = rank,
                        maxRank      = maxRank,
                    })
                end
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
        local bars = skill.bars

        table_insert(blocks, {
            id           = "skill_" .. tostring(skillID),
            title        = skill.name,
            titleColor   = catColor,
            progressBar  = bars[1],
            progressBars = bars,
            OnClick = function(block, btn, clickedBar)
                if btn == "RightButton" or (IsShiftKeyDown and IsShiftKeyDown()) then
                    if clickedBar then
                        if clickedBar.isLocal then
                            ToggleTrackedSkill(skillID)
                        elseif clickedBar.peerKey then
                            RequestRemoteSkillUntrack(clickedBar.peerKey, skillID)
                        end
                        return
                    end
                    if skill.hasLocal then
                        ToggleTrackedSkill(skillID)
                    elseif bars[1] and bars[1].peerKey then
                        RequestRemoteSkillUntrack(bars[1].peerKey, skillID)
                    end
                    return
                end
                if btn == "MiddleButton" then
                    OpenSkillInUI(skillID)
                    return
                end
                local profName = SKILL_ID_TO_PROF_NAME[skillID]
                if profName and sfui.recipes and sfui.recipes.browser and sfui.recipes.OpenBrowser then
                    sfui.recipes.OpenBrowser()
                    if sfui.recipes.browser.SelectProfession then
                        sfui.recipes.browser:SelectProfession(profName)
                    end
                else
                    OpenSkillInUI(skillID)
                end
            end,
            tooltip = function(tip, owner, bData)
                tip:AddLine(skill.name, catColor[1], catColor[2], catColor[3])
                if catName then
                    tip:AddLine(catName, 0.70, 0.70, 0.70)
                end
                if #bars == 1 and bars[1].isLocal then
                    tip:AddLine(string_format("Rank: %d / %d", bars[1].rank, bars[1].maxRank), 1, 1, 1)
                else
                    for _, b in ipairs(bars) do
                        tip:AddDoubleLine(b.coloredOwner or b.ownerName or "player", string_format("%d / %d", b.rank, b.maxRank), 1, 1, 1, 1, 1, 1)
                    end
                end
                if skill.description and skill.description ~= "" then
                    tip:AddLine(" ")
                    tip:AddLine(skill.description, 0.85, 0.85, 0.85, true)
                end
                tip:AddLine(" ")
                local profName = SKILL_ID_TO_PROF_NAME[skillID]
                if profName then
                    tip:AddLine("|cff888888left-click: open recipe catalogue|r", 1, 1, 1)
                    tip:AddLine("|cff888888middle-click: open skills panel|r", 1, 1, 1)
                else
                    tip:AddLine("|cff888888left-click: open skills panel|r", 1, 1, 1)
                end
                tip:AddLine("|cff888888shift-click or right-click: untrack skill|r", 1, 1, 1)
            end,
        })
    end

    if #blocks > 0 then
        return {
            {
                id       = "skills",
                noHeader = true,
                blocks   = blocks,
            }
        }
    end

    return nil
end

sfui.camelot_skills = {
    GetTrackedSkills = GetTrackedSkills,
    IsSkillTracked = IsSkillTracked,
    ToggleTrackedSkill = ToggleTrackedSkill,
    GetSkillCategoryInfo = GetSkillCategoryInfo,
    GetSkillInfo = GetSkillInfo,
    OpenSkillInUI = OpenSkillInUI,
    BroadcastTrackedSkills = function(force)
        ScheduleSkillsSyncBroadcast(force == true, force == true)
    end,
    HandleSyncMessage = HandleSkillsSyncMessage,
}

sfui.tracker.RegisterModule(CamelotSkillsModule)
return CamelotSkillsModule
