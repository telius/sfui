local addonName, addon = ...
sfui = sfui or {}
sfui.gear = sfui.gear or {}

local cfg = sfui.config
local common = sfui.common
local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local C_EquipmentSet = _G.C_EquipmentSet
local GetInstanceInfo = _G.GetInstanceInfo
local UIParent = _G.UIParent
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local table = _G.table
local string = _G.string
local setmetatable = _G.setmetatable
local tonumber = _G.tonumber
local tostring = _G.tostring
local select = _G.select
local math = _G.math
local next = _G.next
local wipe = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
local unpack = _G.unpack or _G.table.unpack
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetItemInfoInstant = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant or sfui.common.get_item_id
local GetItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
local IsShiftKeyDown = _G.IsShiftKeyDown

local function show_tooltip(owner, anchor, title, lines)
    local tip = sfui.tooltip or _G.GameTooltip
    if not tip or not owner then return end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if title then
        tip:SetText(tostring(title):lower())
    end
    if lines then
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                local txt = line[1] and tostring(line[1]):lower() or ""
                tip:AddLine(txt, line[2], line[3], line[4], line[5])
            else
                tip:AddLine(tostring(line):lower())
            end
        end
    end
    tip:Show()
end

local function show_item_tooltip(owner, itemID, anchor, extraLines)
    local tip = sfui.tooltip or _G.GameTooltip
    if not tip or not owner or not itemID then return end
    tip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    tip:SetItemByID(itemID)
    if extraLines then
        for _, el in ipairs(extraLines) do
            if type(el) == "table" then
                local txt = el[1] and tostring(el[1]):lower() or ""
                tip:AddLine(txt, el[2], el[3], el[4])
            else
                tip:AddLine(tostring(el):lower())
            end
        end
    end
    tip:Show()
end

local function hide_tooltip()
    if sfui.tooltip and sfui.tooltip:IsShown() then
        sfui.tooltip:Hide()
    end
    if _G.GameTooltip and _G.GameTooltip:IsShown() then
        _G.GameTooltip:Hide()
    end
end

local function GetHeaderHeight()
    if sfui.gear.GetHeaderHeight then
        return sfui.gear.GetHeaderHeight()
    end
    return (not sfui.isRetail) and 34 or 56
end

-- -------------------------------------------------------------------------
-- STAT DEFINITIONS & COLOR CODING
-- -------------------------------------------------------------------------
local pawnScratchList = {
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
    { stat = "", weight = 0 }, { stat = "", weight = 0 },
}
local function pawnSortDesc(a, b) return a.weight > b.weight end

local DEFENSIVE_STATS = {
    Def = true,
    Defense = true,
    Dodge = true,
    Parry = true,
    Block = true,
    BlockVal = true,
    BlockValue = true,
    blockval = true,
    Arm = true,
    Armor = true,
}
sfui.gear.DEFENSIVE_STATS = DEFENSIVE_STATS

local statAbbrv = {
    -- Retail
    Haste = "h",
    Mastery = "m",
    Versatility = "v",
    Crit = "c",
    H = "h",
    M = "m",
    V = "v",
    C = "c",
    haste = "h",
    mastery = "m",
    versatility = "v",
    crit = "c",
    h = "h",
    m = "m",
    v = "v",
    c = "c",
    -- Classic Primary / Power
    SP = "sp",
    SpellPower = "sp",
    SpellDamage = "sp",
    sp = "sp",
    Heal = "heal",
    Healing = "heal",
    heal = "heal",
    Hit = "hit",
    hit = "hit",
    AP = "ap",
    AttackPower = "ap",
    ap = "ap",
    RAP = "rap",
    RangedAP = "rap",
    rap = "rap",
    MP5 = "mp5",
    ManaRegen = "mp5",
    mp5 = "mp5",
    Str = "str",
    Strength = "str",
    str = "str",
    Agi = "agi",
    Agility = "agi",
    agi = "agi",
    Int = "int",
    Intellect = "int",
    int = "int",
    Spi = "spi",
    Spirit = "spi",
    spi = "spi",
    Stam = "stam",
    Stamina = "stam",
    stam = "stam",
    -- Classic Defensive (Tank only)
    Def = "def",
    Defense = "def",
    def = "def",
    Dodge = "dodge",
    dodge = "dodge",
    Parry = "parry",
    parry = "parry",
    Block = "block",
    block = "block",
    BlockVal = "blockval",
    BlockValue = "blockval",
    blockval = "blockval",
    Arm = "arm",
    Armor = "arm",
    arm = "arm",
    -- Camelot Secondary Stats
    ArP = "arp",
    ArmorPenetration = "arp",
    arp = "arp",
    Exp = "exp",
    Expertise = "exp",
    exp = "exp",
}
sfui.gear.statAbbrv = statAbbrv

local statFullName = {
    H = "haste",
    Haste = "haste",
    h = "haste",
    haste = "haste",
    M = "mastery",
    Mastery = "mastery",
    m = "mastery",
    mastery = "mastery",
    V = "versatility",
    Versatility = "versatility",
    v = "versatility",
    versatility = "versatility",
    C = "crit",
    Crit = "crit",
    c = "crit",
    crit = "crit",
    SP = "spell power",
    SpellPower = "spell power",
    SpellDamage = "spell power",
    sp = "spell power",
    Heal = "healing",
    Healing = "healing",
    heal = "healing",
    Hit = "hit chance",
    hit = "hit chance",
    AP = "attack power",
    AttackPower = "attack power",
    ap = "attack power",
    RAP = "ranged attack power",
    RangedAP = "ranged attack power",
    rap = "ranged attack power",
    MP5 = "mana per 5 sec",
    ManaRegen = "mana per 5 sec",
    mp5 = "mana per 5 sec",
    Str = "strength",
    Strength = "strength",
    str = "strength",
    Agi = "agility",
    Agility = "agility",
    agi = "agility",
    Int = "intellect",
    Intellect = "intellect",
    int = "intellect",
    Spi = "spirit",
    Spirit = "spirit",
    spi = "spirit",
    Stam = "stamina",
    Stamina = "stamina",
    stam = "stamina",
    Def = "defense",
    Defense = "defense",
    def = "defense",
    Dodge = "dodge",
    dodge = "dodge",
    Parry = "parry",
    parry = "parry",
    Block = "block",
    block = "block",
    BlockVal = "block value",
    BlockValue = "block value",
    blockval = "block value",
    Arm = "armor",
    Armor = "armor",
    arm = "armor",
    -- Camelot Secondary Stats
    ArP = "armor penetration",
    ArmorPenetration = "armor penetration",
    arp = "armor penetration",
    Exp = "expertise",
    Expertise = "expertise",
    exp = "expertise",
}

local STAT_COLORS = (sfui.config and sfui.config.stat_colors) or {
    haste       = { 0.2, 0.85, 0.3, 1.0 },
    crit        = { 1.0, 0.45, 0.1, 1.0 },
    mastery     = { 0.75, 0.4, 1.0, 1.0 },
    versatility = { 0.2, 0.65, 1.0, 1.0 },
    -- Classic additions
    spellpower  = { 0.3, 0.75, 1.0, 1.0 },
    healing     = { 0.2, 0.95, 0.5, 1.0 },
    hit         = { 1.0, 0.85, 0.2, 1.0 },
    ap          = { 0.95, 0.3, 0.2, 1.0 },
    rap         = { 0.4, 0.85, 0.3, 1.0 },
    mp5         = { 0.3, 0.55, 0.95, 1.0 },
    strength    = { 0.85, 0.45, 0.25, 1.0 },
    agility     = { 0.3, 0.85, 0.45, 1.0 },
    intellect   = { 0.35, 0.65, 0.95, 1.0 },
    spirit      = { 0.8, 0.8, 0.95, 1.0 },
    stamina     = { 0.75, 0.65, 0.35, 1.0 },
    defense     = { 0.6, 0.65, 0.75, 1.0 },
    dodge       = { 0.35, 0.75, 0.8, 1.0 },
    parry       = { 0.75, 0.55, 0.35, 1.0 },
    block       = { 0.85, 0.75, 0.3, 1.0 },
    blockval    = { 0.75, 0.8, 0.4, 1.0 },
    armor       = { 0.55, 0.55, 0.55, 1.0 },
    arp         = { 0.85, 0.25, 0.45, 1.0 },
    exp         = { 0.95, 0.65, 0.2, 1.0 },
}

local statKeyMap = {
    Haste = "haste", H = "haste", Crit = "crit", C = "crit", Mastery = "mastery", M = "mastery", Versatility = "versatility", V = "versatility",
    SP = "spellpower", SpellPower = "spellpower", SpellDamage = "spellpower", Heal = "healing", Healing = "healing", Hit = "hit", AP = "ap",
    AttackPower = "ap", RAP = "rap", RangedAP = "rap", MP5 = "mp5", ManaRegen = "mp5", Str = "strength", Strength = "strength", Agi = "agility",
    Agility = "agility", Int = "intellect", Intellect = "intellect", Spi = "spirit", Spirit = "spirit", Stam = "stamina", Stamina = "stamina",
    Def = "defense", Defense = "defense", Dodge = "dodge", Parry = "parry", Block = "block", BlockVal = "blockval", BlockValue = "blockval",
    Arm = "armor", Armor = "armor", ArP = "arp", ArmorPenetration = "arp", Exp = "exp", Expertise = "exp",
}

local statBgColors = setmetatable({
    none = { 0.12, 0.12, 0.12, 0.9 },
    None = { 0.12, 0.12, 0.12, 0.9 },
}, {
    __index = function(_, k)
        local colors = sfui.config and sfui.config.stat_colors or STAT_COLORS
        local statKey = statKeyMap[k]
        return statKey and colors[statKey]
    end,
})

-- Unified PvE / PvP lock colors (used for labels, buttons, tooltips)
local PVE_COLOR  = { 0.45, 0.65, 1.0 }
local PVP_COLOR  = { 1.0, 0.4, 0.4 }
local BOTH_COLOR = { 0.72, 0.52, 1.0 }

sfui.gear.TANK_SPECS = sfui.gear.TANK_SPECS or {}

local claimedItemIDs   = {}
local columnOccupied   = {}
local pawnOrderScratch = {}
local curOrderScratch  = {}

local function updateIconRow(icons, lockTbl, forPvP, specID)
    if not icons then return end

    wipe(claimedItemIDs)
    wipe(columnOccupied)

    for i = 1, #icons do
        icons[i]:Hide()
        icons[i].itemID = nil
    end

    if not lockTbl then return end

    local numSpecID = tonumber(specID or (icons and icons.specID)) or 0
    local isVanilla = not sfui.isRetail
        or (numSpecID >= 1482 and numSpecID <= 1491)
        or (sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(numSpecID))
    local usesAmmo = sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
    local slotOrder
    if isVanilla then
        if usesAmmo then
            slotOrder = { 13, 14, 11, 12, 2, 16, 17, 18, 0 }
        else
            slotOrder = { 13, 14, 11, 12, 2, 16, 17, 18 }
        end
    else
        slotOrder = { 13, 14, 11, 12, 2, 16, 17 }
    end

    for colIdx, slotID in ipairs(slotOrder) do
        local link = GetInventoryItemLink("player", slotID)
        if link then
            local itemID = GetItemInfoInstant(link)
            if itemID and lockTbl[itemID] then
                local ico = icons[colIdx]
                if ico then
                    local nativeIcon = select(5, GetItemInfoInstant(link))
                    local tex = nativeIcon or
                        ((_G.C_Item and _G.C_Item.GetItemIconByID) and _G.C_Item.GetItemIconByID(itemID)) or
                        (_G.GetItemIcon and _G.GetItemIcon(itemID))
                    ico.tex:SetTexture(tex)
                    ico.itemID = itemID
                    ico:Show()

                    claimedItemIDs[itemID] = true
                    columnOccupied[colIdx] = true
                end
            end
        end
    end

    local function getSlotCategory(slotID)
        if slotID == 13 or slotID == 14 then return "TRINKET"
        elseif slotID == 11 or slotID == 12 then return "FINGER"
        elseif slotID == 2 then return "NECK"
        elseif slotID == 16 then return "MAINHAND"
        elseif slotID == 17 then return "OFFHAND"
        elseif slotID == 18 then return "RANGED"
        elseif slotID == 0 then return "AMMO"
        end
        return "UNKNOWN"
    end

    local function matchesSlotCategory(equipLoc, category)
        if category == "TRINKET" then return equipLoc == "INVTYPE_TRINKET"
        elseif category == "FINGER" then return equipLoc == "INVTYPE_FINGER"
        elseif category == "NECK" then return equipLoc == "INVTYPE_NECK"
        elseif category == "MAINHAND" then
            return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
                or equipLoc == "INVTYPE_2HWEAPON" or (not isVanilla and (equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"))
        elseif category == "OFFHAND" then
            return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE"
        elseif category == "RANGED" then
            return equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" or equipLoc == "INVTYPE_RELIC"
        elseif category == "AMMO" then
            return equipLoc == "INVTYPE_AMMO"
        end
        return false
    end

    for lockedID in pairs(lockTbl) do
        if not claimedItemIDs[lockedID] then
            local _, _, _, equipLoc, nativeIcon = GetItemInfoInstant(lockedID)
            if equipLoc then
                for colIdx, slotID in ipairs(slotOrder) do
                    if not columnOccupied[colIdx] then
                        local category = getSlotCategory(slotID)
                        if matchesSlotCategory(equipLoc, category) then
                            local ico = icons[colIdx]
                            if ico then
                                local tex = nativeIcon or
                                    ((_G.C_Item and _G.C_Item.GetItemIconByID) and _G.C_Item.GetItemIconByID(lockedID)) or
                                    (_G.GetItemIcon and _G.GetItemIcon(lockedID))
                                ico.tex:SetTexture(tex)
                                ico.itemID = lockedID
                                ico:Show()

                                claimedItemIDs[lockedID] = true
                                columnOccupied[colIdx] = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function resolveStatOrder(specID, db, pool, isTank)
    local numStats = #pool
    local weights = db and db.pawn_weights
    if weights and next(weights) then
        local m = 0
        for stat, w in pairs(weights) do
            m = m + 1
            local entry = pawnScratchList[m]
            if not entry then
                entry = { stat = "", weight = 0 }
                pawnScratchList[m] = entry
            end
            entry.stat = stat
            entry.weight = w
        end
        for i = m + 1, #pawnScratchList do
            pawnScratchList[i] = nil
        end
        table.sort(pawnScratchList, pawnSortDesc)
        wipe(curOrderScratch)
        for i = 1, numStats do
            curOrderScratch[i] = pawnScratchList[i] and pawnScratchList[i].stat or pool[i] or "none"
        end
        return curOrderScratch
    end

    local rawOrder = db and db.stat_order
    if sfui.gear.SanitizeStatOrder then
        return sfui.gear.SanitizeStatOrder(specID, rawOrder, pool, isTank)
    end
    wipe(curOrderScratch)
    for i = 1, numStats do
        curOrderScratch[i] = rawOrder and rawOrder[i] or pool[i] or "none"
    end
    return curOrderScratch
end
sfui.gear.GetResolvedStatOrder = resolveStatOrder

-- -------------------------------------------------------------------------
-- UPDATE STAT UI
-- -------------------------------------------------------------------------
function sfui.gear.UpdateStatUI()
    if not SfuiGearManagerFrame or not SfuiGearManagerFrame:IsShown() then return end
    SfuiDB = SfuiDB or {}
    SfuiDB.gear = SfuiDB.gear or {}

    local autoEnabled = (sfui.gear.isAutoEquipEnabled and sfui.gear.isAutoEquipEnabled()) or false
    if SfuiGearManagerFrame.autoToggle and SfuiGearManagerFrame.autoToggle.UpdateState then
        SfuiGearManagerFrame.autoToggle:UpdateState(autoEnabled)
    end
    if SfuiGearManagerFrame.enableChk and SfuiGearManagerFrame.enableChk.SetChecked then
        SfuiGearManagerFrame.enableChk:SetChecked(autoEnabled)
    end

    -- Header Status label: shows active gear mode
    if SfuiGearManagerFrame.statusLabel then
        local lbl = SfuiGearManagerFrame.statusLabel
        local isNaked = (sfui.gear.isNakedPaused and sfui.gear.isNakedPaused())
        if isNaked then
            lbl:SetText("naked (auto-equip paused)")
            lbl:SetTextColor(1.0, 0.65, 0.2)
        else
            local spec = common.get_current_spec_id()
            local db = spec and spec ~= 0 and SfuiDB.gear and SfuiDB.gear[spec]
            local _, instanceType = GetInstanceInfo()
            local isPvP = sfui.gear.isCurrentlyPvP and sfui.gear.isCurrentlyPvP()
            local targetSet = nil
            if db then
                if instanceType == "pvp" or instanceType == "arena" then
                    targetSet = db.pvp_set
                elseif instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "delve" then
                    targetSet = db.pve_set
                elseif instanceType == "none" then
                    targetSet = isPvP and db.pvp_set or db.pve_set
                end
            end

            local text, r, g, b
            if targetSet and targetSet ~= "" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID then
                local setID = C_EquipmentSet.GetEquipmentSetID(targetSet)
                local isEquipped = setID and select(4, C_EquipmentSet.GetEquipmentSetInfo(setID))
                local checkmark = isEquipped and " \xE2\x9C\x93" or ""
                text = (isPvP and "pvp" or "pve") .. ": " .. targetSet:lower() .. checkmark
                local baseColor = isPvP and PVP_COLOR or PVE_COLOR
                r, g, b = isEquipped and 0 or baseColor[1], isEquipped and 1 or baseColor[2], isEquipped and 1 or baseColor[3]
            else
                text = isPvP and "pvp" or "pve"
                r, g, b = 0.55, 0.55, 0.55
            end

            lbl:SetText(text:lower())
            lbl:SetTextColor(r, g, b)
        end
    end

    -- Refresh UI for the active spec card
    local specID = SfuiGearManagerFrame.activeSpecID or common.get_current_spec_id()
    if specID and SfuiGearManagerFrame.specUIs and SfuiGearManagerFrame.specUIs[specID] then
        local ui = SfuiGearManagerFrame.specUIs[specID]
        local db = SfuiDB.gear[specID] or {}

        if ui.pveDrop and ui.pveDrop.SetSelectedValue then ui.pveDrop:SetSelectedValue(db.pve_set or "") end
        if ui.pvpDrop and ui.pvpDrop.SetSelectedValue then ui.pvpDrop:SetSelectedValue(db.pvp_set or "") end

        updateIconRow(ui.pveLockIcons, db.locked_items_pve, false, specID)
        updateIconRow(ui.pvpLockIcons, db.locked_items_pvp, true, specID)

        if ui.lockBtns then
            for _, entry in ipairs(ui.lockBtns) do
                local link = GetInventoryItemLink("player", entry.slotID)
                local iid = link and GetItemInfoInstant(link)
                local pveL = iid and db.locked_items_pve and db.locked_items_pve[iid]
                local pvpL = iid and db.locked_items_pvp and db.locked_items_pvp[iid]
                local btn = entry.btn

                if pveL and pvpL then
                    btn.lockColor = BOTH_COLOR
                    btn:SetBackdropBorderColor(BOTH_COLOR[1], BOTH_COLOR[2], BOTH_COLOR[3], 1.0)
                    btn:SetBackdropColor(BOTH_COLOR[1] * 0.28, BOTH_COLOR[2] * 0.28, BOTH_COLOR[3] * 0.28, 0.95)
                elseif pveL then
                    btn.lockColor = PVE_COLOR
                    btn:SetBackdropBorderColor(PVE_COLOR[1], PVE_COLOR[2], PVE_COLOR[3], 1.0)
                    btn:SetBackdropColor(PVE_COLOR[1] * 0.28, PVE_COLOR[2] * 0.28, PVE_COLOR[3] * 0.28, 0.95)
                elseif pvpL then
                    btn.lockColor = PVP_COLOR
                    btn:SetBackdropBorderColor(PVP_COLOR[1], PVP_COLOR[2], PVP_COLOR[3], 1.0)
                    btn:SetBackdropColor(PVP_COLOR[1] * 0.28, PVP_COLOR[2] * 0.28, PVP_COLOR[3] * 0.28, 0.95)
                else
                    btn.lockColor = nil
                    btn:SetBackdropBorderColor(0, 0, 0, 1)
                    btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                end
            end
        end

        -- Delegate platform-specific UI updates (Retail tier buttons / Classic role & naked buttons)
        if sfui.gear.UpdateFlavorUI then
            sfui.gear.UpdateFlavorUI(ui, specID, db)
        end

        -- Row 3: Stat priority buttons & pawn weight editboxes
        if ui.statBtns then
            local isTank = (sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(specID, db)) or false
            local role = (db and db.classic_role) or (sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(specID, db))
            local pool = (sfui.gear.GetStatPool and sfui.gear.GetStatPool(specID, isTank, role)) or { "Crit", "Haste", "Mastery", "Versatility" }
            local numStats = #pool
            local currentOrder = resolveStatOrder(specID, db, pool, isTank)

            for j = 1, numStats do
                local sBtn = ui.statBtns[j]
                if sBtn then
                    local s = currentOrder and currentOrder[j]
                    if s then
                        local abbr = statAbbrv[s] or s:sub(1, 4):lower()
                        sBtn:SetText(abbr)
                        local bgCol = statBgColors[s] or statBgColors.none
                        sBtn:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], 0.85)
                    end
                end
            end
        end

        if ui.pawnEdit and not ui.pawnEdit:HasFocus() then
            ui.pawnEdit:SetText(db.pawn_string or "")
        end
    end
end

-- -------------------------------------------------------------------------
-- GEAR MANAGER MAIN WINDOW
-- -------------------------------------------------------------------------
local gearFrame = CreateFrame("Frame", "SfuiGearManagerFrame", UIParent, "BackdropTemplate")
gearFrame:SetPoint("CENTER")
gearFrame:SetMovable(true)
gearFrame:EnableMouse(true)
gearFrame:RegisterForDrag("LeftButton")
gearFrame:SetScript("OnDragStart", gearFrame.StartMoving)
gearFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left = self:GetLeft()
    local top = self:GetTop()
    if left and top then
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    SfuiDB = SfuiDB or {}
    SfuiDB.gear_pos = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs
    }
end)

local HEADER_H = GetHeaderHeight()

sfui.theme.ApplyWindowStyle(gearFrame)
sfui.theme.RegisterWindow(gearFrame, function(frame, pal)
    if frame.headerBar then
        sfui.theme.ApplyHeaderStyle(frame.headerBar, "gear manager")
    end
    if frame.closeBtn then
        sfui.theme.ApplyCloseButtonStyle(frame.closeBtn)
    end
    if frame.content then
        sfui.theme.ApplyContainerStyle(frame.content)
    end
    if frame.specUIs then
        for _, ui in pairs(frame.specUIs) do
            if ui.card then
                sfui.theme.ApplyCardStyle(ui.card)
            end
            if ui.pawnEdit then
                sfui.theme.ApplyInputStyle(ui.pawnEdit)
            end
        end
    end
    if sfui.gear.UpdateFlavorUI and frame.activeSpecID and frame.specUIs and frame.specUIs[frame.activeSpecID] then
        sfui.gear.UpdateFlavorUI(frame.specUIs[frame.activeSpecID], frame.activeSpecID, SfuiDB.gear and SfuiDB.gear[frame.activeSpecID])
    end
    sfui.gear.UpdateStatUI()
end)
gearFrame:Hide()
gearFrame:SetFrameStrata("DIALOG")

-- Header Bar
gearFrame.headerBar = CreateFrame("Frame", nil, gearFrame, "BackdropTemplate")
gearFrame.headerBar:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 6, -6)
gearFrame.headerBar:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -6, -6)
gearFrame.headerBar:SetHeight(24)
sfui.theme.ApplyHeaderStyle(gearFrame.headerBar, "gear manager")
gearFrame.title = gearFrame.headerBar.title

-- Close & Collapse Buttons
local closeBtn = common.create_close_button(gearFrame, function() gearFrame:Hide() end, 22)
closeBtn:ClearAllPoints()
closeBtn:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -4, -4)
closeBtn:SetFrameLevel(gearFrame.headerBar:GetFrameLevel() + 5)
gearFrame.closeBtn = closeBtn

local collapseBtn = common.create_flat_button(gearFrame, "-", 18, 18)
collapseBtn:ClearAllPoints()
collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
collapseBtn:SetFrameLevel(closeBtn:GetFrameLevel())
gearFrame.collapseBtn = collapseBtn

collapseBtn:SetScript("OnClick", function()
    local left = gearFrame:GetLeft()
    local top = gearFrame:GetTop()
    if left and top then
        gearFrame:ClearAllPoints()
        gearFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    gearFrame.collapsed = not gearFrame.collapsed
    SfuiDB = SfuiDB or {}
    SfuiDB.gear_collapsed = gearFrame.collapsed

    local curHeaderH = GetHeaderHeight()
    if gearFrame.collapsed then
        collapseBtn:SetText("+")
        if gearFrame.content then gearFrame.content:Hide() end
        gearFrame:SetHeight(curHeaderH)
    else
        collapseBtn:SetText("-")
        if gearFrame.content then gearFrame.content:Show() end
        gearFrame:SetHeight(gearFrame.expandedHeight or (curHeaderH + 140))
    end
end)

-- Main content container
gearFrame.content = CreateFrame("Frame", nil, gearFrame, "BackdropTemplate")
gearFrame.content:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 8, -HEADER_H)
gearFrame.content:SetPoint("BOTTOMRIGHT", gearFrame, "BOTTOMRIGHT", -8, 8)
gearFrame.content:SetFrameLevel(gearFrame:GetFrameLevel() + 3)
gearFrame.content:Show()
sfui.theme.ApplyContainerStyle(gearFrame.content)

-- UI Helpers
local function makeEditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    eb:SetNumeric(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    sfui.theme.ApplyInputStyle(eb)
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return eb
end

local function mkLabel(parent, txt, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(txt and tostring(txt):lower() or "")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(r or 0.65, g or 0.60, b or 0.50)
    return fs
end

-- Row 1: Action Buttons & Toggle (Parented to content, right-aligned)
local autoToggle = common.create_flat_button(gearFrame.content, "auto: off", 72, 20)
autoToggle:SetPoint("TOPRIGHT", gearFrame.content, "TOPRIGHT", -10, -6)
autoToggle:SetFrameLevel(gearFrame.content:GetFrameLevel() + 5)
function autoToggle:UpdateState(enabled)
    local useAH = sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive()
    if enabled then
        self:SetText("|cff66ff66auto: on|r")
        if useAH then
            sfui.theme.SetButtonSelected(self, true)
            self:SetBackdropBorderColor(0, 0, 0, 0)
            self:SetBackdropColor(0, 0, 0, 0)
        else
            local p = sfui.theme.GetPalette()
            local acc = p and p.accentColor or { 0.95, 0.85, 0.55 }
            self:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.9)
            self:SetBackdropColor(acc[1] * 0.25, acc[2] * 0.25, acc[3] * 0.25, 0.95)
        end
    else
        self:SetText("|cff888888auto: off|r")
        if useAH then
            sfui.theme.SetButtonSelected(self, false)
            self:SetBackdropBorderColor(0, 0, 0, 0)
            self:SetBackdropColor(0, 0, 0, 0)
        else
            local isCamelot = sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
            if isCamelot then
                self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
                self:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
            else
                self:SetBackdropBorderColor(0, 0, 0, 1)
                self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            end
        end
    end
end

autoToggle:SetScript("OnClick", function()
    local newState = not sfui.gear.isAutoEquipEnabled()
    sfui.gear.setAutoEquipEnabled(newState)
    autoToggle:UpdateState(newState)
    if sfui.gearOptionsCheckbox and sfui.gearOptionsCheckbox.SetChecked then
        sfui.gearOptionsCheckbox:SetChecked(newState)
    end
    if newState then sfui.gear.Update() end
    sfui.gear.UpdateStatUI()
end)
autoToggle:SetScript("OnEnter", function(b)
    if sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
        if b._sfuiAHHighlight then b._sfuiAHHighlight:Show() end
        if b.SetBackdropBorderColor then b:SetBackdropBorderColor(0, 0, 0, 0) end
        if b.SetBackdropColor then b:SetBackdropColor(0, 0, 0, 0) end
    else
        local p = sfui.theme.GetPalette()
        local hl = (p and p.highlightColor) or (cfg and cfg.colors and cfg.colors.cyan) or { 0, 1, 1 }
        b:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
    end
    show_tooltip(b, "ANCHOR_TOP", "auto-equip gear", {
        { "automatically equips highest ilvl gear or your designated equipment set upon spec / zone changes.", 0.8, 0.8, 0.8, true }
    })
end)
autoToggle:SetScript("OnLeave", function(b)
    hide_tooltip()
    if sfui.theme.IsAuctionHouseButtonActive and sfui.theme.IsAuctionHouseButtonActive() then
        if b._sfuiAHHighlight then b._sfuiAHHighlight:Hide() end
    end
    autoToggle:UpdateState(sfui.gear.isAutoEquipEnabled())
end)
gearFrame.autoToggle = autoToggle
gearFrame.enableChk = autoToggle

gearFrame.highPvP = common.create_flat_button(gearFrame.content, "pvp", 34, 20)
gearFrame.highPvP:SetPoint("RIGHT", autoToggle, "LEFT", -6, 0)
gearFrame.highPvP:SetFrameLevel(gearFrame.content:GetFrameLevel() + 5)
gearFrame.highPvP:SetScript("OnClick", function()
    if sfui.gear.SetNakedPaused then sfui.gear.SetNakedPaused(false, true) end
    if sfui.gear.pauseAutoEquip then sfui.gear.pauseAutoEquip(0) end
    if sfui.highest then
        sfui.highest.ClearValidationCache()
        sfui.highest.ClearCache()
        sfui.highest.EquipHighestILvl(true)
    end
end)
gearFrame.highPvP:SetScript("OnEnter", function(b)
    show_tooltip(b, "ANCHOR_TOP", "equip highest ilvl pvp gear")
end)
gearFrame.highPvP:SetScript("OnLeave", function() hide_tooltip() end)

gearFrame.highPvE = common.create_flat_button(gearFrame.content, "pve", 34, 20)
gearFrame.highPvE:SetPoint("RIGHT", gearFrame.highPvP, "LEFT", -4, 0)
gearFrame.highPvE:SetFrameLevel(gearFrame.content:GetFrameLevel() + 5)
gearFrame.highPvE:SetScript("OnClick", function()
    if sfui.gear.SetNakedPaused then sfui.gear.SetNakedPaused(false, true) end
    if sfui.gear.pauseAutoEquip then sfui.gear.pauseAutoEquip(0) end
    if sfui.highest then
        sfui.highest.ClearValidationCache()
        sfui.highest.ClearCache()
        sfui.highest.EquipHighestILvl(false)
    end
end)
gearFrame.highPvE:SetScript("OnEnter", function(b)
    show_tooltip(b, "ANCHOR_TOP", "equip highest ilvl pve gear")
end)
gearFrame.highPvE:SetScript("OnLeave", function() hide_tooltip() end)

gearFrame.statusLabel = gearFrame.headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearFrame.statusLabel:SetPoint("LEFT", gearFrame.headerBar, "LEFT", 110, 0)
gearFrame.statusLabel:SetPoint("RIGHT", gearFrame.collapseBtn, "LEFT", -8, 0)
gearFrame.statusLabel:SetJustifyH("RIGHT")
gearFrame.statusLabel:SetShadowOffset(0, 0)
gearFrame.statusLabel:SetText("")

-- -------------------------------------------------------------------------
-- ON SHOW: BUILD CARDS & SPEC NAVIGATION
-- -------------------------------------------------------------------------
gearFrame:SetScript("OnShow", function(self)
    if not self.posLoaded then
        self.posLoaded = true
        if SfuiDB.gear_pos then
            self:ClearAllPoints()
            self:SetPoint(SfuiDB.gear_pos.point, UIParent, SfuiDB.gear_pos.relativePoint, SfuiDB.gear_pos.x, SfuiDB.gear_pos.y)
            if SfuiDB.gear_pos.point ~= "TOPLEFT" then
                local left = self:GetLeft()
                local top = self:GetTop()
                if left and top then
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                end
            end
        end
    end
    if self.initialized then
        if self.SelectSpecTab then
            local specId = common.get_current_spec_id()
            if specId and specId > 0 then self:SelectSpecTab(specId) end
        end
        sfui.gear.UpdateStatUI()
        return
    end
    self.initialized = true
    self.specUIs = {}

    local _, specIDs = common.get_player_specs()
    specIDs = specIDs or {}

    local curHeaderH = GetHeaderHeight()
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -curHeaderH)
    self.content:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -8, 8)

    local isVanillaSpec = not sfui.isRetail
    local CARD_H = isVanillaSpec and 168 or 140
    self.expandedHeight = curHeaderH + CARD_H + 8

    if SfuiDB and SfuiDB.gear_collapsed ~= nil then
        self.collapsed = SfuiDB.gear_collapsed
    end

    if self.collapsed then
        collapseBtn:SetText("+")
        if self.content then self.content:Hide() end
        self:SetSize(496, curHeaderH)
    else
        collapseBtn:SetText("-")
        if self.content then self.content:Show() end
        self:SetSize(496, self.expandedHeight)
    end

    self.SelectSpecTab = function(f, specID)
        f.activeSpecID = specID
        local isVan = not sfui.isRetail
        local cardH = isVan and 168 or 140
        f.expandedHeight = GetHeaderHeight() + cardH + 8
        if not f.collapsed then
            f:SetHeight(f.expandedHeight)
        end
        for id, ui in pairs(f.specUIs) do
            if id == specID then
                if ui.card then ui.card:Show() end
            else
                if ui.card then ui.card:Hide() end
            end
        end
        if sfui.gear.UpdateFlavorUI and f.specUIs[specID] then
            sfui.gear.UpdateFlavorUI(f.specUIs[specID], specID, SfuiDB.gear and SfuiDB.gear[specID])
        end
        sfui.gear.UpdateStatUI()
    end

    -- Setup Retail Header Spec Tabs if available
    if sfui.gear.SetupHeaderTabs then
        sfui.gear.SetupHeaderTabs(self, specIDs)
    end

    local function createLockIcon(parent, specID, forPvP)
        local ico = CreateFrame("Button", nil, parent)
        ico:SetSize(22, 22)
        ico.specID = specID
        ico.forPvP = forPvP
        local t = ico:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ico.tex = t

        ico:SetScript("OnEnter", function(b)
            if b.itemID then
                local col = forPvP and PVP_COLOR or PVE_COLOR
                local tag = forPvP and "[pvp locked] " or "[pve locked] "
                local extra = {
                    { tag .. "this item is locked and will not be swapped out.", col[1], col[2], col[3] },
                    { "click to unlock this item.", 0.8, 0.8, 0.8 },
                }
                show_item_tooltip(b, b.itemID, "ANCHOR_TOP", extra)
            end
        end)
        ico:SetScript("OnLeave", function() hide_tooltip() end)
        ico:SetScript("OnClick", function(b)
            if b.itemID then
                SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
                local db = SfuiDB.gear[specID]
                local lockKey = forPvP and "locked_items_pvp" or "locked_items_pve"
                if db[lockKey] then
                    db[lockKey][b.itemID] = nil
                end
                hide_tooltip()
                sfui.gear.UpdateStatUI()
                sfui.gear.Update()
            end
        end)
        return ico
    end

    for _, id in ipairs(specIDs or {}) do
        self.specUIs[id] = {}
        local ui = self.specUIs[id]

        local card = CreateFrame("Frame", nil, self.content)
        card:SetAllPoints(self.content)
        card:SetFrameLevel(self.content:GetFrameLevel() + 1)
        ui.card = card

        -- ROW 1: pve / pvp set dropdowns (quick equip buttons are anchored to content at TOPRIGHT)
        local pveTag = mkLabel(card, "pve set:", 0.82, 0.72, 0.52)
        pveTag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -11)

        local pveDrop = common.create_dropdown(card, 96, sfui.gear.GetEquipmentSetOptions, function(val)
            SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
            SfuiDB.gear[id].pve_set = val
            sfui.gear.Update()
            sfui.gear.UpdateStatUI()
        end, "")
        pveDrop:SetPoint("TOPLEFT", card, "TOPLEFT", 58, -6)
        ui.pveDrop = pveDrop

        local pvpTag = mkLabel(card, "pvp set:", 0.95, 0.55, 0.55)
        pvpTag:SetPoint("TOPLEFT", card, "TOPLEFT", 166, -11)

        local pvpDrop = common.create_dropdown(card, 96, sfui.gear.GetEquipmentSetOptions, function(val)
            SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
            SfuiDB.gear[id].pvp_set = val
            sfui.gear.Update()
            sfui.gear.UpdateStatUI()
        end, "")
        pvpDrop:SetPoint("TOPLEFT", card, "TOPLEFT", 214, -6)
        ui.pvpDrop = pvpDrop

        -- ROW 2: Lock Slots & Modifiers
        local lockSlots
        if sfui.gear.GetLockSlots then
            lockSlots = sfui.gear.GetLockSlots(id)
        else
            lockSlots = {
                { label = "t1", slot = 13 },
                { label = "t2", slot = 14 },
                { label = "r1", slot = 11 },
                { label = "r2", slot = 12 },
                { label = "nk", slot = 2 },
                { label = "w1", slot = 16 },
                { label = "w2", slot = 17 },
            }
        end

        local pveLockLabel = mkLabel(card, "pve:", PVE_COLOR[1] * 0.8, PVE_COLOR[2] * 0.8, PVE_COLOR[3] * 0.8)
        pveLockLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -36)

        local lockLabel = mkLabel(card, "lock:", 0.65, 0.60, 0.50)
        lockLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -61)

        local pvpLockLabel = mkLabel(card, "pvp:", PVP_COLOR[1] * 0.8, PVP_COLOR[2] * 0.8, PVP_COLOR[3] * 0.8)
        pvpLockLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -84)

        local function lockSlot(slot, forPvP)
            local link = GetInventoryItemLink("player", slot)
            if link then
                local itemID = GetItemInfoInstant(link)
                if itemID then
                    SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                    local ldb = SfuiDB.gear[id]
                    ldb.locked_items_pve = ldb.locked_items_pve or {}
                    ldb.locked_items_pvp = ldb.locked_items_pvp or {}
                    local key = forPvP and "locked_items_pvp" or "locked_items_pve"
                    if ldb[key][itemID] then
                        ldb[key][itemID] = nil
                    else
                        ldb[key][itemID] = true
                    end
                    sfui.gear.UpdateStatUI()
                    sfui.gear.Update()
                end
            end
        end

        ui.lockBtns = {}
        ui.pveLockIcons = {}
        ui.pvpLockIcons = {}
        ui.pveLockIcons.specID = id
        ui.pvpLockIcons.specID = id

        local curLockX = 46
        for _, def in ipairs(lockSlots) do
            local pveIco = createLockIcon(card, id, false)
            pveIco:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX + 1, -32)
            pveIco:Hide()
            table.insert(ui.pveLockIcons, pveIco)

            local btn = common.create_flat_button(card, def.label, 24, 20)
            btn:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX, -57)
            local capturedSlot = def.slot
            btn:SetScript("OnClick", function() lockSlot(capturedSlot, IsShiftKeyDown()) end)
            btn:SetScript("OnEnter", function(b)
                local link = GetInventoryItemLink("player", capturedSlot)
                if link then
                    local itemName = GetItemInfo(link)
                    local iid = GetItemInfoInstant(link)
                    local sdb = SfuiDB and SfuiDB.gear and SfuiDB.gear[id]
                    local pveL = iid and sdb and sdb.locked_items_pve and sdb.locked_items_pve[iid]
                    local pvpL = iid and sdb and sdb.locked_items_pvp and sdb.locked_items_pvp[iid]
                    local tag = ""
                    if pveL and pvpL then
                        tag = string.format("|cff%02x%02x%02x[pve+pvp]|r ", BOTH_COLOR[1] * 255, BOTH_COLOR[2] * 255, BOTH_COLOR[3] * 255)
                    elseif pveL then
                        tag = string.format("|cff%02x%02x%02x[pve]|r ", PVE_COLOR[1] * 255, PVE_COLOR[2] * 255, PVE_COLOR[3] * 255)
                    elseif pvpL then
                        tag = string.format("|cff%02x%02x%02x[pvp]|r ", PVP_COLOR[1] * 255, PVP_COLOR[2] * 255, PVP_COLOR[3] * 255)
                    end
                    show_tooltip(b, "ANCHOR_TOP", tag .. (itemName and itemName:lower() or link or ""), {
                        { "click = toggle pve lock",       PVE_COLOR[1], PVE_COLOR[2], PVE_COLOR[3] },
                        { "shift+click = toggle pvp lock", PVP_COLOR[1], PVP_COLOR[2], PVP_COLOR[3] },
                    })
                else
                    show_tooltip(b, "ANCHOR_TOP", "nothing equipped in " .. def.label, {
                        { "equip an item to toggle its lock state.", 0.6, 0.6, 0.6 }
                    })
                end
            end)
            btn:SetScript("OnLeave", function() hide_tooltip() end)
            table.insert(ui.lockBtns, { btn = btn, slotID = def.slot })

            local pvpIco = createLockIcon(card, id, true)
            pvpIco:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX + 1, -80)
            pvpIco:Hide()
            table.insert(ui.pvpLockIcons, pvpIco)

            curLockX = curLockX + 27
        end

        -- Delegate BuildCardModifiers to Retail (tier buttons) or Classic (role buttons)
        if sfui.gear.BuildCardModifiers then
            sfui.gear.BuildCardModifiers(card, ui, id, curLockX)
        end

        -- ROW 3: Stat Priorities & Pawn Weights
        local R3Y = -112
        local targetDB = SfuiDB.gear[id] or {}
        local isTank = (sfui.gear.IsTankSpec and sfui.gear.IsTankSpec(id, targetDB)) or false
        local role = (targetDB and targetDB.classic_role) or (sfui.gear.GetClassicRole and sfui.gear.GetClassicRole(id, targetDB))
        local pool = (sfui.gear.GetStatPool and sfui.gear.GetStatPool(id, isTank, role)) or { "Crit", "Haste", "Mastery", "Versatility" }
        local numStats = #pool

        local statTag = mkLabel(card, "stats:", 0.65, 0.60, 0.50)
        statTag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, R3Y - 4)

        local statBtnW, sepW, sepGap = 32, 10, 2
        local startX = 46

        local function getResolvedStatOrder()
            return resolveStatOrder(id, targetDB, pool, isTank)
        end

        ui.statBtns = {}
        local resolvedOrder = getResolvedStatOrder()

        for j = 1, numStats do
            local s = resolvedOrder[j]
            local abbr = statAbbrv[s] or (s and s:sub(1, 4):lower()) or "none"
            local sBtn = common.create_flat_button(card, abbr, statBtnW, 20)
            local btnAnchor = (j == 1) and statTag or ui.statBtns[j - 1]
            local btnAnchorPoint = (j == 1) and "LEFT" or "RIGHT"
            local gap = (j == 1) and (startX - 10) or (sepW + sepGap * 2)

            sBtn:SetPoint("LEFT", btnAnchor, btnAnchorPoint, gap, 0)
            sBtn:SetPoint("TOP", card, "TOP", 0, R3Y)

            local bgCol = statBgColors[s] or statBgColors.none
            sBtn:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], 0.85)
            sBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local capturedIndex = j
            sBtn:SetScript("OnClick", function(self, button)
                SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                local ldb = SfuiDB.gear[id]
                ldb.stat_order = ldb.stat_order or {}
                for idx = 1, numStats do
                    if not ldb.stat_order[idx] then ldb.stat_order[idx] = resolvedOrder[idx] end
                end
                local currentList = ldb.stat_order
                if button == "LeftButton" then
                    if capturedIndex > 1 then
                        local temp = currentList[capturedIndex]
                        currentList[capturedIndex] = currentList[capturedIndex - 1]
                        currentList[capturedIndex - 1] = temp
                    end
                elseif button == "RightButton" then
                    if capturedIndex < numStats then
                        local temp = currentList[capturedIndex]
                        currentList[capturedIndex] = currentList[capturedIndex + 1]
                        currentList[capturedIndex + 1] = temp
                    end
                end
                ldb.pawn_weights = nil
                ldb.pawn_string = nil
                sfui.gear.UpdateStatUI()
                sfui.gear.Update()
            end)

            sBtn:SetScript("OnEnter", function(b)
                local currentList = getResolvedStatOrder()
                local full = statFullName[currentList[capturedIndex]] or currentList[capturedIndex]
                show_tooltip(b, "ANCHOR_TOP", full, {
                    { "left-click: move left (higher priority)",  0.8, 0.8, 0.8 },
                    { "right-click: move right (lower priority)", 0.8, 0.8, 0.8 },
                })
            end)
            sBtn:SetScript("OnLeave", function() hide_tooltip() end)
            ui.statBtns[j] = sBtn

            if j < numStats then
                local sep = common.create_flat_button(card, ">", sepW, 20)
                local fs = (sep.text and sep.text.SetTextColor and sep.text) or (sep.GetFontString and sep:GetFontString())
                if fs and fs.SetTextColor then fs:SetTextColor(0.8, 0.8, 0.8) end
                sep:SetPoint("LEFT", btnAnchor, "RIGHT", sepGap, 0)
                sep:SetPoint("TOP", card, "TOP", 0, R3Y)
                sep:EnableMouse(false)
            end
        end

        local pawnTag = mkLabel(card, "pawn:", 0.65, 0.60, 0.50)
        pawnTag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, R3Y - 26)

        local pawnEdit = makeEditBox(card, 300, 20)
        pawnEdit:SetPoint("LEFT", pawnTag, "RIGHT", 6, 0)
        pawnEdit:SetPoint("TOP", card, "TOP", 0, R3Y - 24)
        pawnEdit:SetText(targetDB.pawn_string or "")
        pawnEdit:SetScript("OnEnterPressed", function(eb)
            eb:ClearFocus()
            local text = eb:GetText():trim()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            local weights = {}
            for stat, val in text:gmatch('(%a+)%s*=%s*([%d%.]+)') do
                local num = tonumber(val)
                if num and num > 0 then weights[stat] = num end
            end
            SfuiDB.gear[id].pawn_weights = next(weights) and weights or nil
            SfuiDB.gear[id].pawn_string = (next(weights) and text ~= "") and text or nil
            local specName = common.get_spec_name(id) or ("spec " .. tostring(id))
            sfui.common.print("pawn saved for " .. specName)
            sfui.gear.UpdateStatUI()
        end)
        ui.pawnEdit = pawnEdit
    end

    local activeSpecId = common.get_current_spec_id() or (specIDs and specIDs[1])
    if activeSpecId and self.SelectSpecTab then
        self:SelectSpecTab(activeSpecId)
    end
end)

function sfui.gear.toggle()
    if not SfuiGearManagerFrame then return end
    if SfuiGearManagerFrame:IsShown() then
        SfuiGearManagerFrame:Hide()
    else
        SfuiGearManagerFrame:Show()
    end
end
