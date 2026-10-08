local addonName, addon = ...
sfui = sfui or {}
sfui.commands = sfui.commands or {}
sfui.keybinds = sfui.keybinds or {}

-- Localize Globals
local _G = _G
local tostring = tostring
local C_UI = C_UI
local GetBindingKey = _G.GetBindingKey

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
    pcall(filter_sfui_keybindings)
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
    elseif cmd == "mem" or cmd == "memory" or cmd == "gc" then
        if sfui.mem and sfui.mem.HandleSlash then
            sfui.mem.HandleSlash((cmd == "gc" and "gc") or arg)
        end
    elseif cmd == "portals" or cmd == "portal" or cmd == "teleport" or cmd == "tp" then
        if sfui.portals and sfui.portals.Toggle then
            sfui.portals.Toggle()
        end
    elseif cmd == "totembar" or cmd == "totems" then
        if not sfui.isRetail and sfui.totembar and sfui.totembar.ToggleUnlock then
            sfui.totembar.ToggleUnlock()
        end
    elseif cmd == "shards" or cmd == "shard" then
        if sfui.triage and sfui.triage.CheckSoulShards then
            sfui.triage.CheckSoulShards()
        end
    elseif cmd == "rl" or cmd == "reload" then
        C_UI.Reload()
    elseif cmd == "help" or cmd == "?" then
        if sfui.common and sfui.common.print then
            if sfui.isRetail then
                sfui.common.print("commands: /sfui [tab] | /sfui portals | /sfmem | /rl")
            else
                sfui.common.print("commands: /sfui [tab] | /sfui portals | /sfui shards | /sfmem | /rl | /totembar")
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

-- Dedicated Portals & Teleports Slash Command (/portals, /sfportals)
SLASH_SFUIPORTALS1 = "/sfportals"
SLASH_SFUIPORTALS2 = "/portals"
SlashCmdList["SFUIPORTALS"] = function()
    if sfui.portals and sfui.portals.Toggle then
        sfui.portals.Toggle()
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
