-- warnings.lua for sfui
-- author: teli

sfui = sfui or {}
sfui.warnings = {}

local warningFrame
local warningText
local warningTimer
local event_frame -- Declare event_frame at a higher scope
local hasGrimoireOfSacrifice = false -- Cached status

local registeredEvents = {
    "UNIT_PET",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_TALENT_UPDATE", -- For Grimoire of Sacrifice check
}

local function UpdateGrimoireOfSacrificeStatus()
    local GRIMOIRE_OF_SACRIFICE_SPELL_ID = 108503
    hasGrimoireOfSacrifice = IsPlayerSpell(GRIMOIRE_OF_SACRIFICE_SPELL_ID)
end

local function CreateWarningFrame()
    warningFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150) -- Move 150p down
    warningFrame:SetSize(300, 50) -- Adjust size as needed
    warningFrame:SetFrameStrata("HIGH")
    warningFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "", -- No edge file for no border
        tile = true, tileSize = 16, edgeSize = 0, -- No edge size for no border
        insets = { left = 0, right = 0, top = 0, bottom = 0 } -- No insets
    })
    warningFrame:SetBackdropColor(0.8, 0, 0, 0.8) -- Red background
    warningFrame:SetBackdropBorderColor(0, 0, 0, 0) -- Transparent border
    warningFrame:Hide()

    warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    warningText:SetAllPoints(warningFrame)
    warningText:SetText("** FU PET **")
    warningText:SetTextColor(1, 0, 1, 1) -- #ff00ff
end

local function CheckPetWarning()
    if not warningFrame then CreateWarningFrame() end

    local _, playerClass = UnitClass("player")
    local spec = C_SpecializationInfo.GetSpecialization()
    local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0

    local isAppropriateSpec = false
    if playerClass == "HUNTER" and (specID == 253 or specID == 255) then -- BM or Survival Hunter
        isAppropriateSpec = true
    elseif playerClass == "DEATHKNIGHT" and specID == 252 then -- Unholy DK
        isAppropriateSpec = true
    elseif playerClass == "WARLOCK" then -- Any Warlock spec
        if not hasGrimoireOfSacrifice then
            isAppropriateSpec = true
        end
    end

    local hasPet = UnitExists("pet")
    local mounted = IsMounted()

    if isAppropriateSpec and not hasPet and not mounted then
        if not warningTimer then -- Start timer only if not already running
            warningTimer = C_Timer.After(2, function()
                if not UnitExists("pet") then -- Re-check if pet still not out after delay
                    warningFrame:Show()
                else
                    warningFrame:Hide() -- Hide if pet appeared during delay
                end
                warningTimer = nil -- Clear timer reference
            end)
        end
    else
        if warningTimer then
            C_Timer.Cancel(warningTimer) -- Cancel existing timer if conditions are no longer met
            warningTimer = nil
        end
        warningFrame:Hide()
    end
end

local function UpdateWarningActiveState()
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

    if isAppropriateSpec then
        -- Enable specific pet-related events
        for _, eventName in ipairs(registeredEvents) do
            event_frame:RegisterEvent(eventName)
        end
        CheckPetWarning() -- Initial check
    else
        -- Disable pet-related events and OnUpdate
        for _, eventName in ipairs(registeredEvents) do
            event_frame:UnregisterEvent(eventName)
        end
        event_frame:SetScript("OnUpdate", nil)
        warningFrame:Hide() -- Hide if spec is no longer appropriate
        if warningTimer then
            C_Timer.Cancel(warningTimer)
            warningTimer = nil
        end
    end
end

function sfui.warnings.GetStatus()
    if not warningFrame then return "Not Initialized" end
    if warningFrame:IsShown() then
        return "Warning Active"
    elseif warningTimer then
        return "Timer Active (2s Delay)"
    else
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

        if isAppropriateSpec and not hasPet and not mounted then
            return "Ready to Activate (Delaying)"
        else
            -- More specific status why conditions are not met
            if not isAppropriateSpec then return "Not Appropriate Spec" end
            if hasPet then return "Pet Out" end
            if mounted then return "Mounted" end
            return "Conditions Not Met"
        end
    end
end

function sfui.warnings.Initialize()
    event_frame = CreateFrame("Frame") -- Assign to higher-scoped variable
    event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    event_frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    event_frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            CreateWarningFrame() -- Create frame only once
            UpdateGrimoireOfSacrificeStatus() -- Initial update
        elseif event == "PLAYER_TALENT_UPDATE" then
            UpdateGrimoireOfSacrificeStatus()
        end
        UpdateWarningActiveState() -- Check/update state on relevant events
    end)
    -- OnUpdate will be managed by UpdateWarningActiveState
end