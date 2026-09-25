local addonName, addon = ...
sfui = sfui or {}
sfui.is_ready_for_vendor_frame = false

-- Localize Globals
local _G = _G
local print = print
local type = type
local tonumber = tonumber
local string_lower = string.lower
local string_match = string.match
local string_gmatch = string.gmatch

local CreateFrame = CreateFrame
local UIParent = UIParent
local IsShiftKeyDown = IsShiftKeyDown
local GetCVar = GetCVar
local C_CVar = C_CVar
local C_UI = C_UI
local C_AddOns = C_AddOns
local LibStub = LibStub

local function update_pixel_scale()
    local resolution = GetCVar("gxWindowedResolution")
    if resolution then
        local height = tonumber(string_match(resolution, "%d+x(%d+)"))
        if height then sfui.pixelScale = 768 / (height * UIParent:GetScale()) end
    end
end
sfui.update_pixel_scale = update_pixel_scale

-- Scale updates via central dispatcher
sfui.events.RegisterEvent("UI_SCALE_CHANGED", update_pixel_scale)

local isInitialized = false
local function initialize_sfui()
    if isInitialized then return end
    isInitialized = true

    if sfui.common and sfui.common.invalidate_panels_cache then
        sfui.common.invalidate_panels_cache()
    end
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        LSM:Register("statusbar", "Flat", "Interface/Buttons/WHITE8X8")
        LSM:Register("statusbar", "Blizzard", "Interface/TargetingFrame/UI-StatusBar")
        LSM:Register("statusbar", "Raid", "Interface/RaidFrame/Raid-Bar-Hp-Fill")
        LSM:Register("statusbar", "Spark", "Interface/CastingBar/UI-CastingBar-Spark")
    end

    -- Database & Config Sync
    SfuiDB = SfuiDB or {}
    SfuiDB.alts = SfuiDB.alts or {}
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}
    SfuiDB.minimap_icon = SfuiDB.minimap_icon or {}
    SfuiDB.gear = SfuiDB.gear or {}
    SfuiDB.gear_char = SfuiDB.gear_char or {}
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    SfuiDB.trackedOptionsWindow = SfuiDB.trackedOptionsWindow or {}
    SfuiDB.currencyCaps = SfuiDB.currencyCaps or {}
    SfuiDB.items = SfuiDB.items or {}
    SfuiDB.mythicBestTimes = SfuiDB.mythicBestTimes or {}
    SfuiDB.lootspec = SfuiDB.lootspec or {}
    SfuiDB.bonusroll = SfuiDB.bonusroll or {}
    SfuiDB.worldevents = SfuiDB.worldevents or {}
    SfuiDB.spec_colors = SfuiDB.spec_colors or {}
    SfuiDB.hearthstone = SfuiDB.hearthstone or {}

    SfuiDecorDB = SfuiDecorDB or {}
    SfuiDecorDB.items = SfuiDecorDB.items or {}

    if sfui.db and sfui.db.Initialize then
        sfui.db.Initialize()
    end
    if sfui.InitModules then
        sfui.InitModules()
    end

    if sfui.initialize_database then
        sfui.initialize_database()
    end

    -- Migrate cooldown panels to per-spec structure
    if sfui.common and sfui.common.migrate_cooldown_panels_to_spec then
        sfui.common.migrate_cooldown_panels_to_spec()
    end

    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    local tocVersion = getMeta and getMeta("sfui", "Version")
    if tocVersion then
        sfui.config.version = tocVersion
    end

    if sfui.config and sfui.config.cvars_on_load then
        local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
        if setCVar then
            for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
                if not getCVar or getCVar(cvar_data.name) ~= nil then
                    setCVar(cvar_data.name, cvar_data.value)
                end
            end
        end
    end

    -- Migrate legacy SCT CVars to _v2
    local legacyCVars = {
        "floatingCombatTextDodgeParryMiss",
        "floatingCombatTextDamageReduction",
        "floatingCombatTextEnergyGains",
        "floatingCombatTextAuras",
        "floatingCombatTextCombatState"
    }
    for _, legacy in ipairs(legacyCVars) do
        if SfuiDB[legacy] ~= nil then
            SfuiDB[legacy .. "_v2"] = SfuiDB[legacy]
            SfuiDB[legacy] = nil
        end
    end

    -- Enforce Combat Text Settings from DB
    local combatTextCVars = {
        "enableFloatingCombatText",
        "floatingCombatTextCombatDamage",
        "floatingCombatTextCombatLogPeriodicSpells",
        "floatingCombatTextCombatHealing",
        "floatingCombatTextPetMeleeDamage",
        "floatingCombatTextPetSpellDamage",
        "floatingCombatTextDodgeParryMiss_v2",
        "floatingCombatTextDamageReduction_v2",
        "floatingCombatTextEnergyGains_v2",
        "floatingCombatTextAuras_v2",
        "floatingCombatTextCombatState_v2"
    }
    local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
    local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    if setCVar then
        for _, cvar in ipairs(combatTextCVars) do
            if SfuiDB[cvar] ~= nil and (not getCVar or getCVar(cvar) ~= nil) then
                setCVar(cvar, SfuiDB[cvar] and "1" or "0")
            end
        end
    end
end

sfui.events.RegisterEvent("ADDON_LOADED", function(_, name)
    local lname = string_lower(name or "")
    if lname == "sfui" or lname == string_lower(addonName or "") then
        initialize_sfui()
    end
end)

-- Baganator-style check: If sfui has already finished loading, execute immediately
local isAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
if isAddOnLoaded and select(2, isAddOnLoaded(addonName or "sfui")) then
    initialize_sfui()
end

sfui.events.RegisterEvent("PLAYER_LOGIN", function(event)
    if sfui.update_pixel_scale then sfui.update_pixel_scale() end

    if sfui.EnableModules then
        sfui.EnableModules()
    end

    if sfui.common and sfui.common.hide_blizzard_cooldown_viewers then
        sfui.common.hide_blizzard_cooldown_viewers()
    end

    if sfui.create_currency_frame then
        sfui.create_currency_frame()
    end
    if sfui.create_item_frame then
        sfui.create_item_frame()
    end
    local function is_unregistered(modName)
        return not (sfui.modules and sfui.modules[modName])
    end

    if is_unregistered("bars") and sfui.bars and sfui.bars.on_state_changed then
        sfui.bars:on_state_changed()
    end
    if is_unregistered("castbar") and sfui.castbar and sfui.castbar.initialize then
        sfui.castbar.initialize()
    end
    if is_unregistered("compare") and sfui.compare and sfui.compare.init then
        sfui.compare.init()
    end
    if is_unregistered("gear") and sfui.gear and sfui.gear.initialize then
        sfui.gear.initialize()
    end
    if is_unregistered("hammer") and sfui.hammer and sfui.hammer.initialize then
        sfui.hammer.initialize()
    end
    if is_unregistered("research") and sfui.research and sfui.research.initialize then
        sfui.research.initialize()
    end
    if is_unregistered("automation") and sfui.automation and sfui.automation.initialize then
        sfui.automation.initialize()
    end
    if is_unregistered("cursor") and sfui.cursor and sfui.cursor.initialize then
        sfui.cursor.initialize()
    end
    if is_unregistered("trackedbars") and sfui.trackedbars and sfui.trackedbars.initialize then
        sfui.trackedbars.initialize()
    end
    if is_unregistered("trackedicons") and sfui.trackedicons and sfui.trackedicons.initialize then
        sfui.trackedicons.initialize()
    end
    if is_unregistered("trackedoptions") and sfui.trackedoptions and sfui.trackedoptions.initialize then
        sfui.trackedoptions.initialize()
    end
    if is_unregistered("alts") and sfui.alts and sfui.alts.initialize then
        sfui.alts.initialize()
    end
    if is_unregistered("portals") and sfui.portals and sfui.portals.initialize then
        sfui.portals.initialize()
    end
    if is_unregistered("lootspec") and sfui.lootspec and sfui.lootspec.initialize then
        sfui.lootspec.initialize()
    end
    if is_unregistered("lootviewer") and sfui.lootviewer and sfui.lootviewer.initialize then
        sfui.lootviewer.initialize()
    end
    if is_unregistered("lfg") and sfui.lfg and sfui.lfg.initialize then
        sfui.lfg.initialize()
    end
    if is_unregistered("questlog") and sfui.questlog and sfui.questlog.initialize then
        sfui.questlog.initialize()
    end



    if not LibStub then
        sfui.common.print("|cffff0000SFUI Error:|r LibStub global not found!")
        return
    end

    -- Initialize Minimap Menu
    if not SfuiMinimapMenu then
        local isRetail = (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)

        SfuiMinimapMenu = CreateFrame("Frame", "SfuiMinimapMenu", UIParent, "BackdropTemplate")
        SfuiMinimapMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        SfuiMinimapMenu:SetBackdropColor(0, 0, 0, 0.5)
        SfuiMinimapMenu:SetFrameStrata("TOOLTIP")
        SfuiMinimapMenu:SetClampedToScreen(true)

        local menuButtons = {
            {
                text = "|cff00ffffoptions|r",
                func = function() sfui.toggle_options_panel() end,
            },
            {
                text = "|cff00ff00tracking manager|r",
                func = function()
                    if sfui.trackedoptions and sfui.trackedoptions.toggle_viewer then
                        sfui.trackedoptions.toggle_viewer()
                    end
                end,
            },
            {
                text = "|cff9966ffalts|r",
                func = function()
                    if sfui.alts and sfui.alts.Toggle then
                        sfui.alts.Toggle()
                    end
                end,
            },
        }

        if isRetail then
            table.insert(menuButtons, {
                text = "|cffff9900portals|r",
                func = function()
                    if sfui.portals and sfui.portals.Toggle then
                        sfui.portals.Toggle()
                    end
                end,
            })
            table.insert(menuButtons, {
                text = "|cff22aaffloot browser|r",
                func = function()
                    if sfui.lootviewer and sfui.lootviewer.Toggle then
                        sfui.lootviewer.Toggle()
                    end
                end,
            })
        end

        if _G.C_PetJournal and _G.C_PetJournal.GetNumPets then
            table.insert(menuButtons, {
                text = "|cffff99ccpet manager|r",
                func = function()
                    if sfui.pets and sfui.pets.Toggle then
                        sfui.pets.Toggle()
                    elseif sfui.pets_ui and sfui.pets_ui.Toggle then
                        sfui.pets_ui.Toggle()
                    end
                end,
            })
        end

        table.insert(menuButtons, {
            text = "|cff6600ffmemory profiler|r",
            func = function()
                if sfui.mem and sfui.mem.ToggleGUI then
                    sfui.mem.ToggleGUI()
                end
            end,
        })

        local y = -5
        for _, item in ipairs(menuButtons) do
            local btn = sfui.common.create_flat_button(SfuiMinimapMenu, item.text, 150, 20)
            btn:SetPoint("TOP", 0, y)
            btn:SetScript("OnClick", function()
                SfuiMinimapMenu:Hide()
                if item.func then item.func() end
            end)
            y = y - 25
        end
        SfuiMinimapMenu:SetSize(160, -y + 5)

        local function on_menu_update(self, elapsed)
            self.throttle = self.throttle + elapsed
            if self.throttle < 0.5 then return end
            self.throttle = 0

            if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) then
                self.hideTimer = 0
            else
                self.hideTimer = (self.hideTimer or 0) + 0.5
                if self.hideTimer > 0.5 then
                    self:Hide()
                end
            end
        end

        SfuiMinimapMenu:SetScript("OnShow", function(self)
            self.throttle = 0
            self.hideTimer = 0
            self:SetScript("OnUpdate", on_menu_update)
        end)
        SfuiMinimapMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        SfuiMinimapMenu:Hide()
    end

    local ldb, icon = LibStub("LibDataBroker-1.1", true), LibStub("LibDBIcon-1.0", true)
    if ldb and icon then
        local broker = ldb:NewDataObject("sfui", {
            type = "launcher",
            text = "sfui",
            icon = sfui.config.appearance.addonIcon,
            OnClick = function(self, button)
                if button == "LeftButton" then
                    if SfuiMinimapMenu:IsShown() then
                        SfuiMinimapMenu:Hide()
                    else
                        SfuiMinimapMenu.anchor = self
                        SfuiMinimapMenu.throttle = 0
                        SfuiMinimapMenu.hideTimer = 0
                        SfuiMinimapMenu:ClearAllPoints()
                        SfuiMinimapMenu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -5)
                        SfuiMinimapMenu:Show()
                    end
                elseif button == "RightButton" then
                    if IsShiftKeyDown() then
                        if C_UI and C_UI.Reload then C_UI.Reload() elseif _G.ReloadUI then _G.ReloadUI() end
                    elseif sfui.alts and sfui.alts.Toggle then
                        sfui.alts.Toggle()
                    end
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("sfui")
                tooltip:AddLine("left-click for menu", 0.2, 1, 0.2)
                tooltip:AddLine("right-click for alts", 0.4, 0.7, 1)
                tooltip:AddLine("shift+right-click to reload ui", 1, 0.2, 0.2)
            end,
        })
        icon:Register("sfui", broker, SfuiDB.minimap_icon)
    end
end)
