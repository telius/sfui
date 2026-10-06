local addonName, addon = ...
sfui = sfui or {}
sfui.lootviewer = sfui.lootviewer or {}
sfui.is_ready_for_vendor_frame = false

function sfui.ToggleLootViewer()
    if not sfui.isRetail and sfui.lootviewer_camelot and sfui.lootviewer_camelot.Toggle then
        sfui.lootviewer_camelot.Toggle()
    elseif sfui.lootviewer and sfui.lootviewer.Toggle and sfui.lootviewer.Toggle ~= sfui.ToggleLootViewer then
        sfui.lootviewer.Toggle()
    end
end

if not sfui.lootviewer.Toggle then
    sfui.lootviewer.Toggle = function()
        sfui.ToggleLootViewer()
    end
end

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

    sfui.common.invalidate_panels_cache()
    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        if sfui.config.blizzard_bar_textures then
            for name, path in pairs(sfui.config.blizzard_bar_textures) do
                local isAtlas = type(path) == "string" and not path:find("^[iI]nterface[/\\]")
                if not isAtlas or (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(path)) then
                    LSM:Register("statusbar", name, path)
                end
            end
        else
            LSM:Register("statusbar", "Flat", "Interface/Buttons/WHITE8X8")
            LSM:Register("statusbar", "Blizzard", "Interface/TargetingFrame/UI-StatusBar")
            LSM:Register("statusbar", "Blizzard Target Bar", "Interface/TargetingFrame/UI-TargetingFrame-BarFill")
            LSM:Register("statusbar", "Blizzard Character Skills Bar", "Interface/PaperDollInfoFrame/UI-Character-Skills-Bar")
            LSM:Register("statusbar", "Blizzard Raid Bar", "Interface/RaidFrame/Raid-Bar-Hp-Fill")
            LSM:Register("statusbar", "Blizzard Raid Resource", "Interface/RaidFrame/Raid-Bar-Resource-Fill")
            LSM:Register("statusbar", "Blizzard Raid Health", "Interface/RaidFrame/UI-RaidFrame-HealthBar")
            LSM:Register("statusbar", "Blizzard Shield Fill", "Interface/RaidFrame/Shield-Fill")
            LSM:Register("statusbar", "Blizzard Absorb Fill", "Interface/RaidFrame/Absorb-Fill")
            LSM:Register("statusbar", "Blizzard Professions", "Interface/Spellbook/Professions-Progress-Fill")
            LSM:Register("statusbar", "Blizzard Archaeology", "Interface/Archeology/Arch-Progress-Fill")
        end
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
    if sfui.isRetail then
        SfuiDB.mythicBestTimes = SfuiDB.mythicBestTimes or {}
        SfuiDB.lootspec = SfuiDB.lootspec or {}
        SfuiDB.bonusroll = SfuiDB.bonusroll or {}
        SfuiDB.worldevents = SfuiDB.worldevents or {}
    end
    SfuiDB.spec_colors = SfuiDB.spec_colors or {}
    -- Migration: Purge legacy blue or interim orange for Balance Druid (102 and 14841) so it defaults to Moonfire
    for _, sID in ipairs({ 102, 14841 }) do
        local c = SfuiDB.spec_colors[sID]
        if c then
            local r, g, b = c[1] or c.r or 0, c[2] or c.g or 0, c[3] or c.b or 0
            local isLegacyBlue = (r >= 0.18 and r <= 0.22) and (g <= 0.05) and (b >= 0.78 and b <= 0.82)
            local isInterimOrange = (r >= 0.98) and (g >= 0.45 and g <= 0.53) and (b <= 0.06)
            if isLegacyBlue or isInterimOrange then
                SfuiDB.spec_colors[sID] = nil
            end
        end
    end
    SfuiDB.hearthstone = SfuiDB.hearthstone or {}

    sfui.db.Initialize()
    sfui.InitModules()

    sfui.initialize_database()
    sfui.theme.ApplyCurrentTheme()

    -- Migrate cooldown panels to per-spec structure
    sfui.common.migrate_cooldown_panels_to_spec()

    local tocVersion = sfui.common.get_addon_metadata(addonName or "sfui", "Version")
    if tocVersion then
        sfui.config.version = tocVersion
    end

    if sfui.config.cvars_on_load then
        for _, cvar_data in ipairs(sfui.config.cvars_on_load) do
            if sfui.common and sfui.common.set_cvar then
                sfui.common.set_cvar(cvar_data.name, cvar_data.value)
            elseif (not InCombatLockdown or not InCombatLockdown()) then
                local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
                local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
                if setCVar and (not getCVar or getCVar(cvar_data.name) ~= nil) then
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
    for _, cvar in ipairs(combatTextCVars) do
        if SfuiDB[cvar] ~= nil then
            if sfui.common and sfui.common.set_cvar then
                sfui.common.set_cvar(cvar, SfuiDB[cvar] and "1" or "0")
            elseif (not InCombatLockdown or not InCombatLockdown()) then
                local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
                local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
                if setCVar and (not getCVar or getCVar(cvar) ~= nil) then
                    setCVar(cvar, SfuiDB[cvar] and "1" or "0")
                end
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
    sfui.update_pixel_scale()

    sfui.EnableModules()

    sfui.common.hide_blizzard_cooldown_viewers()

    sfui.create_currency_frame()
    sfui.create_item_frame()
    local function is_unregistered(modName)
        return not (sfui.modules and sfui.modules[modName])
    end

    local isRetail = sfui.isRetail
    if is_unregistered("bars") then
        sfui.bars:on_state_changed()
    end
    if is_unregistered("castbar") or not sfui.castbar.bars then
        sfui.castbar.initialize()
    end
    if is_unregistered("compare") then
        sfui.compare.init()
    end
    if is_unregistered("gear") then
        sfui.gear.initialize()
    end
    if isRetail and is_unregistered("hammer") then
        sfui.hammer.initialize()
    end
    if isRetail and is_unregistered("research") then
        sfui.research.initialize()
    end
    if is_unregistered("automation") then
        sfui.automation.initialize()
    end
    if is_unregistered("cursor") then
        sfui.cursor.initialize()
    end
    if is_unregistered("trackedbars") then
        sfui.trackedbars.initialize()
    end
    if is_unregistered("trackedicons") then
        sfui.trackedicons.initialize()
    end
    if is_unregistered("trackedoptions") then
        sfui.trackedoptions.initialize()
    end
    if is_unregistered("alts") then
        sfui.alts.initialize()
    end
    if isRetail and is_unregistered("portals") then
        sfui.portals.initialize()
    end
    if isRetail and is_unregistered("lootspec") then
        sfui.lootspec.initialize()
    end
    if is_unregistered("lootviewer") and sfui.lootviewer and sfui.lootviewer.initialize then
        sfui.lootviewer.initialize()
    end
    if is_unregistered("questlog") then
        sfui.questlog.initialize()
    end

    if not LibStub then
        sfui.common.print("|cffff0000error:|r libstub global not found!")
        return
    end

    -- Initialize Minimap Menu
    if not SfuiMinimapMenu then
        SfuiMinimapMenu = CreateFrame("Frame", "SfuiMinimapMenu", UIParent, "BackdropTemplate")
        SfuiMinimapMenu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        SfuiMinimapMenu:SetBackdropColor(0, 0, 0, 0.5)
        SfuiMinimapMenu:SetFrameStrata("TOOLTIP")
        SfuiMinimapMenu:SetClampedToScreen(true)

        local menuButtons = {
            {
                text = "|cffffffffoptions|r",
                func = function() sfui.toggle_options_panel() end,
            },
            {
                text = "|cff00ff00tracking manager|r",
                func = function()
                    sfui.trackedoptions.toggle_viewer()
                end,
            },
            {
                text = "|cff9966ffalts|r",
                func = function()
                    sfui.alts.Toggle()
                end,
            },
        }

        if isRetail and sfui.portals then
            table.insert(menuButtons, {
                text = "|cffff9900portals|r",
                func = function()
                    sfui.portals.Toggle()
                end,
            })
        end

        if isRetail and sfui.lootviewer and sfui.lootviewer.Toggle then
            table.insert(menuButtons, {
                text = "|cff22aaffloot browser|r",
                func = function()
                    sfui.lootviewer.Toggle()
                end,
            })
        elseif not isRetail and sfui.lootviewer_camelot and sfui.lootviewer_camelot.Toggle then
            table.insert(menuButtons, {
                text = "|cffd1a652dungeon journal|r",
                func = function()
                    sfui.lootviewer_camelot.Toggle()
                end,
            })
        end

        if _G.C_PetJournal and _G.C_PetJournal.GetNumPets then
            table.insert(menuButtons, {
                text = "|cffff99ccpet manager|r",
                func = function()
                    sfui.pets.Toggle()
                end,
            })
        end

        table.insert(menuButtons, {
            text = "|cff6600ffmemory profiler|r",
            func = function()
                sfui.mem.ToggleGUI()
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
                    else
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
