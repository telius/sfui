local addonName, addon = ...
sfui = sfui or {}
sfui.fishing = sfui.fishing or {}
sfui.fishing.hud = sfui.fishing.hud or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/fishing/fishing_hud.lua
--  Lightweight Floating Fishing Status Pill (Camelot & Classic Forever)
--
--  Automatically fades in when a fishing pole is equipped in main hand.
--  Displays zone skill requirement & difficulty, active lure countdown,
--  session catches & rate (fish/hr), bag space warning, and a rich
--  hover tooltip with local species drop rates and caught status.
-- ══════════════════════════════════════════════════════════════════════════════

local HUD = sfui.fishing.hud
local common = sfui.common
local theme = sfui.theme
local events = sfui.events
local data = sfui.fishing_data

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GetTime = _G.GetTime
local IsAltKeyDown = _G.IsAltKeyDown
local InCombatLockdown = _G.InCombatLockdown
local math_floor = _G.math.floor
local string_format = _G.string.format
local tostring = _G.tostring

local hudFrame = nil
local isHudLocked = true
local lastUpdate = 0
local UpdateHud
local OnHudTick

-- ─── Formatting Helpers ──────────────────────────────────────────────────────

local function FormatDuration(seconds)
    if not seconds or seconds <= 0 then return "0s" end
    if common.format_timer_clock then
        return common.format_timer_clock(seconds, false, "s")
    end
    local m, s = math_floor(seconds / 60), math_floor(seconds % 60)
    return (m > 0) and string_format("%d:%02d", m, s) or string_format("%ds", s)
end

-- ─── Tooltip Construction ────────────────────────────────────────────────────

local function OnHudEnter(self)
    local tip = common.get_tooltip()
    if not tip then return end

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

    -- Local Zone Species Breakdown
    local lootEntries, isClassic = data.GetZoneLoot(mapID)
    if lootEntries and #lootEntries > 0 then
        tip:AddLine(" ")
        tip:AddLine("zone species (drop rates):", 0, 1, 1)

        local savedZones = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.zones
        local zoneStats = savedZones and savedZones[mapID]
        local caughtCounts = zoneStats and zoneStats.fish or {}

        local knownCaught = 0
        local totalKinds = 0

        for _, entry in ipairs(lootEntries) do
            local itemID = entry[1]
            local share = entry[2]
            local kind = entry[3]
            if kind == "f" then totalKinds = totalKinds + 1 end

            local count = caughtCounts[itemID] or 0
            if count > 0 and kind == "f" then knownCaught = knownCaught + 1 end

            local displayLink = data.GetSpeciesDisplay(itemID, true)
            local spHab, habBadge = data.GetSpeciesHabitat(itemID, mapID)
            local badgeSuffix = habBadge and (" " .. habBadge) or ""
            local rightText = string_format("%.1f%%  (caught: %d)", share or 0, count)
            local r, g, b = (count > 0) and 0.2 or 0.7, (count > 0) and 1 or 0.7, (count > 0) and 0.4 or 0.7
            local lr, lg, lb = 1, 1, 1
            if activeHabitat and spHab and spHab ~= activeHabitat then
                lr, lg, lb = 0.55, 0.55, 0.55
            end
            tip:AddDoubleLine("  " .. displayLink .. badgeSuffix, rightText, lr, lg, lb, r, g, b)
        end

        tip:AddDoubleLine("species caught here:", string_format("%d / %d kinds", knownCaught, totalKinds), 0.6, 0.8, 1, 1, 1, 1)
    else
        tip:AddLine(" ")
        tip:AddLine("no recorded fish list for this zone.", 0.6, 0.6, 0.6)
    end

    -- Session Metrics
    local session = sfui.fishing.session
    if session then
        tip:AddLine(" ")
        tip:AddLine("current session:", 0.9, 0.82, 0.5)
        tip:AddDoubleLine("catches / casts:", string_format("%d / %d", session.catches or 0, session.casts or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine("getaways:", string_format("%d", session.getaways or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        tip:AddDoubleLine("current streak:", string_format("%d in a row", session.streak or 0), 0.8, 0.8, 0.8, 0.2, 1, 0.4)
    end

    tip:AddLine(" ")
    tip:AddLine("|cff888888right-click for fishing atlas • alt+drag to move|r", 0.5, 0.5, 0.5)
    tip:Show()
end

local function OnHudLeave(self)
    common.hide_tooltip()
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────

local function RestoreHudPosition()
    if not hudFrame then return end
    local pos = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hudPos
    hudFrame:ClearAllPoints()
    if pos and pos.point then
        hudFrame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or -120)
    else
        hudFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function CreateHudFrame()
    if hudFrame then return hudFrame end

    local f = CreateFrame("Button", "SfuiFishingHud", UIParent, "BackdropTemplate")
    f:SetSize(220, 52)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    hudFrame = f
    RestoreHudPosition()

    -- Dragging logic (unlocked via /sffish lock, sfui edit mode movers, or holding alt like lootfeed)
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        if not isHudLocked or (IsAltKeyDown and IsAltKeyDown()) or (sfui.movers and sfui.movers.isUnlocked) then
            self:StartMoving()
            self._isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if not self._isMoving then return end
        self:StopMovingOrSizing()
        self._isMoving = false
        local point, _, relPoint, x, y = self:GetPoint()
        if point then
            local rx = math_floor((x or 0) + 0.5)
            local ry = math_floor((y or 0) + 0.5)
            SfuiDB = SfuiDB or {}
            SfuiDB.fishing = SfuiDB.fishing or {}
            SfuiDB.fishing.hudPos = { point = point, relPoint = relPoint or point, x = rx, y = ry }
            local mover = sfui.movers and sfui.movers.list and sfui.movers.list["fishinghud"]
            if mover then
                mover:ClearAllPoints()
                mover:SetPoint(point, UIParent, relPoint or point, rx, ry)
            end
        end
    end)

    f:SetScript("OnEnter", OnHudEnter)
    f:SetScript("OnLeave", OnHudLeave)
    f:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        end
    end)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Dedicated elevated overlay frame so text always renders above theme borderFrames/backdrops
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    overlay:EnableMouse(false)
    f.overlayFrame = overlay

    -- Apply native theme styling
    local function ApplyHudTheme(frame)
        if not (theme and theme.RegisterWindow) then
            common.apply_flat_backdrop(frame, { 0.08, 0.08, 0.10, 0.90 }, { 0.25, 0.25, 0.30, 0.85 })
        end
        if frame.overlayFrame then
            frame.overlayFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
        end
    end
    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, ApplyHudTheme)
    else
        ApplyHudTheme(f)
    end

    -- Lifecycle-managed update ticker (only runs when HUD is visible)
    f:HookScript("OnShow", function()
        if f.overlayFrame then
            f.overlayFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
        end
        events.RegisterUpdate("sfui_fishing_hud", 0.5, OnHudTick)
    end)
    f:HookScript("OnHide", function()
        events.UnregisterUpdate("sfui_fishing_hud")
    end)

    -- Top Row: Zone label (left) & Bag warning (right)
    local zoneText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("TOPLEFT", overlay, "TOPLEFT", 8, -6)
    zoneText:SetPoint("RIGHT", overlay, "RIGHT", -60, 0)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetWordWrap(false)
    f.zoneText = zoneText

    local bagText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagText:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -8, -6)
    bagText:SetJustifyH("RIGHT")
    f.bagText = bagText

    -- Middle Row: Fishing skill rank & lure status
    local skillText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillText:SetPoint("LEFT", overlay, "LEFT", 8, 2)
    skillText:SetJustifyH("LEFT")
    f.skillText = skillText

    local lureText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureText:SetPoint("RIGHT", overlay, "RIGHT", -8, 2)
    lureText:SetJustifyH("RIGHT")
    f.lureText = lureText

    -- Bottom Row: Session stats (catches, fish/hr, streak)
    local sessionText = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sessionText:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 8, 6)
    sessionText:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -8, 6)
    sessionText:SetJustifyH("LEFT")
    sessionText:SetWordWrap(false)
    f.sessionText = sessionText

    f:Hide()
    hudFrame = f

    -- Register with SFUI Edit Mode (Movers)
    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(f, {
            key = "fishinghud",
            label = "fishing hud",
            preferredPoint = "TOP",
            customSize = { 220, 52 },
            getPoint = function()
                local p = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hudPos
                local pt = (p and p.point) or "TOP"
                local relPt = (p and p.relPoint) or pt
                local x = (p and p.x) or 0
                local y = (p and p.y) or -120
                return pt, UIParent, relPt, x, y
            end,
            setPoint = function(point, relTo, relPoint, x, y)
                SfuiDB = SfuiDB or {}
                SfuiDB.fishing = SfuiDB.fishing or {}
                SfuiDB.fishing.hudPos = { point = point, relPoint = relPoint or point, x = x, y = y }
                RestoreHudPosition()
            end,
            resetPosition = function()
                HUD.ResetPosition()
            end,
            isEnabled = function()
                if SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hud and SfuiDB.fishing.hud.enabled ~= nil then
                    return SfuiDB.fishing.hud.enabled
                end
                return true
            end,
            onEnterEditMode = function(mover, target)
                isHudLocked = false
                if target then
                    target:Show()
                    UpdateHud()
                end
            end,
            onExitEditMode = function(mover, target)
                isHudLocked = true
                HUD.CheckVisibility()
            end,
        })
    end

    return f
end

-- ─── Dynamic HUD Update Loop ─────────────────────────────────────────────────

local function SetTextIfChanged(fs, text, fieldKey)
    if hudFrame and hudFrame[fieldKey] ~= text then
        hudFrame[fieldKey] = text
        fs:SetText(text)
    end
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

local function UpdateSkill()
    if not hudFrame or not hudFrame:IsShown() then return end
    local rank, maxRank, mod = sfui.fishing.GetFishingSkill()
    local isCapped = (maxRank and maxRank > 0 and maxRank < 300 and rank >= maxRank)
    local rankPart = isCapped
        and string_format("|cffff4444%d/%d|r", rank, maxRank)
        or string_format("|cffffffff%d|r/|cffffffff%d|r", rank, maxRank)
    local skillStr
    if mod and mod > 0 then
        skillStr = string_format("skill: %s (|cff00ffff+%d|r)", rankPart, mod)
    else
        skillStr = string_format("skill: %s", rankPart)
    end
    SetTextIfChanged(hudFrame.skillText, skillStr, "_lastSkillText")
end

local function UpdateLure()
    if not hudFrame or not hudFrame:IsShown() then return end

    -- Query active weapon enchant on main hand for lure
    local hasLure, expSec = false, 0
    if sfui.buffs and sfui.buffs.scan and sfui.buffs.scan.GetSlotWeaponEnchant then
        hasLure, expSec = sfui.buffs.scan.GetSlotWeaponEnchant(16)
    elseif _G.GetWeaponEnchantInfo then
        local hasMH, expMH = _G.GetWeaponEnchantInfo()
        if hasMH then
            hasLure = true
            expSec = expMH and (expMH / 1000) or 0
        end
    end

    local lureStr
    if hasLure and expSec > 0 then
        if expSec <= 60 then
            lureStr = string_format("|cffff4444lure: %s|r", FormatDuration(expSec))
        else
            lureStr = string_format("lure: |cff00ff88%s|r", FormatDuration(expSec))
        end
    else
        local rank = sfui.fishing.GetFishingSkill()
        local bestLure = data.FindBestLureInBags(rank)
        local bagLureCount = bestLure and bestLure.count or 0
        if bagLureCount > 0 then
            lureStr = string_format("|cffffaa00no lure|r (|cff00ffff%d in bags|r)", bagLureCount)
        else
            lureStr = "|cff888888no lure (0 bags)|r"
        end
    end
    SetTextIfChanged(hudFrame.lureText, lureStr, "_lastLureText")
end

local function UpdateSession()
    if not hudFrame or not hudFrame:IsShown() then return end
    local s, _, fph = sfui.fishing.GetSessionMetrics()
    local sessionStr
    if s then
        local streakStr = (s.streak and s.streak > 1) and string_format(" • |cff00ff88%dx streak|r", s.streak) or ""
        sessionStr = string_format("catches: |cffffffff%d|r (|cffffd100%d/hr|r)%s", s.catches or 0, fph, streakStr)
    else
        sessionStr = "catches: |cffffffff0|r"
    end
    SetTextIfChanged(hudFrame.sessionText, sessionStr, "_lastSessionText")
end

UpdateHud = function()
    if not hudFrame or not hudFrame:IsShown() then return end
    UpdateZone()
    UpdateBags()
    UpdateSkill()
    UpdateLure()
    UpdateSession()
end
HUD.Update = UpdateHud

-- ─── Visibility Management ───────────────────────────────────────────────────

local function CheckVisibility()
    if not hudFrame then
        CreateHudFrame()
    end
    local isPole = sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped()
    local isEditMode = sfui.movers and sfui.movers.isUnlocked
    local enabled = true
    if SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hud and SfuiDB.fishing.hud.enabled ~= nil then
        enabled = SfuiDB.fishing.hud.enabled
    end

    if (isPole or isEditMode) and enabled then
        if hudFrame and not hudFrame:IsShown() then
            hudFrame:Show()
            UpdateHud()
        end
    else
        if hudFrame and hudFrame:IsShown() then
            hudFrame:Hide()
        end
    end
end
HUD.CheckVisibility = CheckVisibility

function HUD.ToggleLock()
    isHudLocked = not isHudLocked
    if hudFrame then
        hudFrame:SetMovable(true)
    end
    return isHudLocked
end

function HUD.IsLocked()
    return isHudLocked == true
end

function HUD.GetFrame()
    return hudFrame
end

function HUD.ResetPosition()
    if hudFrame then
        hudFrame:ClearAllPoints()
        hudFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
        SfuiDB = SfuiDB or {}
        SfuiDB.fishing = SfuiDB.fishing or {}
        SfuiDB.fishing.hudPos = { point = "TOP", relPoint = "TOP", x = 0, y = -120 }
    end
end

-- ─── Dispatcher Event Wiring ─────────────────────────────────────────────────

local function OnPoleEquipChanged(event, slot)
    if slot == 16 or not slot then
        CheckVisibility()
        if hudFrame and hudFrame:IsShown() then
            UpdateSkill()
            UpdateLure()
        end
    end
end

local function OnZoneChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateZone()
    end
end

local function OnBagsChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateBags()
        UpdateLure()
    end
end

local function OnSkillChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateSkill()
        UpdateZone()
        UpdateLure()
    end
end

local function OnSessionEvent()
    if hudFrame and hudFrame:IsShown() then
        UpdateSession()
    end
end

OnHudTick = function()
    if hudFrame and hudFrame:IsShown() then
        UpdateLure()
        UpdateSession()
    end
end

events.RegisterEvent("PLAYER_LOGIN", CheckVisibility)
events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnPoleEquipChanged)
events.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneChanged)
events.RegisterEvent("ZONE_CHANGED", OnZoneChanged)
events.RegisterEvent("ZONE_CHANGED_INDOORS", OnZoneChanged)
events.RegisterEvent("BAG_UPDATE_DELAYED", OnBagsChanged)
events.RegisterEvent("SKILL_LINES_CHANGED", OnSkillChanged)

-- Internal pub/sub message listeners for instant HUD refreshes
events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", OnSessionEvent)
events.RegisterMessage("SFUI_FISHING_GETAWAY_RECORDED", OnSessionEvent)
events.RegisterMessage("SFUI_FISHING_SESSION_RESET", OnSessionEvent)
