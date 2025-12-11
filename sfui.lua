-- sfui by teli

-- addon table for scope
sfui = sfui or {}

-- We ensure the table exists at the global scope.
-- This guarantees that SfuiDB is available when other files (like options.lua) are parsed.
SfuiDB = SfuiDB or {}

-- register slash command global variable (required by wow api)
SLASH_SFUI1 = "/sfui"
SLASH_RL1 = "/rl" -- New reload clash command

-- function to handle /sfui slash commands
function sfui.slash_command_handler(msg)
    if msg == "" then
        if sfui.toggle_options_panel then
            sfui.toggle_options_panel()
        else
            print("sfui: options panel not available.")
        end
    end
    -- you can add more commands here later, like /sfui help
end

-- function to handle /rl slash command
function sfui.reload_ui_handler(msg)
    C_UI.Reload()
end

-- register the slash command handlers (required by wow api)
SlashCmdList["SFUI"] = sfui.slash_command_handler
SlashCmdList["RL"] = sfui.reload_ui_handler -- Register the reload command

-- frame to listen for events
local event_frame = CreateFrame("Frame")
event_frame:RegisterEvent("ADDON_LOADED")
event_frame:RegisterEvent("PLAYER_LOGIN")

event_frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name == "sfui" then
            -- Register SharedMedia
            local LSM = LibStub("LibSharedMedia-3.0", true)
            if LSM then
                LSM:Register("statusbar", "Flat", "Interface/Buttons/WHITE8X8")
                LSM:Register("statusbar", "Blizzard", "Interface/TargetingFrame/UI-StatusBar")
                LSM:Register("statusbar", "Raid", "Interface/RaidFrame/Raid-Bar-Hp-Fill")
                LSM:Register("statusbar", "Spark", "Interface/CastingBar/UI-CastingBar-Spark")
            end

            -- Initialize DB
            if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then
                SfuiDB.barTexture = "Flat"
            end
            SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor

            SfuiDB.minimap_auto_zoom = SfuiDB.minimap_auto_zoom or sfui.config.minimap.auto_zoom
            SfuiDB.minimap_square = SfuiDB.minimap_square or sfui.config.minimap.square
            SfuiDB.minimap_collect_buttons = SfuiDB.minimap_collect_buttons or sfui.config.minimap.collect_buttons
            SfuiDB.minimap_masque = SfuiDB.minimap_masque or sfui.config.minimap.masque
            SfuiDB.minimap_rearrange = SfuiDB.minimap_rearrange or false
            SfuiDB.minimap_button_order = SfuiDB.minimap_button_order or {}
            SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false } -- Reset to original (no x,y)

            -- Set CVars on load
            if sfui.config and sfui.config.cvars_on_load then
                for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
                    C_CVar.SetCVar(cvar_data.name, cvar_data.value)
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        -- Create all our UI elements now that the player is in the world.
        if sfui.create_options_panel then
            sfui.create_options_panel()
        end
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

        local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
        local icon = LibStub:GetLibrary("LibDBIcon-1.0", true)
        if ldb and icon then
            local broker = ldb:NewDataObject("sfui", {
                type = "launcher",
                text = "sfui",
                icon = "Interface\\Icons\\Spell_shadow_deathcoil", -- Death Coil (Shadow) icon path
                OnClick = function(_, button)
                    if button == "LeftButton" then
                        sfui.toggle_options_panel()
                    elseif button == "RightButton" then
                        C_UI.Reload()
                    end
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine("sfui")
                    tooltip:AddLine("Left-click to toggle options", 0.2, 1, 0.2)
                    tooltip:AddLine("Right-click to Reload UI", 1, 0.2, 0.2)
                end,
            })
            icon:Register("sfui", broker, SfuiDB.minimap_icon)
        else
            print("sfui: LibDataBroker-1.1 or LibDBIcon-1.0 not loaded (LibDBIcon registration).")
        end
        -- We only need this event once per session.
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)