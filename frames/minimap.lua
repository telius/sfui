local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = {}

-- ========================
-- Local Variables
-- ========================
local isInitialized = false
local collectAttempts = 0

local frame = CreateFrame("Frame", "SfuiMinimapFrame")

local zoom_timer = nil
local DEFAULT_ZOOM = sfui.config.minimap.defaultZoom or 0
local button_bar = nil

local function set_default_zoom()
    if zoom_timer then
        zoom_timer:Cancel()
        zoom_timer = nil
    end
    Minimap:SetZoom(DEFAULT_ZOOM)
end

local ButtonManager = {
    collectedButtons = {},
    processedButtons = {},
}

function sfui.minimap.initialize_masque()
    -- Global and local check handled by common.get_masque_group()
    sfui.minimap.masque_group = sfui.common.get_masque_group()
end

function ButtonManager:store_original_state(button)
    local name = button:GetName()
    if not name or self.processedButtons[name] then return end

    local orig = {
        parent = button:GetParent(),
        points = {},
        scale = button:GetScale(),
        strata = button:GetFrameStrata(),
        level = button:GetFrameLevel(),
    }
    for i = 1, button:GetNumPoints() do
        table.insert(orig.points, { button:GetPoint(i) })
    end
    button.sfuiOriginalState = orig
end

function ButtonManager:restore_button(button)
    if button and button.sfuiOriginalState then
        local orig = button.sfuiOriginalState
        button:SetParent(orig.parent)
        button:ClearAllPoints()
        for _, pointData in ipairs(orig.points) do
            button:SetPoint(unpack(pointData))
        end
        button:SetScale(orig.scale)
        button:SetFrameStrata(orig.strata)
        button:SetFrameLevel(orig.level)
        button.sfuiOriginalState = nil
    end
end

function ButtonManager:restore_all()
    for _, button in ipairs(self.collectedButtons) do
        self:restore_button(button)
    end
    wipe(self.collectedButtons)
    wipe(self.processedButtons)
end

local ignoreNameCache = {}
local validNameCache = {}

function ButtonManager:is_button(frame)
    if not frame or type(frame) ~= "table" then return false end

    if type(frame.GetName) ~= "function" then return false end
    local name = frame:GetName()
    if not name then return false end

    if ignoreNameCache[name] then return false end
    if validNameCache[name] then return true end

    if name:find("Minimap") or name:find("MinimapCluster") or name:find("GameTime") or name:find("MicroMenu") then
        ignoreNameCache[name] = true; return false
    end
    if name:find("OverrideActionBar") or name:find("MainMenuBar") or name:find("PetBattle") or name:find("MultiBar") then
        ignoreNameCache[name] = true; return false
    end
    if type(frame.IsObjectType) ~= "function" then return false end
    if not frame:IsObjectType("Button") and not frame:IsObjectType("CheckButton") then return false end
    if type(frame.GetScript) ~= "function" or (not frame:GetScript("OnClick") and not frame:GetScript("OnMouseDown") and not frame:GetScript("OnMouseUp")) then
        return false
    end
    if type(frame.GetNumRegions) ~= "function" or frame:GetNumRegions() == 0 then return false end

    validNameCache[name] = true
    return true
end

function ButtonManager:add_button(button)
    if not self:is_button(button) then return end

    local name = button:GetName()
    if not name or self.processedButtons[name] then return end

    self:store_original_state(button)
    table.insert(self.collectedButtons, button)
    self.processedButtons[name] = true

    if not button.sfuiLayoutHooked then
        hooksecurefunc(button, "Show", function() ButtonManager:arrange_buttons() end)
        hooksecurefunc(button, "Hide", function() ButtonManager:arrange_buttons() end)
        button.sfuiLayoutHooked = true
    end
end

function ButtonManager:collect_buttons()
    local ldbi = LibStub("LibDBIcon-1.0", true)
    if ldbi then
        for _, buttonName in ipairs(ldbi:GetButtonList()) do
            local button = _G[buttonName]
            -- Note: LibDBIcon often names button "LibDBIcon10_AddonName"
            if button then self:add_button(button) end
        end
    end

    for i = 1, Minimap:GetNumChildren() do
        local child = select(i, Minimap:GetChildren())
        self:add_button(child)
    end

    if MinimapCluster then
        for i = 1, MinimapCluster:GetNumChildren() do
            local child = select(i, MinimapCluster:GetChildren())
            self:add_button(child)
        end
    end
end

function ButtonManager:skin_button(button)
    if not SfuiDB.minimap_masque then
        return
    end
    if not SfuiDB.minimap_masque then
        return
    end

    if button.SetBackdrop then button:SetBackdrop(nil) end

    local Masque = LibStub("Masque", true)
    if not Masque then return end

    -- Based on HidingBar's Masque integration
    local isButton = button:IsObjectType("Button")
    local normal, isNormalIcon = isButton and button:GetNormalTexture()
    local icon, highlight, pushed, border, background, iconMask

    local regions = { button:GetRegions() }

    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local name = region:GetDebugName()
            if name then
                name = name:gsub(".*%.", ""):lower()
            else
                name = ""
            end
            local texture = region:GetTexture()
            local tIsString = type(texture) == "string"
            if tIsString then texture = texture:lower() end
            local layer = region:GetDrawLayer()
            if texture == 136430 or tIsString and texture:find("minimap-trackingborder", 1, true) then
                border = region
            end
            if texture == 136467 or tIsString and texture:find("ui-minimap-background", 1, true) or name:find("background", 1, true) then
                background = region
            end
            if name:find("icon", 1, true) or not icon and tIsString and texture:find("icon", 1, true) then
                icon = region
            end
            if layer == "HIGHLIGHT" or not highlight and name:find("highlight", 1, true) then
                highlight = region
            end
        end
    end

    if normal and (not icon or icon ~= button.icon or icon == normal) then
        isNormalIcon = true
        icon = button:CreateTexture(nil, "BACKGROUND")
        local atlas = normal:GetAtlas()
        if atlas then
            icon:SetAtlas(atlas)
        else
            icon:SetTexture(normal:GetTexture())
        end
        icon:SetTexCoord(normal:GetTexCoord())
        icon:SetVertexColor(normal:GetVertexColor())
        icon:SetSize(normal:GetSize())
        for i = 1, normal:GetNumPoints() do
            icon:SetPoint(normal:GetPoint(i))
        end
    end

    local btnHighlight = isButton and button:GetHighlightTexture()
    if not highlight or highlight == btnHighlight then
        highlight = button:CreateTexture(nil, "HIGHLIGHT")
    end

    if icon then
        for i = 1, icon:GetNumMaskTextures() do
            local mask = icon:GetMaskTexture(i)
            local texture = mask:GetTexture()
            if texture == 130924 or type(texture) == "string" and texture:lower():find("tempportraitalphamask", 1, true) then
                iconMask = mask
                break
            end
        end
    else
        background = nil
    end

    sfui.common.sync_masque(button, { Icon = icon, Highlight = highlight, Border = border })

    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") and region ~= icon then region:SetTexture(nil) end
    end

    pushed = isButton and button:GetPushedTexture()
    if background or pushed or normal or btnHighlight or iconMask then
        if background then background:Hide() end
        if pushed then
            button.SetPushedTexture = function() end
            pushed:SetAlpha(0)
            pushed:SetTexture()
            pushed.SetAlpha = function() end
            pushed.SetAtlas = function() end
            pushed.SetTexture = function() end
        end
        if normal then
            if isNormalIcon then
                button.SetNormalTexture = function(_, value)
                    if not value then return end
                    if C_Texture.GetAtlasInfo(value) then
                        icon:SetAtlas(value)
                    else
                        icon:SetTexture(value)
                    end
                end
                button.SetNormalAtlas = function(_, atlas)
                    if atlas then
                        icon:SetAtlas(atlas)
                    end
                end
                normal.SetAtlas = function() end
                normal.SetTexture = function() end
            else
                button.SetNormalTexture = function() end
                button.SetNormalAtlas = function() end
                normal.SetAtlas = function() end
                normal.SetTexture = function() end
            end
        end
        if btnHighlight then
            button:UnlockHighlight()
            button.LockHighlight = function() end
            button.SetHighlightLocked = function() end
            button.SetHighlightTexture = function() end
            button.SetHighlightAtlas = function() end
            btnHighlight:SetAlpha(0)
            btnHighlight:SetTexture()
            btnHighlight.SetAlpha = function() end
            btnHighlight.SetAtlas = function() end
            btnHighlight.SetTexture = function() end
        end
        if iconMask then
            icon:RemoveMaskTexture(iconMask)
        end
    end

    if not SfuiDB.minimap_masque and icon then
        sfui.common.apply_square_icon_style(button, icon)
    end
end

function ButtonManager:arrange_buttons()
    if InCombatLockdown() then return end
    if not button_bar then return end

    if SfuiDB.minimap_button_order == nil then
        SfuiDB.minimap_button_order = {}
    end

    table.sort(self.collectedButtons, function(a, b)
        local aName = a:GetName() or ""
        local bName = b:GetName() or ""

        if aName == "LibDBIcon_sfui" then return false end
        if bName == "LibDBIcon_sfui" then return true end

        if #SfuiDB.minimap_button_order > 0 then
            local order = {}
            for i, name in ipairs(SfuiDB.minimap_button_order) do
                order[name] = i
            end
            local aOrder = order[aName] or 999
            local bOrder = order[bName] or 999
            if aOrder == bOrder then
                return aName < bName
            else
                return aOrder < bOrder
            end
        else
            return aName < bName
        end
    end)

    local lastButton = nil
    local cfg = sfui.config.minimap.button_bar
    local size = cfg.button_size
    local spacing = cfg.spacing

    for i, button in ipairs(self.collectedButtons) do
        button:SetParent(button_bar)
        if not button.isMoving then
            button:ClearAllPoints()
        end
        button:SetSize(size, size)

        self:skin_button(button)

        if not SfuiDB.minimap_masque and button.SetBackdrop then
            button:SetBackdrop({ edgeFile = sfui.config.textures.white, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
            sfui.common.set_color(button, "black")
        end

        if SfuiDB.minimap_rearrange then
            button:SetMovable(true)
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function(self)
                self.isMoving = true
                self:StartMoving()
                ButtonManager:arrange_buttons()
            end)
            button:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing(); self.isMoving = false
                local newIndex = 1
                for j, btn in ipairs(ButtonManager.collectedButtons) do
                    if self:GetCenter() > btn:GetCenter() then
                        newIndex =
                            j + 1
                    end
                end
                local oldIndex
                for j, btn in ipairs(ButtonManager.collectedButtons) do
                    if btn == self then
                        oldIndex = j; break
                    end
                end
                if oldIndex then
                    table.remove(ButtonManager.collectedButtons, oldIndex)
                    if newIndex > oldIndex then newIndex = newIndex - 1 end
                    if newIndex > #ButtonManager.collectedButtons + 1 then newIndex = #ButtonManager.collectedButtons + 1 end
                    if newIndex < 1 then newIndex = 1 end
                    table.insert(ButtonManager.collectedButtons, newIndex, self)
                    SfuiDB.minimap_button_order = {}
                    for _, btn in ipairs(ButtonManager.collectedButtons) do
                        table.insert(SfuiDB.minimap_button_order,
                            btn:GetName())
                    end
                    ButtonManager:arrange_buttons()
                else
                    ButtonManager:arrange_buttons()
                end
            end)
        else
            button:SetMovable(false)
            button:RegisterForDrag()
            button:SetScript("OnDragStart", nil)
            button:SetScript("OnDragStop", nil)
        end

        if not button.isMoving then
            if button:IsShown() then
                if not lastButton then
                    button:SetPoint("LEFT", button_bar, "LEFT", 5, 0)
                    lastButton = button
                elseif button ~= lastButton then
                    button:SetPoint("LEFT", lastButton, "RIGHT", spacing, 0)
                    lastButton = button
                end
            else
                button:SetPoint("LEFT", button_bar, "LEFT", 0, 0)
            end
        end
    end
end

function sfui.minimap.enable_button_manager(enabled)
    if enabled then
        if not button_bar then
            button_bar = CreateFrame("Frame", "sfui_minimap_button_bar", Minimap, "BackdropTemplate")
            button_bar:SetSize(sfui.config.minimap.default_size, 30)
            button_bar:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                tile = true,
                tileSize = 16,
            })
            button_bar:SetBackdropColor(0, 0, 0, 0.5) -- Semi-transparent black
        end

        -- Update position from saved coordinates
        button_bar:ClearAllPoints()
        button_bar:SetPoint(SfuiDB.minimap_button_point or "TOP", Minimap,
            SfuiDB.minimap_button_relative_point or "BOTTOM", SfuiDB.minimap_button_x or 0,
            SfuiDB.minimap_button_y or sfui.config.minimap.button_bar.defaultY)

        button_bar:Show()

        -- Mouseover logic
        if not button_bar.sfuiMouseoverHooked then
            -- Create an invisible detector frame over the Minimap to avoid HookScript on a secure frame
            if not sfui.minimap.detector then
                sfui.minimap.detector = CreateFrame("Frame", nil, Minimap)
                sfui.minimap.detector:SetAllPoints(Minimap)
                sfui.minimap.detector:SetFrameLevel(Minimap:GetFrameLevel() + 1)
                sfui.minimap.detector:EnableMouse(false) -- Pass through by default
            end

            local function update_alpha()
                if SfuiDB.minimap_buttons_mouseover then
                    local isHovering = button_bar:IsMouseOver() or Minimap:IsMouseOver()
                    if isHovering then
                        button_bar:SetAlpha(1)
                        if lib then -- lib is LibDBIcon if requested via LibStub
                            local LibDBIcon = LibStub("LibDBIcon-1.0", true)
                            if LibDBIcon and LibDBIcon.OnMinimapEnter then
                                pcall(LibDBIcon.OnMinimapEnter)
                            end
                        end
                    else
                        button_bar:SetAlpha(0)
                        if lib then
                            local LibDBIcon = LibStub("LibDBIcon-1.0", true)
                            if LibDBIcon and LibDBIcon.OnMinimapLeave then
                                pcall(LibDBIcon.OnMinimapLeave)
                            end
                        end
                    end
                else
                    button_bar:SetAlpha(1)
                end
            end

            button_bar:SetScript("OnEnter", update_alpha)
            button_bar:SetScript("OnLeave", function() C_Timer.After(0.1, update_alpha) end)

            -- Event-driven mouseover detection using Minimap frame
            -- This eliminates the 10Hz OnUpdate polling
            if Minimap then
                Minimap:HookScript("OnEnter", update_alpha)
                Minimap:HookScript("OnLeave", function() C_Timer.After(0.1, update_alpha) end)
            end

            button_bar.sfuiMouseoverHooked = true
        end

        -- Apply initial state
        if SfuiDB.minimap_buttons_mouseover then
            button_bar:SetAlpha(0)
        else
            button_bar:SetAlpha(1)
        end

        ButtonManager:collect_buttons()
        ButtonManager:arrange_buttons()

        if AddonCompartmentFrame then AddonCompartmentFrame:Hide() end
    else
        ButtonManager:restore_all()
        if button_bar then button_bar:Hide() end
        if AddonCompartmentFrame then AddonCompartmentFrame:Show() end
    end
end

function sfui.minimap.update_button_bar_position()
    if button_bar then
        button_bar:ClearAllPoints()
        button_bar:SetPoint(SfuiDB.minimap_button_point or "TOP", Minimap,
            SfuiDB.minimap_button_relative_point or "BOTTOM", SfuiDB.minimap_button_x or 0,
            SfuiDB.minimap_button_y or sfui.config.minimap.button_bar.defaultY)
    end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
frame:RegisterEvent("MINIMAP_UPDATE_ZOOM")
frame:RegisterEvent("ADDON_LOADED")

local startup_scans = 0
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        sfui.minimap.initialize_masque()
        set_default_zoom()
        sfui.minimap.enable_button_manager(SfuiDB.minimap_collect_buttons)

        if MinimapCluster and MinimapCluster.IndicatorFrame then
            MinimapCluster.IndicatorFrame:Hide(); MinimapCluster.IndicatorFrame:SetAlpha(0)
        end
        if MinimapCluster and MinimapCluster.BorderTop then
            MinimapCluster.BorderTop:Hide(); MinimapCluster.BorderTop:SetAlpha(0)
        end

        -- Startup timer to catch late-loading buttons
        if SfuiDB.minimap_collect_buttons then
            C_Timer.NewTicker(2, function(self)
                startup_scans = startup_scans + 1
                if startup_scans > 5 then
                    self:Cancel()
                else
                    ButtonManager:collect_buttons()
                    ButtonManager:arrange_buttons()
                end
            end)
        end

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        return
    end

    if event == "ADDON_LOADED" then
        if SfuiDB.minimap_collect_buttons then
            ButtonManager:collect_buttons()
            ButtonManager:arrange_buttons()
        end
        return
    end

    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
        set_default_zoom()
    elseif event == "MINIMAP_UPDATE_ZOOM" then
        if Minimap:GetZoom() ~= DEFAULT_ZOOM then
            if zoom_timer then
                zoom_timer:Cancel()
            end
            zoom_timer = C_Timer.NewTimer(5, set_default_zoom)
        end
    end
end)
