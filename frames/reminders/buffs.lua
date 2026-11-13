local _G = _G
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}

local math_floor = math.floor
local math_max = math.max
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GameTooltip = sfui.common.get_tooltip()
local GetTime = _G.GetTime
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local IsMounted = _G.IsMounted
local UnitOnTaxi = _G.UnitOnTaxi
local InCombatLockdown = _G.InCombatLockdown

local providers = sfui.buffs.providers
local FormatTime = providers and providers.FormatTime
local issecretvalue = sfui.common.issecretvalue

local function IsValidTexture(tex)
    if issecretvalue and issecretvalue(tex) then return true end
    return tex ~= nil and tex ~= 0 and tex ~= ""
end

-- Default settings
local DEFAULT_SIZE = 36
local DEFAULT_SPACING = 4
local DEFAULT_POS = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 42 }

local container = nil
local iconPool = {}
local isUnlocked = false
local isTestMode = false

-- Test mode dummy records for previewing
local function GetTestRecords()
    local now = GetTime()
    return {
        {
            isMissing = true,
            isExpiring = false,
            charges = 0,
            expirationTime = 0,
            duration = 0,
            icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
            entry = { name = "power word: fortitude (preview)", type = "aura" }
        },
        {
            isMissing = false,
            isExpiring = true,
            charges = 18,
            expirationTime = now + 145,
            duration = 600,
            icon = "Interface\\Icons\\Spell_Holy_InnerFire",
            entry = { name = "inner fire (preview)", type = "aura" }
        },
        {
            isMissing = true,
            isExpiring = false,
            charges = 0,
            expirationTime = 0,
            duration = 0,
            icon = "Interface\\Icons\\Trade_BrewPoison",
            entry = { name = "main hand poison (preview)", type = "weapon_enchant" }
        },
    }
end

-- ─────────────────────────────────────────────────────────────
--  ICON FRAME CREATION & STYLING
-- ─────────────────────────────────────────────────────────────
local function CreateBuffIcon(index, parent)
    local btn = CreateFrame("Button", "SfuiBuffReminderIcon_" .. index, parent,
        "SecureActionButtonTemplate, BackdropTemplate")
    btn:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp", "AnyDown")

    -- Dark backdrop
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    -- Icon texture with clean modern borderless inset
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.texture = tex

    -- Highlight texture on mouseover
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 1, 1, 0.2)
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn:SetHighlightTexture(hl)

    -- Pushed texture on click
    local pushed = btn:CreateTexture(nil, "OVERLAY")
    pushed:SetColorTexture(0, 0, 0, 0.3)
    pushed:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    pushed:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    btn:SetPushedTexture(pushed)

    -- 1px pixel-perfect border around the perimeter
    if sfui.widgets and sfui.widgets.create_border then
        sfui.widgets.create_border(btn, 1, { 0, 0, 0, 1 })
        if btn.borders then
            for j = 1, #btn.borders do
                btn.borders[j]:SetDrawLayer("OVERLAY", 6)
            end
        end
    end

    -- Remaining duration text (bottom centered, high contrast, outlined font)
    local durationText = btn:CreateFontString(nil, "OVERLAY")
    if _G.NumberFontNormalSmall then
        durationText:SetFontObject(_G.NumberFontNormalSmall)
    else
        durationText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    end
    durationText:SetDrawLayer("OVERLAY", 7)
    durationText:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
    durationText:SetTextColor(1, 0.82, 0, 1)
    durationText:SetShadowColor(0, 0, 0, 1)
    durationText:SetShadowOffset(1, -1)
    btn.durationText = durationText

    -- Stack / charge count text (top right)
    local countText = btn:CreateFontString(nil, "OVERLAY")
    if _G.NumberFontNormalSmall then
        countText:SetFontObject(_G.NumberFontNormalSmall)
    else
        countText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    end
    countText:SetDrawLayer("OVERLAY", 7)
    countText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -1)
    countText:SetTextColor(1, 1, 1, 1)
    countText:SetShadowColor(0, 0, 0, 1)
    countText:SetShadowOffset(1, -1)
    btn.countText = countText

    -- Party member target name label (top center)
    local targetText = btn:CreateFontString(nil, "OVERLAY")
    if _G.NumberFontNormalSmall then
        targetText:SetFontObject(_G.NumberFontNormalSmall)
    else
        targetText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    end
    targetText:SetDrawLayer("OVERLAY", 7)
    targetText:SetPoint("TOP", btn, "TOP", 0, -2)
    targetText:SetTextColor(1, 1, 1, 1)
    targetText:SetShadowColor(0, 0, 0, 1)
    targetText:SetShadowOffset(1, -1)
    btn.targetText = targetText

    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", function(self, delta)
        local rec = self.record
        if not rec or not rec.entry or not providers then return end
        local provider = providers.Resolve(rec.entry)
        if provider and provider.cycle and provider.cycle(rec, delta, self) then
            providers.NotifyCycled(self)
        end
    end)

    -- Tooltip interaction
    btn:SetScript("OnEnter", function(self)
        self.isHovered = true
        local rec = self.record
        if not rec or not providers then return end
        local provider = providers.Resolve(rec.entry)

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()

        if provider and provider.populateTooltip then
            provider.populateTooltip(GameTooltip, rec, self, isTestMode)
        else
            providers.AddStatusHeader(GameTooltip, rec)
        end

        if isUnlocked then
            GameTooltip:AddLine("|cff888888(drag to reposition reminders)|r", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self.isHovered = false
        GameTooltip:Hide()
        if self._needsScanOnLeave then
            self._needsScanOnLeave = false
            if sfui.buffs.scan and sfui.buffs.scan.RequestScan then
                sfui.buffs.scan.RequestScan()
            end
        end
    end)

    return btn
end

-- ─────────────────────────────────────────────────────────────
--  CONTAINER INITIALIZATION & DRAG LOGIC
-- ─────────────────────────────────────────────────────────────
local function InitContainer()
    if container then return container end

    container = CreateFrame("Frame", "SfuiBuffRemindersFrame", UIParent)
    container:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    container:SetClampedToScreen(true)
    container:SetMovable(true)

    -- Restore saved position
    local dbPos = SfuiDB and SfuiDB.buffRemindersPos
    if dbPos and dbPos.point == "CENTER" and dbPos.x == -220 and dbPos.y == -60 then
        dbPos.point = DEFAULT_POS.point
        dbPos.relPoint = DEFAULT_POS.relPoint
        dbPos.x = DEFAULT_POS.x
        dbPos.y = DEFAULT_POS.y
    end

    if dbPos and dbPos.point and dbPos.x and dbPos.y then
        container:SetPoint(dbPos.point, UIParent, dbPos.relPoint or dbPos.point, dbPos.x, dbPos.y)
    else
        container:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.relPoint, DEFAULT_POS.x, DEFAULT_POS.y)
    end

    -- Drag overlay for unlocking
    local dragOverlay = CreateFrame("Frame", nil, container)
    dragOverlay:SetAllPoints()
    dragOverlay:EnableMouse(true)
    dragOverlay:RegisterForDrag("LeftButton")
    dragOverlay:Hide()

    dragOverlay.bg = dragOverlay:CreateTexture(nil, "BACKGROUND")
    dragOverlay.bg:SetAllPoints()
    dragOverlay.bg:SetColorTexture(0.1, 0.6, 0.9, 0.35)

    if sfui.widgets and sfui.widgets.create_border then
        sfui.widgets.create_border(dragOverlay, 1, { 0.2, 0.8, 1, 1 })
    end

    local dragLabel = dragOverlay:CreateFontString(nil, "OVERLAY",
        sfui.config and sfui.config.font_small or "GameFontNormalSmall")
    dragLabel:SetPoint("BOTTOM", dragOverlay, "TOP", 0, 4)
    dragLabel:SetText("|cff00ffffbuff reminders|r |cffaaaaaa(drag)|r")
    dragOverlay.label = dragLabel

    dragOverlay:SetScript("OnDragStart", function()
        container:StartMoving()
    end)

    dragOverlay:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        local point, _, relPoint, x, y = container:GetPoint()
        if SfuiDB then
            SfuiDB.buffRemindersPos = {
                point = point or "CENTER",
                relPoint = relPoint or "CENTER",
                x = math_floor(x or 0),
                y = math_floor(y or 0),
            }
        end
    end)

    container.dragOverlay = dragOverlay
    sfui.buffs.container = container

    if sfui.movers and sfui.movers.Register then
        sfui.movers.Register(container, {
            key = "buffreminders",
            label = "buff reminders",
            preferredPoint = "CENTER",
            getPoint = function()
                local p = SfuiDB and SfuiDB.buffRemindersPos
                if p and p.point then
                    return p.point, UIParent, p.relPoint or p.point, p.x or DEFAULT_POS.x, p.y or DEFAULT_POS.y
                end
                return DEFAULT_POS.point, UIParent, DEFAULT_POS.relPoint, DEFAULT_POS.x, DEFAULT_POS.y
            end,
            setPoint = function(point, relTo, relPoint, x, y)
                local pt = point or "CENTER"
                local rPt = relPoint or pt
                local sx = math_floor((x or 0) + 0.5)
                local sy = math_floor((y or 0) + 0.5)
                container:ClearAllPoints()
                container:SetPoint(pt, UIParent, rPt, sx, sy)
                if SfuiDB then
                    SfuiDB.buffRemindersPos = {
                        point = pt,
                        relPoint = rPt,
                        x = sx,
                        y = sy,
                    }
                end
            end,
            resetPosition = function()
                sfui.buffs.ResetPosition()
            end,
            isEnabled = function()
                return not SfuiDB or not SfuiDB.buffReminders or SfuiDB.buffReminders.enabled ~= false
            end,
        })
    end

    return container
end

local function SetIconBorderColor(icon, r, g, b, a)
    if icon.borders then
        for j = 1, #icon.borders do
            icon.borders[j]:SetVertexColor(r, g, b, a or 1)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
--  DISPLAY UPDATE & RENDER LOOP
-- ─────────────────────────────────────────────────────────────
local function CountdownTick()
    local now = GetTime()
    local anyStillExpiring = false

    for i = 1, #iconPool do
        local icon = iconPool[i]
        if icon:IsShown() and icon.record and icon.record.isExpiring then
            local rec = icon.record
            local expTime = rec.expirationTime or 0
            local rem = expTime - now
            if rem > 0 then
                anyStillExpiring = true
                local formatted = FormatTime(rem)
                if icon._lastDurationText ~= formatted then
                    icon._lastDurationText = formatted
                    icon.durationText:SetText(formatted)
                end
                icon.durationText:Show()
            else
                icon._lastDurationText = nil
                icon.durationText:SetText("")
                icon.durationText:Hide()
                if sfui.buffs.scan and sfui.buffs.scan.RequestScan then
                    sfui.buffs.scan.RequestScan()
                end
            end
        end
    end

    if not anyStillExpiring and sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("SfuiBuffCountdown")
    end
end

function sfui.buffs.OnCombatEnter()
    if sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("SfuiBuffCountdown")
    end
    if container then
        container:SetAlpha(0)
        if not InCombatLockdown() then
            container:Hide()
        end
    end
end

function sfui.buffs.OnCombatLeave()
    local cSecrets = _G.C_Secrets
    local aurasSecret = cSecrets and cSecrets.ShouldAurasBeSecret and cSecrets.ShouldAurasBeSecret()
    if (InCombatLockdown and InCombatLockdown()) or aurasSecret then
        local cTimer = _G.C_Timer
        if cTimer and cTimer.After then
            cTimer.After(0.15, function()
                local stillSecret = cSecrets and cSecrets.ShouldAurasBeSecret and cSecrets.ShouldAurasBeSecret()
                if not InCombatLockdown() and not stillSecret then
                    sfui.buffs.UpdateDisplay()
                end
            end)
        end
        return
    end
    sfui.buffs.UpdateDisplay()
end

local function ApplyIconSecureAction(icon, actionType, actionVal, targetSlot, targetUnit)
    if icon._lastActionType == actionType
        and icon._lastActionVal == actionVal
        and icon._lastSlot == targetSlot
        and icon._lastUnit == targetUnit then
        return
    end
    icon._lastActionType = actionType
    icon._lastActionVal = actionVal
    icon._lastSlot = targetSlot
    icon._lastUnit = targetUnit

    if actionType == "item" and actionVal then
        icon:SetAttribute("type", "item")
        icon:SetAttribute("*type1", "item")
        icon:SetAttribute("item", actionVal)
        icon:SetAttribute("*item1", actionVal)
        icon:SetAttribute("spell", nil)
        icon:SetAttribute("*spell1", nil)
        icon:SetAttribute("target-slot", targetSlot)
        icon:SetAttribute("unit", nil)
    elseif actionType == "spell" and actionVal then
        icon:SetAttribute("type", "spell")
        icon:SetAttribute("*type1", "spell")
        icon:SetAttribute("spell", actionVal)
        icon:SetAttribute("*spell1", actionVal)
        icon:SetAttribute("item", nil)
        icon:SetAttribute("*item1", nil)
        icon:SetAttribute("target-slot", targetSlot)
        icon:SetAttribute("unit", targetUnit)
    else
        icon:SetAttribute("type", nil)
        icon:SetAttribute("*type1", nil)
        icon:SetAttribute("spell", nil)
        icon:SetAttribute("*spell1", nil)
        icon:SetAttribute("item", nil)
        icon:SetAttribute("*item1", nil)
        icon:SetAttribute("target-slot", nil)
        icon:SetAttribute("unit", nil)
    end
end

function sfui.buffs.UpdateDisplay()
    -- Only active on Camelot / Classic clients
    if not sfui.isCamelot and not sfui.isClassic then
        if container then
            container:SetAlpha(0)
            if not InCombatLockdown() then container:Hide() end
        end
        return
    end

    local f = InitContainer()
    local db = SfuiDB and SfuiDB.buffReminders
    if db and db.enabled == false then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiBuffCountdown")
        end
        f.activeIconCount = 0
        f:SetAlpha(0)
        if not InCombatLockdown() then f:Hide() end
        return
    end

    -- Suppression check: strictly hide in combat or when auras are secret
    local cSecrets = _G.C_Secrets
    local aurasSecret = cSecrets and cSecrets.ShouldAurasBeSecret and cSecrets.ShouldAurasBeSecret()
    local inCombat = sfui.common.is_in_combat() or InCombatLockdown() or aurasSecret
    if inCombat and not isUnlocked and not isTestMode then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiBuffCountdown")
        end
        f.activeIconCount = 0
        f:SetAlpha(0)
        if not InCombatLockdown() then
            f:Hide()
        end
        return
    end

    -- Suppression checks: dead, mounted, taxi, rested
    local isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    local isMount = (not db or db.hideMounted ~= false) and IsMounted and IsMounted()
    local isTaxi = (not db or db.hideMounted ~= false) and UnitOnTaxi and UnitOnTaxi("player")
    local isRested = (db and db.hideRested == true) and _G.IsResting and _G.IsResting()

    if (isDead or isMount or isTaxi or isRested) and not isUnlocked and not isTestMode then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiBuffCountdown")
        end
        f.activeIconCount = 0
        f:SetAlpha(0)
        if not InCombatLockdown() then
            f:Hide()
        end
        return
    end

    local records = isTestMode and GetTestRecords() or (sfui.buffs.scan and sfui.buffs.scan.GetResults()) or {}
    local numRecords = #records

    if numRecords == 0 and not isUnlocked then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiBuffCountdown")
        end
        f.activeIconCount = 0
        f:SetAlpha(0)
        if not InCombatLockdown() then
            f:Hide()
        end
        return
    end

    -- Past suppression checks: restore full container alpha
    f:SetAlpha(1.0)

    -- If unlocked but no records, show test preview so the anchor is grabbable
    if isUnlocked and numRecords == 0 then
        records = GetTestRecords()
        numRecords = #records
    end
    f.activeIconCount = numRecords

    local size = (db and db.iconSize) or DEFAULT_SIZE
    local spacing = (db and db.spacing) or DEFAULT_SPACING
    local now = GetTime()
    local allowClick = (not db or db.clickToCast ~= false) and not isTestMode

    for i = 1, numRecords do
        local rec = records[i]
        local icon = iconPool[i]
        if not icon then
            icon = CreateBuffIcon(i, f)
            iconPool[i] = icon
        end

        icon:EnableMouse(true)
        icon:SetAlpha(1.0)
        if icon._lastSize ~= size then
            icon._lastSize = size
            icon:SetSize(size, size)
        end
        local xOffset = (i - 1) * (size + spacing)
        if icon._lastXOffset ~= xOffset then
            icon._lastXOffset = xOffset
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", f, "LEFT", xOffset, 0)
        end
        icon.record = rec

        local provider = providers and providers.Resolve(rec.entry)
        local targetTex, cStr
        if provider and provider.resolveVisual then
            targetTex, cStr = provider.resolveVisual(rec)
        else
            targetTex = rec.icon
            cStr = (providers and providers.DefaultCountText(rec)) or ""
        end
        if not IsValidTexture(targetTex) then
            targetTex = "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        cStr = cStr or ""

        local loadedTex = icon.texture:GetTexture()
        if icon._lastTexture ~= targetTex or not IsValidTexture(loadedTex) then
            icon._lastTexture = targetTex
            icon.texture:SetTexture(targetTex)
            icon._lastStatus = nil
            if not IsValidTexture(icon.texture:GetTexture()) and sfui.common and sfui.common.debounce then
                sfui.common.debounce("sfui_buff_tex_retry", 0.15, function()
                    if sfui.buffs and sfui.buffs.UpdateDisplay and not (InCombatLockdown and InCombatLockdown()) then
                        sfui.buffs.UpdateDisplay()
                    end
                end)
            end
        end

        -- Appearance based on status (missing or expiring only)
        if rec.isMissing then
            if icon._lastStatus ~= "missing" then
                icon._lastStatus = "missing"
                icon.texture:SetDesaturated(true)
                icon.texture:SetVertexColor(1, 1, 1, 1)
                SetIconBorderColor(icon, 0.9, 0.15, 0.15, 1)
            end
            if icon._lastDurationText ~= "" then
                icon._lastDurationText = ""
                icon.durationText:SetText("")
            end
            icon.durationText:Hide()
            icon:SetAlpha(1.0)
        elseif rec.isExpiring then
            if icon._lastStatus ~= "expiring" then
                icon._lastStatus = "expiring"
                icon.texture:SetDesaturated(false)
                icon.texture:SetVertexColor(1, 1, 1, 1)
                SetIconBorderColor(icon, 1.0, 0.8, 0.1, 1)
            end

            local rem = (rec.expirationTime and rec.expirationTime > now) and (rec.expirationTime - now) or 0
            if rem > 0 then
                local formatted = FormatTime(rem)
                if icon._lastDurationText ~= formatted then
                    icon._lastDurationText = formatted
                    icon.durationText:SetText(formatted)
                end
                icon.durationText:Show()
            else
                if icon._lastDurationText ~= "" then
                    icon._lastDurationText = ""
                    icon.durationText:SetText("")
                end
                icon.durationText:Hide()
            end
            icon:SetAlpha(1.0)
        else
            if icon._lastStatus ~= "active" then
                icon._lastStatus = "active"
                icon.texture:SetDesaturated(false)
                icon.texture:SetVertexColor(1, 1, 1, 1)
                SetIconBorderColor(icon, 0, 0, 0, 1)
            end
            if icon._lastDurationText ~= "" then
                icon._lastDurationText = ""
                icon.durationText:SetText("")
            end
            icon.durationText:Hide()
            icon:SetAlpha(1.0)
        end

        -- Charges / stack count (cached to avoid redundant SetText)
        if icon._lastCountText ~= cStr then
            icon._lastCountText = cStr
            if cStr ~= "" then
                icon.countText:SetText(cStr)
                icon.countText:Show()
            else
                icon.countText:SetText("")
                icon.countText:Hide()
            end
        end

        -- Party target short name badge (top of icon)
        local tStr = ""
        if rec.unitName and rec.unitName ~= "" then
            local short = rec.unitName:sub(1, 5)
            if rec.unitClass and sfui.common and sfui.common.class_color_name then
                tStr = sfui.common.class_color_name(short, rec.unitClass)
            else
                tStr = short
            end
        end
        if icon._lastTargetText ~= tStr then
            icon._lastTargetText = tStr
            if tStr ~= "" then
                icon.targetText:SetText(tStr)
                icon.targetText:Show()
            else
                icon.targetText:SetText("")
                icon.targetText:Hide()
            end
        end

        -- Out-of-combat click-to-cast configuration with unified attribute caching
        if not inCombat then
            if allowClick and provider and provider.resolveAction then
                local aType, aVal, aSlot, aUnit = provider.resolveAction(rec)
                ApplyIconSecureAction(icon, aType, aVal, aSlot, aUnit)
            else
                ApplyIconSecureAction(icon, nil, nil, nil, nil)
            end
            icon:Show()
        else
            icon:SetAlpha(1.0)
        end
    end

    -- Hide surplus icons in the pool
    for i = numRecords + 1, #iconPool do
        if not inCombat then
            iconPool[i]:Hide()
            ApplyIconSecureAction(iconPool[i], nil, nil, nil, nil)
        else
            iconPool[i]:SetAlpha(0)
            iconPool[i]:EnableMouse(false)
        end
        iconPool[i].record = nil
    end

    -- Resize container frame to encompass the active icons
    local totalWidth = math_max(size, (numRecords * size) + (math_max(0, numRecords - 1) * spacing))
    f:SetSize(totalWidth, size)
    f:SetAlpha(1.0)
    if not InCombatLockdown() then
        f:Show()
    end

    -- Start or stop live countdown ticker via central dispatcher
    local hasExpiring = false
    for i = 1, numRecords do
        if records[i].isExpiring then
            hasExpiring = true
            break
        end
    end

    if hasExpiring and not inCombat and sfui.events and sfui.events.RegisterUpdate then
        sfui.events.RegisterUpdate("SfuiBuffCountdown", 0.25, CountdownTick)
    elseif sfui.events and sfui.events.UnregisterUpdate then
        sfui.events.UnregisterUpdate("SfuiBuffCountdown")
    end
end

-- ─────────────────────────────────────────────────────────────
--  LOCK / UNLOCK / TEST COMMANDS
-- ─────────────────────────────────────────────────────────────
function sfui.buffs.ToggleLock()
    local f = InitContainer()
    isUnlocked = not isUnlocked

    if isUnlocked then
        f:SetAlpha(1.0)
        if not InCombatLockdown() then f:Show() end
        f.dragOverlay:Show()
        sfui.common.print("buff reminders |cff00ff00unlocked|r: drag to move, then type |cffffd100/sfui buffs lock|r")
    else
        f.dragOverlay:Hide()
        sfui.common.print("buff reminders |cffff4444locked|r.")
    end

    sfui.buffs.UpdateDisplay()
end

function sfui.buffs.ToggleTest()
    local f = InitContainer()
    isTestMode = not isTestMode
    if isTestMode then
        f:SetAlpha(1.0)
        if not InCombatLockdown() then f:Show() end
    end
    sfui.common.print("buff reminders test mode: " .. (isTestMode and "|cff00ff00enabled|r" or "|cffff4444disabled|r"))
    sfui.buffs.UpdateDisplay()
end

function sfui.buffs.IsUnlocked()
    return isUnlocked
end

function sfui.buffs.IsTestMode()
    return isTestMode
end

function sfui.buffs.ResetPosition()
    local f = InitContainer()
    f:ClearAllPoints()
    f:SetPoint(DEFAULT_POS.point, UIParent, DEFAULT_POS.relPoint, DEFAULT_POS.x, DEFAULT_POS.y)
    if SfuiDB then
        SfuiDB.buffRemindersPos = {
            point = DEFAULT_POS.point,
            relPoint = DEFAULT_POS.relPoint,
            x = DEFAULT_POS.x,
            y = DEFAULT_POS.y,
        }
    end
    sfui.common.print("buff reminders position reset to default.")
    sfui.buffs.UpdateDisplay()
end

-- ─────────────────────────────────────────────────────────────
--  CENTRAL INITIALIZATION (sfui.events)
-- ─────────────────────────────────────────────────────────────
local function InitBuffReminders()
    if not sfui.isCamelot and not sfui.isClassic then return end

    if SfuiDB then
        SfuiDB.buffReminders = SfuiDB.buffReminders or {
            enabled = true,
            iconSize = DEFAULT_SIZE,
            spacing = DEFAULT_SPACING,
            shamanImbueMH = "auto",
            shamanImbueOH = "auto",
        }
        if SfuiDB.buffReminders.shamanImbueMH == nil then
            SfuiDB.buffReminders.shamanImbueMH = "auto"
        end
        if SfuiDB.buffReminders.shamanImbueOH == nil then
            SfuiDB.buffReminders.shamanImbueOH = "auto"
        end
        if SfuiDB.buffReminders.trackMinerals == nil then
            SfuiDB.buffReminders.trackMinerals = true
        end
        if SfuiDB.buffReminders.trackHerbs == nil then
            SfuiDB.buffReminders.trackHerbs = true
        end
        if SfuiDB.buffReminders.selectedPet == nil then
            SfuiDB.buffReminders.selectedPet = {}
        end
    end

    InitContainer()
    sfui.buffs.UpdateDisplay()
    if sfui.buffs.scan and sfui.buffs.scan.RequestScan then
        sfui.buffs.scan.RequestScan()
    end
end

if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("PLAYER_LOGIN", InitBuffReminders)
end

-- ─────────────────────────────────────────────────────────────
--  DIAGNOSTICS & MEMORY TELEMETRY
-- ─────────────────────────────────────────────────────────────
local _buffsDebug = {}
function sfui.buffs_debug_info()
    local sInfo = sfui.buffs.scan and sfui.buffs.scan.GetDebugInfo and sfui.buffs.scan.GetDebugInfo()
    _buffsDebug.enabled = (SfuiDB and SfuiDB.buffReminders and SfuiDB.buffReminders.enabled ~= false) or false
    _buffsDebug.containerCreated = (container ~= nil)
    _buffsDebug.containerShown = (container ~= nil and container:IsShown() == true)
    _buffsDebug.containerAlpha = (container ~= nil and container:GetAlpha()) or 0
    _buffsDebug.iconPool = #iconPool
    _buffsDebug.activeIcons = (container and container.activeIconCount) or 0
    _buffsDebug.activeResults = (sInfo and sInfo.activeResults) or 0
    _buffsDebug.auraPool = (sInfo and sInfo.auraPoolCount) or 0
    _buffsDebug.isUnlocked = isUnlocked
    _buffsDebug.isTestMode = isTestMode
    return _buffsDebug
end
sfui.buffs.GetDebugInfo = sfui.buffs_debug_info

if sfui.RegisterModule then
    sfui.buffs.OnEnable = function(self)
        if sfui.buffs.UpdateDisplay then sfui.buffs.UpdateDisplay() end
    end
    sfui.buffs.OnSettingsChanged = function(self, k, v)
        if sfui.buffs.UpdateDisplay then sfui.buffs.UpdateDisplay() end
    end
    sfui.RegisterModule("buffs", sfui.buffs)
end
