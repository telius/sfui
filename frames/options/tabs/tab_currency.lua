local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local CreateFrame = _G.CreateFrame
local tonumber = _G.tonumber
local GetCursorInfo = _G.GetCursorInfo
local GetItemInfoFromHyperlink = _G.GetItemInfoFromHyperlink
local ClearCursor = _G.ClearCursor

sfui.options.RegisterTab({
    id = "currency",
    name = "currency/items",
    build = function(currency_items_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local currency_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
        currency_header:SetPoint("TOPLEFT", 15, -15)
        currency_header:SetTextColor(white[1], white[2], white[3])
        currency_header:SetText("currency display settings")

        local currency_info_text = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
        currency_info_text:SetPoint("TOPLEFT", currency_header, "BOTTOMLEFT", 0, -10)
        currency_info_text:SetPoint("RIGHT", -15, 0)
        currency_info_text:SetJustifyH("LEFT")
        currency_info_text:SetText(
            "the currency display is automatic. to add or remove currencies, open the default character panel, go to the currencies tab, and check 'show on backpack' for any currency you wish to track. opening and closing the character panel will also update the display.")

        local item_header = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
        item_header:SetPoint("TOPLEFT", currency_info_text, "BOTTOMLEFT", 0, -20)
        item_header:SetTextColor(white[1], white[2], white[3])
        item_header:SetText("item tracking settings")

        local item_id_label = currency_items_panel:CreateFontString(nil, "OVERLAY", g.font)
        item_id_label:SetPoint("TOPLEFT", item_header, "BOTTOMLEFT", 0, -10)
        item_id_label:SetText("add item by id:")

        local item_id_input = CreateFrame("EditBox", nil, currency_items_panel, "InputBoxTemplate")
        item_id_input:SetPoint("LEFT", item_id_label, "RIGHT", 10, 0)
        item_id_input:SetSize(100, 32)
        item_id_input:SetAutoFocus(false)

        local add_button = CreateFlatButton(currency_items_panel, "add", 50, 22)
        add_button:SetPoint("LEFT", item_id_input, "RIGHT", 5, 0)
        add_button:SetScript("OnClick", function()
            local id = tonumber(item_id_input:GetText())
            if id and sfui.add_item then
                sfui.add_item(id)
                item_id_input:SetText("")
            end
        end)

        local drop_frame = CreateFrame("Frame", "sfui_item_drop_frame", currency_items_panel, "BackdropTemplate")
        drop_frame:SetPoint("TOPLEFT", item_id_label, "BOTTOMLEFT", 0, -20)
        drop_frame:SetSize(250, 50)
        local drop_frame_backdrop = {
            bgFile = g.textures.tooltip,
            tile = true,
            tileSize = 16,
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        }
        drop_frame:SetBackdrop(drop_frame_backdrop)
        drop_frame:SetBackdropColor(0.3, 0.3, 0.3, 0.7)
        drop_frame:SetBackdropBorderColor(0, 0, 0, 1)

        local drop_label = drop_frame:CreateFontString(nil, "OVERLAY", g.font)
        drop_label:SetAllPoints()
        drop_label:SetText("drop item here")
        drop_label:EnableMouse(false)

        drop_frame:EnableMouse(true)
        drop_frame:RegisterForDrag("LeftButton")
        local function handle_item_drop()
            local cType, _, link = GetCursorInfo()
            if cType == "item" and link then
                local itemID = GetItemInfoFromHyperlink(link)
                if itemID and sfui.add_item then
                    sfui.add_item(itemID)
                    if ClearCursor then ClearCursor() end
                end
            end
        end
        drop_frame:SetScript("OnReceiveDrag", handle_item_drop)
        drop_frame:SetScript("OnMouseUp", handle_item_drop)
    end,
})
