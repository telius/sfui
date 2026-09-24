local addonName, addon = ...
sfui = sfui or {}
sfui.automation = {}

local function on_role_check_show()
    if not SfuiDB.auto_role_check then return end
    if CompleteLFGRoleCheck then
        CompleteLFGRoleCheck(true)
    end
end

local function on_lfg_double_click(self)
    if not SfuiDB.auto_sign_lfg then return end
    if IsShiftKeyDown() then return end

    local result_exists = not LFGListFrame.SearchPanel.SignUpButton.tooltip
    if result_exists then
        LFGListSearchPanel_SignUp(self:GetParent():GetParent():GetParent())
    end
end

local function initialize_lfg_buttons()
    if not LFGListFrame or not LFGListFrame.SearchPanel or not LFGListFrame.SearchPanel.ScrollBox then
        return
    end

    local scroll_target = LFGListFrame.SearchPanel.ScrollBox:GetScrollTarget()
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

local function setup_lfg_dialog()
    if LFGListApplicationDialog then
        if LFGListApplicationDialog.Show then
            hooksecurefunc(LFGListApplicationDialog, "Show", function(self)
                if not SfuiDB.auto_sign_lfg then return end
                if IsShiftKeyDown() then return end

                if self.SignUpButton and self.SignUpButton:IsEnabled() then
                    self.SignUpButton:Click()
                end
            end)
        end
    end
end

local function auto_sell_greys()
    if not SfuiDB.autoSellGreys then return end

    local totalPrice = 0
    sfui.common.for_each_bag_item(function(bag, slot, itemID, link, info)
        if info and (link or info.hyperlink) and info.quality == 0 then
            local price = info.noValue and 0 or (select(11, C_Item.GetItemInfo(link or info.hyperlink)) or 0)
            if price > 0 then
                totalPrice = totalPrice + (price * (info.stackCount or 1))
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end)
    if totalPrice > 0 then
        sfui.common.print("|cff00ff00Auto-sold greys for " .. sfui.common.SafeGetCoinTextureString(totalPrice) .. ".|r")
    end
end

local function auto_repair()
    if not SfuiDB.autoRepair then return end
    if not CanMerchantRepair() then return end

    if SfuiDB.enableMasterHammer ~= false and sfui.hammer and sfui.hammer.has_repair_hammer then
        local hasHammer, hammerName, _, hammerItemID = sfui.hammer.has_repair_hammer()
        if hasHammer and sfui.hammer.can_repair_any_damaged and sfui.hammer.can_repair_any_damaged() then
            local displayName = hammerName or (hammerItemID and C_Item.GetItemNameByID(hammerItemID)) or "Master's Hammer"
            sfui.common.print(string.format("|cffff9900Auto-repair skipped: %s detected.|r", displayName))
            if sfui.hammer.update_hammer_popup then
                sfui.hammer.update_hammer_popup()
            end
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
            sfui.common.print("|cff00ff00Auto-repaired using guild funds for " ..
                sfui.common.SafeGetCoinTextureString(repairAllCost) .. ".|r")
        end
    end

    if not guildRepaired then
        RepairAllItems(false)
        sfui.common.print("|cff00ff00Auto-repaired for " .. sfui.common.SafeGetCoinTextureString(repairAllCost) .. ".|r")
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
    if sfui.hammer and sfui.hammer.update_hammer_popup then
        sfui.hammer.update_hammer_popup()
    end
end)

local function auto_slot_keystone()
    local ReagentClass, KeystoneClass = Enum.ItemClass.Reagent, Enum.ItemReagentSubclass.Keystone
    local slotted = false

    sfui.common.for_each_bag_item(function(bag, slot, ID)
        if ID then
            local Class, SubClass = select(12, C_Item.GetItemInfo(ID))
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

function sfui.automation.initialize()
    setup_lfg_dialog()
    init_keystone_automation()
    init_auction_house_automation()
    init_lfg_dungeon_automation()
    if _G.PVEFrame and not _G.PVEFrame._sfui_lfg_hooked then
        _G.PVEFrame._sfui_lfg_hooked = true
        _G.PVEFrame:HookScript("OnShow", init_lfg_dungeon_automation)
    end
    if sfui.hammer and sfui.hammer.update_hammer_popup then
        sfui.hammer.update_hammer_popup()
    end
end

sfui.events.RegisterEvent("AUCTION_HOUSE_SHOW", function()
    init_auction_house_automation()
    apply_ah_current_expansion_filter()
end)

sfui.events.RegisterEvent("ADDON_LOADED", function(event, addon)
    if addon == "Blizzard_ChallengesUI" then
        init_keystone_automation()
    end

    if addon == "Blizzard_AuctionHouseUI" then
        init_auction_house_automation()
    end

    if addon == "Blizzard_GroupFinder" then
        init_lfg_dungeon_automation()
    end
end)

function sfui.automation_debug_info()
    return {
        autoRelease = SfuiDB and SfuiDB.auto_release or false,
        autoRoleCheck = SfuiDB and SfuiDB.auto_role_check or false,
        autoSignLfg = SfuiDB and SfuiDB.auto_sign_lfg or false,
        skipCinematics = SfuiDB and SfuiDB.skipCinematics or false,
        autoLfgDungeonDefaults = SfuiDB and SfuiDB.autoLfgDungeonDefaults ~= false,
    }
end

if sfui.RegisterModule then
    sfui.automation = sfui.automation or {}
    sfui.automation.GetDebugInfo = sfui.automation_debug_info
    sfui.RegisterModule("automation", sfui.automation)
end
