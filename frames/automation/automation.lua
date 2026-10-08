local addonName, addon = ...
sfui = sfui or {}
sfui.automation = {}

local function get_dungeon_finder_roles()
    -- 1. Read what is filled in on Dungeon Finder role checkbuttons
    if _G.LFDQueueFrameRoleButtonTank and _G.LFDQueueFrame_GetRoles then
        local ok, l, t, h, d = pcall(_G.LFDQueueFrame_GetRoles)
        if ok and (t or h or d) then
            return l or false, t or false, h or false, d or false
        end
    end

    -- 2. Fallback to saved LFG roles
    if _G.GetLFGRoles then
        local l, t, h, d = _G.GetLFGRoles()
        if t or h or d then
            return l or false, t or false, h or false, d or false
        end
    end

    -- 3. Fallback to player's active specialization role
    local specRole = sfui.common.get_spec_role(sfui.common.get_current_spec_id()) or "DAMAGER"
    return false, specRole == "TANK", specRole == "HEALER", specRole == "DAMAGER"
end

local function on_role_check_show()
    if not SfuiDB or not SfuiDB.auto_role_check then return end
    local leader, isTank, isHealer, isDPS = get_dungeon_finder_roles()
    if _G.SetLFGRoles then
        _G.SetLFGRoles(leader, isTank, isHealer, isDPS)
    end
    if CompleteLFGRoleCheck then
        CompleteLFGRoleCheck(true)
    end
end

local _lfg_dialog_handled = false
local _lfg_dialog_hooked = false

local function handle_lfg_dialog(dialog)
    dialog = dialog or _G.LFGListApplicationDialog
    if not dialog or not dialog:IsShown() then return end
    if not SfuiDB or not SfuiDB.auto_sign_lfg then return end
    if IsShiftKeyDown() then return end

    if _lfg_dialog_handled then return end
    _lfg_dialog_handled = true
    C_Timer.After(0.5, function() _lfg_dialog_handled = false end)

    local leader, isTank, isHealer, isDPS = get_dungeon_finder_roles()
    if _G.SetLFGRoles then
        _G.SetLFGRoles(leader, isTank, isHealer, isDPS)
    end

    if dialog.TankButton and dialog.TankButton:IsShown() and dialog.TankButton.CheckButton then
        dialog.TankButton.CheckButton:SetChecked(isTank)
    end
    if dialog.HealerButton and dialog.HealerButton:IsShown() and dialog.HealerButton.CheckButton then
        dialog.HealerButton.CheckButton:SetChecked(isHealer)
    end
    if dialog.DamagerButton and dialog.DamagerButton:IsShown() and dialog.DamagerButton.CheckButton then
        dialog.DamagerButton.CheckButton:SetChecked(isDPS)
    end

    -- Ensure at least one shown role is checked so SignUpButton becomes valid
    local anyChecked = (dialog.TankButton and dialog.TankButton:IsShown() and dialog.TankButton.CheckButton and dialog.TankButton.CheckButton:GetChecked())
                    or (dialog.HealerButton and dialog.HealerButton:IsShown() and dialog.HealerButton.CheckButton and dialog.HealerButton.CheckButton:GetChecked())
                    or (dialog.DamagerButton and dialog.DamagerButton:IsShown() and dialog.DamagerButton.CheckButton and dialog.DamagerButton.CheckButton:GetChecked())

    if not anyChecked then
        if dialog.DamagerButton and dialog.DamagerButton:IsShown() and dialog.DamagerButton.CheckButton then
            dialog.DamagerButton.CheckButton:SetChecked(true)
        elseif dialog.HealerButton and dialog.HealerButton:IsShown() and dialog.HealerButton.CheckButton then
            dialog.HealerButton.CheckButton:SetChecked(true)
        elseif dialog.TankButton and dialog.TankButton:IsShown() and dialog.TankButton.CheckButton then
            dialog.TankButton.CheckButton:SetChecked(true)
        end
    end

    if _G.LFGListApplicationDialog_UpdateValidState then
        _G.LFGListApplicationDialog_UpdateValidState(dialog)
    end

    if dialog.SignUpButton and dialog.SignUpButton:IsEnabled() then
        dialog.SignUpButton:Click()
    end

    -- Fallback for next frame tick if still shown
    C_Timer.After(0, function()
        if dialog and dialog:IsShown() and dialog.SignUpButton and dialog.SignUpButton:IsEnabled() then
            dialog.SignUpButton:Click()
        end
    end)
end

local function setup_lfg_dialog()
    local dialog = _G.LFGListApplicationDialog
    if dialog and not _lfg_dialog_hooked then
        _lfg_dialog_hooked = true
        dialog:HookScript("OnShow", function(self)
            handle_lfg_dialog(self)
        end)
    end

    if _G.LFGListApplicationDialog_Show and not _G.LFGListApplicationDialog_Show_sfui_hooked then
        _G.LFGListApplicationDialog_Show_sfui_hooked = true
        hooksecurefunc("LFGListApplicationDialog_Show", function(d)
            setup_lfg_dialog()
            handle_lfg_dialog(d)
        end)
    end

    if dialog and dialog:IsShown() then
        handle_lfg_dialog(dialog)
    end
end

local function on_lfg_double_click(self)
    if not SfuiDB or not SfuiDB.auto_sign_lfg then return end
    if IsShiftKeyDown() then return end

    setup_lfg_dialog()
    local searchPanel = _G.LFGListFrame and _G.LFGListFrame.SearchPanel
    local signUpBtn = searchPanel and searchPanel.SignUpButton
    if signUpBtn and not signUpBtn.tooltip then
        if _G.LFGListSearchPanel_SignUp then
            _G.LFGListSearchPanel_SignUp(searchPanel)
        end
    end
end

local function initialize_lfg_buttons()
    setup_lfg_dialog()
    local lf = _G.LFGListFrame
    if not lf or not lf.SearchPanel or not lf.SearchPanel.ScrollBox then
        return
    end

    local scroll_target = lf.SearchPanel.ScrollBox:GetScrollTarget()
    if not scroll_target then return end

    local buttons = { scroll_target:GetChildren() }
    for _, child in ipairs(buttons) do
        if child and child:GetObjectType() == "Button" and not child.sfui_automation_init then
            child:SetScript("OnDoubleClick", on_lfg_double_click)
            child:RegisterForClicks("AnyUp")
            child.sfui_automation_init = true
        end
    end
end

local function auto_sell_greys()
    if not SfuiDB.autoSellGreys then return end

    local totalPrice = 0
    sfui.common.for_each_bag_item(function(bag, slot, itemID, link, info)
        if info and (link or info.hyperlink) and info.quality == 0 then
            local price = info.noValue and 0 or (select(11, sfui.common.get_item_info(link or info.hyperlink)) or 0)
            if price > 0 then
                totalPrice = totalPrice + (price * (info.stackCount or 1))
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end)
    if totalPrice > 0 then
        sfui.common.print("|cff00ff00auto-sold greys for " .. sfui.common.SafeGetCoinTextureString(totalPrice) .. ".|r")
    end
end

local function auto_repair()
    if not SfuiDB.autoRepair then return end
    if not CanMerchantRepair() then return end

    if sfui.isRetail and sfui.hammer and SfuiDB.enableMasterHammer ~= false then
        local hasHammer, hammerName, _, hammerItemID = sfui.hammer.has_repair_hammer()
        if hasHammer and sfui.hammer.can_repair_any_damaged() then
            local displayName = hammerName or (hammerItemID and C_Item.GetItemNameByID(hammerItemID)) or "Master's Hammer"
            sfui.common.print(string.format("|cffff9900auto-repair skipped: %s detected.|r", displayName))
            sfui.hammer.update_hammer_popup()
            return
        end
    end

    local repairAllCost, canRepair = GetRepairAllCost()
    if not canRepair or repairAllCost == 0 then return end

    local guildRepaired = false
    if CanGuildBankRepair() then
        local withdrawLimit = GetGuildBankWithdrawMoney()
        if withdrawLimit == -1 or withdrawLimit >= repairAllCost then
            RepairAllItems(true)
            guildRepaired = true
            sfui.common.print("|cff00ff00auto-repaired using guild funds for " ..
                sfui.common.SafeGetCoinTextureString(repairAllCost) .. ".|r")
        end
    end

    if not guildRepaired then
        RepairAllItems(false)
        sfui.common.print("|cff00ff00auto-repaired for " .. sfui.common.SafeGetCoinTextureString(repairAllCost) .. ".|r")
    end
end

function sfui.automation.match_mount()
    if InCombatLockdown() then return end

    local target = "target"
    local C_Secrets = _G.C_Secrets
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
    if UnitExists(target) then
        for i = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(target, i, "HELPFUL")
            if not aura then break end

            local spellID = aura.spellId
            -- C_MountJournal.GetMountFromSpell was added in 10.0
            if C_MountJournal.GetMountFromSpell then
                local mountID = C_MountJournal.GetMountFromSpell(spellID)
                if mountID then
                    local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                    if isCollected then
                        C_MountJournal.SummonByID(mountID)
                        return
                    end
                end
            end
        end
    end

    -- Fallback: Summon Random Favorite
    C_MountJournal.SummonByID(0)
end

_G["SFUI_MATCHMOUNT"] = sfui.automation.match_mount

sfui.events.RegisterEvent("LFG_ROLE_CHECK_SHOW", function()
    C_Timer.After(0.1, on_role_check_show)
end)
sfui.events.RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", function()
    C_Timer.After(0.1, initialize_lfg_buttons)
end)
sfui.events.RegisterEvent("MERCHANT_SHOW", function()
    auto_sell_greys()
    auto_repair()
    if sfui.isRetail and sfui.hammer then
        sfui.hammer.update_hammer_popup()
    end
end)

local function auto_slot_keystone()
    local ReagentClass, KeystoneClass = Enum.ItemClass.Reagent, Enum.ItemReagentSubclass.Keystone
    local slotted = false

    sfui.common.for_each_bag_item(function(bag, slot, ID)
        if ID then
            local Class, SubClass = select(12, sfui.common.get_item_info(ID))
            if Class == ReagentClass and SubClass == KeystoneClass then
                C_Container.PickupContainerItem(bag, slot)
                if C_Cursor.GetCursorItem() then
                    C_ChallengeMode.SlotKeystone()
                    slotted = true
                    return true
                end
            end
        end
    end, true, true, false)
    return slotted
end

local function init_keystone_automation()
    local Frame = ChallengesKeystoneFrame
    if not Frame or Frame.sfui_keystone_init then return end
    Frame.sfui_keystone_init = true

    Frame:HookScript("OnShow", function()
        if SfuiDB.autoKeystone ~= false then
            auto_slot_keystone()
        end
    end)

    if not Frame:IsMovable() then
        Frame:SetMovable(true)
        Frame:SetClampedToScreen(true)
        Frame:RegisterForDrag("LeftButton")
        Frame:SetScript("OnDragStart", Frame.StartMoving)
        Frame:SetScript("OnDragStop", Frame.StopMovingOrSizing)
    end
end

local function apply_ah_current_expansion_filter()
    if SfuiDB.ahCurrentExpansionFilter == false then return end
    if not _G.AuctionHouseFrame then return end

    if _G.g_auctionHouseFilters and _G.g_auctionHouseFilters.filters and Enum and Enum.AuctionHouseFilter then
        _G.g_auctionHouseFilters.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
    end

    local searchBar = _G.AuctionHouseFrame.SearchBar
    if searchBar then
        local fb = searchBar.FilterButton
        if fb and fb.GetFilters and Enum and Enum.AuctionHouseFilter then
            local filters = fb:GetFilters()
            if filters then
                filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
            end
        end
        if searchBar.UpdateClearFiltersButton then
            searchBar:UpdateClearFiltersButton()
        end
    end
end

local function init_auction_house_automation()
    local ah = _G.AuctionHouseFrame
    if not ah or ah._sfui_filter_hooked then return end
    ah._sfui_filter_hooked = true

    ah:HookScript("OnShow", function()
        apply_ah_current_expansion_filter()
    end)

    local searchBar = ah.SearchBar
    if searchBar then
        searchBar:HookScript("OnShow", function()
            apply_ah_current_expansion_filter()
        end)
        local fb = searchBar.FilterButton
        if fb then
            hooksecurefunc(fb, "Reset", function()
                apply_ah_current_expansion_filter()
            end)
        end
    end

    if ah:IsShown() then
        apply_ah_current_expansion_filter()
    end
end

-- ============================================================================
-- LFG Group Creation: Auto Mythic+ Keystone & Competitive Defaults
-- ============================================================================
local lastAutomatedGroupID = nil

local function apply_lfg_dungeon_defaults(force)
    if SfuiDB and SfuiDB.autoLfgDungeonDefaults == false then return end
    local entryCreation = _G.LFGListFrame and _G.LFGListFrame.EntryCreation
    if not entryCreation or not entryCreation:IsShown() then return end

    -- Do not overwrite if user is editing an already listed group
    if entryCreation.editMode then return end

    -- Only apply to Dungeons (Category ID 2)
    local categoryID = entryCreation.selectedCategory
    if categoryID ~= 2 and categoryID ~= (_G.GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2) then
        lastAutomatedGroupID = nil
        return
    end

    -- 1. Automatically enable Competitive (Playstyle)
    -- TAINT WARNING: Do NOT call LFGListEntryCreation_OnPlayStyleSelectedInternal() directly.
    -- That function internally calls SetEntryTitle() (a protected C function). Invoking it
    -- from addon code taints the Lua thread, causing ADDON_ACTION_BLOCKED on any subsequent
    -- secure call in the same frame — even from Blizzard's own LFG code.
    --
    -- Safe approach: write the playstyle state directly, then refresh only the dropdown
    -- widget. The title update that SetEntryTitle performs happens inside Blizzard's own
    -- secure execution when the user next interacts with the panel, which carries no taint.
    local playstyleEnum = Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunSerious
    if playstyleEnum and entryCreation.generalPlaystyle ~= playstyleEnum then
        entryCreation.generalPlaystyle = playstyleEnum
        -- Only refresh the dropdown widget — never call the full OnPlayStyleSelected handler.
        if entryCreation.PlayStyleDropdown and entryCreation.PlayStyleDropdown.GenerateMenu then
            entryCreation.PlayStyleDropdown:GenerateMenu()
        end
    end

    -- 2. Automatically enable Mythic+ Keystone (Difficulty)
    local currActivityID = entryCreation.selectedActivity
    local currActivityInfo = currActivityID and C_LFGList.GetActivityInfoTable(currActivityID)
    local groupID = entryCreation.selectedGroup or (currActivityInfo and currActivityInfo.groupFinderActivityGroupID)

    if not groupID or groupID == 0 then return end

    -- Avoid overriding manual difficulty choices within the same dungeon
    if not force and lastAutomatedGroupID == groupID then
        return
    end
    lastAutomatedGroupID = groupID

    if currActivityInfo and currActivityInfo.isMythicPlusActivity then
        return
    end

    local activities = C_LFGList.GetAvailableActivities(categoryID, groupID)
    if activities then
        local mplusActivityID = nil
        for _, actID in ipairs(activities) do
            local actInfo = C_LFGList.GetActivityInfoTable(actID)
            if actInfo and actInfo.isMythicPlusActivity then
                mplusActivityID = actID
                break
            end
        end

        if mplusActivityID and mplusActivityID ~= currActivityID then
            if _G.LFGListEntryCreation_Select and not entryCreation._sfui_selecting_mplus then
                entryCreation._sfui_selecting_mplus = true
                _G.LFGListEntryCreation_Select(entryCreation, entryCreation.selectedFilters, categoryID, groupID, mplusActivityID)
                entryCreation._sfui_selecting_mplus = false
            end
        end
    end
end

local function init_lfg_dungeon_automation()
    local lf = _G.LFGListFrame
    local entryCreation = lf and lf.EntryCreation
    if not entryCreation or entryCreation._sfui_dungeon_hooked then return end
    entryCreation._sfui_dungeon_hooked = true

    if _G.LFGListEntryCreation_Show then
        hooksecurefunc("LFGListEntryCreation_Show", function()
            lastAutomatedGroupID = nil
            C_Timer.After(0.05, function()
                apply_lfg_dungeon_defaults(true)
            end)
        end)
    end

    if _G.LFGListEntryCreation_Clear then
        hooksecurefunc("LFGListEntryCreation_Clear", function()
            lastAutomatedGroupID = nil
        end)
    end

    if _G.LFGListEntryCreation_Select then
        hooksecurefunc("LFGListEntryCreation_Select", function(self, filters, categoryID, groupID, activityID)
            if self._sfui_selecting_mplus then return end
            apply_lfg_dungeon_defaults(false)
        end)
    end

    entryCreation:HookScript("OnShow", function()
        C_Timer.After(0.05, function()
            apply_lfg_dungeon_defaults(true)
        end)
    end)

    if entryCreation:IsShown() then
        apply_lfg_dungeon_defaults(true)
    end
end

-- ─────────────────────────────────────────────────────────────
--  TOOLTIP ALT ID AUTOMATION (ITEM ID & SPELL ID)
-- ─────────────────────────────────────────────────────────────
local _tooltip_automation_initialized = false

local function is_alt_tooltip_enabled()
    if SfuiDB and SfuiDB.tooltipAltIDs ~= nil then
        return SfuiDB.tooltipAltIDs
    end
    if sfui.config and sfui.config.automation and sfui.config.automation.tooltip_alt_ids ~= nil then
        return sfui.config.automation.tooltip_alt_ids
    end
    return true
end

local function append_tooltip_id(tooltip, idType, id)
    if not tooltip or not id or tooltip._sfuiAltIDAppended then return end
    tooltip._sfuiAltIDAppended = true

    local prefix = (idType == "item") and "item id:" or ((idType == "quest") and "quest id:" or ((idType == "achievement") and "achievement id:" or "spell id:"))
    if tooltip.AddDoubleLine then
        tooltip:AddDoubleLine("|cff00ffff" .. prefix .. "|r", "|cffffffff" .. tostring(id) .. "|r", 0, 1, 1, 1, 1, 1)
    elseif tooltip.AddLine then
        tooltip:AddLine("|cff00ffff" .. prefix .. "|r |cffffffff" .. tostring(id) .. "|r")
    end
    tooltip:Show()
end

sfui.automation = sfui.automation or {}
sfui.automation.is_alt_tooltip_enabled = is_alt_tooltip_enabled
sfui.automation.append_tooltip_id = append_tooltip_id

local function on_tooltip_cleared(tooltip)
    if not tooltip then return end
    tooltip._sfuiAltIDAppended = nil
    tooltip._sfuiCurrentID = nil
    tooltip._sfuiCurrentType = nil
    tooltip._sfuiCurrentHyperlink = nil
end

local function get_item_id_from_tooltip(tooltip, tooltipData)
    if tooltipData and tooltipData.id and tooltipData.id > 0 then
        return tooltipData.id
    end
    if tooltipData and tooltipData.guid then
        local cItem = _G.C_Item
        local link = cItem and cItem.GetItemLinkByGUID and cItem.GetItemLinkByGUID(tooltipData.guid)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id then return id end
        end
    end
    if tooltipData and tooltipData.hyperlink then
        local id = tonumber(tooltipData.hyperlink:match("item:(%d+)"))
        if id then return id end
    end
    local toolUtil = _G.TooltipUtil
    if toolUtil and toolUtil.GetDisplayedItem then
        local _, _, id = toolUtil.GetDisplayedItem(tooltip)
        if id and id > 0 then return id end
    end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id then return id end
        end
    end
    return nil
end

local function get_spell_id_from_tooltip(tooltip, tooltipData)
    if tooltipData and tooltipData.id and tooltipData.id > 0 then
        return tooltipData.id
    end
    local toolUtil = _G.TooltipUtil
    if toolUtil and toolUtil.GetDisplayedSpell then
        local _, id = toolUtil.GetDisplayedSpell(tooltip)
        if id and id > 0 then return id end
    end
    if tooltip.GetSpell then
        local _, id = tooltip:GetSpell()
        if id and id > 0 then return id end
    end
    return nil
end

local function on_tooltip_set_item(tooltip, tooltipData)
    if not tooltip or not is_alt_tooltip_enabled() then return end
    local itemID = get_item_id_from_tooltip(tooltip, tooltipData)
    if not itemID then return end

    tooltip._sfuiCurrentType = "item"
    tooltip._sfuiCurrentID = itemID
    if tooltipData and tooltipData.hyperlink then
        tooltip._sfuiCurrentHyperlink = tooltipData.hyperlink
    elseif tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then tooltip._sfuiCurrentHyperlink = link end
    end

    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
        append_tooltip_id(tooltip, "item", itemID)
    end
end

local function on_tooltip_set_spell(tooltip, tooltipData)
    if not tooltip or not is_alt_tooltip_enabled() then return end
    local spellID = get_spell_id_from_tooltip(tooltip, tooltipData)
    if not spellID then return end

    tooltip._sfuiCurrentType = "spell"
    tooltip._sfuiCurrentID = spellID

    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
        append_tooltip_id(tooltip, "spell", spellID)
    end
end

local function on_tooltip_set_unit_aura(tooltip, tooltipData)
    if not tooltip or not is_alt_tooltip_enabled() then return end
    local spellID = tooltipData and tooltipData.id
    if not spellID or spellID <= 0 then
        if tooltip.GetSpell then
            local _, id = tooltip:GetSpell()
            if id and id > 0 then spellID = id end
        end
    end
    if not spellID then return end

    tooltip._sfuiCurrentType = "spell"
    tooltip._sfuiCurrentID = spellID

    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
        append_tooltip_id(tooltip, "spell", spellID)
    end
end

local function on_tooltip_set_macro(tooltip, tooltipData)
    if not tooltip or not is_alt_tooltip_enabled() then return end
    local spellID = nil
    if tooltip.GetSpell then
        local _, id = tooltip:GetSpell()
        if id and id > 0 then spellID = id end
    end
    if spellID then
        tooltip._sfuiCurrentType = "spell"
        tooltip._sfuiCurrentID = spellID
        if _G.IsAltKeyDown and _G.IsAltKeyDown() then
            append_tooltip_id(tooltip, "spell", spellID)
        end
        return
    end

    local itemID = nil
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then itemID = tonumber(link:match("item:(%d+)")) end
    end
    if itemID then
        tooltip._sfuiCurrentType = "item"
        tooltip._sfuiCurrentID = itemID
        if _G.IsAltKeyDown and _G.IsAltKeyDown() then
            append_tooltip_id(tooltip, "item", itemID)
        end
    end
end

local function get_quest_id_from_tooltip(tooltip, tooltipData)
    if tooltip and tooltip._sfuiCurrentType == "quest" and tooltip._sfuiCurrentID then
        return tooltip._sfuiCurrentID
    end
    if tooltipData and tooltipData.id and tooltipData.id > 0 then
        return tooltipData.id
    end
    if tooltipData and tooltipData.hyperlink then
        local id = tonumber(tooltipData.hyperlink:match("quest:(%d+)"))
        if id then return id end
    end
    if tooltip and tooltip._sfuiCurrentHyperlink then
        local id = tonumber(tooltip._sfuiCurrentHyperlink:match("quest:(%d+)"))
        if id then return id end
    end
    return nil
end

local function on_tooltip_set_quest(tooltip, tooltipData)
    if not tooltip or not is_alt_tooltip_enabled() then return end
    local questID = get_quest_id_from_tooltip(tooltip, tooltipData)
    if not questID then return end

    tooltip._sfuiCurrentType = "quest"
    tooltip._sfuiCurrentID = questID
    if tooltipData and tooltipData.hyperlink then
        tooltip._sfuiCurrentHyperlink = tooltipData.hyperlink
    end

    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
        append_tooltip_id(tooltip, "quest", questID)
    end
end

local function refresh_active_tooltip(tip)
    if not tip or not tip:IsShown() then return end
    local owner = tip.GetOwner and tip:GetOwner()
    local foci = _G.GetMouseFoci and _G.GetMouseFoci()
    local focus = (foci and foci[1]) or (_G.GetMouseFocus and _G.GetMouseFocus())
    local target = (focus and focus.IsMouseOver and focus:IsMouseOver() and focus) or owner
    if target then
        local onEnter = target.GetScript and target:GetScript("OnEnter")
        if onEnter then
            onEnter(target)
            return
        elseif target.OnEnter then
            target:OnEnter()
            return
        end
    end
    if tip == _G.ItemRefTooltip and tip._sfuiCurrentHyperlink then
        tip:SetHyperlink(tip._sfuiCurrentHyperlink)
        return
    end
    if _G.IsAltKeyDown and _G.IsAltKeyDown() and tip._sfuiCurrentID and not tip._sfuiAltIDAppended then
        append_tooltip_id(tip, tip._sfuiCurrentType, tip._sfuiCurrentID)
    end
end

local function update_tooltip_on_alt(tip)
    if not tip or not tip:IsShown() then return end
    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
        if tip._sfuiCurrentID and not tip._sfuiAltIDAppended then
            append_tooltip_id(tip, tip._sfuiCurrentType, tip._sfuiCurrentID)
        else
            refresh_active_tooltip(tip)
        end
    else
        if tip._sfuiAltIDAppended then
            refresh_active_tooltip(tip)
        end
    end
end

local function on_modifier_state_changed(_, key)
    if key and not key:find("ALT", 1, true) then return end
    if not is_alt_tooltip_enabled() then return end

    update_tooltip_on_alt(_G.GameTooltip)
    update_tooltip_on_alt(_G.ItemRefTooltip)
    local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip
    if sfuiTip and sfuiTip ~= _G.GameTooltip then
        update_tooltip_on_alt(sfuiTip)
    end
    update_tooltip_on_alt(_G.ShoppingTooltip1)
    update_tooltip_on_alt(_G.ShoppingTooltip2)
end

local function init_tooltip_automation()
    if _tooltip_automation_initialized then return end
    _tooltip_automation_initialized = true

    local dataProcessor = _G.TooltipDataProcessor
    local enumType = _G.Enum and _G.Enum.TooltipDataType

    local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip

    if dataProcessor and dataProcessor.AddTooltipPostCall and enumType then
        if enumType.Item then
            dataProcessor.AddTooltipPostCall(enumType.Item, on_tooltip_set_item)
        end
        if enumType.Spell then
            dataProcessor.AddTooltipPostCall(enumType.Spell, on_tooltip_set_spell)
        end
        if enumType.UnitAura then
            dataProcessor.AddTooltipPostCall(enumType.UnitAura, on_tooltip_set_unit_aura)
        end
        if enumType.Toy then
            dataProcessor.AddTooltipPostCall(enumType.Toy, on_tooltip_set_item)
        end
        if enumType.Macro then
            dataProcessor.AddTooltipPostCall(enumType.Macro, on_tooltip_set_macro)
        end
        if enumType.Quest then
            dataProcessor.AddTooltipPostCall(enumType.Quest, on_tooltip_set_quest)
        end
    else
        local hookedTips = {}
        local function hook_legacy_tip(tip)
            if not tip or hookedTips[tip] then return end
            hookedTips[tip] = true
            if tip.HookScript then
                tip:HookScript("OnTooltipSetItem", on_tooltip_set_item)
                tip:HookScript("OnTooltipSetSpell", on_tooltip_set_spell)
                tip:HookScript("OnTooltipCleared", on_tooltip_cleared)
                tip:HookScript("OnHide", on_tooltip_cleared)
            end
        end

        hook_legacy_tip(_G.GameTooltip)
        hook_legacy_tip(_G.ItemRefTooltip)
        hook_legacy_tip(sfuiTip)
        hook_legacy_tip(_G.ShoppingTooltip1)
        hook_legacy_tip(_G.ShoppingTooltip2)
    end

    local function hook_tip_hyperlink(tip)
        if not tip or not tip.SetHyperlink then return end
        hooksecurefunc(tip, "SetHyperlink", function(self, link)
            if not is_alt_tooltip_enabled() or not link then return end
            local questID = tonumber(link:match("quest:(%d+)"))
            if questID then
                self._sfuiCurrentType = "quest"
                self._sfuiCurrentID = questID
                self._sfuiCurrentHyperlink = link
                if _G.IsAltKeyDown and _G.IsAltKeyDown() then
                    append_tooltip_id(self, "quest", questID)
                end
            end
        end)
    end

    hook_tip_hyperlink(_G.GameTooltip)
    hook_tip_hyperlink(_G.ItemRefTooltip)
    if sfuiTip and sfuiTip ~= _G.GameTooltip then
        hook_tip_hyperlink(sfuiTip)
    end

    if _G.QuestLogTitleButton_OnEnter then
        hooksecurefunc("QuestLogTitleButton_OnEnter", function(self)
            if not is_alt_tooltip_enabled() or not self or not self.GetID or self.isHeader then return end
            local offset = (_G.FauxScrollFrame_GetOffset and _G.QuestLogListScrollFrame and _G.FauxScrollFrame_GetOffset(_G.QuestLogListScrollFrame)) or 0
            local index = self:GetID() + offset
            if index and index > 0 and _G.GetQuestLogTitle then
                local title, _, _, isHeader, _, _, _, questID = _G.GetQuestLogTitle(index)
                if not isHeader and questID and questID > 0 then
                    local tip = _G.GameTooltip
                    tip._sfuiCurrentType = "quest"
                    tip._sfuiCurrentID = questID
                    if _G.IsAltKeyDown and _G.IsAltKeyDown() then
                        if not tip:IsShown() then
                            tip:SetOwner(self, "ANCHOR_RIGHT")
                            tip:SetText(title or "Quest")
                        end
                        append_tooltip_id(tip, "quest", questID)
                    end
                end
            end
        end)
    end

    local commonTips = { _G.GameTooltip, _G.ItemRefTooltip, sfuiTip, _G.ShoppingTooltip1, _G.ShoppingTooltip2 }
    for i = 1, #commonTips do
        local tip = commonTips[i]
        if tip and tip.HookScript then
            pcall(tip.HookScript, tip, "OnTooltipCleared", on_tooltip_cleared)
            pcall(tip.HookScript, tip, "OnHide", on_tooltip_cleared)
        end
    end

    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("MODIFIER_STATE_CHANGED", on_modifier_state_changed)
    end
end

local _automation_initialized = false
function sfui.automation.initialize()
    if _automation_initialized then return end
    _automation_initialized = true

    setup_lfg_dialog()
    init_keystone_automation()
    init_auction_house_automation()
    init_lfg_dungeon_automation()
    init_tooltip_automation()
    if _G.PVEFrame and not _G.PVEFrame._sfui_lfg_hooked then
        _G.PVEFrame._sfui_lfg_hooked = true
        _G.PVEFrame:HookScript("OnShow", function()
            setup_lfg_dialog()
            init_lfg_dungeon_automation()
        end)
    end
    if sfui.isRetail and sfui.hammer then
        sfui.hammer.update_hammer_popup()
    end
end

sfui.events.RegisterEvent("AUCTION_HOUSE_SHOW", function()
    init_auction_house_automation()
    apply_ah_current_expansion_filter()
end)

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    setup_lfg_dialog()
    init_tooltip_automation()
end)

sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
    if loadedAddon == "Blizzard_ChallengesUI" then
        init_keystone_automation()
    end

    if loadedAddon == "Blizzard_AuctionHouseUI" then
        init_auction_house_automation()
    end

    if loadedAddon == "Blizzard_GroupFinder" or loadedAddon == "Blizzard_PVEFrame" then
        setup_lfg_dialog()
        init_lfg_dungeon_automation()
    end
end)

function sfui.automation_debug_info()
    return {
        autoRoleCheck = SfuiDB and SfuiDB.auto_role_check or false,
        autoSignLfg = SfuiDB and SfuiDB.auto_sign_lfg or false,
        autoRepair = SfuiDB and SfuiDB.autoRepair or false,
        autoSellGreys = SfuiDB and SfuiDB.autoSellGreys or false,
        autoLfgDungeonDefaults = SfuiDB and SfuiDB.autoLfgDungeonDefaults ~= false,
        tooltipAltIDs = SfuiDB and SfuiDB.tooltipAltIDs ~= false,
    }
end

sfui.automation.OnInit = sfui.automation.initialize
sfui.automation.OnEnable = sfui.automation.initialize
sfui.automation.GetDebugInfo = sfui.automation_debug_info
sfui.RegisterModule("automation", sfui.automation)
