sfui = sfui or {}
sfui.automation = {}

local function on_role_check_show()
    if not SfuiDB.auto_role_check then return end
    if CompleteLFGRoleCheck then
        pcall(CompleteLFGRoleCheck, true)
    end
end


local function on_lfg_double_click(self)
    if not SfuiDB.auto_sign_lfg then return end
    if IsShiftKeyDown() then return end

    local result_exists = not LFGListFrame.SearchPanel.SignUpButton.tooltip
    if result_exists then
        LFGListSearchPanel_SignUp(self:GetParent():GetParent():GetParent())
    end
end

local function initialize_lfg_buttons()
    if not LFGListFrame or not LFGListFrame.SearchPanel or not LFGListFrame.SearchPanel.ScrollBox then
        return
    end

    local scroll_target = LFGListFrame.SearchPanel.ScrollBox:GetScrollTarget()
    if not scroll_target then return end

    local buttons = { scroll_target:GetChildren() }
    for _, child in ipairs(buttons) do
        if child and child:GetObjectType() == "Button" and not child.sfui_automation_init then
            child:SetScript("OnDoubleClick", on_lfg_double_click)
            child:RegisterForClicks("AnyUp")
            child.sfui_automation_init = true
        end
    end
end

local function setup_lfg_dialog()
    if LFGListApplicationDialog then
        LFGListApplicationDialog:HookScript("OnShow", function(self)
            if not SfuiDB.auto_sign_lfg then return end
            if IsShiftKeyDown() then return end

            if self.SignUpButton and self.SignUpButton:IsEnabled() then
                self.SignUpButton:Click()
            end
        end)
    end
end

function sfui.automation.initialize()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    frame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
    frame:RegisterEvent("PLAYER_LOGIN")

    frame:SetScript("OnEvent", function(self, event)
        if event == "LFG_ROLE_CHECK_SHOW" then
            C_Timer.After(0.1, on_role_check_show)
        elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
            C_Timer.After(0.1, initialize_lfg_buttons)
        elseif event == "PLAYER_LOGIN" then
            setup_lfg_dialog()
        end
    end)
end
