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
        end, "enables 1-key and double-right-click fishing automation.")
        fishing_enable_cb:SetPoint("TOPLEFT", cast_header, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingDoubleClick == nil then SfuiDB.fishingDoubleClick = true end
        local fishing_double_cb = create_checkbox(p, "double-click fishing", "fishingDoubleClick", function(checked)
            notify_setting_changed("fishing", "doubleClick", checked)
        end, "double right-click anywhere in the world to cast fishing and catch the bobber.")
        fishing_double_cb:SetPoint("LEFT", fishing_enable_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingMounted == nil then SfuiDB.fishingMounted = false end
        local fishing_mounted_cb = create_checkbox(p, "allow while mounted", "fishingMounted", function(checked)
            notify_setting_changed("fishing", "doubleClickForce", checked)
        end, "allows double-click fishing attempts while mounted.")
        fishing_mounted_cb:SetPoint("TOPLEFT", fishing_enable_cb, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingRecast == nil then SfuiDB.fishingRecast = false end
        local fishing_recast_cb = create_checkbox(p, "recast on double-click", "fishingRecast", function(checked)
            notify_setting_changed("fishing", "recastOnDoubleClick", checked)
        end, "double right-click while casting will recast immediately instead of reeling in.")
        fishing_recast_cb:SetPoint("LEFT", fishing_mounted_cb, "LEFT", COL_OFFSET_X, 0)

        if SfuiDB.fishingDoubleClickSpeed == nil then SfuiDB.fishingDoubleClickSpeed = 0.4 end
        local fishing_speed_slider = create_slider_input(p, "double-click speed (sec):", "fishingDoubleClickSpeed", 0.1, 1.0, 0.05, function(val)
            notify_setting_changed("fishing", "doubleClickSpeed", val)
        end, "maximum delay in seconds between right-clicks to trigger fishing.", 220)
        fishing_speed_slider:SetPoint("TOPLEFT", fishing_mounted_cb, "BOTTOMLEFT", 0, -12)

        -- ── Section 2: Bobber & Audio Enhancements ───────────────────────────
        local bobber_header = p:CreateFontString(nil, "OVERLAY", g.font)
        bobber_header:SetPoint("TOPLEFT", fishing_speed_slider, "BOTTOMLEFT", 0, -SECTION_GAP)
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

        if SfuiDB.fishingOverrideLunker == nil then SfuiDB.fishingOverrideLunker = false end
        local fishing_lunker_cb = create_checkbox(p, "override lunker fishing", "fishingOverrideLunker", function(checked)
            notify_setting_changed("fishing", "overrideLunker", checked)
        end, "always use standard fishing cast even when in a lunker fishing pool.")
        fishing_lunker_cb:SetPoint("TOPLEFT", fishing_soft_cb, "BOTTOMLEFT", 0, -10)

        if SfuiDB.fishingSoundScale == nil then SfuiDB.fishingSoundScale = 1.0 end
        local fishing_vol_slider = create_slider_input(p, "sound volume:", "fishingSoundScale", 0.1, 1.0, 0.05, function(val)
            notify_setting_changed("fishing", "enhanceSoundsScale", val)
        end, "volume multiplier for fishing splash sound effects.", 220)
        fishing_vol_slider:SetPoint("LEFT", fishing_lunker_cb, "LEFT", COL_OFFSET_X, 0)

        local sound_reset_btn = CreateFlatButton(p, "restore sound defaults", 150, 20)
        sound_reset_btn:SetPoint("TOPLEFT", fishing_lunker_cb, "BOTTOMLEFT", 0, -10)
        sound_reset_btn:SetScript("OnClick", function()
            if sfui.fishing and sfui.fishing.RestoreSoundDefaults then
                sfui.fishing.RestoreSoundDefaults()
            end
        end)

        -- ── Section 3: Keybinds & Instructions ───────────────────────────────
        local tips_header = p:CreateFontString(nil, "OVERLAY", g.font)
        tips_header:SetPoint("TOPLEFT", sound_reset_btn, "BOTTOMLEFT", 0, -SECTION_GAP)
        tips_header:SetTextColor(0, 1, 1, 1)
        tips_header:SetText("keybinds & instructions")

        local keybind_status = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_status:SetPoint("TOPLEFT", tips_header, "BOTTOMLEFT", 0, -8)

        local function update_keybind_display()
            local keys = sfui.fishing and sfui.fishing.get_all_bound_keys and sfui.fishing.get_all_bound_keys() or {}
            if #keys > 0 then
                keybind_status:SetText("Active Keybind: |cff00ff00" .. table_concat(keys, ", ") .. "|r")
            else
                keybind_status:SetText("Active Keybind: |cffff5555None|r |cff888888(bind 'Cast & Catch Fishing' in Keybindings)|r")
            end
        end
        update_keybind_display()

        local keybind_btn = CreateFlatButton(p, "open keybindings", 140, 20)
        keybind_btn:SetPoint("LEFT", keybind_status, "RIGHT", 15, 0)
        keybind_btn:SetScript("OnClick", function()
            if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            elseif KeyBindingFrame_LoadUI then
                KeyBindingFrame_LoadUI()
                ShowUIPanel(KeyBindingFrame)
            end
        end)

        local tips_text = p:CreateFontString(nil, "OVERLAY", g.font_small)
        tips_text:SetPoint("TOPLEFT", keybind_status, "BOTTOMLEFT", 0, -12)
        tips_text:SetTextColor(0.7, 0.7, 0.7, 1)
        tips_text:SetWidth(480)
        tips_text:SetJustifyH("LEFT")
        tips_text:SetText(
            "• |cffffffff1-Key Cast & Reel|r: Press your bound key once to cast. When the bobber splashes, press the exact same key to reel in.\n\n" ..
            "• |cffffffffGamepad Fishing|r: Enable controller support via |cff00ffff/console GamePadEnable 1|r. In Keybindings > SFUI, bind your trigger or button (e.g. Right Trigger). You can then fish with just that one controller button!\n\n" ..
            "• |cffffffffDouble-Click Fishing|r: Double right-click anywhere in the world to cast. When the bobber splashes, click again to reel in.\n\n" ..
            "• |cffffffffMacro & Slash|r: Use |cff00ffff/sffish|r or |cff00ffff/click SfuiFishingButton|r in macros or chat."
        )

        p:HookScript("OnShow", function()
            update_keybind_display()
        end)

        if sfui.events and sfui.events.RegisterEvent then
            sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
                if p:IsVisible() then
                    update_keybind_display()
                end
            end)
        end
    end,
})
