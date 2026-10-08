local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

-- Only available on Camelot and Classic clients
if sfui.isRetail then return end

local g = sfui.config
local common = sfui.common

local _G = _G
local ipairs = _G.ipairs
local UIParent = _G.UIParent

sfui.options.RegisterTab({
    id = "buffs",
    name = "buffs",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local create_checkbox = common.create_checkbox
        local create_slider_input = common.create_slider_input
        local white = sfui.config.colors.white

        -- Ensure DB initialization
        SfuiDB = SfuiDB or {}
        SfuiDB.buffReminders = SfuiDB.buffReminders or {
            enabled = true,
            clickToCast = true,
            thresholdLong = 300,
            thresholdShort = 60,
            iconSize = 36,
            spacing = 4,
            hideMounted = true,
            hideRested = false,
            showExpiring = true,
            trackFood = false,
            trackFlask = false,
            trackWeaponOil = false,
            trackMinerals = true,
            trackHerbs = true,
            shamanImbueMH = "auto",
            shamanImbueOH = "auto",
            selectedPet = {},
            disabledBuffs = {},
        }
        SfuiDB.buffRemindersPos = SfuiDB.buffRemindersPos or {
            point = "BOTTOM",
            relPoint = "BOTTOM",
            x = 0,
            y = 42,
        }

        local SECTION_GAP = 18
        local COL_OFFSET_X = 260

        -- ── Header & Action Buttons ──────────────────────────────────────────
        local header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        header:SetPoint("TOPLEFT", 15, -15)
        header:SetTextColor(white[1], white[2], white[3])
        header:SetText("buff reminders (camelot)")

        local move_btn = CreateFlatButton(p, "unlock / move", 120, 22)
        move_btn:SetPoint("LEFT", header, "RIGHT", 20, 0)

        local test_btn = CreateFlatButton(p, "test preview", 110, 22)
        test_btn:SetPoint("LEFT", move_btn, "RIGHT", 8, 0)

        local reset_btn = CreateFlatButton(p, "reset position", 110, 22)
        reset_btn:SetPoint("LEFT", test_btn, "RIGHT", 8, 0)

        local function update_button_labels()
            local unlocked = sfui.buffs and sfui.buffs.IsUnlocked and sfui.buffs.IsUnlocked()
            move_btn:SetText(unlocked and "|cff00ff00lock|r" or "unlock / move")

            local testing = sfui.buffs and sfui.buffs.IsTestMode and sfui.buffs.IsTestMode()
            test_btn:SetText(testing and "|cff00ff00hide test|r" or "test preview")
        end

        move_btn:SetScript("OnClick", function()
            if sfui.buffs and sfui.buffs.ToggleLock then
                sfui.buffs.ToggleLock()
            end
            update_button_labels()
        end)

        test_btn:SetScript("OnClick", function()
            if sfui.buffs and sfui.buffs.ToggleTest then
                sfui.buffs.ToggleTest()
            end
            update_button_labels()
        end)

        -- ── Section 1: General Settings ──────────────────────────────────────
        local general_header = p:CreateFontString(nil, "OVERLAY", g.font)
        general_header:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -SECTION_GAP)
        general_header:SetTextColor(0, 1, 1, 1)
        general_header:SetText("general settings")

        local enable_cb = create_checkbox(p, "enable buff reminders", function()
            return SfuiDB.buffReminders.enabled ~= false
        end, function(checked)
            SfuiDB.buffReminders.enabled = checked
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end, "toggles the buff reminder icons on or off.")
        enable_cb:SetPoint("TOPLEFT", general_header, "BOTTOMLEFT", 0, -8)

        local expiring_cb = create_checkbox(p, "show expiring warnings", function()
            return SfuiDB.buffReminders.showExpiring ~= false
        end, function(checked)
            SfuiDB.buffReminders.showExpiring = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RequestScan()
            end
        end, "shows icons when a buff or weapon enchant has less than threshold time remaining.")
        expiring_cb:SetPoint("LEFT", enable_cb, "LEFT", COL_OFFSET_X, 0)

        local mounted_cb = create_checkbox(p, "hide while mounted / taxi", function()
            return SfuiDB.buffReminders.hideMounted ~= false
        end, function(checked)
            SfuiDB.buffReminders.hideMounted = checked
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end, "suppresses reminder icons while riding a mount, flying, or on a flight path.")
        mounted_cb:SetPoint("TOPLEFT", enable_cb, "BOTTOMLEFT", 0, -8)

        local rested_cb = create_checkbox(p, "hide in rested areas", function()
            return SfuiDB.buffReminders.hideRested == true
        end, function(checked)
            SfuiDB.buffReminders.hideRested = checked
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end, "suppresses reminder icons while resting in an inn or major city.")
        rested_cb:SetPoint("LEFT", mounted_cb, "LEFT", COL_OFFSET_X, 0)

        local click_cb = create_checkbox(p, "click to cast (out of combat)", function()
            return SfuiDB.buffReminders.clickToCast ~= false
        end, function(checked)
            SfuiDB.buffReminders.clickToCast = checked
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end, "clicking a missing reminder icon out of combat casts the spell or activates the enchant.")
        click_cb:SetPoint("TOPLEFT", mounted_cb, "BOTTOMLEFT", 0, -8)

        -- ── Section 2: Expiration Warning Thresholds ─────────────────────────
        local thresh_header = p:CreateFontString(nil, "OVERLAY", g.font)
        thresh_header:SetPoint("TOPLEFT", click_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        thresh_header:SetTextColor(0, 1, 1, 1)
        thresh_header:SetText("warning thresholds")

        local thresh_long_slider = create_slider_input(p, "long buffs warn (sec):", function()
            return SfuiDB.buffReminders.thresholdLong or 300
        end, 30, 900, 15, function(val)
            SfuiDB.buffReminders.thresholdLong = val
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RequestScan()
            end
        end)
        thresh_long_slider:SetPoint("TOPLEFT", thresh_header, "BOTTOMLEFT", 0, -8)

        local thresh_short_slider = create_slider_input(p, "short buffs warn (sec):", function()
            return SfuiDB.buffReminders.thresholdShort or 60
        end, 10, 180, 5, function(val)
            SfuiDB.buffReminders.thresholdShort = val
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RequestScan()
            end
        end)
        thresh_short_slider:SetPoint("LEFT", thresh_long_slider, "RIGHT", 15, 0)

        -- ── Section 3: Size & Layout ─────────────────────────────────────────
        local layout_header = p:CreateFontString(nil, "OVERLAY", g.font)
        layout_header:SetPoint("TOPLEFT", thresh_long_slider, "BOTTOMLEFT", 0, -SECTION_GAP)
        layout_header:SetTextColor(0, 1, 1, 1)
        layout_header:SetText("size & layout")

        local size_slider = create_slider_input(p, "icon size:", function()
            return SfuiDB.buffReminders.iconSize or 36
        end, 20, 60, 1, function(val)
            SfuiDB.buffReminders.iconSize = val
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end)
        size_slider:SetPoint("TOPLEFT", layout_header, "BOTTOMLEFT", 0, -8)

        local spacing_slider = create_slider_input(p, "spacing:", function()
            return SfuiDB.buffReminders.spacing or 4
        end, 0, 20, 1, function(val)
            SfuiDB.buffReminders.spacing = val
            if sfui.buffs and sfui.buffs.UpdateDisplay then
                sfui.buffs.UpdateDisplay()
            end
        end)
        spacing_slider:SetPoint("LEFT", size_slider, "RIGHT", 15, 0)

        local pos_x_slider = create_slider_input(p, "pos x:", function()
            return (SfuiDB.buffRemindersPos and SfuiDB.buffRemindersPos.x) or 0
        end, -1000, 1000, 1, function(val)
            SfuiDB.buffRemindersPos = SfuiDB.buffRemindersPos or {}
            SfuiDB.buffRemindersPos.x = val
            local c = sfui.buffs and sfui.buffs.container
            if c then
                local pt = SfuiDB.buffRemindersPos.point or "BOTTOM"
                local rel = SfuiDB.buffRemindersPos.relPoint or "BOTTOM"
                local y = SfuiDB.buffRemindersPos.y or 20
                c:ClearAllPoints()
                c:SetPoint(pt, UIParent, rel, val, y)
            end
        end)
        pos_x_slider:SetPoint("TOPLEFT", size_slider, "BOTTOMLEFT", 0, -10)

        local pos_y_slider = create_slider_input(p, "pos y:", function()
            return (SfuiDB.buffRemindersPos and SfuiDB.buffRemindersPos.y) or 20
        end, -1000, 1000, 1, function(val)
            SfuiDB.buffRemindersPos = SfuiDB.buffRemindersPos or {}
            SfuiDB.buffRemindersPos.y = val
            local c = sfui.buffs and sfui.buffs.container
            if c then
                local pt = SfuiDB.buffRemindersPos.point or "BOTTOM"
                local rel = SfuiDB.buffRemindersPos.relPoint or "BOTTOM"
                local x = SfuiDB.buffRemindersPos.x or 0
                c:ClearAllPoints()
                c:SetPoint(pt, UIParent, rel, x, val)
            end
        end)
        pos_y_slider:SetPoint("LEFT", pos_x_slider, "RIGHT", 15, 0)

        reset_btn:SetScript("OnClick", function()
            if sfui.buffs and sfui.buffs.ResetPosition then
                sfui.buffs.ResetPosition()
            end
            if pos_x_slider.SetSliderValue then
                pos_x_slider:SetSliderValue(0)
            end
            if pos_y_slider.SetSliderValue then
                pos_y_slider:SetSliderValue(20)
            end
        end)

        -- ── Section 4: Consumables Tracking ──────────────────────────────────
        local cons_header = p:CreateFontString(nil, "OVERLAY", g.font)
        cons_header:SetPoint("TOPLEFT", pos_x_slider, "BOTTOMLEFT", 0, -SECTION_GAP)
        cons_header:SetTextColor(0, 1, 1, 1)
        cons_header:SetText("consumables & items")

        local food_cb = create_checkbox(p, "track \"well fed\" (food)", function()
            return SfuiDB.buffReminders.trackFood == true
        end, function(checked)
            SfuiDB.buffReminders.trackFood = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RefreshSpellKnowledge()
                sfui.buffs.scan.RequestScan()
            end
        end, "reminds you when your food buff ('well fed') is missing.")
        food_cb:SetPoint("TOPLEFT", cons_header, "BOTTOMLEFT", 0, -8)

        local flask_cb = create_checkbox(p, "track flask / elixir", function()
            return SfuiDB.buffReminders.trackFlask == true
        end, function(checked)
            SfuiDB.buffReminders.trackFlask = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RefreshSpellKnowledge()
                sfui.buffs.scan.RequestScan()
            end
        end, "reminds you when a raid flask or elixir buff is missing.")
        flask_cb:SetPoint("LEFT", food_cb, "LEFT", COL_OFFSET_X, 0)

        local stone_cb = create_checkbox(p, "track sharpening stones / oils", function()
            return SfuiDB.buffReminders.trackWeaponOil == true
        end, function(checked)
            SfuiDB.buffReminders.trackWeaponOil = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RefreshSpellKnowledge()
                sfui.buffs.scan.RequestScan()
            end
        end, "reminds you when equipped weapons lack a sharpening stone, weightstone, or wizard/mana oil.")
        stone_cb:SetPoint("TOPLEFT", food_cb, "BOTTOMLEFT", 0, -8)

        -- ── Section 5: Resource Tracking ─────────────────────────────────────
        local track_header = p:CreateFontString(nil, "OVERLAY", g.font)
        track_header:SetPoint("TOPLEFT", stone_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        track_header:SetTextColor(0, 1, 1, 1)
        track_header:SetText("tracking spells (gathering)")

        local min_cb = create_checkbox(p, "track \"find minerals\" (mining)", function()
            return SfuiDB.buffReminders.trackMinerals ~= false
        end, function(checked)
            SfuiDB.buffReminders.trackMinerals = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RefreshSpellKnowledge()
                sfui.buffs.scan.RequestScan()
            end
        end, "reminds you when 'find minerals' is not active (if mining is learned).")
        min_cb:SetPoint("TOPLEFT", track_header, "BOTTOMLEFT", 0, -8)

        local herb_cb = create_checkbox(p, "track \"find herbs\" (herbalism)", function()
            return SfuiDB.buffReminders.trackHerbs ~= false
        end, function(checked)
            SfuiDB.buffReminders.trackHerbs = checked
            if sfui.buffs and sfui.buffs.scan then
                sfui.buffs.scan.RefreshSpellKnowledge()
                sfui.buffs.scan.RequestScan()
            end
        end, "reminds you when 'find herbs' is not active (if herbalism is learned).")
        herb_cb:SetPoint("LEFT", min_cb, "LEFT", COL_OFFSET_X, 0)

        -- ── Section 6: Tracked Class Buffs ───────────────────────────────────
        local class_header = p:CreateFontString(nil, "OVERLAY", g.font)
        class_header:SetPoint("TOPLEFT", min_cb, "BOTTOMLEFT", 0, -SECTION_GAP)
        class_header:SetTextColor(0, 1, 1, 1)

        local playerClass = sfui.buffs and sfui.buffs.playerClass or "CLASS"
        class_header:SetText("tracked class buffs (" .. playerClass:lower() .. ")")

        local entries = (sfui.buffs and sfui.buffs.data and sfui.buffs.data.GetClassEntries and sfui.buffs.data.GetClassEntries()) or {}
        local last_entry_anchor = class_header

        SfuiDB.buffReminders.disabledBuffs = SfuiDB.buffReminders.disabledBuffs or {}

        for i, entry in ipairs(entries) do
            local key = entry.key
            local labelText = entry.name or key

            local entry_cb = create_checkbox(p, labelText, function()
                return not SfuiDB.buffReminders.disabledBuffs[key]
            end, function(checked)
                if checked then
                    SfuiDB.buffReminders.disabledBuffs[key] = nil
                else
                    SfuiDB.buffReminders.disabledBuffs[key] = true
                end
                if sfui.buffs and sfui.buffs.scan then
                    sfui.buffs.scan.RequestScan()
                end
            end, "toggles reminders for " .. labelText .. ".")

            entry_cb:SetPoint("TOPLEFT", last_entry_anchor, "BOTTOMLEFT", 0, -8)
            last_entry_anchor = entry_cb
        end

        if playerClass == "SHAMAN" then
            local shamanImbueOptions = {
                { text = "auto (smart priority)", value = "auto" },
                { text = "rockbiter weapon",      value = "rockbiter" },
                { text = "flametongue weapon",    value = "flametongue" },
                { text = "frostbrand weapon",     value = "frostbrand" },
                { text = "windfury weapon",       value = "windfury" },
                { text = "earthliving weapon",    value = "earthliving" },
            }

            local imbue_mh_label = p:CreateFontString(nil, "OVERLAY", g.font)
            imbue_mh_label:SetPoint("TOPLEFT", last_entry_anchor, "BOTTOMLEFT", 0, -12)
            imbue_mh_label:SetTextColor(white[1], white[2], white[3])
            imbue_mh_label:SetText("preferred weapon imbue (main hand):")

            local create_dropdown = common.create_dropdown
            local curMH = (SfuiDB.buffReminders and SfuiDB.buffReminders.shamanImbueMH) or "auto"
            local mh_dropdown = create_dropdown(p, 200, shamanImbueOptions, function(val)
                SfuiDB.buffReminders = SfuiDB.buffReminders or {}
                SfuiDB.buffReminders.shamanImbueMH = val
                if sfui.buffs and sfui.buffs.scan then
                    sfui.buffs.scan.RequestScan()
                end
                if sfui.buffs and sfui.buffs.UpdateDisplay then
                    sfui.buffs.UpdateDisplay()
                end
            end, curMH, nil, 200)
            mh_dropdown:SetPoint("TOPLEFT", imbue_mh_label, "BOTTOMLEFT", 0, -4)
            mh_dropdown.tooltip = "selects the preferred weapon imbue to cast and remind for the main hand weapon."
            last_entry_anchor = mh_dropdown

            if not sfui.isCamelot and not sfui.isClassic then
                local imbue_oh_label = p:CreateFontString(nil, "OVERLAY", g.font)
                imbue_oh_label:SetPoint("TOPLEFT", mh_dropdown, "BOTTOMLEFT", 0, -10)
                imbue_oh_label:SetTextColor(white[1], white[2], white[3])
                imbue_oh_label:SetText("preferred weapon imbue (off hand):")

                local curOH = (SfuiDB.buffReminders and SfuiDB.buffReminders.shamanImbueOH) or "auto"
                local oh_dropdown = create_dropdown(p, 200, shamanImbueOptions, function(val)
                    SfuiDB.buffReminders = SfuiDB.buffReminders or {}
                    SfuiDB.buffReminders.shamanImbueOH = val
                    if sfui.buffs and sfui.buffs.scan then
                        sfui.buffs.scan.RequestScan()
                    end
                    if sfui.buffs and sfui.buffs.UpdateDisplay then
                        sfui.buffs.UpdateDisplay()
                    end
                end, curOH, nil, 200)
                oh_dropdown:SetPoint("TOPLEFT", imbue_oh_label, "BOTTOMLEFT", 0, -4)
                oh_dropdown.tooltip = "selects the preferred weapon imbue to cast and remind for the off hand weapon."
                last_entry_anchor = oh_dropdown
            end
        end

        p:SetScript("OnShow", function()
            update_button_labels()
        end)
    end,
})
