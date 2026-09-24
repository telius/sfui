local addonName, addon = ...
sfui = sfui or {}
sfui.options = sfui.options or {}

local g = sfui.config
local common = sfui.common

local CreateFrame = _G.CreateFrame
local tonumber = _G.tonumber
local GameTooltip = sfui.tooltip or _G.GameTooltip

sfui.options.RegisterTab({
    id = "research",
    name = "research",
    condition = function()
        return not (sfui.compat and sfui.compat.is_classic)
    end,
    build = function(research_panel, tab_button, options_frame)
        local CreateFlatButton = common.create_flat_button
        local white = sfui.config.colors.white

        local research_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        research_header:SetPoint("TOPLEFT", 15, -15)
        research_header:SetTextColor(white[1], white[2], white[3])
        research_header:SetText("research viewer settings")

        local research_info = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        research_info:SetPoint("TOPLEFT", research_header, "BOTTOMLEFT", 0, -10)
        research_info:SetPoint("RIGHT", -15, 0)
        research_info:SetJustifyH("LEFT")
        research_info:SetText(
            "the research viewer allows you to view various talent and research trees (skyriding, delves, etc.) from anywhere. you can also open it by middle-clicking the sfui minimap icon.")

        local toggle_research_button = CreateFlatButton(research_panel, "open research viewer", 160, 22)
        toggle_research_button:SetPoint("TOPLEFT", research_info, "BOTTOMLEFT", 0, -20)
        toggle_research_button:SetScript("OnClick", function()
            if sfui.research and sfui.research.toggle_selection then
                sfui.research.toggle_selection()
                if options_frame then options_frame:Hide() end
            end
        end)

        local custom_header = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        custom_header:SetPoint("TOPLEFT", toggle_research_button, "BOTTOMLEFT", 0, -30)
        custom_header:SetTextColor(white[1], white[2], white[3])
        custom_header:SetText("manual tree entry")

        local custom_id_label = research_panel:CreateFontString(nil, "OVERLAY", g.font)
        custom_id_label:SetPoint("TOPLEFT", custom_header, "BOTTOMLEFT", 0, -10)
        custom_id_label:SetText("enter tree id:")

        local custom_id_input = CreateFrame("EditBox", nil, research_panel, "InputBoxTemplate")
        custom_id_input:SetPoint("LEFT", custom_id_label, "RIGHT", 10, 0)
        custom_id_input:SetSize(80, 32)
        custom_id_input:SetAutoFocus(false)

        local add_trait_button = CreateFlatButton(research_panel, "trait", 60, 22)
        add_trait_button:SetPoint("LEFT", custom_id_input, "RIGHT", 5, 0)
        add_trait_button:SetScript("OnClick", function()
            local id = tonumber(custom_id_input:GetText())
            if id and sfui.research and sfui.research.open_tree then
                sfui.research.open_tree({ id = id, isTraitTree = true, name = "Custom " .. id })
                if options_frame then options_frame:Hide() end
            end
        end)
        add_trait_button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("trait tree (skyriding, delves, etc.)")
                GameTooltip:Show()
            end
        end)
        add_trait_button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        local add_garr_button = CreateFlatButton(research_panel, "garr", 60, 22)
        add_garr_button:SetPoint("LEFT", add_trait_button, "RIGHT", 5, 0)
        add_garr_button:SetScript("OnClick", function()
            local id = tonumber(custom_id_input:GetText())
            if id and sfui.research and sfui.research.open_tree then
                sfui.research.open_tree({ id = id, isTraitTree = false, type = 111, name = "Custom " .. id })
                if options_frame then options_frame:Hide() end
            end
        end)
        add_garr_button:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("garrison / order hall / covenant tree")
                GameTooltip:Show()
            end
        end)
        add_garr_button:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end,
})
