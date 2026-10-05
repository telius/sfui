local addonName, addon = ...
sfui = sfui or {}
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
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local table = _G.table
local string = _G.string
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
local GetTime = _G.GetTime

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

local function hide_tooltip()
    if sfui.tooltip and sfui.tooltip:IsShown() then
        sfui.tooltip:Hide()
    end
    if _G.GameTooltip and _G.GameTooltip:IsShown() then
        _G.GameTooltip:Hide()
    end
end

-- -------------------------------------------------------------------------
-- ENGINE STATE
-- -------------------------------------------------------------------------
local gearEquipQueue = nil
local bagUpdatePending = false
local zoneUpdateQueue = false
local updateScheduled = false
local regenRetries = 0
local manualEditUntil = 0
local nakedPaused = false
local roleEquipTimer = nil
local lastEquippedItems = {}
local equipSetOptionsCache = nil
local lastSpecID = nil

--- Call this to pause automatic equipping from bag changes for `sec` seconds (default 60).
sfui.gear.pauseAutoEquip = function(sec)
    manualEditUntil = GetTime() + (sec or 10)
end

function sfui.gear.isNakedPaused()
    return nakedPaused
end

function sfui.gear.SetNakedPaused(paused, silent)
    nakedPaused = paused and true or false
    if roleEquipTimer then
        roleEquipTimer:Cancel()
        roleEquipTimer = nil
    end
    if nakedPaused then
        gearEquipQueue = nil
    else
        if sfui.gear.StopUnequipDurabilityItems then
            sfui.gear.StopUnequipDurabilityItems()
        end
    end
    sfui.gear.UpdateStatUI()
end

local function autoEquipPaused()
    return nakedPaused or GetTime() < manualEditUntil or (CharacterFrame and CharacterFrame:IsShown() == true)
end

local function isCurrentlyPvP()
    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()
    return (instanceType == "pvp" or instanceType == "arena")
        or (instanceType == "none" and isWarMode)
end
sfui.gear.isCurrentlyPvP = isCurrentlyPvP

local function isClassicOrVanilla()
    if sfui.isRetail then return false end
    return true
end
sfui.gear.isClassicOrVanilla = isClassicOrVanilla

-- Returns true if the correct gear set for the current zone/spec is already equipped
local function isGearSetEquipped()
    if not SfuiDB or not SfuiDB.gear then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then return false end
    local spec = common.get_current_spec_id()
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
sfui.gear.isGearSetEquipped = isGearSetEquipped

-- Unified auto-equip enable check
local function isAutoEquipEnabled()
    if not SfuiDB or not SfuiDB.gear then return false end
    local v = SfuiDB.gear.auto_equip_highest
    if v == nil then return true end
    return v
end
sfui.gear.isAutoEquipEnabled = isAutoEquipEnabled

local function setAutoEquipEnabled(val)
    SfuiDB = SfuiDB or {}
    SfuiDB.gear = SfuiDB.gear or {}
    SfuiDB.gear.auto_equip_highest = val
end
sfui.gear.setAutoEquipEnabled = setAutoEquipEnabled

local function _OnUpdateCastTimer()
    updateScheduled = false
    sfui.gear.Update()
end

local function TryEquipSet(setName)
    if nakedPaused then return false end
    if not setName or setName == "" then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetID then return false end
    local isPole = (sfui.highest.IsFishingPoleEquipped and sfui.highest.IsFishingPoleEquipped())
        or (sfui.gear.IsFishingPoleEquipped and sfui.gear.IsFishingPoleEquipped())
        or (sfui.fishing and sfui.fishing.IsFishingPoleEquipped and sfui.fishing.IsFishingPoleEquipped())
    local isSession = sfui.fishing and sfui.fishing.IsSessionActive and sfui.fishing.IsSessionActive()
    if isPole and isSession then return false end
    local setID = C_EquipmentSet.GetEquipmentSetID(setName)
    if setID then
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if isEquipped then return false end
        if InCombatLockdown() then
            gearEquipQueue = setID
            common.run_after_combat(sfui.gear.handle_player_regen)
            return false
        end
        if UnitCastingInfo("player") or UnitChannelInfo("player") then
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
        sfui.common.print("automatically equipped set: " .. (name or setName or ""))
        return true
    end
    return false
end
sfui.gear.TryEquipSet = TryEquipSet

function sfui.gear.GetEquipmentSetOptions()
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
-- GEAR UPDATE (AUTO EQUIP)
-- -------------------------------------------------------------------------
function sfui.gear.Update(force)
    if nakedPaused then return end
    if not isAutoEquipEnabled() and not force then return end
    if not SfuiDB.gear then return end
    local spec = common.get_current_spec_id()
    if spec == 0 then return end
    local db = SfuiDB.gear[spec]

    local pveSet = db and db.pve_set or ""
    local pvpSet = db and db.pvp_set or ""
    local _, instanceType = GetInstanceInfo()
    local isWarMode = isWarModeDesired()

    local isPvP = (instanceType == "pvp" or instanceType == "arena")
        or (instanceType == "none" and isWarMode)

    local targetSet = nil
    if instanceType == "pvp" or instanceType == "arena" then
        targetSet = pvpSet ~= "" and pvpSet or nil
    elseif instanceType == "party" or instanceType == "raid" or instanceType == "scenario" or instanceType == "delve" then
        targetSet = pveSet ~= "" and pveSet or nil
    elseif instanceType == "none" then
        targetSet = isPvP and (pvpSet ~= "" and pvpSet or nil) or (pveSet ~= "" and pveSet or nil)
    end

    local setEquipped = false
    if targetSet then
        setEquipped = TryEquipSet(targetSet)
    end

    if setEquipped then return end
    if not force and targetSet and targetSet ~= "" and isGearSetEquipped() then return end
    if not force and autoEquipPaused() then return end

    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        if not updateScheduled then
            updateScheduled = true
            C_Timer.After(0.25, _OnUpdateCastTimer)
        end
        return
    end

    if not InCombatLockdown() and not UnitIsDeadOrGhost("player") then
        local shouldEquip = isAutoEquipEnabled()
        if shouldEquip and sfui.highest and sfui.highest.EquipHighestILvl then
            sfui.highest.EquipHighestILvl(isPvP, true)
        end
    end
end

-- -------------------------------------------------------------------------
-- SCAN EQUIPPED ITEMS
-- -------------------------------------------------------------------------
local function scanEquippedForChanges()
    if not SfuiGearManagerFrame or not SfuiGearManagerFrame:IsShown() then return end
    if not SfuiDB or not SfuiDB.gear then return end

    local spec = common.get_current_spec_id()
    if not spec or spec == 0 then return end

    local usesAmmo = sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
    local startSlot = usesAmmo and 0 or 1
    for slotID = startSlot, 18 do
        if slotID ~= 4 then
            local link = GetInventoryItemLink("player", slotID)
            local currentID = link and GetItemInfoInstant(link)
            lastEquippedItems[slotID] = currentID
        end
    end

    sfui.gear.UpdateStatUI()
end

-- -------------------------------------------------------------------------
-- REGEN HANDLER
-- -------------------------------------------------------------------------
local function _OnRegenRetryTimer()
    if gearEquipQueue and not InCombatLockdown() then
        sfui.gear.handle_player_regen()
    end
end

function sfui.gear.handle_player_regen()
    if nakedPaused then
        gearEquipQueue = nil
        return
    end
    if gearEquipQueue then
        if not UnitCastingInfo("player") and not UnitChannelInfo("player") and not UnitIsDeadOrGhost("player") then
            if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo then
                local name = C_EquipmentSet.GetEquipmentSetInfo(gearEquipQueue)
                if C_EquipmentSet.UseEquipmentSet then
                    C_EquipmentSet.UseEquipmentSet(gearEquipQueue)
                end
                if name then
                    common.print("equipped queued set: " .. name)
                end
            end
            gearEquipQueue = nil
            regenRetries = 0
        elseif regenRetries < 5 then
            regenRetries = regenRetries + 1
            C_Timer.After(2.0, _OnRegenRetryTimer)
        else
            gearEquipQueue = nil
            regenRetries = 0
        end
    end
    if zoneUpdateQueue then
        zoneUpdateQueue = false
        sfui.gear.Update()
    end
end

-- -------------------------------------------------------------------------
-- EVENT LISTENERS
-- -------------------------------------------------------------------------
sfui.events.RegisterEvent("EQUIPMENT_SETS_CHANGED", function()
    equipSetOptionsCache = nil
end)

sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
    equipSetOptionsCache = nil
    scanEquippedForChanges()
end)

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    sfui.gear.handle_player_regen()
end)

sfui.events.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    equipSetOptionsCache = nil
    if InCombatLockdown() then
        zoneUpdateQueue = true
        common.run_after_combat(sfui.gear.handle_player_regen)
    else
        sfui.gear.Update()
    end
end)

local function _OnBagUpdateDebounce()
    bagUpdatePending = false
    sfui.gear.Update()
end

sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
    if not bagUpdatePending then
        bagUpdatePending = true
        C_Timer.After(0.4, _OnBagUpdateDebounce)
    end
end)

local function onSpecOrTalentChanged()
    equipSetOptionsCache = nil
    local currentSpecID = common.get_current_spec_id()
    if lastSpecID ~= currentSpecID then
        lastSpecID = currentSpecID
        if SfuiGearManagerFrame and SfuiGearManagerFrame.SelectSpecTab and SfuiGearManagerFrame:IsShown() then
            SfuiGearManagerFrame:SelectSpecTab(currentSpecID)
        end
        sfui.gear.Update(true)
    else
        sfui.gear.UpdateStatUI()
    end
end

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onSpecOrTalentChanged)
sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", onSpecOrTalentChanged)

sfui.events.RegisterEvent("PLAYER_LOGIN", function()
    if not SfuiDB or not SfuiDB.gear then return end
    local spec = common.get_current_spec_id()
    if not spec or spec == 0 then return end
    lastSpecID = spec
    if SfuiGearManagerFrame and SfuiGearManagerFrame.SelectSpecTab then
        SfuiGearManagerFrame:SelectSpecTab(spec)
    end
    sfui.gear.UpdateStatUI()
end)

-- -------------------------------------------------------------------------
-- CHARACTER FRAME TOGGLE BUTTON HOOK
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
        sfui.gear.pauseAutoEquip(10)
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
                    elseif slot == 0 then
                        slotName = "ammo"
                    end

                    if SfuiDB.gear[specID][key][itemID] then
                        SfuiDB.gear[specID][key][itemID] = nil
                        sfui.common.print(string.format("%s unlocked (%s): %s", slotName, ctxPvP and "pvp" or "pve", link))
                    else
                        SfuiDB.gear[specID][key][itemID] = true
                        sfui.common.print(string.format("%s locked (%s): %s", slotName, ctxPvP and "pvp" or "pve", link))
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
        "CharacterAmmoSlot",
    }
    for _, slotName in ipairs(slotsToHook) do
        local slotFrame = _G[slotName]
        if slotFrame then
            slotFrame:HookScript("OnClick", onPaperDollClick)
        end
    end
end

-- -------------------------------------------------------------------------
-- MODULE INITIALIZATION
-- -------------------------------------------------------------------------
function sfui.gear.initialize()
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
    if SfuiDB and SfuiDB.gear_char and SfuiDB.gear then
        if SfuiDB.gear.auto_equip_highest == nil then
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

    local usesAmmo = sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player")
    local startSlot = usesAmmo and 0 or 1
    for slotID = startSlot, 18 do
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

sfui.gear.OnEnable = function(self) self.initialize() end
sfui.gear.OnSpecChanged = function(self, specID) self.Update() end
sfui.gear.GetDebugInfo = sfui.gear_debug_info
sfui.RegisterModule("gear", sfui.gear)
