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
-- 1. BLIZZARD KEYBINDINGS MENU DEFINITIONS
-- ────────────────────────────────────────────────────────────────────────────
BINDING_HEADER_SFUI = "SFUI"
_G["BINDING_NAME_CLICK SfuiHammerPopup:LeftButton"] = "master's hammer repair"
_G["BINDING_NAME_SFUI_MATCHMOUNT"] = "match target mount"
_G["BINDING_NAME_SFUI_PORTALS"] = "portals"
_G["BINDING_NAME_SFUI_ALTS"] = "alts / warband"
_G["BINDING_NAME_SFUI_LOOTVIEWER"] = "loot browser"
_G["BINDING_NAME_SFUI_FISHING"] = "cast & catch fishing"
_G["BINDING_NAME_BETTERFISHINGKEY"] = "cast & catch fishing (better fishing compat)"
_G["BINDING_NAME_SFUI_PET_SUMMON"] = "summon / rotate companion pet"
_G["BINDING_NAME_SFUI_PET_MANAGER"] = "toggle pet manager"

-- ────────────────────────────────────────────────────────────────────────────
-- 2. KEYBIND RESOLUTION & FORMATTING HELPERS
-- ────────────────────────────────────────────────────────────────────────────
--- Formats a raw key string with standard abbreviated modifier prefixes.
--- @param key string
--- @return string
function sfui.keybinds.format_key(key)
    if not key or key == "" then return "" end
    return key:gsub("SHIFT%-", "S-")
              :gsub("CTRL%-", "C-")
              :gsub("ALT%-", "A-")
              :gsub("NUMPAD", "N")
              :gsub("MOUSEWHEELUP", "WU")
              :gsub("MOUSEWHEELDOWN", "WD")
end

--- Returns the primary bound key for a given action string, formatted for UI labels.
--- @param action string e.g. "ACTIONBUTTON1", "SFUI_PORTALS", "SFUI_ALTS"
--- @return string
function sfui.keybinds.get_action_key(action)
    if not action then return "" end
    local key = GetBindingKey and GetBindingKey(action)
    return sfui.keybinds.format_key(key)
end

-- Export aliases to sfui.common for cross-module convenience
sfui.common = sfui.common or {}
sfui.common.format_keybind = sfui.keybinds.format_key
sfui.common.get_binding_text = sfui.keybinds.get_action_key

-- ────────────────────────────────────────────────────────────────────────────
-- 3. SLASH COMMAND HANDLERS
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
    elseif cmd == "rl" or cmd == "reload" then
        C_UI.Reload()
    elseif cmd == "help" or cmd == "?" then
        if sfui.common and sfui.common.print then
            sfui.common.print("commands: /sfui [tab] | /sfmem | /rl")
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
