sfui = sfui or {}
sfui.is_ready_for_vendor_frame = false
SfuiDB = SfuiDB or {}


SLASH_SFUI1 = "/sfui"
SLASH_RL1 = "/rl"

local function UpdatePixelScale()
    local resolution = GetCVar("gxWindowedResolution")
    if resolution then
        local height = tonumber(string.match(resolution, "%d+x(%d+)"))
        if height then sfui.pixelScale = 768 / (height * UIParent:GetScale()) end
    end
end
sfui.UpdatePixelScale = UpdatePixelScale

-- Event frame for scale updates
local scale_event_frame = CreateFrame("Frame")
scale_event_frame:RegisterEvent("UI_SCALE_CHANGED")
scale_event_frame:SetScript("OnEvent", UpdatePixelScale)

function sfui.slash_command_handler(msg)
    if msg == "" then
        if sfui.toggle_options_panel then sfui.toggle_options_panel() else print("sfui: options panel not available.") end
    elseif msg == "research" then
        if sfui.research and sfui.research.ToggleSelection then
            sfui.research.ToggleSelection()
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

            if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then SfuiDB.barTexture = "Flat" end
            SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor
            SfuiDecorDB = SfuiDecorDB or {}
            SfuiDecorDB.items = SfuiDecorDB.items or {}

            SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false }
            SfuiDB.minimap_collect_buttons = (SfuiDB.minimap_collect_buttons == nil) and true or
                SfuiDB.minimap_collect_buttons
            SfuiDB.minimap_buttons_mouseover = (SfuiDB.minimap_buttons_mouseover == nil) and false or
                SfuiDB.minimap_buttons_mouseover
            if SfuiDB.autoSellGreys == nil then SfuiDB.autoSellGreys = false end
            if SfuiDB.autoRepair == nil then SfuiDB.autoRepair = false end
            if SfuiDB.disableMerchant == nil then SfuiDB.disableMerchant = true end
            if SfuiDB.disableVehicle == nil then SfuiDB.disableVehicle = false end




            if sfui.config and sfui.config.cvars_on_load then
                for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
                    C_CVar.SetCVar(cvar_data.name, cvar_data.value)
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if sfui.UpdatePixelScale then sfui.UpdatePixelScale() end

        if sfui.create_currency_frame then
            sfui.create_currency_frame()
        end
        if sfui.create_item_frame then
            sfui.create_item_frame()
        end
        if sfui.bars and sfui.bars.OnStateChanged then
            sfui.bars:OnStateChanged()
        end
        if sfui.warnings and sfui.warnings.Initialize then
            sfui.warnings.Initialize()
        end
        if sfui.research and sfui.research.Initialize then
            sfui.research.Initialize()
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
                        if sfui.research and sfui.research.ToggleSelection then
                            sfui.research.ToggleSelection()
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
