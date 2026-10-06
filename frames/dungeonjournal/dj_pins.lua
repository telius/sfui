local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
local GameTooltip = sfui.common.get_tooltip()  -- private addon tooltip (methods.md §3.7.2)

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
local common = sfui.common

local entrancePinPool  = {}
local activeEntrancePins = {}

local questPinPool     = {}
local activeQuestPins  = {}

local ticker = nil

-- ─── Helper: DB Access ────────────────────────────────────────────────────────
local function DJ_DB()
    return sfui.dungeonjournal.GetDB()
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
            pin:SetBackdropBorderColor(0, 0, 0, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(22, 22)
    pin:SetFrameStrata("HIGH")
    common.apply_flat_backdrop(pin, { 0.04, 0.04, 0.05, 0.95 }, { 0, 0, 0, 1 })

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
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
            pin:SetBackdropBorderColor(0, 0, 0, 1)
            pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            return pin
        end
    end

    local pin = CreateFrame("Button", nil, parent, "BackdropTemplate")
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetSize(20, 20)
    pin:SetFrameStrata("HIGH")
    common.apply_flat_backdrop(pin, { 0.04, 0.04, 0.05, 0.95 }, { 0, 0, 0, 1 })

    local icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon = icon
    icon:SetPoint("TOPLEFT", pin, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")

    local countText = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.countText = countText
    countText:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", 2, -2)
    countText:SetTextColor(1, 0.82, 0, 1)
    countText:SetShadowOffset(1, -1)
    countText:SetShadowColor(0, 0, 0, 1)

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

local function FindOrCreateGroup(mapID, cx, cy)
    for _, g in ipairs(activeGroups) do
        if math.abs(g.x - cx) < 0.008 and math.abs(g.y - cy) < 0.008 then
            return g
        end
    end
    local targetGroup = AcquireGroup(mapID, cx, cy)
    activeGroups[#activeGroups + 1] = targetGroup
    return targetGroup
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
    return sfui.dungeonjournal.IsQuestCompleted(questID)
end

local function IsQuestActive(questID)
    if not questID then return false end
    if not isQuestCacheValid then
        RebuildActiveQuestCache()
    end
    return activeQuestCache[questID] == true
end

local function IsQuestPickedUpInDungeon(q)
    if not q then return false end
    if q.pickedUpInDungeon == true or q.inDungeon == true then
        return true
    end
    if q.pickup then
        local lower = q.pickup:lower()
        if lower:find("inside ") or lower:find("in dungeon") or lower:find("dropped by ") or lower:find("drop from ") or lower:find("found inside") then
            if not lower:find("outside") then
                return true
            end
        end
    end
    return false
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
    local playerFaction = sfui.common.get_player_faction() or "Alliance"

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
            if sfui.dungeonjournal and sfui.dungeonjournal.AreDungeonPinsHidden and sfui.dungeonjournal.AreDungeonPinsHidden(d.id) then return end
            if DJ_DB().autoHideTrivialPins and sfui.dungeonjournal and sfui.dungeonjournal.IsDungeonTrivial and sfui.dungeonjournal.IsDungeonTrivial(d, playerLevel) then
                return
            end
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
                    GameTooltip:AddLine("|cffff4444<right-click for pin options>|r", 1, 0.35, 0.35)
                    GameTooltip:AddLine("|cff888888<shift-right-click to fast hide>|r", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

                local dID = d.id
                pin:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if IsShiftKeyDown() then
                            sfui.dungeonjournal.SetDungeonHidden(dID, true)
                            if sfui.print then
                                sfui.print(string.format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", dID))
                            end
                            return
                        else
                            local items = {
                                {
                                    text = "Hide Pins for " .. (d.name or "Dungeon"),
                                    color = { 1.0, 0.7, 0.4 },
                                    func = function()
                                        sfui.dungeonjournal.SetDungeonPinsHidden(dID, true)
                                        if sfui.print then
                                            sfui.print(string.format("hidden map pins for |cffffd100%s|r. |cff00ccff|Hsfui_undo:pins:%s|h[undo]|h|r", d.name or "dungeon", dID))
                                        end
                                    end,
                                },
                                {
                                    text = "Hide " .. (d.name or "Dungeon") .. " & Pins",
                                    color = { 1.0, 0.4, 0.4 },
                                    func = function()
                                        sfui.dungeonjournal.SetDungeonHidden(dID, true)
                                        if sfui.print then
                                            sfui.print(string.format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", dID))
                                        end
                                    end,
                                },
                                {
                                    text = "Open in Dungeon Journal",
                                    color = { 0.4, 1.0, 0.4 },
                                    func = function()
                                        if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                                            sfui.dungeonjournal.SelectDungeon(dID)
                                        end
                                    end,
                                },
                            }
                            local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()
                            if totalHidden > 0 then
                                table.insert(items, {
                                    text = "Manage Hidden Items (" .. totalHidden .. ")...",
                                    color = { 1.0, 0.82, 0.0 },
                                    func = function()
                                        sfui.dungeonjournal.OpenHiddenManager()
                                    end,
                                })
                            end
                            table.insert(items, {
                                text = "Cancel",
                                color = { 0.6, 0.6, 0.6 },
                                func = function() end,
                            })
                            sfui.dungeonjournal.ShowContextMenu(self, d.name or "Dungeon Entrance", items)
                            return
                        end
                    end
                    if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                        sfui.dungeonjournal.SelectDungeon(dID)
                    end
                end)

                pin:Show()
                activeEntrancePins[#activeEntrancePins + 1] = pin
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
            if sfui.dungeonjournal and sfui.dungeonjournal.AreDungeonPinsHidden and sfui.dungeonjournal.AreDungeonPinsHidden(d.id) then return end

            for _, q in ipairs(d.quests or {}) do
                local minLevel = q.minLevel or (db.questMinLevels and db.questMinLevels[q.id]) or 1
                local levelEligible = (not requireLevel) or (playerLevel >= minLevel)
                local f = q.faction or "Both"
                local factionEligible = (f == "Both" or f == playerFaction)

                if factionEligible then
                    local steps, currentStep, currentStepIndex, allDone = nil, nil, nil, nil
                    if sfui.dungeonjournal and sfui.dungeonjournal.GetQuestChainInfo then
                        steps, currentStep, currentStepIndex, allDone = sfui.dungeonjournal.GetQuestChainInfo(q)
                    end

                    if steps then
                        -- Quest has a prerequisite chain: place pin for the step the player is currently on
                        if not allDone and currentStep then
                            local stepMinLevel = currentStep.minLevel or (currentStepIndex == 1 and q.chainStart and q.chainStart.minLevel) or (db.questMinLevels and currentStep.id and db.questMinLevels[currentStep.id]) or minLevel
                            local stepLevelEligible = (not requireLevel) or (playerLevel >= stepMinLevel)
                            local stepActive = currentStep.id and IsQuestActive(currentStep.id)
                            local insideDungeon = currentStep.isDungeonQuest and IsQuestPickedUpInDungeon(q)

                            local stepID = currentStep.id or q.id
                            local isStepHidden = sfui.dungeonjournal and sfui.dungeonjournal.IsQuestPinHidden and sfui.dungeonjournal.IsQuestPinHidden(stepID, d.id)

                            if not isStepHidden and stepLevelEligible and not stepActive and not insideDungeon then
                                local coords = currentStep.coords or (questCoords and currentStep.id and questCoords[currentStep.id])
                                if coords and coords.mapID == mapID then
                                    local cx = coords.x or 0
                                    local cy = coords.y or 0
                                    if cx > 1 then cx = cx / 100 end
                                    if cy > 1 then cy = cy / 100 end

                                    local targetGroup = FindOrCreateGroup(coords.mapID, cx, cy)
                                    local alreadyPresent = false
                                    for _, it in ipairs(targetGroup.quests) do
                                        if it.quest and (it.quest.id == currentStep.id or it.quest.name == currentStep.name) then
                                            alreadyPresent = true
                                            break
                                        end
                                    end
                                    if not alreadyPresent then
                                        local chainItem = {
                                            id = currentStep.id or q.id,
                                            name = currentStep.name or q.name,
                                            pickup = currentStep.pickup or q.pickup,
                                            level = currentStep.level or q.level,
                                            minLevel = stepMinLevel,
                                            faction = currentStep.faction or f,
                                            objective = currentStep.objective or string.format("Step %d of %d in the quest chain for %s.", currentStepIndex, #steps, q.name or "dungeon quest"),
                                            isChainStep = true,
                                            chainStep = currentStepIndex,
                                            chainTotal = #steps,
                                            parentQuest = q,
                                        }
                                        targetGroup.quests[#targetGroup.quests + 1] = AcquireGroupItem(chainItem, d, stepMinLevel)
                                    end
                                end
                            end
                        end
                    else
                        -- Standalone quest (no chain)
                        local isDone = IsQuestDone(q.id)
                        local isActive = IsQuestActive(q.id)
                        local insideDungeon = IsQuestPickedUpInDungeon(q)

                        local isQuestHidden = sfui.dungeonjournal and sfui.dungeonjournal.IsQuestPinHidden and sfui.dungeonjournal.IsQuestPinHidden(q.id, d.id)

                        if not isQuestHidden and levelEligible and not isDone and not isActive and not insideDungeon then
                            local coords = (questCoords and questCoords[q.id]) or q.coords
                            if coords and coords.mapID == mapID then
                                local cx = coords.x or 0
                                local cy = coords.y or 0
                                if cx > 1 then cx = cx / 100 end
                                if cy > 1 then cy = cy / 100 end

                                local targetGroup = FindOrCreateGroup(coords.mapID, cx, cy)
                                targetGroup.quests[#targetGroup.quests + 1] = AcquireGroupItem(q, d, minLevel)
                            end
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
                pin:SetBackdropBorderColor(0, 0, 0, 1)
            else
                pin.icon:SetDesaturated(false)
                pin.icon:SetVertexColor(1, 1, 1, 1)
                pin:SetBackdropBorderColor(0, 0, 0, 1)
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
                    if (q.isChainStep or q.isChainStart) and q.parentQuest then
                        local stepStr = string.format("step %d of %d in quest chain for: %s", q.chainStep or 1, q.chainTotal or 1, q.parentQuest.name or "dungeon quest")
                        GameTooltip:AddLine("|cffffaa00" .. stepStr .. "|r", 1, 0.85, 0.3)
                    end
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
                        if q.isChainStep or q.isChainStart then
                            GameTooltip:AddLine(string.format("status: |cffffd100available to pick up (chain step %d/%d)|r", q.chainStep or 1, q.chainTotal or 1), 0.65, 0.65, 0.65)
                        else
                            GameTooltip:AddLine("status: |cffffd100available to pick up|r", 0.65, 0.65, 0.65)
                        end
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
                        local chainBadge = (q.isChainStep or q.isChainStart) and string.format(" |cffffaa00[step %d/%d]|r", q.chainStep or 1, q.chainTotal or 1) or ""
                        GameTooltip:AddLine(string.format("- [%s] %s%s%s", d.name or "", q.name or "", chainBadge, statusBadge), 0.9, 0.9, 0.9)
                    end
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00ff00<click to open dungeon journal>|r", 0, 1, 0)
                GameTooltip:AddLine("|cff00bfff<shift-click to set map waypoint>|r", 0, 0.75, 1)
                GameTooltip:AddLine("|cffff4444<right-click for pin options>|r", 1, 0.35, 0.35)
                GameTooltip:AddLine("|cff888888<shift-right-click to fast hide pin>|r", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)

            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

            pin:SetScript("OnClick", function(self, mouseBtn)
                local item = g.quests[1]
                if not item then return end
                local q = item.quest
                local d = item.dungeon

                if mouseBtn == "RightButton" then
                    if IsShiftKeyDown() then
                        local qID = q.id
                        sfui.dungeonjournal.SetQuestPinHidden(qID, true)
                        if sfui.print then
                            sfui.print(string.format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", q.name or "quest", tostring(qID)))
                        end
                        return
                    else
                        local items = {}
                        if #g.quests == 1 then
                            table.insert(items, {
                                text = "Hide this Quest Pin",
                                color = { 1.0, 0.7, 0.4 },
                                func = function()
                                    sfui.dungeonjournal.SetQuestPinHidden(q.id, true)
                                    if sfui.print then
                                        sfui.print(string.format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", q.name or "quest", tostring(q.id)))
                                    end
                                end,
                            })
                        else
                            for _, it in ipairs(g.quests) do
                                local curQ = it.quest
                                table.insert(items, {
                                    text = "Hide Pin: " .. (curQ.name or "quest"),
                                    color = { 1.0, 0.7, 0.4 },
                                    func = function()
                                        sfui.dungeonjournal.SetQuestPinHidden(curQ.id, true)
                                        if sfui.print then
                                            sfui.print(string.format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", curQ.name or "quest", tostring(curQ.id)))
                                        end
                                    end,
                                })
                            end
                            table.insert(items, {
                                text = "Hide All " .. #g.quests .. " Pins at Location",
                                color = { 1.0, 0.5, 0.3 },
                                func = function()
                                    for _, it in ipairs(g.quests) do
                                        sfui.dungeonjournal.SetQuestPinHidden(it.quest.id, true)
                                    end
                                    if sfui.print then
                                        sfui.print(string.format("hidden %d quest pins at this location.", #g.quests))
                                    end
                                end,
                            })
                        end

                        table.insert(items, {
                            text = "Hide All Pins for " .. (d.name or "Dungeon"),
                            color = { 1.0, 0.5, 0.5 },
                            func = function()
                                sfui.dungeonjournal.SetDungeonPinsHidden(d.id, true)
                                if sfui.print then
                                    sfui.print(string.format("hidden map pins for |cffffd100%s|r. |cff00ccff|Hsfui_undo:pins:%s|h[undo]|h|r", d.name or "dungeon", d.id))
                                end
                            end,
                        })

                        table.insert(items, {
                            text = "Hide " .. (d.name or "Dungeon") .. " & Pins",
                            color = { 1.0, 0.3, 0.3 },
                            func = function()
                                sfui.dungeonjournal.SetDungeonHidden(d.id, true)
                                if sfui.print then
                                    sfui.print(string.format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", d.id))
                                end
                            end,
                        })

                        table.insert(items, {
                            text = "Open in Dungeon Journal",
                            color = { 0.4, 1.0, 0.4 },
                            func = function()
                                local targetQuestID = (q.parentQuest and q.parentQuest.id) or q.id
                                if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                                    sfui.dungeonjournal.SelectQuest(d.id, targetQuestID)
                                elseif sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                                    sfui.dungeonjournal.SelectDungeon(d.id)
                                end
                            end,
                        })

                        local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()
                        if totalHidden > 0 then
                            table.insert(items, {
                                text = "Manage Hidden Items (" .. totalHidden .. ")...",
                                color = { 1.0, 0.82, 0.0 },
                                func = function()
                                    sfui.dungeonjournal.OpenHiddenManager()
                                end,
                            })
                        end

                        table.insert(items, {
                            text = "Cancel",
                            color = { 0.6, 0.6, 0.6 },
                            func = function() end,
                        })

                        local menuTitle = (#g.quests == 1) and (q.name or "Quest") or string.format("%d Quests (%s)", #g.quests, d.name or "")
                        sfui.dungeonjournal.ShowContextMenu(self, menuTitle, items)
                        return
                    end
                end

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

                local q = item.quest
                local targetQuestID = (q.parentQuest and q.parentQuest.id) or q.id
                if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                    sfui.dungeonjournal.SelectQuest(item.dungeon.id, targetQuestID)
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
                    if pin and pin.SetSize then pin:SetSize(22, 22) end
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
                    return sfui.dungeonjournal.GetOption("showEntrancePins")
                end,
                function()
                    local cur = sfui.dungeonjournal.GetOption("showEntrancePins")
                    sfui.dungeonjournal.SetOption("showEntrancePins", not cur)
                end)

            rootDescription:CreateCheckbox("Dungeon Quests",
                function()
                    return sfui.dungeonjournal.GetOption("showQuestPins")
                end,
                function()
                    local cur = sfui.dungeonjournal.GetOption("showQuestPins")
                    sfui.dungeonjournal.SetOption("showQuestPins", not cur)
                end)

            rootDescription:CreateCheckbox("Filter Quests by Level",
                function()
                    return sfui.dungeonjournal.GetOption("questPinsRequireLevel")
                end,
                function()
                    local cur = sfui.dungeonjournal.GetOption("questPinsRequireLevel")
                    sfui.dungeonjournal.SetOption("questPinsRequireLevel", not cur)
                end)

            rootDescription:CreateCheckbox("Hide Outleveled Entrances",
                function()
                    return sfui.dungeonjournal.GetOption("autoHideTrivialPins")
                end,
                function()
                    local cur = sfui.dungeonjournal.GetOption("autoHideTrivialPins")
                    sfui.dungeonjournal.SetOption("autoHideTrivialPins", not cur)
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
        local function DebouncedUpdatePins()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                UpdatePins(true)
            end
        end
        local function OnQuestStateChanged()
            InvalidateQuestCache()
            isPinsDirty = true
            if WorldMapFrame and WorldMapFrame:IsShown() then
                common.debounce("dj_pins_quests", 0.15, DebouncedUpdatePins)
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
