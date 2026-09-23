local addonName, addon = ...
sfui = sfui or {}
sfui.colors = sfui.colors or {}
sfui.common = sfui.common or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/core/colors.lua
--  Color Palettes, Normalization, Spec/Class Resolution & Caching
-- ══════════════════════════════════════════════════════════════════════════════

local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local C_ClassColor      = _G.C_ClassColor
local GetSpecializationInfoByID = (_G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecializationInfoByID) or _G.GetSpecializationInfoByID

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
    r = math.floor((r or 1) * 255 + 0.5)
    g = math.floor((g or 1) * 255 + 0.5)
    b = math.floor((b or 1) * 255 + 0.5)
    if a then
        a = math.floor(a * 255 + 0.5)
        return string.format("%02x%02x%02x%02x", a, r, g, b)
    end
    return string.format("%02x%02x%02x", r, g, b)
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
-- ────────────────────────────────────────────────────────────────────────────
-- Classic / Vanilla Spec and Class Mappings
-- ────────────────────────────────────────────────────────────────────────────
local CLASSIC_SPEC_TO_CLASS = {
    [1482] = "MAGE",
    [1484] = "DRUID",
    [1485] = "HUNTER",
    [1486] = "PALADIN",
    [1487] = "PRIEST",
    [1488] = "ROGUE",
    [1489] = "SHAMAN",
    [1490] = "WARLOCK",
    [1491] = "WARRIOR",
}

local CLASS_VANILLA_SPEC_MAP = {
    ["MAGE"] = 1482, [8] = 1482, ["DRUID"] = 1484, [11] = 1484,
    ["HUNTER"] = 1485, [3] = 1485, ["PALADIN"] = 1486, [2] = 1486,
    ["PRIEST"] = 1487, [5] = 1487, ["ROGUE"] = 1488, [4] = 1488,
    ["SHAMAN"] = 1489, [7] = 1489, ["WARLOCK"] = 1490, [9] = 1490,
    ["WARRIOR"] = 1491, [1] = 1491,
}

local CLASSIC_TREE_SPECS = {
    [1491] = { -- Warrior
        [1] = { name = "arms",         icon = 132355, role = "DPS",  specID = 71 },
        [2] = { name = "fury",         icon = 132347, role = "DPS",  specID = 72 },
        [3] = { name = "protection",   icon = 132341, role = "TANK", specID = 73 },
    },
    [1486] = { -- Paladin
        [1] = { name = "holy",         icon = 135920, role = "HEAL", specID = 65 },
        [2] = { name = "protection",   icon = 236264, role = "TANK", specID = 66 },
        [3] = { name = "retribution",  icon = 135873, role = "DPS",  specID = 70 },
    },
    [1485] = { -- Hunter
        [1] = { name = "beast mastery", icon = 132222, role = "DPS", specID = 253 },
        [2] = { name = "marksmanship",  icon = 132218, role = "DPS", specID = 254 },
        [3] = { name = "survival",      icon = 132215, role = "DPS", specID = 255 },
    },
    [1488] = { -- Rogue
        [1] = { name = "assassination", icon = 132292, role = "DPS", specID = 259 },
        [2] = { name = "combat",        icon = 132309, role = "DPS", specID = 260 },
        [3] = { name = "subtlety",      icon = 132320, role = "DPS", specID = 261 },
    },
    [1487] = { -- Priest
        [1] = { name = "discipline",   icon = 135940, role = "HEAL", specID = 256 },
        [2] = { name = "holy",         icon = 237542, role = "HEAL", specID = 257 },
        [3] = { name = "shadow",       icon = 136207, role = "DPS",  specID = 258 },
    },
    [1489] = { -- Shaman
        [1] = { name = "elemental",    icon = 136048, role = "DPS",  specID = 262 },
        [2] = { name = "enhancement",  icon = 136051, role = "DPS",  specID = 263 },
        [3] = { name = "restoration",  icon = 136052, role = "HEAL", specID = 264 },
    },
    [1482] = { -- Mage
        [1] = { name = "arcane",       icon = 135932, role = "DPS",  specID = 62 },
        [2] = { name = "fire",         icon = 135810, role = "DPS",  specID = 63 },
        [3] = { name = "frost",        icon = 135846, role = "DPS",  specID = 64 },
    },
    [1490] = { -- Warlock
        [1] = { name = "affliction",   icon = 136145, role = "DPS",  specID = 265 },
        [2] = { name = "demonology",   icon = 136172, role = "DPS",  specID = 266 },
        [3] = { name = "destruction",  icon = 136186, role = "DPS",  specID = 267 },
    },
    [1484] = { -- Druid
        [1] = { name = "balance",      icon = 136096, role = "DPS",  specID = 102 },
        [2] = { name = "feral",        icon = 132242, role = "DPS",  specID = 103 },
        [3] = { name = "restoration",  icon = 136041, role = "HEAL", specID = 105 },
    },
}

sfui.colors.CLASS_VANILLA_SPEC_MAP = CLASS_VANILLA_SPEC_MAP
sfui.common.CLASS_VANILLA_SPEC_MAP = CLASS_VANILLA_SPEC_MAP
sfui.colors.CLASSIC_TREE_SPECS = CLASSIC_TREE_SPECS
sfui.common.CLASSIC_TREE_SPECS = CLASSIC_TREE_SPECS

-- ────────────────────────────────────────────────────────────────────────────
-- Spec Color Cache (Zero table allocation in high-frequency update loops)
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

-- Returns cached { r, g, b, a } table for a specialization ID (zero allocations)
function sfui.colors.get_spec_color_table(specID)
    specID = (specID and specID > 0 and specID) or (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()) or (sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id()) or 0
    local cached = _specColorTableCache[specID]
    if cached then return cached end

    local r, g, b, a = 0.0, 0.8, 1.0, 1.0
    if not specID or specID == 0 then
        r, g, b, a = 0.35, 0.35, 0.35, 1.0
    else
        local lookupID = specID
        if sfui.isClassic and (specID >= 1482 and specID <= 1491) then
            local specs = (sfui.talents and sfui.talents.get_player_specs and sfui.talents.get_player_specs()) or (sfui.common and sfui.common.get_player_specs and sfui.common.get_player_specs())
            if specs and specs[specID] and specs[specID].equivSpecID then
                lookupID = specs[specID].equivSpecID
            elseif CLASSIC_TREE_SPECS[specID] and CLASSIC_TREE_SPECS[specID][1] then
                lookupID = CLASSIC_TREE_SPECS[specID][1].specID
            end
        end

        local specColor = (lookupID and lookupID > 0 and lookupID ~= specID) and ((SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[lookupID])
            or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[lookupID]))
        if not specColor and specID and specID > 0 then
            specColor = (SfuiDB and SfuiDB.spec_colors and SfuiDB.spec_colors[specID])
                or (sfui.config and sfui.config.spec_colors and sfui.config.spec_colors[specID])
        end

        if specColor then
            r, g, b, a = specColor[1] or specColor.r or 1, specColor[2] or specColor.g or 1, specColor[3] or specColor.b or 1, specColor[4] or specColor.a or 1.0
        else
            local classFile
            if lookupID and lookupID > 0 and lookupID < 1482 and GetSpecializationInfoByID then
                classFile = select(6, GetSpecializationInfoByID(lookupID))
            end
            if not classFile and specID and CLASSIC_SPEC_TO_CLASS[specID] then
                classFile = CLASSIC_SPEC_TO_CLASS[specID]
            end
            if not classFile and lookupID and CLASSIC_SPEC_TO_CLASS[lookupID] then
                classFile = CLASSIC_SPEC_TO_CLASS[lookupID]
            end
            if not classFile then
                local pClass = (sfui.talents and sfui.talents.get_player_class and sfui.talents.get_player_class()) or (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class())
                if type(pClass) == "string" and pClass ~= "" then
                    classFile = pClass
                elseif UnitClass then
                    local _, eng = UnitClass("player")
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

-- Returns RGB(A) color for a specialization ID, falling back to class color or cyan
function sfui.colors.get_spec_color(specID)
    local t = sfui.colors.get_spec_color_table(specID)
    return t[1], t[2], t[3], t[4]
end
sfui.common.get_spec_color = sfui.colors.get_spec_color

-- Returns cached { r, g, b, a } table for the player's active specialization / class color.
-- Respects global SfuiDB.useSpecColor setting and rebuilds in-place via get_spec_color_table().
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
    local isClassic = sfui.isClassic or not (sfui.compat and sfui.compat.has and sfui.compat.has.specializations)
    if not isClassic then
        return sfui.common.get_player_specs()
    end

    local common = sfui.common
    local classFilename, classID = common and common.get_player_class and common.get_player_class()
    if not classFilename or classFilename == "" or type(classFilename) ~= "string" then
        local _, eng, cid = UnitClass("player")
        classFilename = eng
        classID = cid or classID
    end

    local vSpecID = (classFilename and CLASS_VANILLA_SPEC_MAP[classFilename])
        or (classID and CLASS_VANILLA_SPEC_MAP[classID])
    local treeSpecs = vSpecID and CLASSIC_TREE_SPECS[vSpecID]
    if not treeSpecs then
        return sfui.common.get_player_specs()
    end

    local resultSpecs = {}
    local resultIDs = {}
    for treeIdx = 1, 3 do
        local entry = treeSpecs[treeIdx]
        if entry and entry.specID then
            local sID = entry.specID
            local name = entry.name
            local icon = entry.icon

            if GetTalentTabInfo then
                local r1, r2, r3, r4 = GetTalentTabInfo(treeIdx)
                local tabName = (type(r1) == "string" and r1) or (type(r2) == "string" and r2)
                local tabIcon = (type(r2) == "number" and r2) or (type(r4) == "number" and r4)
                if tabName and tabName ~= "" then name = tabName end
                if tabIcon and tabIcon > 0 then icon = tabIcon end
            end

            name = name and string.lower(name) or ("tree " .. treeIdx)

            resultSpecs[sID] = {
                id = sID,
                name = name,
                icon = icon or 134400,
                role = (entry.role == "TANK" and "TANK") or (entry.role == "HEAL" and "HEALER") or "DAMAGER",
                classicRole = entry.role,
                treeIndex = treeIdx,
            }
            resultIDs[#resultIDs + 1] = sID
        end
    end
    return resultSpecs, resultIDs
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
    local colorInfo = GetPowerBarColor and GetPowerBarColor(resource)
    if colorInfo then return colorInfo end
    local powerName = ""
    if type(resource) == "number" then
        powerName = powerTypeToName[resource]
    end
    local cfg = sfui.config
    local resColors = cfg and cfg.colors and cfg.colors.resources
    return (resColors and resColors[powerName]) or (GetPowerBarColor and GetPowerBarColor("MANA")) or { r = 0, g = 0.5, b = 1 }
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


