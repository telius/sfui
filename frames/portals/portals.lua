-- frames/portals.lua
-- Portal panel. Data lives in portals_db.lua.
-- Clicking uses Scotty's InsecureActionButtonTemplate overlay pattern:
--   one shared action button moves onto each icon/row on hover.
local cfg = sfui.config
local addonName, addon  = ...
sfui                    = sfui or {}
sfui.portals            = {}

-- ========================
-- Localization (upvalue globals for faster access)
-- ========================
local math_floor        = math.floor
local str_format        = string.format
local CreateFrame       = _G.CreateFrame
local UIParent          = _G.UIParent
local C_Spell           = _G.C_Spell
local C_SpellBook       = _G.C_SpellBook
local C_Container       = _G.C_Container
local C_ToyBox          = _G.C_ToyBox
local C_Timer           = _G.C_Timer
local C_Item            = _G.C_Item
local GetProfessions    = _G.GetProfessions
local GetProfessionInfo = _G.GetProfessionInfo
local PlayerHasToy      = _G.PlayerHasToy
local GameTooltip       = _G.GameTooltip
local GetTime           = _G.GetTime
local tinsert           = _G.tinsert
local select            = _G.select
local unpack            = _G.unpack
local GetInstanceInfo   = _G.GetInstanceInfo
local C_ChallengeMode   = _G.C_ChallengeMode
local C_Secrets         = _G.C_Secrets
local C_MythicPlus      = _G.C_MythicPlus
local InCombatLockdown  = _G.InCombatLockdown
local UnitGUID          = _G.UnitGUID
local UnitName          = _G.UnitName
local UnitClass         = _G.UnitClass
local GetRealmName      = _G.GetRealmName
local issecretvalue     = _G.issecretvalue
local table_wipe        = _G.table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

local C_SpellBook_IsSpellKnownOrInSpellBook = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
local C_SpellBook_IsSpellInSpellBook        = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local C_SpellBook_IsSpellKnown             = C_SpellBook and C_SpellBook.IsSpellKnown
local IsPlayerSpell                        = _G.IsPlayerSpell
local C_Spell_IsSpellKnown                 = C_Spell and C_Spell.IsSpellKnown
local C_Spell_IsSpellKnownOrOverridesKnown = C_Spell and C_Spell.IsSpellKnownOrOverridesKnown
-- ========================
-- Shared Backdrop Tables
-- Reuse the same table to avoid per-call allocation.
-- ========================
local BACKDROP_ICON     = {
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
}
local BACKDROP_ROW      = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
}
local BACKDROP_MENU     = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}
-- ========================
-- Layout
-- ========================
local ICON_SIZE         = 48
local ICON_SPACING_X    = 4
local ICON_SPACING_Y    = 18 -- More padding for the text label
local ICONS_PER_ROW     = 4
local FRAME_WIDTH       = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING_X) + ICON_SPACING_X + 10 -- ~222

-- ========================
-- Shared overlay action button (Scotty's InsecureActionButtonTemplate pattern).
-- On hover, this button is moved on top of the icon/row and its attributes set.
-- The player clicks this button, which fires the spell/toy via Blizzard's input system.
-- This is the only reliable taint-free casting method from an addon frame.
-- ========================
local actionBtn         = CreateFrame("Button", "SfuiPortalsActionBtn", UIParent, "InsecureActionButtonTemplate")
if actionBtn.SetAttributeNoHandler then
    actionBtn:SetAttributeNoHandler("pressAndHoldAction", 1)
else
    actionBtn:SetAttribute("pressAndHoldAction", 1)
end
actionBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
actionBtn:SetPropagateMouseClicks(true)
actionBtn:SetPropagateMouseMotion(true)
actionBtn:SetFrameStrata("TOOLTIP")
actionBtn:Hide()

local currentlyClicking = false

local function set_attr(frame, name, val)
    if frame.SetAttributeNoHandler then
        frame:SetAttributeNoHandler(name, val)
    else
        frame:SetAttribute(name, val)
    end
end

-- ========================
-- Helpers
-- ========================
local portalFrame    = nil
local openLegacyMenu = nil -- track currently-open legacy dropdown menu

local function sort_portals_by_name(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
end

local is_engineer_cached = nil
local function is_engineer()
    if is_engineer_cached ~= nil then return is_engineer_cached end
    local prof1, prof2 = GetProfessions()
    local isEng = false
    if prof1 and select(7, GetProfessionInfo(prof1)) == 202 then
        isEng = true
    elseif prof2 and select(7, GetProfessionInfo(prof2)) == 202 then
        isEng = true
    end
    is_engineer_cached = isEng
    return isEng
end

local function player_has_spell(spellID)
    if not spellID then return false end
    if C_SpellBook_IsSpellKnownOrInSpellBook and C_SpellBook_IsSpellKnownOrInSpellBook(spellID) then
        return true
    end
    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end
    if C_SpellBook_IsSpellInSpellBook and C_SpellBook_IsSpellInSpellBook(spellID) then
        return true
    end
    if C_SpellBook_IsSpellKnown and C_SpellBook_IsSpellKnown(spellID, Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 1) then
        return true
    end
    if C_Spell_IsSpellKnown and C_Spell_IsSpellKnown(spellID) then
        return true
    end
    if C_Spell_IsSpellKnownOrOverridesKnown and C_Spell_IsSpellKnownOrOverridesKnown(spellID) then
        return true
    end
    return false
end

-- Engineering toy visibility: just check toybox ownership.
local function toy_is_accessible(toyID)
    return PlayerHasToy(toyID)
end

-- Travel toy filter: owned AND character can use it.
-- IsToyUsable: true = can use, false = cannot (e.g. missing unlock), nil = data loading.
-- We treat nil as usable (data hasn't cached yet; avoid hiding toys on first open).
local function toy_is_usable(toyID)
    if not toyID then return false end
    if not PlayerHasToy(toyID) then return false end
    if C_ToyBox and C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(toyID) == false then
        return false
    end
    return true
end

local lastRestrictedTime = -1
local lastRestrictedVal  = false

local function is_restricted_content()
    local now = GetTime()
    if now == lastRestrictedTime then
        return lastRestrictedVal
    end
    lastRestrictedTime = now

    if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
        lastRestrictedVal = C_Secrets.ShouldCooldownsBeSecret()
        return lastRestrictedVal
    end

    local _, instanceType = GetInstanceInfo()
    if instanceType == "pvp" or instanceType == "arena" then
        lastRestrictedVal = true
        return true
    end
    if C_MythicPlus and C_MythicPlus.IsMythicPlusActive and C_MythicPlus.IsMythicPlusActive() then
        lastRestrictedVal = true
        return true
    end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        lastRestrictedVal = true
        return true
    end
    lastRestrictedVal = false
    return false
end

local function spell_cd_remaining(spellID)
    if not spellID then return 0 end
    if is_restricted_content() then return 0 end

    -- 12.0.5+: LuaDurationObject API returns a plain number from GetRemainingDuration()
    -- that is never a secret value — sidesteps field-level taint completely.
    if C_Spell.GetSpellCooldownDuration then
        local durObj = C_Spell.GetSpellCooldownDuration(spellID, true) -- ignoreGCD = true
        if durObj and not durObj:IsZero() and not durObj:HasSecretValues() then
            return durObj:GetRemainingDuration()
        end
        return 0
    end

    -- Fallback: raw table API (pre-12.0.5)
    local start, dur = sfui.common.get_spell_cooldown(spellID)
    if start > 0 and dur > 1.5 then
        return start + dur - GetTime()
    end
    return 0
end

local function toy_cd_remaining(toyID)
    if is_restricted_content() then return 0 end

    local start, dur = C_Container.GetItemCooldown(toyID)
    if start and start > 0 and dur and dur > 0 then
        return start + dur - GetTime()
    end
    return 0
end


-- Scotty's BuildCooldownString logic
local function fmt_cd(secs)
    if secs <= 0 then return "" end
    if secs > 3600 then
        return str_format("%.1fh", secs / 3600)
    elseif secs > 60 then
        return str_format("%dm", secs / 60)
    else
        return str_format("%ds", secs)
    end
end

local function make_section_header(parent, text, yOffset)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", 5, yOffset)
    fs:SetText("|cff6600ff" .. text .. "|r")
    return fs
end

local function make_divider(parent, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(FRAME_WIDTH - 14, 1)
    line:SetPoint("TOPLEFT", 7, yOffset)
    line:SetColorTexture(unpack(cfg.colors.gray))
    return line
end

local currentHoverFrame = nil

-- arm_spell: left-click = spellID, right-click = portalID (optional, e.g. mage group portals)
local function arm_spell(spellID, portalID, frame)
    if InCombatLockdown() then return end
    currentHoverFrame = frame
    set_attr(actionBtn, "pressAndHoldAction", 1)
    set_attr(actionBtn, "type", "spell")
    set_attr(actionBtn, "typerelease", "spell")
    set_attr(actionBtn, "spell", spellID)
    set_attr(actionBtn, "type1", "spell")
    set_attr(actionBtn, "typerelease1", "spell")
    set_attr(actionBtn, "spell1", spellID)
    if portalID and player_has_spell(portalID) then
        set_attr(actionBtn, "type2", "spell")
        set_attr(actionBtn, "typerelease2", "spell")
        set_attr(actionBtn, "spell2", portalID)
    else
        set_attr(actionBtn, "type2", nil)
        set_attr(actionBtn, "typerelease2", nil)
        set_attr(actionBtn, "spell2", nil)
    end
    actionBtn:SetParent(frame)
    actionBtn:ClearAllPoints()
    actionBtn:SetAllPoints(frame)
    actionBtn:SetFrameStrata("TOOLTIP")
    actionBtn:Show()
end

local function arm_toy(toyID, frame)
    if InCombatLockdown() then return end
    currentHoverFrame = frame
    set_attr(actionBtn, "pressAndHoldAction", 1)
    set_attr(actionBtn, "type", "toy")
    set_attr(actionBtn, "typerelease", "toy")
    set_attr(actionBtn, "toy", toyID)
    set_attr(actionBtn, "type1", "toy")
    set_attr(actionBtn, "typerelease1", "toy")
    set_attr(actionBtn, "toy1", toyID)
    set_attr(actionBtn, "type2", nil)
    set_attr(actionBtn, "typerelease2", nil)
    set_attr(actionBtn, "spell2", nil)
    actionBtn:SetParent(frame)
    actionBtn:ClearAllPoints()
    actionBtn:SetAllPoints(frame)
    actionBtn:SetFrameStrata("TOOLTIP")
    actionBtn:Show()
end

local function disarm()
    if currentlyClicking then return end
    if currentHoverFrame and currentHoverFrame.resetHover then
        currentHoverFrame.resetHover()
    end
    currentHoverFrame = nil
    if not InCombatLockdown() then
        actionBtn:Hide()
        actionBtn:ClearAllPoints()
        actionBtn:SetParent(nil)
        set_attr(actionBtn, "type", nil)
        set_attr(actionBtn, "typerelease", nil)
        set_attr(actionBtn, "spell", nil)
        set_attr(actionBtn, "toy", nil)
        set_attr(actionBtn, "type1", nil)
        set_attr(actionBtn, "typerelease1", nil)
        set_attr(actionBtn, "spell1", nil)
        set_attr(actionBtn, "toy1", nil)
        set_attr(actionBtn, "type2", nil)
        set_attr(actionBtn, "typerelease2", nil)
        set_attr(actionBtn, "spell2", nil)
    end
end

local function get_spec_color(specID)
    if sfui.common and sfui.common.get_spec_color then
        return sfui.common.get_spec_color(specID)
    end
    return 0.0, 0.8, 1.0, 1
end

local _, playerClass = UnitClass("player")
local dungeonSpecCache = {}

local function get_dungeon_spec(dungeonName)
    if not dungeonName or not (SfuiDB and SfuiDB.lootspec) then return nil end
    local cached = dungeonSpecCache[dungeonName]
    if cached ~= nil then
        if cached == false then return nil end
        return cached.specID, cached.cmMapID
    end

    local db = SfuiDB.lootspec.classes and SfuiDB.lootspec.classes[playerClass]
    if not db or not db.dungeons then
        dungeonSpecCache[dungeonName] = false
        return nil
    end

    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
    if maps then
        local dLower = dungeonName:lower()
        for _, cmMapID in ipairs(maps) do
            local name = C_ChallengeMode.GetMapUIInfo(cmMapID)
            if name then
                local nLower = name:lower()
                if nLower == dLower or string.find(nLower, dLower, 1, true) or string.find(dLower, nLower, 1, true) then
                    local specID = db.dungeons[cmMapID]
                    if specID and specID ~= 0 then
                        dungeonSpecCache[dungeonName] = { specID = specID, cmMapID = cmMapID }
                        return specID, cmMapID
                    end
                end
            end
        end
    end
    dungeonSpecCache[dungeonName] = false
    return nil
end

local function show_tooltip(owner, spellID, toyID, label, portalID, cdRem)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if spellID then
        GameTooltip:SetSpellByID(spellID)
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444CD: " .. fmt_cd(cdRem) .. "|r")
        end
        if portalID and player_has_spell(portalID) then
            GameTooltip:AddLine("Right-click: group portal", 0.6, 0.6, 0.6)
        end
    elseif toyID then
        if GameTooltip.SetToyByItemID then
            GameTooltip:SetToyByItemID(toyID)
        else
            GameTooltip:SetItemByID(toyID)
        end
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444CD: " .. fmt_cd(cdRem) .. "|r")
        end
    end
    if label then
        GameTooltip:AddLine(label, 0.6, 0.6, 0.6)
        local specID = get_dungeon_spec(label)
        if specID and specID ~= 0 then
            local specName = sfui.common.get_spec_name(specID)
            local r, g, b = get_spec_color(specID)
            GameTooltip:AddDoubleLine("Loot Spec:", specName, 0.7, 0.7, 0.7, r, g, b)
        end
    end
    GameTooltip:Show()
end

local function hide_tooltip()
    if GameTooltip and GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
end

actionBtn:SetScript("PreClick", function(self, button)
    currentlyClicking = true
end)

-- Forward right-click to hovered frame if not using secondary spell
actionBtn:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and currentHoverFrame and currentHoverFrame.OnRightClick then
        if not self:GetAttribute("type2") then
            currentHoverFrame:OnRightClick()
        end
    end
end)

-- Close portal frame after a cast
actionBtn:SetScript("PostClick", function(self, button)
    local isCast = (button == "LeftButton") or (button == "RightButton" and self:GetAttribute("type2") == "spell")
    if isCast then
        _G.C_Timer.After(0.01, function()
            currentlyClicking = false
            disarm()
            hide_tooltip()
            if portalFrame then portalFrame:Hide() end
            if openLegacyMenu then
                openLegacyMenu:Hide()
                openLegacyMenu = nil
            end
        end)
    else
        currentlyClicking = false
    end
end)

-- Safety: always clear highlight when mouse leaves the overlay button
actionBtn:SetScript("OnLeave", function()
    if currentlyClicking then return end
    disarm()
    hide_tooltip()
end)

-- ========================
-- Widget: M+ portal icon (48x48)
-- ========================
local function make_spell_icon(parent, spellID, label, x, y)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetPoint("TOPLEFT", x, y)
    frame:EnableMouse(true)

    frame:SetBackdrop(BACKDROP_ICON)
    frame:SetBackdropBorderColor(unpack(cfg.colors.black))

    -- Spell icon
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local function update_icon()
        local iconID = sfui.common.get_spell_icon(spellID)
        if iconID then
            tex:SetTexture(iconID)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    update_icon()
    frame.tex = tex

    -- Native cooldown sweep
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)

    -- Unusable grey overlay
    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

    -- Configured Loot Spec badge in bottom-right corner (16x16)
    local specBadge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    specBadge:SetSize(16, 16)
    specBadge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    specBadge:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    specBadge:SetFrameLevel(frame:GetFrameLevel() + 5)
    local specIcon = specBadge:CreateTexture(nil, "ARTWORK")
    specIcon:SetAllPoints()
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    specBadge:Hide()
    frame.specBadge = specBadge

    local shortStr = sfui.common.get_short_string(label)
    if shortStr and shortStr ~= "" then
        local text = frame:CreateFontString(nil, "OVERLAY")
        local fontFile = _G.GameFontNormal:GetFont()
        text:SetFont(fontFile, 9, "OUTLINE")
        text:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        text:SetText(shortStr)
        text:SetTextColor(0.9, 0.9, 0.9)
    end

    local function refresh()
        if not tex:GetTexture() then
            update_icon()
        end
        local rem = spell_cd_remaining(spellID)
        local onCD = rem > 0
        if onCD then
            local startTime, duration = sfui.common.get_spell_cooldown(spellID)
            if startTime > 0 and duration > 0 and not (issecretvalue and (issecretvalue(startTime) or issecretvalue(duration))) then
                if frame._lastCDStart ~= startTime or frame._lastCDDur ~= duration then
                    frame._lastCDStart = startTime
                    frame._lastCDDur   = duration
                    cd:SetCooldown(startTime, duration)
                end
            else
                cd:Clear()
                frame._lastCDStart = nil
                frame._lastCDDur   = nil
            end
            if not frame._isOnCD then
                frame._isOnCD = true
                grey:Show()
                frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                cd:Clear()
                frame._lastCDStart = nil
                frame._lastCDDur   = nil
                grey:Hide()
                frame:SetBackdropBorderColor(unpack(cfg.colors.black))
            end
        end

        local specID = get_dungeon_spec(label)
        if specID ~= frame._lastSpecID then
            frame._lastSpecID = specID
            if specID and specID ~= 0 then
                local icon = sfui.common.get_spec_icon(specID)
                if icon then
                    specIcon:SetTexture(icon)
                    local r, g, b = get_spec_color(specID)
                    specBadge:SetBackdropBorderColor(r, g, b, 1)
                    specBadge:Show()
                else
                    specBadge:Hide()
                end
            else
                specBadge:Hide()
            end
        end
    end
    frame.refresh = refresh
    refresh()

    frame.resetHover = refresh -- direct ref, no wrapper closure

    frame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        arm_spell(spellID, nil, self) -- no portal for M+ icons
        local rem = spell_cd_remaining(spellID)
        show_tooltip(self, spellID, nil, label, nil, rem)
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if not actionBtn:IsShown() or actionBtn:GetParent() ~= self then
            refresh()
            disarm()
            hide_tooltip()
        end
    end)

    return frame
end

-- ========================
-- Widget: flat row button (wormholes, personal portals)
-- portalID: optional secondary spell for right-click (mage portals)
-- ========================
local function make_action_row(parent, spellID, portalID, toyID, name, icon, yPos)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH - 10, 22)
    frame:SetPoint("TOPLEFT", 5, yPos)
    frame:EnableMouse(true)
    frame:SetBackdrop(BACKDROP_ROW)
    frame:SetBackdropColor(unpack(cfg.colors.black))
    frame:SetBackdropBorderColor(unpack(cfg.colors.black))

    local ic = frame:CreateTexture(nil, "ARTWORK")
    ic:SetSize(14, 14)
    ic:SetPoint("LEFT", 4, 0)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 22, 0)
    label:SetPoint("RIGHT", -36, 0)
    label:SetJustifyH("LEFT")
    label:SetText(name)
    frame.label = label

    local function update_row_icon()
        local iconID = icon
        if not iconID and spellID then
            iconID = sfui.common.get_spell_icon(spellID)
        elseif not iconID and toyID then
            iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID)
        end
        if iconID then
            ic:SetTexture(iconID)
            ic:Show()
            label:SetPoint("LEFT", 22, 0)
        else
            ic:Hide()
            label:SetPoint("LEFT", 6, 0)
        end
    end
    update_row_icon()

    local cdLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdLabel:SetPoint("RIGHT", -4, 0)
    cdLabel:SetTextColor(1, 0.55, 0.1, 1)
    cdLabel:SetText("")

    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

    local function refresh()
        if not ic:GetTexture() then
            update_row_icon()
        end
        local rem = spellID and spell_cd_remaining(spellID) or toy_cd_remaining(toyID)
        local onCD = rem > 0
        if onCD then
            frame._isOnCD = true
            grey:Show()
            cdLabel:SetText("[" .. fmt_cd(rem) .. "]")
            label:SetTextColor(0.6, 0.6, 0.6, 1)
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                grey:Hide()
                cdLabel:SetText("")
                label:SetTextColor(unpack(cfg.colors.white))
            end
        end
    end
    frame.refresh = refresh
    refresh()

    frame.resetHover = refresh -- direct ref, no wrapper closure

    frame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        label:SetTextColor(unpack(cfg.colors.cyan))
        if spellID then arm_spell(spellID, portalID, self) end
        if toyID then arm_toy(toyID, self) end
        local rem = spellID and spell_cd_remaining(spellID) or toy_cd_remaining(toyID)
        show_tooltip(self, spellID, toyID, nil, portalID, rem)
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if not actionBtn:IsShown() or actionBtn:GetParent() ~= self then
            refresh()
            disarm()
            hide_tooltip()
        end
    end)

    return frame
end

-- ========================
-- Widget: travel toy icon (32x32 compact grid)
-- Same pattern as make_spell_icon but smaller: no spec badge, item CD sweep.
-- TOY_ICON_SIZE and TOY_ICONS_PER_ROW are local constants used only here and
-- in the build section below.
-- ========================
local TOY_ICON_SIZE     = 32
local TOY_ICON_SPACING  = 4
local TOY_ICONS_PER_ROW = 6
local TOY_X_OFFSET      = 5

local function make_toy_icon(parent, toyID, label, x, y)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(TOY_ICON_SIZE, TOY_ICON_SIZE)
    frame:SetPoint("TOPLEFT", x, y)
    frame:EnableMouse(true)
    frame:SetBackdrop(BACKDROP_ICON)
    frame:SetBackdropBorderColor(unpack(cfg.colors.black))

    -- Item icon
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local function update_icon()
        local iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID)
        if iconID then tex:SetTexture(iconID) end
    end
    update_icon()

    -- Native cooldown sweep (works with C_Container.GetItemCooldown below)
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)

    -- Greying overlay for when on cooldown
    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

    -- Short label below icon
    if label and label ~= "" then
        local fontFile = _G.GameFontNormal:GetFont()
        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontFile, 8, "OUTLINE")
        text:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        text:SetWidth(TOY_ICON_SIZE + 8)
        text:SetJustifyH("CENTER")
        text:SetText(label)
        text:SetTextColor(0.9, 0.9, 0.9)
    end

    local function refresh()
        if not tex:GetTexture() then update_icon() end
        local rem = toy_cd_remaining(toyID)
        local onCD = rem > 0
        if onCD then
            local start, dur = C_Container.GetItemCooldown(toyID)
            if start and start > 0 and dur and dur > 0 then
                if frame._lastStart ~= start or frame._lastDur ~= dur then
                    frame._lastStart = start
                    frame._lastDur   = dur
                    cd:SetCooldown(start, dur)
                end
            else
                cd:Clear()
                frame._lastStart = nil
                frame._lastDur   = nil
            end
            if not frame._isOnCD then
                frame._isOnCD = true
                grey:Show()
                frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                cd:Clear()
                frame._lastStart = nil
                frame._lastDur   = nil
                grey:Hide()
                frame:SetBackdropBorderColor(unpack(cfg.colors.black))
            end
        end
    end
    frame.refresh = refresh
    refresh()

    frame.resetHover = refresh

    frame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        arm_toy(toyID, self)
        local rem = toy_cd_remaining(toyID)
        show_tooltip(self, nil, toyID, nil, nil, rem)
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if not actionBtn:IsShown() or actionBtn:GetParent() ~= self then
            refresh()
            disarm()
            hide_tooltip()
        end
    end)

    return frame
end

-- ========================
-- Widget: scrollable cosmetic hearthstone icon
-- Displays your active hearthstone skin; scroll wheel cycles through
-- all collected hearthstone skins. Left-click uses the displayed toy.
-- Selection is saved per character in SfuiDB.hearthstone across reloads.
-- ========================
local cachedPlayerKey = nil
local function get_player_key()
    if cachedPlayerKey then return cachedPlayerKey end
    local guid = UnitGUID("player")
    if guid and guid ~= "" then
        cachedPlayerKey = guid
        return guid
    end
    local name = UnitName("player")
    local realm = GetRealmName()
    if name and realm and name ~= "" and realm ~= "" then
        cachedPlayerKey = name .. "-" .. realm
        return cachedPlayerKey
    end
    return "player"
end

local function make_hearthstone_scroll_icon(parent, skinList, x, y)
    -- skinList: array of toyIDs for collected cosmetic hearthstone skins.
    -- Falls back to base hearthstone (item 6948) via UseHearthstone() if empty.
    local charKey = get_player_key()
    local savedToyID = SfuiDB and SfuiDB.hearthstone and SfuiDB.hearthstone[charKey]
    local idx = 1
    if savedToyID then
        for i, id in ipairs(skinList) do
            if id == savedToyID then
                idx = i
                break
            end
        end
    end
    local function current() return skinList[idx] end

    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(TOY_ICON_SIZE, TOY_ICON_SIZE)
    frame:SetPoint("TOPLEFT", x, y)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetBackdrop(BACKDROP_ICON)
    frame:SetBackdropBorderColor(unpack(cfg.colors.black))

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)

    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

    -- Tiny scroll indicator dot in top-right corner (only shown when >1 skin)
    local dot = frame:CreateTexture(nil, "OVERLAY")
    dot:SetSize(4, 4)
    dot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    dot:SetColorTexture(0.6, 0.6, 1.0, 0.8)
    dot:SetDrawLayer("OVERLAY", 7)
    if #skinList <= 1 then dot:Hide() end

    local function update_display()
        local toyID = current()
        if toyID then
            local iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID)
            if iconID then tex:SetTexture(iconID) end
        else
            -- fallback: classic hearthstone icon
            tex:SetTexture(134414)
        end
    end
    update_display()

    local function refresh()
        local toyID = current()
        local rem = toyID and toy_cd_remaining(toyID) or 0
        local onCD = rem > 0
        if onCD then
            local start, dur = C_Container.GetItemCooldown(toyID)
            if start and start > 0 and dur and dur > 0 then
                if frame._lastStart ~= start or frame._lastDur ~= dur then
                    frame._lastStart = start
                    frame._lastDur   = dur
                    cd:SetCooldown(start, dur)
                end
            else
                cd:Clear()
                frame._lastStart = nil
                frame._lastDur   = nil
            end
            if not frame._isOnCD then
                frame._isOnCD = true
                grey:Show()
                frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                cd:Clear()
                frame._lastStart = nil
                frame._lastDur   = nil
                grey:Hide()
                frame:SetBackdropBorderColor(unpack(cfg.colors.black))
            end
        end
    end
    frame.refresh = refresh
    refresh()

    frame.resetHover = refresh

    frame:SetScript("OnMouseWheel", function(self, delta)
        if #skinList < 2 then return end
        idx = (idx - delta - 1) % #skinList + 1
        local toyID = current()
        if toyID and SfuiDB then
            SfuiDB.hearthstone = SfuiDB.hearthstone or {}
            SfuiDB.hearthstone[charKey] = toyID
        end
        update_display()
        refresh()
        disarm()
        -- Re-arm with newly selected toy if mouse is still over
        if toyID then
            arm_toy(toyID, self)
            local rem = toy_cd_remaining(toyID)
            show_tooltip(self, nil, toyID, nil, nil, rem)
            self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        end
    end)

    frame:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        local toyID = current()
        if toyID then
            arm_toy(toyID, self)
            local rem = toy_cd_remaining(toyID)
            show_tooltip(self, nil, toyID, nil, nil, rem)
        end
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if not actionBtn:IsShown() or actionBtn:GetParent() ~= self then
            refresh()
            disarm()
            hide_tooltip()
        end
    end)

    return frame
end

-- ========================
-- Widget: legacy portal dropdown (secure rows)
-- ========================
local function make_legacy_dropdown(parent, group, yPos)
    local menuWidth = FRAME_WIDTH - 10
    local opts = {}
    for _, e in ipairs(group.portals) do
        if player_has_spell(e.spell) then
            tinsert(opts, e)
        end
    end
    if #opts == 0 then return nil end

    table.sort(opts, sort_portals_by_name)

    -- Header
    local header = sfui.common.create_flat_button(parent, group.label, menuWidth, 20)
    header:SetPoint("TOPLEFT", 5, yPos)

    -- Menu (parented to UIParent so it floats above our frame)
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    parent.legacyMenus = parent.legacyMenus or {}
    tinsert(parent.legacyMenus, menu)
    menu.rows = {}
    menu:SetSize(menuWidth, 6 + #opts * 20)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop(BACKDROP_MENU)
    menu:SetBackdropColor(0, 0, 0, 0.92)
    menu:SetBackdropBorderColor(unpack(cfg.colors.gray))
    menu:Hide()
    menu:EnableMouse(true)

    local rowY = -4
    for _, opt in ipairs(opts) do
        local spellID = opt.spell
        local row = CreateFrame("Frame", nil, menu, "BackdropTemplate")
        row:SetSize(menuWidth - 8, 18)
        row:SetPoint("TOPLEFT", 4, rowY)
        row:EnableMouse(true)

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 4, 0)
        fs:SetPoint("RIGHT", -36, 0)
        fs:SetJustifyH("LEFT")
        fs:SetText(opt.name)

        local cdFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cdFs:SetPoint("RIGHT", -2, 0)
        cdFs:SetTextColor(1, 0.55, 0.1, 1)

        local function refresh_row()
            local rem = spell_cd_remaining(spellID)
            local onCD = rem > 0
            if onCD then
                row._isOnCD = true
                fs:SetTextColor(0.6, 0.6, 0.6, 1)
                cdFs:SetText("[" .. fmt_cd(rem) .. "]")
            else
                if row._isOnCD or row._isOnCD == nil then
                    row._isOnCD = false
                    fs:SetTextColor(unpack(cfg.colors.white))
                    cdFs:SetText("")
                end
            end
        end
        row.refresh = refresh_row
        refresh_row()

        row.resetHover = refresh_row

        row:SetScript("OnEnter", function(self)
            fs:SetTextColor(unpack(cfg.colors.cyan))
            arm_spell(spellID, nil, self) -- no portal for legacy dropdown rows
            local rem = spell_cd_remaining(spellID)
            show_tooltip(self, spellID, nil, nil, nil, rem)
        end)
        row:SetScript("OnLeave", function(self)
            if currentlyClicking then return end
            if not actionBtn:IsShown() or actionBtn:GetParent() ~= self then
                refresh_row()
                disarm()
                hide_tooltip()
            end
        end)

        tinsert(menu.rows, row)
        rowY = rowY - 20
    end

    -- Menus stay open until: header click, option click, or portal frame closed.
    -- No auto-close timer needed.
    header:SetScript("OnClick", function(self)
        if menu:IsShown() then
            menu:Hide()
            openLegacyMenu = nil
        else
            if openLegacyMenu then openLegacyMenu:Hide() end
            menu:ClearAllPoints()
            menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
            -- Refresh row states on open
            for _, row in ipairs(menu.rows) do
                if row.refresh then row.refresh() end
            end
            menu:Show()
            openLegacyMenu = menu
        end
    end)

    return header
end

-- ========================
-- Frame builder (lazy)
-- ========================
local function build_portals_frame()
    if portalFrame then return end
    local db = sfui.portals_db

    portalFrame = CreateFrame("Frame", "SfuiPortalsFrame", UIParent, "BackdropTemplate")
    portalFrame:SetFrameStrata("HIGH")
    portalFrame:SetClampedToScreen(true)
    portalFrame:SetMovable(true)
    portalFrame:EnableMouse(true)
    portalFrame:RegisterForDrag("LeftButton")
    portalFrame:SetScript("OnDragStart", portalFrame.StartMoving)
    portalFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, x, y = self:GetPoint()
        SfuiDB.portals_point = point
        SfuiDB.portals_relativePoint = relativePoint
        SfuiDB.portals_x = x
        SfuiDB.portals_y = y
    end)
    portalFrame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    portalFrame:SetBackdropColor(unpack(cfg.appearance.backdropColor))
    portalFrame:SetBackdropBorderColor(unpack(cfg.colors.black))
    tinsert(UISpecialFrames, "SfuiPortalsFrame")

    portalFrame.refreshable = {}

    local curY = -6

    -- ── M+ Current Season Portals (12.1 Midnight Season 2) ───────
    local seasonSpellMap = {}
    local seasonKnown = {}
    for _, e in ipairs(db.SEASON_PORTALS or {}) do
        if player_has_spell(e.spell) then
            tinsert(seasonKnown, e)
            seasonSpellMap[e.spell] = true
        end
    end
    table.sort(seasonKnown, sort_portals_by_name)

    if #seasonKnown > 0 then
        local col, row = 0, 0
        for _, e in ipairs(seasonKnown) do
            local x = ICON_SPACING_X + col * (ICON_SIZE + ICON_SPACING_X)
            local y = curY - row * (ICON_SIZE + ICON_SPACING_Y)
            local btn = make_spell_icon(portalFrame, e.spell, e.name, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= ICONS_PER_ROW then
                col = 0; row = row + 1
            end
        end
        local usedRows = math_floor((#seasonKnown - 1) / ICONS_PER_ROW) + 1
        curY = curY - usedRows * (ICON_SIZE + ICON_SPACING_Y) - 8
        make_divider(portalFrame, curY)
        curY = curY - 6
    end

    -- ── Midnight Expansion Portals ───────────────────────────────
    local midnightKnown = {}
    for _, e in ipairs(db.MIDNIGHT_PORTALS or {}) do
        if not seasonSpellMap[e.spell] and player_has_spell(e.spell) then
            tinsert(midnightKnown, e)
        end
    end
    table.sort(midnightKnown, sort_portals_by_name)

    if #midnightKnown > 0 then
        local col, row = 0, 0
        for _, e in ipairs(midnightKnown) do
            local x = ICON_SPACING_X + col * (ICON_SIZE + ICON_SPACING_X)
            local y = curY - row * (ICON_SIZE + ICON_SPACING_Y)
            local btn = make_spell_icon(portalFrame, e.spell, e.name, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= ICONS_PER_ROW then
                col = 0; row = row + 1
            end
        end
        local usedRows = math_floor((#midnightKnown - 1) / ICONS_PER_ROW) + 1
        curY = curY - usedRows * (ICON_SIZE + ICON_SPACING_Y) - 8
        make_divider(portalFrame, curY)
        curY = curY - 6
    end


    -- ── Travel Toys + Hearthstone Skins (compact icon grid) ───────
    -- Sits between the expansion portals above and personal/class portals below.
    -- Hearthstone skins: single scrollable icon cycling through all collected skins.
    -- Travel toys: compact icon grid, no text labels.
    do
        local playerFaction = _G.UnitFactionGroup and _G.UnitFactionGroup("player")
        local toyStartY = curY
        local col, row = 0, 0
        local toyCount = 0

        local function place_toy_icon(toyID)
            local x = TOY_X_OFFSET + col * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local y = toyStartY - row * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local btn = make_toy_icon(portalFrame, toyID, nil, x, y) -- nil = no label
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= TOY_ICONS_PER_ROW then col = 0; row = row + 1 end
            toyCount = toyCount + 1
        end

        -- 1. Hearthstone scroll icon (collected cosmetic skins only)
        local ownedSkins = {}
        for _, skinID in ipairs(db.COSMETIC_HEARTHSTONES or {}) do
            if toy_is_usable(skinID) then
                tinsert(ownedSkins, skinID)
            end
        end
        -- Always show a hearthstone slot: if no cosmetic skins, skip (the plain
        -- hearthstone is not a toy and has no icon to show from ToyBox).
        if #ownedSkins > 0 then
            local x = TOY_X_OFFSET + col * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local y = toyStartY - row * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local btn = make_hearthstone_scroll_icon(portalFrame, ownedSkins, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= TOY_ICONS_PER_ROW then col = 0; row = row + 1 end
            toyCount = toyCount + 1
        end

        -- 2. Travel toys
        for _, e in ipairs(db.TRAVEL_TOYS or {}) do
            local toyID = (e.altToy and playerFaction == "Alliance") and e.altToy or e.toy
            if toyID and toy_is_usable(toyID) then
                place_toy_icon(toyID)
            end
        end

        if toyCount > 0 then
            local usedRows = math_floor((toyCount - 1) / TOY_ICONS_PER_ROW) + 1
            curY = toyStartY - (usedRows - 1) * (TOY_ICON_SIZE + TOY_ICON_SPACING) - TOY_ICON_SIZE - 6
            make_divider(portalFrame, curY)
            curY = curY - 6
        end
    end

    -- ── Personal / Class Portals ─────────────────────────────────
    local personalKnown = {}
    for _, e in ipairs(db.PERSONAL_PORTALS or {}) do
        if player_has_spell(e.spell) then
            tinsert(personalKnown, e)
        end
    end
    table.sort(personalKnown, sort_portals_by_name)

    if #personalKnown > 0 then
        for _, e in ipairs(personalKnown) do
            local iconID = sfui.common.get_spell_icon(e.spell)
            -- Pass portal ID (e.portal) for right-click if defined
            local btn    = make_action_row(portalFrame, e.spell, e.portal, nil, e.name, iconID, curY)
            tinsert(portalFrame.refreshable, btn)
            curY = curY - 23
        end
        make_divider(portalFrame, curY - 2)
        curY = curY - 8
    end

    -- ── Engineering Wormholes ────────────────────────────────────
    local wormbolesKnown = {}
    if is_engineer() then
        for _, w in ipairs(db.WORMHOLE_TOYS or {}) do
            -- Show toy only if player has it AND can actually use it
            -- (toy_is_accessible hides skill-locked toys but keeps on-CD ones)
            if toy_is_accessible(w.toy) then
                tinsert(wormbolesKnown, w)
            end
        end
    end

    if #wormbolesKnown > 0 then
        for _, w in ipairs(wormbolesKnown) do
            local icon = C_Item.GetItemIconByID(w.toy)
            local displayName = w.name
                :gsub("Wormhole Generator: ", "")
                :gsub("Wormhole Centrifuge: ", "")
                :gsub("Wyrmhole Generator: ", "")
            local btn = make_action_row(portalFrame, nil, nil, w.toy, displayName, icon, curY)
            tinsert(portalFrame.refreshable, btn)
            curY = curY - 23
        end
        make_divider(portalFrame, curY - 2)
        curY = curY - 8
    end

    -- ── Legacy Portals (Dropdowns) ───────────────────────────────
    local hasLegacy = false
    for _, g in ipairs(db.LEGACY_GROUPS or {}) do
        for _, e in ipairs(g.portals) do
            if player_has_spell(e.spell) then
                hasLegacy = true; break
            end
        end
        if hasLegacy then break end
    end

    if hasLegacy then
        for _, g in ipairs(db.LEGACY_GROUPS or {}) do
            local h = make_legacy_dropdown(portalFrame, g, curY)
            if h then curY = curY - 24 end
        end
    end

    portalFrame:SetSize(FRAME_WIDTH, math.abs(curY) + 4)

    local refreshTicker = nil

    local function run_refresh_pass(self)
        if self.refreshable then
            for _, btn in ipairs(self.refreshable) do
                if btn.refresh then btn.refresh() end
            end
        end
        if openLegacyMenu and openLegacyMenu:IsShown() and openLegacyMenu.rows then
            for _, row in ipairs(openLegacyMenu.rows) do
                if row.refresh then row.refresh() end
            end
        end
    end

    -- Refresh states on every open and maintain 1-sec throttled ticker while visible
    portalFrame:SetScript("OnShow", function(self)
        run_refresh_pass(self)
        if not refreshTicker then
            refreshTicker = C_Timer.NewTicker(1.0, function()
                if not portalFrame or not portalFrame:IsShown() then return end
                run_refresh_pass(portalFrame)
            end)
        end
    end)

    -- Cancel ticker and close legacy dropdown when portal window is dismissed
    portalFrame:SetScript("OnHide", function()
        if refreshTicker then
            refreshTicker:Cancel()
            refreshTicker = nil
        end
        if openLegacyMenu then
            openLegacyMenu:Hide()
            openLegacyMenu = nil
        end
    end)
    portalFrame.cancelTicker = function()
        if refreshTicker then
            refreshTicker:Cancel()
            refreshTicker = nil
        end
    end

    portalFrame:ClearAllPoints()
    if SfuiDB.portals_point and SfuiDB.portals_x and SfuiDB.portals_y then
        portalFrame:SetPoint(SfuiDB.portals_point, UIParent, SfuiDB.portals_relativePoint or "CENTER", SfuiDB.portals_x, SfuiDB.portals_y)
    elseif SfuiDB.portals_x and SfuiDB.portals_y then
        -- Backwards compatibility with just x/y
        portalFrame:SetPoint("CENTER", UIParent, "CENTER", SfuiDB.portals_x, SfuiDB.portals_y)
    else
        portalFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    portalFrame:Hide()
end

-- ========================
-- Public API
-- ========================
function sfui.portals.Toggle()
    if InCombatLockdown() then return end
    if not portalFrame then build_portals_frame() end
    if portalFrame:IsShown() then
        portalFrame:Hide()
    else
        portalFrame:Show()
    end
end

local function portal_entry_matches(e, targetName, targetNameLower, identifier)
    if not e then return false end
    if identifier and (e.spell == identifier or (e.instance and e.instance == identifier)) then
        return true
    end
    if targetName and e.name then
        if e.name == targetName then return true end
        if targetNameLower then
            local eLower = e._nameLower
            if not eLower then
                eLower = e.name:lower()
                e._nameLower = eLower
            end
            if string.find(targetNameLower, eLower, 1, true) or string.find(eLower, targetNameLower, 1, true) then
                return true
            end
        end
    end
    return false
end

function sfui.portals.GetDungeonPortal(identifier)
    if not identifier then return nil, nil, false end
    local targetName = nil

    if type(identifier) == "number" then
        if identifier >= 1 and identifier <= 8 then
            local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()
            if maps and maps[identifier] then
                targetName = C_ChallengeMode.GetMapUIInfo(maps[identifier])
            end
        else
            targetName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(identifier)
        end
    elseif type(identifier) == "string" then
        targetName = identifier
    end

    local db = sfui.portals_db
    if not db then return nil, targetName, false end

    local targetNameLower = targetName and targetName:lower()

    -- 1. Check SEASON_PORTALS
    if db.SEASON_PORTALS then
        for _, e in ipairs(db.SEASON_PORTALS) do
            if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                return e.spell, e.name, player_has_spell(e.spell)
            end
        end
    end

    -- 2. Check MIDNIGHT_PORTALS
    if db.MIDNIGHT_PORTALS then
        for _, e in ipairs(db.MIDNIGHT_PORTALS) do
            if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                return e.spell, e.name, player_has_spell(e.spell)
            end
        end
    end

    -- 3. Check LEGACY_GROUPS
    if db.LEGACY_GROUPS then
        for _, g in ipairs(db.LEGACY_GROUPS) do
            for _, e in ipairs(g.portals or {}) do
                if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                    return e.spell, e.name, player_has_spell(e.spell)
                end
            end
        end
    end

    return nil, targetName, false
end

function sfui.portals.ArmDungeon(identifier, frame)
    local spellID, _, isKnown = sfui.portals.GetDungeonPortal(identifier)
    if spellID and isKnown and frame then
        arm_spell(spellID, nil, frame)
        return true, spellID
    end
    return false, nil
end

function sfui.portals.ArmSpell(spellID, frame, portalID)
    if spellID and frame then
        arm_spell(spellID, portalID, frame)
        return true
    end
    return false
end

function sfui.portals.Disarm()
    disarm()
end

function sfui.portals.RebuildBadges()
    table_wipe(dungeonSpecCache)
    if portalFrame and portalFrame:IsShown() and portalFrame.refreshable then
        for _, btn in ipairs(portalFrame.refreshable) do
            if btn.refresh then
                btn._lastSpecID = nil
                btn.refresh()
            end
        end
    end
end

local function invalidate_portals_frame()
    -- Nil out the cached frame so it fully rebuilds next open,
    -- picking up any newly learned spells or acquired toys.
    is_engineer_cached = nil
    table_wipe(dungeonSpecCache)
    if portalFrame then
        if portalFrame.cancelTicker then
            portalFrame.cancelTicker()
        end
        if portalFrame.legacyMenus then
            for _, m in ipairs(portalFrame.legacyMenus) do
                m:Hide()
                m:SetParent(nil)
            end
        end
        portalFrame:Hide()
        portalFrame:SetParent(nil)
        portalFrame = nil
    end
end

function sfui.portals.initialize()
    -- Rebuild the portals frame when the player's spells change
    -- (learns a new portal spell via training, quest reward, etc.)
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- Always rebuild on login/reload to reflect current character
        invalidate_portals_frame()
    end)
    sfui.events.RegisterEvent("SPELLS_CHANGED", function()
        -- Only invalidate if already built (avoids work before first open)
        if portalFrame then
            invalidate_portals_frame()
        end
    end)
    sfui.events.RegisterEvent("SKILL_LINES_CHANGED", function()
        is_engineer_cached = nil
        if portalFrame then
            invalidate_portals_frame()
        end
    end)
    sfui.events.RegisterEvent("TOYS_UPDATED", function()
        -- A toy was collected or removed; rebuild so the travel toys section reflects it.
        if portalFrame then
            invalidate_portals_frame()
        end
    end)
    sfui.events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
        currentlyClicking = false
        if portalFrame and portalFrame:IsShown() then
            portalFrame:Hide()
        end
        disarm()
        hide_tooltip()
    end)
end

function sfui.portals_debug_info()
    return {
        frameCreated = portalFrame ~= nil,
        frameShown = portalFrame and portalFrame:IsShown() or false,
    }
end
