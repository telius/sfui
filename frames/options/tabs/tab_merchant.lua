local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common
local wipe = _G.wipe or table.wipe

sfui.options.RegisterTab({
    id = "merchant",
    name = "merchant",
    build = function(merchant_panel, tab_button, options_frame)
        local create_checkbox = common.create_checkbox
        local white = sfui.config.colors.white

        local merchant_header = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
        merchant_header:SetPoint("TOPLEFT", 15, -15)
        merchant_header:SetTextColor(white[1], white[2], white[3])
        merchant_header:SetText("merchant settings")

        local enable_merchant_cb = create_checkbox(merchant_panel, "enable merchant frame", "enableMerchant", nil,
            "enables the custom merchant frame.")
        enable_merchant_cb:SetPoint("TOPLEFT", merchant_header, "BOTTOMLEFT", 0, -10)

        local enable_decor_cb = create_checkbox(merchant_panel, "enable decor filter", "enableDecor", function(checked)
            if not checked and SfuiDecorDB then
                wipe(SfuiDecorDB)
                common.print("Decor cache cleared.")
            end
            if sfui.merchant and sfui.merchant.reset_scroll_and_rebuild then
                sfui.merchant.reset_scroll_and_rebuild()
            end
        end, "enables the caching and filtering of housing decor items.")
        enable_decor_cb:SetPoint("TOPLEFT", enable_merchant_cb, "BOTTOMLEFT", 0, -10)

        local decor_cache_label = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
        decor_cache_label:SetPoint("TOPLEFT", enable_decor_cb, "BOTTOMLEFT", 0, -15)
        decor_cache_label:SetTextColor(white[1], white[2], white[3])
        decor_cache_label:SetText("decor cache status:")

        local decor_cache_value = merchant_panel:CreateFontString(nil, "OVERLAY", g.font)
        decor_cache_value:SetPoint("LEFT", decor_cache_label, "RIGHT", 5, 0)
        decor_cache_value:SetText("N/A")

        merchant_panel:HookScript("OnShow", function()
            if sfui.merchant and sfui.merchant.decorCacheStatus then
                decor_cache_value:SetText(sfui.merchant.decorCacheStatus)
            else
                decor_cache_value:SetText("N/A (Not Populated)")
            end
        end)
    end,
})
