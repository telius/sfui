sfui = sfui or {}
sfui.automation = {}

local function on_role_check_show()
    if not SfuiDB.auto_role_check then return end
    if CompleteLFGRoleCheck then
        pcall(CompleteLFGRoleCheck, true)
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

local currentTargetSlot = nil
local SLOT_ORDER = { 16, 17, 1, 3, 5, 9, 10, 8, 7, 6 }
local rotationIndex = 1
local currentREPAIR_NODES = {}

local update_hammer_popup -- Forward declaration

local function setup_lfg_dialog()
    if LFGListApplicationDialog then
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not SfuiDB.auto_sign_lfg then return end
            if IsShiftKeyDown() then return end

            if self.SignUpButton and self.SignUpButton:IsEnabled() then
                self.SignUpButton:Click()
            end
        end)
    end
end

local function auto_sell_greys()
    if not SfuiDB.autoSellGreys then return end

    local totalPrice = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and info.quality == 0 then
                local price = info.noValue and 0 or (select(11, C_Item.GetItemInfo(info.hyperlink)) or 0)
                if price > 0 then
                    totalPrice = totalPrice + (price * info.stackCount)
                    C_Container.UseContainerItem(bag, slot)
                end
            end
        end
    end
    if totalPrice > 0 then
        print("|cff00ff00Auto-sold greys for " .. C_CurrencyInfo.GetCoinTextureString(totalPrice) .. ".|r")
    end
end

local function find_bs_config()
    if bsConfigID then return bsConfigID end

    -- Prioritize Khaz Algar (2872)
    local cfgID = C_ProfSpecs.GetConfigIDForSkillLine(2872)
    if cfgID and cfgID > 0 then
        bsConfigID = cfgID
        return cfgID
    end

    -- Fallback: Scan everything
    local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
    if skillLines then
        for _, skillLineID in ipairs(skillLines) do
            local cfgID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
            if cfgID and cfgID > 0 then
                bsConfigID = cfgID
                return cfgID
            end
        end
    end
    return nil
end

local hammerCache = {
    found = false,
    name = nil,
    icon = nil,
    itemID = nil,
    checked = false
}

function sfui.automation.has_repair_hammer(debug)
    -- If we've already found a hammer this session, just return it
    if hammerCache.checked and hammerCache.found then
        return hammerCache.found, hammerCache.name, hammerCache.icon, hammerCache.itemID
    end

    -- Restriction: Only scan if we have a valid BS config
    -- This prevents scanning on characters that can't possibly use it
    if not find_bs_config() then
        hammerCache.checked = true
        hammerCache.found = false
        return false
    end

    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local itemID = C_Item.GetItemInfoInstant(info.hyperlink)
                -- Fast check against known IDs first to avoid string matching if possible
                if sfui.config.masterHammer[itemID] then
                    local name = C_Item.GetItemInfo(info.hyperlink)
                    local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(info.hyperlink)

                    hammerCache.found = true
                    hammerCache.name = name
                    hammerCache.icon = icon
                    hammerCache.itemID = itemID
                    hammerCache.checked = true
                    return true, name, icon, itemID
                end

                -- Fallback for older/unknown hammers (matches "Master's Hammer")
                local name = C_Item.GetItemInfo(info.hyperlink)
                if name and name:find("Master.s Hammer") then
                    if debug then print("SFUI Debug: Found Hammer:", name) end
                    local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(info.hyperlink)

                    hammerCache.found = true
                    hammerCache.name = name
                    hammerCache.icon = icon
                    hammerCache.itemID = itemID
                    hammerCache.checked = true
                    return true, name, icon, itemID
                end
            end
        end
    end

    -- If we finished a full scan and found nothing, mark as checked but not found
    -- If user picks one up later, BAG_UPDATE should clear this flag
    hammerCache.found = false
    hammerCache.checked = true
    if debug then print("SFUI Debug: No Hammer Found after scan.") end
    return false
end

local SLOT_BUTTON_MAP = {
    [1] = "CharacterHeadSlot",
    [3] = "CharacterShoulderSlot",
    [5] = "CharacterChestSlot",
    [6] = "CharacterWaistSlot",
    [7] = "CharacterLegsSlot",
    [8] = "CharacterFeetSlot",
    [9] = "CharacterWristSlot",
    [10] = "CharacterHandsSlot",
    [16] = "CharacterMainHandSlot",
    [17] = "CharacterSecondaryHandSlot"
}

local SLOT_NAMES = {
    [1] = "Head",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [16] = "MainHand",
    [17] = "OffHand"
}

local ARMOR_LOC_MAP = {
    ["INVTYPE_HEAD"] = "HEAD",
    ["INVTYPE_SHOULDER"] = "SHOULDER",
    ["INVTYPE_CHEST"] = "CHEST",
    ["INVTYPE_ROBE"] = "CHEST",
    ["INVTYPE_WAIST"] = "WAIST",
    ["INVTYPE_LEGS"] = "LEGS",
    ["INVTYPE_FEET"] = "FEET",
    ["INVTYPE_WRIST"] = "WRIST",
    ["INVTYPE_HANDS"] = "HANDS",
    ["INVTYPE_HAND"] = "HANDS"
}

-- Forward declarations for debug system
-- (None needed, debug consolidated to options.lua)

local function create_hammer_popup()
    if hammerPopup then return hammerPopup end
    hammerPopup = CreateFrame("Button", "SfuiHammerPopup", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    hammerPopup:SetSize(64, 64)
    -- Point set below dynamically based on settings
    hammerPopup:SetFrameStrata("DIALOG")              -- Ensure it's on top
    hammerPopup:RegisterForClicks("AnyUp", "AnyDown") -- Ensure it accepts clicks
    hammerPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    hammerPopup:SetBackdropColor(0, 0, 0, 0.8)
    -- Border color set below dynamically

    local icon = hammerPopup:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(134376)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hammerPopup.icon = icon

    local highlight = hammerPopup:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(icon)
    highlight:SetColorTexture(1, 1, 1, 0.2)
    hammerPopup:SetHighlightTexture(highlight)

    local pushed = hammerPopup:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints(icon)
    pushed:SetColorTexture(0, 0, 0, 0.3)
    hammerPopup:SetPushedTexture(pushed)


    local text = hammerPopup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("BOTTOM", 0, -20)
    text:SetText("repair")
    hammerPopup.text = text

    -- Apply Aesthetics from DB
    hammerPopup:Hide()

    hammerPopup:SetScript("PostClick", function(self)
        if InCombatLockdown() then return end
        -- Move to the next slot in the rotation immediately
        rotationIndex = (rotationIndex % #SLOT_ORDER) + 1
        update_hammer_popup()
    end)

    sfui.automation.update_popup_style() -- Apply initial style
    return hammerPopup
end

function sfui.automation.update_popup_style()
    if not hammerPopup then return end

    -- Apply Aesthetics from DB
    local x = SfuiDB.repairIconX or 0
    local y = SfuiDB.repairIconY or 200
    hammerPopup:ClearAllPoints()
    hammerPopup:SetPoint("CENTER", x, y)

    local hex = SfuiDB.repairIconColor or "00FFFF"
    if hex:sub(1, 1) == "#" then hex = hex:sub(2) end
    local r = tonumber("0x" .. hex:sub(1, 2)) or 255
    local g = tonumber("0x" .. hex:sub(3, 4)) or 0
    local b = tonumber("0x" .. hex:sub(5, 6)) or 255

    hammerPopup:SetBackdropBorderColor(r / 255, g / 255, b / 255, 1)
    if hammerPopup.text then
        hammerPopup.text:SetTextColor(r / 255, g / 255, b / 255, 1)
    end
end

local function get_repair_nodes(hammerItemID)
    if not hammerItemID or not sfui.config.masterHammer[hammerItemID] then
        return {}
    end
    currentREPAIR_NODES = sfui.config.masterHammer[hammerItemID].nodes or {}
    return currentREPAIR_NODES
end

local function has_repair_perk(nodeID)
    if not nodeID then return false end
    local cfgID = find_bs_config()
    if not cfgID then return true end

    local nodeInfo = C_Traits.GetNodeInfo(cfgID, nodeID)
    if not nodeInfo or not nodeInfo.ID or nodeInfo.ID == 0 or not nodeInfo.currentRank then
        return true
    end

    return true
end

local function check_repair_eligibility(slot)
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then
        return nil -- Data not ready
    end

    local name, _, _, _, _, _, _, _, equipLoc, _, _, classID, subClassID = C_Item.GetItemInfo(itemLink)
    if not classID then
        print("SFUI Debug: ItemInfo not ready for", itemLink)
        return nil
    end

    local hasHammer, _, _, hammerItemID = sfui.automation.has_repair_hammer()
    if not hasHammer or not hammerItemID then return false end

    local nodes = get_repair_nodes(hammerItemID)

    -- Weapon (Class 2)
    if classID == 2 then
        local node = nodes[subClassID]
        if node then
            return has_repair_perk(node)
        end
        return false -- Unsupported weapon type
    end

    -- Armor (Class 4)
    if classID == 4 then
        if subClassID == 6 then -- Shield
            return has_repair_perk(nodes["SHIELD"])
        end
        if subClassID == 4 then -- Plate (4)
            local key = ARMOR_LOC_MAP[equipLoc]
            if key then return has_repair_perk(nodes[key]) end
            return false -- Plate slot we don't handle
        end
        return false     -- Non-plate/shield not supported
    end
    return false
end

function update_hammer_popup()
    if InCombatLockdown() then return end

    local hasHammer, hammerName, hammerIcon, hammerItemID = sfui.automation.has_repair_hammer()
    if not hasHammer then
        if hammerPopup then hammerPopup:Hide() end
        return
    end

    local popup = create_hammer_popup()
    if hammerIcon then popup.icon:SetTexture(hammerIcon) end

    local damagedFound = false
    local targetSlot = nil
    local totalBroken = 0
    local displayPct = 0

    -- 1. Count total broken and find lowest for display purposes
    -- Uses the configured threshold (default 90%)
    local lowestDur = 100
    local threshold = SfuiDB.repairThreshold or 90
    for _, slot in ipairs(SLOT_ORDER) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and cur < max then
            local pct = (cur / max) * 100
            if pct <= threshold then
                totalBroken = totalBroken + 1
            end
            if pct < lowestDur then lowestDur = pct end
        end
    end
    displayPct = math.floor(lowestDur)

    -- 2. Find the NEXT target in the rotation
    for i = 0, #SLOT_ORDER - 1 do
        local idx = ((rotationIndex + i - 1) % #SLOT_ORDER) + 1
        local slot = SLOT_ORDER[idx]
        local cur, max = GetInventoryItemDurability(slot)

        if cur and max and cur < max then
            targetSlot = slot
            rotationIndex = idx
            damagedFound = true
            break
        end
    end

    if damagedFound and targetSlot then
        local macro = string.format("/use %s\n/use %d", hammerName, targetSlot)
        popup:SetAttribute("type", "macro")
        popup:SetAttribute("macrotext", macro)

        if popup.text then
            popup.text:SetText(string.format("%d%% (%d)", displayPct, totalBroken))
        end

        popup:Show()
        popup:Show()
        -- Respect enable setting (defaults to true if nil)
        if SfuiDB.enableMasterHammer == false then
            popup:SetAlpha(0)
            popup:EnableMouse(false)
        else
            popup:SetAlpha(1)
            popup:EnableMouse(true)
        end
        currentTargetSlot = targetSlot
    else
        popup:Hide()
    end

    -- update_debug_panel() -- Removed: Use Options -> Debug
end

local function auto_repair()
    if not SfuiDB.autoRepair then return end
    if not CanMerchantRepair() then return end

    local hasHammer, hammerName = sfui.automation.has_repair_hammer()
    if hasHammer then
        print(string.format("|cffff9900Auto-repair skipped: %s detected.|r", hammerName))
        update_hammer_popup() -- Ensure popup shows
        return
    end

    local repairAllCost, canRepair = GetRepairAllCost()
    if not canRepair or repairAllCost == 0 then return end

    if CanGuildBankRepair() then
        RepairAllItems(true)
        print("|cff00ff00Auto-repaired using guild funds for " ..
            C_CurrencyInfo.GetCoinTextureString(repairAllCost) .. ".|r")
    else
        RepairAllItems(false)
        print("|cff00ff00Auto-repaired for " .. C_CurrencyInfo.GetCoinTextureString(repairAllCost) .. ".|r")
    end
end

function sfui.automation.initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    frame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- frame:RegisterEvent("BAG_UPDATE") -- Performance opt: Only scan on logic/reload
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    -- frame:RegisterEvent("UI_ERROR_MESSAGE") -- Removed as per user request to rely on durability only
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

    frame:SetScript("OnEvent", function(self, event, ...)
        local arg1, arg2, arg3 = ...
        if event == "LFG_ROLE_CHECK_SHOW" then
            C_Timer.After(0.1, on_role_check_show)
        elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            C_Timer.After(0.1, initialize_lfg_buttons)
        elseif event == "PLAYER_LOGIN" then
            setup_lfg_dialog()
            -- Perform initial one-time scan and check durability immediately
            sfui.automation.has_repair_hammer(false)
            update_hammer_popup()
        elseif event == "MERCHANT_SHOW" then
            rotationIndex = 1
            auto_sell_greys()
            auto_repair()
            update_hammer_popup()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            if arg1 == "player" and (arg3 == 382404 or arg3 == 382403) then -- Master's Hammer cast IDs
                currentTargetSlot = nil
                update_hammer_popup()
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            if arg1 == "player" and (arg3 == 382404 or arg3 == 382403) then
                -- Cast was cancelled/interrupted, clear the current target so it doesn't get blocked
                currentTargetSlot = nil
                update_hammer_popup()
            end
            -- elseif event == "UI_ERROR_MESSAGE" then
            --     -- Removed error handling to prevent false positives/spam.
            --     -- Items are repaired based solely on durability state.
        elseif event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_REGEN_ENABLED" or event == "GET_ITEM_INFO_RECEIVED" then
            update_hammer_popup()
        end
    end)
end
