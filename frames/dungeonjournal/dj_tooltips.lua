local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.dungeonjournal = sfui.dungeonjournal or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/dungeonjournal/dj_tooltips.lua
--  Encounter drop source annotations for GameTooltip & ItemRefTooltip.
--  Displays: "|cff<accent>Drops from:|r <Boss Name>  ·  |cff888888<Dungeon Name>|r"
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local TooltipDataProcessor = _G.TooltipDataProcessor
local TooltipUtil          = _G.TooltipUtil
local GameTooltip          = _G.GameTooltip
local ItemRefTooltip       = _G.ItemRefTooltip
local Enum                 = _G.Enum

local tonumber, tostring   = _G.tonumber, _G.tostring
local math_floor           = _G.math.floor
local string_format        = _G.string.format

local DJ_DB = sfui.dungeonjournal.GetDB

local function GetAccentHex()
    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local accent = pal and pal.accentColor or nil
    local a1, a2, a3 = (accent and accent[1]) or 1, (accent and accent[2]) or 0.82, (accent and accent[3]) or 0.2
    return (sfui.colors and sfui.colors.rgb_to_hex and sfui.colors.rgb_to_hex(a1, a2, a3)) or "ffd133", a1, a2, a3
end

local function RenderDropSource(tooltip, ctx)
    if not tooltip or DJ_DB().showItemTooltips == false then return end
    local itemID = ctx and ctx.itemID
    if not itemID or tooltip._sfuiDJAnnotated == itemID then return end

    local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(itemID)
    if not source then return end

    tooltip._sfuiDJAnnotated = itemID

    local hex, a1, a2, a3 = GetAccentHex()
    if not source.tooltipLine or source.accent1 ~= a1 or source.accent2 ~= a2 or source.accent3 ~= a3 then
        local bossName    = tostring(source.bossName or "encounter"):lower()
        local dungeonName = tostring(source.dungeonName or "dungeon"):lower()
        source.accent1 = a1
        source.accent2 = a2
        source.accent3 = a3
        source.tooltipLine = string_format("|cff%sdrops from:|r %s  ·  |cff888888%s|r", hex, bossName, dungeonName)
    end

    tooltip:AddLine(source.tooltipLine, 1, 1, 1, true)
end

local function CountOwnedT0Pieces(t0Set)
    if not (t0Set and t0Set.pieces) then return 0 end
    local count = 0
    local getCount = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
    for _, id in ipairs(t0Set.pieces) do
        local owned = false
        if sfui.inventory and sfui.inventory.GetCount and (sfui.inventory.GetCount(id) or 0) > 0 then
            owned = true
        elseif getCount and (getCount(id, true) or 0) > 0 then
            owned = true
        elseif _G.GetInventoryItemID then
            for slot = 1, 19 do
                if _G.GetInventoryItemID("player", slot) == id then
                    owned = true
                    break
                end
            end
        end
        if owned then count = count + 1 end
    end
    return count
end

local function RenderSetInfo(tooltip, ctx)
    if not tooltip or DJ_DB().showItemTooltips == false then return end
    local itemID = ctx and ctx.itemID
    if not itemID or tooltip._sfuiSetAnnotated == itemID then return end

    local sc = sfui.sets_camelot
    if not (sc and sc.GetItemSetInfo) then return end
    local info = sc.GetItemSetInfo(itemID)
    if not info then return end

    tooltip._sfuiSetAnnotated = itemID

    if tooltip._sfuiDJAnnotated ~= itemID and sc.GetPieceSources then
        local srcs = sc.GetPieceSources(itemID)
        local first = srcs and srcs[1]
        if first and first.displayBoss then
            local hex = GetAccentHex()
            local who = tostring(first.displayBoss):lower()
            if first.mobs then
                who = who .. " (" .. tostring(first.mobs):lower() .. ")"
            end
            local dPart = first.dungeonName and ("  ·  |cff888888" .. tostring(first.dungeonName):lower() .. "|r") or ""
            tooltip:AddLine(string_format("|cff%sdrops from:|r %s%s", hex, who, dPart), 1, 1, 1, true)
        end
    end

    if sc.GetT0UpgradeInfo then
        local upg = sc.GetT0UpgradeInfo(itemID)
        if upg and upg.t0Set then
            local ownedCnt = CountOwnedT0Pieces(upg.t0Set)
            local totalCnt = #(upg.t0Set.pieces or {})
            tooltip:AddLine(string_format("|cffb066fft0.5 upgrade:|r %s (%d/%d t0 owned)", tostring(upg.stageName or ""):lower(), ownedCnt, totalCnt), 1, 1, 1, true)
        end
    end
end

local function RenderWishlist(tooltip, ctx)
    if not tooltip or DJ_DB().showItemTooltips == false then return end
    local itemID = ctx and ctx.itemID
    if not itemID or tooltip._sfuiDJWishAnnotated == itemID then return end

    local isLocalWish = sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and sfui.dungeonjournal.IsWishlisted(itemID)
    local peerOwners = sfui.sync and sfui.sync.GetPeerWishlistOwners and sfui.sync.GetPeerWishlistOwners(itemID)
    if not isLocalWish and (not peerOwners or #peerOwners == 0) then return end

    tooltip._sfuiDJWishAnnotated = itemID

    if isLocalWish then
        local wishChars = sfui.dungeonjournal.GetWishlistCharacters and sfui.dungeonjournal.GetWishlistCharacters(itemID)
        if wishChars and #wishChars > 0 then
            tooltip:AddLine("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffloot wishlist:|r " .. table.concat(wishChars, ", "), 1, 1, 1, true)
        else
            tooltip:AddLine("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffloot wishlist active|r", 1, 1, 1, false)
        end
    end

    if peerOwners and #peerOwners > 0 then
        tooltip:AddLine("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc66ffparty wishlist:|r " .. table.concat(peerOwners, ", "), 1, 1, 1, true)
    end
end

local function OnTooltipCleared(tooltip)
    if tooltip then
        tooltip._sfuiDJAnnotated = nil
        tooltip._sfuiSetAnnotated = nil
        tooltip._sfuiDJWishAnnotated = nil
    end
end

sfui.tooltips.RegisterItemProvider("drop_source", 20, RenderDropSource)
sfui.tooltips.RegisterItemProvider("set_info", 25, RenderSetInfo)
sfui.tooltips.RegisterItemProvider("wishlist", 30, RenderWishlist)
sfui.tooltips.RegisterClearCallback("dj_tooltips", OnTooltipCleared)
