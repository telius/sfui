local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/options/tabs/tab_hide.lua
--  Options Tab: Blizzard Unitframe & HUD Suppression and Error Filtering
-- ══════════════════════════════════════════════════════════════════════════════

local g = sfui.config
local common = sfui.common

sfui.options.RegisterTab({
    id = "hide",
    name = "hide",
    build = function(panel, tab_button, options_frame)
        local create_checkbox = common.create_checkbox
        local white = sfui.config.colors.white

        local function notify_change(key, val)
            sfui.options.notify_setting_changed("hide", key, val)
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- 1. Main Header
        -- ─────────────────────────────────────────────────────────────────────
        local main_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("frame suppression & error filter")

        -- ─────────────────────────────────────────────────────────────────────
        -- 2. Unit & HUD Frames Suppression
        -- ─────────────────────────────────────────────────────────────────────
        local uf_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        uf_header:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -20)
        uf_header:SetTextColor(white[1], white[2], white[3])
        uf_header:SetText("blizzard unit & hud frames")

        local uf_desc = panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        uf_desc:SetPoint("TOPLEFT", uf_header, "BOTTOMLEFT", 0, -4)
        uf_desc:SetTextColor(0.7, 0.7, 0.7)
        uf_desc:SetText("safely hide default blizzard frames with zero combat taint or errors.")

        local ufEntriesCol1 = {
            { key = "hide_player_frame", label = "hide player frame", tooltip = "hides the default blizzard player frame." },
            { key = "hide_target_frame", label = "hide target frame", tooltip = "hides the default blizzard target frame." },
            { key = "hide_totem_bar",    label = "hide totem bar",    tooltip = "hides the default blizzard totem bar and totem frame." },
            { key = "hide_micromenu",    label = "hide game menu",    tooltip = "hides the default blizzard game menu (micro menu)." },
        }

        local ufEntriesCol2 = {
            { key = "hide_pet_frame",    label = "hide pet frame",    tooltip = "hides the default blizzard pet frame." },
            { key = "hide_focus_frame",  label = "hide focus frame",  tooltip = "hides the default blizzard focus frame." },
            { key = "hide_bagsbar",      label = "hide bags bar",     tooltip = "hides the default blizzard bags bar." },
        }

        local prevUFCol1 = uf_desc
        for i, u in ipairs(ufEntriesCol1) do
            local cb = create_checkbox(
                panel,
                u.label,
                u.key,
                function(checked)
                    notify_change(u.key, checked)
                    sfui.hide.ApplyAllUnitFrames()
                end,
                u.tooltip
            )
            cb:SetPoint("TOPLEFT", prevUFCol1, "BOTTOMLEFT", 0, (i == 1) and -12 or -10)
            prevUFCol1 = cb
        end

        local prevUFCol2 = nil
        for i, u in ipairs(ufEntriesCol2) do
            local cb = create_checkbox(
                panel,
                u.label,
                u.key,
                function(checked)
                    notify_change(u.key, checked)
                    sfui.hide.ApplyAllUnitFrames()
                end,
                u.tooltip
            )
            if i == 1 then
                cb:SetPoint("TOPLEFT", uf_desc, "BOTTOMLEFT", 220, -12)
            else
                cb:SetPoint("TOPLEFT", prevUFCol2, "BOTTOMLEFT", 0, -10)
            end
            prevUFCol2 = cb
        end

        -- ─────────────────────────────────────────────────────────────────────
        -- 3. Error Frame Filtering
        -- ─────────────────────────────────────────────────────────────────────
        local err_header = panel:CreateFontString(nil, "OVERLAY", g.font)
        err_header:SetPoint("TOPLEFT", prevUFCol1, "BOTTOMLEFT", 0, -25)
        err_header:SetTextColor(white[1], white[2], white[3])
        err_header:SetText("ui error messages")

        local err_desc = panel:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        err_desc:SetPoint("TOPLEFT", err_header, "BOTTOMLEFT", 0, -4)
        err_desc:SetTextColor(0.7, 0.7, 0.7)
        err_desc:SetText("filter repetitive combat cooldown spam from the error frame.")

        local err_cb = create_checkbox(
            panel,
            "hide 'spell is not ready yet'",
            "hide_cooldown_errors",
            function(checked)
                notify_change("hide_cooldown_errors", checked)
                sfui.hide.ApplyErrorFilters()
            end,
            "filters out 'spell is not ready yet', 'not enough energy', and ability cooldown errors."
        )
        err_cb:SetPoint("TOPLEFT", err_desc, "BOTTOMLEFT", 0, -10)

        panel.customContentHeight = 350
    end,
})
