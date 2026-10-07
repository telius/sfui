local addonName, addon = ...
sfui = sfui or {}
sfui.triage = sfui.triage or {}
local triage = sfui.triage

local common = sfui.common
local issecretvalue = common.issecretvalue or _G.issecretvalue

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/automation/triage.lua
--  Automated Bag Triage & Overflow Discard Confirmation System
--
--  Monitors regular bag space while leveling/questing. When free slots drop
--  to 1 or 0, analyzes lowest-value grey junk (or outdated consumables)
--  and prompts the player with a safe, confirmed one-click drop action.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localize frequently called globals
local CreateFrame              = _G.CreateFrame
local UIParent                 = _G.UIParent
local InCombatLockdown         = _G.InCombatLockdown
local PlaySound                = _G.PlaySound
local SOUNDKIT                 = _G.SOUNDKIT
local UnitLevel                = _G.UnitLevel
local UnitIsDeadOrGhost        = _G.UnitIsDeadOrGhost
local C_Timer                  = _G.C_Timer
local C_Container              = _G.C_Container
local Enum                     = _G.Enum

-- Container API compatibility (Classic Era, Camelot, Retail)
local GetContainerNumSlots     = (C_Container and C_Container.GetContainerNumSlots) or _G.GetContainerNumSlots
local GetContainerNumFreeSlots = (C_Container and C_Container.GetContainerNumFreeSlots) or _G.GetContainerNumFreeSlots
local GetContainerItemInfo     = (C_Container and C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo
local GetContainerItemID       = (C_Container and C_Container.GetContainerItemID) or _G.GetContainerItemID
local GetContainerItemLink     = (C_Container and C_Container.GetContainerItemLink) or _G.GetContainerItemLink
local PickupContainerItem      = (C_Container and C_Container.PickupContainerItem) or _G.PickupContainerItem
local DeleteCursorItem         = _G.DeleteCursorItem
local ClearCursor              = _G.ClearCursor
local CursorHasItem            = _G.CursorHasItem

local math_max                 = math.max
local table_sort               = table.sort
local string_format            = string.format
local wipe                     = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- Essential / Protected Item IDs (Never recommend dropping these)
local PROTECTED_ITEM_IDS = {
    -- Hearthstones & Teleportation Gadgets
    [6948]   = true, -- Hearthstone
    [140192] = true, -- Dalaran Hearthstone
    [110560] = true, -- Garrison Hearthstone
    [128353] = true, -- Admiral's Compass
    [141605] = true, -- Flight Master's Whistle

    -- Class Reagents & Consumable Tools
    [6265]   = true, -- Soul Shard (Warlock)
    [17030]  = true, -- Ankh (Shaman)
    [17057]  = true, -- Shiny Fish Scales (Shaman)
    [17058]  = true, -- Fish Oil (Shaman)
    [5140]   = true, -- Flash Powder (Rogue)
    [8924]   = true, -- Blinding Powder (Rogue)
    [5060]   = true, -- Thieves' Tools (Rogue)
    [17020]  = true, -- Arcane Powder (Mage)
    [17031]  = true, -- Rune of Teleportation (Mage)
    [17032]  = true, -- Rune of Portals (Mage)
    [17034]  = true, -- Wild Thornroot (Druid)
    [17035]  = true, -- Ironwood Seed (Druid)
    [17028]  = true, -- Sacred Candle (Priest)
    [17029]  = true, -- Holy Candle (Priest)
    [17033]  = true, -- Symbol of Divinity (Paladin)
    [21177]  = true, -- Symbol of Kings (Paladin)

    -- Profession Tools & Gadgets
    [5956]   = true, -- Blacksmith Hammer
    [2901]   = true, -- Mining Pick
    [7005]   = true, -- Skinning Knife
    [6256]   = true, -- Fishing Pole
    [4470]   = true, -- Simple Wood
    [4471]   = true, -- Flint and Tinder
    [6218]   = true, -- Copper Rod
    [6219]   = true, -- Silver Rod
    [6339]   = true, -- Golden Rod
    [11130]  = true, -- Truesilver Rod
    [11145]  = true, -- Arcanite Rod
    [22461]  = true, -- Fel Iron Rod
    [22462]  = true, -- Adamantite Rod
    [22463]  = true, -- Eternium Rod
    [9149]   = true, -- Philosopher's Stone
    [13503]  = true, -- Alchemist's Stone
    [4075]   = true, -- Arclight Spanner
    [4077]   = true, -- Gyromatic Micro-Adjustor
    [20815]  = true, -- Jeweler's Kit
    [20824]  = true, -- Simple Grinder
}

-- Runtime state
local promptFrame           = nil
local currentCandidates     = {}
local currentCandidateIndex = 1
local currentCandidate      = nil
local ignoredInSession      = {}
local isTestMode            = false
local scanTimer             = nil
local lastFreeSlots         = -1
local isEnabled             = true

-- ─────────────────────────────────────────────────────────────────────────────
--  Inventory Scanning & Candidate Analysis
-- ─────────────────────────────────────────────────────────────────────────────

--- Determines whether an equipped container is a standard, general-purpose inventory bag
--- (strictly excluding profession bags, herb/mining/gem/enchanting pouches, soul bags, quivers, ammo pouches, reagent bags)
--- @param bag number
--- @return boolean isRegular, number freeSlots
local function is_regular_inventory_bag(bag)
    if bag == 0 then
        -- Bag 0 is always the primary backpack
        local freeSlots = GetContainerNumFreeSlots and GetContainerNumFreeSlots(0) or 0
        return true, freeSlots or 0
    end

    -- Strictly restrict to equipped character bags 1 to NUM_BAG_SLOTS (excludes keyring -2, bank bags, and retail reagent bag)
    if bag < 1 or bag > (_G.NUM_BAG_SLOTS or 4) then
        return false, 0
    end

    local numSlots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
    if not numSlots or numSlots == 0 then
        return false, 0
    end

    local freeSlots, bagFamily = GetContainerNumFreeSlots and GetContainerNumFreeSlots(bag)
    if not freeSlots then
        return false, 0
    end

    -- If bagFamily is non-zero, it is a specialty bag (e.g. soul bag, quiver, ammo, herb, mining, engineering)
    if bagFamily and bagFamily ~= 0 then
        return false, 0
    end

    -- Additional check: query the equipped container item itself
    local invID = (C_Container and C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag))
        or (_G.ContainerIDToInventoryID and _G.ContainerIDToInventoryID(bag))
    if invID then
        local bagLink = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", invID)
        if bagLink then
            local itemFamily = _G.GetItemFamily and _G.GetItemFamily(bagLink)
            if itemFamily and itemFamily ~= 0 then
                return false, 0
            end
            if _G.IsInventoryItemProfessionBag and _G.IsInventoryItemProfessionBag("player", invID) then
                return false, 0
            end
        end
    end

    return true, freeSlots
end
triage.IsRegularInventoryBag = is_regular_inventory_bag

--- Counts total free slots across regular inventory bags (strictly ignoring specialty containers)
--- @return number freeSlots
local function get_num_free_regular_slots()
    local free = 0
    local maxBag = _G.NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local isRegular, freeSlots = is_regular_inventory_bag(bag)
        if isRegular then
            free = free + (freeSlots or 0)
        end
    end
    return free
end
triage.GetNumFreeRegularSlots = get_num_free_regular_slots

--- Checks whether an item is protected from deletion (Hearthstone, tools, quest items)
--- @param itemID number
--- @param itemLink string|nil
--- @param info table|nil
--- @return boolean isProtected
local function is_item_protected(itemID, itemLink, info)
    if not itemID then return true end
    if PROTECTED_ITEM_IDS[itemID] then return true end
    if ignoredInSession[itemID] then return true end

    -- Check if quest item, quest starter, or locked container
    if info and info.isQuestItem then return true end
    if info and info.hasLoot then return true end

    if itemLink or itemID then
        local _, _, _, _, _, _, _, _, _, _, _, classID, _, bindType = common.get_item_info(itemLink or itemID)
        if bindType == 4 then return true end -- Quest item bind
        -- Class 1 = Container (bags inside bags)
        if classID == 1 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Container) then
            return true
        end
        -- Class 11 = Quiver / Ammo Pouch
        if classID == 11 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Quiver) then
            return true
        end
        -- Class 12 = Quest Item
        if classID == 12 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Questitem) then
            return true
        end
        -- Class 13 = Key
        if classID == 13 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Key) then
            return true
        end
        -- Class 18 = Profession equipment / curios
        if classID == 18 or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Profession) then
            return true
        end
    end

    return false
end

--- Collects and ranks discard candidates from regular bags 0 to 4 (ignoring specialty containers)
--- @return table candidates, string candidateType ("grey", "consumable", or "none")
local function find_candidates()
    local greyCandidates = {}
    local consumableCandidates = {}

    local cfg = sfui.config.triage or {}
    local checkConsumables = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "checkConsumables", cfg.checkConsumables ~= false))
    if checkConsumables == nil then checkConsumables = true end

    local protectFoodWater = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "protectFoodWater", cfg.protectFoodWater ~= false))
    if protectFoodWater == nil then protectFoodWater = true end

    local playerLevel = UnitLevel("player") or 1
    local maxBag = _G.NUM_BAG_SLOTS or 4

    for bag = 0, maxBag do
        local isRegular = is_regular_inventory_bag(bag)
        -- Only scan regular inventory containers (backpack bag 0 or normal bags)
        -- Discarding items from specialty bags (quiver, herb, mining, soul bag) does not free regular space
        if isRegular then
            local numSlots = GetContainerNumSlots and GetContainerNumSlots(bag) or 0
            for slot = 1, numSlots do
                local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
                local itemLink = GetContainerItemLink and GetContainerItemLink(bag, slot)

                if itemID and itemLink then
                    local rawInfo = GetContainerItemInfo and GetContainerItemInfo(bag, slot)
                    local info = (type(rawInfo) == "table") and rawInfo or nil
                    local isLocked = info and info.isLocked

                    if not isLocked and not is_item_protected(itemID, itemLink, info) then
                        local quality = info and info.quality
                        local stackCount = (info and info.stackCount) or 1
                        local icon = (info and info.iconFileID)

                        local name, _, itemQuality, _, itemMinLevel, _, _, _, _, itemTexture, itemSellPrice, classID, subClassID = common.get_item_info(itemLink)
                        quality = quality or itemQuality or 0
                        icon = icon or itemTexture

                        local sellPrice = (info and info.noValue) and 0 or (itemSellPrice or 0)
                        local totalValue = sellPrice * stackCount

                        -- Phase 1: Grey Quality Items (Quality 0)
                        if quality == 0 then
                            greyCandidates[#greyCandidates + 1] = {
                                bag = bag,
                                slot = slot,
                                itemID = itemID,
                                itemLink = itemLink,
                                itemName = name or "junk item",
                                icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                quality = 0,
                                stackCount = stackCount,
                                sellPrice = sellPrice,
                                totalValue = totalValue,
                                category = "grey junk",
                            }
                        -- Phase 2: Consumables (Common/White Quality 1) - ONLY Food & Drink (subclass 5)
                        -- Life-saving potions (1), elixirs (2), flasks (3), and bandages (7) are strictly protected
                        elseif checkConsumables and quality == 1 then
                            local isConsumableClass = (classID == 0) or (Enum and Enum.ItemClass and classID == Enum.ItemClass.Consumable)
                            local isFoodDrink = (subClassID == 5) or (Enum and Enum.ItemConsumableSubclass and subClassID == Enum.ItemConsumableSubclass.Fooddrink)
                            local isExcludedSubclass = (subClassID == 1 or subClassID == 2 or subClassID == 3 or subClassID == 4 or subClassID == 7)
                                or (Enum and Enum.ItemConsumableSubclass and (
                                    subClassID == Enum.ItemConsumableSubclass.Potion
                                    or subClassID == Enum.ItemConsumableSubclass.Elixir
                                    or subClassID == Enum.ItemConsumableSubclass.Flasksphials
                                    or subClassID == Enum.ItemConsumableSubclass.Bandage
                                ))

                            if isConsumableClass and isFoodDrink and not isExcludedSubclass then
                                local reqLevel = itemMinLevel or 0
                                local levelDiff = math_max(0, playerLevel - reqLevel)
                                local isOutdated = (playerLevel >= 15 and reqLevel <= 5)
                                    or (playerLevel >= 25 and reqLevel <= 15)
                                    or (playerLevel >= 35 and reqLevel <= 25)
                                    or (levelDiff >= 15)

                                local canSuggest = true
                                if protectFoodWater and not isOutdated and (reqLevel >= playerLevel - 10) then
                                    canSuggest = false
                                end

                                if canSuggest then
                                    consumableCandidates[#consumableCandidates + 1] = {
                                        bag = bag,
                                        slot = slot,
                                        itemID = itemID,
                                        itemLink = itemLink,
                                        itemName = name or "food/water",
                                        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                        quality = 1,
                                        stackCount = stackCount,
                                        sellPrice = sellPrice,
                                        totalValue = totalValue,
                                        reqLevel = reqLevel,
                                        isOutdated = isOutdated,
                                        category = isOutdated and "outdated food/drink" or "low-value food/drink",
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Return greys first if any exist (sorted by lowest total value, lowest unit price, then smallest stack)
    if #greyCandidates > 0 then
        table_sort(greyCandidates, function(a, b)
            if a.totalValue ~= b.totalValue then
                return a.totalValue < b.totalValue
            end
            if a.sellPrice ~= b.sellPrice then
                return a.sellPrice < b.sellPrice
            end
            if a.stackCount ~= b.stackCount then
                return a.stackCount < b.stackCount
            end
            if a.bag ~= b.bag then
                return a.bag > b.bag
            end
            return a.slot > b.slot
        end)
        return greyCandidates, "grey"
    end

    -- Fallback to consumables (outdated food/drink first, then lowest value/stack)
    if #consumableCandidates > 0 then
        table_sort(consumableCandidates, function(a, b)
            if a.isOutdated ~= b.isOutdated then
                return a.isOutdated
            end
            if a.totalValue ~= b.totalValue then
                return a.totalValue < b.totalValue
            end
            if a.sellPrice ~= b.sellPrice then
                return a.sellPrice < b.sellPrice
            end
            if a.stackCount ~= b.stackCount then
                return a.stackCount < b.stackCount
            end
            return a.slot > b.slot
        end)
        return consumableCandidates, "consumable"
    end

    return {}, "none"
end
triage.FindCandidates = find_candidates

-- ─────────────────────────────────────────────────────────────────────────────
--  Confirmation Prompt UI
-- ─────────────────────────────────────────────────────────────────────────────

local function refresh_triage_frame_levels(f)
    if not f then return end
    local base = f:GetFrameLevel() or 100
    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(f)
    end
    if f.headerFrame then f.headerFrame:SetFrameLevel(base + 15) end
    if f.contentFrame then f.contentFrame:SetFrameLevel(base + 10) end
    if f.iconFrame then f.iconFrame:SetFrameLevel(base + 12) end
    local actBtn = f.deleteBtn or f.dropBtn
    if actBtn then actBtn:SetFrameLevel(base + 15) end
    if f.nextBtn then f.nextBtn:SetFrameLevel(base + 15) end
    if f.keepBtn then f.keepBtn:SetFrameLevel(base + 15) end
    if f.closeBtn then f.closeBtn:SetFrameLevel(base + 20) end
end

local function apply_triage_theme(f, pal)
    if not f then return end
    pal = pal or (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    refresh_triage_frame_levels(f)

    if f.title and pal.headerColor then
        f.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
    end

    if f.slotText and pal.dimTextColor then
        f.slotText:SetTextColor(pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3], 1)
    end

    if f.iconFrame and sfui.theme and sfui.theme.ApplyCardStyle then
        sfui.theme.ApplyCardStyle(f.iconFrame, 2)
    end

    if sfui.theme and sfui.theme.ApplyButtonStyle then
        local actBtn = f.deleteBtn or f.dropBtn
        if actBtn then sfui.theme.ApplyButtonStyle(actBtn, false) end
        if f.nextBtn then sfui.theme.ApplyButtonStyle(f.nextBtn, false) end
        if f.keepBtn then sfui.theme.ApplyButtonStyle(f.keepBtn, false) end
    end

    if f.closeBtn and sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(f.closeBtn)
    end
end

local function create_triage_prompt()
    if promptFrame then return promptFrame end

    local f = CreateFrame("Frame", "SfuiBagTriagePrompt", UIParent, "BackdropTemplate")
    f:SetSize(280, 118)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Clean fallback backdrop with 1px border
    local pScale = sfui.pixelScale or 1
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = pScale,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Apply theme styling (Camelot sculpted bronze, NineSlice, or Modern flat)
    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(f, { cornerBrackets = true })
    end
    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(f, apply_triage_theme, { cornerBrackets = true })
    end
    f:HookScript("OnShow", refresh_triage_frame_levels)

    -- Drag repositioning
    f:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, relPt, x, y = self:GetPoint()
        if SfuiDB then
            SfuiDB.triagePos = { point = pt or "BOTTOM", relPoint = relPt or "BOTTOM", x = x or 0, y = y or 220 }
        end
    end)

    -- Position restoration
    local savedPos = SfuiDB and SfuiDB.triagePos
    if savedPos and savedPos.point and savedPos.x and savedPos.y then
        f:SetPoint(savedPos.point, UIParent, savedPos.relPoint or savedPos.point, savedPos.x, savedPos.y)
    else
        local defPos = (sfui.config.triage and sfui.config.triage.pos) or { point = "BOTTOM", x = 0, y = 220 }
        f:SetPoint(defPos.point, UIParent, defPos.relativePoint or defPos.point, defPos.x, defPos.y)
    end

    -- Elevated header frame & title
    local headerFrame = CreateFrame("Frame", nil, f)
    headerFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(26)
    headerFrame:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    headerFrame:EnableMouse(false)
    f.headerFrame = headerFrame

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local headerR, headerG, headerB = 1, 0.82, 0
    if pal.headerColor then
        headerR, headerG, headerB = pal.headerColor[1], pal.headerColor[2], pal.headerColor[3]
    end

    local title = headerFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetTextColor(headerR, headerG, headerB, 1)
    title:SetText("bag triage")
    f.title = title

    local statusText = headerFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", title, "RIGHT", 6, 0)
    statusText:SetTextColor(0.8, 0.8, 0.8, 1)
    f.statusText = statusText

    -- Close button [x]
    local closeBtn = common.create_close_button(f, function() f:Hide() end, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 20)
    f.closeBtn = closeBtn

    -- Content frame (elevated above theme background/border layers)
    local content = CreateFrame("Frame", nil, f)
    content:SetAllPoints(f)
    content:SetFrameLevel((f:GetFrameLevel() or 100) + 10)
    content:EnableMouse(false)
    f.contentFrame = content

    -- Item icon container
    local iconFrame = CreateFrame("Button", nil, content, "BackdropTemplate")
    iconFrame:SetSize(36, 36)
    iconFrame:SetPoint("TOPLEFT", 10, -28)
    iconFrame:SetFrameLevel((f:GetFrameLevel() or 100) + 12)
    if sfui.theme and sfui.theme.ApplyCardStyle then
        sfui.theme.ApplyCardStyle(iconFrame, 2)
    else
        iconFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        iconFrame:SetBackdropColor(0.04, 0.04, 0.04, 1)
        iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f.iconFrame = iconFrame

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 2, -2)
    iconTex:SetPoint("BOTTOMRIGHT", -2, 2)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconTex = iconTex

    local countText = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
    countText:SetTextColor(1, 1, 1, 1)
    f.countText = countText

    -- Tooltip on icon hover
    iconFrame:SetScript("OnEnter", function(self)
        local tip = sfui.tooltip or _G.SfuiGameTooltip
        if not tip or not currentCandidate then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        if currentCandidate.bag and currentCandidate.slot and not isTestMode then
            tip:SetBagItem(currentCandidate.bag, currentCandidate.slot)
        else
            tip:SetHyperlink(currentCandidate.itemLink or "item:4865")
        end
        tip:Show()
    end)
    iconFrame:SetScript("OnLeave", function()
        local tip = sfui.tooltip or _G.SfuiGameTooltip
        if tip and tip:IsShown() then
            tip:Hide()
        end
    end)

    -- Item details labels
    local nameText = content:CreateFontString(nil, "OVERLAY", sfui.config.font or "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 8, 0)
    nameText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    nameText:SetJustifyH("LEFT")
    f.nameText = nameText

    local infoText = content:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -3)
    infoText:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetTextColor(0.7, 0.7, 0.7, 1)
    f.infoText = infoText

    local dimR, dimG, dimB = 0.5, 0.5, 0.5
    if pal.dimTextColor then
        dimR, dimG, dimB = pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3]
    end

    local slotText = content:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    slotText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -2)
    slotText:SetJustifyH("LEFT")
    slotText:SetTextColor(dimR, dimG, dimB, 1)
    f.slotText = slotText

    -- ── Action Buttons ──
    local CreateFlatButton = common.create_flat_button

    -- [delete] action button (instant deletion on click)
    local deleteBtn = CreateFlatButton(f, "delete", 68, 20)
    deleteBtn:SetPoint("BOTTOMLEFT", 10, 8)
    deleteBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    deleteBtn:SetScript("OnClick", function()
        local cand = currentCandidate
        if not cand then
            f:Hide()
            return
        end

        if isTestMode then
            common.print(string_format("|cff00ffffsfui triage:|r [test preview] deleted %s simulated.", cand.itemLink or cand.itemName))
            f:Hide()
            isTestMode = false
            return
        end

        -- Race condition guard: verify slot still holds the exact candidate item
        local curID = GetContainerItemID and GetContainerItemID(cand.bag, cand.slot)
        local curLink = GetContainerItemLink and GetContainerItemLink(cand.bag, cand.slot)
        if curID ~= cand.itemID or (curLink and cand.itemLink and curLink ~= cand.itemLink) then
            common.print("|cffff8800sfui triage:|r item moved or changed, cancel delete.")
            f:Hide()
            triage.EvaluateTriage()
            return
        end

        -- Verify item is not locked by bag operations or server activity
        local rawInfo = GetContainerItemInfo and GetContainerItemInfo(cand.bag, cand.slot)
        local info = (type(rawInfo) == "table") and rawInfo or nil
        if info and info.isLocked then
            common.print("|cffff8800sfui triage:|r item is currently locked, try again in a moment.")
            return
        end

        -- Clear cursor before picking up
        if CursorHasItem and CursorHasItem() then
            ClearCursor()
        end

        if PickupContainerItem then
            PickupContainerItem(cand.bag, cand.slot)
        end

        if DeleteCursorItem then
            DeleteCursorItem()
        end

        -- Cursor safety cleanup: if native popup is not shown and item is still on cursor, clear it
        if CursorHasItem and CursorHasItem() then
            C_Timer.After(0.2, function()
                if CursorHasItem and CursorHasItem() then
                    local popupVisible = (_G.StaticPopup_Visible and (_G.StaticPopup_Visible("DELETE_ITEM") or _G.StaticPopup_Visible("DELETE_GOOD_ITEM")))
                    if not popupVisible then
                        ClearCursor()
                    end
                end
            end)
        end

        local coinStr = (cand.totalValue and cand.totalValue > 0)
            and common.SafeGetCoinTextureString(cand.totalValue)
            or "0c"
        common.print(string_format("|cff00ffffsfui triage:|r deleted %s%s (%s).",
            cand.itemLink or cand.itemName,
            (cand.stackCount and cand.stackCount > 1) and (" x" .. cand.stackCount) or "",
            coinStr
        ))

        if PlaySound then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        end

        f:Hide()

        -- Re-evaluate after 0.4s once bag updates settle
        C_Timer.After(0.4, function()
            triage.EvaluateTriage()
        end)
    end)
    f.deleteBtn = deleteBtn
    f.dropBtn = deleteBtn -- alias for theme engine and backwards compatibility

    -- [next candidate] button
    local nextBtn = CreateFlatButton(f, "next", 64, 20)
    nextBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 6, 0)
    nextBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    nextBtn:SetScript("OnClick", function()
        if #currentCandidates <= 1 then return end
        currentCandidateIndex = (currentCandidateIndex % #currentCandidates) + 1
        triage.DisplayCandidate(currentCandidates[currentCandidateIndex])
    end)
    f.nextBtn = nextBtn

    -- [keep] button
    local keepBtn = CreateFlatButton(f, "keep", 64, 20)
    keepBtn:SetPoint("LEFT", nextBtn, "RIGHT", 6, 0)
    keepBtn:SetFrameLevel((f:GetFrameLevel() or 100) + 15)
    keepBtn:SetScript("OnClick", function()
        if currentCandidate and currentCandidate.itemID then
            ignoredInSession[currentCandidate.itemID] = true
            common.print(string_format("|cffaaaaaasfui triage:|r keeping %s for this session.", currentCandidate.itemLink or currentCandidate.itemName))
        end
        f:Hide()
    end)
    f.keepBtn = keepBtn

    f:Hide()
    promptFrame = f
    return f
end

--- Updates prompt contents with a candidate's information
--- @param cand table
function triage.DisplayCandidate(cand)
    if not cand then return end
    currentCandidate = cand

    local f = create_triage_prompt()
    local free = get_num_free_regular_slots()

    if isTestMode then
        f.statusText:SetText("|cff00ffff[test preview]|r")
    elseif free == 0 then
        f.statusText:SetText("|cffff4444bags full (0 free)|r")
    else
        f.statusText:SetText(string_format("|cffffcc00bags almost full (%d free)|r", free))
    end

    f.iconTex:SetTexture(cand.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if cand.stackCount and cand.stackCount > 1 then
        f.countText:SetText(tostring(cand.stackCount))
        f.countText:Show()
    else
        f.countText:SetText("")
        f.countText:Hide()
    end

    f.nameText:SetText(cand.itemLink or cand.itemName)

    local valStr = (cand.totalValue and cand.totalValue > 0)
        and common.SafeGetCoinTextureString(cand.totalValue)
        or "0c (no sell value)"
    f.infoText:SetText(string_format("value: %s |cff888888(%s)|r", valStr, cand.category or "junk"))

    if cand.bag and cand.slot then
        f.slotText:SetText(string_format("location: bag %d, slot %d", cand.bag + 1, cand.slot))
    else
        f.slotText:SetText("")
    end

    if #currentCandidates > 1 then
        f.nextBtn:SetText(string_format("next (%d/%d)", currentCandidateIndex, #currentCandidates))
        f.nextBtn:Enable()
        f.nextBtn:SetAlpha(1.0)
    else
        f.nextBtn:SetText("next")
        f.nextBtn:Disable()
        f.nextBtn:SetAlpha(0.4)
    end

    f:Show()

    local cfg = sfui.config.triage or {}
    local soundAlert = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "soundAlert", cfg.soundAlert ~= false))
    if soundAlert ~= false and PlaySound and not isTestMode then
        PlaySound(SOUNDKIT.RAID_WARNING or 8959)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Triage Evaluation Loop
-- ─────────────────────────────────────────────────────────────────────────────

--- Evaluates bag space and displays the triage prompt if free slots <= threshold
function triage.EvaluateTriage()
    if not isEnabled then return end
    if isTestMode then return end

    -- Safety: never prompt during combat
    if sfui.common.is_in_combat() or InCombatLockdown() then
        return
    end

    -- Safety: player dead/ghost
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    -- Safety: at merchant window (selling items is preferred over dropping)
    if _G.MerchantFrame and _G.MerchantFrame:IsShown() then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    local cfg = sfui.config.triage or {}
    local defThresh = (cfg.threshold ~= nil) and cfg.threshold or 1
    local threshold = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "threshold", defThresh))
    if threshold == nil then threshold = defThresh end
    threshold = tonumber(threshold) or 1
    local free = get_num_free_regular_slots()
    lastFreeSlots = free

    -- Bags have enough free space: hide any active prompt
    if free > threshold then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    local candidates, cType = find_candidates()
    if #candidates == 0 then
        if promptFrame and promptFrame:IsShown() then
            promptFrame:Hide()
        end
        return
    end

    currentCandidates = candidates
    currentCandidateIndex = 1
    triage.DisplayCandidate(candidates[1])
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Test Preview & Positioning Helper
-- ─────────────────────────────────────────────────────────────────────────────

function triage.ToggleTestMode()
    local f = create_triage_prompt()
    if isTestMode and f:IsShown() then
        f:Hide()
        isTestMode = false
        return false
    end

    isTestMode = true
    currentCandidates = {
        {
            itemID = 4865,
            itemLink = "|cff9d9d9d|Hitem:4865::::::::1:1447::1::::|h[Broken Boar Tusk]|h|r",
            itemName = "Broken Boar Tusk",
            icon = 134075,
            quality = 0,
            stackCount = 4,
            sellPrice = 1,
            totalValue = 4,
            category = "grey junk",
            bag = 1,
            slot = 3,
        },
        {
            itemID = 4536,
            itemLink = "|cffffffff|Hitem:4536::::::::1:1447::1::::|h[Shiny Red Apple]|h|r",
            itemName = "Shiny Red Apple",
            icon = 133984,
            quality = 1,
            stackCount = 5,
            sellPrice = 2,
            totalValue = 10,
            category = "outdated food/drink",
            bag = 2,
            slot = 1,
        },
    }
    currentCandidateIndex = 1
    triage.DisplayCandidate(currentCandidates[1])
    return true
end

function triage.IsTestMode()
    return isTestMode and promptFrame and promptFrame:IsShown()
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Event Listeners & Dispatcher Wiring
-- ─────────────────────────────────────────────────────────────────────────────

local function on_bag_update()
    if not isEnabled then return end
    if scanTimer then return end
    scanTimer = C_Timer.After(0.3, function()
        scanTimer = nil
        triage.EvaluateTriage()
    end)
end

local function on_ui_error(event, errorType, msg)
    if not isEnabled then return end
    -- Immediately evaluate if inventory full error fires
    if msg == _G.ERR_INV_FULL or (msg and msg:find("Inventory is full", 1, true)) then
        triage.EvaluateTriage()
    end
end

local function on_combat_leave()
    if not isEnabled then return end
    -- Check if bags filled while fighting
    C_Timer.After(0.4, function()
        triage.EvaluateTriage()
    end)
end

local function on_combat_enter()
    -- Always hide prompt in combat to avoid obstruction
    if promptFrame and promptFrame:IsShown() and not isTestMode then
        promptFrame:Hide()
    end
end

local function on_merchant_show()
    -- Always hide prompt at merchant (sell greys at vendor instead)
    if promptFrame and promptFrame:IsShown() and not isTestMode then
        promptFrame:Hide()
    end
end

function triage.Enable()
    isEnabled = true
    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", on_bag_update)
        sfui.events.RegisterEvent("UI_ERROR_MESSAGE", on_ui_error)
        sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", on_combat_leave)
        sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", on_combat_enter)
        sfui.events.RegisterEvent("MERCHANT_SHOW", on_merchant_show)
        sfui.events.RegisterEvent("LOOT_OPENED", on_bag_update)
    end
    triage.EvaluateTriage()
end

function triage.Disable()
    isEnabled = false
    if promptFrame and promptFrame:IsShown() then
        promptFrame:Hide()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SFUI Module Protocol Registration
-- ─────────────────────────────────────────────────────────────────────────────

local _debugInfo = {}
function triage.GetDebugInfo()
    _debugInfo.enabled = isEnabled
    _debugInfo.freeRegularSlots = lastFreeSlots
    _debugInfo.candidateCount = #currentCandidates
    _debugInfo.isPromptShown = promptFrame and promptFrame:IsShown() or false
    return _debugInfo
end

local TriageModule = sfui.RegisterModule("triage", {
    OnInit = function(self)
        if sfui.db and sfui.db.RegisterDefaults and sfui.config and sfui.config.triage then
            sfui.db.RegisterDefaults("triage", sfui.config.triage)
        end
    end,

    OnEnable = function(self)
        local enabled = (sfui.db and sfui.db.Get and sfui.db.Get("triage", "enabled", true))
        if enabled == nil then enabled = true end
        if enabled then
            triage.Enable()
        else
            triage.Disable()
        end
    end,

    OnDisable = function(self)
        triage.Disable()
    end,

    OnSettingsChanged = function(self, key, value)
        if key == "enabled" then
            if value then
                triage.Enable()
            else
                triage.Disable()
            end
        elseif key == "threshold" or key == "checkConsumables" or key == "protectFoodWater" then
            triage.EvaluateTriage()
        end
    end,

    GetDebugInfo = function(self)
        return triage.GetDebugInfo()
    end,
})

sfui.triage.module = TriageModule
