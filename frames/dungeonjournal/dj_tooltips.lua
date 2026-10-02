local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

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

local function DJ_DB()
    SfuiDB = SfuiDB or {}
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    return SfuiDB.dungeonjournal
end

local function OnTooltipSetItem(tooltip)
    if not tooltip then return end
    if DJ_DB().showItemTooltips == false then return end

    local itemID = nil
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, _, id = TooltipUtil.GetDisplayedItem(tooltip)
        itemID = id
    end
    if not itemID and tooltip.GetItem then
        local _, link = tooltip:GetItem()
        if link then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end

    if not itemID then return end

    -- Prevent duplicate annotations on the same tooltip render pass
    if tooltip._sfuiDJAnnotated == itemID then return end

    local source = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(itemID)
    if not source then return end

    tooltip._sfuiDJAnnotated = itemID

    local pal = sfui.theme and sfui.theme.GetPalette and sfui.theme.GetPalette()
    local accent = pal and pal.accentColor or nil
    local a1, a2, a3 = (accent and accent[1]) or 1, (accent and accent[2]) or 0.82, (accent and accent[3]) or 0.2

    if not source.tooltipLine or source.accent1 ~= a1 or source.accent2 ~= a2 or source.accent3 ~= a3 then
        local r = math_floor(a1 * 255)
        local g = math_floor(a2 * 255)
        local b = math_floor(a3 * 255)
        local hex = string_format("%02x%02x%02x", r, g, b)
        local bossName    = source.bossName or "Encounter"
        local dungeonName = source.dungeonName or "Dungeon"
        source.accent1 = a1
        source.accent2 = a2
        source.accent3 = a3
        source.tooltipLine = string_format("|cff%sDrops from:|r %s  ·  |cff888888%s|r", hex, bossName, dungeonName)
    end

    tooltip:AddLine(source.tooltipLine, 1, 1, 1, true)

    if sfui.dungeonjournal and sfui.dungeonjournal.IsWishlisted and sfui.dungeonjournal.IsWishlisted(itemID) then
        tooltip:AddLine("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:12:12:0:0|t |cffcc44ffLoot Wishlist Active|r", 1, 1, 1, false)
    end
end

local function OnTooltipCleared(tooltip)
    if tooltip then
        tooltip._sfuiDJAnnotated = nil
    end
end

-- ─── Tooltip Registration (Retail & Classic Era Compatible) ──────────────────
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
else
    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        GameTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        ItemRefTooltip:HookScript("OnTooltipCleared", OnTooltipCleared)
    end
end
