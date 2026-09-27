local addonName, addon = ...
sfui = sfui or {}
sfui.colors = sfui.colors or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/colors.lua
--  Color Palettes, Normalization, Spec/Class Resolution & Hot-Path Caching
-- ══════════════════════════════════════════════════════════════════════════════

local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local C_ClassColor      = _G.C_ClassColor
local GetSpecializationInfoByID = (_G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecializationInfoByID) or _G.GetSpecializationInfoByID
local select, tonumber, type = _G.select, _G.tonumber, _G.type
local math_floor = math.floor
local string_format = string.format

--- Normalizes and unpacks color from either array { r, g, b, a } or dictionary { r = ..., g = ..., b = ..., a = ... }
function sfui.colors.unpack_color(color, defaultR, defaultG, defaultB, defaultA)
    if not color then return defaultR or 1, defaultG or 1, defaultB or 1, defaultA or 1 end
    local r = color[1] or color.r or defaultR or 1
    local g = color[2] or color.g or defaultG or 1
    local b = color[3] or color.b or defaultB or 1
    local a = color[4] or color.a or defaultA or 1
    return r, g, b, a
end
sfui.common.unpack_color = sfui.colors.unpack_color

--- Convert RGB(A) floats (0-1) to 6 or 8 character hex string without alpha prefix
function sfui.colors.rgb_to_hex(r, g, b, a)
    r = math_floor((r or 1) * 255 + 0.5)
    g = math_floor((g or 1) * 255 + 0.5)
    b = math_floor((b or 1) * 255 + 0.5)
    if a then
        a = math_floor(a * 255 + 0.5)
        return string_format("%02x%02x%02x%02x", a, r, g, b)
    end
    return string_format("%02x%02x%02x", r, g, b)
end
sfui.common.rgb_to_hex = sfui.colors.rgb_to_hex

--- Convert 6 or 8 character hex string to RGB(A) floats (0-1)
function sfui.colors.hex_to_rgb(hex)
    if not hex or type(hex) ~= "string" then return 1, 1, 1, 1 end
    hex = hex:gsub("#", ""):gsub("^ff", "") -- strip leading '#' or alpha prefix if present
    if #hex == 6 then
        local r = tonumber(hex:sub(1, 2), 16) or 255
        local g = tonumber(hex:sub(3, 4), 16) or 255
        local b = tonumber(hex:sub(5, 6), 16) or 255
        return r / 255, g / 255, b / 255, 1
    elseif #hex == 8 then
        local a = tonumber(hex:sub(1, 2), 16) or 255
        local r = tonumber(hex:sub(3, 4), 16) or 255
        local g = tonumber(hex:sub(5, 6), 16) or 255
        local b = tonumber(hex:sub(7, 8), 16) or 255
        return r / 255, g / 255, b / 255, a / 255
    end
    return 1, 1, 1, 1
end
sfui.common.hex_to_rgb = sfui.colors.hex_to_rgb

-- ────────────────────────────────────────────────────────────────────────────
-- Spec Color Cache (Zero table allocation in high-frequency hot-path update loops)
-- ────────────────────────────────────────────────────────────────────────────
local _specColorTableCache = {}
local _specColorCache = { 1, 1, 1, 1 }
local _specColorDirty = true

function sfui.colors.invalidate_spec_color_cache()
    table.wipe(_specColorTableCache)
    _specColorDirty = true
end
sfui.common.invalidate_spec_color_cache = sfui.colors.invalidate_spec_color_cache

sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("SPEC_INVOLUNTARILY_CHANGED", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("PLAYER_TALENT_UPDATE", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("CHARACTER_POINTS_CHANGED", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED", sfui.colors.invalidate_spec_color_cache)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", sfui.colors.invalidate_spec_color_cache)

--- Returns cached { r, g, b, a } table for a specialization ID (zero allocations on hot path)
function sfui.colors.get_spec_color_table(specID)
    specID = (specID and specID > 0 and specID)
        or (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id())
        or (sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id())
        or 0

    local cached = _specColorTableCache[specID]
    if cached then return cached end

    local r, g, b, a = 0.0, 0.8, 1.0, 1.0
    if not specID or specID == 0 then
        r, g, b, a = 0.35, 0.35, 0.35, 1.0
    else
        local specColor = (SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
            or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])

        if specColor then
            r, g, b, a = specColor[1] or specColor.r or 1, specColor[2] or specColor.g or 1, specColor[3] or specColor.b or 1, specColor[4] or specColor.a or 1.0
        else
            local classFile
            if GetSpecializationInfoByID and specID > 0 and specID < 1482 then
                classFile = select(6, GetSpecializationInfoByID(specID))
            end
            if not classFile then
                local pClass = (sfui.talents and sfui.talents.get_player_class and sfui.talents.get_player_class())
                    or (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())
                if type(pClass) == "string" and pClass ~= "" then
                    classFile = pClass
                elseif _G.UnitClass then
                    local _, eng = _G.UnitClass("player")
                    classFile = eng
                end
            end
            local cc = classFile and (C_ClassColor and C_ClassColor.GetClassColor(classFile) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
            if cc then
                r, g, b, a = cc.r, cc.g, cc.b, 1.0
            end
        end
    end

    local t = { r, g, b, a, r = r, g = g, b = b, a = a }
    _specColorTableCache[specID] = t
    return t
end
sfui.common.get_spec_color_table = sfui.colors.get_spec_color_table

--- Returns RGB(A) color for a specialization ID, falling back to class color or cyan
function sfui.colors.get_spec_color(specID)
    local t = sfui.colors.get_spec_color_table(specID)
    return t[1], t[2], t[3], t[4]
end
sfui.common.get_spec_color = sfui.colors.get_spec_color

--- Returns cached { r, g, b, a } table for the player's active specialization / class color.
--- Respects global SfuiDB.useSpecColor setting and rebuilds in-place via get_spec_color_table().
function sfui.colors.get_class_or_spec_color()
    if SfuiDB and SfuiDB.useSpecColor == false then
        return SfuiDB.specColorFallback or { 1, 1, 1, 1 }
    end

    if not _specColorDirty then
        return _specColorCache
    end

    local t = sfui.colors.get_spec_color_table()
    _specColorCache[1], _specColorCache[2], _specColorCache[3], _specColorCache[4] =
        t[1] or 1, t[2] or 1, t[3] or 1, t[4] or 1

    _specColorDirty = false
    return _specColorCache
end
sfui.colors.get_current_spec_color = sfui.colors.get_class_or_spec_color
sfui.common.get_current_spec_color = sfui.colors.get_class_or_spec_color
sfui.common.get_class_or_spec_color = sfui.colors.get_class_or_spec_color

function sfui.colors.get_spec_color_options()
    if sfui.talents and sfui.talents.get_spec_color_options then
        return sfui.talents.get_spec_color_options()
    end
    return {}, {}
end
sfui.common.get_spec_color_options = sfui.colors.get_spec_color_options

local powerTypeToName = {
    [0] = "MANA",
    [1] = "RAGE",
    [2] = "FOCUS",
    [3] = "ENERGY",
    [4] = "COMBO_POINTS",
    [5] = "RUNES",
    [6] = "RUNIC_POWER",
    [7] = "SOUL_SHARDS",
    [8] = "LUNAR_POWER",
    [9] = "HOLY_POWER",
    [11] = "MAELSTROM",
    [12] = "CHI",
    [13] = "INSANITY",
    [16] = "ARCANE_CHARGES",
    [17] = "FURY",
    [18] = "PAIN",
}

function sfui.colors.get_resource_color(resource)
    local colorInfo = _G.GetPowerBarColor and _G.GetPowerBarColor(resource)
    if colorInfo then return colorInfo end
    local powerName = ""
    if type(resource) == "number" then
        powerName = powerTypeToName[resource]
    end
    local cfg = sfui.config
    local resColors = cfg and cfg.colors and cfg.colors.resources
    return (resColors and resColors[powerName]) or (_G.GetPowerBarColor and _G.GetPowerBarColor("MANA")) or { r = 0, g = 0.5, b = 1 }
end
sfui.common.get_resource_color = sfui.colors.get_resource_color

function sfui.colors.set_color(element, colorName, alpha)
    local cfg = sfui.config
    local color = cfg and cfg.colors and cfg.colors[colorName]
    if not color or not element then return end
    alpha = alpha or 1

    if element.SetTextColor then
        element:SetTextColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropBorderColor then
        element:SetBackdropBorderColor(color[1], color[2], color[3], alpha)
    elseif element.SetBackdropColor then
        element:SetBackdropColor(color[1], color[2], color[3], alpha)
    end
end
sfui.common.set_color = sfui.colors.set_color
