local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local isClassic = (sfui.compat and sfui.compat.is_classic)

sfui.options.RegisterTab({
    id = "objectives",
    name = "objectives",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local white = sfui.config.colors.white
        local yOff = -15

        -- Header
        local obj_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        obj_header:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        obj_header:SetTextColor(white[1], white[2], white[3])
        obj_header:SetText("objectives & tracker")
        yOff = yOff - 30

        -- ── Section: Quest Log / Objective Tracker ────────────────────────────
        local ql_section = p:CreateFontString(nil, "OVERLAY", g.font)
        ql_section:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        ql_section:SetTextColor(0, 1, 1, 1)
        ql_section:SetText("quest log / objective tracker")
        yOff = yOff - 22

        local enable_ql_cb = create_checkbox(p, "enable sfui quest log",
            function()
                if sfui.questlog and sfui.questlog.is_enabled then
                    return sfui.questlog.is_enabled()
                end
                if SfuiDB.enableQuestLog ~= nil then return SfuiDB.enableQuestLog end
                return true
            end,
            function(checked)
                if sfui.questlog and sfui.questlog.set_enabled then
                    sfui.questlog.set_enabled(checked)
                else
                    SfuiDB.enableQuestLog = checked
                end
            end,
            "Enables or disables the SFUI custom quest log and objective tracker. " ..
            "When disabled the default Blizzard tracker is shown.")
        enable_ql_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        yOff = yOff - 28

        local lock_ql_cb = create_checkbox(p, "lock quest log position",
            function()
                return SfuiDB.questlogUnlocked ~= true
            end,
            function(checked)
                SfuiDB.questlogUnlocked = not checked
                if sfui.questlog and sfui.questlog.set_locked then
                    sfui.questlog.set_locked(checked)
                end
            end,
            "When unlocked you can drag the quest log frame to a new position. " ..
            "The position is saved between sessions.")
        lock_ql_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        yOff = yOff - 30

        local reset_ql_pos_btn = CreateFlatButton(p, "reset position", 120, 22)
        reset_ql_pos_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
        reset_ql_pos_btn:SetScript("OnClick", function()
            if sfui.questlog and sfui.questlog.reset_position then
                sfui.questlog.reset_position()
            else
                if SfuiDB then
                    SfuiDB.questlogX = nil
                    SfuiDB.questlogY = nil
                end
            end
        end)
        yOff = yOff - 36

        -- ── Section: Mythic+ HUD (Retail only) ────────────────────────────────
        if not isClassic then
            local mplus_section = p:CreateFontString(nil, "OVERLAY", g.font)
            mplus_section:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            mplus_section:SetTextColor(0, 1, 1, 1)
            mplus_section:SetText("mythic+ timer hud")
            yOff = yOff - 22

            local enable_mhud_cb = create_checkbox(p, "enable mythic+ hud",
                function()
                    if sfui.mythic and sfui.mythic.IsEnabled then return sfui.mythic.IsEnabled() end
                    return SfuiDB.mythicHudEnabled ~= false
                end,
                function(checked)
                    if sfui.mythic and sfui.mythic.SetEnabled then
                        sfui.mythic.SetEnabled(checked)
                    else
                        SfuiDB.mythicHudEnabled = checked
                    end
                end,
                "When enabled, SFUI displays a native Mythic+ HUD with the dungeon timer, " ..
                "death count, boss checkmarks, and enemy forces bar. " ..
                "Disable this if you use an external M+ timer addon.")
            enable_mhud_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            yOff = yOff - 28

            local lock_mhud_cb = create_checkbox(p, "lock mythic+ hud position",
                function()
                    return SfuiDB.mythicHudUnlocked ~= true
                end,
                function(checked)
                    SfuiDB.mythicHudUnlocked = not checked
                    if sfui.mythic and sfui.mythic.SetLocked then
                        sfui.mythic.SetLocked(checked)
                    end
                end,
                "When unlocked you can drag the Mythic+ HUD to any position on screen. " ..
                "The position is saved automatically between sessions.")
            lock_mhud_cb:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            yOff = yOff - 30

            local reset_mhud_pos_btn = CreateFlatButton(p, "reset position", 120, 22)
            reset_mhud_pos_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            reset_mhud_pos_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.ResetPosition then
                    sfui.mythic.ResetPosition()
                else
                    if SfuiDB then
                        SfuiDB.mythicHudX = nil
                        SfuiDB.mythicHudY = nil
                    end
                end
            end)
            yOff = yOff - 34

            local preview_hint = p:CreateFontString(nil, "OVERLAY", g.font_small)
            preview_hint:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            preview_hint:SetTextColor(0.6, 0.6, 0.6, 1)
            preview_hint:SetText("preview m+ hud with sample data:")
            yOff = yOff - 20

            local preview_btn = CreateFlatButton(p, "show preview", 110, 22)
            preview_btn:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)

            local hide_preview_btn = CreateFlatButton(p, "hide preview", 110, 22)
            hide_preview_btn:SetPoint("LEFT", preview_btn, "RIGHT", 10, 0)

            preview_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.ShowPreview then
                    sfui.mythic.ShowPreview()
                end
            end)
            hide_preview_btn:SetScript("OnClick", function()
                if sfui.mythic and sfui.mythic.HidePreview then
                    sfui.mythic.HidePreview()
                end
            end)
            yOff = yOff - 34

            local resize_hint = p:CreateFontString(nil, "OVERLAY", g.font_small)
            resize_hint:SetPoint("TOPLEFT", p, "TOPLEFT", 15, yOff)
            resize_hint:SetTextColor(0.45, 0.45, 0.45, 1)
            resize_hint:SetText("unlock the hud above, then drag the purple handle to reposition it.")
        end
    end,
})
