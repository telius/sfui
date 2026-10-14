local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local _G = _G
local GameTooltip = _G.GameTooltip
local GetCursorInfo = _G.GetCursorInfo
local ClearCursor = _G.ClearCursor
local InCombatLockdown = _G.InCombatLockdown
local Settings = _G.Settings
local KeyBindingFrame_LoadUI = _G.KeyBindingFrame_LoadUI
local ShowUIPanel = _G.ShowUIPanel
local KeyBindingFrame = _G.KeyBindingFrame
local tonumber = _G.tonumber
local tostring = _G.tostring

sfui.options.RegisterTab({
    id = "ring",
    name = "rings",
    build = function(p, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        -- ── Header ──────────────────────────────────────────────────────────
        local main_header = p:CreateFontString(nil, "OVERLAY", g.font_large)
        main_header:SetPoint("TOPLEFT", 15, -15)
        main_header:SetTextColor(white[1], white[2], white[3])
        main_header:SetText("radial action rings")

        local main_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        main_desc:SetPoint("TOPLEFT", main_header, "BOTTOMLEFT", 0, -4)
        main_desc:SetTextColor(0.7, 0.7, 0.7)
        main_desc:SetText("opie-style quickdraw action rings. hold key, flick toward slot, release to cast.")

        -- ── Section 1: Dedicated Hardware Keybinds ────────────────────────────
        local keybind_header = p:CreateFontString(nil, "OVERLAY", g.font)
        keybind_header:SetPoint("TOPLEFT", main_desc, "BOTTOMLEFT", 0, -18)
        keybind_header:SetTextColor(0, 1, 1, 1)
        keybind_header:SetText("ring keybindings")

        local keybind_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        keybind_desc:SetPoint("TOPLEFT", keybind_header, "BOTTOMLEFT", 0, -4)
        keybind_desc:SetTextColor(0.7, 0.7, 0.7)
        keybind_desc:SetText("assign hardware keybinds for each radial ring. click to bind, right-click to clear.")

        -- keybind rows
        local rows = {
            { id = "utility",       label = "class & custom:",    title = "class utility & custom ring keybind" },
            { id = "tracking",      label = "minimap tracking:", title = "minimap tracking keybind" },
            { id = "professions",   label = "professions:",       title = "professions keybind" },
            { id = "questitems",    label = "quest items:",       title = "quest items keybind" },
            { id = "targetmarkers", label = "target markers:",    title = "target markers keybind" },
            { id = "worldmarkers",  label = "world markers:",     title = "world markers keybind" },
        }

        local keybindWidgets = {}
        local prevAnchor = keybind_desc
        for i = 1, #rows do
            local item = rows[i]
            local kw = common.create_keybind_input(
                p,
                item.label,
                function() return sfui.ring.get_binding(item.id) end,
                function(key) sfui.ring.set_binding(item.id, key) end,
                function() sfui.ring.unbind(item.id) end,
                item.title,
                "hold key to open radial ring, flick toward slice, release to cast.",
                380
            )
            kw:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, i == 1 and -10 or -6)
            prevAnchor = kw
            keybindWidgets[#keybindWidgets + 1] = kw
        end

        -- ── Section 2: Class Utility & Custom Drop Slots ──────────────────────
        local custom_header = p:CreateFontString(nil, "OVERLAY", g.font)
        custom_header:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -18)
        custom_header:SetTextColor(0, 1, 1, 1)
        custom_header:SetText("custom ring actions (spec profile)")

        local spec_info = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        spec_info:SetPoint("TOPLEFT", custom_header, "BOTTOMLEFT", 0, -4)
        spec_info:SetTextColor(0.85, 0.85, 0.85)

        local custom_desc = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        custom_desc:SetPoint("TOPLEFT", spec_info, "BOTTOMLEFT", 0, -4)
        custom_desc:SetTextColor(0.7, 0.7, 0.7)
        custom_desc:SetText("drag spells, abilities, items, toys, or macros onto any slot. right-click to clear.")

        local slotButtons = {}
        local refresh_all_slots

        local function handle_slot_drop(slotIdx)
            local cursorType, val1, _, val3 = GetCursorInfo()
            if not cursorType then return end

            local util = sfui.ring.utility
            if not util then return end

            local slotData = nil
            if cursorType == "spell" then
                local spellID = val3 or val1
                local name, icon = util.get_spell_details(spellID)
                slotData = {
                    type = "spell",
                    id   = spellID,
                    name = name or tostring(spellID),
                    icon = icon,
                }
            elseif cursorType == "item" then
                local itemID = val1
                local name, icon = util.get_item_details(itemID)
                slotData = {
                    type = "item",
                    id   = itemID,
                    name = name or tostring(itemID),
                    icon = icon,
                }
            elseif cursorType == "toy" then
                local toyID = val1
                local name, icon = util.get_toy_details(toyID)
                slotData = {
                    type = "toy",
                    id   = toyID,
                    name = name or tostring(toyID),
                    icon = icon,
                }
            elseif cursorType == "macro" then
                local macroIdx = val1
                local name, icon = util.get_macro_details(macroIdx)
                slotData = {
                    type = "macro",
                    id   = macroIdx,
                    name = name or ("macro " .. tostring(macroIdx)),
                    icon = icon,
                }
            elseif cursorType == "mount" then
                local mountID = val1
                if _G.C_MountJournal and _G.C_MountJournal.GetMountInfoByID then
                    local name, spellID, icon = _G.C_MountJournal.GetMountInfoByID(mountID)
                    if spellID then
                        slotData = {
                            type = "spell",
                            id   = spellID,
                            name = name or tostring(spellID),
                            icon = icon,
                        }
                    end
                end
            end

            if slotData then
                ClearCursor()
                local playerClass, specID = util.get_class_and_spec()
                util.set_spec_slot(playerClass, specID, slotIdx, slotData)
                if refresh_all_slots then
                    refresh_all_slots()
                end
            end
        end

        local function handle_slot_click(slotIdx, button)
            local util = sfui.ring.utility
            if not util then return end

            local playerClass, specID = util.get_class_and_spec()
            if button == "RightButton" then
                util.clear_spec_slot(playerClass, specID, slotIdx)
                if refresh_all_slots then
                    refresh_all_slots()
                end
                if GameTooltip:IsOwned(slotButtons[slotIdx]) then
                    GameTooltip:Hide()
                end
            elseif button == "LeftButton" then
                if GetCursorInfo() then
                    handle_slot_drop(slotIdx)
                end
            end
        end

        local function show_slot_tooltip(self, slotIdx)
            local data = self._slotData
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if data and data.type and data.id then
                if data.type == "spell" then
                    if GameTooltip.SetSpellByID and tonumber(data.id) then
                        GameTooltip:SetSpellByID(tonumber(data.id))
                    else
                        GameTooltip:AddLine(data.name or "spell", 1, 1, 1)
                    end
                elseif data.type == "item" then
                    if GameTooltip.SetItemByID and tonumber(data.id) then
                        GameTooltip:SetItemByID(tonumber(data.id))
                    else
                        GameTooltip:AddLine(data.name or "item", 1, 1, 1)
                    end
                elseif data.type == "toy" then
                    if GameTooltip.SetToyByItemID and tonumber(data.id) then
                        GameTooltip:SetToyByItemID(tonumber(data.id))
                    else
                        GameTooltip:AddLine(data.name or "toy", 1, 1, 1)
                    end
                elseif data.type == "macro" then
                    GameTooltip:AddLine(data.name or ("macro " .. tostring(data.id)), 1, 1, 1)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff00e5ffslot " .. slotIdx .. "|r  |cff888888(left-click to drop, right-click to remove)|r", 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("custom slot " .. slotIdx, 1, 1, 1)
                GameTooltip:AddLine("empty slot", 0.6, 0.6, 0.6)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cff888888drag and drop a spell, ability, item, toy, or macro here.|r", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end

        -- create 12 interactive drop buttons (2 rows of 6)
        local slotSize = 40
        local slotSpacing = 8
        local slotsContainer = _G.CreateFrame("Frame", nil, p)
        slotsContainer:SetSize(6 * slotSize + 5 * slotSpacing, 2 * slotSize + slotSpacing)
        slotsContainer:SetPoint("TOPLEFT", custom_desc, "BOTTOMLEFT", 0, -10)

        for i = 1, 12 do
            local row = (i <= 6) and 1 or 2
            local col = (i <= 6) and i or (i - 6)

            local btn = _G.CreateFrame("Button", nil, slotsContainer)
            btn:SetSize(slotSize, slotSize)
            btn:SetPoint("TOPLEFT", slotsContainer, "TOPLEFT", (col - 1) * (slotSize + slotSpacing), -((row - 1) * (slotSize + slotSpacing)))
            btn:EnableMouse(true)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:RegisterForDrag("LeftButton")

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(btn)
            btn.icon = icon

            sfui.widgets.apply_round_icon_style(btn, icon, 1.5, { 0.2, 0.2, 0.2, 0.85 })

            local slotNum = btn:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
            slotNum:SetPoint("CENTER", btn, "CENTER", 0, 0)
            slotNum:SetTextColor(0.45, 0.45, 0.45, 1)
            slotNum:SetText(tostring(i))
            btn.slotNum = slotNum

            btn:SetScript("OnReceiveDrag", function()
                handle_slot_drop(i)
            end)

            btn:SetScript("OnClick", function(self, button)
                handle_slot_click(i, button)
            end)

            btn:SetScript("OnEnter", function(self)
                if self.roundBorder then
                    self.roundBorder:SetColorTexture(0, 0.9, 1, 1)
                end
                show_slot_tooltip(self, i)
            end)

            btn:SetScript("OnLeave", function(self)
                if self.roundBorder then
                    if self._slotData and self._slotData.id then
                        self.roundBorder:SetColorTexture(0, 0, 0, 0.85)
                    else
                        self.roundBorder:SetColorTexture(0.2, 0.2, 0.2, 0.85)
                    end
                end
                GameTooltip:Hide()
            end)

            slotButtons[i] = btn
        end

        refresh_all_slots = function()
            local util = sfui.ring.utility
            if not util then return end

            local playerClass, specID = util.get_class_and_spec()
            local specName = (sfui.talents and sfui.talents.get_spec_name and sfui.talents.get_spec_name(specID))
            if not specName or specName == "" or specName:find("Spec ") then
                specName = "general profile"
            end
            spec_info:SetText("active specialization: |cffffffff" .. specName:lower() .. "|r  |cff888888(" .. playerClass:lower() .. ")|r")

            local slots = util.get_spec_slots(playerClass, specID)
            for i = 1, 12 do
                local btn = slotButtons[i]
                local data = slots[i]
                btn._slotData = data

                if data and data.type and data.id then
                    local icon = data.icon
                    if not icon then
                        if data.type == "spell" then
                            _, icon = util.get_spell_details(data.id)
                        elseif data.type == "item" then
                            _, icon = util.get_item_details(data.id)
                        elseif data.type == "toy" then
                            _, icon = util.get_toy_details(data.id)
                        elseif data.type == "macro" then
                            _, icon = util.get_macro_details(data.id)
                        end
                    end
                    btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.icon:Show()
                    btn.slotNum:Hide()
                    if btn.roundBorder then
                        btn.roundBorder:SetColorTexture(0, 0, 0, 0.85)
                    end
                else
                    btn.icon:SetTexture(nil)
                    btn.icon:Hide()
                    btn.slotNum:SetText(tostring(i))
                    btn.slotNum:Show()
                    if btn.roundBorder then
                        btn.roundBorder:SetColorTexture(0.2, 0.2, 0.2, 0.85)
                    end
                end
            end
        end

        local reset_btn = CreateFlatButton(p, "reset spec to defaults", 150, 22, function()
            local util = sfui.ring.utility
            if not util then return end
            local playerClass, specID = util.get_class_and_spec()
            util.reset_spec_to_defaults(playerClass, specID)
            refresh_all_slots()
        end)
        reset_btn:SetPoint("TOPLEFT", slotsContainer, "BOTTOMLEFT", 0, -10)

        local clear_btn = CreateFlatButton(p, "clear all slots", 120, 22, function()
            local util = sfui.ring.utility
            if not util then return end
            local playerClass, specID = util.get_class_and_spec()
            util.clear_all_spec_slots(playerClass, specID)
            refresh_all_slots()
        end)
        clear_btn:SetPoint("LEFT", reset_btn, "RIGHT", 10, 0)

        -- ── Section 3: General Settings ───────────────────────────────────────
        local settings_header = p:CreateFontString(nil, "OVERLAY", g.font)
        settings_header:SetPoint("TOPLEFT", reset_btn, "BOTTOMLEFT", 0, -18)
        settings_header:SetTextColor(0, 1, 1, 1)
        settings_header:SetText("appearance & interaction")

        local cb_enabled = sfui.widgets.create_checkbox(
            p,
            "enable radial rings",
            function() return sfui.db.Get("ring", "enabled", true) end,
            function(val) sfui.db.Set("ring", "enabled", val) end,
            "master toggle for the radial action rings module."
        )
        cb_enabled:SetPoint("TOPLEFT", settings_header, "BOTTOMLEFT", 0, -8)

        local cb_labels = sfui.widgets.create_checkbox(
            p,
            "show slice labels",
            function() return sfui.db.Get("ring", "show_labels", true) end,
            function(val) sfui.db.Set("ring", "show_labels", val) end,
            "display text labels below each radial slot icon."
        )
        cb_labels:SetPoint("TOPLEFT", cb_enabled, "BOTTOMLEFT", 0, -4)

        local cb_sounds = sfui.widgets.create_checkbox(
            p,
            "play sound cues on hover",
            function() return sfui.db.Get("ring", "sound_cues", true) end,
            function(val) sfui.db.Set("ring", "sound_cues", val) end,
            "play a subtle click sound when cursor flicks to a new slot."
        )
        cb_sounds:SetPoint("TOPLEFT", cb_labels, "BOTTOMLEFT", 0, -4)

        local slider_radius = sfui.widgets.create_slider_input(
            p,
            "ring radius",
            function() return sfui.db.Get("ring", "radius", 95) end,
            70, 180, 5,
            function(val) sfui.db.Set("ring", "radius", val) end,
            "distance of slot icons from the ring center.",
            220
        )
        slider_radius:SetPoint("TOPLEFT", cb_sounds, "BOTTOMLEFT", 0, -12)

        local slider_deadzone = sfui.widgets.create_slider_input(
            p,
            "deadzone radius",
            function() return sfui.db.Get("ring", "deadzone", 28) end,
            15, 60, 2,
            function(val) sfui.db.Set("ring", "deadzone", val) end,
            "minimum cursor travel before a slice is highlighted. releasing inside cancels.",
            220
        )
        slider_deadzone:SetPoint("TOPLEFT", slider_radius, "BOTTOMLEFT", 0, -12)

        local slider_size = sfui.widgets.create_slider_input(
            p,
            "slot size",
            function() return sfui.db.Get("ring", "slot_size", 40) end,
            28, 64, 2,
            function(val) sfui.db.Set("ring", "slot_size", val) end,
            "pixel dimensions of each radial slot icon.",
            220
        )
        slider_size:SetPoint("TOPLEFT", slider_deadzone, "BOTTOMLEFT", 0, -12)

        -- ── Section 4: Shortcuts & Hints ──────────────────────────────────────
        local blizz_btn = CreateFlatButton(p, "blizzard keybindings", 150, 22, function()
            if InCombatLockdown and InCombatLockdown() then return end
            if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            elseif KeyBindingFrame_LoadUI then
                KeyBindingFrame_LoadUI()
                ShowUIPanel(KeyBindingFrame)
            end
        end)
        blizz_btn:SetPoint("TOPLEFT", slider_size, "BOTTOMLEFT", 0, -16)

        local tips_text = p:CreateFontString(nil, "OVERLAY", g.font_small or g.font)
        tips_text:SetPoint("TOPLEFT", blizz_btn, "BOTTOMLEFT", 0, -12)
        tips_text:SetTextColor(0.65, 0.65, 0.65, 1)
        tips_text:SetWidth(500)
        tips_text:SetJustifyH("LEFT")
        tips_text:SetText(
            "• |cffffffffhold & release|r: press and hold the key to open the ring at your cursor. flick toward any slice and let go of the key to cast.\n\n" ..
            "• |cffffffffdeadzone cancel|r: release inside the center circle or press escape to cancel without performing an action.\n\n" ..
            "• |cffffffffcombat safe|r: bindings and slices are securely cached so the ring works seamlessly during combat."
        )

        -- update displays on show or bindings change
        p:HookScript("OnShow", function()
            for i = 1, #keybindWidgets do
                if keybindWidgets[i].update_keybind_display then
                    keybindWidgets[i].update_keybind_display()
                end
            end
            if refresh_all_slots then
                refresh_all_slots()
            end
        end)

        sfui.events.RegisterEvent("UPDATE_BINDINGS", function()
            if p:IsVisible() then
                for i = 1, #keybindWidgets do
                    if keybindWidgets[i].update_keybind_display then
                        keybindWidgets[i].update_keybind_display()
                    end
                end
            end
        end)

        local function on_spec_or_spells_updated()
            if p:IsVisible() and refresh_all_slots then
                refresh_all_slots()
            end
        end

        sfui.events.RegisterEvent("SPELLS_CHANGED", on_spec_or_spells_updated)
        sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", on_spec_or_spells_updated)
        sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_spec_or_spells_updated)
        sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", on_spec_or_spells_updated)
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", on_spec_or_spells_updated)
    end,
})
