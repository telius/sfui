sfui = sfui or {}
sfui.warnings = {}

local colors = sfui.config.colors
local warningFrame, warningText, event_frame
local activeWarnings = {}
local PET_WARNING_PRIORITY, RUNE_WARNING_PRIORITY = 10, 5

local function CreateWarningFrame()
    if warningFrame then return end

    warningFrame = CreateFrame("Frame", "SfuiWarningFrame", UIParent, "BackdropTemplate")
    warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    warningFrame:SetSize(300, 50); warningFrame:SetFrameStrata("HIGH")
    warningFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16, edgeSize = 0, insets = { 0, 0, 0, 0 } })
    warningFrame:SetBackdropColor(0.8, 0, 0, 0.8); warningFrame:Hide()

    warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    warningText:SetAllPoints(warningFrame)
    warningText:SetText("")
end

local function UpdateWarningDisplay()
    if not warningFrame then CreateWarningFrame() end

    local highestPri, bestWarning = 0, nil
    for key, warning in pairs(activeWarnings) do
        if warning.active and warning.priority > highestPri then
            highestPri, bestWarning = warning.priority, warning
        end
    end

    if bestWarning then
        warningText:SetText(bestWarning.text)
        sfui.common.SetColor(warningText, bestWarning.color or "magenta")
        warningFrame:Show()
    else
        warningFrame:Hide()
    end
end

local function SetWarning(key, active, text, priority, colorName)
    activeWarnings[key] = {
        active = active,
        text = text,
        priority = priority or 1,
        color = colorName
    }
    UpdateWarningDisplay()
end

local function CheckAugmentRunes()
    local cfg = sfui.config.warnings.rune
    if not cfg or not cfg.enabled or UnitAffectingCombat("player") then
        SetWarning("rune", false); return
    end

    local RUNE_PAIRS = { { itemID = 243191, spellID = 1234969 }, { itemID = 211495, spellID = 393438 } }
    local missingRune = false
    for _, pair in ipairs(RUNE_PAIRS) do
        if C_Item.GetItemCount(pair.itemID) > 0 and not C_UnitAuras.GetPlayerAuraBySpellID(pair.spellID) then
            missingRune = true; break
        end
    end

    if missingRune then
        SetWarning("rune", true, cfg.text, cfg.priority, cfg.color)
    else
        SetWarning("rune", false)
    end
end

local petWarningTimer = nil
local hasGrimoireOfSacrifice = false

local function UpdateGrimoireOfSacrificeStatus()
    hasGrimoireOfSacrifice = IsPlayerSpell(108503)
end

local function CheckPetWarning()
    local cfg = sfui.config.warnings.pet
    if not cfg or not cfg.enabled then
        SetWarning("pet", false)
        return
    end

    local _, playerClass = UnitClass("player")
    local spec = C_SpecializationInfo.GetSpecialization()
    local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0

    local isAppropriateSpec = false
    if playerClass == "HUNTER" and (specID == 253 or specID == 255) then
        isAppropriateSpec = true
    elseif playerClass == "DEATHKNIGHT" and specID == 252 then
        isAppropriateSpec = true
    elseif playerClass == "WARLOCK" then
        if not hasGrimoireOfSacrifice then
            isAppropriateSpec = true
        end
    end

    local hasPet = UnitExists("pet")
    local mounted = IsMounted()
    local resting = IsResting()

    if isAppropriateSpec and not hasPet and not mounted and not resting then
        if not petWarningTimer then
            petWarningTimer = C_Timer.After(2, function()
                if not UnitExists("pet") and not IsResting() then
                    SetWarning("pet", true, cfg.text, cfg.priority, cfg.color)
                else
                    SetWarning("pet", false)
                end
                petWarningTimer = nil
            end)
        end
    else
        if petWarningTimer then
            C_Timer.Cancel(petWarningTimer)
            petWarningTimer = nil
        end
        SetWarning("pet", false)
    end
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        CreateWarningFrame()
        UpdateGrimoireOfSacrificeStatus()
        CheckPetWarning()
        CheckAugmentRunes()
    elseif event == "UNIT_PET" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_UPDATE_RESTING" then
        CheckPetWarning()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        CheckPetWarning(); CheckAugmentRunes()
    elseif event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        UpdateGrimoireOfSacrificeStatus(); CheckPetWarning()
    elseif event == "BAG_UPDATE_DELAYED" or event == "UNIT_AURA" then
        CheckAugmentRunes()
    end
end

function sfui.warnings.GetStatus()
    if not warningFrame then return "Not Initialized" end

    local status = {}
    for k, v in pairs(activeWarnings) do
        if v.active then
            table.insert(status, k .. ": " .. v.text)
        end
    end

    if #status > 0 then
        return table.concat(status, ", ")
    else
        return "No Active Warnings"
    end
end

function sfui.warnings.Initialize()
    event_frame = CreateFrame("Frame")
    event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    event_frame:RegisterEvent("UNIT_PET")
    event_frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    event_frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    event_frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    event_frame:RegisterEvent("PLAYER_UPDATE_RESTING")
    event_frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    event_frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    event_frame:RegisterEvent("BAG_UPDATE_DELAYED")
    event_frame:RegisterEvent("UNIT_AURA")
    event_frame:SetScript("OnEvent", OnEvent)
end
