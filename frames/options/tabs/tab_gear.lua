local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local C_EquipmentSet = _G.C_EquipmentSet
local ipairs = _G.ipairs
local table_insert = table.insert

sfui.options.RegisterTab({
    id = "gear",
    name = "gear swapper",
    build = function(gear_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local gear_header = gear_panel:CreateFontString(nil, "OVERLAY", g.font)
        gear_header:SetPoint("TOPLEFT", 15, -15)
        gear_header:SetTextColor(white[1], white[2], white[3])
        gear_header:SetText("automatic gear swapper settings")

        local gear_info = gear_panel:CreateFontString(nil, "OVERLAY", g.font)
        gear_info:SetPoint("TOPLEFT", gear_header, "BOTTOMLEFT", 0, -10)
        gear_info:SetPoint("RIGHT", -15, 0)
        gear_info:SetJustifyH("LEFT")
        gear_info:SetText(
            "automatically swap to a configured gear set based on the content. entering pvp instances or warmode world zones will equip the pvp set. everything else will equip the pve set."
        )

        local function GetEquipmentSetOptions()
            local options = { { text = "None", value = "" } }
            if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
                local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
                if setIDs then
                    for _, id in ipairs(setIDs) do
                        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                        if name then table_insert(options, { text = name, value = name }) end
                    end
                end
            end
            return options
        end

        local updateFuncs = {}

        gear_panel:SetScript("OnShow", function(self)
            if self.initialized then
                for _, f in ipairs(updateFuncs) do f() end
                return
            end
            self.initialized = true

            local _, gearSpecIDs = common.get_player_specs()

            local open_gear_btn = CreateFlatButton(gear_panel, "open gear manager", 140, 22)
            open_gear_btn:SetPoint("TOPLEFT", gear_info, "BOTTOMLEFT", 0, -10)
            open_gear_btn:SetScript("OnClick", function()
                if sfui.gear and sfui.gear.toggle then
                    sfui.gear.toggle()
                end
            end)

            local gear_auto_open_cb = common.create_checkbox(gear_panel, "Auto-show with Character Panel", function()
                if SfuiDB.gear and SfuiDB.gear.auto_open ~= nil then return SfuiDB.gear.auto_open end
                return true
            end, function(checked)
                SfuiDB.gear = SfuiDB.gear or {}
                SfuiDB.gear.auto_open = checked
            end)
            gear_auto_open_cb:SetPoint("TOPLEFT", open_gear_btn, "BOTTOMLEFT", 0, -10)

            local auto_equip_highest_cb = common.create_checkbox(gear_panel,
                "auto-equip best gear (while not max level)", function()
                if SfuiDB.gear and SfuiDB.gear.auto_equip_highest ~= nil then return SfuiDB.gear.auto_equip_highest end
                return true
            end, function(checked)
                SfuiDB.gear = SfuiDB.gear or {}
                SfuiDB.gear.auto_equip_highest = checked
                if SfuiGearManagerFrame and SfuiGearManagerFrame.maxLvlChk then
                    SfuiGearManagerFrame.maxLvlChk:SetChecked(checked)
                end
                if checked and sfui.gear and sfui.gear.Update then
                    sfui.gear.Update()
                end
            end)
            auto_equip_highest_cb:SetPoint("TOPLEFT", gear_auto_open_cb, "BOTTOMLEFT", 0, -10)

            local pveHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pveHeader:SetPoint("TOPLEFT", auto_equip_highest_cb, "BOTTOMLEFT", 45, -12)
            pveHeader:SetText("PvE Target")

            local pvpHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pvpHeader:SetPoint("LEFT", pveHeader, "RIGHT", 80, 0)
            pvpHeader:SetText("PvP Target")

            local prevRowAnchor
            for i, id in ipairs(gearSpecIDs or {}) do
                local icon = common.get_spec_icon(id)

                local iconTex = self:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(32, 32)
                if i == 1 then
                    iconTex:SetPoint("TOPLEFT", auto_equip_highest_cb, "BOTTOMLEFT", 0, -32)
                else
                    iconTex:SetPoint("TOPLEFT", prevRowAnchor, "BOTTOMLEFT", 0, -12)
                end
                iconTex:SetTexture(icon)

                local pveDrop = common.create_dropdown(gear_panel, 120, GetEquipmentSetOptions, function(val)
                    SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                    SfuiDB.gear[id].pve_set = val
                    if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
                end, "")
                pveDrop:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", 5, -5)

                local pvpDrop = common.create_dropdown(gear_panel, 120, GetEquipmentSetOptions, function(val)
                    SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                    SfuiDB.gear[id].pvp_set = val
                    if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
                end, "")
                pvpDrop:SetPoint("LEFT", pveDrop, "RIGHT", 5, 0)

                table_insert(updateFuncs, function()
                    local db = SfuiDB.gear[id]
                    if db then
                        pveDrop:SetText(db.pve_set ~= "" and db.pve_set or "None")
                        pvpDrop:SetText(db.pvp_set ~= "" and db.pvp_set or "None")
                    end
                end)

                updateFuncs[#updateFuncs]()
                prevRowAnchor = iconTex
            end
        end)
    end,
})
