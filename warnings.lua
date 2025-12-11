-- warnings.lua for sfui
-- author: teli

sfui = sfui or {}
sfui.warnings = {}

local warningFrame
local warningText
local warningTimer

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
        -- Check for Grimoire of Sacrifice (Spell ID 108503)
        local GRIMOIRE_OF_SACRIFICE_SPELL_ID = 108503
        if not IsPlayerSpell(GRIMOIRE_OF_SACRIFICE_SPELL_ID) then
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
            local GRIMOIRE_OF_SACRIFICE_SPELL_ID = 108503
            if not IsPlayerSpell(GRIMOIRE_OF_SACRIFICE_SPELL_ID) then
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
    local event_frame = CreateFrame("Frame")
    event_frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    event_frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    event_frame:RegisterEvent("UNIT_PET") -- Pet summoned/dismissed
    event_frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    event_frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    event_frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
    event_frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Leaving combat

    event_frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            CreateWarningFrame() -- Create frame only once
        end
        CheckPetWarning()
    end)
    -- Also check periodically
    event_frame:SetScript("OnUpdate", function(self, elapsed)
        -- Only call CheckPetWarning if we potentially need to show/hide it.
        -- This prevents constant API calls if conditions are stable.
        if (not IsMounted()) and (not UnitExists("pet")) then
            CheckPetWarning()
        end
    end)
end