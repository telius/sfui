local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local Settings = _G.Settings
local ShowUIPanel = _G.ShowUIPanel
local KeyBindingFrame = _G.KeyBindingFrame
local KeyBindingFrame_LoadUI = _G.KeyBindingFrame_LoadUI
local table_concat = table.concat
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local IsAltKeyDown = _G.IsAltKeyDown
local IsControlKeyDown = _G.IsControlKeyDown
local IsShiftKeyDown = _G.IsShiftKeyDown
local IsMetaKeyDown = _G.IsMetaKeyDown

sfui.options.RegisterTab({
    id = "fishing",
    name = "fishing",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white
        local notify_setting_changed = sfui.options.notify_setting_changed

        local COL_OFFSET_X = 265
        local SECTION_GAP = 22

        -- Header
        local fishing_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        fishing_header:SetPoint("TOPLEFT", 15, -15)
        fishing_header:SetTextColor(white[1], white[2], white[3])
        fishing_header:SetText("fishing automation")

        -- ── Section 1: Casting & Interaction ─────────────────────────────────
        local cast_header = p:CreateFontString(nil, "OVERLAY", g.font)
        cast_header:SetPoint("TOPLEFT", fishing_header, "BOTTOMLEFT", 0, -18)
        cast_header:SetTextColor(0, 1, 1, 1)
        cast_header:SetText("casting & interaction")

        if SfuiDB.fishingEnabled == nil then SfuiDB.fishingEnabled = true end
        local fishing_enable_cb = create_checkbox(p, "enable fishing automation", "fishingEnabled", function(checked)
            notify_setting_changed("fishing", "enabled", checked)
        end, "enables 1-key fishing cast, reel-in, and auto-loot.")
        fishing_enable_cb:SetPoint("TOPLEFT", cast_header, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingAutoLoot == nil then SfuiDB.fishingAutoLoot = true end
        local fishing_autoloot_cb = create_checkbox(p, "auto-loot caught fish", "fishingAutoLoot", function(checked)
            notify_setting_changed("fishing", "autoLoot", checked)
        end, "automatically loots all caught fish and items immediately upon reeling in.")
        fishing_autoloot_cb:SetPoint("LEFT", fishing_enable_cb, "LEFT", COL_OFFSET_X, 0)

        -- ── Section 2: Bobber & Audio Enhancements ───────────────────────────
        local bobber_header = p:CreateFontString(nil, "OVERLAY", g.font)
        bobber_header:SetPoint("TOPLEFT", fishing_enable_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        bobber_header:SetTextColor(0, 1, 1, 1)
        bobber_header:SetText("bobber & audio enhancements")

        if SfuiDB.fishingSoftTarget == nil then SfuiDB.fishingSoftTarget = true end
        local fishing_soft_cb = create_checkbox(p, "soft-target bobber interact", "fishingSoftTarget", function(checked)
            notify_setting_changed("fishing", "softTarget", checked)
        end, "automatically highlights and interacts with the bobber using soft-targeting CVars.")
        fishing_soft_cb:SetPoint("TOPLEFT", bobber_header, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingEnhanceSounds == nil then SfuiDB.fishingEnhanceSounds = true end
        local fishing_sound_cb = create_checkbox(p, "enhance fishing audio", "fishingEnhanceSounds", function(checked)
            notify_setting_changed("fishing", "enhanceSounds", checked)
        end, "boosts splash effects and mutes ambience/music during cast.")
        fishing_sound_cb:SetPoint("LEFT", fishing_soft_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingSoundScale == nil then SfuiDB.fishingSoundScale = 1.0 end
        local fishing_vol_slider = create_slider_input(p, "sound volume:", "fishingSoundScale", 0.1, 1.0, 0.05, function(val)
            notify_setting_changed("fishing", "enhanceSoundsScale", val)
        end, "volume multiplier for fishing splash sound effects.", 220)
        fishing_vol_slider:SetPoint("TOPLEFT", fishing_soft_cb, "BOTTOMLEFT", 0, -14)

        local sound_reset_btn = CreateFlatButton(p, "restore sound defaults", 150, 20)
        sound_reset_btn:SetPoint("LEFT", fishing_vol_slider, "LEFT", COL_OFFSET_X, 0)
        sound_reset_btn:SetScript("OnClick", function()
            if sfui.fishing and sfui.fishing.RestoreSoundDefaults then
                sfui.fishing.RestoreSoundDefaults()
            end
        end)

        -- ── Section 3: Keybinds & Instructions ───────────────────────────────
        local tips_header = p:CreateFontString(nil, "OVERLAY", g.font)
        tips_header:SetPoint("TOPLEFT", fishing_vol_slider, "BOTTOMLEFT", 0, -SECTION_GAP)
        tips_header:SetTextColor(0, 1, 1, 1)
        tips_header:SetText("keybinds & instructions")

        local keybind_status = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_status:SetPoint("TOPLEFT", tips_header, "BOTTOMLEFT", 0, -8)

        local is_listening = false
        local bind_btn = CreateFlatButton(p, "bind key", 110, 20)
        bind_btn:SetPoint("TOPLEFT", keybind_status, "BOTTOMLEFT", 0, -8)
        bind_btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local unbind_btn = CreateFlatButton(p, "unbind", 65, 20)
        unbind_btn:SetPoint("LEFT", bind_btn, "RIGHT", 8, 0)

        local keybind_btn = CreateFlatButton(p, "keybindings menu", 130, 20)
        keybind_btn:SetPoint("LEFT", unbind_btn, "RIGHT", 8, 0)

        local function update_keybind_display()
            if is_listening then return end
            local keys = sfui.fishing and sfui.fishing.get_all_bound_keys and sfui.fishing.get_all_bound_keys() or {}
            if #keys > 0 then
                keybind_status:SetText("active keybind: |cff00ff00" .. table_concat(keys, ", ") .. "|r")
                bind_btn:SetText("rebind key")
            else
                keybind_status:SetText("active keybind: |cffff5555none|r |cff888888(click 'bind key' below to assign)|r")
                bind_btn:SetText("bind key")
            end
        end
        update_keybind_display()

        -- Modal input catcher overlay for key/mouse/gamepad capture
        local catcher = CreateFrame("Button", nil, options_frame or p)
        catcher:SetAllPoints(options_frame or p)
        catcher:SetFrameStrata("DIALOG")
        catcher:EnableMouse(true)
        catcher:RegisterForClicks("AnyDown", "AnyUp")
        catcher:Hide()

        local function stop_listening()
            if not is_listening then return end
            is_listening = false
            catcher:EnableKeyboard(false)
            catcher:Hide()

            local gray = (sfui.config and sfui.config.colors and sfui.config.colors.gray) or { 0.5, 0.5, 0.5 }
            bind_btn:SetBackdropBorderColor(gray[1], gray[2], gray[3], 1)
            update_keybind_display()
        end

        local function start_listening()
            if InCombatLockdown and InCombatLockdown() then return end
            is_listening = true
            bind_btn:SetText("|cffffff00press a key...|r")
            local cyan = { 0, 1, 1 }
            bind_btn:SetBackdropBorderColor(cyan[1], cyan[2], cyan[3], 1)
            keybind_status:SetText("active keybind: |cffffff00press key to bind (ESC to cancel)|r")

            catcher:Show()
            catcher:EnableKeyboard(true)
            if catcher.SetPropagateKeyboardInput then
                catcher:SetPropagateKeyboardInput(false)
            end
        end

        local function is_meta_key(key)
            if _G.IsMetaKey then return _G.IsMetaKey(key) end
            return key == "LALT" or key == "RALT" or key == "ALT"
                or key == "LCTRL" or key == "RCTRL" or key == "CTRL"
                or key == "LSHIFT" or key == "RSHIFT" or key == "SHIFT"
                or key == "LMETA" or key == "RMETA" or key == "META"
        end

        local function build_key_chord(key)
            if not key or key == "" then return nil end
            if _G.CreateKeyChordStringUsingMetaKeyState then
                return _G.CreateKeyChordStringUsingMetaKeyState(key)
            end

            local chord = {}
            if IsAltKeyDown and IsAltKeyDown() then table.insert(chord, "ALT") end
            if IsControlKeyDown and IsControlKeyDown() then table.insert(chord, "CTRL") end
            if IsShiftKeyDown and IsShiftKeyDown() then table.insert(chord, "SHIFT") end
            if IsMetaKeyDown and IsMetaKeyDown() then table.insert(chord, "META") end
            table.insert(chord, key)
            return table.concat(chord, "-")
        end

        catcher:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                stop_listening()
                return
            end

            if is_meta_key(key) or key == "UNKNOWN" or key == "PRINTSCREEN" then
                return
            end

            local chord = build_key_chord(key)
            if chord and chord ~= "" then
                if sfui.fishing and sfui.fishing.set_keybind then
                    sfui.fishing.set_keybind(chord)
                end
            end
            stop_listening()
        end)

        catcher:SetScript("OnGamePadButtonDown", function(self, button)
            if button and button ~= "" then
                if sfui.fishing and sfui.fishing.set_keybind then
                    sfui.fishing.set_keybind(button)
                end
            end
            stop_listening()
        end)

        catcher:SetScript("OnMouseWheel", function(self, delta)
            local key = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
            local chord = build_key_chord(key)
            if chord and chord ~= "" then
                if sfui.fishing and sfui.fishing.set_keybind then
                    sfui.fishing.set_keybind(chord)
                end
            end
            stop_listening()
        end)

        local mouse_button_map = {
            MiddleButton = "BUTTON3",
            Button3      = "BUTTON3",
            Button4      = "BUTTON4",
            Button5      = "BUTTON5",
            Button6      = "BUTTON6",
            Button7      = "BUTTON7",
            Button8      = "BUTTON8",
        }

        catcher:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" or button == "RightButton" then
                stop_listening()
            else
                local mapped = mouse_button_map[button] or (_G.GetConvertedKeyOrButton and _G.GetConvertedKeyOrButton(button))
                if mapped and mapped ~= "BUTTON1" and mapped ~= "BUTTON2" then
                    local chord = build_key_chord(mapped)
                    if chord and chord ~= "" then
                        if sfui.fishing and sfui.fishing.set_keybind then
                            sfui.fishing.set_keybind(chord)
                        end
                    end
                end
                stop_listening()
            end
        end)

        bind_btn:SetScript("OnClick", function(self, button)
            if InCombatLockdown and InCombatLockdown() then return end
            if button == "RightButton" then
                if is_listening then
                    stop_listening()
                else
                    if sfui.fishing and sfui.fishing.unbind_keybinds then
                        sfui.fishing.unbind_keybinds()
                    end
                    update_keybind_display()
                end
            elseif button == "LeftButton" then
                if is_listening then
                    stop_listening()
                else
                    start_listening()
                end
            end
        end)

        unbind_btn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if is_listening then
                stop_listening()
            end
            if sfui.fishing and sfui.fishing.unbind_keybinds then
                sfui.fishing.unbind_keybinds()
            end
            update_keybind_display()
        end)

        keybind_btn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if is_listening then
                stop_listening()
            end
            if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            elseif KeyBindingFrame_LoadUI then
                KeyBindingFrame_LoadUI()
                ShowUIPanel(KeyBindingFrame)
            end
        end)

        local function attach_tooltip(btn, title, desc)
            btn:HookScript("OnEnter", function(self)
                local tip = sfui.tooltip or _G.GameTooltip
                if tip then
                    tip:SetOwner(self, "ANCHOR_TOP")
                    tip:SetText(title, 1, 1, 1)
                    if desc then
                        tip:AddLine(desc, 0.8, 0.8, 0.8, true)
                    end
                    tip:Show()
                end
            end)
            btn:HookScript("OnLeave", function(self)
                local tip = sfui.tooltip or _G.GameTooltip
                if tip then tip:Hide() end
            end)
        end

        attach_tooltip(bind_btn, "fishing keybind", "Left-click: bind a key, button, or wheel scroll.\nRight-click: unbind active key.\nPress ESC while listening to cancel.")
        attach_tooltip(unbind_btn, "clear keybind", "Removes active fishing keybind.")
        attach_tooltip(keybind_btn, "blizzard keybindings", "Opens the standard World of Warcraft keybindings interface.")

        local tips_text = p:CreateFontString(nil, "OVERLAY", g.font_small)
        tips_text:SetPoint("TOPLEFT", bind_btn, "BOTTOMLEFT", 0, -14)
        tips_text:SetTextColor(0.7, 0.7, 0.7, 1)
        tips_text:SetWidth(480)
        tips_text:SetJustifyH("LEFT")
        tips_text:SetText(
            "• |cffffffff1-key cast, catch & loot|r: press your bound key once to cast. when the bobber splashes, press the exact same key to reel in. caught fish are looted automatically (or on your next keypress if loot remains).\n\n" ..
            "• |cffffffffquick binding|r: click '|cff00ffffbind key|r' above and press any key, mouse button, or controller trigger. right-click the button or click '|cff00ffffunbind|r' to remove it.\n\n" ..
            "• |cffffffffgamepad fishing|r: enable controller support via |cff00ffff/console GamePadEnable 1|r. in keybindings > sfui, bind your trigger or button (e.g. right trigger) to fish with one button.\n\n" ..
            "• |cffffffffmacro & slash|r: use |cff00ffff/sffish|r or |cff00ffff/click SfuiFishingButton|r in macros or chat."
        )

        p:HookScript("OnShow", function()
            update_keybind_display()
        end)
        p:HookScript("OnHide", function()
            stop_listening()
        end)
        if options_frame then
            options_frame:HookScript("OnHide", function()
                stop_listening()
            end)
        end

        if sfui.events and sfui.events.RegisterEvent then
            sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
                if p:IsVisible() then
                    update_keybind_display()
                end
            end)
            sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
                stop_listening()
            end)
        end
    end,
})
