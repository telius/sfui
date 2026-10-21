local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}

local g      = sfui.config
local common = sfui.common
local cfg    = g.recipes or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/alts/recipes.lua
--  Cross-Expansion Recipe Knowledge & Eligibility Tracker
--
--  Supports: Retail (Midnight 12.x / TWW 11.x), Camelot (Classic Forever 1.60.x),
--  and Classic Era.
--
--  Tracks which alts already know a recipe, and which alts possess the required
--  profession (and minimum skill rank) to learn it.
-- ══════════════════════════════════════════════════════════════════════════════

-- Localized APIs
local CreateFrame                   = _G.CreateFrame
local UnitGUID                      = _G.UnitGUID
local UnitName                      = _G.UnitName
local UnitClass                     = _G.UnitClass
local GetRealmName                  = _G.GetNormalizedRealmName or _G.GetRealmName
local C_Item                        = _G.C_Item or {}
local C_Item_GetItemInfo            = sfui.common.get_item_info
local C_Item_GetItemInfoInstant     = sfui.common.get_item_instant_info
local C_Item_GetItemSubClassInfo    = C_Item.GetItemSubClassInfo or _G.GetItemSubClassInfo
local C_Item_RequestLoadItemDataByID= C_Item.RequestLoadItemDataByID
local C_TooltipInfo                 = _G.C_TooltipInfo
local TooltipDataProcessor          = _G.TooltipDataProcessor
local TooltipUtil                   = _G.TooltipUtil
local C_ClassColor                  = _G.C_ClassColor
local RAID_CLASS_COLORS             = _G.RAID_CLASS_COLORS
local Enum                          = _G.Enum or {}
local ITEM_SPELL_KNOWN              = _G.ITEM_SPELL_KNOWN or "Already known"
local ITEM_MIN_SKILL                = _G.ITEM_MIN_SKILL or "Requires %s (%d)"
local ITEM_REQ_SKILL                = _G.ITEM_REQ_SKILL or "Requires %s"
local C_Timer                       = _G.C_Timer
local table                         = _G.table
local string                        = _G.string
local pairs                         = _G.pairs
local ipairs                        = _G.ipairs
local select                        = _G.select
local tonumber                      = _G.tonumber
local type                          = _G.type
local wipe                          = _G.wipe
local InCombatLockdown               = _G.InCombatLockdown
local GameTooltip                   = sfui.common.get_tooltip()
local ItemRefTooltip                = _G.ItemRefTooltip

-- Recipe item class constant (9 = Recipe)
local ITEM_CLASS_RECIPE = (Enum.ItemClass and Enum.ItemClass.Recipe) or 9

-- Map of Recipe Subclass IDs to English profession names and standard skillLine IDs
local RECIPE_SUBCLASS_MAP = {
    [1]  = { name = "Leatherworking", skillID = 165 },
    [2]  = { name = "Tailoring",      skillID = 197 },
    [3]  = { name = "Engineering",    skillID = 202 },
    [4]  = { name = "Blacksmithing",  skillID = 164 },
    [5]  = { name = "Cooking",        skillID = 185, secKey = "cooking" },
    [6]  = { name = "Alchemy",        skillID = 171 },
    [7]  = { name = "First Aid",      skillID = 129, secKey = "firstAid" },
    [8]  = { name = "Enchanting",     skillID = 333 },
    [9]  = { name = "Fishing",        skillID = 356, secKey = "fishing" },
    [10] = { name = "Jewelcrafting",  skillID = 755 },
    [11] = { name = "Inscription",   skillID = 773 },
}

local SKILL_ID_TO_NAME = {
    [165] = "Leatherworking",
    [197] = "Tailoring",
    [202] = "Engineering",
    [164] = "Blacksmithing",
    [185] = "Cooking",
    [171] = "Alchemy",
    [129] = "First Aid",
    [333] = "Enchanting",
    [356] = "Fishing",
    [755] = "Jewelcrafting",
    [773] = "Inscription",
}

-- Safe string trimming
local function StrTrim(s)
    if not s then return "" end
    if _G.strtrim then return _G.strtrim(s) end
    return s:match("^%s*(.-)%s*$") or s
end

-- Escape special regex characters in pattern strings
local function EscapePattern(s)
    if not s then return "" end
    return s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

-- Build regex patterns for skill requirement extraction
local minSkillPattern
if ITEM_MIN_SKILL then
    local p = EscapePattern(ITEM_MIN_SKILL)
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    minSkillPattern = "^" .. p .. "$"
end

local reqSkillPattern
if ITEM_REQ_SKILL then
    local p = EscapePattern(ITEM_REQ_SKILL)
    p = p:gsub("%%%%s", "(.-)")
    reqSkillPattern = "^" .. p .. "$"
end

-- Active Player Context
local myGUID = nil
local myRealm = nil
local myName = nil
local myClass = nil

local hasSanitizedRecipeDB = false
local function SanitizeRecipeDB()
    if hasSanitizedRecipeDB then return end
    if SfuiDB and SfuiDB.recipes then
        hasSanitizedRecipeDB = true
        for k in pairs(SfuiDB.recipes) do
            if type(k) ~= "number" then
                SfuiDB.recipes[k] = nil
            end
        end
    end
end

local function EnsurePlayerContext()
    SanitizeRecipeDB()
    if not myGUID then
        myGUID = UnitGUID("player")
    end
    if not myRealm then
        myRealm = GetRealmName()
    end
    if not myName then
        myName = UnitName("player")
    end
    if not myClass then
        local ec = sfui.common.get_player_class()
        myClass = ec
    end
end

-- ── Fast Caching Tables & Scratch Buffers ─────────────────────────────────────
local isRecipeCache          = {}  -- [itemID] = boolean (immutable item class)
local recipeReqCache         = {}  -- [itemID] = { prof = string, rank = number } (immutable per recipe)
local recipeStatusCache      = {}  -- [itemID] = status string (session cache, invalidated on changes)
local formattedNameCache     = {}  -- [key] = string (memoized class-colored alt names)
local recipeOutputCache      = {}  -- [recipeID] = outputItemID (memoized output item ID)

-- Pre-allocated scratch tables for zero-allocation tooltip rendering
local scratchCrafterList     = {}
local scratchKnownList       = {}
local scratchKnownGUIDs      = {}
local scratchCanLearnList    = {}
local scratchLowSkillList    = {}

local function InvalidateRecipeStatusCache()
    wipe(recipeStatusCache)
end

--- Synchronous, permanent check if itemID is a recipe (O(1) memoized)
--- @param itemID number
--- @return boolean isRecipe
local function IsRecipe(itemID)
    if not itemID then return false end
    local cached = isRecipeCache[itemID]
    if cached ~= nil then return cached end

    local classID
    if C_Item_GetItemInfoInstant then
        classID = select(6, C_Item_GetItemInfoInstant(itemID))
    end
    local result = (classID == ITEM_CLASS_RECIPE)
    isRecipeCache[itemID] = result
    return result
end

--- Extract colored character name (memoized)
local function GetColoredCharacterName(name, className, realm)
    local displayName = name or "Unknown"
    local cacheKey = displayName .. ":" .. (className or "") .. ":" .. (realm or "")
    local cached = formattedNameCache[cacheKey]
    if cached then
        return cached
    end

    local col
    if C_ClassColor and C_ClassColor.GetClassColor and className then
        col = C_ClassColor.GetClassColor(className)
    elseif RAID_CLASS_COLORS and className and RAID_CLASS_COLORS[className] then
        col = RAID_CLASS_COLORS[className]
    end

    local hex = (col and col.GenerateHexColor and col:GenerateHexColor()) or
                (col and string.format("ff%02x%02x%02x", (col.r or 1) * 255, (col.g or 1) * 255, (col.b or 1) * 255)) or
                "ffffffff"

    if realm and realm ~= "" and realm ~= myRealm then
        displayName = string.format("%s-%s", displayName, realm)
    end

    local formatted = string.format("|c%s%s|r", hex, displayName)
    formattedNameCache[cacheKey] = formatted
    return formatted
end

-- ── Tooltip Line Scanner (Universal fallback) ─────────────────────────────────
local scanTooltip = nil
local function GetOrCreateScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "SfuiRecipeScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

--- Scan tooltip lines for an item link or item ID to check if active player knows it
--- @param itemID number
--- @return boolean? isKnown, boolean isReady
local function CheckActivePlayerKnownStatus(itemID)
    EnsurePlayerContext()
    if not itemID or type(itemID) ~= "number" or not IsRecipe(itemID) then return nil, true end

    local _, itemLink = C_Item_GetItemInfo(itemID)
    if not itemLink then
        if C_Item_RequestLoadItemDataByID then
            C_Item_RequestLoadItemDataByID(itemID)
        end
        return nil, false
    end

    -- Method 1: Modern C_TooltipInfo (Retail & Classic Beta / Camelot)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                local leftText = line.leftText
                if leftText and (leftText == ITEM_SPELL_KNOWN or leftText:find(ITEM_SPELL_KNOWN, 1, true)) then
                    return true, true
                end
            end
            return false, true
        end
    end

    -- Method 2: Legacy Hidden Tooltip Scanner (Classic Era fallback)
    local tip = GetOrCreateScanTooltip()
    tip:ClearLines()
    tip:SetHyperlink(itemLink)
    local numLines = tip:NumLines()
    if numLines and numLines > 0 then
        for i = 1, numLines do
            local fontString = _G["SfuiRecipeScanTooltipTextLeft" .. i]
            local leftText = fontString and fontString:GetText()
            if leftText and (leftText == ITEM_SPELL_KNOWN or leftText:find(ITEM_SPELL_KNOWN, 1, true)) then
                return true, true
            end
        end
        return false, true
    end

    return nil, false
end

--- Update active player's recipe state in SfuiDB.recipes
--- @param itemID number
--- @return boolean isSuccess
local function UpdateItem(itemID)
    EnsurePlayerContext()
    if not itemID or type(itemID) ~= "number" or not myRealm or not myGUID then return true end
    if not IsRecipe(itemID) then return true end

    local isKnown, isReady = CheckActivePlayerKnownStatus(itemID)
    if not isReady then
        return false
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.recipes = SfuiDB.recipes or {}
    if type(SfuiDB.recipes[itemID]) ~= "table" then
        SfuiDB.recipes[itemID] = {}
    end
    if type(SfuiDB.recipes[itemID][myRealm]) ~= "table" then
        SfuiDB.recipes[itemID][myRealm] = {}
    end

    if isKnown then
        SfuiDB.recipes[itemID][myRealm][myGUID] = true
    else
        SfuiDB.recipes[itemID][myRealm][myGUID] = nil
    end

    return true
end

-- ── Batched Background Update Loop (Zero hitching) ───────────────────────────
local pendingUpdateQueue = {}
local isUpdateLoopRunning = false
local BATCH_SIZE = 10
local BATCH_DELAY = 0.2

local function ProcessNextBatch()
    if not isUpdateLoopRunning then return end

    local processed = 0
    local hasRemaining = false

    for itemID in pairs(pendingUpdateQueue) do
        if processed < BATCH_SIZE then
            pendingUpdateQueue[itemID] = nil
            UpdateItem(itemID)
            processed = processed + 1
        else
            hasRemaining = true
            break
        end
    end

    if hasRemaining then
        C_Timer.After(BATCH_DELAY, ProcessNextBatch)
    else
        isUpdateLoopRunning = false
    end
end

--- Request an asynchronous, non-blocking scan of all stored recipe items
local function RequestUpdateAllItems()
    EnsurePlayerContext()
    if not SfuiDB or not SfuiDB.recipes then return end

    wipe(pendingUpdateQueue)
    for itemID, data in pairs(SfuiDB.recipes) do
        if type(itemID) == "number" and type(data) == "table" and IsRecipe(itemID) then
            pendingUpdateQueue[itemID] = true
        elseif type(itemID) ~= "number" then
            SfuiDB.recipes[itemID] = nil
        end
    end

    if not isUpdateLoopRunning and next(pendingUpdateQueue) then
        isUpdateLoopRunning = true
        C_Timer.After(BATCH_DELAY, ProcessNextBatch)
    end
end

-- ── Tooltip Line Parsing for Requirements ─────────────────────────────────────
--- Extracts required profession name and skill rank from tooltip (memoized per itemID)
--- @param itemID number?
--- @param itemLink string?
--- @param subclassID number?
--- @return string? profName, number? reqRank
local function ExtractRecipeRequirement(itemID, itemLink, subclassID)
    if not itemID then return nil, nil end
    local cached = recipeReqCache[itemID]
    if cached then
        return cached.prof, cached.rank
    end

    local reqProf, reqRank = nil, nil

    if itemLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                local text = line.leftText
                if text then
                    if minSkillPattern then
                        local p, r = text:match(minSkillPattern)
                        if p and r then
                            reqProf = StrTrim(p)
                            reqRank = tonumber(r)
                            break
                        end
                    end
                    if not reqProf and reqSkillPattern then
                        local p = text:match(reqSkillPattern)
                        if p then
                            reqProf = StrTrim(p)
                        end
                    end
                    -- Generic fallback pattern for "Requires <Profession> (<Rank>)"
                    if not reqProf then
                        local p, r = text:match("Requires%s+(.-)%s*%(?(%d+)%)?")
                        if p and r then
                            reqProf = StrTrim(p)
                            reqRank = tonumber(r)
                            break
                        end
                    end
                end
            end
        end
    end

    -- If no explicit requirement text was parsed, derive profession from recipe subclass
    if not reqProf and subclassID and subclassID > 0 then
        if C_Item_GetItemSubClassInfo then
            reqProf = C_Item_GetItemSubClassInfo(ITEM_CLASS_RECIPE, subclassID)
        end
        if not reqProf and RECIPE_SUBCLASS_MAP[subclassID] then
            reqProf = RECIPE_SUBCLASS_MAP[subclassID].name
        end
    end

    if reqProf or itemLink then
        recipeReqCache[itemID] = { prof = reqProf, rank = reqRank }
    end

    return reqProf, reqRank
end

-- ── Check Alt Eligibility ─────────────────────────────────────────────────────
--- Check if an alt possesses the required profession and skill rank
--- @param altData table
--- @param reqProf string?
--- @param reqRank number?
--- @param subclassID number?
--- @param explicitSkillID number?
--- @return boolean hasProf, boolean meetsRank, number? currentRank
local function CheckAltEligibility(altData, reqProf, reqRank, subclassID, explicitSkillID)
    if not altData then return false, false, nil end

    local profKey = subclassID and RECIPE_SUBCLASS_MAP[subclassID] and RECIPE_SUBCLASS_MAP[subclassID].secKey
    local skillID = explicitSkillID or (subclassID and RECIPE_SUBCLASS_MAP[subclassID] and RECIPE_SUBCLASS_MAP[subclassID].skillID)
    if not reqProf and skillID and SKILL_ID_TO_NAME[skillID] then
        reqProf = SKILL_ID_TO_NAME[skillID]
    end
    local subclassName = (subclassID and RECIPE_SUBCLASS_MAP[subclassID] and RECIPE_SUBCLASS_MAP[subclassID].name) or reqProf

    -- 1. Check altData.professions (Classic/Camelot & Standardized Retail)
    if altData.professions then
        local entry = (subclassName and altData.professions[subclassName]) or
                      (reqProf and altData.professions[reqProf]) or
                      (profKey and altData.professions[profKey])

        if not entry and skillID then
            for _, p in pairs(altData.professions) do
                if type(p) == "table" and (p.skillID == skillID or (p.name and subclassName and p.name:lower() == subclassName:lower())) then
                    entry = p
                    break
                end
            end
            if not entry and altData.professions.primaries then
                for _, p in ipairs(altData.professions.primaries) do
                    if type(p) == "table" and (p.skillID == skillID or (p.name and subclassName and p.name:lower() == subclassName:lower())) then
                        entry = p
                        break
                    end
                end
            end
        end

        if entry then
            local rank = entry.rank or entry.skill or 0
            if not reqRank or rank >= reqRank then
                return true, true, rank
            else
                return true, false, rank
            end
        end
    end

    -- 2. Check altData.profKP (Retail specific)
    if altData.profKP then
        for sLine, pData in pairs(altData.profKP) do
            if type(pData) == "table" then
                local pName = pData.name
                if (pName and subclassName and pName:lower() == subclassName:lower()) or
                   (pName and reqProf and pName:lower() == reqProf:lower()) or
                   (skillID and sLine == skillID) then
                    local rank = pData.skill or 0
                    if not reqRank or rank >= reqRank then
                        return true, true, rank
                    else
                        return true, false, rank
                    end
                end
            end
        end
    end

    return false, false, nil
end

-- ── Recipe Status & Color Coding ──────────────────────────────────────────────
sfui.recipes.STATUS_COLORS = {
    KNOWN_CURRENT     = { r = 0.20, g = 0.70, b = 1.00, hex = "33b2ff" }, -- Cyan
    KNOWN_ALT         = { r = 0.70, g = 0.30, b = 1.00, hex = "b34dff" }, -- Purple
    CAN_LEARN_CURRENT = { r = 0.20, g = 1.00, b = 0.40, hex = "33ff66" }, -- Green
    CAN_LEARN_ALT     = { r = 1.00, g = 0.82, b = 0.00, hex = "ffd100" }, -- Gold
    UNLEARNABLE       = { r = 1.00, g = 0.30, b = 0.30, hex = "ff4d4d" }, -- Dim red
}
local STATUS_COLORS = sfui.recipes.STATUS_COLORS

--- Get recipe learned and learnable status across current character and alts
--- @param itemID number
--- @return string? status, table? color
local function GetRecipeStatus(itemID)
    if not itemID then return nil, nil end
    if not IsRecipe(itemID) then return nil, nil end

    local cached = recipeStatusCache[itemID]
    if cached then
        return cached, STATUS_COLORS[cached]
    end

    EnsurePlayerContext()

    local subclassID
    if C_Item_GetItemInfoInstant then
        subclassID = select(7, C_Item_GetItemInfoInstant(itemID))
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.recipes = SfuiDB.recipes or {}
    local recipeRecord = (type(SfuiDB.recipes[itemID]) == "table") and SfuiDB.recipes[itemID] or nil

    -- 1. Check if current character knows it
    local isKnownCurrent = false
    if recipeRecord and myRealm and type(recipeRecord[myRealm]) == "table" and recipeRecord[myRealm][myGUID] then
        isKnownCurrent = true
    else
        local isKnown, isReady = CheckActivePlayerKnownStatus(itemID)
        if isReady and isKnown then
            isKnownCurrent = true
            if myRealm and myGUID then
                if type(SfuiDB.recipes[itemID]) ~= "table" then
                    SfuiDB.recipes[itemID] = {}
                end
                if type(SfuiDB.recipes[itemID][myRealm]) ~= "table" then
                    SfuiDB.recipes[itemID][myRealm] = {}
                end
                SfuiDB.recipes[itemID][myRealm][myGUID] = true
            end
        end
    end

    if isKnownCurrent then
        recipeStatusCache[itemID] = "KNOWN_CURRENT"
        return "KNOWN_CURRENT", STATUS_COLORS.KNOWN_CURRENT
    end

    -- 2. Check if any alt knows it
    local isKnownAlt = false
    if recipeRecord then
        for realm, realmList in pairs(recipeRecord) do
            if type(realmList) == "table" then
                for guid, known in pairs(realmList) do
                    if known and guid ~= myGUID then
                        isKnownAlt = true
                        break
                    end
                end
            end
            if isKnownAlt then break end
        end
    end

    if isKnownAlt then
        recipeStatusCache[itemID] = "KNOWN_ALT"
        return "KNOWN_ALT", STATUS_COLORS.KNOWN_ALT
    end

    -- 3. Check if current player or any alt can learn it
    local _, itemLink = C_Item_GetItemInfo(itemID)
    local reqProf, reqRank = ExtractRecipeRequirement(itemID, itemLink, subclassID)

    if not itemLink and not reqProf then
        -- Item data not yet cached by client; return nil to avoid premature unlearnable tint
        return nil, nil
    end

    -- Current player eligibility
    if SfuiDB.alts and myGUID and SfuiDB.alts[myGUID] then
        local hasProf, meetsRank = CheckAltEligibility(SfuiDB.alts[myGUID], reqProf, reqRank, subclassID)
        if hasProf and meetsRank then
            recipeStatusCache[itemID] = "CAN_LEARN_CURRENT"
            return "CAN_LEARN_CURRENT", STATUS_COLORS.CAN_LEARN_CURRENT
        end
    end

    -- Alts eligibility
    local altCanLearn = false
    if SfuiDB.alts then
        for guid, altData in pairs(SfuiDB.alts) do
            if guid ~= myGUID then
                local hasProf, meetsRank = CheckAltEligibility(altData, reqProf, reqRank, subclassID)
                if hasProf and meetsRank then
                    altCanLearn = true
                    break
                end
            end
        end
    end

    if altCanLearn then
        recipeStatusCache[itemID] = "CAN_LEARN_ALT"
        return "CAN_LEARN_ALT", STATUS_COLORS.CAN_LEARN_ALT
    end

    recipeStatusCache[itemID] = "UNLEARNABLE"
    return "UNLEARNABLE", STATUS_COLORS.UNLEARNABLE
end

-- ── Reverse Crafting Scanner ("Who Can Craft This?") ──────────────────────────
local isTradeSkillScanPending = false
local lastTradeSkillScanTime = 0

local function ScanCurrentTradeSkills(force)
    EnsurePlayerContext()
    if not myGUID then return end

    local now = (GetTime and GetTime()) or 0
    if not force and (now - lastTradeSkillScanTime < 2.0) then
        return
    end
    lastTradeSkillScanTime = now

    SfuiDB = SfuiDB or {}
    SfuiDB.crafts = SfuiDB.crafts or {}
    SfuiDB.recipes = SfuiDB.recipes or {}

    local function RecordKnownRecipe(spellID)
        if not spellID or not myRealm or not myGUID then return end
        SfuiDB.recipes[spellID] = SfuiDB.recipes[spellID] or {}
        SfuiDB.recipes[spellID][myRealm] = SfuiDB.recipes[spellID][myRealm] or {}
        SfuiDB.recipes[spellID][myRealm][myGUID] = true

        if sfui.recipes_camelot and sfui.recipes_camelot.recipes then
            local r = sfui.recipes_camelot.recipes[spellID]
            if r and r.recipeItemID then
                SfuiDB.recipes[r.recipeItemID] = SfuiDB.recipes[r.recipeItemID] or {}
                SfuiDB.recipes[r.recipeItemID][myRealm] = SfuiDB.recipes[r.recipeItemID][myRealm] or {}
                SfuiDB.recipes[r.recipeItemID][myRealm][myGUID] = true
            end
        end
    end

    -- 1. Modern C_TradeSkillUI (Retail & Camelot)
    if C_TradeSkillUI and C_TradeSkillUI.GetFilteredRecipeIDs then
        local recipeIDs = C_TradeSkillUI.GetFilteredRecipeIDs()
        if recipeIDs and #recipeIDs > 0 then
            for _, recipeID in ipairs(recipeIDs) do
                local recipeInfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
                if recipeInfo and recipeInfo.learned then
                    RecordKnownRecipe(recipeID)

                    -- Memoized primary output item
                    local outItemID = recipeOutputCache[recipeID]
                    if not outItemID then
                        if C_TradeSkillUI.GetRecipeOutputItemData then
                            local outData = C_TradeSkillUI.GetRecipeOutputItemData(recipeID)
                            outItemID = outData and outData.itemID
                            if not outItemID and outData and outData.hyperlink then
                                outItemID = tonumber(outData.hyperlink:match("item:(%d+)"))
                            end
                        end
                        if not outItemID and C_TradeSkillUI.GetRecipeItemLink then
                            local link = C_TradeSkillUI.GetRecipeItemLink(recipeID)
                            if link then
                                outItemID = tonumber(link:match("item:(%d+)"))
                            end
                        end
                        if outItemID then
                            recipeOutputCache[recipeID] = outItemID
                        end
                    end
                    if outItemID then
                        SfuiDB.crafts[outItemID] = SfuiDB.crafts[outItemID] or {}
                        SfuiDB.crafts[outItemID][myGUID] = true
                    end

                    -- Multiple quality tiers (TWW / Midnight tiers 1, 2, 3)
                    if C_TradeSkillUI.GetRecipeQualityItemIDs then
                        local qIDs = C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)
                        if qIDs then
                            for _, qItemID in ipairs(qIDs) do
                                if qItemID and qItemID > 0 then
                                    SfuiDB.crafts[qItemID] = SfuiDB.crafts[qItemID] or {}
                                    SfuiDB.crafts[qItemID][myGUID] = true
                                end
                            end
                        end
                    end
                end
            end
            InvalidateRecipeStatusCache()
            return
        end
    end

    -- 2. Legacy TradeSkill (Classic Era)
    if _G.GetNumTradeSkills and _G.GetTradeSkillItemLink then
        local num = _G.GetNumTradeSkills()
        for i = 1, num do
            local _, skillType = _G.GetTradeSkillInfo(i)
            if skillType ~= "header" and skillType ~= "subheader" then
                if _G.GetTradeSkillRecipeLink then
                    local rLink = _G.GetTradeSkillRecipeLink(i)
                    if rLink then
                        local sID = tonumber(rLink:match("spell:(%d+)"))
                        if sID then
                            RecordKnownRecipe(sID)
                        end
                    end
                end

                local link = _G.GetTradeSkillItemLink(i)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID then
                        SfuiDB.crafts[itemID] = SfuiDB.crafts[itemID] or {}
                        SfuiDB.crafts[itemID][myGUID] = true
                    end
                end
            end
        end
    end

    -- 3. Legacy Craft (Classic Era Enchanting)
    if _G.GetNumCrafts and _G.GetCraftItemLink then
        local num = _G.GetNumCrafts()
        for i = 1, num do
            local _, _, craftType = _G.GetCraftInfo(i)
            if craftType ~= "header" then
                if _G.GetCraftRecipeLink then
                    local cLink = _G.GetCraftRecipeLink(i)
                    if cLink then
                        local sID = tonumber(cLink:match("spell:(%d+)"))
                        if sID then
                            RecordKnownRecipe(sID)
                        end
                    end
                end

                local link = _G.GetCraftItemLink(i)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID then
                        SfuiDB.crafts[itemID] = SfuiDB.crafts[itemID] or {}
                        SfuiDB.crafts[itemID][myGUID] = true
                    end
                end
            end
        end
    end

    InvalidateRecipeStatusCache()
end

local function RequestTradeSkillScan(force)
    if isTradeSkillScanPending then return end
    isTradeSkillScanPending = true
    C_Timer.After(0.3, function()
        isTradeSkillScanPending = false
        ScanCurrentTradeSkills(force)
    end)
end

local function PruneOrphanCrafts()
    if not SfuiDB or not SfuiDB.alts then return end

    -- Prune crafts for non-existent alts
    if SfuiDB.crafts then
        for itemID, crafters in pairs(SfuiDB.crafts) do
            if type(crafters) == "table" then
                for guid in pairs(crafters) do
                    if guid ~= myGUID and not SfuiDB.alts[guid] then
                        crafters[guid] = nil
                    end
                end
                if not next(crafters) then
                    SfuiDB.crafts[itemID] = nil
                end
            end
        end
    end

    -- Prune recipes for non-existent alts
    if SfuiDB.recipes then
        for recID, realms in pairs(SfuiDB.recipes) do
            if type(recID) ~= "number" or type(realms) ~= "table" then
                SfuiDB.recipes[recID] = nil
            else
                for realm, guids in pairs(realms) do
                    if type(guids) == "table" then
                        for guid in pairs(guids) do
                            if guid ~= myGUID and not SfuiDB.alts[guid] then
                                guids[guid] = nil
                            end
                        end
                        if not next(guids) then
                            realms[realm] = nil
                        end
                    end
                end
                if not next(realms) then
                    SfuiDB.recipes[recID] = nil
                end
            end
        end
    end
end

-- ── Tooltip Post-Call Handler ─────────────────────────────────────────────────
--- Add cross-alt recipe knowledge and eligibility lines to any tooltip
--- @param tooltip table GameTooltip or custom tooltip frame
--- @param itemOrRecipe number|table itemID or recipe record table
function sfui.recipes.AddAltKnowledgeLines(tooltip, itemOrRecipe)
    if not tooltip or not itemOrRecipe then return end

    EnsurePlayerContext()
    SfuiDB = SfuiDB or {}

    local isExplicitRecipe = (type(itemOrRecipe) == "table")
    local r = isExplicitRecipe and itemOrRecipe or nil
    local itemID = (type(itemOrRecipe) == "number") and itemOrRecipe or (r and (r.recipeItemID or r.output))
    local spellID = r and r.id
    local recipeItemID = r and r.recipeItemID
    local outputItemID = r and r.output

    -- Determine if itemID is an actual recipe scroll (Pattern, Recipe, Plans, Schematic)
    local isRecipeScroll = false
    if itemID then
        isRecipeScroll = IsRecipe(itemID) or (sfui.recipes_camelot and sfui.recipes_camelot.items and sfui.recipes_camelot.items[itemID] ~= nil)
    end

    -- If only itemID is given, perform O(1) lookup in pre-indexed sfui.recipes_camelot maps
    if not r and itemID and sfui.recipes_camelot then
        if isRecipeScroll then
            local sID = sfui.recipes_camelot.items and sfui.recipes_camelot.items[itemID]
            if sID and sfui.recipes_camelot.recipes then
                r = sfui.recipes_camelot.recipes[sID]
                if r then
                    spellID = r.id
                    recipeItemID = r.recipeItemID
                    outputItemID = r.output
                end
            end
        else
            -- Crafted output item: do not treat as recipe record, but retrieve outputItemID / spellID if needed for crafting lookup
            local sID = sfui.recipes_camelot.outputs and sfui.recipes_camelot.outputs[itemID]
            if sID and sfui.recipes_camelot.recipes then
                local outRec = sfui.recipes_camelot.recipes[sID]
                if outRec then
                    spellID = outRec.id
                    outputItemID = outRec.output
                end
            end
        end
    end

    local skillID = r and r.skillID
    local minSkill = r and (r.minSkill or (r.colors and r.colors[1]))
    local profName = skillID and SKILL_ID_TO_NAME[skillID]
    local subclassID = nil

    if itemID and not profName then
        if C_Item_GetItemInfoInstant then
            subclassID = select(7, C_Item_GetItemInfoInstant(itemID))
        end
        local _, itemLink = C_Item_GetItemInfo(itemID)
        profName, minSkill = ExtractRecipeRequirement(itemID, itemLink, subclassID)
    end

    if itemID and not subclassID and C_Item_GetItemInfoInstant then
        subclassID = select(7, C_Item_GetItemInfoInstant(itemID))
    end
    if not skillID and subclassID and RECIPE_SUBCLASS_MAP[subclassID] then
        skillID = RECIPE_SUBCLASS_MAP[subclassID].skillID
    end
    if not profName and skillID and SKILL_ID_TO_NAME[skillID] then
        profName = SKILL_ID_TO_NAME[skillID]
    end

    local maxAlts = SfuiDB.recipesMaxAlts or 4
    local showKnown = (SfuiDB.recipesShowKnown ~= false)
    local showCanLearn = (SfuiDB.recipesShowCanLearn ~= false)
    local showNeedsSkill = (SfuiDB.recipesShowNeedsSkill ~= false) and showCanLearn
    local showCraftable = (SfuiDB.recipesShowCraftable ~= false)

    -- Do not show "needs skill" for cooking (skillID 185 / subclassID 5) and first aid (skillID 129 / subclassID 7)
    -- to prevent tooltip bloat across characters since every character can learn these secondary skills
    local isSecondaryCommon = (skillID == 185 or skillID == 129 or subclassID == 5 or subclassID == 7)
    if not isSecondaryCommon and profName then
        local pLower = profName:lower()
        if pLower == "cooking" or pLower == "first aid" then
            isSecondaryCommon = true
        end
    end
    if not isSecondaryCommon and profName and C_Item_GetItemSubClassInfo then
        local locCooking = C_Item_GetItemSubClassInfo(ITEM_CLASS_RECIPE, 5)
        local locFirstAid = C_Item_GetItemSubClassInfo(ITEM_CLASS_RECIPE, 7)
        if (locCooking and profName == locCooking) or (locFirstAid and profName == locFirstAid) then
            isSecondaryCommon = true
        end
    end
    if isSecondaryCommon then
        showNeedsSkill = false
    end

    local addedSpacing = false
    local function AddLine(...)
        if not addedSpacing then
            tooltip:AddLine(" ")
            addedSpacing = true
        end
        tooltip:AddLine(...)
    end

    -- 1. Reverse Crafting Lookup ("Who Can Craft This?")
    -- Only show "craftable by:" if hovering a crafted item directly (not a recipe scroll or recipe row)
    local craftTarget = outputItemID or itemID
    if showCraftable and (not isExplicitRecipe) and (not isRecipeScroll) and craftTarget and SfuiDB.crafts and SfuiDB.crafts[craftTarget] then
        wipe(scratchCrafterList)
        for guid, canCraft in pairs(SfuiDB.crafts[craftTarget]) do
            if canCraft then
                local alt = SfuiDB.alts and SfuiDB.alts[guid]
                local name = (alt and alt.name) or (guid == myGUID and myName)
                local className = (alt and alt.class) or (guid == myGUID and myClass)
                local realm = (alt and alt.realm) or (guid == myGUID and myRealm)
                if name then
                    table.insert(scratchCrafterList, GetColoredCharacterName(name, className, realm))
                end
            end
        end

        local totalCrafters = #scratchCrafterList
        if totalCrafters > 0 then
            local text = ""
            for i = 1, math.min(totalCrafters, maxAlts) do
                text = (text == "") and scratchCrafterList[i] or (text .. ", " .. scratchCrafterList[i])
            end
            if totalCrafters > maxAlts then
                text = string.format("%s, |cffaaaaaa+%d more|r", text, totalCrafters - maxAlts)
            end
            AddLine("|cffffaa00craftable by:|r " .. text, 1, 1, 1, true)
        end
    end

    -- 2. Recipe Knowledge ("Known alts" & "Can learn")
    local isRecipeItem = isExplicitRecipe or isRecipeScroll
    if not isRecipeItem then
        return
    end

    wipe(scratchKnownList)
    wipe(scratchKnownGUIDs)

    -- A. From SfuiDB.crafts (crafters of output item)
    if craftTarget and SfuiDB.crafts and SfuiDB.crafts[craftTarget] then
        for guid, canCraft in pairs(SfuiDB.crafts[craftTarget]) do
            if canCraft and guid ~= myGUID then
                scratchKnownGUIDs[guid] = true
            end
        end
    end

    -- B. From SfuiDB.recipes (recipe itemID or spellID)
    local checkIDs = { recipeItemID, itemID, spellID }
    if SfuiDB.recipes then
        for _, id in ipairs(checkIDs) do
            if id and SfuiDB.recipes[id] then
                for realm, realmList in pairs(SfuiDB.recipes[id]) do
                    if type(realmList) == "table" then
                        for guid, isKnown in pairs(realmList) do
                            if isKnown and guid ~= myGUID then
                                scratchKnownGUIDs[guid] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- C. Base recipes (minSkill <= 0): any alt with this profession knows it automatically
    if minSkill and minSkill <= 0 and (skillID or profName) and SfuiDB.alts then
        for guid, altData in pairs(SfuiDB.alts) do
            if guid ~= myGUID and not scratchKnownGUIDs[guid] then
                local hasProf = CheckAltEligibility(altData, profName, 0, subclassID, skillID)
                if hasProf then
                    scratchKnownGUIDs[guid] = true
                end
            end
        end
    end

    -- Format Known Alts
    for guid in pairs(scratchKnownGUIDs) do
        local alt = SfuiDB.alts and SfuiDB.alts[guid]
        if alt and alt.name then
            table.insert(scratchKnownList, GetColoredCharacterName(alt.name, alt.class, alt.realm))
        end
    end

    -- 3. Gather Eligible "Can Learn" & "Needs Skill" Alts
    wipe(scratchCanLearnList)
    wipe(scratchLowSkillList)

    if (showCanLearn or showNeedsSkill) and SfuiDB.alts and (profName or skillID or (subclassID and subclassID > 0)) then
        for guid, altData in pairs(SfuiDB.alts) do
            if guid ~= myGUID and not scratchKnownGUIDs[guid] then
                local hasProf, meetsRank, currentRank = CheckAltEligibility(altData, profName, minSkill, subclassID, skillID)
                if hasProf then
                    local formatted = GetColoredCharacterName(altData.name, altData.class, altData.realm)
                    if meetsRank then
                        if showCanLearn then
                            table.insert(scratchCanLearnList, formatted)
                        end
                    elseif showNeedsSkill then
                        local lowFormatted = string.format("%s |cff888888(%d/%d)|r", formatted, currentRank or 0, minSkill or 0)
                        table.insert(scratchLowSkillList, lowFormatted)
                    end
                end
            end
        end
    end

    -- Render Tooltip Lines
    local totalKnown = #scratchKnownList
    if showKnown and totalKnown > 0 then
        local text = ""
        for i = 1, math.min(totalKnown, maxAlts) do
            text = (text == "") and scratchKnownList[i] or (text .. ", " .. scratchKnownList[i])
        end
        if totalKnown > maxAlts then
            text = string.format("%s, |cffaaaaaa+%d more|r", text, totalKnown - maxAlts)
        end
        AddLine("|cff00ccffknown alts:|r " .. text, 1, 1, 1, true)
    end

    local totalCanLearn = #scratchCanLearnList
    if showCanLearn and totalCanLearn > 0 then
        local text = ""
        for i = 1, math.min(totalCanLearn, maxAlts) do
            text = (text == "") and scratchCanLearnList[i] or (text .. ", " .. scratchCanLearnList[i])
        end
        if totalCanLearn > maxAlts then
            text = string.format("%s, |cffaaaaaa+%d more|r", text, totalCanLearn - maxAlts)
        end
        AddLine("|cff00ff88can learn:|r " .. text, 1, 1, 1, true)
    end

    local totalLow = #scratchLowSkillList
    if showNeedsSkill and totalLow > 0 then
        local text = ""
        for i = 1, math.min(totalLow, maxAlts) do
            text = (text == "") and scratchLowSkillList[i] or (text .. ", " .. scratchLowSkillList[i])
        end
        if totalLow > maxAlts then
            text = string.format("%s, |cffaaaaaa+%d more|r", text, totalLow - maxAlts)
        end
        AddLine("|cffffbb33needs skill:|r " .. text, 1, 1, 1, true)
    end
end

-- ── Tooltip Post-Call Handler ─────────────────────────────────────────────────
local function SetItemTooltip(tooltip, data)
    if not tooltip or not tooltip.AddLine then return end
    if tooltip._sfuiInRecipeBrowser then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip and tooltip ~= sfui.tooltip then return end

    local itemID = (data and data.id)
    if not itemID and TooltipUtil and TooltipUtil.GetDisplayedItem then
        itemID = select(3, TooltipUtil.GetDisplayedItem(tooltip))
    end
    if not itemID and tooltip.GetPrimaryTooltipData then
        local tipData = tooltip:GetPrimaryTooltipData()
        if tipData and tipData.type == Enum.TooltipDataType.Item then
            itemID = tipData.id
        end
    end
    if not itemID and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    local issecretvalue = (sfui.safety and sfui.safety.issecretvalue) or (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue
    if not itemID or (issecretvalue and issecretvalue(itemID)) or type(itemID) ~= "number" or itemID <= 0 then return end

    -- Update active player status for recipe items
    if IsRecipe(itemID) then
        UpdateItem(itemID)
    end

    sfui.recipes.AddAltKnowledgeLines(tooltip, itemID)
end

-- ── Tooltip Registration (Retail & Classic Era Compatible) ────────────────────
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, SetItemTooltip)
else
    -- Fallback for legacy Classic Era clients without TooltipDataProcessor
    -- hook both the blizzard tooltip and our private one
    if _G.GameTooltip then
        _G.GameTooltip:HookScript("OnTooltipSetItem", SetItemTooltip)
    end
    if sfui.tooltip and sfui.tooltip ~= _G.GameTooltip then
        sfui.tooltip:HookScript("OnTooltipSetItem", SetItemTooltip)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", SetItemTooltip)
    end
end

-- ── Bag & Merchant Icon Tinting ───────────────────────────────────────────────
local function UpdateBagItemButton(button)
    if not button or not SfuiDB or SfuiDB.recipesTintIcons == false then return end
    local bagID = button.GetBagID and button:GetBagID()
    local slotID = button.GetID and button:GetID()
    if not bagID or not slotID then return end

    local itemID = nil
    if C_Container and C_Container.GetContainerItemID then
        itemID = C_Container.GetContainerItemID(bagID, slotID)
    else
        local link = _G.GetContainerItemLink and _G.GetContainerItemLink(bagID, slotID)
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if not itemID then return end

    -- FAST EXIT: Non-recipe items exit in ~2 nanoseconds
    if not IsRecipe(itemID) then return end

    local _, color = GetRecipeStatus(itemID)
    local icon = button.icon or _G[button:GetName() .. "IconTexture"] or button.Icon
    if icon and color then
        icon:SetVertexColor(color.r, color.g, color.b)
    end
end

local containerButtonsHooked = false
local function HookContainerButtons()
    if containerButtonsHooked then return end
    containerButtonsHooked = true

    if ContainerFrameItemButtonMixin and hooksecurefunc then
        if ContainerFrameItemButtonMixin.UpdateCooldown then
            hooksecurefunc(ContainerFrameItemButtonMixin, "UpdateCooldown", UpdateBagItemButton)
        end
    end

    if _G.ContainerFrame_Update and hooksecurefunc then
        hooksecurefunc("ContainerFrame_Update", function(frame)
            if not frame or not frame.GetID then return end
            local name = frame:GetName()
            if not name then return end
            local size = frame.size or 0
            for i = 1, size do
                local itemButton = _G[name .. "Item" .. i]
                if itemButton then
                    UpdateBagItemButton(itemButton)
                end
            end
        end)
    end

    -- Fallback for default Blizzard Merchant frame (if SFUI custom merchant is not active)
    if _G.MerchantFrame_UpdateMerchantInfo and hooksecurefunc then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
            if not SfuiDB or SfuiDB.recipesTintIcons == false then return end
            local numItems = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
            local page = _G.MERCHANT_ITEMS_PER_PAGE or 10
            for i = 1, page do
                local index = ((_G.MerchantFrame and _G.MerchantFrame.page or 1) - 1) * page + i
                if index <= numItems then
                    local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(index)
                    if link then
                        local itemID = tonumber(link:match("item:(%d+)"))
                        if IsRecipe(itemID) then
                            local _, color = GetRecipeStatus(itemID)
                            local btn = _G["MerchantItem" .. i .. "ItemButton"]
                            if btn and btn.icon then
                                if color then
                                    btn.icon:SetVertexColor(color.r, color.g, color.b)
                                else
                                    btn.icon:SetVertexColor(1, 1, 1)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

-- ── Event Initialization via sfui.events ──────────────────────────────────────
local function OnLogin()
    EnsurePlayerContext()
    SfuiDB = SfuiDB or {}
    SfuiDB.recipes = SfuiDB.recipes or {}
    SfuiDB.crafts = SfuiDB.crafts or {}

    PruneOrphanCrafts()
    HookContainerButtons()
end

local function OnRecipeLearned()
    InvalidateRecipeStatusCache()
    RequestTradeSkillScan(true)
end

sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", OnLogin)
sfui.events.RegisterEvent("NEW_RECIPE_LEARNED", OnRecipeLearned)
sfui.events.RegisterEvent("TRADE_SKILL_SHOW", RequestTradeSkillScan)
sfui.events.RegisterEvent("TRADE_SKILL_LIST_UPDATE", RequestTradeSkillScan)
sfui.events.RegisterEvent("CRAFT_SHOW", RequestTradeSkillScan)
sfui.events.RegisterEvent("CRAFT_UPDATE", RequestTradeSkillScan)
sfui.events.RegisterEvent("SKILL_LINES_CHANGED", function()
    RequestTradeSkillScan(true)
    PruneOrphanCrafts()
end)
-- Attempt early hook if container mixin is already available
HookContainerButtons()

-- Expose Public Methods
sfui.recipes.STATUS_COLORS = STATUS_COLORS
sfui.recipes.GetRecipeStatus = GetRecipeStatus
sfui.recipes.IsRecipe = IsRecipe
sfui.recipes.InvalidateCache = InvalidateRecipeStatusCache
sfui.recipes.UpdateItem = UpdateItem
sfui.recipes.RequestUpdateAllItems = RequestUpdateAllItems
sfui.recipes.ScanCurrentTradeSkills = ScanCurrentTradeSkills
sfui.recipes.AddAltKnowledgeLines = sfui.recipes.AddAltKnowledgeLines
sfui.recipes.CheckAltEligibility = CheckAltEligibility
