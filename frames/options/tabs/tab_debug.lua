local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local tostring = _G.tostring
local tonumber = _G.tonumber
local type = _G.type
local pairs = _G.pairs
local string_format = _G.string.format
local string_match = _G.string.match
local Enum = _G.Enum
local GetShapeshiftFormID = _G.GetShapeshiftFormID
local GetShapeshiftForm = _G.GetShapeshiftForm
local IsStealthed = _G.IsStealthed

sfui.options.RegisterTab({
    id = "debug",
    name = "debug",
    icon = "Interface\\Icons\\Spell_Shadow_EvilEye",
    build = function(debug_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local function get_power_type_name(power_enum)
            if not power_enum then return "none" end
            if type(power_enum) ~= "number" then return tostring(power_enum):lower() end
            if Enum and Enum.PowerType then
                for name, value in pairs(Enum.PowerType) do
                    if value == power_enum then return name:lower() end
                end
            end
            return tostring(power_enum)
        end

        local debug_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font_large)
        debug_header:SetPoint("TOPLEFT", 15, -15)
        debug_header:SetTextColor(white[1], white[2], white[3])
        debug_header:SetText("diagnostics & debug")

        local debug_refresh_button = CreateFlatButton(debug_panel, "refresh", 100, 22)
        debug_refresh_button:SetPoint("TOPLEFT", debug_header, "BOTTOMLEFT", 0, -10)

        local memory_button = CreateFlatButton(debug_panel, "memory profiler", 130, 22)
        memory_button:SetPoint("LEFT", debug_refresh_button, "RIGHT", 10, 0)
        memory_button:SetScript("OnClick", function()
            sfui.mem.ToggleGUI()
        end)

        -- ── Column 1 Top: Character & Spec ────────────────────────────────────
        local col1_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        col1_header:SetPoint("TOPLEFT", debug_refresh_button, "BOTTOMLEFT", 0, -18)
        col1_header:SetTextColor(0, 1, 1, 1)
        col1_header:SetText("character & spec")

        local spec_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        spec_id_label:SetPoint("TOPLEFT", col1_header, "BOTTOMLEFT", 0, -10)
        spec_id_label:SetText("spec id:")

        local spec_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        spec_id_value:SetPoint("LEFT", spec_id_label, "RIGHT", 5, 0)

        local color_swatch = debug_panel:CreateTexture(nil, "ARTWORK")
        color_swatch:SetSize(16, 16)
        color_swatch:SetPoint("LEFT", spec_id_value, "RIGHT", 8, 0)
        color_swatch:SetTexture("Interface/Buttons/WHITE8X8")

        local primary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        primary_power_label:SetPoint("TOPLEFT", spec_id_label, "BOTTOMLEFT", 0, -10)
        primary_power_label:SetText("primary power:")
        local primary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        primary_power_value:SetPoint("LEFT", primary_power_label, "RIGHT", 5, 0)

        local secondary_power_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        secondary_power_label:SetPoint("TOPLEFT", primary_power_label, "BOTTOMLEFT", 0, -10)
        secondary_power_label:SetText("secondary power:")
        local secondary_power_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        secondary_power_value:SetPoint("LEFT", secondary_power_label, "RIGHT", 5, 0)

        local form_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        form_id_label:SetPoint("TOPLEFT", secondary_power_label, "BOTTOMLEFT", 0, -10)
        form_id_label:SetText("current form id:")
        local form_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        form_id_value:SetPoint("LEFT", form_id_label, "RIGHT", 5, 0)

        -- ── Column 2 Top: Modules & Automation ────────────────────────────────
        local col2_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        col2_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 280, -75)
        col2_header:SetTextColor(0, 1, 1, 1)
        col2_header:SetText("modules & automation")

        local pet_warning_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        pet_warning_label:SetPoint("TOPLEFT", col2_header, "BOTTOMLEFT", 0, -10)
        pet_warning_label:SetText("pet warning status:")
        local pet_warning_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        pet_warning_value:SetPoint("LEFT", pet_warning_label, "RIGHT", 5, 0)

        local hammer_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_label:SetPoint("TOPLEFT", pet_warning_label, "BOTTOMLEFT", 0, -10)
        hammer_label:SetText("master's hammer:")
        local hammer_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_value:SetPoint("LEFT", hammer_label, "RIGHT", 5, 0)

        local hammer_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_id_label:SetPoint("TOPLEFT", hammer_label, "BOTTOMLEFT", 0, -10)
        hammer_id_label:SetText("hammer item id:")
        local hammer_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        hammer_id_value:SetPoint("LEFT", hammer_id_label, "RIGHT", 5, 0)

        -- ── Column 1 Bottom: Spec Resolver (talents_camelot) ──────────────────
        local resolver_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        resolver_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 15, -195)
        resolver_header:SetTextColor(0, 1, 1, 1)
        resolver_header:SetText("spec resolver (talents_camelot)")

        local res_status_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_status_label:SetPoint("TOPLEFT", resolver_header, "BOTTOMLEFT", 0, -10)
        res_status_label:SetText("resolver status:")
        local res_status_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_status_value:SetPoint("LEFT", res_status_label, "RIGHT", 5, 0)

        local res_id_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_id_label:SetPoint("TOPLEFT", res_status_label, "BOTTOMLEFT", 0, -10)
        res_id_label:SetText("camelot spec id:")
        local res_id_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_id_value:SetPoint("LEFT", res_id_label, "RIGHT", 5, 0)

        local res_tree_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_tree_label:SetPoint("TOPLEFT", res_id_label, "BOTTOMLEFT", 0, -10)
        res_tree_label:SetText("dominant tree:")
        local res_tree_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_tree_value:SetPoint("LEFT", res_tree_label, "RIGHT", 5, 0)

        local res_role_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_role_label:SetPoint("TOPLEFT", res_tree_label, "BOTTOMLEFT", 0, -10)
        res_role_label:SetText("predicted role:")
        local res_role_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_role_value:SetPoint("LEFT", res_role_label, "RIGHT", 5, 0)

        local res_points_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_points_label:SetPoint("TOPLEFT", res_role_label, "BOTTOMLEFT", 0, -10)
        res_points_label:SetText("talent points:")
        local res_points_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_points_value:SetPoint("LEFT", res_points_label, "RIGHT", 5, 0)

        local res_equiv_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_equiv_label:SetPoint("TOPLEFT", res_points_label, "BOTTOMLEFT", 0, -10)
        res_equiv_label:SetText("retail equiv id:")
        local res_equiv_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        res_equiv_value:SetPoint("LEFT", res_equiv_label, "RIGHT", 5, 0)

        -- ── Column 2 Bottom: Available Swing Bars ─────────────────────────────
        local swing_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 280, -195)
        swing_header:SetTextColor(0, 1, 1, 1)
        swing_header:SetText("available swing bars")

        local swing_status_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_status_label:SetPoint("TOPLEFT", swing_header, "BOTTOMLEFT", 0, -10)
        swing_status_label:SetText("swing engine:")
        local swing_status_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_status_value:SetPoint("LEFT", swing_status_label, "RIGHT", 5, 0)

        local swing_main_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_main_label:SetPoint("TOPLEFT", swing_status_label, "BOTTOMLEFT", 0, -10)
        swing_main_label:SetText("main-hand bar:")
        local swing_main_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_main_value:SetPoint("LEFT", swing_main_label, "RIGHT", 5, 0)

        local swing_off_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_off_label:SetPoint("TOPLEFT", swing_main_label, "BOTTOMLEFT", 0, -10)
        swing_off_label:SetText("off-hand bar:")
        local swing_off_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_off_value:SetPoint("LEFT", swing_off_label, "RIGHT", 5, 0)

        local swing_ranged_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_ranged_label:SetPoint("TOPLEFT", swing_off_label, "BOTTOMLEFT", 0, -10)
        swing_ranged_label:SetText("ranged / wand bar:")
        local swing_ranged_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_ranged_value:SetPoint("LEFT", swing_ranged_label, "RIGHT", 5, 0)

        local swing_state_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_state_label:SetPoint("TOPLEFT", swing_ranged_label, "BOTTOMLEFT", 0, -10)
        swing_state_label:SetText("combat state:")
        local swing_state_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_state_value:SetPoint("LEFT", swing_state_label, "RIGHT", 5, 0)

        local swing_bars_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_bars_label:SetPoint("TOPLEFT", swing_state_label, "BOTTOMLEFT", 0, -10)
        swing_bars_label:SetText("active bars:")
        local swing_bars_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        swing_bars_value:SetPoint("LEFT", swing_bars_label, "RIGHT", 5, 0)

        -- ── Row 3: sfuibug (inhouse bugtracker) ──────────────────────────────
        local sfuibug_header = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        sfuibug_header:SetPoint("TOPLEFT", debug_panel, "TOPLEFT", 15, -450)
        sfuibug_header:SetTextColor(0, 1, 1, 1)
        sfuibug_header:SetText("sfuibug (inhouse bugtracker)")

        local sfuibug_list_btn = CreateFlatButton(debug_panel, "list errors", 90, 22)
        sfuibug_list_btn:SetPoint("TOPLEFT", sfuibug_header, "BOTTOMLEFT", 0, -8)
        sfuibug_list_btn:SetScript("OnClick", function()
            if _G.sfuibug and _G.sfuibug.List then
                _G.sfuibug.List()
            end
        end)

        local sfuibug_inspect_btn = CreateFlatButton(debug_panel, "inspect last", 95, 22)
        sfuibug_inspect_btn:SetPoint("LEFT", sfuibug_list_btn, "RIGHT", 8, 0)
        sfuibug_inspect_btn:SetScript("OnClick", function()
            if _G.sfuibug and _G.sfuibug.Inspect then
                _G.sfuibug.Inspect("last")
            end
        end)

        local sfuibug_clear_btn = CreateFlatButton(debug_panel, "clear errors", 95, 22)
        sfuibug_clear_btn:SetPoint("LEFT", sfuibug_inspect_btn, "RIGHT", 8, 0)
        sfuibug_clear_btn:SetScript("OnClick", function()
            if _G.sfuibug and _G.sfuibug.Clear then
                _G.sfuibug.Clear()
            end
            if debug_panel.update_debug_info then
                debug_panel.update_debug_info()
            end
        end)

        local sfuibug_minimap_cb = common.create_checkbox(
            debug_panel,
            "show minimap icon",
            function()
                return _G.SfuiBugDB and _G.SfuiBugDB.minimap and not _G.SfuiBugDB.minimap.hide
            end,
            function()
                if _G.sfuibug and _G.sfuibug.ToggleMinimap then
                    _G.sfuibug.ToggleMinimap()
                end
                if debug_panel.update_debug_info then
                    debug_panel.update_debug_info()
                end
            end
        )
        sfuibug_minimap_cb:SetPoint("LEFT", sfuibug_clear_btn, "RIGHT", 14, 0)

        -- Column 1
        local bug_status_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_status_label:SetPoint("TOPLEFT", sfuibug_list_btn, "BOTTOMLEFT", 0, -12)
        bug_status_label:SetText("hook status:")
        local bug_status_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_status_value:SetPoint("LEFT", bug_status_label, "RIGHT", 5, 0)

        local bug_active_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_active_label:SetPoint("TOPLEFT", bug_status_label, "BOTTOMLEFT", 0, -10)
        bug_active_label:SetText("active errors:")
        local bug_active_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_active_value:SetPoint("LEFT", bug_active_label, "RIGHT", 5, 0)

        local bug_total_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_total_label:SetPoint("TOPLEFT", bug_active_label, "BOTTOMLEFT", 0, -10)
        bug_total_label:SetText("total recorded:")
        local bug_total_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_total_value:SetPoint("LEFT", bug_total_label, "RIGHT", 5, 0)

        -- Column 2
        local bug_file_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_file_label:SetPoint("LEFT", debug_panel, "LEFT", 280, 0)
        bug_file_label:SetPoint("TOP", bug_status_label, "TOP", 0, 0)
        bug_file_label:SetText("savedvariables:")
        local bug_file_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_file_value:SetPoint("LEFT", bug_file_label, "RIGHT", 5, 0)

        local bug_minimap_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_minimap_label:SetPoint("TOPLEFT", bug_file_label, "BOTTOMLEFT", 0, -10)
        bug_minimap_label:SetText("minimap button:")
        local bug_minimap_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_minimap_value:SetPoint("LEFT", bug_minimap_label, "RIGHT", 5, 0)

        local bug_recent_label = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_recent_label:SetPoint("TOPLEFT", bug_minimap_label, "BOTTOMLEFT", 0, -10)
        bug_recent_label:SetText("latest error:")
        local bug_recent_value = debug_panel:CreateFontString(nil, "OVERLAY", g.font)
        bug_recent_value:SetPoint("LEFT", bug_recent_label, "RIGHT", 5, 0)

        local function update_debug_info()
            local specID = common.get_current_spec_id()
            spec_id_value:SetText(specID > 0 and tostring(specID) or "n/a")

            local color = common.get_class_or_spec_color()
            if color then color_swatch:SetColorTexture(color[1], color[2], color[3]) end

            primary_power_value:SetText(get_power_type_name(common.get_primary_resource()))
            secondary_power_value:SetText(get_power_type_name(common.get_secondary_resource()))

            pet_warning_value:SetText("n/a")

            if sfui.isRetail and sfui.hammer then
                local found, name, _, itemID = sfui.hammer.has_repair_hammer(true)
                if found then
                    local nameStr = (name and name:lower()) or "unknown"
                    hammer_value:SetText("|cff00ff88found|r (" .. nameStr .. ")")
                    hammer_id_value:SetText(tostring(itemID))
                else
                    hammer_value:SetText("|cffff4444not found|r")
                    hammer_id_value:SetText("none")
                end
            else
                hammer_value:SetText("n/a")
                hammer_id_value:SetText("n/a")
            end

            local formID = (GetShapeshiftFormID and GetShapeshiftFormID()) or (GetShapeshiftForm and GetShapeshiftForm()) or 0
            local isStealthed = (IsStealthed and IsStealthed()) or false
            form_id_value:SetText(tostring(formID) .. (isStealthed and " |cff00ffff(stealthed)|r" or ""))

            -- ── Spec Resolver Details (talents_camelot) ───────────────────────
            if not sfui.isRetail and sfui.talents and sfui.talents.get_classic_talent_spec_info then
                local specInfo = sfui.talents.get_classic_talent_spec_info()
                local camelotID, domTree, role = 0, 1, "DAMAGER"
                if sfui.talents._specResolver then
                    camelotID, domTree, role = sfui.talents._specResolver()
                end

                res_status_value:SetText("|cff00ff88active (camelot / classic)|r")
                res_id_value:SetText(camelotID > 0 and tostring(camelotID) or "n/a")

                local treeName = specInfo and specInfo.name or "unknown"
                local treeIdx = domTree or (specInfo and specInfo.dominantTree) or 1
                res_tree_value:SetText(string_format("tree %d (%s)", treeIdx, treeName:lower()))
                res_role_value:SetText(string_format("%s (classic: %s)", tostring(role):lower(), tostring(specInfo and specInfo.classicRole or "dps"):lower()))
                res_points_value:SetText(string_format("%d spent", tonumber(specInfo and specInfo.totalPoints) or 0))

                local eqID = specInfo and specInfo.equivSpecID
                local eqName = eqID and sfui.common and sfui.common.get_spec_name and sfui.common.get_spec_name(eqID)
                if eqID and eqID > 0 then
                    res_equiv_value:SetText(string_format("%d%s", eqID, eqName and (" (" .. eqName:lower() .. ")") or ""))
                else
                    res_equiv_value:SetText("n/a")
                end
            else
                res_status_value:SetText("|cff888888inactive (retail engine)|r")
                res_id_value:SetText(specID > 0 and tostring(specID) or "n/a")
                res_tree_value:SetText("n/a (standard specs)")
                res_role_value:SetText("n/a (retail roles)")
                res_points_value:SetText("n/a (dragonflight/tww)")
                res_equiv_value:SetText(specID > 0 and tostring(specID) or "n/a")
            end

            -- ── Available Swing Bars Details ──────────────────────────────────
            if sfui.isRetail or not _G.C_SwingTimer then
                swing_status_value:SetText("|cff888888unsupported (retail client)|r")
                swing_main_value:SetText("n/a")
                swing_off_value:SetText("n/a")
                swing_ranged_value:SetText("n/a")
                swing_state_value:SetText("n/a")
                swing_bars_value:SetText("n/a")
            else
                local sw = sfui.swing_debug_info and sfui.swing_debug_info()
                local isEnabled = SfuiDB and (SfuiDB.enableSwingBars ~= false)
                if isEnabled then
                    swing_status_value:SetText("|cff00ff88ready (c_swingtimer)|r")
                else
                    swing_status_value:SetText("|cffff4444disabled in settings|r")
                end

                if sw then
                    if sw.hasMainHand then
                        local shownStr = sw.mainShown and "|cff00ff88shown|r" or "|cff888888hidden|r"
                        swing_main_value:SetText(string_format("|cff00ff88equipped|r (%.2fs) • %s", sw.mainHandSpeed or 0, shownStr))
                    else
                        swing_main_value:SetText("|cff888888none|r")
                    end

                    if sw.hasOffHand then
                        local shownStr = sw.offShown and "|cff00ff88shown|r" or "|cff888888hidden|r"
                        swing_off_value:SetText(string_format("|cff00ff88equipped|r (%.2fs) • %s", sw.offHandSpeed or 0, shownStr))
                    else
                        swing_off_value:SetText("|cff888888none|r")
                    end

                    if sw.hasRanged then
                        local shownStr = sw.rangedShown and "|cff00ff88shown|r" or "|cff888888hidden|r"
                        local rSpeedStr = (sw.rangedSpeed and sw.rangedSpeed > 0) and string_format("(%.2fs) • ", sw.rangedSpeed) or ""
                        swing_ranged_value:SetText(string_format("|cff00ff88equipped|r %s%s", rSpeedStr, shownStr))
                    else
                        swing_ranged_value:SetText("|cff888888none|r")
                    end

                    local stateStr = sw.isAttacking and "|cff00ff88attacking|r" or "|cff888888idle (not attacking)|r"
                    if sw.isAutoRepeating then stateStr = "|cff00ffffauto-shooting|r" end
                    swing_state_value:SetText(stateStr)

                    swing_bars_value:SetText(string_format("%d created • %d visible", tonumber(sw.barCount) or 0, tonumber(sw.shownCount) or 0))
                else
                    swing_main_value:SetText("n/a")
                    swing_off_value:SetText("n/a")
                    swing_ranged_value:SetText("n/a")
                    swing_state_value:SetText("idle")
                    swing_bars_value:SetText("none")
                end
            end

            -- ── sfuibug Details & Options ─────────────────────────────────────
            local has_sfuibug = (_G.sfuibug ~= nil)
                or (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded and _G.C_AddOns.IsAddOnLoaded("sfuibug"))
                or (_G.IsAddOnLoaded and _G.IsAddOnLoaded("sfuibug"))

            if has_sfuibug then
                sfuibug_header:Show()
                sfuibug_list_btn:Show()
                sfuibug_inspect_btn:Show()
                sfuibug_clear_btn:Show()
                if sfuibug_minimap_cb then sfuibug_minimap_cb:Show() end
                bug_status_label:Show()
                bug_status_value:Show()
                bug_active_label:Show()
                bug_active_value:Show()
                bug_total_label:Show()
                bug_total_value:Show()
                bug_file_label:Show()
                bug_file_value:Show()
                bug_minimap_label:Show()
                bug_minimap_value:Show()
                bug_recent_label:Show()
                bug_recent_value:Show()
                local mode = _G.sfuibug and _G.sfuibug.captureMode or "active"
                local sunk = _G.sfuibug and _G.sfuibug.GetSunkCount and _G.sfuibug.GetSunkCount() or 0
                local statusText = string_format("|cff00ff88active (%s sink)|r", mode)
                if sunk > 0 then
                    statusText = statusText .. string_format(" |cff888888(%d sunk)|r", sunk)
                end
                bug_status_value:SetText(statusText)

                local db = _G.SfuiBugDB or {}
                local activeCount = db.order and #db.order or 0
                local totalCount = db.total_recorded or activeCount
                if activeCount > 0 then
                    bug_active_value:SetText(string_format("|cffff4444%d unique error%s|r", activeCount, activeCount == 1 and "" or "s"))
                else
                    bug_active_value:SetText("|cff00ff880 errors (clean)|r")
                end
                bug_total_value:SetText(string_format("%d occurrences", totalCount))
                bug_file_value:SetText("|cffaaaaaasfuibug.lua (~2-5kb)|r")

                local isMinimapHidden = db.minimap and db.minimap.hide
                bug_minimap_value:SetText(isMinimapHidden and "|cff888888hidden|r" or "|cff00ff88visible (curse of doom)|r")

                if sfuibug_minimap_cb and sfuibug_minimap_cb.SetChecked then
                    sfuibug_minimap_cb:SetChecked(not isMinimapHidden)
                end

                if activeCount > 0 then
                    local latestFp = db.order[activeCount]
                    local latestErr = db.errors and db.errors[latestFp]
                    if latestErr then
                        local shortFile = string_match(latestErr.file or "", "([^/]+%.lua)$") or latestErr.file or "unknown"
                        local evSuffix = (latestErr.event and latestErr.event ~= "none") and (" [" .. latestErr.event .. "]") or ""
                        bug_recent_value:SetText(string_format("[%s] %s:%d%s (x%d)", latestErr.module or "core", shortFile, latestErr.line or 0, evSuffix, latestErr.count or 1))
                    else
                        bug_recent_value:SetText("none")
                    end
                else
                    bug_recent_value:SetText("|cff888888none|r")
                end
            else
                sfuibug_header:Hide()
                sfuibug_list_btn:Hide()
                sfuibug_inspect_btn:Hide()
                sfuibug_clear_btn:Hide()
                if sfuibug_minimap_cb then sfuibug_minimap_cb:Hide() end
                bug_status_label:Hide()
                bug_status_value:Hide()
                bug_active_label:Hide()
                bug_active_value:Hide()
                bug_total_label:Hide()
                bug_total_value:Hide()
                bug_file_label:Hide()
                bug_file_value:Hide()
                bug_minimap_label:Hide()
                bug_minimap_value:Hide()
                bug_recent_label:Hide()
                bug_recent_value:Hide()
            end
        end

        debug_refresh_button:SetScript("OnClick", update_debug_info)

        debug_panel.update_debug_info = update_debug_info
        update_debug_info()
    end,
    onShow = function(debug_panel, tab_button, options_frame)
        if debug_panel and debug_panel.update_debug_info then
            debug_panel.update_debug_info()
        end
    end,
})
