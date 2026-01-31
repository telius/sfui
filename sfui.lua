sfui = sfui or {}
sfui.is_ready_for_vendor_frame = false
SfuiDB = SfuiDB or {}


SLASH_SFUI1 = "/sfui"
SLASH_RL1 = "/rl"

local function update_pixel_scale()
    local resolution = GetCVar("gxWindowedResolution")
    if resolution then
        local height = tonumber(string.match(resolution, "%d+x(%d+)"))
        if height then sfui.pixelScale = 768 / (height * UIParent:GetScale()) end
    end
end
sfui.update_pixel_scale = update_pixel_scale

-- Event frame for scale updates
local scale_event_frame = CreateFrame("Frame")
scale_event_frame:RegisterEvent("UI_SCALE_CHANGED")
scale_event_frame:SetScript("OnEvent", update_pixel_scale)

function sfui.slash_command_handler(msg)
    if msg == "" then
        if sfui.toggle_options_panel then sfui.toggle_options_panel() else print("sfui: options panel not available.") end
    elseif msg == "research" then
        if sfui.research and sfui.research.toggle_selection then
            sfui.research.toggle_selection()
        else
            print("sfui: research viewer not available.")
        end
    end
end

-- function to handle /rl slash command
function sfui.reload_ui_handler(msg)
    C_UI.Reload()
end

SlashCmdList["SFUI"] = sfui.slash_command_handler
SlashCmdList["RL"] = sfui.reload_ui_handler
local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("ADDON_LOADED")
event_frame:RegisterEvent("PLAYER_LOGIN")


event_frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if string.lower(name) == "sfui" then
            local LSM = LibStub("LibSharedMedia-3.0", true)
            if LSM then
                LSM:Register("statusbar", "Flat", "Interface/Buttons/WHITE8X8")
                LSM:Register("statusbar", "Blizzard", "Interface/TargetingFrame/UI-StatusBar")
                LSM:Register("statusbar", "Raid", "Interface/RaidFrame/Raid-Bar-Hp-Fill")
                LSM:Register("statusbar", "Spark", "Interface/CastingBar/UI-CastingBar-Spark")
            end

            -- Sync version from TOC to config (single source of truth)
            local tocVersion = C_AddOns.GetAddOnMetadata("sfui", "Version")
            if tocVersion then
                sfui.config.version = tocVersion
            end

            if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then SfuiDB.barTexture = "Flat" end
            SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor
            SfuiDecorDB = SfuiDecorDB or {}
            SfuiDecorDB.items = SfuiDecorDB.items or {}

            SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false }
            SfuiDB.minimap_collect_buttons = (SfuiDB.minimap_collect_buttons == nil) and true or
                SfuiDB.minimap_collect_buttons
            SfuiDB.minimap_buttons_mouseover = (SfuiDB.minimap_buttons_mouseover == nil) and false or
                SfuiDB.minimap_buttons_mouseover
            if SfuiDB.minimap_button_x == nil then SfuiDB.minimap_button_x = 0 end
            if SfuiDB.minimap_button_y == nil then SfuiDB.minimap_button_y = 35 end
            if SfuiDB.autoSellGreys == nil then SfuiDB.autoSellGreys = false end
            if SfuiDB.autoRepair == nil then SfuiDB.autoRepair = false end
            if SfuiDB.disableMerchant == nil then SfuiDB.disableMerchant = true end
            if SfuiDB.disableVehicle == nil then SfuiDB.disableVehicle = false end

            -- Bar settings
            if SfuiDB.healthBarX == nil then SfuiDB.healthBarX = 0 end
            if SfuiDB.healthBarY == nil then SfuiDB.healthBarY = 300 end
            if SfuiDB.enableHealthBar == nil then SfuiDB.enableHealthBar = true end
            if SfuiDB.enablePowerBar == nil then SfuiDB.enablePowerBar = true end
            if SfuiDB.enableSecondaryPowerBar == nil then SfuiDB.enableSecondaryPowerBar = true end
            if SfuiDB.enableVigorBar == nil then SfuiDB.enableVigorBar = true end
            if SfuiDB.enableMountSpeedBar == nil then SfuiDB.enableMountSpeedBar = true end

            -- Castbar settings
            if SfuiDB.castBarEnabled == nil then SfuiDB.castBarEnabled = sfui.config.castBar.enabled end
            if SfuiDB.castBarX == nil then SfuiDB.castBarX = sfui.config.castBar.pos.x end
            if SfuiDB.castBarY == nil then SfuiDB.castBarY = sfui.config.castBar.pos.y end
            sfui.config.castBar.enabled = SfuiDB.castBarEnabled
            sfui.config.castBar.pos.x = SfuiDB.castBarX
            sfui.config.castBar.pos.y = SfuiDB.castBarY

            if SfuiDB.targetCastBarEnabled == nil then SfuiDB.targetCastBarEnabled = sfui.config.targetCastBar.enabled end
            if SfuiDB.targetCastBarX == nil then SfuiDB.targetCastBarX = sfui.config.targetCastBar.pos.x end
            if SfuiDB.targetCastBarY == nil then SfuiDB.targetCastBarY = sfui.config.targetCastBar.pos.y end
            sfui.config.targetCastBar.enabled = SfuiDB.targetCastBarEnabled
            sfui.config.targetCastBar.pos.x = SfuiDB.targetCastBarX
            sfui.config.targetCastBar.pos.y = SfuiDB.targetCastBarY

            if SfuiDB.enableReminders == nil then SfuiDB.enableReminders = true end
            if SfuiDB.remindersX == nil then SfuiDB.remindersX = 0 end
            if SfuiDB.remindersY == nil then SfuiDB.remindersY = 10 end
            if SfuiDB.remindersSolo == nil then SfuiDB.remindersSolo = false end
            if SfuiDB.remindersEverywhere == nil then SfuiDB.remindersEverywhere = false end
            if SfuiDB.enablePetWarning == nil then SfuiDB.enablePetWarning = true end
            if SfuiDB.enableRuneWarning == nil then SfuiDB.enableRuneWarning = true end

            -- automation settings
            if SfuiDB.auto_role_check == nil then SfuiDB.auto_role_check = true end
            if SfuiDB.auto_sign_lfg == nil then SfuiDB.auto_sign_lfg = true end




            if sfui.config and sfui.config.cvars_on_load then
                for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
                    C_CVar.SetCVar(cvar_data.name, cvar_data.value)
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if sfui.update_pixel_scale then sfui.update_pixel_scale() end

        if sfui.create_currency_frame then
            sfui.create_currency_frame()
        end
        if sfui.create_item_frame then
            sfui.create_item_frame()
        end
        if sfui.bars and sfui.bars.on_state_changed then
            sfui.bars:on_state_changed()
        end
        if sfui.research and sfui.research.initialize then
            sfui.research.initialize()
        end
        if sfui.reminders and sfui.reminders.initialize then
            sfui.reminders.initialize()
        end
        if sfui.automation and sfui.automation.initialize then
            sfui.automation.initialize()
        end

        local ldb, icon = LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
        if ldb and icon then
            local broker = ldb:NewDataObject("sfui", {
                type = "launcher",
                text = "sfui",
                icon = "Interface\\Icons\\Spell_shadow_deathcoil",
                OnClick = function(_, button)
                    if button == "LeftButton" then
                        sfui.toggle_options_panel()
                    elseif button == "RightButton" then
                        C_UI.Reload()
                    elseif button == "MiddleButton" then
                        if sfui.research and sfui.research.toggle_selection then
                            sfui.research.toggle_selection()
                        end
                    end
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine("sfui")
                    tooltip:AddLine("Left-click to toggle options", 0.2, 1, 0.2)
                    tooltip:AddLine("Middle-click to toggle Research Viewer", 0.2, 0.6, 1)
                    tooltip:AddLine("Right-click to Reload UI", 1, 0.2, 0.2)
                end,
            })
            icon:Register("sfui", broker, SfuiDB.minimap_icon)
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
