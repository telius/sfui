local addonName, addon = ...
sfui = sfui or {}
sfui.fishing = sfui.fishing or {}
sfui.fishing.hud = sfui.fishing.hud or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing/fishing_hud.lua
--  Expandable Floating Fishing HUD (Camelot & Classic Forever)
--
--  Auto-shows when a fishing pole is equipped in main hand or in edit mode.
--  Header displays zone skill check & water habitat, free bag alert, skill rank
--  with skillup progress/milestones, clickable secure lure & bag-container
--  buttons, and session catch rate. Expandable drawer lists live current-zone
--  species (drop rate, bite windows, bag/goal, session, and total counts).
-- ══════════════════════════════════════════════════════════════════════════════

local HUD = sfui.fishing.hud
local common = sfui.common
local set_square_icon_coords = (common and common.set_square_icon_coords)
    or function(tex) if tex and tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end end
local theme = sfui.theme
local events = sfui.events
local data = sfui.fishing_data

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local IsAltKeyDown = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local InCombatLockdown = _G.InCombatLockdown
local GetTime = _G.GetTime
local pairs, ipairs, tonumber, tostring = pairs, ipairs, tonumber, tostring
local math_floor = _G.math.floor
local math_max = _G.math.max
local table_sort = _G.table.sort
local table_concat = _G.table.concat
local string_format = _G.string.format

local HUD_WIDTH = 310
local HEADER_HEIGHT = 58
local COL_HEADER_HEIGHT = 18
local ROW_HEIGHT = 18
local BOTTOM_PAD = 6
local MAX_HUD_ROWS = 18
local GOAL_PRESETS = { 10, 20, 40, 60, 100 }

local hudFrame = nil
local isHudLocked = true
local pendingCombatUpdate = false
local QueueCombatUpdate
local openingContainerUntil = 0
local lastListTickTime = 0
local activeZoneGoal = nil
local bagCounts = {}
local goalNotified = {}
local goalSeeded = false

local UpdateHud
local OnHudTick
local UpdateHeaderRightLayout
local UpdateSpeciesList

-- ─── Settings & Formatting Helpers ───────────────────────────────────────────

local function GetHudConfig()
    _G.SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB.fishing = _G.SfuiDB.fishing or {}
    local cfg = _G.SfuiDB.fishing.hud
    if type(cfg) ~= "table" then
        cfg = {}
        _G.SfuiDB.fishing.hud = cfg
    end
    if cfg.enabled == nil then cfg.enabled = true end
    if cfg.collapsed == nil then cfg.collapsed = false end
    if cfg.hideTrophies == nil then cfg.hideTrophies = true end
    if type(cfg.goals) ~= "table" then cfg.goals = {} end
    return cfg
end

local function FormatDuration(seconds)
    return sfui.common.format_duration(seconds, "clock_compact", "0s")
end

local function FormatDurationEta(seconds)
    return sfui.common.format_duration(seconds, "eta", false)
end

local function SetTextIfChanged(fs, text, fieldKey)
    if not fs then return end
    if hudFrame and fieldKey then
        if hudFrame[fieldKey] ~= text then
            hudFrame[fieldKey] = text
            fs:SetText(text)
        end
    elseif fs._sfuiLastText ~= text then
        fs._sfuiLastText = text
        fs:SetText(text)
    end
end

local function GetDynamicTooltipAnchor(frame)
    if hudFrame and hudFrame.GetCenter and UIParent and UIParent.GetWidth then
        local cx = hudFrame:GetCenter()
        local uiW = UIParent:GetWidth()
        if cx and uiW and cx > (uiW * 0.5) then
            return "ANCHOR_LEFT"
        end
    end
    return "ANCHOR_RIGHT"
end

-- ─── Position & Size Management ──────────────────────────────────────────────

local function RestoreHudPosition()
    if not hudFrame then return end
    if InCombatLockdown and InCombatLockdown() then
        QueueCombatUpdate()
        return
    end
    local pos = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.hudPos
    hudFrame:ClearAllPoints()
    if pos and pos.point then
        hudFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or -120)
    else
        hudFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function ApplyHudSize(targetHeight)
    if not hudFrame then return end
    if InCombatLockdown and InCombatLockdown() then
        QueueCombatUpdate()
        return
    end
    local pt = hudFrame:GetPoint()
    if pt and pt ~= "TOP" and pt ~= "TOPLEFT" and pt ~= "TOPRIGHT" then
        local left, width, top = hudFrame:GetLeft(), hudFrame:GetWidth(), hudFrame:GetTop()
        local uiW = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
        local uiH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
        if left and width and top and uiW > 0 and uiH > 0 then
            local rx = math_floor(((left + (width * 0.5)) - (uiW * 0.5)) + 0.5)
            local ry = math_floor((top - uiH) + 0.5)
            _G.SfuiDB = _G.SfuiDB or {}
            _G.SfuiDB.fishing = _G.SfuiDB.fishing or {}
            _G.SfuiDB.fishing.hudPos = { point = "TOP", relPoint = "TOP", x = rx, y = ry }
            hudFrame:ClearAllPoints()
            hudFrame:SetPoint("TOP", UIParent, "TOP", rx, ry)
        end
    end
    targetHeight = math_max(HEADER_HEIGHT, math_floor((targetHeight or HEADER_HEIGHT) + 0.5))
    if hudFrame._lastWidth ~= HUD_WIDTH or hudFrame._lastHeight ~= targetHeight then
        hudFrame._lastWidth = HUD_WIDTH
        hudFrame._lastHeight = targetHeight
        hudFrame:SetSize(HUD_WIDTH, targetHeight)
        local mover = sfui.movers and sfui.movers.list and sfui.movers.list["fishinghud"]
        if mover and mover.SetSize then
            mover:SetSize(HUD_WIDTH, targetHeight)
        end
    end
end

local function StartHudDrag()
    if not hudFrame then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not isHudLocked or (IsAltKeyDown and IsAltKeyDown()) or (sfui.movers and sfui.movers.isUnlocked) then
        hudFrame:StartMoving()
        hudFrame._isMoving = true
    end
end

local function StopHudDrag()
    if not hudFrame or not hudFrame._isMoving then return end
    hudFrame:StopMovingOrSizing()
    hudFrame._isMoving = false
    hudFrame._justDraggedTime = GetTime()

    local uiW = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local uiH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 0
    local left = hudFrame:GetLeft()
    local width = hudFrame:GetWidth()
    local top = hudFrame:GetTop()

    local pt, relPt, rx, ry
    if left and width and top and uiW > 0 and uiH > 0 then
        pt = "TOP"
        relPt = "TOP"
        rx = math_floor(((left + (width * 0.5)) - (uiW * 0.5)) + 0.5)
        ry = math_floor((top - uiH) + 0.5)
        hudFrame:ClearAllPoints()
        hudFrame:SetPoint(pt, UIParent, relPt, rx, ry)
    else
        local point, _, rPoint, x, y = hudFrame:GetPoint()
        pt = point or "TOP"
        relPt = rPoint or pt
        rx = math_floor((x or 0) + 0.5)
        ry = math_floor((y or 0) + 0.5)
    end

    _G.SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB.fishing = _G.SfuiDB.fishing or {}
    _G.SfuiDB.fishing.hudPos = { point = pt, relPoint = relPt, x = rx, y = ry }

    local mover = sfui.movers and sfui.movers.list and sfui.movers.list["fishinghud"]
    if mover then
        mover:ClearAllPoints()
        mover:SetPoint(pt, UIParent, relPt, rx, ry)
    end
end

local function WasRecentlyDragged()
    return hudFrame and hudFrame._justDraggedTime and (GetTime() - hudFrame._justDraggedTime) < 0.2
end

local function AttachDragForwarding(widget)
    widget:RegisterForDrag("LeftButton")
    widget:SetScript("OnDragStart", StartHudDrag)
    widget:SetScript("OnDragStop", StopHudDrag)
end

-- ─── Bag Counts & Goal Celebration ───────────────────────────────────────────

local function GetBagCount(itemID)
    if not itemID then return 0 end
    local cached = bagCounts[itemID]
    if cached ~= nil then
        return cached
    end
    local count = (_G.C_Item and _G.C_Item.GetItemCount and _G.C_Item.GetItemCount(itemID, false))
        or (_G.GetItemCount and _G.GetItemCount(itemID, false))
        or 0
    bagCounts[itemID] = count
    return count
end

local function RefreshBagCountsAndGoals()
    for k in pairs(bagCounts) do
        bagCounts[k] = nil
    end
    local cfg = GetHudConfig()
    local goals = cfg.goals
    if type(goals) ~= "table" then
        goalSeeded = true
        return
    end

    for rawID, target in pairs(goals) do
        local itemID = tonumber(rawID)
        local goal = tonumber(target)
        if itemID and goal and goal > 0 then
            local count = GetBagCount(itemID)
            if not goalSeeded then
                if count >= goal then
                    goalNotified[itemID] = true
                end
            elseif count >= goal and not goalNotified[itemID] then
                goalNotified[itemID] = true
                local disp = (data and data.GetSpeciesDisplay and data.GetSpeciesDisplay(itemID, true)) or ("item:" .. itemID)
                if common and common.print then
                    common.print(string_format("fishing goal reached: %s (%d/%d)!", disp, count, goal))
                end
                if _G.PlaySound then
                    _G.PlaySound((_G.SOUNDKIT and _G.SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 878)
                end
            elseif count < goal then
                goalNotified[itemID] = nil
            end
        elseif itemID then
            goalNotified[itemID] = nil
        end
    end
    goalSeeded = true
end

local function SetItemGoal(itemID, newGoal)
    if not itemID then return end
    local cfg = GetHudConfig()
    if newGoal and newGoal > 0 then
        newGoal = math_floor(newGoal)
        cfg.goals[itemID] = newGoal
        local count = GetBagCount(itemID)
        if count >= newGoal then
            goalNotified[itemID] = true
        else
            goalNotified[itemID] = nil
        end
    else
        cfg.goals[itemID] = nil
        goalNotified[itemID] = nil
    end
end

-- ─── Header & Row Tooltips ───────────────────────────────────────────────────

local function OnHudEnter(self)
    local tip = common.get_tooltip()
    if not tip then return end

    tip._sfuiInFishingAtlas = nil
    tip:SetOwner(self, "ANCHOR_TOP", 0, 8)
    tip:ClearLines()

    local mapID = common.get_player_map_id()
    local zoneName = common.get_player_map_name() or (data.GetZoneName and data.GetZoneName(mapID)) or "current zone"
    local subZone = (_G.GetSubZoneText and _G.GetSubZoneText()) or (_G.GetMinimapZoneText and _G.GetMinimapZoneText())
    local reqSkill, subArea, activeHabitat, _, isMixed = data.ResolveSubZone(mapID, subZone)
    local rank, maxRank, mod, totalSkill = sfui.fishing.GetFishingSkill()

    local headerText = zoneName:lower()
    if type(subZone) == "string" and subZone ~= "" and subZone:lower() ~= headerText then
        headerText = string_format("%s • |cffcccccc%s|r", headerText, subZone:lower())
    end
    tip:AddLine(headerText, 1, 0.82, 0)

    if reqSkill then
        local statusColor = (totalSkill >= reqSkill) and "|cff00ff880% getaways|r" or "|cffff4444fish can escape|r"
        tip:AddDoubleLine("required skill:", string_format("%d (%s)", reqSkill, statusColor), 0.8, 0.8, 0.8, 1, 1, 1)
        if subArea and reqSkill < (subArea.skill or 0) then
            tip:AddDoubleLine("sub-area requirement:", string_format("%s (|cffffd100%d|r)", subArea.area, subArea.skill), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    else
        tip:AddDoubleLine("required skill:", "|cff888888unknown|r", 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if activeHabitat == "coastal" then
        tip:AddDoubleLine("water habitat:", "|cff44bbffcoastal / ocean|r", 0.8, 0.8, 0.8, 1, 1, 1)
    elseif activeHabitat == "inland" then
        tip:AddDoubleLine("water habitat:", "|cff66dd88inland (lake / river)|r", 0.8, 0.8, 0.8, 1, 1, 1)
    elseif activeHabitat == "oasis" then
        tip:AddDoubleLine("water habitat:", "|cffffcc44barrens oasis|r", 0.8, 0.8, 0.8, 1, 1, 1)
    elseif isMixed then
        tip:AddDoubleLine("water habitat:", "|cff44bbff[coast]|r & |cff66dd88[inland]|r waters", 0.8, 0.8, 0.8, 1, 1, 1)
    end

    tip:AddDoubleLine("your fishing skill:", string_format("%d / %d (|cff00ffff+%d bonus|r = %d)", rank, maxRank, mod, totalSkill), 0.8, 0.8, 0.8, 1, 1, 1)

    if data.GetActiveMilestone then
        local playerLevel = _G.UnitLevel and _G.UnitLevel("player")
        local m, st = data.GetActiveMilestone(rank, maxRank, playerLevel)
        if m and st then
            if st == "capped" then
                tip:AddDoubleLine("trainer milestone:", string_format("|cffff4444[capped at %d]|r %s", maxRank, m.text), 1, 0.4, 0.4, 1, 0.82, 0.5)
            elseif st == "available" then
                tip:AddDoubleLine("trainer milestone:", string_format("|cffffaa00[ready]|r %s", m.text), 0.9, 0.82, 0.5, 1, 1, 1)
            elseif st == "level_locked" then
                tip:AddDoubleLine("trainer milestone:", string_format("|cffffaa00[need lvl %d]|r %s", m.reqLevel or 0, m.text), 0.9, 0.82, 0.5, 0.8, 0.8, 0.8)
            end
        end
    end

    local session = sfui.fishing.session
    if session then
        tip:AddLine(" ")
        tip:AddLine("current session:", 0.9, 0.82, 0.5)
        tip:AddDoubleLine("catches / casts:", string_format("%d / %d", session.catches or 0, session.casts or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine("current streak:", string_format("%d in a row", session.streak or 0), 0.8, 0.8, 0.8, 0.2, 1, 0.4)
        local expected = data.GetExpectedCatchesForSkillup and data.GetExpectedCatchesForSkillup(rank)
        if expected and rank > 0 and rank < maxRank and rank < 300 then
            tip:AddDoubleLine("next skillup:", string_format("%d / ~%d catches", session.catchesSinceSkillup or 0, expected), 0.8, 0.8, 0.8, 0.53, 0.87, 1)
        end
    end

    tip:AddLine(" ")
    tip:AddLine("|cff888888right-click: atlas • alt+drag: move • [-]/[+] toggle fish list|r", 0.5, 0.5, 0.5)
    tip:Show()
end

local function OnHudLeave()
    local tip = common.get_tooltip()
    if tip then tip._sfuiInFishingAtlas = nil end
    common.hide_tooltip()
end

local function OnLureEnter(self)
    self._isHovered = true
    local tip = common.get_tooltip()
    if not tip then return end

    tip:SetOwner(self, "ANCHOR_TOP", 0, 6)
    tip:ClearLines()
    tip:AddLine("fishing lure", 1, 0.82, 0)

    local rank = sfui.fishing.GetFishingSkill()
    local bestLure = data.FindBestLureInBags and data.FindBestLureInBags(rank)
    if self._hasLure and self._expSec and self._expSec > 0 then
        local remColor = (self._expSec <= 60) and "|cffff4444" or "|cff00ff88"
        tip:AddDoubleLine("active lure:", string_format("%s%s remaining|r", remColor, FormatDuration(self._expSec)), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        tip:AddDoubleLine("active lure:", "|cffffaa00none|r", 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if bestLure then
        tip:AddDoubleLine("best in bags:", string_format("|cff00ffff%s|r (+%d skill, %d in bags)", (bestLure.name or "lure"):lower(), bestLure.bonus or 0, bestLure.count or 1), 0.8, 0.8, 0.8, 1, 1, 1)
        if (not self._hasLure or (self._expSec or 0) <= 60) then
            if InCombatLockdown and InCombatLockdown() then
                tip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
            else
                tip:AddLine("|cff55ff55left-click to apply lure to fishing pole|r", 0.3, 1, 0.3)
            end
        end
    else
        tip:AddLine("|cff888888no compatible lures found in bags.|r", 0.6, 0.6, 0.6)
    end
    tip:Show()
end

local function OnLureLeave(self)
    self._isHovered = false
    common.hide_tooltip()
end

local function OnContainerEnter(self)
    local tip = common.get_tooltip()
    if not tip or not self._container then return end
    local c = self._container
    tip:SetOwner(self, "ANCHOR_TOP", 0, 6)
    tip:ClearLines()
    tip:AddLine(string_format("open %s", (c.name or "container"):lower()), 0, 1, 1)
    tip:AddDoubleLine("total in bags:", tostring(c.totalCount or 1), 0.8, 0.8, 0.8, 1, 1, 1)
    if InCombatLockdown and InCombatLockdown() then
        tip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
    else
        tip:AddLine("|cff55ff55left-click to open • right-click: atlas|r", 0.3, 1, 0.3)
    end
    tip:Show()
end

local function OnContainerLeave()
    common.hide_tooltip()
end

local function OnRowEnter(self)
    local rowData = self._rowData
    if not rowData or not rowData.itemID then return end
    local itemID = rowData.itemID
    local tip = common.get_tooltip()
    if not tip then return end

    tip._sfuiInFishingAtlas = true
    tip:SetOwner(self, GetDynamicTooltipAnchor(self))
    tip:SetHyperlink("item:" .. itemID)

    tip:AddLine(" ")
    local habText = (rowData.habitat == "coastal" and "coastal (ocean)")
        or (rowData.habitat == "inland" and "inland (lake / river)")
        or (rowData.habitat == "oasis" and "barrens oasis")
        or "all waters"
    if rowData.share and rowData.share > 0 then
        tip:AddDoubleLine("zone drop rate:", string_format("%.1f%% • %s", rowData.share, habText), 0.7, 0.85, 1, 1, 1, 1)
    else
        tip:AddDoubleLine("water habitat:", habText, 0.7, 0.85, 1, 1, 1, 1)
    end

    if rowData.biteDetail then
        tip:AddDoubleLine("bite window:", rowData.biteDetail, 0.7, 0.85, 1, 1, 0.9, 0.5)
    end

    tip:AddDoubleLine(
        "session / zone / total / bags:",
        string_format("|cffffffff%d|r / |cffffffff%d|r / |cffffffff%d|r / |cff00ffff%d|r", rowData.sessionCount or 0, rowData.zoneTotal or 0, rowData.totalCount or 0, rowData.bagCount or 0),
        0.8, 0.8, 0.8, 1, 1, 1
    )

    if rowData.goal and rowData.goal > 0 then
        local gStr
        if (rowData.bagCount or 0) >= rowData.goal then
            gStr = string_format("|cff00ff88%d/%d (complete!)|r", rowData.bagCount or 0, rowData.goal)
        elseif rowData.etaSec then
            gStr = string_format("|cff80d8ff%d/%d (eta ~%s)|r", rowData.bagCount or 0, rowData.goal, FormatDurationEta(rowData.etaSec) or "--")
        else
            gStr = string_format("|cff80d8ff%d/%d|r", rowData.bagCount or 0, rowData.goal)
        end
        tip:AddDoubleLine("farming goal:", gStr, 0.8, 0.8, 0.8, 1, 1, 1)
    end

    if sfui.fishing and sfui.fishing.GetSpeciesCharBreakdown then
        local _, totalCaught, anglers = sfui.fishing.GetSpeciesCharBreakdown(itemID)
        if totalCaught and totalCaught > 0 and type(anglers) == "table" and #anglers > 0 then
            tip:AddLine(" ")
            tip:AddLine(string_format("caught across accounts (%d):", totalCaught), 0, 1, 1)
            for i = 1, math.min(#anglers, 8) do
                local a = anglers[i]
                tip:AddDoubleLine("  " .. (a.coloredName or a.name or "?") .. (a.accountTag or ""), tostring(a.count or 0), 1, 1, 1, 0, 1, 0.53)
            end
        end
    end

    tip:AddLine(" ")
    tip:AddLine("|cff888888click: atlas • ctrl-click: recipes • shift-click: link • alt-click/scroll: goal|r", 0.5, 0.5, 0.5)
    tip:Show()
end

local function OnRowLeave()
    local tip = common.get_tooltip()
    if tip then tip._sfuiInFishingAtlas = nil end
    common.hide_tooltip()
end

-- ─── Row Interactions ────────────────────────────────────────────────────────

local function CyclePresetGoal(itemID, bagCount, currentGoal)
    local threshold = (currentGoal and currentGoal > 0) and currentGoal or (bagCount or 0)
    for _, preset in ipairs(GOAL_PRESETS) do
        if preset > threshold then
            return preset
        end
    end
    if not currentGoal or currentGoal <= 0 then
        return (bagCount or 0) + 20
    end
    return nil
end

local function OnRowClick(self, button)
    if WasRecentlyDragged() then return end
    local rowData = self._rowData
    if not rowData or not rowData.itemID then return end
    local itemID = rowData.itemID

    if IsAltKeyDown and IsAltKeyDown() then
        if button == "LeftButton" then
            local nextGoal = CyclePresetGoal(itemID, rowData.bagCount, rowData.goal)
            SetItemGoal(itemID, nextGoal)
            UpdateHud()
            if self:IsMouseOver() then OnRowEnter(self) end
            return
        elseif button == "RightButton" then
            SetItemGoal(itemID, nil)
            UpdateHud()
            if self:IsMouseOver() then OnRowEnter(self) end
            return
        end
    end

    if button == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
        local _, link = common.get_item_info(itemID)
        link = link or ("item:" .. itemID)
        if common.insert_link_to_chat then
            common.insert_link_to_chat(link)
        end
        return
    end

    if button == "LeftButton" and IsControlKeyDown and IsControlKeyDown() then
        local opened = false
        if sfui.recipes and sfui.recipes.GetRecipesUsingReagent and sfui.recipes.OpenBrowserForReagent then
            local sids = sfui.recipes.GetRecipesUsingReagent(itemID)
            if sids and #sids > 0 then
                opened = sfui.recipes.OpenBrowserForReagent(itemID)
            end
        end
        if not opened and sfui.nav and sfui.nav.OpenRecipeOrFishing then
            opened = sfui.nav.OpenRecipeOrFishing(itemID)
        end
        if not opened and sfui.fishing.atlas and sfui.fishing.atlas.OpenToSpecies then
            sfui.fishing.atlas.OpenToSpecies(itemID)
        end
        return
    end

    if button == "LeftButton" then
        if sfui.fishing.atlas and sfui.fishing.atlas.OpenToSpecies then
            sfui.fishing.atlas.OpenToSpecies(itemID)
        end
    elseif button == "RightButton" then
        if sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
            sfui.fishing.atlas.Toggle()
        end
    end
end

local function OnRowMouseWheel(self, delta)
    if not (IsAltKeyDown and IsAltKeyDown()) then return end
    local rowData = self._rowData
    if not rowData or not rowData.itemID then return end
    local step = (IsShiftKeyDown and IsShiftKeyDown()) and 1 or 5
    local cur = (rowData.goal and rowData.goal > 0) and rowData.goal or (rowData.bagCount or 0)
    local nextGoal = cur + (delta * step)
    if nextGoal <= 0 then
        nextGoal = nil
    end
    SetItemGoal(rowData.itemID, nextGoal)
    UpdateHud()
    if self:IsMouseOver() then OnRowEnter(self) end
end

local function CreateSpeciesRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(HUD_WIDTH - 12, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -(HEADER_HEIGHT + COL_HEADER_HEIGHT + ((index - 1) * ROW_HEIGHT)))
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    AttachDragForwarding(row)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(1, 1, 1, 0.03)
    else
        bg:SetColorTexture(0, 0, 0, 0)
    end
    row.bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    set_square_icon_coords(icon)
    row.icon = icon

    local totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    totalText:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    totalText:SetWidth(34)
    totalText:SetJustifyH("RIGHT")
    totalText:SetWordWrap(false)
    row.totalText = totalText

    local sessText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessText:SetPoint("RIGHT", totalText, "LEFT", -4, 0)
    sessText:SetWidth(30)
    sessText:SetJustifyH("RIGHT")
    sessText:SetWordWrap(false)
    row.sessText = sessText

    local bagText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagText:SetPoint("RIGHT", sessText, "LEFT", -4, 0)
    bagText:SetWidth(42)
    bagText:SetJustifyH("RIGHT")
    bagText:SetWordWrap(false)
    row.bagText = bagText

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameText:SetPoint("RIGHT", bagText, "LEFT", -4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", OnRowLeave)
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnMouseWheel", OnRowMouseWheel)
    row:Hide()
    return row
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────

local function CreateHudFrame()
    if hudFrame then return hudFrame end

    local f = CreateFrame("Button", "SfuiFishingHud", UIParent, "BackdropTemplate")
    f:SetSize(HUD_WIDTH, HEADER_HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    hudFrame = f
    RestoreHudPosition()

    f:SetScript("OnDragStart", StartHudDrag)
    f:SetScript("OnDragStop", StopHudDrag)
    f:SetScript("OnEnter", OnHudEnter)
    f:SetScript("OnLeave", OnHudLeave)
    f:SetScript("OnClick", function(self, button)
        if WasRecentlyDragged() then return end
        if button == "RightButton" then
            if sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        end
    end)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Elevated overlay keeps text and controls above theme borderFrames
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    overlay:EnableMouse(false)
    f.overlayFrame = overlay

    local function ApplyHudTheme(frame)
        if not (theme and theme.RegisterWindow) then
            common.apply_flat_backdrop(frame, { 0.08, 0.08, 0.10, 0.90 }, { 0.25, 0.25, 0.30, 0.85 })
        end
        if frame.overlayFrame and not (InCombatLockdown and InCombatLockdown()) then
            frame.overlayFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
        end
    end
    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, ApplyHudTheme)
    else
        ApplyHudTheme(f)
    end

    f:HookScript("OnShow", function()
        if f.overlayFrame and not (InCombatLockdown and InCombatLockdown()) then
            f.overlayFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
        end
        events.RegisterUpdate("sfui_fishing_hud", 0.5, OnHudTick)
    end)
    f:HookScript("OnHide", function()
        events.UnregisterUpdate("sfui_fishing_hud")
    end)

    -- ── Header Row 1: Zone | Bag Warning | [Container] | [Trophy Filter] | [-/+] ──
    local collapseBtn = CreateFrame("Button", nil, overlay)
    collapseBtn:SetSize(18, 16)
    collapseBtn:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -6, -5)
    collapseBtn:RegisterForClicks("LeftButtonUp")
    AttachDragForwarding(collapseBtn)
    local colHl = collapseBtn:CreateTexture(nil, "HIGHLIGHT")
    colHl:SetAllPoints()
    colHl:SetColorTexture(1, 1, 1, 0.15)
    local colText = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    colText:SetPoint("CENTER")
    collapseBtn.text = colText
    collapseBtn:SetScript("OnClick", function()
        if WasRecentlyDragged() then return end
        HUD.ToggleCollapse()
    end)
    collapseBtn:SetScript("OnEnter", function(self)
        local tip = common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP", 0, 6)
        tip:ClearLines()
        local cfg = GetHudConfig()
        tip:AddLine(cfg.collapsed and "expand zone fish list" or "collapse zone fish list", 1, 0.82, 0)
        tip:AddLine("|cff888888left-click to toggle • /sffish collapse|r", 0.6, 0.6, 0.6)
        tip:Show()
    end)
    collapseBtn:SetScript("OnLeave", common.hide_tooltip)
    f.collapseBtn = collapseBtn

    local trophyBtn = CreateFrame("Button", nil, overlay)
    trophyBtn:SetSize(36, 16)
    trophyBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -2, 0)
    trophyBtn:RegisterForClicks("LeftButtonUp")
    AttachDragForwarding(trophyBtn)
    local trHl = trophyBtn:CreateTexture(nil, "HIGHLIGHT")
    trHl:SetAllPoints()
    trHl:SetColorTexture(1, 1, 1, 0.15)
    local trText = trophyBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trText:SetPoint("CENTER")
    trophyBtn.text = trText
    trophyBtn:SetScript("OnClick", function()
        if WasRecentlyDragged() then return end
        local cfg = GetHudConfig()
        cfg.hideTrophies = not cfg.hideTrophies
        UpdateHud()
    end)
    trophyBtn:SetScript("OnEnter", function(self)
        local tip = common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP", 0, 6)
        tip:ClearLines()
        local cfg = GetHudConfig()
        tip:AddLine("trophy & rare filter", 1, 0.82, 0)
        tip:AddLine(
            cfg.hideTrophies
                and "currently showing main zone species (hiding <1% trophies unless caught or targeted)."
                or "currently showing all species including <1% rare trophies.",
            0.8, 0.8, 0.8, true
        )
        tip:AddLine("|cff888888left-click to toggle|r", 0.6, 0.6, 0.6)
        tip:Show()
    end)
    trophyBtn:SetScript("OnLeave", common.hide_tooltip)
    f.trophyBtn = trophyBtn

    local containerBtn = CreateFrame("Button", "SfuiFishingHudContainerBtn", overlay, "SecureActionButtonTemplate")
    containerBtn:SetSize(18, 18)
    containerBtn:SetPoint("RIGHT", trophyBtn, "LEFT", -3, 0)
    containerBtn:RegisterForClicks("AnyUp", "AnyDown")

    local contBg = containerBtn:CreateTexture(nil, "BACKGROUND")
    contBg:SetAllPoints()
    contBg:SetColorTexture(0, 0, 0, 0.85)
    local contIcon = containerBtn:CreateTexture(nil, "ARTWORK")
    contIcon:SetPoint("TOPLEFT", containerBtn, "TOPLEFT", 1, -1)
    contIcon:SetPoint("BOTTOMRIGHT", containerBtn, "BOTTOMRIGHT", -1, 1)
    set_square_icon_coords(contIcon)
    containerBtn.icon = contIcon

    local contHl = containerBtn:CreateTexture(nil, "HIGHLIGHT")
    contHl:SetAllPoints()
    contHl:SetColorTexture(1, 1, 1, 0.25)

    local contCount = containerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    contCount:SetPoint("BOTTOMRIGHT", containerBtn, "BOTTOMRIGHT", 0, 0)
    contCount:SetShadowColor(0, 0, 0, 1)
    contCount:SetShadowOffset(1, -1)
    containerBtn.countText = contCount

    containerBtn:SetScript("PostClick", function(self, button, down)
        if down then return end
        if button == "LeftButton" and self._container then
            openingContainerUntil = GetTime() + 1.5
        elseif button == "RightButton" then
            if sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        end
    end)
    containerBtn:SetScript("OnEnter", OnContainerEnter)
    containerBtn:SetScript("OnLeave", OnContainerLeave)
    containerBtn:Hide()
    f.containerBtn = containerBtn

    local bagText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagText:SetPoint("RIGHT", containerBtn, "LEFT", -4, 0)
    bagText:SetJustifyH("RIGHT")
    f.bagText = bagText

    local zoneText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -6)
    zoneText:SetPoint("RIGHT", bagText, "LEFT", -4, 0)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetWordWrap(false)
    f.zoneText = zoneText

    -- ── Header Row 2: Skill Rank (+Skillup) | Clickable Secure Lure Button ────
    local lureBtn = CreateFrame("Button", "SfuiFishingHudLureBtn", overlay, "SecureActionButtonTemplate")
    lureBtn:SetSize(118, 16)
    lureBtn:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -8, -23)
    lureBtn:RegisterForClicks("AnyUp", "AnyDown")

    local lureHl = lureBtn:CreateTexture(nil, "HIGHLIGHT")
    lureHl:SetAllPoints()
    lureHl:SetColorTexture(1, 1, 1, 0.12)

    local lureIcon = lureBtn:CreateTexture(nil, "ARTWORK")
    lureIcon:SetSize(13, 13)
    lureIcon:SetPoint("LEFT", lureBtn, "LEFT", 2, 0)
    set_square_icon_coords(lureIcon)
    lureIcon:Hide()
    lureBtn.icon = lureIcon

    local lureText = lureBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureText:SetPoint("LEFT", lureBtn, "LEFT", 2, 0)
    lureText:SetPoint("RIGHT", lureBtn, "RIGHT", 0, 0)
    lureText:SetJustifyH("RIGHT")
    lureText:SetWordWrap(false)
    lureBtn.text = lureText

    lureBtn:SetScript("PostClick", function(_, button, down)
        if not down and button == "RightButton" then
            if sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        end
    end)
    lureBtn:SetScript("OnEnter", OnLureEnter)
    lureBtn:SetScript("OnLeave", OnLureLeave)
    f.lureBtn = lureBtn

    local skillText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -25)
    skillText:SetPoint("RIGHT", lureBtn, "LEFT", -4, 0)
    skillText:SetJustifyH("LEFT")
    skillText:SetWordWrap(false)
    f.skillText = skillText

    -- ── Header Row 3: Session Catches / Rate / Streak / Goal ETA ──────────────
    local sessionText = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sessionText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -41)
    sessionText:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -8, -41)
    sessionText:SetJustifyH("LEFT")
    sessionText:SetWordWrap(false)
    f.sessionText = sessionText

    -- ── Expanded Drawer: Zone Species Table ───────────────────────────────────
    local drawer = CreateFrame("Frame", nil, overlay)
    drawer:SetAllPoints(overlay)
    drawer:EnableMouse(false)
    f.drawer = drawer

    local divider = drawer:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", overlay, "TOPLEFT", 6, -57)
    divider:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -6, -57)
    divider:SetColorTexture(0.35, 0.35, 0.42, 0.6)
    f.divider = divider

    local colTotal = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    colTotal:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -6, -61)
    colTotal:SetWidth(34)
    colTotal:SetJustifyH("RIGHT")
    colTotal:SetText("total")
    f.colTotal = colTotal

    local colSess = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    colSess:SetPoint("RIGHT", colTotal, "LEFT", -4, 0)
    colSess:SetWidth(30)
    colSess:SetJustifyH("RIGHT")
    colSess:SetText("sess")
    f.colSess = colSess

    local colBag = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    colBag:SetPoint("RIGHT", colSess, "LEFT", -4, 0)
    colBag:SetWidth(42)
    colBag:SetJustifyH("RIGHT")
    colBag:SetText("bag")
    f.colBag = colBag

    local colSpecies = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    colSpecies:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -61)
    colSpecies:SetPoint("RIGHT", colBag, "LEFT", -4, 0)
    colSpecies:SetJustifyH("LEFT")
    colSpecies:SetWordWrap(false)
    colSpecies:SetText("zone species")
    f.colSpecies = colSpecies

    local speciesRows = {}
    for i = 1, MAX_HUD_ROWS do
        speciesRows[i] = CreateSpeciesRow(drawer, i)
    end
    f.speciesRows = speciesRows

    local footerText = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -(HEADER_HEIGHT + COL_HEADER_HEIGHT + (MAX_HUD_ROWS * ROW_HEIGHT) + 2))
    footerText:SetPoint("RIGHT", overlay, "RIGHT", -8, 0)
    footerText:SetJustifyH("LEFT")
    footerText:Hide()
    f.footerText = footerText

    local emptyText = drawer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -(HEADER_HEIGHT + COL_HEADER_HEIGHT + 2))
    emptyText:SetPoint("RIGHT", overlay, "RIGHT", -8, 0)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("|cff888888no recorded fish in this zone|r")
    emptyText:Hide()
    f.emptyText = emptyText

    f:Hide()

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(f, {
            key = "fishinghud",
            label = "fishing hud",
            preferredPoint = "TOP",
            customSize = function()
                local w = (hudFrame and hudFrame:GetWidth()) or HUD_WIDTH
                local h = (hudFrame and hudFrame:GetHeight()) or HEADER_HEIGHT
                return w, h
            end,
            getPoint = function()
                local p = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.hudPos
                local pt = (p and p.point) or "TOP"
                local relPt = (p and p.relPoint) or pt
                local x = (p and p.x) or 0
                local y = (p and p.y) or -120
                return pt, UIParent, relPt, x, y
            end,
            setPoint = function(point, _, relPoint, x, y)
                _G.SfuiDB = _G.SfuiDB or {}
                _G.SfuiDB.fishing = _G.SfuiDB.fishing or {}
                _G.SfuiDB.fishing.hudPos = { point = point, relPoint = relPoint or point, x = x, y = y }
                RestoreHudPosition()
            end,
            resetPosition = function()
                HUD.ResetPosition()
            end,
            isEnabled = function()
                return GetHudConfig().enabled == true
            end,
            onEnterEditMode = function(_, target)
                isHudLocked = false
                if target and not (InCombatLockdown and InCombatLockdown()) then
                    target:Show()
                    UpdateHud()
                end
            end,
            onExitEditMode = function()
                isHudLocked = true
                HUD.CheckVisibility()
            end,
        })
    end

    return f
end

-- ─── Dynamic HUD Update Loop ─────────────────────────────────────────────────

UpdateHeaderRightLayout = function()
    if not hudFrame then return end
    local cfg = GetHudConfig()

    SetTextIfChanged(hudFrame.collapseBtn.text, cfg.collapsed and "[+]" or "[-]", "_lastCollapseText")

    if cfg.collapsed then
        hudFrame.trophyBtn:Hide()
    else
        SetTextIfChanged(hudFrame.trophyBtn.text, cfg.hideTrophies and "|cff88ccff[main]|r" or "|cffffd100[all]|r", "_lastTrophyText")
        hudFrame.trophyBtn:Show()
    end

    local leftMostControl = hudFrame.trophyBtn:IsShown() and hudFrame.trophyBtn or hudFrame.collapseBtn

    if not (InCombatLockdown and InCombatLockdown()) and hudFrame.containerBtn:IsShown() then
        hudFrame.containerBtn:ClearAllPoints()
        hudFrame.containerBtn:SetPoint("RIGHT", leftMostControl, "LEFT", -3, 0)
        leftMostControl = hudFrame.containerBtn
    elseif hudFrame.containerBtn:IsShown() then
        leftMostControl = hudFrame.containerBtn
    end

    hudFrame.bagText:ClearAllPoints()
    hudFrame.bagText:SetPoint("RIGHT", leftMostControl, "LEFT", -4, 0)
end

local function UpdateZone()
    if not hudFrame or not hudFrame:IsShown() then return end
    local mapID = common.get_player_map_id()
    local zoneName = common.get_player_map_name() or (data.GetZoneName and data.GetZoneName(mapID)) or "zone"
    local subZone = (_G.GetSubZoneText and _G.GetSubZoneText()) or (_G.GetMinimapZoneText and _G.GetMinimapZoneText())
    local reqSkill, _, activeHabitat = data.ResolveSubZone(mapID, subZone)
    local _, _, _, totalSkill = sfui.fishing.GetFishingSkill()

    local habTag = ""
    if activeHabitat == "coastal" then
        habTag = " |cff44bbff[coast]|r"
    elseif activeHabitat == "inland" then
        habTag = " |cff66dd88[inland]|r"
    elseif activeHabitat == "oasis" then
        habTag = " |cffffcc44[oasis]|r"
    end

    local zoneStr
    if reqSkill then
        if totalSkill >= reqSkill then
            zoneStr = string_format("|cff00ff88%s|r (|cffffd100%d|r)%s", zoneName:lower(), reqSkill, habTag)
        else
            local deficit = reqSkill - totalSkill
            zoneStr = string_format("|cffff4444%s|r (|cffff8800-%d skill|r)%s", zoneName:lower(), deficit, habTag)
        end
    else
        zoneStr = string_format("|cffffffff%s|r%s", zoneName:lower(), habTag)
    end
    SetTextIfChanged(hudFrame.zoneText, zoneStr, "_lastZoneText")
end

local function UpdateBags()
    if not hudFrame or not hudFrame:IsShown() then return end
    local freeSlots = 0
    local numBags = _G.NUM_BAG_SLOTS or 4
    for b = 0, numBags do
        local free = (_G.C_Container and _G.C_Container.GetContainerNumFreeSlots and _G.C_Container.GetContainerNumFreeSlots(b))
            or (_G.GetContainerNumFreeSlots and _G.GetContainerNumFreeSlots(b)) or 0
        freeSlots = freeSlots + free
    end

    local bagStr = ""
    if freeSlots <= 2 then
        bagStr = string_format("|cffff2222bags: %d|r", freeSlots)
    elseif freeSlots <= 5 then
        bagStr = string_format("|cffffaa00bags: %d|r", freeSlots)
    end
    SetTextIfChanged(hudFrame.bagText, bagStr, "_lastBagText")
end

local function UpdateContainerButton()
    if not hudFrame or not hudFrame:IsShown() then return end
    local containerBtn = hudFrame.containerBtn
    if not containerBtn then return end
    if InCombatLockdown and InCombatLockdown() then
        QueueCombatUpdate()
        return
    end

    local container = data.FindOpenableContainerInBags and data.FindOpenableContainerInBags()
    if container and container.bag ~= nil and container.slot ~= nil then
        containerBtn._container = container
        containerBtn:SetAttribute("type", nil)
        containerBtn:SetAttribute("*type1", "item")
        containerBtn:SetAttribute("*item1", container.bag .. " " .. container.slot)
        containerBtn:SetAttribute("target-slot", nil)
        containerBtn.icon:SetTexture(container.icon or "Interface\\Icons\\INV_Box_01")
        containerBtn.countText:SetText((container.totalCount and container.totalCount > 1) and tostring(container.totalCount) or "")
        containerBtn:Show()
    else
        containerBtn._container = nil
        containerBtn:SetAttribute("type", nil)
        containerBtn:SetAttribute("*type1", nil)
        containerBtn:SetAttribute("*item1", nil)
        containerBtn:SetAttribute("target-slot", nil)
        containerBtn:Hide()
    end

    UpdateHeaderRightLayout()
end

local function UpdateSkill()
    if not hudFrame or not hudFrame:IsShown() then return end
    local rank, maxRank, mod = sfui.fishing.GetFishingSkill()
    local isCapped = (maxRank and maxRank > 0 and maxRank < 300 and rank >= maxRank)
    local rankPart = isCapped
        and string_format("|cffff4444%d/%d|r", rank, maxRank)
        or string_format("|cffffffff%d|r/|cffffffff%d|r", rank, maxRank)

    local modPart = (mod and mod > 0) and string_format(" (|cff00ffff+%d|r)", mod) or ""
    local progPart = ""

    if data.GetActiveMilestone then
        local playerLevel = _G.UnitLevel and _G.UnitLevel("player")
        local m, st = data.GetActiveMilestone(rank, maxRank, playerLevel)
        if m and st == "capped" then
            progPart = " |cffff4444[capped!]|r"
        elseif m and st == "available" then
            progPart = string_format(" |cffffaa00[train %d]|r", m.maxRank or 0)
        end
    end

    if progPart == "" and rank > 0 and rank < maxRank and rank < 300 and data.GetExpectedCatchesForSkillup then
        local expected = data.GetExpectedCatchesForSkillup(rank)
        local s = sfui.fishing.session
        local caughtSince = (s and s.catchesSinceSkillup) or 0
        if expected then
            progPart = string_format(" • |cff88ddff+1: %d/~%d|r", caughtSince, expected)
        end
    end

    SetTextIfChanged(hudFrame.skillText, string_format("skill: %s%s%s", rankPart, modPart, progPart), "_lastSkillText")
end

local function UpdateLure()
    if not hudFrame or not hudFrame:IsShown() then return end
    local lureBtn = hudFrame.lureBtn
    if not lureBtn then return end

    local hasLure, expSec = false, 0
    if sfui.buffs and sfui.buffs.scan and sfui.buffs.scan.GetSlotWeaponEnchant then
        hasLure, expSec = sfui.buffs.scan.GetSlotWeaponEnchant(16, "temporary")
    elseif _G.C_Item and _G.C_Item.GetWeaponEnchantInfo and _G.Enum and _G.Enum.WeaponSlot then
        local enchants = _G.C_Item.GetWeaponEnchantInfo(_G.Enum.WeaponSlot.MainHand)
        if _G.type(enchants) == "table" then
            local tempType = _G.Enum.ItemEnchantType and _G.Enum.ItemEnchantType.Temporary
            local imbueType = _G.Enum.ItemEnchantType and _G.Enum.ItemEnchantType.Imbue
            for _, ench in pairs(enchants) do
                if ench and ench.hasEnchant and ((tempType and ench.enchantType == tempType) or (not tempType and (not imbueType or ench.enchantType ~= imbueType))) then
                    hasLure = true
                    expSec = ench.timeLeft and (ench.timeLeft / 1000) or 0
                    break
                end
            end
        end
    elseif _G.GetWeaponEnchantInfo then
        local hasMH, expMH = _G.GetWeaponEnchantInfo()
        if hasMH then
            hasLure = true
            expSec = expMH and (expMH / 1000) or 0
        end
    end

    lureBtn._hasLure = hasLure and expSec > 0
    lureBtn._expSec = expSec

    local rank = sfui.fishing.GetFishingSkill()
    local bestLure = data.FindBestLureInBags and data.FindBestLureInBags(rank)
    local inCombat = InCombatLockdown and InCombatLockdown()
    local lureStr
    local iconTex = nil

    if hasLure and expSec > 60 then
        lureStr = string_format("lure: |cff00ff88%s|r", FormatDuration(expSec))
        if not inCombat then
            lureBtn:SetAttribute("type", nil)
            lureBtn:SetAttribute("*type1", nil)
            lureBtn:SetAttribute("*item1", nil)
            lureBtn:SetAttribute("target-slot", nil)
        else
            QueueCombatUpdate()
        end
    elseif bestLure and bestLure.itemID then
        iconTex = common.get_item_instant_info and select(5, common.get_item_instant_info(bestLure.itemID))
        if hasLure and expSec > 0 then
            lureStr = string_format("|cffff4444%s|r |cffffaa00[reapply]|r", FormatDuration(expSec))
        else
            lureStr = string_format("|cffffaa00apply +%d|r (|cff00ffff%d|r)", bestLure.bonus or 0, bestLure.count or 1)
        end
        if not inCombat then
            lureBtn:SetAttribute("type", nil)
            lureBtn:SetAttribute("*type1", "item")
            lureBtn:SetAttribute("*item1", "item:" .. bestLure.itemID)
            lureBtn:SetAttribute("target-slot", 16)
        else
            QueueCombatUpdate()
        end
    else
        if hasLure and expSec > 0 then
            lureStr = string_format("|cffff4444lure: %s|r", FormatDuration(expSec))
        else
            lureStr = "|cff888888no lure (0 bags)|r"
        end
        if not inCombat then
            lureBtn:SetAttribute("type", nil)
            lureBtn:SetAttribute("*type1", nil)
            lureBtn:SetAttribute("*item1", nil)
            lureBtn:SetAttribute("target-slot", nil)
        else
            QueueCombatUpdate()
        end
    end

    if iconTex then
        lureBtn.icon:SetTexture(iconTex)
        lureBtn.icon:Show()
    else
        lureBtn.icon:Hide()
    end

    SetTextIfChanged(lureBtn.text, lureStr, "_lastLureText")
    if lureBtn._isHovered then
        OnLureEnter(lureBtn)
    end
end

local function UpdateSession()
    if not hudFrame or not hudFrame:IsShown() then return end
    local s, _, fph = sfui.fishing.GetSessionMetrics()
    local sessionStr
    if s then
        local streakStr = (s.streak and s.streak > 1) and string_format(" • |cff00ff88%dx streak|r", s.streak) or ""
        local goalStr = ""
        if activeZoneGoal then
            local eta = activeZoneGoal.etaSec and FormatDurationEta(activeZoneGoal.etaSec) or nil
            if eta then
                goalStr = string_format(" • |cff80d8ffgoal eta: %s|r", eta)
            else
                goalStr = string_format(" • |cff80d8ffgoal: %d/%d|r", activeZoneGoal.bagCount or 0, activeZoneGoal.goal or 0)
            end
        end
        sessionStr = string_format("catches: |cffffffff%d|r (|cffffd100%d/hr|r)%s%s", s.catches or 0, fph, streakStr, goalStr)
    else
        sessionStr = "catches: |cffffffff0|r"
    end
    SetTextIfChanged(hudFrame.sessionText, sessionStr, "_lastSessionText")
end

UpdateSpeciesList = function()
    if not hudFrame or not hudFrame:IsShown() then return end

    local cfg = GetHudConfig()
    local mapID = common.get_player_map_id()
    local subZone = (_G.GetSubZoneText and _G.GetSubZoneText()) or (_G.GetMinimapZoneText and _G.GetMinimapZoneText())
    local _, _, activeHabitat, _, isMixed = data.ResolveSubZone(mapID, subZone)
    local session, elapsed, fph = sfui.fishing.GetSessionMetrics()
    local savedZone = _G.SfuiDB and _G.SfuiDB.fishing and _G.SfuiDB.fishing.zones and _G.SfuiDB.fishing.zones[mapID]
    local savedZoneFish = savedZone and savedZone.fish
    local sessFish = session and session.fish
    local sessZoneFish = session and session.zoneFish and session.zoneFish[mapID]

    local entries = {}
    local seen = {}
    local lootEntries = data.GetZoneLoot and data.GetZoneLoot(mapID)
    if lootEntries then
        for _, entry in ipairs(lootEntries) do
            local itemID = entry[1]
            if itemID and not seen[itemID] then
                seen[itemID] = true
                entries[#entries + 1] = {
                    itemID = itemID,
                    share = entry[2] or 0,
                    kind = entry[3] or "f",
                }
            end
        end
    end

    local function AppendDynamicCatchKeys(tbl)
        if type(tbl) ~= "table" then return end
        for rawID, cnt in pairs(tbl) do
            local itemID = tonumber(rawID)
            if itemID and (cnt or 0) > 0 and not seen[itemID] then
                seen[itemID] = true
                entries[#entries + 1] = {
                    itemID = itemID,
                    share = 0,
                    kind = "f",
                }
            end
        end
    end
    AppendDynamicCatchKeys(savedZoneFish)
    AppendDynamicCatchKeys(sessZoneFish)

    local knownCaughtKinds, totalFishKinds = 0, 0
    local rowsData = {}
    activeZoneGoal = nil

    for _, rawEntry in ipairs(entries) do
        local itemID = rawEntry.itemID
        local share = rawEntry.share or 0
        local kind = rawEntry.kind or "f"
        local sessionCount = (sessFish and sessFish[itemID]) or 0

        local zoneTotal = 0
        if sfui.fishing and sfui.fishing.GetZoneFishCharBreakdown then
            local _, zt = sfui.fishing.GetZoneFishCharBreakdown(mapID, itemID)
            zoneTotal = zt or 0
        elseif savedZoneFish then
            zoneTotal = tonumber(savedZoneFish[itemID]) or 0
        end

        local lifetimeTotal = 0
        if sfui.fishing and sfui.fishing.GetSpeciesCharBreakdown then
            local _, lt = sfui.fishing.GetSpeciesCharBreakdown(itemID)
            lifetimeTotal = lt or 0
        end
        local totalCount = math_max(lifetimeTotal, zoneTotal, sessionCount)
        local bagCount = GetBagCount(itemID)
        local goal = cfg.goals and tonumber(cfg.goals[itemID]) or nil
        if goal and goal <= 0 then goal = nil end

        if kind == "f" then
            totalFishKinds = totalFishKinds + 1
            if zoneTotal > 0 or sessionCount > 0 then
                knownCaughtKinds = knownCaughtKinds + 1
            end
        end

        local hideRow = false
        if cfg.hideTrophies and (kind == "t" or (share < 1.0 and kind ~= "q")) then
            if sessionCount == 0 and zoneTotal == 0 and not goal then
                hideRow = true
            end
        end

        if not hideRow then
            local spHab, habBadge = data.GetSpeciesHabitat(itemID, mapID)
            local biteState, biteBadge, biteDetail
            if data.GetSpeciesBiteWindow then
                biteState, biteBadge, biteDetail = data.GetSpeciesBiteWindow(itemID)
                if (itemID == 13755 or itemID == 13756) and biteState == "off" and sessionCount > 0 then
                    biteState = "active"
                end
            end

            local isDimmed = ((activeHabitat and spHab and spHab ~= activeHabitat) or (biteState == "off")) and true or false
            local etaSec = nil
            if goal and goal > bagCount then
                local rem = goal - bagCount
                local speciesFph = 0
                if sessionCount >= 3 and elapsed >= 180 then
                    speciesFph = sessionCount / (elapsed / 3600)
                elseif fph > 0 and share > 0 then
                    speciesFph = fph * (share / 100)
                end
                if speciesFph > 0.1 then
                    etaSec = (rem / speciesFph) * 3600
                end
            end

            rowsData[#rowsData + 1] = {
                itemID = itemID,
                share = share,
                kind = kind,
                habitat = spHab,
                habBadge = habBadge,
                activeHabitat = activeHabitat,
                isMixed = isMixed,
                biteState = biteState,
                biteBadge = biteBadge,
                biteDetail = biteDetail,
                isDimmed = isDimmed,
                sessionCount = sessionCount,
                zoneTotal = zoneTotal,
                totalCount = totalCount,
                bagCount = bagCount,
                goal = goal,
                etaSec = etaSec,
            }
        end
    end

    table_sort(rowsData, function(a, b)
        if a.isDimmed ~= b.isDimmed then
            return not a.isDimmed
        end
        if (a.share or 0) ~= (b.share or 0) then
            return (a.share or 0) > (b.share or 0)
        end
        if (a.sessionCount or 0) ~= (b.sessionCount or 0) then
            return (a.sessionCount or 0) > (b.sessionCount or 0)
        end
        if (a.totalCount or 0) ~= (b.totalCount or 0) then
            return (a.totalCount or 0) > (b.totalCount or 0)
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    for _, r in ipairs(rowsData) do
        if r.goal and r.goal > (r.bagCount or 0) then
            activeZoneGoal = {
                itemID = r.itemID,
                goal = r.goal,
                bagCount = r.bagCount or 0,
                etaSec = r.etaSec,
            }
            break
        end
    end

    if cfg.collapsed then
        hudFrame.drawer:Hide()
        for i = 1, MAX_HUD_ROWS do
            hudFrame.speciesRows[i]:Hide()
        end
        hudFrame.footerText:Hide()
        hudFrame.emptyText:Hide()
        ApplyHudSize(HEADER_HEIGHT)
        return
    end

    hudFrame.drawer:Show()
    SetTextIfChanged(hudFrame.colSpecies, string_format("zone species (%d/%d)", knownCaughtKinds, totalFishKinds), "_lastColSpecies")

    local totalRows = #rowsData
    if totalRows == 0 then
        for i = 1, MAX_HUD_ROWS do
            hudFrame.speciesRows[i]:Hide()
        end
        hudFrame.footerText:Hide()
        hudFrame.emptyText:Show()
        ApplyHudSize(HEADER_HEIGHT + COL_HEADER_HEIGHT + 18 + BOTTOM_PAD)
        return
    end

    hudFrame.emptyText:Hide()
    local showCount = (totalRows > MAX_HUD_ROWS) and MAX_HUD_ROWS or totalRows

    for i = 1, MAX_HUD_ROWS do
        local row = hudFrame.speciesRows[i]
        if i <= showCount then
            local rd = rowsData[i]
            row._rowData = rd

            local _, texture, lowerName, _, quality = data.GetSpeciesDisplay(rd.itemID, false)
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_Fish_02")
            if row.icon.SetDesaturated then
                row.icon:SetDesaturated(rd.isDimmed)
            end
            row.icon:SetAlpha(rd.isDimmed and 0.55 or 1.0)

            local nameStr = lowerName or ("item:" .. rd.itemID)
            if rd.isDimmed then
                nameStr = "|cff777777" .. nameStr .. "|r"
            elseif quality and quality >= 2 and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
                nameStr = _G.ITEM_QUALITY_COLORS[quality].hex .. nameStr .. "|r"
            end

            local shareStr = ""
            if rd.share and rd.share >= 1 then
                shareStr = string_format(" |cff999999%.0f%%|r", rd.share)
            elseif rd.share and rd.share > 0 then
                shareStr = string_format(" |cff777777%.1f%%|r", rd.share)
            end

            local tagSuffix = ""
            if rd.habBadge and ((rd.isMixed and not rd.activeHabitat) or (rd.activeHabitat and rd.habitat and rd.habitat ~= rd.activeHabitat)) then
                tagSuffix = " " .. rd.habBadge
            end
            if rd.biteBadge then
                tagSuffix = tagSuffix .. " " .. rd.biteBadge
            end

            row.nameText:SetText(nameStr .. shareStr .. tagSuffix)

            if rd.goal and rd.goal > 0 then
                if (rd.bagCount or 0) >= rd.goal then
                    row.bagText:SetText(string_format("|cff00ff88%d/%d|r", rd.bagCount or 0, rd.goal))
                else
                    row.bagText:SetText(string_format("|cff80d8ff%d/%d|r", rd.bagCount or 0, rd.goal))
                end
            elseif (rd.bagCount or 0) > 0 then
                row.bagText:SetText(string_format("|cffcccccc%d|r", rd.bagCount))
            else
                row.bagText:SetText("|cff5555550|r")
            end

            if (rd.sessionCount or 0) > 0 then
                row.sessText:SetText(string_format("|cffffffff%d|r", rd.sessionCount))
            else
                row.sessText:SetText("|cff5555550|r")
            end

            if (rd.totalCount or 0) > 0 then
                row.totalText:SetText(string_format("|cffffd100%d|r", rd.totalCount))
            else
                row.totalText:SetText("|cff5555550|r")
            end

            row:Show()
            if row:IsMouseOver() then
                OnRowEnter(row)
            end
        else
            row._rowData = nil
            row:Hide()
        end
    end

    local extraFooter = 0
    if totalRows > MAX_HUD_ROWS then
        extraFooter = 16
        hudFrame.footerText:SetText(string_format("|cff888888+%d more in atlas (right-click)|r", totalRows - MAX_HUD_ROWS))
        hudFrame.footerText:Show()
    else
        hudFrame.footerText:Hide()
    end

    ApplyHudSize(HEADER_HEIGHT + COL_HEADER_HEIGHT + (showCount * ROW_HEIGHT) + extraFooter + BOTTOM_PAD)
end

local bagsDirty = false

UpdateHud = function()
    if not hudFrame or not hudFrame:IsShown() then return end
    if bagsDirty then
        bagsDirty = false
        RefreshBagCountsAndGoals()
    end
    UpdateHeaderRightLayout()
    UpdateZone()
    UpdateBags()
    UpdateContainerButton()
    UpdateSkill()
    UpdateLure()
    UpdateSpeciesList()
    UpdateSession()
end
HUD.Update = UpdateHud

-- ─── Visibility & Public Controls ────────────────────────────────────────────

local function CheckVisibility()
    if not hudFrame then
        CreateHudFrame()
    end
    local isPole = sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped()
    local isEditMode = sfui.movers and sfui.movers.isUnlocked
    local enabled = GetHudConfig().enabled == true
    local shouldShow = (isPole or isEditMode) and enabled

    if InCombatLockdown and InCombatLockdown() then
        QueueCombatUpdate()
        if hudFrame then
            hudFrame:SetAlpha(shouldShow and 1 or 0)
        end
        return
    end

    if hudFrame then
        hudFrame:SetAlpha(1)
    end
    if shouldShow then
        if hudFrame and not hudFrame:IsShown() then
            hudFrame:Show()
        end
        UpdateHud()
    else
        if hudFrame and hudFrame:IsShown() then
            hudFrame:Hide()
        end
    end
end
HUD.CheckVisibility = CheckVisibility

function HUD.ToggleLock()
    isHudLocked = not isHudLocked
    if hudFrame and not (InCombatLockdown and InCombatLockdown()) then
        hudFrame:SetMovable(true)
    end
    return isHudLocked
end

function HUD.IsLocked()
    return isHudLocked == true
end

function HUD.ToggleCollapse()
    local cfg = GetHudConfig()
    cfg.collapsed = not cfg.collapsed
    UpdateHud()
    return cfg.collapsed
end

function HUD.IsCollapsed()
    return GetHudConfig().collapsed == true
end

function HUD.GetFrame()
    return hudFrame
end

function HUD.ResetPosition()
    _G.SfuiDB = _G.SfuiDB or {}
    _G.SfuiDB.fishing = _G.SfuiDB.fishing or {}
    _G.SfuiDB.fishing.hudPos = { point = "TOP", relPoint = "TOP", x = 0, y = -120 }
    RestoreHudPosition()
end

-- ─── Dispatcher Event Wiring ─────────────────────────────────────────────────

local function OnPlayerLogin()
    RefreshBagCountsAndGoals()
    CheckVisibility()
end

local function OnPoleEquipChanged(_, slot)
    if slot == 16 or not slot then
        CheckVisibility()
        if hudFrame and hudFrame:IsShown() then
            UpdateSkill()
            UpdateLure()
        end
    end
end

local function OnLeaveCombat()
    if pendingCombatUpdate then
        pendingCombatUpdate = false
        CheckVisibility()
        if hudFrame and hudFrame:IsShown() then
            UpdateHud()
        end
    end
end

QueueCombatUpdate = function()
    pendingCombatUpdate = true
    if InCombatLockdown and InCombatLockdown() and sfui.safety and sfui.safety.DeferOutOfCombat then
        sfui.safety.DeferOutOfCombat("fishing_hud_combat", sfui.safety.OOC_P1, OnLeaveCombat)
    end
end

local function OnZoneChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateZone()
        UpdateSpeciesList()
        UpdateSession()
    end
end

local function OnBagsChanged()
    if not hudFrame or not hudFrame:IsShown() then
        bagsDirty = true
        return
    end
    bagsDirty = false
    RefreshBagCountsAndGoals()
    UpdateBags()
    UpdateContainerButton()
    UpdateLure()
    UpdateSpeciesList()
    UpdateSession()
end

local function OnSkillChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateSkill()
        UpdateZone()
        UpdateLure()
    end
end

local function OnSessionEvent()
    RefreshBagCountsAndGoals()
    if hudFrame and hudFrame:IsShown() then
        UpdateSkill()
        UpdateSpeciesList()
        UpdateSession()
    end
end

local function OnItemInfoReceived()
    if not hudFrame or not hudFrame:IsShown() then return end
    if common and common.debounce then
        common.debounce("fishing_hud_item_info", 0.25, UpdateSpeciesList)
    else
        UpdateSpeciesList()
    end
end

local function OnContainerLootReady()
    if GetTime() > openingContainerUntil then return end
    if _G.IsFishingLoot and _G.IsFishingLoot() then return end
    if _G.SfuiDB and _G.SfuiDB.fishingAutoLoot == false then return end
    local num = (_G.GetNumLootItems and _G.GetNumLootItems()) or 0
    if num > 0 and _G.LootSlot then
        for i = num, 1, -1 do
            _G.LootSlot(i)
        end
    end
end

local function OnLootClosed()
    openingContainerUntil = 0
end

OnHudTick = function()
    if not hudFrame or not hudFrame:IsShown() then return end
    UpdateLure()
    UpdateSession()
    local now = GetTime()
    if (now - lastListTickTime) >= 15 then
        lastListTickTime = now
        UpdateSpeciesList()
        UpdateSession()
    end
end

events.RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)
events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnPoleEquipChanged)
events.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneChanged)
events.RegisterEvent("ZONE_CHANGED", OnZoneChanged)
events.RegisterEvent("ZONE_CHANGED_INDOORS", OnZoneChanged)
events.RegisterEvent("BAG_UPDATE_DELAYED", OnBagsChanged)
events.RegisterEvent("SKILL_LINES_CHANGED", OnSkillChanged)
events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemInfoReceived)
events.RegisterEvent("LOOT_READY", OnContainerLootReady)
events.RegisterEvent("LOOT_OPENED", OnContainerLootReady)
events.RegisterEvent("LOOT_CLOSED", OnLootClosed)

events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", OnSessionEvent)
events.RegisterMessage("SFUI_FISHING_GETAWAY_RECORDED", OnSessionEvent)
events.RegisterMessage("SFUI_FISHING_SESSION_RESET", OnSessionEvent)
events.RegisterMessage("SFUI_FISHING_SKILLUP", OnSkillChanged)
events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", UpdateSpeciesList)
