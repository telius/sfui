local addonName, addon = ...
local sfui = _G.sfui or {}

sfui.tracker = sfui.tracker or {}
sfui.tracker.helpers = sfui.tracker.helpers or {}

local Tooltip = {}
sfui.tracker.helpers.tooltip = Tooltip

local _G = _G
local GameTooltip = _G.GameTooltip
local UIParent = _G.UIParent
local type = type
local tostring = tostring
local ipairs = ipairs
local math_floor = math.floor
local string_format = string.format

local issecretvalue = (sfui.safety and sfui.safety.issecretvalue)
    or (sfui.common and sfui.common.issecretvalue)
    or _G.issecretvalue
    or function() return false end

local function PickAnchor(owner)
    if not owner then return "ANCHOR_LEFT" end
    local cx = owner:GetCenter()
    if not cx or not UIParent then return "ANCHOR_LEFT" end
    local ownerPx = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end
Tooltip.PickAnchor = PickAnchor

function Tooltip.ShowBlockTooltip(owner, bData)
    local tip = _G.GameTooltip
    if not tip or not bData then return end

    local anchor = PickAnchor(owner)
    tip:SetOwner(owner, anchor)
    tip:ClearLines()

    -- 1. Custom tooltip function or string
    if type(bData.tooltip) == "function" then
        bData.tooltip(tip, owner, bData)
        tip:Show()
        return
    elseif type(bData.tooltip) == "string" and bData.tooltip ~= "" then
        tip:AddLine(bData.title or "Objective", 1, 1, 1)
        tip:AddLine(bData.tooltip, 0.85, 0.85, 0.85, true)
        tip:Show()
        return
    end

    -- 2. Achievement
    if bData.isAchievement and bData.achievementID then
        tip:AddLine(bData.title or "Achievement", 0.95, 0.75, 0.3)
        if bData.description and bData.description ~= "" and not issecretvalue(bData.description) then
            tip:AddLine(bData.description, 0.85, 0.85, 0.85, true)
        end
        if bData.points and bData.points > 0 and not issecretvalue(bData.points) then
            tip:AddLine(tostring(bData.points) .. " Achievement Points", 0.3, 0.9, 0.4)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Open Achievement Panel|r", 1, 1, 1)
        tip:AddLine("|cff888888Right-click: Collapse/Expand criteria|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack Achievement|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 3. Traveler's Log (Activities)
    if bData.isPerksActivity and bData.activityID then
        tip:AddLine(bData.title or "Traveler's Log", 0.20, 0.85, 0.95)
        tip:AddLine("Trading Post - Traveler's Log", 0.85, 0.85, 0.85)
        if bData.description and bData.description ~= "" and not issecretvalue(bData.description) then
            tip:AddLine(bData.description, 0.85, 0.85, 0.85, true)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Open Traveler's Log|r", 1, 1, 1)
        tip:AddLine("|cff888888Right-click: Collapse/Expand requirements|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack Activity|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 4. Housing Endeavor
    if bData.isHousingTask and bData.housingTaskID then
        tip:AddLine(bData.title or "Housing Endeavor", 0.55, 0.85, 0.35)
        tip:AddLine("Player Housing Neighborhood Initiative", 0.85, 0.85, 0.85)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Open Endeavors Tab|r", 1, 1, 1)
        tip:AddLine("|cff888888Right-click: Collapse/Expand requirements|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack Task|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 5. Tracked Recipe
    if bData.isRecipe and bData.recipeID then
        tip:AddLine(bData.title or "Tracked Recipe", 0.90, 0.65, 0.30)
        tip:AddLine(bData.isRecraft and "Recrafting Recipe" or "Crafting Recipe", 0.85, 0.85, 0.85)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), r, g, b, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Open Recipe in Profession Window|r", 1, 1, 1)
        tip:AddLine("|cff888888Right-click: Collapse/Expand reagents|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack Recipe|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 6. Collectables (Mounts, Appearances, Decor)
    if bData.isCollectable then
        tip:AddLine(bData.title or "Collectable", 0.85, 0.55, 0.95)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    tip:AddLine("  " .. tostring(line.text), 0.85, 0.85, 0.85, true)
                end
            end
        end
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Preview in Wardrobe / Collections|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Stop Tracking|r", 1, 1, 1)
        tip:Show()
        return
    end

    -- 7. Scenario / Delve / World Event
    if bData.isScenario or bData.isWorldEvent or bData.questID == -1 then
        local r, g, b = 1.00, 0.60, 0.10
        if bData.isWorldEvent then
            if bData.isOngoing then
                r, g, b = 1.00, 0.75, 0.10
            else
                r, g, b = 0.90, 0.45, 0.90
            end
        end
        tip:AddLine(bData.title or "Event", r, g, b)
        if bData.zoneName and bData.zoneName ~= "" and not issecretvalue(bData.zoneName) then
            tip:AddLine(bData.zoneName, 0.70, 0.70, 0.70)
        end
        if bData.timeLeftText and not issecretvalue(bData.timeLeftText) then
            tip:AddLine(bData.timeLeftText, 0.20, 0.85, 0.95)
        end
        if bData.hasReminder then
            tip:AddLine("Event Reminder: ACTIVE", 0.0, 1.0, 0.8)
        end
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local lr, lg, lb = 0.75, 0.75, 0.75
                    if line.completed then lr, lg, lb = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), lr, lg, lb, true)
                end
            end
        end
        tip:AddLine(" ")
        if bData.isWorldEvent then
            tip:AddLine("|cff888888Left-click: Track & Show on Map|r", 1, 1, 1)
            tip:AddLine("|cff888888Right-click: Collapse/Expand objectives|r", 1, 1, 1)
            tip:AddLine("|cff888888Shift-click: Toggle Reminder|r", 1, 1, 1)
        else
            tip:AddLine("|cff888888Left-click: Show on World Map|r", 1, 1, 1)
            tip:AddLine("|cff888888Right-click: Collapse/Expand objectives|r", 1, 1, 1)
        end
        tip:Show()
        return
    end

    -- 8. Standard Quest or World Quest
    if bData.questID and bData.questID > 0 then
        local isComplete = bData.isComplete
        if isComplete == nil and _G.C_QuestLog and _G.C_QuestLog.IsComplete then
            isComplete = _G.C_QuestLog.IsComplete(bData.questID)
        end

        local titleText = bData.rawTitle or bData.title or (_G.C_QuestLog and _G.C_QuestLog.GetTitleForQuestID and _G.C_QuestLog.GetTitleForQuestID(bData.questID)) or "Quest"
        if isComplete then
            tip:AddLine(titleText, 0.2, 1.0, 0.2)
            tip:AddLine("|cff33ff33Ready for turn-in|r", 0.2, 1.0, 0.2)
        elseif bData.isFailed then
            tip:AddLine(titleText, 1.0, 0.2, 0.2)
            tip:AddLine("|cffff3333Failed|r", 1.0, 0.2, 0.2)
        else
            tip:AddLine(titleText, 1, 1, 1)
        end

        if bData.zoneName and bData.zoneName ~= "" and not issecretvalue(bData.zoneName) then
            tip:AddLine(bData.zoneName, 0.70, 0.70, 0.70)
        end

        if bData.suggestedGroup and bData.suggestedGroup > 1 then
            tip:AddLine(string_format("Suggested Players: %d", bData.suggestedGroup), 0.30, 0.80, 1.00)
        end

        if bData.timeLeftText and not issecretvalue(bData.timeLeftText) then
            tip:AddLine(bData.timeLeftText, 0.20, 0.85, 0.95)
        end

        local isCamelot = sfui.isForever or (sfui.compat and (sfui.compat.is_wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        if bData.isRepeatable and not bData.isWarbandCompleted then
            tip:AddLine("Repeatable Quest", 0.00, 1.00, 1.00)
        elseif bData.isWarbandCompleted and not isCamelot then
            tip:AddLine("Warband Completed", 0.75, 0.15, 0.15)
        end

        -- Quest Description / Summary (Classic/Camelot & Retail)
        local questDesc = nil
        if bData.questLogIndex and _G.GetQuestLogQuestText then
            local desc, obj = _G.GetQuestLogQuestText(bData.questLogIndex)
            if obj and obj ~= "" and not issecretvalue(obj) then
                questDesc = obj
            elseif not obj and _G.SelectQuestLogEntry and _G.GetQuestLogSelection then
                local prev = _G.GetQuestLogSelection()
                _G.SelectQuestLogEntry(bData.questLogIndex)
                local d, o = _G.GetQuestLogQuestText()
                if prev and prev > 0 then _G.SelectQuestLogEntry(prev) end
                if o and o ~= "" and not issecretvalue(o) then
                    questDesc = o
                elseif d and d ~= "" and not issecretvalue(d) then
                    questDesc = d
                end
            elseif desc and desc ~= "" and not issecretvalue(desc) then
                questDesc = desc
            end
        end
        if not questDesc and _G.C_QuestLog and _G.C_QuestLog.GetQuestDescription then
            local desc = _G.C_QuestLog.GetQuestDescription(bData.questID)
            if desc and desc ~= "" and not issecretvalue(desc) then
                questDesc = desc
            end
        end
        if questDesc then
            tip:AddLine(" ")
            tip:AddLine(questDesc, 0.85, 0.85, 0.85, true)
        end

        -- Objective lines
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    local r, g, b = 0.75, 0.75, 0.75
                    if line.completed then r, g, b = 0.30, 0.80, 0.30 end
                    tip:AddLine("  " .. (line.completed and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(line.text), r, g, b, true)
                end
            end
        elseif _G.C_QuestLog and _G.C_QuestLog.GetQuestObjectives then
            local objs = _G.C_QuestLog.GetQuestObjectives(bData.questID)
            if objs and #objs > 0 then
                tip:AddLine(" ")
                for _, obj in ipairs(objs) do
                    if obj.text and obj.text ~= "" and not issecretvalue(obj.text) then
                        local r, g, b = 0.75, 0.75, 0.75
                        if obj.finished then r, g, b = 0.30, 0.80, 0.30 end
                        tip:AddLine("  " .. (obj.finished and "|cff33cc33✓|r " or "|cff888888-|r ") .. tostring(obj.text), r, g, b, true)
                    end
                end
            end
        end

        -- Group Party Progress
        if _G.IsInGroup and _G.IsInGroup() and tip.SetQuestPartyProgress then
            pcall(tip.SetQuestPartyProgress, tip, bData.questID)
        end

        -- Click hints
        tip:AddLine(" ")
        tip:AddLine("|cff888888Left-click: Open Quest Details / Map|r", 1, 1, 1)
        tip:AddLine("|cff888888Right-click: Collapse/Expand objectives|r", 1, 1, 1)
        tip:AddLine("|cff888888Shift-click: Untrack Quest|r", 1, 1, 1)
        if not bData.isWorldQuest then
            tip:AddLine("|cff888888Alt-click: Share Quest|r", 1, 1, 1)
            tip:AddLine("|cff888888Ctrl-click: Abandon Quest|r", 1, 1, 1)
        end
        if bData.canFindGroup then
            tip:AddLine("|cff00ff88Eye Button: Find Group in Group Finder|r", 1, 1, 1)
        end

        tip:Show()
        return
    end

    -- 9. Generic fallback if block has a title
    if bData.title and bData.title ~= "" then
        tip:AddLine(bData.title, 1, 1, 1)
        if bData.lines and #bData.lines > 0 then
            tip:AddLine(" ")
            for _, line in ipairs(bData.lines) do
                if line.text and line.text ~= "" and not issecretvalue(line.text) then
                    tip:AddLine("  - " .. tostring(line.text), 0.85, 0.85, 0.85, true)
                end
            end
        end
        tip:Show()
    end
end

function Tooltip.HideBlockTooltip(owner, bData)
    local tip = _G.GameTooltip
    if tip then tip:Hide() end
end

return Tooltip
