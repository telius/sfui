local addonName, addon = ...
local isRetail = (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)
if not isRetail then return end

sfui = sfui or {}
sfui.hammer = sfui.hammer or {}

-- Localize frequently-called globals
local CreateFrame                = _G.CreateFrame
local UIParent                   = _G.UIParent
local InCombatLockdown           = _G.InCombatLockdown
local C_Timer                    = _G.C_Timer
local C_Container                = _G.C_Container
local C_Item                     = _G.C_Item
local C_Traits                   = _G.C_Traits
local C_TradeSkillUI             = _G.C_TradeSkillUI
local C_ProfSpecs                = _G.C_ProfSpecs
local GetInventoryItemLink       = _G.GetInventoryItemLink
local GetInventoryItemDurability = _G.GetInventoryItemDurability
local ipairs, tonumber, tostring = ipairs, tonumber, tostring
local math_floor                 = math.floor
local wipe                       = _G.wipe or table.wipe

local currentTargetSlot = nil
local SLOT_ORDER = { 16, 17, 1, 3, 5, 9, 10, 8, 7, 6 }
local rotationIndex = 1

local hammerPopup
local testModeActive = false

local KNOWN_BS_SKILL_LINES = { 2907, 2872, 2822 }

local profConfigIDs = {}
local seenSkillLines = {}

local function get_all_prof_configs()
    if #profConfigIDs > 0 then return profConfigIDs end

    wipe(profConfigIDs)
    wipe(seenSkillLines)

    local function addSkillLine(skillLineID)
        if not skillLineID or seenSkillLines[skillLineID] then return end
        seenSkillLines[skillLineID] = true
        if C_ProfSpecs and C_ProfSpecs.GetConfigIDForSkillLine then
            local cfgID = C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)
            if cfgID and cfgID > 0 then
                table.insert(profConfigIDs, cfgID)
            end
        end
    end

    -- 1. Query known Blacksmithing skill lines first (Midnight: 2907, TWW: 2872, DF: 2822)
    for _, skillLineID in ipairs(KNOWN_BS_SKILL_LINES) do
        addSkillLine(skillLineID)
    end

    -- 2. Query player's primary professions
    if _G.GetProfessions then
        local prof1, prof2 = _G.GetProfessions()
        for _, prof in ipairs({ prof1, prof2 }) do
            if prof and _G.GetProfessionInfo then
                local _, _, _, _, _, _, skillLine = _G.GetProfessionInfo(prof)
                if skillLine then
                    addSkillLine(skillLine)
                end
            end
        end
    end

    -- 3. Query trade skill lines from UI API if available
    if C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines then
        local skillLines = C_TradeSkillUI.GetAllProfessionTradeSkillLines()
        if skillLines then
            for _, skillLineID in ipairs(skillLines) do
                addSkillLine(skillLineID)
            end
        end
    end

    return profConfigIDs
end

local EXPANSION_NAMES = {
    [0]  = "Classic",
    [1]  = "The Burning Crusade",
    [2]  = "Wrath of the Lich King",
    [3]  = "Cataclysm",
    [4]  = "Mists of Pandaria",
    [5]  = "Warlords of Draenor",
    [6]  = "Legion",
    [7]  = "Battle for Azeroth",
    [8]  = "Shadowlands",
    [9]  = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
}
sfui.hammer.EXPANSION_NAMES = EXPANSION_NAMES

local itemExpansionCache = {}

local function get_item_expansion(itemLink)
    if not itemLink then return nil end
    local itemID = sfui.common.get_item_id(itemLink)
    if itemID and itemExpansionCache[itemID] ~= nil then
        return itemExpansionCache[itemID]
    end

    local expacID = select(15, C_Item.GetItemInfo(itemLink))
    if expacID == nil and _G.GetItemInfo then
        expacID = select(15, _G.GetItemInfo(itemLink))
    end

    if expacID == nil and itemID then
        sfui.common.request_item_load(itemID)
    end

    if expacID ~= nil and itemID then
        itemExpansionCache[itemID] = expacID
    end

    return expacID
end
sfui.hammer.get_item_expansion = get_item_expansion

local carriedHammers = {}
local carriedByExpac = {}
local hammerPool = {}
local seenBagItemIDs = {}
local primaryHammer = nil
local hammersChecked = false

local function recycle_hammer_entries()
    for _, entry in ipairs(carriedHammers) do
        table.insert(hammerPool, entry)
    end
    wipe(carriedHammers)
    wipe(carriedByExpac)
    wipe(seenBagItemIDs)
    primaryHammer = nil
end

local function get_hammer_entry(itemID, name, icon, expac, expacName, hammerCfg)
    local entry = table.remove(hammerPool) or {}
    entry.itemID = itemID
    entry.name = name
    entry.icon = icon
    entry.expansion = expac
    entry.expansionName = expacName
    entry.config = hammerCfg
    return entry
end

local function scan_bags_for_hammers()
    recycle_hammer_entries()

    sfui.common.for_each_bag_item(function(bag, slot, itemID, link, info)
        if info then
            local id = itemID or info.itemID or sfui.common.get_item_id(info.hyperlink)
            if id and not seenBagItemIDs[id] then
                local hammerCfg = sfui.config.masterHammer and sfui.config.masterHammer[id]
                if hammerCfg then
                    seenBagItemIDs[id] = true
                    local name, _, _, _, _, _, _, _, _, icon = (link or info.hyperlink) and C_Item.GetItemInfo and C_Item.GetItemInfo(link or info.hyperlink)
                    name = name or (id and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or "Master's Hammer"
                    icon = icon or (id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or info.iconFileID or 134376
                    local expac = hammerCfg.expansion
                    local expacName = hammerCfg.expansionName or (expac and EXPANSION_NAMES[expac]) or "Unknown"

                    local entry = get_hammer_entry(id, name, icon, expac, expacName, hammerCfg)
                    table.insert(carriedHammers, entry)
                    if expac then
                        carriedByExpac[expac] = entry
                    end
                    -- Prioritize higher expansion hammer as primary
                    if not primaryHammer or ((expac or 0) > (primaryHammer.expansion or 0)) then
                        primaryHammer = entry
                    end
                elseif info.hyperlink or id then
                    -- Fallback for generic/older hammers matching name
                    local name = ((link or info.hyperlink) and C_Item.GetItemInfo and C_Item.GetItemInfo(link or info.hyperlink)) or (id and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
                    if name and (name:find("Master.s Hammer") or name:find("Master Repair Hammer") or name:find("Meisterhammer")) then
                        seenBagItemIDs[id] = true
                        local _, _, _, _, _, _, _, _, _, icon = (link or info.hyperlink) and C_Item.GetItemInfo and C_Item.GetItemInfo(link or info.hyperlink)
                        icon = icon or (id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or info.iconFileID or 134376
                        local entry = get_hammer_entry(id, name, icon, nil, "Generic", nil)
                        table.insert(carriedHammers, entry)
                        if not primaryHammer then
                            primaryHammer = entry
                        end
                    end
                end
            end
        end
    end)

    hammersChecked = true
    return carriedHammers
end

function sfui.hammer.get_carried_hammers(forceRefresh)
    if forceRefresh or not hammersChecked then
        scan_bags_for_hammers()
    end
    return carriedHammers, carriedByExpac, primaryHammer
end

function sfui.hammer.has_repair_hammer(forceRefresh, targetExpac)
    if forceRefresh or not hammersChecked then
        scan_bags_for_hammers()
    end

    if targetExpac and carriedByExpac[targetExpac] then
        local h = carriedByExpac[targetExpac]
        return true, h.name, h.icon, h.itemID
    end

    if primaryHammer then
        return true, primaryHammer.name, primaryHammer.icon, primaryHammer.itemID
    end

    return false
end

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

local function extract_node_rank(cfgID, nodeInfo)
    if not nodeInfo then return 0, 0 end
    local maxRanks = nodeInfo.maxRanks or 0
    local highestRank = 0

    -- 1. Check currentRank (committed ranks)
    if type(nodeInfo.currentRank) == "number" and nodeInfo.currentRank > highestRank then
        highestRank = nodeInfo.currentRank
    end

    -- 2. Check activeRank (active ranks including unlock rank)
    if type(nodeInfo.activeRank) == "number" and nodeInfo.activeRank > highestRank then
        highestRank = nodeInfo.activeRank
    end

    -- 3. Check activeEntry (active entry rank in C_Traits)
    if nodeInfo.activeEntry and type(nodeInfo.activeEntry.rank) == "number" and nodeInfo.activeEntry.rank > highestRank then
        highestRank = nodeInfo.activeEntry.rank
    end

    -- 4. Check ranksPurchased (staged uncommitted ranks)
    if type(nodeInfo.ranksPurchased) == "number" and nodeInfo.ranksPurchased > highestRank then
        highestRank = nodeInfo.ranksPurchased
    end

    -- 5. Check entryIDsWithCommittedRanks
    if nodeInfo.entryIDsWithCommittedRanks and #nodeInfo.entryIDsWithCommittedRanks > 0 and C_Traits and C_Traits.GetEntryInfo then
        for _, entryID in ipairs(nodeInfo.entryIDsWithCommittedRanks) do
            local entry = C_Traits.GetEntryInfo(cfgID, entryID)
            if entry and type(entry.rank) == "number" and entry.rank > highestRank then
                highestRank = entry.rank
            end
        end
    end

    -- 6. Check entryIDs directly
    if nodeInfo.entryIDs and #nodeInfo.entryIDs > 0 and C_Traits and C_Traits.GetEntryInfo then
        for _, entryID in ipairs(nodeInfo.entryIDs) do
            local entry = C_Traits.GetEntryInfo(cfgID, entryID)
            if entry and type(entry.rank) == "number" and entry.rank > highestRank then
                highestRank = entry.rank
            end
        end
    end

    return highestRank, maxRanks
end

local perkCache = {}

local function has_repair_perk(nodeID)
    if not nodeID then return false, 0, 0 end

    local cached = perkCache[nodeID]
    if cached ~= nil then
        return cached.unlocked, cached.rank, cached.maxRank
    end

    local cfgs = get_all_prof_configs()
    if not cfgs or #cfgs == 0 then return true, 0, 0 end

    local requiredRank = (sfui.config.masterHammer and sfui.config.masterHammer.requiredRank) or 26
    local bestRank = 0
    local bestMaxRanks = 0
    local perkUnlocked = false

    for _, cfgID in ipairs(cfgs) do
        local nodeInfo = C_Traits and C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(cfgID, nodeID)
        if nodeInfo and nodeInfo.ID == nodeID then
            local rank, maxRanks = extract_node_rank(cfgID, nodeInfo)
            if maxRanks > bestMaxRanks then bestMaxRanks = maxRanks end
            if rank > bestRank then bestRank = rank end

            -- Milestone 5:
            -- 1. If rank is maxed (e.g. 26/26 or 25/25)
            local isMaxed = (maxRanks > 0 and rank >= maxRanks)
            -- 2. If rank directly meets requiredRank (26, 0 counts as a step too)
            local meetsRequired = (rank >= requiredRank)

            if isMaxed or meetsRequired then
                perkUnlocked = true
                bestRank = rank
                bestMaxRanks = maxRanks
                break
            end
        end
    end

    perkCache[nodeID] = { unlocked = perkUnlocked, rank = bestRank, maxRank = bestMaxRanks }
    return perkUnlocked, bestRank, bestMaxRanks
end

local function check_repair_eligibility_detail(slot, needDetail)
    local itemLink = GetInventoryItemLink("player", slot)
    if not itemLink then return false, needDetail and "No item link" or nil, nil, nil end

    local _, _, _, equipLoc, _, classID, subClassID = sfui.common.get_item_instant_info(itemLink)
    if not classID then return false, needDetail and "Cannot determine item type" or nil, nil, nil end

    local itemExpac = get_item_expansion(itemLink)
    local itemExpacName = needDetail and ((itemExpac and EXPANSION_NAMES[itemExpac]) or (itemExpac and ("Expac " .. itemExpac)) or nil)

    -- Find matching hammer for this item's expansion
    local hasMatchingHammer, hammerName, hammerIcon, hammerItemID
    if itemExpac then
        hasMatchingHammer, hammerName, hammerIcon, hammerItemID = sfui.hammer.has_repair_hammer(false, itemExpac)
    end

    -- If no expansion-specific hammer found, check if player carries ANY hammer
    if not hasMatchingHammer then
        local hasAny, anyName, _, anyItemID = sfui.hammer.has_repair_hammer(false)
        if not hasAny then
            return false, needDetail and "No Master's Hammer in bags" or nil, itemExpac, nil
        end

        -- Player carries a hammer, but it is from a different expansion
        if itemExpac then
            local anyCfg = sfui.config.masterHammer and sfui.config.masterHammer[anyItemID]
            local carriedExpacName = anyCfg and (anyCfg.expansionName or EXPANSION_NAMES[anyCfg.expansion]) or "different expansion"
            local reason = needDetail and string.format("%s item requires %s hammer (carrying %s)", itemExpacName, itemExpacName, carriedExpacName) or nil
            return false, reason, itemExpac, nil
        else
            hammerItemID = anyItemID
            hammerName = anyName
        end
    end

    local hammerConfig = sfui.config.masterHammer and sfui.config.masterHammer[hammerItemID]
    if not hammerConfig then
        return true, needDetail and "Generic hammer allowed" or nil, itemExpac, hammerItemID
    end

    local reqRank = (sfui.config.masterHammer and sfui.config.masterHammer.requiredRank) or 26

    -- Universal Node support (Dragonflight Master's Hammer 198254 -> node 82244)
    if hammerConfig.universalNode then
        local hasPerk, rank, maxRank = has_repair_perk(hammerConfig.universalNode)
        if not hasPerk then
            local reason = needDetail and string.format("Universal node %d rank %d/%d (requires %d)", hammerConfig.universalNode, rank, maxRank or 0, reqRank) or nil
            return false, reason, itemExpac, hammerItemID
        end
        if classID == 2 then return true, needDetail and string.format("Weapon (Universal perk active %d/%d)", rank, maxRank or 0) or nil, itemExpac, hammerItemID end
        if classID == 4 then
            if subClassID == 6 then return true, needDetail and string.format("Shield (Universal perk active %d/%d)", rank, maxRank or 0) or nil, itemExpac, hammerItemID end
            if subClassID == 4 then return true, needDetail and string.format("Plate (Universal perk active %d/%d)", rank, maxRank or 0) or nil, itemExpac, hammerItemID end
        end
        return false, needDetail and "Non-plate/shield/weapon item cannot be repaired by Blacksmithing" or nil, itemExpac, hammerItemID
    end

    local nodes = hammerConfig.nodes
    if not nodes then return true, needDetail and "No node restrictions" or nil, itemExpac, hammerItemID end

    -- Weapon (Class 2)
    if classID == 2 then
        local node = nodes[subClassID]
        if node then
            local hasPerk, rank, maxRank = has_repair_perk(node)
            if hasPerk then
                return true, needDetail and string.format("Weapon node %d rank %d/%d", node, rank, maxRank or 0) or nil, itemExpac, hammerItemID
            else
                return false, needDetail and string.format("Weapon node %d rank %d/%d (requires %d)", node, rank, maxRank or 0, reqRank) or nil, itemExpac, hammerItemID
            end
        end
        return false, needDetail and "Weapon subclass not repairable by Blacksmithing" or nil, itemExpac, hammerItemID
    end

    -- Armor (Class 4)
    if classID == 4 then
        if subClassID == 6 then -- Shield
            local node = nodes["SHIELD"]
            if node then
                local hasPerk, rank, maxRank = has_repair_perk(node)
                if hasPerk then
                    return true, needDetail and string.format("Shield node %d rank %d/%d", node, rank, maxRank or 0) or nil, itemExpac, hammerItemID
                else
                    return false, needDetail and string.format("Shield node %d rank %d/%d (requires %d)", node, rank, maxRank or 0, reqRank) or nil, itemExpac, hammerItemID
                end
            end
            return false, needDetail and "Shield repair node not configured" or nil, itemExpac, hammerItemID
        end
        if subClassID == 4 then -- Plate (4)
            local key = ARMOR_LOC_MAP[equipLoc]
            if key and nodes[key] then
                local node = nodes[key]
                local hasPerk, rank, maxRank = has_repair_perk(node)
                if hasPerk then
                    return true, needDetail and string.format("%s plate node %d rank %d/%d", key, node, rank, maxRank or 0) or nil, itemExpac, hammerItemID
                else
                    return false, needDetail and string.format("%s plate node %d rank %d/%d (requires %d)", key, node, rank, maxRank or 0, reqRank) or nil, itemExpac, hammerItemID
                end
            end
            return false, needDetail and string.format("Plate slot %s node not found", tostring(key or equipLoc)) or nil, itemExpac, hammerItemID
        end
        return false, needDetail and "Cloth, Leather, or Mail cannot be repaired by Blacksmithing" or nil, itemExpac, hammerItemID
    end

    return false, needDetail and "Non-equipment item" or nil, itemExpac, hammerItemID
end

local function check_repair_eligibility(slot)
    return check_repair_eligibility_detail(slot, false)
end

function sfui.hammer.can_repair_any_damaged()
    local threshold = SfuiDB.repairThreshold or 90
    for _, slot in ipairs(SLOT_ORDER) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 and cur < max then
            local pct = (cur / max) * 100
            if pct <= threshold and check_repair_eligibility(slot) then
                return true
            end
        end
    end
    return false
end

function sfui.hammer.is_test_mode()
    return testModeActive
end

local function create_hammer_popup()
    if hammerPopup then return hammerPopup end
    hammerPopup = CreateFrame("Button", "SfuiHammerPopup", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
    hammerPopup:SetSize(64, 64)
    hammerPopup:SetFrameStrata("DIALOG")              -- Ensure it's on top of UI frames
    hammerPopup:SetFrameLevel(100)
    hammerPopup:SetClampedToScreen(true)
    hammerPopup:RegisterForClicks("AnyUp", "AnyDown") -- Ensure it accepts clicks
    hammerPopup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    hammerPopup:SetBackdropColor(0, 0, 0, 0.8)

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

    -- Tooltip info
    hammerPopup:SetScript("OnEnter", function(self)
        local tip = sfui.tooltip or _G.GameTooltip
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")

        if testModeActive then
            tip:AddLine("Master's Hammer (Preview Mode)", 0, 1, 1)
            tip:AddLine("This is a preview of the automated repair button.", 1, 1, 1)
            tip:AddLine(" ")
            tip:AddLine("|cff00ff00Left Drag|r: Move button position", 0.7, 0.7, 0.7)
            tip:AddLine("|cff00ffff/sfui hammer test|r: Toggle preview off", 0.7, 0.7, 0.7)
            tip:Show()
            return
        end

        local _, hammerName = sfui.hammer.has_repair_hammer()
        tip:AddLine(hammerName or "Master's Hammer", 0, 1, 1)

        if currentTargetSlot then
            local targetLink = GetInventoryItemLink("player", currentTargetSlot)
            local cur, max = GetInventoryItemDurability(currentTargetSlot)
            local durStr = (cur and max and max > 0) and string.format(" (%d%%)", math_floor((cur / max) * 100)) or ""
            local targetExpac = get_item_expansion(targetLink)
            local targetExpacName = (targetExpac and EXPANSION_NAMES[targetExpac]) or (targetExpac and ("Expac " .. targetExpac))
            local expacSuffix = targetExpacName and (" [" .. targetExpacName .. "]") or ""
            tip:AddLine("Next Target: " .. (targetLink or ("Slot " .. currentTargetSlot)) .. durStr .. expacSuffix, 1, 1, 1)
        end

        local damagedCount = 0
        local threshold = SfuiDB.repairThreshold or 90
        for _, slot in ipairs(SLOT_ORDER) do
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 and cur < max and check_repair_eligibility(slot) then
                local pct = math_floor((cur / max) * 100)
                if pct <= threshold then
                    local link = GetInventoryItemLink("player", slot)
                    if link then
                        damagedCount = damagedCount + 1
                        if damagedCount == 1 then
                            tip:AddLine(" ")
                            tip:AddLine("Eligible Damaged Gear:", 1, 0.82, 0)
                        end
                        local slotExpac = get_item_expansion(link)
                        local slotExpacName = (slotExpac and EXPANSION_NAMES[slotExpac])
                        local textLeft = slotExpacName and (link .. " |cff888888[" .. slotExpacName .. "]|r") or link
                        tip:AddDoubleLine(textLeft, string.format("%d%%", pct), 1, 1, 1, 1, pct < 50 and 0.2 or 0.8, 0.2)
                    end
                end
            end
        end

        tip:AddLine(" ")
        tip:AddLine("|cff00ff00Click|r: Repair targeted item", 0.7, 0.7, 0.7)
        if not SfuiDB.lockRepairIcon then
            tip:AddLine("|cff00ff00Drag|r: Move icon", 0.7, 0.7, 0.7)
        end
        tip:Show()
    end)
    hammerPopup:SetScript("OnLeave", function()
        local tip = sfui.tooltip or _G.GameTooltip
        if tip then tip:Hide() end
    end)

    -- Apply Aesthetics from DB
    hammerPopup:Hide()

    hammerPopup:SetScript("PostClick", function(self, button, down)
        if down then return end
        if InCombatLockdown() then return end
        if testModeActive then
            if sfui.common and sfui.common.print then
                sfui.common.print("sfui: repair button test click received.")
            end
            return
        end
        -- Move to the next slot in the rotation immediately
        rotationIndex = (rotationIndex % #SLOT_ORDER) + 1
        sfui.hammer.update_hammer_popup()
    end)

    hammerPopup:SetScript("PreClick", function(self)
        if InCombatLockdown() or testModeActive then return end
        -- Listen for the cast result only when we actually use the tool
        sfui.hammer.register_transient_listeners()
    end)

    -- Make Movable
    hammerPopup:SetMovable(true)
    hammerPopup:RegisterForDrag("LeftButton")
    hammerPopup:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        if not SfuiDB.lockRepairIcon or testModeActive then
            self:StartMoving()
        end
    end)
    hammerPopup:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        -- Save position relative to center
        local center_x, center_y = self:GetCenter()
        local uip_x, uip_y = UIParent:GetCenter()
        if not center_x or not center_y or not uip_x or not uip_y then return end

        local x = math_floor(center_x - uip_x)
        local y = math_floor(center_y - uip_y)

        SfuiDB.repairIconX = x
        SfuiDB.repairIconY = y

        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", x, y)

        if sfui.options and sfui.options.sync_hammer_sliders then
            sfui.options.sync_hammer_sliders(x, y)
        end
    end)

    sfui.hammer.update_popup_style() -- Apply initial style
    return hammerPopup
end

function sfui.hammer.update_popup_style()
    local popup = hammerPopup or create_hammer_popup()
    if not popup then return end

    -- Apply position from DB or config defaults
    local defaultPos = sfui.config.masterHammer.defaultPosition
    local x = SfuiDB.repairIconX or defaultPos.x
    local y = SfuiDB.repairIconY or defaultPos.y
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", UIParent, "CENTER", x, y)

    -- Apply color from DB or config default
    local hex = SfuiDB.repairIconColor or sfui.config.masterHammer.defaultColor
    if hex:sub(1, 1) == "#" then hex = hex:sub(2) end
    local r = tonumber("0x" .. hex:sub(1, 2)) or 255
    local g = tonumber("0x" .. hex:sub(3, 4)) or 0
    local b = tonumber("0x" .. hex:sub(5, 6)) or 255

    popup:SetBackdropBorderColor(r / 255, g / 255, b / 255, 1)
    if popup.text then
        popup.text:SetTextColor(r / 255, g / 255, b / 255, 1)
    end
end

function sfui.hammer.toggle_test_popup(enable)
    if InCombatLockdown() then
        if sfui.common and sfui.common.print then
            sfui.common.print("sfui: cannot toggle repair preview during combat.")
        end
        return false
    end

    if enable == nil then
        testModeActive = not testModeActive
    else
        testModeActive = enable
    end

    local popup = create_hammer_popup()
    if testModeActive then
        local _, hammerName, hammerIcon = sfui.hammer.has_repair_hammer()
        local fallbackIcon = (C_Item and C_Item.GetItemIconByID and (C_Item.GetItemIconByID(238020) or C_Item.GetItemIconByID(225660) or C_Item.GetItemIconByID(198254))) or 134376
        popup.icon:SetTexture(hammerIcon or fallbackIcon)
        popup:SetAttribute("type", nil)
        popup:SetAttribute("macrotext", nil)
        if popup.text then
            popup.text:SetText("TEST (3)")
        end
        sfui.hammer.update_popup_style()
        popup:SetAlpha(1)
        popup:EnableMouse(true)
        popup:Show()
        if sfui.common and sfui.common.print then
            sfui.common.print("sfui: repair button preview shown. Drag with left-click to move.")
        end
    else
        popup:Hide()
        if sfui.common and sfui.common.print then
            sfui.common.print("sfui: repair button preview hidden.")
        end
        sfui.hammer.update_hammer_popup()
    end
    return testModeActive
end

function sfui.hammer.update_hammer_popup()
    if InCombatLockdown() then return end
    if testModeActive then return end

    if SfuiDB.enableMasterHammer == false then
        if hammerPopup then hammerPopup:Hide() end
        currentTargetSlot = nil
        return
    end

    local hasHammer, hammerName, hammerIcon, hammerItemID = sfui.hammer.has_repair_hammer()
    if not hasHammer or not hammerItemID then
        if hammerPopup then hammerPopup:Hide() end
        currentTargetSlot = nil
        return
    end

    local popup = create_hammer_popup()

    local damagedFound = false
    local targetSlot = nil
    local targetHammerItemID = nil
    local totalBroken = 0
    local displayPct = 0

    -- 1. Count total broken and find lowest for display purposes (only eligible gear!)
    local lowestDur = 100
    local threshold = SfuiDB.repairThreshold or 90
    for _, slot in ipairs(SLOT_ORDER) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 and cur < max then
            local pct = (cur / max) * 100
            if pct <= threshold and check_repair_eligibility(slot) then
                totalBroken = totalBroken + 1
                if pct < lowestDur then lowestDur = pct end
            end
        end
    end
    displayPct = (lowestDur < 100) and math_floor(lowestDur) or 0

    -- 2. Find the NEXT target in the rotation
    for i = 0, #SLOT_ORDER - 1 do
        local idx = ((rotationIndex + i - 1) % #SLOT_ORDER) + 1
        local slot = SLOT_ORDER[idx]
        local cur, max = GetInventoryItemDurability(slot)

        if cur and max and max > 0 and cur < max then
            local pct = (cur / max) * 100
            if pct <= threshold then
                local eligible, _, _, itemHammerID = check_repair_eligibility(slot)
                if eligible and itemHammerID then
                    targetSlot = slot
                    targetHammerItemID = itemHammerID
                    rotationIndex = idx
                    damagedFound = true
                    break
                end
            end
        end
    end

    if damagedFound and targetSlot and targetHammerItemID then
        local macro = string.format("/use item:%d\n/use %d", targetHammerItemID, targetSlot)
        popup:SetAttribute("type", "macro")
        popup:SetAttribute("macrotext", macro)

        local activeIcon = (targetHammerItemID and C_Item.GetItemIconByID and C_Item.GetItemIconByID(targetHammerItemID)) or hammerIcon
        if activeIcon then popup.icon:SetTexture(activeIcon) end

        if popup.text then
            popup.text:SetText(string.format("%d%% (%d)", displayPct, totalBroken))
        end

        popup:SetAlpha(1)
        popup:EnableMouse(true)
        popup:Show()
        currentTargetSlot = targetSlot
    else
        popup:Hide()
        currentTargetSlot = nil
    end
end

local updatePending = false
local function request_popup_update(delay)
    if updatePending then return end
    updatePending = true
    local seconds = (type(delay) == "number" and delay > 0 and delay) or 1.0
    C_Timer.After(seconds, function()
        updatePending = false
        sfui.hammer.update_hammer_popup()
    end)
end
sfui.hammer.request_popup_update = request_popup_update

function sfui.hammer.reset_caches()
    hammersChecked = false
    wipe(perkCache)
    wipe(profConfigIDs)
    wipe(seenSkillLines)
    wipe(itemExpansionCache)
end

function sfui.hammer.print_hammer_status(debugMode)
    local p = (sfui.common and sfui.common.print) or print
    p("|cff00ffff[SFUI] Master's Hammer Status:|r")
    p(string.format("  Enabled: %s", (SfuiDB.enableMasterHammer ~= false) and "|cff00ff00Yes|r" or "|cffff0000No|r"))

    sfui.hammer.reset_caches()
    local carried, byExpac, prim = sfui.hammer.get_carried_hammers(true)
    if #carried > 0 then
        p(string.format("  Hammers in Bags (%d found):", #carried))
        for _, h in ipairs(carried) do
            p(string.format("    - |cff00ff00Found|r %s [%s] (ID: %d)", h.name, h.expansionName or "Unknown", h.itemID))
        end
    else
        p("  Hammer in Bags: |cffff0000Not found|r in bags 0-5. (Must carry a Master's Hammer)")
    end

    local threshold = SfuiDB.repairThreshold or 90
    p(string.format("  Threshold: %d%% durability or lower", threshold))
    local reqRank = sfui.config.masterHammer and sfui.config.masterHammer.requiredRank or 26
    p(string.format("  Required Trait Rank: %d", reqRank))

    local cfgs = get_all_prof_configs()
    if debugMode then
        local cfgStr = (cfgs and #cfgs > 0) and table.concat(cfgs, ", ") or "None"
        p(string.format("  [DEBUG] Profession Config IDs: %s", cfgStr))
    end

    local totalSlots = 0
    local damagedSlots = 0
    local eligibleDamaged = 0

    for _, slot in ipairs(SLOT_ORDER) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            totalSlots = totalSlots + 1
            local cur, max = GetInventoryItemDurability(slot)
            if cur and max and max > 0 then
                local pct = math_floor((cur / max) * 100)
                if cur < max then
                    damagedSlots = damagedSlots + 1
                    local eligible, reason, itemExpac, itemHammerID = check_repair_eligibility_detail(slot, true)
                    local isBelow = (pct <= threshold)
                    local expacName = (itemExpac and EXPANSION_NAMES[itemExpac]) or (itemExpac and ("Expac " .. itemExpac)) or "Unknown"
                    local expacTag = string.format("|cff888888[%s]|r", expacName)

                    if eligible and isBelow then
                        eligibleDamaged = eligibleDamaged + 1
                        p(string.format("    - Slot %d: %s %s at %d%% |cff00ff00[ELIGIBLE]|r (%s)", slot, link, expacTag, pct, reason or "OK"))
                    elseif eligible and not isBelow then
                        p(string.format("    - Slot %d: %s %s at %d%% (Above threshold %d%%, %s)", slot, link, expacTag, pct, threshold, reason or "OK"))
                    else
                        p(string.format("    - Slot %d: %s %s at %d%% |cffff6666[INELIGIBLE]|r (%s)", slot, link, expacTag, pct, reason or "Perk missing or ineligible"))
                    end

                    if debugMode and cfgs then
                        local _, _, _, equipLoc, _, classID, subClassID = sfui.common.get_item_instant_info(link)
                        local hammerConfig = itemHammerID and sfui.config.masterHammer and sfui.config.masterHammer[itemHammerID]
                        if not hammerConfig and prim then
                            hammerConfig = prim.config
                        end
                        local nodeID = hammerConfig and hammerConfig.nodes and (classID == 2 and hammerConfig.nodes[subClassID] or (classID == 4 and (subClassID == 6 and hammerConfig.nodes["SHIELD"] or (subClassID == 4 and ARMOR_LOC_MAP[equipLoc] and hammerConfig.nodes[ARMOR_LOC_MAP[equipLoc]]))))
                        if nodeID then
                            for _, cID in ipairs(cfgs) do
                                local nInfo = C_Traits and C_Traits.GetNodeInfo and C_Traits.GetNodeInfo(cID, nodeID)
                                if nInfo then
                                    p(string.format("      cfg %d: curRank=%s, actRank=%s, purRank=%s, actEntryRank=%s, maxRanks=%s",
                                        cID, tostring(nInfo.currentRank), tostring(nInfo.activeRank), tostring(nInfo.ranksPurchased),
                                        tostring(nInfo.activeEntry and nInfo.activeEntry.rank), tostring(nInfo.maxRanks)))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if damagedSlots == 0 then
        p("  Gear Durability: |cff00ff00All equipped items are at 100% durability.|r")
    end

    local isShown = hammerPopup and hammerPopup:IsShown()
    p(string.format("  Button State: %s", isShown and "|cff00ff00VISIBLE|r" or "|cffff8800HIDDEN|r"))
    if not isShown then
        if #carried == 0 then
            p("  Reason hidden: No Master's Hammer found in bags.")
        elseif eligibleDamaged == 0 then
            p("  Reason hidden: No eligible damaged gear <= threshold.")
        elseif InCombatLockdown() then
            p("  Reason hidden: In combat lockdown.")
        end
    end
    p("  Tip: Type |cff00ffff/sfui hammer test|r to preview and reposition the button.")
end

local function on_hammer_cast_finished(event, unit, _, spellID)
    if unit == "player" then
        local _, _, _, hammerItemID = sfui.hammer.has_repair_hammer()
        local _, hammerSpellID = hammerItemID and C_Item.GetItemSpell(hammerItemID)
        if (hammerSpellID and spellID == hammerSpellID) or spellID == 382404 or spellID == 382403 or not hammerSpellID then
            currentTargetSlot = nil
            sfui.hammer.update_hammer_popup()
            sfui.hammer.unregister_transient_listeners()
        end
    end
end

local function on_hammer_cast_interrupted(event, unit, _, spellID)
    if unit == "player" then
        local _, _, _, hammerItemID = sfui.hammer.has_repair_hammer()
        local _, hammerSpellID = hammerItemID and C_Item.GetItemSpell(hammerItemID)
        if (hammerSpellID and spellID == hammerSpellID) or spellID == 382404 or spellID == 382403 or not hammerSpellID then
            currentTargetSlot = nil
            sfui.hammer.update_hammer_popup()
            sfui.hammer.unregister_transient_listeners()
        end
    end
end

function sfui.hammer.register_transient_listeners()
    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", on_hammer_cast_finished)
    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", on_hammer_cast_interrupted)
    C_Timer.After(5, sfui.hammer.unregister_transient_listeners)
end

function sfui.hammer.unregister_transient_listeners()
    sfui.events.UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", on_hammer_cast_finished)
    sfui.events.UnregisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", on_hammer_cast_interrupted)
end

local function on_traits_updated()
    sfui.hammer.reset_caches()
    request_popup_update()
end

local function on_bags_updated()
    hammersChecked = false
    request_popup_update()
end

local function on_equipment_updated()
    request_popup_update()
end

local function on_durability_or_regen()
    request_popup_update()
end

-- Event Listeners
sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", on_bags_updated)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_traits_updated)
sfui.events.RegisterEvent("SKILL_LINES_CHANGED", on_traits_updated)
sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", on_equipment_updated)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    sfui.hammer.reset_caches()
    request_popup_update(1.0)
end)
sfui.events.RegisterEvent("UPDATE_INVENTORY_DURABILITY", on_durability_or_regen)
sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_durability_or_regen)
sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(event, itemID, success)
    if not success or not itemID then return end
    request_popup_update()
end)

function sfui.hammer.initialize()
    sfui.hammer.update_hammer_popup()
end

-- Backward compatibility aliases on sfui.automation
sfui.automation = sfui.automation or {}
sfui.automation.has_repair_hammer = sfui.hammer.has_repair_hammer
sfui.automation.get_carried_hammers = sfui.hammer.get_carried_hammers
sfui.automation.get_item_expansion = sfui.hammer.get_item_expansion
sfui.automation.EXPANSION_NAMES = sfui.hammer.EXPANSION_NAMES
sfui.automation.update_hammer_popup = sfui.hammer.update_hammer_popup
sfui.automation.toggle_test_popup = sfui.hammer.toggle_test_popup
sfui.automation.is_test_mode = sfui.hammer.is_test_mode
sfui.automation.update_popup_style = sfui.hammer.update_popup_style
sfui.automation.print_hammer_status = sfui.hammer.print_hammer_status
sfui.automation.register_transient_listeners = sfui.hammer.register_transient_listeners
sfui.automation.unregister_transient_listeners = sfui.hammer.unregister_transient_listeners
sfui.automation.can_repair_any_damaged = sfui.hammer.can_repair_any_damaged
sfui.automation.reset_caches = sfui.hammer.reset_caches

local _hamDebug = {}
function sfui.hammer_debug_info()
    local found, _, _, itemID = sfui.hammer.has_repair_hammer(true)
    local carried = sfui.hammer.get_carried_hammers()
    _hamDebug.hasHammer = found
    _hamDebug.hammerItemID = itemID
    _hamDebug.carriedCount = carried and #carried or 0
    _hamDebug.popupShown = (hammerPopup and hammerPopup:IsShown()) and true or false
    return _hamDebug
end

if sfui.RegisterModule then
    sfui.hammer.GetDebugInfo = sfui.hammer_debug_info
    sfui.RegisterModule("hammer", sfui.hammer)
end
