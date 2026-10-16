local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

-- ========================
-- Localization
-- ========================
local _G = _G
local string_format = _G.string.format
local math_floor = _G.math.floor
local math_max = _G.math.max
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster
local CreateFrame = _G.CreateFrame

local weather_frame = nil

local WEATHER_ICONS = {
    [0] = "Interface\\PetBattles\\Weather-Sunlight",
    [1] = "Interface\\PetBattles\\Weather-Rain",
    [2] = "Interface\\PetBattles\\Weather-Blizzard",
    [3] = "Interface\\PetBattles\\Weather-Sandstorm",
    [4] = "Interface\\PetBattles\\Weather-StaticField",
}

local WEATHER_NAMES = {
    [0] = "clear",
    [1] = "rain",
    [2] = "snow",
    [3] = "sandstorm",
    [4] = "storm",
}

-- ------------------------------------------------------------------------------
-- Resolve Blizzard Day/Light Indicator
-- ------------------------------------------------------------------------------
local function get_day_light_indicator()
    local cluster = _G.MinimapCluster
    if cluster and cluster.DielFrame then
        return cluster.DielFrame
    end
    if _G.GameTimeFrame then
        return _G.GameTimeFrame
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- Icon & Bronze Border Skinning
-- ------------------------------------------------------------------------------
local function skin_weather_button(button, icon)
    if not button or not icon then return end

    if button.SetBackdrop then
        button:SetBackdrop(nil)
    end

    local isCamelot = (sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot))
        or (sfui.theme and sfui.theme.GetActiveThemeID and sfui.theme.GetActiveThemeID() == "camelot")
    local hasCycleAtlas = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo("UI-HUD-Minimap-Frame-Cycle")

    local btnW = button:GetWidth()
    local size = (btnW and btnW > 0) and btnW or 26

    if isCamelot or hasCycleAtlas then
        -- Native Camelot heavy bronze circular border (exact match to DielFrame)
        if not button.mask then
            local mask = button:CreateMaskTexture()
            mask:SetAllPoints(button)
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            button.mask = mask
        else
            button.mask:SetAllPoints(button)
        end

        -- Dark circular lens backing so minimap terrain does not bleed through
        if not button.lensBg then
            local bg = button:CreateTexture(nil, "BACKGROUND", nil, 0)
            bg:SetAllPoints(button)
            bg:SetColorTexture(0.04, 0.05, 0.08, 0.95)
            if button.mask then
                bg:AddMaskTexture(button.mask)
            end
            button.lensBg = bg
        else
            button.lensBg:SetAllPoints(button)
            button.lensBg:Show()
        end

        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button, "CENTER", 0, 0)
        local iconSize = math_floor(size * 0.70)
        icon:SetSize(iconSize, iconSize)
        icon:SetDrawLayer("ARTWORK", 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not icon.hasRoundMask and button.mask then
            icon:AddMaskTexture(button.mask)
            icon.hasRoundMask = true
        end

        if not button.bronzeBorder then
            local border = button:CreateTexture(nil, "OVERLAY", nil, 2)
            border:SetAllPoints(button)
            border:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
            button.bronzeBorder = border
        else
            button.bronzeBorder:SetAllPoints(button)
            button.bronzeBorder:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
            button.bronzeBorder:Show()
        end

        if button.roundBorder then button.roundBorder:Hide() end
        if button.roundBg then button.roundBg:Hide() end
    else
        if button.lensBg then button.lensBg:Hide() end
        -- Fallback standard round icon style with 1px border
        if button.bronzeBorder then button.bronzeBorder:Hide() end
        if sfui.common and sfui.common.apply_round_icon_style then
            sfui.common.apply_round_icon_style(button, icon, 1, { 0, 0, 0, 1 })
        elseif sfui.widgets and sfui.widgets.apply_round_icon_style then
            sfui.widgets.apply_round_icon_style(button, icon, 1, { 0, 0, 0, 1 })
        end
    end
end

-- ------------------------------------------------------------------------------
-- Get or Create Weather Indicator Frame
-- ------------------------------------------------------------------------------
local function get_or_create_weather_frame()
    if weather_frame then return weather_frame end

    local size = (sfui.config and sfui.config.minimap and sfui.config.minimap.status and sfui.config.minimap.status.icon_size) or 26
    local diel = get_day_light_indicator()
    local parent = (diel and diel:GetParent()) or _G.MinimapCluster or _G.Minimap or _G.UIParent

    local f = CreateFrame("Button", "sfui_minimap_weather", parent)
    f:SetSize(size, size)
    f:EnableMouse(true)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(25)

    local tex = f:CreateTexture(nil, "ARTWORK")
    f.texture = tex
    f.icon = tex
    skin_weather_button(f, tex)

    f:SetScript("OnEnter", function(self)
        local tip = sfui.common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        tip:ClearLines()
        local wType = (self.weatherInfo and self.weatherInfo.type) or 0
        local wName = WEATHER_NAMES[wType] or "clear"
        local pct = math_floor((((self.weatherInfo and self.weatherInfo.intensity) or 0) * 100) + 0.5)
        tip:AddLine("weather: " .. wName, 1, 1, 1)
        if pct > 0 then
            tip:AddLine(string_format("intensity: %d%%", pct), 0.7, 0.7, 0.7)
        end
        if _G.C_DateAndTime and _G.C_DateAndTime.IsDayTime then
            local isDay = _G.C_DateAndTime.IsDayTime()
            tip:AddLine(isDay and "time: daytime" or "time: nighttime", 0.75, 0.85, 1)
        end
        tip:Show()
    end)

    f:SetScript("OnLeave", function()
        local tip = sfui.common.get_tooltip()
        if tip then tip:Hide() end
    end)

    weather_frame = f
    sfui.minimap.status_container = f
    return f
end

sfui.minimap.get_status_container = get_or_create_weather_frame

-- ------------------------------------------------------------------------------
-- Main Update Function
-- ------------------------------------------------------------------------------
function sfui.minimap.update_status()
    local hasWeatherAPI = _G.C_Weather and _G.C_Weather.GetCurrentWeather
    local db = _G.SfuiDB
    local wantWeather = hasWeatherAPI and (db == nil or db.minimap_show_weather ~= false)

    if not wantWeather then
        if weather_frame then
            weather_frame:Hide()
            weather_frame.weatherInfo = nil
            local tip = sfui.common.get_tooltip()
            if tip and tip:IsOwned(weather_frame) then
                tip:Hide()
            end
        end
        return
    end

    local f = get_or_create_weather_frame()
    local diel = get_day_light_indicator()

    -- Ensure Blizzard day/light indicator is visible
    if diel and diel.SetAlpha then
        diel:SetAlpha(1)
        if not diel:IsShown() then
            diel:Show()
        end
    end

    local weatherInfo = hasWeatherAPI and _G.C_Weather.GetCurrentWeather()
    if not weatherInfo or weatherInfo.type == nil then
        weatherInfo = { type = 0, intensity = 0 }
    end

    local wType = weatherInfo.type or 0
    f.weatherInfo = weatherInfo
    local tex = WEATHER_ICONS[wType] or "Interface\\PetBattles\\Weather-Sunlight"
    if wType == 0 and _G.C_DateAndTime and _G.C_DateAndTime.IsDayTime and not _G.C_DateAndTime.IsDayTime() then
        tex = "Interface\\PetBattles\\Weather-Moonlight"
    end
    f.texture:SetTexture(tex)

    local size = (sfui.config and sfui.config.minimap and sfui.config.minimap.status and sfui.config.minimap.status.icon_size) or 26
    f:SetSize(size, size)
    skin_weather_button(f, f.texture)

    f:ClearAllPoints()
    if diel then
        if f:GetParent() ~= diel then
            f:SetParent(diel)
        end
        f.ignoreInLayout = true
        f:SetFrameStrata(diel:GetFrameStrata() or "MEDIUM")
        f:SetFrameLevel(math_max(5, (diel:GetFrameLevel() or 5) + 2))
        -- Conjoined cleanly to the southeast of the Diel indicator along the compass rim
        f:SetPoint("CENTER", diel, "CENTER", 22, -22)
    else
        local targetParent = _G.MinimapCluster or _G.Minimap or _G.UIParent
        if f:GetParent() ~= targetParent then
            f:SetParent(targetParent)
        end
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(25)
        local map = _G.Minimap
        if map then
            f:SetPoint("TOPRIGHT", map, "TOPRIGHT", -4, -4)
        end
    end

    f:Show()
end

-- ------------------------------------------------------------------------------
-- Event Registrations for Weather & Day/Night Cycle
-- ------------------------------------------------------------------------------
if _G.C_Weather then
    sfui.events.RegisterEvent("WEATHER_CHANGED", function()
        sfui.minimap.update_status()
    end)
end

sfui.events.RegisterEvent("DIEL_CYCLE_CHANGED", function()
    sfui.minimap.update_status()
end)

sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    sfui.minimap.update_status()
end)

sfui.events.RegisterEvent("ZONE_CHANGED", function()
    sfui.minimap.update_status()
end)

sfui.events.RegisterEvent("ZONE_CHANGED_INDOORS", function()
    sfui.minimap.update_status()
end)
