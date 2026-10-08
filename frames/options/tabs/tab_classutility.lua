local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local _G = _G
local UnitClass = _G.UnitClass
local tonumber = _G.tonumber

sfui.options.RegisterTab({
    id = "classutility",
    name = "class utility",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local COL_OFFSET_X = 265
        local _, playerClass = UnitClass("player")

        -- ── Camelot / Classic Era: Class Utility ──────────────────────────────
        local main_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("class utility")

        local main_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        main_desc:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -4)
        main_desc:SetTextColor(0.7, 0.7, 0.7)
        main_desc:SetText("class-specific tools, automation, and shared keybinds.")

        -- ── Section 1: Singular Shared Keybind ───────────────────────────────
        local keybind_header = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_header:SetPoint("TOPLEFT", main_desc, "BOTTOMLEFT", 0, -14)
        keybind_header:SetTextColor(0, 1, 1, 1)
        keybind_header:SetText("class utility keybind")

        local role_str = (playerClass == "SHAMAN" and "|cff00fffftotem sequence|r (casts totems in order)")
            or (playerClass == "WARLOCK" and "|cff00ffffsoul shard purge|r (prunes excess shards)")
            or "|cffaaaaaaclass utility (dormant on this class)|r"

        local role_label = p:CreateFontString(nil, "OVERLAY", g.font)
        role_label:SetPoint("TOPLEFT", keybind_header, "BOTTOMLEFT", 0, -4)
        role_label:SetTextColor(white[1], white[2], white[3])
        role_label:SetText("active function: " .. role_str)

        local keybind_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_desc:SetPoint("TOPLEFT", role_label, "BOTTOMLEFT", 0, -4)
        keybind_desc:SetTextColor(0.7, 0.7, 0.7)
        keybind_desc:SetText("shared keybind that adapts to your character (shaman: totem sequence, warlock: shard purge).")

        local keybind_widget = common.create_keybind_input(
            p,
            "utility keybind:",
            function() return sfui.keybinds.GetClassUtilityKey() end,
            function(key) return sfui.keybinds.SetClassUtilityKey(key) end,
            function() return sfui.keybinds.UnbindClassUtilityKey() end,
            "class utility keybind",
            "casts totem sequence (shaman) or purges shards (warlock)."
        )
        keybind_widget:SetPoint("TOPLEFT", keybind_desc, "BOTTOMLEFT", 0, -10)

        local macro_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        macro_hint:SetPoint("TOPLEFT", keybind_widget, "BOTTOMLEFT", 0, -6)
        macro_hint:SetTextColor(0.5, 0.75, 0.85)
        macro_hint:SetText("macro: /click SfuiClassUtilityBtn")

        -- ── Section 2: Shaman Totem Bar & Cast Sequencer ─────────────────────
        local shaman_tag = (playerClass == "SHAMAN" and " |cff00ff00(your class)|r" or "")
        local shaman_header = p:CreateFontString(nil, "OVERLAY", g.font)
        shaman_header:SetPoint("TOPLEFT", macro_hint, "BOTTOMLEFT", 0, -20)
        shaman_header:SetTextColor(0, 1, 1, 1)
        shaman_header:SetText("shaman: totem bar" .. shaman_tag)

        local shaman_guide = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        shaman_guide:SetPoint("TOPLEFT", shaman_header, "BOTTOMLEFT", 0, -4)
        shaman_guide:SetTextColor(0.7, 0.7, 0.7)
        shaman_guide:SetText("scroll icon to pick totem • left-click to cast • right-click to recall/destroy.")

        local totem_enable_cb = create_checkbox(
            p,
            "enable totem bar",
            function()
                if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.enabled ~= nil then
                    return SfuiDB.totembar.enabled
                end
                return sfui.config and sfui.config.totembar and sfui.config.totembar.enabled ~= false
            end,
            function(checked)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.enabled = checked
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "toggle the standalone totem bar."
        )
        totem_enable_cb:SetPoint("TOPLEFT", shaman_guide, "BOTTOMLEFT", 0, -8)

        local totem_element_cb = create_checkbox(
            p,
            "color borders by element",
            function()
                if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.colorByElement ~= nil then
                    return SfuiDB.totembar.colorByElement
                end
                return sfui.config and sfui.config.totembar and sfui.config.totembar.colorByElement ~= false
            end,
            function(checked)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.colorByElement = checked
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "color borders and glows by elemental school."
        )
        totem_element_cb:SetPoint("LEFT", totem_enable_cb, "LEFT", COL_OFFSET_X, 0)

        local totem_timer_cb = create_checkbox(
            p,
            "show timer text",
            function()
                if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showTimerText ~= nil then
                    return SfuiDB.totembar.showTimerText
                end
                return sfui.config and sfui.config.totembar and sfui.config.totembar.showTimerText ~= false
            end,
            function(checked)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.showTimerText = checked
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "show active totem countdown timer."
        )
        totem_timer_cb:SetPoint("TOPLEFT", totem_enable_cb, "BOTTOMLEFT", 0, -8)

        local totem_glow_cb = create_checkbox(
            p,
            "show active glow",
            function()
                if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showGlow ~= nil then
                    return SfuiDB.totembar.showGlow
                end
                return sfui.config and sfui.config.totembar and sfui.config.totembar.showGlow ~= false
            end,
            function(checked)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.showGlow = checked
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "show glow around active totems."
        )
        totem_glow_cb:SetPoint("LEFT", totem_timer_cb, "LEFT", COL_OFFSET_X, 0)

        local totem_size_slider = create_slider_input(
            p,
            "icon size:",
            function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.size or 36 end,
            24, 64, 2,
            function(val)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.size = val
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "button size in pixels (default 36)."
        )
        totem_size_slider:SetPoint("TOPLEFT", totem_timer_cb, "BOTTOMLEFT", 0, -10)

        local totem_spacing_slider = create_slider_input(
            p,
            "spacing:",
            function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.spacing or 4 end,
            0, 16, 1,
            function(val)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.spacing = val
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "spacing between buttons (default 4)."
        )
        totem_spacing_slider:SetPoint("LEFT", totem_size_slider, "LEFT", COL_OFFSET_X, 0)

        local unlock_totem_btn = CreateFlatButton(p, "unlock totem bar", 140, 22)
        unlock_totem_btn:SetPoint("TOPLEFT", totem_size_slider, "BOTTOMLEFT", 0, -10)
        unlock_totem_btn:SetScript("OnClick", function(self)
            if sfui.totembar and sfui.totembar.ToggleUnlock then
                local unlocked = sfui.totembar.ToggleUnlock()
                self:SetText(unlocked and "lock totem bar" or "unlock totem bar")
            end
        end)

        local reset_totem_btn = CreateFlatButton(p, "reset position", 120, 22)
        reset_totem_btn:SetPoint("LEFT", unlock_totem_btn, "RIGHT", 10, 0)
        reset_totem_btn:SetScript("OnClick", function()
            if sfui.totembar and sfui.totembar.ResetPosition then
                sfui.totembar.ResetPosition()
            end
        end)

        local show_seq_cb = create_checkbox(
            p,
            "show sequence button on bar",
            function()
                if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showSequenceButton ~= nil then
                    return SfuiDB.totembar.showSequenceButton
                end
                return sfui.config and sfui.config.totembar and sfui.config.totembar.showSequenceButton == true
            end,
            function(checked)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.showSequenceButton = checked
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "show 5th button on bar for sequence progress."
        )
        show_seq_cb:SetPoint("TOPLEFT", unlock_totem_btn, "BOTTOMLEFT", 0, -10)

        local seq_reset_slider = create_slider_input(
            p,
            "sequence reset (sec):",
            function() return SfuiDB and SfuiDB.totembar and SfuiDB.totembar.resetTimer or 15 end,
            5, 60, 1,
            function(val)
                SfuiDB = SfuiDB or {}
                SfuiDB.totembar = SfuiDB.totembar or {}
                SfuiDB.totembar.resetTimer = val
                if sfui.totembar and sfui.totembar.ApplySettings then
                    sfui.totembar.ApplySettings()
                end
            end,
            "seconds before sequence resets (default 15)."
        )
        seq_reset_slider:SetPoint("LEFT", show_seq_cb, "LEFT", COL_OFFSET_X, 0)

        -- ── Section 3: Warlock Soul Shard Purge ───────────────────────────────
        local warlock_tag = (playerClass == "WARLOCK" and " |cff00ff00(your class)|r" or "")
        local warlock_header = p:CreateFontString(nil, "OVERLAY", g.font)
        warlock_header:SetPoint("TOPLEFT", show_seq_cb, "BOTTOMLEFT", 0, -20)
        warlock_header:SetTextColor(0, 1, 1, 1)
        warlock_header:SetText("warlock: soul shard purge" .. warlock_tag)

        local warlock_guide = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        warlock_guide:SetPoint("TOPLEFT", warlock_header, "BOTTOMLEFT", 0, -4)
        warlock_guide:SetTextColor(0.7, 0.7, 0.7)
        warlock_guide:SetText("deletes excess soul shards out of combat down to your maximum limit.")

        local soulshard_cb = create_checkbox(
            p,
            "prompt on excess soul shards",
            function()
                local cfg = sfui.config.triage or {}
                return sfui.db.Get("triage", "deleteSoulShards", cfg.deleteSoulShards or false)
            end,
            function(checked)
                sfui.db.Set("triage", "deleteSoulShards", checked)
                if checked and sfui.triage and sfui.triage.CheckSoulShards then
                    sfui.triage.CheckSoulShards()
                end
            end,
            "show triage prompt popup when excess shards exist."
        )
        soulshard_cb:SetPoint("TOPLEFT", warlock_guide, "BOTTOMLEFT", 0, -8)

        local soulshard_preserve_cb = create_checkbox(
            p,
            "preserve soul bag slots",
            function()
                local cfg = sfui.config.triage or {}
                return sfui.db.Get("triage", "preserveSoulBag", cfg.preserveSoulBag ~= false)
            end,
            function(checked)
                sfui.db.Set("triage", "preserveSoulBag", checked)
                if checked and sfui.triage and sfui.triage.CheckSoulShards then
                    sfui.triage.CheckSoulShards()
                end
            end,
            "protect shards inside dedicated soul bags; only prune regular bags."
        )
        soulshard_preserve_cb:SetPoint("TOPLEFT", soulshard_cb, "BOTTOMLEFT", 0, -8)

        local soulshard_chat_cb = create_checkbox(
            p,
            "chat notification summary",
            function()
                local cfg = sfui.config.triage or {}
                return sfui.db.Get("triage", "soulShardChat", cfg.soulShardChat ~= false)
            end,
            function(checked)
                sfui.db.Set("triage", "soulShardChat", checked)
            end,
            "print single-line summary when shards are pruned."
        )
        soulshard_chat_cb:SetPoint("TOPLEFT", soulshard_preserve_cb, "BOTTOMLEFT", 0, -8)

        local soulshard_slider = create_slider_input(
            p,
            "max soul shards:",
            function()
                local cfg = sfui.config.triage or {}
                local val = sfui.db.Get("triage", "maxSoulShards", cfg.maxSoulShards or 20)
                return tonumber(val) or 20
            end,
            1, 32, 1,
            function(val)
                sfui.db.Set("triage", "maxSoulShards", tonumber(val) or 20)
                if sfui.triage and sfui.triage.CheckSoulShards then
                    sfui.triage.CheckSoulShards()
                end
            end,
            "max soul shards to retain in inventory (default 20).",
            220
        )
        soulshard_slider:SetPoint("TOPLEFT", soulshard_cb, "TOPLEFT", COL_OFFSET_X, 4)

        local purge_now_btn = CreateFlatButton(p, "purge excess now", 130, 22)
        purge_now_btn:SetPoint("TOPLEFT", soulshard_chat_cb, "BOTTOMLEFT", 0, -10)
        purge_now_btn:SetScript("OnClick", function()
            if sfui.triage and sfui.triage.ExecutePurge then
                sfui.triage.ExecutePurge()
            elseif sfui.triage and sfui.triage.PurgeSingleExcessSoulShard then
                sfui.triage.PurgeSingleExcessSoulShard()
            end
        end)

        local purge_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        purge_hint:SetPoint("LEFT", purge_now_btn, "RIGHT", 10, 0)
        purge_hint:SetTextColor(0.65, 0.65, 0.65, 1)
        purge_hint:SetText("macro: /click SfuiPurgeSoulShards")

        p.customContentHeight = 560
    end,
})
