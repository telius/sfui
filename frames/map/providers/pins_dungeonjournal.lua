local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/providers/pins_dungeonjournal.lua
--  WorldMap Pin Provider: Camelot & Classic Dungeon Entrances & Quests
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local pins = sfui.pins
if not pins then return end

local _G                  = _G
local UnitLevel           = _G.UnitLevel
local IsShiftKeyDown      = _G.IsShiftKeyDown
local ipairs              = _G.ipairs
local tostring            = _G.tostring
local string_format       = string.format
local table_insert        = _G.table.insert

-- ─── Helper: DB Access ────────────────────────────────────────────────────────
local function DJ_DB()
    if sfui.dungeonjournal and sfui.dungeonjournal.GetDB then
        return sfui.dungeonjournal.GetDB()
    end
    return {}
end

local function IsQuestPickedUpInDungeon(q)
    if not q then return false end
    if q.pickedUpInDungeon == true or q.inDungeon == true then return true end
    if q.pickup then
        local lower = q.pickup:lower()
        if lower:find("inside ") or lower:find("in dungeon") or lower:find("dropped by ") or lower:find("drop from ") or lower:find("found inside") then
            if not lower:find("outside") then return true end
        end
    end
    return false
end

-- ─── Interactive Tooltip Handlers ─────────────────────────────────────────────
local function OnEnterEntrance(pin, tooltip, pinData)
    local d = pinData.dungeon
    if not d then return end

    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:AddLine(d.name or "dungeon entrance", 1, 0.82, 0)
    if d.level then tooltip:AddLine("level: " .. d.level, 0.85, 0.85, 0.85) end
    if d.zone then tooltip:AddLine("zone: " .. d.zone, 0.65, 0.65, 0.65) end

    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    local playerFaction = (sfui.common and sfui.common.get_player_faction and sfui.common.get_player_faction()) or "Alliance"
    local playerLevel = (UnitLevel and UnitLevel("player")) or 1

    local totalQuests = 0
    local available = 0
    local inLog = 0
    local completed = 0
    local pFaction = playerFaction and playerFaction:lower() or "alliance"
    for _, q in ipairs(d.quests or {}) do
        local f = q.faction and q.faction:lower() or "both"
        if f == "both" or f == pFaction then
            totalQuests = totalQuests + 1
            local minLvl = q.minLevel or (db and db.questMinLevels and db.questMinLevels[q.id]) or 1
            if pins.IsQuestCompleted(q.id) then
                completed = completed + 1
            elseif pins.IsQuestActive(q.id) then
                inLog = inLog + 1
            elseif playerLevel >= minLvl then
                available = available + 1
            end
        end
    end

    if totalQuests > 0 then
        tooltip:AddLine(
            string_format("quests: %d available · %d in log · %d completed", available, inLog, completed),
            0.75, 0.75, 0.75)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff00<click to open dungeon journal>|r", 0, 1, 0)
    tooltip:AddLine("|cff00bfff<shift-click to set map waypoint>|r", 0, 0.75, 1)
    tooltip:AddLine("|cffff4444<right-click for pin options>|r", 1, 0.35, 0.35)
    tooltip:AddLine("|cff888888<shift-right-click to fast hide>|r", 0.6, 0.6, 0.6)
    tooltip:Show()
end

local function OnClickEntrance(pin, mouseBtn, pinData)
    local d = pinData.dungeon
    if not d then return end
    local dID = d.id

    if mouseBtn == "RightButton" then
        if IsShiftKeyDown() then
            if sfui.dungeonjournal and sfui.dungeonjournal.SetDungeonHidden then
                sfui.dungeonjournal.SetDungeonHidden(dID, true)
                if sfui.print then
                    sfui.print(string_format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", dID))
                end
            end
            return
        else
            local items = {
                {
                    text = "hide pins for " .. (d.name and d.name:lower() or "dungeon"),
                    color = { 1.0, 0.7, 0.4 },
                    func = function()
                        if sfui.dungeonjournal and sfui.dungeonjournal.SetDungeonPinsHidden then
                            sfui.dungeonjournal.SetDungeonPinsHidden(dID, true)
                            if sfui.print then
                                sfui.print(string_format("hidden map pins for |cffffd100%s|r. |cff00ccff|Hsfui_undo:pins:%s|h[undo]|h|r", d.name or "dungeon", dID))
                            end
                        end
                    end,
                },
                {
                    text = "hide " .. (d.name and d.name:lower() or "dungeon") .. " & pins",
                    color = { 1.0, 0.4, 0.4 },
                    func = function()
                        if sfui.dungeonjournal and sfui.dungeonjournal.SetDungeonHidden then
                            sfui.dungeonjournal.SetDungeonHidden(dID, true)
                            if sfui.print then
                                sfui.print(string_format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", dID))
                            end
                        end
                    end,
                },
                {
                    text = "open in dungeon journal",
                    color = { 0.4, 1.0, 0.4 },
                    func = function()
                        if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                            sfui.dungeonjournal.SelectDungeon(dID, nil, true)
                        end
                    end,
                },
            }

            if sfui.dungeonjournal and sfui.dungeonjournal.GetHiddenCounts then
                local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()
                if totalHidden and totalHidden > 0 then
                    table_insert(items, {
                        text = "manage hidden items (" .. totalHidden .. ")...",
                        color = { 1.0, 0.82, 0.0 },
                        func = function()
                            if sfui.dungeonjournal.OpenHiddenManager then
                                sfui.dungeonjournal.OpenHiddenManager()
                            end
                        end,
                    })
                end
            end

            table_insert(items, {
                text = "cancel",
                color = { 0.6, 0.6, 0.6 },
                func = function() end,
            })

            if sfui.dungeonjournal and sfui.dungeonjournal.ShowContextMenu then
                sfui.dungeonjournal.ShowContextMenu(pin, d.name and d.name:lower() or "dungeon entrance", items)
            end
            return
        end
    end

    if sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
        sfui.dungeonjournal.SelectDungeon(dID, nil, true)
    end
end

local function OnEnterQuestGroup(pin, tooltip, pinData)
    local g = pinData.groupData
    if not g or not g.quests or #g.quests == 0 then return end
    local playerLevel = (UnitLevel and UnitLevel("player")) or 1

    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if #g.quests == 1 then
        local item = g.quests[1]
        local q = item.quest
        local d = item.dungeon
        local minLvl = item.minLevel or q.minLevel or 1
        local underlevel = (playerLevel < minLvl)

        tooltip:AddLine(q.name or "dungeon quest", 1, 0.82, 0)
        tooltip:AddLine("dungeon: " .. (d.name or ""), 0.85, 0.85, 0.85)
        if (q.isChainStep or q.isChainStart) and q.parentQuest then
            local stepStr = string_format("step %d of %d in quest chain for: %s", q.chainStep or 1, q.chainTotal or 1, q.parentQuest.name or "dungeon quest")
            tooltip:AddLine("|cffffaa00" .. stepStr .. "|r", 1, 0.85, 0.3)
        end
        if q.pickup and q.pickup ~= "" then
            tooltip:AddLine("starts from: " .. q.pickup, 0.85, 0.85, 0.85)
        end
        if underlevel then
            tooltip:AddLine(string_format("requires level: %d  (your level %d)", minLvl, playerLevel), 1, 0.35, 0.35)
            tooltip:AddLine("status: |cffff4444locked (level requirement not met)|r", 1, 0.35, 0.35)
        else
            if q.level then
                tooltip:AddLine(string_format("requires level: %d  (rec %s)", minLvl, tostring(q.level)), 0.65, 0.65, 0.65)
            else
                tooltip:AddLine(string_format("requires level: %d", minLvl), 0.65, 0.65, 0.65)
            end
            if q.isChainStep or q.isChainStart then
                tooltip:AddLine(string_format("status: |cffffd100available to pick up (chain step %d/%d)|r", q.chainStep or 1, q.chainTotal or 1), 0.65, 0.65, 0.65)
            else
                tooltip:AddLine("status: |cffffd100available to pick up|r", 0.65, 0.65, 0.65)
            end
        end
        if q.objective and q.objective ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(q.objective, 0.75, 0.75, 0.75, true)
        end
    else
        tooltip:AddLine(string_format("dungeon quests (%d)", #g.quests), 1, 0.82, 0)
        local giver = g.quests[1].quest.pickup
        if giver and giver ~= "" then
            tooltip:AddLine("starts from: " .. giver, 0.85, 0.85, 0.85)
        end
        tooltip:AddLine(" ")
        for _, item in ipairs(g.quests) do
            local q = item.quest
            local d = item.dungeon
            local minLvl = item.minLevel or q.minLevel or 1
            local statusBadge = ""
            if playerLevel < minLvl then
                statusBadge = string_format(" |cffff4444[req lvl %d]|r", minLvl)
            else
                statusBadge = string_format(" |cff888888[lvl %s]|r", tostring(q.level or minLvl))
            end
            local chainBadge = (q.isChainStep or q.isChainStart) and string_format(" |cffffaa00[step %d/%d]|r", q.chainStep or 1, q.chainTotal or 1) or ""
            tooltip:AddLine(string_format("- [%s] %s%s%s", d.name or "", q.name or "", chainBadge, statusBadge), 0.9, 0.9, 0.9)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff00<click to open dungeon journal>|r", 0, 1, 0)
    tooltip:AddLine("|cff00bfff<shift-click to set map waypoint>|r", 0, 0.75, 1)
    tooltip:AddLine("|cffff4444<right-click for pin options>|r", 1, 0.35, 0.35)
    tooltip:AddLine("|cff888888<shift-right-click to fast hide pin>|r", 0.6, 0.6, 0.6)
    tooltip:Show()
end

local function OnClickQuestGroup(pin, mouseBtn, pinData)
    local g = pinData.groupData
    if not g or not g.quests or #g.quests == 0 then return end
    local item = g.quests[1]
    local q = item.quest
    local d = item.dungeon

    if mouseBtn == "RightButton" then
        if IsShiftKeyDown() then
            local qID = q.id
            if sfui.dungeonjournal and sfui.dungeonjournal.SetQuestPinHidden then
                sfui.dungeonjournal.SetQuestPinHidden(qID, true)
                if sfui.print then
                    sfui.print(string_format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", q.name or "quest", tostring(qID)))
                end
            end
            return
        else
            local items = {}
            if #g.quests == 1 then
                table_insert(items, {
                    text = "hide this quest pin",
                    color = { 1.0, 0.7, 0.4 },
                    func = function()
                        if sfui.dungeonjournal and sfui.dungeonjournal.SetQuestPinHidden then
                            sfui.dungeonjournal.SetQuestPinHidden(q.id, true)
                            if sfui.print then
                                sfui.print(string_format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", q.name or "quest", tostring(q.id)))
                            end
                        end
                    end,
                })
            else
                for _, it in ipairs(g.quests) do
                    local curQ = it.quest
                    table_insert(items, {
                        text = "hide pin: " .. (curQ.name or "quest"),
                        color = { 1.0, 0.7, 0.4 },
                        func = function()
                            if sfui.dungeonjournal and sfui.dungeonjournal.SetQuestPinHidden then
                                sfui.dungeonjournal.SetQuestPinHidden(curQ.id, true)
                                if sfui.print then
                                    sfui.print(string_format("hidden quest pin |cffffd100%s|r. |cff00ccff|Hsfui_undo:quest:%s|h[undo]|h|r", curQ.name or "quest", tostring(curQ.id)))
                                end
                            end
                        end,
                    })
                end
                table_insert(items, {
                    text = "hide all " .. #g.quests .. " pins at location",
                    color = { 1.0, 0.5, 0.3 },
                    func = function()
                        for _, it in ipairs(g.quests) do
                            if sfui.dungeonjournal and sfui.dungeonjournal.SetQuestPinHidden then
                                sfui.dungeonjournal.SetQuestPinHidden(it.quest.id, true)
                            end
                        end
                        if sfui.print then
                            sfui.print(string_format("hidden %d quest pins at this location.", #g.quests))
                        end
                    end,
                })
            end

            table_insert(items, {
                text = "hide all pins for " .. (d.name and d.name:lower() or "dungeon"),
                color = { 1.0, 0.5, 0.5 },
                func = function()
                    if sfui.dungeonjournal and sfui.dungeonjournal.SetDungeonPinsHidden then
                        sfui.dungeonjournal.SetDungeonPinsHidden(d.id, true)
                        if sfui.print then
                            sfui.print(string_format("hidden map pins for |cffffd100%s|r. |cff00ccff|Hsfui_undo:pins:%s|h[undo]|h|r", d.name or "dungeon", d.id))
                        end
                    end
                end,
            })

            table_insert(items, {
                text = "hide " .. (d.name and d.name:lower() or "dungeon") .. " & pins",
                color = { 1.0, 0.3, 0.3 },
                func = function()
                    if sfui.dungeonjournal and sfui.dungeonjournal.SetDungeonHidden then
                        sfui.dungeonjournal.SetDungeonHidden(d.id, true)
                        if sfui.print then
                            sfui.print(string_format("hidden |cffffd100%s|r and its map pins. |cff00ccff|Hsfui_undo:dungeon:%s|h[undo]|h|r", d.name or "dungeon", d.id))
                        end
                    end
                end,
            })

            table_insert(items, {
                text = "open in dungeon journal",
                color = { 0.4, 1.0, 0.4 },
                func = function()
                    local targetQuestID = (q.parentQuest and q.parentQuest.id) or q.id
                    if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
                        sfui.dungeonjournal.SelectQuest(d.id, targetQuestID)
                    elseif sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
                        sfui.dungeonjournal.SelectDungeon(d.id, nil, true)
                    end
                end,
            })

            if sfui.dungeonjournal and sfui.dungeonjournal.GetHiddenCounts then
                local _, _, _, totalHidden = sfui.dungeonjournal.GetHiddenCounts()
                if totalHidden and totalHidden > 0 then
                    table_insert(items, {
                        text = "manage hidden items (" .. totalHidden .. ")...",
                        color = { 1.0, 0.82, 0.0 },
                        func = function()
                            if sfui.dungeonjournal.OpenHiddenManager then
                                sfui.dungeonjournal.OpenHiddenManager()
                            end
                        end,
                    })
                end
            end

            table_insert(items, {
                text = "cancel",
                color = { 0.6, 0.6, 0.6 },
                func = function() end,
            })

            local menuTitle = (#g.quests == 1) and (q.name and q.name:lower() or "quest") or string_format("%d quests (%s)", #g.quests, d.name and d.name:lower() or "")
            if sfui.dungeonjournal and sfui.dungeonjournal.ShowContextMenu then
                sfui.dungeonjournal.ShowContextMenu(pin, menuTitle, items)
            end
            return
        end
    end

    local targetQuestID = (q.parentQuest and q.parentQuest.id) or q.id
    if sfui.dungeonjournal and sfui.dungeonjournal.SelectQuest then
        sfui.dungeonjournal.SelectQuest(item.dungeon.id, targetQuestID)
    elseif sfui.dungeonjournal and sfui.dungeonjournal.SelectDungeon then
        sfui.dungeonjournal.SelectDungeon(item.dungeon.id, nil, true)
    end
end

-- ─── Provider Implementation ──────────────────────────────────────────────────
local function GetEntrancePins(mapID, playerLevel, playerFaction)
    if DJ_DB().showEntrancePins == false then return nil end
    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if not db then return nil end

    local out = {}
    local function ProcessEntrance(d)
        if sfui.dungeonjournal and sfui.dungeonjournal.AreDungeonPinsHidden and sfui.dungeonjournal.AreDungeonPinsHidden(d.id) then return end
        if DJ_DB().autoHideTrivialPins and sfui.dungeonjournal and sfui.dungeonjournal.IsDungeonTrivial and sfui.dungeonjournal.IsDungeonTrivial(d, playerLevel) then
            return
        end
        local ent = d.entrance
        if ent and ent.mapID == mapID and ent.x and ent.y then
            local iconTexture = d.iconStr or d.icon or "Interface\\Icons\\INV_Misc_Rune_01"
            table_insert(out, {
                id          = "dj_entrance_" .. d.id,
                dungeonID   = d.id,
                provider    = "dj_entrances",
                mapID       = ent.mapID,
                x           = ent.x,
                y           = ent.y,
                size        = 22,
                icon        = iconTexture,
                texCoord    = { 0.08, 0.92, 0.08, 0.92 },
                borderColor = { 0, 0, 0, 1 },
                title       = d.name or "dungeon entrance",
                dungeon     = d,
                OnEnter     = OnEnterEntrance,
                OnClick     = OnClickEntrance,
            })
        end
    end

    if db.dungeons then for _, d in ipairs(db.dungeons) do ProcessEntrance(d) end end
    if db.raids then for _, r in ipairs(db.raids) do ProcessEntrance(r) end end
    return out
end

local function GetQuestPins(mapID, playerLevel, playerFaction)
    if DJ_DB().showQuestPins == false then return nil end
    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if not db then return nil end

    local requireLevel = DJ_DB().questPinsRequireLevel ~= false
    local questCoords  = db.questCoords
    local groups       = {}

    local function ProcessQuestDungeon(d)
        if sfui.dungeonjournal and sfui.dungeonjournal.AreDungeonPinsHidden and sfui.dungeonjournal.AreDungeonPinsHidden(d.id) then return end

        for _, q in ipairs(d.quests or {}) do
            local minLevel = q.minLevel or (db.questMinLevels and db.questMinLevels[q.id]) or 1
            local levelEligible = (not requireLevel) or (playerLevel >= minLevel)
            local f = q.faction and q.faction:lower() or "both"
            local pFaction = playerFaction and playerFaction:lower() or "alliance"
            local factionEligible = (f == "both" or f == pFaction)

            if factionEligible then
                local steps, currentStep, currentStepIndex, allDone = nil, nil, nil, nil
                if sfui.dungeonjournal and sfui.dungeonjournal.GetQuestChainInfo then
                    steps, currentStep, currentStepIndex, allDone = sfui.dungeonjournal.GetQuestChainInfo(q)
                end

                if steps then
                    if not allDone and currentStep then
                        local stepMinLevel = currentStep.minLevel or
                            (currentStepIndex == 1 and q.chainStart and q.chainStart.minLevel) or
                            (db.questMinLevels and currentStep.id and db.questMinLevels[currentStep.id]) or minLevel
                        local stepLevelEligible = (not requireLevel) or (playerLevel >= stepMinLevel)
                        local stepActive = currentStep.id and pins.IsQuestActive(currentStep.id)
                        local insideDungeon = currentStep.isDungeonQuest and IsQuestPickedUpInDungeon(q)
                        local stepID = currentStep.id or q.id
                        local isStepHidden = sfui.dungeonjournal and sfui.dungeonjournal.IsQuestPinHidden and
                            sfui.dungeonjournal.IsQuestPinHidden(stepID, d.id)

                        if not isStepHidden and stepLevelEligible and not stepActive and not insideDungeon then
                            local coords = currentStep.coords or (questCoords and currentStep.id and questCoords[currentStep.id])
                            if coords and coords.mapID == mapID then
                                local cx = coords.x or 0
                                local cy = coords.y or 0
                                if cx > 1 then cx = cx / 100 end
                                if cy > 1 then cy = cy / 100 end

                                local targetGroup = pins.FindOrCreateGroup(groups, cx, cy, 0.008, coords.mapID)
                                targetGroup.quests = targetGroup.quests or {}
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
                                        objective = currentStep.objective or
                                            string_format("step %d of %d in the quest chain for %s.", currentStepIndex, #steps, q.name or "dungeon quest"),
                                        isChainStep = true,
                                        chainStep = currentStepIndex,
                                        chainTotal = #steps,
                                        parentQuest = q,
                                    }
                                    table_insert(targetGroup.quests, { quest = chainItem, dungeon = d, minLevel = stepMinLevel })
                                end
                            end
                        end
                    end
                else
                    local isDone = pins.IsQuestCompleted(q.id)
                    local isActive = pins.IsQuestActive(q.id)
                    local insideDungeon = IsQuestPickedUpInDungeon(q)
                    local isQuestHidden = sfui.dungeonjournal and sfui.dungeonjournal.IsQuestPinHidden and
                        sfui.dungeonjournal.IsQuestPinHidden(q.id, d.id)

                    if not isQuestHidden and levelEligible and not isDone and not isActive and not insideDungeon then
                        local coords = (questCoords and questCoords[q.id]) or q.coords
                        if coords and coords.mapID == mapID then
                            local cx = coords.x or 0
                            local cy = coords.y or 0
                            if cx > 1 then cx = cx / 100 end
                            if cy > 1 then cy = cy / 100 end

                            local targetGroup = pins.FindOrCreateGroup(groups, cx, cy, 0.008, coords.mapID)
                            targetGroup.quests = targetGroup.quests or {}
                            table_insert(targetGroup.quests, { quest = q, dungeon = d, minLevel = minLevel })
                        end
                    end
                end
            end
        end
    end

    if db.dungeons then for _, d in ipairs(db.dungeons) do ProcessQuestDungeon(d) end end
    if db.raids then for _, r in ipairs(db.raids) do ProcessQuestDungeon(r) end end

    local out = {}
    for _, g in ipairs(groups) do
        if g.quests and #g.quests > 0 then
            local anyLevelMet = false
            for _, it in ipairs(g.quests) do
                if playerLevel >= (it.minLevel or 1) then
                    anyLevelMet = true
                    break
                end
            end

            local firstQuest = g.quests[1].quest
            local pinData = {
                id          = "dj_quest_" .. (firstQuest.id or "q"),
                provider    = "dj_quests",
                mapID       = g.mapID,
                x           = g.x,
                y           = g.y,
                size        = 20,
                icon        = "Interface\\GossipFrame\\AvailableQuestIcon",
                texCoord    = { 0, 1, 0, 1 },
                desaturated = not anyLevelMet,
                vertexColor = (not anyLevelMet and { 0.85, 0.55, 0.55, 0.85 }) or { 1, 1, 1, 1 },
                borderColor = { 0, 0, 0, 1 },
                count       = (#g.quests > 1 and #g.quests) or nil,
                countColor  = { 1, 0.82, 0, 1 },
                title       = firstQuest.name or "dungeon quest",
                groupData   = g,
                OnEnter     = OnEnterQuestGroup,
                OnClick     = OnClickQuestGroup,
            }
            table_insert(out, pinData)
        end
    end

    return out
end

-- ─── Provider & Menu Registration ─────────────────────────────────────────────
pins.RegisterProvider("dj_entrances", {
    priority    = 10,
    defaultSize = 22,
    enabled     = function() return DJ_DB().showEntrancePins ~= false end,
    GetPins     = GetEntrancePins,
})

pins.RegisterProvider("dj_quests", {
    priority    = 15,
    defaultSize = 20,
    enabled     = function() return DJ_DB().showQuestPins ~= false end,
    GetPins     = GetQuestPins,
})

pins.RegisterTrackingCategory("dungeon journal", {
    { text = "dungeon entrances", get = function() return sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("showEntrancePins") end, set = function(v) if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then sfui.dungeonjournal.SetOption("showEntrancePins", v) end end },
    { text = "dungeon quests", get = function() return sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("showQuestPins") end, set = function(v) if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then sfui.dungeonjournal.SetOption("showQuestPins", v) end end },
    { text = "filter quests by level", get = function() return sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("questPinsRequireLevel") end, set = function(v) if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then sfui.dungeonjournal.SetOption("questPinsRequireLevel", v) end end },
    { text = "hide outleveled entrances", get = function() return sfui.dungeonjournal and sfui.dungeonjournal.GetOption and sfui.dungeonjournal.GetOption("autoHideTrivialPins") end, set = function(v) if sfui.dungeonjournal and sfui.dungeonjournal.SetOption then sfui.dungeonjournal.SetOption("autoHideTrivialPins", v) end end },
})

sfui.dungeonjournal = sfui.dungeonjournal or {}
function sfui.dungeonjournal.UpdatePins() pins.RequestRefresh(0) end
function sfui.dungeonjournal.HighlightEntrancePin(dungeonID)
    if not dungeonID then return end
    pins.HighlightPin("dj_entrance_" .. dungeonID, 0.6, 28)
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_SETTING_CHANGED", function()
        pins.RequestRefresh(0)
    end)
end
