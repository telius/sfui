-- frames/portals/portals_standard.lua
-- SFUI Retail / Standard Portals Frame Builder
-- Midnight, Mythic+ seasonal portals, travel toys, hearthstone skins,
-- class travel, engineering wormholes, and legacy dropdown menus.
local isRetail = (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)
if not isRetail then return end

local addonName, addon  = ...
sfui                    = sfui or {}
sfui.portals            = sfui.portals or {}

local p                 = sfui.portals
local cfg               = sfui.config

-- Localization / API aliases
local math_floor        = math.floor
local str_format        = string.format
local CreateFrame       = _G.CreateFrame
local UIParent          = _G.UIParent
local C_Item            = _G.C_Item
local C_ChallengeMode   = _G.C_ChallengeMode
local InCombatLockdown  = _G.InCombatLockdown
local tinsert           = _G.tinsert
local unpack            = _G.unpack
local select            = _G.select
local table_wipe        = _G.table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

local ICON_SIZE         = p.ICON_SIZE
local ICON_SPACING_X    = p.ICON_SPACING_X
local ICON_SPACING_Y    = p.ICON_SPACING_Y
local ICONS_PER_ROW     = p.ICONS_PER_ROW
local FRAME_WIDTH       = p.FRAME_WIDTH
local TOY_ICON_SIZE     = p.TOY_ICON_SIZE
local TOY_ICON_SPACING  = p.TOY_ICON_SPACING
local TOY_ICONS_PER_ROW = p.TOY_ICONS_PER_ROW
local TOY_X_OFFSET      = p.TOY_X_OFFSET

local BACKDROP_ICON     = p.BACKDROP_ICON
local BACKDROP_ROW      = p.BACKDROP_ROW
local BACKDROP_MENU     = p.BACKDROP_MENU

local playerClass       = sfui.common.get_player_class()
local dungeonSpecCache  = {}
local openLegacyMenu    = nil

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
p.get_dungeon_spec = get_dungeon_spec

-- ========================
-- Widget: scrollable cosmetic hearthstone icon
-- Displays your active hearthstone skin; scroll wheel cycles through
-- all collected hearthstone skins. Left-click uses the displayed toy.
-- Selection is saved per character in SfuiDB.hearthstone across reloads.
-- ========================
local function get_player_key()
    return sfui.common.get_player_unique_key()
end

local function make_hearthstone_scroll_icon(parent, skinList, x, y)
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

    local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)

    local grey = frame:CreateTexture(nil, "OVERLAY")
    grey:SetAllPoints()
    grey:SetColorTexture(0, 0, 0, 0.5)
    grey:Hide()

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
            tex:SetTexture(134414)
        end
    end
    update_display()

    local function refresh()
        local toyID = current()
        local rem = toyID and p.toy_cd_remaining(toyID) or 0
        local onCD = rem > 0
        if onCD then
            local start, dur = sfui.api.GetItemCooldown(toyID)
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
                if not frame._isHovered then
                    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
            end
        else
            if frame._isOnCD or frame._isOnCD == nil then
                frame._isOnCD = false
                cd:Clear()
                frame._lastStart = nil
                frame._lastDur   = nil
                grey:Hide()
                if not frame._isHovered then
                    frame:SetBackdropBorderColor(unpack(cfg.colors.black))
                end
            end
        end
    end
    frame.refresh = refresh
    refresh()

    local function reset_hover()
        frame._isHovered = false
        local toyID = current()
        local rem = toyID and p.toy_cd_remaining(toyID) or 0
        p.set_cd_border(frame, rem)
    end
    frame.resetHover = reset_hover

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
        p.disarm()
        if toyID then
            p.arm_toy(toyID, self)
            local rem = p.toy_cd_remaining(toyID)
            p.show_tooltip(self, nil, toyID, nil, nil, rem)
            self._isHovered = true
            self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        end
    end)

    frame:SetScript("OnEnter", function(self)
        self._isHovered = true
        self:SetBackdropBorderColor(unpack(cfg.colors.cyan))
        local toyID = current()
        if toyID then
            p.arm_toy(toyID, self)
            local rem = p.toy_cd_remaining(toyID)
            p.show_tooltip(self, nil, toyID, nil, nil, rem)
        end
    end)
    frame:SetScript("OnLeave", function(self)
        if p.is_currently_clicking() then return end
        if not p.actionBtn:IsShown() or p.actionBtn:GetParent() ~= self then
            reset_hover()
            p.disarm()
            p.hide_tooltip()
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
        if p.player_has_spell(e.spell) then
            tinsert(opts, e)
        end
    end
    if #opts == 0 then return nil end

    table.sort(opts, p.sort_portals_by_name)

    local header = sfui.common.create_flat_button(parent, group.label, menuWidth, 20)
    header:SetPoint("TOPLEFT", 5, yPos)

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    parent.legacyMenus = parent.legacyMenus or {}
    tinsert(parent.legacyMenus, menu)
    menu.rows = {}
    menu:SetSize(menuWidth, 6 + #opts * 20)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop(BACKDROP_MENU)
    menu:SetBackdropColor(0, 0, 0, 0.92)
    menu:SetBackdropBorderColor(unpack(cfg.colors.black))
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

        local function reset_hover()
            row._isHovered = false
            local rem = p.spell_cd_remaining(spellID)
            p.set_cd_text(fs, rem)
        end
        row.resetHover = reset_hover

        local function refresh_row()
            local rem = p.spell_cd_remaining(spellID)
            local onCD = rem > 0
            if onCD then
                row._isOnCD = true
                cdFs:SetText("[" .. p.fmt_cd(rem) .. "]")
                if not row._isHovered then
                    fs:SetTextColor(0.6, 0.6, 0.6, 1)
                end
            else
                row._isOnCD = false
                cdFs:SetText("")
                if not row._isHovered then
                    fs:SetTextColor(unpack(cfg.colors.white))
                end
            end
        end
        row.refresh = refresh_row
        refresh_row()

        row:SetScript("OnEnter", function(self)
            self._isHovered = true
            fs:SetTextColor(unpack(cfg.colors.cyan))
            p.arm_spell(spellID, nil, self)
            local rem = p.spell_cd_remaining(spellID)
            p.show_tooltip(self, spellID, nil, nil, nil, rem)
        end)
        row:SetScript("OnLeave", function(self)
            if p.is_currently_clicking() then return end
            if not p.actionBtn:IsShown() or p.actionBtn:GetParent() ~= self then
                reset_hover()
                p.disarm()
                p.hide_tooltip()
            end
        end)

        tinsert(menu.rows, row)
        rowY = rowY - 20
    end

    header:SetScript("OnClick", function(self)
        if menu:IsShown() then
            menu:Hide()
            openLegacyMenu = nil
        else
            if openLegacyMenu then openLegacyMenu:Hide() end
            menu:ClearAllPoints()
            menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
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
-- Frame builder (standard / retail)
-- ========================
local function build_standard_portals_frame()
    local db = sfui.portals_db
    if not db then return nil end

    local portalFrame = p.create_base_frame("SfuiPortalsFrame")
    local curY = -6

    -- ── M+ Current Season Portals (12.1 Midnight Season 2) ───────
    local seasonSpellMap = {}
    local seasonKnown = {}
    for _, e in ipairs(db.SEASON_PORTALS or {}) do
        if p.player_has_spell(e.spell) then
            tinsert(seasonKnown, e)
            seasonSpellMap[e.spell] = true
        end
    end
    table.sort(seasonKnown, p.sort_portals_by_name)

    if #seasonKnown > 0 then
        local col, row = 0, 0
        for _, e in ipairs(seasonKnown) do
            local x = ICON_SPACING_X + col * (ICON_SIZE + ICON_SPACING_X)
            local y = curY - row * (ICON_SIZE + ICON_SPACING_Y)
            local btn = p.make_spell_icon(portalFrame, e.spell, e.name, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= ICONS_PER_ROW then
                col = 0; row = row + 1
            end
        end
        local usedRows = math_floor((#seasonKnown - 1) / ICONS_PER_ROW) + 1
        curY = curY - usedRows * (ICON_SIZE + ICON_SPACING_Y) - 8
        p.make_divider(portalFrame, curY)
        curY = curY - 6
    end

    -- ── Midnight Expansion Portals ───────────────────────────────
    local midnightKnown = {}
    for _, e in ipairs(db.MIDNIGHT_PORTALS or {}) do
        if not seasonSpellMap[e.spell] and p.player_has_spell(e.spell) then
            tinsert(midnightKnown, e)
        end
    end
    table.sort(midnightKnown, p.sort_portals_by_name)

    if #midnightKnown > 0 then
        local col, row = 0, 0
        for _, e in ipairs(midnightKnown) do
            local x = ICON_SPACING_X + col * (ICON_SIZE + ICON_SPACING_X)
            local y = curY - row * (ICON_SIZE + ICON_SPACING_Y)
            local btn = p.make_spell_icon(portalFrame, e.spell, e.name, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= ICONS_PER_ROW then
                col = 0; row = row + 1
            end
        end
        local usedRows = math_floor((#midnightKnown - 1) / ICONS_PER_ROW) + 1
        curY = curY - usedRows * (ICON_SIZE + ICON_SPACING_Y) - 8
        p.make_divider(portalFrame, curY)
        curY = curY - 6
    end

    -- ── Travel Toys + Hearthstone Skins (compact icon grid) ───────
    do
        local playerFaction = sfui.common.get_player_faction()
        local toyStartY = curY
        local col, row = 0, 0
        local toyCount = 0

        local function place_toy_icon(toyID)
            local x = TOY_X_OFFSET + col * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local y = toyStartY - row * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local btn = p.make_toy_icon(portalFrame, toyID, nil, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= TOY_ICONS_PER_ROW then col = 0; row = row + 1 end
            toyCount = toyCount + 1
        end

        local ownedSkins = {}
        for _, skinID in ipairs(db.COSMETIC_HEARTHSTONES or {}) do
            if p.toy_is_usable(skinID) then
                tinsert(ownedSkins, skinID)
            end
        end
        if #ownedSkins > 0 then
            local x = TOY_X_OFFSET + col * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local y = toyStartY - row * (TOY_ICON_SIZE + TOY_ICON_SPACING)
            local btn = make_hearthstone_scroll_icon(portalFrame, ownedSkins, x, y)
            tinsert(portalFrame.refreshable, btn)
            col = col + 1
            if col >= TOY_ICONS_PER_ROW then col = 0; row = row + 1 end
            toyCount = toyCount + 1
        end

        for _, e in ipairs(db.TRAVEL_TOYS or {}) do
            local toyID = (e.altToy and playerFaction == "Alliance") and e.altToy or e.toy
            if toyID and p.toy_is_usable(toyID) then
                place_toy_icon(toyID)
            end
        end

        if toyCount > 0 then
            local usedRows = math_floor((toyCount - 1) / TOY_ICONS_PER_ROW) + 1
            curY = toyStartY - (usedRows - 1) * (TOY_ICON_SIZE + TOY_ICON_SPACING) - TOY_ICON_SIZE - 6
            p.make_divider(portalFrame, curY)
            curY = curY - 6
        end
    end

    -- ── Personal / Class Portals ─────────────────────────────────
    local personalKnown = {}
    for _, e in ipairs(db.PERSONAL_PORTALS or {}) do
        if p.player_has_spell(e.spell) then
            tinsert(personalKnown, e)
        end
    end
    table.sort(personalKnown, p.sort_portals_by_name)

    if #personalKnown > 0 then
        for _, e in ipairs(personalKnown) do
            local iconID = sfui.common.get_spell_icon(e.spell)
            local btn    = p.make_action_row(portalFrame, e.spell, e.portal, nil, e.name, iconID, curY)
            tinsert(portalFrame.refreshable, btn)
            curY = curY - 23
        end
        p.make_divider(portalFrame, curY - 2)
        curY = curY - 8
    end

    -- ── Engineering Wormholes ────────────────────────────────────
    local wormholesKnown = {}
    if p.is_engineer() then
        for _, w in ipairs(db.WORMHOLE_TOYS or {}) do
            if p.toy_is_accessible(w.toy) then
                tinsert(wormholesKnown, w)
            end
        end
    end

    if #wormholesKnown > 0 then
        for _, w in ipairs(wormholesKnown) do
            local icon = C_Item.GetItemIconByID(w.toy)
            local displayName = w.name
                :gsub("Wormhole Generator: ", "")
                :gsub("Wormhole Centrifuge: ", "")
                :gsub("Wyrmhole Generator: ", "")
            local btn = p.make_action_row(portalFrame, nil, nil, w.toy, displayName, icon, curY)
            tinsert(portalFrame.refreshable, btn)
            curY = curY - 23
        end
        p.make_divider(portalFrame, curY - 2)
        curY = curY - 8
    end

    -- ── Legacy Portals (Dropdowns) ───────────────────────────────
    local hasLegacy = false
    for _, g in ipairs(db.LEGACY_GROUPS or {}) do
        for _, e in ipairs(g.portals) do
            if p.player_has_spell(e.spell) then
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
    p.setup_frame_scripts(portalFrame)
    return portalFrame
end
p.build_frame = build_standard_portals_frame

p.on_invalidate = function()
    table_wipe(dungeonSpecCache)
end

-- ========================
-- Public Retail Portal API
-- ========================
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

    if db.SEASON_PORTALS then
        for _, e in ipairs(db.SEASON_PORTALS) do
            if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                return e.spell, e.name, p.player_has_spell(e.spell)
            end
        end
    end

    if db.MIDNIGHT_PORTALS then
        for _, e in ipairs(db.MIDNIGHT_PORTALS) do
            if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                return e.spell, e.name, p.player_has_spell(e.spell)
            end
        end
    end

    if db.LEGACY_GROUPS then
        for _, g in ipairs(db.LEGACY_GROUPS) do
            for _, e in ipairs(g.portals or {}) do
                if portal_entry_matches(e, targetName, targetNameLower, identifier) then
                    return e.spell, e.name, p.player_has_spell(e.spell)
                end
            end
        end
    end

    return nil, targetName, false
end

function sfui.portals.ArmDungeon(identifier, frame)
    local spellID, _, isKnown = sfui.portals.GetDungeonPortal(identifier)
    if spellID and isKnown and frame then
        p.arm_spell(spellID, nil, frame)
        return true, spellID
    end
    return false, nil
end

function sfui.portals.RebuildBadges()
    table_wipe(dungeonSpecCache)
    local portalFrame = p.GetPortalFrame()
    if portalFrame and portalFrame:IsShown() and portalFrame.refreshable then
        for _, btn in ipairs(portalFrame.refreshable) do
            if btn.refresh then
                btn._lastSpecID = nil
                btn.refresh()
            end
        end
    end
end
