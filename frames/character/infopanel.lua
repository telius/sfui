local addonName, addon = ...
sfui = sfui or {}
sfui.character = sfui.character or {}
sfui.character.infopanel = {}

local panelModule = sfui.character.infopanel

-- Guard: Camelot only
if not sfui.isCamelot then
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
local InCombatLockdown = _G.InCombatLockdown
local C_Timer = _G.C_Timer
local math_max = math.max
local math_min = math.min
local math_floor = math.floor
local string_format = string.format
local tostring = _G.tostring
local ipairs = _G.ipairs
local UnitLevel = _G.UnitLevel
local UnitDefenseSkill = _G.UnitDefenseSkill
local UnitPowerType = _G.UnitPowerType
local UnitUsesAmmo = _G.UnitUsesAmmo
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitCanAttack = _G.UnitCanAttack
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsPlayer = _G.UnitIsPlayer
local UnitClassification = _G.UnitClassification
local GetCreatureDifficultyColor = _G.GetCreatureDifficultyColor
local GetGlancingBlowChance = _G.GetGlancingBlowChance
local GetGlancingBlowPenalty = _G.GetGlancingBlowPenalty
local GetOffhandHitModifier = _G.GetOffhandHitModifier
local GetHitModifier = _G.GetHitModifier
local GetRangedHitModifier = _G.GetRangedHitModifier
local GetSpellHitModifier = _G.GetSpellHitModifier
local GetRangedCritChance = _G.GetRangedCritChance
local GetSpellCritChance = _G.GetSpellCritChance
local GetDodgeChance = _G.GetDodgeChance
local GetParryChance = _G.GetParryChance
local GetBlockChance = _G.GetBlockChance
local GetShieldBlock = _G.GetShieldBlock
local GetSpellPenetration = _G.GetSpellPenetration
local GetManaRegen = _G.GetManaRegen
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring
local C_Item = _G.C_Item
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

local issecretvalue = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

local function safe_num(val, default)
    if val == nil or issecretvalue(val) then
        return default or 0
    end
    local n = tonumber(val)
    return n or (default or 0)
end

-- Target Calculations (Dynamic: Character Level + 3, or Selected Target Out of Combat)
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

--- Get active telemetry target info (valid target if selected, or default boss)
--- @param pLevel number?
--- @return table
local function GetActiveTelemetryTarget(pLevel)
    pLevel = pLevel or UnitLevel("player") or 60

    if UnitExists and UnitExists("target") and (not UnitIsDeadOrGhost or not UnitIsDeadOrGhost("target")) then
        local targetName = (UnitName and UnitName("target")) or "target"
        local rawLevel = (UnitLevel and UnitLevel("target")) or -1
        local isPlayer = (UnitIsPlayer and UnitIsPlayer("target")) or false
        local classification = (UnitClassification and UnitClassification("target")) or "normal"
        local isSkull = (rawLevel <= 0) or (classification == "worldboss")

        local effectiveLevel = isSkull and (pLevel + TARGET_LEVEL_OFFSET) or rawLevel
        local defenseSkill = effectiveLevel * 5
        local weaponSkill = effectiveLevel * 5

        local r, g, b = 0.5, 0.5, 0.5
        if GetCreatureDifficultyColor then
            local diffColor = GetCreatureDifficultyColor(isSkull and (pLevel + TARGET_LEVEL_OFFSET) or effectiveLevel)
            if diffColor then
                r, g, b = diffColor.r, diffColor.g, diffColor.b
            end
        else
            local lvlDelta = effectiveLevel - pLevel
            if isSkull or lvlDelta >= 5 then
                r, g, b = 1.0, 0.2, 0.2
            elseif lvlDelta >= 3 then
                r, g, b = 1.0, 0.5, 0.2
            elseif lvlDelta >= -2 then
                r, g, b = 1.0, 1.0, 0.2
            elseif lvlDelta >= -6 then
                r, g, b = 0.2, 1.0, 0.2
            else
                r, g, b = 0.5, 0.5, 0.5
            end
        end

        return {
            isTarget = true,
            isPlayer = isPlayer,
            isSkull = isSkull,
            name = targetName,
            level = effectiveLevel,
            rawLevel = rawLevel,
            defenseSkill = defenseSkill,
            weaponSkill = weaponSkill,
            color = { r, g, b },
        }
    end

    local bLevel = pLevel + TARGET_LEVEL_OFFSET
    return {
        isTarget = false,
        isPlayer = false,
        isSkull = true,
        name = "boss",
        level = bLevel,
        rawLevel = -1,
        defenseSkill = bLevel * 5,
        weaponSkill = bLevel * 5,
        color = nil,
    }
end

local panelFrame = nil
local toggleButton = nil
local allRows = {}
local activeRowCount = 0
local inCombat = false
local pendingUpdate = false
local updateTimer = nil
local OnStateChanged = nil

-- ─────────────────────────────────────────────────────────────────────────────
--  Data Extraction & Combat Math
-- ─────────────────────────────────────────────────────────────────────────────

--- Get equipped weapon details and effective skill from Camelot gear system
--- @param slotID number 16: main hand, 17: off hand, 18: ranged
--- @return table|nil
local function GetEquippedWeaponInfo(slotID)
    if sfui.gear and sfui.gear.get_equipped_weapon_info then
        return sfui.gear.get_equipped_weapon_info(slotID)
    end
    return nil
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
        if rawChance and not issecretvalue(rawChance) and rawChance >= 0 then
            chance = rawChance * 100
        end
    end

    if GetGlancingBlowPenalty then
        local rawPenalty = GetGlancingBlowPenalty(weaponSkill, targetDefenseSkill)
        if rawPenalty and not issecretvalue(rawPenalty) and rawPenalty >= 0 then
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

--- Compute armor physical damage reduction percentage
--- Authoritatively queries PaperDollFrame_GetArmorReductionAgainstTarget or PaperDollFrame_GetArmorReduction
--- with fallback to the official Classic Era 60+ formula.
--- @param armor number
--- @param target table
--- @return number armorDR (percentage, capped at 75%)
local function ComputeArmorReduction(armor, target)
    armor = safe_num(armor, 0)
    if armor <= 0 then return 0.0 end

    if target and target.isTarget and _G.PaperDollFrame_GetArmorReductionAgainstTarget then
        local targetDR = _G.PaperDollFrame_GetArmorReductionAgainstTarget(armor)
        if targetDR and not issecretvalue(targetDR) and targetDR > 0 then
            return math_min(75.0, targetDR)
        end
    end

    local attackerLevel = (target and target.level) or 63
    if _G.PaperDollFrame_GetArmorReduction then
        local lvlDR = _G.PaperDollFrame_GetArmorReduction(armor, attackerLevel)
        if lvlDR and not issecretvalue(lvlDR) and lvlDR > 0 then
            return math_min(75.0, lvlDR)
        end
    end

    if C_PaperDollInfo and C_PaperDollInfo.GetArmorEffectiveness then
        local eff = C_PaperDollInfo.GetArmorEffectiveness(armor, attackerLevel)
        if eff and not issecretvalue(eff) and eff > 0 then
            return math_min(75.0, eff * 100)
        end
    end

    -- Classic Era / Camelot formula:
    -- Level 1-59: 400 + 85 * level
    -- Level 60+:  400 + 85 * (level + 4.5 * (level - 59))
    local k = (attackerLevel >= 60) and (400 + 85 * (attackerLevel + 4.5 * (attackerLevel - 59))) or (400 + 85 * attackerLevel)
    return math_min(75.0, (armor / (armor + k)) * 100)
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

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1.0, 1.0, 1.0, 1.0)
        row.value = value

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 6, 0)
        label:SetPoint("RIGHT", value, "LEFT", -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(0.72, 0.72, 0.72, 1.0)
        row.label = label

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
        header.label:ClearAllPoints()
        header.label:SetPoint("LEFT", header, "LEFT", 6, 0)
        header.label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
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
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
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
    local target = GetActiveTelemetryTarget(pLevel)
    local baseSkill = pLevel * 5
    local softSkillCap = baseSkill + 5
    local defCritImmunity = target.weaponSkill + 125
    local isPvp = target.isTarget and target.isPlayer

    local pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or {}
    local dim = pal.dimTextColor or { 0.5, 0.5, 0.5 }

    if panelFrame and panelFrame.subTitle then
        if target.isTarget then
            if target.isSkull then
                panelFrame.subTitle:SetText(string_format("vs %s (boss / +3 lvl, %d def)", target.name:lower(), target.defenseSkill))
            else
                panelFrame.subTitle:SetText(string_format("vs %s (lv %d, %d def)", target.name:lower(), target.level, target.defenseSkill))
            end
            panelFrame.subTitle:SetTextColor(target.color[1], target.color[2], target.color[3], 1.0)
        else
            panelFrame.subTitle:SetText(string_format("vs lv %d boss (+3 lvl, %d def)", target.level, target.defenseSkill))
            panelFrame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
        end
    end

    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or _G.UnitClassBase("player")

    -- 1. Weapons & Glancing Math
    local wpnHeaderText = target.isTarget
        and string_format("weapon skills & glancing (%s)", target.isSkull and "vs boss" or string_format("vs lv %d", target.level))
        or string_format("weapon skills & glancing (vs lv %d boss)", target.level)
    y = AddHeaderRow(scrollChild, y, wpnHeaderText)

    local mhInfo = GetEquippedWeaponInfo(16)
    local mhSkill = mhInfo and mhInfo.skill or baseSkill
    local mhGlanceChance, mhGlancePenalty = 0.0, 0.0

    if isPvp then
        mhGlanceChance = 0.0
        mhGlancePenalty = 0.0
    elseif target.isTarget and (target.level < pLevel) and not target.isSkull then
        mhGlanceChance = 0.0
        mhGlancePenalty = 0.0
    elseif target.isSkull or (target.level >= pLevel + 3) then
        mhGlanceChance, mhGlancePenalty = ComputeGlancingBlowData(mhSkill, target.defenseSkill)
    else
        local rawChance = GetGlancingBlowChance and GetGlancingBlowChance(mhSkill, target.defenseSkill)
        if rawChance and not issecretvalue(rawChance) and rawChance >= 0 then
            mhGlanceChance = rawChance * 100
        else
            local skillDiff = target.defenseSkill - mhSkill
            mhGlanceChance = math_max(0.0, math_min(40.0, 10.0 + (skillDiff * 2.0)))
        end
        local _, rawPenalty = ComputeGlancingBlowData(mhSkill, target.defenseSkill)
        mhGlancePenalty = rawPenalty
    end

    local mhHitMod = safe_num(GetHitModifier and GetHitModifier())
    local crMeleeHit = safe_num(GetCombatRatingBonus and _G.CR_HIT_MELEE and GetCombatRatingBonus(_G.CR_HIT_MELEE))
    local totalMeleeHit = mhHitMod + crMeleeHit

    local yellowHitCap = 5.0
    if isPvp then
        yellowHitCap = 5.0
    else
        local skillDiff = target.defenseSkill - mhSkill
        if skillDiff > 10 then
            yellowHitCap = 7.0 + ((skillDiff - 10) * 0.4)
        elseif skillDiff >= 0 then
            yellowHitCap = math_max(5.0, 5.0 + (skillDiff * 0.1))
        else
            yellowHitCap = math_max(0.0, 5.0 + (skillDiff * 0.1))
        end
    end

    local mhSkillName = (mhInfo and mhInfo.skillName) or "weapon"
    local mhSkillTip = string_format("effective %s skill (soft cap %d).", mhSkillName:lower(), softSkillCap)
    y = AddDataRow(scrollChild, y, "main-hand:", string_format("%d / %d", mhSkill, mhInfo and mhInfo.maxSkill or baseSkill),
        (mhSkill >= softSkillCap) and COLOR_GREEN or COLOR_WHITE,
        "main-hand weapon skill", mhSkillTip)

    local glanceChanceText = isPvp and "0.0% (pvp)"
        or (target.isTarget and target.level < pLevel and not target.isSkull) and "0.0% (lower level)"
        or string_format("%.1f%%", mhGlanceChance)
    local glanceChanceColor = (isPvp or (target.isTarget and target.level < pLevel and not target.isSkull)) and COLOR_GREEN or COLOR_YELLOW
    local glanceChanceTip = isPvp and "attacks against players never glance."
        or (target.isTarget and target.level < pLevel and not target.isSkull) and "attacks against lower level mobs do not glance."
        or string_format("glancing blow chance on white attacks against %s.", target.isTarget and target.name:lower() or "bosses")
    y = AddDataRow(scrollChild, y, "glance chance:", glanceChanceText,
        glanceChanceColor,
        isPvp and "pvp: no glancing blows" or "glancing blow chance", glanceChanceTip)

    local glancePenaltyText = (isPvp or mhGlanceChance == 0) and "none" or string_format("-%.1f%% dmg", mhGlancePenalty)
    local glancePenaltyColor = (isPvp or mhGlanceChance == 0 or mhSkill >= softSkillCap) and COLOR_GREEN or COLOR_RED
    local glancePenaltyTip = (isPvp or mhGlanceChance == 0) and "no damage penalty suffered."
        or "damage penalty suffered on glancing blows."
    y = AddDataRow(scrollChild, y, "glance penalty:", glancePenaltyText,
        glancePenaltyColor,
        "glancing blow damage penalty", glancePenaltyTip)

    local hitCapTip = isPvp and "hit chance needed to never miss players (5.0%)."
        or string_format("hit chance needed for specials to never miss %s.", target.isTarget and target.name:lower() or "bosses")
    y = AddDataRow(scrollChild, y, "yellow hit cap:", string_format("%.1f%% (have %.1f%%)", yellowHitCap, totalMeleeHit),
        (totalMeleeHit >= yellowHitCap) and COLOR_GREEN or COLOR_YELLOW,
        "special / yellow hit cap", hitCapTip)

    local ohInfo = GetEquippedWeaponInfo(17)
    if ohInfo then
        local ohSkillName = (ohInfo and ohInfo.skillName) or "weapon"
        y = AddDataRow(scrollChild, y, "off-hand:", string_format("%d / %d", ohInfo.skill, ohInfo.maxSkill),
            (ohInfo.skill >= softSkillCap) and COLOR_GREEN or COLOR_WHITE,
            "off-hand weapon skill", string_format("effective %s skill for off-hand attacks.", ohSkillName:lower()))

        local ohHitMod = safe_num(GetOffhandHitModifier and GetOffhandHitModifier())
        local totalOhHit = ohHitMod + crMeleeHit
        y = AddDataRow(scrollChild, y, "off-hand hit:", string_format("+%.1f%%", totalOhHit),
            COLOR_LIGHT_BLUE,
            "off-hand hit modifier", "hit bonus applied to off-hand attacks.")

        local ohPenalty = 0.0
        if not isPvp and not (target.isTarget and target.level < pLevel and not target.isSkull) then
            local _, rawOhPenalty = ComputeGlancingBlowData(ohInfo.skill, target.defenseSkill)
            ohPenalty = rawOhPenalty
        end
        local ohPenaltyText = (isPvp or mhGlanceChance == 0) and "none" or string_format("-%.1f%% dmg", ohPenalty)
        local ohPenaltyColor = (isPvp or mhGlanceChance == 0 or ohInfo.skill >= softSkillCap) and COLOR_GREEN or COLOR_RED
        y = AddDataRow(scrollChild, y, "off-hand glance:", ohPenaltyText,
            ohPenaltyColor,
            "off-hand glancing penalty", "damage penalty on off-hand glancing blows.")

        y = AddDataRow(scrollChild, y, "dual wield miss:", "+19.0% miss",
            COLOR_DIM,
            "dual wield penalty", "dual wielding adds a 19% miss penalty to white attacks.")
    end

    -- 2. Defense & Avoidance vs Target/Boss
    y = y - 4
    local defHeaderText = target.isTarget
        and string_format("defense & avoidance (%s)", target.isSkull and "vs boss" or string_format("vs lv %d", target.level))
        or string_format("defense & avoidance (vs lv %d boss)", target.level)
    y = AddHeaderRow(scrollChild, y, defHeaderText)

    local effDef, baseDef, modDef, maxDef = baseSkill, baseSkill, 0, baseSkill
    if UnitDefenseSkill then
        local b, m = UnitDefenseSkill("player")
        baseDef = safe_num(b, baseSkill)
        modDef = safe_num(m, 0)
        effDef = math_max(0, baseDef + modDef)
        maxDef = baseSkill
    end

    local defTip = string_format("reduces incoming crit/hit chance (%d defense needed vs %s).", defCritImmunity, target.isTarget and target.name:lower() or "bosses")
    y = AddDataRow(scrollChild, y, "defense:", string_format("%d / %d", effDef, maxDef),
        (effDef >= defCritImmunity) and COLOR_GREEN or COLOR_WHITE,
        "defense skill", defTip)

    local targetSkillDiff = target.weaponSkill - effDef
    local critAgainstPlayer = math_max(0.0, math_min(100.0, 5.0 + (targetSkillDiff * 0.04)))
    local critValText = (not isPvp and effDef >= defCritImmunity) and "0.0% (immune)" or string_format("%.2f%%", critAgainstPlayer)
    local critValColor = (not isPvp and effDef >= defCritImmunity) and COLOR_GREEN or COLOR_RED
    local critTip = string_format("chance for %s to crit you (0.0%% at %d defense).", target.isTarget and target.name:lower() or "bosses", defCritImmunity)
    y = AddDataRow(scrollChild, y, "crit vs you:", critValText,
        critValColor,
        "crit chance against you", critTip)

    local crushingChance = 0.0
    local crushingText = "0.0%"
    local crushingColor = COLOR_ORANGE
    local crushingTip = ""

    if isPvp then
        crushingChance = 0.0
        crushingText = "0.0% (pvp)"
        crushingColor = COLOR_GREEN
        crushingTip = "players cannot deal crushing blows."
    elseif target.isTarget and (target.level < pLevel + 3) and not target.isSkull then
        crushingChance = 0.0
        crushingText = "0.0% (target < +3 lv)"
        crushingColor = COLOR_GREEN
        crushingTip = string_format("mobs must be 3+ levels higher (lv %d+) to crush.", pLevel + 3)
    else
        local crushingDiff = target.weaponSkill - math_min(effDef, maxDef)
        crushingChance = (crushingDiff >= 15) and math_max(0.0, math_min(100.0, (crushingDiff * 2.0) - 15.0)) or 0.0
        crushingText = string_format("%.1f%%", crushingChance)
        crushingColor = (crushingChance > 0) and COLOR_ORANGE or COLOR_GREEN
        crushingTip = "150% damage attacks from 3+ level higher mobs unless avoided."
    end

    y = AddDataRow(scrollChild, y, "crushing blow:", crushingText,
        crushingColor,
        "crushing blow chance", crushingTip)

    local rawDodge = safe_num(GetDodgeChance and GetDodgeChance())
    local rawParry = safe_num(GetParryChance and GetParryChance())
    local rawBlock = safe_num(GetBlockChance and GetBlockChance())
    local blockVal = safe_num(GetShieldBlock and GetShieldBlock())

    local skillMod = (baseSkill - target.weaponSkill) * 0.04
    local effDodge = math_max(0.0, rawDodge + skillMod)
    local effParry = (rawParry > 0) and math_max(0.0, rawParry + skillMod) or 0.0
    local effBlock = (rawBlock > 0) and math_max(0.0, rawBlock + skillMod) or 0.0

    y = AddDataRow(scrollChild, y, "dodge/parry/block:", string_format("%.1f / %.1f / %.1f%%", effDodge, effParry, effBlock),
        COLOR_LIGHT_GRAY,
        "avoidance chances", string_format("dodge: %.1f%%  |  parry: %.1f%%  |  block: %.1f%% (absorbs %d dmg)", effDodge, effParry, effBlock, blockVal))

    local effMiss = math_max(0.0, math_min(100.0, 5.0 + ((effDef - target.weaponSkill) * 0.04)))
    local totalAvoidance = effMiss + effDodge + effParry + effBlock
    local avoidanceGoal = 100.0
    local avoidanceTip = target.isTarget
        and string_format("effective avoidance vs %s (100%% pushes crushing/hits off table).", target.name:lower())
        or "effective avoidance vs boss (100% pushes crushing/hits off table, 102.4% raw)."

    y = AddDataRow(scrollChild, y, "total avoidance:", string_format("%.1f%%", totalAvoidance),
        (totalAvoidance >= avoidanceGoal) and COLOR_GREEN or COLOR_LIGHT_GRAY_2,
        "total avoidance", avoidanceTip)

    local effectiveArmor = 0
    if _G.UnitArmor then
        local _, eff = _G.UnitArmor("player")
        effectiveArmor = safe_num(eff, 0)
    end
    local armorDR = ComputeArmorReduction(effectiveArmor, target)
    local armorTipTitle = target.isTarget and "armor damage reduction vs target" or "armor damage reduction vs boss"
    local armorTipText = string_format("physical damage reduction from %s armor against %s (75%% cap).", BreakUpLargeNumbers(effectiveArmor), target.isTarget and (target.name:lower() .. " attacks") or "boss attacks")

    y = AddDataRow(scrollChild, y, "armor dr:", string_format("%.1f%%", armorDR),
        COLOR_MID_GRAY,
        armorTipTitle, armorTipText)

    -- 3. Ranged & Ammo (Hunter or classes with equipped ranged weapon/ammo)
    local rangedInfo = GetEquippedWeaponInfo(18)
    local usesAmmo = (UnitUsesAmmo and UnitUsesAmmo("player")) or (pClass == "HUNTER")
    if rangedInfo or usesAmmo then
        y = y - 4
        y = AddHeaderRow(scrollChild, y, "ranged & ammo")

        if rangedInfo then
            local rSkillName = rangedInfo.skillName or "ranged"
            y = AddDataRow(scrollChild, y, "ranged skill:", string_format("%d / %d", rangedInfo.skill, rangedInfo.maxSkill),
                (rangedInfo.skill >= softSkillCap) and COLOR_GREEN or COLOR_WHITE,
                "ranged weapon skill", string_format("effective %s weapon skill.", rSkillName:lower()))
        end

        if usesAmmo then
            local ammoCount = _G.GetInventoryItemCount and _G.GetInventoryItemCount("player", 0) or 0
            if issecretvalue(ammoCount) then ammoCount = 0 end
            local ammoID = _G.GetInventoryItemID and _G.GetInventoryItemID("player", 0)
            if issecretvalue(ammoID) then ammoID = nil end
            local ammoName = ammoID and C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(ammoID) or "no ammo equipped"

            y = AddDataRow(scrollChild, y, "ammo type:", tostring(ammoName):lower(),
                (ammoCount > 0) and COLOR_WHITE or COLOR_RED_ALERT,
                "equipped ammo", "currently equipped ammunition in slot 0.")

            y = AddDataRow(scrollChild, y, "ammo count:", BreakUpLargeNumbers(ammoCount),
                (ammoCount > 500) and COLOR_GREEN or (ammoCount > 100) and COLOR_YELLOW or COLOR_RED_ALERT,
                "ammo count", "remaining quantity of equipped ammunition.")
        end

        local rangedHit = safe_num(GetRangedHitModifier and GetRangedHitModifier())
        local crRangedHit = safe_num(GetCombatRatingBonus and _G.CR_HIT_RANGED and GetCombatRatingBonus(_G.CR_HIT_RANGED))
        local totalRangedHit = rangedHit + crRangedHit
        local rangedCrit = safe_num(GetRangedCritChance and GetRangedCritChance())

        y = AddDataRow(scrollChild, y, "ranged hit/crit:", string_format("%.1f%% / %.1f%%", totalRangedHit, rangedCrit),
            COLOR_LIGHT_GRAY,
            "ranged hit and crit", "ranged hit bonus and critical strike chance.")
    end

    -- 4. Spell & Mana (Mana users)
    local powerType = UnitPowerType("player")
    local isCaster = (powerType == Enum.PowerType.Mana) or (pClass == "MAGE" or pClass == "WARLOCK" or pClass == "PRIEST" or pClass == "DRUID" or pClass == "SHAMAN" or pClass == "PALADIN")
    if isCaster then
        y = y - 4
        y = AddHeaderRow(scrollChild, y, "spellcasting & mana")

        local spellHit = safe_num(GetSpellHitModifier and GetSpellHitModifier())
        local crSpellHit = safe_num(GetCombatRatingBonus and _G.CR_HIT_SPELL and GetCombatRatingBonus(_G.CR_HIT_SPELL))
        local totalSpellHit = spellHit + crSpellHit

        local spellHitCap = 16.0
        local baseSpellHit = 83.0

        if isPvp then
            spellHitCap = 3.0
            baseSpellHit = 96.0
        else
            local lvlDelta = target.level - pLevel
            if target.isSkull or lvlDelta >= 3 then
                spellHitCap = 16.0
                baseSpellHit = 83.0
            elseif lvlDelta == 2 then
                spellHitCap = 6.0
                baseSpellHit = 94.0
            elseif lvlDelta == 1 then
                spellHitCap = 5.0
                baseSpellHit = 95.0
            elseif lvlDelta == 0 then
                spellHitCap = 4.0
                baseSpellHit = 96.0
            else
                spellHitCap = math_max(1.0, 4.0 + lvlDelta)
                baseSpellHit = 100.0 - (spellHitCap + 1.0)
            end
        end

        local spellHitTip = string_format("spell hit chance against %s (%.1f%% cap).", target.isTarget and target.name:lower() or "bosses", spellHitCap)

        y = AddDataRow(scrollChild, y, "spell hit:", string_format("%.1f%% / %.1f%%", totalSpellHit, spellHitCap),
            (totalSpellHit >= spellHitCap) and COLOR_GREEN or COLOR_WHITE,
            "spell hit chance", spellHitTip)

        local spellCrit = safe_num(GetSpellCritChance and GetSpellCritChance())
        if GetSpellCritChance then
            for school = 2, 7 do
                local sCrit = safe_num(GetSpellCritChance(school))
                if sCrit > spellCrit then
                    spellCrit = sCrit
                end
            end
        end
        y = AddDataRow(scrollChild, y, "spell crit:", string_format("%.2f%%", spellCrit),
            COLOR_PURPLE_BLUE,
            "spell crit chance", "base spell critical strike chance.")

        local spellPen = safe_num(GetSpellPenetration and GetSpellPenetration())
        y = AddDataRow(scrollChild, y, "spell pen:", tostring(spellPen),
            COLOR_MID_GRAY,
            "spell penetration", "reduces target magic resistance against your spells.")

        if GetManaRegen then
            local baseRegen, castingRegen = GetManaRegen()
            baseRegen = safe_num(baseRegen) * 5
            castingRegen = safe_num(castingRegen) * 5
            y = AddDataRow(scrollChild, y, "mana regen:", string_format("%.0f / %.0f", baseRegen, castingRegen),
                COLOR_MANA_BLUE,
                "mana regeneration", "mana restored per 5 seconds (not casting / while casting).")
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

-- ─────────────────────────────────────────────────────────────────────────────
--  Lifecycle & Debounced State Updates
-- ─────────────────────────────────────────────────────────────────────────────

local DEBOUNCE_OUT_OF_COMBAT = 0.4
local DEBOUNCE_IN_COMBAT     = 2.0

OnStateChanged = function()
    if not panelFrame or not panelFrame:IsShown() or (CharacterFrame and not CharacterFrame:IsShown()) then
        pendingUpdate = true
        return
    end

    if updateTimer then
        pendingUpdate = true
        return
    end

    local isCombatActive = inCombat or (InCombatLockdown and InCombatLockdown())
    local delay = isCombatActive and DEBOUNCE_IN_COMBAT or DEBOUNCE_OUT_OF_COMBAT

    pendingUpdate = false
    updateTimer = C_Timer.NewTimer(delay, function()
        updateTimer = nil
        if panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
            panelModule.UpdateValues()
            if pendingUpdate then
                OnStateChanged()
            end
        else
            pendingUpdate = true
        end
    end)
end

function panelModule.CreatePanel()
    if panelFrame then return panelFrame end

    panelFrame = CreateFrame("Frame", "SfuiCharacterInfoPanel", UIParent, "BackdropTemplate")
    panelFrame:Hide()
    panelFrame:SetFrameStrata("HIGH")
    panelFrame:SetFrameLevel((CharacterFrame and CharacterFrame:GetFrameLevel() or 10) + 5)
    panelFrame:SetSize(290, 420)
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
        if updateTimer then
            updateTimer:Cancel()
            updateTimer = nil
        end
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
    subTitle:SetWidth(270)
    subTitle:SetWordWrap(false)
    subTitle:SetJustifyH("CENTER")
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
        RestorePosition(panelFrame)
        if activeRowCount == 0 or not (inCombat or (InCombatLockdown and InCombatLockdown())) then
            panelModule.UpdateValues()
        else
            OnStateChanged()
        end
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
            tip:AddLine("click to toggle combat telemetry panel.", 0.8, 0.8, 0.8, true)
            tip:AddLine("drag to move | shift+right-click to reset.", 0.65, 0.65, 0.65, true)
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
            if SfuiDB then SfuiDB.showCombatInfoPanel = true end
            RestorePosition(panelFrame)
            panelFrame:Show()
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
--  Initialization
-- ─────────────────────────────────────────────────────────────────────────────

local function Initialize()
    panelModule.CreatePanel()
    panelModule.CreateToggleButton()

    if CharacterFrame then
        if CharacterFrame:IsShown() and SfuiDB and SfuiDB.showCombatInfoPanel then
            if not panelFrame then panelModule.CreatePanel() end
            if not panelFrame:IsShown() then
                panelFrame:Show()
            else
                RestorePosition(panelFrame)
                if inCombat or (InCombatLockdown and InCombatLockdown()) then
                    OnStateChanged()
                else
                    panelModule.UpdateValues()
                end
            end
        else
            if panelFrame then panelFrame:Hide() end
        end

        if not panelModule._cfHooked then
            panelModule._cfHooked = true
            hooksecurefunc(CharacterFrame, "Show", function()
                if sfui.character and sfui.character.AlignHeaderButtons then
                    sfui.character.AlignHeaderButtons()
                end
                if SfuiDB and SfuiDB.showCombatInfoPanel then
                    if not panelFrame then panelModule.CreatePanel() end
                    if not panelFrame:IsShown() then
                        panelFrame:Show()
                    else
                        RestorePosition(panelFrame)
                        if inCombat or (InCombatLockdown and InCombatLockdown()) then
                            OnStateChanged()
                        else
                            panelModule.UpdateValues()
                        end
                    end
                end
            end)

            hooksecurefunc(CharacterFrame, "Hide", function()
                if panelFrame and panelFrame:IsShown() then
                    panelFrame:Hide()
                end
            end)
        end
    else
        if panelFrame then panelFrame:Hide() end
    end

    local events = {
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_TARGET_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
        "SKILL_LINES_CHANGED",
        "CHAT_MSG_SKILL",
        "UNIT_STATS",
        "CHARACTER_POINTS_CHANGED",
        "PLAYER_LEVEL_UP",
        "UPDATE_SHAPESHIFT_FORM",
    }

    local watcher = CreateFrame("Frame")
    for _, evt in ipairs(events) do
        watcher:RegisterEvent(evt)
    end
    watcher:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            if panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
                OnStateChanged()
            end
            return
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            if panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
                if updateTimer then
                    updateTimer:Cancel()
                    updateTimer = nil
                end
                panelModule.UpdateValues()
            end
            return
        end

        if event == "PLAYER_TARGET_CHANGED" then
            if panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown()) then
                OnStateChanged()
            end
            return
        end

        if (event == "UNIT_STATS" or event == "UNIT_INVENTORY_CHANGED") and arg1 ~= "player" then
            return
        end

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
