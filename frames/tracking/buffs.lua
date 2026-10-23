local addonName, addon = ...
sfui = sfui or {}
sfui.trackedbuffs = {}

-- strictly retail cdm module
if not sfui.isRetail then return end

local cfg = sfui.config
local common = sfui.common
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local wipe = table.wipe or wipe
local ipairs = ipairs
local table_sort = table.sort
local table_insert = table.insert
local math_floor = math.floor
local math_max = math.max
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local C_CooldownViewer = C_CooldownViewer
local C_Item = C_Item
local BuffIconCooldownViewer = BuffIconCooldownViewer
local CooldownViewerSettings = CooldownViewerSettings

-- static reuse & throttling (memory & cpu optimization)
local UPDATE_THROTTLE = 0.05
local activeFrames = {}
local slots = {}
local previewSlots = {}
local isPreviewMode = false
local previewActive = false
local socketContainer = nil
local mover = nil
local timeSinceLastUpdate = 0
local isHooked = false

local DEFAULT_PREVIEW_ICONS = {
    136080, -- fireball / flame shock
    136096, -- frostbolt
    136116, -- pyroblast
    136075, -- combustion
}

local CreateSocketContainer -- forward declaration

-- check if blizzard buff item is in pandemic refresh window
local function IsBlizzardItemInPandemic(blizzFrame)
    local icon = blizzFrame and blizzFrame.PandemicIcon
    if not icon or not icon.IsShown then return false end
    local ok, shown = pcall(icon.IsShown, icon)
    return ok and shown == true
end

-- determine if item is currently active without inspecting secret cooldown values
local function IsItemActive(blizzFrame)
    if not blizzFrame or not blizzFrame.cooldownID then return false end
    if blizzFrame.isActive ~= nil then
        return blizzFrame.isActive == true
    end
    if blizzFrame.IsActive then
        local ok, active = pcall(blizzFrame.IsActive, blizzFrame)
        if ok and active ~= nil then
            return active == true
        end
    end
    return blizzFrame:IsShown() == true
end

-- skin blizzard item into sfui square style with 1px border & clean font
local function SkinBlizzardItem(blizzFrame)
    if not blizzFrame or blizzFrame._sfuiSkinned then return end
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

    -- disable mouse to prevent any tooltip or interaction taint on secret values
    blizzFrame:EnableMouse(false)
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
    local defPoint = (bCfg and bCfg.anchor and bCfg.anchor.point) or "CENTER"
    local defX = (bCfg and bCfg.anchor and bCfg.anchor.x) or 0
    local defY = (bCfg and bCfg.anchor and bCfg.anchor.y) or -220

    -- heal previous default if unchanged
    if db and db.anchor and db.anchor.x == 0 and db.anchor.y == -110 then
        db.anchor.y = -220
    end
    if db and db.size == 36 then
        db.size = 42
    end

    local point = (db and db.anchor and db.anchor.point) or defPoint
    local x = (db and db.anchor and db.anchor.x) or defX
    local y = (db and db.anchor and db.anchor.y) or defY

    socketContainer:ClearAllPoints()
    socketContainer:SetPoint(point, UIParent, point, x, y)

    if mover then
        mover:ClearAllPoints()
        mover:SetPoint(point, UIParent, point, x, y)
    end
end
sfui.trackedbuffs.UpdatePosition = UpdatePosition

-- render preview dummy buffs for live slider adjustment and mover repositioning
local function RenderPreview()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local db = SfuiDB and SfuiDB.trackedBuffs or (cfg and cfg.trackedBuffs) or {}
    local size = db.size or (bCfg and bCfg.size) or 42
    local spacing = db.spacing or 4

    local tracked = sfui.trackedbuffs.GetTrackedBuffs and sfui.trackedbuffs.GetTrackedBuffs()
    local numPreview = (tracked and #tracked > 0) and math_max(3, math.min(#tracked, 5)) or 3

    local totalWidth = numPreview * size + (numPreview - 1) * spacing
    socketContainer:SetSize(totalWidth, size)
    socketContainer:Show()

    if mover then
        mover:SetSize(math_max(totalWidth, 120), size)
    end

    local startX = -totalWidth / 2 + size / 2

    for i = 1, numPreview do
        local slot = GetOrCreatePreviewSlot(i)
        slot:SetSize(size, size)

        local iconTexture = (tracked and tracked[i] and tracked[i].icon) or DEFAULT_PREVIEW_ICONS[((i - 1) % #DEFAULT_PREVIEW_ICONS) + 1]
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
                sfui.glows.start_glow(slot, {
                    glowType = "pixel",
                    glowColor = { 1, 0.85, 0.2, 1 },
                    glowLines = 8,
                    glowThickness = 2,
                })
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
        if sfui.glows and sfui.glows.stop_glow then
            sfui.glows.stop_glow(slot)
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

-- live layout update for size and spacing changes
local function UpdateLayout()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local db = SfuiDB and SfuiDB.trackedBuffs or (cfg and cfg.trackedBuffs) or {}
    local size = db.size or (bCfg and bCfg.size) or 42
    local spacing = db.spacing or 4

    if #activeFrames > 0 then
        local numActive = #activeFrames
        local totalWidth = numActive * size + (numActive - 1) * spacing
        socketContainer:SetSize(totalWidth, size)
        if mover then mover:SetSize(math_max(totalWidth, 120), size) end

        local startX = -totalWidth / 2 + size / 2
        for i = 1, numActive do
            local slot = slots[i]
            if slot then
                slot:SetSize(size, size)
                local posX = startX + (i - 1) * (size + spacing)
                slot:ClearAllPoints()
                slot:SetPoint("CENTER", socketContainer, "CENTER", posX, 0)
            end
        end
    elseif isPreviewMode or (mover and mover:IsShown()) then
        RenderPreview()
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
        common.apply_flat_backdrop(mover, { hlCol[1], hlCol[2], hlCol[3], 0.5 }, { borderCol[1], borderCol[2], borderCol[3], 1 })
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

        if socketContainer then
            socketContainer:ClearAllPoints()
            socketContainer:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        end

        if sfui.trackedoptions and sfui.trackedoptions.buffsContent and sfui.trackedoptions.buffsContent._generated then
            sfui.trackedoptions.RenderBuffsTab(sfui.trackedoptions.buffsContent)
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

    -- register with actionbars movers list
    if sfui.actionbars and sfui.actionbars.movers and sfui.actionbars.movers.list then
        sfui.actionbars.movers.list["trackedBuffs"] = mover
    end

    -- onupdate throttle loop for real-time responsiveness
    socketContainer:SetScript("OnUpdate", function(self, elapsed)
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        if timeSinceLastUpdate >= UPDATE_THROTTLE then
            timeSinceLastUpdate = 0
            sfui.trackedbuffs.Sync()
        end
    end)
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
local function SyncWithBlizzard()
    if not socketContainer then CreateSocketContainer() end
    if not socketContainer then return end

    local db = SfuiDB and SfuiDB.trackedBuffs or (cfg and cfg.trackedBuffs) or {}
    if db.enabled == false and not isPreviewMode then
        socketContainer:Hide()
        HidePreview()
        for _, slot in ipairs(slots) do
            slot:Hide()
            if sfui.glows and sfui.glows.stop_glow then sfui.glows.stop_glow(slot) end
        end
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
            elseif db.hideDragonriding and common and common.IsDragonriding and common.IsDragonriding() then
                mustHide = true
            end
        end
    end

    if mustHide then
        socketContainer:Hide()
        HidePreview()
        for _, slot in ipairs(slots) do
            slot:Hide()
            if sfui.glows and sfui.glows.stop_glow then sfui.glows.stop_glow(slot) end
        end
        return
    end

    -- collect active frames
    wipe(activeFrames)
    if BuffIconCooldownViewer and BuffIconCooldownViewer.itemFramePool then
        for blizzFrame in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
            if IsItemActive(blizzFrame) then
                table_insert(activeFrames, blizzFrame)
            end
        end
    end

    -- sort by blizzard layoutIndex to preserve user cdm ordering
    if #activeFrames > 1 then
        table_sort(activeFrames, function(a, b)
            local la = a.layoutIndex or 999
            local lb = b.layoutIndex or 999
            if la ~= lb then
                return la < lb
            end
            return (a.cooldownID or 0) < (b.cooldownID or 0)
        end)
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
        for _, slot in ipairs(slots) do
            slot:Hide()
            if sfui.glows and sfui.glows.stop_glow then sfui.glows.stop_glow(slot) end
        end
        return
    end

    -- Real active blizzard buffs exist: hide preview if active
    if previewActive then
        HidePreview()
    end
    socketContainer:Show()

    local size = db.size or (bCfg and bCfg.size) or 42
    local spacing = db.spacing or 4
    local totalWidth = numActive * size + (numActive - 1) * spacing
    socketContainer:SetSize(totalWidth, size)

    if mover then
        mover:SetSize(math_max(totalWidth, 120), size)
    end

    -- center active icons symmetrically around socket center
    local startX = -totalWidth / 2 + size / 2

    for i = 1, numActive do
        local blizzFrame = activeFrames[i]
        local slot = GetOrCreateSlot(i)
        slot:SetSize(size, size)

        -- skin blizzard frame
        SkinBlizzardItem(blizzFrame)

        -- socket blizzard frame into slot
        if blizzFrame:GetParent() ~= slot then
            blizzFrame:SetParent(slot)
        end
        blizzFrame:ClearAllPoints()
        blizzFrame:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
        blizzFrame:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
        blizzFrame:SetAlpha(1)
        blizzFrame:Show()

        -- pandemic / alert glow
        local inPandemic = IsBlizzardItemInPandemic(blizzFrame)
        if inPandemic and (db.glow ~= false) then
            if blizzFrame.PandemicIcon then
                blizzFrame.PandemicIcon:SetAlpha(0)
            end
            if sfui.glows and sfui.glows.start_glow then
                sfui.glows.start_glow(slot, {
                    glowType = "pixel",
                    glowColor = { 1, 0.85, 0.2, 1 },
                    glowLines = 8,
                    glowThickness = 2,
                })
            end
        else
            if sfui.glows and sfui.glows.stop_glow then
                sfui.glows.stop_glow(slot)
            end
        end

        -- position slot centered
        local posX = startX + (i - 1) * (size + spacing)
        slot:ClearAllPoints()
        slot:SetPoint("CENTER", socketContainer, "CENTER", posX, 0)
        slot:Show()
    end

    -- hide remaining inactive slots
    for i = numActive + 1, #slots do
        local slot = slots[i]
        slot:Hide()
        if sfui.glows and sfui.glows.stop_glow then
            sfui.glows.stop_glow(slot)
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

-- retrieve list of assigned tracked buffs in blizzard cdm
function sfui.trackedbuffs.GetTrackedBuffs()
    local result = {}
    local seen = {}

    -- 1. check live active frames in pool
    if BuffIconCooldownViewer and BuffIconCooldownViewer.itemFramePool then
        for blizzFrame in BuffIconCooldownViewer.itemFramePool:EnumerateActive() do
            local id = blizzFrame.cooldownID
            if id and not seen[id] then
                seen[id] = true
                local name, icon
                if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                    if ok and info then
                        if info.spellID then
                            name = common.get_spell_name(info.spellID)
                            icon = common.get_spell_icon(info.spellID)
                        elseif info.itemID then
                            name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)
                            icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID)
                        end
                    end
                end
                if not name and blizzFrame.GetSpellID then
                    local ok, sp = pcall(blizzFrame.GetSpellID, blizzFrame)
                    if ok and sp then
                        name = common.get_spell_name(sp)
                        icon = common.get_spell_icon(sp)
                    end
                end
                if not name then name = common.get_spell_name(id) end
                if not icon then icon = common.get_spell_icon(id) end

                table_insert(result, {
                    id = id,
                    name = name or ("unknown (" .. id .. ")"),
                    icon = icon or (cfg and cfg.textures and cfg.textures.white) or 134400,
                    active = IsItemActive(blizzFrame),
                    layoutIndex = blizzFrame.layoutIndex or 999,
                })
            end
        end
    end

    -- 2. check cdm data provider for configured but inactive buffs
    local dp = CooldownViewerSettings and CooldownViewerSettings.GetDataProvider and CooldownViewerSettings:GetDataProvider()
    local cat = (Enum and Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBuff) or 2
    if dp and dp.GetOrderedCooldownIDsForCategory then
        local ok, ids = pcall(dp.GetOrderedCooldownIDsForCategory, dp, cat, true)
        if ok and ids then
            for idx, id in ipairs(ids) do
                if not seen[id] then
                    seen[id] = true
                    local name, icon
                    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                        if ok2 and info then
                            if info.spellID then
                                name = common.get_spell_name(info.spellID)
                                icon = common.get_spell_icon(info.spellID)
                            elseif info.itemID then
                                name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)
                                icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(info.itemID)
                            end
                        end
                    end
                    if not name then name = common.get_spell_name(id) end
                    if not icon then icon = common.get_spell_icon(id) end

                    table_insert(result, {
                        id = id,
                        name = name or ("unknown (" .. id .. ")"),
                        icon = icon or (cfg and cfg.textures and cfg.textures.white) or 134400,
                        active = false,
                        layoutIndex = idx,
                    })
                end
            end
        end
    end

    table_sort(result, function(a, b)
        if a.layoutIndex ~= b.layoutIndex then
            return (a.layoutIndex or 999) < (b.layoutIndex or 999)
        end
        return (a.name or "") < (b.name or "")
    end)

    return result
end

-- hook blizzard cooldown viewer methods for instant response
local function HookBlizzardViewer()
    if isHooked then return end
    if not BuffIconCooldownViewer then return end
    isHooked = true

    if hooksecurefunc then
        hooksecurefunc(BuffIconCooldownViewer, "RefreshLayout", function()
            SyncWithBlizzard()
        end)
        hooksecurefunc(BuffIconCooldownViewer, "RefreshData", function()
            SyncWithBlizzard()
        end)
    end
end

-- event registration
local function RegisterEvents()
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    eventFrame:RegisterEvent("ADDON_LOADED")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownViewer" then
            HookBlizzardViewer()
            SyncWithBlizzard()
        else
            SyncWithBlizzard()
        end
    end)
end

-- lifecycle hooks
function sfui.trackedbuffs.OnInit()
    if not sfui.isRetail then return end
    if not sfui.common.is_addon_loaded("Blizzard_CooldownViewer") then
        sfui.common.ensure_addon_loaded("Blizzard_CooldownViewer")
    end
    CreateSocketContainer()
    HookBlizzardViewer()
    RegisterEvents()
end

function sfui.trackedbuffs.OnEnable()
    if not sfui.isRetail then return end
    UpdatePosition()
    SyncWithBlizzard()
end

-- register module with sfui
if sfui.RegisterModule then
    sfui.RegisterModule("trackedbuffs", sfui.trackedbuffs)
end
