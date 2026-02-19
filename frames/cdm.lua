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

-- Layout Constants
local POOL_WIDTH = 350
local ZONE_WIDTH = 350
local ICON_SIZE = 30
local ICON_SPACING = 2
local GROUP_HEADER_HEIGHT = 20

-- Main Container
local cdmFrame = nil
local poolFrame = nil
local zonesFrame = nil

-- Data Storage for Dragging
local draggedInfo = nil

-- Frame Pools (avoid GC churn on refresh)
local poolIconFrames = {}
local poolIconCount = 0
local poolBucketFrames = {}
local poolBucketCount = 0

-- Forward Declarations (must be before AcquirePoolIcon closures)
local RefreshPool
local RefreshZones
local OnIconDragStart
local OnIconDragStop
local OnZoneReceiveDrag
local HandleExternalDrop

local function AcquirePoolIcon(parent)
    poolIconCount = poolIconCount + 1
    local icon = poolIconFrames[poolIconCount]
    if not icon then
        icon = CreateFrame("Button", nil, parent)
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        icon.tex = tex
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function(self) OnIconDragStart(self) end)
        icon:SetScript("OnDragStop", function(self) OnIconDragStop(self) end)
        icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        poolIconFrames[poolIconCount] = icon
    end
    icon:SetParent(parent)
    icon:ClearAllPoints()
    icon:Show()
    return icon
end

local function AcquirePoolBucket(parent)
    poolBucketCount = poolBucketCount + 1
    local bucket = poolBucketFrames[poolBucketCount]
    if not bucket then
        bucket = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        bucket:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        bucket.header = bucket:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bucket.header:SetPoint("TOPLEFT", 5, -3)
        poolBucketFrames[poolBucketCount] = bucket
    end
    bucket:SetParent(parent)
    bucket:ClearAllPoints()
    bucket:Show()
    return bucket
end

local function ResetPools()
    for i = 1, poolIconCount do poolIconFrames[i]:Hide() end
    for i = 1, poolBucketCount do poolBucketFrames[i]:Hide() end
    poolIconCount = 0
    poolBucketCount = 0
end

-- ----------------------------------------------------------------------------
-- Initialization & Layout
-- ----------------------------------------------------------------------------

function sfui.cdm.RefreshPool()
    if RefreshPool then RefreshPool() end
end

function sfui.cdm.RefreshZones()
    if RefreshZones then RefreshZones() end
end

function sfui.cdm.create_panel(parent)
    if cdmFrame then
        cdmFrame:SetParent(parent)
        cdmFrame:SetAllPoints(parent)
        cdmFrame:Show()
        RefreshPool()
        RefreshZones()
        return cdmFrame
    end

    cdmFrame = CreateFrame("Frame", "SfuiCDMPanel", parent)
    cdmFrame:SetAllPoints(parent)

    -- Global Drag Cleanup (if mouse released outside any zone)
    cdmFrame:SetScript("OnMouseUp", function()
        if draggedInfo then
            local icon = draggedInfo.icon
            if icon then
                -- icon:StopMovingOrSizing() -- we use a cursor frame, so no need to stop moving the original
            end
            if draggedInfo.cursor then draggedInfo.cursor:Hide() end
            draggedInfo = nil
        end
    end)


    -- 1. Blizzard Cooldown Pool (Left Column)
    poolFrame = CreateFrame("Frame", nil, cdmFrame, "BackdropTemplate")
    poolFrame:SetPoint("TOPLEFT", 10, -10)
    poolFrame:SetPoint("BOTTOMLEFT", 10 + POOL_WIDTH, 10)
    poolFrame:SetWidth(POOL_WIDTH)
    poolFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    poolFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    poolFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    local poolHeader = poolFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    poolHeader:SetPoint("TOPLEFT", 5, 10)
    poolHeader:SetText("blizzard cooldown pool")

    local refreshBtn = CreateFlatButton(poolFrame, "refresh", 60, 18)
    refreshBtn:SetPoint("TOPRIGHT", poolFrame, "TOPRIGHT", -5, 12)
    refreshBtn:SetScript("OnClick", function()
        RefreshPool()
    end)

    -- Pool Scroll Area
    local poolScroll = CreateFrame("ScrollFrame", "SfuiCDMPoolScroll", poolFrame, "UIPanelScrollFrameTemplate")
    poolScroll:SetPoint("TOPLEFT", 5, -5)
    poolScroll:SetPoint("BOTTOMRIGHT", -25, 5)

    local poolContent = CreateFrame("Frame", nil, poolScroll)
    poolContent:SetSize(POOL_WIDTH - 30, 800)
    poolScroll:SetScrollChild(poolContent)
    cdmFrame.poolContent = poolContent

    -- Capture mouse up on pool frame too
    poolFrame:SetScript("OnMouseUp", function()
        if draggedInfo then cdmFrame:GetScript("OnMouseUp")(cdmFrame) end
    end)


    -- 2. Drop Zones (Right Column) (Vertical Stack)
    zonesFrame = CreateFrame("Frame", nil, cdmFrame, "BackdropTemplate")
    zonesFrame:SetPoint("TOPLEFT", poolFrame, "TOPRIGHT", 10, 0)
    zonesFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    zonesFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    zonesFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    zonesFrame:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    -- Zones Scroll Area
    local zonesScroll = CreateFrame("ScrollFrame", "SfuiCDMZonesScroll", zonesFrame, "UIPanelScrollFrameTemplate")
    zonesScroll:SetPoint("TOPLEFT", 5, -5)
    zonesScroll:SetPoint("BOTTOMRIGHT", -25, 5)

    local zonesContent = CreateFrame("Frame", nil, zonesScroll)
    zonesContent:SetSize(zonesFrame:GetWidth() - 30, 800)
    zonesScroll:SetScrollChild(zonesContent)
    cdmFrame.zonesContent = zonesContent

    -- Initial Population
    cdmFrame:SetScript("OnShow", function()
        RefreshPool()
        RefreshZones()
    end)
    cdmFrame:SetScript("OnHide", function()
        if draggedInfo then OnIconDragStop(draggedInfo.icon) end
    end)

    RefreshPool()
    RefreshZones()

    return cdmFrame
end

-- ----------------------------------------------------------------------------
-- Logic
-- ----------------------------------------------------------------------------

RefreshPool = function()
    local container = cdmFrame and cdmFrame.poolContent
    if not container then return end

    -- Reset pools to recycle all frames
    ResetPools()

    if not CooldownViewerSettings then return end

    local dataProvider = CooldownViewerSettings:GetDataProvider()
    if not dataProvider then return end

    local cooldownIDs = dataProvider:GetOrderedCooldownIDs()

    -- Group Icons
    local groups = {}
    for i = -2, 4 do groups[i] = {} end

    for _, id in ipairs(cooldownIDs) do
        local info = dataProvider:GetCooldownInfoForID(id)
        if info then
            local gId = info.category or 4
            if not groups[gId] then groups[gId] = {} end
            table.insert(groups[gId], { id = id, info = info })
        end
    end

    local yPos = -5
    local MAX_ROW_WIDTH = container:GetWidth() - 10

    local groupNames = {
        [-2] = "Internal / Ignored",
        [-1] = "Essential",
        [0] = "Essential",
        [1] = "Utility",
        [2] = "Buffs",
        [3] = "Tracked Bars",
        [4] = "Items / Trinkets / Misc"
    }

    for gId = 0, 4 do
        local list = groups[gId] or {}

        -- Acquire bucket from pool
        local bucket = AcquirePoolBucket(container)
        bucket:SetPoint("TOPLEFT", 5, yPos)
        bucket:SetPoint("RIGHT", -5, 0)
        bucket:SetBackdropColor(0.15, 0.15, 0.15, 0.3)
        bucket:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

        -- Header
        bucket.header:SetText((groupNames[gId] or ("Group " .. gId)) .. " (" .. #list .. ")")
        bucket.header:SetTextColor(1, 0.8, 0, 1)

        -- Icons Grid inside Bucket
        local xOffset = 5
        local yOffset = -20

        for _, item in ipairs(list) do
            local icon = AcquirePoolIcon(bucket)

            -- Grid Logic
            if xOffset + ICON_SIZE > (MAX_ROW_WIDTH - 10) then
                xOffset = 5
                yOffset = yOffset - ICON_SIZE - ICON_SPACING
            end

            icon:SetPoint("TOPLEFT", xOffset, yOffset)
            xOffset = xOffset + ICON_SIZE + ICON_SPACING

            local spellId = item.info.spellID or item.info.itemID
            local texture = C_Spell.GetSpellTexture(spellId)
            if not texture then texture = C_Item.GetItemIconByID(spellId) end

            icon.tex:SetTexture(texture or 134400)
            icon.info = item.info
            icon.cooldownID = item.id

            -- Masque Support
            sfui.common.sync_masque(icon, { Icon = icon.tex })

            -- Tooltip
            icon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.info.spellID then
                    GameTooltip:SetSpellByID(self.info.spellID)
                elseif self.info.itemID then
                    GameTooltip:SetItemByID(self.info.itemID)
                else
                    GameTooltip:SetText(self.info.name or "Unknown")
                end

                GameTooltip:AddLine(" ")
                if self.info.cooldownID then
                    GameTooltip:AddDoubleLine("Cooldown ID:", "|cffffffff" .. self.info.cooldownID .. "|r")
                end
                if self.info.spellID then
                    GameTooltip:AddDoubleLine("Spell ID:", "|cffffffff" .. self.info.spellID .. "|r")
                end
                if self.info.itemID then
                    GameTooltip:AddDoubleLine("Item ID:", "|cffffffff" .. self.info.itemID .. "|r")
                end

                GameTooltip:Show()
            end)
        end

        -- Resize Bucket
        local bucketHeight = math.abs(yOffset) + ICON_SIZE + 5
        bucket:SetHeight(bucketHeight)

        -- Prepare for next group
        yPos = yPos - bucketHeight - 5
    end

    container:SetHeight(math.abs(yPos) + 50)
end

local function CreateZone(parent, name, yPos, panelData, isTrackedBars, panelIndex)
    local zone = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    zone:SetPoint("TOPLEFT", 0, yPos)
    zone:SetPoint("RIGHT", 0, 0)
    -- Limit to 2 rows: 20 (header) + 5 (pad) + 30 (row1) + 2 (spacing) + 30 (row2) + 5 (bottom pad) = 92
    zone:SetHeight(92)
    zone:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })

    -- Visual Style
    if isTrackedBars then
        zone:SetBackdropColor(0.1, 0.0, 0.2, 0.3) -- Purple tint
        zone:SetBackdropBorderColor(0.8, 0.4, 1.0, 0.8)
    else
        zone:SetBackdropColor(0.05, 0.05, 0.05, 0.5)
        zone:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end

    local label = zone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 5, -5)

    if isTrackedBars then
        label:SetText("Tracked Bars (Global Visibility)")
        label:SetTextColor(0.8, 0.4, 1.0)
    else
        label:SetText(panelData.name or "Unnamed Panel")

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
                    RefreshZones()
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
        RefreshZones()
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
        if not CooldownViewerSettings then return 134400 end
        local dp = CooldownViewerSettings:GetDataProvider()
        if not dp then return 134400 end

        local id = (type(cdID) == "table" and cdID.id) or cdID
        local typeStr = (type(cdID) == "table" and cdID.type) or "spell"
        local cooldownID = (type(cdID) == "table" and cdID.cooldownID) or id

        local info = dp:GetCooldownInfoForID(cooldownID)
        if not info then
            -- Fallback if type is spell/item
            if typeStr == "item" then return C_Item.GetItemIconByID(id) or 134400 end
            return C_Spell.GetSpellTexture(id) or 134400
        end

        local spellId = info.spellID or info.itemID
        local texture = C_Spell.GetSpellTexture(spellId)
        if not texture then texture = C_Item.GetItemIconByID(spellId) end
        return texture or 134400
    end

    if entries then
        -- Handle TrackedBars structure (map[id] = true/table) vs Panel structure (list of ids)
        local list = {}
        if isTrackedBars then
            for id, enabled in pairs(entries) do
                if enabled then table.insert(list, id) end
            end
        else
            list = entries
        end

        for _, cdID in ipairs(list) do
            local icon = CreateFrame("Button", nil, content)
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon:SetPoint("TOPLEFT", x, y)

            local tex = icon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(GetIconTexture(cdID))
            icon.tex = tex

            -- Masque Support
            sfui.common.sync_masque(icon, { Icon = tex })


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
    local container = cdmFrame and cdmFrame.zonesContent
    if not container then return end

    -- Clear old zones
    if container.children then
        for _, child in ipairs(container.children) do child:Hide() end
    end
    container.children = {}

    local yPos = 0
    local GAP = 10

    -- 1. Tracked Bars Zone (Always Top)
    local tbZone = CreateZone(container, "Tracked Bars", yPos, nil, true)
    table.insert(container.children, tbZone)
    yPos = yPos - 102 -- Height 92 + 10 gap

    -- 2. Custom Panels
    local panels = sfui.common.get_cooldown_panels()
    if panels then
        for i, panel in ipairs(panels) do
            local zone = CreateZone(container, panel.name, yPos, panel, false, i)
            table.insert(container.children, zone)
            yPos = yPos - 102
        end
    end

    -- 3. Add Panel UI
    local addFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    addFrame:SetSize(300, 30)
    addFrame:SetPoint("TOPLEFT", 0, yPos - 10)
    addFrame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    addFrame:SetBackdropColor(0, 0, 0, 0.5)
    addFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    table.insert(container.children, addFrame)

    local eb = CreateFrame("EditBox", nil, addFrame)
    eb:SetSize(200, 20)
    eb:SetPoint("LEFT", 5, 0)
    eb:SetFontObject("ChatFontNormal")
    eb:SetMultiLine(false)
    eb:SetAutoFocus(false)
    eb:SetText("New Panel Name")
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEnterPressed", function(self)
        local name = self:GetText()
        if name and name ~= "" and name ~= "New Panel Name" then
            sfui.common.add_custom_panel(name)
            RefreshZones()
        end
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = sfui.common.create_flat_button(addFrame, "Add", 60, 20)
    addBtn:SetPoint("RIGHT", -5, 0)
    addBtn:SetScript("OnClick", function()
        local name = eb:GetText()
        if name and name ~= "" and name ~= "New Panel Name" then
            sfui.common.add_custom_panel(name)
            RefreshZones()
        end
        eb:ClearFocus()
    end)

    container:SetHeight(math.abs(yPos) + 100)
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
        cursor.tex = cursor:CreateTexture(nil, "OVERLAY")
        cursor.tex:SetAllPoints()
    end

    cursor.tex:SetTexture(self.tex:GetTexture())
    cursor.tex:SetAlpha(0.7)

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
    local container = cdmFrame and cdmFrame.zonesContent
    if container and container.children then
        for _, zone in ipairs(container.children) do
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

    RefreshZones()
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
    RefreshZones()
end
