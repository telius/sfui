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

-- Target Constants (Level 63 Raid Boss)
local RAID_BOSS_LEVEL = 63
local BOSS_DEFENSE_SKILL = 315
local BOSS_WEAPON_SKILL = 315

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
local rowPool = {}
local activeRows = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  Data Extraction & Combat Math
-- ─────────────────────────────────────────────────────────────────────────────

--- Find skill information by skillID safely
--- @param targetSkillID number
--- @return table|nil
local function GetSkillInfoByID(targetSkillID)
    if not targetSkillID then return nil end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local count = C_SkillInfo.GetNumSkillLines()
        for i = 1, count do
            local info = C_SkillInfo.GetSkillLineInfo(i)
            if info and info.skillID == targetSkillID then
                return {
                    name = info.name,
                    rank = info.rank or 0,
                    modifier = info.modifier or 0,
                    maxRank = info.maxRank or 0,
                }
            end
        end
    elseif _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local count = _G.GetNumSkillLines()
        for i = 1, count do
            local skillName, isHeader, _, skillRank, _, skillModifier, skillMaxRank = _G.GetSkillLineInfo(i)
            if not isHeader and skillName then
                -- Fallback lookup
            end
        end
    end
    return nil
end

--- Get equipped weapon details and effective skill
--- @param slotID number 16: main hand, 17: off hand, 18: ranged
--- @return table|nil
local function GetEquippedWeaponInfo(slotID)
    local pLevel = UnitLevel("player") or 60
    local baseSkill = pLevel * 5
    local itemID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", slotID)

    if not itemID then
        if slotID == 16 then
            local skillData = GetSkillInfoByID(162)
            local rank = skillData and (skillData.rank + skillData.modifier) or baseSkill
            return {
                name = "unarmed",
                skill = rank,
                maxSkill = skillData and skillData.maxRank or baseSkill,
                isRanged = false,
                isDualWield = false,
            }
        end
        return nil
    end

    local itemName = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(itemID)
    local _, _, _, _, _, itemSubClassID, itemClassID = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemID)

    if slotID == 17 and itemClassID ~= Enum.ItemClass.Weapon then
        return nil -- Shield or off-hand frill item
    end

    local skillID = WEAPON_SUBCLASS_TO_SKILL_ID[itemSubClassID] or 162
    local skillData = GetSkillInfoByID(skillID)
    local totalSkill = skillData and (skillData.rank + skillData.modifier) or baseSkill

    return {
        name = itemName and itemName:lower() or "weapon",
        skill = totalSkill,
        maxSkill = skillData and skillData.maxRank or baseSkill,
        skillID = skillID,
        isRanged = (slotID == 18),
        isDualWield = (slotID == 17),
    }
end

--- Compute glancing blow chance and damage penalty against boss
--- @param weaponSkill number|nil
--- @return number chancePercent, number penaltyPercent
local function ComputeGlancingBlowData(weaponSkill)
    local chance = 40.0
    local penalty = 35.0

    if GetGlancingBlowChance then
        local rawChance = GetGlancingBlowChance(weaponSkill, BOSS_DEFENSE_SKILL)
        if rawChance and rawChance >= 0 then
            chance = rawChance * 100
        end
    end

    if GetGlancingBlowPenalty then
        local rawPenalty = GetGlancingBlowPenalty(weaponSkill, BOSS_DEFENSE_SKILL)
        if rawPenalty and rawPenalty >= 0 then
            penalty = rawPenalty * 100
        end
    else
        local pLevel = UnitLevel("player") or 60
        local skill = weaponSkill or (pLevel * 5)
        local skillDiff = BOSS_DEFENSE_SKILL - skill
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

local function AcquireRow(parent)
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row:SetHeight(18)
        row:EnableMouse(true)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 8, 0)
        label:SetJustifyH("LEFT")
        label:SetTextColor(0.72, 0.72, 0.72, 1.0)
        row.label = label

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
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
                local tip = sfui.common.get_tooltip()
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:ClearLines()
                tip:AddLine(self.tooltipTitle, 1, 1, 1)
                if self.tooltipText then
                    tip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true)
                end
                tip:Show()
            end
        end)

        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
            sfui.common.hide_tooltip()
        end)
    else
        row:SetParent(parent)
        row:Show()
    end
    activeRows[#activeRows + 1] = row
    return row
end

local function ClearRows()
    for i = #activeRows, 1, -1 do
        local row = table.remove(activeRows, i)
        row:Hide()
        row.tooltipTitle = nil
        row.tooltipText = nil
        rowPool[#rowPool + 1] = row
    end
end

local function AddHeaderRow(parent, yOffset, titleText)
    local header = AcquireRow(parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    header:SetHeight(22)
    header.label:SetText(titleText)
    local specColor = (sfui.config and sfui.config.spec_color) or { 0.4, 0.8, 1.0 }
    header.label:SetTextColor(specColor[1] or 0.4, specColor[2] or 0.8, specColor[3] or 1.0, 1.0)
    header.value:SetText("")
    header:EnableMouse(false)

    local sep = header:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 6, 2)
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -6, 2)
    sep:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    return yOffset - 24
end

local function AddDataRow(parent, yOffset, labelText, valueText, valColor, tipTitle, tipText)
    local row = AcquireRow(parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    row:SetHeight(18)
    row.label:SetText(labelText)
    row.label:SetTextColor(0.72, 0.72, 0.72, 1.0)
    row.value:SetText(valueText)
    if valColor then
        row.value:SetTextColor(valColor[1], valColor[2], valColor[3], 1.0)
    else
        row.value:SetTextColor(1.0, 1.0, 1.0, 1.0)
    end
    row.tooltipTitle = tipTitle
    row.tooltipText = tipText
    row:EnableMouse(tipTitle ~= nil)
    return yOffset - 18
end

--- Refresh all combat telemetry and calculations in the panel
function panelModule.UpdateValues()
    if not panelFrame or not panelFrame:IsShown() then return end

    ClearRows()
    local scrollChild = panelFrame.scrollChild
    local y = -4

    local pLevel = UnitLevel("player") or 60
    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or _G.UnitClassBase("player")

    -- 1. Weapons & Boss Glancing Math
    y = AddHeaderRow(scrollChild, y, "weapon skills & boss glancing")

    local mhInfo = GetEquippedWeaponInfo(16)
    local mhSkill = mhInfo and mhInfo.skill or (pLevel * 5)
    local mhGlanceChance, mhGlancePenalty = ComputeGlancingBlowData(mhSkill)

    local mhHitMod = (GetHitModifier and GetHitModifier()) or 0
    local crMeleeHit = (GetCombatRatingBonus and _G.CR_HIT_MELEE and GetCombatRatingBonus(_G.CR_HIT_MELEE)) or 0
    local totalMeleeHit = mhHitMod + crMeleeHit

    local yellowHitCap = (mhSkill >= 305) and 6.0 or 9.0

    y = AddDataRow(scrollChild, y, "main-hand skill:", string_format("%d / %d", mhSkill, mhInfo and mhInfo.maxSkill or (pLevel * 5)),
        (mhSkill >= 305) and { 0.3, 1.0, 0.3 } or { 1.0, 1.0, 1.0 },
        "main-hand weapon skill", "effective weapon skill including racials and gear bonuses. 305+ weapon skill reduces glancing blow penalty and drops boss yellow hit cap from 9% to 6%.")

    y = AddDataRow(scrollChild, y, "glancing blow chance:", string_format("%.1f%%", mhGlanceChance),
        { 1.0, 0.82, 0.2 },
        "boss glancing blow chance", "all white melee attacks against higher-level targets suffer a flat 40% glancing blow chance. glancing blows cannot crit.")

    y = AddDataRow(scrollChild, y, "glancing blow penalty:", string_format("-%.1f%% dmg", mhGlancePenalty),
        (mhSkill >= 305) and { 0.3, 1.0, 0.3 } or { 1.0, 0.4, 0.4 },
        "glancing blow damage penalty", "damage penalty suffered on glancing hits. baseline at 300 skill is ~35% penalty. with 305 weapon skill, damage penalty drops to ~15%.")

    y = AddDataRow(scrollChild, y, "special / yellow hit cap:", string_format("%.1f%% (have %.1f%%)", yellowHitCap, totalMeleeHit),
        (totalMeleeHit >= yellowHitCap) and { 0.3, 1.0, 0.3 } or { 1.0, 0.8, 0.2 },
        "boss special / yellow hit cap", "required hit chance to guarantee special abilities (sinister strike, mortal strike, bloodthirst) never miss against a level 63 raid boss.")

    local ohInfo = GetEquippedWeaponInfo(17)
    if ohInfo then
        y = AddDataRow(scrollChild, y, "off-hand skill:", string_format("%d / %d", ohInfo.skill, ohInfo.maxSkill),
            (ohInfo.skill >= 305) and { 0.3, 1.0, 0.3 } or { 1.0, 1.0, 1.0 },
            "off-hand weapon skill", "weapon skill for your equipped off-hand weapon.")

        local ohHitMod = (GetOffhandHitModifier and GetOffhandHitModifier()) or 0
        local totalOhHit = ohHitMod + crMeleeHit
        y = AddDataRow(scrollChild, y, "off-hand hit modifier:", string_format("+%.1f%%", totalOhHit),
            { 0.8, 0.8, 1.0 },
            "off-hand hit modifier", "current hit bonus applied to off-hand attacks.")

        local _, ohPenalty = ComputeGlancingBlowData(ohInfo.skill)
        y = AddDataRow(scrollChild, y, "off-hand glancing penalty:", string_format("-%.1f%% dmg", ohPenalty),
            (ohInfo.skill >= 305) and { 0.3, 1.0, 0.3 } or { 1.0, 0.4, 0.4 },
            "off-hand glancing penalty", "damage penalty on glancing blows with your off-hand weapon.")

        y = AddDataRow(scrollChild, y, "dual wield miss penalty:", "+19.0% miss",
            { 0.7, 0.7, 0.7 },
            "dual wield penalty", "dual wielding adds a 19% miss penalty to all white auto-attacks. special abilities are not affected.")
    end

    -- 2. Defense & Avoidance vs Boss
    y = y - 4
    y = AddHeaderRow(scrollChild, y, "defense & avoidance (vs lv 63)")

    local effDef, baseDef, modDef, maxDef = 300, 300, 0, 300
    if UnitDefenseSkill then
        baseDef, modDef = UnitDefenseSkill("player")
        baseDef = baseDef or 300
        modDef = modDef or 0
        effDef = math_max(0, baseDef + modDef)
        maxDef = pLevel * 5
    end

    y = AddDataRow(scrollChild, y, "defense skill:", string_format("%d / %d", effDef, maxDef),
        (effDef >= 440) and { 0.3, 1.0, 0.3 } or { 1.0, 1.0, 1.0 },
        "defense skill", "your defense skill. 440 defense (140 defense rating above 300) achieves crit immunity against level 63 raid bosses.")

    local skillDiff = BOSS_WEAPON_SKILL - effDef
    local bossCritAgainstPlayer = math_max(0.0, math_min(100.0, 5.0 + (skillDiff * 0.04)))
    y = AddDataRow(scrollChild, y, "boss crit against you:", (effDef >= 440) and "0.0% (immune)" or string_format("%.2f%%", bossCritAgainstPlayer),
        (effDef >= 440) and { 0.3, 1.0, 0.3 } or { 1.0, 0.4, 0.4 },
        "boss crit chance", "chance for a level 63 boss to critically hit you. reaches 0.0% (crit immunity) at 440 defense.")

    local crushingDiff = BOSS_WEAPON_SKILL - math_min(effDef, maxDef)
    local crushingChance = (crushingDiff >= 15) and math_max(0.0, math_min(100.0, (crushingDiff * 2.0) - 15.0)) or 0.0
    y = AddDataRow(scrollChild, y, "boss crushing blow:", string_format("%.1f%%", crushingChance),
        { 1.0, 0.6, 0.2 },
        "boss crushing blow chance", "mobs 3+ levels higher have a 15% chance to land a crushing blow for 150% damage unless pushed off the table via 102.4% total avoidance.")

    local dodge = (GetDodgeChance and GetDodgeChance()) or 0
    local parry = (GetParryChance and GetParryChance()) or 0
    local block = (GetBlockChance and GetBlockChance()) or 0
    local blockVal = (GetShieldBlock and GetShieldBlock()) or 0
    local missChance = math_max(0.0, math_min(100.0, 5.0 - (skillDiff * 0.04)))
    local totalAvoidance = missChance + dodge + parry + block

    y = AddDataRow(scrollChild, y, "dodge / parry / block:", string_format("%.1f / %.1f / %.1f%%", dodge, parry, block),
        { 0.85, 0.85, 0.85 },
        "avoidance chances", string_format("dodge: %.1f%%  |  parry: %.1f%%  |  block: %.1f%% (absorbs %d dmg)", dodge, parry, block, blockVal))

    y = AddDataRow(scrollChild, y, "total avoidance (vs 102.4%):", string_format("%.1f%%", totalAvoidance),
        (totalAvoidance >= 102.4) and { 0.3, 1.0, 0.3 } or { 0.9, 0.9, 0.9 },
        "total avoidance", "sum of miss, dodge, parry, and block. when active avoidance reaches 102.4% (e.g. through shield block), crushing blows are pushed off the combat table.")

    local armor = _G.UnitArmor and _G.UnitArmor("player") or 0
    local armorDR = (armor > 0) and (armor / (armor + 400 + 85 * RAID_BOSS_LEVEL) * 100) or 0
    armorDR = math_min(75.0, armorDR)
    y = AddDataRow(scrollChild, y, "armor dr vs boss:", string_format("%.1f%% (cap: 75%%)", armorDR),
        { 0.8, 0.8, 0.8 },
        "armor damage reduction", string_format("physical damage reduction against a level 63 boss attacks. current armor: %s.", BreakUpLargeNumbers(armor)))

    -- 3. Ranged & Ammo (Hunter or classes with ammo)
    local usesAmmo = (UnitUsesAmmo and UnitUsesAmmo("player")) or (pClass == "HUNTER")
    if usesAmmo then
        y = y - 4
        y = AddHeaderRow(scrollChild, y, "ranged & ammo")

        local ammoCount = _G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0
        local ammoID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 0)
        local ammoName = ammoID and C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(ammoID) or "no ammo equipped"

        y = AddDataRow(scrollChild, y, "ammo equipped:", tostring(ammoName):lower(),
            (ammoCount > 0) and { 1.0, 1.0, 1.0 } or { 1.0, 0.3, 0.3 },
            "equipped ammo", "current ammo equipped in your ammo slot (slot 0).")

        y = AddDataRow(scrollChild, y, "ammo count remaining:", BreakUpLargeNumbers(ammoCount),
            (ammoCount > 500) and { 0.3, 1.0, 0.3 } or (ammoCount > 100) and { 1.0, 0.8, 0.2 } or { 1.0, 0.3, 0.3 },
            "ammo count", "remaining quantity of equipped ammunition.")

        local rangedHit = (GetRangedHitModifier and GetRangedHitModifier()) or 0
        local crRangedHit = (GetCombatRatingBonus and _G.CR_HIT_RANGED and GetCombatRatingBonus(_G.CR_HIT_RANGED)) or 0
        local totalRangedHit = rangedHit + crRangedHit
        local rangedCrit = (GetRangedCritChance and GetRangedCritChance()) or 0

        y = AddDataRow(scrollChild, y, "ranged hit / crit:", string_format("%.1f%% / %.1f%%", totalRangedHit, rangedCrit),
            { 0.85, 0.85, 0.85 },
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
            (totalSpellHit >= 16.0) and { 0.3, 1.0, 0.3 } or { 1.0, 1.0, 1.0 },
            "spell hit chance", "against a level 63 raid boss, base spell hit chance is 83%. 16% spell hit is required to reach the 99% hit cap (1% is always resisted).")

        local spellCrit = (GetSpellCritChance and GetSpellCritChance()) or 0
        y = AddDataRow(scrollChild, y, "spell crit chance:", string_format("%.2f%%", spellCrit),
            { 0.85, 0.85, 1.0 },
            "spell crit chance", "base spell critical strike chance.")

        local spellPen = (GetSpellPenetration and GetSpellPenetration()) or 0
        y = AddDataRow(scrollChild, y, "spell penetration:", tostring(spellPen),
            { 0.8, 0.8, 0.8 },
            "spell penetration", "reduces the target's magic resistance against your spells.")

        if GetManaRegen then
            local baseRegen, castingRegen = GetManaRegen()
            baseRegen = (baseRegen or 0) * 5
            castingRegen = (castingRegen or 0) * 5
            y = AddDataRow(scrollChild, y, "mana regen (5s / cast):", string_format("%.0f / %.0f", baseRegen, castingRegen),
                { 0.4, 0.8, 1.0 },
                "mana regeneration", "mana restored per 5 seconds. first value is outside 5-second rule (not casting). second value is while casting (meditation/talents).")
        end
    end

    local totalHeight = math_max(1, -y + 10)
    scrollChild:SetHeight(totalHeight)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Panel & Toggle Button Construction
-- ─────────────────────────────────────────────────────────────────────────────

function panelModule.CreatePanel()
    if panelFrame then return panelFrame end

    local parent = CharacterFrame or UIParent

    panelFrame = CreateFrame("Frame", "SfuiCharacterInfoPanel", parent, "BackdropTemplate")
    panelFrame:SetFrameStrata("MEDIUM")
    panelFrame:SetFrameLevel((CharacterFrame and CharacterFrame:GetFrameLevel() or 10) + 5)
    panelFrame:SetWidth(270)
    panelFrame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -12)
    panelFrame:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 38)
    panelFrame:EnableMouse(true)
    panelFrame:SetClampedToScreen(true)

    local mult = sfui.pixelScale or 1
    panelFrame:SetBackdrop({
        bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        tile = false,
        tileSize = 0,
        edgeSize = mult,
        insets = { left = mult, right = mult, top = mult, bottom = mult },
    })
    panelFrame:SetBackdropColor(0.04, 0.04, 0.04, 0.94)
    panelFrame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title Bar
    local title = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 10, -8)
    title:SetText("combat telemetry")
    local specColor = (sfui.config and sfui.config.spec_color) or { 0.4, 0.8, 1.0 }
    title:SetTextColor(specColor[1] or 0.4, specColor[2] or 0.8, specColor[3] or 1.0, 1.0)

    local subTitle = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subTitle:SetText("vs lv 63 raid boss (315 def)")
    subTitle:SetTextColor(0.5, 0.5, 0.5, 1.0)

    -- Close Button ('x')
    local closeBtn = CreateFrame("Button", nil, panelFrame)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -6, -6)
    closeBtn:SetNormalFontObject("GameFontHighlightSmall")
    closeBtn:SetText("x")
    closeBtn:GetFontString():SetTextColor(0.6, 0.6, 0.6, 1.0)
    closeBtn:SetScript("OnEnter", function(self)
        self:GetFontString():SetTextColor(1.0, 0.3, 0.3, 1.0)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:GetFontString():SetTextColor(0.6, 0.6, 0.6, 1.0)
    end)
    closeBtn:SetScript("OnClick", function()
        panelFrame:Hide()
        if SfuiDB then SfuiDB.showCombatInfoPanel = false end
    end)

    -- Separator Line
    local topSep = panelFrame:CreateTexture(nil, "ARTWORK")
    topSep:SetHeight(1)
    topSep:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 6, -34)
    topSep:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -6, -34)
    topSep:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Scroll Frame
    local sf = CreateFrame("ScrollFrame", "SfuiCharacterInfoScroll", panelFrame, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 2, -38)
    sf:SetPoint("BOTTOMRIGHT", panelFrame, "BOTTOMRIGHT", -22, 6)
    sf:EnableMouseWheel(true)
    if sf.ScrollBar and sfui.common.style_scrollbar then
        sfui.common.style_scrollbar(sf.ScrollBar)
    end

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(240)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    panelFrame.scrollFrame = sf
    panelFrame.scrollChild = sc

    panelFrame:SetScript("OnShow", function()
        panelModule.UpdateValues()
    end)

    return panelFrame
end

function panelModule.CreateToggleButton()
    if toggleButton then return toggleButton end
    if not CharacterFrame then return nil end

    local anchorTarget = _G.SfuiGearToggleBtn or CharacterFrameCloseButton
    if not anchorTarget then return nil end

    toggleButton = CreateFrame("Button", "SfuiCombatStatsToggleBtn", CharacterFrame)
    toggleButton:SetSize(22, 22)
    toggleButton:SetPoint("RIGHT", anchorTarget, "LEFT", -4, 0)
    toggleButton:SetNormalTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
    toggleButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if toggleButton:GetNormalTexture() then
        toggleButton:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    toggleButton:SetScript("OnEnter", function(self)
        local tip = sfui.common.get_tooltip()
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        tip:AddLine("combat telemetry", 1, 1, 1)
        tip:AddLine("click to toggle extended combat math & boss glancing blow panel.", 0.8, 0.8, 0.8, true)
        tip:Show()
    end)

    toggleButton:SetScript("OnLeave", function()
        sfui.common.hide_tooltip()
    end)

    toggleButton:SetScript("OnClick", function()
        if not panelFrame then panelModule.CreatePanel() end
        if panelFrame:IsShown() then
            panelFrame:Hide()
            if SfuiDB then SfuiDB.showCombatInfoPanel = false end
        else
            panelFrame:Show()
            if SfuiDB then SfuiDB.showCombatInfoPanel = true end
            panelModule.UpdateValues()
        end
    end)

    return toggleButton
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Lifecycle & Events
-- ─────────────────────────────────────────────────────────────────────────────

local function OnStateChanged()
    if panelFrame and panelFrame:IsShown() then
        panelModule.UpdateValues()
    end
end

local function Initialize()
    panelModule.CreatePanel()
    panelModule.CreateToggleButton()

    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function()
            if SfuiDB and SfuiDB.showCombatInfoPanel then
                if not panelFrame then panelModule.CreatePanel() end
                panelFrame:Show()
                panelModule.UpdateValues()
            end
        end)

        CharacterFrame:HookScript("OnHide", function()
            if panelFrame and panelFrame:IsShown() then
                panelFrame:Hide()
            end
        end)
    end

    local events = {
        "UNIT_INVENTORY_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED",
        "SKILL_LINES_CHANGED",
        "UNIT_STATS",
        "UNIT_DAMAGE",
        "UNIT_ATTACK_POWER",
        "UNIT_RANGED_ATTACK_POWER",
        "CHARACTER_POINTS_CHANGED",
    }

    local watcher = CreateFrame("Frame")
    for _, evt in ipairs(events) do
        watcher:RegisterEvent(evt)
    end
    watcher:SetScript("OnEvent", function(self, event, unit)
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
