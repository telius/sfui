local addonName, addon = ...
sfui = sfui or {}
sfui.commands = sfui.commands or {}
sfui.keybinds = sfui.keybinds or {}

-- Localize Globals
local _G = _G
local tostring = tostring
local C_UI = C_UI

-- ────────────────────────────────────────────────────────────────────────────
-- 1. BLIZZARD KEYBINDINGS MENU DEFINITIONS & DYNAMIC FILTERING
-- ────────────────────────────────────────────────────────────────────────────
BINDING_HEADER_SFUI = "SFUI"
_G["BINDING_NAME_SFUI_PORTALS"] = "portals"

if not sfui.isRetail then
    _G["BINDING_NAME_CLICK SfuiClassUtilityBtn:LeftButton"] = "class utility (totems / shards)"
    _G["BINDING_NAME_CLICK SfuiTriageDeleteBtn:LeftButton"] = "triage: delete / purge active item"
    _G["BINDING_NAME_CLICK SfuiPurgeSoulShards:LeftButton"] = "purge excess soul shards"
    _G["BINDING_NAME_SFUI_LOOTVIEWER"] = "dungeon journal"
else
    _G["BINDING_NAME_SFUI_LOOTVIEWER"] = "loot browser"
end

_G["BINDING_NAME_CLICK SfuiHammerPopup:LeftButton"] = "master's hammer repair"
_G["BINDING_NAME_SFUI_MATCHMOUNT"] = "match target mount"
_G["BINDING_NAME_SFUI_ALTS"] = "alts / warband"
_G["BINDING_NAME_SFUI_FISHING"] = "cast & catch fishing"
_G["BINDING_NAME_SFUI_PET_SUMMON"] = "summon / rotate companion pet"
_G["BINDING_NAME_CLICK SfuiRing_specs:LeftButton"]         = "ring: specializations"
_G["BINDING_NAME_CLICK SfuiRing_targetmarkers:LeftButton"] = "ring: target markers"
_G["BINDING_NAME_CLICK SfuiRing_worldmarkers:LeftButton"]  = "ring: world markers"
_G["BINDING_NAME_CLICK SfuiRing_professions:LeftButton"]   = "ring: professions"
_G["BINDING_NAME_CLICK SfuiRing_questitems:LeftButton"]    = "ring: quest items"
_G["BINDING_NAME_CLICK SfuiRing_tracking:LeftButton"]      = "ring: minimap tracking"
_G["BINDING_NAME_CLICK SfuiRing_utility:LeftButton"]       = "ring: class utility & custom"

-- Dynamic filter for Blizzard Keybindings Settings UI:
-- - On Retail: exclude class utility (camelot/classic only)
-- - On Camelot: single class utility keybind (purge legacy totem/shard actions)
-- - Universal: remove deprecated pet manager and duplicate portal bindings
local function filter_sfui_keybindings()
    if not _G.Settings or not _G.Settings.KEYBINDINGS_CATEGORY_ID or not _G.SettingsPanel then return end
    local kbCategory = _G.SettingsPanel:GetCategory(_G.Settings.KEYBINDINGS_CATEGORY_ID)
    if not kbCategory then return end
    local layout = (_G.SettingsPanel.GetLayout and _G.SettingsPanel:GetLayout(kbCategory)) or (kbCategory.GetLayout and kbCategory:GetLayout())
    if not layout or not layout.GetInitializers then return end
    local initializers = layout:GetInitializers()
    if not initializers then return end

    for _, init in ipairs(initializers) do
        if init.data and (init.data.name == "SFUI" or init.data.name == _G.BINDING_HEADER_SFUI) then
            local list = init.data.bindingsCategories
            if list then
                for i = #list, 1, -1 do
                    local entry = list[i]
                    local action = entry and entry[2]
                    if action then
                        if sfui.isRetail and (action:find("SfuiClassUtilityBtn") or action:find("SfuiTotem") or action:find("PurgeSoulShards")) then
                            table.remove(list, i)
                        elseif action:find("SfuiTotemSequenceBtn") or action:find("SfuiPurgeSoulShards") then
                            table.remove(list, i)
                        elseif action == "SFUI_PET_MANAGER" or action:find("SfuiPortalsBtn") or action == "SFUI_PORTALS_CAMELOT" or action == "BETTERFISHINGKEY" then
                            table.remove(list, i)
                        end
                    end
                end
            end
        end
    end
end

local settingsHooked = false
local function try_hook_settings()
    if settingsHooked then return end
    if _G.SettingsPanel and _G.SettingsPanel.HookScript then
        _G.SettingsPanel:HookScript("OnShow", function()
            pcall(filter_sfui_keybindings)
        end)
        settingsHooked = true
    end
    if _G.EventRegistry and _G.EventRegistry.RegisterCallback then
        _G.EventRegistry:RegisterCallback("Settings.CategoryChanged", function(_, category)
            if category and _G.Settings and category:GetID() == _G.Settings.KEYBINDINGS_CATEGORY_ID then
                pcall(filter_sfui_keybindings)
            end
        end, "SFUI_FilterKeybindings")
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", try_hook_settings)
end
try_hook_settings()

-- ────────────────────────────────────────────────────────────────────────────
-- 2. SLASH COMMAND HANDLERS
-- ────────────────────────────────────────────────────────────────────────────

-- Quick UI Reload (/rl)
SLASH_RL1 = "/rl"
SlashCmdList["RL"] = function()
    C_UI.Reload()
end

-- Memory Profiler & Garbage Collection (/sfmem)
SLASH_SFMEM1 = "/sfmem"
SlashCmdList["SFMEM"] = function(msg)
    if sfui.mem and sfui.mem.HandleSlash then
        sfui.mem.HandleSlash(msg)
    end
end

-- CPU Profiler (/sfcpu [seconds])
SLASH_SFCPU1 = "/sfcpu"
SlashCmdList["SFCPU"] = function(msg)
    if sfui.mem and sfui.mem.StartCPUWatcher then
        sfui.mem.StartCPUWatcher(msg)
    end
end

-- Master SFUI Options & Command Router (/sfui)
SLASH_SFUI1 = "/sfui"
SlashCmdList["SFUI"] = function(msg)
    local raw = msg and _G.strtrim and _G.strtrim(msg) or (msg or "")
    local clean = raw:lower()
    local cmd, arg = clean:match("^(%S+)%s*(.*)$")
    cmd = cmd or clean

    if cmd == "" or cmd == "options" or cmd == "opt" or cmd == "config" or cmd == "menu" then
        if sfui.toggle_options_panel then
            sfui.toggle_options_panel(arg ~= "" and arg or nil)
        end
    elseif cmd == "reload" or cmd == "popup" or cmd == "reloadpopup" then
        if sfui.hide and sfui.hide.ShowEditModeReloadPopup then
            sfui.hide.ShowEditModeReloadPopup()
        end
    elseif cmd == "mem" or cmd == "memory" or cmd == "gc" then
        if sfui.mem and sfui.mem.HandleSlash then
            sfui.mem.HandleSlash((cmd == "gc" and "gc") or arg)
        end
    elseif cmd == "portals" or cmd == "portal" or cmd == "teleport" or cmd == "tp" then
        if sfui.portals and sfui.portals.Toggle then
            sfui.portals.Toggle()
        end
    elseif cmd == "recipes" or cmd == "recipe" or cmd == "professions" or cmd == "prof" then
        if sfui.recipes and sfui.recipes.ToggleBrowser then
            sfui.recipes.ToggleBrowser(arg ~= "" and arg or nil)
        end
    elseif cmd == "fish" or cmd == "fishing" or cmd == "atlas" then
        if not sfui.isRetail and (arg == "atlas" or arg == "book" or cmd == "atlas") then
            if sfui.fishing and sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        elseif arg == "hud" then
            if sfui.fishing and sfui.fishing.hud and sfui.fishing.hud.CheckVisibility then
                SfuiDB = SfuiDB or {}
                SfuiDB.fishing = SfuiDB.fishing or {}
                SfuiDB.fishing.hud = SfuiDB.fishing.hud or {}
                SfuiDB.fishing.hud.enabled = not SfuiDB.fishing.hud.enabled
                sfui.fishing.hud.CheckVisibility()
                if sfui.common and sfui.common.print then
                    sfui.common.print("fishing hud: " .. (SfuiDB.fishing.hud.enabled and "enabled" or "disabled"))
                end
            end
        elseif arg == "reset" then
            if sfui.fishing and sfui.fishing.ResetSession then
                sfui.fishing.ResetSession()
            end
        elseif sfui.toggle_options_panel then
            sfui.toggle_options_panel("fishing")
        end
    elseif cmd == "mail" or cmd == "mailrouting" or cmd == "altmail" then
        if sfui.alts and sfui.alts.ToggleMailConfig then
            sfui.alts.ToggleMailConfig()
        end
    elseif cmd == "lead" or cmd == "makelead" then
        if sfui.sync and sfui.sync.MakeMeLead then
            sfui.sync.MakeMeLead()
        end
    elseif cmd == "party" or cmd == "formparty" or cmd == "invite" then
        if sfui.sync and sfui.sync.FormSyncedParty then
            sfui.sync.FormSyncedParty()
        end
    elseif cmd == "reloadall" or cmd == "rlall" then
        if sfui.sync and sfui.sync.ReloadAllClients then
            sfui.sync.ReloadAllClients()
        end
    elseif cmd == "away" or cmd == "pause" then
        if sfui.sync and sfui.sync.ToggleAway then
            sfui.sync.ToggleAway(arg ~= "" and arg or nil)
        end
    elseif cmd == "sync" or cmd == "multibox" then
        if arg == "now" or arg == "all" then
            if sfui.sync and sfui.sync.SyncAllNow then sfui.sync.SyncAllNow() end
        elseif arg == "invite" or arg == "form" then
            if sfui.sync and sfui.sync.FormSyncedParty then sfui.sync.FormSyncedParty() end
        elseif arg == "reload" or arg == "rl" then
            if sfui.sync and sfui.sync.ReloadAllClients then sfui.sync.ReloadAllClients() end
        elseif arg == "target" then
            if sfui.sync and sfui.sync.PairWithTarget then sfui.sync.PairWithTarget() end
        elseif arg == "party" or arg == "group" then
            if sfui.sync and sfui.sync.PairWithParty then sfui.sync.PairWithParty() end
        elseif arg and arg ~= "" then
            if sfui.sync and sfui.sync.PairWithCharacter then sfui.sync.PairWithCharacter(arg) end
        elseif sfui.toggle_options_panel then
            sfui.toggle_options_panel("sync")
        end
    elseif cmd == "pet" or cmd == "pets" or cmd == "sfpet" then
        if arg and arg ~= "" and _G.SlashCmdList and _G.SlashCmdList["SFPET"] then
            _G.SlashCmdList["SFPET"](arg)
        elseif sfui.toggle_options_panel then
            sfui.toggle_options_panel("pets")
        end
    elseif cmd == "totembar" or cmd == "totems" then
        if not sfui.isRetail and sfui.totembar and sfui.totembar.ToggleUnlock then
            sfui.totembar.ToggleUnlock()
        end
    elseif cmd == "shards" or cmd == "shard" then
        if sfui.triage and sfui.triage.CheckSoulShards then
            sfui.triage.CheckSoulShards()
        end
    elseif cmd == "move" or cmd == "unlock" or cmd == "edit" then
        if sfui.movers and sfui.movers.Toggle then
            sfui.movers.Toggle(true)
        elseif sfui.actionbars and sfui.actionbars.ToggleMovers then
            sfui.actionbars.ToggleMovers(true)
        end
    elseif cmd == "lock" then
        if sfui.movers and sfui.movers.Toggle then
            sfui.movers.Toggle(false)
        elseif sfui.actionbars and sfui.actionbars.ToggleMovers then
            sfui.actionbars.ToggleMovers(false)
        end
    elseif cmd == "ring" or cmd == "rings" then
        if arg == "target" or arg == "markers" then
            if sfui.ring and sfui.ring.live and sfui.ring.live.open then sfui.ring.live.open("targetmarkers") end
        elseif arg == "world" or arg == "flares" then
            if sfui.ring and sfui.ring.live and sfui.ring.live.open then sfui.ring.live.open("worldmarkers") end
        elseif arg == "prof" or arg == "professions" then
            if sfui.ring and sfui.ring.live and sfui.ring.live.open then sfui.ring.live.open("professions") end
        elseif arg == "quest" or arg == "quests" or arg == "items" then
            if sfui.ring and sfui.ring.live and sfui.ring.live.open then sfui.ring.live.open("questitems") end
        elseif arg == "track" or arg == "tracking" or arg == "minimap" then
            if sfui.ring and sfui.ring.live and sfui.ring.live.open then sfui.ring.live.open("tracking") end
        elseif sfui.toggle_options_panel then
            sfui.toggle_options_panel("ring")
        end
    elseif cmd == "theme" or cmd == "themes" or cmd == "style" then
        if arg and arg ~= "" then
            local targetTheme = arg:lower():gsub("%s+", "")
            if sfui.theme and sfui.theme.SetTheme then
                if sfui.theme.IsThemeAvailable and not sfui.theme.IsThemeAvailable(targetTheme) then
                    if sfui.common and sfui.common.print then
                        sfui.common.print("theme '" .. arg .. "' is not available on this client.")
                    end
                else
                    sfui.theme.SetTheme(targetTheme)
                    local pal = sfui.theme.GetPalette and sfui.theme.GetPalette()
                    if sfui.common and sfui.common.print then
                        sfui.common.print("theme mode set to '" .. targetTheme .. "' (active: " .. tostring(pal and pal.name or targetTheme):lower() .. ").")
                    end
                end
            end
        elseif sfui.toggle_options_panel then
            sfui.toggle_options_panel("theme")
        end
    elseif cmd == "bug" or cmd == "bugs" or cmd == "errors" then
        if _G.SlashCmdList and _G.SlashCmdList["SFUIBUG"] then
            _G.SlashCmdList["SFUIBUG"](arg or "")
        elseif sfui.common and sfui.common.print then
            sfui.common.print("sfuibug companion addon is not loaded.")
        end
    elseif cmd == "rl" or cmd == "reload" then
        C_UI.Reload()
    elseif cmd == "help" or cmd == "?" then
        if sfui.common and sfui.common.print then
            if sfui.isRetail then
                sfui.common.print("commands: /sfui [tab] | /sfui edit | /sfui theme [mode] | /sfui portals | /sfmem | /rl")
            else
                sfui.common.print("commands: /sfui [tab] | /sfui edit | /sfui theme [mode] | /sfui recipes | /sfui portals | /sfui shards | /sfmem | /rl | /totembar")
            end
        end
    else
        -- If a tab name was specified (e.g. /sfui experience, /sfui bars, /sfui theme), open options directly to that tab
        if sfui.toggle_options_panel then
            sfui.toggle_options_panel(cmd)
        elseif sfui.common and sfui.common.print then
            sfui.common.print("unknown command: /sfui " .. tostring(cmd) .. ". type /sfui for options.")
        end
    end
end

-- Dedicated Theme Slash Command (/sftheme [mode])
SLASH_SFUITHEME1 = "/sftheme"
SlashCmdList["SFUITHEME"] = function(msg)
    local target = msg and _G.strtrim and _G.strtrim(msg) or (msg or "")
    if target ~= "" then
        _G.SlashCmdList["SFUI"]("theme " .. target)
    else
        _G.SlashCmdList["SFUI"]("theme")
    end
end

-- Dedicated Portals & Teleports Slash Command (/portals, /sfportals)
SLASH_SFUIPORTALS1 = "/sfportals"
SLASH_SFUIPORTALS2 = "/portals"
SlashCmdList["SFUIPORTALS"] = function()
    if sfui.portals and sfui.portals.Toggle then
        sfui.portals.Toggle()
    end
end

-- Dedicated Recipe Catalogue Slash Command (/recipes, /sfrecipes) (Camelot only)
if not sfui.isRetail then
    SLASH_SFUIRECIPES1 = "/sfrecipes"
    SLASH_SFUIRECIPES2 = "/recipes"
    SlashCmdList["SFUIRECIPES"] = function(msg)
        if sfui.recipes and sfui.recipes.ToggleBrowser then
            local raw = msg and _G.strtrim and _G.strtrim(msg) or (msg or "")
            sfui.recipes.ToggleBrowser(raw ~= "" and raw or nil)
        end
    end

    -- Dedicated Fishing Atlas Slash Command (/sffish, /fishing) (Camelot only)
    SLASH_SFUIFISHING1 = "/sffish"
    SLASH_SFUIFISHING2 = "/fishing"
    SlashCmdList["SFUIFISHING"] = function(msg)
        local raw = msg and _G.strtrim and _G.strtrim(msg) or (msg or "")
        local clean = raw:lower()
        if clean == "hud" then
            SfuiDB = SfuiDB or {}
            SfuiDB.fishing = SfuiDB.fishing or {}
            SfuiDB.fishing.hud = SfuiDB.fishing.hud or {}
            SfuiDB.fishing.hud.enabled = not SfuiDB.fishing.hud.enabled
            if sfui.fishing and sfui.fishing.hud and sfui.fishing.hud.CheckVisibility then
                sfui.fishing.hud.CheckVisibility()
            end
            if sfui.common and sfui.common.print then
                sfui.common.print("fishing hud: " .. (SfuiDB.fishing.hud.enabled and "enabled" or "disabled"))
            end
        elseif clean == "lock" or clean == "unlock" then
            if sfui.fishing and sfui.fishing.hud and sfui.fishing.hud.ToggleLock then
                local locked = sfui.fishing.hud.ToggleLock()
                if sfui.common and sfui.common.print then
                    sfui.common.print("fishing hud: " .. (locked and "locked" or "unlocked (draggable)"))
                end
            end
        elseif clean == "reset" then
            if sfui.fishing and sfui.fishing.ResetSession then
                sfui.fishing.ResetSession()
            end
        elseif clean == "opt" or clean == "options" or clean == "config" then
            if sfui.toggle_options_panel then
                sfui.toggle_options_panel("fishing")
            end
        else
            if sfui.fishing and sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
                sfui.fishing.atlas.Toggle()
            end
        end
    end
end

-- Totem Bar Unlock & Move (/totembar) (Vanilla / Camelot only)
if not sfui.isRetail then
    SLASH_SFUITOTEM1 = "/totembar"
    SLASH_SFUITOTEM2 = "/sftotems"
    SlashCmdList["SFUITOTEM"] = function()
        if sfui.totembar and sfui.totembar.ToggleUnlock then
            sfui.totembar.ToggleUnlock()
        end
    end

    SLASH_SFUISHARDS1 = "/sfshards"
    SlashCmdList["SFUISHARDS"] = function()
        if sfui.triage and sfui.triage.CheckSoulShards then
            sfui.triage.CheckSoulShards()
        end
    end
end

-- Dedicated Alts Mail Routing Slash Command (/sfmail, /altsmail)
SLASH_SFUIMAIL1 = "/sfmail"
SLASH_SFUIMAIL2 = "/altsmail"
SlashCmdList["SFUIMAIL"] = function()
    if sfui.alts and sfui.alts.ToggleMailConfig then
        sfui.alts.ToggleMailConfig()
    end
end

-- Dedicated Standalone SFUI Edit Mode Commands (/sfmove, /sfedit, /sflock)
SLASH_SFUIMOVE1 = "/sfmove"
SLASH_SFUIMOVE2 = "/sfedit"
SLASH_SFUIMOVE3 = "/sfuiunlock"
SlashCmdList["SFUIMOVE"] = function()
    if sfui.movers and sfui.movers.Toggle then
        sfui.movers.Toggle(true)
    elseif sfui.actionbars and sfui.actionbars.ToggleMovers then
        sfui.actionbars.ToggleMovers(true)
    end
end

SLASH_SFUILOCK1 = "/sflock"
SLASH_SFUILOCK2 = "/sfuilock"
SlashCmdList["SFUILOCK"] = function()
    if sfui.movers and sfui.movers.Toggle then
        sfui.movers.Toggle(false)
    elseif sfui.actionbars and sfui.actionbars.ToggleMovers then
        sfui.actionbars.ToggleMovers(false)
    end
end

-- Dedicated Radial Action Rings Slash Command (/sfring)
SLASH_SFRING1 = "/sfring"
SlashCmdList["SFRING"] = function(msg)
    if _G.SlashCmdList and _G.SlashCmdList["SFUI"] then
        _G.SlashCmdList["SFUI"]("ring " .. (msg or ""))
    end
end



