local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

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
    end,
})
