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
    name = sfui.isRetail and "portals" or "class utility",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        local COL_OFFSET_X = 265
        local _, playerClass = UnitClass("player")

        if sfui.isRetail then
            -- ── Retail: Portals Hub & Keybind ─────────────────────────────────
            local main_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
            main_header:SetPoint("TOPLEFT", 15, -15)
            main_header:SetTextColor(white[1], white[2], white[3])
            main_header:SetText("portals & teleports")

            local main_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            main_desc:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -4)
            main_desc:SetTextColor(0.7, 0.7, 0.7)
            main_desc:SetText("quick-access travel hub for hearthstones, toys, mythic+ dungeon portals, and class teleports.")

            local keybind_header = p:CreateFontString(nil, "OVERLAY", g.font)
            keybind_header:SetPoint("TOPLEFT", main_desc, "BOTTOMLEFT", 0, -18)
            keybind_header:SetTextColor(0, 1, 1, 1)
            keybind_header:SetText("portal window keybind")

            local role_label = p:CreateFontString(nil, "OVERLAY", g.font)
            role_label:SetPoint("TOPLEFT", keybind_header, "BOTTOMLEFT", 0, -4)
            role_label:SetTextColor(white[1], white[2], white[3])
            role_label:SetText("active function on this character: |cff00ffffportals popup|r")

            local keybind_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            keybind_desc:SetPoint("TOPLEFT", role_label, "BOTTOMLEFT", 0, -6)
            keybind_desc:SetTextColor(0.7, 0.7, 0.7)
            keybind_desc:SetText("one hardware keybind to toggle your quick travel hub without cluttering action bars. works seamlessly across all characters and classes.")

            local keybind_bullets = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            keybind_bullets:SetPoint("TOPLEFT", keybind_desc, "BOTTOMLEFT", 0, -6)
            keybind_bullets:SetTextColor(0.6, 0.6, 0.6)
            keybind_bullets:SetText("• hearthstones & toys: covenant, dalaran, garrison, and cosmetic hearthstone toys\n• mythic+ & raid portals: active seasonal dungeon teleports and raid gateways\n• class travel: mage teleport/portal spells, druid dreamwalk, death knight death gate\n• one-click travel: left-click to cast teleport, right-click to cast party portal")

            local keybind_widget = common.create_keybind_input(
                p,
                "portals keybind:",
                function() return sfui.keybinds.GetClassUtilityKey() end,
                function(key) return sfui.keybinds.SetClassUtilityKey(key) end,
                function() return sfui.keybinds.UnbindClassUtilityKey() end,
                "portals keybind",
                "hardware keybind: toggles the portals, hearthstones, and teleports window."
            )
            keybind_widget:SetPoint("TOPLEFT", keybind_bullets, "BOTTOMLEFT", 0, -10)

            local macro_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            macro_hint:SetPoint("TOPLEFT", keybind_widget, "BOTTOMLEFT", 0, -8)
            macro_hint:SetTextColor(0.5, 0.75, 0.85)
            macro_hint:SetText("macro triggers: /click SfuiPortalsBtn | /click SfuiClassUtilityBtn | /sfui portals")

            local portals_toggle_btn = CreateFlatButton(p, "toggle portals popup", 150, 22)
            portals_toggle_btn:SetPoint("TOPLEFT", macro_hint, "BOTTOMLEFT", 0, -14)
            portals_toggle_btn:SetScript("OnClick", function()
                if sfui.portals and sfui.portals.Toggle then
                    sfui.portals.Toggle()
                end
            end)

            local portals_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            portals_hint:SetPoint("LEFT", portals_toggle_btn, "RIGHT", 10, 0)
            portals_hint:SetTextColor(0.65, 0.65, 0.65, 1)
            portals_hint:SetText("opens or closes the travel hub")

            p.customContentHeight = 360
            return
        end

        -- ── Camelot / Classic Era: Class Utility ──────────────────────────────
        local main_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("class utility")

        local main_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        main_desc:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -4)
        main_desc:SetTextColor(0.7, 0.7, 0.7)
        main_desc:SetText("unified management for class-specific tools, automation, and shared hardware keybinds.")

        -- ── Section 1: Singular Shared Keybind ───────────────────────────────
        local keybind_header = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_header:SetPoint("TOPLEFT", main_desc, "BOTTOMLEFT", 0, -18)
        keybind_header:SetTextColor(0, 1, 1, 1)
        keybind_header:SetText("singular class utility keybind")

        local role_str = (playerClass == "SHAMAN" and "|cff00fffftotem sequence|r (casts totems in order)")
            or (playerClass == "WARLOCK" and "|cff00ffffsoul shard purge|r (deletes excess shards down to max)")
            or "|cffaaaaaaclass utility (dormant on this class)|r"

        local role_label = p:CreateFontString(nil, "OVERLAY", g.font)
        role_label:SetPoint("TOPLEFT", keybind_header, "BOTTOMLEFT", 0, -4)
        role_label:SetTextColor(white[1], white[2], white[3])
        role_label:SetText("active function on this character: " .. role_str)

        local keybind_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_desc:SetPoint("TOPLEFT", role_label, "BOTTOMLEFT", 0, -6)
        keybind_desc:SetTextColor(0.7, 0.7, 0.7)
        keybind_desc:SetText("one shared keybind for all your characters. because totem sequencing and soul shard purging are mutually exclusive class mechanics, binding this single key automatically executes the correct hardware action without binding conflicts.")

        local keybind_bullets = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_bullets:SetPoint("TOPLEFT", keybind_desc, "BOTTOMLEFT", 0, -6)
        keybind_bullets:SetTextColor(0.6, 0.6, 0.6)
        keybind_bullets:SetText("• shaman: securely cycles and casts your active totem sequence (combat protected)\n• warlock: purges excess soul shards out of combat down to your maximum limit\n• others: dormant fallback button")

        local keybind_widget = common.create_keybind_input(
            p,
            "utility keybind:",
            function() return sfui.keybinds.GetClassUtilityKey() end,
            function(key) return sfui.keybinds.SetClassUtilityKey(key) end,
            function() return sfui.keybinds.UnbindClassUtilityKey() end,
            "class utility keybind",
            "singular shared keybind: casts totem sequence (shaman) or purges shards (warlock)."
        )
        keybind_widget:SetPoint("TOPLEFT", keybind_bullets, "BOTTOMLEFT", 0, -10)

        local macro_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        macro_hint:SetPoint("TOPLEFT", keybind_widget, "BOTTOMLEFT", 0, -8)
        macro_hint:SetTextColor(0.5, 0.75, 0.85)
        macro_hint:SetText("macro triggers: /click SfuiTotemSequenceBtn (shaman) | /click SfuiPurgeSoulShards (warlock)")

        -- ── Section 2: Shaman Totem Bar & Cast Sequencer ─────────────────────
        local shaman_tag = (playerClass == "SHAMAN" and " |cff00ff00(your class)|r" or "")
        local shaman_header = p:CreateFontString(nil, "OVERLAY", g.font)
        shaman_header:SetPoint("TOPLEFT", macro_hint, "BOTTOMLEFT", 0, -24)
        shaman_header:SetTextColor(0, 1, 1, 1)
        shaman_header:SetText("shaman: totem bar & cast sequencer" .. shaman_tag)

        local shaman_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        shaman_desc:SetPoint("TOPLEFT", shaman_header, "BOTTOMLEFT", 0, -4)
        shaman_desc:SetTextColor(0.7, 0.7, 0.7)
        shaman_desc:SetText("standalone totem bar with scroll wheel selection, timers, glows, and automated /castsequence.")

        local shaman_guide = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        shaman_guide:SetPoint("TOPLEFT", shaman_desc, "BOTTOMLEFT", 0, -4)
        shaman_guide:SetTextColor(0.6, 0.6, 0.6)
        shaman_guide:SetText("• scroll wheel: hover over any element icon and scroll to cycle available totems\n• left-click: casts that individual totem directly\n• right-click: cancels / destroys that specific active totem in combat\n• cast sequence: press your keybind repeatedly to drop your totems in order")

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
            "toggles the standalone movable totem tracking bar on or off."
        )
        totem_enable_cb:SetPoint("TOPLEFT", shaman_guide, "BOTTOMLEFT", 0, -10)

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
            "colors button borders and active glows by elemental school (earth: brown, fire: orange, water: blue, air: green)."
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
            "shows countdown duration text below the totem icon when placed in the world."
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
            "shows an animated pixel glow around active totems while alive in the world."
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
            "size of each totem button in pixels (default 36)."
        )
        totem_size_slider:SetPoint("TOPLEFT", totem_timer_cb, "BOTTOMLEFT", 0, -12)

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
            "spacing between totem buttons in pixels (default 4)."
        )
        totem_spacing_slider:SetPoint("LEFT", totem_size_slider, "LEFT", COL_OFFSET_X, 0)

        local unlock_totem_btn = CreateFlatButton(p, "unlock totem bar", 140, 22)
        unlock_totem_btn:SetPoint("TOPLEFT", totem_size_slider, "BOTTOMLEFT", 0, -12)
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
            "displays a 5th button on the totem bar displaying sequence progress and allowing manual clicks."
        )
        show_seq_cb:SetPoint("TOPLEFT", unlock_totem_btn, "BOTTOMLEFT", 0, -12)

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
            "seconds of inactivity before the cast sequence resets back to the first totem (default 15)."
        )
        seq_reset_slider:SetPoint("LEFT", show_seq_cb, "LEFT", COL_OFFSET_X, 0)

        -- ── Section 3: Warlock Soul Shard Purge ───────────────────────────────
        local warlock_tag = (playerClass == "WARLOCK" and " |cff00ff00(your class)|r" or "")
        local warlock_header = p:CreateFontString(nil, "OVERLAY", g.font)
        warlock_header:SetPoint("TOPLEFT", show_seq_cb, "BOTTOMLEFT", 0, -24)
        warlock_header:SetTextColor(0, 1, 1, 1)
        warlock_header:SetText("warlock: soul shard purge & triage" .. warlock_tag)

        local warlock_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        warlock_desc:SetPoint("TOPLEFT", warlock_header, "BOTTOMLEFT", 0, -4)
        warlock_desc:SetTextColor(0.7, 0.7, 0.7)
        warlock_desc:SetText("inventory soul shard management, dedicated soul bag protection, and excess purge.")

        local warlock_guide = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        warlock_guide:SetPoint("TOPLEFT", warlock_desc, "BOTTOMLEFT", 0, -4)
        warlock_guide:SetTextColor(0.6, 0.6, 0.6)
        warlock_guide:SetText("• manual purge: press your keybind or use /click SfuiPurgeSoulShards out of combat to prune down to your max limit\n• soul bag protection: shards inside dedicated soul bags are preserved; only spillover shards in regular bags are deleted\n• combat safety: purging is completely silent and ignored in combat to prevent chat spam and cursor taint\n• audio feedback: plays a subtle interface confirmation click when shards are deleted")

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
            "shows a triage popup prompt with a [purge] button whenever excess soul shards exist. leave unchecked if you prefer using the keybind/macro."
        )
        soulshard_cb:SetPoint("TOPLEFT", warlock_guide, "BOTTOMLEFT", 0, -10)

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
            "keeps dedicated soul bags (e.g. soul pouch, box of souls, felcloth bag) intact and only prunes spillover shards taking up regular inventory bags."
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
            "prints a consolidated single-line summary to chat when soul shards are pruned."
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
            "maximum number of soul shards to retain in inventory. excess shards will be safely deleted (default 20).",
            220
        )
        soulshard_slider:SetPoint("TOPLEFT", soulshard_cb, "TOPLEFT", COL_OFFSET_X, 4)

        local purge_now_btn = CreateFlatButton(p, "purge excess now", 130, 22)
        purge_now_btn:SetPoint("TOPLEFT", soulshard_chat_cb, "BOTTOMLEFT", 0, -12)
        purge_now_btn:SetScript("OnClick", function()
            if sfui.triage and sfui.triage.PurgeSoulShards then
                sfui.triage.PurgeSoulShards(true)
            end
        end)

        local purge_hint = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        purge_hint:SetPoint("LEFT", purge_now_btn, "RIGHT", 10, 0)
        purge_hint:SetTextColor(0.65, 0.65, 0.65, 1)
        purge_hint:SetText("macro: /click SfuiPurgeSoulShards")

        p.customContentHeight = 750
    end,
})
