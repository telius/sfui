-- frames/portals/portals.lua
-- SFUI Portals Core Framework & Secure Casting Overlay
-- Shared infrastructure for both Retail and Camelot / Classic clients.
-- Clicking uses Scotty's InsecureActionButtonTemplate overlay pattern:
--   one shared action button moves onto each icon/row on hover.

local addonName, addon  = ...
sfui                    = sfui or {}
sfui.portals            = sfui.portals or {}

local cfg               = sfui.config

-- ========================
-- Localization (upvalue globals for faster access)
-- ========================
local str_format        = string.format
local CreateFrame       = _G.CreateFrame
local UIParent          = _G.UIParent
local C_Spell           = _G.C_Spell
local C_ToyBox          = _G.C_ToyBox
local C_Item            = _G.C_Item
local GetProfessions    = _G.GetProfessions
local GetProfessionInfo = _G.GetProfessionInfo
local PlayerHasToy      = _G.PlayerHasToy
local GameTooltip       = sfui.common.get_tooltip()
local GetTime           = _G.GetTime
local select            = _G.select
local unpack            = _G.unpack
local GetInstanceInfo   = _G.GetInstanceInfo
local C_ChallengeMode   = _G.C_ChallengeMode
local C_Secrets         = _G.C_Secrets
local C_MythicPlus      = _G.C_MythicPlus
local InCombatLockdown  = _G.InCombatLockdown
local issecretvalue = sfui.common.issecretvalue

-- ========================
-- Shared Backdrop Tables
-- ========================
local BACKDROP_ICON = {
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 0, right = 0, top = 0, bottom = 0 },
}
local BACKDROP_ROW  = sfui.widgets.FLAT_BACKDROP
local BACKDROP_MENU = sfui.widgets.FLAT_BACKDROP

sfui.portals.BACKDROP_ICON = BACKDROP_ICON
sfui.portals.BACKDROP_ROW  = BACKDROP_ROW
sfui.portals.BACKDROP_MENU = BACKDROP_MENU

-- ========================
-- Layout Constants
-- ========================
local ICON_SIZE         = 48
local ICON_SPACING_X    = 4
local ICON_SPACING_Y    = 18
local ICONS_PER_ROW     = 4
local FRAME_WIDTH       = ICONS_PER_ROW * (ICON_SIZE + ICON_SPACING_X) + ICON_SPACING_X + 10 -- ~222

local TOY_ICON_SIZE     = 32
local TOY_ICON_SPACING  = 4
local TOY_ICONS_PER_ROW = 6
local TOY_X_OFFSET      = 5

sfui.portals.ICON_SIZE         = ICON_SIZE
sfui.portals.ICON_SPACING_X    = ICON_SPACING_X
sfui.portals.ICON_SPACING_Y    = ICON_SPACING_Y
sfui.portals.ICONS_PER_ROW     = ICONS_PER_ROW
sfui.portals.FRAME_WIDTH       = FRAME_WIDTH
sfui.portals.TOY_ICON_SIZE     = TOY_ICON_SIZE
sfui.portals.TOY_ICON_SPACING  = TOY_ICON_SPACING
sfui.portals.TOY_ICONS_PER_ROW = TOY_ICONS_PER_ROW
sfui.portals.TOY_X_OFFSET      = TOY_X_OFFSET

local portalFrame = nil
local currentlyClicking = false
local currentHoverFrame = nil

-- ========================
-- Shared overlay action button (InsecureActionButtonTemplate pattern)
-- ========================
local actionBtn = CreateFrame("Button", "SfuiPortalsActionBtn", UIParent, "InsecureActionButtonTemplate")
actionBtn:RegisterForClicks("AnyDown", "AnyUp")
actionBtn:SetFrameStrata("TOOLTIP")
actionBtn:EnableMouseWheel(true)
actionBtn:SetScript("OnMouseWheel", function(self, delta)
    if currentHoverFrame and currentHoverFrame:GetScript("OnMouseWheel") then
        currentHoverFrame:GetScript("OnMouseWheel")(currentHoverFrame, delta)
    end
end)
actionBtn:Hide()

sfui.portals.actionBtn = actionBtn

local function set_attr(frame, name, val)
    if frame.SetAttributeNoHandler then
        frame:SetAttributeNoHandler(name, val)
    else
        frame:SetAttribute(name, val)
    end
end
sfui.portals.set_attr = set_attr

local function arm_action(kind, primary, portalID, frame)
    if InCombatLockdown() or not frame or not frame:IsVisible() then return end
    if portalFrame and not portalFrame:IsShown() then return end
    if currentHoverFrame and currentHoverFrame ~= frame and currentHoverFrame.resetHover then
        currentHoverFrame.resetHover()
    end
    currentHoverFrame = frame
    set_attr(actionBtn, "pressAndHoldAction", nil)
    set_attr(actionBtn, "typerelease", nil)
    set_attr(actionBtn, "typerelease1", nil)
    set_attr(actionBtn, "typerelease2", nil)
    if kind == "spell" then
        if primary then
            set_attr(actionBtn, "type", "spell")
            set_attr(actionBtn, "spell", primary)
            set_attr(actionBtn, "type1", "spell")
            set_attr(actionBtn, "spell1", primary)
        else
            set_attr(actionBtn, "type", nil)
            set_attr(actionBtn, "spell", nil)
            set_attr(actionBtn, "type1", nil)
            set_attr(actionBtn, "spell1", nil)
        end
        if portalID and sfui.portals.player_has_spell(portalID) then
            set_attr(actionBtn, "type2", "spell")
            set_attr(actionBtn, "spell2", portalID)
        else
            set_attr(actionBtn, "type2", nil)
            set_attr(actionBtn, "spell2", nil)
        end
        set_attr(actionBtn, "toy", nil)
        set_attr(actionBtn, "toy1", nil)
        set_attr(actionBtn, "item", nil)
        set_attr(actionBtn, "item1", nil)
    elseif kind == "toy" then
        set_attr(actionBtn, "type", "toy")
        set_attr(actionBtn, "toy", primary)
        set_attr(actionBtn, "type1", "toy")
        set_attr(actionBtn, "toy1", primary)
        set_attr(actionBtn, "type2", nil)
        set_attr(actionBtn, "toy2", nil)
        set_attr(actionBtn, "spell", nil)
        set_attr(actionBtn, "spell1", nil)
        set_attr(actionBtn, "spell2", nil)
        set_attr(actionBtn, "item", nil)
        set_attr(actionBtn, "item1", nil)
    elseif kind == "item" then
        local itemStr = "item:" .. primary
        set_attr(actionBtn, "type", "item")
        set_attr(actionBtn, "item", itemStr)
        set_attr(actionBtn, "type1", "item")
        set_attr(actionBtn, "item1", itemStr)
        set_attr(actionBtn, "type2", nil)
        set_attr(actionBtn, "item2", nil)
        set_attr(actionBtn, "spell", nil)
        set_attr(actionBtn, "spell1", nil)
        set_attr(actionBtn, "spell2", nil)
        set_attr(actionBtn, "toy", nil)
        set_attr(actionBtn, "toy1", nil)
    end
    actionBtn:ClearAllPoints()
    actionBtn:SetAllPoints(frame)
    actionBtn:SetFrameStrata("TOOLTIP")
    actionBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 15)
    actionBtn:Show()
end
local function arm_spell(spellID, portalID, frame)
    arm_action("spell", spellID, portalID, frame)
end
local function arm_toy(toyID, frame)
    arm_action("toy", toyID, nil, frame)
end
local function arm_item(itemID, frame)
    arm_action("item", itemID, nil, frame)
end
sfui.portals.arm_action = arm_action
sfui.portals.arm_spell  = arm_spell
sfui.portals.arm_toy    = arm_toy
sfui.portals.arm_item   = arm_item

local isDisarming = false
local function disarm()
    if currentlyClicking or isDisarming then return end
    isDisarming = true
    if currentHoverFrame and currentHoverFrame.resetHover then
        currentHoverFrame.resetHover()
    end
    currentHoverFrame = nil
    if not InCombatLockdown() then
        actionBtn:Hide()
        actionBtn:ClearAllPoints()
        set_attr(actionBtn, "type", nil)
        set_attr(actionBtn, "typerelease", nil)
        set_attr(actionBtn, "spell", nil)
        set_attr(actionBtn, "toy", nil)
        set_attr(actionBtn, "item", nil)
        set_attr(actionBtn, "type1", nil)
        set_attr(actionBtn, "typerelease1", nil)
        set_attr(actionBtn, "spell1", nil)
        set_attr(actionBtn, "toy1", nil)
        set_attr(actionBtn, "item1", nil)
        set_attr(actionBtn, "type2", nil)
        set_attr(actionBtn, "typerelease2", nil)
        set_attr(actionBtn, "spell2", nil)
        set_attr(actionBtn, "pressAndHoldAction", nil)
    end
    isDisarming = false
end
sfui.portals.disarm = disarm
sfui.portals.get_hover_frame = function() return currentHoverFrame end
sfui.portals.is_currently_clicking = function() return currentlyClicking end

-- ========================
-- Helpers
-- ========================

local function sort_portals_by_name(a, b)
    return (a.name or ""):lower() < (b.name or ""):lower()
end
sfui.portals.sort_portals_by_name = sort_portals_by_name

local is_engineer_cached = nil
local function is_engineer()
    if is_engineer_cached ~= nil then return is_engineer_cached end
    if GetProfessions then
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
    if _G.GetNumSkillLines then
        for i = 1, _G.GetNumSkillLines() do
            local name = _G.GetSkillLineInfo(i)
            if name and (name:lower() == "engineering" or name:lower() == "ingenieurskunst") then
                is_engineer_cached = true
                return true
            end
        end
    end
    is_engineer_cached = false
    return false
end
sfui.portals.is_engineer = is_engineer

local player_has_spell = sfui.common.is_spell_known
sfui.portals.player_has_spell = player_has_spell

local function toy_is_accessible(toyID)
    return PlayerHasToy(toyID)
end
sfui.portals.toy_is_accessible = toy_is_accessible

local function toy_is_usable(toyID)
    if not toyID then return false end
    if not PlayerHasToy(toyID) then return false end
    if C_ToyBox and C_ToyBox.IsToyUsable and C_ToyBox.IsToyUsable(toyID) == false then
        return false
    end
    return true
end
sfui.portals.toy_is_usable = toy_is_usable

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

    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local durObj = C_Spell.GetSpellCooldownDuration(spellID, true)
        if durObj and not durObj:IsZero() and not durObj:HasSecretValues() then
            return durObj:GetRemainingDuration()
        end
        return 0
    end

    local start, dur = sfui.common.get_spell_cooldown(spellID)
    if start > 0 and dur > 1.5 then
        return start + dur - GetTime()
    end
    return 0
end
sfui.portals.spell_cd_remaining = spell_cd_remaining

local function item_cd_remaining(itemID)
    if is_restricted_content() then return 0 end
    local start, dur = sfui.api.GetItemCooldown(itemID)
    if start and start > 0 and dur and dur > 0 then
        return start + dur - GetTime()
    end
    return 0
end
local toy_cd_remaining = item_cd_remaining
sfui.portals.item_cd_remaining = item_cd_remaining
sfui.portals.toy_cd_remaining  = toy_cd_remaining

local function fmt_cd(secs)
    return sfui.common.format_duration(secs, "cooldown_hm", "")
end
sfui.portals.fmt_cd = fmt_cd

local function track_dynamic(parent, obj)
    if parent and obj then
        parent._dynamicObjects = parent._dynamicObjects or {}
        parent._dynamicObjects[#parent._dynamicObjects + 1] = obj
    end
    return obj
end
sfui.portals.track_dynamic = track_dynamic

local function make_section_header(parent, text, yOffset)
    local host = (parent and parent.overlayFrame) or parent
    local fs = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
    fs:SetText("|cff6600ff" .. text .. "|r")
    return track_dynamic(parent, fs)
end
sfui.portals.make_section_header = make_section_header

local function make_divider(parent, yOffset, width)
    local host = (parent and parent.overlayFrame) or parent
    local line = host:CreateTexture(nil, "ARTWORK")
    line:SetSize(width or (FRAME_WIDTH - 14), 1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, yOffset)
    line:SetColorTexture(unpack(cfg.colors.gray))
    return track_dynamic(parent, line)
end
sfui.portals.make_divider = make_divider

local function set_cd_border(frame, rem)
    if rem > 0 then
        frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    else
        frame:SetBackdropBorderColor(unpack(cfg.colors.black))
    end
end
sfui.portals.set_cd_border = set_cd_border

local function set_cd_text(fs, rem)
    if rem > 0 then
        fs:SetTextColor(0.6, 0.6, 0.6, 1)
    else
        fs:SetTextColor(unpack(cfg.colors.white))
    end
end
sfui.portals.set_cd_text = set_cd_text

local function show_tooltip(owner, spellID, toyID, label, portalID, cdRem, extraLines, itemID)
    if not GameTooltip or not owner then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if spellID then
        GameTooltip:SetSpellByID(spellID)
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444cd: " .. fmt_cd(cdRem) .. "|r")
        end
        if portalID and sfui.portals.player_has_spell(portalID) then
            GameTooltip:AddLine("right-click: group portal", 0.6, 0.6, 0.6)
        end
    elseif portalID and sfui.portals.player_has_spell(portalID) then
        GameTooltip:SetSpellByID(portalID)
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444cd: " .. fmt_cd(cdRem) .. "|r")
        end
        GameTooltip:AddLine("right-click: group portal", 0.6, 0.6, 0.6)
    elseif toyID then
        if GameTooltip.SetToyByItemID then
            GameTooltip:SetToyByItemID(toyID)
        else
            GameTooltip:SetItemByID(toyID)
        end
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444cd: " .. fmt_cd(cdRem) .. "|r")
        end
    elseif itemID then
        GameTooltip:SetItemByID(itemID)
        if cdRem and cdRem > 0 then
            GameTooltip:AddLine("|cffff4444cd: " .. fmt_cd(cdRem) .. "|r")
        end
    end
    if label then
        GameTooltip:AddLine(label, 0.6, 0.6, 0.6)
        if sfui.portals.get_dungeon_spec then
            local specID = sfui.portals.get_dungeon_spec(label)
            if specID and specID ~= 0 then
                local specName = sfui.common.get_spec_name(specID)
                local r, g, b = sfui.common.get_spec_color(specID)
                GameTooltip:AddDoubleLine("loot spec:", specName, 0.7, 0.7, 0.7, r, g, b)
            end
        end
    end
    if extraLines then
        for _, line in ipairs(extraLines) do
            if type(line) == "table" then
                if line.right then
                    GameTooltip:AddDoubleLine(line.left or "", line.right, line.lr or 1, line.lg or 1, line.lb or 1, line.rr or 1, line.rg or 1, line.rb or 1)
                else
                    GameTooltip:AddLine(line.text or line[1], line.r or 1, line.g or 1, line.b or 1)
                end
            elseif type(line) == "string" then
                GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
            end
        end
    end
    GameTooltip:Show()
end
sfui.portals.show_tooltip = show_tooltip

local hide_tooltip = sfui.common.hide_tooltip
sfui.portals.hide_tooltip = hide_tooltip

-- Action button event scripts
actionBtn:SetScript("OnMouseDown", function(self, button)
    currentlyClicking = true
end)

actionBtn:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and currentHoverFrame and currentHoverFrame.OnRightClick then
        if not self:GetAttribute("type2") then
            currentHoverFrame:OnRightClick()
        end
    end
end)

actionBtn:SetScript("PostClick", function(self, button)
    local isCast = (button == "LeftButton") or (button == "RightButton" and self:GetAttribute("type2") == "spell")
    if isCast then
        _G.C_Timer.After(0.05, function()
            currentlyClicking = false
            disarm()
            hide_tooltip()
            if portalFrame then portalFrame:Hide() end
            if portalFrame and portalFrame.legacyMenus then
                for _, m in ipairs(portalFrame.legacyMenus) do
                    m:Hide()
                end
            end
        end)
    else
        currentlyClicking = false
    end
end)

actionBtn:SetScript("OnLeave", function(self)
    if currentlyClicking then return end
    if currentHoverFrame and currentHoverFrame:IsMouseOver() then
        return
    end
    disarm()
    hide_tooltip()
end)

-- ========================
-- Shared Widget: Icon Tile (M+ Spell, Travel Toy, Hearthstone Scroll)
-- ========================
local function make_icon_tile(parent, opts)
    local size = opts.size or ICON_SIZE
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("TOPLEFT", opts.x, opts.y)
    frame:EnableMouse(true)
    if opts.enableWheel then
        frame:EnableMouseWheel(true)
    end
    frame:SetBackdrop(BACKDROP_ICON)
    frame:SetBackdropBorderColor(unpack(cfg.colors.black))

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    if opts.cropOnCreate then
        sfui.common.set_square_icon_coords(tex)
    end
    frame.tex = tex

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)

    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

    local specBadge, specIcon
    if opts.withSpecBadge then
        specBadge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        specBadge:SetSize(16, 16)
        specBadge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
        specBadge:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        specBadge:SetFrameLevel(frame:GetFrameLevel() + 5)
        specIcon = specBadge:CreateTexture(nil, "ARTWORK")
        specIcon:SetAllPoints()
        sfui.common.set_square_icon_coords(specIcon)
        specBadge:Hide()
        frame.specBadge = specBadge
    end

    if opts.label and opts.label ~= "" then
        local fontFile = sfui.common.get_font_file()
        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFont(fontFile, opts.fontSize or 9, "OUTLINE")
        text:SetPoint("TOP", frame, "BOTTOM", 0, -2)
        if opts.wrapLabel then
            text:SetWidth(size + 8)
            text:SetJustifyH("CENTER")
        end
        text:SetText(opts.label)
        text:SetTextColor(0.9, 0.9, 0.9)
    end

    local function update_icon()
        if opts.updateIcon then
            opts.updateIcon(tex)
        end
    end
    update_icon()

    local function refresh()
        if not opts.skipEmptyTexCheck and not tex:GetTexture() then
            update_icon()
        end
        local rem = opts.getRemaining() or 0
        local onCD = rem > 0
        if onCD then
            local startTime, duration = opts.getCooldown()
            if startTime and startTime > 0 and duration and duration > 0
                and not (issecretvalue and (issecretvalue(startTime) or issecretvalue(duration))) then
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
                if not frame._isHovered then
                    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
            end
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                cd:Clear()
                frame._lastCDStart = nil
                frame._lastCDDur   = nil
                grey:Hide()
                if not frame._isHovered then
                    frame:SetBackdropBorderColor(unpack(cfg.colors.black))
                end
            end
        end

        if specBadge and opts.getSpecID then
            local specID = opts.getSpecID()
            if specID ~= frame._lastSpecID then
                frame._lastSpecID = specID
                if specID and specID ~= 0 then
                    local icon = sfui.common.get_spec_icon(specID)
                    if icon then
                        specIcon:SetTexture(icon)
                        local r, g, b = sfui.common.get_spec_color(specID)
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
    end
    frame.updateIcon = update_icon
    frame.refresh = refresh
    refresh()

    local function reset_hover()
        frame._isHovered = false
        set_cd_border(frame, opts.getRemaining() or 0)
    end
    frame.resetHover = reset_hover

    frame:SetScript("OnEnter", function(self)
        self._isHovered = true
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        opts.onEnterArm(self)
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if currentHoverFrame == self and actionBtn:IsShown() then
            return
        end
        reset_hover()
        disarm()
        hide_tooltip()
    end)

    return track_dynamic(parent, frame)
end
sfui.portals.make_icon_tile = make_icon_tile

local function make_spell_icon(parent, spellID, label, x, y)
    return make_icon_tile(parent, {
        size          = ICON_SIZE,
        x             = x,
        y             = y,
        label         = sfui.common.get_short_string(label),
        fontSize      = 9,
        withSpecBadge = true,
        updateIcon    = function(tex)
            local iconID = sfui.common.get_spell_icon(spellID)
            if iconID then
                tex:SetTexture(iconID)
                sfui.common.set_square_icon_coords(tex)
            end
        end,
        getRemaining  = function()
            return spell_cd_remaining(spellID)
        end,
        getCooldown   = function()
            return sfui.common.get_spell_cooldown(spellID)
        end,
        getSpecID     = function()
            return sfui.portals.get_dungeon_spec and sfui.portals.get_dungeon_spec(label)
        end,
        onEnterArm    = function(self)
            arm_spell(spellID, nil, self)
            show_tooltip(self, spellID, nil, label, nil, spell_cd_remaining(spellID))
        end,
    })
end
sfui.portals.make_spell_icon = make_spell_icon

-- ========================
-- Widget: flat row button (wormholes, personal portals, items)
-- ========================
local function make_action_row(parent, spellID, portalID, toyID, name, icon, yPos, itemID, extraOpts)
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
    sfui.common.set_square_icon_coords(ic)

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
            iconID = (sfui.api.GetItemIconByID and sfui.api.GetItemIconByID(toyID))
                or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID))
                or (GetItemIcon and GetItemIcon(toyID))
        elseif not iconID and itemID then
            iconID = (sfui.api.GetItemIcon and sfui.api.GetItemIcon(itemID))
                or (sfui.api.GetItemIconByID and sfui.api.GetItemIconByID(itemID))
                or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
                or (GetItemIcon and GetItemIcon(itemID))
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
    frame.cdLabel = cdLabel

    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()
    frame.grey = grey

    local function refresh()
        if not ic:GetTexture() then update_row_icon() end
        local rem = (spellID and spell_cd_remaining(spellID))
            or (toyID and toy_cd_remaining(toyID))
            or (itemID and item_cd_remaining(itemID))
            or 0
        local onCD = rem > 0
        if onCD then
            frame._isOnCD = true
            grey:Show()
            cdLabel:SetText("[" .. fmt_cd(rem) .. "]")
            if not frame._isHovered then
                label:SetTextColor(0.6, 0.6, 0.6, 1)
                frame:SetBackdropBorderColor(unpack(cfg.colors.black))
            end
        else
            frame._isOnCD = false
            grey:Hide()
            cdLabel:SetText("")
            if not frame._isHovered then
                label:SetTextColor(unpack(cfg.colors.white))
                frame:SetBackdropBorderColor(unpack(cfg.colors.black))
            end
        end
        if extraOpts and extraOpts.onRefresh then
            extraOpts.onRefresh(frame)
        end
    end
    frame.refresh = refresh
    refresh()

    local function reset_hover()
        frame._isHovered = false
        frame:SetBackdropBorderColor(unpack(cfg.colors.black))
        local rem = (spellID and spell_cd_remaining(spellID))
            or (toyID and toy_cd_remaining(toyID))
            or (itemID and item_cd_remaining(itemID))
            or 0
        set_cd_text(label, rem)
    end
    frame.resetHover = reset_hover

    frame:SetScript("OnEnter", function(self)
        self._isHovered = true
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        label:SetTextColor(unpack(cfg.colors.cyan))
        if spellID or portalID then arm_spell(spellID, portalID, self) end
        if toyID then arm_toy(toyID, self) end
        if itemID then arm_item(itemID, self) end
        local rem = (spellID and spell_cd_remaining(spellID))
            or (toyID and toy_cd_remaining(toyID))
            or (itemID and item_cd_remaining(itemID))
            or 0
        local extraLines = extraOpts and extraOpts.tooltipLines
        if type(extraLines) == "function" then extraLines = extraLines(self) end
        show_tooltip(self, spellID, toyID, nil, portalID, rem, extraLines, itemID)
    end)
    frame:SetScript("OnLeave", function(self)
        if currentlyClicking then return end
        if currentHoverFrame == self and actionBtn:IsShown() then
            return
        end
        reset_hover()
        disarm()
        hide_tooltip()
    end)

    return track_dynamic(parent, frame)
end
sfui.portals.make_action_row = make_action_row

-- ========================
-- Widget: travel toy icon (32x32 compact grid)
-- ========================
local function make_toy_icon(parent, toyID, label, x, y)
    return make_icon_tile(parent, {
        size         = TOY_ICON_SIZE,
        x            = x,
        y            = y,
        label        = label,
        fontSize     = 8,
        wrapLabel    = true,
        cropOnCreate = true,
        updateIcon   = function(tex)
            local iconID = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(toyID)
            if iconID then tex:SetTexture(iconID) end
        end,
        getRemaining = function()
            return item_cd_remaining(toyID)
        end,
        getCooldown  = function()
            return sfui.api.GetItemCooldown(toyID)
        end,
        onEnterArm   = function(self)
            arm_toy(toyID, self)
            show_tooltip(self, nil, toyID, nil, nil, item_cd_remaining(toyID))
        end,
    })
end
sfui.portals.make_toy_icon = make_toy_icon

-- ========================
-- Base Frame Construction & Scripts
-- ========================
local function create_base_frame(name)
    local frameName = name or "SfuiPortalsFrame"
    local f = _G[frameName]
    if not f then
        f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        f:SetFrameStrata("HIGH")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, x, y = self:GetPoint()
            SfuiDB.portals_point = point
            SfuiDB.portals_relativePoint = relativePoint
            SfuiDB.portals_x = x
            SfuiDB.portals_y = y
        end)
        f:SetBackdrop(sfui.widgets.FLAT_BACKDROP)
        f:SetBackdropColor(unpack(cfg.appearance.backdropColor))
        f:SetBackdropBorderColor(unpack(cfg.colors.black))

        if sfui.common and sfui.common.register_special_frame then
            sfui.common.register_special_frame(f)
        end

        local overlay = CreateFrame("Frame", nil, f)
        overlay:SetAllPoints(f)
        overlay:SetFrameLevel((f:GetFrameLevel() or 1) + 4)
        overlay:EnableMouse(false)
        f.overlayFrame = overlay
    end

    if f._dynamicObjects then
        for i = #f._dynamicObjects, 1, -1 do
            local obj = f._dynamicObjects[i]
            f._dynamicObjects[i] = nil
            if obj then
                if obj.Hide then obj:Hide() end
                if obj.ClearAllPoints then obj:ClearAllPoints() end
                if obj.SetParent then obj:SetParent(nil) end
            end
        end
    else
        f._dynamicObjects = {}
    end

    f.refreshable = {}
    f.legacyHeaders = nil
    f.legacyMenus = nil
    f.updateRunes = nil
    f.customRefresh = nil

    f:ClearAllPoints()
    if SfuiDB and SfuiDB.portals_point and SfuiDB.portals_x and SfuiDB.portals_y then
        f:SetPoint(SfuiDB.portals_point, UIParent, SfuiDB.portals_relativePoint or "CENTER", SfuiDB.portals_x, SfuiDB.portals_y)
    elseif SfuiDB and SfuiDB.portals_x and SfuiDB.portals_y then
        f:SetPoint("CENTER", UIParent, "CENTER", SfuiDB.portals_x, SfuiDB.portals_y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    if not f.isThemeRegistered and sfui.theme and sfui.theme.RegisterWindow then
        f.isThemeRegistered = true
        sfui.theme.RegisterWindow(f, function(frame, pal)
            if sfui.theme.ElevateWindowContents then
                sfui.theme.ElevateWindowContents(frame)
            end
        end, { cornerBrackets = true })
    end

    f:Hide()
    return f
end
sfui.portals.create_base_frame = create_base_frame

local function setup_frame_scripts(frame)
    local tickerActive = false
    local lastRefreshPass = 0

    local function run_refresh_pass(self, force)
        local now = GetTime()
        if not force and (now - lastRefreshPass) < 0.3 then
            return
        end
        lastRefreshPass = now

        if self.refreshable then
            for _, btn in ipairs(self.refreshable) do
                if btn.refresh then btn.refresh() end
            end
        end
        if self.legacyMenus then
            for _, m in ipairs(self.legacyMenus) do
                if m:IsShown() and m.rows then
                    for _, row in ipairs(m.rows) do
                        if row.refresh then row.refresh() end
                    end
                end
            end
        end
        if self.customRefresh then
            self:customRefresh()
        end
    end

    local function stop_ticker()
        if tickerActive then
            if sfui.events and sfui.events.UnregisterUpdate then
                sfui.events.UnregisterUpdate("SfuiPortalsRefresh")
            end
            tickerActive = false
        end
    end

    local function on_refresh_tick()
        if not frame or not frame:IsShown() then
            stop_ticker()
            return
        end
        run_refresh_pass(frame, true)
    end

    frame:SetScript("OnShow", function(self)
        if sfui.theme and sfui.theme.ApplyWindowStyle then
            sfui.theme.ApplyWindowStyle(self, { cornerBrackets = true })
            if sfui.theme.ElevateWindowContents then
                sfui.theme.ElevateWindowContents(self)
            end
        end
        run_refresh_pass(self)
        if not tickerActive and sfui.events and sfui.events.RegisterUpdate then
            tickerActive = true
            sfui.events.RegisterUpdate("SfuiPortalsRefresh", 1.0, on_refresh_tick)
        end
    end)

    frame:SetScript("OnHide", function()
        disarm()
        hide_tooltip()
        stop_ticker()
        if frame.legacyMenus then
            for _, m in ipairs(frame.legacyMenus) do
                m:Hide()
            end
        end
    end)

    frame.cancelTicker = stop_ticker
end
sfui.portals.setup_frame_scripts = setup_frame_scripts

local function invalidate_portals_frame()
    is_engineer_cached = nil
    if portalFrame then
        if portalFrame.cancelTicker then
            portalFrame.cancelTicker()
        end
        if portalFrame.legacyMenus then
            for _, m in ipairs(portalFrame.legacyMenus) do
                m:Hide()
            end
        end
        portalFrame:Hide()
        portalFrame._needsRebuild = true
    end
    if sfui.portals.on_invalidate then
        sfui.portals.on_invalidate()
    end
end
sfui.portals.invalidate_portals_frame = invalidate_portals_frame
sfui.portals.InvalidateFrame         = invalidate_portals_frame

-- ========================
-- Public API
-- ========================
local lastToggleTime = 0
local isToggling = false

function sfui.portals.Toggle()
    local now = GetTime()
    if (now - lastToggleTime) < 0.20 or isToggling then
        return
    end
    lastToggleTime = now
    isToggling = true

    if not portalFrame or portalFrame._needsRebuild then
        if sfui.portals.build_frame then
            portalFrame = sfui.portals.build_frame()
            if portalFrame then
                portalFrame._needsRebuild = nil
            end
        end
    end

    if not portalFrame then
        isToggling = false
        return
    end

    if portalFrame:IsShown() then
        portalFrame:Hide()
    else
        if InCombatLockdown() then
            isToggling = false
            return
        end
        portalFrame:Show()
    end
    isToggling = false
end

function sfui.portals.GetPortalFrame()
    return portalFrame
end

function sfui.portals.SetPortalFrame(f)
    portalFrame = f
end

function sfui.portals.ArmSpell(spellID, frame, portalID)
    if spellID and frame then
        arm_spell(spellID, portalID, frame)
        return true
    end
    return false
end

function sfui.portals.ArmItem(itemID, frame)
    if itemID and frame then
        arm_item(itemID, frame)
        return true
    end
    return false
end

function sfui.portals.Disarm()
    disarm()
end

-- Default fallback stubs (overridden by portals_standard when loaded on retail)
sfui.portals.GetDungeonPortal = sfui.portals.GetDungeonPortal or function() return nil, nil, false end
sfui.portals.ArmDungeon       = sfui.portals.ArmDungeon or function() return false, nil end
sfui.portals.RebuildBadges    = sfui.portals.RebuildBadges or function() end

function sfui.portals.initialize()
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        invalidate_portals_frame()
    end)
    sfui.events.RegisterEvent("SPELLS_CHANGED", function()
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
        if portalFrame then
            invalidate_portals_frame()
        end
    end)
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        if portalFrame and portalFrame:IsShown() then
            if portalFrame.refreshable then
                for _, btn in ipairs(portalFrame.refreshable) do
                    if btn.refresh then btn.refresh() end
                end
            end
            if portalFrame.customRefresh then
                portalFrame:customRefresh()
            end
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

local _portalsDebug = {}
function sfui.portals_debug_info()
    _portalsDebug.frameCreated = portalFrame ~= nil
    _portalsDebug.frameShown   = portalFrame and portalFrame:IsShown() or false
    return _portalsDebug
end

if sfui.RegisterModule then
    sfui.portals = sfui.portals or {}
    sfui.portals.OnEnable = function(self)
        if self.initialize then self.initialize() end
    end
    sfui.portals.GetDebugInfo = sfui.portals_debug_info
    sfui.RegisterModule("portals", sfui.portals)
end
