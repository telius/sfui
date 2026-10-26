local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

-- ========================
-- Localization
-- ========================
local _G = _G
local math_floor = _G.math.floor
local math_max = _G.math.max
local string_format = _G.string.format
local CreateFrame = _G.CreateFrame
local GetMinimapZoneText = _G.GetMinimapZoneText
local GetZonePVPInfo = _G.GetZonePVPInfo
local ToggleWorldMap = _G.ToggleWorldMap
local IsResting = _G.IsResting
local UnitIsPVP = _G.UnitIsPVP
local UnitIsPVPFreeForAll = _G.UnitIsPVPFreeForAll
local IsPVPTimerRunning = _G.IsPVPTimerRunning
local GetPVPTimer = _G.GetPVPTimer
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster

local locationFrame = nil

-- ------------------------------------------------------------------------------
-- Suppress Blizzard Clutter (Find / Tracking, Calendar, and default ZoneTextButton)
-- ------------------------------------------------------------------------------
local function is_valid_region(obj)
    local t = type(obj)
    return (t == "table" or t == "userdata") and obj.SetAlpha ~= nil
end

local function suppress_blizzard_elements()
    local btn = (MinimapCluster and MinimapCluster.ZoneTextButton) or _G.MinimapZoneTextButton
    if btn then
        btn:SetAlpha(0)
        if btn.EnableMouse then btn:EnableMouse(false) end
        if is_valid_region(btn.StateTexture) then btn.StateTexture:SetAlpha(0) end
        if is_valid_region(btn.AddTexture) then btn.AddTexture:SetAlpha(0) end

        if not sfui.minimap._zoneBtnSuppressed then
            sfui.minimap._zoneBtnSuppressed = true
            hooksecurefunc(btn, "SetAlpha", function(self, a)
                if a > 0 then
                    C_Timer.After(0, function()
                        if self and self.SetAlpha and self:GetAlpha() > 0 then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end)
            if btn.EnableMouse then
                hooksecurefunc(btn, "EnableMouse", function(self, e)
                    if e then
                        C_Timer.After(0, function()
                            if self and self.EnableMouse and not InCombatLockdown() then
                                self:EnableMouse(false)
                            end
                        end)
                    end
                end)
            end
            if is_valid_region(btn.StateTexture) then
                hooksecurefunc(btn.StateTexture, "SetAlpha", function(self, a)
                    if a > 0 then
                        C_Timer.After(0, function()
                            if self and self.SetAlpha and self:GetAlpha() > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end)
            end
            if is_valid_region(btn.AddTexture) then
                hooksecurefunc(btn.AddTexture, "SetAlpha", function(self, a)
                    if a > 0 then
                        C_Timer.After(0, function()
                            if self and self.SetAlpha and self:GetAlpha() > 0 then
                                self:SetAlpha(0)
                            end
                        end)
                    end
                end)
            end
        end
    end

    local zoneText = _G.MinimapZoneText
    if zoneText then
        zoneText:SetAlpha(0)
        if not sfui.minimap._zoneTextSuppressed then
            sfui.minimap._zoneTextSuppressed = true
            hooksecurefunc(zoneText, "SetAlpha", function(self, a)
                if a > 0 then
                    C_Timer.After(0, function()
                        if self and self.SetAlpha and self:GetAlpha() > 0 then
                            self:SetAlpha(0)
                        end
                    end)
                end
            end)
        end
    end

    local tracking = (MinimapCluster and MinimapCluster.Tracking) or _G.MiniMapTracking
    if tracking then
        tracking:SetAlpha(0)
        if tracking.EnableMouse then tracking:EnableMouse(false) end
    end
    if _G.MiniMapTrackingButton then
        _G.MiniMapTrackingButton:SetAlpha(0)
        _G.MiniMapTrackingButton:EnableMouse(false)
    end

    local cal = _G.GameTimeFrame
    if cal then
        cal:Hide()
        cal:SetAlpha(0)
        if cal.EnableMouse then cal:EnableMouse(false) end
    end
end

-- ------------------------------------------------------------------------------
-- Color by Zone PvP Type
-- ------------------------------------------------------------------------------
local function get_zone_color()
    if not GetZonePVPInfo then
        return 1.0, 0.82, 0.0
    end
    local pvpType = GetZonePVPInfo()
    if pvpType == "sanctuary" then
        return 0.41, 0.8, 0.94
    elseif pvpType == "arena" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "friendly" then
        return 0.1, 1.0, 0.1
    elseif pvpType == "hostile" then
        return 1.0, 0.1, 0.1
    elseif pvpType == "contested" then
        return 1.0, 0.7, 0.0
    else
        return 1.0, 0.82, 0.0
    end
end

-- ------------------------------------------------------------------------------
-- Build Status Tags (Resting & PvP)
-- ------------------------------------------------------------------------------
local function get_status_tags()
    local db = _G.SfuiDB
    local wantStatus = (db == nil or db.minimap_show_status ~= false)
    if not wantStatus then
        return "", ""
    end

    local restTag = ""
    if IsResting and IsResting() then
        restTag = " |cff80c0ffzzz|r"
    end

    local pvpTag = ""
    local isFFA = UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player")
    local isPVP = (UnitIsPVP and UnitIsPVP("player")) or isFFA

    if isFFA then
        pvpTag = " |cffff3333[ffa]|r"
    elseif isPVP then
        if IsPVPTimerRunning and IsPVPTimerRunning() then
            local ms = GetPVPTimer and GetPVPTimer() or 0
            local totalSec = math_floor(ms / 1000)
            if totalSec > 0 then
                local m = math_floor(totalSec / 60)
                local s = totalSec % 60
                pvpTag = string_format(" |cffff5555[pvp %d:%02d]|r", m, s)
            else
                pvpTag = " |cffff5555[pvp]|r"
            end
        else
            pvpTag = " |cffff9900[pvp]|r"
        end
    end

    return restTag, pvpTag
end

-- ------------------------------------------------------------------------------
-- Get or Create Native SFUI Location Frame
-- ------------------------------------------------------------------------------
local function get_or_create_location_frame()
    if locationFrame then return locationFrame end

    local parent = sfui.minimap.Holder or _G.Minimap or _G.UIParent
    local f = CreateFrame("Button", "sfui_MinimapLocation", parent)
    f.ignoreInLayout = true
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(30)
    f:SetSize(200, 20)
    f:EnableMouse(true)

    local text = f:CreateFontString(nil, "OVERLAY")
    local fontPath = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (sfui.config and sfui.config.fonts and sfui.config.fonts.normal)
        or "Fonts\\FRIZQT__.TTF"
    text:SetFont(fontPath, 12, "OUTLINE")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    f.text = text

    -- Click to toggle world map (matching Blizzard ZoneTextButton behavior)
    f:SetScript("OnClick", function(self, button)
        if (InCombatLockdown and InCombatLockdown()) or (sfui.map and sfui.map.IsInCombat and sfui.map.IsInCombat()) then return end
        if sfui.map and sfui.map.ToggleWorldMap then
            sfui.map.ToggleWorldMap()
        elseif ToggleWorldMap then
            pcall(ToggleWorldMap)
        end
    end)

    -- Informative Tooltip
    f:SetScript("OnEnter", function(self)
        local tip = sfui.common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:ClearLines()
        local zoneText = GetMinimapZoneText and GetMinimapZoneText() or ""
        local r, g, b = get_zone_color()
        tip:AddLine(zoneText, r, g, b)

        local pvpType = GetZonePVPInfo and GetZonePVPInfo()
        if pvpType then
            tip:AddLine("territory: " .. pvpType, 0.85, 0.85, 0.85)
        end

        local isRest = IsResting and IsResting()
        if isRest then
            tip:AddLine("resting: you are in a rest area (200% rested xp)", 0.5, 0.8, 1)
        end

        local isFFA = UnitIsPVPFreeForAll and UnitIsPVPFreeForAll("player")
        local isPVP = (UnitIsPVP and UnitIsPVP("player")) or isFFA
        if isFFA then
            tip:AddLine("free for all pvp: hostile to all players", 1, 0.2, 0.2)
        elseif isPVP then
            local faction = sfui.common.get_player_faction and sfui.common.get_player_faction() or "PvP"
            tip:AddLine(string_format("pvp enabled (%s)", faction), 1, 0.82, 0)
            if IsPVPTimerRunning and IsPVPTimerRunning() then
                local ms = GetPVPTimer and GetPVPTimer() or 0
                local totalSec = math_floor(ms / 1000)
                if totalSec > 0 then
                    local m = math_floor(totalSec / 60)
                    local s = totalSec % 60
                    tip:AddLine(string_format("pvp timer: %d:%02d remaining", m, s), 0.85, 0.85, 0.85)
                else
                    tip:AddLine("pvp dropping soon...", 0.85, 0.85, 0.85)
                end
            end
        end

        tip:AddLine("click: toggle world map", 0.6, 0.6, 0.6)
        tip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        local tip = sfui.common.get_tooltip()
        if tip then tip:Hide() end
    end)

    locationFrame = f
    return f
end

-- ------------------------------------------------------------------------------
-- Main Update Function
-- ------------------------------------------------------------------------------
function sfui.minimap.update_location_bar(overrideX, overrideY)
    suppress_blizzard_elements()

    local db = _G.SfuiDB
    local showLocation = (db == nil or db.minimap_show_location ~= false)
    local f = get_or_create_location_frame()

    if not showLocation then
        f:Hide()
        f:SetScript("OnUpdate", nil)
        return
    end

    local map = _G.Minimap
    if not map then return end

    local zoneX = overrideX
        or (db and db.minimap_zone_x)
        or (sfui.config and sfui.config.minimap and sfui.config.minimap.zone_x)
        or 0
    local zoneY = overrideY
        or (db and db.minimap_zone_y)
        or (sfui.config and sfui.config.minimap and sfui.config.minimap.zone_y)
        or 35

    local zoneText = GetMinimapZoneText and GetMinimapZoneText() or ""
    local restTag, pvpTag = get_status_tags()
    f.text:SetText(zoneText .. pvpTag .. restTag)

    local r, g, b = get_zone_color()
    f.text:SetTextColor(r, g, b, 1)

    local mapW = (map:GetWidth() and map:GetWidth() > 0) and map:GetWidth() or 200
    local targetW = math_max(160, mapW + 40)
    f:SetSize(targetW, 20)
    f.text:SetWidth(targetW)

    f:ClearAllPoints()
    f:SetPoint("TOP", map, "TOP", zoneX, zoneY)
    f:Show()

    -- 1-second ticker when PvP timer is running to smoothly count down
    if IsPVPTimerRunning and IsPVPTimerRunning() then
        if not f._pvpTickerRunning then
            f._pvpTickerRunning = true
            f.elapsed = 0
            f:SetScript("OnUpdate", function(self, dt)
                self.elapsed = (self.elapsed or 0) + dt
                if self.elapsed >= 1.0 then
                    self.elapsed = 0
                    if not IsPVPTimerRunning or not IsPVPTimerRunning() then
                        self._pvpTickerRunning = nil
                        self:SetScript("OnUpdate", nil)
                    end
                    local zText = GetMinimapZoneText and GetMinimapZoneText() or ""
                    local rTag, pTag = get_status_tags()
                    self.text:SetText(zText .. pTag .. rTag)
                end
            end)
        end
    else
        if f._pvpTickerRunning then
            f._pvpTickerRunning = nil
            f:SetScript("OnUpdate", nil)
        end
    end
end

function sfui.minimap.hook_location_bar()
    suppress_blizzard_elements()
    sfui.minimap.update_location_bar()
end

-- ------------------------------------------------------------------------------
-- Events for Zone, Resting, and PvP Changes
-- ------------------------------------------------------------------------------
sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterEvent("ZONE_CHANGED", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterEvent("ZONE_CHANGED_INDOORS", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterEvent("PLAYER_UPDATE_RESTING", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterUnitEvent("UNIT_FACTION", "player", function()
    sfui.minimap.update_location_bar()
end)

sfui.events.RegisterEvent("PVP_TIMER_UPDATE", function()
    sfui.minimap.update_location_bar()
end)
