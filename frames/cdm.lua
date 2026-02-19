local addonName, addon = ...
sfui = sfui or {}
sfui.cdm = {}

local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local UIParent = UIParent
local C_Spell = C_Spell
local C_Item = C_Item
local C_Timer = C_Timer

-- Local references to common utilities
local CreateFlatButton = sfui.common.create_flat_button
local issecretvalue = sfui.common.issecretvalue
local g = sfui.config
local c = g.options_panel

local function AddVerticalAccent(frame)
    if not frame then return end
    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(0.4, 0, 1, 1) -- Purple accent
    frame.accent = accent
end

local function IsValidID(id)
    if not id then return false end
    local nid = tonumber(id)
    return nid and nid >= -2147483648 and nid <= 2147483647
end

-- Layout Constants
local ICON_SIZE          = 30
local ICON_SPACING       = 2

-- Main Container
local cdmFrame           = nil
local poolFrame          = nil
local zonesFrame         = nil

-- Data Storage for Dragging
local draggedInfo        = nil
local selectedPanelIndex = nil -- Index of panel being edited in settings below
local selectedPanelData  = nil -- Data of selected panel (or true for Tracked Bars)

-- Frame Pools (avoid GC churn on refresh)
local zoneIconFrames     = {}
local zoneIconCount      = 0

-- Forward Declarations (must be before AcquirePoolIcon closures)
local RefreshZones
local OnIconDragStart
local OnIconDragStop
local OnZoneReceiveDrag
local HandleExternalDrop

local function AcquireZoneIcon(parent)
    zoneIconCount = zoneIconCount + 1
    local icon = zoneIconFrames[zoneIconCount]
    if not icon then
        icon = CreateFrame("Button", nil, parent)
        icon:SetSize(ICON_SIZE, ICON_SIZE)

        local bb = icon:CreateTexture(nil, "BACKGROUND")
        bb:SetAllPoints()
        bb:SetColorTexture(0, 0, 0, 1)
        bb:Hide()
        icon.borderBackdrop = bb

        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        icon.texture = tex

        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        zoneIconFrames[zoneIconCount] = icon
    end

    if sfui.trackedicons and sfui.trackedicons.ApplyIconBorderStyle then
        sfui.trackedicons.ApplyIconBorderStyle(icon, SfuiDB.iconGlobalSettings)
    end
    -- Enforce borderless logic removed to respect user settings

    sfui.common.sync_masque(icon, { Icon = icon.texture })

    icon:SetParent(parent)
    icon:ClearAllPoints()
    icon:Show()
    return icon
end

-- ... (skipping to HandleExternalDrop updates)

local function ResetBucketPool()
    for i = 1, #zoneIconFrames do zoneIconFrames[i]:Hide() end
    zoneIconCount = 0
end

-- ----------------------------------------------------------------------------
-- Initialization & Layout
-- ----------------------------------------------------------------------------

function sfui.cdm.RefreshZones()
    if RefreshZones then RefreshZones() end
end

-- Layout Constants
local PANEL_LIST_W = 360 -- Left column: panel list
local SETTINGS_W = 370   -- Right column: settings
local GAP = 10

function sfui.cdm.create_panel(parent)
    if cdmFrame then
        cdmFrame:SetParent(parent)
        cdmFrame:SetAllPoints(parent)
        cdmFrame:Show()
        sfui.cdm.RefreshLayout()
        return cdmFrame
    end

    cdmFrame = CreateFrame("Frame", "SfuiCDMPanel", parent)
    cdmFrame:SetAllPoints(parent)

    -- Global Drag Cleanup
    cdmFrame:SetScript("OnMouseUp", function()
        if draggedInfo then
            if draggedInfo.cursor then draggedInfo.cursor:Hide() end
            draggedInfo = nil
        end
    end)

    -- ─── Left Column: Panel List ─────────────────────────────────────────────
    local leftScroll = CreateFrame("ScrollFrame", "SfuiCDMLeftScroll", cdmFrame, "UIPanelScrollFrameTemplate")
    leftScroll:SetPoint("TOPLEFT", 5, -5)
    leftScroll:SetPoint("BOTTOMLEFT", 5, 5)
    leftScroll:SetWidth(PANEL_LIST_W - 20) -- Move scrollbar 20px left by reducing width

    local leftContent = CreateFrame("Frame", nil, leftScroll)
    leftContent:SetSize(PANEL_LIST_W - 20, 2000)
    leftScroll:SetScrollChild(leftContent)
    cdmFrame.leftContent = leftContent

    -- ─── Right Column: Settings ───────────────────────────────────────────────
    local rightScroll = CreateFrame("ScrollFrame", "SfuiCDMRightScroll", cdmFrame, "UIPanelScrollFrameTemplate")
    rightScroll:SetPoint("TOPLEFT", 5 + PANEL_LIST_W + GAP, -5)
    rightScroll:SetPoint("BOTTOMRIGHT", -25, 5)

    local rightContent = CreateFrame("Frame", nil, rightScroll)
    rightContent:SetSize(SETTINGS_W, 3000)
    rightScroll:SetScrollChild(rightContent)
    cdmFrame.rightContent = rightContent

    -- ─── Divider ──────────────────────────────────────────────────────────────
    local divider = cdmFrame:CreateTexture(nil, "ARTWORK")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", 5 + PANEL_LIST_W + 5, -5)
    divider:SetPoint("BOTTOMLEFT", 5 + PANEL_LIST_W + 5, 5)
    divider:SetColorTexture(0.4, 0, 1, 0.5)

    function sfui.cdm.RefreshLayout()
        ResetBucketPool()
        RefreshZones()
        -- Resize left content to actual zone height
        local kids = { leftContent:GetChildren() }
        local maxBottom = 0
        for _, k in ipairs(kids) do
            if k:IsShown() then
                local _, _, _, _, y = k:GetPoint(1)
                maxBottom = math.max(maxBottom, math.abs(y or 0) + k:GetHeight())
            end
        end
        leftContent:SetHeight(math.max(maxBottom + 50, 200))
    end

    cdmFrame:SetScript("OnShow", sfui.cdm.RefreshLayout)
    cdmFrame:SetScript("OnHide", function()
        if draggedInfo then OnIconDragStop(draggedInfo.icon) end
    end)

    sfui.cdm.RefreshLayout()
    return cdmFrame
end

-- ----------------------------------------------------------------------------
-- Logic
-- ----------------------------------------------------------------------------

local function CreateZone(parent, name, yPos, xPos, width, panelData, isTrackedBars, panelIndex)
    local zone = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    zone:SetPoint("TOPLEFT", xPos, yPos)
    zone:SetSize(width or 400, 92)
    zone:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
    })
    AddVerticalAccent(zone)

    -- Visual Style
    if isTrackedBars then
        zone:SetBackdropColor(0.06, 0, 0.12, 0.9) -- Dark Purple tint
        zone:SetBackdropBorderColor(0, 0, 0, 0)
    else
        zone:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
        zone:SetBackdropBorderColor(0, 0, 0, 0)
    end

    local label = zone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 5, -5)

    if isTrackedBars then
        label:SetText("Tracked Bars")
        label:SetTextColor(0.4, 0, 1, 1) -- Purple accent
    else
        label:SetText(panelData.name or "Unnamed Panel")
        label:SetTextColor(0.4, 0, 1, 1) -- Purple accent
    end

    -- Selection Checkbox (Right side)
    local sel = sfui.common.create_checkbox(zone, "Edit",
        function()
            return selectedPanelIndex == panelIndex
        end,
        function(val)
            if val then
                selectedPanelIndex = panelIndex
                selectedPanelData = isTrackedBars and true or panelData
            else
                if selectedPanelIndex == panelIndex then
                    selectedPanelIndex = nil
                    selectedPanelData = nil
                end
            end
            sfui.cdm.RefreshLayout()
        end)
    sel:SetPoint("BOTTOMRIGHT", -5, 5)

    -- Customize label position and color
    if sel.text then
        sel.text:ClearAllPoints()
        sel.text:SetPoint("BOTTOM", sel, "TOP", 0, 2)
        sel.text:SetTextColor(1, 1, 1, 1) -- White
    end

    zone.selCheck = sel

    if not isTrackedBars then
        -- Delete Button for custom panels
        local isBuiltIn = (name == "CENTER" or name == "UTILITY" or name == "Left" or name == "Right")
        if not isBuiltIn and panelIndex then
            local del = CreateFrame("Button", nil, zone)
            del:SetSize(16, 16)
            del:SetPoint("TOPRIGHT", -5, -5)
            del:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            del:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
            del:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
            del:SetScript("OnClick", function()
                if sfui.common.delete_custom_panel(panelIndex) then
                    sfui.cdm.RefreshLayout()
                end
            end)
            zone.deleteBtn = del
        end
    end

    -- Import Dropdown
    local options = {
        { text = "Import: Essential",    value = 0 },
        { text = "Import: Utility",      value = 1 },
        { text = "Import: Buffs",        value = 2 },
        { text = "Import: Tracked Bars", value = 3 },
    }
    local importBtn = sfui.common.create_dropdown(zone, 80, options, function(gId)
        if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then return end
        local list = C_CooldownViewer.GetCooldownViewerCategorySet(gId, false)
        if not list then return end

        local entries = isTrackedBars and SfuiDB.trackedBars or (panelData and panelData.entries)
        local dp = (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) and
            CooldownViewerSettings:GetDataProvider()
        if dp then
            for _, cooldownID in ipairs(list) do
                if not sfui.common.issecretvalue(cooldownID) then
                    if not IsValidID(cooldownID) then
                        print("|cffff0000SFUI CDM Error:|r Skipping invalid ID " ..
                            tostring(cooldownID) .. " (outside 32-bit range)")
                    else
                        local entry = { id = cooldownID, type = "cooldown", cooldownID = cooldownID }
                        if isTrackedBars then
                            entries[cooldownID] = entry
                        else
                            local exists = false
                            for _, val in ipairs(entries) do
                                local existingId = (type(val) == "table" and val.id) or val
                                if existingId == cooldownID then
                                    exists = true; break
                                end
                            end
                            if not exists then table.insert(entries, entry) end
                        end
                    end
                end
            end
        end
        sfui.cdm.RefreshLayout()
        -- Also refresh the visual icons in the panels if they are active
        if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
        if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
    end)
    importBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Content Area for current icons
    local content = CreateFrame("Frame", nil, zone)
    content:SetPoint("TOPLEFT", 5, -25)
    content:SetPoint("BOTTOMRIGHT", -5, 5)

    zone.panelEntries = isTrackedBars and SfuiDB.trackedBars or (panelData and panelData.entries)

    -- Populate Existing Icons
    local entries = isTrackedBars and SfuiDB.trackedBars or (panelData and panelData.entries)
    local x, y = 0, 0
    local icons = {}

    -- Helper to get texture
    local function GetIconTexture(cdID)
        local id = (type(cdID) == "table" and cdID.id) or cdID
        local typeStr = (type(cdID) == "table" and cdID.type) or "spell"
        local entry = (type(cdID) == "table") and cdID or { id = id, type = typeStr }

        if sfui.trackedicons and sfui.trackedicons.GetIconTexture then
            local tex, _ = sfui.trackedicons.GetIconTexture(id, typeStr, entry)
            return tex or 134400
        end
        return 134400
    end

    if entries then
        -- Handle TrackedBars structure (map[id] = true/table) vs Panel structure (list of ids)
        local list = {}
        if isTrackedBars then
            for id, enabled in pairs(entries) do
                if enabled and IsValidID(id) then
                    table.insert(list, tonumber(id))
                end
            end
        else
            list = entries
        end

        for _, cdID in ipairs(list) do
            local icon = AcquireZoneIcon(content)
            icon:SetPoint("TOPLEFT", x, y)
            icon.texture:SetTexture(GetIconTexture(cdID))


            -- Right click to delete
            icon:RegisterForClicks("RightButtonUp")
            icon:SetScript("OnClick", function()
                if isTrackedBars then
                    entries[cdID] = nil
                    if not next(entries) then SfuiDB.trackedBars = {} end -- Clean up empty
                    -- Force update bars
                    if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
                    if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
                else
                    -- Remove from array
                    for i, val in ipairs(entries) do
                        local entryId = (type(val) == "table" and val.id) or val
                        local targetId = (type(cdID) == "table" and cdID.id) or cdID
                        if entryId == targetId then
                            table.remove(entries, i)
                            break
                        end
                    end
                    -- Update Panels
                    if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
                end
                RefreshZones() -- Redraw
            end)

            -- Tooltip for existing icons
            icon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

                local id = (type(cdID) == "table" and cdID.id) or cdID
                local entry = (type(cdID) == "table") and cdID or { id = id, type = "spell" }

                if entry.type == "cooldown" or entry.cooldownID then
                    local cdInfo = C_CooldownViewer and
                        C_CooldownViewer.GetCooldownViewerCooldownInfo(entry.cooldownID or id)
                    if cdInfo then
                        if cdInfo.spellID then
                            GameTooltip:SetSpellByID(cdInfo.spellID)
                        elseif cdInfo.itemID then
                            GameTooltip:SetItemByID(cdInfo.itemID)
                        end

                        GameTooltip:AddLine(" ")
                        GameTooltip:AddDoubleLine("Cooldown ID:", "|cffffffff" .. (entry.cooldownID or id) .. "|r")
                        if cdInfo.spellID then
                            GameTooltip:AddDoubleLine("Spell ID:",
                                "|cffffffff" .. cdInfo.spellID .. "|r")
                        end
                        if cdInfo.itemID then GameTooltip:AddDoubleLine("Item ID:", "|cffffffff" .. cdInfo.itemID .. "|r") end
                    else
                        GameTooltip:SetText("Cooldown " .. (entry.cooldownID or id))
                    end
                elseif entry.type == "item" then
                    if type(id) == "number" then
                        GameTooltip:SetItemByID(id)
                    else
                        GameTooltip:SetText("Item " .. tostring(id))
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Item ID:", "|cffffffff" .. tostring(id) .. "|r")
                else
                    if type(id) == "number" and id > 0 then
                        GameTooltip:SetSpellByID(id)
                    else
                        GameTooltip:SetText("Spell/ID " .. tostring(id))
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Spell ID:", "|cffffffff" .. tostring(id) .. "|r")
                end

                GameTooltip:Show()
            end)
            icon:SetScript("OnDragStart", function(self)
                OnIconDragStart(self, isTrackedBars)
            end)
            icon:SetScript("OnDragStop", function(self)
                OnIconDragStop(self)
            end)
            icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Drag Handling (Allow picking up from zones)
            icon:RegisterForDrag("LeftButton")
            icon:SetScript("OnDragStart", function(self)
                OnIconDragStart(self, isTrackedBars)
            end)
            icon:SetScript("OnDragStop", function(self)
                OnIconDragStop(self)
            end)

            -- Ensure it has the necessary info for dragging
            local iconId = (type(cdID) == "table" and cdID.id) or cdID
            local entry = (type(cdID) == "table") and cdID or { id = iconId, type = "spell" }

            icon.cooldownID = (type(cdID) == "table" and cdID.cooldownID) or iconId
            icon.info = {
                spellID = (type(cdID) == "table" and cdID.spellID) or (entry.type ~= "item" and iconId),
                itemID = (type(cdID) == "table" and cdID.itemID) or (entry.type == "item" and iconId),
                name = (C_Spell.GetSpellName(iconId) or C_Item.GetItemNameByID(iconId) or "Unknown")
            }

            x = x + ICON_SIZE + 2
            if x > 300 then
                x = 0; y = y - ICON_SIZE - 2
            end
        end
    end

    -- Drop Handler
    zone:SetScript("OnUpdate", function(self)
        if draggedInfo and self:IsMouseOver() then
            self:SetBackdropBorderColor(0, 1, 0, 1) -- Hover highlight
        else
            if isTrackedBars then
                self:SetBackdropBorderColor(0.8, 0.4, 1.0, 0.8)
            else
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end
    end)

    zone:SetScript("OnMouseUp", function(self)
        OnZoneReceiveDrag(self, panelData, isTrackedBars)
    end)

    -- Accept spells/items dragged from Blizzard UI (spellbook, bags, character panel)
    zone:SetScript("OnReceiveDrag", function(self)
        HandleExternalDrop(self, panelData, isTrackedBars)
    end)

    return zone
end

RefreshZones = function()
    local leftContainer  = cdmFrame and cdmFrame.leftContent
    local rightContainer = cdmFrame and cdmFrame.rightContent
    if not leftContainer then return end

    -- ── Clear Left (panels list) ──────────────────────────────────────────────
    if sfui.trackedoptions.ReleaseSettingsWidgets then
        sfui.trackedoptions.ReleaseSettingsWidgets(leftContainer)
    end
    leftContainer.zoneChildren = {}

    -- ── Clear Right (settings) ────────────────────────────────────────────────
    if rightContainer and sfui.trackedoptions.ReleaseSettingsWidgets then
        sfui.trackedoptions.ReleaseSettingsWidgets(rightContainer)
    end

    local currentY = -5
    local ZONE_H   = 92
    local ROW_GAP  = 8
    local ZONE_W   = PANEL_LIST_W - 22 -- leave room for scroll bar

    local function MakeZone(panelData, isTrackedBars, panelIndex)
        local zone = CreateZone(leftContainer, isTrackedBars and "Tracked Bars" or (panelData and panelData.name),
            currentY, 0, ZONE_W, panelData, isTrackedBars, panelIndex)



        if not selectedPanelIndex then
            selectedPanelIndex = panelIndex
            selectedPanelData = panelData
            if isTrackedBars then selectedPanelIndex = "TRACKED_BARS" end
        end

        -- ── Accent colour based on selection ─────────────────────────────────
        local isSelected = (selectedPanelIndex == panelIndex)
        if zone.accent then
            if isSelected then
                zone.accent:SetColorTexture(0, 1, 1, 1)   -- Cyan #00FFFF
            else
                zone.accent:SetColorTexture(0.4, 0, 1, 1) -- Purple
            end
        end

        if not leftContainer.zoneChildren then leftContainer.zoneChildren = {} end
        table.insert(leftContainer.zoneChildren, zone)

        currentY = currentY - ZONE_H - ROW_GAP
    end

    -- 1. Tracked Bars
    MakeZone(nil, true, "TRACKED_BARS")

    -- 2. All Panels
    local panels = sfui.common.get_cooldown_panels()
    if panels then
        for i, panel in ipairs(panels) do
            MakeZone(panel, false, i)
        end
    end

    -- 3. Add Panel row
    local addFrame = CreateFrame("Frame", nil, leftContainer, "BackdropTemplate")
    addFrame:SetSize(ZONE_W, 30)
    addFrame:SetPoint("TOPLEFT", 0, currentY - 8)
    addFrame:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
    addFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    addFrame:SetBackdropBorderColor(0, 0, 0, 0)
    AddVerticalAccent(addFrame)

    local eb = CreateFrame("EditBox", nil, addFrame)
    eb:SetSize(ZONE_W - 70, 20)
    eb:SetPoint("LEFT", 10, 0)
    eb:SetFontObject("ChatFontNormal")
    eb:SetTextColor(0.8, 0.8, 0.8)
    eb:SetMultiLine(false)
    eb:SetAutoFocus(false)
    eb:SetText("New Panel Name")
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEnterPressed", function(self)
        local name = self:GetText()
        if name and name ~= "" and name ~= "New Panel Name" then
            sfui.common.add_custom_panel(name)
            sfui.cdm.RefreshLayout()
        end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = sfui.common.create_flat_button(addFrame, "Add", 55, 20)
    addBtn:SetPoint("RIGHT", -5, 0)
    addBtn:SetBackdropBorderColor(0.4, 0, 1, 1)
    addBtn:SetScript("OnClick", function()
        local name = eb:GetText()
        if name and name ~= "" and name ~= "New Panel Name" then
            sfui.common.add_custom_panel(name)
            sfui.cdm.RefreshLayout()
        end
        eb:ClearFocus()
    end)
    currentY = currentY - 46

    leftContainer:SetHeight(math.abs(currentY) + 20)

    -- ── Render Settings on Right ──────────────────────────────────────────────
    if rightContainer then
        if selectedPanelData then
            sfui.trackedoptions.RenderPanelSettings(rightContainer, selectedPanelData, 0, -5, SETTINGS_W - 22)
        else
            -- Placeholder hint
            local hint = rightContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hint:SetPoint("TOP", 0, -30)
            hint:SetWidth(SETTINGS_W - 40)
            hint:SetTextColor(0.4, 0.4, 0.4, 1)

            if selectedPanelIndex == "TRACKED_BARS" then
                hint:SetText("Tracked Bars configuration has been moved to the 'Bars' tab in the main options window.")
            else
                hint:SetText("← Select a panel to configure it")
            end
        end
    end
end


-- ----------------------------------------------------------------------------
-- Logic Helpers
-- ----------------------------------------------------------------------------

local function PurgeIconFromEverywhere(targetId)
    if not targetId then return end

    -- 1. Purge from Tracked Bars
    if SfuiDB.trackedBars then
        SfuiDB.trackedBars[targetId] = nil
    end

    -- 2. Purge from Custom Panels
    local panels = sfui.common.get_cooldown_panels()
    if panels then
        for _, panel in ipairs(panels) do
            if panel.entries then
                for i = #panel.entries, 1, -1 do
                    local val = panel.entries[i]
                    local entryId = (type(val) == "table" and (val.cooldownID or val.id)) or val
                    if entryId == targetId then
                        table.remove(panel.entries, i)
                    end
                end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Drag Handlers
-- ----------------------------------------------------------------------------

OnIconDragStart = function(self, isFromTrackedBars)
    if InCombatLockdown() then return end

    if not cursor then
        cursor = CreateFrame("Frame", nil, UIParent)
        cursor:SetSize(ICON_SIZE, ICON_SIZE)
        cursor:SetFrameStrata("TOOLTIP")
        cursor.texture = cursor:CreateTexture(nil, "OVERLAY")
        cursor.texture:SetAllPoints()
    end

    cursor.texture:SetTexture(self.texture:GetTexture())
    cursor.texture:SetAlpha(0.7)

    cursor:EnableMouse(false) -- CRITICAL: Ghost must not block MouseUp events

    draggedInfo = {
        icon = self, -- Original icon
        cursor = cursor,
        info = self.info,
        cooldownID = self.cooldownID,
        isFromTrackedBars = isFromTrackedBars, -- NEW
        entry = (self.cooldownID) and { id = self.cooldownID, type = "cooldown", cooldownID = self.cooldownID } or nil,
        originalPanelEntries = self:GetParent().panelEntries,
        -- Store original position to snap back if needed?
        originalParent = self:GetParent(),
        originalPoint = "TOPLEFT",
        originalRelative = nil,
        originalX = 0,
        originalY = 0
    }

    -- Creating a ghost cursor follows mouse
    cursor:SetScript("OnUpdate", function(c)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        c:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    cursor:Show()

    -- Hide original? Or dim it?
    self:SetAlpha(0.5)
end

OnZoneReceiveDrag = function(zoneFrame, panelData, isTrackedBars)
    if not draggedInfo then return end

    local incomingId = draggedInfo.cooldownID or
        (draggedInfo.info and (draggedInfo.info.spellID or draggedInfo.info.itemID))

    if not incomingId then
        print("|cffFF0000SFUI Error:|r Invalid Icon ID")
        return
    end

    -- CRITICAL: Icons can only exist in ONE panel. Purge from everywhere else first.
    PurgeIconFromEverywhere(incomingId)

    if isTrackedBars then
        -- Add to tracked bars
        sfui.common.ensure_tracked_bar_db(incomingId)

        -- Update immediate
        if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
        if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end

        print("|cff00FF00SFUI:|r Added to Tracked Bars")
    else
        -- Add to panel
        if not panelData.entries then panelData.entries = {} end

        -- check dupe
        local exists = false
        for _, val in ipairs(panelData.entries) do
            local existingId = (type(val) == "table" and (val.cooldownID or val.id)) or val
            if existingId == incomingId then
                exists = true; break
            end
        end

        if not exists then
            local entry = draggedInfo.entry or {
                id = incomingId,
                type = (draggedInfo.info and draggedInfo.info.itemID) and "item" or
                    (draggedInfo.cooldownID and "cooldown" or "spell"),
                cooldownID = draggedInfo.cooldownID
            }
            table.insert(panelData.entries, entry)

            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            print("|cff00FF00SFUI:|r Added to " .. panelData.name)
        end
    end

    -- We don't call OnIconDragStop here because OnDragStop will trigger on the icon itself
end

OnIconDragStop = function(self)
    if not draggedInfo then return end

    -- Capture info for cleanup
    local targetCursor = draggedInfo.cursor
    local targetIcon = draggedInfo.icon

    -- Hit-test Zones
    local dropTargetZone = nil
    local container = cdmFrame and cdmFrame.leftContent
    if container and container.zoneChildren then
        for _, zone in ipairs(container.zoneChildren) do
            if zone:IsVisible() and zone:IsMouseOver() then
                dropTargetZone = zone
                break
            end
        end
    end

    if dropTargetZone then
        -- Trigger drop (wrapped in pcall for safety)
        local script = dropTargetZone:GetScript("OnMouseUp")
        if script then pcall(script, dropTargetZone) end
    else
        -- Dropped in empty space (Trash)
        if draggedInfo.originalPanelEntries then
            local source = draggedInfo.originalPanelEntries
            local targetId = draggedInfo.cooldownID or
                (draggedInfo.info and (draggedInfo.info.spellID or draggedInfo.info.itemID))

            if targetId then
                if draggedInfo.isFromTrackedBars then
                    source[targetId] = nil
                else
                    for i = #source, 1, -1 do
                        local val = source[i]
                        local entryId = (type(val) == "table" and (val.cooldownID or val.id)) or val
                        if entryId == targetId then
                            table.remove(source, i)
                        end
                    end
                end

                if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
                print("|cffFF0000SFUI:|r Removed from Zone")
            end
        end
    end

    -- ALWAYS Cleanup drag
    if targetCursor then targetCursor:Hide() end
    if targetIcon then targetIcon:SetAlpha(1) end
    draggedInfo = nil

    sfui.cdm.RefreshLayout()
end

-- Handle drops from Blizzard UI (spellbook, bags, character panel)
HandleExternalDrop = function(zoneFrame, panelData, isTrackedBars)
    -- If an internal drag is active, let OnZoneReceiveDrag handle it via OnMouseUp
    if draggedInfo then return end
    if InCombatLockdown() then return end

    local cursorType, id, link = GetCursorInfo()
    if not cursorType then return end

    local entry = nil

    if cursorType == "spell" then
        -- id is the spell ID
        entry = { id = id, type = "spell" }
    elseif cursorType == "item" then
        -- id is the item ID
        entry = { id = id, type = "item" }
    elseif cursorType == "petaction" or cursorType == "macro" then
        print("|cffFF9900SFUI:|r Macros and pet actions are not supported.")
        ClearCursor()
        return
    else
        ClearCursor()
        return
    end

    if not entry then
        ClearCursor()
        return
    end

    -- Check for a matching CooldownViewer cooldown ID
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local dp = CooldownViewerSettings:GetDataProvider()
        if dp and dp.GetCooldownInfoForSpellID and entry.type == "spell" then
            local cdInfo = dp:GetCooldownInfoForSpellID(entry.id)
            if cdInfo and cdInfo.cooldownID then
                entry.cooldownID = cdInfo.cooldownID
                entry.type = "cooldown"
            end
        end
    end

    local incomingId = entry.cooldownID or entry.id

    -- Debug print to help user verify ID
    if entry.type == "spell" then
        local link = C_Spell.GetSpellLink(incomingId)
        print("|cff00FF00SFUI:|r Imported Spell: " .. (link or incomingId) .. " (ID: " .. incomingId .. ")")
    elseif entry.type == "item" then
        local link = C_Item.GetItemLink(incomingId) or incomingId
        print("|cff00FF00SFUI:|r Imported Item: " .. link .. " (ID: " .. incomingId .. ")")
    end

    if isTrackedBars then
        sfui.common.ensure_tracked_bar_db(incomingId)
        if sfui.trackedbars and sfui.trackedbars.UpdateVisibility then sfui.trackedbars.UpdateVisibility() end
        if sfui.trackedbars and sfui.trackedbars.ForceLayoutUpdate then sfui.trackedbars.ForceLayoutUpdate() end
        print("|cff00FF00SFUI:|r Added to Tracked Bars")
    else
        if not panelData.entries then panelData.entries = {} end

        local exists = false
        for _, val in ipairs(panelData.entries) do
            local existingId = (type(val) == "table" and (val.cooldownID or val.id)) or val
            if existingId == incomingId then
                exists = true; break
            end
        end

        if not exists then
            table.insert(panelData.entries, entry)
            if sfui.trackedicons and sfui.trackedicons.Update then sfui.trackedicons.Update() end
            print("|cff00FF00SFUI:|r Added to " .. (panelData.name or "panel"))
        end
    end

    ClearCursor()
    sfui.cdm.RefreshLayout()
end
sfui.cdm.activeZones = {}

function sfui.cdm.UpdateVisibility()
    if not sfui.cdm.activeZones then return end
    local inCombat = InCombatLockdown()
    local isMounted = IsMounted()

    for _, zone in ipairs(sfui.cdm.activeZones) do
        local shouldShow = true
        local panelData = zone.panelData

        if zone.isTrackedBars then
            -- Tracked Bars visibility logic (optional, currently always shown unless empty logic handled elsewhere)
        elseif panelData then
            if panelData.hideOOC and not inCombat then shouldShow = false end
            if panelData.hideMounted and isMounted then shouldShow = false end
            -- Legacy support
            if panelData.visibility == "combat" and not inCombat then shouldShow = false end
            if panelData.visibility == "noCombat" and inCombat then shouldShow = false end
        end

        if shouldShow then
            zone:Show()
        else
            zone:Hide()
        end
    end
end
