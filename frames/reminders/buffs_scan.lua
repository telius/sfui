local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.scan = {}

local _G = _G
local string_lower = string.lower
local wipe = _G.wipe
local UnitExists = _G.UnitExists
local UnitIsDead = _G.UnitIsDead
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local IsMounted = _G.IsMounted
local UnitOnTaxi = _G.UnitOnTaxi
local GetWeaponEnchantInfo = _G.GetWeaponEnchantInfo
local GetInventoryItemLink = _G.GetInventoryItemLink
local GetShapeshiftForm = _G.GetShapeshiftForm
local GetTime = _G.GetTime
local GetSpellInfo = _G.GetSpellInfo
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local C_Secrets = _G.C_Secrets
local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue

local function AreAurasSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return true
    end
    return false
end

local data = sfui.buffs.data
local entries = nil

-- Caches & Table Pools
local knownCache = {}
local activeResults = {}
local auraRecordPool = {}
local activeAuraList = {}
local activeAurasBySpellID = {}
local activeAurasByName = {}
local dirty = true
local throttleTimer = nil
local lastResultCount = -1
local prevResultKeys = {}

local function RefreshSpellKnowledge()
    if sfui.buffs.paladin and sfui.buffs.paladin.InvalidateCache then
        sfui.buffs.paladin.InvalidateCache()
    end
    entries = (data.GetAllEntries and data.GetAllEntries()) or data.GetClassEntries()
    for i = 1, #entries do
        local entry = entries[i]
        local known = false
        if entry.isConsumable then
            known = true
        elseif entry.isKnownCheck then
            known = entry.isKnownCheck(entry)
        elseif entry.spellIDs then
            known = data.IsAnySpellKnown(entry.spellIDs)
        else
            known = true
        end
        knownCache[entry.key] = known

        -- Pre-compute lowercased name lookups once to eliminate string allocations during scan loops
        if not entry._cachedLookups then
            entry._cachedLookups = true
            if entry.name then
                entry.lowerName = string_lower(entry.name)
            end
            if entry.names then
                entry.lowerNames = {}
                for j = 1, #entry.names do
                    entry.lowerNames[j] = string_lower(entry.names[j])
                end
            end
            if entry.spellIDs then
                entry.spellbookNames = {}
                for j = 1, #entry.spellIDs do
                    local sID = entry.spellIDs[j]
                    local sName = (data and data.ResolveSpellName and data.ResolveSpellName(sID))
                        or (sfui.api and sfui.api.GetSpellName and sfui.api.GetSpellName(sID))
                        or (GetSpellInfo and GetSpellInfo(sID))
                    if sName and sName ~= "" then
                        entry.spellbookNames[#entry.spellbookNames + 1] = string_lower(sName)
                    end
                end
            end
        end
    end
    dirty = true
end
sfui.buffs.scan.RefreshSpellKnowledge = RefreshSpellKnowledge

local function ReleasePlayerAuras()
    wipe(activeAurasBySpellID)
    wipe(activeAurasByName)
    for i = #activeAuraList, 1, -1 do
        local r = table.remove(activeAuraList, i)
        wipe(r)
        auraRecordPool[#auraRecordPool + 1] = r
    end
end

local function RecordActiveAura(name, spellId, duration, expirationTime, applications, icon)
    if issecretvalue then
        if issecretvalue(name) then name = nil end
        if issecretvalue(spellId) then spellId = nil end
        if issecretvalue(duration) then duration = 0 end
        if issecretvalue(expirationTime) then expirationTime = 0 end
        if issecretvalue(applications) then applications = 0 end
    end
    if not name and not spellId then return nil end

    local r = table.remove(auraRecordPool) or {}
    r.name = name
    r.spellId = spellId
    r.duration = duration or 0
    r.expirationTime = expirationTime or 0
    r.applications = applications or 0
    r.icon = icon

    if spellId then
        activeAurasBySpellID[spellId] = r
    end
    if type(name) == "string" and name ~= "" then
        activeAurasByName[string_lower(name)] = r
    end
    activeAuraList[#activeAuraList + 1] = r
    return r
end

local function CollectPlayerAuras()
    ReleasePlayerAuras()
    if AreAurasSecret() or sfui.common.is_in_combat() then
        return
    end

    -- Never call AuraUtil.ForEachAura here: it invokes C_UnitAuras.GetAuraSlots(),
    -- which lacks SecretWhenUnitAuraRestricted and throws a C++ error if any slot is secret.
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local checkIndexSecret = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
        for i = 1, 40 do
            if not (checkIndexSecret and checkIndexSecret("player", i, "HELPFUL")) then
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then break end
                RecordActiveAura(
                    aura.name,
                    aura.spellId,
                    aura.duration,
                    aura.expirationTime,
                    aura.applications,
                    aura.icon
                )
            end
        end
    elseif _G.UnitAura then
        for i = 1, 40 do
            local name, icon, count, _, duration, expTime, _, _, _, sID = _G.UnitAura("player", i, "HELPFUL")
            if not name then break end
            RecordActiveAura(name, sID, duration, expTime, count, icon)
        end
    end
end

local function ScanPlayerAura(entry)
    if AreAurasSecret() then
        return false, 0, 0, 0, nil
    end
    local spellIDs = entry.spellIDs

    -- 1. Fast path: check C_UnitAuras.GetPlayerAuraBySpellID directly if available
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and spellIDs then
        local checkSpellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
        for i = 1, #spellIDs do
            local sID = spellIDs[i]
            if not (checkSpellSecret and checkSpellSecret(sID)) then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(sID)
                if aura then
                    local dur = (not (issecretvalue and issecretvalue(aura.duration)) and aura.duration) or 0
                    local exp = (not (issecretvalue and issecretvalue(aura.expirationTime)) and aura.expirationTime) or 0
                    local app = (not (issecretvalue and issecretvalue(aura.applications)) and aura.applications) or 0
                    return true, dur, exp, app, aura.icon
                end
            end
        end
    end

    -- 2. O(1) Hash lookup by Spell ID
    if spellIDs then
        for i = 1, #spellIDs do
            local a = activeAurasBySpellID[spellIDs[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 3. O(1) Hash lookup by Pre-lowercased configured names
    local lowerNames = entry.lowerNames
    if lowerNames then
        for i = 1, #lowerNames do
            local a = activeAurasByName[lowerNames[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 4. O(1) Hash lookup by Pre-lowercased entry name
    if entry.lowerName then
        local a = activeAurasByName[entry.lowerName]
        if a then
            return true, a.duration, a.expirationTime, a.applications, a.icon
        end
    end

    -- 5. O(1) Hash lookup by Pre-lowercased spellbook names
    local spellbookNames = entry.spellbookNames
    if spellbookNames then
        for i = 1, #spellbookNames do
            local a = activeAurasByName[spellbookNames[i]]
            if a then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    -- 6. Pattern fallback for Paladin blessings and auras (handles custom Camelot rank IDs)
    if entry.key == "blessing" then
        for lowerAuraName, a in pairs(activeAurasByName) do
            if (lowerAuraName:find("^blessing of ") or lowerAuraName:find("^greater blessing of "))
                and not lowerAuraName:find("protection", 1, true)
                and not lowerAuraName:find("freedom", 1, true)
                and not lowerAuraName:find("sacrifice", 1, true) then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    elseif entry.key == "aura" and sfui.buffs.playerClass == "PALADIN" then
        for lowerAuraName, a in pairs(activeAurasByName) do
            if lowerAuraName:find(" aura$") then
                return true, a.duration, a.expirationTime, a.applications, a.icon
            end
        end
    end

    return false, 0, 0, 0, nil
end

local function ScanStance(entry)
    local form = GetShapeshiftForm and GetShapeshiftForm()
    if form and form > 0 then
        return true, 0, 0, 0, nil
    end
    return false, 0, 0, 0, nil
end

local ENCHANT_ID_TO_NAME = {
    -- Rockbiter Weapon (Classic / Camelot ranks 1-9)
    [29]   = "Rockbiter Weapon",
    [6]    = "Rockbiter Weapon",
    [1]    = "Rockbiter Weapon",
    [503]  = "Rockbiter Weapon",
    [1663] = "Rockbiter Weapon",
    [683]  = "Rockbiter Weapon",
    [1664] = "Rockbiter Weapon",
    [2634] = "Rockbiter Weapon",
    [2635] = "Rockbiter Weapon",

    -- Flametongue Weapon (Classic / Camelot ranks 1-10 + Retail)
    [5]    = "Flametongue Weapon",
    [4]    = "Flametongue Weapon",
    [3]    = "Flametongue Weapon",
    [523]  = "Flametongue Weapon",
    [1665] = "Flametongue Weapon",
    [1666] = "Flametongue Weapon",
    [2636] = "Flametongue Weapon",
    [2637] = "Flametongue Weapon",
    [2638] = "Flametongue Weapon",
    [2639] = "Flametongue Weapon",
    [5400] = "Flametongue Weapon",

    -- Frostbrand Weapon (Classic / Camelot ranks 1-9)
    [2]    = "Frostbrand Weapon",
    [12]   = "Frostbrand Weapon",
    [524]  = "Frostbrand Weapon",
    [1667] = "Frostbrand Weapon",
    [1668] = "Frostbrand Weapon",
    [2640] = "Frostbrand Weapon",
    [2641] = "Frostbrand Weapon",
    [2642] = "Frostbrand Weapon",

    -- Windfury Weapon (Classic / Camelot ranks 1-8 + Retail)
    [283]  = "Windfury Weapon",
    [284]  = "Windfury Weapon",
    [525]  = "Windfury Weapon",
    [1669] = "Windfury Weapon",
    [2643] = "Windfury Weapon",
    [2644] = "Windfury Weapon",
    [2645] = "Windfury Weapon",
    [5401] = "Windfury Weapon",

    -- Earthliving Weapon (Classic / Camelot ranks 1-6 + Retail)
    [3345] = "Earthliving Weapon",
    [3346] = "Earthliving Weapon",
    [3347] = "Earthliving Weapon",
    [3348] = "Earthliving Weapon",
    [3349] = "Earthliving Weapon",
    [3350] = "Earthliving Weapon",
    [6498] = "Earthliving Weapon",
}

local function GetSlotWeaponEnchant(slot)
    -- slot is 16 (main hand) or 17 (off hand)
    -- 1. Modern C_PaperDollInfo API (authoritative native engine API on Camelot 1.60.1 and Retail)
    local cPaperDoll = _G.C_PaperDollInfo
    if cPaperDoll and cPaperDoll.GetTemporaryEnchantmentInfo then
        local info = cPaperDoll.GetTemporaryEnchantmentInfo(slot)
        if info then
            local expSec = (info.remainingTimeMs or 0) / 1000
            local charges = info.chargesRemaining or 0
            local enchantID = info.enchantID
            return true, expSec, charges, enchantID
        end
    end

    -- 2. C_Item.GetWeaponEnchantInfo (TOC 11.0+ / 1.60.1)
    local cItem = _G.C_Item
    local enumTable = _G.Enum
    if cItem and cItem.GetWeaponEnchantInfo and enumTable and enumTable.WeaponSlot then
        local weaponSlot = (slot == 17) and enumTable.WeaponSlot.OffHand or enumTable.WeaponSlot.MainHand
        local enchants = cItem.GetWeaponEnchantInfo(weaponSlot)
        if enchants then
            for _, ench in pairs(enchants) do
                if ench.hasEnchant then
                    local expSec = ench.timeLeft and (ench.timeLeft / 1000) or 0
                    local charges = ench.charges or 0
                    local enchantID = ench.enchantID
                    return true, expSec, charges, enchantID
                end
            end
        end
    end

    -- 3. Legacy GetWeaponEnchantInfo()
    local getWepEnchant = _G.GetWeaponEnchantInfo
    if getWepEnchant then
        local hasMH, expMH, chargesMH, idMH, hasOH, expOH, chargesOH, idOH = getWepEnchant()
        if slot == 16 and hasMH then
            local expSec = expMH and (expMH / 1000) or 0
            return true, expSec, chargesMH or 0, idMH
        elseif slot == 17 and hasOH then
            local expSec = expOH and (expOH / 1000) or 0
            return true, expSec, chargesOH or 0, idOH
        end
    end

    return false, 0, 0, nil
end
sfui.buffs.scan.GetSlotWeaponEnchant = GetSlotWeaponEnchant

local function GetActiveWeaponEnchantName(slot, enchantID)
    if enchantID and ENCHANT_ID_TO_NAME[enchantID] then
        return ENCHANT_ID_TO_NAME[enchantID]
    end

    local cTooltip = _G.C_TooltipInfo
    if cTooltip and cTooltip.GetInventoryItem then
        local tipData = cTooltip.GetInventoryItem("player", slot)
        if tipData and tipData.lines then
            for i = 1, #tipData.lines do
                local line = tipData.lines[i]
                local txt = line and line.leftText
                if txt then
                    local lower = txt:lower()
                    if lower:find("rockbiter", 1, true) then return "Rockbiter Weapon"
                    elseif lower:find("flametongue", 1, true) then return "Flametongue Weapon"
                    elseif lower:find("frostbrand", 1, true) then return "Frostbrand Weapon"
                    elseif lower:find("windfury", 1, true) then return "Windfury Weapon"
                    elseif lower:find("earthliving", 1, true) then return "Earthliving Weapon"
                    end
                end
            end
        end
    end

    local tip = sfui.tooltip or _G.SfuiGameTooltip
    if tip and tip.SetInventoryItem then
        if tip.SetOwner and _G.UIParent then
            tip:SetOwner(_G.UIParent, "ANCHOR_NONE")
        end
        tip:ClearLines()
        tip:SetInventoryItem("player", slot)
        local numLines = tip:NumLines() or 0
        for i = 1, numLines do
            local fsL = _G["SfuiGameTooltipTextLeft" .. i]
            if fsL then
                local txt = fsL:GetText()
                if txt then
                    local lower = txt:lower()
                    if lower:find("rockbiter", 1, true) then return "Rockbiter Weapon"
                    elseif lower:find("flametongue", 1, true) then return "Flametongue Weapon"
                    elseif lower:find("frostbrand", 1, true) then return "Frostbrand Weapon"
                    elseif lower:find("windfury", 1, true) then return "Windfury Weapon"
                    elseif lower:find("earthliving", 1, true) then return "Earthliving Weapon"
                    end
                end
            end
        end
    end
    return nil
end
sfui.buffs.scan.GetActiveWeaponEnchantName = GetActiveWeaponEnchantName

local function GetItemEquipLoc(itemLink)
    if not itemLink then return nil end
    if data and data.GetItemEquipLoc then
        local loc = data.GetItemEquipLoc(itemLink)
        if loc and loc ~= "" then return loc end
    end
    local common = sfui.common
    if common and common.get_item_equip_loc then
        local loc = common.get_item_equip_loc(itemLink)
        if loc and loc ~= "" then return loc end
    end
    if common and common.get_item_instant_info then
        local loc = select(4, common.get_item_instant_info(itemLink))
        if loc and loc ~= "" then return loc end
    end
    if common and common.get_item_info then
        local loc = select(9, common.get_item_info(itemLink))
        if loc and loc ~= "" then return loc end
    end
    local cItem = _G.C_Item
    local getInstant = (cItem and cItem.GetItemInfoInstant) or _G.GetItemInfoInstant
    if getInstant then
        local loc = select(4, getInstant(itemLink))
        if loc and loc ~= "" then return loc end
    end
    local getInfo = (cItem and cItem.GetItemInfo) or _G.GetItemInfo
    if getInfo then
        local loc = select(9, getInfo(itemLink))
        if loc and loc ~= "" then return loc end
    end
    return nil
end
sfui.buffs.scan.GetItemEquipLoc = GetItemEquipLoc

local function ScanWeaponEnchant(entry)
    local slot = entry.slot or 16
    local getInvItemID = _G.GetInventoryItemID
    local getInvItemLink = _G.GetInventoryItemLink
    local itemID = getInvItemID and getInvItemID("player", slot)
    local itemLink = getInvItemLink and getInvItemLink("player", slot)
    if not itemID and not itemLink then
        -- No item equipped in this slot: nothing to remind
        return true, 0, 0, 0, nil
    end

    local pClass = sfui.buffs.playerClass or (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())

    local isPole = sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped()
    if entry.isFishingLure then
        if not isPole then
            return true, 0, 0, 0, nil
        end
        local hasMH, expSec, chargesMH = GetSlotWeaponEnchant(16)
        local skillRank = (sfui.fishing and sfui.fishing.GetSkill and sfui.fishing.GetSkill()) or 0
        local bestLure = sfui.fishing_data and sfui.fishing_data.FindBestLureInBags and sfui.fishing_data.FindBestLureInBags(skillRank)
        local lureIcon = nil
        if bestLure and bestLure.itemID then
            lureIcon = (sfui.common and sfui.common.get_item_instant_info and select(5, sfui.common.get_item_instant_info(bestLure.itemID)))
                or (_G.C_Item and _G.C_Item.GetItemIconByID and _G.C_Item.GetItemIconByID(bestLure.itemID))
                or (_G.GetItemIcon and _G.GetItemIcon(bestLure.itemID))
        end
        lureIcon = lureIcon or entry.fallbackIcon

        if not hasMH then
            return false, 0, 0, 0, lureIcon, nil
        end
        local now = GetTime()
        return true, 600, now + expSec, chargesMH or 0, lureIcon, "Fishing Lure"
    elseif isPole then
        return true, 0, 0, 0, nil
    end

    if slot == 16 then
        local hasMH, expSec, chargesMH, idMH = GetSlotWeaponEnchant(16)
        local activeEnchant = hasMH and GetActiveWeaponEnchantName(16, idMH)
        local _, castIcon = data.GetBestCastSpell(entry, activeEnchant)

        if not hasMH then
            return false, 0, 0, 0, castIcon, activeEnchant
        end
        local now = GetTime()
        return true, 1800, now + expSec, chargesMH or 0, castIcon, activeEnchant
    elseif slot == 17 then
        -- Check if main hand is a 2-Handed weapon: if so, off hand cannot hold a weapon
        local mhRef = (getInvItemLink and getInvItemLink("player", 16)) or (getInvItemID and getInvItemID("player", 16))
        if mhRef then
            local mhEquipLoc = GetItemEquipLoc(mhRef)
            if mhEquipLoc == "INVTYPE_2HWEAPON" then
                return true, 0, 0, 0, nil
            end
        end

        local ohRef = itemLink or itemID
        local equipLoc = ohRef and GetItemEquipLoc(ohRef)
        -- Off hand slot must be an actual weapon (1H or Off Hand only)
        -- Shields (INVTYPE_SHIELD) and held in off-hand frills (INVTYPE_HOLDABLE) can NEVER be imbued!
        if equipLoc and (equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE") then
            return true, 0, 0, 0, nil
        end

        -- If player is Shaman on Classic / Camelot, Shamans cannot dual wield
        if pClass == "SHAMAN" and (sfui.isCamelot or sfui.isClassic) then
            return true, 0, 0, 0, nil
        end

        local hasOH, expSec, chargesOH, idOH = GetSlotWeaponEnchant(17)
        local activeEnchant = hasOH and GetActiveWeaponEnchantName(17, idOH)
        local _, castIcon = data.GetBestCastSpell(entry, activeEnchant)

        if not hasOH then
            return false, 0, 0, 0, castIcon, activeEnchant
        end
        local now = GetTime()
        return true, 1800, now + expSec, chargesOH or 0, castIcon, activeEnchant
    end

    return true, 0, 0, 0, nil
end

local function ScanPet(entry)
    if IsMounted and IsMounted() then
        return true, 0, 0, 0, nil
    end
    if UnitOnTaxi and UnitOnTaxi("player") then
        return true, 0, 0, 0, nil
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return true, 0, 0, 0, nil
    end

    local hasPet = UnitExists("pet") and not (UnitIsDead and UnitIsDead("pet"))
    if hasPet then
        return true, 0, 0, 0, nil
    end

    local petIcon = nil
    if sfui.buffs.pets and sfui.buffs.pets.GetSelectedPet then
        local selectedPet = sfui.buffs.pets.GetSelectedPet()
        if selectedPet and selectedPet.icon then
            petIcon = selectedPet.icon
        end
    end

    return false, 0, 0, 0, petIcon
end

local MIN_TRACKING_ID = 2580
local HERB_TRACKING_ID = 2383
local MIN_TRACKING_LOWER = "find minerals"
local HERB_TRACKING_LOWER = "find herbs"
local MIN_TRACKING_ICON = "Interface\\Icons\\Spell_Nature_Earthquake"
local HERB_TRACKING_ICON = "Interface\\Icons\\Spell_Nature_NatureTouchGrow"

local function IsTrackingActive(spellID, targetLower, targetTexture)
    -- 1. Modern / Camelot C_Minimap API
    local cMinimap = _G.C_Minimap
    if cMinimap and cMinimap.GetNumTrackingTypes and cMinimap.GetTrackingInfo then
        local count = cMinimap.GetNumTrackingTypes() or 0
        for i = 1, count do
            local info = cMinimap.GetTrackingInfo(i)
            if info and info.active then
                if spellID and info.spellID and info.spellID == spellID then
                    return true, info.texture
                end
                if targetLower and info.name and string_lower(info.name) == targetLower then
                    return true, info.texture
                end
            end
        end
        return false, nil
    end

    -- 2. Classic / Legacy global GetTrackingInfo
    if _G.GetNumTrackingTypes and _G.GetTrackingInfo then
        local count = _G.GetNumTrackingTypes() or 0
        for i = 1, count do
            local tName, texture, active = _G.GetTrackingInfo(i)
            if active then
                if targetLower and tName and string_lower(tName) == targetLower then
                    return true, texture
                end
            end
        end
        return false, nil
    end

    -- 3. Fallback: GetTrackingTexture
    if _G.GetTrackingTexture then
        local tex = _G.GetTrackingTexture()
        if tex and tex ~= "" then
            if targetTexture and tex == targetTexture then
                return true, tex
            end
            if spellID and data and data.ResolveTexture then
                local res = data.ResolveTexture(spellID, targetTexture)
                if res and tex == res then
                    return true, tex
                end
            end
        end
    end

    return false, nil
end

local function ScanTracking(entry, disabledBuffs)
    -- Check if both gathering tracking spells are currently known and enabled in options
    local minKnownAndEnabled = knownCache["tracking_minerals"] and not (disabledBuffs and disabledBuffs["tracking_minerals"])
    local herbKnownAndEnabled = knownCache["tracking_herbs"] and not (disabledBuffs and disabledBuffs["tracking_herbs"])
    local bothGathering = minKnownAndEnabled and herbKnownAndEnabled

    if bothGathering then
        -- In Classic / Camelot, minimap tracking is mutually exclusive (only one tracking type active at a time).
        -- If player has both Mining & Herbalism learned and enabled,
        -- having either gathering tracking active satisfies the reminder so the player is not permanently nagged.
        local minActive, minTex = IsTrackingActive(MIN_TRACKING_ID, MIN_TRACKING_LOWER, MIN_TRACKING_ICON)
        if minActive then
            return true, 0, 0, 0, minTex
        end
        local herbActive, herbTex = IsTrackingActive(HERB_TRACKING_ID, HERB_TRACKING_LOWER, HERB_TRACKING_ICON)
        if herbActive then
            return true, 0, 0, 0, herbTex
        end
        -- Neither is active: both reminder icons appear so the player can click their desired tracking
        return false, 0, 0, 0, nil
    end

    -- Single gathering profession known/enabled: check only the relevant tracking spell
    local isTargetMinerals = (entry.key == "tracking_minerals")
    local spellID = isTargetMinerals and MIN_TRACKING_ID or HERB_TRACKING_ID
    local targetLower = isTargetMinerals and MIN_TRACKING_LOWER or HERB_TRACKING_LOWER
    local fallbackTex = isTargetMinerals and MIN_TRACKING_ICON or HERB_TRACKING_ICON

    local isActive, activeTex = IsTrackingActive(spellID, targetLower, fallbackTex)
    if isActive then
        return true, 0, 0, 0, activeTex
    end
    return false, 0, 0, 0, nil
end

local scanners = {
    aura = ScanPlayerAura,
    aura_group = ScanPlayerAura,
    stance = ScanStance,
    weapon_enchant = ScanWeaponEnchant,
    pet = ScanPet,
    tracking = ScanTracking,
}
sfui.buffs.scan._scanners = scanners

--- Scans all registered class buffs and populates activeResults
--- @return table array of scanned reminder records
function sfui.buffs.scan.RunScan()
    -- Bypass Blizzard API queries completely during combat, aura secrecy, or death
    if sfui.common.is_in_combat() or AreAurasSecret() then
        dirty = true
        return activeResults
    end

    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        dirty = true
        return activeResults
    end

    if not entries then
        RefreshSpellKnowledge()
    end

    CollectPlayerAuras()

    local count = 0
    local now = GetTime()

    local cfg = SfuiDB and SfuiDB.buffReminders
    local disabledBuffs = cfg and cfg.disabledBuffs
    local allowExpiring = not cfg or (cfg.showExpiring ~= false)
    local thresholdLong = (cfg and cfg.thresholdLong) or 300
    local thresholdShort = (cfg and cfg.thresholdShort) or 60
    local providers = sfui.buffs.providers

    for i = 1, #entries do
        local entry = entries[i]
        local isKnown = knownCache[entry.key]
        local isBuffDisabled = disabledBuffs and disabledBuffs[entry.key]

        if isKnown and not isBuffDisabled then
            local provider = providers and providers.Resolve(entry)
            local scanFn = (provider and provider.scan)
                or scanners[(provider and provider.scanType) or entry.type]
            local hasBuff, duration, expTime, charges, icon, extraData = false, 0, 0, 0, nil, nil
            if scanFn then
                hasBuff, duration, expTime, charges, icon, extraData = scanFn(entry, disabledBuffs)
            end

            local baseThreshold = entry.threshold or 300
            local effectiveThreshold = (baseThreshold > 60) and thresholdLong or thresholdShort
            if duration and duration > 0 and duration <= 300 and effectiveThreshold >= duration then
                effectiveThreshold = thresholdShort
            end

            local isExpiring = false
            if allowExpiring and hasBuff and expTime and expTime > 0 and effectiveThreshold > 0 then
                local remaining = expTime - now
                if remaining > 0 and remaining <= effectiveThreshold then
                    isExpiring = true
                end
            end

            local isMissing = not hasBuff
            local shouldInclude = isMissing or isExpiring

            if shouldInclude then
                count = count + 1
                local rec = activeResults[count]
                if not rec then
                    rec = {}
                    activeResults[count] = rec
                end

                rec.entry = entry
                rec.hasBuff = hasBuff
                rec.isMissing = isMissing
                rec.isExpiring = isExpiring
                rec.expirationTime = expTime or 0
                rec.duration = duration or 0
                rec.charges = charges or 0
                if provider and provider.resolveScanIcon then
                    icon = provider.resolveScanIcon(entry, icon)
                end
                rec.icon = icon or (entry.spellIDs and data.ResolveTexture(entry.spellIDs[1], entry.fallbackIcon)) or entry.fallbackIcon
                rec.activeEnchant = extraData
                rec.unit = nil
                rec.unitName = nil
                rec.unitClass = nil
                rec.unitSpecLabel = nil
            end
        end
    end

    if sfui.buffs.party and sfui.buffs.party.AppendPartyReminders then
        count = sfui.buffs.party.AppendPartyReminders(activeResults, count, now, cfg)
    end

    -- Trim surplus reusable entries
    for i = count + 1, #activeResults do
        activeResults[i] = nil
    end

    dirty = false

    -- Only notify the radial ring provider if the active reminder results actually changed
    local resultsChanged = (lastResultCount ~= count)
    if not resultsChanged then
        for i = 1, count do
            local rec = activeResults[i]
            local prev = prevResultKeys[i]
            if not rec or not prev or rec.entry.key ~= prev.key or rec.isMissing ~= prev.isMissing or rec.isExpiring ~= prev.isExpiring then
                resultsChanged = true
                break
            end
        end
    end

    if resultsChanged then
        lastResultCount = count
        for i = 1, count do
            local rec = activeResults[i]
            local p = prevResultKeys[i]
            if not p then
                p = {}
                prevResultKeys[i] = p
            end
            p.key = rec.entry.key
            p.isMissing = rec.isMissing
            p.isExpiring = rec.isExpiring
        end
        for i = count + 1, #prevResultKeys do
            prevResultKeys[i] = nil
        end
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
    end

    return activeResults
end

--- Returns cached results without rescanning if clean
function sfui.buffs.scan.GetResults()
    if dirty then
        return sfui.buffs.scan.RunScan()
    end
    return activeResults
end

--- Marks the scan state dirty and schedules a throttled update
function sfui.buffs.scan.RequestScan()
    if sfui.common.is_in_combat() or AreAurasSecret() then
        dirty = true
        return
    end

    dirty = true
    if throttleTimer then return end

    -- C_Timer.After returns nil, so track the pending state with a flag
    throttleTimer = true
    C_Timer.After(0.08, function()
        throttleTimer = nil
        if sfui.common.is_in_combat() or AreAurasSecret() then
            dirty = true
            return
        end
        sfui.buffs.scan.RunScan()
        if sfui.buffs.UpdateDisplay then
            sfui.buffs.UpdateDisplay()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
--  CENTRAL EVENT ROUTING (sfui.events)
-- ─────────────────────────────────────────────────────────────
local function InitScanEvents()
    -- Only active on Camelot / Classic clients
    if not sfui.isCamelot and not sfui.isClassic then return end
    if not sfui.events then return end

    local function on_player_unit_change()
        sfui.buffs.scan.RequestScan()
    end

    local function on_knowledge_change()
        if sfui.talents and sfui.talents.invalidate_protection_paladin_cache then
            sfui.talents.invalidate_protection_paladin_cache()
        end
        if sfui.buffs.pets and sfui.buffs.pets.InvalidatePetCache then
            sfui.buffs.pets.InvalidatePetCache()
        end
        if sfui.buffs.paladin and sfui.buffs.paladin.InvalidateCache then
            sfui.buffs.paladin.InvalidateCache()
        end
        if sfui.buffs.party and sfui.buffs.party.InvalidateSpecCache then
            sfui.buffs.party.InvalidateSpecCache()
        end
        RefreshSpellKnowledge()
        sfui.buffs.scan.RequestScan()
    end

    -- C-level unit filtered events: only invoke Lua when the player token updates
    sfui.events.RegisterUnitEvent("UNIT_AURA", "player", on_player_unit_change)
    if sfui.buffs.playerClass == "PALADIN" then
        sfui.events.RegisterUnitEvent("UNIT_AURA", "party1", on_player_unit_change)
        sfui.events.RegisterUnitEvent("UNIT_AURA", "party2", on_player_unit_change)
        sfui.events.RegisterUnitEvent("UNIT_AURA", "party3", on_player_unit_change)
        sfui.events.RegisterUnitEvent("UNIT_AURA", "party4", on_player_unit_change)
    end
    sfui.events.RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player", on_player_unit_change)
    sfui.events.RegisterUnitEvent("UNIT_PET", "player", on_player_unit_change)

    -- Weapon temporary enchants & equipment events
    sfui.events.RegisterEvent("WEAPON_ENCHANT_CHANGED", on_player_unit_change)
    sfui.events.RegisterEvent("WEAPON_SLOT_CHANGED", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", on_player_unit_change)
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", on_player_unit_change)

    -- Global state events
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_ALIVE", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_UNGHOST", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_player_unit_change)
    sfui.events.RegisterEvent("PLAYER_UPDATE_RESTING", on_player_unit_change)
    sfui.events.RegisterEvent("MINIMAP_UPDATE_TRACKING", on_knowledge_change)
    sfui.events.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", on_player_unit_change)

    -- Periodic safety refresh for temporary weapon enchants and time-expiring buffs
    local cTimer = _G.C_Timer
    if cTimer and cTimer.NewTicker then
        cTimer.NewTicker(3.0, function()
            if not sfui.common.is_in_combat() then
                sfui.buffs.scan.RequestScan()
            end
        end)
    end

    -- Talent, spec, gearset, & spell changes
    sfui.events.RegisterEvent("SPELLS_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", on_knowledge_change)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", on_knowledge_change)
    sfui.events.RegisterEvent("PET_STABLE_UPDATE", on_knowledge_change)
    sfui.events.RegisterEvent("PLAYER_ROLES_ASSIGNED", on_knowledge_change)
    sfui.events.RegisterEvent("GROUP_ROSTER_UPDATE", on_knowledge_change)
    sfui.events.RegisterEvent("EQUIPMENT_SETS_CHANGED", on_knowledge_change)
    sfui.events.RegisterEvent("EQUIPMENT_SWAP_FINISHED", on_knowledge_change)
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", on_knowledge_change)
        sfui.events.RegisterMessage("SFUI_GEAR_ROLE_CHANGED", on_knowledge_change)
    end

    -- Combat state transitions
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if sfui.buffs and sfui.buffs.OnCombatEnter then
            sfui.buffs.OnCombatEnter()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if sfui.buffs and sfui.buffs.OnCombatLeave then
            sfui.buffs.OnCombatLeave()
        end
        sfui.buffs.scan.RequestScan()

        -- Safety delayed retries in case client engine was still in lockdown or aura secrecy during event frame
        local cTimer = _G.C_Timer
        if cTimer and cTimer.After then
            cTimer.After(0.15, function()
                if not sfui.common.is_in_combat() and not InCombatLockdown() and not AreAurasSecret() then
                    sfui.buffs.scan.RequestScan()
                    if sfui.buffs and sfui.buffs.UpdateDisplay then
                        sfui.buffs.UpdateDisplay()
                    end
                end
            end)
            cTimer.After(0.35, function()
                if not sfui.common.is_in_combat() and not InCombatLockdown() and not AreAurasSecret() then
                    if sfui.buffs and sfui.buffs.UpdateDisplay then
                        sfui.buffs.UpdateDisplay()
                    end
                end
            end)
        end
    end)
end
InitScanEvents()

local _scanDebug = {}
function sfui.buffs.scan.GetDebugInfo()
    _scanDebug.activeResults = #activeResults
    _scanDebug.auraPoolCount = #auraRecordPool
    return _scanDebug
end


