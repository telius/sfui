local _G = _G
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}
sfui.buffs.providers = {}

local P = sfui.buffs.providers

local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local string_format = string.format
local tostring = _G.tostring
local GetTime = _G.GetTime
local InCombatLockdown = _G.InCombatLockdown

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
P.QUESTION_MARK_ICON = QUESTION_MARK_ICON
local issecretvalue = sfui.common.issecretvalue

local function IsValidTexture(tex)
    if issecretvalue and issecretvalue(tex) then return true end
    return tex ~= nil and tex ~= 0 and tex ~= ""
end
P.IsValidTexture = IsValidTexture

local providersById = {}

-- ─────────────────────────────────────────────────────────────
--  SHARED FORMATTING & VISUAL / ACTION DEFAULTS
-- ─────────────────────────────────────────────────────────────
local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 3600 then
        return string_format("%dh", math_floor(seconds / 3600))
    elseif seconds >= 60 then
        return string_format("%dm", math_ceil(seconds / 60))
    else
        return string_format("%ds", math_max(1, math_floor(seconds)))
    end
end
P.FormatTime = FormatTime

local function DefaultCountText(rec)
    if rec and rec.charges and rec.charges > 1 then
        return tostring(rec.charges)
    end
    return ""
end
P.DefaultCountText = DefaultCountText

function P.DefaultResolveVisual(rec)
    local icon = rec and rec.icon
    local tex = (IsValidTexture(icon) and icon) or QUESTION_MARK_ICON
    return tex, DefaultCountText(rec)
end

function P.ResolveDefaultSpellAction(rec)
    local entry = rec and rec.entry
    if not entry then return nil end

    local buffsData = sfui.buffs.data
    local castSpell, _, castSpellID
    if buffsData and buffsData.GetBestCastSpell then
        castSpell, _, castSpellID = buffsData.GetBestCastSpell(entry, rec.activeEnchant)
    end

    local targetSlot = (entry.type == "weapon_enchant") and (entry.slot or 16) or nil
    local targetUnit = (not targetSlot and entry.type ~= "pet") and (entry.unit or rec.unit or "player") or nil
    local spellToCast = (entry.type == "pet" and castSpellID) or castSpell or castSpellID
    if spellToCast then
        return "spell", spellToCast, targetSlot, targetUnit
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────
--  SHARED TOOLTIP & SCROLL HELPERS
-- ─────────────────────────────────────────────────────────────
function P.AddStatusHeader(tip, rec, labelOverride)
    local entry = rec and rec.entry
    local label = labelOverride or (entry and entry.name) or "buff"
    if rec.isMissing then
        tip:AddLine("|cffff4444[missing]|r " .. label, 1, 1, 1)
    elseif rec.isExpiring then
        tip:AddLine("|cffffcc00[expiring]|r " .. label, 1, 1, 1)
    else
        tip:AddLine("|cff00ff00[active]|r " .. label, 1, 1, 1)
    end

    if rec.expirationTime and rec.expirationTime > 0 then
        local rem = rec.expirationTime - GetTime()
        if rem > 0 then
            tip:AddLine(string_format("remaining: |cffffd100%s|r", FormatTime(rem)), 0.8, 0.8, 0.8)
        end
    end

    if rec.charges and rec.charges > 0 then
        tip:AddLine(string_format("charges: |cffffffff%d|r", rec.charges), 0.8, 0.8, 0.8)
    end
end

function P.AddClickPrompt(tip, verb, targetLabel, isTestMode)
    local db = SfuiDB and SfuiDB.buffReminders
    if not db or db.clickToCast == false or isTestMode then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        tip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
    elseif targetLabel and targetLabel ~= "" then
        tip:AddLine("|cff55ff55[click to " .. verb .. "]|r " .. targetLabel, 0.3, 1, 0.3)
    end
end

function P.AddSpellChoiceList(tip, prompt, choices, matchField, matchVal)
    if not choices or #choices <= 1 then return end
    tip:AddLine(" ")
    tip:AddLine(prompt, 0.5, 0.8, 1)
    for i = 1, #choices do
        local cInfo = choices[i]
        local label = cInfo.displayName or (cInfo.spellName and cInfo.spellName:lower()) or ""
        if matchVal ~= nil and cInfo[matchField] == matchVal then
            tip:AddLine("  > " .. label, 1, 0.82, 0)
        else
            tip:AddLine("    " .. label, 0.6, 0.6, 0.6)
        end
    end
end

function P.AddItemChoiceList(tip, prompt, items, selectedItem)
    if not items or #items <= 1 or not selectedItem then return end
    tip:AddLine(" ")
    tip:AddLine(prompt, 0.5, 0.8, 1)
    for i = 1, #items do
        local info = items[i]
        local isCur = (info.itemID and info.itemID == selectedItem.itemID)
            or (not info.itemID and info.name == selectedItem.name)
        local line = (info.name or ""):lower() .. string_format(" (%d)", info.count or 0)
        if isCur then
            tip:AddLine("  > " .. line, 1, 0.82, 0)
        else
            tip:AddLine("    " .. line, 0.6, 0.6, 0.6)
        end
    end
end

function P.NotifyCycled(btn, needsScanOnLeave)
    if btn and needsScanOnLeave then
        btn._needsScanOnLeave = true
    end
    if btn and btn.isHovered then
        local onEnter = btn:GetScript("OnEnter")
        if onEnter then
            onEnter(btn)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  PROVIDER REGISTRY & O(1) ENTRY RESOLUTION
-- ─────────────────────────────────────────────────────────────
function P.Register(id, def)
    if not id or not def then return end
    def.id = id
    if not def.resolveVisual then
        def.resolveVisual = P.DefaultResolveVisual
    end
    if not def.resolveAction then
        def.resolveAction = P.ResolveDefaultSpellAction
    end
    providersById[id] = def
end

function P.Get(id)
    return providersById[id]
end

local function ResolveProviderId(entry)
    if not entry then return "aura" end
    local cached = entry._providerId
    if cached then return cached end

    local key = entry.key
    local eType = entry.type
    local pClass = sfui.buffs and sfui.buffs.playerClass
    local id

    if key == "consumable_food" then
        id = "consumable_food"
    elseif key == "consumable_flask" then
        id = "consumable_flask"
    elseif key == "consumable_weapon_mh" or key == "consumable_weapon_oh" or key == "poison_mh" or key == "poison_oh" then
        id = "consumable_oil"
    elseif entry.isFishingLure then
        id = "fishing_lure"
    elseif pClass == "SHAMAN" and (key == "weapon_mh" or key == "weapon_oh") then
        id = "shaman_imbue"
    elseif pClass == "PALADIN" and key == "aura" then
        id = "paladin_aura"
    elseif pClass == "PALADIN" and key == "blessing" then
        id = "paladin_blessing"
    elseif eType == "party_blessing" then
        id = "party_blessing"
    elseif eType == "pet" then
        id = "pet"
    elseif eType == "stance" then
        id = "stance"
    elseif eType == "tracking" then
        id = "tracking"
    elseif eType == "weapon_enchant" then
        id = "weapon_enchant"
    else
        id = "aura"
    end

    if pClass then
        entry._providerId = id
    end
    return id
end
P.ResolveId = ResolveProviderId

function P.Resolve(entry)
    local id = ResolveProviderId(entry)
    return providersById[id] or providersById.aura
end

