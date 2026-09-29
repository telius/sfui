local addonName, addon = ...
sfui.gear = sfui.gear or {}

local cfg = sfui.config
local common = sfui.common
local _G = _G
local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local C_EquipmentSet = _G.C_EquipmentSet
local GetInstanceInfo = _G.GetInstanceInfo
local C_PvP = _G.C_PvP
local C_Timer = _G.C_Timer
local UIParent = _G.UIParent
local CharacterFrame = _G.CharacterFrame
local CharacterFrameCloseButton = _G.CharacterFrameCloseButton
local print = _G.print
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
local GetItemInfoInstant = (_G.C_Item and _G.C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant or
(sfui.common and sfui.common.get_item_id)
local GetItemInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
local IsShiftKeyDown = _G.IsShiftKeyDown

local function isWarModeDesired()
    return (C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()) or false
end

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



local gearEquipQueue = nil
-- P1: debounce BAG_UPDATE_DELAYED so rapid bag changes don't fire full scans repeatedly
local bagUpdatePending = false
local zoneUpdateQueue = false
-- Guard: prevents stacking C_Timer.After(Update) calls during prolonged casts
local updateScheduled = false
-- Counter: caps PLAYER_REGEN_ENABLED retry depth after combat
local regenRetries = 0

-- Manual-edit protection: suppress BAG_UPDATE auto-equip while player is managing gear
local manualEditUntil = 0
local GetTime = _G.GetTime

--- Call this to pause automatic equipping from bag changes for `sec` seconds (default 60).
--- Opening the CharacterFrame also triggers this automatically.
sfui.gear.pauseAutoEquip = function(sec)
    manualEditUntil = GetTime() + (sec or 10)
end

local function autoEquipPaused()
    return GetTime() < manualEditUntil or (CharacterFrame and CharacterFrame:IsShown() == true)
end

local function isCurrentlyPvP()
    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()
    return (instanceType == "pvp" or instanceType == "arena")
        or (instanceType == "none" and isWarMode)
end

local function isClassicOrVanilla()
    if sfui.isForever or sfui.isClassic or sfui.isEra then return true end
    if sfui.compat and (sfui.compat.is_classic or sfui.compat.is_wow_forever or sfui.compat.is_classic_era) then return true end
    if sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail) then return true end
    local spec = (common and common.get_specialization and common.get_specialization()) or
    (_G.GetSpecialization and _G.GetSpecialization())
    local numSpec = tonumber(spec)
    if numSpec and numSpec >= 1482 and numSpec <= 1491 then return true end
    return false
end
sfui.gear.isClassicOrVanilla = isClassicOrVanilla

-- Returns true if the correct gear set for the current zone/spec is already equipped,
-- meaning EquipHighestILvl must NOT override it.
local function isGearSetEquipped()
    if not SfuiDB or not SfuiDB.gear then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then return false end
    local spec = common and common.get_current_spec_id and common.get_current_spec_id()
    if not spec or spec == 0 then return false end
    local db = SfuiDB.gear[spec]
    if not db then return false end

    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()
    local targetSet
    if instanceType == "pvp" or instanceType == "arena" then
        targetSet = db.pvp_set
    elseif instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "delve" then
        targetSet = db.pve_set
    elseif instanceType == "none" then
        targetSet = isWarMode and db.pvp_set or db.pve_set
    end
    if not targetSet or targetSet == "" then return false end

    local setID = C_EquipmentSet.GetEquipmentSetID(targetSet)
    if not setID then return false end
    local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    return isEquipped == true
end

-- Unified auto-equip enable check.
-- Reads from the global SfuiDB.gear.auto_equip_highest toggle (set by both
-- the gear manager "Enable" checkbox and the options panel checkbox).
-- Defaults to true when nil (first-time users get auto-equip enabled).
local function isAutoEquipEnabled()
    if not SfuiDB or not SfuiDB.gear then return false end
    local v = SfuiDB.gear.auto_equip_highest
    if v == nil then return true end -- default: enabled
    return v
end

local function setAutoEquipEnabled(val)
    SfuiDB = SfuiDB or {}
    SfuiDB.gear = SfuiDB.gear or {}
    SfuiDB.gear.auto_equip_highest = val
end

local function _OnUpdateCastTimer()
    updateScheduled = false
    if sfui.gear and sfui.gear.Update then
        sfui.gear.Update()
    end
end

local function TryEquipSet(setName)
    if not setName or setName == "" then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then return false end
    local isPole = (sfui.highest and sfui.highest.IsFishingPoleEquipped and sfui.highest.IsFishingPoleEquipped())
        or (sfui.gear and sfui.gear.IsFishingPoleEquipped and sfui.gear.IsFishingPoleEquipped())
        or (sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped())
    local isSession = (sfui.fishing and sfui.fishing.IsSessionActive and sfui.fishing.IsSessionActive())
    if isPole and isSession then return false end
    local setID = C_EquipmentSet.GetEquipmentSetID(setName)
    if setID then
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if isEquipped then return false end
        if InCombatLockdown() then
            gearEquipQueue = setID
            if common and common.run_after_combat then
                common.run_after_combat(sfui.gear.handle_player_regen)
            end
            return false
        end
        if UnitCastingInfo("player") or UnitChannelInfo("player") then
            -- Defers the update; guard prevents stacking timers during casts
            if not updateScheduled then
                updateScheduled = true
                C_Timer.After(0.25, _OnUpdateCastTimer)
            end
            return false
        end
        if UnitIsDeadOrGhost("player") then
            return false
        end
        if C_EquipmentSet.UseEquipmentSet then
            C_EquipmentSet.UseEquipmentSet(setID)
        end
        if common and common.print then
            common.print("automatically equipped set: " .. (name and name:lower() or (setName and setName:lower() or "")))
        else
            print("|cff6600ffsfui:|r automatically equipped set: " ..
            (name and name:lower() or (setName and setName:lower() or "")))
        end
        return true
    end
    return false
end

-- P4: pre-allocated scratch list with 16 fixed sub-tables; reused to avoid per-call allocation
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

local DEFENSIVE_STATS           = {
    Def = true,
    Defense = true,
    Dodge = true,
    Parry = true,
    Block = true,
    Arm = true,
    Armor = true,
}

local statAbbrv                 = {
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
    Arm = "arm",
    Armor = "arm",
    arm = "arm",
}

local statFullName              = {
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
    Arm = "armor",
    Armor = "armor",
    arm = "armor",
}

local STAT_COLORS               = (sfui.config and sfui.config.stat_colors) or {
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
    armor       = { 0.55, 0.55, 0.55, 1.0 },
}

local statKeyMap                = {
    Haste = "haste",
    H = "haste",
    Crit = "crit",
    C = "crit",
    Mastery = "mastery",
    M = "mastery",
    Versatility = "versatility",
    V = "versatility",
    SP = "spellpower",
    SpellPower = "spellpower",
    SpellDamage = "spellpower",
    Heal = "healing",
    Healing = "healing",
    Hit = "hit",
    AP = "ap",
    AttackPower = "ap",
    RAP = "rap",
    RangedAP = "rap",
    MP5 = "mp5",
    ManaRegen = "mp5",
    Str = "strength",
    Strength = "strength",
    Agi = "agility",
    Agility = "agility",
    Int = "intellect",
    Intellect = "intellect",
    Spi = "spirit",
    Spirit = "spirit",
    Stam = "stamina",
    Stamina = "stamina",
    Def = "defense",
    Defense = "defense",
    Dodge = "dodge",
    Parry = "parry",
    Block = "block",
    Arm = "armor",
    Armor = "armor",
}

local statBgColors              = setmetatable({
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
local PVE_COLOR                 = { 0.45, 0.65, 1.0 } -- blue
local PVP_COLOR                 = { 1.0, 0.4, 0.4 } -- red
local BOTH_COLOR                = { 0.72, 0.52, 1.0 } -- purple

sfui.gear.TANK_SPECS            = sfui.gear.TANK_SPECS or {}

sfui.gear.CLASSIC_ROLES_BY_SPEC = {
    [1484] = { "DPS", "HEAL", "TANK" }, -- Druid
    [1486] = { "DPS", "HEAL", "TANK" }, -- Paladin
    [1487] = { "DPS", "HEAL" },         -- Priest
    [1489] = { "DPS", "HEAL" },         -- Shaman
    [1491] = { "DPS", "TANK" },         -- Warrior
}

-- Authoritative stat, role, and spec queries are provided directly by data/stats.lua & frames/gear/engine.lua

local claimedItemIDs = {}
local columnOccupied = {}
local pawnOrderScratch = {}
local curOrderScratch = {}

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
    local isVanilla = (numSpecID >= 1482 and numSpecID <= 1491)
        or (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(numSpecID))
        or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and not sfui.version.retail)
        or sfui.isClassic or sfui.isForever
    local slotOrder = isVanilla and { 13, 14, 11, 12, 2, 16, 17, 18 } or { 13, 14, 11, 12, 2, 16, 17 }

    -- Step 1: Populate currently equipped locked items in their respective columns
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

    -- Step 2: Populate remaining locked items (in bags) to empty columns of the same category
    local function getSlotCategory(slotID)
        if slotID == 13 or slotID == 14 then
            return "TRINKET"
        elseif slotID == 11 or slotID == 12 then
            return "FINGER"
        elseif slotID == 2 then
            return "NECK"
        elseif slotID == 16 then
            return "MAINHAND"
        elseif slotID == 17 then
            return "OFFHAND"
        elseif slotID == 18 then
            return "RANGED"
        end
        return "UNKNOWN"
    end

    local function matchesSlotCategory(equipLoc, category)
        if category == "TRINKET" then
            return equipLoc == "INVTYPE_TRINKET"
        elseif category == "FINGER" then
            return equipLoc == "INVTYPE_FINGER"
        elseif category == "NECK" then
            return equipLoc == "INVTYPE_NECK"
        elseif category == "MAINHAND" then
            return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
                or equipLoc == "INVTYPE_2HWEAPON" or
                (not isVanilla and (equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT"))
        elseif category == "OFFHAND" then
            return equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONOFFHAND"
                or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE"
        elseif category == "RANGED" then
            return equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" or
            equipLoc == "INVTYPE_RELIC"
        end
        return false
    end

    for lockedID in pairs(lockTbl) do
        if not claimedItemIDs[lockedID] then
            local _, _, _, equipLoc, nativeIcon = GetItemInfoInstant(lockedID)
            if equipLoc then
                -- Find an empty column that matches this category
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
                                break -- move to next locked item
                            end
                        end
                    end
                end
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- UPDATE STAT UI
-- -------------------------------------------------------------------------
function sfui.gear.UpdateStatUI()
    if not SfuiGearManagerFrame or not SfuiGearManagerFrame:IsShown() then return end
    SfuiDB = SfuiDB or {}
    SfuiDB.gear = SfuiDB.gear or {}

    local autoEnabled = isAutoEquipEnabled()
    if SfuiGearManagerFrame.autoToggle and SfuiGearManagerFrame.autoToggle.UpdateState then
        SfuiGearManagerFrame.autoToggle:UpdateState(autoEnabled)
    end
    if SfuiGearManagerFrame.enableChk and SfuiGearManagerFrame.enableChk.SetChecked then
        SfuiGearManagerFrame.enableChk:SetChecked(autoEnabled)
    elseif SfuiGearManagerFrame.maxLvlChk and SfuiGearManagerFrame.maxLvlChk.SetChecked then
        SfuiGearManagerFrame.maxLvlChk:SetChecked(autoEnabled)
    end

    -- Status label: shows what gear mode is currently active
    if SfuiGearManagerFrame.statusLabel then
        local lbl = SfuiGearManagerFrame.statusLabel
        local spec = common and common.get_current_spec_id and common.get_current_spec_id()
        local db = spec and spec ~= 0 and SfuiDB.gear and SfuiDB.gear[spec]
        local _, instanceType = GetInstanceInfo()
        local isWarMode = C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired()

        local isPvP = (instanceType == "pvp" or instanceType == "arena")
            or (instanceType == "none" and isWarMode)
        local targetSet = nil
        if db then
            if instanceType == "pvp" or instanceType == "arena" then
                targetSet = db.pvp_set
            elseif instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "delve" then
                targetSet = db.pve_set
            elseif instanceType == "none" then
                targetSet = isWarMode and db.pvp_set or db.pve_set
            end
        end

        local text, r, g, b
        if targetSet and targetSet ~= "" and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID then
            local setID = C_EquipmentSet.GetEquipmentSetID(targetSet)
            local isEquipped = setID and select(4, C_EquipmentSet.GetEquipmentSetInfo(setID))
            local checkmark = isEquipped and " \xE2\x9C\x93" or ""
            text = (isPvP and "pvp" or "pve") .. ": " .. targetSet:lower() .. checkmark
            local baseColor = isPvP and PVP_COLOR or PVE_COLOR
            r, g, b = isEquipped and 0 or baseColor[1], isEquipped and 1 or baseColor[2],
                isEquipped and 1 or baseColor[3]
        else
            text = isPvP and "pvp" or "pve"
            r, g, b = 0.55, 0.55, 0.55
        end

        lbl:SetText(text:lower())
        lbl:SetTextColor(r, g, b)
    end

    -- Refresh tab button icons and borders
    if SfuiGearManagerFrame and SfuiGearManagerFrame.tabBtns then
        local p = sfui.theme and sfui.theme.GetPalette()
        local accent = p and p.accentColor or { 0, 0.8, 1 }
        local curSpec = SfuiGearManagerFrame.activeSpecID or common.get_current_spec_id()
        for id, btn in pairs(SfuiGearManagerFrame.tabBtns) do
            if btn.tex and common and common.get_spec_icon then
                local ic = common.get_spec_icon(id)
                if ic then btn.tex:SetTexture(ic) end
            end
            if id == curSpec then
                btn:SetAlpha(1.0)
                btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0)
            else
                btn:SetAlpha(0.40)
                btn:SetBackdropBorderColor(0, 0, 0, 0.8)
            end
        end
    end

    local getSpecs = (common and common.get_player_specs) or (sfui.common and sfui.common.get_player_specs)
    local _, specIDs
    if getSpecs then
        _, specIDs = getSpecs()
    end

    for _, specID in ipairs(specIDs or {}) do
        local specID = specID
        if specID and SfuiGearManagerFrame.specUIs and SfuiGearManagerFrame.specUIs[specID] then
            local ui = SfuiGearManagerFrame.specUIs[specID]
            local db = SfuiDB.gear[specID] or {}
            SfuiDB.gear[specID] = db

            if ui.pawnEdit then ui.pawnEdit:SetText(db.pawn_string or "") end
            if ui.pveDrop and ui.pveDrop.SetSelectedValue then ui.pveDrop:SetSelectedValue(db.pve_set or "") end
            if ui.pvpDrop and ui.pvpDrop.SetSelectedValue then ui.pvpDrop:SetSelectedValue(db.pvp_set or "") end

            -- locked item icons (if present)
            if ui.pveLockIcons then updateIconRow(ui.pveLockIcons, db.locked_items_pve, false, specID) end
            if ui.pvpLockIcons then updateIconRow(ui.pvpLockIcons, db.locked_items_pvp, true, specID) end

            -- update lock button border, backdrop & text color based on PvE/PvP lock state
            if ui.lockBtns then
                local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
                for _, entry in ipairs(ui.lockBtns) do
                    local btn, slotID = entry.btn, entry.slotID
                    local link = GetInventoryItemLink("player", slotID)
                    local pveLocked, pvpLocked = false, false
                    if link then
                        local iid = GetItemInfoInstant(link)
                        if iid then
                            pveLocked = db.locked_items_pve and db.locked_items_pve[iid] or false
                            pvpLocked = db.locked_items_pvp and db.locked_items_pvp[iid] or false
                        end
                    end
                    local c = nil
                    if pveLocked and pvpLocked then
                        c = BOTH_COLOR
                    elseif pveLocked then
                        c = PVE_COLOR
                    elseif pvpLocked then
                        c = PVP_COLOR
                    end
                    btn.lockColor = c
                    local fs = btn:GetFontString()
                    if c then
                        btn:SetBackdropBorderColor(c[1], c[2], c[3], 1.0)
                        btn:SetBackdropColor(c[1] * 0.28, c[2] * 0.28, c[3] * 0.28, 0.95)
                        if fs then fs:SetTextColor(c[1], c[2], c[3], 1.0) end
                    else
                        if isCamelot then
                            btn:SetBackdropBorderColor(0.24, 0.19, 0.12, 0.8)
                            btn:SetBackdropColor(0.10, 0.08, 0.06, 0.95)
                            if fs then fs:SetTextColor(0.82, 0.75, 0.62, 1) end
                        else
                            btn:SetBackdropBorderColor(0, 0, 0, 1)
                            btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                            if fs then fs:SetTextColor(1, 1, 1, 0.85) end
                        end
                    end
                end
            end

            -- tier force button coloring (theme-aware accent)
            local p = sfui.theme and sfui.theme.GetPalette()
            local activeColor = p and p.accentColor or { 0, 0.8, 1 }
            local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
            local activeBg = { activeColor[1] * 0.35, activeColor[2] * 0.35, activeColor[3] * 0.35, 0.95 }
            local inactiveBg = isCamelot and { 0.12, 0.10, 0.08, 0.95 } or { 0, 0, 0, 1 }

            if ui.btn2S then
                local on = db.force_2set
                ui.btn2S:SetBackdropColor(unpack(on and activeBg or inactiveBg))
                if on then
                    ui.btn2S:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
                else
                    ui.btn2S:SetBackdropBorderColor(0, 0, 0, isCamelot and 0 or 1)
                end
            end
            if ui.btn4S then
                local on = (db.force_4set ~= false) and not db.force_2set
                ui.btn4S:SetBackdropColor(unpack(on and activeBg or inactiveBg))
                if on then
                    ui.btn4S:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
                else
                    ui.btn4S:SetBackdropBorderColor(0, 0, 0, isCamelot and 0 or 1)
                end
            end
            if ui.btn2E then
                local on = db.force_2emb
                ui.btn2E:SetBackdropColor(unpack(on and activeBg or inactiveBg))
                if on then
                    ui.btn2E:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
                else
                    ui.btn2E:SetBackdropBorderColor(0, 0, 0, isCamelot and 0 or 1)
                end
            end
            if ui.btnILvl then
                local isTank = sfui.gear.IsTankSpec(specID, db)
                local on = db.armor_ilvl_prio
                if on == nil then on = isTank end
                ui.btnILvl:SetBackdropColor(unpack(on and activeBg or inactiveBg))
                if on then
                    ui.btnILvl:SetBackdropBorderColor(activeColor[1], activeColor[2], activeColor[3], 1)
                else
                    ui.btnILvl:SetBackdropBorderColor(0, 0, 0, isCamelot and 0 or 1)
                end
            end
            if ui.roleBtns then
                local curRole = sfui.gear.GetClassicRole(specID, db)
                for rKey, rBtn in pairs(ui.roleBtns) do
                    local isSelected = (curRole == rKey)
                    if isSelected then
                        local c = rBtn.roleColor or { 0, 0.5, 0.5 }
                        rBtn:SetBackdropColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
                        rBtn:SetBackdropBorderColor(c[1], c[2], c[3], 1)
                        local fs = rBtn:GetFontString()
                        if fs then fs:SetTextColor(c[1], c[2], c[3], 1) end
                    else
                        rBtn:SetBackdropColor(unpack(inactiveBg))
                        rBtn:SetBackdropBorderColor(0, 0, 0, isCamelot and 0 or 1)
                        local fs = rBtn:GetFontString()
                        if fs then fs:SetTextColor(0.6, 0.6, 0.6, 1) end
                    end
                end
            end

            -- stat priority
            if ui.manBtns then
                local hasSet        = db.pve_set and db.pve_set ~= ""
                local alpha         = hasSet and 0.35 or 1.0

                local targetDB      = db
                local isTank        = sfui.gear.IsTankSpec(specID, targetDB)
                local curRole       = sfui.gear.GetClassicRole(specID, targetDB)
                local pool          = sfui.gear.GetStatPool(specID, isTank, curRole) or { "H", "M", "V", "C" }

                local isClassicSpec = (tonumber(specID) and tonumber(specID) >= 1482 and tonumber(specID) <= 1491)
                    or (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(specID))
                    or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
                    or (sfui.version and not sfui.version.retail)
                    or sfui.isClassic or sfui.isForever
                local numStats      = isClassicSpec and 8 or 4

                local pawnOrder
                if targetDB.pawn_weights and not hasSet then
                    -- P4: reuse pre-allocated sub-tables; no allocation in hot path
                    local n = 0
                    for k, v in pairs(targetDB.pawn_weights) do
                        local sName = k:gsub("Rating", "")
                        local abbrv = statAbbrv[sName] or statAbbrv[k]
                        if abbrv and not (not isTank and DEFENSIVE_STATS[abbrv]) then
                            n = n + 1
                            local e = pawnScratchList[n]
                            if not e then
                                e = { stat = "", weight = 0 }; pawnScratchList[n] = e
                            end
                            e.stat = abbrv; e.weight = tonumber(v) or 0
                        end
                    end
                    for i = n + 1, #pawnScratchList do pawnScratchList[i] = nil end
                    table.sort(pawnScratchList, pawnSortDesc)
                    wipe(pawnOrderScratch)
                    for j = 1, math.min(numStats, n) do table.insert(pawnOrderScratch, pawnScratchList[j].stat) end
                    pawnOrder = #pawnOrderScratch > 0 and pawnOrderScratch or nil
                end

                local rawOrder = pawnOrder or targetDB.stat_order or db.stat_order or
                    sfui.gear.GetDefaultStats(specID, curRole) or
                    (sfui.default_stats and sfui.default_stats[tonumber(specID)]) or pool
                rawOrder = rawOrder or pool or { "H", "M", "V", "C" }
                local equals = targetDB.stat_equals or db.stat_equals or {}

                -- Sanitize order: if not isTank, replace any defensive stats
                local order = {}
                for j = 1, numStats do
                    local st = rawOrder[j]
                    if not st or (not isTank and DEFENSIVE_STATS[st]) then
                        for _, cand in ipairs(pool) do
                            local inUse = false
                            for k = 1, #order do if order[k] == cand then
                                    inUse = true
                                    break
                                end end
                            if not inUse then
                                st = cand
                                break
                            end
                        end
                    end
                    order[j] = st or pool[j] or "none"
                end

                for j = 1, numStats do
                    local btn = ui.manBtns[j]
                    if btn then
                        local st = order[j] or "none"
                        local abbr = statAbbrv[st] or st
                        btn:SetText(tostring(abbr):lower())
                        local c = statBgColors[st]
                        if c and st ~= "none" then
                            btn:SetBackdropColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25, 0.9)
                            btn:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
                            local fs = btn:GetFontString()
                            if fs then fs:SetTextColor(c[1], c[2], c[3], 1.0) end
                        else
                            btn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
                            btn:SetBackdropBorderColor(0, 0, 0, 1)
                            local fs = btn:GetFontString()
                            if fs then fs:SetTextColor(1, 1, 1, 1) end
                        end
                        btn:SetAlpha(alpha)
                    end
                    if j < numStats then
                        if ui.manTgls[j] and ui.manTgls[j].SetText then
                            ui.manTgls[j]:SetText(equals[j] and "=" or ">")
                        end
                    end
                end

                if ui.setActiveLabel then ui.setActiveLabel:SetShown(hasSet) end
            end
        end
    end
end

-- -------------------------------------------------------------------------
-- GEAR UPDATE (AUTO EQUIP)
-- -------------------------------------------------------------------------
function sfui.gear.Update(force)
    if not isAutoEquipEnabled() and not force then return end
    if not SfuiDB.gear then return end
    local spec = common.get_current_spec_id()
    if spec == 0 then return end
    local db = SfuiDB.gear[spec] -- may be nil if never configured

    local pveSet = db and db.pve_set or ""
    local pvpSet = db and db.pvp_set or ""
    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()

    -- Authoritative isPvP: derived from zone + war mode, not from set names
    local isPvP = (instanceType == "pvp" or instanceType == "arena")
        or (instanceType == "none" and isWarMode)

    -- Which configured named set should be active in this context (nil = none configured)
    local targetSet = nil
    if instanceType == "pvp" or instanceType == "arena" then
        targetSet = pvpSet ~= "" and pvpSet or nil
    elseif instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "delve" then
        targetSet = pveSet ~= "" and pveSet or nil
    elseif instanceType == "none" then
        targetSet = isPvP and (pvpSet ~= "" and pvpSet or nil) or (pveSet ~= "" and pveSet or nil)
    end

    -- PvE/PvP set swap: equip configured named set for the current zone/spec.
    -- TryEquipSet returns true when it actually triggered an equip.
    local setEquipped = false
    if targetSet then
        setEquipped = TryEquipSet(targetSet)
    end

    -- If we just triggered a set equip, bail — EquipHighestILvl would conflict.
    if setEquipped then return end

    -- If the correct set is already equipped, also skip EquipHighestILvl UNLESS forced.
    if not force and isGearSetEquipped() then return end

    -- EquipHighestILvl is gated by the manual-edit pause UNLESS forced (e.g. spec change).
    if not force and autoEquipPaused() then return end

    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        if not updateScheduled then
            updateScheduled = true
            C_Timer.After(0.25, _OnUpdateCastTimer)
        end
        return
    end

    if sfui.highest and sfui.highest.EquipHighestILvl
        and not InCombatLockdown()
        and not UnitIsDeadOrGhost("player") then
        local shouldEquip = isAutoEquipEnabled()
        if shouldEquip then
            sfui.highest.EquipHighestILvl(isPvP, true)
        end
    end
end

-- P5: cache equipment set options; invalidated when sets change
local equipSetOptionsCache = nil

-- -------------------------------------------------------------------------
-- EVENT HANDLERS
-- -------------------------------------------------------------------------
sfui.events.RegisterEvent("EQUIPMENT_SETS_CHANGED", function()
    equipSetOptionsCache = nil
end)

local lastEquippedItems = {}

local function scanEquippedForChanges()
    if not SfuiDB or not SfuiDB.gear then return end

    local spec = common and common.get_current_spec_id and common.get_current_spec_id()
    if not spec or spec == 0 then return end

    for slotID = 1, 18 do
        if slotID ~= 4 then
            local link = GetInventoryItemLink("player", slotID)
            local currentID = link and GetItemInfoInstant(link)
            lastEquippedItems[slotID] = currentID
        end
    end

    if sfui.gear.UpdateStatUI then
        sfui.gear.UpdateStatUI()
    end
end

sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
    equipSetOptionsCache = nil
    scanEquippedForChanges()
end)

local function _OnRegenRetryTimer()
    if gearEquipQueue and not InCombatLockdown() then
        sfui.gear.handle_player_regen()
    end
end

function sfui.gear.handle_player_regen()
    if gearEquipQueue then
        if not UnitCastingInfo("player") and not UnitChannelInfo("player") and not UnitIsDeadOrGhost("player") then
            if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
                local name = C_EquipmentSet.GetEquipmentSetInfo(gearEquipQueue)
                if C_EquipmentSet.UseEquipmentSet then
                    C_EquipmentSet.UseEquipmentSet(gearEquipQueue)
                end
                if name and common and common.print then
                    common.print("equipped queued set: " .. name:lower())
                end
            end
            gearEquipQueue = nil
            regenRetries = 0
        elseif regenRetries < 5 then
            -- Still casting post-combat: retry up to 5 times (10 s total) then give up
            regenRetries = regenRetries + 1
            C_Timer.After(2, _OnRegenRetryTimer)
        else
            -- Give up: discard the queued set equip
            gearEquipQueue = nil
            regenRetries = 0
        end
    end
end

local function _OnBagUpdateTimer()
    bagUpdatePending = false
    -- Fix 1: respect manual-edit pause (CharacterFrame open / explicit pause)
    if autoEquipPaused() then return end
    -- Fix 2: if a gear set is configured AND equipped, don't override it
    if isGearSetEquipped() then return end

    local shouldEquip = isAutoEquipEnabled()
    if shouldEquip and sfui.highest and sfui.highest.EquipHighestILvl
        and not InCombatLockdown()
        and not UnitCastingInfo("player")
        and not UnitChannelInfo("player")
        and not UnitIsDeadOrGhost("player") then
        local isPvP = false
        local _, instanceType = GetInstanceInfo()
        if instanceType == "pvp" or instanceType == "arena" or (instanceType == "none" and isWarModeDesired()) then
            isPvP = true
        end
        sfui.highest.EquipHighestILvl(isPvP, true)
    end
    -- UpdateStatUI shifted securely into the debounce block
    if sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
end

sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
    -- [BAG_UPDATE_DELAYED Throttle Lock]
    -- Why lock for 2 seconds?
    -- This event fires violently rapidly when moving items, looting multiple items, or sorting bags.
    -- We lock (debounce) the auto-equip queue here for precisely 2 seconds so the inventory
    -- state can fully settle. This strictly prevents the CPU from re-scanning all 144 bag slots
    -- repeatedly every micro-second, and stops the UI from aggressively swapping gear while
    -- you are actively trying to organize your inventory.
    if not bagUpdatePending then
        bagUpdatePending = true
        C_Timer.After(2, _OnBagUpdateTimer)
    end
end)

local function _OnPlayerFlagsTimer()
    if sfui.gear and sfui.gear.Update then
        sfui.gear.Update()
    end
end

sfui.events.RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", function(event, unit)
    local delay = (cfg and cfg.gear and cfg.gear.updateDelay) or 3
    C_Timer.After(delay, _OnPlayerFlagsTimer)
end)

local lastSpecID = nil

local function doSpecSwap()
    if InCombatLockdown and InCombatLockdown() then return end
    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()
    local isPvP = (instanceType == "pvp" or instanceType == "arena") or (instanceType == "none" and isWarMode)

    sfui.gear.Update(true)
end

local specChangePending = false
local function _OnSpecChangeTimer()
    specChangePending = false
    doSpecSwap()
end

local function handle_spec_change(event, unit)
    if (event == "PLAYER_SPECIALIZATION_CHANGED" or event == "UNIT_SPELLCAST_SUCCEEDED") and unit and unit ~= "player" then return end

    local specId = common.get_current_spec_id()
    if not specId or specId == 0 then return end

    -- On initial login or reload, record the current spec and avoid triggering a spec swap
    if not lastSpecID then
        lastSpecID = specId
        return
    end

    -- If talents/traits updated but the specialization itself didn't change:
    if specId == lastSpecID and (event == "TRAIT_CONFIG_UPDATED" or event == "ACTIVE_TALENT_GROUP_CHANGED") then
        if SfuiGearManagerFrame and SfuiGearManagerFrame.SelectSpecTab and SfuiGearManagerFrame:IsShown() then
            SfuiGearManagerFrame:SelectSpecTab(specId)
        end
        return
    end

    lastSpecID = specId

    -- Clear validity cache on true specialization change
    if sfui.highest and sfui.highest.ClearCache then
        sfui.highest.ClearCache()
    end

    -- Force clear manual edit pause
    manualEditUntil = 0

    if SfuiGearManagerFrame and SfuiGearManagerFrame.SelectSpecTab then
        SfuiGearManagerFrame:SelectSpecTab(specId)
    end

    if not specChangePending then
        specChangePending = true
        C_Timer.After(0.15, _OnSpecChangeTimer)
    end
end
sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", handle_spec_change)
sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", handle_spec_change)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", handle_spec_change)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", handle_spec_change)
sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", function()
    if sfui.highest and sfui.highest.ClearCache then
        sfui.highest.ClearCache()
    end
    if sfui.gear and sfui.gear.Update then
        sfui.gear.Update(true)
    end
    if sfui.gear and sfui.gear.UpdateStatUI then
        sfui.gear.UpdateStatUI()
    end
end)

local function _OnZoneChangeTimer()
    zoneUpdateQueue = false
    if sfui.gear and sfui.gear.Update then
        sfui.gear.Update()
    end
end

local function handle_zone_change(event, isLogin, isReload)
    if not zoneUpdateQueue then
        zoneUpdateQueue = true
        -- Give inventory and equipment data 2 seconds to settle on initial login or reload
        local delay = (isLogin or isReload) and 2.0 or 0.5
        C_Timer.After(delay, _OnZoneChangeTimer)
    end
end
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", handle_zone_change)
sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", handle_zone_change)
sfui.events.RegisterEvent("PLAYER_LEVEL_UP", function()
    if sfui.highest and sfui.highest.ClearValidationCache then
        sfui.highest.ClearValidationCache()
    end
    sfui.gear.Update(true)
end)

-- Weapon specialization & skill updates (e.g. learning Staves, Polearms, Bows at Weapon Master)
local skillUpdatePending = false
local function _OnSkillChangeTimer()
    skillUpdatePending = false
    if sfui.highest and sfui.highest.ClearValidationCache then
        sfui.highest.ClearValidationCache()
    end
    if sfui.gear and sfui.gear.Update then
        sfui.gear.Update(true)
    end
    if sfui.gear and sfui.gear.UpdateStatUI then
        sfui.gear.UpdateStatUI()
    end
end

local function handle_skill_change()
    if not skillUpdatePending then
        skillUpdatePending = true
        C_Timer.After(0.3, _OnSkillChangeTimer)
    end
end

sfui.events.RegisterEvent("SKILL_LINES_CHANGED", handle_skill_change)
sfui.events.RegisterEvent("SPELLS_CHANGED", handle_skill_change)
sfui.events.RegisterEvent("LEARNED_SPELL_IN_TAB", handle_skill_change)
sfui.events.RegisterEvent("TRAINER_UPDATE", handle_skill_change)
sfui.events.RegisterEvent("TRAINER_CLOSED", handle_skill_change)
if sfui.isClassic then
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", handle_skill_change)
end


-- B2: ADDON_LOADED registration removed (InitToggleHook called at login via PLAYER_LOGIN)

-- -------------------------------------------------------------------------
-- GEAR MANAGER FRAME
-- -------------------------------------------------------------------------
local gearFrame = CreateFrame("Frame", "SfuiGearManagerFrame", UIParent, "BackdropTemplate")
gearFrame:SetPoint("CENTER")
gearFrame:SetMovable(true)
gearFrame:EnableMouse(true)
gearFrame:RegisterForDrag("LeftButton")
gearFrame:SetScript("OnDragStart", gearFrame.StartMoving)
gearFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Force TOPLEFT absolute anchoring so the frame always unfolds downwards
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
local HEADER_H = 56

if sfui.theme and sfui.theme.ApplyWindowStyle then
    sfui.theme.ApplyWindowStyle(gearFrame)
    sfui.theme.RegisterWindow(gearFrame, function(frame, pal)
        if frame.headerBar and sfui.theme.ApplyHeaderStyle then
            sfui.theme.ApplyHeaderStyle(frame.headerBar, "gear manager")
        end
        if frame.closeBtn and sfui.theme.ApplyCloseButtonStyle then
            sfui.theme.ApplyCloseButtonStyle(frame.closeBtn)
        end
        if frame.content and sfui.theme.ApplyContainerStyle then
            sfui.theme.ApplyContainerStyle(frame.content)
        end
        if frame.specUIs then
            for _, ui in pairs(frame.specUIs) do
                if ui.card and sfui.theme.ApplyCardStyle then
                    sfui.theme.ApplyCardStyle(ui.card)
                end
                if ui.pawnEdit and sfui.theme.ApplyInputStyle then
                    sfui.theme.ApplyInputStyle(ui.pawnEdit)
                end
            end
        end
        if frame.tabBtns and frame.activeSpecID then
            local accent = pal and pal.accentColor or { 0, 0.8, 1 }
            for id, btn in pairs(frame.tabBtns) do
                if id == frame.activeSpecID then
                    btn:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0)
                else
                    btn:SetBackdropBorderColor(0, 0, 0, 0.8)
                end
            end
        end
        if sfui.gear and sfui.gear.UpdateStatUI then
            sfui.gear.UpdateStatUI()
        end
    end)
else
    gearFrame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    gearFrame:SetBackdropColor(0.055, 0.055, 0.055, 0.97)
end
gearFrame:Hide()
gearFrame:SetFrameStrata("DIALOG")

-- Row 1: Header Bar (styled identically to the objective tracker with genuine banner / accent)
gearFrame.headerBar = CreateFrame("Frame", nil, gearFrame, "BackdropTemplate")
gearFrame.headerBar:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 6, -6)
gearFrame.headerBar:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -6, -6)
gearFrame.headerBar:SetHeight(24)
if sfui.theme and sfui.theme.ApplyHeaderStyle then
    sfui.theme.ApplyHeaderStyle(gearFrame.headerBar, "gear manager")
end
gearFrame.title = gearFrame.headerBar.title

-- Close & Collapse Buttons (Top-Right of Row 1)
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
    -- Lock header rigidly in place by migrating active anchor to TOPLEFT on first collapse
    local left = gearFrame:GetLeft()
    local top = gearFrame:GetTop()
    if left and top then
        gearFrame:ClearAllPoints()
        gearFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end

    gearFrame.collapsed = not gearFrame.collapsed
    SfuiDB = SfuiDB or {}
    SfuiDB.gear_collapsed = gearFrame.collapsed

    if gearFrame.collapsed then
        collapseBtn:SetText("+")
        if gearFrame.content then gearFrame.content:Hide() end
        gearFrame:SetHeight(HEADER_H)
    else
        collapseBtn:SetText("-")
        if gearFrame.content then gearFrame.content:Show() end
        gearFrame:SetHeight(gearFrame.expandedHeight or (HEADER_H + 140))
    end
end)

-- Main content container for body children (Spec Cards)
-- Inset with 8px margins from the outer frame border
gearFrame.content = CreateFrame("Frame", nil, gearFrame, "BackdropTemplate")
gearFrame.content:SetPoint("TOPLEFT", gearFrame, "TOPLEFT", 8, -HEADER_H)
gearFrame.content:SetPoint("BOTTOMRIGHT", gearFrame, "BOTTOMRIGHT", -8, 8)
gearFrame.content:SetFrameLevel(gearFrame:GetFrameLevel() + 3)
gearFrame.content:Show()
if sfui.theme and sfui.theme.ApplyContainerStyle then
    sfui.theme.ApplyContainerStyle(gearFrame.content)
end

local function GetEquipmentSetOptions()
    if equipSetOptionsCache then return equipSetOptionsCache end
    local options = { { text = "none", value = "" } }
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
        local setIDs = C_EquipmentSet.GetEquipmentSetIDs()
        if setIDs then
            for _, id in ipairs(setIDs) do
                local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                if name then table.insert(options, { text = name:lower(), value = name }) end
            end
        end
    end
    equipSetOptionsCache = options
    return options
end

-- -------------------------------------------------------------------------
-- HELPER: styled edit box
-- -------------------------------------------------------------------------
local function makeEditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h)
    eb:SetAutoFocus(false)
    eb:SetNumeric(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    if sfui.theme and sfui.theme.ApplyInputStyle then
        sfui.theme.ApplyInputStyle(eb)
    else
        local app = (cfg and cfg.appearance) or {}
        local ebCol = app.editBoxColor or { 0.1, 0.1, 0.1, 0.8 }
        local hlCol = app.highlightColor or (cfg and cfg.colors and cfg.colors.purple) or { 0.4, 0, 1, 0.9 }
        eb:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
        eb:SetBackdropColor(ebCol[1], ebCol[2], ebCol[3], ebCol[4] or 0.8)
        eb:SetScript("OnEditFocusGained", function(s)
            s:SetBackdropColor(hlCol[1] * 0.3, hlCol[2] * 0.3, hlCol[3] * 0.3, 0.9)
        end)
        eb:SetScript("OnEditFocusLost", function(s)
            s:SetBackdropColor(ebCol[1], ebCol[2], ebCol[3], ebCol[4] or 0.8)
        end)
    end
    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    return eb
end

-- -------------------------------------------------------------------------
-- HELPER: small font string label
-- -------------------------------------------------------------------------
local function mkLabel(parent, txt, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetText(txt and tostring(txt):lower() or "")
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(r or 0.65, g or 0.60, b or 0.50)
    return fs
end

-- Row 2 Quick Controls: Auto-Equip Toggle & Quick Equip Buttons
local autoToggle = common.create_flat_button(gearFrame, "auto: off", 72, 20)
autoToggle:SetPoint("TOPRIGHT", gearFrame, "TOPRIGHT", -10, -31)
function autoToggle:UpdateState(enabled)
    if enabled then
        self:SetText("|cff66ff66auto: on|r")
        local p = sfui.theme and sfui.theme.GetPalette()
        local acc = p and p.accentColor or { 0.95, 0.85, 0.55 }
        self:SetBackdropBorderColor(acc[1], acc[2], acc[3], 0.9)
        self:SetBackdropColor(acc[1] * 0.25, acc[2] * 0.25, acc[3] * 0.25, 0.95)
    else
        self:SetText("|cff888888auto: off|r")
        local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
        if isCamelot then
            self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
            self:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
        else
            self:SetBackdropBorderColor(0, 0, 0, 1)
            self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        end
    end
end

autoToggle:SetScript("OnClick", function()
    local newState = not isAutoEquipEnabled()
    setAutoEquipEnabled(newState)
    autoToggle:UpdateState(newState)
    if sfui.gearOptionsCheckbox and sfui.gearOptionsCheckbox.SetChecked then
        sfui.gearOptionsCheckbox:SetChecked(newState)
    end
    if newState then sfui.gear.Update() end
    if sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
end)
autoToggle:SetScript("OnEnter", function(b)
    local p = sfui.theme and sfui.theme.GetPalette()
    local hl = (p and p.highlightColor) or (cfg and cfg.colors and cfg.colors.cyan) or { 0, 1, 1 }
    b:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
    show_tooltip(b, "ANCHOR_TOP", "auto-equip gear", {
        { "automatically equips highest ilvl gear or your designated equipment set upon spec / zone changes.", 0.8, 0.8, 0.8, true }
    })
end)
autoToggle:SetScript("OnLeave", function(b)
    hide_tooltip()
    autoToggle:UpdateState(isAutoEquipEnabled())
end)
gearFrame.autoToggle = autoToggle
gearFrame.enableChk = autoToggle
gearFrame.maxLvlChk = autoToggle

gearFrame.highPvP = common.create_flat_button(gearFrame, "pvp", 36, 20)
gearFrame.highPvP:SetPoint("RIGHT", gearFrame.autoToggle, "LEFT", -6, 0)
gearFrame.highPvP:SetScript("OnClick", function()
    if sfui.highest and sfui.highest.EquipHighestILvl then sfui.highest.EquipHighestILvl(true) end
end)
gearFrame.highPvP:SetScript("OnEnter", function(b)
    show_tooltip(b, "ANCHOR_TOP", "equip highest ilvl pvp gear")
end)
gearFrame.highPvP:SetScript("OnLeave", function() hide_tooltip() end)

gearFrame.highPvE = common.create_flat_button(gearFrame, "pve", 36, 20)
gearFrame.highPvE:SetPoint("RIGHT", gearFrame.highPvP, "LEFT", -4, 0)
gearFrame.highPvE:SetScript("OnClick", function()
    if sfui.highest and sfui.highest.EquipHighestILvl then sfui.highest.EquipHighestILvl(false) end
end)
gearFrame.highPvE:SetScript("OnEnter", function(b)
    show_tooltip(b, "ANCHOR_TOP", "equip highest ilvl pve gear")
end)
gearFrame.highPvE:SetScript("OnLeave", function() hide_tooltip() end)

gearFrame.statusLabel = gearFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
gearFrame.statusLabel:SetPoint("LEFT", gearFrame, "TOPLEFT", 120, -41)
gearFrame.statusLabel:SetPoint("RIGHT", gearFrame.highPvE, "LEFT", -8, 0)
gearFrame.statusLabel:SetJustifyH("RIGHT")
gearFrame.statusLabel:SetShadowOffset(0, 0)
gearFrame.statusLabel:SetText("")

-- -------------------------------------------------------------------------
-- ON SHOW: build per-spec cards
-- -------------------------------------------------------------------------
gearFrame:SetScript("OnShow", function(self)
    if not self.posLoaded then
        self.posLoaded = true
        if SfuiDB.gear_pos then
            self:ClearAllPoints()
            self:SetPoint(SfuiDB.gear_pos.point, UIParent, SfuiDB.gear_pos.relativePoint, SfuiDB.gear_pos.x,
                SfuiDB.gear_pos.y)

            -- Convert legacy positional saves cleanly to TOPLEFT bounds if needed
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
            local specId = common and common.get_current_spec_id and common.get_current_spec_id()
            if specId and specId > 0 then self:SelectSpecTab(specId) end
        end
        if sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
        return
    end
    self.initialized = true
    self.specUIs = {}

    local getSpecs = (common and common.get_player_specs) or (sfui.common and sfui.common.get_player_specs)
    local _, specIDs
    if getSpecs then
        _, specIDs = getSpecs()
    end
    specIDs               = specIDs or {}

    local isVanilla       = (sfui.version and not sfui.version.retail)
        or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or sfui.isClassic or sfui.isForever
    local HEADER_H        = 56
    local activeSpecId    = (common and common.get_current_spec_id and common.get_current_spec_id()) or
    (specIDs and specIDs[1])
    local isActiveVanilla = (tonumber(activeSpecId) and tonumber(activeSpecId) >= 1482 and tonumber(activeSpecId) <= 1491)
        or (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(activeSpecId))
        or isVanilla
    local CARD_H          = isActiveVanilla and 168 or 140
    self.expandedHeight   = HEADER_H + CARD_H + 8

    if SfuiDB and SfuiDB.gear_collapsed ~= nil then
        self.collapsed = SfuiDB.gear_collapsed
    end

    if self.collapsed then
        collapseBtn:SetText("+")
        if self.content then self.content:Hide() end
        self:SetSize(496, HEADER_H)
    else
        collapseBtn:SetText("-")
        if self.content then self.content:Show() end
        self:SetSize(496, self.expandedHeight)
    end

    self.tabBtns = self.tabBtns or {}

    self.SelectSpecTab = function(f, specID)
        f.activeSpecID = specID
        local isVanillaSpec = (tonumber(specID) and tonumber(specID) >= 1482 and tonumber(specID) <= 1491)
            or (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(specID))
            or isVanilla
        local cardH = isVanillaSpec and 168 or 140
        f.expandedHeight = HEADER_H + cardH + 8
        if not f.collapsed then
            f:SetHeight(f.expandedHeight)
        end
        local p = sfui.theme and sfui.theme.GetPalette()
        local accent = p and p.accentColor or { 0.95, 0.85, 0.55 }
        for id, ui in pairs(f.specUIs) do
            if id == specID then
                if ui.card then ui.card:Show() end
                if f.tabBtns[id] then
                    f.tabBtns[id]:SetAlpha(1.0)
                    f.tabBtns[id]:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0)
                end
            else
                if ui.card then ui.card:Hide() end
                if f.tabBtns[id] then
                    f.tabBtns[id]:SetAlpha(0.40)
                    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
                    if isCamelot then
                        f.tabBtns[id]:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
                    else
                        f.tabBtns[id]:SetBackdropBorderColor(0, 0, 0, 0.8)
                    end
                end
            end
        end
        if sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
    end

    local startX = 12
    for _, id in ipairs(specIDs or {}) do
        local icon = common.get_spec_icon(id)
        if id and icon then
            local btn = CreateFrame("Button", nil, self, "BackdropTemplate")
            btn:SetSize(22, 22)
            btn:SetPoint("TOPLEFT", self, "TOPLEFT", startX, -30)
            local t = btn:CreateTexture(nil, "ARTWORK")
            t:SetAllPoints()
            t:SetTexture(icon)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.tex = t
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
            btn:SetBackdropColor(0, 0, 0, 0.7)
            btn:SetBackdropBorderColor(isCamelot and 0.28 or 0, isCamelot and 0.22 or 0, isCamelot and 0.14 or 0, 0.85)
            btn:SetScript("OnClick", function() self:SelectSpecTab(id) end)
            btn:SetScript("OnEnter", function(b)
                b:SetAlpha(1.0)
                local specName = common and common.get_spec_name and common.get_spec_name(id)
                show_tooltip(b, "ANCHOR_TOP", (specName and specName:lower()) or "specialization")
            end)
            btn:SetScript("OnLeave", function(b)
                if self.activeSpecID ~= id then
                    b:SetAlpha(0.40)
                end
                hide_tooltip()
            end)
            self.tabBtns[id] = btn
            startX = startX + 26
        end
    end

    -- icon helper: clicking unlocks the item in the respective context (PvE or PvP)
    local function createLockIcon(parent, specId, forPvP)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(22, 22)
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.tex = tex
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        local col = forPvP and PVP_COLOR or PVE_COLOR
        btn:SetBackdropBorderColor(col[1], col[2], col[3], 0.75)
        btn:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetScript("OnClick", function(b)
            if b.itemID and SfuiDB.gear[specId] then
                local sdb = SfuiDB.gear[specId]
                local key = forPvP and "locked_items_pvp" or "locked_items_pve"
                if sdb[key] then
                    sdb[key][b.itemID] = nil
                end
                hide_tooltip()
                sfui.gear.UpdateStatUI()
                sfui.gear.Update()
            end
        end)
        btn:SetScript("OnEnter", function(b)
            if b.itemID then
                local hl = forPvP and PVP_COLOR or PVE_COLOR
                b:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0)
                show_item_tooltip(b, b.itemID, "ANCHOR_TOP", {
                    { "click = unlock (" .. (forPvP and "pvp" or "pve") .. ")", 1, 0.4, 0.4 },
                })
            end
        end)
        btn:SetScript("OnLeave", function(b)
            local col = forPvP and PVP_COLOR or PVE_COLOR
            b:SetBackdropBorderColor(col[1], col[2], col[3], 0.75)
            hide_tooltip()
        end)
        return btn
    end

    for _, id in ipairs(specIDs or {}) do
        self.specUIs[id] = {}
        local ui = self.specUIs[id]

        local isVanillaSpec = (tonumber(id) and tonumber(id) >= 1482 and tonumber(id) <= 1491)
            or (sfui.gear and sfui.gear.IsClassicSpec and sfui.gear.IsClassicSpec(id))
            or (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
            or (sfui.version and not sfui.version.retail)

        -- Spec container inside self.content (seamless, no nested border)
        local card = CreateFrame("Frame", nil, self.content)
        card:SetAllPoints(self.content)
        ui.card = card

        -- ROW 1 (y = -6, height = 20): pve / pvp sets
        local pveTag = mkLabel(card, "pve set:", 0.82, 0.72, 0.52)
        pveTag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -11)

        local pveDrop = common.create_dropdown(card, 140, GetEquipmentSetOptions, function(val)
            SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
            SfuiDB.gear[id].pve_set = val
            sfui.gear.Update()
            sfui.gear.UpdateStatUI()
        end, "")
        pveDrop:SetPoint("TOPLEFT", card, "TOPLEFT", 66, -6)
        ui.pveDrop = pveDrop

        local pvpTag = mkLabel(card, "pvp set:", 0.95, 0.55, 0.55)
        pvpTag:SetPoint("TOPLEFT", card, "TOPLEFT", 236, -11)

        local pvpDrop = common.create_dropdown(card, 140, GetEquipmentSetOptions, function(val)
            SfuiDB.gear[id] = SfuiDB.gear[id] or { pve_set = "", pvp_set = "" }
            SfuiDB.gear[id].pvp_set = val
            sfui.gear.Update()
            sfui.gear.UpdateStatUI()
        end, "")
        pvpDrop:SetPoint("TOPLEFT", card, "TOPLEFT", 292, -6)
        ui.pvpDrop = pvpDrop

        -- ROW 2: Lock Slots & Build Modifiers (3-tier layout)
        -- Row 2A (y = -32): PvE locked item icons (above slot buttons)
        -- Row 2B (y = -57): Slot lock buttons & Build modifiers / Classic roles (middle)
        -- Row 2C (y = -80): PvP locked item icons (underneath slot buttons)
        local lockSlots = {
            { label = "t1", slot = 13 },
            { label = "t2", slot = 14 },
            { label = "r1", slot = 11 },
            { label = "r2", slot = 12 },
            { label = "nk", slot = 2 },
            { label = "w1", slot = 16 },
            { label = "w2", slot = 17 },
        }
        if isVanillaSpec then
            table.insert(lockSlots, { label = "rg", slot = 18 })
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
                    ldb[key] = ldb[key] or {}
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
            -- PvE Icon (Row 2A: above slot button)
            local pveIco = createLockIcon(card, id, false)
            pveIco:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX + 1, -32)
            pveIco:Hide()
            table.insert(ui.pveLockIcons, pveIco)

            -- Middle Slot Button (Row 2B)
            local btn = common.create_flat_button(card, def.label, 24, 20)
            btn:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX, -57)
            local capturedSlot = def.slot
            btn:SetScript("OnClick", function() lockSlot(capturedSlot, IsShiftKeyDown()) end)
            btn:SetScript("OnEnter", function(b)
                local p = sfui.theme and sfui.theme.GetPalette()
                local hl = p and p.highlightColor or (cfg and cfg.colors and cfg.colors.cyan) or { 0, 1, 1 }
                b:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
                local link = GetInventoryItemLink("player", capturedSlot)
                if link then
                    local itemName, itemLink = GetItemInfo(link)
                    local iid = GetItemInfoInstant(link)
                    local sdb = SfuiDB and SfuiDB.gear and SfuiDB.gear[id]
                    local pveL = iid and sdb and sdb.locked_items_pve and sdb.locked_items_pve[iid]
                    local pvpL = iid and sdb and sdb.locked_items_pvp and sdb.locked_items_pvp[iid]
                    local tag = ""
                    if pveL and pvpL then
                        tag = string.format("|cff%02x%02x%02x[pve+pvp]|r ", BOTH_COLOR[1] * 255, BOTH_COLOR[2] * 255,
                            BOTH_COLOR[3] * 255)
                    elseif pveL then
                        tag = string.format("|cff%02x%02x%02x[pve]|r ", PVE_COLOR[1] * 255, PVE_COLOR[2] * 255,
                            PVE_COLOR[3] * 255)
                    elseif pvpL then
                        tag = string.format("|cff%02x%02x%02x[pvp]|r ", PVP_COLOR[1] * 255, PVP_COLOR[2] * 255,
                            PVP_COLOR[3] * 255)
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
            btn:SetScript("OnLeave", function(b)
                hide_tooltip()
                if b.lockColor then
                    local c = b.lockColor
                    b:SetBackdropBorderColor(c[1], c[2], c[3], 1.0)
                    b:SetBackdropColor(c[1] * 0.28, c[2] * 0.28, c[3] * 0.28, 0.95)
                else
                    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive()
                    if isCamelot then
                        b:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
                        b:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
                    else
                        b:SetBackdropBorderColor(0, 0, 0, 1)
                        b:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
                    end
                end
            end)
            table.insert(ui.lockBtns, { btn = btn, slotID = def.slot })

            -- PvP Icon (Row 2C: underneath slot button)
            local pvpIco = createLockIcon(card, id, true)
            pvpIco:SetPoint("TOPLEFT", card, "TOPLEFT", curLockX + 1, -80)
            pvpIco:Hide()
            table.insert(ui.pvpLockIcons, pvpIco)

            curLockX = curLockX + 27
        end

        -- Build Modifiers (Retail: 2s, 4s, 2e, ilvl; Classic: tank, heal, dps)
        local btn2S = common.create_flat_button(card, "2s", 26, 20)
        btn2S:SetPoint("TOPLEFT", card, "TOPLEFT", 260, -57)
        btn2S:SetScript("OnClick", function()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            SfuiDB.gear[id].force_2set = not SfuiDB.gear[id].force_2set
            if SfuiDB.gear[id].force_2set then SfuiDB.gear[id].force_4set = false end
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end)
        btn2S:SetScript("OnEnter", function(b)
            show_tooltip(b, "ANCHOR_TOP", "force 2-piece tier set", {
                { "drafts 2 set pieces into your highest ilvl build, prioritizing lowest ilvl sacrifice.", 0.8, 0.8, 0.8, true }
            })
        end)
        btn2S:SetScript("OnLeave", function() hide_tooltip() end)
        ui.btn2S = btn2S

        local btn4S = common.create_flat_button(card, "4s", 26, 20)
        btn4S:SetPoint("TOPLEFT", card, "TOPLEFT", 290, -57)
        btn4S:SetScript("OnClick", function()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            local current = (SfuiDB.gear[id].force_4set ~= false) and not SfuiDB.gear[id].force_2set
            SfuiDB.gear[id].force_4set = not current
            if SfuiDB.gear[id].force_4set then SfuiDB.gear[id].force_2set = false end
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end)
        btn4S:SetScript("OnEnter", function(b)
            show_tooltip(b, "ANCHOR_TOP", "force 4-piece tier set", {
                { "drafts 4 set pieces into your highest ilvl build, prioritizing lowest ilvl sacrifice.", 0.8, 0.8, 0.8, true }
            })
        end)
        btn4S:SetScript("OnLeave", function() hide_tooltip() end)
        ui.btn4S = btn4S

        local btn2E = common.create_flat_button(card, "2e", 26, 20)
        btn2E:SetPoint("TOPLEFT", card, "TOPLEFT", 320, -57)
        btn2E:SetScript("OnClick", function()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            SfuiDB.gear[id].force_2emb = not SfuiDB.gear[id].force_2emb
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end)
        btn2E:SetScript("OnEnter", function(b)
            show_tooltip(b, "ANCHOR_TOP", "force 2 embellishments", {
                { "drafts up to 2 embellished crafted items into your gear set.", 0.8, 0.8, 0.8, true },
                { "wow limits active embellishments to a maximum of 2.",          0.6, 0.9, 0.6, true }
            })
        end)
        btn2E:SetScript("OnLeave", function() hide_tooltip() end)
        ui.btn2E = btn2E

        local btnILvl = common.create_flat_button(card, "ilvl", 36, 20)
        btnILvl:SetPoint("TOPLEFT", card, "TOPLEFT", 350, -57)
        btnILvl:SetScript("OnClick", function()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            local isTank = sfui.gear.IsTankSpec(id, SfuiDB.gear[id])
            local current = SfuiDB.gear[id].armor_ilvl_prio
            if current == nil then current = isTank end
            local newTank = not current
            SfuiDB.gear[id].armor_ilvl_prio = newTank
            local numID = tonumber(id) or 0
            local classID = (sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(numID)) or numID
            if isVanillaSpec or (classID >= 1482 and classID <= 1491) then
                SfuiDB.gear[id].is_tank = newTank
                if newTank then
                    local defOrder = sfui.gear.GetDefaultStats(numID, "TANK")
                    SfuiDB.gear[id].stat_order = defOrder and { unpack(defOrder) } or
                    { "Def", "Stam", "Arm", "Dodge", "Parry", "Block", "Hit", "Str" }
                else
                    SfuiDB.gear[id].stat_order = nil
                end
            end
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end)
        btnILvl:SetScript("OnEnter", function(b)
            show_tooltip(b, "ANCHOR_TOP", "prioritize armor item level (tanks)", {
                { "prioritizes highest item level on armor slots for maximum armor, stamina, and primary stat.", 0.8, 0.8, 0.8, true },
                { "jewelry, cloak, and trinkets continue using your secondary stat priority / pawn weights.",    0.6, 0.9, 0.6, true },
                { "enabled by default for tank specializations.",                                                0.5, 0.8, 1.0, true },
            })
        end)
        btnILvl:SetScript("OnLeave", function() hide_tooltip() end)
        ui.btnILvl = btnILvl

        local numID = tonumber(id) or 0
        local classID = (sfui.gear and sfui.gear.GetClassicClassID and sfui.gear.GetClassicClassID(numID)) or numID
        local classicRoles = isVanillaSpec and sfui.gear.CLASSIC_ROLES_BY_SPEC and
        (sfui.gear.CLASSIC_ROLES_BY_SPEC[numID] or (classID and sfui.gear.CLASSIC_ROLES_BY_SPEC[classID]))
        if classicRoles then
            ui.roleBtns = {}
            local curX = 274
            local roleColors = {
                ["TANK"] = { 0.4, 0.7, 1.0 },
                ["HEAL"] = { 0.3, 1.0, 0.4 },
                ["DPS"]  = { 1.0, 0.4, 0.3 },
            }
            local roleLabels = {
                ["TANK"] = "tank",
                ["HEAL"] = "heal",
                ["DPS"]  = "dps",
            }
            local roleWidths = {
                ["TANK"] = 38,
                ["HEAL"] = 38,
                ["DPS"]  = 36,
            }
            for _, rKey in ipairs(classicRoles) do
                local rLabel = roleLabels[rKey] or rKey:lower()
                local rW = roleWidths[rKey] or 38
                local rBtn = common.create_flat_button(card, rLabel, rW, 20)
                rBtn:SetPoint("TOPLEFT", card, "TOPLEFT", curX, -57)
                rBtn.roleKey = rKey
                rBtn.roleColor = roleColors[rKey]
                rBtn:SetScript("OnClick", function()
                    SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                    local sdb = SfuiDB.gear[id]
                    sdb.user_selected_role = true
                    sdb.classic_role = rKey
                    sdb.role = (rKey == "DPS" and "DAMAGER") or (rKey == "HEAL" and "HEALER") or "TANK"
                    if rKey == "TANK" then
                        sdb.is_tank = true
                        sdb.armor_ilvl_prio = true
                        sdb.is_healer = false
                    elseif rKey == "HEAL" then
                        sdb.is_tank = false
                        sdb.armor_ilvl_prio = false
                        sdb.is_healer = true
                    else
                        sdb.is_tank = false
                        sdb.armor_ilvl_prio = false
                        sdb.is_healer = false
                    end
                    local defOrder = sfui.gear.GetDefaultStats(numID, rKey)
                    if defOrder then
                        sdb.stat_order = {}
                        for sIdx, st in ipairs(defOrder) do sdb.stat_order[sIdx] = st end
                        sdb.stat_equals = nil
                        sdb.pawn_weights = nil
                    end
                    sfui.gear.UpdateStatUI()
                    sfui.gear.Update()
                    if not common.get_current_spec_id or common.get_current_spec_id() == id then
                        if sfui.highest and sfui.highest.EquipHighestILvl then
                            sfui.highest.EquipHighestILvl(isCurrentlyPvP())
                        end
                    end
                end)
                rBtn:SetScript("OnEnter", function(b)
                    local desc = (rKey == "TANK" and "configure stat priority, defensive stats, and armor item level prioritization for tanking.")
                        or (rKey == "HEAL" and "configure stat priority and gear optimization for healing.")
                        or "configure stat priority and gear optimization for damage dealing."
                    show_tooltip(b, "ANCHOR_TOP", (rLabel .. " role"), {
                        { desc, 0.8, 0.8, 0.8, true },
                    })
                end)
                rBtn:SetScript("OnLeave", function() hide_tooltip() end)
                ui.roleBtns[rKey] = rBtn
                curX = curX + rW + 4
            end
        end

        if isVanillaSpec then
            btn2S:Hide(); btn4S:Hide(); btn2E:Hide(); btnILvl:Hide()
        end

        -- ROW 3 (y = -110, height = 20): Stat priority
        local numStats = isVanillaSpec and 8 or 4
        local R3Y = -110
        local R4Y = -138

        local resetBtn = common.create_flat_button(card, "rst", 26, 20)
        resetBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 10, R3Y)
        resetBtn:SetScript("OnEnter", function(b)
            show_tooltip(b, "ANCHOR_TOP", "reset stat priority & pawn weights")
        end)
        resetBtn:SetScript("OnLeave", function() hide_tooltip() end)
        resetBtn:SetScript("OnClick", function()
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            local targetDB = SfuiDB.gear[id]
            local curRole = sfui.gear.GetClassicRole(tonumber(id), targetDB)
            local defOrder = sfui.gear.GetDefaultStats(tonumber(id), curRole)
            if defOrder then
                targetDB.stat_order = {}
                for sIdx, st in ipairs(defOrder) do targetDB.stat_order[sIdx] = st end
            else
                targetDB.stat_order = nil
            end
            targetDB.stat_equals  = nil
            targetDB.pawn_weights = nil
            targetDB.pawn_string  = nil
            if ui.pawnEdit then ui.pawnEdit:SetText("") end
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end)

        local prioTag = mkLabel(card, "prio:", 0.65, 0.60, 0.50)
        prioTag:SetPoint("LEFT", resetBtn, "RIGHT", 4, -1)

        ui.manBtns = {}
        ui.manTgls = {}
        local btnAnchor = prioTag

        local function getCurrentOrder()
            SfuiDB = SfuiDB or {}
            SfuiDB.gear = SfuiDB.gear or {}
            local db = SfuiDB.gear[id] or {}
            local targetDB = db
            local isTank = sfui.gear.IsTankSpec(tonumber(id), targetDB)
            local curRole = sfui.gear.GetClassicRole(tonumber(id), targetDB)
            local pool = sfui.gear.GetStatPool(tonumber(id), isTank, curRole) or { "H", "M", "V", "C" }
            if targetDB.pawn_weights then
                -- Reuse pre-allocated sub-tables; indexed write avoids table.wipe allocation churn
                local m = 0
                for k, v in pairs(targetDB.pawn_weights) do
                    local sName = k:gsub("Rating", "")
                    local st = statAbbrv[sName] or statAbbrv[k]
                    if st and not (not isTank and DEFENSIVE_STATS[st]) then
                        m = m + 1
                        local e = pawnScratchList[m]
                        if not e then
                            e = { stat = "", weight = 0 }; pawnScratchList[m] = e
                        end
                        e.stat = st; e.weight = tonumber(v) or 0
                    end
                end
                for i = m + 1, #pawnScratchList do pawnScratchList[i] = nil end
                table.sort(pawnScratchList, pawnSortDesc)
                wipe(curOrderScratch)
                for i = 1, numStats do curOrderScratch[i] = pawnScratchList[i] and pawnScratchList[i].stat or pool[i] or
                    "none" end
                return curOrderScratch
            end
            local rawOrder = targetDB.stat_order
                or db.stat_order
                or sfui.gear.GetDefaultStats(tonumber(id), curRole)
                or (sfui.default_stats and sfui.default_stats[tonumber(id)])
                or pool
            rawOrder = rawOrder or pool or { "H", "M", "V", "C" }
            local clean = {}
            for i = 1, numStats do
                local st = rawOrder[i]
                if not st or (not isTank and DEFENSIVE_STATS[st]) then
                    for _, cand in ipairs(pool) do
                        local inUse = false
                        for k = 1, #clean do
                            if clean[k] == cand or (statAbbrv[cand] and statAbbrv[cand] == (statAbbrv[clean[k]] or clean[k])) then
                                inUse = true
                                break
                            end
                        end
                        if not inUse then
                            st = cand
                            break
                        end
                    end
                end
                clean[i] = st or pool[i] or "none"
            end
            return clean
        end

        local function cycleStat(b, delta)
            SfuiDB = SfuiDB or {}
            SfuiDB.gear = SfuiDB.gear or {}
            SfuiDB.gear[id] = SfuiDB.gear[id] or {}
            local targetDB = SfuiDB.gear[id]
            if targetDB.pawn_weights then
                targetDB.pawn_weights = nil
                targetDB.pawn_string = nil
                if ui.pawnEdit then ui.pawnEdit:SetText("") end
            end
            local isTank = sfui.gear.IsTankSpec(tonumber(id), targetDB)
            local curRole = sfui.gear.GetClassicRole(tonumber(id), targetDB)
            local pool = sfui.gear.GetStatPool(tonumber(id), isTank, curRole)
            if not pool or #pool == 0 then return end

            local order = getCurrentOrder()
            local newOrder = {}
            for k = 1, numStats do newOrder[k] = order[k] end
            local currentStat = newOrder[b.idx] or pool[1]

            local curIdx = 1
            for pIdx, s in ipairs(pool) do
                if s == currentStat or statAbbrv[s] == currentStat or (statAbbrv[currentStat] and statAbbrv[s] == statAbbrv[currentStat]) then
                    curIdx = pIdx
                    break
                end
            end

            local nextStat = currentStat
            for step = 1, #pool do
                curIdx = curIdx + delta
                if curIdx > #pool then curIdx = 1 end
                if curIdx < 1 then curIdx = #pool end
                local candidate = pool[curIdx]
                local inUse = false
                for k = 1, numStats do
                    if k ~= b.idx and (newOrder[k] == candidate or (statAbbrv[candidate] and statAbbrv[candidate] == (statAbbrv[newOrder[k]] or newOrder[k]))) then
                        inUse = true
                        break
                    end
                end
                if not inUse then
                    nextStat = candidate
                    break
                end
            end

            newOrder[b.idx] = nextStat
            targetDB.stat_order = newOrder
            sfui.gear.UpdateStatUI()
            sfui.gear.Update()
        end

        local statBtnW = isVanillaSpec and 24 or 28
        local sepW = isVanillaSpec and 11 or 13
        local sepGap = 1

        for j = 1, numStats do
            local btn = common.create_flat_button(card, "?", statBtnW, 20)
            btn:SetPoint("LEFT", btnAnchor, "RIGHT", j == 1 and 4 or sepGap, 0)
            btn:SetPoint("TOP", card, "TOP", 0, R3Y)
            btn.idx = j
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:EnableMouseWheel(true)
            btn:SetScript("OnClick", function(b, mouseBtn)
                SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                local targetDB = SfuiDB.gear[id]
                if targetDB.pawn_weights then
                    targetDB.pawn_weights = nil
                    targetDB.pawn_string = nil
                    if ui.pawnEdit then ui.pawnEdit:SetText("") end
                end
                if IsShiftKeyDown() then
                    cycleStat(b, mouseBtn == "LeftButton" and 1 or -1)
                    return
                end
                local order = getCurrentOrder()
                local newOrder = {}
                for k = 1, numStats do newOrder[k] = order[k] end
                if mouseBtn == "LeftButton" and b.idx > 1 then
                    newOrder[b.idx] = order[b.idx - 1]
                    newOrder[b.idx - 1] = order[b.idx]
                    targetDB.stat_order = newOrder
                    sfui.gear.UpdateStatUI()
                    sfui.gear.Update()
                elseif mouseBtn == "RightButton" and b.idx < numStats then
                    newOrder[b.idx] = order[b.idx + 1]
                    newOrder[b.idx + 1] = order[b.idx]
                    targetDB.stat_order = newOrder
                    sfui.gear.UpdateStatUI()
                    sfui.gear.Update()
                end
            end)
            btn:SetScript("OnMouseWheel", function(b, delta)
                cycleStat(b, delta > 0 and 1 or -1)
            end)
            btn:SetScript("OnEnter", function(b)
                local order = getCurrentOrder()
                local st = order[b.idx] or "?"
                local title = statFullName[st] or tostring(st):lower()
                local tips = {
                    { "left-click: increase priority",  0.7, 0.7, 0.7 },
                    { "right-click: decrease priority", 0.7, 0.7, 0.7 },
                }
                if isVanillaSpec then
                    table.insert(tips, { "shift-click or scroll: change stat", 0.4, 0.8, 1.0 })
                end
                show_tooltip(b, "ANCHOR_TOP", title, tips)
            end)
            btn:SetScript("OnLeave", function() hide_tooltip() end)
            ui.manBtns[j] = btn
            btnAnchor = btn

            if j < numStats then
                local sep = common.create_flat_button(card, ">", sepW, 20)
                local fs = (sep.text and sep.text.SetTextColor and sep.text) or
                (sep.GetFontString and sep:GetFontString())
                if fs and fs.SetTextColor then fs:SetTextColor(0.8, 0.8, 0.8) end
                sep:SetPoint("LEFT", btnAnchor, "RIGHT", sepGap, 0)
                sep:SetPoint("TOP", card, "TOP", 0, R3Y)

                sep.idx = j
                sep:SetScript("OnClick", function(b)
                    SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                    local targetDB = SfuiDB.gear[id]
                    local eq = targetDB.stat_equals or {}
                    eq[b.idx] = not eq[b.idx]
                    targetDB.stat_equals = eq
                    sfui.gear.UpdateStatUI()
                    sfui.gear.Update()
                end)

                ui.manTgls[j] = sep
                btnAnchor = sep
            end
        end

        if not isVanillaSpec then
            -- Retail: Pawn on right side of Row 3
            local pawnSaveBtn = common.create_flat_button(card, "save", 38, 20)
            pawnSaveBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, R3Y)

            local pawnEdit = makeEditBox(card, 136, 20)
            pawnEdit:SetPoint("RIGHT", pawnSaveBtn, "LEFT", -4, 0)
            pawnEdit:SetPoint("TOP", card, "TOP", 0, R3Y)
            pawnEdit:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
            pawnEdit:SetScript("OnEnter", function(b)
                show_tooltip(b, "ANCHOR_TOP", "pawn scale string", {
                    { "paste a pawn export scale string here and click save.", 0.8, 0.8, 0.8, true },
                })
            end)
            pawnEdit:SetScript("OnLeave", function() hide_tooltip() end)
            ui.pawnEdit = pawnEdit

            local pawnTag = mkLabel(card, "pawn:", 0.65, 0.60, 0.50)
            pawnTag:SetPoint("RIGHT", pawnEdit, "LEFT", -4, -1)

            pawnSaveBtn:SetScript("OnClick", function()
                local text = pawnEdit:GetText()
                SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                local weights = {}
                for stat, val in text:gmatch("(%a+)=(%-?[%d%.]+)") do
                    weights[stat:gsub("Rating", "")] = tonumber(val)
                end
                SfuiDB.gear[id].pawn_weights = next(weights) and weights or nil
                SfuiDB.gear[id].pawn_string  = (next(weights) and text ~= "") and text or nil
                local specName               = (common and common.get_spec_name and common.get_spec_name(id)) or
                ("spec " .. tostring(id))
                if common and common.print then common.print("pawn saved for " .. specName:lower()) end
                sfui.gear.UpdateStatUI()
            end)
        else
            -- Classic: Pawn on ROW 4
            local pawnTag = mkLabel(card, "pawn:", 0.65, 0.60, 0.50)
            pawnTag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, R4Y - 1)

            local pawnEdit = makeEditBox(card, 370, 20)
            pawnEdit:SetPoint("LEFT", pawnTag, "RIGHT", 6, 0)
            pawnEdit:SetPoint("TOP", card, "TOP", 0, R4Y)
            pawnEdit:SetScript("OnEnterPressed", function(b) b:ClearFocus() end)
            pawnEdit:SetScript("OnEnter", function(b)
                show_tooltip(b, "ANCHOR_TOP", "pawn scale string", {
                    { "paste a pawn export scale string here and click save.",                   0.8, 0.8, 0.8, true },
                    { "example: ( pawn: v1: \"mage\": intellect=1.5, spellpower=2.5, hit=2.0 )", 0.6, 0.8, 1.0, true },
                })
            end)
            pawnEdit:SetScript("OnLeave", function() hide_tooltip() end)
            ui.pawnEdit = pawnEdit

            local pawnSaveBtn = common.create_flat_button(card, "save", 42, 20)
            pawnSaveBtn:SetPoint("LEFT", pawnEdit, "RIGHT", 6, 0)
            pawnSaveBtn:SetPoint("TOP", card, "TOP", 0, R4Y)

            pawnSaveBtn:SetScript("OnClick", function()
                local text = pawnEdit:GetText()
                SfuiDB.gear[id] = SfuiDB.gear[id] or {}
                local weights = {}
                for stat, val in text:gmatch("(%a+)=(%-?[%d%.]+)") do
                    weights[stat:gsub("Rating", "")] = tonumber(val)
                end
                SfuiDB.gear[id].pawn_weights = next(weights) and weights or nil
                SfuiDB.gear[id].pawn_string  = (next(weights) and text ~= "") and text or nil
                local specName               = (common and common.get_spec_name and common.get_spec_name(id)) or
                ("spec " .. tostring(id))
                if common and common.print then common.print("pawn saved for " .. specName:lower()) end
                sfui.gear.UpdateStatUI()
            end)
        end
    end
    self:SelectSpecTab(activeSpecId)

    if sfui.gear.UpdateStatUI then sfui.gear.UpdateStatUI() end
end)

sfui.gear.Frame = gearFrame

function sfui.gear.toggle()
    if not SfuiGearManagerFrame then return end
    if SfuiGearManagerFrame:IsShown() then
        SfuiGearManagerFrame:Hide()
    else
        SfuiGearManagerFrame:Show()
    end
end

-- -------------------------------------------------------------------------
-- CHARACTER FRAME TOGGLE BUTTON
-- -------------------------------------------------------------------------
local function InitToggleHook()
    if sfui.gear.toggle_hooked then return end
    if not CharacterFrame or not CharacterFrameCloseButton then return end
    sfui.gear.toggle_hooked = true

    local toggleBtn = CreateFrame("Button", "SfuiGearToggleBtn", CharacterFrame)
    toggleBtn:SetSize(22, 22)
    toggleBtn:SetPoint("RIGHT", CharacterFrameCloseButton, "LEFT", -5, 0)
    toggleBtn:SetNormalTexture("Interface\\Icons\\inv_misc_gear_01")
    toggleBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if toggleBtn:GetNormalTexture() then
        toggleBtn:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    toggleBtn:SetScript("OnEnter", function(self)
        show_tooltip(self, "ANCHOR_RIGHT", "sfui gear manager")
    end)
    toggleBtn:SetScript("OnLeave", function() hide_tooltip() end)
    toggleBtn:SetScript("OnClick", function()
        sfui.gear.toggle()
    end)

    toggleBtn:SetScript("OnShow", function()
        if sfui.gear.pauseAutoEquip then sfui.gear.pauseAutoEquip(10) end
        if SfuiGearManagerFrame and SfuiDB.gear and SfuiDB.gear.auto_open ~= false then
            SfuiGearManagerFrame:Show()
        end
    end)
    toggleBtn:SetScript("OnHide", function()
        if SfuiGearManagerFrame and SfuiDB.gear and SfuiDB.gear.auto_open ~= false then
            SfuiGearManagerFrame:Hide()
        end
    end)
end

if CharacterFrame then InitToggleHook() end

-- -------------------------------------------------------------------------
-- PAPERDOLL ITEM LOCK (Shift+Left-click)
-- -------------------------------------------------------------------------
local function InitPaperDollLockHook()
    if sfui.gear.paperdoll_hooked then return end
    sfui.gear.paperdoll_hooked = true

    local function onPaperDollClick(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            local slot = self:GetID()
            local link = GetInventoryItemLink("player", slot)
            if link then
                local itemID = GetItemInfoInstant(link)
                local specID = common.get_current_spec_id()
                if itemID and specID then
                    SfuiDB.gear[specID] = SfuiDB.gear[specID] or {}
                    local ctxPvP = isCurrentlyPvP()
                    local key = ctxPvP and "locked_items_pvp" or "locked_items_pve"
                    SfuiDB.gear[specID][key] = SfuiDB.gear[specID][key] or {}

                    local slotName = "item"
                    if slot == 13 or slot == 14 then
                        slotName = "trinket"
                    elseif slot == 11 or slot == 12 then
                        slotName = "ring"
                    elseif slot == 2 then
                        slotName = "neck"
                    elseif slot == 16 then
                        slotName = "main hand"
                    elseif slot == 17 then
                        slotName = "off hand"
                    elseif slot == 18 then
                        slotName = "ranged"
                    end

                    if SfuiDB.gear[specID][key][itemID] then
                        SfuiDB.gear[specID][key][itemID] = nil
                        if common and common.print then
                            common.print(string.format("%s unlocked (%s): %s", slotName, ctxPvP and "pvp" or "pve", link))
                        end
                    else
                        SfuiDB.gear[specID][key][itemID] = true
                        if common and common.print then
                            common.print(string.format("%s locked (%s): %s", slotName, ctxPvP and "pvp" or "pve", link))
                        end
                    end
                    sfui.gear.UpdateStatUI()
                end
            end
        end
    end

    local slotsToHook = {
        "CharacterTrinket0Slot",
        "CharacterTrinket1Slot",
        "CharacterFinger0Slot",
        "CharacterFinger1Slot",
        "CharacterNeckSlot",
        "CharacterMainHandSlot",
        "CharacterSecondaryHandSlot",
        "CharacterRangedSlot",
    }
    for _, slotName in ipairs(slotsToHook) do
        local slotFrame = _G[slotName]
        if slotFrame then
            slotFrame:HookScript("OnClick", onPaperDollClick)
        end
    end
end

function sfui.gear.initialize()
    -- Global single-pass legacy DB migration
    if SfuiDB and SfuiDB.gear then
        for specID, db in pairs(SfuiDB.gear) do
            if type(specID) == "number" and db.locked_items then
                db.locked_items_pve = db.locked_items_pve or {}
                db.locked_items_pvp = db.locked_items_pvp or {}
                for k in pairs(db.locked_items) do
                    db.locked_items_pve[k] = true
                    db.locked_items_pvp[k] = true
                end
                db.locked_items = nil
            end
        end
    end
    -- Migrate legacy per-character autoequip_enabled → unified SfuiDB.gear.auto_equip_highest
    if SfuiDB and SfuiDB.gear_char and SfuiDB.gear then
        if SfuiDB.gear.auto_equip_highest == nil then
            -- Check if ANY character had autoequip_enabled = true; if so, carry it over
            for _, charData in pairs(SfuiDB.gear_char) do
                if charData.autoequip_enabled then
                    SfuiDB.gear.auto_equip_highest = true
                    break
                end
            end
        end
    end

    InitToggleHook()
    InitPaperDollLockHook()

    -- Populate initial equipped items to track changes
    for slotID = 1, 18 do
        if slotID ~= 4 then
            local link = GetInventoryItemLink("player", slotID)
            lastEquippedItems[slotID] = link and GetItemInfoInstant(link)
        end
    end

    lastSpecID = common.get_current_spec_id()
end

function sfui.gear_debug_info()
    local eqCount = 0
    for _ in pairs(lastEquippedItems) do eqCount = eqCount + 1 end

    return {
        equippedCache = eqCount,
        lastEquipped  = eqCount,
    }
end

if sfui.RegisterModule then
    sfui.gear.OnEnable = function(self) self.initialize() end
    sfui.gear.OnSpecChanged = function(self, specID)
        if self.Update then self.Update() end
    end
    sfui.gear.GetDebugInfo = sfui.gear_debug_info
    sfui.RegisterModule("gear", sfui.gear)
end
