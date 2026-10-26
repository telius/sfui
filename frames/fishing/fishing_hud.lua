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
    if seconds >= 60 then
        local m = math_floor(seconds / 60)
        local s = math_floor(seconds % 60)
        return string_format("%d:%02d", m, s)
    else
        return string_format("%ds", math_floor(seconds))
    end
end

-- ─── Tooltip Construction ────────────────────────────────────────────────────

local function OnHudEnter(self)
    local tip = common.get_tooltip()
    if not tip then return end

    tip:SetOwner(self, "ANCHOR_TOP", 0, 8)
    tip:ClearLines()

    local mapID = common.get_player_map_id()
    local zoneName = common.get_player_map_name() or "current zone"
    local reqSkill, subArea = data.GetZoneRequirement(mapID)
    local rank, maxRank, mod, totalSkill = sfui.fishing.GetFishingSkill()

    tip:AddLine(zoneName:lower(), 1, 0.82, 0)

    if reqSkill then
        local statusColor = (totalSkill >= reqSkill) and "|cff00ff880% getaways|r" or "|cffff4444fish can escape|r"
        tip:AddDoubleLine("required skill:", string_format("%d (%s)", reqSkill, statusColor), 0.8, 0.8, 0.8, 1, 1, 1)
        if subArea then
            tip:AddDoubleLine("sub-area requirement:", string_format("%s (|cffffd100%d|r)", subArea.area, subArea.skill), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    else
        tip:AddDoubleLine("required skill:", "|cff888888unknown|r", 0.8, 0.8, 0.8, 1, 1, 1)
    end

    tip:AddDoubleLine("your fishing skill:", string_format("%d / %d (|cff00ffff+%d bonus|r = %d)", rank, maxRank, mod, totalSkill), 0.8, 0.8, 0.8, 1, 1, 1)

    -- Local Zone Species Breakdown
    local lootEntries, isClassic = data.GetZoneLoot(mapID)
    if lootEntries and #lootEntries > 0 then
        tip:AddLine(" ")
        tip:AddLine("zone species (cmangos drop rates):", 0, 1, 1)

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

            local itemName, itemLink = common.get_item_info(itemID)
            local count = caughtCounts[itemID] or 0
            if count > 0 and kind == "f" then knownCaught = knownCaught + 1 end

            local displayLink = itemLink or itemName or ("item:" .. itemID)
            local rightText = string_format("%.1f%%  (caught: %d)", share or 0, count)
            local r, g, b = (count > 0) and 0.2 or 0.7, (count > 0) and 1 or 0.7, (count > 0) and 0.4 or 0.7
            tip:AddDoubleLine("  " .. displayLink:lower(), rightText, 1, 1, 1, r, g, b)
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
        if session.value and session.value > 0 then
            tip:AddDoubleLine("vendor value:", common.format_money(session.value), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end

    tip:AddLine(" ")
    tip:AddLine("|cff888888click /sffish atlas for the complete fishing journal|r", 0.5, 0.5, 0.5)
    tip:Show()
end

local function OnHudLeave(self)
    common.hide_tooltip()
end

-- ─── Frame Creation ──────────────────────────────────────────────────────────

local function CreateHudFrame()
    if hudFrame then return hudFrame end

    local f = CreateFrame("Button", "SfuiFishingHud", UIParent, "BackdropTemplate")
    f:SetSize(220, 52)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Restore saved position or default to top-center
    local pos = SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hudPos
    if pos and pos.point then
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or -120)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end

    -- Dragging logic
    f:SetScript("OnDragStart", function(self)
        if not isHudLocked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        SfuiDB = SfuiDB or {}
        SfuiDB.fishing = SfuiDB.fishing or {}
        SfuiDB.fishing.hudPos = { point = point, relPoint = relPoint, x = math_floor(x + 0.5), y = math_floor(y + 0.5) }
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

    -- Apply native theme styling
    local function ApplyHudTheme(frame, pal)
        if theme and theme.ApplyContainerStyle then
            theme.ApplyContainerStyle(frame)
        else
            common.apply_flat_backdrop(frame, { 0.08, 0.08, 0.10, 0.90 }, { 0.25, 0.25, 0.30, 0.85 })
        end
    end
    ApplyHudTheme(f)
    if theme and theme.RegisterWindow then
        theme.RegisterWindow(f, ApplyHudTheme)
    end

    -- Lifecycle-managed update ticker (only runs when HUD is visible)
    f:HookScript("OnShow", function()
        events.RegisterUpdate("sfui_fishing_hud", 0.5, OnHudTick)
    end)
    f:HookScript("OnHide", function()
        events.UnregisterUpdate("sfui_fishing_hud")
    end)

    -- Top Row: Zone label (left) & Bag warning (right)
    local zoneText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    zoneText:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
    zoneText:SetPoint("RIGHT", f, "RIGHT", -60, 0)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetWordWrap(false)
    f.zoneText = zoneText

    local bagText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
    bagText:SetJustifyH("RIGHT")
    f.bagText = bagText

    -- Middle Row: Fishing skill rank & lure status
    local skillText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    skillText:SetPoint("LEFT", f, "LEFT", 8, 2)
    skillText:SetJustifyH("LEFT")
    f.skillText = skillText

    local lureText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureText:SetPoint("RIGHT", f, "RIGHT", -8, 2)
    lureText:SetJustifyH("RIGHT")
    f.lureText = lureText

    -- Bottom Row: Session stats (catches, fish/hr, streak)
    local sessionText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sessionText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
    sessionText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 6)
    sessionText:SetJustifyH("LEFT")
    sessionText:SetWordWrap(false)
    f.sessionText = sessionText

    f:Hide()
    hudFrame = f
    return f
end

-- ─── Dynamic HUD Update Loop ─────────────────────────────────────────────────

UpdateHud = function()
    if not hudFrame or not hudFrame:IsShown() then return end

    local mapID = common.get_player_map_id()
    local zoneName = common.get_player_map_name() or "zone"
    local reqSkill = data.GetZoneRequirement(mapID)
    local rank, maxRank, mod, totalSkill = sfui.fishing.GetFishingSkill()

    -- 1. Zone Text & Skill Feasibility
    if reqSkill then
        if totalSkill >= reqSkill then
            hudFrame.zoneText:SetText(string_format("|cff00ff88%s|r (|cffffd100%d|r)", zoneName:lower(), reqSkill))
        else
            local deficit = reqSkill - totalSkill
            hudFrame.zoneText:SetText(string_format("|cffff4444%s|r (|cffff8800-%d skill|r)", zoneName:lower(), deficit))
        end
    else
        hudFrame.zoneText:SetText(string_format("|cffffffff%s|r", zoneName:lower()))
    end

    -- 2. Bag Capacity Warning
    local freeSlots = 0
    local numBags = _G.NUM_BAG_SLOTS or 4
    for b = 0, numBags do
        local free = (_G.C_Container and _G.C_Container.GetContainerNumFreeSlots and _G.C_Container.GetContainerNumFreeSlots(b))
            or (_G.GetContainerNumFreeSlots and _G.GetContainerNumFreeSlots(b)) or 0
        freeSlots = freeSlots + free
    end
    if freeSlots <= 2 then
        hudFrame.bagText:SetText(string_format("|cffff2222bags: %d|r", freeSlots))
    elseif freeSlots <= 5 then
        hudFrame.bagText:SetText(string_format("|cffffaa00bags: %d|r", freeSlots))
    else
        hudFrame.bagText:SetText("")
    end

    -- 3. Skill & Lure Row
    local skillStr
    if mod and mod > 0 then
        skillStr = string_format("skill: |cffffffff%d|r/|cffffffff%d|r (|cff00ffff+%d|r)", rank, maxRank, mod)
    else
        skillStr = string_format("skill: |cffffffff%d|r/|cffffffff%d|r", rank, maxRank)
    end
    hudFrame.skillText:SetText(skillStr)

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

    local bestLure = data.FindBestLureInBags(rank)
    local bagLureCount = bestLure and bestLure.count or 0

    if hasLure and expSec > 0 then
        if expSec <= 60 then
            hudFrame.lureText:SetText(string_format("|cffff4444lure: %s|r", FormatDuration(expSec)))
        else
            hudFrame.lureText:SetText(string_format("lure: |cff00ff88%s|r", FormatDuration(expSec)))
        end
    else
        if bagLureCount > 0 then
            hudFrame.lureText:SetText(string_format("|cffffaa00no lure|r (|cff00ffff%d in bags|r)", bagLureCount))
        else
            hudFrame.lureText:SetText("|cff888888no lure (0 bags)|r")
        end
    end

    -- 4. Session Metrics
    local s = sfui.fishing.session
    if s then
        local elapsed = GetTime() - (s.startTime or GetTime())
        local fph = (elapsed >= 60 and s.catches and s.catches > 0)
            and math_floor((s.catches / (elapsed / 3600)) + 0.5)
            or 0
        local streakStr = (s.streak and s.streak > 1) and string_format(" • |cff00ff88%dx streak|r", s.streak) or ""
        hudFrame.sessionText:SetText(string_format("catches: |cffffffff%d|r (|cffffd100%d/hr|r)%s", s.catches or 0, fph, streakStr))
    else
        hudFrame.sessionText:SetText("catches: |cffffffff0|r")
    end
end
HUD.Update = UpdateHud

-- ─── Visibility Management ───────────────────────────────────────────────────

local function CheckVisibility()
    local isPole = sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped()
    local enabled = true
    if SfuiDB and SfuiDB.fishing and SfuiDB.fishing.hud and SfuiDB.fishing.hud.enabled ~= nil then
        enabled = SfuiDB.fishing.hud.enabled
    end

    if isPole and enabled then
        if not hudFrame then
            CreateHudFrame()
        end
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
        hudFrame:SetMovable(not isHudLocked)
    end
    return isHudLocked
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
    end
end

local function OnZoneChanged()
    if hudFrame and hudFrame:IsShown() then
        UpdateHud()
    end
end

OnHudTick = function()
    if hudFrame and hudFrame:IsShown() then
        UpdateHud()
    end
end

events.RegisterEvent("PLAYER_LOGIN", CheckVisibility)
events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", OnPoleEquipChanged)
events.RegisterEvent("ZONE_CHANGED_NEW_AREA", OnZoneChanged)
events.RegisterEvent("ZONE_CHANGED", OnZoneChanged)
events.RegisterEvent("BAG_UPDATE_DELAYED", OnZoneChanged)

-- Internal pub/sub message listeners for instant HUD refreshes
events.RegisterMessage("SFUI_FISHING_CATCH_RECORDED", function()
    if hudFrame and hudFrame:IsShown() then
        UpdateHud()
    end
end)

events.RegisterMessage("SFUI_FISHING_GETAWAY_RECORDED", function()
    if hudFrame and hudFrame:IsShown() then
        UpdateHud()
    end
end)

events.RegisterMessage("SFUI_FISHING_SESSION_RESET", function()
    if hudFrame and hudFrame:IsShown() then
        UpdateHud()
    end
end)
