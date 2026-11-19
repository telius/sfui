local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
local GameTooltip = sfui.common.get_tooltip() -- private addon tooltip (methods.md §3.7.2)
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_bosses.lua
--  Boss selection list + loot scroll panel for the Camelot Dungeon Journal.
--  Uses frame pooling for boss list buttons and loot row items.
--  Resolves items lazily via sfui.common.get_item_info() and handles
--  ITEM_DATA_LOAD_RESULT with debounced UI refreshes.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

-- ─── Constants ────────────────────────────────────────────────────────────────
local BOSS_BTN_H           = 42
local BOSS_BTN_PAD         = 4
local LOOT_ROW_H           = 44
local LOOT_ROW_PAD         = 4
local LOOT_ROW_STRIDE      = LOOT_ROW_H + LOOT_ROW_PAD
local ICON_SZ              = 34
local BOSS_LIST_W          = 200

local theme                = sfui.theme
local common               = sfui.common

-- ─── Locals & State ───────────────────────────────────────────────────────────
local bossPanel            = nil
local bossListScroll       = nil
local bossListContent      = nil
local lootScroll           = nil
local lootContent          = nil
local bossHeaderFrame      = nil

local bossButtons          = {}
local lootButtons          = {}

local selectedBossIndex    = 1
local currentBossItemSet   = {}
local currentLootFilter    = "all"
local usableFilterSpecMode = "spec" -- "spec" = active spec, "all" = all class specs
local categoryUsableOnly   = {}     -- e.g. categoryUsableOnly["armor"] = true
local filterButtons        = {}
local UpdateFilterPills    = nil
local ApplyPillStyle       = nil

local filteredLootRows     = {}
local filteredLootCount    = 0
local renderedLootBoss     = nil
local renderedLootDungeon  = nil
local lastLootFirstIdx     = 0
local lastLootLastIdx      = 0
local lastLootScrollY      = 0

local FILTER_BUTTONS       = {
    { key = "all",      label = "all" },
    { key = "usable",   label = "usable" },
    { key = "armor",    label = "armor" },
    { key = "weapons",  label = "weapons" },
    { key = "trinkets", label = "trinkets" },
    { key = "other",    label = "other" },
    { key = "wishlist", label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t wishlist" },
}

-- ─── Spec & Usability Evaluation (rules.lua / stats.lua) ─────────────────────
local function GetPlayerSpecsForFilter()
    local playerSpecs, playerSpecIDs = common.get_player_specs()
    if playerSpecIDs and #playerSpecIDs > 0 then
        return playerSpecs, playerSpecIDs
    end

    local englishClass = sfui.common.get_player_class()
    local specIDs = {}
    local specMap = {}
    if sfui.data and sfui.data.SPEC_DEFINITIONS then
        for _, def in ipairs(sfui.data.SPEC_DEFINITIONS) do
            if def.class == englishClass or def.classFile == englishClass then
                local sID = def.camelotID or def.retailID
                if sID then
                    specIDs[#specIDs + 1] = sID
                    specMap[sID] = def
                end
            end
        end
    end
    return specMap, specIDs
end

local function GetPlayerActiveSpecID()
    local sID = common.get_current_spec_id and common.get_current_spec_id()
    if sID and sID > 0 then
        return sID
    end
    local _, specIDs = GetPlayerSpecsForFilter()
    return specIDs and specIDs[1]
end

local function GetSpecDisplayName(specID)
    if not specID or specID == 0 then return "" end
    local bridge = sfui.talents and sfui.talents.SPEC_BRIDGE and sfui.talents.SPEC_BRIDGE[specID]
    if bridge and bridge.name then
        return tostring(bridge.name):lower()
    end
    local infoName = sfui.common.get_spec_name and sfui.common.get_spec_name(specID)
    if infoName and infoName ~= "" then
        return tostring(infoName):lower()
    end
    return ""
end

local function GetItemClassScanTooltip()
    return common.get_scan_tooltip()
end

local itemClassUsableCache = {}
local cachedLocClassLower  = nil
local cachedClassPattern   = nil
local cachedClassPrefix    = nil
local classInfoCached      = false

local function EnsureClassMatchLocals()
    if classInfoCached and cachedLocClassLower ~= "" then return end
    local locClass = UnitClass and UnitClass("player")
    cachedLocClassLower = locClass and locClass:lower() or ""
    if not classInfoCached then
        cachedClassPattern = _G.ITEM_CLASSES_ALLOWED and _G.ITEM_CLASSES_ALLOWED:gsub("%%s", ".*") or nil
        local rawPrefix = _G.ITEM_CLASSES_ALLOWED and _G.ITEM_CLASSES_ALLOWED:match("^([^:%%]+)")
        cachedClassPrefix = rawPrefix and rawPrefix:trim():lower() or "classes"
        classInfoCached = true
    end
end

local function ItemMatchesPlayerClass(itemID, itemLink)
    if not itemID or itemID <= 0 then return true end
    if itemClassUsableCache[itemID] ~= nil then
        return itemClassUsableCache[itemID]
    end

    local link = itemLink or ("item:" .. itemID)

    -- 1. Check C_Item.GetItemSpecInfo if available
    local specList = common.get_item_spec_info and (common.get_item_spec_info(link) or common.get_item_spec_info(itemID))
    if specList and #specList > 0 then
        local playerSpecs = common.get_player_specs()
        if playerSpecs then
            local foundMySpec = false
            for _, sID in ipairs(specList) do
                if playerSpecs[sID] then
                    foundMySpec = true
                    break
                end
            end
            if not foundMySpec then
                itemClassUsableCache[itemID] = false
                return false
            end
        end
    end

    -- 2. Tooltip inspection for class restrictions (e.g. "Classes: Paladin, Priest")
    EnsureClassMatchLocals()
    local locClassLower = cachedLocClassLower
    local classPattern = cachedClassPattern
    local classPrefix = cachedClassPrefix

    local foundRestriction = nil
    local dataReady = false

    -- Method A: C_TooltipInfo
    if C_TooltipInfo then
        local tData = (link and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link))
            or (C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(itemID))
        if tData and tData.lines and #tData.lines > 1 then
            dataReady = true
            if TooltipUtil and TooltipUtil.SurfaceArgs then
                TooltipUtil.SurfaceArgs(tData)
            end
            for _, line in ipairs(tData.lines) do
                local lineType = line.type
                local isRestrictedClassType = (lineType and Enum and Enum.TooltipDataLineType and lineType == Enum.TooltipDataLineType.RestrictedRaceClass)
                local txt = line.leftText
                local txtLower = (txt and type(txt) == "string") and txt:lower() or ""

                local isClassLine = isRestrictedClassType
                    or (classPattern and txt and txt:match(classPattern))
                    or (classPrefix and txtLower ~= "" and txtLower:find(classPrefix, 1, true))
                    or (txtLower ~= "" and (txtLower:find("classes:", 1, true) or txtLower:find("klassen:", 1, true)))

                if isClassLine then
                    local isRed = false
                    local clr = line.leftColor
                    if clr and clr.r and clr.g and clr.b then
                        if clr.r > 0.85 and clr.g < 0.25 and clr.b < 0.25 then
                            isRed = true
                        end
                    end
                    local matchesMyClass = locClassLower ~= "" and txtLower ~= "" and
                        txtLower:find(locClassLower, 1, true)
                    if isRed or (txtLower ~= "" and not matchesMyClass) then
                        foundRestriction = false
                        break
                    else
                        foundRestriction = true
                    end
                end
            end
        end
    end

    -- Method B: Fallback hidden GameTooltip only when C_TooltipInfo was unavailable or incomplete
    if not dataReady and foundRestriction == nil then
        local tip, tipName = GetItemClassScanTooltip()
        if tip then
            tip:SetHyperlink(link)
            local numLines = tip:NumLines() or 0
            if numLines and numLines > 1 then
                dataReady = true
                for i = 1, numLines do
                    local fs = _G[tipName .. "TextLeft" .. i]
                    if fs then
                        local txt = fs:GetText()
                        local txtLower = (txt and type(txt) == "string") and txt:lower() or ""
                        local isClassLine = (classPattern and txt and txt:match(classPattern))
                            or (classPrefix and txtLower ~= "" and txtLower:find(classPrefix, 1, true))
                            or (txtLower ~= "" and (txtLower:find("classes:", 1, true) or txtLower:find("klassen:", 1, true)))

                        if isClassLine then
                            local r, g, b = fs:GetTextColor()
                            local isRed = (r and g and b and r > 0.85 and g < 0.25 and b < 0.25)
                            local matchesMyClass = locClassLower ~= "" and txtLower ~= "" and
                                txtLower:find(locClassLower, 1, true)

                            if isRed or (txtLower ~= "" and not matchesMyClass) then
                                foundRestriction = false
                                break
                            else
                                foundRestriction = true
                            end
                        end
                    end
                end
            end
            tip:Hide()
        end
    end

    if foundRestriction == false then
        itemClassUsableCache[itemID] = false
        return false
    elseif foundRestriction == true then
        itemClassUsableCache[itemID] = true
        return true
    end

    if dataReady or (C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemID)) then
        itemClassUsableCache[itemID] = true
        return true
    end

    if common and common.request_item_load then
        common.request_item_load(itemID)
    end
    return true
end

local function IsItemUsableGear(itemLink, targetSpecID)
    if not itemLink then return false end
    if not sfui.highest or not sfui.highest.IsItemValidForSpec then
        return true
    end

    if targetSpecID and targetSpecID > 0 then
        return sfui.highest.IsItemValidForSpec(itemLink, targetSpecID, true, false)
    end

    local _, specIDs = GetPlayerSpecsForFilter()
    if specIDs and #specIDs > 0 then
        for _, sID in ipairs(specIDs) do
            if sfui.highest.IsItemValidForSpec(itemLink, sID, true, false) then
                return true
            end
        end
        return false
    end

    local curSpec = GetPlayerActiveSpecID()
    if curSpec and curSpec > 0 then
        return sfui.highest.IsItemValidForSpec(itemLink, curSpec, true, false)
    end

    return false
end

local function IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
    if not itemID or itemID <= 0 then return true end
    local link = itemLink or ("item:" .. itemID)

    -- 1. Must match player's class (if class restricted)
    if not ItemMatchesPlayerClass(itemID, link) then
        return false
    end

    -- 2. Check equippable gear against spec rules & stats
    local isEquippable = (classID == 2 or classID == 4)
        or (equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_NON_EQUIP_IGNORE")

    local isToken = (classID == 5 and subclassID == 2)
        or (not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_NON_EQUIP_IGNORE")

    if isEquippable and not isToken then
        return IsItemUsableGear(link, targetSpecID)
    end

    -- 3. Non-equippable items (tokens, recipes, bags, consumables, misc)
    return true
end

local function IsItemMatchingFilter(filterKey, itemID, classID, subclassID, equipSlot, itemLink)
    if filterKey == "all" then
        return true
    elseif filterKey == "wishlist" then
        local dj = sfui.dungeonjournal
        return dj and dj.IsWishlisted and dj.IsWishlisted(itemID)
    elseif filterKey == "usable" then
        local targetSpecID = (usableFilterSpecMode == "spec") and GetPlayerActiveSpecID() or nil
        return IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
    elseif filterKey == "armor" then
        local isArmor = (classID == 4 and equipSlot ~= "INVTYPE_TRINKET" and equipSlot ~= "INVTYPE_FINGER" and equipSlot ~= "INVTYPE_NECK" and equipSlot ~= "INVTYPE_HOLDABLE")
            or equipSlot == "INVTYPE_HEAD"
            or equipSlot == "INVTYPE_SHOULDER"
            or equipSlot == "INVTYPE_CHEST"
            or equipSlot == "INVTYPE_ROBE"
            or equipSlot == "INVTYPE_WAIST"
            or equipSlot == "INVTYPE_LEGS"
            or equipSlot == "INVTYPE_FEET"
            or equipSlot == "INVTYPE_WRIST"
            or equipSlot == "INVTYPE_HAND"
            or equipSlot == "INVTYPE_CLOAK"
            or equipSlot == "INVTYPE_SHIELD"
        if not isArmor then return false end
        if categoryUsableOnly["armor"] then
            local targetSpecID = (usableFilterSpecMode == "spec") and GetPlayerActiveSpecID() or nil
            return IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
        end
        return true
    elseif filterKey == "weapons" then
        local isWeapon = (classID == 2)
            or equipSlot == "INVTYPE_WEAPON"
            or equipSlot == "INVTYPE_2HWEAPON"
            or equipSlot == "INVTYPE_WEAPONMAINHAND"
            or equipSlot == "INVTYPE_WEAPONOFFHAND"
            or equipSlot == "INVTYPE_RANGED"
            or equipSlot == "INVTYPE_RANGEDRIGHT"
            or equipSlot == "INVTYPE_THROWN"
        if not isWeapon then return false end
        if categoryUsableOnly["weapons"] then
            local targetSpecID = (usableFilterSpecMode == "spec") and GetPlayerActiveSpecID() or nil
            return IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
        end
        return true
    elseif filterKey == "trinkets" then
        local isTrinket = equipSlot == "INVTYPE_TRINKET"
            or equipSlot == "INVTYPE_FINGER"
            or equipSlot == "INVTYPE_NECK"
            or equipSlot == "INVTYPE_HOLDABLE"
        if not isTrinket then return false end
        if categoryUsableOnly["trinkets"] then
            local targetSpecID = (usableFilterSpecMode == "spec") and GetPlayerActiveSpecID() or nil
            return IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
        end
        return true
    elseif filterKey == "other" then
        local isArmor = (classID == 4 and equipSlot ~= "INVTYPE_TRINKET" and equipSlot ~= "INVTYPE_FINGER" and equipSlot ~= "INVTYPE_NECK" and equipSlot ~= "INVTYPE_HOLDABLE")
            or equipSlot == "INVTYPE_HEAD"
            or equipSlot == "INVTYPE_SHOULDER"
            or equipSlot == "INVTYPE_CHEST"
            or equipSlot == "INVTYPE_ROBE"
            or equipSlot == "INVTYPE_WAIST"
            or equipSlot == "INVTYPE_LEGS"
            or equipSlot == "INVTYPE_FEET"
            or equipSlot == "INVTYPE_WRIST"
            or equipSlot == "INVTYPE_HAND"
            or equipSlot == "INVTYPE_CLOAK"
            or equipSlot == "INVTYPE_SHIELD"
        local isWeapon = (classID == 2)
            or equipSlot == "INVTYPE_WEAPON"
            or equipSlot == "INVTYPE_2HWEAPON"
            or equipSlot == "INVTYPE_WEAPONMAINHAND"
            or equipSlot == "INVTYPE_WEAPONOFFHAND"
            or equipSlot == "INVTYPE_RANGED"
            or equipSlot == "INVTYPE_RANGEDRIGHT"
            or equipSlot == "INVTYPE_THROWN"
        local isTrinket = equipSlot == "INVTYPE_TRINKET"
            or equipSlot == "INVTYPE_FINGER"
            or equipSlot == "INVTYPE_NECK"
            or equipSlot == "INVTYPE_HOLDABLE"
        local isOther = not isArmor and not isWeapon and not isTrinket
        if not isOther then return false end
        if categoryUsableOnly["other"] then
            local targetSpecID = (usableFilterSpecMode == "spec") and GetPlayerActiveSpecID() or nil
            return IsItemUsableByPlayer(itemID, classID, subclassID, equipSlot, itemLink, targetSpecID)
        end
        return true
    end
    return true
end

-- ─── Database & State Access ──────────────────────────────────────────────────
local dj                = sfui.dungeonjournal
local DJ_DB             = dj.GetDB
local GetCurrentDungeon = dj.GetCurrentDungeon

local function GetEncounterList(dungeon)
    if not dungeon then return {} end
    if dungeon._encounters then return dungeon._encounters end
    local bosses = dungeon.bosses or {}
    if #bosses == 0 then return {} end

    -- Build All Bosses combined entry
    local allItems = {}
    local seenItems = {}
    local allDropRates = {}
    for _, b in ipairs(bosses) do
        for _, it in ipairs(b.items or {}) do
            local id = type(it) == "table" and (it.id or it[1]) or it
            id = tonumber(id)
            if id and not seenItems[id] then
                seenItems[id] = true
                allItems[#allItems + 1] = it
            end
            if id and b.dropRates and b.dropRates[id] and not allDropRates[id] then
                allDropRates[id] = b.dropRates[id]
            end
        end
    end

    local list = {}
    list[1] = {
        isAll     = true,
        name      = "all bosses",
        level     = "all",
        subtitle  = string.format("%d encounters · %d drops", #bosses, #allItems),
        icon      = dungeon.icon or 133743,
        items     = allItems,
        dropRates = allDropRates,
    }

    for _, b in ipairs(bosses) do
        list[#list + 1] = b
    end

    dungeon._encounters = list
    return list
end

-- ─── Quality Color Helper ─────────────────────────────────────────────────────
local GetQualityColor = dj.GetQualityColor

-- ─── Wishlist Detection Helpers ───────────────────────────────────────────────
local function GetBossWishlistInfo(boss)
    if not boss or boss.isAll or not boss.items then return false, 0, nil end
    local isWishlisted = sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted
    if not isWishlisted then return false, 0, nil end
    local count = 0
    local names = nil
    for _, it in ipairs(boss.items) do
        local id = type(it) == "table" and (it.id or it[1]) or it
        id = tonumber(id)
        if id and isWishlisted(id) then
            count = count + 1
            if not names then names = {} end
            local name, link = common.get_item_info(id)
            if not name then
                local instName = (_G.C_Item and _G.C_Item.GetItemNameByID and _G.C_Item.GetItemNameByID(id))
                name = instName or ("item #" .. id)
            end
            names[#names + 1] = link or name or ("item #" .. id)
        end
    end
    return count > 0, count, names
end

local function UpdateBossButtonWishlist(btn)
    if not btn or not btn:IsShown() or not btn.bossData then return end
    local hasWish, count, itemNames = GetBossWishlistInfo(btn.bossData)
    btn.hasWishlist                 = hasWish
    btn.wishItemCount               = count
    btn.wishItemNames               = itemNames
    if btn.wishIcon then
        if hasWish then
            btn.wishIcon:Show()
            btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -26, -4)
            btn.levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -26, 5)
        else
            btn.wishIcon:Hide()
            btn.nameText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -4)
            btn.levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 5)
        end
    end
end

UpdateAllBossButtonsWishlistState = function()
    if not bossButtons then return end
    for _, btn in ipairs(bossButtons) do
        UpdateBossButtonWishlist(btn)
    end
end

local function CompareSortedItems(a, b)
    if a.rate ~= b.rate then
        return a.rate > b.rate
    end
    return a.index < b.index
end

local RenderLoot

local function ApplyBossButtonSelectedStyle(btn, isSelected, accent)
    if not btn then return end
    btn.isSelected = isSelected
    if isSelected then
        btn.nameText:SetTextColor(accent[1], accent[2], accent[3], 1)
        btn:SetBackdropColor(0.14, 0.14, 0.18, 0.95)
        btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
        if btn.icoFrame then
            btn.icoFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.85)
        end
    else
        btn.nameText:SetTextColor(0.85, 0.85, 0.85, 1)
        btn:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
        btn:SetBackdropBorderColor(0, 0, 0, 0)
        if btn.icoFrame then
            btn.icoFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
        end
    end
end

local function OnBossBtnClick(self)
    local newIdx = self.bossIndex
    if not newIdx then return end
    local prevIdx = selectedBossIndex
    selectedBossIndex = newIdx
    DJ_DB().lastBoss = newIdx
    if prevIdx ~= newIdx then
        local pal = theme.GetPalette()
        local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
        if prevIdx and bossButtons[prevIdx] then
            ApplyBossButtonSelectedStyle(bossButtons[prevIdx], false, accent)
        end
        ApplyBossButtonSelectedStyle(self, true, accent)
    end
    local dungeon = GetCurrentDungeon()
    local encounters = GetEncounterList(dungeon)
    local currentBoss = encounters[newIdx]
    if RenderLoot then
        RenderLoot(currentBoss, dungeon)
    end
end

local function OnBossBtnEnter(self)
    if self.hasWishlist and self.wishItemCount and self.wishItemCount > 0 then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.bossName or "boss encounter", 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            string.format(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffwishlist drop%s (%d)|r",
                (self.wishItemCount > 1 and "s" or ""), self.wishItemCount), 1, 1, 1)
        if self.wishItemNames then
            for _, itemName in ipairs(self.wishItemNames) do
                GameTooltip:AddLine("  • " .. itemName, 0.85, 0.85, 0.85)
            end
        end
        GameTooltip:AddLine("click to view encounter loot.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end
end

local function OnBossBtnLeave()
    GameTooltip:Hide()
end

-- ─── Boss Button Pool ─────────────────────────────────────────────────────────
local function AcquireBossButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then
            if btn.wishIcon then btn.wishIcon:Hide() end
            btn.hasWishlist   = nil
            btn.wishItemCount = nil
            btn.wishItemNames = nil
            return btn
        end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BOSS_BTN_H)
    common.apply_flat_backdrop(btn, { 0.08, 0.08, 0.10, 0.0 }, { 0, 0, 0, 0 })

    -- Icon (creature portrait or skull in 1px bordered frame)
    local icoFrame = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.icoFrame = icoFrame
    icoFrame:SetSize(30, 30)
    icoFrame:SetPoint("LEFT", 6, 0)
    common.apply_flat_backdrop(icoFrame, { 0.05, 0.05, 0.07, 0.9 }, { 0.20, 0.20, 0.25, 0.6 })

    local ico = icoFrame:CreateTexture(nil, "ARTWORK")
    btn.icon = ico
    ico:SetAllPoints()
    ico:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

    -- Wishlist gem icon on the right side of the boss button
    local wishIcon = btn:CreateTexture(nil, "OVERLAY")
    btn.wishIcon = wishIcon
    wishIcon:SetSize(16, 16)
    wishIcon:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    wishIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    wishIcon:Hide()

    -- Name
    local name = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText = name
    name:SetPoint("TOPLEFT", icoFrame, "TOPRIGHT", 8, -4)
    name:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -6, -4)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)

    -- Level badge / subtitle
    local levelText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.levelText = levelText
    levelText:SetPoint("BOTTOMLEFT", icoFrame, "BOTTOMRIGHT", 8, 5)
    levelText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 5)
    levelText:SetJustifyH("LEFT")
    levelText:SetWordWrap(false)
    levelText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.25)

    btn:SetScript("OnClick", OnBossBtnClick)
    btn:SetScript("OnEnter", OnBossBtnEnter)
    btn:SetScript("OnLeave", OnBossBtnLeave)

    pool[#pool + 1] = btn
    return btn
end

-- ─── Loot Button Pool ─────────────────────────────────────────────────────────
local function OnLootBtnEnter(self)
    local itemID = self.itemID
    if not itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local Resolve = sfui.dungeonjournal and sfui.dungeonjournal.ResolveItemLink
    local itemLink = Resolve and Resolve(self, itemID)
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        GameTooltip:SetItemByID(itemID)
    end
    local isRecipe = sfui.recipes and sfui.recipes.IsRecipe and sfui.recipes.IsRecipe(itemID)
    if isRecipe then
        if sfui.recipes.AddAltKnowledgeLines then
            sfui.recipes.AddAltKnowledgeLines(GameTooltip, itemID, true)
        end
        GameTooltip:AddLine(" ")
        local sID = (sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[itemID]) or itemID
        local isPinned = sfui.recipes.IsRecipePinned and sfui.recipes.IsRecipePinned(sID)
        GameTooltip:AddLine("|cff80c0ffctrl-click: open recipe catalogue|r", 0.5, 0.8, 1)
        GameTooltip:AddLine(
            string.format("|cff00ff88right-click: %s objective tracker|r",
                isPinned and "unpin from" or "track in"),
            0.2, 1, 0.4)
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff888888<shift-click to link · ctrl-click to view>|r", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function OnLootBtnLeave()
    GameTooltip:Hide()
end

local function OnLootBtnClick(self, mouseBtn)
    local itemID = self.itemID
    if not itemID then return end
    local isRecipe = sfui.recipes and sfui.recipes.IsRecipe and sfui.recipes.IsRecipe(itemID)
    if isRecipe and mouseBtn == "RightButton" then
        local sID = (sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[itemID]) or itemID
        if sfui.recipes.TogglePinRecipe then
            sfui.recipes.TogglePinRecipe(sID)
            if GameTooltip:IsOwned(self) then
                OnLootBtnEnter(self)
            end
            return
        end
    end
    if isRecipe and mouseBtn == "LeftButton" and _G.IsControlKeyDown and _G.IsControlKeyDown()
        and not (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
        and not (_G.IsAltKeyDown and _G.IsAltKeyDown()) then
        local sID = (sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[itemID]) or itemID
        if sfui.recipes.OpenBrowserToRecipe then
            sfui.recipes.OpenBrowserToRecipe(sID)
            return
        end
    end
    if sfui.dungeonjournal and sfui.dungeonjournal.HandleItemClick then
        sfui.dungeonjournal.HandleItemClick(self, mouseBtn, itemID)
    end
end

local function AcquireLootButton(pool, parent)
    for _, btn in ipairs(pool) do
        if not btn:IsShown() then return btn end
    end

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetHeight(LOOT_ROW_H)
    common.apply_flat_backdrop(btn, { 0.06, 0.06, 0.08, 0.7 }, { 0.15, 0.15, 0.18, 0.8 })

    -- Item icon container
    local iconBtn = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    btn.iconBtn = iconBtn
    iconBtn:SetSize(ICON_SZ, ICON_SZ)
    iconBtn:SetPoint("LEFT", 6, 0)
    iconBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    btn.iconTex = iconTex
    iconTex:SetAllPoints()
    common.set_square_icon_coords(iconTex)

    -- Wishlist diamond button on the far right
    local starBtn = CreateFrame("Button", nil, btn)
    btn.starBtn = starBtn
    starBtn:SetSize(22, 22)
    starBtn:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

    local starIcon = starBtn:CreateTexture(nil, "ARTWORK")
    starBtn.starIcon = starIcon
    starIcon:SetSize(16, 16)
    starIcon:SetPoint("CENTER", 0, 0)
    starIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_3")
    starIcon:SetDesaturated(true)
    starIcon:SetAlpha(0.25)

    starBtn:SetScript("OnEnter", function(self)
        local isWish = self.isWishlisted
        if not isWish and self.starIcon then
            self.starIcon:SetAlpha(0.7)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isWish then
            GameTooltip:SetText(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffcc44ffwishlisted item|r")
            GameTooltip:AddLine("click to remove from your loot wishlist.", 0.85, 0.85, 0.85)
            GameTooltip:AddLine("wishlisted items trigger special alert banners and sounds when dropped.", 0.6, 0.6, 0.6,
                true)
        else
            GameTooltip:SetText(
                "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cffffffffadd to wishlist|r")
            GameTooltip:AddLine("click to track this item on your loot wishlist.", 0.85, 0.85, 0.85)
            GameTooltip:AddLine("triggers alerts and highlights whenever this item drops.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    starBtn:SetScript("OnLeave", function(self)
        if not self.isWishlisted and self.starIcon then
            self.starIcon:SetAlpha(0.25)
        end
        GameTooltip:Hide()
    end)

    starBtn:SetScript("OnClick", function(self)
        if btn.itemID and sfui.dungeonjournal and sfui.dungeonjournal.ToggleWishlist then
            local active = sfui.dungeonjournal.ToggleWishlist(btn.itemID)
            self.isWishlisted = active
            if active then
                if self.starIcon then
                    self.starIcon:SetDesaturated(false)
                    self.starIcon:SetAlpha(1.0)
                end
                btn:SetBackdropBorderColor(0.8, 0.27, 1.0, 0.7)
            else
                if self.starIcon then
                    self.starIcon:SetDesaturated(true)
                    self.starIcon:SetAlpha(0.25)
                end
                btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.8)
            end
            if GameTooltip:IsOwned(self) then
                self:GetScript("OnEnter")(self)
            end
        end
    end)

    -- Level info / Drop rate text (right-aligned before star)
    local reqText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.reqText = reqText
    reqText:SetPoint("RIGHT", starBtn, "LEFT", -6, 0)
    reqText:SetJustifyH("RIGHT")
    reqText:SetWordWrap(false)
    reqText:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Item Name
    local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameText = nameText
    nameText:SetPoint("TOPLEFT", iconBtn, "TOPRIGHT", 8, -4)
    nameText:SetPoint("TOPRIGHT", starBtn, "TOPLEFT", -110, -4)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    -- Subtext: Slot & Subtype (e.g. "One-Hand · Sword" or "Leather · Chest")
    local typeText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.typeText = typeText
    typeText:SetPoint("BOTTOMLEFT", iconBtn, "BOTTOMRIGHT", 8, 4)
    typeText:SetPoint("BOTTOMRIGHT", starBtn, "BOTTOMLEFT", -110, 4)
    typeText:SetJustifyH("LEFT")
    typeText:SetWordWrap(false)
    typeText:SetTextColor(0.65, 0.65, 0.65, 1)

    -- Highlight
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hi:SetBlendMode("ADD")
    hi:SetAlpha(0.2)

    btn:SetScript("OnEnter", OnLootBtnEnter)
    btn:SetScript("OnLeave", OnLootBtnLeave)
    btn:SetScript("OnClick", OnLootBtnClick)

    pool[#pool + 1] = btn
    return btn
end

local ReleaseAll = dj.ReleaseAll

local function GetItemNumericDropRate(itemEntry, itemID, boss)
    local dropRate = (type(itemEntry) == "table" and (itemEntry.dropRate or itemEntry.rate or itemEntry[2]))
        or (boss and boss.dropRates and boss.dropRates[itemID])
    if not dropRate and boss and boss.isAll then
        local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(itemID)
        if source and source.boss and source.boss.dropRates then
            dropRate = source.boss.dropRates[itemID]
        end
    end
    if not dropRate then return 0, nil end
    local numRate = tonumber(dropRate)
    local rateStr
    if numRate and numRate > 0 and numRate < 1 then
        numRate = numRate * 100
        rateStr = string.format("%d%%", math.floor(numRate + 0.5))
    elseif numRate then
        rateStr = string.format("%g%%", numRate)
    else
        rateStr = tostring(dropRate)
        numRate = 0
    end
    return numRate or 0, rateStr
end

-- ─── Virtualized Loot Rows Renderer ──────────────────────────────────────────
local function RenderLootRowAt(slotIdx, rowIdx)
    local row = filteredLootRows[rowIdx]
    local btn = lootButtons[slotIdx]
    if not btn then
        btn = AcquireLootButton(lootButtons, lootContent)
        lootButtons[slotIdx] = btn
    end
    local y = (rowIdx - 1) * LOOT_ROW_STRIDE
    if btn._lastY ~= y then
        btn._lastY = y
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", lootContent, "TOPLEFT", 0, -y)
        btn:SetPoint("TOPRIGHT", lootContent, "TOPRIGHT", 0, -y)
        btn:SetHeight(LOOT_ROW_H)
    end

    local itemID     = row.id
    local link       = row.link
    local name       = row.name
    local quality    = row.quality
    local iLevel     = row.iLevel
    local reqLevel   = row.reqLevel
    local class      = row.class
    local subclass   = row.subclass
    local equipSlot  = row.equipSlot
    local icon       = row.icon
    local rateStr    = row.rateStr
    local boss       = renderedLootBoss

    btn.itemID               = itemID
    btn.link                 = link

    local isWish             = sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and
        sfui.dungeonjournal.IsWishlisted(itemID)
    btn.starBtn.isWishlisted = isWish
    if isWish then
        if btn.starBtn.starIcon then
            btn.starBtn.starIcon:SetDesaturated(false)
            btn.starBtn.starIcon:SetAlpha(1.0)
        end
        btn:SetBackdropBorderColor(0.8, 0.27, 1.0, 0.7)
    else
        if btn.starBtn.starIcon then
            btn.starBtn.starIcon:SetDesaturated(true)
            btn.starBtn.starIcon:SetAlpha(0.25)
        end
        btn:SetBackdropBorderColor(0.15, 0.15, 0.18, 0.8)
    end

    local r, g, b = GetQualityColor(quality)
    btn.iconTex:SetTexture(icon or 134400)
    btn.iconBtn:SetBackdropBorderColor(r, g, b, 0.8)

    btn.nameText:SetText(name or ("item #" .. itemID))
    btn.nameText:SetTextColor(r, g, b, 1)

    local slotText = equipSlot and _G[equipSlot] or equipSlot
    local typeLabel = ""
    if slotText and subclass and subclass ~= "" then
        typeLabel = tostring(slotText):lower() .. "  ·  " .. tostring(subclass):lower()
    elseif slotText then
        typeLabel = tostring(slotText):lower()
    elseif subclass then
        typeLabel = tostring(subclass):lower()
    elseif class then
        typeLabel = tostring(class):lower()
    end
    if boss and boss.isAll then
        local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and
            sfui.dj_camelot.GetItemSource(itemID)
        if source and source.bossName then
            if typeLabel ~= "" then
                typeLabel = typeLabel .. "  ·  |cff888888" .. tostring(source.bossName):lower() .. "|r"
            else
                typeLabel = "|cff888888" .. tostring(source.bossName):lower() .. "|r"
            end
        end
    end
    if sfui.recipes and sfui.recipes.IsRecipe and sfui.recipes.IsRecipe(itemID) then
        local status = sfui.recipes.GetRecipeStatus and sfui.recipes.GetRecipeStatus(itemID)
        local isAlt = sfui.recipes.IsAltNeeded and sfui.recipes.IsAltNeeded(itemID)
        local badge
        if status == "KNOWN_CURRENT" or status == "known" then
            badge = "  ·  |cff40c040[known]|r"
        elseif status == "CAN_LEARN_CURRENT" or status == "learnable" then
            badge = "  ·  |cff00ff88[learnable]|r"
        elseif status == "CAN_LEARN_ALT" or isAlt then
            badge = "  ·  |cff80c0ff[alt needs]|r"
        elseif status == "KNOWN_ALT" or status == "alt_known" then
            badge = "  ·  |cff80c0ff[alt known]|r"
        else
            badge = "  ·  |cffffa500[recipe]|r"
        end
        typeLabel = typeLabel .. badge
    end
    local upgEval = sfui.gear and sfui.gear.EvaluateItemUpgrade and sfui.gear.EvaluateItemUpgrade(link or itemID, nil, true)
    if upgEval and upgEval.isUpgrade then
        local pctTag = (upgEval.pctGain >= 99.5) and "+upgrade" or string.format("+%.0f%%", upgEval.pctGain)
        local clr = upgEval.isOffSpec and "|cff66ccff" or "|cff33ff88"
        local sep = (typeLabel ~= "") and "  ·  " or ""
        typeLabel = typeLabel .. sep .. clr .. "[" .. pctTag .. "]|r"
        if not isWish then
            btn:SetBackdropBorderColor(0.20, 0.75, 0.45, 0.65)
        end
    end
    if isWish and sfui.dungeonjournal and sfui.dungeonjournal.GetWishlistCharacters then
        local wishChars = sfui.dungeonjournal.GetWishlistCharacters(itemID)
        if wishChars and #wishChars > 0 then
            typeLabel = typeLabel .. "  ·  |cffcc44ff[" .. table.concat(wishChars, ", ") .. "]|r"
        end
    end
    btn.typeText:SetText(typeLabel)

    local reqStr = ""
    if sfui.recipes and sfui.recipes.IsRecipe and sfui.recipes.IsRecipe(itemID) then
        local rec = sfui.recipes.GetRecipe and sfui.recipes.GetRecipe(itemID)
        if rec and rec.minSkill and rec.minSkill > 0 then
            reqStr = "skill " .. rec.minSkill
        elseif reqLevel and reqLevel > 0 then
            reqStr = "req " .. reqLevel
        end
    elseif reqLevel and reqLevel > 0 then
        reqStr = "req " .. reqLevel
    elseif iLevel and iLevel > 0 then
        reqStr = "ilvl " .. iLevel
    end

    if rateStr and reqStr ~= "" then
        btn.reqText:SetText(string.format("|cff00e5ff%s|r  ·  %s", rateStr, reqStr))
    elseif rateStr then
        btn.reqText:SetText(string.format("|cff00e5ff%s|r", rateStr))
    else
        btn.reqText:SetText(reqStr)
    end

    if not btn:IsShown() then
        btn:Show()
    end
end

local function RenderVisibleLootRows(force, explicitScrollY)
    if not lootScroll or not lootContent then return end
    if filteredLootCount == 0 then
        lastLootFirstIdx = 0
        lastLootLastIdx = 0
        for i = 1, #lootButtons do
            lootButtons[i]:Hide()
        end
        return
    end

    local scrollY = explicitScrollY
    if scrollY == nil then
        scrollY = (lootScroll.GetVerticalScroll and lootScroll:GetVerticalScroll()) or lastLootScrollY or 0
    end
    if scrollY < 0 then scrollY = 0 end
    lastLootScrollY = scrollY

    local viewH = (lootScroll.GetHeight and lootScroll:GetHeight()) or 0
    if viewH < 100 then viewH = 440 end
    local visibleCount = math.ceil(viewH / LOOT_ROW_STRIDE) + 2
    local firstIdx = math.max(1, math.floor(scrollY / LOOT_ROW_STRIDE) + 1)
    local lastIdx = math.min(filteredLootCount, firstIdx + visibleCount - 1)
    firstIdx = math.max(1, lastIdx - visibleCount + 1)

    if not force and firstIdx == lastLootFirstIdx and lastIdx == lastLootLastIdx then
        return
    end
    lastLootFirstIdx = firstIdx
    lastLootLastIdx = lastIdx

    local slotIdx = 0
    for rowIdx = firstIdx, lastIdx do
        slotIdx = slotIdx + 1
        RenderLootRowAt(slotIdx, rowIdx)
    end
    for i = slotIdx + 1, #lootButtons do
        if lootButtons[i]:IsShown() then
            lootButtons[i]:Hide()
        end
    end
end

-- ─── Render Loot Items ────────────────────────────────────────────────────────
RenderLoot = function(boss, dungeon)
    if not lootScroll or not lootContent then return end

    local pal    = theme.GetPalette()
    local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }

    -- Update Boss Header details
    if bossHeaderFrame then
        if boss then
            if boss.isAll then
                bossHeaderFrame.name:SetText("all bosses")
                local dungeonName = (dungeon and dungeon.name) or "Dungeon"
                local numBosses = (dungeon and dungeon.bosses and #dungeon.bosses) or 0
                bossHeaderFrame.sub:SetText(dungeonName .. "  ·  " .. numBosses .. " boss encounters combined")

                local dropCount = (boss.items and #boss.items) or 0
                if dropCount > 0 then
                    bossHeaderFrame.count:SetText(dropCount .. " total drop" .. (dropCount > 1 and "s" or ""))
                    bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
                else
                    bossHeaderFrame.count:SetText("no recorded drops")
                    bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
                end

                bossHeaderFrame._lastDispID = nil
                bossHeaderFrame.portrait:SetTexture(boss.icon or (dungeon and dungeon.icon) or 133743)
                common.set_square_icon_coords(bossHeaderFrame.portrait)
                if bossHeaderFrame.portraitFrame then
                    bossHeaderFrame.portraitFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
                    bossHeaderFrame.portraitFrame:Show()
                end
                if bossHeaderFrame.mapBtn then
                    bossHeaderFrame.mapBtn:Hide()
                end
                if bossHeaderFrame.wishUpgBtn then
                    bossHeaderFrame.wishUpgBtn:ClearAllPoints()
                    bossHeaderFrame.wishUpgBtn:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", 0, -2)
                    bossHeaderFrame.wishUpgBtn:Show()
                end
            else
                local hasWish = GetBossWishlistInfo(boss)
                local wishTag = hasWish and "  |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:16:16:0:0|t" or ""
                bossHeaderFrame.name:SetText((boss.name or "unknown encounter") .. wishTag)
                local dungeonName = (dungeon and dungeon.name) or "dungeon"
                local lvlStr = boss.level and ("level " .. boss.level .. " encounter") or "boss encounter"
                bossHeaderFrame.sub:SetText(dungeonName .. "  ·  " .. lvlStr)

                local dropCount = (boss.items and #boss.items) or 0
                if dropCount > 0 then
                    bossHeaderFrame.count:SetText(dropCount .. " recorded drop" .. (dropCount > 1 and "s" or ""))
                    bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
                else
                    bossHeaderFrame.count:SetText("no recorded drops")
                    bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
                end

                -- Update Header Portrait (cached by displayId)
                local set = false
                if boss.displayId and SetPortraitTextureFromCreatureDisplayID then
                    if bossHeaderFrame._lastDispID == boss.displayId and bossHeaderFrame.portrait:GetTexture() then
                        set = true
                    else
                        local ok = pcall(SetPortraitTextureFromCreatureDisplayID, bossHeaderFrame.portrait, boss.displayId)
                        if ok and bossHeaderFrame.portrait:GetTexture() then
                            bossHeaderFrame._lastDispID = boss.displayId
                            bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
                            set = true
                        else
                            bossHeaderFrame._lastDispID = nil
                        end
                    end
                end
                if not set then
                    bossHeaderFrame._lastDispID = nil
                    if boss.icon then
                        bossHeaderFrame.portrait:SetTexture(boss.icon)
                        common.set_square_icon_coords(bossHeaderFrame.portrait)
                    else
                        bossHeaderFrame.portrait:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                        bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
                    end
                end
                if bossHeaderFrame.portraitFrame then
                    bossHeaderFrame.portraitFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
                    bossHeaderFrame.portraitFrame:Show()
                end
                if bossHeaderFrame.mapBtn then
                    local spot = sfui.dj_map and sfui.dj_map.FindBossMapSpot and sfui.dj_map.FindBossMapSpot(dungeon, boss.name)
                    if spot then
                        bossHeaderFrame.mapBtn.bossName = boss.name
                        bossHeaderFrame.mapBtn.dungeon = dungeon
                        bossHeaderFrame.mapBtn:Show()
                        if bossHeaderFrame.wishUpgBtn then
                            bossHeaderFrame.wishUpgBtn:ClearAllPoints()
                            bossHeaderFrame.wishUpgBtn:SetPoint("RIGHT", bossHeaderFrame.mapBtn, "LEFT", -6, 0)
                            bossHeaderFrame.wishUpgBtn:Show()
                        end
                    else
                        bossHeaderFrame.mapBtn:Hide()
                        if bossHeaderFrame.wishUpgBtn then
                            bossHeaderFrame.wishUpgBtn:ClearAllPoints()
                            bossHeaderFrame.wishUpgBtn:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", 0, -2)
                            bossHeaderFrame.wishUpgBtn:Show()
                        end
                    end
                end
            end
        else
            bossHeaderFrame.name:SetText("select an encounter")
            bossHeaderFrame.sub:SetText("choose a boss from the list on the left")
            bossHeaderFrame.count:SetText("")
            bossHeaderFrame._lastDispID = nil
            if bossHeaderFrame.portrait then
                bossHeaderFrame.portrait:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                bossHeaderFrame.portrait:SetTexCoord(0, 1, 0, 1)
            end
            if bossHeaderFrame.portraitFrame then
                bossHeaderFrame.portraitFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
            end
            if bossHeaderFrame.mapBtn then
                bossHeaderFrame.mapBtn:Hide()
            end
            if bossHeaderFrame.wishUpgBtn then
                bossHeaderFrame.wishUpgBtn:Hide()
            end
        end
    end

    local bossChanged = (renderedLootBoss ~= boss) or (renderedLootDungeon ~= dungeon)
    renderedLootBoss = boss
    renderedLootDungeon = dungeon

    wipe(currentBossItemSet)
    if not boss or not boss.items or #boss.items == 0 then
        filteredLootCount = 0
        RenderVisibleLootRows(true, 0)
        lootContent:SetHeight(10)
        if lootScroll and lootScroll.SetVerticalScroll then
            lootScroll:SetVerticalScroll(0)
        end
        if lootScroll and lootScroll.ScrollBar and lootScroll.ScrollBar.UpdateVisibility then
            lootScroll.ScrollBar:UpdateVisibility()
        end
        return
    end

    -- Cache sorted item list per boss (highest drop rate first)
    local sortedItems = boss._sortedItems
    if not sortedItems then
        sortedItems = {}
        for idx, itemEntry in ipairs(boss.items) do
            local itemID = type(itemEntry) == "table" and (itemEntry.id or itemEntry[1]) or itemEntry
            itemID = tonumber(itemID)
            if itemID then
                local numRate, rateStr = GetItemNumericDropRate(itemEntry, itemID, boss)
                sortedItems[#sortedItems + 1] = {
                    entry   = itemEntry,
                    id      = itemID,
                    rate    = numRate,
                    rateStr = rateStr,
                    index   = idx,
                }
            end
        end
        table.sort(sortedItems, CompareSortedItems)
        boss._sortedItems = sortedItems
    end

    local shownCount = 0
    for i = 1, #sortedItems do
        local sortedItem = sortedItems[i]
        local itemID     = sortedItem.id
        currentBossItemSet[itemID] = true

        local name, link, quality, iLevel, reqLevel, class, subclass, _, equipSlot, icon, _, classID, subclassID = common
            .get_item_info(itemID)

        if not name or not icon then
            local _, instType, instSubType, instEquipLoc, instIcon, instClassID, instSubClassID = common
                .get_item_instant_info(itemID)
            local instName = (_G.C_Item and _G.C_Item.GetItemNameByID and _G.C_Item.GetItemNameByID(itemID))
            name       = instName or ("item #" .. itemID)
            quality    = common.get_item_quality(itemID) or 1
            icon       = instIcon or (_G.C_Item and _G.C_Item.GetItemIconByID and _G.C_Item.GetItemIconByID(itemID)) or 134400
            equipSlot  = equipSlot or instEquipLoc
            class      = class or instType
            subclass   = subclass or instSubType
            classID    = classID or instClassID
            subclassID = subclassID or instSubClassID
            if common and common.request_item_load then
                common.request_item_load(itemID)
            elseif _G.C_Item and _G.C_Item.RequestLoadItemDataByID then
                _G.C_Item.RequestLoadItemDataByID(itemID)
            end
        end

        local itemLink = link or ("item:" .. itemID)
        if IsItemMatchingFilter(currentLootFilter, itemID, classID, subclassID, equipSlot, itemLink) then
            shownCount = shownCount + 1
            local rec = filteredLootRows[shownCount]
            if not rec then
                rec = {}
                filteredLootRows[shownCount] = rec
            end
            rec.id         = itemID
            rec.link       = link
            rec.name       = name
            rec.quality    = quality
            rec.iLevel     = iLevel
            rec.reqLevel   = reqLevel
            rec.class      = class
            rec.subclass   = subclass
            rec.equipSlot  = equipSlot
            rec.icon       = icon
            rec.rateStr    = sortedItem.rateStr
        end
    end

    for i = shownCount + 1, #filteredLootRows do
        filteredLootRows[i] = nil
    end
    filteredLootCount = shownCount

    -- Update count badge if filtered
    if bossHeaderFrame and bossHeaderFrame.count and boss and boss.items then
        local totalCount = #boss.items
        if currentLootFilter ~= "all" then
            if shownCount > 0 then
                bossHeaderFrame.count:SetText(string.format("%d of %d items", shownCount, totalCount))
                bossHeaderFrame.count:SetTextColor(accent[1], accent[2], accent[3], 1)
            else
                bossHeaderFrame.count:SetText(string.format("0 of %d items", totalCount))
                bossHeaderFrame.count:SetTextColor(0.5, 0.5, 0.5, 1)
            end
        end
    end

    local totalH = math.max(1, shownCount * LOOT_ROW_STRIDE)
    lootContent:SetHeight(totalH)
    if bossChanged and lootScroll.SetVerticalScroll then
        lastLootScrollY = 0
        lootScroll:SetVerticalScroll(0)
    end
    RenderVisibleLootRows(true, bossChanged and 0 or nil)
    if lootScroll and lootScroll.ScrollBar and lootScroll.ScrollBar.UpdateVisibility then
        lootScroll.ScrollBar:UpdateVisibility()
    end
end

-- ─── Render Boss List ─────────────────────────────────────────────────────────
local function RefreshBossView()
    if not bossPanel or not bossPanel:IsShown() then return end

    local dungeon = GetCurrentDungeon()
    local encounters = GetEncounterList(dungeon)

    ReleaseAll(bossButtons)

    local savedBoss = DJ_DB().lastBoss or 1
    if savedBoss > #encounters then savedBoss = 1 end
    selectedBossIndex = savedBoss

    local pal         = theme.GetPalette()
    local accent      = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }

    local y           = 0
    for idx, boss in ipairs(encounters) do
        local btn = AcquireBossButton(bossButtons, bossListContent)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", bossListContent, "TOPLEFT", 0, -y)
        btn:SetPoint("TOPRIGHT", bossListContent, "TOPRIGHT", 0, -y)
        btn:SetHeight(BOSS_BTN_H)

        -- Icon (cached by displayId)
        local set = false
        if boss.isAll then
            btn._lastDispID = nil
            btn.icon:SetTexture(boss.icon or (dungeon and dungeon.icon) or 133743)
            common.set_square_icon_coords(btn.icon)
            set = true
        elseif boss.displayId and SetPortraitTextureFromCreatureDisplayID then
            if btn._lastDispID == boss.displayId and btn.icon:GetTexture() then
                set = true
            else
                local ok = pcall(SetPortraitTextureFromCreatureDisplayID, btn.icon, boss.displayId)
                if ok and btn.icon:GetTexture() then
                    btn._lastDispID = boss.displayId
                    btn.icon:SetTexCoord(0, 1, 0, 1)
                    set = true
                else
                    btn._lastDispID = nil
                end
            end
        end
        if not set then
            btn._lastDispID = nil
            if boss.icon then
                btn.icon:SetTexture(boss.icon)
                common.set_square_icon_coords(btn.icon)
            else
                btn.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
                btn.icon:SetTexCoord(0, 1, 0, 1)
            end
        end

        btn.nameText:SetText(boss.name or ("boss #" .. idx))

        if boss.isAll then
            btn.levelText:SetText(boss.subtitle or "all encounters")
        elseif boss.level then
            btn.levelText:SetText("level " .. boss.level)
        else
            btn.levelText:SetText("boss encounter")
        end

        ApplyBossButtonSelectedStyle(btn, (idx == selectedBossIndex), accent)

        btn.bossIndex = idx
        btn.bossData  = boss
        btn.bossName  = boss.name
        UpdateBossButtonWishlist(btn)

        btn:Show()
        y = y + BOSS_BTN_H + BOSS_BTN_PAD
    end

    bossListContent:SetHeight(math.max(1, y))
    if bossListScroll and bossListScroll.ScrollBar and bossListScroll.ScrollBar.UpdateVisibility then
        bossListScroll.ScrollBar:UpdateVisibility()
    end

    local currentBoss = encounters[selectedBossIndex]
    RenderLoot(currentBoss, dungeon)
end

-- ─── Debounced Item Load Refresh ──────────────────────────────────────────────
local isRefreshQueued = false

local function QueueLootRefresh(itemID)
    if not bossPanel or not bossPanel:IsShown() then return end
    if isRefreshQueued then return end
    if itemID and not currentBossItemSet[itemID] then return end

    isRefreshQueued = true
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0.15, function()
            isRefreshQueued = false
            if bossPanel and bossPanel:IsShown() then
                local dungeon = GetCurrentDungeon()
                local encounters = GetEncounterList(dungeon)
                local currentBoss = encounters[selectedBossIndex]
                if currentBoss then
                    RenderLoot(currentBoss, dungeon)
                end
                UpdateAllBossButtonsWishlistState()
            end
        end)
    else
        isRefreshQueued = false
    end
end

-- ─── Build UI Structure ───────────────────────────────────────────────────────
local function OnFrameCreated(arg1, arg2)
    local payload = (type(arg1) == "table" and arg1) or arg2
    if not payload or not payload.bossPanel then return end
    if lootScroll then return end -- already initialized
    bossPanel = payload.bossPanel

    -- ── Left Sub-Panel: Boss List Container ───────────────────────────────────
    local bossListContainer = CreateFrame("Frame", nil, bossPanel, "BackdropTemplate")
    bossListContainer:SetPoint("TOPLEFT", bossPanel, "TOPLEFT", 0, 0)
    bossListContainer:SetPoint("BOTTOMLEFT", bossPanel, "BOTTOMLEFT", 0, 0)
    bossListContainer:SetWidth(BOSS_LIST_W)
    theme.ApplyContainerStyle(bossListContainer)

    bossListScroll = CreateFrame("ScrollFrame", "SfuiDJBossListScroll", bossListContainer, "UIPanelScrollFrameTemplate")
    bossListScroll:SetPoint("TOPLEFT", bossListContainer, "TOPLEFT", 4, -4)
    bossListScroll:SetPoint("BOTTOMRIGHT", bossListContainer, "BOTTOMRIGHT", -22, 4)

    local BOSS_SCROLL_W = 174
    bossListContent = CreateFrame("Frame", nil, bossListScroll)
    bossListContent:SetSize(BOSS_SCROLL_W, 1)
    bossListScroll:SetScrollChild(bossListContent)

    if bossListScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(bossListScroll.ScrollBar)
    end

    -- ── Right Sub-Panel: Loot & Details Container ─────────────────────────────
    local detailContainer = CreateFrame("Frame", nil, bossPanel, "BackdropTemplate")
    detailContainer:SetPoint("TOPLEFT", bossListContainer, "TOPRIGHT", 8, 0)
    detailContainer:SetPoint("BOTTOMRIGHT", bossPanel, "BOTTOMRIGHT", 0, 0)
    theme.ApplyContainerStyle(detailContainer)

    -- Top Header in Detail Container
    bossHeaderFrame = CreateFrame("Frame", nil, detailContainer)
    bossHeaderFrame:SetPoint("TOPLEFT", detailContainer, "TOPLEFT", 10, -8)
    bossHeaderFrame:SetPoint("TOPRIGHT", detailContainer, "TOPRIGHT", -10, -8)
    bossHeaderFrame:SetHeight(48)

    -- Creature portrait in boss header
    local portraitFrame = CreateFrame("Frame", nil, bossHeaderFrame, "BackdropTemplate")
    bossHeaderFrame.portraitFrame = portraitFrame
    portraitFrame:SetSize(42, 42)
    portraitFrame:SetPoint("LEFT", bossHeaderFrame, "LEFT", 0, 0)
    common.apply_flat_backdrop(portraitFrame, { 0.04, 0.04, 0.06, 0.9 }, { 0.20, 0.20, 0.25, 0.6 })

    local portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
    bossHeaderFrame.portrait = portrait
    portrait:SetAllPoints()

    local bossTitle = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bossHeaderFrame.name = bossTitle
    bossTitle:SetPoint("TOPLEFT", portraitFrame, "TOPRIGHT", 10, -2)
    bossTitle:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", -225, -2)
    bossTitle:SetJustifyH("LEFT")
    bossTitle:SetWordWrap(false)

    local bossSub = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bossHeaderFrame.sub = bossSub
    bossSub:SetPoint("BOTTOMLEFT", portraitFrame, "BOTTOMRIGHT", 10, 4)
    bossSub:SetPoint("BOTTOMRIGHT", bossHeaderFrame, "BOTTOMRIGHT", -130, 4)
    bossSub:SetJustifyH("LEFT")
    bossSub:SetWordWrap(false)
    bossSub:SetTextColor(0.7, 0.7, 0.7, 1)

    local dropCountText = bossHeaderFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bossHeaderFrame.count = dropCountText
    dropCountText:SetPoint("BOTTOMRIGHT", bossHeaderFrame, "BOTTOMRIGHT", 0, 4)
    dropCountText:SetJustifyH("RIGHT")

    local mapBtn = CreateFrame("Button", nil, bossHeaderFrame, "BackdropTemplate")
    bossHeaderFrame.mapBtn = mapBtn
    mapBtn:SetSize(96, 20)
    mapBtn:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", 0, -2)
    local mfs = mapBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mapBtn.fs = mfs
    mfs:SetPoint("CENTER")
    mfs:SetText("show on map")
    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(mapBtn, false)
        sfui.theme.RegisterButton(mapBtn, false)
    else
        common.apply_flat_backdrop(mapBtn, { 0.10, 0.10, 0.14, 0.9 }, { 0.24, 0.24, 0.28, 1 })
    end
    mapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("show on dungeon map", 1, 0.82, 0)
        GameTooltip:AddLine("switch to the map tab and highlight this boss encounter.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    mapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapBtn:SetScript("OnClick", function(self)
        GameTooltip:Hide()
        if self.dungeon and self.bossName and sfui.dj_map and sfui.dj_map.FocusBoss then
            sfui.dj_map.FocusBoss(nil, self.dungeon, self.bossName)
        end
    end)
    mapBtn:Hide()

    local wishUpgBtn = CreateFrame("Button", nil, bossHeaderFrame, "BackdropTemplate")
    bossHeaderFrame.wishUpgBtn = wishUpgBtn
    wishUpgBtn:SetSize(116, 20)
    wishUpgBtn:SetPoint("TOPRIGHT", bossHeaderFrame, "TOPRIGHT", 0, -2)
    local wufs = wishUpgBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    wishUpgBtn.fs = wufs
    wufs:SetPoint("CENTER")
    wufs:SetText("wishlist upgrades")
    if sfui.theme and sfui.theme.ApplyButtonStyle then
        sfui.theme.ApplyButtonStyle(wishUpgBtn, false)
        sfui.theme.RegisterButton(wishUpgBtn, false)
    else
        common.apply_flat_backdrop(wishUpgBtn, { 0.10, 0.10, 0.14, 0.9 }, { 0.24, 0.24, 0.28, 1 })
    end
    wishUpgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("wishlist dungeon upgrades", 1, 0.82, 0)
        GameTooltip:AddLine("adds all spec upgrades across this dungeon to your wishlist.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    wishUpgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wishUpgBtn:SetScript("OnClick", function()
        GameTooltip:Hide()
        local dungeon = GetCurrentDungeon()
        if not dungeon or not dungeon.bosses or not (sfui.gear and sfui.gear.EvaluateItemUpgrade) then return end
        local toAdd = {}
        local uncached = 0
        local seen = {}
        for _, b in ipairs(dungeon.bosses) do
            for _, it in ipairs(b.items or {}) do
                local id = tonumber(type(it) == "table" and (it.id or it[1]) or it)
                if id and not seen[id] then
                    seen[id] = true
                    local nm, link = common.get_item_info(id)
                    if not nm then
                        uncached = uncached + 1
                        if common.request_item_load then common.request_item_load(id) end
                    else
                        local eval = sfui.gear.EvaluateItemUpgrade(link or id, nil, true)
                        if eval and eval.isUpgrade and not eval.isOffSpec then
                            toAdd[#toAdd + 1] = id
                        end
                    end
                end
            end
        end
        local added = 0
        if #toAdd > 0 and sfui.dungeonjournal then
            if sfui.dungeonjournal.AddWishlistItemsBatch then
                added = sfui.dungeonjournal.AddWishlistItemsBatch(toAdd, true)
            elseif sfui.dungeonjournal.AddWishlistItem then
                for i = 1, #toAdd do
                    if sfui.dungeonjournal.AddWishlistItem(toAdd[i], true, i < #toAdd) then
                        added = added + 1
                    end
                end
            end
        end
        if sfui.print then
            local dName = (dungeon.name and dungeon.name:lower()) or "dungeon"
            if added > 0 then
                sfui.print(string.format("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:14:14:0:0|t |cff33ff88wishlisted %d upgrade%s in %s.|r", added, added == 1 and "" or "s", dName))
            elseif uncached > 0 then
                sfui.print(string.format("|cffaaaaaa%d item(s) still caching for %s; click again in a moment.|r", uncached, dName))
            else
                sfui.print(string.format("|cffaaaaaano new main-spec upgrades found in %s.|r", dName))
            end
        end
        RefreshBossView()
    end)
    wishUpgBtn:Hide()

    -- Divider under boss header
    local div = detailContainer:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", bossHeaderFrame, "BOTTOMLEFT", 0, -2)
    div:SetPoint("TOPRIGHT", bossHeaderFrame, "BOTTOMRIGHT", 0, -2)
    div:SetHeight(1)
    div:SetColorTexture(0.2, 0.2, 0.24, 0.8)

    -- Filter Bar Container (between header and loot scroll)
    local filterBar = CreateFrame("Frame", nil, detailContainer)
    filterBar:SetPoint("TOPLEFT", div, "BOTTOMLEFT", 0, -4)
    filterBar:SetPoint("TOPRIGHT", div, "BOTTOMRIGHT", 0, -4)
    filterBar:SetHeight(22)

    ApplyPillStyle = function(pBtn, accent)
        local key = pBtn.filterKey
        local isSel = (key == currentLootFilter)
        local isUsableOnly = (categoryUsableOnly[key] == true)
        if isSel then
            pBtn:SetBackdropColor(accent[1], accent[2], accent[3], 0.22)
            pBtn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.75)
            pBtn.label:SetTextColor(accent[1], accent[2], accent[3], 1)
        elseif isUsableOnly then
            pBtn:SetBackdropColor(0.12, 0.22, 0.14, 0.6)
            pBtn:SetBackdropBorderColor(0.25, 0.7, 0.35, 0.75)
            pBtn.label:SetTextColor(0.4, 0.85, 0.5, 1)
        else
            pBtn:SetBackdropColor(0.08, 0.08, 0.10, 0.6)
            pBtn:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.6)
            pBtn.label:SetTextColor(0.65, 0.65, 0.7, 1)
        end
    end

    UpdateFilterPills = function()
        local pal    = theme.GetPalette()
        local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
        local pillX  = 0

        for _, pBtn in ipairs(filterButtons) do
            local key = pBtn.filterKey
            local isSel = (key == currentLootFilter)
            local isUsableOnly = (categoryUsableOnly[key] == true)

            -- Base label
            local labelText = pBtn.baseLabel or ""
            if key == "usable" and isSel then
                if usableFilterSpecMode == "all" then
                    labelText = "usable (all)"
                else
                    labelText = "usable"
                end
            elseif isUsableOnly then
                labelText = labelText .. " *"
            end
            pBtn.label:SetText(labelText)

            local textW = pBtn.label:GetStringWidth() or 20
            local minW = (key == "wishlist") and 70 or 34
            local extraPad = (key == "wishlist") and 22 or 14
            local btnW = math.max(minW, math.floor(textW + extraPad))
            pBtn:SetWidth(btnW)
            pBtn:ClearAllPoints()
            pBtn:SetPoint("LEFT", filterBar, "LEFT", pillX, 0)
            pillX = pillX + btnW + 5

            ApplyPillStyle(pBtn, accent)
        end
    end

    local pillX = 0
    for _, def in ipairs(FILTER_BUTTONS) do
        local pBtn     = CreateFrame("Button", nil, filterBar, "BackdropTemplate")
        pBtn.filterKey = def.key
        pBtn.baseLabel = def.label
        pBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pBtn:SetHeight(18)
        common.apply_flat_backdrop(pBtn)
        pBtn:SetPoint("LEFT", filterBar, "LEFT", pillX, 0)

        local pLbl = pBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pBtn.label = pLbl
        pLbl:SetPoint("CENTER", pBtn, "CENTER", 0, 0)
        pLbl:SetText(def.label)

        local textW = pLbl:GetStringWidth() or 20
        local minW = (def.key == "wishlist") and 70 or 34
        local extraPad = (def.key == "wishlist") and 22 or 14
        local btnW = math.max(minW, math.floor(textW + extraPad))
        pBtn:SetWidth(btnW)
        pillX = pillX + btnW + 5

        pBtn:SetScript("OnClick", function(self, mouseBtn)
            if def.key == "usable" then
                if currentLootFilter ~= "usable" then
                    currentLootFilter = "usable"
                else
                    usableFilterSpecMode = (usableFilterSpecMode == "spec") and "all" or "spec"
                end
            elseif def.key == "armor" or def.key == "weapons" or def.key == "trinkets" or def.key == "other" then
                if mouseBtn == "RightButton" then
                    currentLootFilter = def.key
                    categoryUsableOnly[def.key] = not categoryUsableOnly[def.key]
                else
                    currentLootFilter = def.key
                    categoryUsableOnly[def.key] = false
                end
            else
                currentLootFilter = def.key
                categoryUsableOnly = {}
            end

            UpdateFilterPills()
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end

            if self:IsMouseOver() and self.OnEnterHandler then
                self.OnEnterHandler(self)
            end
        end)

        pBtn.OnEnterHandler = function(self)
            if self.filterKey ~= currentLootFilter and not categoryUsableOnly[self.filterKey] then
                self:SetBackdropBorderColor(0.4, 0.4, 0.48, 0.9)
                self.label:SetTextColor(0.9, 0.9, 0.95, 1)
            end

            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()

            local key = self.filterKey
            if key == "all" then
                GameTooltip:AddLine("all drops", 1, 1, 1)
                GameTooltip:AddLine("shows all loot from this boss", 0.7, 0.7, 0.7)
            elseif key == "usable" then
                GameTooltip:AddLine("usable loot", 1, 1, 1)
                local curClass = UnitClass("player")
                local curClassLower = curClass and curClass:lower() or "class"
                if usableFilterSpecMode == "spec" then
                    local activeSpec = GetPlayerActiveSpecID()
                    local sName = GetSpecDisplayName(activeSpec)
                    local desc = (sName ~= "") and (sName .. " " .. curClassLower) or curClassLower
                    GameTooltip:AddLine("filtered for: " .. desc .. " (active spec)", 0.3, 0.85, 0.4)
                    GameTooltip:AddLine("click to show: all " .. curClassLower .. " specs", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("filtered for: all " .. curClassLower .. " specs", 0.3, 0.85, 0.4)
                    local activeSpec = GetPlayerActiveSpecID()
                    local sName = GetSpecDisplayName(activeSpec)
                    if sName ~= "" then
                        GameTooltip:AddLine("click to show: " .. sName .. " only (active spec)", 0.7, 0.7, 0.7)
                    end
                end
            elseif key == "armor" then
                GameTooltip:AddLine("armor drops", 1, 1, 1)
                if categoryUsableOnly["armor"] then
                    GameTooltip:AddLine("showing: usable armor only", 0.3, 0.85, 0.4)
                    GameTooltip:AddLine("left-click: show all armor", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("showing: all armor", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("right-click: filter usable armor only", 0.7, 0.7, 0.7)
                end
            elseif key == "weapons" then
                GameTooltip:AddLine("weapon drops", 1, 1, 1)
                if categoryUsableOnly["weapons"] then
                    GameTooltip:AddLine("showing: usable weapons only", 0.3, 0.85, 0.4)
                    GameTooltip:AddLine("left-click: show all weapons", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("showing: all weapons", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("right-click: filter usable weapons only", 0.7, 0.7, 0.7)
                end
            elseif key == "trinkets" then
                GameTooltip:AddLine("trinket & jewelry drops", 1, 1, 1)
                if categoryUsableOnly["trinkets"] then
                    GameTooltip:AddLine("showing: usable trinkets & jewelry only", 0.3, 0.85, 0.4)
                    GameTooltip:AddLine("left-click: show all trinkets & jewelry", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("showing: all trinkets, rings, and necks", 0.8, 0.8, 0.8)
                    GameTooltip:AddLine("right-click: filter usable only", 0.7, 0.7, 0.7)
                end
            elseif key == "other" then
                GameTooltip:AddLine("other drops", 1, 1, 1)
                GameTooltip:AddLine("tokens, relics, recipes, bags, misc", 0.7, 0.7, 0.7)
                if categoryUsableOnly["other"] then
                    GameTooltip:AddLine("showing: usable other drops only", 0.3, 0.85, 0.4)
                    GameTooltip:AddLine("left-click: show all other drops", 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("right-click: filter usable only", 0.7, 0.7, 0.7)
                end
            elseif key == "wishlist" then
                GameTooltip:AddLine("wishlisted drops", 1, 1, 1)
                GameTooltip:AddLine("shows items you marked with a purple gem", 0.7, 0.7, 0.7)
            end

            GameTooltip:Show()
        end

        pBtn:SetScript("OnEnter", pBtn.OnEnterHandler)
        pBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            local pal = theme.GetPalette()
            local accent = pal and pal.accentColor or { 1, 0.78, 0.2, 1 }
            ApplyPillStyle(self, accent)
        end)

        filterButtons[#filterButtons + 1] = pBtn
    end

    UpdateFilterPills()

    -- Loot ScrollFrame (width: 428 - 10 - 22 = 396)
    lootScroll = CreateFrame("ScrollFrame", "SfuiDJLootScroll", detailContainer, "UIPanelScrollFrameTemplate")
    lootScroll:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -6)
    lootScroll:SetPoint("BOTTOMRIGHT", detailContainer, "BOTTOMRIGHT", -22, 8)

    local LOOT_SCROLL_W = 396
    lootContent = CreateFrame("Frame", nil, lootScroll)
    lootContent:SetSize(LOOT_SCROLL_W, 1)
    lootScroll:SetScrollChild(lootContent)

    lootScroll:HookScript("OnVerticalScroll", function(_, offset)
        RenderVisibleLootRows(false, offset)
    end)

    if lootScroll.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(lootScroll.ScrollBar)
    end

    local function OnItemLoadResult(_, itemID, success)
        if success ~= false then
            QueueLootRefresh(itemID)
        end
    end

    bossPanel:HookScript("OnShow", function()
        if sfui.events and sfui.events.RegisterEvent then
            sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemLoadResult)
            sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoadResult)
        end
    end)
    bossPanel:HookScript("OnHide", function()
        if sfui.events and sfui.events.UnregisterEvent then
            sfui.events.UnregisterEvent("GET_ITEM_INFO_RECEIVED", OnItemLoadResult)
            sfui.events.UnregisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoadResult)
        end
    end)
    if bossPanel:IsShown() and sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("GET_ITEM_INFO_RECEIVED", OnItemLoadResult)
        sfui.events.RegisterEvent("ITEM_DATA_LOAD_RESULT", OnItemLoadResult)
    end

    -- Register with orchestrator
    if sfui.dungeonjournal and sfui.dungeonjournal._registerBosses then
        sfui.dungeonjournal._registerBosses(RefreshBossView)
    end

    RefreshBossView()
end

sfui.dungeonjournal._initBosses = OnFrameCreated

function sfui.dungeonjournal.SelectBoss(bossIndexOrName)
    if not bossIndexOrName then return end
    local d = GetCurrentDungeon()
    local encounters = GetEncounterList(d)
    if not encounters or #encounters == 0 then return end

    if type(bossIndexOrName) == "number" then
        if bossIndexOrName >= 1 and bossIndexOrName <= #encounters then
            selectedBossIndex = bossIndexOrName
            DJ_DB().lastBoss = bossIndexOrName
            RefreshBossView()
            return
        end
    elseif type(bossIndexOrName) == "string" then
        local target = bossIndexOrName:lower()
        for idx, enc in ipairs(encounters) do
            if enc.name and (enc.name:lower() == target or enc.name:lower():find(target, 1, true)) then
                selectedBossIndex = idx
                DJ_DB().lastBoss = idx
                RefreshBossView()
                return
            end
        end
    end
end

-- ─── Message & Event Hooks ───────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_DJ_CLEAR_CACHE", function()
        itemClassUsableCache = {}
        ReleaseAll(bossButtons)
        ReleaseAll(lootButtons)
        RefreshBossView()
    end)
    sfui.events.RegisterMessage("SFUI_DJ_WISHLIST_UPDATED", function()
        if bossPanel and bossPanel:IsShown() then
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end
            UpdateAllBossButtonsWishlistState()
        end
    end)
    sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", function()
        if UpdateFilterPills then
            UpdateFilterPills()
        end
        if bossPanel and bossPanel:IsShown() then
            local dungeon = GetCurrentDungeon()
            local encounters = GetEncounterList(dungeon)
            local currentBoss = encounters[selectedBossIndex]
            if currentBoss then
                RenderLoot(currentBoss, dungeon)
            end
        end
    end)
end
