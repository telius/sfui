--[[
    sfui/frames/bars/totembar.lua
    shaman totem bar with scroll selection and in-combat right-click destroy.
    architected following smarttotem principles for classic / camelot.
]]

local _, _ = ...
sfui = sfui or {}
sfui.totembar = sfui.totembar or {}

-- Shamans on Classic / Camelot only
if sfui.isRetail then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "SHAMAN" then return end

-- ---------------------------------------------------------------------------
-- Upvalues & Localization
-- ---------------------------------------------------------------------------
local CreateFrame         = _G.CreateFrame
local UIParent            = _G.UIParent
local GameTooltip         = _G.GameTooltip
local InCombatLockdown    = _G.InCombatLockdown
local GetTotemInfo        = _G.GetTotemInfo
local GetTime             = _G.GetTime
local issecretvalue       = _G.issecretvalue
local pcall, type         = _G.pcall, _G.type
local tonumber            = _G.tonumber
local ipairs, pairs, wipe = _G.ipairs, _G.pairs, _G.wipe
local math_floor          = math.floor
local string_format       = string.format
local C_Spell             = _G.C_Spell
local C_SpellBook         = _G.C_SpellBook
local IsPlayerSpell       = _G.IsPlayerSpell
local IsSpellKnown        = _G.IsSpellKnown
local GetSpellBookItemName = _G.GetSpellBookItemName
local BOOKTYPE_SPELL      = _G.BOOKTYPE_SPELL
local Enum                = _G.Enum
local GetBindingKey       = _G.GetBindingKey
local SetBinding          = _G.SetBinding
local SaveBindings        = _G.SaveBindings
local GetCurrentBindingSet = _G.GetCurrentBindingSet
local C_KeyBindings       = _G.C_KeyBindings
local tostring            = _G.tostring
local table_insert        = table.insert
local table_concat        = table.concat

local ACTION_SEQUENCE     = "CLICK SfuiTotemSequenceBtn:LeftButton"

-- ---------------------------------------------------------------------------
-- Constants & Static Totem Database
-- ---------------------------------------------------------------------------
local ELEMENTS = { "Earth", "Fire", "Water", "Air" }

-- Blizzard slot indices: Fire = 1, Earth = 2, Water = 3, Air = 4
local ELEMENT_SLOT = {
    Fire  = 1,
    Earth = 2,
    Water = 3,
    Air   = 4,
}

local SLOT_TO_ELEMENT = {
    [1] = "Fire",
    [2] = "Earth",
    [3] = "Water",
    [4] = "Air",
}

local ELEMENT_COLORS = {
    Earth = { 0.85, 0.55, 0.20 },
    Fire  = { 1.00, 0.25, 0.10 },
    Water = { 0.10, 0.60, 1.00 },
    Air   = { 0.75, 0.90, 1.00 },
}

local DEFAULT_TOTEMS = {
    Earth = "Stoneskin Totem",
    Fire  = "Searing Totem",
    Water = "Healing Stream Totem",
    Air   = "Windfury Totem",
}

local TOTEM_LIST = {
    Earth = {
        "Strength of Earth Totem",
        "Stoneskin Totem",
        "Tremor Totem",
        "Earthbind Totem",
        "Stoneclaw Totem",
        "Earth Elemental Totem",
    },
    Fire = {
        "Searing Totem",
        "Magma Totem",
        "Fire Nova Totem",
        "Flametongue Totem",
        "Frost Resistance Totem",
        "Totem of Wrath",
        "Fire Elemental Totem",
    },
    Water = {
        "Healing Stream Totem",
        "Mana Spring Totem",
        "Poison Cleansing Totem",
        "Disease Cleansing Totem",
        "Fire Resistance Totem",
        "Mana Tide Totem",
    },
    Air = {
        "Windfury Totem",
        "Grace of Air Totem",
        "Wrath of Air Totem",
        "Grounding Totem",
        "Nature Resistance Totem",
        "Windwall Totem",
        "Tranquil Air Totem",
        "Sentry Totem",
    },
}

local TOTEM_ELEMENT = {}
for element, list in pairs(TOTEM_LIST) do
    for _, name in ipairs(list) do
        TOTEM_ELEMENT[name] = element
    end
end

local TOTEM_DURATIONS = {
    ["Strength of Earth Totem"] = 120,
    ["Stoneskin Totem"]         = 120,
    ["Tremor Totem"]            = 120,
    ["Earthbind Totem"]         = 45,
    ["Stoneclaw Totem"]         = 15,
    ["Earth Elemental Totem"]   = 120,

    ["Searing Totem"]           = 55,
    ["Magma Totem"]             = 20,
    ["Fire Nova Totem"]         = 5,
    ["Flametongue Totem"]       = 120,
    ["Frost Resistance Totem"]  = 120,
    ["Totem of Wrath"]          = 120,
    ["Fire Elemental Totem"]    = 120,

    ["Healing Stream Totem"]    = 120,
    ["Mana Spring Totem"]       = 120,
    ["Poison Cleansing Totem"]  = 120,
    ["Disease Cleansing Totem"] = 120,
    ["Fire Resistance Totem"]   = 120,
    ["Mana Tide Totem"]         = 12,

    ["Windfury Totem"]          = 120,
    ["Grace of Air Totem"]      = 120,
    ["Wrath of Air Totem"]      = 120,
    ["Grounding Totem"]         = 45,
    ["Nature Resistance Totem"] = 120,
    ["Windwall Totem"]          = 120,
    ["Tranquil Air Totem"]      = 120,
    ["Sentry Totem"]            = 300,
}

local ICON_FILES = {
    ["Windfury Totem"]          = "Spell_Nature_Windfury",
    ["Grace of Air Totem"]      = "Spell_Nature_InvisibilityTotem",
    ["Wrath of Air Totem"]      = "Spell_Nature_SlowingTotem",
    ["Grounding Totem"]         = "Spell_Nature_GroundingTotem",
    ["Tranquil Air Totem"]      = "Spell_Nature_Brilliance",
    ["Windwall Totem"]          = "Spell_Nature_EarthBind",
    ["Nature Resistance Totem"] = "Spell_Nature_NatureResistanceTotem",
    ["Sentry Totem"]            = "Spell_Nature_RemoveCurse",
    ["Strength of Earth Totem"] = "Spell_Nature_EarthBindTotem",
    ["Stoneskin Totem"]         = "Spell_Nature_StoneSkin",
    ["Stoneclaw Totem"]         = "Spell_Nature_StoneClawTotem",
    ["Earthbind Totem"]         = "Spell_Nature_StrengthOfEarth",
    ["Tremor Totem"]            = "Spell_Nature_TremorTotem",
    ["Earth Elemental Totem"]   = "Spell_Nature_EarthElemental_Totem",
    ["Searing Totem"]           = "Spell_Fire_SearingTotem",
    ["Magma Totem"]             = "Spell_Fire_SelfDestruct",
    ["Fire Nova Totem"]         = "Spell_Fire_SealOfFire",
    ["Flametongue Totem"]       = "Spell_Nature_GuardianWard",
    ["Frost Resistance Totem"]  = "Spell_FrostResistanceTotem_01",
    ["Totem of Wrath"]          = "Spell_Fire_TotemOfWrath",
    ["Fire Elemental Totem"]    = "Spell_Fire_Elemental_Totem",
    ["Healing Stream Totem"]    = "INV_Spear_04",
    ["Mana Spring Totem"]       = "Spell_Nature_ManaRegenTotem",
    ["Mana Tide Totem"]         = "Spell_Frost_SummonWaterElemental",
    ["Poison Cleansing Totem"]  = "Spell_Nature_PoisonCleansingTotem",
    ["Disease Cleansing Totem"] = "Spell_Nature_DiseaseCleansingTotem",
    ["Fire Resistance Totem"]   = "Spell_FireResistanceTotem_01",
    ["Totemic Call"]            = "Spell_Shaman_TotemRecall",
}

-- SmartTotem static icon IDs (numeric spell IDs that resolve directly in CASC)
local TOTEM_SPELL_IDS = {
    ["Windfury Totem"]          = 8512,
    ["Grace of Air Totem"]      = 8835,
    ["Wrath of Air Totem"]      = 3738,
    ["Grounding Totem"]         = 8177,
    ["Tranquil Air Totem"]      = 25908,
    ["Windwall Totem"]          = 15107,
    ["Nature Resistance Totem"] = 10595,
    ["Sentry Totem"]            = 6495,
    ["Strength of Earth Totem"] = 8075,
    ["Stoneskin Totem"]         = 8071,
    ["Stoneclaw Totem"]         = 5730,
    ["Earthbind Totem"]         = 2484,
    ["Tremor Totem"]            = 8143,
    ["Earth Elemental Totem"]   = 2062,
    ["Searing Totem"]           = 3599,
    ["Magma Totem"]             = 8190,
    ["Fire Nova Totem"]         = 1535,
    ["Flametongue Totem"]       = 8227,
    ["Frost Resistance Totem"]  = 8181,
    ["Totem of Wrath"]          = 30706,
    ["Fire Elemental Totem"]    = 2894,
    ["Healing Stream Totem"]    = 5394,
    ["Mana Spring Totem"]       = 5675,
    ["Mana Tide Totem"]         = 16190,
    ["Poison Cleansing Totem"]  = 8166,
    ["Disease Cleansing Totem"] = 8170,
    ["Fire Resistance Totem"]   = 8184,
    ["Totemic Call"]            = 36936,
}

local REST_ALPHA = 0.72

-- ---------------------------------------------------------------------------
-- Helper: Format Time
-- ---------------------------------------------------------------------------
local function FormatTime(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return "" end
    seconds = math_floor(seconds + 0.5)
    local minutes = math_floor(seconds / 60)
    local secs = seconds % 60
    if minutes > 0 then
        return string_format("%d:%02d", minutes, secs)
    else
        return string_format("%d", secs)
    end
end

-- ---------------------------------------------------------------------------
-- Helper: Font Path Resolver
-- ---------------------------------------------------------------------------
local function GetFontPath()
    local f = sfui.config and (sfui.config.fontFile or sfui.config.font_path)
    if f and f ~= "" and f ~= "GameFontNormal" then
        return f
    end
    if _G.GameFontNormal and _G.GameFontNormal.GetFont then
        local ok, blizzFont = pcall(_G.GameFontNormal.GetFont, _G.GameFontNormal)
        if ok and blizzFont and blizzFont ~= "" and blizzFont ~= "GameFontNormal" then
            return blizzFont
        end
    end
    return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- ---------------------------------------------------------------------------
-- Helper: SmartTotem-Style Infallible Totem Icon Resolver
-- Queries spell ID / client texture database first, falls back to loose icon
-- ---------------------------------------------------------------------------
local iconCache = {}

local function IsUsableTotemIcon(value)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value) == "number" then return value > 0 and value ~= 134400 end
    if type(value) == "string" then
        return value ~= "" and not value:lower():find("inv_misc_questionmark", 1, true)
    end
    return false
end

local function GetIconForTotem(totemName)
    if not totemName or totemName == "" then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    if iconCache[totemName] then
        return iconCache[totemName]
    end

    local getTexture = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture
    if getTexture then
        for _, query in ipairs({ TOTEM_SPELL_IDS[totemName] or totemName, totemName }) do
            local ok, texture = pcall(getTexture, query)
            if ok and IsUsableTotemIcon(texture) then
                iconCache[totemName] = texture
                return texture
            end
        end
    end

    local file = ICON_FILES[totemName]
    local fallback = file and ("Interface\\Icons\\" .. file) or "Interface\\Icons\\INV_Misc_QuestionMark"
    iconCache[totemName] = fallback
    return fallback
end

-- ---------------------------------------------------------------------------
-- Helper: Learned-Spell Scanner (SmartTotem Compat.PlayerHasSpell pattern)
-- Strictly verifies the player has actually learned this totem
-- ---------------------------------------------------------------------------
local knownSpellsCache = {}

local function StripRank(name)
    if not name then return "" end
    return (name:gsub("%s*%(Rank %d+%)", ""):gsub("%s*%(.*%)", ""))
end

local function RefreshSpellBookCache()
    wipe(knownSpellsCache)

    -- 1. Modern / Camelot C_SpellBook slot inspection
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1
        for slot = 1, 300 do
            local ok, name = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
            if ok and name and name ~= "" then
                knownSpellsCache[name] = true
                knownSpellsCache[StripRank(name)] = true
            end
            if C_SpellBook.GetSpellBookItemType then
                local tOk, _, _, spellID = pcall(C_SpellBook.GetSpellBookItemType, slot, bank)
                if tOk and spellID and spellID > 0 then
                    knownSpellsCache[spellID] = true
                end
            end
        end
    end

    -- 2. Classic GetSpellBookItemName inspection
    if GetSpellBookItemName then
        local bookType = BOOKTYPE_SPELL or "spell"
        for slot = 1, 300 do
            local ok, name, _, spellID = pcall(GetSpellBookItemName, slot, bookType)
            if ok and name and name ~= "" then
                knownSpellsCache[name] = true
                knownSpellsCache[StripRank(name)] = true
            end
            if ok and spellID and spellID > 0 then
                knownSpellsCache[spellID] = true
            end
        end
    end
end

local function IsTotemKnown(totemName)
    if not totemName or totemName == "" then return false end

    -- Check cached spellbook entries
    if knownSpellsCache[totemName] or knownSpellsCache[StripRank(totemName)] then
        return true
    end

    -- Check learned spell ID APIs (classic client)
    local id = TOTEM_SPELL_IDS[totemName]
    if id then
        if knownSpellsCache[id] then
            return true
        end

        local getSpellName = (C_Spell and C_Spell.GetSpellName) or _G.GetSpellInfo
        if getSpellName then
            local ok, locName = pcall(getSpellName, id)
            if ok and locName and (knownSpellsCache[locName] or knownSpellsCache[StripRank(locName)]) then
                return true
            end
        end

        if C_SpellBook and C_SpellBook.IsSpellKnown then
            local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
            if ok and known then return true end
        end
        if IsPlayerSpell then
            local ok, known = pcall(IsPlayerSpell, id)
            if ok and known then return true end
        end
        if IsSpellKnown then
            local ok, known = pcall(IsSpellKnown, id)
            if ok and known then return true end
        end
    end

    return false
end

local function GetKnownTotems(element)
    local fullList = TOTEM_LIST[element] or {}
    local knownList = {}
    for _, name in ipairs(fullList) do
        if IsTotemKnown(name) then
            knownList[#knownList + 1] = name
        end
    end
    return knownList
end

local function GetDefaultTotemForElement(element)
    local selected = SfuiDB and SfuiDB.totembar and SfuiDB.totembar.selectedTotems and SfuiDB.totembar.selectedTotems[element]
    if selected and IsTotemKnown(selected) then
        return selected, true
    end
    local known = GetKnownTotems(element)
    if known and #known > 0 then
        return known[1], true
    end
    return DEFAULT_TOTEMS[element], false
end

-- ---------------------------------------------------------------------------
-- Helper: Secret-Value-Safe Totem Reader
-- Returns:
--   true, name, startTime, duration, icon (totem active and readable)
--   false                                 (slot empty and readable)
--   nil                                   (secret / unreadable in combat)
-- ---------------------------------------------------------------------------
local function SafeTotemInfo(slot)
    if not GetTotemInfo then return false end
    local ok, haveTotem, name, startTime, duration, icon = pcall(GetTotemInfo, slot)
    if not ok then return nil end

    if issecretvalue and (issecretvalue(haveTotem) or issecretvalue(name) or issecretvalue(startTime)) then
        return nil
    end

    local checkOk, isPresent = pcall(function()
        if haveTotem and name and name ~= "" then
            return true
        end
        return false
    end)
    if not checkOk then return nil end

    if isPresent then
        local mathOk = pcall(function() return (startTime or 0) + (duration or 0) end)
        if not mathOk then startTime, duration = nil, nil end
        return true, name, startTime, duration, icon
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Border & Button Skinning Helpers (SFUI Icon Styling)
-- ---------------------------------------------------------------------------
local function AddBorder(frame, r, g, b, a, subLevel)
    local mult = sfui.pixelScale or 1
    local thickness = math.max(1, math.floor(1 * mult + 0.5))
    local sub = subLevel or 6

    local r_val, g_val, b_val, a_val = 1, 1, 1, 1
    if type(r) == "table" then
        r_val = r[1] or r.r or 1
        g_val = r[2] or r.g or 1
        b_val = r[3] or r.b or 1
        a_val = r[4] or r.a or (type(g) == "number" and g) or 1
    elseif type(r) == "number" then
        r_val = r
        g_val = g or 1
        b_val = b or 1
        a_val = a or 1
    end

    local top = frame:CreateTexture(nil, "OVERLAY", nil, sub)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(thickness)

    local bottom = frame:CreateTexture(nil, "OVERLAY", nil, sub)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(thickness)

    local left = frame:CreateTexture(nil, "OVERLAY", nil, sub)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(thickness)

    local right = frame:CreateTexture(nil, "OVERLAY", nil, sub)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(thickness)

    local parts = { top, bottom, left, right }
    for _, p in ipairs(parts) do
        p:SetTexture("Interface\\Buttons\\WHITE8x8")
        p:SetVertexColor(r_val, g_val, b_val, a_val)
    end
    return parts
end

local function SkinTotemButton(btn, iconTex, r, g, b)
    -- Dark solid backdrop underneath icon
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.06, 1)
    btn.bg = bg

    -- Icon texture with standard SFUI square crop (0.08, 0.92) & 1px inset
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if iconTex then
        icon:SetTexture(iconTex)
    end
    btn.icon = icon

    -- 1px pixel-perfect colored border (OVERLAY, 6)
    btn.border = AddBorder(btn, r or 1, g or 1, b or 1, 0.85, 6)

    -- Highlight texture (ADD blend, ButtonHilight-Square)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(icon)
    hl:SetBlendMode("ADD")
    btn:SetHighlightTexture(hl)

    -- Pushed texture (UI-Quickslot-Depress)
    local pushed = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    pushed:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    pushed:SetAllPoints(icon)
    btn:SetPushedTexture(pushed)

    return icon
end


-- ---------------------------------------------------------------------------
-- Module State
-- ---------------------------------------------------------------------------
local bar
local dragOverlay
local seqBtn
local buttons = {}      -- element -> { frame, icon, cooldown, overlay, timerText, border, activeBorder, selectedTotem }
local activeState = {}  -- element -> { name, startTime, duration }
local activeTotemCount = 0
local statePool = {}
local deferredArm = {}  -- element -> totemName (deferred if scrolled in combat)
local deferredSeqUpdate = false
local deferredSettingsUpdate = false

local isUnlocked = false
local inCombat = false

-- ---------------------------------------------------------------------------
-- Active Color Resolver (Spec Color)
-- ---------------------------------------------------------------------------
local function GetActiveTotemColor()
    if sfui.common and sfui.common.get_spec_color then
        local r, g, b = sfui.common.get_spec_color()
        if r and g and b then
            return r, g, b
        end
    end
    if sfui.common and sfui.common.get_class_or_spec_color then
        local c = sfui.common.get_class_or_spec_color()
        if c then
            return c[1] or c.r or 0.0, c[2] or c.g or 0.8, c[3] or c.b or 1.0
        end
    end
    return 0.0, 0.8, 1.0
end

-- ---------------------------------------------------------------------------
-- Config & Timer Helpers
-- ---------------------------------------------------------------------------
local function ShouldColorByElement()
    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.colorByElement ~= nil then
        return SfuiDB.totembar.colorByElement ~= false
    end
    if sfui.config and sfui.config.totembar and sfui.config.totembar.colorByElement ~= nil then
        return sfui.config.totembar.colorByElement ~= false
    end
    return true
end

local function UpdateButtonBorderAlpha(btn, isKnown)
    if btn and btn.border then
        local a = isKnown and 0.9 or 0.28
        if not ShouldColorByElement() and isKnown then
            a = 1.0
        end
        for _, p in ipairs(btn.border) do p:SetAlpha(a) end
    end
end

local function ShouldShowTimerText()
    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showTimerText ~= nil then
        return SfuiDB.totembar.showTimerText ~= false
    end
    if sfui.config and sfui.config.totembar and sfui.config.totembar.showTimerText ~= nil then
        return sfui.config.totembar.showTimerText ~= false
    end
    return true
end

local function ShouldShowGlow()
    if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.showGlow ~= nil then
        return SfuiDB.totembar.showGlow ~= false
    end
    if sfui.config and sfui.config.totembar and sfui.config.totembar.showGlow ~= nil then
        return sfui.config.totembar.showGlow ~= false
    end
    return true
end

local function SanitizeTimeAndDuration(name, startTime, duration, existingState)
    local dur
    if type(duration) == "number" and duration > 0 then
        dur = duration
    elseif existingState and existingState.duration and existingState.duration > 0 then
        dur = existingState.duration
    else
        dur = TOTEM_DURATIONS[name] or 120
    end

    local st
    local now = GetTime()
    if type(startTime) == "number" and startTime > 0 and (now - startTime) <= dur and (startTime - now) <= 1.0 then
        st = startTime
    elseif existingState and existingState.startTime and existingState.startTime > 0 and (now - existingState.startTime) <= dur then
        st = existingState.startTime
    else
        st = now
    end

    return st, dur
end

local function GetElementTimeLeft(element, state, now)
    local slot = ELEMENT_SLOT[element]
    local fnTimeLeft = _G.GetTotemTimeLeft
    if slot and fnTimeLeft then
        local ok, tl = pcall(fnTimeLeft, slot)
        if ok and tl and not (issecretvalue and issecretvalue(tl)) then
            local num = tonumber(tl)
            if num and num > 0 then
                return num
            end
        end
    end
    if state and state.duration and state.startTime then
        return state.duration - (now - state.startTime)
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Glow Helper (sfui.glows Integration)
-- ---------------------------------------------------------------------------
local function StartActiveGlow(btn)
    if not btn or not btn.frame then return end
    if not ShouldShowGlow() then return end
    if sfui.glows and sfui.glows.start_glow then
        local gr, gg, gb
        local elem = btn.element
        if not elem then
            for e, b in pairs(buttons) do
                if b == btn or b.frame == btn.frame then
                    elem = e
                    break
                end
            end
        end
        if ShouldColorByElement() and elem and ELEMENT_COLORS[elem] then
            gr, gg, gb = unpack(ELEMENT_COLORS[elem])
        else
            gr, gg, gb = GetActiveTotemColor()
        end
        local gType = "pixel"
        local gScale = 1.0
        local gSpeed = 0.25
        local gLines = 8
        local gThick = 2
        local cfg = (SfuiDB and SfuiDB.totembar) or (sfui.config and sfui.config.totembar)
        if cfg then
            if cfg.glowType then gType = cfg.glowType end
            if cfg.glowScale then gScale = cfg.glowScale end
            if cfg.glowSpeed then gSpeed = cfg.glowSpeed end
            if cfg.glowLines then gLines = cfg.glowLines end
            if cfg.glowThickness then gThick = cfg.glowThickness end
        end

        sfui.glows.start_glow(btn.frame, {
            glowType      = gType,
            glowColor     = { gr, gg, gb, 1.0 },
            glowLines     = gLines,
            glowThickness = gThick,
            glowSpeed     = gSpeed,
            glowScale     = gScale,
        })
    end
end

local function StopActiveGlow(btn)
    if not btn or not btn.frame then return end
    if sfui.glows and sfui.glows.stop_glow then
        sfui.glows.stop_glow(btn.frame)
    end
end

local function UpdateActiveColors()
    local colorByElement = ShouldColorByElement()
    local sr, sg, sb = GetActiveTotemColor()
    for _, element in ipairs(ELEMENTS) do
        local btn = buttons[element]
        if btn then
            local ar, ag, ab = sr, sg, sb
            if colorByElement and ELEMENT_COLORS[element] then
                ar, ag, ab = unpack(ELEMENT_COLORS[element])
            end
            if btn.activeBorder then
                for _, p in ipairs(btn.activeBorder) do
                    p:SetVertexColor(ar, ag, ab, 1)
                end
            end
            if activeState[element] then
                if ShouldShowGlow() then
                    StartActiveGlow(btn)
                else
                    StopActiveGlow(btn)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Core Functions: Set Active / Inactive
-- ---------------------------------------------------------------------------
local function SetActive(element, name, startTime, duration)
    local btn = buttons[element]
    if not btn then return end

    local existing = activeState[element]
    local st, dur = SanitizeTimeAndDuration(name, startTime, duration, existing)

    local state = existing or table.remove(statePool) or {}
    state.name      = name
    state.startTime = st
    state.duration  = dur

    if not existing then
        activeTotemCount = activeTotemCount + 1
    end
    activeState[element] = state

    local tex = GetIconForTotem(name)
    btn.icon:SetTexture(tex)
    btn.icon:SetAlpha(1.0)

    if btn.cooldown then
        btn.cooldown:Clear()
        if st and dur and dur > 0 then
            btn.cooldown:SetCooldown(st, dur)
            btn.cooldown:Show()
        else
            btn.cooldown:Hide()
        end
    end

    if btn.timerText then
        if ShouldShowTimerText() then
            local rem = dur - (GetTime() - st)
            if rem > 0 then
                local formatted = FormatTime(rem)
                btn._lastTimerStr = formatted
                btn.timerText:SetText(formatted)
                btn.timerText:Show()
            else
                btn._lastTimerStr = nil
                btn.timerText:SetText("")
                btn.timerText:Hide()
            end
        else
            btn._lastTimerStr = nil
            btn.timerText:SetText("")
            btn.timerText:Hide()
        end
    end

    if btn.activeBorder then
        local ar, ag, ab
        if ShouldColorByElement() and ELEMENT_COLORS[element] then
            ar, ag, ab = unpack(ELEMENT_COLORS[element])
        else
            ar, ag, ab = GetActiveTotemColor()
        end
        for _, p in ipairs(btn.activeBorder) do
            p:SetVertexColor(ar, ag, ab, 1)
            p:SetAlpha(1)
        end
    end
    UpdateButtonBorderAlpha(btn, true)
    StartActiveGlow(btn)
end

local function SetInactive(element)
    local btn = buttons[element]
    if not btn then return end

    local existing = activeState[element]
    if existing then
        activeState[element] = nil
        activeTotemCount = math.max(0, activeTotemCount - 1)
        wipe(existing)
        statePool[#statePool + 1] = existing
    end

    StopActiveGlow(btn)

    if btn.cooldown then
        btn.cooldown:Clear()
        btn.cooldown:Hide()
    end

    if btn.timerText then
        btn._lastTimerStr = nil
        btn.timerText:SetText("")
        btn.timerText:Hide()
    end

    local selected, isKnown = GetDefaultTotemForElement(element)
    btn.icon:SetTexture(GetIconForTotem(selected))
    btn.icon:SetAlpha(isKnown and REST_ALPHA or 0.28)

    if btn.activeBorder then
        for _, p in ipairs(btn.activeBorder) do p:SetAlpha(0) end
    end
    UpdateButtonBorderAlpha(btn, isKnown)
end

-- ---------------------------------------------------------------------------
-- Arm Main Button (Out of Combat only)
-- ---------------------------------------------------------------------------
local function ArmMainButton(element, totemName)
    local btn = buttons[element]
    if not btn or not btn.frame then return end

    if InCombatLockdown and InCombatLockdown() then
        deferredArm[element] = totemName
        return
    end

    local fallbackTotem, isKnown = GetDefaultTotemForElement(element)
    totemName = totemName or fallbackTotem
    isKnown = IsTotemKnown(totemName) or isKnown

    btn.selectedTotem = totemName

    SfuiDB = SfuiDB or {}
    SfuiDB.totembar = SfuiDB.totembar or {}
    SfuiDB.totembar.selectedTotems = SfuiDB.totembar.selectedTotems or {}
    if isKnown then
        SfuiDB.totembar.selectedTotems[element] = totemName
    end

    if isKnown then
        btn.frame:SetAttribute("type", "spell")
        btn.frame:SetAttribute("type1", "spell")
        btn.frame:SetAttribute("spell", totemName)
        btn.frame:SetAttribute("spell1", totemName)
    else
        btn.frame:SetAttribute("type", nil)
        btn.frame:SetAttribute("type1", nil)
        btn.frame:SetAttribute("spell", nil)
        btn.frame:SetAttribute("spell1", nil)
    end
    btn.frame:SetAttribute("type2", "destroytotem")
    btn.frame:SetAttribute("totem-slot", ELEMENT_SLOT[element])

    if not activeState[element] then
        btn.icon:SetTexture(GetIconForTotem(totemName))
        btn.icon:SetAlpha(isKnown and REST_ALPHA or 0.28)
        UpdateButtonBorderAlpha(btn, isKnown)
    end
end

-- ---------------------------------------------------------------------------
-- Cast Sequence Generator & Updater
-- ---------------------------------------------------------------------------
local function GetSequenceSpells()
    local spells = {}
    local order = { "Earth", "Fire", "Water", "Air" }
    local cfg = (SfuiDB and SfuiDB.totembar) or (sfui.config and sfui.config.totembar) or {}
    if cfg.castOrder and type(cfg.castOrder) == "table" and #cfg.castOrder > 0 then
        order = cfg.castOrder
    end

    for _, element in ipairs(order) do
        local chosen, isKnown = GetDefaultTotemForElement(element)
        local btn = buttons[element]
        if btn and btn.selectedTotem then
            chosen = btn.selectedTotem
            isKnown = IsTotemKnown(chosen)
        end
        if chosen and isKnown then
            table_insert(spells, chosen)
        end
    end
    return spells
end

local function GetSequenceMacroText()
    local spells = GetSequenceSpells()
    if #spells == 0 then
        return ""
    end

    local cfg = (SfuiDB and SfuiDB.totembar) or (sfui.config and sfui.config.totembar) or {}
    local resetTimer = tonumber(cfg.resetTimer) or 15
    local resetStr = "reset=" .. resetTimer .. "/combat"

    return "/castsequence " .. resetStr .. " " .. table_concat(spells, ", ")
end

local function UpdateSequence()
    if not seqBtn then return end

    if InCombatLockdown and InCombatLockdown() then
        deferredSeqUpdate = true
        return
    end

    local macroText = GetSequenceMacroText()
    if macroText and macroText ~= "" then
        seqBtn:SetAttribute("type", "macro")
        seqBtn:SetAttribute("macrotext", macroText)
    else
        seqBtn:SetAttribute("type", nil)
        seqBtn:SetAttribute("macrotext", nil)
    end

    if seqBtn.icon then
        local spells = GetSequenceSpells()
        local firstSpell = spells[1]
        local tex = firstSpell and GetIconForTotem(firstSpell) or "Interface\\Icons\\INV_Misc_QuestionMark"
        seqBtn.icon:SetTexture(tex)
    end
end

local function RefreshAllArming()
    if InCombatLockdown and InCombatLockdown() then return end
    RefreshSpellBookCache()
    for _, element in ipairs(ELEMENTS) do
        local chosen = deferredArm[element] or (SfuiDB and SfuiDB.totembar and SfuiDB.totembar.selectedTotems and SfuiDB.totembar.selectedTotems[element])
        deferredArm[element] = nil
        ArmMainButton(element, chosen)
    end
    UpdateSequence()
end

-- ---------------------------------------------------------------------------
-- Tooltip Helper
-- ---------------------------------------------------------------------------
local function UpdateTotemTooltip(element, btn)
    if not btn or not btn.frame or not btn.frame.isHovered then return end
    if not GameTooltip or GameTooltip:GetOwner() ~= btn.frame then return end

    local er, eg, eb = unpack(ELEMENT_COLORS[element] or { 0.5, 0.5, 0.5 })
    GameTooltip:SetOwner(btn.frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(element .. " totem", er, eg, eb)

    local current = activeState[element]
    local arm, armKnown = GetDefaultTotemForElement(element)
    if current then
        GameTooltip:AddLine("active: " .. current.name:lower(), 0.4, 1, 0.4)
        GameTooltip:AddLine("right-click: destroy active totem", 1, 0.4, 0.4)
    end
    if armKnown then
        GameTooltip:AddLine("selected: " .. arm:lower(), 1, 1, 1)
        GameTooltip:AddLine("left-click: cast " .. arm:lower(), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("no totems learned for this element", 0.6, 0.6, 0.6)
    end

    local allTotems = GetKnownTotems(element)
    if allTotems and #allTotems > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("scroll wheel to select:", 0.5, 0.8, 1)
        for _, tName in ipairs(allTotems) do
            if tName == arm then
                GameTooltip:AddLine("  > " .. tName:lower(), 1, 0.82, 0)
            else
                GameTooltip:AddLine("    " .. tName:lower(), 0.6, 0.6, 0.6)
            end
        end
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Mouse Wheel Totem Cycling
-- ---------------------------------------------------------------------------
local function CycleTotem(element, delta)
    local totems = GetKnownTotems(element)
    if not totems or #totems <= 1 then return end

    local btn = buttons[element]
    local current = (btn and btn.selectedTotem) or (SfuiDB and SfuiDB.totembar and SfuiDB.totembar.selectedTotems and SfuiDB.totembar.selectedTotems[element])
    local currentIndex = 1
    for idx, name in ipairs(totems) do
        if name == current then
            currentIndex = idx
            break
        end
    end

    -- delta > 0: scroll up -> next totem; delta < 0: scroll down -> previous totem
    local nextIndex = currentIndex + (delta > 0 and 1 or -1)
    if nextIndex > #totems then
        nextIndex = 1
    elseif nextIndex < 1 then
        nextIndex = #totems
    end

    local chosen = totems[nextIndex]
    if not chosen then return end

    if InCombatLockdown and InCombatLockdown() then
        deferredArm[element] = chosen
        deferredSeqUpdate = true
        if btn then
            btn.selectedTotem = chosen
            if not activeState[element] and btn.icon then
                btn.icon:SetTexture(GetIconForTotem(chosen))
                btn.icon:SetAlpha(REST_ALPHA)
                UpdateButtonBorderAlpha(btn, true)
            end
        end
        SfuiDB = SfuiDB or {}
        SfuiDB.totembar = SfuiDB.totembar or {}
        SfuiDB.totembar.selectedTotems = SfuiDB.totembar.selectedTotems or {}
        SfuiDB.totembar.selectedTotems[element] = chosen
    else
        ArmMainButton(element, chosen)
        UpdateSequence()
    end

    UpdateTotemTooltip(element, btn)
end

-- ---------------------------------------------------------------------------
-- Combat Handlers
-- ---------------------------------------------------------------------------
local function OnCombatStart()
    inCombat = true
end

local function OnCombatEnd()
    inCombat = false
    sfui.totembar.ApplySettings()
    deferredSettingsUpdate = false
    deferredSeqUpdate = false
end

-- ---------------------------------------------------------------------------
-- Build Main Totem Bar
-- ---------------------------------------------------------------------------
local function CreateTotemBar()
    if bar then return end

    local cfg = (SfuiDB and SfuiDB.totembar) or {}
    local bSize = cfg.size or 36
    local spacing = cfg.spacing or 4

    bar = CreateFrame("Frame", "SfuiTotemBar", UIParent)
    bar:SetSize(4 * bSize + 3 * spacing + 8, bSize + 8)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)

    local pos = cfg.pos or { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 88 }
    bar:SetPoint(pos.point or "BOTTOM", UIParent, pos.relPoint or "BOTTOM", pos.x or 0, pos.y or 88)

    local font = GetFontPath()
    local fontSize = math.max(9, math.min(14, math.floor(bSize * 0.32 + 0.5)))

    for i, element in ipairs(ELEMENTS) do
        local b = CreateFrame("Button", "SfuiTotemBtn_" .. element, bar, "SecureActionButtonTemplate")
        b:SetSize(bSize, bSize)
        b:SetPoint("LEFT", bar, "LEFT", 4 + (i - 1) * (bSize + spacing), 0)
        b:EnableMouse(true)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:Hide()

        local colorByElement = ShouldColorByElement()
        local er, eg, eb
        if colorByElement then
            er, eg, eb = unpack(ELEMENT_COLORS[element])
        else
            er, eg, eb = 0, 0, 0
        end
        local chosen, isKnown = GetDefaultTotemForElement(element)

        local icon = SkinTotemButton(b, GetIconForTotem(chosen), er, eg, eb)
        icon:SetAlpha(isKnown and REST_ALPHA or 0.28)

        local cooldown = CreateFrame("Cooldown", "SfuiTotemBtn_" .. element .. "Cooldown", b, "CooldownFrameTemplate")
        cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        if cooldown.SetDrawEdge then cooldown:SetDrawEdge(false) end
        if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end
        cooldown:SetFrameLevel(b:GetFrameLevel() + 2)
        cooldown:Hide()

        local overlay = CreateFrame("Frame", nil, b)
        overlay:SetAllPoints(b)
        overlay:EnableMouse(false)
        overlay:SetFrameLevel(cooldown:GetFrameLevel() + 5)
        b.overlay = overlay

        local timerText = overlay:CreateFontString(nil, "OVERLAY", nil, 7)
        timerText:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 2)
        timerText:SetFont(font, fontSize, "OUTLINE")
        timerText:SetTextColor(1, 1, 1, 1)
        timerText:SetShadowOffset(1, -1)
        timerText:SetShadowColor(0, 0, 0, 1)
        timerText:Hide()

        local ar, ag, ab
        if colorByElement and ELEMENT_COLORS[element] then
            ar, ag, ab = unpack(ELEMENT_COLORS[element])
        else
            ar, ag, ab = GetActiveTotemColor()
        end
        local activeBorder = AddBorder(overlay, ar, ag, ab, 1, 6)
        for _, p in ipairs(activeBorder) do p:SetAlpha(0) end

        if sfui.common and sfui.common.sync_masque then
            sfui.common.sync_masque(b, { Icon = icon, Cooldown = cooldown })
        end

        b:HookScript("OnEnter", function(self)
            self.isHovered = true
            UpdateTotemTooltip(element, buttons[element] or { frame = self })
        end)

        b:HookScript("OnLeave", function(self)
            self.isHovered = false
            GameTooltip:Hide()
        end)

        b:EnableMouseWheel(true)
        b:HookScript("OnMouseWheel", function(_, delta)
            CycleTotem(element, delta)
        end)

        b:HookScript("PostClick", function(_, clickedBtn, down)
            if down then return end
            if clickedBtn == "RightButton" then
                SetInactive(element)
            end
        end)

        buttons[element] = {
            frame         = b,
            icon          = icon,
            cooldown      = cooldown,
            overlay       = overlay,
            timerText     = timerText,
            border        = b.border,
            activeBorder  = activeBorder,
            selectedTotem = chosen,
            element       = element,
        }

        UpdateButtonBorderAlpha(buttons[element], isKnown)
        ArmMainButton(element, chosen)
    end

    -- Sequence Secure Action Button (SfuiTotemSequenceBtn)
    if not seqBtn then
        seqBtn = CreateFrame("Button", "SfuiTotemSequenceBtn", UIParent, "SecureActionButtonTemplate")
        seqBtn:RegisterForClicks("AnyUp", "AnyDown")
        local icon = SkinTotemButton(seqBtn, "Interface\\Icons\\INV_Misc_QuestionMark", 0, 0, 0)
        seqBtn.icon = icon

        if _G.SfuiClassUtilityBtn then
            _G.SfuiClassUtilityBtn:SetAttribute("type", "click")
            _G.SfuiClassUtilityBtn:SetAttribute("clickbutton", seqBtn)
        end

        seqBtn:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("totem cast sequence", 1, 1, 1)
            local spells = GetSequenceSpells()
            if #spells > 0 then
                GameTooltip:AddLine("casts selected totems in sequence:", 0.8, 0.8, 0.8)
                for idx, sp in ipairs(spells) do
                    GameTooltip:AddLine(string_format("  %d. %s", idx, sp:lower()), 0.6, 0.8, 1)
                end
            else
                GameTooltip:AddLine("no totems selected / learned", 0.6, 0.6, 0.6)
            end
            local _, formattedKey = sfui.totembar.GetBoundKey()
            if formattedKey and formattedKey ~= "" then
                GameTooltip:AddLine("keybind: |cff00ffff" .. formattedKey:lower() .. "|r", 0.9, 0.9, 0.9)
            else
                GameTooltip:AddLine("keybind: |cff888888none (bind in options)|r", 0.9, 0.9, 0.9)
            end
            GameTooltip:AddLine("left-click: cast sequence", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)

        seqBtn:HookScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    -- Movable drag overlay
    dragOverlay = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    dragOverlay:SetAllPoints()
    dragOverlay:SetFrameStrata("DIALOG")
    dragOverlay:EnableMouse(true)
    dragOverlay:RegisterForDrag("LeftButton")
    dragOverlay:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    dragOverlay:SetBackdropColor(0, 0.6, 0.3, 0.35)
    dragOverlay:SetBackdropBorderColor(0, 1, 0.5, 0.9)

    local dragText = dragOverlay:CreateFontString(nil, "OVERLAY")
    dragText:SetPoint("CENTER", 0, 0)
    dragText:SetFont(font, 10, "OUTLINE")
    dragText:SetTextColor(1, 1, 1)
    dragText:SetText("totem bar (drag)")

    dragOverlay:SetScript("OnDragStart", function()
        bar:StartMoving()
    end)
    dragOverlay:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        local pt, _, relPt, x, y = bar:GetPoint(1)
        SfuiDB = SfuiDB or {}
        SfuiDB.totembar = SfuiDB.totembar or {}
        SfuiDB.totembar.pos = {
            point    = pt or "BOTTOM",
            relPoint = relPt or "BOTTOM",
            x        = math_floor((x or 0) + 0.5),
            y        = math_floor((y or 0) + 0.5),
        }
    end)
    dragOverlay:Hide()

    sfui.totembar.ApplySettings()
end

-- ---------------------------------------------------------------------------
-- OnUpdate Loop (Throttled Active Totem Timers)
-- ---------------------------------------------------------------------------
local function OnTotemUpdate(_)
    if activeTotemCount <= 0 then return end

    -- Countdown timer updates on active totems
    local now = GetTime()
    local showTimer = ShouldShowTimerText()
    for i = 1, #ELEMENTS do
        local element = ELEMENTS[i]
        local state = activeState[element]
        if state then
            local rem = GetElementTimeLeft(element, state, now)
            if rem <= 0 then
                SetInactive(element)
            else
                local btn = buttons[element]
                if btn and btn.timerText then
                    if showTimer then
                        local formatted = FormatTime(rem)
                        if btn._lastTimerStr ~= formatted then
                            btn._lastTimerStr = formatted
                            btn.timerText:SetText(formatted)
                        end
                        if not btn.timerText:IsShown() then
                            btn.timerText:Show()
                        end
                    else
                        if btn.timerText:IsShown() then
                            btn._lastTimerStr = nil
                            btn.timerText:SetText("")
                            btn.timerText:Hide()
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Event Handlers
-- ---------------------------------------------------------------------------
local function OnSpellcastSucceeded(_, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local spellName
    local id = type(spellID) == "number" and spellID or (type(castGUID) == "number" and castGUID)
    if id then
        if C_Spell and C_Spell.GetSpellName then
            spellName = C_Spell.GetSpellName(id)
        elseif _G.GetSpellInfo then
            spellName = _G.GetSpellInfo(id)
        end
    end
    if not spellName or spellName == "" then
        if type(castGUID) == "string" and TOTEM_ELEMENT[castGUID] then
            spellName = castGUID
        elseif type(spellID) == "string" and TOTEM_ELEMENT[spellID] then
            spellName = spellID
        end
    end
    if not spellName or spellName == "" then return end

    if spellName == "Totemic Call" then
        for _, el in ipairs(ELEMENTS) do SetInactive(el) end
        return
    end

    local element = TOTEM_ELEMENT[spellName]
    if element then
        local duration = TOTEM_DURATIONS[spellName] or 120
        SetActive(element, spellName, GetTime(), duration)
    end
end

local function OnPlayerTotemUpdate(_, slot)
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > 4 then return end

    local element = SLOT_TO_ELEMENT[slot]
    if not element then return end

    local present, name, startTime, duration = SafeTotemInfo(slot)
    if present == false then
        SetInactive(element)
    elseif present == true then
        local current = activeState[element]
        local activeName = (name and name ~= "") and name or (current and current.name) or DEFAULT_TOTEMS[element]
        local activeStart, activeDur = SanitizeTimeAndDuration(activeName, startTime, duration, current)
        SetActive(element, activeName, activeStart, activeDur)
    end
    -- present == nil: secret value in combat, leave prediction running safely
end

local function OnPlayerEnteringWorld()
    RefreshSpellBookCache()
    CreateTotemBar()
    if not InCombatLockdown() then
        RefreshAllArming()
        if SfuiDB and SfuiDB.totembar and SfuiDB.totembar.keybind then
            local k1 = sfui.totembar.GetBoundKey()
            if not k1 or k1 == "" then
                sfui.totembar.SetKeybind(SfuiDB.totembar.keybind)
            end
        end
    end
    for slot = 1, 4 do
        OnPlayerTotemUpdate(nil, slot)
    end
end

local function OnBindingsUpdated()
    if GetBindingKey then
        local k1 = sfui.totembar.GetBoundKey()
        SfuiDB = SfuiDB or {}
        SfuiDB.totembar = SfuiDB.totembar or {}
        SfuiDB.totembar.keybind = (k1 and k1 ~= "") and k1 or nil
        SfuiDB.classUtilityKeybind = (k1 and k1 ~= "") and k1 or nil
    end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function sfui.totembar.ApplySettings()
    if not bar then return end
    if InCombatLockdown and InCombatLockdown() then
        deferredSettingsUpdate = true
        return
    end
    local cfg = (SfuiDB and SfuiDB.totembar) or {}

    if cfg.enabled == false then
        bar:Hide()
        return
    end

    RefreshSpellBookCache()

    local bSize = cfg.size or 36
    local spacing = cfg.spacing or 4
    local showSeq = cfg.showSequenceButton == true

    local visibleCount = 0
    local visibleElements = {}
    for _, element in ipairs(ELEMENTS) do
        local known = GetKnownTotems(element)
        local isLearned = (known and #known > 0) or (activeState[element] ~= nil)
        if isLearned then
            visibleCount = visibleCount + 1
            visibleElements[element] = true
        else
            visibleElements[element] = false
        end
    end

    if visibleCount == 0 and not isUnlocked then
        bar:Hide()
        if seqBtn then
            seqBtn:Hide()
        end
        return
    end

    bar:Show()

    local totalBtns = visibleCount + (showSeq and 1 or 0)
    local barWidth
    if totalBtns > 0 then
        barWidth = totalBtns * bSize + math.max(0, totalBtns - 1) * spacing + 8
    else
        barWidth = bSize + 8
    end
    bar:SetSize(barWidth, bSize + 8)

    local font = GetFontPath()
    local fontSize = math.max(9, math.min(14, math.floor(bSize * 0.32 + 0.5)))
    local showTimer = ShouldShowTimerText()
    local colorByElement = ShouldColorByElement()

    local btnIndex = 0
    for _, element in ipairs(ELEMENTS) do
        local btn = buttons[element]
        if btn and btn.frame then
            if visibleElements[element] then
                btn.frame:ClearAllPoints()
                btn.frame:SetPoint("LEFT", bar, "LEFT", 4 + btnIndex * (bSize + spacing), 0)
                btn.frame:SetSize(bSize, bSize)
                btn.frame:Show()
                btnIndex = btnIndex + 1

                local _, isKnown = GetDefaultTotemForElement(element)
                local er, eg, eb
                if colorByElement then
                    er, eg, eb = unpack(ELEMENT_COLORS[element])
                else
                    er, eg, eb = 0, 0, 0
                end
                if btn.border then
                    for _, p in ipairs(btn.border) do p:SetVertexColor(er, eg, eb, 1) end
                end
                UpdateButtonBorderAlpha(btn, isKnown)

                if btn.timerText then
                    btn.timerText:SetFont(font, fontSize, "OUTLINE")
                    if showTimer then
                        if activeState[element] then
                            btn.timerText:Show()
                        end
                    else
                        btn._lastTimerStr = nil
                        btn.timerText:SetText("")
                        btn.timerText:Hide()
                    end
                end
            else
                btn.frame:ClearAllPoints()
                btn.frame:Hide()
                StopActiveGlow(btn)
                if btn.timerText then
                    btn._lastTimerStr = nil
                    btn.timerText:SetText("")
                    btn.timerText:Hide()
                end
            end
        end
    end

    if showSeq and visibleCount > 0 then
        if seqBtn then
            seqBtn:SetParent(bar)
            seqBtn:ClearAllPoints()
            seqBtn:SetPoint("LEFT", bar, "LEFT", 4 + visibleCount * (bSize + spacing), 0)
            seqBtn:SetSize(bSize, bSize)
            seqBtn:SetAlpha(1.0)
            seqBtn:EnableMouse(true)
            seqBtn:Show()
        end
    else
        if seqBtn then
            seqBtn:SetParent(UIParent)
            seqBtn:ClearAllPoints()
            seqBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1000, -1000)
            seqBtn:SetSize(1, 1)
            seqBtn:SetAlpha(0)
            seqBtn:EnableMouse(true)
            seqBtn:Show()
        end
    end

    UpdateActiveColors()
    RefreshAllArming()
    UpdateSequence()
end

function sfui.totembar.GetBoundKey()
    if sfui.keybinds and sfui.keybinds.GetClassUtilityKey then
        return sfui.keybinds.GetClassUtilityKey()
    end
    return nil, ""
end

function sfui.totembar.SetKeybind(newKey)
    if sfui.keybinds and sfui.keybinds.SetClassUtilityKey then
        return sfui.keybinds.SetClassUtilityKey(newKey)
    end
    return false
end

function sfui.totembar.UnbindKey()
    if sfui.keybinds and sfui.keybinds.UnbindClassUtilityKey then
        return sfui.keybinds.UnbindClassUtilityKey()
    end
    return false
end

function sfui.totembar.GetSequenceMacroText()
    return GetSequenceMacroText()
end

function sfui.totembar.GetSequenceSpells()
    return GetSequenceSpells()
end

function sfui.totembar.ToggleUnlock()
    if not bar or not dragOverlay then return false end
    isUnlocked = not isUnlocked
    if isUnlocked then
        dragOverlay:Show()
        if sfui.common and sfui.common.print then
            sfui.common.print("totem bar unlocked (drag to reposition).")
        end
    else
        dragOverlay:Hide()
        if sfui.common and sfui.common.print then
            sfui.common.print("totem bar locked.")
        end
    end
    sfui.totembar.ApplySettings()
    return isUnlocked
end

function sfui.totembar.ResetPosition()
    if not bar then return end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 88)
    SfuiDB = SfuiDB or {}
    SfuiDB.totembar = SfuiDB.totembar or {}
    SfuiDB.totembar.pos = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 88 }
    if sfui.common and sfui.common.print then
        sfui.common.print("totem bar position reset to default.")
    end
end

function sfui.totembar.GetDebugInfo()
    local activeCount = 0
    for _, el in ipairs(ELEMENTS) do
        if activeState[el] then activeCount = activeCount + 1 end
    end
    return {
        enabled      = (SfuiDB and SfuiDB.totembar and SfuiDB.totembar.enabled ~= false),
        activeTotems = activeCount,
        isUnlocked   = isUnlocked,
        frameCreated = bar ~= nil,
    }
end

function sfui.totembar.UpdateActiveColors()
    UpdateActiveColors()
end


-- ---------------------------------------------------------------------------
-- Registration with Central Event Dispatcher
-- ---------------------------------------------------------------------------
if sfui.events then
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnPlayerEnteringWorld)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatStart)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatEnd)
    sfui.events.RegisterEvent("PLAYER_TOTEM_UPDATE", OnPlayerTotemUpdate)
    sfui.events.RegisterEvent("SPELLS_CHANGED", function()
        if InCombatLockdown and InCombatLockdown() then
            deferredSettingsUpdate = true
        else
            sfui.totembar.ApplySettings()
        end
    end)
    sfui.events.RegisterEvent("LEARNED_SPELL_IN_TAB", function()
        if InCombatLockdown and InCombatLockdown() then
            deferredSettingsUpdate = true
        else
            sfui.totembar.ApplySettings()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", function()
        UpdateActiveColors()
        if InCombatLockdown and InCombatLockdown() then
            deferredSettingsUpdate = true
        else
            sfui.totembar.ApplySettings()
        end
    end)
    sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", function()
        if InCombatLockdown and InCombatLockdown() then
            deferredSettingsUpdate = true
        else
            sfui.totembar.ApplySettings()
        end
    end)
    sfui.events.RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", OnSpellcastSucceeded)
    sfui.events.RegisterUpdate("TotemBar", 0.2, OnTotemUpdate)
    sfui.events.RegisterEvent("UPDATE_BINDINGS", OnBindingsUpdated)
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", UpdateActiveColors)
        sfui.events.RegisterMessage("SFUI_SPEC_COLORS_UPDATED", UpdateActiveColors)
    end
end
