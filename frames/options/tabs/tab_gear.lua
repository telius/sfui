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
                sfui.gear.toggle()
            end)

            local gear_auto_open_cb = common.create_checkbox(gear_panel, "auto-show with character panel", function()
                if SfuiDB.gear and SfuiDB.gear.auto_open ~= nil then return SfuiDB.gear.auto_open end
                return true
            end, function(checked)
                SfuiDB.gear = SfuiDB.gear or {}
                SfuiDB.gear.auto_open = checked
            end)
            gear_auto_open_cb:SetPoint("TOPLEFT", open_gear_btn, "BOTTOMLEFT", 0, -10)

            local auto_equip_highest_cb = common.create_checkbox(gear_panel,
                "enable auto-equip best gear", function()
                if SfuiDB.gear and SfuiDB.gear.auto_equip_highest ~= nil then return SfuiDB.gear.auto_equip_highest end
                return true
            end, function(checked)
                SfuiDB.gear = SfuiDB.gear or {}
                SfuiDB.gear.auto_equip_highest = checked
                if SfuiGearManagerFrame then
                    if SfuiGearManagerFrame.enableChk then
                        SfuiGearManagerFrame.enableChk:SetChecked(checked)
                    elseif SfuiGearManagerFrame.maxLvlChk then
                        SfuiGearManagerFrame.maxLvlChk:SetChecked(checked)
                    end
                end
                if checked then
                    sfui.gear.Update()
                end
            end)
            auto_equip_highest_cb:SetPoint("TOPLEFT", gear_auto_open_cb, "BOTTOMLEFT", 0, -10)
            sfui.gearOptionsCheckbox = auto_equip_highest_cb

            table_insert(updateFuncs, function()
                if auto_equip_highest_cb and auto_equip_highest_cb.SetChecked then
                    local enabled = (SfuiDB.gear and SfuiDB.gear.auto_equip_highest ~= nil) and SfuiDB.gear.auto_equip_highest or true
                    auto_equip_highest_cb:SetChecked(enabled)
                end
            end)

            local isRetail = (sfui.isRetail == true) or (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)

            local STAT_MAP = {
                critrating = "Crit", crit = "Crit",
                hasterating = "Haste", haste = "Haste",
                masteryrating = "Mastery", mastery = "Mastery",
                versatility = "Versatility", versatilityrating = "Versatility",
                intellect = "Intellect", agility = "Agility", strength = "Strength", stamina = "Stamina",
                spellpower = "SpellPower", spelldamage = "SpellPower", healing = "Healing",
                hitrating = "Hit", hit = "Hit", attackpower = "AttackPower", ap = "AttackPower",
                rangedattackpower = "RangedAP", rap = "RangedAP",
                manaregen = "ManaRegen", mp5 = "ManaRegen", spirit = "Spirit",
                defenserating = "Defense", defense = "Defense",
                dodgerating = "Dodge", dodge = "Dodge",
                parryrating = "Parry", parry = "Parry",
                blockrating = "Block", block = "Block",
                blockvalue = "BlockValue",
                armor = "Armor", armorpenetration = "ArmorPenetration", arp = "ArmorPenetration",
                expertiserating = "Expertise", expertise = "Expertise",
            }

            local function SavePawnForSpec(specID, text)
                local trimmed = text and text:match("^%s*(.-)%s*$") or ""
                SfuiDB.gear = SfuiDB.gear or {}
                SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
                local sdb = SfuiDB.gear[specID]

                if trimmed == "" then
                    sdb.pawn_weights = nil
                    sdb.pawn_string = nil
                    local specName = (common.get_spec_name and common.get_spec_name(specID)) or ("spec " .. tostring(specID))
                    common.print("pawn cleared for " .. tostring(specName):lower())
                else
                    local weights = {}
                    for stat, val in trimmed:gmatch('(%a+)%s*=%s*([%d%.]+)') do
                        local num = tonumber(val)
                        if num and num > 0 then
                            local canon = STAT_MAP[stat:lower()] or stat
                            weights[canon] = num
                        end
                    end
                    if next(weights) then
                        sdb.pawn_weights = weights
                        sdb.pawn_string = trimmed
                        local specName = (common.get_spec_name and common.get_spec_name(specID)) or ("spec " .. tostring(specID))
                        common.print("pawn saved for " .. tostring(specName):lower())
                    else
                        common.print("|cffff4444invalid pawn string:|r no valid stat weights found")
                        return false
                    end
                end

                if sfui.gear and sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
                if sfui.gear and sfui.gear.Update then sfui.gear.Update() end
                return true
            end

            local pveHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pveHeader:SetText("pve target")

            local pvpHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pvpHeader:SetText("pvp target")

            local pawnHeader = nil
            if isRetail then
                pawnHeader = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                pawnHeader:SetText("pawn string import")
            end

            local dropW = isRetail and 110 or 120
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

                local pveDrop = common.create_dropdown(gear_panel, dropW, GetEquipmentSetOptions, function(val)
                    SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                    SfuiDB.gear[id].pve_set = val
                    sfui.gear.Update()
                end, "")
                pveDrop:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", 6, -5)

                local pvpDrop = common.create_dropdown(gear_panel, dropW, GetEquipmentSetOptions, function(val)
                    SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
                    SfuiDB.gear[id].pvp_set = val
                    sfui.gear.Update()
                end, "")
                pvpDrop:SetPoint("LEFT", pveDrop, "RIGHT", 6, 0)

                local pawnEdit = nil
                if isRetail then
                    pawnEdit = CreateFrame("EditBox", nil, gear_panel, "BackdropTemplate")
                    pawnEdit:SetSize(175, 22)
                    pawnEdit:SetPoint("LEFT", pvpDrop, "RIGHT", 8, 0)
                    pawnEdit:SetAutoFocus(false)
                    pawnEdit:SetMaxLetters(0)
                    pawnEdit:SetFontObject("GameFontHighlightSmall")
                    pawnEdit:SetTextInsets(6, 6, 0, 0)
                    sfui.theme.ApplyInputStyle(pawnEdit)
                    pawnEdit:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)

                    local saveBtn = CreateFlatButton(gear_panel, "save", 36, 22)
                    saveBtn:SetPoint("LEFT", pawnEdit, "RIGHT", 4, 0)

                    local clearBtn = CreateFlatButton(gear_panel, "x", 20, 22)
                    clearBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)

                    pawnEdit:SetScript("OnEnterPressed", function(eb)
                        eb:ClearFocus()
                        SavePawnForSpec(id, eb:GetText())
                    end)

                    saveBtn:SetScript("OnClick", function()
                        pawnEdit:ClearFocus()
                        SavePawnForSpec(id, pawnEdit:GetText())
                    end)

                    clearBtn:SetScript("OnClick", function()
                        pawnEdit:SetText("")
                        pawnEdit:ClearFocus()
                        SavePawnForSpec(id, "")
                    end)

                    pawnEdit:SetScript("OnEnter", function(b)
                        if GameTooltip then
                            GameTooltip:SetOwner(b, "ANCHOR_TOP")
                            GameTooltip:SetText("pawn string import")
                            GameTooltip:AddLine("paste a pawn string (from raidbots / simc) and press enter or click save.", 1, 1, 1, true)
                            GameTooltip:AddLine("example: ( Pawn: v1: \"Spec\": Intellect=1.5, CritRating=1.2, HasteRating=0.9 )", 0.6, 0.6, 0.6, true)
                            GameTooltip:Show()
                        end
                    end)
                    pawnEdit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

                    saveBtn:SetScript("OnEnter", function(b)
                        if GameTooltip then
                            GameTooltip:SetOwner(b, "ANCHOR_TOP")
                            GameTooltip:SetText("save pawn string")
                            GameTooltip:AddLine("parse and save stat weights for this spec.", 0.8, 0.8, 0.8, true)
                            GameTooltip:Show()
                        end
                    end)
                    saveBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

                    clearBtn:SetScript("OnEnter", function(b)
                        if GameTooltip then
                            GameTooltip:SetOwner(b, "ANCHOR_TOP")
                            GameTooltip:SetText("clear pawn string")
                            GameTooltip:AddLine("remove pawn weights and revert to manual stat priorities.", 0.8, 0.8, 0.8, true)
                            GameTooltip:Show()
                        end
                    end)
                    clearBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                end

                if i == 1 then
                    pveHeader:SetPoint("BOTTOMLEFT", pveDrop, "TOPLEFT", 0, 4)
                    pvpHeader:SetPoint("BOTTOMLEFT", pvpDrop, "TOPLEFT", 0, 4)
                    if pawnHeader and pawnEdit then
                        pawnHeader:SetPoint("BOTTOMLEFT", pawnEdit, "TOPLEFT", 0, 4)
                    end
                end

                table_insert(updateFuncs, function()
                    local db = SfuiDB.gear[id]
                    if db then
                        pveDrop:SetText(db.pve_set ~= "" and db.pve_set or "None")
                        pvpDrop:SetText(db.pvp_set ~= "" and db.pvp_set or "None")
                        if pawnEdit and not pawnEdit:HasFocus() then
                            pawnEdit:SetText(db.pawn_string or "")
                        end
                    end
                end)

                updateFuncs[#updateFuncs]()
                prevRowAnchor = iconTex
            end
        end)
    end,
})
