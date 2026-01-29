sfui = sfui or {}
sfui.reminders = {}

local RAID_BUFFS = {}
local PERSONAL_BUFFS = {}

local function IsClassPresent(className)
    local _, playerClass = UnitClass("player")
    if playerClass == className then return true end
    if not IsInGroup() then return false end

    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class == className then return true end
        end
    end
    return false
end

local function HasRune()
    local RUNE_PAIRS = {
        { itemID = 243191, spellID = 1234969 }, -- Ethereal Augment Rune (TWW Permanent)
        { itemID = 224572, spellID = 449652 },  -- Algari Augment Rune (TWW Consumable)
        { itemID = 211495, spellID = 393438 },  -- Draconic Augment Rune (DF)
    }
    for _, pair in ipairs(RUNE_PAIRS) do
        if C_Item.GetItemCount(pair.itemID) > 0 then
            local icon = C_Item.GetItemIconByID(pair.itemID)
            return true, pair.spellID, pair.itemID, icon
        end
    end
    -- Also check if we just HAVE the buff, regardless of item count (e.g. reused already)
    return false
end

local function HasWeaponEnchant()
    local hasMainHandEnchant, mainHandExpiration, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
    if hasMainHandEnchant and (mainHandExpiration / 1000) > (10 * 60) then return true end
    if hasOffHandEnchant and (offHandExpiration / 1000) > (10 * 60) then return true end
    return false
end

local function HasHealthstone()
    local HEALTHSTONES = { 5512, 162397, 221235, 224464 } -- Classic, Abyssal, Algari, Demonic
    for _, id in ipairs(HEALTHSTONES) do
        if C_Item.GetItemCount(id) > 0 then return true end
    end
    return false
end

local function UpdateBuffData()
    local _, playerClass = UnitClass("player")
    local spec = C_SpecializationInfo.GetSpecialization()
    local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0

    local raidBuffs = {
        { name = "Stamina",      spellID = 21562,  icon = 135987,  class = "PRIEST" },                                        -- Power Word: Fortitude
        { name = "Intellect",    spellID = 1459,   icon = 135932,  class = "MAGE" },                                          -- Arcane Intellect
        { name = "Attack Power", spellID = 6673,   icon = 132333,  class = "WARRIOR" },                                       -- Battle Shout
        { name = "Versatility",  spellID = 1126,   icon = 136078,  class = "DRUID" },                                         -- Mark of the Wild
        { name = "Bronze",       spellID = 364343, icon = 4622455, class = "EVOKER" },                                        -- Blessing of the Bronze
        { name = "Soulstone",    spellID = 20707,  icon = 134336,  class = "WARLOCK", isAny = true, ignoreThreshold = true }, -- Soulstone
    }

    -- Reset BUFF_DATA
    wipe(RAID_BUFFS)
    wipe(PERSONAL_BUFFS)

    for _, b in ipairs(raidBuffs) do
        if IsClassPresent(b.class) then
            table.insert(RAID_BUFFS, b)
        end
    end

    if IsClassPresent("WARLOCK") then
        table.insert(PERSONAL_BUFFS, { name = "Healthstone", isHealthstone = true, icon = 135230 })
    end

    table.insert(PERSONAL_BUFFS, { name = "Food", isFood = true, icon = 136000 })
    table.insert(PERSONAL_BUFFS, { name = "Flask", isFlask = true, icon = 5931173 })

    local hasRune, runeSpellID, runeItemID, runeIcon = HasRune()
    if hasRune then
        table.insert(PERSONAL_BUFFS,
            { name = "Rune", spellID = runeSpellID, itemID = runeItemID, icon = runeIcon or 134430, isPersonal = true })
    end

    -- Weapon Oil / Enchant
    table.insert(PERSONAL_BUFFS, { name = "Weapon Oil", isWeaponEnchant = true, icon = 609892 })

    -- Personal Buffs
    if playerClass == "ROGUE" then
        table.insert(PERSONAL_BUFFS, { name = "Poison", isPoison = true, icon = 132273 })
    elseif playerClass == "PRIEST" and specID == 258 then
        table.insert(PERSONAL_BUFFS, { name = "Shadowform", spellID = 15473, icon = 136202 })
    elseif playerClass == "SHAMAN" then
        if specID == 263 then -- Enhancement
            table.insert(PERSONAL_BUFFS, { name = "Windfury", spellID = 33757, icon = 136018 })
            table.insert(PERSONAL_BUFFS, { name = "Flametongue", spellID = 318038, icon = 135814 })
        elseif specID == 262 then -- Elemental
            table.insert(PERSONAL_BUFFS, { name = "Flametongue", spellID = 318038, icon = 135814 })
        elseif specID == 264 then -- Restoration
            table.insert(PERSONAL_BUFFS, { name = "Earthliving", spellID = 382303, icon = 135945 })
        end
    end
end

local frame
local icons = {}
local masqueGroup = sfui.common.GetMasqueGroup("Reminders")

-- Warning Frame Logic (Merged from warnings.lua)
local warningFrame, warningText
local activeWarnings = {}

local function CreateWarningFrame()
    if warningFrame then return end
    warningFrame = CreateFrame("Frame", "SfuiWarningFrame", UIParent, "BackdropTemplate")
    warningFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    warningFrame:SetSize(300, 50); warningFrame:SetFrameStrata("HIGH")
    warningFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", tile = true, tileSize = 16, edgeSize = 0, insets = { 0, 0, 0, 0 } })
    warningFrame:SetBackdropColor(0.8, 0, 0, 0.8); warningFrame:Hide()

    warningText = warningFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    warningText:SetAllPoints(warningFrame)
    warningText:SetText("")
end

local function UpdateWarningDisplay()
    if not warningFrame then CreateWarningFrame() end
    local highestPri, bestWarning = 0, nil
    for _, warning in pairs(activeWarnings) do
        if warning.active and warning.priority > highestPri then
            highestPri, bestWarning = warning.priority, warning
        end
    end

    if bestWarning then
        warningText:SetText(bestWarning.text)
        sfui.common.SetColor(warningText, bestWarning.color or "magenta")
        warningFrame:Show()
    else
        warningFrame:Hide()
    end
end

local function SetWarning(key, active, text, priority, colorName)
    activeWarnings[key] = { active = active, text = text, priority = priority or 1, color = colorName }
    UpdateWarningDisplay()
end

local threshold = 600 -- 10 minutes

local function HasAura(spellID, unit, ignoreThreshold)
    unit = unit or "player"
    local spellName
    if C_Spell and C_Spell.GetSpellName then
        spellName = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        spellName = GetSpellInfo(spellID)
    end

    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not aura then break end

        if aura.spellId == spellID or (spellName and aura.name == spellName) then
            if aura.expirationTime == 0 or ignoreThreshold then return true end
            return (aura.expirationTime - GetTime()) > threshold
        end
    end
    return false
end

local function CheckGroupBuffStatus(spellID, ignoreThreshold)
    if not IsInGroup() then return HasAura(spellID, "player", ignoreThreshold) end
    if not spellID then return false end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local unitsToCheck = {}

    if isRaid then
        for i = 1, numMembers do table.insert(unitsToCheck, "raid" .. i) end
    else
        table.insert(unitsToCheck, "player")
        for i = 1, numMembers - 1 do table.insert(unitsToCheck, "party" .. i) end
    end

    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            if not HasAura(spellID, unit, ignoreThreshold) then return false end
        end
    end
    return true
end

local function CheckAnyGroupBuffStatus(spellID, ignoreThreshold)
    if not IsInGroup() then return HasAura(spellID, "player", ignoreThreshold) end
    if not spellID then return false end

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    local unitsToCheck = {}

    if isRaid then
        for i = 1, numMembers do table.insert(unitsToCheck, "raid" .. i) end
    else
        table.insert(unitsToCheck, "player")
        for i = 1, numMembers - 1 do table.insert(unitsToCheck, "party" .. i) end
    end

    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            if HasAura(spellID, unit, ignoreThreshold) then return true end
        end
    end
    return false
end

local function HasFood()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if aura.name == "Well Fed" or (aura.spellId == 22568) then
            if aura.expirationTime == 0 or (aura.expirationTime - GetTime()) > threshold then
                return true
            end
        end
    end
    return false
end

local function HasFlask()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local name = aura.name:lower()
        if name:find("flask") or name:find("phial") or name:find("greater flask") then
            if aura.expirationTime == 0 or (aura.expirationTime - GetTime()) > threshold then
                return true
            end
        end
    end
    return false
end

local function HasPoison()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local name = aura.name:lower()
        if name:find("poison") then
            if aura.expirationTime == 0 or (aura.expirationTime - GetTime()) > threshold then
                return true
            end
        end
    end
    local hasMainHandEnchant, mainHandExpiration, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
    if hasMainHandEnchant and (mainHandExpiration / 1000) > threshold then return true end
    if hasOffHandEnchant and (offHandExpiration / 1000) > threshold then return true end
    return false
end

local function CheckAugmentRunes()
    if InCombatLockdown() or not SfuiDB.enableRuneWarning then
        SetWarning("rune", false); return
    end

    local cfg = sfui.config.warnings.rune

    local hasRune, spellID = HasRune()
    -- Use HasAura for robust name matching
    local missingRune = hasRune and not HasAura(spellID, "player")

    if missingRune then
        SetWarning("rune", true, cfg.text, cfg.priority, cfg.color)
    else
        SetWarning("rune", false)
    end
end

local petWarningTimer = nil
local hasGrimoireOfSacrifice = false

local function UpdateGrimoireOfSacrificeStatus()
    hasGrimoireOfSacrifice = IsPlayerSpell(108503)
end
local function CheckPetWarning()
    if InCombatLockdown() or not SfuiDB.enablePetWarning then
        SetWarning("pet", false); return
    end

    local _, playerClass = UnitClass("player")
    local spec = C_SpecializationInfo.GetSpecialization()
    local specID = spec and select(1, C_SpecializationInfo.GetSpecializationInfo(spec)) or 0
    local isAppropriateSpec = false

    if playerClass == "HUNTER" and (specID == 253 or specID == 255) then
        isAppropriateSpec = true
    elseif playerClass == "DEATHKNIGHT" and specID == 252 then
        isAppropriateSpec = true
    elseif playerClass == "WARLOCK" and not hasGrimoireOfSacrifice then -- Grimoire of Sacrifice
        isAppropriateSpec = true
    end

    if isAppropriateSpec and not UnitExists("pet") and not IsMounted() and not IsResting() then
        if not petWarningTimer then
            petWarningTimer = C_Timer.After(2, function()
                if not UnitExists("pet") and not IsResting() then
                    local cfg = sfui.config.warnings.pet
                    SetWarning("pet", true, cfg.text, cfg.priority, cfg.color)
                else
                    SetWarning("pet", false)
                end
                petWarningTimer = nil
            end)
        end
    else
        if petWarningTimer then
            C_Timer.Cancel(petWarningTimer); petWarningTimer = nil
        end
        SetWarning("pet", false)
    end
end


local function CreateIcons()
    if InCombatLockdown() then return end
    if not frame then
        frame = CreateFrame("Frame", "SfuiRemindersFrame", UIParent, "SecureHandlerStateTemplate")

        -- Create background panel
        frame.bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.bg:SetFrameLevel(frame:GetFrameLevel() - 1)
        frame.bg:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            tile = true,
            tileSize = 16,
        })
        frame.bg:SetBackdropColor(0, 0, 0, 0.5) -- Semi-transparent black
        frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
        frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    end
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.remindersX, SfuiDB.remindersY)

    for _, icon in ipairs(icons) do icon:Hide() end

    local size, spacing, groupSpacing = 32, 4, 12
    local combined = {}
    for _, b in ipairs(RAID_BUFFS) do table.insert(combined, b) end
    for i, b in ipairs(PERSONAL_BUFFS) do
        local entry = {}
        for k, v in pairs(b) do entry[k] = v end
        if i == 1 then entry.isNewGroup = true end
        table.insert(combined, entry)
    end

    local totalWidth = 0
    for i, b in ipairs(combined) do
        totalWidth = totalWidth + size
        if i < #combined then totalWidth = totalWidth + (b.isNewGroup and groupSpacing or spacing) end
    end
    frame:SetSize(totalWidth or size, size)

    for i, data in ipairs(combined) do
        local button = icons[i]
        if not button then
            button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
            button:SetSize(size, size)
            button.texture = button:CreateTexture(nil, "ARTWORK")
            button.texture:SetAllPoints()
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetAllPoints()
            button.bg:SetColorTexture(0, 0, 0, 0.5)
            button:HookScript("OnClick", function(self)
                if IsShiftKeyDown() and self.data and not self.data.isPersonal then
                    local name = self.data.name
                    if self.data.spellID then
                        local link = C_Spell.GetSpellLink(self.data.spellID)
                        name = link or name
                    end
                    local msg = string.format("- %s missing -", name)
                    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
                    if IsInInstance() then channel = "INSTANCE_CHAT" end
                    SendChatMessage(msg, channel)
                end
            end)
            if masqueGroup then masqueGroup:AddButton(button) end
            icons[i] = button
        end

        button.data = data
        button.data.isPersonal = (i > #RAID_BUFFS)
        button.texture:SetTexture(data.icon)
        button:ClearAllPoints()

        if data.itemID then
            button:SetAttribute("type", "item")
            button:SetAttribute("item", "item:" .. data.itemID)
        else
            button:SetAttribute("type", nil); button:SetAttribute("item", nil)
        end

        if i == 1 then
            button:SetPoint("LEFT", frame, "LEFT", 0, 0)
        else
            local prev = icons[i - 1]
            local offset = data.isNewGroup and groupSpacing or spacing
            button:SetPoint("LEFT", prev, "RIGHT", offset, 0)
        end
        button:Show()
    end
end

local function UpdateIcons()
    if not frame then return end
    if InCombatLockdown() then return end

    local inInstance, _ = IsInInstance()
    local inGroup = IsInGroup()

    -- Visibility is now primarily handled by the Secure State Driver,
    -- but we still apply the user's manual enable/disable here (outside combat).
    if not SfuiDB.enableReminders then
        frame:Hide()
        return
    end

    local combined = {}
    for _, b in ipairs(RAID_BUFFS) do table.insert(combined, b) end
    for _, b in ipairs(PERSONAL_BUFFS) do table.insert(combined, b) end

    for i, data in ipairs(combined) do
        local button = icons[i]
        if button then
            local hasBuff = false
            if data.spellID then
                if data.isPersonal then
                    hasBuff = HasAura(data.spellID, "player", data.ignoreThreshold)
                elseif data.isAny then
                    hasBuff = CheckAnyGroupBuffStatus(data.spellID, data.ignoreThreshold)
                else
                    hasBuff = CheckGroupBuffStatus(data.spellID, data.ignoreThreshold)
                end
            elseif data.isFood then
                hasBuff = HasFood()
            elseif data.isFlask then
                hasBuff = HasFlask()
            elseif data.isPoison then
                hasBuff = HasPoison()
            elseif data.isWeaponEnchant then
                hasBuff = HasWeaponEnchant()
            elseif data.isHealthstone then
                hasBuff = HasHealthstone()
            end
            button:SetAlpha(hasBuff and 0.1 or 1.0)
        end
    end
end

function sfui.reminders.UpdatePosition()
    if frame then frame:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.remindersX, SfuiDB.remindersY) end
end

function sfui.reminders.OnStateChanged(enabled)
    if enabled then
        UpdateBuffData(); CreateIcons(); UpdateIcons()
        if sfui.reminders.UpdateVisibility then sfui.reminders.UpdateVisibility() end
    else
        if frame then
            if not InCombatLockdown() then frame:Hide() end
            RegisterStateDriver(frame, "visibility", "hide")
        end
    end
    -- Always check warnings as they have their own toggles
    CheckPetWarning(); CheckAugmentRunes()
end

function sfui.reminders.UpdateWarnings()
    CheckPetWarning(); CheckAugmentRunes()
end

function sfui.reminders.GetStatus()
    local status = {}
    for k, v in pairs(activeWarnings) do
        if v.active then table.insert(status, k .. ": " .. v.text) end
    end
    return #status > 0 and table.concat(status, ", ") or "No Active Warnings"
end

function sfui.reminders.UpdateVisibility()
    if InCombatLockdown() then return end
    if not frame then return end

    local settings = SfuiDB
    if not settings.enableReminders then
        RegisterStateDriver(frame, "visibility", "hide")
        return
    end

    local inInstance, instanceType = IsInInstance()
    local isInstance = (instanceType == "party" or instanceType == "raid")
    local allowedZone = settings.remindersEverywhere or isInstance

    if not allowedZone then
        RegisterStateDriver(frame, "visibility", "hide")
        return
    end

    local driver = "[combat] hide; "
    if settings.remindersSolo then
        driver = driver .. "show"
    else
        driver = driver .. "[group] show; hide"
    end

    RegisterStateDriver(frame, "visibility", driver)
end

function sfui.reminders.Initialize()
    UpdateBuffData()
    UpdateGrimoireOfSacrificeStatus()
    CreateIcons()
    CreateWarningFrame()

    if frame then
        sfui.reminders.UpdateVisibility()
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")

    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Visibility is handled by State Driver
            return
        end

        if InCombatLockdown() then return end

        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_TALENT_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
            UpdateBuffData()
            UpdateGrimoireOfSacrificeStatus()
            CreateIcons()
            CheckPetWarning()
            CheckAugmentRunes()
            if sfui.reminders.UpdateVisibility then sfui.reminders.UpdateVisibility() end
        end
        if event == "UNIT_AURA" and unit ~= "player" and not IsInGroup() then return end

        if event == "UNIT_AURA" or event == "BAG_UPDATE_DELAYED" then CheckAugmentRunes() end
        if event == "UNIT_PET" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_UPDATE_RESTING" then
            CheckPetWarning()
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            CheckPetWarning(); CheckAugmentRunes()
        end

        -- Throttle updates to avoid excessive processing in raids
        if not self.updateTimer then
            self.updateTimer = C_Timer.NewTimer(0.5, function()
                UpdateIcons()
                self.updateTimer = nil
            end)
        end
    end)

    local lastUpdate = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed
        if lastUpdate > 10 then
            UpdateIcons(); lastUpdate = 0
        end
    end)

    UpdateIcons()
    CheckPetWarning()
    CheckAugmentRunes()
end
