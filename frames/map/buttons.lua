local addonName, addon = ...
sfui = sfui or {}
sfui.minimap = sfui.minimap or {}

-- ========================
-- Localization
-- ========================
local _G = _G
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local tostring = _G.tostring
local unpack = _G.unpack
local table_insert = _G.table.insert
local table_remove = _G.table.remove
local table_sort = _G.table.sort
local table_wipe = _G.table.wipe
local math_max = _G.math.max
local InCombatLockdown = _G.InCombatLockdown
local CreateFrame = _G.CreateFrame
local LibStub = _G.LibStub
local hooksecurefunc = _G.hooksecurefunc
local C_Timer = _G.C_Timer
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster

local button_bar = nil

-- ------------------------------------------------------------------------------
-- ButtonManager Object Definition
-- ------------------------------------------------------------------------------
local ButtonManager = {
    collectedButtons = {},
    processedButtons = {},
    pendingArrange = false,
}
sfui.minimap.ButtonManager = ButtonManager

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
        table_insert(orig.points, { button:GetPoint(i) })
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
    table_wipe(self.collectedButtons)
    table_wipe(self.processedButtons)
end

local ignoreNameCache = {}
local validNameCache = {}

local KNOWN_ADDON_BUTTONS = {
    "BagSync_MinimapButton",
    "DBMMinimapButton",
    "WIM3MinimapButton",
    "HealBot_Button",
    "RecipeRadarMinimapButton",
    "AltoholicMinimapButton",
    "OutfitterMinimapButton",
    "ItemRack_Minimap",
    "TomTomMinimapButton",
    "ZGVMarker",
    "HandyNotes_MinimapButton",
    "RaiderIO_MinimapButton",
    "DetailsMinimapButton",
    "BigWigsMinimapButton",
    "WeakAurasMinimapButton",
    "PlaterMinimapButton",
    "BugSack",
    "BugGrabber",
    "PasteMinimapButton",
    "SimcMinimapButton",
    "PawnMinimapButton",
    "ArchyMinimapButton",
    "RareScannerMinimapIcon",
    "SilverDragonMinimapIcon",
    "QuestieFrame",
    "ZygorGuidesViewerMapIcon",
}

-- Blizzard Core Frame / Pin Blacklist (Strictly Blizzard frames only)
local BLIZZARD_IGNORE_PREFIXES = {
    "minimapcluster",
    "minimapbackdrop",
    "minimapcompass",
    "minimapzoomin",
    "minimapzoomout",
    "minimapnorthtag",
    "timemanager",
    "gametime",
    "queuestatus",
    "garrisonlanding",
    "expansionlanding",
    "minimaptracking",
    "minimapinstancedifficulty",
    "guildinstancedifficulty",
    "minimapchallengemode",
    "minimapworldmap",
    "blizzard_",
    "diel",
}

function ButtonManager:is_button(frame)
    if not frame or type(frame) ~= "table" then return false end

    -- NEVER touch forbidden/protected frames or MapCanvas/AreaPOI pin frames
    if frame.IsForbidden and frame:IsForbidden() then return false end
    if frame.IsProtected and frame:IsProtected() then return false end
    if frame.dataProvider or frame.owningMap or frame.pinTemplate or frame.GetMap or
        frame.pinFrameLevelType or frame.normalizedX or frame.poiInfo or frame.isPin or
        frame.superTracked or frame.textureKit or frame.GetElementData or frame.nudgeTargetFactor or
        frame.vignetteInfo or frame.areaPoiID or frame.questID then
        return false
    end

    local name = frame.GetName and frame:GetName()
    if not name or type(name) ~= "string" or name == "" then
        return false
    end

    -- Fast-track LibDBIcon buttons (always valid addon buttons)
    if name:find("^LibDBIcon10_") or name:find("^LibDBIcon") then
        validNameCache[name] = true
        return true
    end

    if ignoreNameCache[name] then return false end
    if validNameCache[name] then return true end

    -- NEVER collect SFUI's own internal frames or buttons
    if name:find("^sfui") then
        ignoreNameCache[name] = true
        return false
    end

    local lowerName = name:lower()

    -- Filter out Blizzard internal/protected buttons and all map pin/POI variations
    for _, prefix in ipairs(BLIZZARD_IGNORE_PREFIXES) do
        if lowerName:find(prefix, 1, true) then
            ignoreNameCache[name] = true
            return false
        end
    end

    if lowerName:find("poi") or lowerName:find("pin") or lowerName:find("canvas") or
        lowerName:find("vignette") or lowerName:find("worldquest") or lowerName:find("bonus") or
        lowerName:find("dungeon") or lowerName:find("delve") or lowerName:find("scenario") or
        lowerName:find("worldmap") or lowerName:find("overlay") then
        ignoreNameCache[name] = true
        return false
    end

    if type(frame.IsObjectType) ~= "function" then return false end
    if not frame:IsObjectType("Button") and not frame:IsObjectType("CheckButton") then return false end

    validNameCache[name] = true
    return true
end

function ButtonManager:add_button(button)
    if not self:is_button(button) then return false end

    local name = button:GetName()
    if not name or self.processedButtons[name] then return false end

    self:store_original_state(button)
    table_insert(self.collectedButtons, button)
    self.processedButtons[name] = true

    if not button.sfuiLayoutHooked then
        hooksecurefunc(button, "Show", function() ButtonManager:arrange_buttons() end)
        hooksecurefunc(button, "Hide", function() ButtonManager:arrange_buttons() end)
        button.sfuiLayoutHooked = true
    end
    return true
end

function ButtonManager:collect_buttons()
    local foundNew = false

    -- 1. LibDBIcon-1.0 registered objects (Details, WeakAuras, Raider.IO, BugSack, MRT, etc.)
    local ldbi = LibStub("LibDBIcon-1.0", true)
    if ldbi then
        if not sfui.minimap._ldbiHooked and ldbi.Register then
            sfui.minimap._ldbiHooked = true
            hooksecurefunc(ldbi, "Register", function()
                C_Timer.After(0.05, function()
                    ButtonManager:collect_buttons()
                    ButtonManager:arrange_buttons()
                end)
            end)
        end

        if ldbi.objects then
            for _, button in pairs(ldbi.objects) do
                if button and self:add_button(button) then foundNew = true end
            end
        end
    end

    -- 2. Whitelist of known standalone addon buttons
    for _, buttonName in ipairs(KNOWN_ADDON_BUTTONS) do
        local button = _G[buttonName]
        if button and self:add_button(button) then foundNew = true end
    end

    return foundNew
end

function ButtonManager:skin_button(button)
    if button.sfuiSkinned then return end

    local btnName = (button.GetName and button:GetName()) or ""
    local isButton = button:IsObjectType("Button")
    local normal = isButton and button:GetNormalTexture()
    local icon, highlight, pushed, border, background, iconMask

    local regions = { button:GetRegions() }

    -- 1. Identify icon: check common properties first, then inspect regions
    icon = button.icon or button.Icon or button.texture or button.Texture
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
            if texture == 136430 or (tIsString and texture:find("minimap-trackingborder", 1, true)) then
                border = region
            end
            if texture == 136467 or (tIsString and texture:find("ui-minimap-background", 1, true)) or name:find("background", 1, true) then
                background = region
            end
            if not icon and (name:find("icon", 1, true) or (tIsString and texture:find("icon", 1, true))) then
                icon = region
            end
            if layer == "HIGHLIGHT" or (not highlight and name:find("highlight", 1, true)) then
                highlight = region
            end
        end
    end

    -- Fallback: if icon is still not resolved, pick the first valid non-chrome texture
    if not icon then
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") and region ~= border and region ~= background and region ~= highlight and region ~= normal then
                if region:GetTexture() then
                    icon = region
                    break
                end
            end
        end
    end
    if not icon and normal and normal:GetTexture() then
        icon = normal
    end

    -- 2. Normalize and force all collected icons into SFUI square style
    if icon then
        icon:SetDrawLayer("ARTWORK", 1)
        icon:Show()

        -- Strip any circular mask textures (e.g. TempPortraitAlphaMask or custom masks)
        if icon.GetNumMaskTextures and icon.RemoveMaskTexture then
            for i = icon:GetNumMaskTextures(), 1, -1 do
                local mask = icon:GetMaskTexture(i)
                if mask then
                    icon:RemoveMaskTexture(mask)
                end
            end
        end

        -- Determine crop coordinates:
        -- Baked circular coin icons (like BugJar) need a deeper 22% crop to eliminate
        -- their outer ring, while standard WoW icons get the standard 7% square bevel crop.
        local isBakedCircle = btnName:find("BugJar", 1, true)
            or (icon:GetTexture() and tostring(icon:GetTexture()):lower():find("bugjar", 1, true))
            or btnName:find("HousingDecorGuide", 1, true)

        local cropL, cropR, cropT, cropB = 0.08, 0.92, 0.08, 0.92
        if isBakedCircle then
            cropL, cropR, cropT, cropB = 0.22, 0.78, 0.22, 0.78
        end

        -- Lock coordinates & override UpdateCoord so LibDBIcon or external code cannot revert it
        icon.UpdateCoord = function(self)
            self:SetTexCoord(cropL, cropR, cropT, cropB)
        end
        if not icon._sfuiCoordHooked then
            icon._sfuiCoordHooked = true
            local origSetTexCoord = icon.SetTexCoord
            icon.SetTexCoord = function(self, left, right, top, bottom)
                origSetTexCoord(self, cropL, cropR, cropT, cropB)
            end
        end
        icon:SetTexCoord(cropL, cropR, cropT, cropB)

        -- Re-anchor icon to fill the square frame cleanly flush
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
    end

    local Masque = SfuiDB and SfuiDB.minimap_masque and LibStub("Masque", true)
    if not Masque then
        -- Standard square styling if Masque is disabled or unavailable
        if icon then
            sfui.common.apply_square_icon_style(button, icon)
        end
        if border then border:SetTexture(nil) end
        if background then background:SetTexture(nil) end
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") and region ~= icon and region ~= highlight and region ~= normal then
                local tex = region:GetTexture()
                if tex == 136430 or tex == 136467 then
                    region:SetTexture(nil)
                end
            end
        end
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(math_max(20, button:GetFrameLevel()))
        button.sfuiSkinned = true
        return
    end

    if button.SetBackdrop then button:SetBackdrop(nil) end

    -- Based on HidingBar's Masque integration
    if normal and (not icon or icon ~= button.icon or icon == normal) then
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

    sfui.common.sync_masque(button, { Icon = icon, Highlight = highlight, Border = border })

    if border then border:SetTexture(nil) end
    if background then background:SetTexture(nil) end

    pushed = isButton and button:GetPushedTexture()
    if background then background:Hide() end
    if pushed then pushed:SetAlpha(0) end

    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(math_max(20, button:GetFrameLevel()))
    button.sfuiSkinned = true
end

function ButtonManager:arrange_buttons()
    if InCombatLockdown() then
        self.pendingArrange = true
        return
    end
    self.pendingArrange = false
    if not button_bar then return end

    if SfuiDB and SfuiDB.minimap_button_order == nil then
        SfuiDB.minimap_button_order = {}
    end

    local orderCache = {}
    if SfuiDB and SfuiDB.minimap_button_order and #SfuiDB.minimap_button_order > 0 then
        for i, name in ipairs(SfuiDB.minimap_button_order) do
            orderCache[name] = i
        end
    end

    table_sort(self.collectedButtons, function(a, b)
        local aName = a:GetName() or ""
        local bName = b:GetName() or ""

        if aName == "LibDBIcon_sfui" then return false end
        if bName == "LibDBIcon_sfui" then return true end

        if SfuiDB and SfuiDB.minimap_button_order and #SfuiDB.minimap_button_order > 0 then
            local aOrder = orderCache[aName] or 999
            local bOrder = orderCache[bName] or 999
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
    local cfg = sfui.config and sfui.config.minimap and sfui.config.minimap.button_bar or {}
    local size = cfg.button_size or 20
    local spacing = cfg.spacing or 8
    local padX = cfg.pad_x or 24

    for i, button in ipairs(self.collectedButtons) do
        button:SetParent(button_bar)
        if not button.isMoving then
            button:ClearAllPoints()
        end
        button:SetSize(size, size)

        self:skin_button(button)

        if SfuiDB and not SfuiDB.minimap_masque and button.SetBackdrop then
            button:SetBackdrop({ edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8", edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
            sfui.common.set_color(button, "black")
        end

        if SfuiDB and SfuiDB.minimap_rearrange then
            button:SetMovable(true)
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function(self)
                self.isMoving = true
                self:StartMoving()
                ButtonManager:arrange_buttons()
            end)
            button:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                self.isMoving = false
                local newIndex = 1
                for j, btn in ipairs(ButtonManager.collectedButtons) do
                    if self:GetCenter() > btn:GetCenter() then
                        newIndex = j + 1
                    end
                end
                local oldIndex
                for j, btn in ipairs(ButtonManager.collectedButtons) do
                    if btn == self then
                        oldIndex = j
                        break
                    end
                end
                if oldIndex then
                    table_remove(ButtonManager.collectedButtons, oldIndex)
                    if newIndex > oldIndex then newIndex = newIndex - 1 end
                    if newIndex > #ButtonManager.collectedButtons + 1 then newIndex = #ButtonManager.collectedButtons + 1 end
                    if newIndex < 1 then newIndex = 1 end
                    table_insert(ButtonManager.collectedButtons, newIndex, self)
                    SfuiDB.minimap_button_order = {}
                    for _, btn in ipairs(ButtonManager.collectedButtons) do
                        table_insert(SfuiDB.minimap_button_order, btn:GetName())
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
                    button:SetPoint("LEFT", button_bar, "LEFT", padX, 0)
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

    local clock = (sfui.minimap and sfui.minimap.system_button and sfui.minimap.system_button:IsShown() and sfui.minimap.system_button) or _G.TimeManagerClockButton
    local isClockInside = clock and clock:IsShown() and clock:GetParent() == button_bar
    local clockWidth = isClockInside and (clock:GetWidth() > 0 and clock:GetWidth() or 48) or 0

    local status_container = sfui.minimap.status_container or (sfui.minimap.get_status_container and sfui.minimap.get_status_container())
    local isStatusInside = status_container and status_container:IsShown() and status_container:GetParent() == button_bar
    local statusWidth = isStatusInside and (status_container:GetWidth() > 0 and (status_container:GetWidth() + 6) or 0) or 0

    local indicator = (MinimapCluster and MinimapCluster.IndicatorFrame) or _G.MinimapIndicatorFrame
    local mailFrame = (indicator and indicator.MailFrame) or _G.MiniMapMailFrame or indicator
    local isMailInside = button_bar and ((indicator and indicator:GetParent() == button_bar and indicator:IsShown()) or (mailFrame and mailFrame:GetParent() == button_bar and mailFrame:IsShown()))
    local mailWidth = isMailInside and (indicator and indicator:GetWidth() > 0 and (indicator:GetWidth() + 8) or 26) or 0

    local rightReserved = isClockInside and (clockWidth + 14 + statusWidth + mailWidth) or (padX + statusWidth + mailWidth)

    local mapWidth = (Minimap and Minimap:GetWidth() and Minimap:GetWidth() > 0) and Minimap:GetWidth()
        or (SfuiDB and SfuiDB.minimap_width)
        or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
        or 220
    button_bar:SetWidth(mapWidth)
end

sfui.minimap.arrange_buttons = function()
    ButtonManager:arrange_buttons()
end

-- ------------------------------------------------------------------------------
-- Button Bar Management
-- ------------------------------------------------------------------------------
function sfui.minimap.update_button_bar_position()
    if button_bar then
        local isSquare = sfui.map and sfui.map.square and sfui.map.square.IsEnabled and sfui.map.square:IsEnabled()
        local barWidth = (SfuiDB and SfuiDB.minimap_width)
            or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
            or (Minimap and Minimap:GetWidth() and Minimap:GetWidth() > 0 and Minimap:GetWidth())
            or 220
        button_bar:SetWidth(barWidth)
        local anchorTarget = (not isSquare and MinimapCluster and MinimapCluster.MinimapContainer) or Minimap
        button_bar:ClearAllPoints()
        button_bar:SetPoint(
            (SfuiDB and SfuiDB.minimap_button_point) or "TOP",
            anchorTarget,
            (SfuiDB and SfuiDB.minimap_button_relative_point) or "BOTTOM",
            (SfuiDB and SfuiDB.minimap_button_x) or
            (sfui.config and sfui.config.minimap and sfui.config.minimap.button_bar and sfui.config.minimap.button_bar.defaultX) or
            0,
            (SfuiDB and SfuiDB.minimap_button_y) or
            (sfui.config and sfui.config.minimap and sfui.config.minimap.button_bar and sfui.config.minimap.button_bar.defaultY) or
            30
        )
        sfui.minimap.update_clock_position()
    end
end

function sfui.minimap.enable_button_manager(enabled)
    if enabled then
        if not button_bar then
            -- Parent to MinimapCluster instead of Minimap to avoid protected frame taint
            button_bar = CreateFrame("Frame", "sfui_minimap_button_bar", MinimapCluster, "BackdropTemplate")
            local mapWidth = (Minimap and Minimap:GetWidth() and Minimap:GetWidth() > 0) and Minimap:GetWidth()
                or (SfuiDB and SfuiDB.minimap_width)
                or (sfui.config and sfui.config.minimap and (sfui.config.minimap.width or sfui.config.minimap.default_size))
                or 220
            button_bar:SetSize(mapWidth, 36)
            sfui.theme.ApplyMinimapButtonBarStyle(button_bar)
            sfui.minimap.button_bar = button_bar
        end

        -- Update position and width from saved coordinates
        sfui.minimap.update_button_bar_position()

        button_bar:Show()

        -- Mouseover logic
        if not button_bar.sfuiMouseoverHooked then
            local function update_alpha()
                if SfuiDB and SfuiDB.minimap_buttons_mouseover then
                    local isHovering = button_bar:IsMouseOver() or Minimap:IsMouseOver()
                    if isHovering then
                        button_bar:SetAlpha(1)
                        if not sfui.minimap.ldbi then
                            sfui.minimap.ldbi = LibStub("LibDBIcon-1.0", true)
                        end
                        if sfui.minimap.ldbi and sfui.minimap.ldbi.OnMinimapEnter then
                            sfui.minimap.ldbi:OnMinimapEnter()
                        end
                    else
                        button_bar:SetAlpha(0)
                        if not sfui.minimap.ldbi then
                            sfui.minimap.ldbi = LibStub("LibDBIcon-1.0", true)
                        end
                        if sfui.minimap.ldbi and sfui.minimap.ldbi.OnMinimapLeave then
                            sfui.minimap.ldbi:OnMinimapLeave()
                        end
                    end
                else
                    button_bar:SetAlpha(1)
                end
            end

            button_bar:SetScript("OnEnter", update_alpha)
            button_bar:SetScript("OnLeave", function() C_Timer.After(0.1, update_alpha) end)

            button_bar.sfuiMouseoverHooked = true
        end

        -- Apply initial state
        if SfuiDB and SfuiDB.minimap_buttons_mouseover then
            button_bar:SetAlpha(0)
        else
            button_bar:SetAlpha(1)
        end

        ButtonManager:collect_buttons()
        ButtonManager:arrange_buttons()

        if _G.AddonCompartmentFrame then _G.AddonCompartmentFrame:Hide() end
        sfui.minimap.update_clock_position()
        if sfui.minimap.update_status then
            sfui.minimap.update_status()
        end
        if sfui.minimap.update_indicator_positions then
            sfui.minimap.update_indicator_positions()
        end
    else
        ButtonManager:restore_all()
        if button_bar then button_bar:Hide() end
        if _G.AddonCompartmentFrame then _G.AddonCompartmentFrame:Show() end
        if sfui.minimap.system_button then
            sfui.minimap.system_button:Hide()
        end
        local clock = _G.TimeManagerClockButton
        if clock then
            clock.sfuiRepositioning = true
            clock:ClearAllPoints()
            clock:SetParent(MinimapCluster or Minimap)
            clock:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -2)
            clock.sfuiRepositioning = nil
            clock.sfuiAnchored = nil
            clock:Show()
        end
        if sfui.minimap.update_status then
            sfui.minimap.update_status()
        end
        if sfui.minimap.update_indicator_positions then
            sfui.minimap.update_indicator_positions()
        end
    end
end

-- ------------------------------------------------------------------------------
-- TimeManager Clock Management
-- ------------------------------------------------------------------------------
function sfui.minimap.update_clock_position()
    if not button_bar then return end

    if sfui.minimap.update_system_button then
        sfui.minimap.update_system_button(button_bar)
        local clock = _G.TimeManagerClockButton
        if clock and clock.Hide then
            clock:Hide()
        end
        if sfui.minimap.update_status then
            sfui.minimap.update_status()
        end
        if sfui.minimap.update_indicator_positions then
            sfui.minimap.update_indicator_positions()
        end
        return
    end

    local clock = _G.TimeManagerClockButton
    if not clock then
        if not sfui.common.ensure_addon_loaded("Blizzard_TimeManager") and _G.UIParentLoadAddOn then
            _G.UIParentLoadAddOn("Blizzard_TimeManager")
        end
        clock = _G.TimeManagerClockButton
    end

    if not clock or not button_bar then return end

    local isClockEnabled = true
    if _G.GetCVarBool then
        local show = _G.GetCVarBool("showClock")
        if show ~= nil then isClockEnabled = show end
    end

    if not isClockEnabled then
        clock:Hide()
        return
    end

    clock:SetParent(button_bar)
    clock:SetFrameStrata(button_bar:GetFrameStrata())
    clock:SetFrameLevel(button_bar:GetFrameLevel() + 5)

    if not clock.sfuiAnchored then
        -- Strip default background textures for clean text appearance
        local regions = { clock:GetRegions() }
        for _, region in ipairs(regions) do
            if region:IsObjectType("Texture") then
                local tex = region:GetTexture()
                if tex and type(tex) == "string" and (tex:lower():find("timemanager") or tex:lower():find("clock")) then
                    region:SetTexture(nil)
                    region:SetAlpha(0)
                end
            end
        end

        if _G.TimeManagerClockTicker then
            _G.TimeManagerClockTicker:ClearAllPoints()
            _G.TimeManagerClockTicker:SetPoint("CENTER", clock, "CENTER", 0, 0)
        end

        hooksecurefunc(clock, "SetPoint", function(self)
            if self.sfuiRepositioning or not button_bar or not button_bar:IsShown() then return end
            self.sfuiRepositioning = true
            self:ClearAllPoints()
            self:SetPoint("RIGHT", button_bar, "RIGHT", -8, 2)
            self.sfuiRepositioning = nil
        end)

        clock.sfuiAnchored = true
    end

    if _G.TimeManagerClockTicker then
        _G.TimeManagerClockTicker:ClearAllPoints()
        _G.TimeManagerClockTicker:SetPoint("CENTER", clock, "CENTER", 0, 0)
        local tickerW = (_G.TimeManagerClockTicker.GetStringWidth and _G.TimeManagerClockTicker:GetStringWidth()) or 40
        clock:SetSize(math_max(44, tickerW + 8), 20)
    end

    clock.sfuiRepositioning = true
    clock:ClearAllPoints()
    clock:SetPoint("RIGHT", button_bar, "RIGHT", -8, 2)
    clock.sfuiRepositioning = nil
    clock:Show()

    if sfui.minimap.update_status then
        sfui.minimap.update_status()
    end
    if sfui.minimap.update_indicator_positions then
        sfui.minimap.update_indicator_positions()
    end
end

-- ------------------------------------------------------------------------------
-- Event Listeners for Buttons & Clock
-- ------------------------------------------------------------------------------
sfui.events.RegisterEvent("ADDON_LOADED", function(_, loadedAddon)
    if loadedAddon == "Blizzard_TimeManager" then
        sfui.minimap.update_clock_position()
    end
    if SfuiDB and SfuiDB.minimap_collect_buttons then
        if ButtonManager:collect_buttons() then
            ButtonManager:arrange_buttons()
        end
    end
end)

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if ButtonManager.pendingArrange then
        ButtonManager:arrange_buttons()
    end
end)
