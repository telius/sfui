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
--  Context-Aware Combat Telemetry Panel (slides out next to the character frame)
--
--  Section order and depth adapt to what the player actually plays:
--    spec / role  : sfui.common.get_current_spec_id()   (core/talents_camelot.lua resolver)
--                   sfui.gear.GetClassicRole()            (core/bridge.lua, honours gear-manager role picks)
--                   live druid form (bear → tank, cat → melee)
--    weapons      : sfui.gear.get_equipped_weapon_info()  (frames/gear/gear_camelot.lua)
--    combat math  : sfui.stats.*                           (data/stats.lua)
--  This file only resolves context and renders rows — it owns no combat formulas.
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local UnitLevel = _G.UnitLevel
local UnitExists = _G.UnitExists
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsPlayer = _G.UnitIsPlayer
local UnitClassification = _G.UnitClassification
local UnitPowerType = _G.UnitPowerType
local UnitArmor = _G.UnitArmor
local GetCreatureDifficultyColor = _G.GetCreatureDifficultyColor
local GetDodgeChance = _G.GetDodgeChance
local GetParryChance = _G.GetParryChance
local GetSpellPenetration = _G.GetSpellPenetration
local GetInventoryItemCount = _G.GetInventoryItemCount
local GetInventoryItemID = _G.GetInventoryItemID
local BreakUpLargeNumbers = _G.BreakUpLargeNumbers or tostring
local Enum = _G.Enum or {}
local math_max = math.max
local math_floor = math.floor
local string_format = string.format
local tostring = _G.tostring

local common = sfui.common
local stats = sfui.stats
local gear = sfui.gear
local num = stats.num
local issecretvalue = common.issecretvalue or _G.issecretvalue or function() return false end

local CharacterFrame = _G.CharacterFrame

-- ─────────────────────────────────────────────────────────────────────────────
--  Constants
-- ─────────────────────────────────────────────────────────────────────────────

local BOSS_LEVEL_OFFSET = 3
local SKILL_PER_LEVEL   = 5
local CRIT_IMMUNITY_GAP = 125 -- defense above attacker skill that removes the 5% base crit (0.04% per point)
local AP_PER_DPS        = 14  -- ATTACK_POWER_MAGIC_NUMBER
local DEBOUNCE_DELAY    = 0.4
local DEBOUNCE_KEY      = "sfui_infopanel_refresh"

local POWER_MANA    = (Enum.PowerType and Enum.PowerType.Mana) or 0
local POWER_RAGE    = (Enum.PowerType and Enum.PowerType.Rage) or 1
local POWER_ENERGY  = (Enum.PowerType and Enum.PowerType.Energy) or 3
local WAND_SUBCLASS = (Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Wand) or 19

-- Static color constants (no runtime table allocations during refreshes)
local COLOR_GREEN           = { 0.3, 1.0, 0.3 }
local COLOR_WHITE           = { 1.0, 1.0, 1.0 }
local COLOR_YELLOW          = { 1.0, 0.82, 0.2 }
local COLOR_RED             = { 1.0, 0.4, 0.4 }
local COLOR_ORANGE          = { 1.0, 0.6, 0.2 }
local COLOR_DIM             = { 0.7, 0.7, 0.7 }
local COLOR_LIGHT_GRAY      = { 0.85, 0.85, 0.85 }
local COLOR_MID_GRAY        = { 0.8, 0.8, 0.8 }
local COLOR_MANA_BLUE       = { 0.4, 0.8, 1.0 }
local COLOR_SPELL           = { 0.85, 0.85, 1.0 }
local COLOR_HEAL            = { 0.55, 1.0, 0.65 }
local COLOR_ACCENT_FALLBACK = { 0.4, 0.8, 1.0 }
local EMPTY_PALETTE         = {}

-- Resistance schools (Enum.Damageclass ids for UnitResistance)
local DMG = Enum.Damageclass or {}
local RESIST_SCHOOLS = {
    { damageClass = DMG.Fire or 2,   name = "fire",   color = { 1.0, 0.55, 0.25 } },
    { damageClass = DMG.Nature or 3, name = "nature", color = { 0.45, 0.9, 0.35 } },
    { damageClass = DMG.Frost or 4,  name = "frost",  color = { 0.55, 0.8, 1.0 } },
    { damageClass = DMG.Shadow or 5, name = "shadow", color = { 0.7, 0.5, 1.0 } },
    { damageClass = DMG.Arcane or 6, name = "arcane", color = { 0.95, 0.7, 1.0 } },
}

-- GetSpellBonusDamage luaIndex → school name (1 = physical is never shown)
local SPELL_SCHOOL_NAMES = { [2] = "holy", [3] = "fire", [4] = "nature", [5] = "frost", [6] = "shadow", [7] = "arcane" }

-- Classic role key (sfui.gear.GetClassicRole) → telemetry archetype
local ROLE_ARCHETYPE = {
    bear = "tank", prot = "tank", tank = "tank",
    resto = "healer", holy = "healer", disc = "healer", heal = "healer",
    moon = "caster", ele = "caster", shad = "caster",
    arc = "caster", fire = "caster", frost = "caster",
    aff = "caster", demo = "caster", destro = "caster",
    bm = "ranged", mm = "ranged", surv = "ranged",
    cat = "melee", ret = "melee", arms = "melee", fury = "melee", enh = "melee",
    sin = "melee", combat = "melee", sub = "melee",
}

-- Section order per archetype. Each renderer decides its own depth (full vs compact)
-- and may skip itself entirely when irrelevant (e.g. spell section for warriors).
local SECTION_ORDER = {
    caster = { "spell", "ranged", "resist", "defense" },
    healer = { "spell", "ranged", "resist", "defense" },
    tank   = { "defense", "melee", "resist", "spell", "ranged" },
    melee  = { "melee", "defense", "resist", "spell", "ranged" },
    ranged = { "ranged", "melee", "spell", "defense", "resist" },
}

-- ─────────────────────────────────────────────────────────────────────────────
--  State
-- ─────────────────────────────────────────────────────────────────────────────

local panelFrame = nil
local toggleButton = nil
local inCombat = false

-- Render context, reused across refreshes (zero table churn per update)
local ctx = {
    target      = {},
    incoming    = {},
    schoolPower = {},
}

local function IsInCombat()
    return inCombat or (InCombatLockdown and InCombatLockdown())
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Context Resolution
-- ─────────────────────────────────────────────────────────────────────────────

--- Fill `t` with the selected (living) target, or a level +3 raid boss when nothing is targeted.
local function resolve_target(t, pLevel)
    local bossLevel = pLevel + BOSS_LEVEL_OFFSET
    if UnitExists("target") and not UnitIsDeadOrGhost("target") then
        local rawLevel = num(UnitLevel("target"), -1)
        local name = UnitName("target")
        t.isTarget = true
        t.isPlayer = UnitIsPlayer("target") and true or false
        t.isSkull  = rawLevel <= 0 or UnitClassification("target") == "worldboss"
        t.name     = (name and not issecretvalue(name)) and name:lower() or "target"
        t.level    = t.isSkull and bossLevel or rawLevel
    else
        t.isTarget, t.isPlayer, t.isSkull, t.name, t.level = false, false, true, "boss", bossLevel
    end
    t.defense     = t.level * SKILL_PER_LEVEL
    t.weaponSkill = t.level * SKILL_PER_LEVEL
    t.levelDelta  = t.level - pLevel
    t.who         = t.isTarget and t.name or "bosses"

    local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(t.level)
    t.r, t.g, t.b = (c and c.r) or 1.0, (c and c.g) or 0.82, (c and c.b) or 0.2
    return t
end

--- Resolve role, gear and shared stat snapshot once per refresh.
local function resolve_context()
    local pLevel    = UnitLevel("player") or 60
    local pClass    = common.get_player_class()
    local specID    = common.get_current_spec_id()
    local roleKey   = gear.GetClassicRole(specID, gear.GetSpecDB(specID))
    local powerType = UnitPowerType("player")
    local archetype = ROLE_ARCHETYPE[roleKey] or "melee"

    -- live druid forms override the saved role: bear plays as a tank, cat as melee
    local form = nil
    if pClass == "DRUID" then
        if powerType == POWER_RAGE then
            archetype, form = "tank", "bear form"
        elseif powerType == POWER_ENERGY then
            archetype, form = "melee", "cat form"
        end
    end

    local lookup = sfui.talents.CLASSIC_SPEC_LOOKUP and sfui.talents.CLASSIC_SPEC_LOOKUP[specID]
    local specName = (lookup and lookup.name) or tostring(UnitClass("player") or ""):lower()

    ctx.level     = pLevel
    ctx.baseSkill = pLevel * SKILL_PER_LEVEL
    ctx.class     = pClass
    ctx.roleKey   = roleKey
    ctx.archetype = archetype
    ctx.label     = form and string_format("%s (%s)", specName, form) or specName
    ctx.onMana    = (powerType == POWER_MANA)

    ctx.mh     = gear.get_equipped_weapon_info(16)
    ctx.oh     = gear.get_equipped_weapon_info(17)
    ctx.ranged = gear.get_equipped_weapon_info(18)
    ctx.isWand = (ctx.ranged and ctx.ranged.subclassID == WAND_SUBCLASS) or false

    local _
    _, ctx.meleeHit, ctx.rangedHit, ctx.spellHit = stats.GetHitChance("player")
    _, ctx.meleeCrit, ctx.rangedCrit, ctx.spellCrit = stats.GetCritChance("player")
    _, ctx.meleeHaste, ctx.rangedHaste, ctx.spellHaste = stats.GetHaste("player")

    local t = resolve_target(ctx.target, pLevel)
    ctx.defense = stats.GetEffectiveDefense("player")
    stats.GetIncomingCombatTable(t.weaponSkill, ctx.defense, t.isPlayer, ctx.incoming)
    return ctx
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Row Pool & Layout Cursor
-- ─────────────────────────────────────────────────────────────────────────────

local allRows = {}
local activeRowCount = 0
local cursorY = 0
local scrollChild = nil
local pal = EMPTY_PALETTE -- palette snapshot for the current render pass

local function row_on_enter(self)
    self.highlight:Show()
    if not self.tooltipTitle then return end
    local tip = common.get_tooltip and common.get_tooltip()
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:ClearLines()
    tip:AddLine(self.tooltipTitle, 1, 1, 1)
    if self.tooltipText then
        tip:AddLine(self.tooltipText, 0.8, 0.8, 0.8, true)
    end
    tip:Show()
end

local function row_on_leave(self)
    self.highlight:Hide()
    if common.hide_tooltip then common.hide_tooltip() end
end

local function acquire_row()
    activeRowCount = activeRowCount + 1
    local row = allRows[activeRowCount]
    if not row then
        row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(18)
        row:EnableMouse(true)

        local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        value:SetJustifyH("RIGHT")
        row.value = value

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label

        local highlight = row:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints(row)
        highlight:Hide()
        row.highlight = highlight

        row:SetScript("OnEnter", row_on_enter)
        row:SetScript("OnLeave", row_on_leave)
        allRows[activeRowCount] = row
    elseif row:GetParent() ~= scrollChild then
        row:SetParent(scrollChild)
        row.currentY = nil
    end
    return row
end

--- Position a pooled row at the cursor, re-anchoring only when its slot or kind changed.
local function place_row(row, isHeader, height)
    if row.currentY == cursorY and row.isHeader == isHeader then return end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, cursorY)
    row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, cursorY)
    row:SetHeight(height)
    row.currentY = cursorY
    row.isHeader = isHeader
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    if isHeader then
        row.label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    else
        row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    end
end

local function header(titleText)
    if activeRowCount > 0 then cursorY = cursorY - 4 end
    local h = acquire_row()
    place_row(h, true, 22)

    local accent = pal.accentColor or (sfui.config and sfui.config.spec_color) or COLOR_ACCENT_FALLBACK
    h.label:SetText(titleText)
    h.label:SetTextColor(accent[1] or 0.4, accent[2] or 0.8, accent[3] or 1.0, 1.0)
    h.value:SetText("")
    h.tooltipTitle, h.tooltipText = nil, nil
    h:EnableMouse(false)

    if not h.sep then
        h.sep = h:CreateTexture(nil, "ARTWORK")
        h.sep:SetHeight(1)
        h.sep:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 4, 1)
        h.sep:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -4, 1)
    end
    local isCamelotTheme = sfui.theme and sfui.theme.IsCamelotActive and sfui.theme.IsCamelotActive()
    local hl = pal.highlightColor
    if isCamelotTheme and hl then
        h.sep:SetColorTexture(hl[1], hl[2], hl[3], 0.35)
    else
        h.sep:SetColorTexture(0.25, 0.25, 0.25, 0.75)
    end
    h.sep:Show()
    h:Show()
    cursorY = cursorY - 24
end

local function row(labelText, valueText, valColor, tipTitle, tipText)
    local r = acquire_row()
    place_row(r, false, 18)
    if r.sep then r.sep:Hide() end

    local dim = pal.dimTextColor or COLOR_DIM
    r.label:SetText(labelText)
    r.label:SetTextColor(dim[1], dim[2], dim[3], 1.0)

    local vc = valColor or pal.headerColor or COLOR_WHITE
    r.value:SetText(valueText)
    r.value:SetTextColor(vc[1], vc[2], vc[3], 1.0)

    local hl = pal.highlightColor
    if hl then
        r.highlight:SetColorTexture(hl[1], hl[2], hl[3], 0.12)
    else
        r.highlight:SetColorTexture(1, 1, 1, 0.05)
    end

    r.tooltipTitle, r.tooltipText = tipTitle, tipText
    r:EnableMouse(tipTitle ~= nil)
    r:Show()
    cursorY = cursorY - 18
end

local function have_vs_cap(have, cap)
    return string_format("%.1f%% / %.1f%%", have, cap), (have >= cap) and COLOR_GREEN or COLOR_YELLOW
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Section Renderers
-- ─────────────────────────────────────────────────────────────────────────────

local SECTIONS = {}

--- Spell power, hit, crit, regen. Full for casters / healers, compact for mana hybrids.
function SECTIONS.spell(c)
    local arch = c.archetype
    local full = (arch == "caster" or arch == "healer")
    if not full and not c.onMana then return end

    local minDmg, maxDmg, maxSchool, healing = stats.GetSpellPower(c.schoolPower)
    local idleRegen, castRegen = stats.GetManaRegen()

    header((arch == "healer" and "healing & mana") or (full and "spellcasting & mana") or "mana & spell power")

    if arch == "healer" then
        row("bonus healing:", BreakUpLargeNumbers(healing), COLOR_HEAL,
            "bonus healing", "healing added to your spells by gear and buffs.")
    end

    if full or maxDmg > 0 then
        local p = c.schoolPower
        local text = (maxDmg > minDmg)
            and string_format("%d (%s %d)", minDmg, SPELL_SCHOOL_NAMES[maxSchool], maxDmg)
            or BreakUpLargeNumbers(maxDmg)
        row("spell damage:", text, COLOR_SPELL, "spell damage by school",
            string_format("holy %d  |  fire %d  |  nature %d\nfrost %d  |  shadow %d  |  arcane %d",
                p[2] or 0, p[3] or 0, p[4] or 0, p[5] or 0, p[6] or 0, p[7] or 0))
    end

    if arch == "caster" then
        local t = c.target
        local miss, cap = stats.GetSpellMissChance(t.levelDelta, t.isPlayer)
        local text, color = have_vs_cap(c.spellHit, cap)
        row("spell hit:", text, color, "spell hit cap",
            string_format("spells miss %s %.0f%% of the time; %.0f%% hit reaches the cap (1%% always misses).", t.who, miss, cap))

        local pen = num(GetSpellPenetration and GetSpellPenetration())
        if pen > 0 then
            row("spell pen:", tostring(pen), COLOR_MID_GRAY,
                "spell penetration", "reduces the target's resistances against your spells.")
        end
    end

    if full then
        row("spell crit:", string_format("%.2f%%", c.spellCrit), COLOR_SPELL,
            "spell crit chance", "critical strike chance for spells.")
        if c.spellHaste > 0 then
            row("spell haste:", string_format("%.1f%%", c.spellHaste), COLOR_LIGHT_GRAY,
                "spell haste", "reduces cast times.")
        end
    end

    row("mana regen:", string_format("%d / %d", castRegen, idleRegen), COLOR_MANA_BLUE,
        "mana per 5 sec", "while casting / outside the five-second rule.")
end

--- Magic resistances with expected mitigation against the target's level.
function SECTIONS.resist(c)
    local casterLevel = c.target.level
    header("resistances")
    for i = 1, #RESIST_SCHOOLS do
        local s = RESIST_SCHOOLS[i]
        local effective, bonus, reduction = stats.GetResistance(s.damageClass, casterLevel)
        row(s.name .. ":", string_format("%d  (%.0f%%)", effective, reduction),
            (effective > 0) and s.color or COLOR_DIM,
            s.name .. " resistance",
            string_format("%d total (%+d from gear & buffs). resists %.1f%% of %s damage on average vs lv %d casters (75%% cap).",
                effective, bonus, reduction, s.name, casterLevel))
    end
end

--- Incoming attack table. Full avoidance breakdown for tanks, survivability summary otherwise.
function SECTIONS.defense(c)
    local t, inc = c.target, c.incoming
    local isTank = (c.archetype == "tank")
    local immunity = t.weaponSkill + CRIT_IMMUNITY_GAP

    header(isTank and "defense & avoidance" or "defense")

    if isTank then
        row("defense:", string_format("%d / %d", c.defense, immunity),
            (c.defense >= immunity) and COLOR_GREEN or COLOR_YELLOW,
            "defense (crit immunity)",
            string_format("%d defense stops %s from critting you (5%% base, -0.04%% per point).", immunity, t.who))
    else
        row("defense:", tostring(c.defense), COLOR_WHITE,
            "defense skill", string_format("%d defense needed for crit immunity vs %s.", immunity, t.who))
    end

    if t.isPlayer then
        row("crit vs you:", "n/a (pvp)", COLOR_DIM, "crit chance against you",
            "player crit depends on their gear; each defense point reduces it by 0.04%.")
    else
        local immune = inc.critChance <= 0
        row("crit vs you:", immune and "0.0% (immune)" or string_format("%.2f%%", inc.critChance),
            immune and COLOR_GREEN or COLOR_RED, "crit chance against you",
            string_format("chance for %s to crit you (0%% at %d defense).", t.who, immunity))
    end

    -- dodge / parry / block, shifted by the attacker's weapon skill
    local mod = inc.avoidanceMod
    local dodge = math_max(0, num(GetDodgeChance and GetDodgeChance()) + mod)
    local rawParry = num(GetParryChance and GetParryChance())
    local parry = (rawParry > 0) and math_max(0, rawParry + mod) or 0
    local rawBlock, blockValue = stats.GetBlockInfo("player")
    local block = (rawBlock > 0) and math_max(0, rawBlock + mod) or 0

    if isTank then
        if t.isPlayer then
            row("crushing blow:", "0.0% (pvp)", COLOR_GREEN, "crushing blows", "players cannot deal crushing blows.")
        else
            local crush = inc.crushingChance
            row("crushing blow:", string_format("%.1f%%", crush), (crush > 0) and COLOR_ORANGE or COLOR_GREEN,
                "crushing blows", "150% damage hits from mobs 3+ levels above you, unless pushed off the table.")
        end
    end

    row("dodge / parry:", string_format("%.1f / %.1f%%", dodge, parry), COLOR_LIGHT_GRAY,
        "avoidance vs " .. t.who, "includes the attacker's weapon skill adjustment.")

    if isTank then
        if block > 0 then
            row("block:", string_format("%.1f%% (%d)", block, blockValue), COLOR_LIGHT_GRAY,
                "shield block", string_format("chance to block, absorbing %d damage per block.", blockValue))
        end
        local total = inc.missChance + dodge + parry + block
        row("total avoidance:", string_format("%.1f%%", total), (total >= 100) and COLOR_GREEN or COLOR_LIGHT_GRAY,
            "miss + dodge + parry + block",
            string_format("miss %.1f%%  |  dodge %.1f%%  |  parry %.1f%%  |  block %.1f%%\n100%% pushes crushing blows and normal hits off the attack table.",
                inc.missChance, dodge, parry, block))
    end

    local _, armor = UnitArmor("player")
    armor = num(armor)
    local dr = stats.GetArmorReduction(armor, t.level, t.isTarget)
    row("armor:", string_format("%s (%.1f%%)", BreakUpLargeNumbers(armor), dr), COLOR_MID_GRAY,
        "armor damage reduction", string_format("physical damage reduction vs lv %d attacks (75%% cap).", t.level))
end

--- Melee weapon skill, hit cap, glancing. Compact (skill + hit) for hunters.
function SECTIONS.melee(c)
    local t = c.target
    local compact = (c.archetype == "ranged")
    local mh = c.mh
    local mhSkill = (mh and mh.skill) or c.baseSkill
    local softCap = c.baseSkill + SKILL_PER_LEVEL
    local miss, cap, dwCap = stats.GetMeleeMissChance(mhSkill, t.defense, t.isPlayer)

    header(compact and "melee" or "melee & weapon skill")

    if not compact then
        local ap = stats.GetAttackPower(false)
        row("attack power:", BreakUpLargeNumbers(ap), COLOR_WHITE,
            "melee attack power", string_format("adds %.1f damage per second to melee attacks.", ap / AP_PER_DPS))
    end

    row("main-hand:", string_format("%d / %d", mhSkill, (mh and mh.maxSkill) or c.baseSkill),
        (mhSkill >= softCap) and COLOR_GREEN or COLOR_WHITE,
        ((mh and mh.skillName) or "weapon") .. " skill",
        string_format("%d skill removes most of the glancing penalty vs lv %d.", softCap, t.level))

    local hitText, hitColor = have_vs_cap(c.meleeHit, cap)
    row("hit:", hitText, hitColor, "special attack hit cap",
        string_format("specials miss %s %.1f%% of the time (%d skill vs %d defense).", t.who, miss, mhSkill, t.defense))

    if compact then return end

    row("crit:", string_format("%.2f%%", c.meleeCrit), COLOR_LIGHT_GRAY,
        "melee crit chance", "character sheet critical strike chance.")

    local glanceChance, glancePenalty = stats.GetGlancingBlow(mhSkill, t.level, t.isPlayer)
    if glanceChance > 0 then
        row("glancing:", string_format("%.0f%% (-%.0f%% dmg)", glanceChance, glancePenalty),
            (mhSkill >= softCap) and COLOR_YELLOW or COLOR_RED, "glancing blows",
            string_format("white swings vs %s glance %.1f%% of the time for %.1f%% less damage.", t.who, glanceChance, glancePenalty))
    else
        row("glancing:", "none", COLOR_GREEN, "glancing blows",
            t.isPlayer and "attacks against players never glance." or "targets below your level do not glance.")
    end

    local oh = c.oh
    if oh then
        local _, ohPenalty = stats.GetGlancingBlow(oh.skill, t.level, t.isPlayer)
        local ohText = (glanceChance > 0)
            and string_format("%d / %d (-%.0f%%)", oh.skill, oh.maxSkill, ohPenalty)
            or string_format("%d / %d", oh.skill, oh.maxSkill)
        row("off-hand:", ohText, (oh.skill >= softCap) and COLOR_GREEN or COLOR_WHITE,
            (oh.skillName or "weapon") .. " skill", "off-hand weapon skill and its glancing penalty.")

        local dwText = string_format("%.1f%% / %.1f%%", c.meleeHit, dwCap)
        row("white hit (dw):", dwText, (c.meleeHit >= dwCap) and COLOR_GREEN or COLOR_DIM,
            "dual-wield white hit cap", "dual wielding adds a large miss penalty to auto attacks; specials use the normal cap.")
    end
end

--- Ranged weapon, hit cap and ammo. Full for hunters, wand rows for casters / healers,
--- skill + hit for melee pullers. Ammo rows only apply to ammo-firing weapons.
function SECTIONS.ranged(c)
    local t, r = c.target, c.ranged
    local isRangedArch = (c.archetype == "ranged")
    if not r and not isRangedArch then return end
    local isWand = c.isWand

    header((isWand and "wand") or (isRangedArch and "ranged & ammo") or "ranged")

    if isRangedArch and not isWand then
        local rap = stats.GetAttackPower(true)
        row("ranged ap:", BreakUpLargeNumbers(rap), COLOR_WHITE,
            "ranged attack power", string_format("adds %.1f damage per second to ranged attacks.", rap / AP_PER_DPS))
    end

    if r then
        local miss, cap = stats.GetMeleeMissChance(r.skill, t.defense, t.isPlayer)
        row(isWand and "wand skill:" or "ranged skill:", string_format("%d / %d", r.skill, r.maxSkill),
            (r.skill >= c.baseSkill + SKILL_PER_LEVEL) and COLOR_GREEN or COLOR_WHITE,
            (r.skillName or "ranged") .. " skill", "effective ranged weapon skill.")

        if isWand then
            local dps, minDmg, maxDmg, speed = stats.GetRangedDamage()
            row("wand dps:", string_format("%.1f", dps), COLOR_SPELL, "wand damage",
                string_format("%.0f - %.0f damage every %.2f sec.", minDmg, maxDmg, speed))
        end

        local hitText, hitColor = have_vs_cap(c.rangedHit, cap)
        row(isWand and "wand hit:" or "ranged hit:", hitText, hitColor, "ranged hit cap",
            string_format("shots miss %s %.1f%% of the time (%d skill vs %d defense).", t.who, miss, r.skill, t.defense))
    end

    if not isRangedArch or isWand then return end

    row("ranged crit:", string_format("%.2f%%", c.rangedCrit), COLOR_LIGHT_GRAY,
        "ranged crit chance", "character sheet ranged critical strike chance.")
    if c.rangedHaste > 0 then
        row("ranged haste:", string_format("%.1f%%", c.rangedHaste), COLOR_LIGHT_GRAY,
            "ranged haste", "includes quiver and ammo pouch haste.")
    end

    if sfui.api and sfui.api.UnitUsesAmmo and sfui.api.UnitUsesAmmo("player") then
        local count = num(GetInventoryItemCount and GetInventoryItemCount("player", 0))
        local ammoID = GetInventoryItemID and GetInventoryItemID("player", 0)
        if ammoID and issecretvalue(ammoID) then ammoID = nil end
        local ammoName = ammoID and common.get_item_info(ammoID)
        row("ammo:", ammoName and ammoName:lower() or "none equipped", ammoName and COLOR_WHITE or COLOR_RED,
            "equipped ammunition", "ammunition in the ammo slot.")
        row("ammo count:", BreakUpLargeNumbers(count),
            (count > 500 and COLOR_GREEN) or (count > 100 and COLOR_YELLOW) or COLOR_RED,
            "ammo count", "remaining quantity of equipped ammunition.")
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Render Pass
-- ─────────────────────────────────────────────────────────────────────────────

local function update_subtitle(c)
    local sub = panelFrame and panelFrame.subTitle
    if not sub then return end
    local t = c.target
    local vs
    if not t.isTarget then
        vs = string_format("vs lv %d boss", t.level)
    elseif t.isSkull then
        vs = string_format("vs %s (boss)", t.name)
    else
        vs = string_format("vs %s (lv %d)", t.name, t.level)
    end
    sub:SetText(string_format("%s - %s, %d def", c.label, vs, t.defense))
    if t.isTarget then
        sub:SetTextColor(t.r, t.g, t.b, 1.0)
    else
        local dim = pal.dimTextColor or COLOR_DIM
        sub:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end
end

--- Refresh all combat telemetry in the panel (out of combat only).
function panelModule.UpdateValues()
    if IsInCombat() or not panelFrame or not panelFrame:IsShown() or not panelFrame.scrollChild then return end
    if CharacterFrame and not CharacterFrame:IsShown() then return end

    local c = resolve_context()
    pal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
    scrollChild = panelFrame.scrollChild
    activeRowCount, cursorY = 0, -4

    update_subtitle(c)

    local order = SECTION_ORDER[c.archetype] or SECTION_ORDER.melee
    for i = 1, #order do
        SECTIONS[order[i]](c)
    end

    for i = activeRowCount + 1, #allRows do
        allRows[i]:Hide()
    end

    local totalHeight = math_max(1, -cursorY + 10)
    if scrollChild:GetHeight() ~= totalHeight then
        scrollChild:SetHeight(totalHeight)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Panel & Toggle Button Construction
-- ─────────────────────────────────────────────────────────────────────────────

local function RestorePosition(frame)
    if not frame or IsInCombat() then return end
    frame:ClearAllPoints()
    local pos = SfuiDB and SfuiDB.characterInfoPanelPos
    if pos and pos.point and pos.x and pos.y then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or "BOTTOMLEFT", pos.x, pos.y)
    elseif CharacterFrame then
        frame:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 2, -12)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
end

local function SavePosition(frame)
    if not frame or IsInCombat() then return end
    frame:StopMovingOrSizing()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then return end
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

local function ApplyTheme(frame, palette)
    if not frame then return end
    palette = palette or (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE

    if frame.headerBar and sfui.theme and sfui.theme.ApplyHeaderStyle then
        sfui.theme.ApplyHeaderStyle(frame.headerBar, "combat telemetry")
    end
    if frame.subTitle then
        local dim = palette.dimTextColor or COLOR_DIM
        frame.subTitle:SetTextColor(dim[1], dim[2], dim[3], 1.0)
    end
    if frame.closeBtn and sfui.theme and sfui.theme.ApplyCloseButtonStyle then
        sfui.theme.ApplyCloseButtonStyle(frame.closeBtn)
    end
    if frame.content and sfui.theme and sfui.theme.ApplyContainerStyle then
        sfui.theme.ApplyContainerStyle(frame.content)
    end
    if frame.scrollFrame and frame.scrollFrame.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(frame.scrollFrame.ScrollBar)
    end
    if sfui.theme and sfui.theme.ElevateWindowContents then
        sfui.theme.ElevateWindowContents(frame)
    end
    if frame:IsShown() then
        panelModule.UpdateValues()
    end
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
        if IsInCombat() then return end
        self:StartMoving()
    end)
    panelFrame:SetScript("OnDragStop", SavePosition)
    panelFrame:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)

    -- Header Bar
    local headerBar
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
        if IsInCombat() then return end
        panelFrame:StartMoving()
    end)
    headerBar:SetScript("OnDragStop", function()
        SavePosition(panelFrame)
    end)
    headerBar:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" or not (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) or IsInCombat() then return end
        if SfuiDB then SfuiDB.characterInfoPanelPos = nil end
        RestorePosition(panelFrame)
        if common.print then
            common.print("character telemetry panel position reset to default.")
        end
    end)
    headerBar:SetScript("OnEnter", function(self)
        local tip = common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        tip:ClearLines()
        tip:AddLine("combat telemetry", 1, 1, 1)
        if ctx.archetype then
            tip:AddLine(string_format("layout: %s (%s)", ctx.archetype, ctx.roleKey or "auto"), 0.8, 0.8, 0.8)
            tip:AddLine("sections follow your talents, druid form and gear manager role.", 0.65, 0.65, 0.65, true)
        end
        tip:AddLine("drag to move | shift+right-click to reset position", 0.7, 0.7, 0.7)
        tip:Show()
    end)
    headerBar:SetScript("OnLeave", function()
        if common.hide_tooltip then common.hide_tooltip() end
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

    -- Subtitle (spec / form label + target context, filled on every refresh)
    local subTitle = panelFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panelFrame.subTitle = subTitle
    subTitle:SetPoint("TOP", headerBar, "BOTTOM", 0, -2)
    subTitle:SetWidth(270)
    subTitle:SetWordWrap(false)
    subTitle:SetJustifyH("CENTER")
    local initPal = (sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()) or EMPTY_PALETTE
    local initDim = initPal.dimTextColor or COLOR_DIM
    subTitle:SetTextColor(initDim[1], initDim[2], initDim[3], 1.0)

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
    if sf.ScrollBar and common.style_scrollbar then
        common.style_scrollbar(sf.ScrollBar)
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

    panelFrame:SetScript("OnShow", function(self)
        if IsInCombat() then
            self:Hide()
            return
        end
        RestorePosition(self)
        panelModule.UpdateValues()
        if sfui.theme and sfui.theme.ElevateWindowContents then
            sfui.theme.ElevateWindowContents(self)
        end
    end)

    RestorePosition(panelFrame)
    panelFrame:Hide()
    return panelFrame
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Visibility & Debounced Refresh
-- ─────────────────────────────────────────────────────────────────────────────

local function is_panel_live()
    return panelFrame and panelFrame:IsShown() and (not CharacterFrame or CharacterFrame:IsShown())
end

local function do_refresh()
    if not IsInCombat() and is_panel_live() then
        panelModule.UpdateValues()
    end
end

--- Coalesce bursts of stat / gear / target events into one refresh (hidden panels refresh on show).
local function request_refresh()
    if IsInCombat() or not is_panel_live() then return end
    common.debounce(DEBOUNCE_KEY, DEBOUNCE_DELAY, do_refresh)
end

local function hide_panel()
    if panelFrame and panelFrame:IsShown() then
        panelFrame:Hide()
    end
end

--- Show the panel when the character frame is open and the player left it toggled on.
local function show_if_wanted()
    if IsInCombat() or not (CharacterFrame and CharacterFrame:IsShown()) then return end
    if not (SfuiDB and SfuiDB.showCombatInfoPanel) then return end
    if not panelFrame then panelModule.CreatePanel() end
    if panelFrame:IsShown() then
        RestorePosition(panelFrame)
        panelModule.UpdateValues()
    else
        panelFrame:Show()
    end
end

local function align_header_buttons()
    if sfui.character and sfui.character.AlignHeaderButtons then
        sfui.character.AlignHeaderButtons()
    end
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
        local tip = common.get_tooltip and common.get_tooltip()
        if not tip then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:ClearLines()
        tip:AddLine("combat telemetry", 1, 1, 1)
        if IsInCombat() then
            tip:AddLine("combat telemetry is paused during combat.", 1.0, 0.4, 0.4, true)
        else
            tip:AddLine("click to toggle combat telemetry panel.", 0.8, 0.8, 0.8, true)
            tip:AddLine("drag to move | shift+right-click to reset.", 0.65, 0.65, 0.65, true)
        end
        tip:Show()
    end)
    toggleButton:SetScript("OnLeave", function()
        if common.hide_tooltip then common.hide_tooltip() end
    end)

    toggleButton:SetScript("OnClick", function()
        if IsInCombat() then
            hide_panel()
            if common.print then
                common.print("combat telemetry is unavailable during combat.")
            end
            return
        end
        if not panelFrame then panelModule.CreatePanel() end
        if panelFrame:IsShown() then
            panelFrame:Hide()
            if SfuiDB then SfuiDB.showCombatInfoPanel = false end
        else
            if SfuiDB then SfuiDB.showCombatInfoPanel = true end
            panelFrame:Show()
        end
    end)

    toggleButton:HookScript("OnShow", align_header_buttons)
    toggleButton:HookScript("OnHide", align_header_buttons)

    if sfui.character and sfui.character.AlignHeaderButtons then
        sfui.character.HookHeaderButtons()
        sfui.character.AlignHeaderButtons()
    end

    return toggleButton
end

-- ─────────────────────────────────────────────────────────────────────────────
--  Initialization & Events (routed through sfui.events)
-- ─────────────────────────────────────────────────────────────────────────────

local REFRESH_EVENTS = {
    "PLAYER_TARGET_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
    "SKILL_LINES_CHANGED",
    "CHAT_MSG_SKILL",
    "CHARACTER_POINTS_CHANGED",
    "PLAYER_LEVEL_UP",
    "UPDATE_SHAPESHIFT_FORM",
    "COMBAT_RATING_UPDATE",
    "SPELL_POWER_CHANGED",
    "PLAYER_DAMAGE_DONE_MODS",
}

local REFRESH_UNIT_EVENTS = {
    "UNIT_STATS",
    "UNIT_INVENTORY_CHANGED",
    "UNIT_RESISTANCES",
    "UNIT_ATTACK_POWER",
    "UNIT_RANGED_ATTACK_POWER",
    "UNIT_DEFENSE",
    "UNIT_DISPLAYPOWER",
}

local function on_combat_start()
    inCombat = true
    hide_panel()
end

local function on_combat_end()
    inCombat = false
    show_if_wanted()
end

local function initialize()
    CharacterFrame = CharacterFrame or _G.CharacterFrame
    if panelModule.initialized or not CharacterFrame then return end
    panelModule.initialized = true

    panelModule.CreatePanel()
    panelModule.CreateToggleButton()

    hooksecurefunc(CharacterFrame, "Show", function()
        align_header_buttons()
        if IsInCombat() then
            hide_panel()
            return
        end
        show_if_wanted()
    end)
    hooksecurefunc(CharacterFrame, "Hide", hide_panel)

    local events = sfui.events
    events.RegisterEvent("PLAYER_REGEN_DISABLED", on_combat_start)
    events.RegisterEvent("PLAYER_REGEN_ENABLED", on_combat_end)
    for i = 1, #REFRESH_EVENTS do
        events.RegisterEvent(REFRESH_EVENTS[i], request_refresh)
    end
    events.RegisterUnitEvents(REFRESH_UNIT_EVENTS, "player", request_refresh)
    events.RegisterMessage("SFUI_SPEC_CHANGED", request_refresh)

    show_if_wanted()
end

sfui.events.RegisterEvent("PLAYER_LOGIN", initialize)
