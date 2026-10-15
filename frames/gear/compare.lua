local addonName, addon = ...
sfui = sfui or {}
sfui.compare = sfui.compare or {}

local is_initialized = false

local function safe_set_cvar(cvar, val)
    if sfui.common and sfui.common.set_cvar then
        return sfui.common.set_cvar(cvar, val)
    elseif (not InCombatLockdown or not InCombatLockdown()) then
        local setCVar = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
        local getCVar = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
        if setCVar then
            local strVal = tostring(val)
            if not getCVar or getCVar(cvar) ~= strVal then
                local ok = pcall(setCVar, cvar, strVal)
                if not ok and tonumber(strVal) ~= nil then
                    pcall(setCVar, cvar, tonumber(strVal))
                end
            end
            return true
        end
    end
    return false
end

local function update_cvar()
    if not SfuiDB then return end
    local should_enable = (SfuiDB.enableAutoCompare ~= false)
    safe_set_cvar("alwaysCompareItems", should_enable and "1" or "0")
end

local function is_equippable(tooltip)
    if not tooltip then return false end
    local link
    if tooltip.GetItem then
        local _, itemLink = tooltip:GetItem()
        link = itemLink
    end
    if not link and tooltip.GetPrimaryTooltipData then
        local data = tooltip:GetPrimaryTooltipData()
        if data then
            link = data.hyperlink or data.id
        end
    end
    if not link then return false end
    local getInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant
    if not getInstant then return true end
    local equipLoc = select(4, getInstant(link))
    return equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

local function is_target_tooltip(tt)
    if not tt then return false end

    -- Only allow sfui's dedicated tooltip, GameTooltip, or ItemRefTooltip
    local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip
    if tt ~= sfuiTip and tt ~= _G.GameTooltip and tt ~= _G.ItemRefTooltip then
        return false
    end

    -- Ensure shoppingTooltips table is populated for valid tooltips
    if not tt.shoppingTooltips or #tt.shoppingTooltips == 0 or not tt.shoppingTooltips[1] then
        if tt == _G.ItemRefTooltip then
            local is1 = _G.ItemRefShoppingTooltip1
            local is2 = _G.ItemRefShoppingTooltip2
            if is1 and is2 then
                tt.shoppingTooltips = { is1, is2 }
            end
        else
            local s1 = _G.ShoppingTooltip1
            local s2 = _G.ShoppingTooltip2
            if s1 and s2 then
                tt.shoppingTooltips = { s1, s2 }
            end
        end
    end

    -- Must have a valid shoppingTooltips table to avoid ipairs(nil) crash in TooltipComparisonManager
    if type(tt.shoppingTooltips) ~= "table" or #tt.shoppingTooltips == 0 or not tt.shoppingTooltips[1] then
        return false
    end

    -- Must be shown and support item comparison
    if not tt:IsShown() then
        return false
    end
    if tt.supportsItemComparison == false or tt.suppressAutomaticCompareItem then
        return false
    end

    return true
end

local function try_show_compare(tooltip)
    if not (SfuiDB and SfuiDB.enableAutoCompare ~= false) then return end
    if not is_target_tooltip(tooltip) then return end
    if not _G.GameTooltip_ShowCompareItem then return end

    local shop1 = tooltip.shoppingTooltips and tooltip.shoppingTooltips[1]
    local shop2 = tooltip.shoppingTooltips and tooltip.shoppingTooltips[2]
    if (shop1 and shop1:IsShown()) or (shop2 and shop2:IsShown()) then
        return
    end

    if not is_equippable(tooltip) then
        return
    end

    pcall(_G.GameTooltip_ShowCompareItem, tooltip)
end
sfui.compare.try_show_compare = try_show_compare

local function on_cvar_update(event, cvar_name)
    if cvar_name and cvar_name:lower() == "alwayscompareitems" then
        local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
        local current = get and get("alwaysCompareItems")
        local expected = (SfuiDB and SfuiDB.enableAutoCompare ~= false) and "1" or "0"
        if current ~= expected then
            update_cvar()
        end
    end
end

function sfui.compare.init()
    if SfuiDB and SfuiDB.enableAutoCompare == nil then
        SfuiDB.enableAutoCompare = true
    end

    -- Ensure sfui.tooltip has item comparison and shopping tooltips wired
    local sfuiTip = (sfui.common and sfui.common.get_tooltip and sfui.common.get_tooltip()) or sfui.tooltip
    if sfuiTip then
        sfuiTip.supportsItemComparison = true
        if not sfuiTip.shoppingTooltips or #sfuiTip.shoppingTooltips == 0 or not sfuiTip.shoppingTooltips[1] then
            local s1 = _G.ShoppingTooltip1
            local s2 = _G.ShoppingTooltip2
            if s1 and s2 then
                sfuiTip.shoppingTooltips = { s1, s2 }
            end
        end
    end

    update_cvar()

    if not is_initialized then
        is_initialized = true

        -- Keep CVar enforced across login, loading screens, and CVar resets
        sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", update_cvar)
        sfui.events.RegisterEvent("VARIABLES_LOADED", update_cvar)
        sfui.events.RegisterEvent("CVAR_UPDATE", on_cvar_update)

        -- Fallback comparison trigger for tooltips that do not auto-invoke GameTooltip_ShowCompareItem
        local TooltipDataProcessor = _G.TooltipDataProcessor
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
                if is_target_tooltip(tt) then
                    try_show_compare(tt)
                end
            end)
        end

        -- On modern clients with TooltipDataProcessor, AddTooltipPostCall handles all item tooltip updates.
        -- Legacy fallback for classic clients where TooltipDataProcessor does not exist:
        if not TooltipDataProcessor then
            local GameTooltip = _G.GameTooltip
            if GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetItem") then
                pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", try_show_compare)
            end

            local ItemRefTooltip = _G.ItemRefTooltip
            if ItemRefTooltip and ItemRefTooltip.HasScript and ItemRefTooltip:HasScript("OnTooltipSetItem") then
                pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", try_show_compare)
            end

            if sfui.tooltip and sfui.tooltip.HasScript and sfui.tooltip:HasScript("OnTooltipSetItem") and sfui.tooltip ~= GameTooltip then
                pcall(sfui.tooltip.HookScript, sfui.tooltip, "OnTooltipSetItem", try_show_compare)
            end
        end
    end
end

sfui.compare.update = update_cvar
