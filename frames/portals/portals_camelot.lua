-- frames/portals/portals_camelot.lua
-- SFUI Camelot & Classic Era Mage Teleport & Portal Travel Hub
-- Dedicated travel hub with custom keybind, macro support, and reagent tracking.
-- Tracks Rune of Teleportation and Rune of Portals reagents, supports
-- left-click self-teleport and right-click group portal casting,
-- plus Hearthstone and Engineering gadgets.

-- Guard: Classic / Camelot only (Exclude Retail)
local isRetail = (sfui.version and sfui.version.retail) or (sfui.compat and not sfui.compat.is_classic)
if isRetail then return end

local addonName, addon  = ...
sfui                    = sfui or {}
sfui.portals            = sfui.portals or {}

local p                 = sfui.portals
local cfg               = sfui.config

-- Localization / API aliases
local CreateFrame       = _G.CreateFrame
local UIParent          = _G.UIParent
local UnitClass         = _G.UnitClass
local GetItemCount      = _G.GetItemCount
local GetBindLocation   = _G.GetBindLocation
local InCombatLockdown  = _G.InCombatLockdown
local tinsert           = _G.tinsert
local str_format        = string.format
local unpack            = _G.unpack

local FRAME_WIDTH       = p.FRAME_WIDTH

-- Reagent item IDs
local RUNE_TELEPORT     = 17031 -- Rune of Teleportation
local RUNE_PORTAL       = 17032 -- Rune of Portals

-- Classic / Camelot Mage Destinations
local MAGE_DESTINATIONS = {
    -- Alliance
    { spell = 3561,  portal = 10059, name = "Stormwind",     faction = "Alliance" },
    { spell = 3562,  portal = 11416, name = "Ironforge",     faction = "Alliance" },
    { spell = 3565,  portal = 11419, name = "Darnassus",     faction = "Alliance" },
    { spell = 49359, portal = 49360, name = "Theramore",     faction = "Alliance" },
    -- Horde
    { spell = 3567,  portal = 11417, name = "Orgrimmar",     faction = "Horde" },
    { spell = 3563,  portal = 11418, name = "Undercity",     faction = "Horde" },
    { spell = 3566,  portal = 11420, name = "Thunder Bluff", faction = "Horde" },
    { spell = 49358, portal = 49361, name = "Stonard",       faction = "Horde" },
}

-- Other class travel spells (Druid Moonglade, Shaman Astral Recall)
local CLASS_TRAVEL = {
    { spell = 18960, name = "Moonglade (Druid)", class = "DRUID" },
    { spell = 556,   name = "Astral Recall",     class = "SHAMAN" },
}

-- Classic Engineering teleporter items (in bags)
local ENGINEERING_ITEMS = {
    { item = 18986, name = "Gadgetzan (Ultrasafe)" },
    { item = 18984, name = "Everlook (Dimensional)" },
}

local function get_rune_counts()
    local tele = sfui.api.GetItemCount(RUNE_TELEPORT) or 0
    local port = sfui.api.GetItemCount(RUNE_PORTAL) or 0
    return tele, port
end

-- ========================
-- Frame builder (Camelot / Classic)
-- ========================
local function build_camelot_portals_frame()
    local _, playerClass = UnitClass("player")
    local isMage = (playerClass == "MAGE")

    local frame = p.create_base_frame("SfuiPortalsFrame")
    local curY = -6

    -- ── Section 1: Title & Reagents ─────────────────────────────
    local titleText = isMage and "mage teleports & portals" or "travel hub"
    local header = p.make_section_header(frame, titleText, curY)
    curY = curY - 16

    local runeFs = nil
    if isMage then
        runeFs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        runeFs:SetPoint("TOPLEFT", 6, curY)
        runeFs:SetJustifyH("LEFT")

        local function update_runes()
            local tele, port = get_rune_counts()
            local teleStr = (tele > 0) and ("|cff00ffff" .. tele .. " teleport|r") or "|cffff44440 teleport|r"
            local portStr = (port > 0) and ("|cff00ffff" .. port .. " portal|r") or "|cffff44440 portal|r"
            runeFs:SetText("runes: " .. teleStr .. " · " .. portStr)
        end
        update_runes()
        frame.updateRunes = update_runes
        curY = curY - 16
    end

    p.make_divider(frame, curY)
    curY = curY - 6

    -- ── Section 2: Mage Destinations ────────────────────────────
    local knownDests = {}
    for _, dest in ipairs(MAGE_DESTINATIONS) do
        if p.player_has_spell(dest.spell) or p.player_has_spell(dest.portal) then
            tinsert(knownDests, dest)
        end
    end
    table.sort(knownDests, function(a, b) return (a.name or "") < (b.name or "") end)

    if #knownDests > 0 then
        for _, dest in ipairs(knownDests) do
            local hasTele = p.player_has_spell(dest.spell)
            local hasPort = p.player_has_spell(dest.portal)
            local iconID = (hasTele and sfui.common.get_spell_icon(dest.spell))
                or (hasPort and sfui.common.get_spell_icon(dest.portal))
                or 135758

            local extraOpts = {
                tooltipLines = function()
                    local lines = {}
                    local tele, port = get_rune_counts()
                    if hasTele then
                        local col = (tele > 0) and "|cff00ff00" or "|cffff4444"
                        tinsert(lines, "left-click: teleport (self)")
                        tinsert(lines, { left = "  reagent: rune of teleportation", right = col .. tele .. " in bags|r" })
                    else
                        tinsert(lines, "|cff888888teleport: not yet learned|r")
                    end
                    if hasPort then
                        local col = (port > 0) and "|cff00ff00" or "|cffff4444"
                        tinsert(lines, "right-click: group portal")
                        tinsert(lines, { left = "  reagent: rune of portals", right = col .. port .. " in bags|r" })
                    else
                        tinsert(lines, "|cff888888group portal: not yet learned|r")
                    end
                    return lines
                end,
                onRefresh = function(btn)
                    local tele, _ = get_rune_counts()
                    if hasTele and tele == 0 and not btn._isOnCD then
                        btn:SetBackdropBorderColor(0.4, 0.2, 0.2, 1)
                    end
                end,
            }

            local row = p.make_action_row(
                frame,
                hasTele and dest.spell or nil,
                hasPort and dest.portal or nil,
                nil, -- toyID
                dest.name,
                iconID,
                curY,
                nil, -- itemID
                extraOpts
            )
            tinsert(frame.refreshable, row)
            curY = curY - 23
        end
        p.make_divider(frame, curY - 2)
        curY = curY - 8
    elseif isMage then
        local noSpellsFs = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        noSpellsFs:SetPoint("TOPLEFT", 8, curY)
        noSpellsFs:SetText("no teleport spells learned yet.\ntrain at a mage trainer (lvl 20+).")
        curY = curY - 30
        p.make_divider(frame, curY - 2)
        curY = curY - 8
    end

    -- ── Section 3: Class Travel (Druid Moonglade) ────────────────
    local knownClassTravel = {}
    for _, ct in ipairs(CLASS_TRAVEL) do
        if p.player_has_spell(ct.spell) then
            tinsert(knownClassTravel, ct)
        end
    end
    if #knownClassTravel > 0 then
        for _, ct in ipairs(knownClassTravel) do
            local iconID = sfui.common.get_spell_icon(ct.spell)
            local row = p.make_action_row(
                frame,
                ct.spell,
                nil,
                nil,
                ct.name,
                iconID,
                curY,
                nil,
                {
                    tooltipLines = { "left-click: cast class teleport" }
                }
            )
            tinsert(frame.refreshable, row)
            curY = curY - 23
        end
        p.make_divider(frame, curY - 2)
        curY = curY - 8
    end

    -- ── Section 4: Hearthstone (Item 6948) ────────────────────────
    local hasHearth = (sfui.api.GetItemCount(6948) or 0) > 0
    if hasHearth then
        local bindLocation = GetBindLocation and GetBindLocation()
        local hsLabel = (bindLocation and bindLocation ~= "") and ("Hearthstone (" .. bindLocation .. ")") or "Hearthstone"
        local hsIcon = (sfui.api.GetItemIcon and sfui.api.GetItemIcon(6948))
            or (sfui.api.GetItemIconByID and sfui.api.GetItemIconByID(6948))
            or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(6948))
            or (GetItemIcon and GetItemIcon(6948))
            or 134414

        local hsOpts = {
            tooltipLines = function()
                local loc = GetBindLocation and GetBindLocation()
                local lines = { "left-click: return to inn" }
                if loc and loc ~= "" then
                    tinsert(lines, { left = "inn:", right = "|cff00ffff" .. loc .. "|r" })
                end
                return lines
            end,
            onRefresh = function(btn)
                local loc = GetBindLocation and GetBindLocation()
                if loc and loc ~= "" and btn.label then
                    btn.label:SetText("Hearthstone (" .. loc .. ")")
                end
            end,
        }

        local hsRow = p.make_action_row(
            frame,
            nil, -- spellID
            nil, -- portalID
            nil, -- toyID
            hsLabel,
            hsIcon,
            curY,
            6948, -- itemID
            hsOpts
        )
        tinsert(frame.refreshable, hsRow)
        curY = curY - 23
        p.make_divider(frame, curY - 2)
        curY = curY - 8
    end

    -- ── Section 5: Engineering Gadgets in bags ───────────────────
    local knownEngItems = {}
    if p.is_engineer() then
        for _, eng in ipairs(ENGINEERING_ITEMS) do
            if (sfui.api.GetItemCount(eng.item) or 0) > 0 then
                tinsert(knownEngItems, eng)
            end
        end
    end

    if #knownEngItems > 0 then
        p.make_section_header(frame, "engineering", curY)
        curY = curY - 18
        for _, eng in ipairs(knownEngItems) do
            local icon = (sfui.api.GetItemIcon and sfui.api.GetItemIcon(eng.item))
                or (sfui.api.GetItemIconByID and sfui.api.GetItemIconByID(eng.item))
                or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(eng.item))
                or (GetItemIcon and GetItemIcon(eng.item))
                or 134400
            local row = p.make_action_row(
                frame,
                nil,
                nil,
                nil,
                eng.name,
                icon,
                curY,
                eng.item,
                {
                    tooltipLines = { "left-click: use teleporter gadget" }
                }
            )
            tinsert(frame.refreshable, row)
            curY = curY - 23
        end
        p.make_divider(frame, curY - 2)
        curY = curY - 8
    end

    if #frame.refreshable == 0 and not isMage then
        local emptyFs = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyFs:SetPoint("TOPLEFT", 8, curY - 2)
        emptyFs:SetText("no travel items or spells available.")
        curY = curY - 20
    end

    -- Finalize size
    local totalH = math.abs(curY) + 6
    if totalH < 70 then totalH = 70 end
    frame:SetSize(FRAME_WIDTH, totalH)

    frame.customRefresh = function(self)
        if self.updateRunes then
            self:updateRunes()
        end
    end

    p.setup_frame_scripts(frame)
    return frame
end
p.build_frame = build_camelot_portals_frame
