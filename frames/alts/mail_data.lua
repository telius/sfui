local addonName, addon = ...
sfui = sfui or {}
sfui.alts = sfui.alts or {}
sfui.alts.mail = sfui.alts.mail or {}

local mail = sfui.alts.mail
local common = sfui.common

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/alts/mail_data.lua
--  Account-wide routing rules, item evaluation, and bag scanning engine
-- ══════════════════════════════════════════════════════════════════════════════

local C_Container = _G.C_Container
local C_Item = _G.C_Item
local GetItemInfoInstant = (common and common.get_item_instant_info) or _G.GetItemInfoInstant
local GetItemInfo = (common and common.get_item_info) or _G.GetItemInfo
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass

--- Highest carried bag index to scan (backpack 0, bags 1-4, reagent bag 5 when available)
--- @return number lastBag
function mail.GetLastBagIndex()
    local total = _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS
    if not total then
        local consts = _G.Constants and _G.Constants.InventoryConstants
        if consts and consts.NumBagSlots then
            total = consts.NumBagSlots + (consts.NumReagentBagSlots or 0)
        end
    end
    return total or _G.NUM_BAG_SLOTS or 4
end

--- Ensure accountwide database structure is initialized
--- @return table settings
function mail.GetSettings()
    SfuiDB = SfuiDB or {}
    if not SfuiDB.altMailRouting then
        SfuiDB.altMailRouting = {
            enabled               = true,
            autoOpenAtMailbox     = true,
            disenchanterGUID      = nil,
            disenchantQuality     = 2, -- legacy: 2 = uncommon+, 3 = rare+, 4 = epic
            disenchantQualityMode = "all", -- "all", "green", "green_blue", "rare_epic"
            disenchantWeapons     = true,
            disenchantArmor       = true,
            routes                = {},
            ignoredItems          = {},
        }
    end
    local s = SfuiDB.altMailRouting
    s.routes = s.routes or {}
    s.ignoredItems = s.ignoredItems or {}
    if s.disenchantQualityMode == nil then
        s.disenchantQualityMode = "all"
    end
    return s
end

local SECONDARY_PROFESSIONS = {
    ["cooking"]       = true,
    ["fishing"]       = true,
    ["first aid"]     = true,
    ["firstaid"]      = true,
    ["archaeology"]   = true,
    ["comprehension"] = true,
}

local PRIMARY_PROF_HANDLES = {
    ["alchemy"]        = "alch",
    ["blacksmithing"]  = "bs",
    ["enchanting"]     = "ench",
    ["engineering"]    = "eng",
    ["herbalism"]      = "h",
    ["inscription"]    = "ins",
    ["jewelcrafting"]  = "jc",
    ["leatherworking"] = "lw",
    ["mining"]         = "m",
    ["skinning"]       = "skin",
    ["tailoring"]      = "t",
}

local PRIMARY_PROF_ICONS = {
    ["alchemy"]        = "Interface\\Icons\\Trade_Alchemy",
    ["blacksmithing"]  = "Interface\\Icons\\Trade_BlackSmithing",
    ["enchanting"]     = "Interface\\Icons\\Trade_Engraving",
    ["engineering"]    = "Interface\\Icons\\Trade_Engineering",
    ["herbalism"]      = "Interface\\Icons\\Spell_Nature_NatureTouchGrow",
    ["inscription"]    = "Interface\\Icons\\INV_Inscription_Tradeskill01",
    ["jewelcrafting"]  = "Interface\\Icons\\INV_Misc_Gem_01",
    ["leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
    ["mining"]         = "Interface\\Icons\\Trade_Mining",
    ["skinning"]       = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    ["tailoring"]      = "Interface\\Icons\\Trade_Tailoring",
}

local PRIMARY_PROF_BY_ID = {
    [171] = "alchemy",
    [164] = "blacksmithing",
    [333] = "enchanting",
    [202] = "engineering",
    [182] = "herbalism",
    [165] = "leatherworking",
    [186] = "mining",
    [393] = "skinning",
    [197] = "tailoring",
    [755] = "jewelcrafting",
    [773] = "inscription",
}

--- Identify canonical base profession key from raw name or subspecialization
--- @param name string
--- @return string|nil baseKey
local function IdentifyBaseProfession(name)
    if not name or name == "" then return nil end
    local lower = name:lower()
    if SECONDARY_PROFESSIONS[lower] or lower:find("cook") or lower:find("fish") or lower:find("first aid") or lower:find("archaeo") or lower:find("comprehen") then
        return nil
    end

    if lower:find("alchem") then
        return "alchemy"
    elseif lower:find("blacksmith") or lower:find("smith") or lower:find("armorsmith") or lower:find("weaponsmith") then
        return "blacksmithing"
    elseif lower:find("enchant") then
        return "enchanting"
    elseif lower:find("engineer") then
        return "engineering"
    elseif lower:find("herb") then
        return "herbalism"
    elseif lower:find("inscript") then
        return "inscription"
    elseif lower:find("jewel") or lower:find("gem") then
        return "jewelcrafting"
    elseif lower:find("skin") then
        return "skinning"
    elseif lower:find("leather") then
        return "leatherworking"
    elseif lower:find("mining") or lower:find("smelt") then
        return "mining"
    elseif lower:find("tailor") then
        return "tailoring"
    end

    if PRIMARY_PROF_ICONS[lower] then
        return lower
    end

    return nil
end

--- Format a single primary profession into its short handle, taking into account specializations
--- @param profName string
--- @return string|nil handle
function mail.FormatProfessionHandle(profName)
    if not profName or profName == "" then return nil end
    local lower = profName:lower()

    -- Explicitly exclude secondary professions
    if SECONDARY_PROFESSIONS[lower] or lower:find("cook") or lower:find("fish") or lower:find("first aid") or lower:find("archaeo") or lower:find("comprehen") then
        return nil
    end

    -- Blacksmithing specializations
    if lower:find("armor") and (lower:find("smith") or lower:find("blacksmith")) then
        return "bs - armor"
    elseif lower:find("weapon") and (lower:find("smith") or lower:find("blacksmith")) then
        return "bs - weapon"
    elseif lower:find("axe") and lower:find("smith") then
        return "bs - axe"
    elseif lower:find("sword") and lower:find("smith") then
        return "bs - sword"
    elseif lower:find("hammer") and lower:find("smith") then
        return "bs - hammer"
    elseif lower:find("blacksmith") then
        return "bs"
    -- Leatherworking specializations
    elseif lower:find("dragon") and lower:find("leather") then
        return "lw - dragon"
    elseif lower:find("elem") and lower:find("leather") then
        return "lw - elem"
    elseif lower:find("tribal") and lower:find("leather") then
        return "lw - tribal"
    elseif lower:find("leatherwork") then
        return "lw"
    -- Tailoring specializations
    elseif lower:find("shadow") and lower:find("tailor") then
        return "t - shadow"
    elseif lower:find("spellfire") and lower:find("tailor") then
        return "t - fire"
    elseif lower:find("moon") and lower:find("tailor") then
        return "t - moon"
    elseif lower:find("tailor") then
        return "t"
    -- Engineering specializations
    elseif lower:find("goblin") and lower:find("engineer") then
        return "eng - gob"
    elseif lower:find("gnom") and lower:find("engineer") then
        return "eng - gnom"
    elseif lower:find("engineer") then
        return "eng"
    -- Gathering
    elseif lower:find("herb") then
        return "h"
    elseif lower:find("mining") then
        return "m"
    elseif lower:find("skin") then
        return "skin"
    -- Crafting
    elseif lower:find("alchem") then
        return "alch"
    elseif lower:find("enchant") then
        return "ench"
    elseif lower:find("jewel") or lower:find("gem") then
        return "jc"
    elseif lower:find("inscript") then
        return "ins"
    end

    return PRIMARY_PROF_HANDLES[lower] or nil
end

--- Get a list of short primary profession handles for an alt
--- @param guid string
--- @return table handles, string formattedString
function mail.GetAltProfessionHandles(guid)
    if not guid or not SfuiDB or not SfuiDB.alts then return {}, "" end
    local alt = SfuiDB.alts[guid]
    if not alt or not alt.professions then return {}, "" end

    local profs = alt.professions
    local rawNames = {}
    local seen = {}

    -- 1. Check primaries list
    if profs.primaries then
        for _, p in ipairs(profs.primaries) do
            local name = p.name or p.defName
            if name then
                local lname = name:lower()
                if not SECONDARY_PROFESSIONS[lname] and not seen[lname] then
                    seen[lname] = true
                    table.insert(rawNames, name)
                end
            end
        end
    end

    -- 2. Check key-value table, ignoring secondary keys
    for k, v in pairs(profs) do
        local lk = tostring(k):lower()
        if k ~= "primaries" and not SECONDARY_PROFESSIONS[lk] and type(v) == "table" and v.name then
            local name = v.name
            local lname = name:lower()
            if not SECONDARY_PROFESSIONS[lname] and not seen[lname] then
                seen[lname] = true
                table.insert(rawNames, name)
            end
        end
    end

    -- Convert to handles and deduplicate/upgrade (e.g. "bs - armor" upgrades "bs")
    local handlesMap = {}
    for _, rawName in ipairs(rawNames) do
        local h = mail.FormatProfessionHandle(rawName)
        if h and h ~= "" then
            if h:find(" %- ") then
                local base = h:match("^(%S+)")
                if base and handlesMap[base] then
                    handlesMap[base] = nil
                end
                handlesMap[h] = true
            else
                local hasSpec = false
                for existing in pairs(handlesMap) do
                    if existing:match("^" .. h .. " %-") then
                        hasSpec = true
                        break
                    end
                end
                if not hasSpec then
                    handlesMap[h] = true
                end
            end
        end
    end

    local result = {}
    for h in pairs(handlesMap) do
        table.insert(result, h)
    end
    table.sort(result)

    return result, table.concat(result, ", ")
end

--- Get a list of primary professions with icons, ranks, and metadata for an alt
--- @param guid string
--- @return table professions List of { name = string, baseKey = string, icon = string, rank = number, maxRank = number }
function mail.GetAltProfessions(guid)
    if not guid or not SfuiDB or not SfuiDB.alts then return {} end
    local alt = SfuiDB.alts[guid]
    if not alt or not alt.professions then return {} end

    local profs = alt.professions
    local collected = {}

    local function processEntry(entry)
        if type(entry) ~= "table" then return end
        local rawName = entry.name or entry.defName
        local skillID = entry.skillID
        local baseKey = (skillID and PRIMARY_PROF_BY_ID[skillID]) or IdentifyBaseProfession(rawName)
        if not baseKey then return end

        local icon = entry.icon
        if not icon or icon == "" then
            icon = PRIMARY_PROF_ICONS[baseKey] or "Interface\\Icons\\INV_Misc_QuestionMark"
        end

        local rank = entry.rank or 0
        local maxRank = (entry.maxRank and entry.maxRank > 0) and entry.maxRank or 300
        local dispName = (rawName and rawName ~= "") and rawName:lower() or baseKey
        local isSpec = (dispName ~= baseKey)

        if not collected[baseKey] then
            collected[baseKey] = {
                name    = dispName,
                baseKey = baseKey,
                icon    = icon,
                rank    = rank,
                maxRank = maxRank,
                isSpec  = isSpec,
            }
        else
            local cur = collected[baseKey]
            if not cur.isSpec and isSpec then
                cur.name = dispName
                cur.isSpec = true
                if icon and icon ~= "" then cur.icon = icon end
            end
            if rank > (cur.rank or 0) then cur.rank = rank end
            if maxRank > (cur.maxRank or 0) then cur.maxRank = maxRank end
        end
    end

    if profs.primaries then
        for _, p in ipairs(profs.primaries) do
            processEntry(p)
        end
    end

    for k, v in pairs(profs) do
        if k ~= "primaries" then
            processEntry(v)
        end
    end

    local result = {}
    for _, item in pairs(collected) do
        table.insert(result, item)
    end
    table.sort(result, function(a, b)
        return a.baseKey < b.baseKey
    end)

    return result
end

--- Get inline formatted icons string for alt's primary professions
--- @param guid string
--- @param size number?
--- @return string markup
function mail.GetAltProfessionIconsMarkup(guid, size)
    local profs = mail.GetAltProfessions(guid)
    if #profs == 0 then return "" end
    local s = size or 13
    local parts = {}
    for _, p in ipairs(profs) do
        table.insert(parts, string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t", p.icon, s, s))
    end
    return table.concat(parts, " ")
end

--- Get all tracked alts from SfuiDB.alts sorted alphabetically
--- @param includeCurrent boolean?
--- @return table alts
function mail.GetAlts(includeCurrent)
    local myGUID = UnitGUID("player")
    if includeCurrent and myGUID and (not SfuiDB or not SfuiDB.alts or not SfuiDB.alts[myGUID]) then
        if sfui.alts and sfui.alts.SyncCurrentCharacter then
            sfui.alts.SyncCurrentCharacter()
        end
    end
    local list = {}
    local altsDB = SfuiDB and SfuiDB.alts

    if altsDB then
        for guid, altData in pairs(altsDB) do
            local isCurrent = (guid == myGUID)
            if includeCurrent or not isCurrent then
                local hasEnchanting = false
                local profList = mail.GetAltProfessions(guid)
                for _, p in ipairs(profList) do
                    if p.baseKey == "enchanting" then
                        hasEnchanting = true
                        break
                    end
                end

                if not hasEnchanting and altData.professions then
                    if altData.professions["Enchanting"] or altData.professions["enchanting"] then
                        hasEnchanting = true
                    end
                end

                local _, profString = mail.GetAltProfessionHandles(guid)
                local iconsMarkup = mail.GetAltProfessionIconsMarkup(guid, 13)

                table.insert(list, {
                    guid          = guid,
                    name          = altData.name or "unknown",
                    surname       = altData.surname,
                    realm         = altData.realm or (GetRealmName and GetRealmName()) or "",
                    class         = altData.class or "WARRIOR",
                    level         = altData.level or 1,
                    isCurrent     = isCurrent,
                    hasEnchanting = hasEnchanting,
                    profString    = profString,
                    iconsMarkup   = iconsMarkup,
                    professions   = profList,
                })
            end
        end
    end

    table.sort(list, function(a, b)
        local lvlA = tonumber(a.level) or 1
        local lvlB = tonumber(b.level) or 1
        if lvlA ~= lvlB then
            return lvlA > lvlB
        end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    return list
end

--- Get route settings for a specific alt guid
--- @param guid string
--- @return table route
function mail.GetRoute(guid)
    if not guid then return {} end
    local settings = mail.GetSettings()
    if not settings.routes[guid] then
        settings.routes[guid] = {
            items           = {},
            sendHerbs       = false,
            sendOre         = false,
            sendCloth       = false,
            sendLeather     = false,
            sendEnchanting  = false,
            sendGems        = false,
            sendElemental   = false,
            sendCooking     = false,
            sendEngineering   = false,
            sendInscription   = false,
            sendComprehension = false,
        }
    end
    return settings.routes[guid]
end

--- Set or clear the assigned disenchanter alt
--- @param guid string|nil
function mail.SetAssignedDisenchanter(guid)
    local settings = mail.GetSettings()
    settings.disenchanterGUID = guid
end

--- Get assigned disenchanter alt data
--- @return table|nil altData
function mail.GetAssignedDisenchanter()
    local settings = mail.GetSettings()
    local guid = settings.disenchanterGUID
    if not guid or not SfuiDB or not SfuiDB.alts then return nil end
    local alt = SfuiDB.alts[guid]
    if alt then
        return {
            guid  = guid,
            name  = alt.name or "unknown",
            realm = alt.realm or (GetRealmName and GetRealmName()) or "",
            class = alt.class or "PRIEST",
            level = alt.level or 1,
        }
    end
    return nil
end

--- Add an item to an alt's assigned list
--- @param guid string
--- @param itemID number
function mail.AddItemToRoute(guid, itemID)
    if not guid or not itemID then return end
    local settings = mail.GetSettings()
    for otherGuid, otherRoute in pairs(settings.routes or {}) do
        if otherGuid ~= guid and otherRoute.items and otherRoute.items[itemID] then
            otherRoute.items[itemID] = nil
        end
    end
    local route = mail.GetRoute(guid)
    route.items = route.items or {}
    route.items[itemID] = true
end

--- Remove an item from an alt's assigned list
--- @param guid string
--- @param itemID number
function mail.RemoveItemFromRoute(guid, itemID)
    if not guid or not itemID then return end
    local route = mail.GetRoute(guid)
    if route.items then
        route.items[itemID] = nil
    end
end

--- Toggle category rule for an alt
--- @param guid string
--- @param categoryKey string
--- @param enabled boolean
function mail.ToggleCategory(guid, categoryKey, enabled)
    if not guid or not categoryKey then return end
    local settings = mail.GetSettings()
    if enabled then
        -- Automatically unassign from other alts so this category routes exclusively here
        for otherGuid, otherRoute in pairs(settings.routes or {}) do
            if otherGuid ~= guid and otherRoute[categoryKey] then
                otherRoute[categoryKey] = false
            end
        end
    end
    local route = mail.GetRoute(guid)
    route[categoryKey] = enabled and true or false
end

--- Get information about which character a category is currently routed to
--- @param categoryKey string
--- @return string|nil name, string|nil class, string|nil guid
function mail.GetCategoryRecipient(categoryKey)
    if not categoryKey then return nil, nil, nil end
    local settings = mail.GetSettings()
    local myGUID = UnitGUID and UnitGUID("player")
    for guid, route in pairs(settings.routes or {}) do
        if route[categoryKey] == true then
            local alt = SfuiDB and SfuiDB.alts and SfuiDB.alts[guid]
            local dName = alt and alt.name
            if not dName and guid == myGUID and UnitName then
                dName = UnitName("player")
            end
            local class = (alt and alt.class) or (guid == myGUID and UnitClass and select(2, UnitClass("player"))) or "WARRIOR"
            return dName, class, guid
        end
    end
    return nil, nil, nil
end

--- Check if an item is blacklisted from auto-routing
--- @param itemID number
--- @return boolean isIgnored
function mail.IsItemIgnored(itemID)
    if not itemID then return false end
    local settings = mail.GetSettings()
    return settings.ignoredItems and settings.ignoredItems[itemID] == true
end

--- Add or remove an item from the blacklist
--- @param itemID number
--- @param ignored boolean
function mail.SetItemIgnored(itemID, ignored)
    if not itemID then return end
    local settings = mail.GetSettings()
    settings.ignoredItems = settings.ignoredItems or {}
    if ignored then
        settings.ignoredItems[itemID] = true
    else
        settings.ignoredItems[itemID] = nil
    end
end

--- Get all ignored item IDs
--- @return table ignoredItems
function mail.GetIgnoredItems()
    local settings = mail.GetSettings()
    return settings.ignoredItems or {}
end

--- Get disenchant quality filtering mode
--- @return string mode "all", "green", "green_blue", "rare_epic"
function mail.GetDisenchantQualityMode()
    local settings = mail.GetSettings()
    return settings.disenchantQualityMode or "all"
end

--- Set disenchant quality filtering mode
--- @param mode string
function mail.SetDisenchantQualityMode(mode)
    local settings = mail.GetSettings()
    settings.disenchantQualityMode = mode or "all"
end

--- Check if an item is a Bind-on-Equip gear item suitable for disenchanting
--- @param itemID number
--- @param itemLink string
--- @param classID number?
--- @param subclassID number?
--- @param quality number?
--- @param bindType number?
--- @return boolean isDisenchantable
function mail.IsDisenchantableBoE(itemID, itemLink, classID, subclassID, quality, bindType)
    if not itemID or not itemLink then return false end
    local settings = mail.GetSettings()
    if not settings.disenchanterGUID then return false end

    -- Extract info if not pre-fetched
    if not classID or not quality or not bindType then
        local _, _, q, _, _, _, _, _, _, _, _, cID, _, bType = GetItemInfo(itemLink)
        quality = quality or q
        classID = classID or cID
        bindType = bindType or bType
    end

    -- Must be BoE (bindType == 2)
    if bindType ~= 2 then return false end

    -- Must be Weapon or Armor
    local isWeapon = (classID == Enum.ItemClass.Weapon or classID == 2)
    local isArmor  = (classID == Enum.ItemClass.Armor or classID == 4)
    if not isWeapon and not isArmor then return false end

    if isWeapon and not settings.disenchantWeapons then return false end
    if isArmor and not settings.disenchantArmor then return false end

    -- Quality mode threshold (green only = 2, green & blue = 2-3, rare+ = 3-4, all = 2-4)
    if not quality then return false end
    local mode = settings.disenchantQualityMode or "all"
    if mode == "green" then
        if quality ~= 2 then return false end
    elseif mode == "green_blue" then
        if quality < 2 or quality > 3 then return false end
    elseif mode == "rare_epic" then
        if quality < 3 or quality > 4 then return false end
    else
        local minQuality = settings.disenchantQuality or 2
        if quality < minQuality or quality > 4 then return false end
    end

    return true
end


-- ─────────────────────────────────────────────────────────────────────────────
--  Mage Comprehension Scrolls (Camelot / Warcraft Forever - Skill 3012)
-- ─────────────────────────────────────────────────────────────────────────────
local COMPREHENSION_SCROLL_IDS = {
    [211780] = true, -- Scroll: KWYJIBO
    [211784] = true, -- Scroll: WUBBA WUBBA
    [211785] = true, -- Scroll: CWAL
    [211786] = true, -- Scroll: CHAP BALK WELLES
    [211787] = true, -- Scroll: LOWER PING WHOMEVER
    [211853] = true, -- Scroll: VOCE WELL
    [211854] = true, -- Scroll: OMIT KESA
    [211855] = true, -- Scroll: STHENIC LUNATE
    [213543] = true, -- Scroll: UPDOG
    [213544] = true, -- Scroll: TOPAZ YORAK
    [213545] = true, -- Scroll: PEATCHY ATTAX
    [213546] = true, -- Scroll: SHOOBEEDOOP
    [213547] = true, -- Scroll: THAW WORDS
    [281015] = true, -- Scroll: DOST OREM
    [281016] = true, -- Scroll: FORGOT HOOF THUD
    [281017] = true, -- Scroll: KEEP CLEF FOCI
    [281018] = true, -- Scroll: RARE SERVICHI RADAR
}

--- Check if an item is an untranslated Mage Comprehension scroll
--- @param itemID number?
--- @param itemLink string?
--- @param classID number?
--- @param subclassID number?
--- @return boolean isScroll
local function IsComprehensionScroll(itemID, itemLink, classID, subclassID)
    if not itemID and not itemLink then return false end

    if itemID and COMPREHENSION_SCROLL_IDS[itemID] then
        return true
    end

    -- Heuristic check: Consumable -> Scroll with "Scroll: <Cipher>" naming pattern
    local scrollClass = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
    local scrollSubclass = (Enum and Enum.ItemConsumableSubclass and Enum.ItemConsumableSubclass.Scroll) or 4
    local isScroll = (classID == scrollClass or classID == 0) and (subclassID == scrollSubclass or subclassID == 4)

    if isScroll then
        local itemName = GetItemInfo(itemLink or itemID)
        if itemName and itemName:lower():match("^scroll%s*:") then
            return true
        end
    end

    -- Tooltip check: look for "comprehension" skill requirement
    local C_TooltipInfo = _G.C_TooltipInfo
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink and itemLink then
        local data = C_TooltipInfo.GetHyperlink(itemLink)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local text = (line.leftText or (line.args and line.args[2] and line.args[2].stringVal) or ""):lower()
                if text:find("comprehension") then
                    return true
                end
            end
        end
    end

    return false
end

--- Check if an item matches tradeskill category filters
--- @param classID number?
--- @param subclassID number?
--- @param categoryKey string
--- @param itemID number?
--- @param itemLink string?
--- @return boolean matches
local function MatchesTradeskillCategory(classID, subclassID, categoryKey, itemID, itemLink)
    local tradeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
    local gemClass = (Enum and Enum.ItemClass and Enum.ItemClass.Gem) or 3
    local isTrade = (classID == tradeClass or classID == 7)

    if categoryKey == "sendHerbs" then
        return isTrade and subclassID == 9
    elseif categoryKey == "sendOre" then
        return isTrade and subclassID == 7
    elseif categoryKey == "sendCloth" then
        return isTrade and subclassID == 5
    elseif categoryKey == "sendLeather" then
        return isTrade and subclassID == 6
    elseif categoryKey == "sendEnchanting" then
        return isTrade and subclassID == 12
    elseif categoryKey == "sendGems" then
        return (classID == gemClass or classID == 3) or (isTrade and (subclassID == 4 or subclassID == 3))
    elseif categoryKey == "sendElemental" then
        return isTrade and subclassID == 10
    elseif categoryKey == "sendCooking" then
        return isTrade and subclassID == 8
    elseif categoryKey == "sendEngineering" then
        return isTrade and (subclassID == 0 or subclassID == 1 or subclassID == 2 or subclassID == 17)
    elseif categoryKey == "sendInscription" then
        return isTrade and subclassID == 16
    elseif categoryKey == "sendComprehension" then
        return IsComprehensionScroll(itemID, itemLink, classID, subclassID)
    end
    return false
end

-- ── recipe-usage fallback for generic trade goods ─────────────────────────────
-- trade goods subclass 11 ("other": dyes, bleach, flux, vials, spices, salt) has no
-- profession hint. route these by which professions consume them in the recipe db.
local TRADE_OTHER_SUBCLASS = 11
local SKILL_TO_CATEGORY = {
    [197] = "sendCloth",       -- tailoring
    [165] = "sendLeather",     -- leatherworking
    [164] = "sendOre",         -- blacksmithing
    [202] = "sendEngineering", -- engineering
    [333] = "sendEnchanting",  -- enchanting
    [171] = "sendHerbs",       -- alchemy
    [185] = "sendCooking",     -- cooking
    [773] = "sendInscription", -- inscription
    [755] = "sendGems",        -- jewelcrafting
}
-- tie-break order when two professions use a reagent equally often
local CATEGORY_RANK = {
    sendCloth = 1, sendLeather = 2, sendOre = 3, sendEngineering = 4, sendEnchanting = 5,
    sendHerbs = 6, sendCooking = 7, sendInscription = 8, sendGems = 9,
}

local reagentCounts   -- itemID -> { [catKey] = recipeCount }, built lazily (false = no db)
local reagentSorted = {} -- itemID -> { catKey, ... } ordered by usage, memoized per item

local function BuildReagentCounts()
    reagentCounts = false
    local db = sfui.recipes_camelot
    local raw = db and db._raw
    if type(raw) ~= "table" then return end

    local counts = {}
    for _, rec in pairs(raw) do
        local catKey = SKILL_TO_CATEGORY[rec[2]]
        local reagentStr = rec[8]
        if catKey and type(reagentStr) == "string" then
            for idStr in reagentStr:gmatch("(%d+):?%d*") do
                local id = tonumber(idStr)
                local c = counts[id]
                if not c then
                    c = {}
                    counts[id] = c
                end
                c[catKey] = (c[catKey] or 0) + 1
            end
        end
    end
    reagentCounts = counts
end

--- Categories whose professions consume this item, most recipes first
--- @param itemID number
--- @return table|nil catKeys
function mail.GetReagentCategories(itemID)
    if not itemID then return nil end
    local cached = reagentSorted[itemID]
    if cached ~= nil then return cached or nil end

    if reagentCounts == nil then BuildReagentCounts() end
    local c = reagentCounts and reagentCounts[itemID]
    if not c then
        reagentSorted[itemID] = false
        return nil
    end

    local list = {}
    for catKey in pairs(c) do list[#list + 1] = catKey end
    table.sort(list, function(a, b)
        if c[a] ~= c[b] then return c[a] > c[b] end
        return CATEGORY_RANK[a] < CATEGORY_RANK[b]
    end)
    reagentSorted[itemID] = list
    return list
end

--- Find destination recipient for a specific bag item
--- @param bag number
local ROUTING_CAT_KEYS = {
    "sendHerbs",
    "sendOre",
    "sendCloth",
    "sendLeather",
    "sendEnchanting",
    "sendGems",
    "sendElemental",
    "sendCooking",
    "sendEngineering",
    "sendInscription",
    "sendComprehension",
}

--- @param slot number
--- @param candidateAlts table? Optional pre-fetched `mail.GetAlts(false)` list
--- @param preloadedInfo table? Optional pre-fetched `C_Container.GetContainerItemInfo(bag, slot)`
--- @param ignoreEnabledCheck boolean? When true, evaluates routing rules even if auto-mail checkbox is off
--- @return string|nil targetGUID, string|nil targetName, string|nil targetRealm, string|nil reason, table|nil info
function mail.FindDestinationForBagItem(bag, slot, candidateAlts, preloadedInfo, ignoreEnabledCheck)
    if not C_Container then return nil end
    local settings = mail.GetSettings()
    if not ignoreEnabledCheck and not settings.enabled then return nil end

    local info = preloadedInfo or C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID or not info.hyperlink then return nil end

    -- Soulbound items can never be mailed or traded
    if info.isBound then return nil end

    local itemID = info.itemID

    -- Check if item is explicitly blacklisted
    if mail.IsItemIgnored(itemID) then return nil end

    local itemLink = info.hyperlink
    local myGUID = UnitGUID("player")
    local _, _, quality, _, _, _, _, _, _, _, _, classID, subclassID, bindType = GetItemInfo(itemLink)

    -- Instant lookup fallback if item info is still caching from server
    if (not classID or not subclassID) and GetItemInfoInstant then
        local _, _, _, _, _, cID, scID = GetItemInfoInstant(itemID)
        classID = classID or cID
        subclassID = subclassID or scID
    end

    candidateAlts = candidateAlts or mail.GetAlts(false)

    -- 1. Explicit item assigned directly to an alt
    for _, alt in ipairs(candidateAlts) do
        local route = settings.routes and settings.routes[alt.guid]
        if route and route.items and route.items[itemID] then
            return alt.guid, alt.name, alt.realm, "assigned_item", info
        end
    end

    -- 2. Category match (herbs, ore, cloth, leather, enchanting, gems, elemental, cooking, engineering, inscription, comprehension)
    if classID and subclassID then
        for _, alt in ipairs(candidateAlts) do
            local route = settings.routes and settings.routes[alt.guid]
            if route then
                for _, catKey in ipairs(ROUTING_CAT_KEYS) do
                    if route[catKey] and MatchesTradeskillCategory(classID, subclassID, catKey, itemID, itemLink) then
                        return alt.guid, alt.name, alt.realm, "category_" .. catKey, info
                    end
                end
            end
        end

        -- 2b. generic trade goods ("other"): route to the alt handling the profession that uses it most
        local tradeClass = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7
        if (classID == tradeClass or classID == 7) and subclassID == TRADE_OTHER_SUBCLASS then
            local catList = mail.GetReagentCategories(itemID)
            if catList then
                for _, catKey in ipairs(catList) do
                    for _, alt in ipairs(candidateAlts) do
                        local route = settings.routes and settings.routes[alt.guid]
                        if route and route[catKey] then
                            return alt.guid, alt.name, alt.realm, "category_" .. catKey, info
                        end
                    end
                end
            end
        end
    end

    -- 3. Disenchant BoE rule
    if settings.disenchanterGUID and settings.disenchanterGUID ~= myGUID then
        if mail.IsDisenchantableBoE(itemID, itemLink, classID, subclassID, quality, bindType) then
            local alt = SfuiDB.alts and SfuiDB.alts[settings.disenchanterGUID]
            if alt and alt.name then
                return settings.disenchanterGUID, alt.name, alt.realm, "disenchant_boe", info
            end
        end
    end

    return nil
end

--- Scan player bags and build a pending mail manifest
--- @param targetGUID string? Optional alt GUID to filter dispatch to a single recipient
--- @return table manifest, number totalItems, number recipientCount
function mail.ScanPendingMail(targetGUID)
    local manifest = {}
    local totalItems = 0
    local recipientCount = 0

    if not C_Container then return manifest, 0, 0 end
    local candidateAlts = mail.GetAlts(false)

    -- Scan backpack (0), bags (1-4) and reagent bag (5) when present
    for bag = 0, mail.GetLastBagIndex() do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local destGUID, destName, destRealm, reason, itemInfo = mail.FindDestinationForBagItem(bag, slot, candidateAlts)
            if destGUID and destName and (not targetGUID or destGUID == targetGUID) then
                local info = itemInfo or C_Container.GetContainerItemInfo(bag, slot)
                if info then
                    if not manifest[destGUID] then
                        local altData = SfuiDB.alts and SfuiDB.alts[destGUID]
                        manifest[destGUID] = {
                            guid        = destGUID,
                            name        = destName,
                            surname     = altData and altData.surname,
                            realm       = destRealm or (GetRealmName and GetRealmName()) or "",
                            class       = altData and altData.class or "WARRIOR",
                            level       = altData and altData.level or 1,
                            iconsMarkup = mail.GetAltProfessionIconsMarkup(destGUID, 12),
                            professions = mail.GetAltProfessions(destGUID),
                            items       = {},
                        }
                        recipientCount = recipientCount + 1
                    end

                    table.insert(manifest[destGUID].items, {
                        bag      = bag,
                        slot     = slot,
                        itemID   = info.itemID,
                        link     = info.hyperlink,
                        texture  = info.iconFileID,
                        count    = info.stackCount or 1,
                        quality  = info.quality or 1,
                        reason   = reason,
                    })
                    totalItems = totalItems + 1
                end
            end
        end
    end

    return manifest, totalItems, recipientCount
end

--- Record inbox mail count, expiration time, and gold for the current character
function mail.RecordMailboxStatus()
    local myGUID = UnitGUID("player")
    if not myGUID or not SfuiDB or not SfuiDB.alts then return end
    local alt = SfuiDB.alts[myGUID]
    if not alt then return end

    local GetInboxNumItems = _G.GetInboxNumItems
    local GetInboxHeaderInfo = _G.GetInboxHeaderInfo
    local numItems = (GetInboxNumItems and GetInboxNumItems()) or 0

    local minDays = 999
    local totalMoney = 0
    for i = 1, numItems do
        if GetInboxHeaderInfo then
            local _, _, _, _, money, _, daysLeft = GetInboxHeaderInfo(i)
            if daysLeft and daysLeft < minDays then
                minDays = daysLeft
            end
            if money and money > 0 then
                totalMoney = totalMoney + money
            end
        end
    end

    alt.inboxCount = numItems
    alt.inboxDaysLeft = (numItems > 0 and minDays < 999) and minDays or 30
    alt.inboxMoney = totalMoney
    alt.inboxLastVisit = (_G.GetServerTime and _G.GetServerTime()) or time()
end

