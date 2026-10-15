local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local _G = _G
local C_SpecializationInfo = _G.C_SpecializationInfo or {}
local GetNumSpecializations = C_SpecializationInfo.GetNumSpecializations or _G.GetNumSpecializations
local GetSpecialization     = C_SpecializationInfo.GetSpecialization or _G.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo or _G.GetSpecializationInfo
local SetSpecialization     = C_SpecializationInfo.SetSpecialization or _G.SetSpecialization
local GetNumSpecGroups      = C_SpecializationInfo.GetNumSpecGroups or _G.GetNumSpecGroups or _G.GetNumTalentGroups
local GetActiveSpecGroup    = C_SpecializationInfo.GetActiveSpecGroup or _G.GetActiveSpecGroup or _G.GetActiveTalentGroup
local SetActiveSpecGroup    = C_SpecializationInfo.SetActiveSpecGroup or _G.SetActiveSpecGroup or _G.SetActiveTalentGroup
local InCombatLockdown      = _G.InCombatLockdown
local PlaySound             = _G.PlaySound
local SOUNDKIT              = _G.SOUNDKIT
local tostring              = _G.tostring

local function build_specs_ring(out)
    local numSpecs = (GetNumSpecializations and GetNumSpecializations()) or 0

    if numSpecs and numSpecs > 0 then
        local currentSpec = (GetSpecialization and GetSpecialization()) or 0
        for i = 1, numSpecs do
            local specID, name, _, icon = GetSpecializationInfo(i)
            if specID then
                local isActive = (i == currentSpec)
                local labelText = name and name:lower() or ("spec " .. i)
                if isActive then
                    labelText = labelText .. " (active)"
                end

                local specIndex = i
                out[#out + 1] = {
                    id          = "spec_" .. tostring(specID),
                    specID      = specID,
                    specIndex   = specIndex,
                    label       = labelText,
                    icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    active      = isActive,
                    color       = isActive and { 1, 1, 1 } or { 0.8, 0.8, 0.8 },
                    insecure_func = function()
                        if InCombatLockdown and InCombatLockdown() then
                            if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                                _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
                            end
                            return
                        end
                        if isActive then return end
                        if SetSpecialization then
                            SetSpecialization(specIndex)
                        end
                        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE then
                            PlaySound(SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE)
                        end
                    end,
                }
            end
        end
    else
        local numGroups = (GetNumSpecGroups and GetNumSpecGroups()) or 0
        if numGroups > 1 then
            local activeGroup = (GetActiveSpecGroup and GetActiveSpecGroup()) or 1
            for g = 1, numGroups do
                local isActive = (g == activeGroup)
                local groupName = (g == 1 and (_G.DUAL_SPEC_PRIMARY or "primary spec"))
                    or (g == 2 and (_G.DUAL_SPEC_SECONDARY or "secondary spec"))
                    or ("spec group " .. g)
                local labelText = groupName:lower()
                if isActive then
                    labelText = labelText .. " (active)"
                end

                local curSpecID = sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()
                local icon = (sfui.talents and sfui.talents.get_spec_icon and sfui.talents.get_spec_icon(curSpecID))
                    or "Interface\\Icons\\Spell_Nature_WispSplode"

                local groupIndex = g
                out[#out + 1] = {
                    id          = "spec_group_" .. g,
                    specID      = curSpecID,
                    specIndex   = groupIndex,
                    label       = labelText,
                    icon        = icon,
                    active      = isActive,
                    color       = isActive and { 1, 1, 1 } or { 0.8, 0.8, 0.8 },
                    insecure_func = function()
                        if InCombatLockdown and InCombatLockdown() then
                            if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                                _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
                            end
                            return
                        end
                        if isActive then return end
                        if SetActiveSpecGroup then
                            SetActiveSpecGroup(groupIndex)
                        end
                        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE then
                            PlaySound(SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE)
                        end
                    end,
                }
            end
        end
    end

    if #out == 0 then
        local curSpecID = sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()
        local name = (sfui.talents and sfui.talents.get_spec_name and sfui.talents.get_spec_name(curSpecID)) or "current spec"
        local icon = (sfui.talents and sfui.talents.get_spec_icon and sfui.talents.get_spec_icon(curSpecID)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        out[#out + 1] = {
            id          = "spec_current",
            specID      = curSpecID,
            label       = name:lower() .. " (current)",
            icon        = icon,
            active      = true,
            color       = { 1, 1, 1 },
            insecure_func = function() end,
        }
    end
end

sfui.ring.register_provider("specs", {
    name   = "specializations",
    title  = "specializations",
    events = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED",
        "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED",
        "PLAYER_ENTERING_WORLD",
    },
    build  = build_specs_ring,
})

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function()
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
    end)
end
