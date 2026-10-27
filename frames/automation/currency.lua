local addonName, addon = ...
sfui = sfui or {}

local CharacterFrame = _G.CharacterFrame
local C_CurrencyInfo = _G.C_CurrencyInfo
local C_Item = _G.C_Item
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local ipairs = ipairs
local table_remove = table.remove
local table_wipe = table.wipe
local GameTooltip = sfui.common.get_tooltip()
local function UpdateCurrencyAnchors()
    local cFrame = _G.sfui_currency_frame
    local iFrame = _G.sfui_item_frame
    if not CharacterFrame then return end

    local isChonky = sfui.common.is_addon_loaded("ChonkyCharacterSheet")
    local anchorParent = isChonky and (_G.CharacterFrameBgbg or _G.CharacterFrameBg or CharacterFrame) or CharacterFrame
    local offsetY = isChonky and -54 or -110

    if cFrame then
        cFrame:ClearAllPoints()
        cFrame:SetPoint("TOPLEFT", anchorParent, "BOTTOMLEFT", 0, offsetY)
    end

    if iFrame then
        iFrame:ClearAllPoints()
        if cFrame and cFrame:IsShown() then
            iFrame:SetPoint("TOPLEFT", cFrame, "BOTTOMLEFT", 0, -2)
        else
            iFrame:SetPoint("TOPLEFT", anchorParent, "BOTTOMLEFT", 0, offsetY)
        end
    end
end

if CharacterFrame and hooksecurefunc then
    hooksecurefunc(CharacterFrame, "Show", function()
        UpdateCurrencyAnchors()
        if sfui.update_currency_display then sfui.update_currency_display() end
        if sfui.update_item_display then sfui.update_item_display() end
    end)
end

do
    local widget_frame, icons, value_labels = nil, {}, {}
    local _currencyDetail = {}
    local _currencySourceData = {}

    local function OnCurrencyEnter(self)
        if not GameTooltip or not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetCurrencyByID(self.id)
        GameTooltip:Show()
    end

    local function OnCurrencyLeave()
        if GameTooltip then GameTooltip:Hide() end
    end

    local function get_currency_details(currency_id)
        local get_currency_info = sfui.common and sfui.common.get_currency_info
        local info = get_currency_info and get_currency_info(currency_id)
        if not info then return nil end
        _currencyDetail.texture = info.iconFileID
        _currencyDetail.quantity = info.quantity
        _currencyDetail.on_enter = OnCurrencyEnter
        _currencyDetail.on_leave = OnCurrencyLeave
        _currencyDetail.on_mouseup = nil
        return _currencyDetail
    end

    function sfui.update_currency_display()
        if not widget_frame then return end
        UpdateCurrencyAnchors()
        table_wipe(_currencySourceData)
        local get_backpack_info = C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo
        if get_backpack_info then
            local i = 1
            while true do
                local backpackCurrencyInfo = get_backpack_info(i)
                if not backpackCurrencyInfo then break end
                _currencySourceData[#_currencySourceData + 1] = backpackCurrencyInfo.currencyTypesID
                i = i + 1
            end
        end
        sfui.common.update_widget_bar(widget_frame, icons, value_labels, _currencySourceData, get_currency_details)
        UpdateCurrencyAnchors()
    end

    function sfui.create_currency_frame()
        if widget_frame or not CharacterFrame then return end
        local c = sfui.config.currency_frame
        widget_frame = CreateFrame("Frame", "sfui_currency_frame", CharacterFrame, "BackdropTemplate")
        widget_frame:SetSize(c.width, c.height)
        widget_frame:SetFrameStrata("HIGH")
        widget_frame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 5)
        widget_frame:SetBackdrop({ bgFile = sfui.config.textures.white, tile = true, tileSize = 32 })
        widget_frame:SetBackdropColor(0, 0, 0, 0.5)

        UpdateCurrencyAnchors()

        widget_frame:SetScript("OnShow", function()
            UpdateCurrencyAnchors()
            sfui.update_currency_display()
        end)

        sfui.events.RegisterThrottledEvent("CURRENCY_DISPLAY_UPDATE", 0.2, function()
            if widget_frame and (CharacterFrame:IsShown() or widget_frame:IsShown()) then
                sfui.update_currency_display()
            end
        end)
    end
end

do
    local widget_frame, icons, value_labels = nil, {}, {}
    local _itemDetail = {}

    local function remove_item(itemID)
        if not SfuiDB or not SfuiDB.items then return end
        for i, id in ipairs(SfuiDB.items) do
            if id == itemID then
                table_remove(SfuiDB.items, i)
                sfui.update_item_display()
                return
            end
        end
    end

    local function OnIconLeave(self)
        if GameTooltip then GameTooltip:Hide() end
    end

    local function OnItemIconEnter(self)
        if not GameTooltip or not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end

    local function OnItemIconMouseUp(self, button)
        if button == "RightButton" then
            remove_item(self.id)
        end
    end

    local function get_item_details(itemID)
        local get_item_info = (sfui.common and sfui.common.get_item_info)
            or (sfui.items and sfui.items.get_item_info)
            or (C_Item and C_Item.GetItemInfo)
            or _G.GetItemInfo
        if not get_item_info then return nil end
        local _, _, _, _, _, _, _, _, _, texture = get_item_info(itemID)
        if not texture then return nil end
        _itemDetail.texture = texture
        _itemDetail.quantity = GetItemCount and GetItemCount(itemID) or 0
        _itemDetail.on_enter = OnItemIconEnter
        _itemDetail.on_leave = OnIconLeave
        _itemDetail.on_mouseup = OnItemIconMouseUp
        return _itemDetail
    end

    function sfui.add_item(itemID)
        if not itemID then return end
        for _, id in ipairs(SfuiDB.items) do
            if id == itemID then return end
        end
        SfuiDB.items[#SfuiDB.items + 1] = itemID
        sfui.update_item_display()
    end

    function sfui.update_item_display()
        if not widget_frame then return end
        UpdateCurrencyAnchors()
        sfui.common.update_widget_bar(widget_frame, icons, value_labels, SfuiDB.items, get_item_details)
        UpdateCurrencyAnchors()
    end

    function sfui.create_item_frame()
        if widget_frame or not CharacterFrame then return end
        local c = sfui.config.item_frame
        widget_frame = CreateFrame("Frame", "sfui_item_frame", CharacterFrame, "BackdropTemplate")
        widget_frame:SetSize(c.width, c.height)
        widget_frame:SetFrameStrata("HIGH")
        widget_frame:SetFrameLevel(CharacterFrame:GetFrameLevel() + 5)
        widget_frame:SetBackdrop({ bgFile = sfui.config.textures.white, tile = true, tileSize = 32 })
        widget_frame:SetBackdropColor(0, 0, 0, 0.5)

        UpdateCurrencyAnchors()

        widget_frame:SetScript("OnShow", function()
            UpdateCurrencyAnchors()
            sfui.update_item_display()
        end)

        sfui.events.RegisterThrottledEvent("BAG_UPDATE_DELAYED", 0.2, function()
            if widget_frame and (CharacterFrame:IsShown() or widget_frame:IsShown()) then
                sfui.update_item_display()
            end
        end)
    end

    function sfui.currency_debug_info()
        return {
            currencyFrameCreated = _G.sfui_currency_frame ~= nil,
            itemFrameCreated = _G.sfui_item_frame ~= nil,
        }
    end

    if sfui.RegisterModule then
        sfui.currency = sfui.currency or {}
        sfui.currency.GetDebugInfo = sfui.currency_debug_info
        sfui.RegisterModule("currency", sfui.currency)
    end
end
