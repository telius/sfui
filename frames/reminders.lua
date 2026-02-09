local addonName, addon = ...
sfui = sfui or {}
sfui.reminders = {}

local RAID_BUFFS = {}
local PERSONAL_BUFFS = {}



local function has_rune()
    local RUNE_PAIRS = {
        { itemID = 243191, spellID = 1234969 }, -- Ethereal Augment Rune (TWW Permanent)
        { itemID = 224572, spellID = 449652 },  -- Algari Augment Rune (TWW Consumable)
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

local function has_weapon_enchant()
    local hasMainHandEnchant, mainHandExpiration, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
    if hasMainHandEnchant and (mainHandExpiration / 1000) > (10 * 60) then return true end
    if hasOffHandEnchant and (offHandExpiration / 1000) > (10 * 60) then return true end
    return false
end

local function has_healthstone()
    local HEALTHSTONES = { 5512, 162397, 221235, 224464 } -- Classic, Abyssal, Algari, Demonic
    for _, id in ipairs(HEALTHSTONES) do
        if C_Item.GetItemCount(id) > 0 then return true end
    end
    return false
end

local function update_buff_data()
    local playerClass = sfui.common.get_player_class()
    local specID = sfui.common.get_current_spec_id()

    local raidBuffs = {
        { name = "Stamina",      spellID = 21562,  icon = 135987,  class = "PRIEST" },                                        -- Power Word: Fortitude
        { name = "Intellect",    spellID = 1459,   icon = 135932,  class = "MAGE" },                                          -- Arcane Intellect
        { name = "Attack Power", spellID = 6673,   icon = 132333,  class = "WARRIOR" },                                       -- Battle Shout
        { name = "Versatility",  spellID = 1126,   icon = 136078,  class = "DRUID" },                                         -- Mark of the Wild
        { name = "Bronze",       spellID = 381748, icon = 4622448, class = "EVOKER" },                                        -- Blessing of the Bronze
        { name = "Soulstone",    spellID = 20707,  icon = 134336,  class = "WARLOCK", isAny = true, ignoreThreshold = true }, -- Soulstone
    }

    -- Reset BUFF_DATA
    wipe(RAID_BUFFS)
    wipe(PERSONAL_BUFFS)

    for _, b in ipairs(raidBuffs) do
        if sfui.common.is_class_in_group(b.class) then
            table.insert(RAID_BUFFS, b)
        end
    end

    local isSolo = not IsInGroup()
    -- Logic: If enableConsumables is true AND (enableConsumablesSolo is true OR we are in a group), show them.
    local enableConsumables = (SfuiDB.enableConsumables ~= false)
    local showConsumables = enableConsumables and (SfuiDB.enableConsumablesSolo or not isSolo)

    if showConsumables then
        if sfui.common.is_class_in_group("WARLOCK") then
            table.insert(PERSONAL_BUFFS, { name = "Healthstone", isHealthstone = true, icon = 135230 })
        end

        table.insert(PERSONAL_BUFFS, { name = "Food", isFood = true, icon = 136000 })
        table.insert(PERSONAL_BUFFS, { name = "Flask", isFlask = true, icon = 5931173 })

        local hasRune, runeSpellID, runeItemID, runeIcon = has_rune()
        if hasRune then
            table.insert(PERSONAL_BUFFS,
                { name = "Rune", spellID = runeSpellID, itemID = runeItemID, icon = runeIcon or 134430, isPersonal = true })
        end

        -- Weapon Oil / Enchant
        table.insert(PERSONAL_BUFFS, { name = "Weapon Oil", isWeaponEnchant = true, icon = 609892 })
    end

    -- Personal Buffs
    if playerClass == "ROGUE" then
        if showConsumables then
            table.insert(PERSONAL_BUFFS, { name = "Poison", isPoison = true, icon = 132273 })
        end
    elseif playerClass == "PRIEST" and specID == 258 then
        table.insert(PERSONAL_BUFFS, { name = "Shadowform", isShadowform = true, icon = 136200 })
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
local masqueGroup = sfui.common.get_masque_group("Reminders")

-- Warning Frame Logic (Merged from warnings.lua)
local warningFrame, warningText
local activeWarnings = {}

local function create_warning_frame()
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

local function update_warning_display()
    if not warningFrame then create_warning_frame() end
    local highestPri, bestWarning = 0, nil
    for _, warning in pairs(activeWarnings) do
        if warning.active and warning.priority > highestPri then
            highestPri, bestWarning = warning.priority, warning
        end
    end

    if bestWarning then
        warningText:SetText(bestWarning.text)
        sfui.common.set_color(warningText, bestWarning.color or "magenta")
        warningFrame:Show()
    else
        warningFrame:Hide()
    end
end

local function set_warning(key, active, text, priority, colorName)
    activeWarnings[key] = { active = active, text = text, priority = priority or 1, color = colorName }
    update_warning_display()
end

local threshold = sfui.config.reminders.buffThreshold -- From config

-- Reusable table for combining buffs (performance optimization)
local combined = {}


local function check_group_buff_status(spellID, ignoreThreshold)
    if not IsInGroup() then return sfui.common.has_aura(spellID, "player", not ignoreThreshold and threshold) end
    if not spellID then return false end

    local unitsToCheck = sfui.common.get_group_units()

    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            if not sfui.common.has_aura(spellID, unit, not ignoreThreshold and threshold) then return false end
        end
    end
    return true
end

local function check_any_group_buff_status(spellID, ignoreThreshold)
    if not IsInGroup() then return sfui.common.has_aura(spellID, "player", not ignoreThreshold and threshold) end
    if not spellID then return false end

    local unitsToCheck = sfui.common.get_group_units()

    for _, unit in ipairs(unitsToCheck) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            if sfui.common.has_aura(spellID, unit, not ignoreThreshold and threshold) then return true end
        end
    end
    return false
end

local function has_food()
    -- Direct safe lookup for "Well Fed" to avoid scanning in instances
    local aura = C_UnitAuras.GetAuraDataBySpellName("player", "Well Fed")
    if aura then
        if aura.expirationTime == 0 or (aura.expirationTime - GetTime()) > threshold then
            return true
        end
    end
    return false
end

local function has_flask()
    -- Direct Safe Lookup: Iterate known Flask IDs
    if sfui.common.FLASK_IDS then
        for _, spellID in ipairs(sfui.common.FLASK_IDS) do
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
            if aura then
                if aura.expirationTime == 0 or (aura.expirationTime - GetTime()) > threshold then
                    return true
                end
            end
        end
    end
    return false
end

local function has_poison()
    -- Poisons are now best checked via Weapon Enchants (Temp Enchants) for safety/compatibility
    local hasMainHandEnchant, mainHandExpiration, _, _, hasOffHandEnchant, offHandExpiration = GetWeaponEnchantInfo()
    if hasMainHandEnchant and (mainHandExpiration / 1000) > threshold then return true end
    if hasOffHandEnchant and (offHandExpiration / 1000) > threshold then return true end
    return false
end

local function IsPetOnPassive()
    if not UnitExists("pet") or not PetHasActionBar() then return false end
    for i = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(i)
        if isToken and name == "PET_MODE_PASSIVE" and isActive then return true end
    end
    return false
end

local function IsPetFelguard()
    local guid = UnitGUID("pet")
    if not guid then return false end
    local _, _, _, _, _, npcID = strsplit("-", guid)
    local id = tonumber(npcID)
    -- 17252: Felguard, 58965: Wrathguard (Glyph)
    return id == 17252 or id == 58965
end

local petWarningTimer = nil
local hasGrimoireOfSacrifice = false

function sfui.reminders.update_grimoire_status()
    hasGrimoireOfSacrifice = IsPlayerSpell(108503)
end

local function check_pet_warning()
    if InCombatLockdown() or not SfuiDB.enablePetWarning then
        set_warning("pet", false); return
    end

    -- 1. Check Passive Stance (Priority)
    if UnitExists("pet") and IsPetOnPassive() then
        -- Don't warn if we are mounted/resting, unless in combat (but we return early in combat anyway)
        if not IsMounted() and not IsResting() then
            set_warning("pet", true, "PET PASSIVE", 2, "red")
            return
        end
    end

    -- 2. Check Missing / Wrong Pet
    local playerClass = sfui.common.get_player_class()
    local specID = sfui.common.get_current_spec_id()
    local isAppropriateSpec = false
    local expectFelguard = false

    if playerClass == "HUNTER" and (specID == 253 or specID == 255) then -- BM or SV
        isAppropriateSpec = true
    elseif playerClass == "DEATHKNIGHT" and specID == 252 then           -- Unholy
        isAppropriateSpec = true
    elseif playerClass == "WARLOCK" then
        if not hasGrimoireOfSacrifice then
            isAppropriateSpec = true
            if specID == 266 then -- Demonology
                expectFelguard = true
            end
        end
    elseif playerClass == "MAGE" and specID == 64 then -- Frost
        if IsPlayerSpell(31687) then                   -- Summon Water Elemental
            isAppropriateSpec = true
        end
    end

    if not isAppropriateSpec then
        if petWarningTimer then
            C_Timer.Cancel(petWarningTimer); petWarningTimer = nil
        end
        set_warning("pet", false)
        return
    end

    -- Delayed check to handle dismount/zoning
    local function do_check()
        if InCombatLockdown() then return end
        local warning = false
        local text = ""

        if expectFelguard then
            if not UnitExists("pet") then
                warning = true; text = "NO PET"
            elseif not IsPetFelguard() then
                warning = true; text = "WRONG PET"
            end
        elseif not UnitExists("pet") then
            warning = true; text = "NO PET"
        end

        if warning and not IsMounted() and not IsResting() then
            local cfg = sfui.config.warnings.pet
            set_warning("pet", true, text, cfg.priority, cfg.color)
        else
            set_warning("pet", false)
        end
        petWarningTimer = nil
    end

    if not UnitExists("pet") or (expectFelguard and not IsPetFelguard()) then
        if not petWarningTimer then
            petWarningTimer = C_Timer.After(2, do_check)
        end
    else
        -- Happy path: Pet exists and is correct
        if petWarningTimer then
            C_Timer.Cancel(petWarningTimer); petWarningTimer = nil
        end
        set_warning("pet", false)
    end
end


local function create_icons()
    if InCombatLockdown() then return end
    local cfg = sfui.config.reminders

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
        frame.bg:SetBackdropColor(unpack(cfg.backdrop.color)) -- Semi-transparent black
        frame.bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -cfg.backdrop.padding, cfg.backdrop.padding)
        frame.bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", cfg.backdrop.padding, -cfg.backdrop.padding)
    end
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.remindersX or cfg.pos.x, SfuiDB.remindersY or cfg.pos.y)

    for _, icon in ipairs(icons) do icon:Hide() end

    local size, spacing, groupSpacing = cfg.icon_size, cfg.spacing, cfg.group_spacing

    -- Reuse combined table instead of recreating it
    wipe(combined)
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
        if i < #combined then
            local nextItem = combined[i + 1]
            local space = (nextItem and nextItem.isNewGroup) and groupSpacing or spacing
            totalWidth = totalWidth + space
        end
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

local function update_icons()
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
                    hasBuff = sfui.common.has_aura(data.spellID, "player", not data.ignoreThreshold and threshold)
                elseif data.isAny then
                    hasBuff = check_any_group_buff_status(data.spellID, data.ignoreThreshold)
                else
                    hasBuff = check_group_buff_status(data.spellID, data.ignoreThreshold)
                end
            elseif data.isFood then
                hasBuff = has_food()
            elseif data.isFlask then
                hasBuff = has_flask()
            elseif data.isPoison then
                hasBuff = has_poison()
            elseif data.isWeaponEnchant then
                hasBuff = has_weapon_enchant()
            elseif data.isHealthstone then
                hasBuff = has_healthstone()
            elseif data.isShadowform then
                -- Check for Shadowform (Form ID 28)
                hasBuff = (GetShapeshiftFormID() == 28)
            end
            button:SetAlpha(hasBuff and 0.1 or 1.0)
        end
    end
end

function sfui.reminders.update_position()
    if frame then frame:SetPoint("BOTTOM", UIParent, "BOTTOM", SfuiDB.remindersX, SfuiDB.remindersY) end
end

function sfui.reminders.on_state_changed(enabled)
    if enabled then
        update_buff_data(); sfui.reminders.update_grimoire_status(); create_icons(); update_icons()
        if sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
    else
        if frame then
            if not InCombatLockdown() then frame:Hide() end
            RegisterStateDriver(frame, "visibility", "hide")
        end
    end
    -- Always check warnings as they have their own toggles
    check_pet_warning()
end

function sfui.reminders.update_warnings()
    check_pet_warning()
end

function sfui.reminders.get_status()
    local status = {}
    for k, v in pairs(activeWarnings) do
        if v.active then table.insert(status, k .. ": " .. v.text) end
    end
    return #status > 0 and table.concat(status, ", ") or "No Active Warnings"
end

function sfui.reminders.update_visibility()
    if InCombatLockdown() then return end
    if not frame then return end

    local settings = SfuiDB
    if not settings.enableReminders then
        RegisterStateDriver(frame, "visibility", "hide")
        return
    end

    -- Check for M+ / Challenge Mode
    local activeKeystoneLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    if activeKeystoneLevel and activeKeystoneLevel > 0 then
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

function sfui.reminders.initialize()
    update_buff_data()
    sfui.reminders.update_grimoire_status()
    create_icons()
    create_warning_frame()

    if frame then
        sfui.reminders.update_visibility()
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
    -- M+ Events
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")

    eventFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_REGEN_DISABLED" then
            return
        end

        if event == "PLAYER_REGEN_ENABLED" then
            check_pet_warning()
            if sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
            return
        end

        if InCombatLockdown() then return end

        if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
            if sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end

        if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_TALENT_UPDATE" or event == "ZONE_CHANGED_NEW_AREA" then
            update_buff_data()
            sfui.reminders.update_grimoire_status()
            create_icons()
            check_pet_warning()
            if sfui.reminders.update_visibility then sfui.reminders.update_visibility() end
        end
        if event == "UNIT_AURA" and unit ~= "player" and not IsInGroup() then return end

        if event == "UNIT_PET" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_UPDATE_RESTING" then
            check_pet_warning()
        end

        -- Throttle updates to avoid excessive processing in raids
        if not self.updateTimer then
            self.updateTimer = C_Timer.NewTimer(0.5, function()
                update_icons()
                self.updateTimer = nil
            end)
        end
    end)

    local lastUpdate = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        lastUpdate = lastUpdate + elapsed
        if lastUpdate > 10 then
            update_icons(); lastUpdate = 0
        end
    end)

    update_icons()
    check_pet_warning()
end
