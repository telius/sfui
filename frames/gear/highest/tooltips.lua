local addonName, addon = ...
sfui.highest = sfui.highest or {}

local _G = _G
local common = sfui.common
local C_Item = _G.C_Item
local C_TooltipInfo = _G.C_TooltipInfo
local C_Container = _G.C_Container
local C_PlayerInfo = _G.C_PlayerInfo
local TooltipUtil = _G.TooltipUtil
local UnitClass = _G.UnitClass
local WorldFrame = _G.WorldFrame
local CreateFrame = _G.CreateFrame
local tonumber = _G.tonumber
local tostring = _G.tostring
local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local wipe = _G.wipe

-- ══════════════════════════════════════════════════════════════════════════════
-- Hidden Scanning Tooltip
-- ══════════════════════════════════════════════════════════════════════════════
local scanTip = nil
local function GetScanTooltip()
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "SfuiHighestScanTooltip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end
sfui.highest.GetScanTooltip = GetScanTooltip

-- ══════════════════════════════════════════════════════════════════════════════
-- Caches
-- ══════════════════════════════════════════════════════════════════════════════
sfui.highest.embellishCache = sfui.highest.embellishCache or {}
local embellishCache = sfui.highest.embellishCache
local embellishCacheCount = 0
local EMBELLISH_CACHE_MAX = 300

sfui.highest.pvpIlvlCache = sfui.highest.pvpIlvlCache or {}
local pvpIlvlCache = sfui.highest.pvpIlvlCache
local pvpIlvlCacheCount = 0
local PVP_CACHE_MAX = 200

sfui.highest.boeAttemptedAt = sfui.highest.boeAttemptedAt or {}
local boeAttemptedAt = sfui.highest.boeAttemptedAt

function sfui.highest.pvpCacheSet(link, val)
    if not pvpIlvlCache[link] then
        pvpIlvlCacheCount = pvpIlvlCacheCount + 1
        if pvpIlvlCacheCount > PVP_CACHE_MAX then
            wipe(pvpIlvlCache)
            pvpIlvlCacheCount = 1
        end
    end
    pvpIlvlCache[link] = val
end

function sfui.highest.ClearCache()
    if sfui.highest.validationCache then
        wipe(sfui.highest.validationCache)
        sfui.highest.validationCacheCount = 0
    end
    wipe(embellishCache)
    embellishCacheCount = 0
    wipe(pvpIlvlCache)
    pvpIlvlCacheCount = 0
    wipe(boeAttemptedAt)
    if sfui.common and sfui.common.clear_item_stats_cache then
        sfui.common.clear_item_stats_cache()
    end
end
sfui.highest.ClearValidationCache = sfui.highest.ClearCache

-- ══════════════════════════════════════════════════════════════════════════════
-- Item Usability (Red text scan for unmet weapon skill / class / level)
-- ══════════════════════════════════════════════════════════════════════════════
local function CanPlayerUseItem(itemLink, itemID, ignorePlayerLevel)
    if not itemLink and not itemID then return true end
    if not itemID and itemLink then
        itemID = common.get_item_id(itemLink)
    end

    if itemID and C_PlayerInfo and C_PlayerInfo.CanPlayerUseItem then
        local canUse = C_PlayerInfo.CanPlayerUseItem(itemID)
        if canUse == false then
            return false
        end
    end

    if itemLink then
        if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
            local tData = C_TooltipInfo.GetHyperlink(itemLink)
            if tData and tData.lines then
                if TooltipUtil and TooltipUtil.SurfaceArgs then
                    TooltipUtil.SurfaceArgs(tData)
                end
                for _, line in ipairs(tData.lines) do
                    local clr = line.leftColor
                    if clr and clr.r and clr.g and clr.b then
                        if clr.r > 0.85 and clr.g < 0.25 and clr.b < 0.25 then
                            local txt = line.leftText
                            local isDurability = txt and (type(txt) == "string") and (txt:find("Durability") or txt:find("Haltbarkeit") or (_G.ITEM_DURABILITY and txt:find(_G.ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (type(txt) == "string") and (txt:find("Level") or (_G.ITEM_MIN_LEVEL and txt:find(_G.ITEM_MIN_LEVEL:match("%%d") and _G.ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                    local rclr = line.rightColor
                    if rclr and rclr.r and rclr.g and rclr.b then
                        if rclr.r > 0.85 and rclr.g < 0.25 and rclr.b < 0.25 then
                            local txt = line.rightText
                            local isDurability = txt and (type(txt) == "string") and (txt:find("Durability") or txt:find("Haltbarkeit") or (_G.ITEM_DURABILITY and txt:find(_G.ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (type(txt) == "string") and (txt:find("Level") or (_G.ITEM_MIN_LEVEL and txt:find(_G.ITEM_MIN_LEVEL:match("%%d") and _G.ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                end
            end
        else
            local tip = GetScanTooltip()
            if tip then
                tip:ClearLines()
                tip:SetHyperlink(itemLink)
                local numLines = tip:NumLines() or 0
                for i = 1, numLines do
                    local fsL = _G["SfuiHighestScanTooltipTextLeft" .. i]
                    if fsL then
                        local r, g, b = fsL:GetTextColor()
                        if r and g and b and r > 0.85 and g < 0.25 and b < 0.25 then
                            local txt = fsL:GetText()
                            local isDurability = txt and (txt:find("Durability") or txt:find("Haltbarkeit") or (_G.ITEM_DURABILITY and txt:find(_G.ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (txt:find("Level") or (_G.ITEM_MIN_LEVEL and txt:find(_G.ITEM_MIN_LEVEL:match("%%d") and _G.ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                    local fsR = _G["SfuiHighestScanTooltipTextRight" .. i]
                    if fsR then
                        local r, g, b = fsR:GetTextColor()
                        if r and g and b and r > 0.85 and g < 0.25 and b < 0.25 then
                            local txt = fsR:GetText()
                            local isDurability = txt and (txt:find("Durability") or txt:find("Haltbarkeit") or (_G.ITEM_DURABILITY and txt:find(_G.ITEM_DURABILITY, 1, true)))
                            local isLevelReq = ignorePlayerLevel and txt and (txt:find("Level") or (_G.ITEM_MIN_LEVEL and txt:find(_G.ITEM_MIN_LEVEL:match("%%d") and _G.ITEM_MIN_LEVEL:gsub("%%d", "") or "Level", 1, true)))
                            if not isDurability and not isLevelReq then
                                return false
                            end
                        end
                    end
                end
            end
        end
    end
    return true
end
sfui.highest.CanPlayerUseItem = CanPlayerUseItem

-- ══════════════════════════════════════════════════════════════════════════════
-- Weapon DPS Parser
-- ══════════════════════════════════════════════════════════════════════════════
local function GetWeaponDPS(itemData)
    if not itemData or not itemData.link then return 0 end
    local dps = sfui.common.get_weapon_stats(itemData.link)
    if dps and dps > 0 then
        return dps
    end
    if C_TooltipInfo then
        local data
        if itemData.bag and itemData.slot then
            data = C_TooltipInfo.GetBagItem(itemData.bag, itemData.slot)
        elseif itemData.equippedSlot then
            data = C_TooltipInfo.GetInventoryItem("player", itemData.equippedSlot)
        else
            data = C_TooltipInfo.GetHyperlink(itemData.link)
        end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local left = line.leftText
                if left and type(left) == "string" then
                    local clean = left:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                    local m = clean:match("%(([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]%)")
                        or clean:match("([%d%.,]+)%s+[Dd][Aa][Mm][Aa][Gg][Ee]%s+[Pp][Ee][Rr]%s+[Ss][Ee][Cc][Oo][Nn][Dd]")
                        or clean:match("%(([%d%.,]+)%s+[Dd][Pp][Ss]%)")
                        or clean:match("([%d%.,]+)%s+[Dd][Pp][Ss]")
                    if m then
                        local dpsVal = 0
                        if m:find(",") and m:find("%.") then
                            if m:find(",") < m:find("%.") then
                                dpsVal = tonumber((m:gsub(",", ""))) or 0
                            else
                                dpsVal = tonumber((m:gsub("%.", ""):gsub(",", "."))) or 0
                            end
                        elseif m:find(",") then
                            dpsVal = tonumber((m:gsub(",", "."))) or 0
                        else
                            dpsVal = tonumber(m) or 0
                        end
                        if dpsVal > 0 then return dpsVal end
                    end
                end
            end
        end
    end
    return itemData.effectiveIlvl or itemData.ilvl or common.get_item_level(itemData.link) or 0
end
sfui.highest.GetWeaponDPS = GetWeaponDPS

-- ══════════════════════════════════════════════════════════════════════════════
-- Embellishment Scanner
-- ══════════════════════════════════════════════════════════════════════════════
local function HasEmbellishment(itemData)
    if not itemData or not itemData.link then return false end
    local link = itemData.link
    if embellishCache[link] ~= nil then
        return embellishCache[link]
    end

    local isEmbellished = false
    local embCat = _G["ITEM_LIMIT_CATEGORY_EMBELLISHED"]
    local embPattern = embCat and embCat:lower()

    if C_TooltipInfo then
        local data
        if itemData.bag and itemData.slot then
            data = C_TooltipInfo.GetBagItem(itemData.bag, itemData.slot)
        elseif itemData.equippedSlot then
            data = C_TooltipInfo.GetInventoryItem("player", itemData.equippedSlot)
        else
            data = C_TooltipInfo.GetHyperlink(link)
        end

        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt and type(txt) == "string" and txt ~= "" then
                    local ltxt = txt:lower()
                    if (embPattern and ltxt:find(embPattern, 1, true))
                        or ltxt:find("embellish", 1, true)
                        or ltxt:find("verziert", 1, true)
                        or ltxt:find("orné", 1, true)
                        or ltxt:find("adornad", 1, true)
                        or ltxt:find("украшен", 1, true)
                        or ltxt:find("美化", 1, true)
                        or ltxt:find("장식", 1, true) then
                        isEmbellished = true
                        break
                    end
                end
            end
        end
    end

    if embellishCacheCount >= EMBELLISH_CACHE_MAX then
        wipe(embellishCache)
        embellishCacheCount = 0
    end
    embellishCacheCount = embellishCacheCount + 1
    embellishCache[link] = isEmbellished
    return isEmbellished
end
sfui.highest.HasEmbellishment = HasEmbellishment

-- ══════════════════════════════════════════════════════════════════════════════
-- Razorice & Runeforge Scanner
-- ══════════════════════════════════════════════════════════════════════════════
local RAZORICE_SPELL_ID = 53343
local cachedRazoriceName = nil

local function HasRazoriceEnchant(itemData)
    if not itemData or not itemData.link then return false end
    local link = itemData.link

    -- 1. Direct enchantID check (3370 = Rune of Razorice)
    local enchantID = tonumber(link:match("item:%d+:(%d+):"))
    if enchantID == 3370 then
        return true
    end

    if not cachedRazoriceName then
        local spellName = common.get_spell_name(RAZORICE_SPELL_ID) or "Razorice"
        if spellName and spellName ~= "" then
            cachedRazoriceName = spellName:lower()
        end
    end

    -- 2. Tooltip scan for Runeforged enchant text
    if C_TooltipInfo then
        local data
        if itemData.bag and itemData.slot then
            data = C_TooltipInfo.GetBagItem(itemData.bag, itemData.slot)
        elseif itemData.equippedSlot then
            data = C_TooltipInfo.GetInventoryItem("player", itemData.equippedSlot)
        else
            data = C_TooltipInfo.GetHyperlink(link)
        end
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local txt = line.leftText
                if txt and type(txt) == "string" and txt ~= "" then
                    local lowerTxt = txt:lower()
                    if (cachedRazoriceName and lowerTxt:find(cachedRazoriceName, 1, true)) or lowerTxt:find("razorice", 1, true) then
                        return true
                    end
                end
            end
        end
    end

    return false
end
sfui.highest.HasRazoriceEnchant = HasRazoriceEnchant

-- ══════════════════════════════════════════════════════════════════════════════
-- Rogue Spec & Backstab Detection
-- ══════════════════════════════════════════════════════════════════════════════
local function DoesRogueUseBackstab(specID)
    if specID then
        local isRogue = (specID == 1488 or (specID >= 14881 and specID <= 14883) or specID == 259 or specID == 260 or specID == 261)
        if isRogue then return true end
    end
    local classFilename = (sfui.talents and sfui.talents.get_player_class and sfui.talents.get_player_class()) or (UnitClass and select(2, UnitClass("player")))
    return classFilename == "ROGUE"
end
sfui.highest.DoesRogueUseBackstab = DoesRogueUseBackstab
sfui.common.does_rogue_use_backstab = DoesRogueUseBackstab

-- ══════════════════════════════════════════════════════════════════════════════
-- Item Soulbound Verification
-- ══════════════════════════════════════════════════════════════════════════════
local C_Container_GetContainerItemInfo = (_G.C_Container and _G.C_Container.GetContainerItemInfo) or _G.GetContainerItemInfo

local function IsBagItemBound(bag, slot)
    if not bag or not slot then return true end
    local info = C_Container_GetContainerItemInfo(bag, slot)
    if type(info) == "table" then
        if info.isBound then return true end
    elseif info ~= nil and _G.GetContainerItemInfo then
        local isBound = select(11, _G.GetContainerItemInfo(bag, slot))
        if isBound then return true end
    end
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local tData = C_TooltipInfo.GetBagItem(bag, slot)
        if tData and tData.lines then
            for _, line in ipairs(tData.lines) do
                local t = line.leftText
                if t and type(t) == "string" then
                    if t:find(_G.ITEM_SOULBOUND or "Soulbound")
                        or t:find(_G.ITEM_BNETACCOUNTBOUND or "Account")
                        or t:find(_G.ITEM_BIND_TO_ACCOUNT or "Binds to account")
                        or t:find(_G.ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net account") then
                        return true
                    end
                end
            end
        end
    else
        local tip = GetScanTooltip()
        if tip then
            tip:ClearLines()
            if tip.SetBagItem then
                tip:SetBagItem(bag, slot)
            end
            for i = 1, tip:NumLines() do
                local line = _G["SfuiHighestScanTooltipTextLeft" .. i]
                local t = line and line:GetText()
                if t then
                    if t:find(_G.ITEM_SOULBOUND or "Soulbound")
                        or t:find(_G.ITEM_BNETACCOUNTBOUND or "Account")
                        or t:find(_G.ITEM_BIND_TO_ACCOUNT or "Binds to account")
                        or t:find(_G.ITEM_BIND_TO_BNETACCOUNT or "Binds to Battle.net account") then
                        return true
                    end
                end
            end
        end
    end
    return false
end
sfui.highest.IsBagItemBound = IsBagItemBound
