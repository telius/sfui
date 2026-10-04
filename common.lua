local addonName, addon = ...
sfui = sfui or {}
sfui.common = sfui.common or {}

function sfui.common.print(msg, ...)
    local prefix = (sfui.config and sfui.config.prefix) or "|cff6600ffsfui:|r"
    if msg == nil then
        print(prefix, ...)
        return
    end

    local text = tostring(msg)
    -- Defensively strip any repeated sfui: / [sfui] / color-wrapped sfui: prefixes
    local changed = true
    while changed do
        local prev = text
        -- Strip whole color-wrapped sfui prefix: e.g. |cff6600ffsfui:|r or |cff6600ffsfui|r: or |cff8888ff[SFUI]|r
        text = text:gsub("^%s*|c%x%x%x%x%x%x%x%x%[?[Ss][Ff][Uu][Ii]%]?%:?|r%:?%s*", "")
        -- Preserve error color wrapper: e.g. |cffff0000SFUI Error:|r -> |cffff0000Error:|r
        text = text:gsub("^(%s*|c%x%x%x%x%x%x%x%x)[Ss][Ff][Uu][Ii]%s+([Ee][Rr][Rr][Oo][Rr]:?)", "%1%2")
        -- Strip any partial color-wrapped sfui if left without closing |r
        text = text:gsub("^(%s*|c%x%x%x%x%x%x%x%x)%[?[Ss][Ff][Uu][Ii]%]?%:?%s*", "%1")

        -- Strip plain sfui: or [sfui] prefix
        text = text:gsub("^%s*%[?[Ss][Ff][Uu][Ii]%]?%:?%s*", "")
        changed = (text ~= prev)
    end

    if text == "" then
        print(prefix, ...)
    else
        print(prefix .. " " .. text, ...)
    end
end

function sfui.common.get_tooltip()
    return sfui.tooltip or _G.GameTooltip
end

function sfui.common.SyncTrackedSpells()
    -- No-op stub for backwards compatibility
end

function sfui.common.get_tracked_bar_db(id)
    if not id then return {} end
    return (SfuiDB and SfuiDB.trackedBars and SfuiDB.trackedBars[id]) or {}
end


-- ────────────────────────────────────────────────────────────────────────────
-- Domain Services Note:
-- Safety, Colors, Talents, and Items have been extracted to /core:
--   sfui/core/safety.lua  (sfui.safety  -> sfui.common)
--   sfui/core/colors.lua  (sfui.colors  -> sfui.common)
--   sfui/core/talents.lua (sfui.talents -> sfui.common)
--   sfui/core/items.lua   (sfui.items   -> sfui.common)
-- All public APIs remain accessible via sfui.common.* for backward compatibility.
-- ────────────────────────────────────────────────────────────────────────────

-- ────────────────────────────────────────────────────────────────────────────
-- Spell Engine (C_Spell Modernization & Normalization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Spell                         = _G.C_Spell or {}
local C_Spell_GetSpellInfo            = C_Spell.GetSpellInfo
local C_Spell_GetSpellName            = C_Spell.GetSpellName
local C_Spell_GetSpellTexture         = C_Spell.GetSpellTexture or _G.GetSpellTexture
local C_Spell_GetSpellCooldown        = C_Spell.GetSpellCooldown or _G.GetSpellCooldown
local C_Spell_GetSpellCooldownDuration = C_Spell.GetSpellCooldownDuration
local C_Spell_RequestLoadSpellData    = C_Spell.RequestLoadSpellData

-- Returns unified spell info table or nil
-- Compatible with both modern C_Spell.GetSpellInfo (table) and legacy _G.GetSpellInfo (multi-return)
function sfui.common.get_spell_info(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info then
            return {
                name     = info.name,
                icon     = info.iconID or info.originalIconID,
                castTime = info.castTime,
                minRange = info.minRange,
                maxRange = info.maxRange,
                spellID  = info.spellID or spellID,
            }
        end
    end
    if _G.GetSpellInfo then
        local name, _, icon, castTime, minRange, maxRange, id = _G.GetSpellInfo(spellID)
        if name then
            return {
                name     = name,
                icon     = icon,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID  = id or spellID,
            }
        end
    end
    return nil
end

-- Returns spell name string or nil
function sfui.common.get_spell_name(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellName then
        local name = C_Spell_GetSpellName(spellID)
        if name and name ~= "" then return name end
    end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info and info.name and info.name ~= "" then return info.name end
    end
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if name and name ~= "" then return name end
    end
    return nil
end

-- Returns spell icon texture (fileID/path) or nil
function sfui.common.get_spell_icon(spellID)
    if not spellID then return nil end
    if C_Spell_GetSpellTexture then
        local icon = C_Spell_GetSpellTexture(spellID)
        if icon then return icon end
    end
    if C_Spell_GetSpellInfo then
        local info = C_Spell_GetSpellInfo(spellID)
        if info and (info.iconID or info.originalIconID) then
            return info.iconID or info.originalIconID
        end
    end
    if _G.GetSpellTexture then
        local icon = _G.GetSpellTexture(spellID)
        if icon then return icon end
    end
    return nil
end

--- Checks if a spell is a known class buff/aura pattern or currently active on the player.
--- @param spellIDOrName number|string
--- @return boolean isAura, string|nil spellName
function sfui.common.is_known_aura_spell(spellIDOrName)
    if not spellIDOrName then return false end
    if type(spellIDOrName) == "number" and sfui.api and sfui.api.IsKnownAuraSpellID and sfui.api.IsKnownAuraSpellID(spellIDOrName) then
        return true, sfui.common.get_spell_name(spellIDOrName)
    end
    local name = type(spellIDOrName) == "string" and spellIDOrName or sfui.common.get_spell_name(spellIDOrName)
    if not name or name == "" then return false end

    if sfui.spells_db.MatchesAuraPattern(name) then
        return true, name
    end

    -- Dynamic check: is it already active on the player?
    local aura = sfui.api.GetUnitAuraByNameOrID("player", name)
    if aura then
        return true, name
    end

    return false, name
end


-- Returns normalized cooldown info: startTime, duration, isEnabled, modRate
function sfui.common.get_spell_cooldown(spellID)
    if not spellID then return 0, 0, false, 1 end
    if C_Spell_GetSpellCooldown then
        local cd = C_Spell_GetSpellCooldown(spellID)
        if cd then
            if type(cd) == "table" then
                return cd.startTime or 0, cd.duration or 0, cd.isEnabled ~= false, cd.modRate or 1
            else
                local start, dur, enabled, modRate = C_Spell_GetSpellCooldown(spellID)
                return start or 0, dur or 0, enabled ~= 0 and enabled ~= false, modRate or 1
            end
        end
    end
    if _G.GetSpellCooldown then
        local start, dur, enabled, modRate = _G.GetSpellCooldown(spellID)
        return start or 0, dur or 0, enabled ~= 0 and enabled ~= false, modRate or 1
    end
    return 0, 0, false, 1
end

-- Safely requests async spell data loading
function sfui.common.request_spell_load(spellID)
    if spellID and C_Spell_RequestLoadSpellData then
        C_Spell_RequestLoadSpellData(spellID)
    end
end

-- ────────────────────────────────────────────────────────────────────────────
-- Container & Bag Engine (C_Container Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Container                      = _G.C_Container or {}
local C_Container_GetContainerNumSlots = C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
local C_Container_GetContainerItemInfo = C_Container.GetContainerItemInfo or _G.GetContainerItemInfo
local C_Container_GetContainerItemLink = C_Container.GetContainerItemLink or _G.GetContainerItemLink
local C_Container_GetContainerItemID   = C_Container.GetContainerItemID or _G.GetContainerItemID

--- Iterates over the player's equipped bags and invokes callback for each item.
--- Stops iteration early if callback returns true.
--- @param callback fun(bag: number, slot: number, itemID: number|nil, itemLink: string|nil, itemInfo: table|nil): boolean|nil
--- @param includeReagent boolean|nil If true or nil, includes reagent bag (index 5)
--- @param skipEmpty boolean|nil If true or nil, only calls callback on non-empty slots
--- @param needInfo boolean|nil If false, avoids calling C_Container.GetContainerItemInfo (zero table allocations)
--- @return boolean Returns true if iteration was terminated early by callback
function sfui.common.for_each_bag_item(callback, includeReagent, skipEmpty, needInfo)
    if type(callback) ~= "function" then return false end
    if not C_Container_GetContainerNumSlots then return false end

    local maxBag = (includeReagent ~= false) and (_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) or (_G.NUM_BAG_SLOTS or 4)
    local shouldSkipEmpty = (skipEmpty ~= false)

    for bag = 0, maxBag do
        local numSlots = C_Container_GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            -- Fast path: Query numeric itemID first (zero table allocation)
            local itemID = C_Container_GetContainerItemID and C_Container_GetContainerItemID(bag, slot)
            local itemLink = nil
            local info = nil

            if itemID or not shouldSkipEmpty then
                itemLink = C_Container_GetContainerItemLink and C_Container_GetContainerItemLink(bag, slot)

                -- Only query heavy itemInfo table if caller needs it or didn't explicitly opt out
                if needInfo ~= false then
                    info = C_Container_GetContainerItemInfo and C_Container_GetContainerItemInfo(bag, slot)
                    if not itemID and info then
                        itemID = info.itemID or sfui.common.get_item_id(info.hyperlink)
                    end
                    if not itemLink and info then
                        itemLink = info.hyperlink
                    end
                end

                if not shouldSkipEmpty or itemID or itemLink or info then
                    if callback(bag, slot, itemID, itemLink, info) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ────────────────────────────────────────────────────────────────────────────
-- Map & Zone Engine (C_Map Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_Map                   = _G.C_Map or {}
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetMapInfo        = C_Map.GetMapInfo

--- Returns the player's current best uiMapID, or 0
--- @return number
function sfui.common.get_player_map_id()
    if C_Map_GetBestMapForUnit then
        return C_Map_GetBestMapForUnit("player") or 0
    end
    return 0
end

--- Returns map info table for the given uiMapID or nil
--- @param mapID number
--- @return table|nil
function sfui.common.get_map_info(mapID)
    if not mapID or mapID <= 0 then return nil end
    if C_Map_GetMapInfo then
        return C_Map_GetMapInfo(mapID)
    end
    return nil
end

--- Returns map info table for the player's current best map or nil
--- @return table|nil
function sfui.common.get_player_map_info()
    local mapID = sfui.common.get_player_map_id()
    return sfui.common.get_map_info(mapID)
end

--- Returns the localized name of the specified uiMapID or nil
--- @param mapID number
--- @return string|nil
function sfui.common.get_map_name(mapID)
    local info = sfui.common.get_map_info(mapID)
    return info and info.name or nil
end

--- Returns the localized name of the player's current zone/map or nil
--- @return string|nil
function sfui.common.get_player_map_name()
    local info = sfui.common.get_player_map_info()
    return info and info.name or nil
end

-- ────────────────────────────────────────────────────────────────────────────
-- Currency Engine (C_CurrencyInfo Modernization)
-- ────────────────────────────────────────────────────────────────────────────
local C_CurrencyInfo                 = _G.C_CurrencyInfo or {}
local C_CurrencyInfo_GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo or _G.GetCurrencyInfo

--- Returns currency info table or nil
--- @param currencyID number
--- @return table|nil
function sfui.common.get_currency_info(currencyID)
    if not currencyID then return nil end
    local cID = tonumber(currencyID)
    if not cID or cID <= 0 then return nil end
    if C_CurrencyInfo_GetCurrencyInfo then
        return C_CurrencyInfo_GetCurrencyInfo(cID)
    end
    return nil
end

--- Returns current quantity of the specified currency, or 0
--- Zero garbage allocation (no fallback table allocation).
--- @param currencyID number
--- @return number
function sfui.common.get_currency_quantity(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return (info and info.quantity) or 0
end

--- Returns localized name of the specified currency, or nil
--- @param currencyID number
--- @return string|nil
function sfui.common.get_currency_name(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return info and info.name or nil
end

--- Returns icon fileID/path for the specified currency, or nil
--- @param currencyID number
--- @return number|string|nil
function sfui.common.get_currency_icon(currencyID)
    local info = sfui.common.get_currency_info(currencyID)
    return info and (info.iconFileID or info.icon) or nil
end


-- ────────────────────────────────────────────────────────────────────────────
-- Cooldown Panels & Tracked Bars DB:
-- Extracted to sfui/frames/tracking/panels.lua (sfui.tracking -> sfui.common)
-- ────────────────────────────────────────────────────────────────────────────


local primaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.RunicPower,
    DEMONHUNTER = Enum.PowerType.Fury,
    DRUID = { [0] = Enum.PowerType.Mana, [1] = Enum.PowerType.Energy, [5] = Enum.PowerType.Rage, [27] = Enum.PowerType.Mana, [31] = Enum.PowerType.LunarPower, [35] = Enum.PowerType.LunarPower, [1484] = Enum.PowerType.Mana },
    EVOKER = Enum.PowerType.Mana,
    HUNTER = Enum.PowerType.Focus,
    MAGE = Enum.PowerType.Mana,
    MONK = { [0] = Enum.PowerType.Energy, [268] = Enum.PowerType.Energy, [269] = Enum.PowerType.Energy, [270] = Enum.PowerType.Mana },
    PALADIN = Enum.PowerType.Mana,
    PRIEST = { [0] = Enum.PowerType.Mana, [256] = Enum.PowerType.Mana, [257] = Enum.PowerType.Mana, [258] = Enum.PowerType.Insanity, [1487] = Enum.PowerType.Mana },
    ROGUE = Enum.PowerType.Energy,
    SHAMAN = { [0] = Enum.PowerType.Mana, [262] = Enum.PowerType.Maelstrom, [263] = Enum.PowerType.Mana, [264] = Enum.PowerType.Mana, [1489] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.Mana,
    WARRIOR = Enum.PowerType.Rage
}

local secondaryResourcesCache = {
    DEATHKNIGHT = Enum.PowerType.Runes,
    DEMONHUNTER = nil,
    DRUID = { [1] = Enum.PowerType.ComboPoints },
    EVOKER = Enum.PowerType.Essence,
    HUNTER = nil,
    MAGE = { [62] = Enum.PowerType.ArcaneCharges },
    MONK = { [268] = "STAGGER", [269] = Enum.PowerType.Chi, [270] = nil },
    PALADIN = Enum.PowerType.HolyPower,
    PRIEST = { [258] = Enum.PowerType.Mana },
    ROGUE = Enum.PowerType.ComboPoints,
    SHAMAN = { [262] = Enum.PowerType.Mana },
    WARLOCK = Enum.PowerType.SoulShards,
    WARRIOR = nil
}

-- ────────────────────────────────────────────────────────────────────────────
-- Central Out-of-Combat Action Queue
-- ────────────────────────────────────────────────────────────────────────────
local _oocQueue = {}
local _oocProcessing = false

--- Enqueue a callback to be executed when the player is out of combat lockdown.
--- If not currently in combat lockdown, the callback executes immediately.
--- Callbacks are executed inside pcall to prevent errors from breaking the queue.
--- @param callback function
function sfui.common.run_after_combat(callback)
    if type(callback) ~= "function" then return end
    if not InCombatLockdown() then
        local ok, err = pcall(callback)
        if not ok then
            print("|cff6600ffsfui|r run_after_combat error: " .. tostring(err))
        end
    else
        _oocQueue[#_oocQueue + 1] = callback
    end
end

local function flush_ooc_queue()
    if _oocProcessing or #_oocQueue == 0 then return end
    _oocProcessing = true
    local count = #_oocQueue
    for i = 1, count do
        local fn = _oocQueue[i]
        _oocQueue[i] = nil
        if fn then
            local ok, err = pcall(fn)
            if not ok then
                print("|cff6600ffsfui|r ooc callback error: " .. tostring(err))
            end
        end
    end
    -- Compact any items enqueued during callback execution
    local remaining = #_oocQueue
    if remaining > 0 then
        local writeIdx = 1
        for i = count + 1, remaining do
            _oocQueue[writeIdx] = _oocQueue[i]
            _oocQueue[i] = nil
            writeIdx = writeIdx + 1
        end
    end
    _oocProcessing = false
end

sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", flush_ooc_queue)

-- ------------------------------------------------------------
-- Central Vehicle and Dragonflying / Skyriding State Cache
-- ------------------------------------------------------------
local _dragonflyingCache = nil
local _getBonusIdx = C_ActionBar and C_ActionBar.GetBonusBarIndex or GetBonusBarIndex
local _getBonusOff = C_ActionBar and C_ActionBar.GetBonusBarOffset or GetBonusBarOffset

function sfui.common.invalidate_dragonflying_cache()
    _dragonflyingCache = nil
end

function sfui.common.is_dragonflying()
    if _dragonflyingCache ~= nil then return _dragonflyingCache end
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then
        _dragonflyingCache = false
        return false
    end
    local isFlying, canGlide = C_PlayerInfo.GetGlidingInfo()
    local hasSkyridingBar = _getBonusIdx and _getBonusOff and
        (_getBonusIdx() == 11 and _getBonusOff() == 5) or false
    _dragonflyingCache = (isFlying or (canGlide and hasSkyridingBar)) and true or false
    return _dragonflyingCache
end

function sfui.common.is_in_vehicle()
    if sfui.common.is_dragonflying() then return false end
    if UnitInVehicle("player") or UnitHasVehicleUI("player") then return true end
    if UnitExists("vehicle") and UnitVehicleSkin and UnitVehicleSkin("player") ~= nil then return true end
    if C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar() then return true end
    return false
end

local function on_glide_or_vehicle_event()
    sfui.common.invalidate_dragonflying_cache()
end

sfui.events.RegisterEvent("PLAYER_CAN_GLIDE_CHANGED",     on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_IS_GLIDING_CHANGED",    on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_SHAPESHIFT_FORM",       on_glide_or_vehicle_event)
sfui.events.RegisterUnitEvents({"UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE"}, "player", on_glide_or_vehicle_event)
sfui.events.RegisterEvent("VEHICLE_UPDATE",               on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_VEHICLE_ACTIONBAR",     on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR",    on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_POSSESS_BAR",           on_glide_or_vehicle_event)
sfui.events.RegisterEvent("UPDATE_BONUS_ACTIONBAR",       on_glide_or_vehicle_event)
sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD",        on_glide_or_vehicle_event)


function sfui.common.update_widget_bar(widget_frame, icons_pool, labels_pool, source_data, get_details_func)
    if not widget_frame then return end
    local cfg = sfui.config.widget_bar
    local last_icon = nil
    local i = 1
    for _, itemID in ipairs(source_data) do
        local details = get_details_func(itemID)
        if details then
            local icon = icons_pool[i]
            if not icon then
                icon = CreateFrame("Button", nil, widget_frame)
                icon:SetSize(cfg.icon_size, cfg.icon_size)
                local texture = icon:CreateTexture(nil, "ARTWORK")
                texture:SetAllPoints(icon)
                icon.texture = texture
                icon:SetScript("OnEnter", details.on_enter)
                icon:SetScript("OnLeave", details.on_leave)
                icon:SetScript("OnMouseUp", details.on_mouseup)
                icons_pool[i] = icon
            end
            local label = labels_pool[i]
            if not label then
                label = widget_frame:CreateFontString(nil, "OVERLAY", sfui.config.font_small)
                label:SetPoint("TOP", icon, "BOTTOM", 0, cfg.label_offset_y)
                label:SetTextColor(cfg.label_color[1], cfg.label_color[2], cfg.label_color[3])
                labels_pool[i] = label
            end
            icon.id = itemID
            icon.texture:SetTexture(details.texture or sfui.config.textures.gold_icon)
            label:SetText(details.quantity)
            if i == 1 then
                icon:SetPoint("TOPLEFT", cfg.spacing or 5, -(cfg.spacing or 5))
            elseif last_icon then
                icon:SetPoint("TOPLEFT", last_icon, "TOPRIGHT", cfg.icon_spacing, 0)
            end
            icon:Show()
            label:Show()
            last_icon = icon
            i = i + 1
        end
    end
    for j = i, #icons_pool do icons_pool[j]:Hide() end
    for j = i, #labels_pool do labels_pool[j]:Hide() end
    if last_icon and not InCombatLockdown() then
        local left = widget_frame:GetLeft()
        if left then
            widget_frame:SetWidth(last_icon:GetRight() - left + (cfg.spacing or 5))
        end
        if CharacterFrame:IsShown() then widget_frame:Show() end
    else
        widget_frame:Hide()
    end
end

function sfui.common.get_primary_resource()
    local pClass = sfui.common.get_player_class()
    if not pClass then return nil end

    local isClassic = (sfui.compat and (sfui.compat.has.wow_forever or sfui.compat.is_classic_era or sfui.compat.is_classic))
        or (sfui.version and (sfui.version.classic_era or sfui.version.wow_forever or not sfui.version.retail))

    if isClassic then
        if pClass == "HUNTER" then
            return Enum.PowerType.Mana or 0
        end
        if UnitPowerType then
            local uType = UnitPowerType("player")
            if uType ~= nil then
                return uType
            end
        end
    end

    if pClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
        local druidCache = primaryResourcesCache[pClass]
        local res = druidCache and druidCache[form]
        if res ~= nil then return res end
        if UnitPowerType then
            return UnitPowerType("player")
        end
        return Enum.PowerType.Mana or 0
    end

    local cache = primaryResourcesCache[pClass]
    local res
    if type(cache) == "table" then
        local specID = sfui.common.get_current_spec_id()
        res = cache[specID]
        if res == nil and cache[0] ~= nil then
            res = cache[0]
        end
    else
        res = cache
    end

    if res == nil and UnitPowerType then
        res = UnitPowerType("player")
    end

    return res or Enum.PowerType.Mana or 0
end

function sfui.common.get_secondary_resource()
    local pClass = sfui.common.get_player_class()
    if not pClass then return nil end

    local isClassic = sfui.isClassic

    if isClassic and pClass ~= "ROGUE" and pClass ~= "DRUID" then
        sfui.bars.bar1_in_use = false
        return nil
    end

    local res
    if pClass == "DRUID" then
        local form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
        local druidCache = secondaryResourcesCache[pClass]
        res = druidCache and druidCache[form]
    else
        local cache = secondaryResourcesCache[pClass]
        if type(cache) == "table" then
            local specID = sfui.common.get_current_spec_id()
            res = cache[specID]
        else
            res = cache
        end
    end

    sfui.bars.bar1_in_use = (res ~= nil)
    return res
end

-- ────────────────────────────────────────────────────────────────────────────
-- UI Widgets & Styling Note:
-- Factory methods (create_bar, create_panel, create_border, create_button,
-- create_flat_button, create_slider_input, create_checkbox, set_color,
-- create_font_string, etc.) are located in sfui/core/widgets.lua and
-- sfui/core/colors.lua and bound to sfui.common.*.
-- ────────────────────────────────────────────────────────────────────────────

function sfui.common.is_item_known(itemLink)
    if not itemLink then return false end

    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if data and data.lines then
        for _, line in ipairs(data.lines) do
            local text = line.leftText
            if text then
                if text == ITEM_SPELL_KNOWN or text == "Already known" then
                    return true
                end
                if string.find(text, "You've collected this appearance") then
                    return true
                end
            end
        end
    end

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    if itemID then
        local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(itemID)
        if sourceID then
            local categoryID, visualID, canEnchant, icon, isCollected = C_TransmogCollection.GetAppearanceSourceInfo(
                sourceID)
            if isCollected then
                return true
            end
        end

        if C_ToyBox and C_ToyBox.GetToyInfo then
            local toyID = C_ToyBox.GetToyInfo(itemID)
            if toyID and PlayerHasToy(itemID) then return true end
        end
    end

    return false
end

function sfui.common.shorten_name(name, length)
    if not name or type(name) ~= "string" then return "" end
    length = length or 25
    if string.len(name) <= length then return name end
    return string.sub(name, 1, length - 3) .. "..."
end

-- Shared Masque group for all sfui buttons
function sfui.common.get_masque_group()
    -- Check global setting
    local enabled = sfui.config.icon_panel_global_defaults.enableMasque
    if SfuiDB and SfuiDB.iconGlobalSettings and SfuiDB.iconGlobalSettings.enableMasque ~= nil then
        enabled = SfuiDB.iconGlobalSettings.enableMasque
    end

    if not enabled then
        return nil
    end

    local Masque = LibStub and LibStub("Masque", true)
    if not Masque then return nil end
    local group = Masque:Group("sfui")
    if group and not group._sfui_init then
        -- Set "Dream" as the preferred default skin with safety checks
        if group.Skin then
            group:Skin("Dream")
        elseif group.SetSkin then
            group:SetSkin("Dream")
        end
        group._sfui_init = true
    end
    return group
end

-- Centralized Helper to Sync Frame with Masque State
function sfui.common.sync_masque(frame, subElements)
    if not frame then return end
    if InCombatLockdown() then return end
    local Masque = LibStub and LibStub("Masque", true)
    if not Masque then return end
    local group = Masque:Group("sfui")
    if not group then return end

    local enabled = sfui.config.icon_panel_global_defaults.enableMasque
    if SfuiDB and SfuiDB.iconGlobalSettings and SfuiDB.iconGlobalSettings.enableMasque ~= nil then
        enabled = SfuiDB.iconGlobalSettings.enableMasque
    end

    if enabled then
        if not frame._isMasqued then
            group:AddButton(frame, subElements)
            frame._isMasqued = true
        end
    else
        if frame._isMasqued then
            group:RemoveButton(frame)
            frame._isMasqued = false
        end
    end
end

-- ========================
-- Item Utilities
-- ========================


-- Checks if a decor item grants House XP (e.g. uncollected first-time bonus)
function sfui.common.decor_grants_xp(link)
    if not link then return false end
    local itemID = sfui.common.get_item_id_from_link(link)
    if not itemID then return false end

    if C_HousingCatalog and C_HousingCatalog.GetCatalogEntryInfoByItem then
        local ok, info = pcall(C_HousingCatalog.GetCatalogEntryInfoByItem, itemID)
        if ok and info then
            if info.firstAcquisitionBonus and info.firstAcquisitionBonus > 0 then
                return true, info.firstAcquisitionBonus
            end
            return false
        end
    end

    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and data and data.lines then
            for i = 1, #data.lines do
                local line = data.lines[i]
                local text = line and (line.leftText or (line.args and line.args[2] and line.args[2].stringVal))
                if text and (text:find("House XP", 1, true) or text:find("First%-Time Collection Bonus", 1, true)) then
                    return true
                end
            end
        end
    end
    return false
end

-- Checks if the player is currently in a Player Housing zone (Razorwind Shores, Founder's Point, houses, plots, neighborhoods)
function sfui.common.is_housing_zone()
    -- 1. Official C_Housing APIs (Patch 12.0+)
    if C_Housing then
        if C_Housing.IsOnNeighborhoodMap and C_Housing.IsOnNeighborhoodMap() then return true end
        if C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then return true end
        if C_Housing.IsInsideHouse and C_Housing.IsInsideHouse() then return true end
        if C_Housing.IsInsidePlot and C_Housing.IsInsidePlot() then return true end
        if C_Housing.GetCurrentNeighborhoodGUID and C_Housing.GetCurrentNeighborhoodGUID() then return true end
    end
    if C_HousingNeighborhood and C_HousingNeighborhood.GetNeighborhoodMapData then
        local ok, data = pcall(C_HousingNeighborhood.GetNeighborhoodMapData)
        if ok and data and #data > 0 then return true end
    end

    -- 2. Instance Info Name check (Razorwind Shores, Founder's Point, etc.)
    if _G.GetInstanceInfo then
        local instName = _G.GetInstanceInfo()
        if instName and instName ~= "" then
            local lower = instName:lower()
            if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
                return true
            end
        end
    end

    -- 3. Area and Subzone text checks
    local zone = (_G.GetRealZoneText and _G.GetRealZoneText()) or (_G.GetZoneText and _G.GetZoneText()) or ""
    if zone ~= "" then
        local lower = zone:lower()
        if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
            return true
        end
    end

    local subzone = (_G.GetSubZoneText and _G.GetSubZoneText()) or (_G.GetMinimapZoneText and _G.GetMinimapZoneText()) or ""
    if subzone ~= "" then
        local lower = subzone:lower()
        if lower:find("razorwind") or lower:find("founder") then
            return true
        end
    end

    -- 4. Map Name check via C_Map
    local mapName = sfui.common.get_player_map_name()
    if mapName then
        local lower = mapName:lower()
        if lower:find("razorwind") or lower:find("founder") or lower:find("housing") or lower:find("neighborhood") then
            return true
        end
    end

    return false
end


-- ========================
-- Utility Helpers
-- ========================



function sfui.initialize_database()
    if type(SfuiDB) ~= "table" then SfuiDB = {} end
    SfuiDB.iconGlobalSettings = SfuiDB.iconGlobalSettings or {}
    local igs = SfuiDB.iconGlobalSettings
    local g = sfui.config.icon_panel_global_defaults
    if igs.enableMasque == nil then igs.enableMasque = g.enableMasque end
    if igs.readyGlow == nil then igs.readyGlow = g.readyGlow end
    if igs.glowType == nil then igs.glowType = g.glowType or "pixel" end

    local activeThemeID = (sfui.theme and sfui.theme.GetActiveThemeID and sfui.theme.GetActiveThemeID()) or "modern"
    local activeTheme = sfui.theme and sfui.theme.GetTheme and sfui.theme.GetTheme(activeThemeID)
    local defaultBarTexture = (activeTheme and (activeTheme.barTexture or (activeTheme.bars and activeTheme.bars.texture)))
        or (activeThemeID == "camelot" and "Blizzard Nameplate")
        or "Flat"

    if type(SfuiDB.barTexture) ~= "string" or SfuiDB.barTexture == "" then
        SfuiDB.barTexture = defaultBarTexture
    elseif activeThemeID == "camelot" and SfuiDB.barTexture == "Flat" and not SfuiDB._barTextureCustomized then
        -- Automatically swap Camelot to Blizzard Nameplate if still using the legacy default "Flat"
        SfuiDB.barTexture = "Blizzard Nameplate"
    end
    sfui.config.barTexture = sfui.widgets.get_bar_texture()
    SfuiDB.absorbBarColor = SfuiDB.absorbBarColor or sfui.config.absorbBarColor

    SfuiDB.minimap_icon = SfuiDB.minimap_icon or { hide = false }
    SfuiDB.minimap_collect_buttons = (SfuiDB.minimap_collect_buttons == nil) and true or SfuiDB.minimap_collect_buttons
    if SfuiDB.minimap_rearrange == nil then SfuiDB.minimap_rearrange = true end
    SfuiDB.minimap_buttons_mouseover = (SfuiDB.minimap_buttons_mouseover == nil) and false or
        SfuiDB.minimap_buttons_mouseover
    if SfuiDB.minimap_show_status == nil then SfuiDB.minimap_show_status = true end
    if SfuiDB.minimap_masque == nil then SfuiDB.minimap_masque = true end
    if SfuiDB.minimap_auto_zoom == nil then SfuiDB.minimap_auto_zoom = true end
    if SfuiDB.minimap_auto_zoom_delay == nil then SfuiDB.minimap_auto_zoom_delay = 5 end
    if SfuiDB.minimap_button_x == nil then SfuiDB.minimap_button_x = sfui.config.minimap.button_bar.defaultX end
    if SfuiDB.minimap_button_y == nil then SfuiDB.minimap_button_y = sfui.config.minimap.button_bar.defaultY end
    if SfuiDB.autoSellGreys == nil then SfuiDB.autoSellGreys = true end
    if SfuiDB.autoRepair == nil then SfuiDB.autoRepair = true end
    if SfuiDB.autoRankUp == nil then SfuiDB.autoRankUp = true end
    if SfuiDB.repairThreshold == nil then SfuiDB.repairThreshold = 90 end
    if SfuiDB.enableMasterHammer == nil then SfuiDB.enableMasterHammer = true end
    if SfuiDB.enableMerchant == nil then SfuiDB.enableMerchant = true end
    if SfuiDB.repairIconColor == nil then SfuiDB.repairIconColor = sfui.config.masterHammer.defaultColor end
    if SfuiDB.enableCursorRing == nil then SfuiDB.enableCursorRing = true end
    if SfuiDB.cursorRingScale == nil then SfuiDB.cursorRingScale = 1.0 end
    if SfuiDB.useSpecColor == nil then SfuiDB.useSpecColor = true end
    if SfuiDB.specColorFallback == nil then SfuiDB.specColorFallback = { 1, 1, 1, 1 } end

    -- Bar settings
    if SfuiDB.healthBarX == nil then SfuiDB.healthBarX = 0 end
    if SfuiDB.healthBarY == nil then SfuiDB.healthBarY = 300 end
    if SfuiDB.enableHealthBar == nil then SfuiDB.enableHealthBar = true end
    if SfuiDB.enablePowerBar == nil then SfuiDB.enablePowerBar = true end
    if SfuiDB.enableSecondaryPowerBar == nil then SfuiDB.enableSecondaryPowerBar = true end
    if SfuiDB.enableVigorBar == nil then SfuiDB.enableVigorBar = true end
    if SfuiDB.enableMountSpeedBar == nil then SfuiDB.enableMountSpeedBar = true end
    if SfuiDB.enableSwingBars == nil then SfuiDB.enableSwingBars = true end

    -- Castbar settings
    if SfuiDB.castBarEnabled == nil then SfuiDB.castBarEnabled = sfui.config.castBar.enabled end
    if SfuiDB.castBarX == nil then SfuiDB.castBarX = sfui.config.castBar.pos.x end
    if SfuiDB.castBarY == nil then SfuiDB.castBarY = sfui.config.castBar.pos.y end
    sfui.config.castBar.enabled = SfuiDB.castBarEnabled
    sfui.config.castBar.pos.x = SfuiDB.castBarX
    sfui.config.castBar.pos.y = SfuiDB.castBarY

    if SfuiDB.targetCastBarEnabled == nil then SfuiDB.targetCastBarEnabled = sfui.config.targetCastBar.enabled end
    if SfuiDB.targetCastBarX == nil then SfuiDB.targetCastBarX = sfui.config.targetCastBar.pos.x end
    if SfuiDB.targetCastBarY == nil then SfuiDB.targetCastBarY = sfui.config.targetCastBar.pos.y end
    sfui.config.targetCastBar.enabled = SfuiDB.targetCastBarEnabled
    sfui.config.targetCastBar.pos.x = SfuiDB.targetCastBarX
    sfui.config.targetCastBar.pos.y = SfuiDB.targetCastBarY

    -- automation settings
    if SfuiDB.auto_role_check == nil then SfuiDB.auto_role_check = true end
    if SfuiDB.auto_sign_lfg == nil then SfuiDB.auto_sign_lfg = true end
    if SfuiDB.autoDungeonPortalPopup == nil then SfuiDB.autoDungeonPortalPopup = true end
    if SfuiDB.portalPopupOnlyWhenFull == nil then SfuiDB.portalPopupOnlyWhenFull = true end

    -- Tracked Bars
    SfuiDB.trackedBars = SfuiDB.trackedBars or {}
    if SfuiDB.trackedBarsX == nil then SfuiDB.trackedBarsX = -300 end
    if SfuiDB.trackedBarsY == nil then SfuiDB.trackedBarsY = 300 end
end

-- Robust player key generator resilient to realmless architectures and first+last names
local _cached_player_key = nil
function sfui.common.get_player_unique_key()
    if _cached_player_key then return _cached_player_key end

    local guid = _G.UnitGUID and _G.UnitGUID("player")
    if guid and guid ~= "" then
        _cached_player_key = guid
        return guid
    end

    local name = _G.UnitName and _G.UnitName("player")
    local getRealm = _G.GetNormalizedRealmName or _G.GetRealmName
    local realm = getRealm and getRealm()
    if (not realm or realm == "") and _G.GetCVar then
        realm = _G.GetCVar("realmName")
    end
    if not realm or realm == "" then
        realm = "Global"
    end

    if name and name ~= "" and name ~= "Unknown Entity" and name ~= "Unknown" then
        local safeName = name:gsub("%s+", "_")
        local key = safeName .. "-" .. realm
        _cached_player_key = key
        return key
    end

    return "player"
end

function sfui.common.get_player_display_name()
    local name = _G.UnitName and _G.UnitName("player")
    return (name and name ~= "" and name ~= "Unknown Entity") and name or "Unknown"
end

-- Helper to systematically hide specific Blizzard CooldownViewer frames
local cooldownViewersInitialized = false

function sfui.common.hide_blizzard_cooldown_viewers()
    -- Ensure the addon is loaded first
    if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
        C_AddOns.LoadAddOn("Blizzard_CooldownViewer")
    end

    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffBarCooldownViewer",
    }

    -- Ensure BuffIconCooldownViewer (Blizzard Tracked Buffs stack) remains visible and interactive
    local buffViewer = _G["BuffIconCooldownViewer"]
    if buffViewer then
        buffViewer:SetAlpha(1)
        buffViewer:EnableMouse(true)
    end

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer then
            viewer:SetAlpha(0)
            viewer:EnableMouse(false)
        end
    end

    if not cooldownViewersInitialized then
        cooldownViewersInitialized = true

        -- Cinematic and cutscene frame OnHide hooks
        if _G.CinematicFrame then
            _G.CinematicFrame:HookScript("OnHide", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end
        if _G.MovieFrame then
            _G.MovieFrame:HookScript("OnHide", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end

        -- Blizzard EventRegistry callbacks (strictly non-panel events)
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("CinematicFrame.CinematicStopped", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
            EventRegistry:RegisterCallback("EditMode.Exit", function()
                sfui.common.hide_blizzard_cooldown_viewers()
            end)
        end

        -- Game events for cinematics, movies, challenge mode, and layout updates
        sfui.events.RegisterEvent("CINEMATIC_STOP", function()
            sfui.common.hide_blizzard_cooldown_viewers()
        end)
        sfui.events.RegisterEvent("STOP_MOVIE", function()
            sfui.common.hide_blizzard_cooldown_viewers()
        end)
        sfui.events.RegisterEvent("CHALLENGE_MODE_START", function()
            sfui.common.hide_blizzard_cooldown_viewers()
        end)
        sfui.events.RegisterEvent("CHALLENGE_MODE_RESET", function()
            sfui.common.hide_blizzard_cooldown_viewers()
        end)
        sfui.events.RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED", function()
            sfui.common.hide_blizzard_cooldown_viewers()
        end)
        sfui.events.RegisterEvent("ADDON_LOADED", function(event, loadedAddon)
            if loadedAddon == "Blizzard_CooldownViewer" then
                sfui.common.hide_blizzard_cooldown_viewers()
            end
        end)
    end

    -- Ensure the CVar is set to 1 so Blizzard's internal data systems are active.
    -- We hide the frames visually, but we need the data provider to function.
    if GetCVar("cooldownViewerEnabled") == "0" then
        SetCVar("cooldownViewerEnabled", 1)
    end
end

function sfui.common.are_blizzard_cooldown_viewers_hidden()
    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffBarCooldownViewer",
    }
    for _, name in ipairs(viewers) do
        local f = _G[name]
        if f and (f:GetAlpha() > 0 or f:IsMouseEnabled()) then
            return false
        end
    end
    return true
end

function sfui.common.get_short_string(name)
    if not name then return "" end

    local overrides = sfui.portals_db and sfui.portals_db.SHORT_STRINGS or {}

    if overrides[name] then return overrides[name] end

    local abbrev = ""
    for word in name:gmatch("%a+") do
        if word:upper() ~= "OF" and word:upper() ~= "THE" then
            local first = word:sub(1, 1)
            if first == first:upper() then
                abbrev = abbrev .. first
            end
        end
    end
    if abbrev:len() > 0 and abbrev:len() <= 4 then return abbrev end

    return name:sub(1, 4):upper()
end

function sfui.common.get_short_map_name(mapID)
    if not mapID then return nil end
    local ccm = _G.C_ChallengeMode
    local name = ccm and ccm.GetMapUIInfo and ccm.GetMapUIInfo(mapID)
    if not name then return nil end
    return sfui.common.get_short_string(name)
end

--- Parse a Mythic+ keystone level from a string (e.g. LFG title, comment, or chat message).
--- Prioritizes explicit "+" notation ("+12", "M+12"), then tagged notation ("key 12", "(12)"),
--- and finally bounded standalone integers (2-40) via frontier pattern.
--- @param str string|number|nil
--- @return number|nil
function sfui.common.parse_keystone_level(str)
    if not str then return nil end
    if type(str) == "number" then
        return (str >= 2 and str <= 40) and str or nil
    end
    if type(str) ~= "string" or str == "" then return nil end

    -- 1. Explicit "+" notation: "+12", "+ 12", "M+12", "m+ 12"
    local plusLevel = str:match("[+]%s*(%d+)")
    if plusLevel then
        local num = tonumber(plusLevel)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end

    -- 2. Explicit keyword notation: "key 12", "keystone 12", "(12)"
    local tagLevel = str:match("[Kk][Ee][Yy]%s*(%d+)") or str:match("%((%d+)%)")
    if tagLevel then
        local num = tonumber(tagLevel)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end

    -- 3. Standalone number between 2 and 40 (keystone levels)
    -- Using frontier patterns %f[%d] and %f[%D] so it doesn't match ilvl (e.g. 615) or score (e.g. 2500)
    for numStr in str:gmatch("%f[%d](%d+)%f[%D]") do
        local num = tonumber(numStr)
        if num and num >= 2 and num <= 40 then
            return num
        end
    end
    return nil
end

--- Authoritative M+ keystone query across bags, C_MythicPlus, and C_LFGList.
--- Prioritizes physical bags for instant reflection of downgrades/rerolls/upgrades.
--- @return table|nil { mapID = number|nil, level = number, link = string|nil, name = string|nil, itemID = number|nil }
function sfui.common.get_owned_keystone_info()
    local playerLevel = _G.UnitLevel and _G.UnitLevel("player")
    local maxLevel = (_G.GetMaxPlayerLevel and _G.GetMaxPlayerLevel()) or 80
    if playerLevel and playerLevel < maxLevel then
        return nil
    end

    local C_Item          = _G.C_Item
    local C_MythicPlus    = _G.C_MythicPlus
    local C_LFGList       = _G.C_LFGList
    local C_ChallengeMode = _G.C_ChallengeMode

    -- 1. Query the C_MythicPlus API directly (the exact Blizzard API that powers the in-game M+ Challenges panel)
    local mpMap = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local mpLvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()

    local bagMapID, bagLevel, bagLink, bagItemID, linkDungeonName
    if mpLvl and mpLvl > 0 and mpLvl < 100 then
        bagLevel = mpLvl
    end
    if mpMap and mpMap > 0 then
        bagMapID = mpMap
    end

    -- 2. Scan physical bags to retrieve clickable item link (for chat linking & tooltips) or as fallback
    sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink)
            if not itemLink and _G.C_Container and _G.C_Container.GetContainerItemLink then
                itemLink = _G.C_Container.GetContainerItemLink(bag, slot)
            end
            if itemLink then
                local isKeystone = (itemID and (itemID == 180653 or itemID == 187786 or itemID == 151086 or (C_Item and C_Item.IsItemKeystoneByID and C_Item.IsItemKeystoneByID(itemID))))
                    or string.find(itemLink, "keystone", 1, true)
                    or string.find(itemLink, "item:180653", 1, true)
                    or string.find(itemLink, "item:187786", 1, true)
                    or string.find(itemLink, "item:151086", 1, true)

                if isKeystone then
                    bagItemID = itemID or bagItemID or 180653
                    bagLink   = itemLink

                    -- A. Bracket notation from display link text: [Keystone: Dungeon Name (12)]
                    local rawBracket, bracketLvl = string.match(itemLink, "%[(.-)%s*%((%d+)%)%]")
                    if not bagLevel and bracketLvl then
                        local bl = tonumber(bracketLvl)
                        if bl and bl > 0 and bl < 100 then
                            bagLevel = bl
                        end
                    end
                    if rawBracket then
                        local cleanName = string.match(rawBracket, ":%s*(.+)") or rawBracket
                        linkDungeonName = cleanName:match("^%s*(.-)%s*$")
                    end

                    -- B. Hyperlink payload:
                    -- Modern Retail: keystone:itemID:mapID:level:... (e.g. keystone:180653:587:12:...)
                    -- Legacy:        keystone:mapID:level:... (e.g. keystone:587:12:...)
                    if not bagMapID or not bagLevel then
                        local p1, p2, p3 = string.match(itemLink, "keystone:(%d+):(%d+):?(%d*)")
                        if p1 then
                            local n1 = tonumber(p1)
                            local n2 = tonumber(p2)
                            local n3 = tonumber(p3)
                            if n1 and n1 > 10000 and n2 and n3 then
                                bagItemID = n1
                                if not bagMapID then bagMapID = n2 end
                                if not bagLevel or bagLevel >= 100 then bagLevel = n3 end
                            elseif n1 and n2 then
                                if not bagMapID then bagMapID = n1 end
                                if not bagLevel or bagLevel >= 100 then bagLevel = n2 end
                            end
                        end
                    end

                    -- C. Item hyperlink format: item:180653:... (modifiers 17 = mapID, 18 = level)
                    if (not bagMapID or not bagLevel or bagLevel >= 100) and string.find(itemLink, "item:", 1, true) then
                        local raw = string.match(itemLink, "item:%d+:([^|]+)")
                        if raw then
                            local temp = { strsplit(":", itemLink) }
                            for i = 1, #temp - 1 do
                                if temp[i] == "17" and not bagMapID then
                                    bagMapID = tonumber(temp[i + 1])
                                elseif temp[i] == "18" and (not bagLevel or bagLevel >= 100) then
                                    local l = tonumber(temp[i + 1])
                                    if l and l > 0 and l < 100 then
                                        bagLevel = l
                                    end
                                end
                            end
                        end
                    end

                    -- D. Parenthesized fallback: %(%d+%)
                    if not bagLevel or bagLevel >= 100 then
                        local nameLevel = string.match(itemLink, "%((%d+)%)")
                        if nameLevel then
                            local nl = tonumber(nameLevel)
                            if nl and nl > 0 and nl < 100 then
                                bagLevel = nl
                            end
                        end
                    end

                    -- Validate bagMapID against C_ChallengeMode: if invalid mapID, clear it
                    if bagMapID and bagMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                        local testName = C_ChallengeMode.GetMapUIInfo(bagMapID)
                        if not testName then
                            bagMapID = nil
                        end
                    end

                    -- Fallback: resolve mapID from dungeon name against current season maps
                    if not bagMapID and linkDungeonName and C_ChallengeMode and C_ChallengeMode.GetMapTable then
                        local maps = C_ChallengeMode.GetMapTable()
                        if maps then
                            for _, mID in ipairs(maps) do
                                local mName = C_ChallengeMode.GetMapUIInfo(mID)
                                if mName and (mName == linkDungeonName or string.find(mName, linkDungeonName, 1, true) or string.find(linkDungeonName, mName, 1, true)) then
                                    bagMapID = mID
                                    break
                                end
                            end
                        end
                    end

                    if bagLevel and bagLevel > 0 and bagMapID and bagMapID > 0 then
                        return true
                    end
                end
            end
        end, true, true, true)

    -- 3. Fall back to C_LFGList if still missing or out of bounds
    if (not bagMapID or not bagLevel or bagLevel >= 100) and C_LFGList and C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
        local activityID, groupID, lfgLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
        if not activityID then
            activityID, groupID, lfgLevel = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel(true)
        end
        if lfgLevel and lfgLevel > 0 and lfgLevel < 100 then
            if not bagLevel or bagLevel >= 100 then bagLevel = lfgLevel end
            if not bagMapID and activityID then
                local actInfo = C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(activityID)
                if actInfo and actInfo.mapID then
                    bagMapID = actInfo.mapID
                end
            end
        end
    end

    -- 4. If we have a valid keystone level (< 100), resolve name and return full keystone record
    if bagLevel and bagLevel > 0 and bagLevel < 100 then
        local mapName = nil
        if bagMapID and bagMapID > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            mapName = C_ChallengeMode.GetMapUIInfo(bagMapID)
        end
        if not mapName and linkDungeonName and linkDungeonName ~= "" then
            mapName = linkDungeonName
        end
        return {
            mapID   = bagMapID,
            level   = bagLevel,
            link    = bagLink,
            name    = mapName,
            itemID  = bagItemID or 180653,
        }
    end

    return nil
end
sfui.items = sfui.items or {}
sfui.items.get_owned_keystone_info = sfui.common.get_owned_keystone_info



