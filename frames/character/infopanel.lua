local addonName, addon = ...
sfui = sfui or {}
sfui.character = sfui.character or {}
sfui.character.infopanel = {}

local panelModule = sfui.character.infopanel

-- Guard: Exclude Retail (Camelot & Classic only)
if sfui.isRetail then
    return
end

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/character/infopanel.lua
--  Slide-Out Combat Telemetry & Boss Glancing Blow Information Panel
--  Authoritatively grounded in Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua
--  and Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local CharacterFrame = _G.CharacterFrame
local CharacterFrameCloseButton = _G.CharacterFrameCloseButton
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format
local tostring = _G.tostring
local tonumber = _G.tonumber
local pairs = _G.pairs
local ipairs = _G.ipairs
local UnitLevel = _G.UnitLevel
local UnitClass = _G.UnitClass
local UnitDefenseSkill = _G.UnitDefenseSkill
local UnitPowerType = _G.UnitPowerType
local UnitUsesAmmo = _G.UnitUsesAmmo
local GetGlancingBlowChance = _G.GetGlancingBlowChance
local GetGlancingBlowPenalty = _G.GetGlancingBlowPenalty
local GetOffhandHitModifier = _G.GetOffhandHitModifier
local GetHitModifier = _G.GetHitModifier
local GetRangedHitModifier = _G.GetRangedHitModifier
local GetSpellHitModifier = _G.GetSpellHitModifier
local GetCritChance = _G.GetCritChance
local GetRangedCritChance = _G.GetRangedCritChance
local GetSpellCritChance = _G.GetSpellCritChance
local GetDodgeChance = _G.GetDodgeChance
local GetParryChance = _G.GetParryChance
local GetBlockChance = _G.GetBlockChance
local GetShieldBlock = _G.GetShieldBlock
local GetArmorPenetration = _G.GetArmorPenetration
local GetSpellPenetration = _G.GetSpellPenetration
local GetManaRegen = _G.GetManaRegen
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring
local C_Item = _G.C_Item
local C_SkillInfo = _G.C_SkillInfo
local Enum = _G.Enum

-- Static color constants to eliminate runtime table allocations on updates
local COLOR_GREEN        = { 0.3, 1.0, 0.3 }
local COLOR_WHITE        = { 1.0, 1.0, 1.0 }
local COLOR_YELLOW       = { 1.0, 0.82, 0.2 }
local COLOR_RED          = { 1.0, 0.4, 0.4 }
local COLOR_RED_ALERT    = { 1.0, 0.3, 0.3 }
local COLOR_ORANGE       = { 1.0, 0.6, 0.2 }
local COLOR_LIGHT_BLUE   = { 0.8, 0.8, 1.0 }
local COLOR_DIM          = { 0.7, 0.7, 0.7 }
local COLOR_LIGHT_GRAY   = { 0.85, 0.85, 0.85 }
local COLOR_LIGHT_GRAY_2 = { 0.9, 0.9, 0.9 }
local COLOR_MID_GRAY     = { 0.8, 0.8, 0.8 }
local COLOR_MANA_BLUE    = { 0.4, 0.8, 1.0 }
local COLOR_PURPLE_BLUE  = { 0.85, 0.85, 1.0 }
local COLOR_ACCENT_FALLBACK = { 0.4, 0.8, 1.0 }

-- Target Calculations (Dynamic: Character Level + 3)
local TARGET_LEVEL_OFFSET = 3

--- Get target boss stats based on player level
--- @param pLevel number?
--- @return number targetLevel, number targetDefenseSkill, number targetWeaponSkill
local function GetTargetBossStats(pLevel)
    pLevel = pLevel or UnitLevel("player") or 60
    local targetLevel = pLevel + TARGET_LEVEL_OFFSET
    local targetDefenseSkill = targetLevel * 5
    local targetWeaponSkill = targetLevel * 5
    return targetLevel, targetDefenseSkill, targetWeaponSkill
end

-- Weapon Subclass to Skill ID mapping (from Camelot SkillsFrame.lua)
local WEAPON_SUBCLASS_TO_SKILL_ID = {
    [Enum.ItemWeaponSubclass.Sword1H]  = 43,  -- Swords
    [Enum.ItemWeaponSubclass.Axe1H]    = 44,  -- Axes
    [Enum.ItemWeaponSubclass.Bows]     = 45,  -- Bows
    [Enum.ItemWeaponSubclass.Guns]     = 46,  -- Guns
    [Enum.ItemWeaponSubclass.Mace1H]   = 54,  -- Maces
    [Enum.ItemWeaponSubclass.Sword2H]  = 55,  -- Two-Handed Swords
    [Enum.ItemWeaponSubclass.Staff]    = 136, -- Staves
    [Enum.ItemWeaponSubclass.Mace2H]   = 160, -- Two-Handed Maces
    [Enum.ItemWeaponSubclass.Axe2H]    = 172, -- Two-Handed Axes
    [Enum.ItemWeaponSubclass.Dagger]   = 173, -- Daggers
    [Enum.ItemWeaponSubclass.Thrown]   = 176, -- Thrown
    [Enum.ItemWeaponSubclass.Crossbow] = 226, -- Crossbows
    [Enum.ItemWeaponSubclass.Wand]     = 228, -- Wands
    [Enum.ItemWeaponSubclass.Polearm]  = 229, -- Polearms
    [Enum.ItemWeaponSubclass.Unarmed]  = 162, -- Fist Weapons / Unarmed
}

local panelFrame = nil
local toggleButton = nil
local allRows = {}
local activeRowCount = 0
local inCombat = false
local pendingUpdate = false
local updateTimer = nil
local cachedMhInfo = {}
local cachedOhInfo = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  Data Extraction & Combat Math
-- ─────────────────────────────────────────────────────────────────────────────

--- Find skill information by skillID safely without table allocations
--- @param targetSkillID number
--- @return number|nil rank, number|nil modifier, number|nil maxRank
local function GetSkillInfoByID(targetSkillID)
    if not targetSkillID then return nil, nil, nil end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local count = C_SkillInfo.GetNumSkillLines()
        for i = 1, count do
            local info = C_SkillInfo.GetSkillLineInfo(i)
            if info and info.skillID == targetSkillID then
                return info.rank or 0, info.modifier or 0, info.maxRank or 0
            end
        end
    end
    return nil, nil, nil
end

--- Get equipped weapon details and effective skill without dynamic table churn
--- @param slotID number 16: main hand, 17: off hand, 18: ranged
--- @return table|nil
local function GetEquippedWeaponInfo(slotID)
    local pLevel = UnitLevel("player") or 60
    local baseSkill = pLevel * 5
    local targetTable = (slotID == 16) and cachedMhInfo or cachedOhInfo

    local itemID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", slotID)
    if not itemID then
        if slotID == 16 then
            local rank, modifier, maxRank = GetSkillInfoByID(162)
            local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill
            targetTable.name = "unarmed"
            targetTable.skill = totalSkill
            targetTable.maxSkill = maxRank or baseSkill
            targetTable.skillID = 162
            targetTable.isRanged = false
            targetTable.isDualWield = false
            return targetTable
        end
        return nil
    end

    local itemName = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
    local _, _, _, _, _, itemSubClassID, itemClassID = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemID)

    if slotID == 17 and itemClassID ~= Enum.ItemClass.Weapon then
        return nil -- Shield or off-hand frill item
    end

    local skillID = WEAPON_SUBCLASS_TO_SKILL_ID[itemSubClassID] or 162
    local rank, modifier, maxRank = GetSkillInfoByID(skillID)
    local totalSkill = (rank and (rank + (modifier or 0))) or baseSkill

    targetTable.name = itemName and itemName:lower() or "weapon"
    targetTable.skill = totalSkill
    targetTable.maxSkill = maxRank or baseSkill
    targetTable.skillID = skillID
    targetTable.isRanged = (slotID == 18)
    targetTable.isDualWield = (slotID == 17)
    return targetTable
end

--- Compute glancing blow chance and damage penalty against boss
--- @param weaponSkill number|nil
--- @param targetDefenseSkill number|nil
--- @return number chancePercent, number penaltyPercent
local function ComputeGlancingBlowData(weaponSkill, targetDefenseSkill)
    targetDefenseSkill = targetDefenseSkill or (((UnitLevel("player") or 60) + TARGET_LEVEL_OFFSET) * 5)
    local chance = 40.0
    local penalty = 35.0

    if GetGlancingBlowChance then
        local rawChance = GetGlancingBlowChance(weaponSkill, targetDefenseSkill)
        if rawChance and rawChance >= 0 then
            chance = rawChance * 100
        end
    end

    if GetGlancingBlowPenalty then
        local rawPenalty = GetGlancingBlowPenalty(weaponSkill, targetDefenseSkill)
        if rawPenalty and rawPenalty >= 0 then
            penalty = rawPenalty * 100
        end
    else
        local pLevel = UnitLevel("player") or 60
        local skill = weaponSkill or (pLevel * 5)
        local skillDiff = targetDefenseSkill - skill
        local low = math_max(0.01, math_min(1.2, 1.30 - (skillDiff * 0.05)))
        local high = math_max(0.01, math_min(0.99, 1.20 - (skillDiff * 0.03)))
        local avgDmg = (low + high) / 2
        penalty = math_max(0, (1 - avgDmg) * 100)
    end

    return chance, penalty
end

-- ─────────────────────────────────────────────────────────────────────────────
--  UI Creation & Layout
-- ─────────────────────────────────────────────────────────────────────────────

local function GetRow(parent)
    activeRowCount = activeRowCount + 1
    local row = allRows[activeRowCount]
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetHeight(18)
        row:EnableMouse(true)
        row:ClearAllPoints()

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 6, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.72, 0.72, 0.72, 1.0)
        row.label = label

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1.0, 1.0, 1.0, 1.0)
        row.value = value

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(1, 1, 1, 0.05)
        highlight:Hide()
        row.highlight = highlight

        row:SetScript("OnEnter", function(self)
            self.highlight:Show()
            if self.tooltipTitle then
                local tip = sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()
                if tip then
                    tip:SetOwner(self, "ANCHOR_RIGHT")
                    tip:ClearLines()
                    tip:AddLine(self.tooltipTitle, 1, 1, 1)
                    if self.tooltipText then
                        tip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true)
                    end
                    tip:Show()
                end
            end
        end)

        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
            if sfui.common and sfui.common.hide_tooltip then
                sfui.common.hide_tooltip()
            end
        end)

        allRows[activeRowCount] = row
    end

    if row:GetParent() ~= parent then
        row:SetParent(parent)
        row.currentY = nil
    end

    return row
end

local function AddHeaderRow(parent, yOffset, titleText)
    if not parent then return yOffset end
    local header = GetRow(parent)
    if not header then return yOffset end

    if header.currentY ~= yOffset or not header.isHeader then
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
        header:SetHeight(22)
        header.currentY = yOffset
        header.isHeader = true
    end

    header.label:SetText(titleText)

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local accent = pal.accentColor or (sfui.config and sfui.config.spec_color) or COLOR_ACCENT_FALLBACK
    header.label:SetTextColor(accent[1] or 0.4, accent[2] or 0.8, accent[3] or 1.0, 1.0)
    header.value:SetText("")
    header:EnableMouse(false)
    header.tooltipTitle = nil
    header.tooltipText = nil

    if not header.sep then
        header.sep = header:CreateTexture(nil, "ARTWORK")
        header.sep:SetHeight(1)
        header.sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 4, 1)
        header.sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -4, 1)
    end
    header.sep:Show()

    local isCamelot = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    if isCamelot and pal.highlightColor then
        header.sep:SetColorTexture(pal.highlightColor[1], pal.highlightColor[2], pal.highlightColor[3], 0.35)
    else
        header.sep:SetColorTexture(0.25, 0.25, 0.25, 0.75)
    end

    header:Show()
    return yOffset - 24
end

local function AddDataRow(parent, yOffset, labelText, valueText, valColor, tipTitle, tipText)
    if not parent then return yOffset end
    local row = GetRow(parent)
    if not row then return yOffset end

    if row.currentY ~= yOffset or row.isHeader then
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
        row:SetHeight(18)
        row.currentY = yOffset
        row.isHeader = false
    end

    if row.sep then
        row.sep:Hide()
    end

    row.label:SetText(labelText)

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local dim = pal.dimTextColor or COLOR_DIM
    row.label:SetTextColor(dim[1], dim[2], dim[3], 1.0)

    row.value:SetText(valueText)
    if valColor then
        row.value:SetTextColor(valColor[1], valColor[2], valColor[3], 1.0)
    else
        local hdr = pal.headerColor or COLOR_WHITE
        row.value:SetTextColor(hdr[1], hdr[2], hdr[3], 1.0)
    end

    if pal.highlightColor then
        row.highlight:SetColorTexture(pal.highlightColor[1], pal.highlightColor[2], pal.highlightColor[3], 0.12)
    else
        row.highlight:SetColorTexture(1, 1, 1, 0.05)
    end

    row.tooltipTitle = tipTitle
    row.tooltipText = tipText
    row:EnableMouse(tipTitle ~= nil)
    row:Show()
    return yOffset - 18
end

--- Refresh all combat telemetry and calculations in the panel
function panelModule.UpdateValues()
    if inCombat or (InCombatLockdown and InCombatLockdown()) then
        pendingUpdate = true
        return
    end
    if not panelFrame or not panelFrame:IsShown() or not panelFrame.scrollChild then
        pendingUpdate = true
        return
    end
    if CharacterFrame and not CharacterFrame:IsShown() then
        pendingUpdate = true
        return
    end

    local scrollChild = panelFrame.scrollChild
    activeRowCount = 0
    local y = -4

    local pLevel = UnitLevel("player") or 60
    local targetLevel, targetDefenseSkill, targetWeaponSkill = GetTargetBossStats(pLevel)
    local baseSkill = pLevel * 5
    local softSkillCap = baseSkill + 5
    local defCritImmunity = targetWeaponSkill + 125

    if panelFrame and panelFrame.subTitle then
        panelFrame.subTitle:SetText(string_format("vs lv %d boss (+3 lvl, %d def)", targetLevel, targetDefenseSkill))
    end

    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or _G.UnitClassBase("player")

    -- 1. Weapons & Boss Glancing Math
    y = AddHeaderRow(scrollChild, y, "weapon skills & boss glancing")

    local mhInfo = GetEquippedWeaponInfo(16)
    local mhSkill = mhInfo and mhInfo.skill or baseSkill
    local mhGlanceChance, mhGlancePenalty = ComputeGlancingBlowData(mhSkill, targetDefenseSkill)

    local mhHitMod = (GetHitModifier and GetHitModifier()) or 0
    local crMeleeHit = (GetCombatRatingBonus and _G.CR_HIT_MELEE and GetCombatRatingBonus(_G.CR_HIT_MELEE)) or 0
    local totalMeleeHit = mhHitMod + crMeleeHit

    local skillDiff = targetDefenseSkill - mhSkill
    local yellowHitCap = 6.0
    if skillDiff > 10 then
        yellowHitCap = 7.0 + ((skillDiff - 10) * 0.4)
    else
        yellowHitCap = math_max(5.0, 5.0 + (skillDiff * 0.1))
    end

    y = AddDataRow(scrollChild, y, "main-hand skill:", string_format("%d / %d", mhSkill, mhInfo and mhInfo.maxSkill or baseSkill),
        (mhSkill >= softSkillCap) and COLOR_GREEN or COLOR_WHITE,
        "main-hand weapon skill", string_format("effective weapon skill including racials and gear bonuses. %d+ weapon skill reduces glancing blow penalty and drops boss yellow hit cap from 9%% to 6%%.", softSkillCap))

    y = AddDataRow(scrollChild, y, "glancing blow chance:", string_format("%.1f%%", mhGlanceChance),
        COLOR_YELLOW,
        "boss glancing blow chance", string_format("all white melee attacks against higher-level targets suffer a flat 40%% glancing blow chance against level %d boss. glancing blows cannot crit.", targetLevel))

    y = AddDataRow(scrollChild, y, "glancing blow penalty:", string_format("-%.1f%% dmg", mhGlancePenalty),
        (mhSkill >= softSkillCap) and COLOR_GREEN or COLOR_RED,
        "glancing blow damage penalty", string_format("damage penalty suffered on glancing hits. baseline at %d skill is ~35%% penalty. with %d weapon skill, damage penalty drops to ~15%%.", baseSkill, softSkillCap))

    y = AddDataRow(scrollChild, y, "special / yellow hit cap:", string_format("%.1f%% (have %.1f%%)", yellowHitCap, totalMeleeHit),
        (totalMeleeHit >= yellowHitCap) and COLOR_GREEN or COLOR_YELLOW,
        "boss special / yellow hit cap", string_format("required hit chance to guarantee special abilities (sinister strike, mortal strike, bloodthirst) never miss against a level %d boss.", targetLevel))

    local ohInfo = GetEquippedWeaponInfo(17)
    if ohInfo then
        y = AddDataRow(scrollChild, y, "off-hand skill:", string_format("%d / %d", ohInfo.skill, ohInfo.maxSkill),
            (ohInfo.skill >= softSkillCap) and COLOR_GREEN or COLOR_WHITE,
            "off-hand weapon skill", "weapon skill for your equipped off-hand weapon.")

        local ohHitMod = (GetOffhandHitModifier and GetOffhandHitModifier()) or 0
        local totalOhHit = ohHitMod + crMeleeHit
        y = AddDataRow(scrollChild, y, "off-hand hit modifier:", string_format("+%.1f%%", totalOhHit),
            COLOR_LIGHT_BLUE,
            "off-hand hit modifier", "current hit bonus applied to off-hand attacks.")

        local _, ohPenalty = ComputeGlancingBlowData(ohInfo.skill, targetDefenseSkill)
        y = AddDataRow(scrollChild, y, "off-hand glancing penalty:", string_format("-%.1f%% dmg", ohPenalty),
            (ohInfo.skill >= softSkillCap) and COLOR_GREEN or COLOR_RED,
            "off-hand glancing penalty", "damage penalty on glancing blows with your off-hand weapon.")

        y = AddDataRow(scrollChild, y, "dual wield miss penalty:", "+19.0% miss",
            COLOR_DIM,
            "dual wield penalty", "dual wielding adds a 19% miss penalty to all white auto-attacks. special abilities are not affected.")
    end

    -- 2. Defense & Avoidance vs Boss
    y = y - 4
    y = AddHeaderRow(scrollChild, y, string_format("defense & avoidance (vs lv %d)", targetLevel))

    local effDef, baseDef, modDef, maxDef = baseSkill, baseSkill, 0, baseSkill
    if UnitDefenseSkill then
        baseDef, modDef = UnitDefenseSkill("player")
        baseDef = baseDef or baseSkill
        modDef = modDef or 0
        effDef = math_max(0, baseDef + modDef)
        maxDef = baseSkill
    end

    y = AddDataRow(scrollChild, y, "defense skill:", string_format("%d / %d", effDef, maxDef),
        (effDef >= defCritImmunity) and COLOR_GREEN or COLOR_WHITE,
        "defense skill", string_format("your defense skill. %d defense (%d above base %d) achieves crit immunity against level %d boss attacks.", defCritImmunity, defCritImmunity - baseSkill, baseSkill, targetLevel))

    local bossSkillDiff = targetWeaponSkill - effDef
    local bossCritAgainstPlayer = math_max(0.0, math_min(100.0, 5.0 + (bossSkillDiff * 0.04)))
    y = AddDataRow(scrollChild, y, "boss crit against you:", (effDef >= defCritImmunity) and "0.0% (immune)" or string_format("%.2f%%", bossCritAgainstPlayer),
        (effDef >= defCritImmunity) and COLOR_GREEN or COLOR_RED,
        "boss crit chance", string_format("chance for a level %d boss to critically hit you. reaches 0.0%% (crit immunity) at %d defense.", targetLevel, defCritImmunity))

    local crushingDiff = targetWeaponSkill - math_min(effDef, maxDef)
    local crushingChance = (crushingDiff >= 15) and math_max(0.0, math_min(100.0, (crushingDiff * 2.0) - 15.0)) or 0.0
    y = AddDataRow(scrollChild, y, "boss crushing blow:", string_format("%.1f%%", crushingChance),
        COLOR_ORANGE,
        "boss crushing blow chance", "mobs 3+ levels higher have a 15% chance to land a crushing blow for 150% damage unless pushed off the table via 102.4% total avoidance.")

    local dodge = (GetDodgeChance and GetDodgeChance()) or 0
    local parry = (GetParryChance and GetParryChance()) or 0
    local block = (GetBlockChance and GetBlockChance()) or 0
    local blockVal = (GetShieldBlock and GetShieldBlock()) or 0
    local missChance = math_max(0.0, math_min(100.0, 5.0 - (bossSkillDiff * 0.04)))
    local totalAvoidance = missChance + dodge + parry + block

    y = AddDataRow(scrollChild, y, "dodge / parry / block:", string_format("%.1f / %.1f / %.1f%%", dodge, parry, block),
        COLOR_LIGHT_GRAY,
        "avoidance chances", string_format("dodge: %.1f%%  |  parry: %.1f%%  |  block: %.1f%% (absorbs %d dmg)", dodge, parry, block, blockVal))

    y = AddDataRow(scrollChild, y, "total avoidance (vs 102.4%):", string_format("%.1f%%", totalAvoidance),
        (totalAvoidance >= 102.4) and COLOR_GREEN or COLOR_LIGHT_GRAY_2,
        "total avoidance", "sum of miss, dodge, parry, and block. when active avoidance reaches 102.4% (e.g. through shield block), crushing blows are pushed off the combat table.")

    local armor = _G.UnitArmor and _G.UnitArmor("player") or 0
    local armorDR = (armor > 0) and (armor / (armor + 400 + 85 * targetLevel) * 100) or 0
    armorDR = math_min(75.0, armorDR)
    y = AddDataRow(scrollChild, y, "armor dr vs boss:", string_format("%.1f%% (cap: 75%%)", armorDR),
        COLOR_MID_GRAY,
        "armor damage reduction", string_format("physical damage reduction against level %d boss attacks. current armor: %s.", targetLevel, BreakUpLargeNumbers(armor)))

    -- 3. Ranged & Ammo (Hunter or classes with ammo)
    local usesAmmo = (UnitUsesAmmo and UnitUsesAmmo("player")) or (pClass == "HUNTER")
    if usesAmmo then
        y = y - 4
        y = AddHeaderRow(scrollChild, y, "ranged & ammo")

        local ammoCount = _G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0
        local ammoID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 0)
        local ammoName = ammoID and C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(ammoID) or "no ammo equipped"

        y = AddDataRow(scrollChild, y, "ammo equipped:", tostring(ammoName):lower(),
            (ammoCount > 0) and COLOR_WHITE or COLOR_RED_ALERT,
            "equipped ammo", "current ammo equipped in your ammo slot (slot 0).")

        y = AddDataRow(scrollChild, y, "ammo count remaining:", BreakUpLargeNumbers(ammoCount),
            (ammoCount > 500) and COLOR_GREEN or (ammoCount > 100) and COLOR_YELLOW or COLOR_RED_ALERT,
            "ammo count", "remaining quantity of equipped ammunition.")

        local rangedHit = (GetRangedHitModifier and GetRangedHitModifier()) or 0
        local crRangedHit = (GetCombatRatingBonus and _G.CR_HIT_RANGED and GetCombatRatingBonus(_G.CR_HIT_RANGED)) or 0
        local totalRangedHit = rangedHit + crRangedHit
        local rangedCrit = (GetRangedCritChance and GetRangedCritChance()) or 0

        y = AddDataRow(scrollChild, y, "ranged hit / crit:", string_format("%.1f%% / %.1f%%", totalRangedHit, rangedCrit),
            COLOR_LIGHT_GRAY,
            "ranged hit and crit", "ranged physical hit bonus and critical strike chance.")
    end

    -- 4. Spell & Mana (Mana users)
    local powerType = UnitPowerType("player")
    local isCaster = (powerType == Enum.PowerType.Mana) or (pClass == "MAGE" or pClass == "WARLOCK" or pClass == "PRIEST" or pClass == "DRUID" or pClass == "SHAMAN" or pClass == "PALADIN")
    if isCaster then
        y = y - 4
        y = AddHeaderRow(scrollChild, y, "spellcasting & mana")

        local spellHit = (GetSpellHitModifier and GetSpellHitModifier()) or 0
        local crSpellHit = (GetCombatRatingBonus and _G.CR_HIT_SPELL and GetCombatRatingBonus(_G.CR_HIT_SPELL)) or 0
        local totalSpellHit = spellHit + crSpellHit
        y = AddDataRow(scrollChild, y, "spell hit (vs 16% cap):", string_format("%.1f%% / 16.0%%", totalSpellHit),
            (totalSpellHit >= 16.0) and COLOR_GREEN or COLOR_WHITE,
            "spell hit chance", string_format("against a level %d boss (+3 levels), base spell hit chance is 83%%. 16%% spell hit is required to reach the 99%% hit cap (1%% is always resisted).", targetLevel))

        local spellCrit = (GetSpellCritChance and GetSpellCritChance()) or 0
        y = AddDataRow(scrollChild, y, "spell crit chance:", string_format("%.2f%%", spellCrit),
            COLOR_PURPLE_BLUE,
            "spell crit chance", "base spell critical strike chance.")

        local spellPen = (GetSpellPenetration and GetSpellPenetration()) or 0
        y = AddDataRow(scrollChild, y, "spell penetration:", tostring(spellPen),
            COLOR_MID_GRAY,
            "spell penetration", "reduces the target's magic resistance against your spells.")

        if GetManaRegen then
            local baseRegen, castingRegen = GetManaRegen()
            baseRegen = (baseRegen or 0) * 5
            castingRegen = (castingRegen or 0) * 5
            y = AddDataRow(scrollChild, y, "mana regen (5s / cast):", string_format("%.0f / %.0f", baseRegen, castingRegen),
                COLOR_MANA_BLUE,
                "mana regeneration", "mana restored per 5 seconds. first value is outside 5-second rule (not casting). second value is while casting (meditation/talents).")
        end
    end

    for i = activeRowCount + 1, #allRows do
        allRows[i]:Hide()
    end

    local totalHeight = math_max(1, -y + 10)
    if scrollChild:GetHeight() ~= totalHeight then
        scrollChild:SetHeight(totalHeight)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Panel & Toggle Button Construction
-- ─────────────────────────────────────────────────────────────────────────────

local function RestorePosition(frame)
    if not frame then return end
    if inCombat or (InCombatLockdown and InCombatLockdown()) then return end
    frame:ClearAllPoints()
    local pos = SfuiDB and SfuiDB.characterInfoPanelPos
    if pos and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
    else
        if CharacterFrame then
            frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 2, -12)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
    end
end

local function SavePosition(frame)
    if not frame then return end
    if inCombat or (InCombatLockdown and InCombatLockdown()) then return end
    frame:StopMovingOrSizing()
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if left and top then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        SfuiDB = SfuiDB or {}
        SfuiDB.characterInfoPanelPos = {
            point = "TOPLEFT",
            relPoint = "BOTTOMLEFT",
            x = math_floor(left + 0.5),
            y = math_floor(top + 0.5),
        }
    end
end

local function ApplyTheme(frame, pal)
    if not frame then return end
    pal = pal or (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}

    if frame.headerBar and sfui.theme and sfui.theme.ApplyHeaderStyle then
        sfui.theme.ApplyHeaderStyle(frame.headerBar, "combat telemetry")
    end

    if frame.subTitle then
        local dim = pal.dimTextColor or { 0.5, 0.5, 0.5 }
        frame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end

    if frame.closeBtn and sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(frame.closeBtn)
    end

    if frame.content and sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(frame.content)
    end

    if frame.scrollFrame and frame.scrollFrame.ScrollBar and sfui.common and sfui.common.style_scrollbar then
        sfui.common.style_scrollbar(frame.scrollFrame.ScrollBar)
    end

    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(frame)
    end

    if frame:IsShown() and frame.scrollChild then
        panelModule.UpdateValues()
    end
end

function panelModule.CreatePanel()
    if panelFrame then return panelFrame end

    panelFrame = CreateFrame("Frame", "SfuiCharacterInfoPanel", UIParent, "BackdropTemplate")
    panelFrame:Hide()
    panelFrame:SetFrameStrata("HIGH")
    panelFrame:SetFrameLevel((CharacterFrame and CharacterFrame:GetFrameLevel() or 10) + 5)
    panelFrame:SetSize(280, 420)
    panelFrame:SetClampedToScreen(true)
    panelFrame:SetMovable(true)
    panelFrame:EnableMouse(true)
    panelFrame:RegisterForDrag("LeftButton")

    panelFrame:SetScript("OnDragStart", function(self)
        if inCombat or (InCombatLockdown and InCombatLockdown()) then return end
        self:StartMoving()
    end)

    panelFrame:SetScript("OnDragStop", function(self)
        SavePosition(self)
    end)

    panelFrame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)

    -- Header Bar
    local headerBar = nil
    if sfui.theme and sfui.theme.CreateWindowHeader then
        headerBar = sfui.theme.CreateWindowHeader(panelFrame, "combat telemetry", 210)
    else
        headerBar = CreateFrame("Frame", nil, panelFrame)
        headerBar:SetSize(210, 24)
        headerBar:SetPoint("TOP", panelFrame, "TOP", 0, -8)
    end
    panelFrame.headerBar = headerBar

    headerBar:EnableMouse(true)
    headerBar:RegisterForDrag("LeftButton")
    headerBar:SetScript("OnDragStart", function()
        if inCombat or (InCombatLockdown and InCombatLockdown()) then return end
        panelFrame:StartMoving()
    end)
    headerBar:SetScript("OnDragStop", function()
        SavePosition(panelFrame)
    end)
    headerBar:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
            if inCombat or (InCombatLockdown and InCombatLockdown()) then return end
            if SfuiDB then SfuiDB.characterInfoPanelPos = nil end
            RestorePosition(panelFrame)
            if sfui.common and sfui.common.print then
                sfui.common.print("character telemetry panel position reset to default.")
            end
        end
    end)
    headerBar:SetScript("OnEnter", function(self)
        local tip = sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()
        if tip then
            tip:SetOwner(self, "ANCHOR_TOP")
            tip:ClearLines()
            tip:AddLine("combat telemetry", 1, 1, 1)
            tip:AddLine("drag to move | shift+right-click to reset position", 0.7, 0.7, 0.7)
            tip:Show()
        end
    end)
    headerBar:SetScript("OnLeave", function()
        if sfui.common and sfui.common.hide_tooltip then
            sfui.common.hide_tooltip()
        end
    end)

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, panelFrame, "UIPanelCloseButton")
    panelFrame.closeBtn = closeBtn
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -4, -4)
    closeBtn:SetFrameLevel((panelFrame:GetFrameLevel() or 10) + 20)
    closeBtn:SetScript("OnClick", function()
        panelFrame:Hide()
        if SfuiDB then SfuiDB.showCombatInfoPanel = false end
    end)
    if sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(closeBtn)
    end

    -- Subtitle
    local subTitle = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panelFrame.subTitle = subTitle
    subTitle:SetPoint("TOP", headerBar, "BOTTOM", 0, -2)
    local pLevelInit = UnitLevel("player") or 60
    local tLvlInit, tDefInit = GetTargetBossStats(pLevelInit)
    subTitle:SetText(string_format("vs lv %d boss (+3 lvl, %d def)", tLvlInit, tDefInit))
    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local dim = pal.dimTextColor or { 0.5, 0.5, 0.5 }
    subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)

    -- Inset Content Container
    local content = CreateFrame("Frame", nil, panelFrame, "BackdropTemplate")
    panelFrame.content = content
    content:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 8, -48)
    content:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -8, 8)
    content:SetFrameLevel((panelFrame:GetFrameLevel() or 10) + 5)
    if sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(content)
    end

    -- Scroll Frame
    local sf = CreateFrame("ScrollFrame", "SfuiCharacterInfoScroll", content, "UIPanelScrollFrameTemplate")
    panelFrame.scrollFrame = sf
    sf:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -18, 4)
    sf:SetFrameLevel((content:GetFrameLevel() or 15) + 2)
    sf:EnableMouseWheel(true)
    if sf.ScrollBar and sfui.common and sfui.common.style_scrollbar then
        sfui.common.style_scrollbar(sf.ScrollBar)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(238)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)
    panelFrame.scrollChild = sc

    -- Window Theming (registered after all sub-elements and scrollChild exist)
    if sfui.theme and sfui.theme.ApplyWindowStyle then
        sfui.theme.ApplyWindowStyle(panelFrame, { cornerBrackets = true })
    end
    if sfui.theme and sfui.theme.RegisterWindow then
        sfui.theme.RegisterWindow(panelFrame, ApplyTheme, { cornerBrackets = true })
    end

    panelFrame:SetScript("OnShow", function()
        if inCombat or (InCombatLockdown and InCombatLockdown()) then
            pendingUpdate = true
            return
        end
        RestorePosition(panelFrame)
        panelModule.UpdateValues()
        if sfui.theme and sfui.theme.ElevateWindowContents then
            sfui.theme.ElevateWindowContents(panelFrame)
        end
    end)

    RestorePosition(panelFrame)
    panelFrame:Hide()
    return panelFrame
end

function panelModule.CreateToggleButton()
    if toggleButton then return toggleButton end
    if not CharacterFrame then return nil end

    toggleButton = CreateFrame("Button", "SfuiCombatStatsToggleBtn", CharacterFrame, "BackdropTemplate")
    toggleButton:SetSize(16, 16)
    toggleButton:SetHitRectInsets(-2, -2, -2, -2)
    toggleButton:SetNormalTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
    toggleButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if toggleButton:GetNormalTexture() then
        toggleButton:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local mult = sfui.pixelScale or 1
    toggleButton:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = mult,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    toggleButton:SetBackdropBorderColor(0, 0, 0, 1)

    local closeBtn = _G.CharacterFrameCloseButton
    if closeBtn and closeBtn.GetFrameLevel then
        toggleButton:SetFrameLevel((closeBtn:GetFrameLevel() or 500) + 5)
    end

    toggleButton:SetScript("OnEnter", function(self)
        local tip = sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()
        if tip then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:ClearLines()
            tip:AddLine("combat telemetry", 1, 1, 1)
            tip:AddLine("click to toggle extended combat math & boss glancing blow panel.", 0.8, 0.8, 0.8, true)
            tip:AddLine("drag to move | shift+right-click header to reset position.", 0.65, 0.65, 0.65, true)
            tip:Show()
        end
    end)

    toggleButton:SetScript("OnLeave", function()
        if sfui.common and sfui.common.hide_tooltip then
            sfui.common.hide_tooltip()
        end
    end)

    toggleButton:SetScript("OnClick", function()
        if not panelFrame then panelModule.CreatePanel() end
        if panelFrame:IsShown() then
            panelFrame:Hide()
            if SfuiDB then SfuiDB.showCombatInfoPanel = false end
        else
            if inCombat or (InCombatLockdown and InCombatLockdown()) then
                pendingUpdate = true
                panelFrame:Show()
                if SfuiDB then SfuiDB.showCombatInfoPanel = true end
                return
            end
            RestorePosition(panelFrame)
            panelFrame:Show()
            if SfuiDB then SfuiDB.showCombatInfoPanel = true end
            panelModule.UpdateValues()
        end
    end)

    toggleButton:HookScript("OnShow", function()
        if sfui.character and sfui.character.AlignHeaderButtons then
            sfui.character.AlignHeaderButtons()
        end
    end)
    toggleButton:HookScript("OnHide", function()
        if sfui.character and sfui.character.AlignHeaderButtons then
            sfui.character.AlignHeaderButtons()
        end
    end)

    if sfui.character and sfui.character.AlignHeaderButtons then
        sfui.character.HookHeaderButtons()
        sfui.character.AlignHeaderButtons()
    end

    return toggleButton
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Lifecycle & Events
-- ─────────────────────────────────────────────────────────────────────────────

local function OnStateChanged()
    if inCombat or (InCombatLockdown and InCombatLockdown()) then
        pendingUpdate = true
        return
    end
    if not panelFrame or not panelFrame:IsShown() or (CharacterFrame and not CharacterFrame:IsShown()) then
        pendingUpdate = true
        return
    end
    if updateTimer then return end
    updateTimer = C_Timer.NewTimer(0.4, function()
        updateTimer = nil
        if inCombat or (InCombatLockdown and InCombatLockdown()) then
            pendingUpdate = true
            return
        end
        if panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
            pendingUpdate = false
            panelModule.UpdateValues()
        end
    end)
end

local function Initialize()
    panelModule.CreatePanel()
    panelModule.CreateToggleButton()

    if CharacterFrame then
        if CharacterFrame:IsShown() and SfuiDB and SfuiDB.showCombatInfoPanel then
            if inCombat or (InCombatLockdown and InCombatLockdown()) then
                pendingUpdate = true
            else
                if not panelFrame then panelModule.CreatePanel() end
                RestorePosition(panelFrame)
                panelFrame:Show()
                panelModule.UpdateValues()
            end
        else
            if panelFrame then panelFrame:Hide() end
        end

        CharacterFrame:HookScript("OnShow", function()
            if sfui.character and sfui.character.AlignHeaderButtons then
                sfui.character.AlignHeaderButtons()
            end
            if SfuiDB and SfuiDB.showCombatInfoPanel then
                if inCombat or (InCombatLockdown and InCombatLockdown()) then
                    pendingUpdate = true
                    if not panelFrame then panelModule.CreatePanel() end
                    panelFrame:Show()
                    return
                end
                if not panelFrame then panelModule.CreatePanel() end
                RestorePosition(panelFrame)
                panelFrame:Show()
                panelModule.UpdateValues()
            end
        end)

        CharacterFrame:HookScript("OnHide", function()
            if panelFrame and panelFrame:IsShown() then
                panelFrame:Hide()
            end
        end)
    else
        if panelFrame then panelFrame:Hide() end
    end

    local events = {
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
        "SKILL_LINES_CHANGED",
        "UNIT_STATS",
        "CHARACTER_POINTS_CHANGED",
        "PLAYER_LEVEL_UP",
    }

    local watcher = CreateFrame("Frame")
    for _, evt in ipairs(events) do
        watcher:RegisterEvent(evt)
    end
    watcher:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            if updateTimer then
                updateTimer:Cancel()
                updateTimer = nil
            end
            pendingUpdate = true
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            if pendingUpdate and panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
                pendingUpdate = false
                panelModule.UpdateValues()
            end
            return
        end

        if unit and unit ~= "player" then return end
        OnStateChanged()
    end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if CharacterFrame and not panelModule.initialized then
        panelModule.initialized = true
        Initialize()
    end
end)
