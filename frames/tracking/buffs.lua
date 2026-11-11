sfui = sfui or {}
sfui.trackedbuffs = {}

-- retail & camelot (forever) blizzard cdm buff socket module
local isSupportedClient = (sfui.isRetail or sfui.isCamelot) == true
if not isSupportedClient then return end

local cfg = sfui.config
local common = sfui.common
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local wipe = table.wipe or wipe
local ipairs = ipairs
local tonumber = tonumber
local type = type
local table_sort = table.sort
local table_insert = table.insert
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local bit_band = bit and bit.band
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local C_CooldownViewer = C_CooldownViewer
local C_Item = C_Item
local C_Timer = C_Timer
local C_CVar = C_CVar
local Enum = Enum
local EventRegistry = EventRegistry
local issecretvalue = issecretvalue

-- static reuse & state (zero-polling memory & cpu design)
local activeFrames = {}
local slots = {}
local previewSlots = {}
local _liveActive = {}
local _liveIndex = {}
local _liveIcon = {}
local _seen = {}

local isPreviewMode = false
local previewActive = false
local socketContainer = nil
local mover = nil
local isHooked = false
local isRegistryHooked = false
local pendingTabRefresh = false
local pendingLayoutPreview = false

local PANDEMIC_GLOW_OPTS = {
    glowType = "pixel",
    glowColor = { 1, 0.85, 0.2, 1 },
    glowLines = 8,
    glowThickness = 2,
}

local DEFAULT_PREVIEW_ICONS = {
    136080, -- fireball / flame shock
    136096, -- frostbolt
    136116, -- pyroblast
    136075, -- combustion
}

local ALL_CDM_CATEGORIES = { 0, 1, 2, 3, 4, 5, 6, 7 }

local CreateSocketContainer -- forward declaration
local SyncWithBlizzard      -- forward declaration
local RenderPreview         -- forward declaration
local HookItemFrame         -- forward declaration

local function GetBlizzBuffViewer()
    return _G.BuffIconCooldownViewer
end

local function GetCooldownInfoSafe(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    if issecretvalue and issecretvalue(id) then return nil end
    if sfui.tracking and sfui.tracking.SafeGetCooldownInfo then
        return sfui.tracking.SafeGetCooldownInfo(id)
    end
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        return C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    end
    return nil
end

local function ScheduleBuffsTabRefresh(layoutChanged)
    if layoutChanged then
        pendingLayoutPreview = true
    end
    if pendingTabRefresh then return end
    pendingTabRefresh = true

    local function runRefresh()
        pendingTabRefresh = false
        local doPreview = pendingLayoutPreview
        pendingLayoutPreview = false

        if doPreview and (isPreviewMode or (mover and mover:IsShown())) and #activeFrames == 0 then
            RenderPreview()
        end

        local to = sfui.trackedoptions
        local content = to and to.buffsContent
        if not content then return end

        local isTabOpen = to.frame and to.frame:IsShown() and to.frame.selectedTabId == 4
        if isTabOpen and content._generated and to.RefreshBuffsList then
            to.RefreshBuffsList(content)
        else
            content._listDirty = true
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, runRefresh)
    else
        runRefresh()
    end
end

-- static comparator for active cooldown frame ordering
local function CompareActiveFrames(a, b)
    local la = a.layoutIndex or 999
    local lb = b.layoutIndex or 999
    if la ~= lb then
        return la < lb
    end
    local ca = a.cooldownID
    local cb = b.cooldownID
    if issecretvalue and ((ca and issecretvalue(ca)) or (cb and issecretvalue(cb))) then
        return false
    end
    return (ca or 0) < (cb or 0)
end

-- check if blizzard buff item is in pandemic refresh window
local function IsBlizzardItemInPandemic(blizzFrame)
    local icon = blizzFrame and blizzFrame.PandemicIcon
    if not icon or not icon.IsShown then return false end
    local shown = icon:IsShown()
    if issecretvalue and issecretvalue(shown) then return false end
    return shown == true
end

-- determine if item is currently active without inspecting secret cooldown values
local function IsItemActive(blizzFrame)
    if not blizzFrame then return false end
    local id = blizzFrame.cooldownID
    if not id or (issecretvalue and issecretvalue(id)) then return false end

    local active = blizzFrame.isActive
    if active ~= nil then
        if issecretvalue and issecretvalue(active) then
            return blizzFrame:IsShown() == true
        end
        return active == true
    end
    if blizzFrame.IsActive then
        local val = blizzFrame:IsActive()
        if issecretvalue and issecretvalue(val) then
            return blizzFrame:IsShown() == true
        end
        return val == true
    end
    return blizzFrame:IsShown() == true
end

local function DisarmBlizzardItemMouse(blizzFrame)
    if not blizzFrame then return end
    if blizzFrame.SetMouseMotionEnabled then
        blizzFrame:SetMouseMotionEnabled(false)
    end
    if blizzFrame.SetMouseClickEnabled then
        blizzFrame:SetMouseClickEnabled(false)
    end
    if blizzFrame.EnableMouse then
        blizzFrame:EnableMouse(false)
    end
end

-- return any previously socketed frame back to blizzard's hidden viewer when inactive
local function ReturnInactiveFramesToViewer(viewer, returnAll)
    if not viewer or not viewer.itemFramePool then return end
    for blizzFrame in viewer.itemFramePool:EnumerateActive() do
        HookItemFrame(blizzFrame)
        if (returnAll or not IsItemActive(blizzFrame)) and blizzFrame:GetParent() ~= viewer then
            blizzFrame:SetParent(viewer)
        end
    end
end

-- skin blizzard item into sfui square style with 1px border & clean font
local function SkinBlizzardItem(blizzFrame)
    if not blizzFrame then return end
    DisarmBlizzardItemMouse(blizzFrame)
    if blizzFrame._sfuiSkinned then return end
    blizzFrame._sfuiSkinned = true

    -- strip circular masks and extraneous blizzard overlay textures
    local regions = { blizzFrame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("MaskTexture") then
            if blizzFrame.Icon and blizzFrame.Icon.RemoveMaskTexture then
                blizzFrame.Icon:RemoveMaskTexture(region)
            end
            region:Hide()
        elseif region:IsObjectType("Texture") and region ~= blizzFrame.Icon then
            region:SetAlpha(0)
        end
    end

    -- apply sfui square texcoords
    if blizzFrame.Icon then
        blizzFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        blizzFrame.Icon:ClearAllPoints()
        blizzFrame.Icon:SetAllPoints(blizzFrame)
    end

    -- setup blizzard cooldown widget
    if blizzFrame.Cooldown then
        blizzFrame.Cooldown:ClearAllPoints()
        blizzFrame.Cooldown:SetAllPoints(blizzFrame)
        blizzFrame.Cooldown:SetDrawEdge(true)
    end

    -- style stack count fontstring
    local appText = blizzFrame.Applications and blizzFrame.Applications.Applications
    if appText then
        appText:SetFontObject(sfui.config and sfui.config.font_small or NumberFontNormal)
        appText:ClearAllPoints()
        appText:SetPoint("BOTTOMRIGHT", blizzFrame, "BOTTOMRIGHT", -2, 2)
        if common and common.style_text then
            common.style_text(appText, nil, nil, "OUTLINE")
        end
    end

    -- hide debuff border
    if blizzFrame.DebuffBorder then
        blizzFrame.DebuffBorder:Hide()
    end
end

-- acquire or create a slot with sfui 1px black border
local function GetOrCreateSlot(index)
    local slot = slots[index]
    if slot then return slot end

    local name = "SfuiTrackedBuffSlot_" .. index
    slot = CreateFrame("Frame", name, socketContainer)
    slot:SetSize(42, 42)
    slot:EnableMouse(false)

    -- 1px solid black border backdrop
    local bg = slot:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(slot)
    bg:SetColorTexture(0, 0, 0, 1)
    slot.bg = bg

    slots[index] = slot
    return slot
end

-- acquire or create a preview dummy slot with sfui 1px black border
local function GetOrCreatePreviewSlot(index)
    local slot = previewSlots[index]
    if slot then return slot end

    local name = "SfuiTrackedBuffPreviewSlot_" .. index
    slot = CreateFrame("Frame", name, socketContainer)
    slot:SetSize(42, 42)
    slot:EnableMouse(false)

    -- 1px solid black border backdrop
    local bg = slot:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(slot)
    bg:SetColorTexture(0, 0, 0, 1)
    slot.bg = bg

    -- icon texture with 1px inset
    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.icon = icon

    -- applications / stack count
    local appText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    appText:SetFontObject(sfui.config and sfui.config.font_small or NumberFontNormal)
    appText:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
    if common and common.style_text then
        common.style_text(appText, nil, nil, "OUTLINE")
    end
    slot.appText = appText

    -- preview cooldown frame
    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:ClearAllPoints()
    cd:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    cd:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    cd:SetDrawEdge(true)
    slot.cooldown = cd

    previewSlots[index] = slot
    return slot
end

-- update container and mover screen position
local function UpdatePosition()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end
    local db = SfuiDB and SfuiDB.trackedBuffs
    local bCfg = cfg and cfg.trackedBuffs

    -- heal previous default if unchanged
    if db and db.anchor and db.anchor.x == 0 and (db.anchor.y == -220 or db.anchor.y == -110) and not db.anchor.isCustom then
        db.anchor.isCustom = false
    end
    if db and db.size == 36 then
        db.size = 42
    end

    local isCustom = false
    if db and db.anchor then
        if db.anchor.isCustom == true then
            isCustom = true
        elseif db.anchor.isCustom == nil then
            if db.anchor.x ~= 0 or (db.anchor.y ~= -220 and db.anchor.y ~= -110) then
                isCustom = true
            end
        end
    end

    if not isCustom then
        local topAnchor = sfui.trackedbars and sfui.trackedbars.GetTopAnchor and sfui.trackedbars.GetTopAnchor()
        if not topAnchor and sfui.trackedbars and sfui.trackedbars.UpdateTopAnchor then
            topAnchor = sfui.trackedbars.UpdateTopAnchor()
        end
        topAnchor = topAnchor or _G["SfuiTrackedBarsTopAnchor"] or _G["sfui_bar0_Backdrop"] or UIParent

        socketContainer:ClearAllPoints()
        socketContainer:SetPoint("BOTTOM", topAnchor, "TOP", 0, 4)

        if mover then
            mover:ClearAllPoints()
            mover:SetPoint("BOTTOM", topAnchor, "TOP", 0, 4)
        end
    else
        local defPoint = (bCfg and bCfg.anchor and bCfg.anchor.point) or "CENTER"
        local point = (db and db.anchor and db.anchor.point) or defPoint
        local x = (db and db.anchor and db.anchor.x) or 0
        local y = (db and db.anchor and db.anchor.y) or 0

        socketContainer:ClearAllPoints()
        socketContainer:SetPoint(point, UIParent, point, x, y)

        if mover then
            mover:ClearAllPoints()
            mover:SetPoint(point, UIParent, point, x, y)
        end
    end
end
sfui.trackedbuffs.UpdatePosition = UpdatePosition

-- render preview dummy buffs for live slider adjustment and mover repositioning
RenderPreview = function()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local bCfg = cfg and cfg.trackedBuffs
    local db = SfuiDB and SfuiDB.trackedBuffs or bCfg or {}
    local size = db.size or (cfg and cfg.trackedBuffs and cfg.trackedBuffs.size) or 42
    local spacing = db.spacing or 4

    local tracked = sfui.trackedbuffs.GetTrackedBuffs and sfui.trackedbuffs.GetTrackedBuffs()
    local numPreview = (tracked and #tracked > 0) and math_max(3, math_min(#tracked, 5)) or 3

    local totalWidth = numPreview * size + (numPreview - 1) * spacing
    socketContainer:SetSize(totalWidth, size)
    socketContainer._lastWidth = totalWidth
    socketContainer._lastHeight = size
    socketContainer:Show()

    if mover then
        local moverW = math_max(totalWidth, 120)
        mover:SetSize(moverW, size)
        mover._lastWidth = moverW
        mover._lastHeight = size
    end

    local startX = -totalWidth / 2 + size / 2

    for i = 1, numPreview do
        local slot = GetOrCreatePreviewSlot(i)
        slot:SetSize(size, size)

        local iconTexture = (tracked and tracked[i] and tracked[i].icon) or
            DEFAULT_PREVIEW_ICONS[((i - 1) % #DEFAULT_PREVIEW_ICONS) + 1]
        slot.icon:SetTexture(iconTexture)

        -- dummy stack count on 2nd slot
        if i == 2 then
            slot.appText:SetText("3")
            slot.appText:Show()
        else
            slot.appText:SetText("")
            slot.appText:Hide()
        end

        -- dummy cooldown animation
        if slot.cooldown then
            slot.cooldown:SetCooldown(GetTime() - (i * 2), 15)
        end

        -- pandemic glow preview on 1st slot if db.glow enabled
        if i == 1 and (db.glow ~= false) then
            if sfui.glows and sfui.glows.start_glow then
                sfui.glows.start_glow(slot, PANDEMIC_GLOW_OPTS)
            end
        else
            if sfui.glows and sfui.glows.stop_glow then
                sfui.glows.stop_glow(slot)
            end
        end

        local posX = startX + (i - 1) * (size + spacing)
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", socketContainer, "CENTER", posX, 0)
        slot:Show()
    end

    -- hide any extra preview slots
    for i = numPreview + 1, #previewSlots do
        local slot = previewSlots[i]
        slot:Hide()
        if sfui.glows and sfui.glows.stop_glow then
            sfui.glows.stop_glow(slot)
        end
    end

    -- hide real blizzard slots during dummy preview
    for _, slot in ipairs(slots) do
        slot:Hide()
        slot._posX = nil
        if slot._isGlowing then
            slot._isGlowing = false
            if sfui.glows and sfui.glows.stop_glow then
                sfui.glows.stop_glow(slot)
            end
        end
    end

    previewActive = true
end

-- hide preview dummy slots
local function HidePreview()
    previewActive = false
    for _, slot in ipairs(previewSlots) do
        slot:Hide()
        if sfui.glows and sfui.glows.stop_glow then
            sfui.glows.stop_glow(slot)
        end
    end
end

local function HideAllSlots()
    for _, slot in ipairs(slots) do
        if slot:IsShown() then
            slot:Hide()
            slot._posX = nil
            if slot._isGlowing then
                slot._isGlowing = false
                if sfui.glows and sfui.glows.stop_glow then sfui.glows.stop_glow(slot) end
            end
        end
    end
end

-- live layout update for size and spacing changes
local function UpdateLayout()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local bCfg = cfg and cfg.trackedBuffs
    local db = SfuiDB and SfuiDB.trackedBuffs or bCfg or {}
    local size = db.size or (cfg and cfg.trackedBuffs and cfg.trackedBuffs.size) or 42
    local spacing = db.spacing or 4

    if #activeFrames > 0 then
        local numActive = #activeFrames
        local totalWidth = numActive * size + (numActive - 1) * spacing
        socketContainer:SetSize(totalWidth, size)
        socketContainer._lastWidth = totalWidth
        socketContainer._lastHeight = size
        if mover then
            local moverW = math_max(totalWidth, 120)
            mover:SetSize(moverW, size)
            mover._lastWidth = moverW
            mover._lastHeight = size
        end

        local startX = -totalWidth / 2 + size / 2
        for i = 1, numActive do
            local slot = slots[i]
            if slot then
                slot:SetSize(size, size)
                slot._size = size
                local posX = startX + (i - 1) * (size + spacing)
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", socketContainer, "CENTER", posX, 0)
                slot._posX = posX
            end
        end
    elseif isPreviewMode or (mover and mover:IsShown()) then
        RenderPreview()
    else
        SyncWithBlizzard()
    end
end
sfui.trackedbuffs.UpdateLayout = UpdateLayout

-- create the socket container and mover frame
CreateSocketContainer = function()
    if socketContainer then return end

    socketContainer = CreateFrame("Frame", "SfuiTrackedBuffsSocket", UIParent)
    socketContainer:SetSize(42, 42)
    socketContainer:EnableMouse(false)
    UpdatePosition()

    -- create mover frame for /sfui unlock integration
    local moverName = "sfui_TrackedBuffsMover"
    mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(false)
    mover:RegisterForDrag("LeftButton")
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(50)
    mover:SetSize(120, 42)
    mover:Hide()

    if common and common.apply_flat_backdrop then
        local app = cfg and cfg.appearance
        local hlCol = (app and app.highlightColor) or { 0.4, 0, 1, 0.4 }
        local borderCol = (app and app.accentColor) or { 0, 1, 1, 1 }
        common.apply_flat_backdrop(mover, { hlCol[1], hlCol[2], hlCol[3], 0.5 },
            { borderCol[1], borderCol[2], borderCol[3], 1 })
    end

    local label = mover:CreateFontString(nil, "OVERLAY", (cfg and cfg.font) or "GameFontNormal")
    label:SetPoint("CENTER", mover, "CENTER", 0, 0)
    label:SetText("tracked buffs")
    label:SetTextColor(1, 1, 1, 1)
    mover.label = label

    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self:StartMoving()
    end)

    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local screenWidth = UIParent:GetWidth()
        local screenHeight = UIParent:GetHeight()
        local offsetX = math_floor(cx - (screenWidth / 2) + 0.5)
        local offsetY = math_floor(cy - (screenHeight / 2) + 0.5)

        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)

        SfuiDB = SfuiDB or {}
        SfuiDB.trackedBuffs = SfuiDB.trackedBuffs or {}
        SfuiDB.trackedBuffs.anchor = SfuiDB.trackedBuffs.anchor or {}
        SfuiDB.trackedBuffs.anchor.point = "CENTER"
        SfuiDB.trackedBuffs.anchor.x = offsetX
        SfuiDB.trackedBuffs.anchor.y = offsetY
        SfuiDB.trackedBuffs.anchor.isCustom = true

        if socketContainer then
            socketContainer:ClearAllPoints()
            socketContainer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        end

        if sfui.trackedoptions and sfui.trackedoptions.SyncBuffsPositionControls then
            sfui.trackedoptions.SyncBuffsPositionControls(offsetX, offsetY)
        end
    end)

    mover:HookScript("OnShow", function()
        if not isPreviewMode then
            sfui.trackedbuffs.SetPreviewMode(true)
        end
    end)

    mover:HookScript("OnHide", function()
        local optionsOpenOnBuffs = sfui.trackedoptions and sfui.trackedoptions.frame
            and sfui.trackedoptions.frame:IsShown()
            and sfui.trackedoptions.frame.selectedTabId == 4
        if not optionsOpenOnBuffs then
            sfui.trackedbuffs.SetPreviewMode(false)
        end
    end)

    -- register with sfui movers
    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(socketContainer, {
            key = "trackedBuffs",
            label = "tracked buffs",
            preferredPoint = "CENTER",
            getPoint = function()
                local pt, relTo, relPt, x, y = socketContainer:GetPoint()
                return pt or "CENTER", relTo or UIParent, relPt or "CENTER", x or 0, y or 260
            end,
            setPoint = function(point, _, _, x, y)
                local savedPt = point or "CENTER"
                local savedX = math_floor((x or 0) + 0.5)
                local savedY = math_floor((y or 0) + 0.5)
                socketContainer:ClearAllPoints()
                socketContainer:SetPoint(savedPt, UIParent, savedPt, savedX, savedY)
                if mover then
                    mover:ClearAllPoints()
                    mover:SetPoint(savedPt, UIParent, savedPt, savedX, savedY)
                end
                SfuiDB = SfuiDB or {}
                SfuiDB.trackedBuffs = SfuiDB.trackedBuffs or {}
                SfuiDB.trackedBuffs.anchor = SfuiDB.trackedBuffs.anchor or {}
                SfuiDB.trackedBuffs.anchor.point = savedPt
                SfuiDB.trackedBuffs.anchor.x = savedX
                SfuiDB.trackedBuffs.anchor.y = savedY
                SfuiDB.trackedBuffs.anchor.isCustom = true
                if sfui.trackedoptions and sfui.trackedoptions.SyncBuffsPositionControls then
                    sfui.trackedoptions.SyncBuffsPositionControls(savedX, savedY)
                end
            end,
            onEnterEditMode = function()
                if not isPreviewMode then
                    sfui.trackedbuffs.SetPreviewMode(true)
                end
            end,
            onExitEditMode = function()
                local optionsOpenOnBuffs = sfui.trackedoptions and sfui.trackedoptions.frame
                    and sfui.trackedoptions.frame:IsShown()
                    and sfui.trackedoptions.frame.selectedTabId == 4
                if not optionsOpenOnBuffs then
                    sfui.trackedbuffs.SetPreviewMode(false)
                end
            end,
        })
    elseif sfui.actionbars and sfui.actionbars.movers and sfui.actionbars.movers.list then
        sfui.actionbars.movers.list["trackedBuffs"] = mover
    end
end

-- control preview mode for options configuring
function sfui.trackedbuffs.SetPreviewMode(enable)
    if enable == nil then
        enable = not isPreviewMode
    end
    isPreviewMode = enable

    if not socketContainer then CreateSocketContainer() end
    UpdatePosition()

    if isPreviewMode then
        SyncWithBlizzard()
    else
        HidePreview()
        SyncWithBlizzard()
    end
end

function sfui.trackedbuffs.IsPreview()
    return isPreviewMode == true
end

function sfui.trackedbuffs.IsMoverShown()
    return (mover and mover:IsShown()) == true
end

-- synchronize active buff items from blizzard's bufficoncooldownviewer
SyncWithBlizzard = function()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local viewer = GetBlizzBuffViewer()
    local db = SfuiDB and SfuiDB.trackedBuffs or (cfg and cfg.trackedBuffs) or {}

    if db.enabled == false and not isPreviewMode and not (mover and mover:IsShown()) then
        wipe(activeFrames)
        ReturnInactiveFramesToViewer(viewer, true)
        socketContainer:Hide()
        HidePreview()
        HideAllSlots()
        return
    end

    -- combat & visibility checks (bypassed if previewMode or mover is shown)
    local inCombat = common and common.is_in_combat and common.is_in_combat()
    local mustHide = false
    if not isPreviewMode and not (mover and mover:IsShown()) then
        if db.hideOOC and not inCombat then
            mustHide = true
        elseif not inCombat then
            if db.hideMounted and common and common.is_mounted_or_travel_form and common.is_mounted_or_travel_form() then
                mustHide = true
            elseif db.hideInVehicle and ((UnitHasVehicleUI and UnitHasVehicleUI("player")) or (UnitInVehicle and UnitInVehicle("player"))) then
                mustHide = true
            elseif sfui.isRetail and db.hideDragonriding and common and common.IsDragonriding and common.IsDragonriding() then
                mustHide = true
            end
        end
    end

    if mustHide then
        wipe(activeFrames)
        ReturnInactiveFramesToViewer(viewer, true)
        socketContainer:Hide()
        HidePreview()
        HideAllSlots()
        return
    end

    -- collect active frames & return inactive ones to hidden viewer
    wipe(activeFrames)
    if viewer and viewer.itemFramePool then
        for blizzFrame in viewer.itemFramePool:EnumerateActive() do
            HookItemFrame(blizzFrame)
            if IsItemActive(blizzFrame) then
                table_insert(activeFrames, blizzFrame)
            elseif blizzFrame:GetParent() ~= viewer then
                blizzFrame:SetParent(viewer)
            end
        end
    end

    -- sort by blizzard layoutIndex to preserve user cdm ordering
    if #activeFrames > 1 then
        table_sort(activeFrames, CompareActiveFrames)
    end

    local numActive = #activeFrames
    if numActive == 0 then
        if isPreviewMode or (mover and mover:IsShown()) then
            if not previewActive then
                RenderPreview()
            end
            return
        end

        if previewActive then
            HidePreview()
        end
        socketContainer:Hide()
        HideAllSlots()
        return
    end

    -- real active blizzard buffs exist: hide preview if active
    if previewActive then
        HidePreview()
    end
    if not socketContainer:IsShown() then
        socketContainer:Show()
    end

    local size = db.size or (cfg and cfg.trackedBuffs and cfg.trackedBuffs.size) or 42
    local spacing = db.spacing or 4
    local totalWidth = numActive * size + (numActive - 1) * spacing
    if socketContainer._lastWidth ~= totalWidth or socketContainer._lastHeight ~= size then
        socketContainer:SetSize(totalWidth, size)
        socketContainer._lastWidth = totalWidth
        socketContainer._lastHeight = size
    end

    if mover then
        local moverW = math_max(totalWidth, 120)
        if mover._lastWidth ~= moverW or mover._lastHeight ~= size then
            mover:SetSize(moverW, size)
            mover._lastWidth = moverW
            mover._lastHeight = size
        end
    end

    -- center active icons symmetrically around socket center
    local startX = -totalWidth / 2 + size / 2

    for i = 1, numActive do
        local blizzFrame = activeFrames[i]
        local slot = GetOrCreateSlot(i)
        if slot._size ~= size then
            slot:SetSize(size, size)
            slot._size = size
        end

        SkinBlizzardItem(blizzFrame)
        if blizzFrame:GetScale() ~= 1 then
            blizzFrame:SetScale(1)
        end

        -- socket blizzard frame into slot
        if blizzFrame:GetParent() ~= slot then
            blizzFrame:SetParent(slot)
            blizzFrame:ClearAllPoints()
            blizzFrame:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
            blizzFrame:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        end
        if blizzFrame:GetAlpha() ~= 1 then
            blizzFrame:SetAlpha(1)
        end
        if not blizzFrame:IsShown() then
            blizzFrame:Show()
        end

        -- pandemic / alert glow
        local inPandemic = IsBlizzardItemInPandemic(blizzFrame)
        if inPandemic and (db.glow ~= false) then
            if blizzFrame.PandemicIcon and blizzFrame.PandemicIcon:GetAlpha() ~= 0 then
                blizzFrame.PandemicIcon:SetAlpha(0)
            end
            if not slot._isGlowing then
                slot._isGlowing = true
                if sfui.glows and sfui.glows.start_glow then
                    sfui.glows.start_glow(slot, PANDEMIC_GLOW_OPTS)
                end
            end
        else
            if slot._isGlowing then
                slot._isGlowing = false
                if sfui.glows and sfui.glows.stop_glow then
                    sfui.glows.stop_glow(slot)
                end
            end
        end

        -- position slot centered
        local posX = startX + (i - 1) * (size + spacing)
        if slot._posX ~= posX or not slot:IsShown() then
            slot:ClearAllPoints()
            slot:SetPoint("CENTER", socketContainer, "CENTER", posX, 0)
            slot._posX = posX
            slot:Show()
        end
    end

    -- hide remaining inactive slots
    for i = numActive + 1, #slots do
        local slot = slots[i]
        if slot:IsShown() then
            slot:Hide()
            slot._posX = nil
            if slot._isGlowing then
                slot._isGlowing = false
                if sfui.glows and sfui.glows.stop_glow then
                    sfui.glows.stop_glow(slot)
                end
            end
        end
    end
end
sfui.trackedbuffs.Sync = SyncWithBlizzard

-- toggle mover frame visibility for options / slash command
function sfui.trackedbuffs.ToggleMover(show)
    if not mover then CreateSocketContainer() end
    if not mover then return false end
    if show == nil then
        show = not mover:IsShown()
    end
    if show then
        mover:Show()
        mover:EnableMouse(true)
        sfui.trackedbuffs.SetPreviewMode(true)
    else
        mover:Hide()
        mover:EnableMouse(false)
        local optionsOpenOnBuffs = sfui.trackedoptions and sfui.trackedoptions.frame
            and sfui.trackedoptions.frame:IsShown()
            and sfui.trackedoptions.frame.selectedTabId == 4
        if not optionsOpenOnBuffs then
            sfui.trackedbuffs.SetPreviewMode(false)
        end
    end
    return mover:IsShown()
end

-- inspect blizzard cdm state without mutating any cvars or edit mode settings
function sfui.trackedbuffs.GetBlizzardStatus()
    if C_CVar and C_CVar.GetCVarBool and not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        return "cvar_disabled", "blizzard cooldown manager is disabled in game options; enable it so blizzard updates live buff icons."
    end
    local viewer = GetBlizzBuffViewer()
    local visEnum = Enum and Enum.CooldownViewerVisibleSetting
    if viewer and visEnum and viewer.visibleSetting ~= nil then
        if viewer.visibleSetting == visEnum.Hidden then
            return "viewer_hidden", "blizzard 'tracked buffs' is set to 'hidden' in edit mode; set visibility to 'always' for live updates."
        elseif viewer.visibleSetting == visEnum.InCombat then
            return "viewer_combat_only", "note: blizzard 'tracked buffs' visibility is set to 'in combat' in edit mode (out-of-combat buffs only update in combat)."
        end
    end
    return "ok", nil
end

local function ResolveBuffDisplay(id, info)
    info = info or GetCooldownInfoSafe(id)
    local name, icon

    if info then
        local spellID = (info.overrideSpellID and info.overrideSpellID > 0 and info.overrideSpellID) or info.spellID
        if spellID and spellID > 0 then
            name = common.get_spell_name(spellID)
            icon = common.get_spell_icon(spellID)
        elseif info.itemID and info.itemID > 0 then
            name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)
            icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID)
        end
        if (not name or not icon) and info.linkedSpellIDs and info.linkedSpellIDs[1] then
            local linkedID = info.linkedSpellIDs[1]
            name = name or common.get_spell_name(linkedID)
            icon = icon or common.get_spell_icon(linkedID)
        end
    end

    if not icon and _liveIcon[id] then
        icon = _liveIcon[id]
    end
    if not name then name = common.get_spell_name(id) end
    if not icon then icon = common.get_spell_icon(id) end

    return name or ("unknown (" .. id .. ")"),
        icon or (cfg and cfg.textures and cfg.textures.white) or 134400
end

local function IsHideByDefault(info)
    if not info or not bit_band or not info.flags then return false end
    local hideFlag = Enum and Enum.CooldownSetSpellFlags and Enum.CooldownSetSpellFlags.HideByDefault
    if not hideFlag then return false end
    return bit_band(info.flags, hideFlag) ~= 0
end

local function AppendBuffResult(result, id, info, orderIdx)
    if _seen[id] then return end
    _seen[id] = true
    local name, icon = ResolveBuffDisplay(id, info)
    table_insert(result, {
        id = id,
        name = name,
        icon = icon,
        active = _liveActive[id] == true,
        layoutIndex = _liveIndex[id] or orderIdx or 999,
    })
end

local function CompareBuffResults(a, b)
    if a.layoutIndex ~= b.layoutIndex then
        return (a.layoutIndex or 999) < (b.layoutIndex or 999)
    end
    return (a.name or "") < (b.name or "")
end

-- retrieve list of assigned tracked buffs in blizzard cdm (100% read-only, zero taint)
function sfui.trackedbuffs.GetTrackedBuffs()
    local result = {}
    wipe(_liveActive)
    wipe(_liveIndex)
    wipe(_liveIcon)
    wipe(_seen)

    local viewer = GetBlizzBuffViewer()
    if viewer and viewer.itemFramePool then
        for blizzFrame in viewer.itemFramePool:EnumerateActive() do
            HookItemFrame(blizzFrame)
            local id = blizzFrame.cooldownID
            if type(id) == "number" and (not issecretvalue or not issecretvalue(id)) then
                _liveActive[id] = IsItemActive(blizzFrame)
                if blizzFrame.layoutIndex then
                    _liveIndex[id] = blizzFrame.layoutIndex
                end
                local tex = blizzFrame.Icon and blizzFrame.Icon.GetTexture and blizzFrame.Icon:GetTexture()
                if tex and (not issecretvalue or not issecretvalue(tex)) then
                    _liveIcon[id] = tex
                end
            end
        end
    end

    local cat = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff) or 2
    local settings = _G.CooldownViewerSettings
    local dp = settings and settings.dataProvider
    local dd = dp and not dp.displayDataDirty and dp.displayData
    local resolvedFromLayout = false

    -- 1. read-only lookup from already-built blizzard displayData (never calls CheckBuildDisplayData)
    if dd and dd.orderedCooldownIDs and dd.cooldownInfoByID then
        resolvedFromLayout = true
        for idx, id in ipairs(dd.orderedCooldownIDs) do
            local info = dd.cooldownInfoByID[id]
            if info and not info.isInvisible and info.category == cat and info.isKnown ~= false then
                AppendBuffResult(result, id, info, idx)
            end
        end
    else
        -- 2. read-only lookup from deserialized layoutManager active layout (works even when displayData is dirty or cvar is 0)
        local lm = settings and settings.layoutManager
        local activeLayoutID = lm and lm.activeLayoutID
        local activeLayout = activeLayoutID and lm.layouts and lm.layouts[activeLayoutID]
        if activeLayout then
            resolvedFromLayout = true
            local overrides = activeLayout.cooldownInfo
            local ordered = activeLayout.orderedCooldownIDs
            local orderCounter = 0

            local function checkLayoutID(id)
                if _seen[id] then return end
                local info = GetCooldownInfoSafe(id)
                if not info or info.isInvisible or info.isKnown == false then return end
                local block = overrides and overrides[id]
                local effCat
                if block and block.category ~= nil then
                    effCat = tonumber(block.category)
                elseif IsHideByDefault(info) then
                    effCat = -2
                else
                    effCat = info.category
                end
                if effCat == cat then
                    orderCounter = orderCounter + 1
                    AppendBuffResult(result, id, info, orderCounter)
                end
            end

            if ordered then
                for _, id in ipairs(ordered) do
                    checkLayoutID(id)
                end
            end
            if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
                for _, scanCat in ipairs(ALL_CDM_CATEGORIES) do
                    local ids = C_CooldownViewer.GetCooldownViewerCategorySet(scanCat, false)
                    if ids then
                        for _, id in ipairs(ids) do
                            checkLayoutID(id)
                        end
                    end
                end
            end
        end
    end

    -- 3. unmodified default layout fallback
    if not resolvedFromLayout and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet then
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, false)
        if ids then
            for idx, id in ipairs(ids) do
                local info = GetCooldownInfoSafe(id)
                if info and not info.isInvisible and not IsHideByDefault(info) then
                    AppendBuffResult(result, id, info, idx)
                end
            end
        end
    end

    -- 4. ensure any currently acquired live frame in BuffIconCooldownViewer is included
    if viewer and viewer.itemFramePool then
        for blizzFrame in viewer.itemFramePool:EnumerateActive() do
            local id = blizzFrame.cooldownID
            if type(id) == "number" and (not issecretvalue or not issecretvalue(id)) and not _seen[id] then
                AppendBuffResult(result, id, nil, blizzFrame.layoutIndex or 999)
            end
        end
    end

    if #result > 1 then
        table_sort(result, CompareBuffResults)
    end

    return result
end

HookItemFrame = function(blizzFrame)
    if not blizzFrame or blizzFrame._sfuiBuffHooked or not hooksecurefunc then return end
    blizzFrame._sfuiBuffHooked = true

    if blizzFrame.OnActiveStateChanged then
        hooksecurefunc(blizzFrame, "OnActiveStateChanged", function()
            SyncWithBlizzard()
            ScheduleBuffsTabRefresh(false)
        end)
    end
    if blizzFrame.ShowPandemicStateFrame then
        hooksecurefunc(blizzFrame, "ShowPandemicStateFrame", function()
            SyncWithBlizzard()
        end)
    end
    if blizzFrame.HidePandemicStateFrame then
        hooksecurefunc(blizzFrame, "HidePandemicStateFrame", function()
            SyncWithBlizzard()
        end)
    end
end

-- hook blizzard cooldown viewer & eventregistry callbacks (zero UNIT_AURA / SPELL_UPDATE_COOLDOWN polling)
local function HookBlizzardViewer()
    local viewer = GetBlizzBuffViewer()
    if viewer and not isHooked and hooksecurefunc then
        isHooked = true

        if viewer.OnAcquireItemFrame then
            hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, itemFrame)
                HookItemFrame(itemFrame)
            end)
        end
        if viewer.itemFramePool then
            for blizzFrame in viewer.itemFramePool:EnumerateActive() do
                HookItemFrame(blizzFrame)
            end
        end

        hooksecurefunc(viewer, "RefreshLayout", function()
            SyncWithBlizzard()
            ScheduleBuffsTabRefresh(true)
        end)
        hooksecurefunc(viewer, "RefreshData", function()
            SyncWithBlizzard()
            ScheduleBuffsTabRefresh(false)
        end)
        if viewer.UpdateShownState then
            hooksecurefunc(viewer, "UpdateShownState", function()
                SyncWithBlizzard()
                ScheduleBuffsTabRefresh(true)
            end)
        end
    end

    if not isRegistryHooked and EventRegistry and EventRegistry.RegisterCallback then
        isRegistryHooked = true
        local function onCdmChanged()
            SyncWithBlizzard()
            ScheduleBuffsTabRefresh(true)
        end
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", onCdmChanged, "sfui_trackedbuffs_data")
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnShow", onCdmChanged, "sfui_trackedbuffs_show")
        EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", onCdmChanged, "sfui_trackedbuffs_hide")
        EventRegistry:RegisterCallback("EditMode.Exit", onCdmChanged, "sfui_trackedbuffs_editmode")
    end
end

-- event registration (state transitions only — aura/pandemic updates come directly from blizzard item hooks)
local function RegisterEvents()
    local function onStateEvent()
        HookBlizzardViewer()
        SyncWithBlizzard()
    end
    local function onLayoutEvent()
        HookBlizzardViewer()
        SyncWithBlizzard()
        ScheduleBuffsTabRefresh(true)
    end

    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", onLayoutEvent)
    sfui.events.RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", onLayoutEvent)
    sfui.events.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", onLayoutEvent)
    sfui.events.RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", onLayoutEvent)
    sfui.events.RegisterEvent("TRAIT_CONFIG_UPDATED", onLayoutEvent)
    sfui.events.RegisterEvent("SPELLS_CHANGED", onLayoutEvent)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", onStateEvent)
    sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR", onStateEvent)
    sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", onStateEvent)
    sfui.events.RegisterEvent("UNIT_ENTERED_VEHICLE", onStateEvent)
    sfui.events.RegisterEvent("UNIT_EXITED_VEHICLE", onStateEvent)
    sfui.events.RegisterEvent("ADDON_LOADED", function(_, arg1)
        if arg1 == "Blizzard_CooldownViewer" then
            onLayoutEvent()
        end
    end)
end

-- lifecycle hooks
function sfui.trackedbuffs.OnInit()
    if not isSupportedClient then return end
    CreateSocketContainer()
    HookBlizzardViewer()
    RegisterEvents()
end

function sfui.trackedbuffs.OnEnable()
    if not isSupportedClient then return end
    HookBlizzardViewer()
    UpdatePosition()
    SyncWithBlizzard()
end

-- telemetry & debug for mem.lua
local _tbuffDebug = {}
function sfui.trackedbuffs_debug_info()
    local db                   = SfuiDB and SfuiDB.trackedBuffs
    _tbuffDebug.enabled        = not db or db.enabled ~= false
    _tbuffDebug.activeCount    = #activeFrames
    _tbuffDebug.slotCount      = #slots
    _tbuffDebug.previewActive  = previewActive
    _tbuffDebug.containerShown = (socketContainer and socketContainer:IsShown()) == true
    _tbuffDebug.isHooked       = isHooked
    _tbuffDebug.isMoverShown   = (mover and mover:IsShown()) == true
    return _tbuffDebug
end

sfui.trackedbuffs.GetDebugInfo = sfui.trackedbuffs_debug_info

-- register module with sfui
if sfui.RegisterModule then
    sfui.RegisterModule("trackedbuffs", sfui.trackedbuffs)
end
