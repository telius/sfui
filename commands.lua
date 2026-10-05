local addonName, addon = ...
sfui = sfui or {}
sfui.commands = sfui.commands or {}
sfui.keybinds = sfui.keybinds or {}

-- Localize Globals
local _G = _G
local print = print
local type = type
local tostring = tostring
local string_lower = string.lower
local string_format = string.format
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

-- Quick UI Reload
SLASH_RL1 = "/rl"
SlashCmdList["RL"] = function()
    C_UI.Reload()
end

-- Fishing Cast & Catch
SLASH_SFFISH1 = "/sffish"
SlashCmdList["SFFISH"] = function(msg)
    local clean = msg and _G.strtrim and _G.strtrim(msg):lower() or (msg and msg:lower() or "")
    if clean == "sound" or clean == "soundreset" or clean == "reset" then
        sfui.fishing.RestoreSoundDefaults()
        return
    end
    sfui.fishing.RunKeybind(true)
end

-- Companion Pet Summon / Rotate
SLASH_SFPET1 = "/sfpet"
SlashCmdList["SFPET"] = function(msg)
    local clean = msg and _G.strtrim and _G.strtrim(msg):lower() or (msg and msg:lower() or "")
    local cmd = clean:match("^(%S+)") or clean
    if cmd == "add" then
        sfui.pets.AddCurrentPetToCharFavs()
    elseif cmd == "remove" or cmd == "del" then
        sfui.pets.RemoveCurrentPetFromCharFavs()
    elseif cmd == "list" then
        sfui.pets.ListCharFavs()
    elseif cmd == "clear" then
        sfui.pets.ClearCharFavs()
    elseif cmd == "summon" or cmd == "next" then
        sfui.pets.SummonNext(true)
    elseif cmd == "dismiss" then
        sfui.pets.Dismiss()
    else
        sfui.pets.Toggle()
    end
end

-- Memory Profiler & Garbage Collection
SLASH_SFMEM1 = "/sfmem"
SlashCmdList["SFMEM"] = function(msg)
    sfui.mem.HandleSlash(msg)
end

-- Quest Log HUD
SLASH_SFQL1 = "/sfql"
SLASH_SFQL2 = "/sfquestlog"
SlashCmdList["SFQL"] = function(msg)
    local clean = msg and _G.strtrim and _G.strtrim(msg):lower() or (msg and msg:lower() or "")
    if clean == "reset" or clean == "unhide" then
        sfui.questlog.unhide_all()
        return
    end
    sfui.questlog.toggle()
end

-- Alts & Warband Dashboard
SLASH_SFUIALTS1 = "/alts"
SLASH_SFUIALTS2 = "/sfalts"
SlashCmdList["SFUIALTS"] = function(msg)
    local clean = msg and _G.strtrim and _G.strtrim(msg):lower() or (msg and msg:lower() or "")
    if clean == "resetweeklies" then
        sfui.alts.ResetWeeklies()
        return
    end
    sfui.alts.Toggle()
end

-- Master SFUI Slash Command Router
SLASH_SFUI1 = "/sfui"
SlashCmdList["SFUI"] = function(msg)
    local raw = msg and _G.strtrim and _G.strtrim(msg) or (msg or "")
    local clean = raw:lower()
    local cmd, arg = clean:match("^(%S+)%s*(.*)$")
    cmd = cmd or clean

    if cmd == "" then
        sfui.toggle_options_panel()
    elseif cmd == "theme" or cmd == "style" then
        local sub = arg and _G.strtrim and _G.strtrim(arg):lower() or (arg and arg:lower() or "")
        if sub == "auto" or sub == "detect" or sub == "reset" then
            sfui.theme.SetTheme("auto")
            local active = sfui.theme.GetActiveThemeID() or "modern"
            sfui.common.print("theme set to auto-detect (active: " .. tostring(active) .. ").")
        elseif sfui.theme.GetTheme(sub) then
            sfui.theme.SetTheme(sub)
            local themeDef = sfui.theme.GetTheme(sub)
            sfui.common.print("theme set to " .. tostring(themeDef.name or sub) .. ".")
        elseif sub == "camelot" or sub == "bronze" then
            sfui.theme.SetTheme("camelot")
            sfui.common.print("theme set to camelot heavy bronze.")
        elseif sub == "modern" or sub == "retail" or sub == "minimal" or sub == "slate" then
            sfui.theme.SetTheme("modern")
            sfui.common.print("theme set to modern minimalist.")
        else
            local curMode = (SfuiDB and (SfuiDB.themeMode or (SfuiDB.theme and SfuiDB.theme.mode))) or "auto"
            local active = sfui.theme.GetActiveThemeID() or "modern"
            local _, regOrder = sfui.theme.GetRegisteredThemes()
            local list = "auto"
            if regOrder then
                for _, id in ipairs(regOrder) do list = list .. " | " .. id end
            else
                list = "auto | camelot | modern"
            end
            sfui.common.print("theme mode is '" .. tostring(curMode) .. "' (currently rendering " .. tostring(active) .. "). usage: /sfui theme [" .. list .. "]")
        end
    elseif cmd == "barstyle" or cmd == "barborder" or cmd == "barborders" or cmd == "bars" then
        local sub = arg and _G.strtrim and _G.strtrim(arg):lower() or (arg and arg:lower() or "")
        if sub == "inset" or sub == "darkinset" or sub == "dark" or sub == "1" then
            sfui.theme.SetBarStyle("inset")
            sfui.common.print("bar style set to |cffffd100dark inset|r (castbar match: dark recessed well, softened corners, antique bronze rim).")
        elseif sub == "bezel" or sub == "nameplate" or sub == "hud" or sub == "blizzard" or sub == "2" then
            sfui.theme.SetBarStyle("bezel")
            sfui.common.print("bar style set to |cffffd100blizzard bezel|r (native hud cooldownmanager/nameplate atlas).")
        elseif sub == "darkbronze" or sub == "bronze" or sub == "3" then
            sfui.theme.SetBarStyle("darkbronze")
            sfui.common.print("bar style set to |cffffd100dark bronze|r (sculpted dark bronze with micro-corners).")
        elseif sub == "castbar" or sub == "cast" or sub == "4" then
            sfui.theme.SetBarStyle("castbar")
            sfui.common.print("bar style set to |cffffd100castbar replica|r (pure 1:1 black border, no decor).")
        elseif sub == "heavy" or sub == "c" or sub == "brackets" or sub == "chiseled" or sub == "5" then
            sfui.theme.SetBarStyle("heavy")
            sfui.common.print("bar style set to |cffffd100chiseled heavy|r (square corner brackets & gold highlight).")
        elseif sub == "thin" or sub == "a" or sub == "flat" or sub == "minimal" or sub == "6" then
            sfui.theme.SetBarStyle("thin")
            sfui.common.print("bar style set to |cffffd100thin|r (1px clean bronze edge).")
        elseif sub == "glow" or sub == "b" or sub == "recessed" or sub == "7" then
            sfui.theme.SetBarStyle("glow")
            sfui.common.print("bar style set to |cffffd100glow|r (borderless recessed amber inner glow).")
        elseif sub == "cycle" or sub == "next" or sub == "" then
            local order = { "inset", "bezel", "darkbronze", "castbar", "heavy", "thin", "glow" }
            local cur = sfui.theme.GetBarStyle() or "inset"
            local nextIdx = 1
            for idx, st in ipairs(order) do
                if st == cur then
                    nextIdx = (idx % #order) + 1
                    break
                end
            end
            local nextStyle = order[nextIdx]
            sfui.theme.SetBarStyle(nextStyle)
            sfui.common.print("bar style cycled to |cffffd100" .. nextStyle .. "|r. usage: /sfui barstyle [inset | bezel | darkbronze | castbar | heavy | thin | glow]")
        else
            local cur = sfui.theme.GetBarStyle() or "inset"
            sfui.common.print("bar style is currently '|cffffd100" .. tostring(cur) .. "|r'. usage: /sfui barstyle [inset | bezel | darkbronze | castbar | heavy | thin | glow]")
        end
    elseif cmd == "alts" or cmd == "warband" then
        SlashCmdList["SFUIALTS"](arg)
    elseif cmd == "ql" or cmd == "quests" or cmd == "questlog" then
        SlashCmdList["SFQL"](arg)
    elseif cmd == "mem" or cmd == "memory" or cmd == "gc" then
        local sub = (cmd == "gc" and "gc") or arg
        SlashCmdList["SFMEM"](sub)
    elseif cmd == "cv" or cmd == "cooldowns" then
        sfui.trackedoptions.toggle_viewer()
    elseif cmd == "portals" or cmd == "portal" or cmd == "portalpopup" or cmd == "teleport" then
        if arg == "test" or arg == "preview" or arg == "popup" or cmd == "portalpopup" then
            sfui.portals.TestPortalPopup()
        else
            sfui.portals.Toggle()
        end
    elseif cmd == "gear" then
        sfui.gear.toggle()
    elseif cmd == "highest" then
        if sfui.gear and sfui.gear.SetNakedPaused then sfui.gear.SetNakedPaused(false, true) end
        sfui.highest.toggle()
    elseif cmd == "naked" or cmd == "unequip" then
        if sfui.gear and sfui.gear.ToggleNaked then
            sfui.gear.ToggleNaked()
        elseif sfui.gear and sfui.gear.UnequipDurabilityItems then
            sfui.gear.UnequipDurabilityItems()
        end
    elseif cmd == "lootspec" or cmd == "spec" or cmd == "loot" or cmd == "lootviewer" or cmd == "lv" or cmd == "camelot" or cmd == "dj" or cmd == "journal" then
        if arg == "restore" or arg == "unhide" then
            if sfui.dungeonjournal and sfui.dungeonjournal.RestoreHiddenDungeons then
                sfui.dungeonjournal.RestoreHiddenDungeons()
            else
                sfui.common.print("dungeon journal restore is not available.")
            end
            return
        end
        if not sfui.isRetail and sfui.lootviewer_camelot and sfui.lootviewer_camelot.Toggle then
            sfui.lootviewer_camelot.Toggle()
        elseif sfui.lootviewer and sfui.lootviewer.Toggle then
            sfui.lootviewer.Toggle()
        else
            sfui.common.print("loot viewer / dungeon journal is not available.")
        end
    elseif cmd == "bonusroll" or cmd == "br" or cmd == "rescan" then
        if not sfui.isRetail then
            sfui.common.print("bonus roll is retail only.")
            return
        end
        sfui.bonusroll.CheckAll(true)
    elseif cmd == "research" then
        if not sfui.isRetail then
            sfui.common.print("research is retail only.")
            return
        end
        sfui.research.toggle_selection()
    elseif cmd == "mythic" or cmd == "m+" or cmd == "delve" or cmd == "dungeon" then
        if not sfui.isRetail then
            sfui.common.print("mythic tracker is retail only.")
            return
        end
        if sfui.mythic.previewActive then
            sfui.mythic.HidePreview()
        else
            sfui.mythic.ShowPreview()
        end
    elseif cmd == "hammer" or cmd == "repair" then
        if not sfui.isRetail then
            sfui.common.print("master's hammer is retail only.")
            return
        end
        local hammer = sfui.hammer
        if arg == "test" or arg == "preview" then
            hammer.toggle_test_popup()
        elseif arg == "lock" then
            SfuiDB.lockRepairIcon = not SfuiDB.lockRepairIcon
            sfui.common.print("repair icon " .. (SfuiDB.lockRepairIcon and "locked" or "unlocked") .. ".")
        elseif arg == "reset" then
            local def = sfui.config.masterHammer.defaultPosition
            SfuiDB.repairIconX = def.x
            SfuiDB.repairIconY = def.y
            hammer.update_popup_style()
            if sfui.options.sync_hammer_sliders then
                sfui.options.sync_hammer_sliders(def.x, def.y)
            end
            sfui.common.print("repair button position reset to center (" .. def.x .. ", " .. def.y .. ").")
        else
            hammer.print_hammer_status(arg == "debug")
        end
    elseif cmd == "fish" or cmd == "fishing" then
        if arg == "sound" or arg == "soundreset" or arg == "reset" then
            sfui.fishing.RestoreSoundDefaults()
        else
            sfui.fishing.RunKeybind(true)
        end
    elseif cmd == "pet" or cmd == "pets" or cmd == "petwalker" then
        if arg == "add" then
            sfui.pets.AddCurrentPetToCharFavs()
        elseif arg == "remove" or arg == "del" then
            sfui.pets.RemoveCurrentPetFromCharFavs()
        elseif arg == "list" then
            sfui.pets.ListCharFavs()
        elseif arg == "clear" then
            sfui.pets.ClearCharFavs()
        elseif arg == "summon" or arg == "next" then
            sfui.pets.SummonNext(true)
        elseif arg == "dismiss" then
            sfui.pets.Dismiss()
        else
            sfui.pets.Toggle()
        end
    elseif cmd == "target" or cmd == "targetbar" then
        if sfui.isRetail then
            sfui.common.print("target bar is only available on camelot / classic.")
        else
            if arg == "reset" then
                sfui.target.ResetPosition()
                sfui.common.print("target bar position reset to top of the screen.")
            else
                sfui.target.ToggleLock()
                local status = sfui.target.unlocked and "|cff00ff00unlocked (shift+drag to move)|r" or "|cffff3333locked|r"
                sfui.common.print("target bar: " .. status)
            end
        end
    elseif cmd == "threat" or cmd == "threatbar" then
        if sfui.isRetail then
            sfui.common.print("threat bar is only available on camelot / classic.")
        else
            SfuiDB = SfuiDB or {}
            SfuiDB.enableThreatBar = (SfuiDB.enableThreatBar == false)
            sfui.threat.UpdateVisibility()
            local status = SfuiDB.enableThreatBar and "|cff00ff00enabled|r" or "|cffff3333disabled|r"
            sfui.common.print("threat bar: " .. status)
        end
    elseif cmd == "rl" or cmd == "reload" then
        C_UI.Reload()
    elseif cmd == "help" or cmd == "?" then
        sfui.common.print("commands: /sfui [options | target | threat | theme [camelot|modern|auto] | barstyle [thin|glow|heavy] | fish | pet | hammer [test|lock|reset|debug] | alts | ql | portals [test] | cv | gear | highest | lootspec | loot | research | mythic | mem | rl]")
    else
        sfui.common.print("unknown command: /sfui " .. tostring(cmd) .. ". type /sfui help for a list of commands.")
    end
end

-- Quick Theme Switcher Shortcut
SLASH_SFTHEME1 = "/sftheme"
SlashCmdList["SFTHEME"] = function(msg)
    SlashCmdList["SFUI"]("theme " .. (msg or ""))
end

-- Quick Bar Style Switcher Shortcut
SLASH_SFBARSTYLE1 = "/sfbarstyle"
SlashCmdList["SFBARSTYLE"] = function(msg)
    SlashCmdList["SFUI"]("barstyle " .. (msg or ""))
end
