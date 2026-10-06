local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
local GameTooltip = sfui.common.get_tooltip()  -- private addon tooltip (methods.md §3.7.2)

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_quests.lua
--  Quest selection list + detail/reward panel for the Camelot Dungeon Journal.
--  Uses frame pooling for quest buttons and reward item rows.
--  Supports faction filtering (Alliance / Horde / Both), completion checks,
--  and interactive item reward tooltips/links.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

-- ─── Constants ────────────────────────────────────────────────────────────────
local QUEST_BTN_H    = 46
local QUEST_BTN_PAD  = 4
local REWARD_ROW_H   = 46
local REWARD_ROW_PAD = 4
local ICON_SZ        = 34
local QUEST_LIST_W   = 200

local theme  = sfui.theme
local common = sfui.common

-- ─── Locals & State ───────────────────────────────────────────────────────────
local questPanel        = nil
local questListScroll   = nil
local questListContent  = nil
local detailScroll      = nil
local detailContent     = nil
local questHeaderFrame  = nil

local questButtons      = {}
local rewardButtons     = {}

local selectedQuestIndex = 1
local debounceTimer      = nil

-- ─── Player Faction Helper ────────────────────────────────────────────────────
local function GetPlayerFaction()
    local _, faction = sfui.common.get_player_faction()
    return faction == "horde" and "horde" or "alliance"
end

-- ─── Database & State Access ──────────────────────────────────────────────────
local function DJ_DB()
    return sfui.dungeonjournal.GetDB()
end

local function GetCurrentDungeon()
    return sfui.dungeonjournal.GetCurrentDungeon()
end

-- ─── Quality Color Helper ─────────────────────────────────────────────────────
local function GetQualityColor(quality)
    return sfui.dungeonjournal.GetQualityColor(quality)
end

-- ─── Quest Status & Live Helpers ──────────────────────────────────────────────
local function IsQuestCompleted(questID)
    return sfui.dungeonjournal.IsQuestCompleted(questID)
end

local function IsQuestInLog(questID)
    return sfui.dungeonjournal.IsQuestActive(questID)
end

local function IsQuestShareable(questID, quest)
    if quest and quest.shareable ~= nil then
        return quest.shareable
    end
    if questID and _G.C_QuestLog and _G.C_QuestLog.IsPushableQuest then
        local ok, val = pcall(_G.C_QuestLog.IsPushableQuest, questID)
        if ok and val ~= nil then return val end
    end
    return nil
end

local function CanShareQuestNow(questID, quest)
    if not IsQuestInLog(questID) then return false end
    if not (_G.IsInGroup and _G.IsInGroup()) then return false end
    local shareable = IsQuestShareable(questID, quest)
    return shareable ~= false
end

local function ShareQuest(questID)
    if not questID then return end
    if sfui.api and sfui.api.ShareQuest then
        sfui.api.ShareQuest(questID)
        return
    end
    if _G.C_QuestLog and _G.C_QuestLog.SetSelectedQuest then
        pcall(_G.C_QuestLog.SetSelectedQuest, questID)
    end
    local logIndex = nil
    if _G.C_QuestLog and _G.C_QuestLog.GetLogIndexForQuestID then
        local ok, idx = pcall(_G.C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and type(idx) == "number" and idx > 0 then logIndex = idx end
    elseif _G.GetQuestLogIndexByID then
        local ok, idx = pcall(_G.GetQuestLogIndexByID, questID)
        if ok and type(idx) == "number" and idx > 0 then logIndex = idx end
    end
    if logIndex and _G.SelectQuestLogEntry then
        pcall(_G.SelectQuestLogEntry, logIndex)
    end
    if _G.QuestLogPushQuest then
        pcall(_G.QuestLogPushQuest)
    elseif _G.QuestFramePushQuestButton and _G.QuestFramePushQuestButton.Click then
        pcall(_G.QuestFramePushQuestButton.Click, _G.QuestFramePushQuestButton)
    end
end

local reusedObjectiveLines = {}
local function GetLiveQuestObjectives(questID)
    if not questID then return nil end
    if _G.C_QuestLog and _G.C_QuestLog.GetQuestObjectives then
        local ok, objectives = pcall(_G.C_QuestLog.GetQuestObjectives, questID)
        if ok and type(objectives) == "table" and #objectives > 0 then
            wipe(reusedObjectiveLines)
            for _, obj in ipairs(objectives) do
                if type(obj) == "table" and obj.text and obj.text ~= "" then
                    local isFinished = obj.finished or (obj.numRequired and obj.numRequired > 0 and obj.numFulfilled and obj.numFulfilled >= obj.numRequired)
                    if isFinished then
                        reusedObjectiveLines[#reusedObjectiveLines + 1] = "|cff00ff00[done]|r " .. obj.text
                    else
                        reusedObjectiveLines[#reusedObjectiveLines + 1] = "|cffffd100[ ]|r " .. obj.text
                    end
                end
            end
            if #reusedObjectiveLines > 0 then
                return table.concat(reusedObjectiveLines, "\n")
            end
        end
    end
    return nil
end

local function GetQuestObjectiveText(quest)
    if not quest then return nil end
    if quest.id and IsQuestInLog(quest.id) then
        local live = GetLiveQuestObjectives(quest.id)
        if live and live ~= "" then return live end
    end
    return quest.objective or quest.objectives or nil
end


-- ─── Quest Button Pool ────────────────────────────────────────────────────────
local function AcquireQuestButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then return btn end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(QUEST_BTN_H)
    common.apply_flat_backdrop(btn, { 0.08, 0.08, 0.10, 0.0 }, { 0, 0, 0, 0 })

    -- Faction / Status Icon
    local ico = btn:CreateTexture(nil, "ARTWORK")
    btn.icon = ico
    ico:SetSize(20, 20)
    ico:SetPoint("LEFT", btn, "LEFT", 6, 0)

    -- Quest Title (anchored to top of button)
    local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText = name
    name:SetPoint("TOPLEFT", btn, "TOPLEFT", 30, -6)
    name:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -26, -6)
    name:SetHeight(14)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    -- Status & Level subtext (anchored to bottom of button)
    local statusText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.statusText = statusText
    statusText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 30, 6)
    statusText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -26, 6)
    statusText:SetHeight(12)
    statusText:SetJustifyH("LEFT")
    statusText:SetWordWrap(false)

    -- Checkmark icon on right for completed quests
    local checkIcon = btn:CreateTexture(nil, "OVERLAY")
    btn.checkIcon = checkIcon
    checkIcon:SetSize(16, 16)
    checkIcon:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    checkIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    checkIcon:Hide()

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.25)

    pool[#pool + 1] = btn
    return btn
end

-- ─── Reward Button Pool ───────────────────────────────────────────────────────
local function AcquireRewardButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then return btn end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetHeight(REWARD_ROW_H)
    common.apply_flat_backdrop(btn, { 0.06, 0.06, 0.08, 0.7 }, { 0.15, 0.15, 0.18, 0.8 })

    -- Icon frame
    local iconBtn = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.iconBtn = iconBtn
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("LEFT", btn, "LEFT", 6, 0)
    iconBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    btn.iconTex = iconTex
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Item Name
    local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameText = nameText
    nameText:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, -2)
    nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -2)
    nameText:SetHeight(14)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    -- Subtext (Slot · Subclass)
    local subText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.subText = subText
    subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    subText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, 0)
    subText:SetHeight(12)
    subText:SetJustifyH("LEFT")
    subText:SetWordWrap(false)
    subText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.2)

    pool[#pool + 1] = btn
    return btn
end

local function ReleaseAll(pool)
    sfui.dungeonjournal.ReleaseAll(pool)
end

local function ResolveItemLink(btn, fallbackItemID)
    return sfui.dungeonjournal.ResolveItemLink(btn, fallbackItemID)
end

local function InsertItemLinkIntoChat(link)
    return sfui.dungeonjournal.InsertItemLinkIntoChat(link)
end

-- ─── Render Quest Detail ──────────────────────────────────────────────────────
local function RenderQuestDetail(quest, dungeon)
    if not detailScroll or not detailContent then return end
    ReleaseAll(rewardButtons)

    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }

    if not quest then
        if questHeaderFrame then
            questHeaderFrame.title:SetText("no quest selected")
            questHeaderFrame.sub:SetText("choose a quest from the list on the left")
        end
        if detailContent.infoFrame then detailContent.infoFrame:Hide() end
        detailContent:SetHeight(10)
        if detailScroll and detailScroll.SetVerticalScroll then
            detailScroll:SetVerticalScroll(0)
        end
        if detailScroll and detailScroll.ScrollBar and detailScroll.ScrollBar.UpdateVisibility then
            detailScroll.ScrollBar:UpdateVisibility()
        end
        return
    end

    -- Update Header
    if questHeaderFrame then
        local isDone   = IsQuestCompleted(quest.id)
        local isActive = not isDone and IsQuestInLog(quest.id)
        local qTitle   = quest.name or ("quest #" .. (quest.id or "?"))

        if isDone then
            questHeaderFrame.title:SetText(qTitle .. "  |cff00ff00[completed]|r")
            questHeaderFrame.title:SetTextColor(0.45, 0.95, 0.45, 1)
        elseif isActive then
            questHeaderFrame.title:SetText(qTitle .. "  |cff00e5ff[in quest log]|r")
            questHeaderFrame.title:SetTextColor(accent[1], accent[2], accent[3], 1)
        else
            questHeaderFrame.title:SetText(qTitle)
            questHeaderFrame.title:SetTextColor(accent[1], accent[2], accent[3], 1)
        end

        local fColor = "|cffffd100"
        local fLower = quest.faction and quest.faction:lower() or "both"
        if fLower == "alliance" then fColor = "|cff00aaff"
        elseif fLower == "horde" then fColor = "|cffff4444" end

        local tagsLine1 = {}
        if dungeon and dungeon.name then
            tagsLine1[#tagsLine1 + 1] = dungeon.name
        end
        local minLvl = quest.minLevel or (sfui.dj_camelot and sfui.dj_camelot.questMinLevels and sfui.dj_camelot.questMinLevels[quest.id])
        if minLvl and quest.level then
            tagsLine1[#tagsLine1 + 1] = "req lvl " .. minLvl .. "  ·  rec lvl " .. quest.level
        elseif quest.level then
            tagsLine1[#tagsLine1 + 1] = "level " .. quest.level
        end

        local tagsLine2 = {}
        if isDone then
            tagsLine2[#tagsLine2 + 1] = "|cff00ff00completed|r"
        elseif isActive then
            tagsLine2[#tagsLine2 + 1] = "|cff00e5ffpicked up (in log)|r"
        elseif minLvl and (UnitLevel("player") or 1) < minLvl then
            tagsLine2[#tagsLine2 + 1] = "|cffff4444locked (req lvl " .. minLvl .. ")|r"
        else
            tagsLine2[#tagsLine2 + 1] = "|cffffaa00not picked up|r"
        end
        if quest.faction then
            tagsLine2[#tagsLine2 + 1] = fColor .. fLower .. "|r"
        end
        if quest.pickedUpInDungeon then
            tagsLine2[#tagsLine2 + 1] = "|cff00e5ffinside dungeon|r"
        end
        if quest.hasPrereq or quest.prereq or (quest.prerequisites and #quest.prerequisites > 0) then
            tagsLine2[#tagsLine2 + 1] = "|cffffaa00quest chain|r"
        end
        local shareable = IsQuestShareable(quest.id, quest)
        if shareable == true then
            tagsLine2[#tagsLine2 + 1] = "|cff00ff00shareable|r"
        elseif shareable == false then
            tagsLine2[#tagsLine2 + 1] = "|cff888888not shareable|r"
        end

        local str1 = table.concat(tagsLine1, "  ·  ")
        local str2 = table.concat(tagsLine2, "  ·  ")
        if str2 ~= "" then
            questHeaderFrame.sub:SetText(str1 .. "\n" .. str2)
        else
            questHeaderFrame.sub:SetText(str1)
        end
    end

    -- Details Info Container
    local info = detailContent.infoFrame
    if not info then
        info = CreateFrame("Frame", nil, detailContent)
        detailContent.infoFrame = info
        info:SetPoint("TOPLEFT",  detailContent, "TOPLEFT",  8, -6)
        info:SetPoint("TOPRIGHT", detailContent, "TOPRIGHT", -8, -6)

        local FONT_DESC  = _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal"
        local FONT_LABEL = _G.GameFontHighlightMed2 and "GameFontHighlightMed2" or (_G.GameFontHighlight and "GameFontHighlight" or "GameFontNormal")

        local oLabel = info:CreateFontString(nil, "OVERLAY", FONT_LABEL)
        info.oLabel = oLabel
        oLabel:SetText("objectives:")
        oLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

        local oText = info:CreateFontString(nil, "OVERLAY", FONT_DESC)
        info.oText = oText
        oText:SetJustifyH("LEFT")
        oText:SetWordWrap(true)

        local pLabel = info:CreateFontString(nil, "OVERLAY", FONT_LABEL)
        info.pLabel = pLabel
        pLabel:SetText("starts from:")
        pLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

        local pText = info:CreateFontString(nil, "OVERLAY", FONT_DESC)
        info.pText = pText
        pText:SetJustifyH("LEFT")
        pText:SetWordWrap(true)

        local tLabel = info:CreateFontString(nil, "OVERLAY", FONT_LABEL)
        info.tLabel = tLabel
        tLabel:SetText("turns in to:")
        tLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

        local tText = info:CreateFontString(nil, "OVERLAY", FONT_DESC)
        info.tText = tText
        tText:SetJustifyH("LEFT")
        tText:SetWordWrap(true)

        local cLabel = info:CreateFontString(nil, "OVERLAY", FONT_LABEL)
        info.cLabel = cLabel
        cLabel:SetText("prerequisite:")
        cLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

        local cText = info:CreateFontString(nil, "OVERLAY", FONT_DESC)
        info.cText = cText
        cText:SetJustifyH("LEFT")
        cText:SetWordWrap(true)

        local rLabel = detailContent:CreateFontString(nil, "OVERLAY", FONT_LABEL)
        info.rLabel = rLabel
        rLabel:SetText("rewards:")
        rLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

        -- Share button
        local shareBtn = CreateFrame("Button", nil, info, "BackdropTemplate")
        info.shareBtn = shareBtn
        shareBtn:SetSize(130, 22)
        local sfs = shareBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        shareBtn.fs = sfs
        sfs:SetPoint("CENTER")
        sfs:SetText("share quest")

        if sfui.theme and sfui.theme.ApplyButtonStyle then
            sfui.theme.ApplyButtonStyle(shareBtn, false)
            sfui.theme.RegisterButton(shareBtn, false)
        else
            common.apply_flat_backdrop(shareBtn, { 0.10, 0.10, 0.14, 0.9 })
            shareBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            sfs:SetTextColor(accent[1], accent[2], accent[3], 1)
        end

        shareBtn:SetScript("OnEnter", function(self)
            if not self._sfuiCamelotBg then
                self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
            end
        end)
        shareBtn:SetScript("OnLeave", function(self)
            if not self._sfuiCamelotBg then
                self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            end
        end)

        shareBtn:SetScript("OnClick", function()
            local q = detailContent.activeQuest
            if q and q.id then
                ShareQuest(q.id)
            end
        end)

        -- Helper to resolve mapID and coordinates for any quest
        local function ResolveQuestMapCoords(quest)
            if not quest or not quest.id then return nil end
            local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)

            -- 0. Prerequisite chain step: point to the current step the player is on
            if sfui.dungeonjournal and sfui.dungeonjournal.GetQuestChainInfo then
                local steps, currentStep, currentStepIndex, allDone = sfui.dungeonjournal.GetQuestChainInfo(quest)
                if steps and currentStep then
                    local c = currentStep.coords or (db and ((db.GetQuestCoords and db.GetQuestCoords(currentStep.id)) or (db.questCoords and db.questCoords[currentStep.id])))
                    if c and c.mapID then
                        local x = c.x
                        local y = c.y
                        if x and x > 1 then x = x / 100 end
                        if y and y > 1 then y = y / 100 end
                        return c.mapID, x, y, "chain_step", currentStep
                    end
                end
            end

            -- 1. Explicit quest coordinates from database
            local c = db and ((db.GetQuestCoords and db.GetQuestCoords(quest.id)) or (db.questCoords and db.questCoords[quest.id]))
            if c and c.mapID then
                local x = c.x
                local y = c.y
                if x and x > 1 then x = x / 100 end
                if y and y > 1 then y = y / 100 end
                return c.mapID, x, y, "quest"
            end

            -- 2. Quest log API map (if quest is in log)
            if C_QuestLog and C_QuestLog.GetQuestUiMapID then
                local ok, qMap = pcall(C_QuestLog.GetQuestUiMapID, quest.id)
                if ok and qMap and qMap > 0 then
                    return qMap, nil, nil, "questlog"
                end
            end

            -- 3. Dungeon entrance coordinates
            local dungeon = GetCurrentDungeon()
            if dungeon and dungeon.entrance and dungeon.entrance.mapID then
                local ent = dungeon.entrance
                local x = ent.x
                local y = ent.y
                if x and x > 1 then x = x / 100 end
                if y and y > 1 then y = y / 100 end
                return ent.mapID, x, y, "entrance"
            end

            -- 4. Dungeon zoneMapID or mapID
            if dungeon and (dungeon.zoneMapID or dungeon.mapID) then
                return dungeon.zoneMapID or dungeon.mapID, nil, nil, "dungeon"
            end

            return nil
        end
        info.ResolveQuestMapCoords = ResolveQuestMapCoords

        -- Show on Map button
        local mapBtn = CreateFrame("Button", nil, info, "BackdropTemplate")
        info.mapBtn = mapBtn
        mapBtn:SetSize(130, 22)
        local mfs = mapBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        mapBtn.fs = mfs
        mfs:SetPoint("CENTER")
        mfs:SetText("show on map")

        if sfui.theme and sfui.theme.ApplyButtonStyle then
            sfui.theme.ApplyButtonStyle(mapBtn, false)
            sfui.theme.RegisterButton(mapBtn, false)
        else
            common.apply_flat_backdrop(mapBtn, { 0.10, 0.10, 0.14, 0.9 })
            mapBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            mfs:SetTextColor(accent[1], accent[2], accent[3], 1)
        end

        mapBtn:SetScript("OnEnter", function(self)
            if not self._sfuiCamelotBg then
                self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("show on map", accent[1], accent[2], accent[3])
            local q = detailContent.activeQuest
            local mapID, x, y, src, step = ResolveQuestMapCoords(q)
            if src == "chain_step" and step then
                GameTooltip:AddLine(string.format("Opens map and places a waypoint at current step: %s (%s).", tostring(step.name or "chain step"), tostring(step.pickup or "")), 1, 1, 1, true)
            elseif src == "quest" then
                GameTooltip:AddLine("opens map and places a waypoint at the quest pickup location.", 1, 1, 1, true)
            elseif src == "entrance" then
                GameTooltip:AddLine("opens map and places a waypoint at the dungeon entrance.", 1, 1, 1, true)
            else
                GameTooltip:AddLine("opens the world map for this dungeon's zone.", 1, 1, 1, true)
            end
            if mapID and C_Map and C_Map.GetMapInfo then
                local minfo = C_Map.GetMapInfo(mapID)
                if minfo and minfo.name then
                    GameTooltip:AddLine(string.format("|cff888888Zone: %s|r", minfo.name))
                end
            end
            GameTooltip:Show()
        end)

        mapBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            GameTooltip:Hide()
        end)

        mapBtn:SetScript("OnClick", function()
            local q = detailContent.activeQuest
            if not q or not q.id then return end

            local mapID, x, y, src, step = ResolveQuestMapCoords(q)
            if not mapID then return end

            local waypointSet = false
            if x and y and C_Map and UiMapPoint and UiMapPoint.CreateFromCoordinates then
                local canSet = true
                if C_Map.CanSetUserWaypointOnMap then
                    local ok, allowed = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
                    if ok and allowed == false then
                        canSet = false
                    end
                end
                if canSet and C_Map.SetUserWaypoint then
                    local ok, pt = pcall(UiMapPoint.CreateFromCoordinates, mapID, x, y)
                    if ok and pt then
                        local okSet = pcall(C_Map.SetUserWaypoint, pt)
                        if okSet then
                            waypointSet = true
                            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                            end
                        end
                    end
                end
            end

            -- TomTom integration if present
            if x and y and _G.TomTom and _G.TomTom.AddWaypoint then
                local wpTitle = (src == "chain_step" and step and step.name) or q.name or "Dungeon Quest"
                pcall(_G.TomTom.AddWaypoint, _G.TomTom, mapID, x, y, {
                    title = wpTitle,
                    persistent = false,
                    minimap = true,
                    world = true,
                })
            end


            -- Open the World Map to this mapID
            if waypointSet and _G.OpenMapToUserWaypoint then
                pcall(_G.OpenMapToUserWaypoint)
            elseif _G.OpenWorldMap then
                pcall(_G.OpenWorldMap, mapID)
            else
                if _G.ShowUIPanel and _G.WorldMapFrame then
                    pcall(_G.ShowUIPanel, _G.WorldMapFrame)
                elseif _G.WorldMapFrame then
                    _G.WorldMapFrame:Show()
                end
                if _G.WorldMapFrame and _G.WorldMapFrame.SetMapID then
                    pcall(_G.WorldMapFrame.SetMapID, _G.WorldMapFrame, mapID)
                end
            end

            -- Fallback verification: ensure WorldMapFrame is shown and set to mapID
            if _G.WorldMapFrame then
                if not _G.WorldMapFrame:IsShown() then
                    if _G.ShowUIPanel then
                        pcall(_G.ShowUIPanel, _G.WorldMapFrame)
                    else
                        _G.WorldMapFrame:Show()
                    end
                end
                if _G.WorldMapFrame.GetMapID and _G.WorldMapFrame.SetMapID then
                    local curID = _G.WorldMapFrame:GetMapID()
                    if curID ~= mapID then
                        pcall(_G.WorldMapFrame.SetMapID, _G.WorldMapFrame, mapID)
                    end
                end
            end

            -- Ensure Dungeon Journal remains open, visible, and elevated above the WorldMap
            local djFrame = (sfui.dungeonjournal and sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame())
                         or (sfui.dungeonjournal and sfui.dungeonjournal.frame)
            if djFrame then
                if not djFrame:IsShown() then
                    djFrame:Show()
                end
                if djFrame.Raise then
                    pcall(djFrame.Raise, djFrame)
                end
            end
        end)

        -- Divider between text details and item rewards
        local div = info:CreateTexture(nil, "ARTWORK")
        info.div = div
        div:SetHeight(1)
        div:SetColorTexture(0.2, 0.2, 0.24, 0.8)
    end

    detailContent.activeQuest = quest
    info:Show()

    local currY = 0

    -- 1. Objectives (live or static)
    local isDone = IsQuestCompleted(quest.id)
    local objText = GetQuestObjectiveText(quest)
    if objText and objText ~= "" then
        info.oLabel:Show()
        info.oText:Show()

        if isDone then
            info.oLabel:SetText("objectives:  |cff00ff00[completed]|r")
            info.oLabel:SetTextColor(0.45, 0.95, 0.45, 1)
        else
            info.oLabel:SetText("objectives:")
            info.oLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
        end

        info.oLabel:ClearAllPoints()
        info.oLabel:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
        local oLabelH = math.max(14, math.ceil(info.oLabel:GetStringHeight() or 14))
        currY = currY + oLabelH + 3

        info.oText:ClearAllPoints()
        info.oText:SetPoint("TOPLEFT",  info, "TOPLEFT",  0, -currY)
        info.oText:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, -currY)
        info.oText:SetText(objText)
        local oH = math.max(16, math.ceil(info.oText:GetStringHeight() or 16))
        currY = currY + oH + 10
    else
        info.oLabel:Hide()
        info.oText:Hide()
    end

    -- 2. Starts from
    info.pLabel:ClearAllPoints()
    info.pLabel:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
    local pLabelH = math.max(14, math.ceil(info.pLabel:GetStringHeight() or 14))
    currY = currY + pLabelH + 3

    info.pText:ClearAllPoints()
    info.pText:SetPoint("TOPLEFT",  info, "TOPLEFT",  0, -currY)
    info.pText:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, -currY)
    local pickupStatusStr = ""
    if isDone then
        pickupStatusStr = "  |cff00ff00[completed]|r"
    elseif isActive then
        pickupStatusStr = "  |cff00e5ff[picked up]|r"
    else
        pickupStatusStr = "  |cffffaa00[not picked up]|r"
    end
    local pickupStr = (quest.pickup or "unknown quest giver") .. pickupStatusStr
    if quest.pickedUpInDungeon then
        pickupStr = pickupStr .. "  |cff00e5ff(inside dungeon)|r"
    end
    info.pText:SetText(pickupStr)
    local pH = math.max(16, math.ceil(info.pText:GetStringHeight() or 16))
    currY = currY + pH + 10

    -- 3. Turns in to
    info.tLabel:ClearAllPoints()
    info.tLabel:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
    local tLabelH = math.max(14, math.ceil(info.tLabel:GetStringHeight() or 14))
    currY = currY + tLabelH + 3

    info.tText:ClearAllPoints()
    info.tText:SetPoint("TOPLEFT",  info, "TOPLEFT",  0, -currY)
    info.tText:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, -currY)
    info.tText:SetText(quest.turnin or "unknown turn-in npc")
    local tH = math.max(16, math.ceil(info.tText:GetStringHeight() or 16))
    currY = currY + tH + 10

    -- 4. Prerequisite / Chain (if applicable)
    local steps, currentStep, currentStepIndex, allDone = nil, nil, nil, nil
    if sfui.dungeonjournal and sfui.dungeonjournal.GetQuestChainInfo then
        steps, currentStep, currentStepIndex, allDone = sfui.dungeonjournal.GetQuestChainInfo(quest)
    end

    local hasPrereq = quest.hasPrereq or quest.prereq or (quest.prerequisites and #quest.prerequisites > 0)
    local prereqDesc = quest.prereqText or quest.note
    if (steps and #steps > 0) or hasPrereq or prereqDesc then
        info.cLabel:Show()
        info.cText:Show()

        if steps and #steps > 0 then
            info.cLabel:SetText(string.format("quest chain (%d steps):", #steps))
            info.cLabel:SetTextColor(accent[1], accent[2], accent[3], 1)

            local lines = {}
            if prereqDesc then
                lines[#lines + 1] = "|cffaaaaaa" .. prereqDesc .. "|r"
            end

            for i, s in ipairs(steps) do
                local sDone = s.id and IsQuestCompleted(s.id)
                local sActive = s.id and IsQuestInLog(s.id)
                local statusBadge = ""
                local titleColor = "|cffffffff"
                local numColor = "|cff888888"

                if sDone then
                    statusBadge = "  |cff00ff00[completed]|r"
                    titleColor = "|cff888888"
                elseif sActive then
                    statusBadge = "  |cff00e5ff[in progress]|r"
                    titleColor = "|cff00e5ff"
                    numColor = "|cff00e5ff"
                elseif i == currentStepIndex then
                    statusBadge = "  |cffffd100[current step]|r"
                    titleColor = "|cffffd100"
                    numColor = "|cffffd100"
                else
                    statusBadge = "  |cff666666[locked]|r"
                    titleColor = "|cff777777"
                end

                local dTag = s.isDungeonQuest and " |cff00bfff(dungeon quest)|r" or ""
                local sName = s.name or ("Quest #" .. tostring(s.id))
                local stepHeader = string.format("%s%d.|r %s%s|r%s", numColor, i, titleColor, sName, dTag, statusBadge)
                if s.pickup and s.pickup ~= "" then
                    local locStr = string.format("     |cff888888starts from: %s|r", s.pickup)
                    lines[#lines + 1] = stepHeader .. "\n" .. locStr
                else
                    lines[#lines + 1] = stepHeader
                end
            end
            info.cText:SetText(table.concat(lines, "\n\n"))
        else
            info.cLabel:SetText("prerequisite:")
            info.cLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
            info.cText:SetText(prereqDesc or "part of a quest chain (requires prerequisite quests)")
        end

        info.cLabel:ClearAllPoints()
        info.cLabel:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
        local cLabelH = math.max(14, math.ceil(info.cLabel:GetStringHeight() or 14))
        currY = currY + cLabelH + 4

        info.cText:ClearAllPoints()
        info.cText:SetPoint("TOPLEFT",  info, "TOPLEFT",  0, -currY)
        info.cText:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, -currY)
        local cH = math.max(16, math.ceil(info.cText:GetStringHeight() or 16))
        currY = currY + cH + 12
    else
        info.cLabel:Hide()
        info.cText:Hide()
    end

    -- 5. Action Buttons (Share Quest & Show on Map)
    local hasShare = CanShareQuestNow(quest.id, quest)
    local resolveFn = info.ResolveQuestMapCoords
    local hasMap = resolveFn and (resolveFn(quest) ~= nil)
    if hasMap == nil then
        local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
        local qcoords = db and ((db.GetQuestCoords and db.GetQuestCoords(quest.id)) or (db.questCoords and db.questCoords[quest.id]))
        hasMap = (qcoords ~= nil) or (GetCurrentDungeon() ~= nil)
    end

    if info.shareBtn then
        if hasShare then
            info.shareBtn:ClearAllPoints()
            info.shareBtn:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
            info.shareBtn:Show()
        else
            info.shareBtn:Hide()
        end
    end

    if info.mapBtn then
        if hasMap then
            info.mapBtn:ClearAllPoints()
            if hasShare and info.shareBtn:IsShown() then
                info.mapBtn:SetPoint("LEFT", info.shareBtn, "RIGHT", 8, 0)
            else
                info.mapBtn:SetPoint("TOPLEFT", info, "TOPLEFT", 0, -currY)
            end
            info.mapBtn:Show()
        else
            info.mapBtn:Hide()
        end
    end

    if (hasShare and info.shareBtn:IsShown()) or (hasMap and info.mapBtn:IsShown()) then
        currY = currY + 22 + 10
    end

    -- Divider & Item Rewards
    local rewardItems = quest.rewardItems or {}
    local textBlockHeight = currY + 4
    info:SetHeight(textBlockHeight)

    if #rewardItems > 0 then
        info.div:ClearAllPoints()
        info.div:SetPoint("TOPLEFT",  info, "TOPLEFT",  0, -textBlockHeight)
        info.div:SetPoint("TOPRIGHT", info, "TOPRIGHT", 0, -textBlockHeight)
        info.div:Show()

        local startY = textBlockHeight + 14

        info.rLabel:Show()
        info.rLabel:ClearAllPoints()
        info.rLabel:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 8, -startY)
        local rLabelH = math.max(14, math.ceil(info.rLabel:GetStringHeight() or 14))
        startY = startY + rLabelH + 6

        for _, itemID in ipairs(rewardItems) do
            local btn = AcquireRewardButton(rewardButtons, detailContent)
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT",  detailContent, "TOPLEFT",  8, -startY)
            btn:SetPoint("TOPRIGHT", detailContent, "TOPRIGHT", -8, -startY)
            btn:SetHeight(REWARD_ROW_H)

            local name, link, quality, iLevel, reqLevel, class, subclass, _, equipSlot, icon = common.get_item_info(itemID)

            if not name or not icon then
                local instName, _, instQuality, _, _, _, _, _, instEquipLoc, instIcon = common.get_item_instant_info(itemID)
                name      = instName or ("item #" .. itemID)
                quality   = instQuality or 1
                icon      = instIcon or 134400
                equipSlot = instEquipLoc
                if common and common.request_item_load then
                    common.request_item_load(itemID)
                elseif _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                    pcall(_G.C_Item.RequestLoadItemDataByID, itemID)
                end
            end

            btn.itemID = itemID
            btn.link   = link

            local r, g, b = GetQualityColor(quality)

            btn.iconTex:SetTexture(icon or 134400)
            btn.iconBtn:SetBackdropBorderColor(r, g, b, 0.8)

            btn.nameText:SetText(name or ("item #" .. itemID))
            btn.nameText:SetTextColor(r, g, b, 1)

            local slotText = equipSlot and _G[equipSlot] or equipSlot
            local subLabel = ""
            if slotText and subclass and subclass ~= "" then
                subLabel = tostring(slotText):lower() .. "  ·  " .. tostring(subclass):lower()
            elseif slotText then
                subLabel = tostring(slotText):lower()
            elseif subclass then
                subLabel = tostring(subclass):lower()
            elseif class then
                subLabel = tostring(class):lower()
            end

            if subLabel and subLabel ~= "" then
                btn.subText:SetText(subLabel)
                btn.subText:Show()
                btn.nameText:ClearAllPoints()
                btn.nameText:SetPoint("TOPLEFT", btn.iconBtn, "TOPRIGHT", 8, -2)
                btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, -2)
                btn.subText:ClearAllPoints()
                btn.subText:SetPoint("TOPLEFT", btn.nameText, "BOTTOMLEFT", 0, -3)
                btn.subText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -8, 0)
            else
                btn.subText:SetText("")
                btn.subText:Hide()
                btn.nameText:ClearAllPoints()
                btn.nameText:SetPoint("LEFT", btn.iconBtn, "RIGHT", 8, 0)
                btn.nameText:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
            end

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local itemLink = ResolveItemLink(self, itemID)
                if itemLink then
                    GameTooltip:SetHyperlink(itemLink)
                else
                    GameTooltip:SetItemByID(itemID)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff888888<shift-click to link · ctrl-click to view>|r", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            btn:SetScript("OnClick", function(self, mouseBtn)
                sfui.dungeonjournal.HandleItemClick(self, mouseBtn, itemID)
            end)

            btn:Show()
            startY = startY + REWARD_ROW_H + REWARD_ROW_PAD
        end
        detailContent:SetHeight(math.max(1, startY + 10))
    else
        info.div:Hide()
        info.rLabel:Hide()
        detailContent:SetHeight(math.max(1, textBlockHeight + 14))
    end
    if detailScroll and detailScroll.ScrollBar and detailScroll.ScrollBar.UpdateVisibility then
        detailScroll.ScrollBar:UpdateVisibility()
    end
end

-- ─── Filter Quests by Player Faction ─────────────────────────────────────────
local filteredQuests = {}
local function GetFilteredQuests(allQuests)
    wipe(filteredQuests)
    if not allQuests or #allQuests == 0 then return filteredQuests end

    local playerFaction = GetPlayerFaction()
    for _, q in ipairs(allQuests) do
        local f = q.faction and q.faction:lower() or "both"
        if f == "both" or f == playerFaction then
            filteredQuests[#filteredQuests + 1] = q
        end
    end
    return filteredQuests
end

-- ─── Render Quest List ────────────────────────────────────────────────────────
local function RefreshQuestView()
    if not questPanel or not questPanel:IsShown() then return end

    local dungeon   = GetCurrentDungeon()
    local allQuests = dungeon and dungeon.quests or {}
    local quests    = GetFilteredQuests(allQuests)

    ReleaseAll(questButtons)

    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
    local pLvl   = UnitLevel("player") or 1

    local savedQuest = DJ_DB().lastQuest or 1
    if savedQuest > #quests then savedQuest = 1 end
    selectedQuestIndex = savedQuest

    local y = 0
    for idx, q in ipairs(quests) do
        local btn = AcquireQuestButton(questButtons, questListContent)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  questListContent, "TOPLEFT",  0, -y)
        btn:SetPoint("TOPRIGHT", questListContent, "TOPRIGHT", 0, -y)
        btn:SetHeight(QUEST_BTN_H)

        -- Status check
        local isDone   = IsQuestCompleted(q.id)
        local isActive = not isDone and IsQuestInLog(q.id)
        local isSelected = (idx == selectedQuestIndex)

        -- Icon & Checkmark
        if isDone then
            btn.checkIcon:Show()
            btn.icon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            btn.icon:SetTexCoord(0, 1, 0, 1)
            btn.icon:SetVertexColor(1, 1, 1, 1)
        elseif isActive then
            btn.checkIcon:Hide()
            btn.icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
            btn.icon:SetTexCoord(0, 1, 0, 1)
            btn.icon:SetVertexColor(1, 1, 1, 1)
        else
            btn.checkIcon:Hide()
            local f = q.faction and q.faction:lower() or "both"
            if f == "alliance" then
                btn.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
                btn.icon:SetTexCoord(0.04, 0.60, 0.04, 0.60)
            elseif f == "horde" then
                btn.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Horde")
                btn.icon:SetTexCoord(0.04, 0.60, 0.04, 0.60)
            else
                btn.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                btn.icon:SetTexCoord(0, 1, 0, 1)
            end
            btn.icon:SetVertexColor(1, 1, 1, 1)
        end

        -- Title & Background Styling
        local qTitle = q.name or ("quest #" .. (q.id or idx))
        if isDone then
            btn.nameText:SetText(qTitle)
            if isSelected then
                btn.nameText:SetTextColor(0.40, 0.95, 0.40, 1)
                btn:SetBackdropColor(0.06, 0.18, 0.08, 0.95)
                btn:SetBackdropBorderColor(0.25, 0.85, 0.35, 0.9)
            else
                btn.nameText:SetTextColor(0.55, 0.80, 0.55, 1)
                btn:SetBackdropColor(0.04, 0.11, 0.05, 0.60)
                btn:SetBackdropBorderColor(0.15, 0.45, 0.20, 0.70)
            end
        else
            btn.nameText:SetText(qTitle)
            if isSelected then
                btn.nameText:SetTextColor(accent[1], accent[2], accent[3], 1)
                btn:SetBackdropColor(0.14, 0.14, 0.18, 0.95)
                btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
            else
                if isActive then
                    btn.nameText:SetTextColor(1, 1, 1, 1)
                else
                    btn.nameText:SetTextColor(0.85, 0.85, 0.85, 1)
                end
                btn:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
                btn:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end

        local minLvl = q.minLevel or (sfui.dj_camelot and sfui.dj_camelot.questMinLevels and sfui.dj_camelot.questMinLevels[q.id])
        local lvlStr = q.level and ("[" .. q.level .. "] ") or ""
        local statusStr = ""
        if isDone then
            statusStr = lvlStr .. "|cff00ff00completed|r"
        elseif isActive then
            statusStr = lvlStr .. "|cff00e5ffpicked up|r"
        elseif minLvl and pLvl < minLvl then
            statusStr = lvlStr .. "|cffff4444req lvl " .. minLvl .. "|r"
        else
            statusStr = lvlStr .. "|cffffaa00not picked up|r"
        end

        -- Badges
        local badges = {}
        if q.pickedUpInDungeon then
            badges[#badges + 1] = "|cff00e5ffinside|r"
        end
        if q.hasPrereq or q.prereq or (q.prerequisites and #q.prerequisites > 0) then
            badges[#badges + 1] = "|cffffaa00chain|r"
        end
        local shareable = IsQuestShareable(q.id, q)
        if shareable == false then
            badges[#badges + 1] = "|cff888888no share|r"
        end

        if #badges > 0 then
            btn.statusText:SetText(statusStr .. "  ·  " .. table.concat(badges, " · "))
        else
            btn.statusText:SetText(statusStr)
        end

        local currentIdx = idx
        btn:SetScript("OnClick", function()
            selectedQuestIndex = currentIdx
            DJ_DB().lastQuest = currentIdx
            RefreshQuestView()
        end)

        btn:Show()
        y = y + QUEST_BTN_H + QUEST_BTN_PAD
    end

    questListContent:SetHeight(math.max(1, y))
    if questListScroll and questListScroll.ScrollBar and questListScroll.ScrollBar.UpdateVisibility then
        questListScroll.ScrollBar:UpdateVisibility()
    end

    -- Update Top Notifier Bar (e.g. "(p 1/6 - c 3/6)")
    if questPanel and questPanel.questSummaryBar then
        local inProg = 0
        local completed = 0
        local total = #quests
        for _, q in ipairs(quests) do
            if IsQuestCompleted(q.id) then
                completed = completed + 1
            elseif IsQuestInLog(q.id) then
                inProg = inProg + 1
            end
        end

        local hasVisibleProgress = (total > 0) and (completed < total) and (inProg > 0 or completed > 0)

        if hasVisibleProgress then
            local pStr = (inProg > 0) and string.format("|cff00e5ffp %d/%d|r", inProg, total) or string.format("|cff777777p %d/%d|r", inProg, total)
            local cStr = (completed > 0) and string.format("|cff00ff00c %d/%d|r", completed, total) or string.format("|cff777777c %d/%d|r", completed, total)
            questPanel.questSummaryBar.text:SetText(string.format("|cff888888(|r%s |cff666666-|r %s|cff888888)|r", pStr, cStr))
            questPanel.questSummaryBar:Show()
            if questListScroll and questPanel.questListContainer then
                questListScroll:ClearAllPoints()
                questListScroll:SetPoint("TOPLEFT", questPanel.questSummaryBar, "BOTTOMLEFT", 0, -3)
                questListScroll:SetPoint("BOTTOMRIGHT", questPanel.questListContainer, "BOTTOMRIGHT", -22, 4)
            end
        else
            questPanel.questSummaryBar.text:SetText("")
            questPanel.questSummaryBar:Hide()
            if questListScroll and questPanel.questListContainer then
                questListScroll:ClearAllPoints()
                questListScroll:SetPoint("TOPLEFT", questPanel.questListContainer, "TOPLEFT", 4, -4)
                questListScroll:SetPoint("BOTTOMRIGHT", questPanel.questListContainer, "BOTTOMRIGHT", -22, 4)
            end
        end

        questPanel.questSummaryBar:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("dungeon quest progress", 1, 0.82, 0)
            GameTooltip:AddLine(string.format("in progress (picked up): %d / %d", inProg, total), 0, 0.9, 1)
            GameTooltip:AddLine(string.format("completed: %d / %d", completed, total), 0, 1, 0)
            GameTooltip:AddLine(string.format("not picked up: %d / %d", total - inProg - completed, total), 0.75, 0.75, 0.75)
            GameTooltip:Show()
        end)
        questPanel.questSummaryBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Render the currently selected quest details
    local currentQuest = quests[selectedQuestIndex]
    RenderQuestDetail(currentQuest, dungeon)
end

-- ─── Debounced Item Load Refresh ──────────────────────────────────────────────
local isQuestRefreshQueued = false

local function QueueQuestRefresh(itemID)
    if not questPanel or not questPanel:IsShown() then return end
    if isQuestRefreshQueued then return end

    if itemID then
        local dungeon   = GetCurrentDungeon()
        local allQuests = dungeon and dungeon.quests or {}
        local quests    = GetFilteredQuests(allQuests)
        local currentQuest = quests[selectedQuestIndex]
        if not currentQuest or not currentQuest.rewardItems then return end
        local found = false
        for _, id in ipairs(currentQuest.rewardItems) do
            if id == itemID then
                found = true
                break
            end
        end
        if not found then return end
    end

    isQuestRefreshQueued = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0.15, function()
            isQuestRefreshQueued = false
            if questPanel and questPanel:IsShown() then
                local dungeon   = GetCurrentDungeon()
                local allQuests = dungeon and dungeon.quests or {}
                local quests    = GetFilteredQuests(allQuests)
                local currentQuest = quests[selectedQuestIndex]
                if currentQuest then
                    RenderQuestDetail(currentQuest, dungeon)
                end
            end
        end)
    else
        isQuestRefreshQueued = false
    end
end

-- ─── Build UI Structure ───────────────────────────────────────────────────────
local function OnFrameCreated(arg1, arg2)
    local payload = (type(arg1) == "table" and arg1) or arg2
    if not payload or not payload.questPanel then return end
    if detailScroll then return end -- already initialized
    questPanel = payload.questPanel

    -- ── Left Sub-Panel: Quest List Container ──────────────────────────────────
    local questListContainer = CreateFrame("Frame", nil, questPanel, "BackdropTemplate")
    questListContainer:SetPoint("TOPLEFT",    questPanel, "TOPLEFT",    0, 0)
    questListContainer:SetPoint("BOTTOMLEFT", questPanel, "BOTTOMLEFT", 0, 0)
    questListContainer:SetWidth(QUEST_LIST_W)
    theme.ApplyContainerStyle(questListContainer)

    -- Top Notifier Bar (e.g. "(p 1/6 - c 3/6)")
    local questSummaryBar = CreateFrame("Frame", nil, questListContainer, "BackdropTemplate")
    questPanel.questSummaryBar = questSummaryBar
    questSummaryBar:SetPoint("TOPLEFT",  questListContainer, "TOPLEFT",  4, -4)
    questSummaryBar:SetPoint("TOPRIGHT", questListContainer, "TOPRIGHT", -4, -4)
    questSummaryBar:SetHeight(22)
    common.apply_flat_backdrop(questSummaryBar, { 0.06, 0.06, 0.08, 0.85 }, { 0.18, 0.18, 0.22, 0.8 })

    local sumText = questSummaryBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questSummaryBar.text = sumText
    sumText:SetPoint("CENTER")
    sumText:SetText("")

    -- ScrollFrame below summary bar (width: 200 - 6 - 22 = 172)
    questListScroll = CreateFrame("ScrollFrame", "SfuiDJQuestListScroll", questListContainer, "UIPanelScrollFrameTemplate")
    questListScroll:SetPoint("TOPLEFT",     questSummaryBar,    "BOTTOMLEFT",  0, -3)
    questListScroll:SetPoint("BOTTOMRIGHT", questListContainer, "BOTTOMRIGHT", -22, 4)

    local QUEST_SCROLL_W = 172
    questListContent = CreateFrame("Frame", nil, questListScroll)
    questListContent:SetSize(QUEST_SCROLL_W, 1)
    questListScroll:SetScrollChild(questListContent)

    if questListScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(questListScroll.ScrollBar)
    end

    -- ── Right Sub-Panel: Quest Detail Container ───────────────────────────────
    local detailContainer = CreateFrame("Frame", nil, questPanel, "BackdropTemplate")
    detailContainer:SetPoint("TOPLEFT",     questListContainer, "TOPRIGHT",    8, 0)
    detailContainer:SetPoint("BOTTOMRIGHT", questPanel,         "BOTTOMRIGHT", 0, 0)
    theme.ApplyContainerStyle(detailContainer)

    -- Header in Detail Container
    questHeaderFrame = CreateFrame("Frame", nil, detailContainer)
    questHeaderFrame:SetPoint("TOPLEFT",  detailContainer, "TOPLEFT",  10, -8)
    questHeaderFrame:SetPoint("TOPRIGHT", detailContainer, "TOPRIGHT", -10, -8)
    questHeaderFrame:SetHeight(58)

    local qTitle = questHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    questHeaderFrame.title = qTitle
    qTitle:SetPoint("TOPLEFT", questHeaderFrame, "TOPLEFT", 0, 0)
    qTitle:SetPoint("TOPRIGHT", questHeaderFrame, "TOPRIGHT", 0, 0)
    qTitle:SetJustifyH("LEFT")

    local qSub = questHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    questHeaderFrame.sub = qSub
    qSub:SetPoint("TOPLEFT", qTitle, "BOTTOMLEFT", 0, -4)
    qSub:SetPoint("TOPRIGHT", questHeaderFrame, "TOPRIGHT", 0, -4)
    qSub:SetJustifyH("LEFT")
    qSub:SetSpacing(2)
    qSub:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Divider under header
    local div = detailContainer:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT",  questHeaderFrame, "BOTTOMLEFT",  0, -2)
    div:SetPoint("TOPRIGHT", questHeaderFrame, "BOTTOMRIGHT", 0, -2)
    div:SetHeight(1)
    div:SetColorTexture(0.2, 0.2, 0.24, 0.8)

    -- Details ScrollFrame (width: 428 - 10 - 22 = 396)
    detailScroll = CreateFrame("ScrollFrame", "SfuiDJQuestDetailScroll", detailContainer, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT",     questHeaderFrame, "BOTTOMLEFT",   0, -8)
    detailScroll:SetPoint("BOTTOMRIGHT", detailContainer,  "BOTTOMRIGHT", -22, 8)

    local DETAIL_SCROLL_W = 396
    detailContent = CreateFrame("Frame", nil, detailScroll)
    detailContent:SetSize(DETAIL_SCROLL_W, 1)
    detailScroll:SetScrollChild(detailContent)

    if detailScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(detailScroll.ScrollBar)
    end

    -- Register with orchestrator
    sfui.dungeonjournal._registerQuests(RefreshQuestView)

    RefreshQuestView()
end

sfui.dungeonjournal._initQuests = OnFrameCreated

-- ─── Message & Event Hooks ───────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_FRAME_CREATED", OnFrameCreated)
    sfui.events.RegisterMessage("SFUI_DJ_CLEAR_CACHE", function()
        questButtons  = {}
        rewardButtons = {}
        RefreshQuestView()
    end)
end

if sfui.events and sfui.events.RegisterEvent then

    -- Live quest updates when completing or picking up quests (debounced)
    local function DebouncedRefresh()
        if questPanel and questPanel:IsShown() then
            RefreshQuestView()
        end
    end
    local function OnQuestLogChanged()
        if questPanel and questPanel:IsShown() then
            common.debounce("dj_quests_log", 0.15, DebouncedRefresh)
        end
    end
    sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestLogChanged)
    sfui.events.RegisterEvent("QUEST_TURNED_IN",  OnQuestLogChanged)

    -- Debounced item cache updates
    local function OnItemInfoReceived(_, itemID, success)
        if success ~= false then
            QueueQuestRefresh(itemID)
        end
    end
    sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemInfoReceived)
    sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemInfoReceived)
end

-- ─── Focus / Select Quest Programmatically ──────────────────────────────────
function sfui.dungeonjournal.FocusQuest(questID)
    if not questID then return end
    local dungeon   = GetCurrentDungeon()
    local allQuests = dungeon and dungeon.quests or {}
    local quests    = GetFilteredQuests(allQuests)
    for idx, q in ipairs(quests) do
        if q.id == questID then
            selectedQuestIndex = idx
            DJ_DB().lastQuest = idx
            RefreshQuestView()
            return
        end
    end
end
