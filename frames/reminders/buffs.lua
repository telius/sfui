local addonName, addon = ...
sfui = sfui or {}
sfui.buffs = sfui.buffs or {}

local _G = _G
local ipairs, pairs = _G.ipairs, _G.pairs
local math_floor = math.floor
local math_ceil = math.ceil
local string_format = string.format
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local GameTooltip = sfui.common.get_tooltip()
local GetTime = _G.GetTime
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local IsMounted = _G.IsMounted
local UnitOnTaxi = _G.UnitOnTaxi
local InCombatLockdown = _G.InCombatLockdown
local tostring = _G.tostring

-- Default settings
local DEFAULT_SIZE = 36
local DEFAULT_SPACING = 4
local DEFAULT_POS = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 42 }

local container = nil
local iconPool = {}
local isUnlocked = false
local isTestMode = false
local hasPendingCombatUpdate = false

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

local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 3600 then
        return string_format("%dh", math_floor(seconds / 3600))
    elseif seconds >= 60 then
        return string_format("%dm", math_ceil(seconds / 60))
    else
        return string_format("%ds", math.max(1, math_floor(seconds)))
    end
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

    btn:EnableMouseWheel(true)
    btn:SetScript("OnMouseWheel", function(self, delta)
        if self.record and self.record.entry and self.record.entry.key == "consumable_food" then
            if sfui.buffs.consumables and sfui.buffs.consumables.CycleFood then
                sfui.buffs.consumables.CycleFood(delta)
                if self.isHovered and GameTooltip and GameTooltip:GetOwner() == self then
                    local onEnter = self:GetScript("OnEnter")
                    if onEnter then onEnter(self) end
                end
            end
        elseif self.record and self.record.entry and self.record.entry.type == "pet" then
            if sfui.buffs.pets and sfui.buffs.pets.CyclePet then
                sfui.buffs.pets.CyclePet(delta)
                if self.isHovered and GameTooltip and GameTooltip:GetOwner() == self then
                    local onEnter = self:GetScript("OnEnter")
                    if onEnter then onEnter(self) end
                end
            end
        end
    end)

    -- Tooltip interaction
    btn:SetScript("OnEnter", function(self)
        self.isHovered = true
        if not self.record then return end
        local rec = self.record
        local entry = rec.entry

        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()

        if rec.isMissing then
            GameTooltip:AddLine("|cffff4444[missing]|r " .. (entry.name or "buff"), 1, 1, 1)
        elseif rec.isExpiring then
            GameTooltip:AddLine("|cffffcc00[expiring]|r " .. (entry.name or "buff"), 1, 1, 1)
        else
            GameTooltip:AddLine("|cff00ff00[active]|r " .. (entry.name or "buff"), 1, 1, 1)
        end

        if rec.expirationTime and rec.expirationTime > 0 then
            local rem = rec.expirationTime - GetTime()
            if rem > 0 then
                GameTooltip:AddLine(string_format("remaining: |cffffd100%s|r", FormatTime(rem)), 0.8, 0.8, 0.8)
            end
        end

        if rec.charges and rec.charges > 0 then
            GameTooltip:AddLine(string_format("charges: |cffffffff%d|r", rec.charges), 0.8, 0.8, 0.8)
        end

        if entry.type == "weapon_enchant" then
            GameTooltip:AddLine("apply weapon temporary enchant / poison", 0.6, 0.6, 0.6)
        elseif entry.type == "pet" then
            GameTooltip:AddLine("summon your active pet", 0.6, 0.6, 0.6)
        elseif entry.type == "stance" then
            GameTooltip:AddLine("activate your combat stance", 0.6, 0.6, 0.6)
        elseif entry.type == "tracking" then
            GameTooltip:AddLine("activate resource tracking", 0.6, 0.6, 0.6)
        end

        if entry.key == "consumable_food" and sfui.buffs.consumables and sfui.buffs.consumables.GetSelectedFood then
            local selectedFood, allFoods = sfui.buffs.consumables.GetSelectedFood()
            if selectedFood and (selectedFood.itemLink or selectedFood.itemID) then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetHyperlink(selectedFood.itemLink or ("item:" .. selectedFood.itemID))

                GameTooltip:AddLine(" ")
                if rec.isMissing then
                    GameTooltip:AddLine("|cffff4444[missing well fed buff]|r", 1, 0.4, 0.4)
                elseif rec.isExpiring then
                    local rem = (rec.expirationTime and rec.expirationTime > 0) and (rec.expirationTime - GetTime()) or 0
                    if rem > 0 then
                        GameTooltip:AddLine(string_format("|cffffcc00[expiring well fed]|r remaining: |cffffd100%s|r", FormatTime(rem)), 1, 0.8, 0)
                    else
                        GameTooltip:AddLine("|cffffcc00[expiring well fed]|r", 1, 0.8, 0)
                    end
                else
                    GameTooltip:AddLine("|cff00ff00[well fed active]|r", 0.4, 1, 0.4)
                end

                if selectedFood.count and selectedFood.count > 0 then
                    local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
                    if inCombat then
                        GameTooltip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
                    else
                        GameTooltip:AddLine("|cff55ff55[click to eat]|r " .. selectedFood.name:lower(), 0.3, 1, 0.3)
                    end
                else
                    GameTooltip:AddLine("|cffff5555no food with buff in bags|r", 0.9, 0.4, 0.4)
                end

                if allFoods and #allFoods > 1 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("scroll wheel to select food:", 0.5, 0.8, 1)
                    for _, fInfo in ipairs(allFoods) do
                        local isCur = (fInfo.name == selectedFood.name or fInfo.itemID == selectedFood.itemID)
                        local cStr = string_format(" (%d)", fInfo.count or 0)
                        if isCur then
                            GameTooltip:AddLine("  > " .. fInfo.name:lower() .. cStr, 1, 0.82, 0)
                        else
                            GameTooltip:AddLine("    " .. fInfo.name:lower() .. cStr, 0.6, 0.6, 0.6)
                        end
                    end
                end

                if isUnlocked then
                    GameTooltip:AddLine("|cff888888(drag to reposition reminders)|r", 0.5, 0.5, 0.5)
                end
                GameTooltip:Show()
                return
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffff5555no food with buff in bags|r", 0.9, 0.4, 0.4)
        elseif entry.type == "pet" and sfui.buffs.pets and sfui.buffs.pets.GetSelectedPet then
            local selectedPet, allPets = sfui.buffs.pets.GetSelectedPet()
            if selectedPet then
                GameTooltip:ClearLines()
                if rec.isMissing then
                    GameTooltip:AddLine("|cffff4444[missing]|r " .. selectedPet.displayName, 1, 1, 1)
                else
                    GameTooltip:AddLine("|cff00ff00[active]|r " .. selectedPet.displayName, 1, 1, 1)
                end
                GameTooltip:AddLine("summon your active pet", 0.6, 0.6, 0.6)

                local db = SfuiDB and SfuiDB.buffReminders
                if db and db.clickToCast ~= false and not isTestMode then
                    local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
                    if inCombat then
                        GameTooltip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
                    else
                        local castLabel = (selectedPet.cleanName or selectedPet.displayName or selectedPet.spellName:gsub("^[Ss][Uu][Mm][Mm][Oo][Nn]%s+", "")):lower()
                        GameTooltip:AddLine("|cff55ff55[click to summon]|r " .. castLabel, 0.3, 1, 0.3)
                    end
                end

                if allPets and #allPets > 1 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("scroll wheel to select pet:", 0.5, 0.8, 1)
                    for _, pInfo in ipairs(allPets) do
                        local isCur = (pInfo.id == selectedPet.id)
                        if isCur then
                            GameTooltip:AddLine("  > " .. pInfo.displayName, 1, 0.82, 0)
                        else
                            GameTooltip:AddLine("    " .. pInfo.displayName, 0.6, 0.6, 0.6)
                        end
                    end
                end

                if isUnlocked then
                    GameTooltip:AddLine("|cff888888(drag to reposition reminders)|r", 0.5, 0.5, 0.5)
                end
                GameTooltip:Show()
                return
            end
        else
            local db = SfuiDB and SfuiDB.buffReminders
            if db and db.clickToCast ~= false and not isTestMode then
                local inCombat = _G.InCombatLockdown and _G.InCombatLockdown()
                if inCombat then
                    GameTooltip:AddLine("|cff888888[combat locked]|r", 0.6, 0.6, 0.6)
                else
                    local castSpell = sfui.buffs.data and sfui.buffs.data.GetBestCastSpell and
                        sfui.buffs.data.GetBestCastSpell(entry, rec.activeEnchant)
                    if castSpell then
                        GameTooltip:AddLine("|cff55ff55[click to cast]|r " .. castSpell:lower(), 0.3, 1, 0.3)
                    end
                end
            end
        end

        if isUnlocked then
            GameTooltip:AddLine("|cff888888(drag to reposition reminders)|r", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self.isHovered = false
        GameTooltip:Hide()
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
    hasPendingCombatUpdate = true
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
    hasPendingCombatUpdate = false
    if InCombatLockdown and InCombatLockdown() then
        hasPendingCombatUpdate = true
        local cTimer = _G.C_Timer
        if cTimer and cTimer.After then
            cTimer.After(0.15, function()
                if not InCombatLockdown() then
                    hasPendingCombatUpdate = false
                    sfui.buffs.UpdateDisplay()
                end
            end)
        end
        return
    end
    sfui.buffs.UpdateDisplay()
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
        f:SetAlpha(0)
        if not InCombatLockdown() then f:Hide() end
        return
    end

    -- Suppression check: strictly hide in combat
    local inCombat = sfui.common.is_in_combat() or InCombatLockdown()
    if inCombat and not isUnlocked and not isTestMode then
        if sfui.events and sfui.events.UnregisterUpdate then
            sfui.events.UnregisterUpdate("SfuiBuffCountdown")
        end
        f:SetAlpha(0)
        if not InCombatLockdown() then
            f:Hide()
        end
        hasPendingCombatUpdate = true
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
        f:SetAlpha(0)
        if not InCombatLockdown() then
            f:Hide()
        end
        return
    end

    -- Past suppression checks: restore full container alpha
    hasPendingCombatUpdate = false
    f:SetAlpha(1.0)

    -- If unlocked but no records, show test preview so the anchor is grabbable
    if isUnlocked and numRecords == 0 then
        records = GetTestRecords()
        numRecords = #records
    end

    local size = (db and db.iconSize) or DEFAULT_SIZE
    local spacing = (db and db.spacing) or DEFAULT_SPACING
    local now = GetTime()

    for i = 1, numRecords do
        local rec = records[i]
        local icon = iconPool[i]
        if not icon then
            icon = CreateBuffIcon(i, f)
            iconPool[i] = icon
        end

        icon:EnableMouse(true)
        icon:SetAlpha(1.0)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", f, "LEFT", (i - 1) * (size + spacing), 0)
        icon.record = rec

        local isFood = (rec.entry and rec.entry.key == "consumable_food")
        local selectedFood = isFood and sfui.buffs.consumables and sfui.buffs.consumables.GetSelectedFood and sfui.buffs.consumables.GetSelectedFood()

        local isPet = (rec.entry and rec.entry.type == "pet")
        local selectedPet = isPet and sfui.buffs.pets and sfui.buffs.pets.GetSelectedPet and sfui.buffs.pets.GetSelectedPet()

        -- Set texture
        if isFood and selectedFood and selectedFood.icon then
            icon.texture:SetTexture(selectedFood.icon)
        elseif isPet and selectedPet and selectedPet.icon then
            icon.texture:SetTexture(selectedPet.icon)
        else
            icon.texture:SetTexture(rec.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
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
        local cStr = ""
        if isFood then
            if selectedFood and selectedFood.count and selectedFood.count > 0 then
                cStr = tostring(selectedFood.count)
            elseif rec.isMissing then
                cStr = "0"
            end
        elseif rec.charges and rec.charges > 1 then
            cStr = tostring(rec.charges)
        end

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

        -- Out-of-combat click-to-cast configuration with attribute caching
        if not inCombat then
            if isFood then
                if db and db.clickToCast ~= false and not isTestMode and selectedFood and selectedFood.count and selectedFood.count > 0 then
                    local itemName = selectedFood.name
                    if icon._lastItem ~= itemName or icon._lastSpell ~= nil or icon._lastSlot ~= nil then
                        icon._lastItem = itemName
                        icon._lastSpell = nil
                        icon._lastSlot = nil
                        icon:SetAttribute("type", "item")
                        icon:SetAttribute("item", itemName)
                        icon:SetAttribute("spell", nil)
                        icon:SetAttribute("target-slot", nil)
                        icon:SetAttribute("unit", nil)
                    end
                else
                    if icon._lastItem ~= nil or icon._lastSpell ~= nil or icon._lastSlot ~= nil then
                        icon._lastItem = nil
                        icon._lastSpell = nil
                        icon._lastSlot = nil
                        icon:SetAttribute("type", nil)
                        icon:SetAttribute("item", nil)
                        icon:SetAttribute("spell", nil)
                        icon:SetAttribute("target-slot", nil)
                        icon:SetAttribute("unit", nil)
                    end
                end
            elseif db and db.clickToCast ~= false and not isTestMode and rec.entry then
                local castSpell = sfui.buffs.data and sfui.buffs.data.GetBestCastSpell and
                    sfui.buffs.data.GetBestCastSpell(rec.entry, rec.activeEnchant)
                local targetSlot = (rec.entry.type == "weapon_enchant") and (rec.entry.slot or 16) or nil
                if castSpell then
                    if icon._lastSpell ~= castSpell or icon._lastSlot ~= targetSlot or icon._lastItem ~= nil then
                        icon._lastSpell = castSpell
                        icon._lastSlot = targetSlot
                        icon._lastItem = nil
                        icon:SetAttribute("type", "spell")
                        icon:SetAttribute("spell", castSpell)
                        icon:SetAttribute("item", nil)
                        if targetSlot then
                            icon:SetAttribute("target-slot", targetSlot)
                            icon:SetAttribute("unit", nil)
                        elseif rec.entry.type == "pet" then
                            icon:SetAttribute("target-slot", nil)
                            icon:SetAttribute("unit", nil)
                        else
                            icon:SetAttribute("target-slot", nil)
                            icon:SetAttribute("unit", "player")
                        end
                    end
                else
                    if icon._lastSpell ~= nil or icon._lastSlot ~= nil or icon._lastItem ~= nil then
                        icon._lastSpell = nil
                        icon._lastSlot = nil
                        icon._lastItem = nil
                        icon:SetAttribute("type", nil)
                        icon:SetAttribute("spell", nil)
                        icon:SetAttribute("item", nil)
                        icon:SetAttribute("target-slot", nil)
                        icon:SetAttribute("unit", nil)
                    end
                end
            else
                if icon._lastSpell ~= nil or icon._lastSlot ~= nil or icon._lastItem ~= nil then
                    icon._lastSpell = nil
                    icon._lastSlot = nil
                    icon._lastItem = nil
                    icon:SetAttribute("type", nil)
                    icon:SetAttribute("spell", nil)
                    icon:SetAttribute("item", nil)
                    icon:SetAttribute("target-slot", nil)
                    icon:SetAttribute("unit", nil)
                end
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
            if iconPool[i]._lastSpell ~= nil or iconPool[i]._lastSlot ~= nil or iconPool[i]._lastItem ~= nil then
                iconPool[i]._lastSpell = nil
                iconPool[i]._lastSlot = nil
                iconPool[i]._lastItem = nil
                iconPool[i]:SetAttribute("type", nil)
                iconPool[i]:SetAttribute("spell", nil)
                iconPool[i]:SetAttribute("item", nil)
                iconPool[i]:SetAttribute("target-slot", nil)
                iconPool[i]:SetAttribute("unit", nil)
            end
        else
            iconPool[i]:SetAlpha(0)
            iconPool[i]:EnableMouse(false)
        end
        iconPool[i].record = nil
    end

    -- Resize container frame to encompass the active icons
    local totalWidth = math.max(size, (numRecords * size) + (math.max(0, numRecords - 1) * spacing))
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
