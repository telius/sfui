local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.pet = {}

local petModule = sfui.experience.pet

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/pet.lua
--  Dedicated Hunter Pet Experience Status Bar for Camelot & Classic
--  Tracks: Pet Level, Pet XP, XP to Next Level, and Progress Percentage
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local tostring = _G.tostring
local UnitExists = _G.UnitExists
local UnitLevel = _G.UnitLevel
local UnitName = _G.UnitName
local UnitCreatureFamily = _G.UnitCreatureFamily
local GetPetExperience = _G.GetPetExperience
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring

local petContainer = nil
local petBar = nil
local textLeft = nil
local textCenter = nil
local textRight = nil

local PET_BAR_COLOR = { 0.18, 0.65, 0.32, 1.0 }

--- Check if pet experience tracking is available and relevant
--- @return boolean
function petModule.IsAvailable()
    local isCamelotOrClassic = not sfui.isRetail or sfui.isClassic or sfui.isCamelot
    if not isCamelotOrClassic then return false end

    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or _G.UnitClassBase("player")
    if pClass ~= "HUNTER" then return false end

    if not UnitExists("pet") then return false end

    local petLevel = UnitLevel("pet") or 0
    local playerLevel = UnitLevel("player") or 0
    if petLevel <= 0 or (playerLevel > 0 and petLevel >= playerLevel) then
        return false
    end

    if not GetPetExperience then return false end
    local currXP, nextXP = GetPetExperience()
    return (nextXP and nextXP > 0)
end

--- Query pet experience data safely
--- @return table|nil
function petModule.GetData()
    if not petModule.IsAvailable() then return nil end

    local currXP, nextXP = GetPetExperience()
    if not nextXP or nextXP <= 0 then return nil end

    local petLevel = UnitLevel("pet") or 0
    local petName = UnitName("pet") or "Pet"
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")

    return {
        name = petName,
        family = family,
        level = petLevel,
        current = currXP,
        max = nextXP,
        percent = (nextXP > 0) and (currXP / nextXP * 100) or 0,
        remaining = math_max(0, nextXP - currXP),
    }
end

--- Apply theme and styling
function petModule.ApplyTheme()
    if not petBar then return end

    local tex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture())
        or (sfui.config and sfui.config.textures and sfui.config.textures.status)
        or "Interface\\TargetingFrame\\UI-StatusBar"
    petBar:SetStatusBarTexture(tex)

    petBar:SetStatusBarColor(PET_BAR_COLOR[1], PET_BAR_COLOR[2], PET_BAR_COLOR[3], PET_BAR_COLOR[4])

    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (sfui.config and sfui.config.fontFile)
        or (_G.GameFontNormal and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
    local fontSize = 10
    if textLeft then
        textLeft:SetFont(fontFile, fontSize, "")
        textLeft:SetShadowOffset(1, -1)
        textLeft:SetShadowColor(0, 0, 0, 1)
    end
    if textCenter then
        textCenter:SetFont(fontFile, fontSize, "")
        textCenter:SetShadowOffset(1, -1)
        textCenter:SetShadowColor(0, 0, 0, 1)
    end
    if textRight then
        textRight:SetFont(fontFile, fontSize, "")
        textRight:SetShadowOffset(1, -1)
        textRight:SetShadowColor(0, 0, 0, 1)
    end

    if petContainer then
        if sfui.theme and sfui.theme.ApplyStatusBarStyle then
            sfui.theme.ApplyStatusBarStyle(petContainer, "xp")
        else
            local mult = sfui.pixelScale or 1
            local pad = 1 * mult
            petContainer:SetBackdrop({
                bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                tile = false,
                tileSize = 0,
                edgeSize = mult,
                insets = { left = pad, right = pad, top = pad, bottom = pad },
            })
            petContainer:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
            petContainer:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
end

--- Create the pet experience bar
--- @return Frame
function petModule.Create()
    if petContainer then return petContainer end

    local parent = _G.UIParent
    local mainExpBar = _G.SfuiExperienceBar

    petContainer = CreateFrame("Button", "SfuiPetExperienceBar", parent, "BackdropTemplate")
    petContainer:SetFrameStrata("HIGH")
    petContainer:SetFrameLevel(22)
    petContainer:SetClampedToScreen(true)
    petContainer:EnableMouse(true)

    local barWidth = 360
    local barHeight = 8
    if mainExpBar then
        barWidth = mainExpBar:GetWidth() or barWidth
        petContainer:SetPoint("BOTTOM", mainExpBar, "TOP", 0, 3)
    else
        petContainer:SetPoint("BOTTOM", parent, "BOTTOM", 0, 130)
    end
    petContainer:SetSize(barWidth, barHeight)

    petBar = CreateFrame("StatusBar", nil, petContainer)
    petBar:SetFrameLevel(petContainer:GetFrameLevel() + 1)
    petBar:SetAllPoints(petContainer)
    petBar:EnableMouse(false)

    local textFrame = CreateFrame("Frame", nil, petContainer)
    textFrame:SetFrameLevel(petContainer:GetFrameLevel() + 2)
    textFrame:SetAllPoints(petContainer)
    textFrame:EnableMouse(false)

    local font = (sfui.config and sfui.config.font) or "GameFontHighlightSmall"

    textLeft = textFrame:CreateFontString(nil, "OVERLAY", font)
    textLeft:SetPoint("LEFT", textFrame, "LEFT", 6, 0)
    textLeft:SetJustifyH("LEFT")
    textLeft:SetTextColor(0.9, 0.9, 0.9, 1.0)

    textCenter = textFrame:CreateFontString(nil, "OVERLAY", font)
    textCenter:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textCenter:SetJustifyH("CENTER")
    textCenter:SetTextColor(1.0, 1.0, 1.0, 1.0)

    textRight = textFrame:CreateFontString(nil, "OVERLAY", font)
    textRight:SetPoint("RIGHT", textFrame, "RIGHT", -6, 0)
    textRight:SetJustifyH("RIGHT")
    textRight:SetTextColor(0.85, 0.85, 0.85, 1.0)

    petContainer:SetScript("OnEnter", function(self)
        local data = petModule.GetData()
        if not data then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        _G.GameTooltip:ClearLines()
        _G.GameTooltip:AddDoubleLine(data.name .. (data.family and (" (" .. data.family .. ")") or ""), "level " .. data.level, 0.18, 0.65, 0.32, 1, 1, 1)
        _G.GameTooltip:AddLine(" ")
        _G.GameTooltip:AddDoubleLine("experience:", string_format("%s / %s (%.1f%%)", BreakUpLargeNumbers(data.current), BreakUpLargeNumbers(data.max), data.percent), 0.8, 0.8, 0.8, 1, 1, 1)
        _G.GameTooltip:AddDoubleLine("remaining:", BreakUpLargeNumbers(data.remaining), 0.8, 0.8, 0.8, 1, 0.8, 0.4)
        _G.GameTooltip:Show()
    end)

    petContainer:SetScript("OnLeave", function()
        _G.GameTooltip:Hide()
    end)

    petModule.ApplyTheme()
    return petContainer
end

--- Update pet experience values and visibility
function petModule.UpdateValues()
    local data = petModule.GetData()
    if not data then
        if petContainer then
            petContainer:Hide()
        end
        return
    end

    if not petContainer then
        petModule.Create()
    end

    petBar:SetMinMaxValues(0, data.max)
    petBar:SetValue(data.current)

    if textLeft then
        textLeft:SetText(string_format("%s (lv %d)", (data.name or "pet"):lower(), data.level))
    end
    if textCenter then
        textCenter:SetText(string_format("%s / %s (%.1f%%)", BreakUpLargeNumbers(data.current), BreakUpLargeNumbers(data.max), data.percent))
    end
    if textRight then
        textRight:SetText(string_format("%s to next", BreakUpLargeNumbers(data.remaining)))
    end

    petContainer:Show()
end

--- Get the pet container frame
--- @return Frame|nil
function petModule.GetFrame()
    return petContainer
end
