local addonName, addon = ...
sfui = sfui or {}
sfui.experience = sfui.experience or {}
sfui.experience.pet = {}

local petModule = sfui.experience.pet

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/experience/pet.lua
--  Dedicated Hunter Pet Experience Status Bar for Camelot & Classic
--  Tracks: Pet Level, Pet XP, XP to Next Level, Progress Percentage,
--          Pet Loyalty Rank & Rate, Training Points (Available, Spent, Debt),
--          and Pet Happiness & Diet
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local table_concat = table.concat
local tostring = _G.tostring
local UnitExists = _G.UnitExists
local UnitLevel = _G.UnitLevel
local UnitName = _G.UnitName
local UnitCreatureFamily = _G.UnitCreatureFamily
local GetPetExperience = _G.GetPetExperience
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring
local C_PetInfo = _G.C_PetInfo
local GameTooltip = sfui.common.get_tooltip()

local petContainer = nil
local petBar = nil
local textFrame = nil
local textLeft = nil
local textCenter = nil
local textRight = nil
local portraitFrame = nil
local portraitTexture = nil
local tpText = nil

local cachedPetData = {}
local _, playerClass = _G.UnitClass("player")
local isHunterClass = (playerClass == "HUNTER")
local isCamelotOrClassic = not sfui.isRetail or sfui.isClassic or sfui.isCamelot

local PET_BAR_COLOR_XP = { 0.18, 0.65, 0.32, 1.0 }
local PET_BAR_COLOR_TP = { 0.88, 0.62, 0.14, 1.0 }

--- Update text visibility based on hover state and configuration
--- @param isHovering boolean
local function UpdateTextVisibility(isHovering)
    local data = sfui.experience.data
    local alpha = data and data.GetTextAlpha and data.GetTextAlpha(isHovering) or (isHovering and 1.0 or 0.0)

    if textLeft then textLeft:SetAlpha(alpha) end
    if textCenter then textCenter:SetAlpha(alpha) end
    if textRight then textRight:SetAlpha(alpha) end
    if portraitFrame then portraitFrame:SetAlpha(isHovering and 1.0 or 0.9) end
    if tpText then tpText:SetAlpha(isHovering and 1.0 or 0.9) end
end

--- Check if pet tracking is available and relevant
--- @return boolean
function petModule.IsAvailable()
    if not isHunterClass or not isCamelotOrClassic then return false end

    if not UnitExists("pet") then return false end

    if _G.HasPetUI then
        local hasUI, isHunterPet = _G.HasPetUI()
        if not hasUI or not isHunterPet then return false end
    end

    local petLevel = UnitLevel("pet") or 0
    if petLevel <= 0 then return false end

    local playerLevel = UnitLevel("player") or 0
    local nextXP = 0
    if GetPetExperience then
        _, nextXP = GetPetExperience()
    end
    nextXP = nextXP or 0

    local totalTP, usedTP = 0, 0
    if C_PetInfo and C_PetInfo.GetPetTrainingPoints then
        totalTP, usedTP = C_PetInfo.GetPetTrainingPoints()
    elseif _G.GetPetTrainingPoints then
        totalTP, usedTP = _G.GetPetTrainingPoints()
    end
    totalTP = totalTP or 0
    usedTP = usedTP or 0
    local unspentTP = totalTP - usedTP

    local loyaltyRank = 1
    if petLevel > 0 and totalTP >= 0 then
        loyaltyRank = math_min(6, math_max(1, math_floor(totalTP / petLevel) + 1))
    end

    local isXpCapped = (nextXP <= 0) or (playerLevel > 0 and petLevel >= playerLevel)
    local isLoyaltyCapped = (loyaltyRank >= 6)
    local alwaysShow = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "petBarAlwaysShow", false))

    -- Show if pet is gaining XP, has unspent TP or point debt, loyalty is not maxed, or user forced always show
    if not isXpCapped then
        return true
    end
    if unspentTP ~= 0 or not isLoyaltyCapped or alwaysShow then
        return true
    end

    return false
end

--- Query pet experience, training points, and loyalty data safely
--- @return table|nil
function petModule.GetData()
    if not petModule.IsAvailable() then return nil end

    local petLevel = UnitLevel("pet") or 0
    local playerLevel = UnitLevel("player") or 0
    local petName = UnitName("pet") or "pet"
    local family = UnitCreatureFamily and UnitCreatureFamily("pet")

    -- Pet Experience
    local currXP, nextXP = 0, 0
    if GetPetExperience then
        currXP, nextXP = GetPetExperience()
    end
    currXP = currXP or 0
    nextXP = nextXP or 0

    -- Training Points
    local totalTP, usedTP = 0, 0
    if C_PetInfo and C_PetInfo.GetPetTrainingPoints then
        totalTP, usedTP = C_PetInfo.GetPetTrainingPoints()
    elseif _G.GetPetTrainingPoints then
        totalTP, usedTP = _G.GetPetTrainingPoints()
    end
    totalTP = totalTP or 0
    usedTP = usedTP or 0
    local unspentTP = totalTP - usedTP

    -- Loyalty
    local loyaltyName = nil
    if C_PetInfo and C_PetInfo.GetPetLoyalty then
        loyaltyName = C_PetInfo.GetPetLoyalty()
    elseif _G.GetPetLoyalty then
        loyaltyName = _G.GetPetLoyalty()
    end
    loyaltyName = loyaltyName or "rebellious"

    local loyaltyRank = 1
    if petLevel > 0 and totalTP >= 0 then
        loyaltyRank = math_min(6, math_max(1, math_floor(totalTP / petLevel) + 1))
    end

    -- Happiness & Damage Modifier
    local happiness, dmgPct, loyaltyRate = nil, nil, nil
    if C_PetInfo and C_PetInfo.GetPetHappiness then
        happiness, dmgPct, loyaltyRate = C_PetInfo.GetPetHappiness()
    elseif _G.GetPetHappiness then
        happiness, dmgPct, loyaltyRate = _G.GetPetHappiness()
    end
    happiness = happiness or 2
    dmgPct = dmgPct or (happiness == 1 and 75 or (happiness == 3 and 125 or 100))
    loyaltyRate = loyaltyRate or 0

    -- Diet / Food Types
    local diet = nil
    if C_PetInfo and C_PetInfo.GetPetFoodTypes then
        diet = C_PetInfo.GetPetFoodTypes()
    elseif _G.GetPetFoodTypes then
        diet = _G.GetPetFoodTypes()
    end

    local isXpCapped = (nextXP <= 0) or (playerLevel > 0 and petLevel >= playerLevel)
    local percent = (nextXP > 0) and (currXP / nextXP * 100) or 100
    local remaining = math_max(0, nextXP - currXP)

    cachedPetData.name = petName
    cachedPetData.family = family
    cachedPetData.level = petLevel
    cachedPetData.playerLevel = playerLevel
    cachedPetData.isXpCapped = isXpCapped
    cachedPetData.currentXP = currXP
    cachedPetData.maxXP = nextXP
    cachedPetData.percentXP = percent
    cachedPetData.remainingXP = remaining
    cachedPetData.totalTP = totalTP
    cachedPetData.usedTP = usedTP
    cachedPetData.unspentTP = unspentTP
    cachedPetData.loyaltyName = loyaltyName:lower()
    cachedPetData.loyaltyRank = loyaltyRank
    cachedPetData.happiness = happiness
    cachedPetData.damagePct = dmgPct
    cachedPetData.loyaltyRate = loyaltyRate
    cachedPetData.diet = diet

    return cachedPetData
end

--- Set status bar texture directly
--- @param tex string|nil
function petModule.SetBarTexture(tex)
    if not petBar then return end
    tex = tex or (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture()) or "Interface\\TargetingFrame\\UI-StatusBar"
    if sfui.widgets and sfui.widgets.resolve_statusbar_texture then
        tex = sfui.widgets.resolve_statusbar_texture(tex)
    end
    petBar:SetStatusBarTexture(tex)
end

--- Apply theme and styling
function petModule.ApplyTheme()
    if not petBar then return end

    local tex = (sfui.widgets and sfui.widgets.get_bar_texture and sfui.widgets.get_bar_texture())
        or (sfui.config and sfui.config.textures and sfui.config.textures.status)
        or "Interface\\TargetingFrame\\UI-StatusBar"
    if sfui.widgets and sfui.widgets.resolve_statusbar_texture then
        tex = sfui.widgets.resolve_statusbar_texture(tex)
    end
    petBar:SetStatusBarTexture(tex)

    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (sfui.config and sfui.config.fontFile)
        or (_G.GameFontNormal and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"
    local fontSize = 9
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
    if tpText then
        tpText:SetFont(fontFile, fontSize, "")
        tpText:SetShadowOffset(0, 0)
        tpText:SetShadowColor(0, 0, 0, 0)
    end

    if petContainer then
        if sfui.theme and sfui.theme.ApplyStatusBarStyle then
            sfui.theme.ApplyStatusBarStyle(petContainer, "xp")
        else
            petContainer:SetBackdrop({
                bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                tile = false,
                tileSize = 0,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            petContainer:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
            petContainer:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end
end

--- Update layout and docking position relative to experience, reputation, and challenge bars
function petModule.UpdateLayout()
    if not petContainer then return end

    local cfg = sfui.config and sfui.config.experience or {}
    local width = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "width", cfg.width or 460)) or 460
    local barHeight = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "petHeight", cfg.petHeight or 10)) or 10

    petContainer:SetSize(width, barHeight)
    petContainer:ClearAllPoints()

    local expBar = sfui.experience.bar and sfui.experience.bar.GetFrame and sfui.experience.bar.GetFrame()
    local repBar = sfui.experience.reputation and sfui.experience.reputation.GetFrame and sfui.experience.reputation.GetFrame()
    local chalBar = sfui.experience.challenges and sfui.experience.challenges.GetFrame and sfui.experience.challenges.GetFrame()

    local isChalShown = chalBar and chalBar:IsShown() and chalBar:GetAlpha() > 0
    local isRepShown = repBar and repBar:IsShown() and repBar:GetAlpha() > 0
    local isExpShown = expBar and expBar:IsShown() and expBar:GetAlpha() > 0

    local anchorFrame = nil
    if isChalShown then
        anchorFrame = chalBar
    elseif isRepShown then
        anchorFrame = repBar
    elseif isExpShown then
        anchorFrame = expBar
    end

    if anchorFrame then
        petContainer:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 2)
        petContainer:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 2)
    else
        local pos = (sfui.db and sfui.db.Get and sfui.db.Get("experience", "pos", cfg.pos)) or cfg.pos or { point = "BOTTOM", x = 0, y = 4 }
        petContainer:SetPoint(pos.point or "BOTTOM", _G.UIParent, pos.relativePoint or pos.point or "BOTTOM", pos.x or 0, pos.y or 4)
    end

    if petBar then
        petBar:ClearAllPoints()
        petBar:SetPoint("TOPLEFT", petContainer, "TOPLEFT", 1, -1)
        petBar:SetPoint("BOTTOMRIGHT", petContainer, "BOTTOMRIGHT", -1, 1)
    end
end

--- Toggle the character sheet pet pane for Camelot, Classic, or Retail
local function TogglePetPanel()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end

    -- Camelot PaperDoll sidebar system (sidebar tab 4 is CharacterStatsPanePetScrollBox)
    if _G.CharacterStatsPanePetScrollBox then
        local charFrame = _G.CharacterFrame
        local paperDoll = _G.PaperDollFrame
        local petBox = _G.CharacterStatsPanePetScrollBox
        local sidebarTabs = _G.PaperDollSidebarTabs

        if charFrame and charFrame:IsShown() and paperDoll and paperDoll:IsShown() and petBox:IsShown() then
            if _G.HideUIPanel then
                securecall(_G.HideUIPanel, charFrame)
            else
                charFrame:Hide()
            end
        else
            if _G.ToggleCharacter then
                securecall(_G.ToggleCharacter, "PaperDollFrame", true)
            elseif charFrame then
                if _G.ShowUIPanel then securecall(_G.ShowUIPanel, charFrame) else charFrame:Show() end
            end

            if _G.PaperDollFrame_SetSidebar and sidebarTabs then
                securecall(_G.PaperDollFrame_SetSidebar, sidebarTabs, 4)
            elseif _G.PaperDollSidebarTab4 and _G.PaperDollSidebarTab4.Click then
                securecall(_G.PaperDollSidebarTab4.Click, _G.PaperDollSidebarTab4)
            end
        end
        return
    end

    -- Classic Era / Vanilla with dedicated PetPaperDollFrame subframe
    if _G.PetPaperDollFrame and _G.ToggleCharacter then
        securecall(_G.ToggleCharacter, "PetPaperDollFrame")
        return
    end

    -- General fallback: toggle character sheet
    if _G.ToggleCharacter then
        securecall(_G.ToggleCharacter, "PaperDollFrame")
    end
end

--- Open or toggle the Beast Training craft window
local function OpenBeastTraining()
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
            _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
        end
        return
    end

    if _G.CraftFrame and _G.CraftFrame:IsShown() then
        if _G.HideUIPanel then securecall(_G.HideUIPanel, _G.CraftFrame) else _G.CraftFrame:Hide() end
        return
    end

    local casted = false
    if _G.CastSpellByID then
        local ok = pcall(_G.CastSpellByID, 5149)
        if ok then casted = true end
    end
    if not casted and _G.CastSpellByName then
        local spellName = (_G.C_Spell and _G.C_Spell.GetSpellInfo and _G.C_Spell.GetSpellInfo(5149) and _G.C_Spell.GetSpellInfo(5149).name)
                          or (_G.GetSpellInfo and _G.GetSpellInfo(5149))
                          or "Beast Training"
        pcall(_G.CastSpellByName, spellName)
    end
end

--- Create the pet experience and training bar
--- @return Frame
function petModule.Create()
    if petContainer then return petContainer end

    local parent = _G.UIParent

    petContainer = CreateFrame("Button", "SfuiPetExperienceBar", parent, "BackdropTemplate")
    petContainer:SetFrameStrata("HIGH")
    petContainer:SetFrameLevel(22)
    petContainer:SetClampedToScreen(true)
    petContainer:EnableMouse(true)
    petContainer:RegisterForClicks("AnyUp")

    petBar = CreateFrame("StatusBar", nil, petContainer)
    petBar:SetFrameLevel(petContainer:GetFrameLevel() + 1)
    petBar:SetPoint("TOPLEFT", petContainer, "TOPLEFT", 1, -1)
    petBar:SetPoint("BOTTOMRIGHT", petContainer, "BOTTOMRIGHT", -1, 1)
    petBar:EnableMouse(false)

    textFrame = CreateFrame("Frame", nil, petContainer)
    textFrame:SetFrameLevel(petContainer:GetFrameLevel() + 2)
    textFrame:SetAllPoints(petContainer)
    textFrame:EnableMouse(false)

    local font = (sfui.config and sfui.config.font) or "GameFontHighlightSmall"

    textLeft = textFrame:CreateFontString(nil, "OVERLAY", font)
    textLeft:SetPoint("LEFT", textFrame, "LEFT", 4, 0)
    textLeft:SetJustifyH("LEFT")
    textLeft:SetTextColor(0.9, 0.9, 0.9, 1.0)

    textCenter = textFrame:CreateFontString(nil, "OVERLAY", font)
    textCenter:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textCenter:SetJustifyH("CENTER")
    textCenter:SetTextColor(1.0, 1.0, 1.0, 1.0)
    textCenter:Hide()

    textRight = textFrame:CreateFontString(nil, "OVERLAY", font)
    textRight:SetPoint("RIGHT", textFrame, "RIGHT", -4, 0)
    textRight:SetJustifyH("RIGHT")
    textRight:SetTextColor(0.85, 0.85, 0.85, 1.0)

    -- Center pet portrait (twice the bar size, centered directly in the middle of the bar)
    portraitFrame = CreateFrame("Frame", "SfuiPetExpPortraitFrame", textFrame)
    portraitFrame:SetFrameLevel(petContainer:GetFrameLevel() + 6)
    portraitFrame:SetPoint("CENTER", petContainer, "CENTER", 0, 0)
    portraitFrame:EnableMouse(false)

    portraitTexture = portraitFrame:CreateTexture(nil, "ARTWORK")
    portraitTexture:SetAllPoints(portraitFrame)
    if sfui.widgets and sfui.widgets.apply_round_icon_style then
        sfui.widgets.apply_round_icon_style(portraitFrame, portraitTexture, 1.2, { 0, 0, 0, 0.9 })
    elseif sfui.widgets and sfui.widgets.set_round_icon_coords then
        sfui.widgets.set_round_icon_coords(portraitTexture)
    else
        portraitTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Training points counter anchored immediately to the right of the portrait
    local fontFile = (sfui.common and sfui.common.get_font_file and sfui.common.get_font_file())
        or (_G.GameFontNormal and _G.GameFontNormal:GetFont())
        or "Fonts\\FRIZQT__.TTF"

    tpText = textFrame:CreateFontString(nil, "OVERLAY")
    tpText:SetFont(fontFile, 10, "")
    tpText:SetShadowOffset(0, 0)
    tpText:SetShadowColor(0, 0, 0, 0)
    tpText:SetPoint("LEFT", portraitFrame, "RIGHT", 4, 0)
    tpText:SetJustifyH("LEFT")
    tpText:SetTextColor(1.0, 1.0, 1.0, 1.0)

    petContainer:SetScript("OnEnter", function(self)
        UpdateTextVisibility(true)
        local data = petModule.GetData()
        if not data then return end

        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 4)
        GameTooltip:ClearLines()

        -- Title line: name (family) — level lvl
        local titleLeft = data.name:lower() .. (data.family and (" (" .. data.family:lower() .. ")") or "")
        local titleRight = "level " .. data.level
        GameTooltip:AddDoubleLine(titleLeft, titleRight, 0.18, 0.65, 0.32, 1, 1, 1)
        GameTooltip:AddLine(" ")

        -- Loyalty
        local loyaltyR, loyaltyG, loyaltyB = 1, 1, 1
        if data.loyaltyRank == 6 then
            loyaltyR, loyaltyG, loyaltyB = 1.0, 0.82, 0.2
        elseif data.loyaltyRate > 0 then
            loyaltyR, loyaltyG, loyaltyB = 0.2, 0.9, 0.2
        elseif data.loyaltyRate < 0 then
            loyaltyR, loyaltyG, loyaltyB = 0.9, 0.2, 0.2
        end
        GameTooltip:AddDoubleLine("loyalty:", string_format("%s (rank %d of 6)", data.loyaltyName, data.loyaltyRank), 0.8, 0.8, 0.8, loyaltyR, loyaltyG, loyaltyB)

        if data.loyaltyRate > 0 then
            GameTooltip:AddDoubleLine("loyalty trend:", "gaining loyalty (keep pet happy)", 0.6, 0.6, 0.6, 0.2, 0.9, 0.2)
        elseif data.loyaltyRate < 0 then
            GameTooltip:AddDoubleLine("loyalty trend:", "losing loyalty (feed your pet)", 0.6, 0.6, 0.6, 0.9, 0.2, 0.2)
        end

        -- Happiness
        local hapText = "content"
        local hapR, hapG, hapB = 0.95, 0.8, 0.2
        if data.happiness == 3 then
            hapText = "happy"
            hapR, hapG, hapB = 0.2, 0.9, 0.2
        elseif data.happiness == 1 then
            hapText = "unhappy"
            hapR, hapG, hapB = 0.95, 0.2, 0.2
        end
        GameTooltip:AddDoubleLine("happiness:", string_format("%s (%d%% damage)", hapText, data.damagePct), 0.8, 0.8, 0.8, hapR, hapG, hapB)

        -- Diet
        if data.diet and #data.diet > 0 then
            local dietStr = table_concat(data.diet, ", "):lower()
            GameTooltip:AddDoubleLine("diet:", dietStr, 0.8, 0.8, 0.8, 0.9, 0.9, 0.9)
        end

        GameTooltip:AddLine(" ")

        -- Experience section
        GameTooltip:AddLine("pet experience", 0.18, 0.65, 0.32)
        if data.isXpCapped then
            GameTooltip:AddDoubleLine("status:", "capped at player level", 0.8, 0.8, 0.8, 1, 0.82, 0.2)
        else
            GameTooltip:AddDoubleLine("current xp:", string_format("%s / %s (%.1f%%)", BreakUpLargeNumbers(data.currentXP), BreakUpLargeNumbers(data.maxXP), data.percentXP), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("xp remaining:", BreakUpLargeNumbers(data.remainingXP), 0.8, 0.8, 0.8, 1, 0.82, 0.4)
            GameTooltip:AddDoubleLine("xp rule:", "kills within 5 levels of pet", 0.6, 0.6, 0.6, 0.7, 0.7, 0.7)
        end

        GameTooltip:AddLine(" ")

        -- Training points section
        GameTooltip:AddLine("pet training points", 0.88, 0.62, 0.14)
        if data.unspentTP > 0 then
            GameTooltip:AddDoubleLine("unspent points:", string_format("%s tp available", BreakUpLargeNumbers(data.unspentTP)), 0.8, 0.8, 0.8, 0.2, 0.9, 0.2)
        elseif data.unspentTP < 0 then
            GameTooltip:AddDoubleLine("points debt:", string_format("%s tp", BreakUpLargeNumbers(data.unspentTP)), 0.8, 0.8, 0.8, 0.95, 0.2, 0.2)
        else
            GameTooltip:AddDoubleLine("unspent points:", "0 tp", 0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddDoubleLine("points spent:", string_format("%s / %s tp", BreakUpLargeNumbers(data.usedTP), BreakUpLargeNumbers(data.totalTP)), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("formula:", "level x (loyalty rank - 1)", 0.6, 0.6, 0.6, 0.7, 0.7, 0.7)

        if data.unspentTP < 0 then
            GameTooltip:AddLine("tamed pet has negative tp balance until loyalty increases", 0.9, 0.4, 0.2)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("<left-click: open pet character pane>", 0.5, 0.8, 0.5)
        GameTooltip:AddLine("<right-click: open beast training menu>", 0.88, 0.62, 0.14)
        GameTooltip:AddLine("<middle-click: fast feed pet>", 0.2, 0.9, 0.2)

        GameTooltip:Show()
    end)

    petContainer:SetScript("OnLeave", function()
        UpdateTextVisibility(false)
        GameTooltip:Hide()
    end)

    petContainer:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            OpenBeastTraining()
        elseif button == "MiddleButton" then
            if sfui.pet and sfui.pet.fast_feed then
                sfui.pet.fast_feed()
            end
        else
            TogglePetPanel()
        end
    end)

    petModule.ApplyTheme()
    petModule.UpdateLayout()
    UpdateTextVisibility(false)
    return petContainer
end

--- Update pet experience and training values and visibility
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

    petModule.UpdateLayout()

    local cfg = sfui.config and sfui.config.experience or {}
    local colors = (cfg and cfg.colors) or {}
    local colorXP = colors.petXP or PET_BAR_COLOR_XP
    local colorTP = colors.petTP or PET_BAR_COLOR_TP

    if not data.isXpCapped and data.maxXP > 0 then
        -- Mode 1: Active XP Progression
        petBar:SetStatusBarColor(colorXP[1], colorXP[2], colorXP[3], colorXP[4] or 1.0)
        petBar:SetMinMaxValues(0, data.maxXP)
        petBar:SetValue(data.currentXP)

        if textLeft then
            textLeft:SetText(string_format("%s (lv %d)", data.name:lower(), data.level))
        end
        if textRight then
            textRight:SetText(string_format("%s / %s (%.1f%%)", BreakUpLargeNumbers(data.currentXP), BreakUpLargeNumbers(data.maxXP), data.percentXP))
        end
    else
        -- Mode 2: Capped XP -> Training Points & Loyalty Tracking
        petBar:SetStatusBarColor(colorTP[1], colorTP[2], colorTP[3], colorTP[4] or 1.0)
        local maxPoints = math_max(data.totalTP, 1)
        local availableTP = math_max(0, data.unspentTP)
        petBar:SetMinMaxValues(0, maxPoints)
        petBar:SetValue(math_min(maxPoints, availableTP))

        if textLeft then
            textLeft:SetText(string_format("%s (lv %d - loyalty %d/6)", data.name:lower(), data.level, data.loyaltyRank))
        end
        if textRight then
            textRight:SetText(string_format("%s / %s tp available", BreakUpLargeNumbers(availableTP), BreakUpLargeNumbers(maxPoints)))
        end
    end

    -- Center portrait and TP counter
    if portraitTexture then
        if _G.SetPortraitTexture and UnitExists("pet") then
            _G.SetPortraitTexture(portraitTexture, "pet")
        else
            portraitTexture:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
        end
    end

    local barH = petContainer:GetHeight() or 10
    local pSize = math_max(20, math_floor((barH * 2.0) + 0.5))
    if portraitFrame then
        portraitFrame:SetSize(pSize, pSize)
        portraitFrame:ClearAllPoints()
        portraitFrame:SetPoint("CENTER", petContainer, "CENTER", 0, 0)
    end

    if tpText then
        local unspentTP = data.unspentTP or 0
        if unspentTP > 0 then
            tpText:SetText("|cff33ff33" .. BreakUpLargeNumbers(unspentTP) .. "|r")
        elseif unspentTP < 0 then
            tpText:SetText("|cffff5533" .. BreakUpLargeNumbers(unspentTP) .. "|r")
        else
            tpText:SetText("|cffaaaaaa0|r")
        end
        tpText:ClearAllPoints()
        tpText:SetPoint("LEFT", portraitFrame, "RIGHT", 4, 0)
    end

    UpdateTextVisibility(petContainer:IsMouseOver())
    petContainer:Show()
end

--- Get the pet container frame
--- @return Frame|nil
function petModule.GetFrame()
    return petContainer
end
