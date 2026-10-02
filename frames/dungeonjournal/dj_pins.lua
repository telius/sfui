local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_pins.lua
--  WorldMap canvas pins for Camelot & Classic dungeon / raid entrances
--  and dungeon quest pickup locations.
--
--  Features:
--    - Dungeon entrance portal pins with dungeon icons & levels
--    - Dungeon quest pickup pins with exclamation icons & giver/level info
--    - Faction filtering (Alliance / Horde / Both)
--    - Automatic hiding of completed quests
--    - Status indicator (available vs in quest log)
--    - Left-Click: Opens Dungeon Journal focused on that dungeon & quest
--    - Shift-Left-Click: Sets native map waypoint & SuperTracks the NPC
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local theme = sfui.theme

local entrancePinPool  = {}
local activeEntrancePins = {}

local questPinPool     = {}
local activeQuestPins  = {}

local ticker = nil

-- ─── Helper: DB Access ────────────────────────────────────────────────────────
local function DJ_DB()
    SfuiDB = SfuiDB or {}
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    return SfuiDB.dungeonjournal
end

-- ─── Helper: Get Map Canvas ───────────────────────────────────────────────────
local function GetCanvas()
    if not WorldMapFrame then return nil end
    if type(WorldMapFrame.GetCanvas) == "function" then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    if WorldMapFrame.ScrollContainer then
        return WorldMapFrame.ScrollContainer.Child or WorldMapFrame.ScrollContainer
    end
    return WorldMapFrame
end

local function GetCurrentMapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and id then return id end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and id then return id end
    end
    return nil
end

-- ─── Entrance Pin Frame Factory ───────────────────────────────────────────────
local function AcquireEntrancePin(parent)
    for _, pin in ipairs(entrancePinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:SetSize(22, 22)
    pin:SetFrameStrata("HIGH")
    pin:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pin:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
    pin:SetBackdropBorderColor(1, 0.82, 0, 0.9)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.3)

    entrancePinPool[#entrancePinPool + 1] = pin
    return pin
end

local function ReleaseEntrancePins()
    for _, pin in ipairs(activeEntrancePins) do
        pin:Hide()
        pin.dungeon = nil
    end
    _G.wipe(activeEntrancePins)
end

-- ─── Quest Pin Frame Factory ──────────────────────────────────────────────────
local function AcquireQuestPin(parent)
    for _, pin in ipairs(questPinPool) do
        if not pin:IsShown() then
            pin:SetParent(parent)
            pin.icon:SetDesaturated(false)
            pin.icon:SetVertexColor(1, 1, 1, 1)
            pin:SetBackdropBorderColor(1, 0.82, 0, 0.95)
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")
    pin:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pin:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
    pin:SetBackdropBorderColor(1, 0.82, 0, 0.95)

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")

    local countText = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.countText = countText
    countText:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2, -2)
    countText:SetTextColor(1, 0.82, 0, 1)

    local hi = pin:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetColorTexture(1, 1, 1, 0.3)

    questPinPool[#questPinPool + 1] = pin
    return pin
end

local groupPool     = {}
local groupItemPool = {}
local activeGroups  = {}

local function ReleaseQuestGroups()
    for _, g in ipairs(activeGroups) do
        for _, it in ipairs(g.quests) do
            it.quest = nil
            it.dungeon = nil
            it.minLevel = nil
            groupItemPool[#groupItemPool + 1] = it
        end
        _G.wipe(g.quests)
        groupPool[#groupPool + 1] = g
    end
    _G.wipe(activeGroups)
end

local function AcquireGroup(mapID, x, y)
    local g = table.remove(groupPool)
    if not g then
        g = { mapID = mapID, x = x, y = y, quests = {} }
    else
        g.mapID = mapID
        g.x = x
        g.y = y
        _G.wipe(g.quests)
    end
    return g
end

local function AcquireGroupItem(q, d, minLevel)
    local it = table.remove(groupItemPool)
    if not it then
        it = { quest = q, dungeon = d, minLevel = minLevel }
    else
        it.quest = q
        it.dungeon = d
        it.minLevel = minLevel
    end
    return it
end

local function ReleaseQuestPins()
    for _, pin in ipairs(activeQuestPins) do
        pin:Hide()
        pin.groupData = nil
    end
    _G.wipe(activeQuestPins)
    ReleaseQuestGroups()
end

-- ─── Quest Status & Cache Helpers ─────────────────────────────────────────────
local activeQuestCache  = {}
local isQuestCacheValid = false

local function InvalidateQuestCache()
    isQuestCacheValid = false
    _G.wipe(activeQuestCache)
end

local function RebuildActiveQuestCache()
    if isQuestCacheValid then return end
    _G.wipe(activeQuestCache)
    local numEntries = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
        if ok and n then numEntries = n end
    elseif GetNumQuestLogEntries then
        local ok, n = pcall(GetNumQuestLogEntries)
        if ok and n then numEntries = n end
    end
    for i = 1, numEntries do
        local qID = nil
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and info.questID and info.questID > 0 then qID = info.questID end
        end
        if not qID and GetQuestLogTitle then
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if not isHeader and id and id > 0 then qID = id end
        end
        if qID then
            activeQuestCache[qID] = true
        end
    end
    isQuestCacheValid = true
end

local function IsQuestDone(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    if IsQuestFlaggedCompleted then
        local ok, done = pcall(IsQuestFlaggedCompleted, questID)
        if ok and done then return true end
    end
    return false
end

local function IsQuestActive(questID)
    if not questID then return false end
    if not isQuestCacheValid then
        RebuildActiveQuestCache()
    end
    return activeQuestCache[questID] == true
end

-- ─── Update Pins on Canvas ────────────────────────────────────────────────────
local isPinsDirty      = true
local lastMapID        = nil
local lastCanvasW      = nil
local lastCanvasH      = nil
local lastPlayerLevel  = nil

local function UpdatePins(force)
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        ReleaseEntrancePins()
        ReleaseQuestPins()
        lastMapID = nil
        return
    end

    local canvas = GetCanvas()
    if not canvas then
        ReleaseEntrancePins()
        ReleaseQuestPins()
        lastMapID = nil
        return
    end

    local mapID = GetCurrentMapID()
    if not mapID then
        ReleaseEntrancePins()
        ReleaseQuestPins()
        lastMapID = nil
        return
    end

    local canvasW, canvasH = canvas:GetSize()
    if not canvasW or canvasW <= 0 or not canvasH or canvasH <= 0 then return end

    local playerLevel   = UnitLevel("player") or 1
    local playerFaction = UnitFactionGroup("player") or "Alliance"

    -- Zero-CPU early out if map view, scale, and quest status are unchanged
    if not force and not isPinsDirty
       and mapID == lastMapID
       and canvasW == lastCanvasW
       and canvasH == lastCanvasH
       and playerLevel == lastPlayerLevel then
        return
    end

    isPinsDirty = false
    lastMapID = mapID
    lastCanvasW = canvasW
    lastCanvasH = canvasH
    lastPlayerLevel = playerLevel

    ReleaseEntrancePins()
    ReleaseQuestPins()

    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if not db then return end

    -- ── 1. Dungeon Entrance Pins ──────────────────────────────────────────────
    if DJ_DB().showEntrancePins ~= false then
        local function ProcessEntrance(d)
            if not (DJ_DB().hiddenDungeons and DJ_DB().hiddenDungeons[d.id]) then
                local ent = d.entrance
                if ent and ent.mapID == mapID and ent.x and ent.y then
                    local pin = AcquireEntrancePin(canvas)
                    pin.dungeon = d

                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * ent.x, -canvasH * ent.y)

                    local textureLoaded = false
                    if d.iconStr then
                        pin.icon:SetTexture(d.iconStr)
                        if pin.icon:GetTexture() then textureLoaded = true end
                    end
                    if not textureLoaded and d.icon then
                        pin.icon:SetTexture(d.icon)
                        if pin.icon:GetTexture() then textureLoaded = true end
                    end
                    if not textureLoaded then
                        pin.icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
                    end

                    pin:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(d.name or "dungeon entrance", 1, 0.82, 0)
                        if d.level then
                            GameTooltip:AddLine("level: " .. d.level, 0.85, 0.85, 0.85)
                        end
                        if d.zone then
                            GameTooltip:AddLine("zone: " .. d.zone, 0.65, 0.65, 0.65)
                        end

                        -- Count quests available for this dungeon
                        local totalQuests = 0
                        local available = 0
                        local inLog = 0
                        local completed = 0
                        for _, q in ipairs(d.quests or {}) do
                            local f = q.faction or "Both"
                            if f == "Both" or f == playerFaction then
                                totalQuests = totalQuests + 1
                                local minLvl = q.minLevel or (db.questMinLevels and db.questMinLevels[q.id]) or 1
                                if IsQuestDone(q.id) then
                                    completed = completed + 1
                                elseif IsQuestActive(q.id) then
                                    inLog = inLog + 1
                                elseif playerLevel >= minLvl then
                                    available = available + 1
                                end
                            end
                        end
                        if totalQuests > 0 then
                            GameTooltip:AddLine(string.format("quests: %d available · %d in log · %d completed", available, inLog, completed), 0.75, 0.75, 0.75)
                        end

                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff00ff00<click to open dungeon journal>|r", 0, 1, 0)
                        GameTooltip:Show()
                    end)
                    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

                    local dID = d.id
                    pin:SetScript("OnClick", function()
                        if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                            sfui.dungeonjournal.SelectDungeon(dID)
                        end
                    end)

                    pin:Show()
                    activeEntrancePins[#activeEntrancePins + 1] = pin
                end
            end
        end

        if db.dungeons then
            for _, d in ipairs(db.dungeons) do ProcessEntrance(d) end
        end
        if db.raids then
            for _, r in ipairs(db.raids) do ProcessEntrance(r) end
        end
    end

    -- ── 2. Dungeon Quest Pickup Pins ──────────────────────────────────────────
    -- Map pins are displayed for quests that are:
    --   1. Not completed
    --   2. Not currently picked up / in quest log
    --   3. Player meets the required minimum pickup level (minLevel) - unless opted out!
    if DJ_DB().showQuestPins ~= false then
        local requireLevel = DJ_DB().questPinsRequireLevel ~= false
        local questCoords  = db.questCoords

        local function ProcessQuestDungeon(d)
            if DJ_DB().hiddenDungeons and DJ_DB().hiddenDungeons[d.id] then return end
            for _, q in ipairs(d.quests or {}) do
                local minLevel = q.minLevel or (db.questMinLevels and db.questMinLevels[q.id]) or 1
                local levelEligible = (not requireLevel) or (playerLevel >= minLevel)
                if levelEligible and not IsQuestDone(q.id) and not IsQuestActive(q.id) then
                    local f = q.faction or "Both"
                    if f == "Both" or f == playerFaction then
                        local coords = questCoords and questCoords[q.id]
                        if coords and coords.mapID == mapID then
                            local targetGroup = nil
                            for _, g in ipairs(activeGroups) do
                                if math.abs(g.x - coords.x) < 0.008 and math.abs(g.y - coords.y) < 0.008 then
                                    targetGroup = g
                                    break
                                end
                            end
                            if not targetGroup then
                                targetGroup = AcquireGroup(coords.mapID, coords.x, coords.y)
                                activeGroups[#activeGroups + 1] = targetGroup
                            end
                            targetGroup.quests[#targetGroup.quests + 1] = AcquireGroupItem(q, d, minLevel)
                        end
                    end
                end
            end
        end

        if db.dungeons then
            for _, d in ipairs(db.dungeons) do ProcessQuestDungeon(d) end
        end
        if db.raids then
            for _, r in ipairs(db.raids) do ProcessQuestDungeon(r) end
        end

        for _, g in ipairs(activeGroups) do
            local pin = AcquireQuestPin(canvas)
            pin.groupData = g

            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", canvasW * g.x, -canvasH * g.y)

            -- Check if any quest in this group is currently available for player's level
            local anyLevelMet = false
            for _, it in ipairs(g.quests) do
                if playerLevel >= (it.minLevel or 1) then
                    anyLevelMet = true
                    break
                end
            end

            pin.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            if not anyLevelMet then
                pin.icon:SetDesaturated(true)
                pin.icon:SetVertexColor(0.85, 0.55, 0.55, 0.85)
                pin:SetBackdropBorderColor(0.8, 0.35, 0.35, 0.85)
            else
                pin.icon:SetDesaturated(false)
                pin.icon:SetVertexColor(1, 1, 1, 1)
                pin:SetBackdropBorderColor(1, 0.82, 0, 0.95)
            end

            if #g.quests > 1 then
                pin.countText:SetText(#g.quests)
                pin.countText:Show()
            else
                pin.countText:Hide()
            end

            pin:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if #g.quests == 1 then
                    local item = g.quests[1]
                    local q = item.quest
                    local d = item.dungeon
                    local minLvl = item.minLevel or q.minLevel or 1
                    local underlevel = (playerLevel < minLvl)

                    GameTooltip:AddLine(q.name or "dungeon quest", 1, 0.82, 0)
                    GameTooltip:AddLine("dungeon: " .. (d.name or ""), 0.85, 0.85, 0.85)
                    if q.pickup and q.pickup ~= "" then
                        GameTooltip:AddLine("starts from: " .. q.pickup, 0.85, 0.85, 0.85)
                    end
                    if underlevel then
                        GameTooltip:AddLine(string.format("requires level: %d  (your level %d)", minLvl, playerLevel), 1, 0.35, 0.35)
                        GameTooltip:AddLine("status: |cffff4444locked (level requirement not met)|r", 1, 0.35, 0.35)
                    else
                        if q.level then
                            GameTooltip:AddLine(string.format("requires level: %d  (rec %s)", minLvl, tostring(q.level)), 0.65, 0.65, 0.65)
                        else
                            GameTooltip:AddLine(string.format("requires level: %d", minLvl), 0.65, 0.65, 0.65)
                        end
                        GameTooltip:AddLine("status: |cffffd100available to pick up|r", 0.65, 0.65, 0.65)
                    end
                    if q.objective and q.objective ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine(q.objective, 0.75, 0.75, 0.75, true)
                    end
                else
                    GameTooltip:AddLine(string.format("dungeon quests (%d)", #g.quests), 1, 0.82, 0)
                    local giver = g.quests[1].quest.pickup
                    if giver and giver ~= "" then
                        GameTooltip:AddLine("starts from: " .. giver, 0.85, 0.85, 0.85)
                    end
                    GameTooltip:AddLine(" ")
                    for _, item in ipairs(g.quests) do
                        local q = item.quest
                        local d = item.dungeon
                        local minLvl = item.minLevel or q.minLevel or 1
                        local statusBadge = ""
                        if playerLevel < minLvl then
                            statusBadge = string.format(" |cffff4444[req lvl %d]|r", minLvl)
                        else
                            statusBadge = string.format(" |cff888888[lvl %s]|r", tostring(q.level or minLvl))
                        end
                        GameTooltip:AddLine(string.format("- [%s] %s%s", d.name or "", q.name or "", statusBadge), 0.9, 0.9, 0.9)
                    end
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ff00<click to open dungeon journal>|r", 0, 1, 0)
                GameTooltip:AddLine("|cff00bfff<shift-click to set map waypoint>|r", 0, 0.75, 1)
                GameTooltip:Show()
            end)

            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

            pin:SetScript("OnClick", function()
                if IsShiftKeyDown() then
                    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
                        pcall(function()
                            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(g.mapID, g.x, g.y))
                        end)
                        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                            pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                        end
                        local qName = g.quests[1].quest.name or "dungeon quest"
                        if sfui.print then
                            sfui.print("waypoint set for " .. qName)
                        end
                    end
                    return
                end

                local item = g.quests[1]
                if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                    sfui.dungeonjournal.SelectQuest(item.dungeon.id, item.quest.id)
                elseif sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                    sfui.dungeonjournal.SelectDungeon(item.dungeon.id)
                end
            end)

            pin:Show()
            activeQuestPins[#activeQuestPins + 1] = pin
        end
    end
end

sfui.dungeonjournal = sfui.dungeonjournal or {}
sfui.dungeonjournal.UpdatePins = UpdatePins

function sfui.dungeonjournal.HighlightEntrancePin(dungeonID)
    if not dungeonID then return end
    for _, pin in ipairs(activeEntrancePins) do
        if pin.dungeon and pin.dungeon.id == dungeonID then
            pin:SetSize(28, 28)
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, function()
                    if pin and pin.SetSize then pin:SetSize(20, 20) end
                end)
            end
            break
        end
    end
end

-- ─── Native WorldMap Tracking Dropdown Menu Integration ───────────────────────
local function HookWorldMapTrackingMenu()
    if _G.Menu and _G.Menu.ModifyMenu then
        pcall(_G.Menu.ModifyMenu, "MENU_WORLD_MAP_TRACKING", function(owner, rootDescription)
            rootDescription:CreateDivider()
            rootDescription:CreateTitle("Dungeon Journal")

            rootDescription:CreateCheckbox("Dungeon Entrances",
                function()
                    if sfui.dungeonjournal and sfui.dungeonjournal.GetOption then
                        return sfui.dungeonjournal.GetOption("showEntrancePins")
                    end
                    return DJ_DB().showEntrancePins ~= false
                end,
                function()
                    local cur = (sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("showEntrancePins")) or (DJ_DB().showEntrancePins ~= false)
                    if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then
                        sfui.dungeonjournal.SetOption("showEntrancePins", not cur)
                    else
                        DJ_DB().showEntrancePins = not cur
                        UpdatePins()
                    end
                end)

            rootDescription:CreateCheckbox("Dungeon Quests",
                function()
                    if sfui.dungeonjournal and sfui.dungeonjournal.GetOption then
                        return sfui.dungeonjournal.GetOption("showQuestPins")
                    end
                    return DJ_DB().showQuestPins ~= false
                end,
                function()
                    local cur = (sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("showQuestPins")) or (DJ_DB().showQuestPins ~= false)
                    if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then
                        sfui.dungeonjournal.SetOption("showQuestPins", not cur)
                    else
                        DJ_DB().showQuestPins = not cur
                        UpdatePins()
                    end
                end)

            rootDescription:CreateCheckbox("Filter Quests by Level",
                function()
                    if sfui.dungeonjournal and sfui.dungeonjournal.GetOption then
                        return sfui.dungeonjournal.GetOption("questPinsRequireLevel")
                    end
                    return DJ_DB().questPinsRequireLevel ~= false
                end,
                function()
                    local cur = (sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("questPinsRequireLevel")) or (DJ_DB().questPinsRequireLevel ~= false)
                    if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then
                        sfui.dungeonjournal.SetOption("questPinsRequireLevel", not cur)
                    else
                        DJ_DB().questPinsRequireLevel = not cur
                        UpdatePins()
                    end
                end)
        end)
    end
end

-- ─── Event Registrations ──────────────────────────────────────────────────────
local function InitPins()
    HookWorldMapTrackingMenu()

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", UpdatePins)
        WorldMapFrame:HookScript("OnHide", function()
            ReleaseEntrancePins()
            ReleaseQuestPins()
        end)
    end

    if sfui.events and sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_DJ_SETTING_CHANGED", function()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(true)
            end
        end)
    end

    if sfui.events and sfui.events.RegisterEvent then
        local questDebounceTimer = nil
        local function OnQuestStateChanged()
            InvalidateQuestCache()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                if not questDebounceTimer then
                    if _G.C_Timer and _G.C_Timer.After then
                        questDebounceTimer = _G.C_Timer.After(0.15, function()
                            questDebounceTimer = nil
                            if WorldMapFrame and WorldMapFrame:IsShown() then
                                UpdatePins(true)
                            end
                        end)
                    else
                        UpdatePins(true)
                    end
                end
            end
        end

        sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() isPinsDirty = true; UpdatePins(true) end)
        sfui.events.RegisterEvent("ZONE_CHANGED",          function() isPinsDirty = true; UpdatePins(true) end)
        sfui.events.RegisterEvent("QUEST_LOG_UPDATE", OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_ACCEPTED",   OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_REMOVED",    OnQuestStateChanged)
        sfui.events.RegisterEvent("QUEST_TURNED_IN",  OnQuestStateChanged)
        sfui.events.RegisterEvent("PLAYER_LEVEL_UP",  OnQuestStateChanged)
    end

    -- Map canvas update loop via centralized sfui.events dispatcher
    if sfui.events and sfui.events.RegisterUpdate then
        sfui.events.RegisterUpdate("DungeonJournalPins", 0.5, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(false)
            end
        end)
    elseif _G.C_Timer and _G.C_Timer.NewTicker then
        ticker = _G.C_Timer.NewTicker(0.5, function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(false)
            end
        end)
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitPins)
end
