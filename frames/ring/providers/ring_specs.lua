local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local _G = _G
local C_SpecializationInfo = _G.C_SpecializationInfo or {}
local GetNumSpecializations = C_SpecializationInfo.GetNumSpecializations or _G.GetNumSpecializations
local GetSpecialization     = C_SpecializationInfo.GetSpecialization or _G.GetSpecialization
local GetSpecializationInfo = C_SpecializationInfo.GetSpecializationInfo or _G.GetSpecializationInfo
local SetSpecialization     = C_SpecializationInfo.SetSpecialization or _G.SetSpecialization
local GetNumSpecGroups      = _G.GetNumTalentGroups or C_SpecializationInfo.GetNumSpecGroups
local GetCombatConfigIDForSpecGroup = C_SpecializationInfo.GetCombatConfigIDForSpecGroup
local GetActiveSpecGroup    = C_SpecializationInfo.GetActiveSpecGroup or _G.GetActiveSpecGroup or _G.GetActiveTalentGroup
local SetActiveSpecGroup    = C_SpecializationInfo.SetActiveSpecGroup or _G.SetActiveSpecGroup or _G.SetActiveTalentGroup
local InCombatLockdown      = _G.InCombatLockdown
local PlaySound             = _G.PlaySound
local SOUNDKIT              = _G.SOUNDKIT
local UnitLevel             = _G.UnitLevel
local ipairs                = _G.ipairs
local tostring              = _G.tostring
local wipe                  = _G.wipe
local string_lower          = string.lower

-- ── Classic & Forever Consumable Lookup Tables ───────────────────────────────
local HEALTHSTONE_IDS = {
    [5512] = true, [19004] = true, [19005] = true, -- Minor Healthstone
    [5511] = true, [19006] = true, [19007] = true, -- Lesser Healthstone
    [5509] = true, [19008] = true, [19009] = true, -- Healthstone
    [5510] = true, [19010] = true, [19011] = true, -- Greater Healthstone
    [9421] = true, [19012] = true, [19013] = true, -- Major Healthstone
    [22103] = true, [22104] = true, [22105] = true, -- Master Healthstone
    [36889] = true, [36890] = true, [36891] = true, -- Demonic Healthstone
    [36892] = true, [36893] = true, [36894] = true, -- Fel Healthstone
}

local CREATE_HEALTHSTONE_SPELLS = { 6201, 6202, 5699, 11729, 11730, 27230, 47871, 47878 }
local CONJURE_FOOD_SPELLS       = { 587, 597, 990, 6129, 10144, 10145, 28612, 42955 }
local CONJURE_WATER_SPELLS      = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 37420, 27090, 42956 }

local _seenItems  = {}
local _seenSpells = {}
local _bagCounts  = {}
local _bagOrder   = {}
local _bagMeta    = {}
local _potions    = {}

local function get_highest_known_spell(spellList)
    local isKnown = (sfui.buffs and sfui.buffs.data and sfui.buffs.data.IsSpellActuallyKnown)
        or (sfui.common and sfui.common.is_spell_known)
    if not isKnown then return nil end
    for i = #spellList, 1, -1 do
        local sID = spellList[i]
        if isKnown(sID) then
            local name = sfui.common and sfui.common.get_spell_name and sfui.common.get_spell_name(sID)
            local icon = sfui.common and sfui.common.get_spell_icon and sfui.common.get_spell_icon(sID)
            return sID, name, icon
        end
    end
    return nil
end

local function add_item_slice(out, idPrefix, itemID, name, icon, count, labelPrefix, color, selectionColor, extraAttrs)
    if not itemID or _seenItems[itemID] then return end
    _seenItems[itemID] = true

    local itemRef = "item:" .. tostring(itemID)
    local attrs = {
        type = "item",
        item = itemRef,
    }
    if extraAttrs then
        for k, v in _G.pairs(extraAttrs) do
            attrs[k] = v
        end
    end

    local cleanName = (name and string_lower(name)) or ("item " .. tostring(itemID))
    local label = labelPrefix and (labelPrefix .. cleanName) or cleanName

    out[#out + 1] = {
        id             = idPrefix .. "_" .. tostring(itemID),
        itemID         = itemID,
        label          = label,
        icon           = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        count          = count or 1,
        charges        = count or 1,
        color          = color or { 1, 1, 1 },
        selectionColor = selectionColor,
        attrs          = attrs,
    }
end

local function add_spell_slice(out, idPrefix, spellID, spellToCast, name, icon, labelPrefix, color, selectionColor, extraAttrs)
    local key = tostring(spellID or spellToCast)
    if not key or _seenSpells[key] then return end
    _seenSpells[key] = true

    local attrs = {
        type  = "spell",
        spell = spellToCast or spellID,
    }
    if extraAttrs then
        for k, v in _G.pairs(extraAttrs) do
            attrs[k] = v
        end
    end

    local cleanName = (name and string_lower(name)) or tostring(spellToCast or spellID)
    local label = labelPrefix and (labelPrefix .. cleanName) or cleanName

    out[#out + 1] = {
        id             = idPrefix .. "_" .. key,
        spellID        = tonumber(spellID),
        label          = label,
        icon           = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        color          = color or { 1, 1, 1 },
        selectionColor = selectionColor,
        attrs          = attrs,
    }
end

local function is_alchemy_potion(m)
    if not m or not m.lowerName then return false end
    local classID = m.classID
    local subClassID = m.subClassID
    local ln = m.lowerName

    -- Enum.ItemClass.Consumable == 0
    if classID ~= nil and classID ~= 0 then
        return false
    end

    -- Enum.ItemConsumableSubclass: Potion (1), Elixir (2), Flasksphials (3), Draught (13)
    if subClassID == 1 or subClassID == 2 or subClassID == 3 or subClassID == 13 then
        return true
    end

    -- Fallback for Classic Era items where subClassID is 0 (Generic)
    if ln:find("potion", 1, true)
        or ln:find("elixir", 1, true)
        or ln:find("flask of ", 1, true)
        or ln:find("draught", 1, true) then
        return true
    end

    return false
end

local function sort_potions(a, b)
    if (a.ilvl or 0) ~= (b.ilvl or 0) then
        return (a.ilvl or 0) > (b.ilvl or 0)
    end
    if (a.minLevel or 0) ~= (b.minLevel or 0) then
        return (a.minLevel or 0) > (b.minLevel or 0)
    end
    return (a.lowerName or "") < (b.lowerName or "")
end

local function build_classic_consumables_and_buffs_ring(out)
    wipe(_seenItems)
    wipe(_seenSpells)
    wipe(_bagCounts)
    wipe(_bagOrder)
    wipe(_potions)

    local pLevel = (UnitLevel and UnitLevel("player")) or 1
    local pClass = (sfui.common and sfui.common.get_player_class and sfui.common.get_player_class()) or ""

    -- ── 1. Single-pass Bag Scan (Healthstones, Alchemy Potions, Conjured Food/Water) ─
    local bestHealthstone   = nil
    local bestConjuredFood  = nil
    local bestConjuredWater = nil
    local bestFlask         = nil
    local bestWeaponStone   = nil

    if sfui.common and sfui.common.for_each_bag_item then
        sfui.common.for_each_bag_item(function(bag, slot, itemID, itemLink, info)
            if not itemID then return end
            local stack = (info and info.stackCount) or 1
            if not _bagCounts[itemID] then
                _bagCounts[itemID] = stack
                _bagOrder[#_bagOrder + 1] = itemID
                local meta = _bagMeta[itemID]
                if not meta then
                    meta = {}
                    _bagMeta[itemID] = meta
                end
                local name, _, _, ilvl, minLevel, _, _, _, _, tex, _, classID, subClassID = sfui.common.get_item_info(itemLink or itemID)
                if (classID == nil or subClassID == nil) and sfui.common.get_item_instant_info then
                    local _, _, _, _, instantTex, instClassID, instSubClassID = sfui.common.get_item_instant_info(itemLink or itemID)
                    tex = tex or instantTex
                    classID = classID or instClassID
                    subClassID = subClassID or instSubClassID
                end
                meta.itemID     = itemID
                meta.itemLink   = itemLink
                meta.bag        = bag
                meta.slot       = slot
                meta.name       = name or (info and info.hyperlink and info.hyperlink:match("%[(.-)%]"))
                meta.lowerName  = meta.name and string_lower(meta.name) or nil
                meta.icon       = tex or (info and info.iconFileID)
                meta.ilvl       = ilvl or 0
                meta.minLevel   = minLevel or 0
                meta.classID    = classID
                meta.subClassID = subClassID
            else
                _bagCounts[itemID] = _bagCounts[itemID] + stack
            end
        end, true, true, true)
    end

    local function is_better(candidate, current)
        if not current then return true end
        if (candidate.ilvl or 0) ~= (current.ilvl or 0) then
            return (candidate.ilvl or 0) > (current.ilvl or 0)
        end
        return (candidate.minLevel or 0) > (current.minLevel or 0)
    end

    for i = 1, #_bagOrder do
        local id = _bagOrder[i]
        local m = _bagMeta[id]
        if m and m.lowerName and pLevel >= (m.minLevel or 0) then
            m.count = _bagCounts[id] or 1
            local ln = m.lowerName

            if HEALTHSTONE_IDS[id] or ln:find("healthstone", 1, true) then
                if is_better(m, bestHealthstone) then bestHealthstone = m end
            elseif ln:find("^conjured ") then
                local isFood, isDrink = false, false
                if sfui.items and sfui.items.get_food_drink_info then
                    isFood, isDrink = sfui.items.get_food_drink_info(m.bag, m.slot, id, m.itemLink)
                end
                if not isFood and not isDrink then
                    if ln:find("water", 1, true) or ln:find("milk", 1, true) then
                        isDrink = true
                    else
                        isFood = true
                    end
                end
                if isDrink and is_better(m, bestConjuredWater) then
                    bestConjuredWater = m
                end
                if isFood and is_better(m, bestConjuredFood) then
                    bestConjuredFood = m
                end
            elseif ln:find("sharpening stone", 1, true) or ln:find("weightstone", 1, true) or ln:find("wizard oil", 1, true) or ln:find("mana oil", 1, true) then
                if is_better(m, bestWeaponStone) then bestWeaponStone = m end
            elseif is_alchemy_potion(m) then
                _potions[#_potions + 1] = m
                if (m.subClassID == 2 or m.subClassID == 3 or ln:find("flask of ", 1, true) or ln:find("elixir", 1, true)) and is_better(m, bestFlask) then
                    bestFlask = m
                end
            end
        end
    end

    table.sort(_potions, sort_potions)

    -- ── 2. Missing & Expiring Buffs from sfui.buffs (Reminders Module) ───────
    local records = (sfui.buffs and sfui.buffs.scan and sfui.buffs.scan.GetResults and sfui.buffs.scan.GetResults()) or nil
    if records and #records > 0 then
        for i = 1, #records do
            local rec = records[i]
            local entry = rec and rec.entry
            if entry then
                local prefix = rec.isMissing and "[missing] " or "[expiring] "
                local tint   = rec.isMissing and { 1.0, 0.78, 0.78 } or { 1.0, 0.92, 0.65 }
                local selCol = rec.isMissing and { 1.0, 0.30, 0.30 } or { 1.0, 0.80, 0.15 }

                if entry.key == "consumable_food" then
                    local selectedFood = sfui.buffs.consumables and sfui.buffs.consumables.GetSelectedFood and sfui.buffs.consumables.GetSelectedFood()
                    if selectedFood and selectedFood.itemID and (selectedFood.count or 0) > 0 then
                        add_item_slice(out, "buff_food", selectedFood.itemID, selectedFood.name, selectedFood.icon, selectedFood.count, prefix, tint, selCol)
                    end
                elseif entry.isFishingLure then
                    local skillRank = (sfui.fishing and sfui.fishing.GetSkill and sfui.fishing.GetSkill()) or 0
                    local bestLure = sfui.fishing_data and sfui.fishing_data.FindBestLureInBags and sfui.fishing_data.FindBestLureInBags(skillRank)
                    if bestLure and bestLure.itemID then
                        local lureIcon = (sfui.common and sfui.common.get_item_instant_info and select(5, sfui.common.get_item_instant_info(bestLure.itemID)))
                            or entry.fallbackIcon
                        add_item_slice(out, "buff_lure", bestLure.itemID, bestLure.name, lureIcon, bestLure.count or 1, prefix, tint, selCol, { ["target-slot"] = 16 })
                    end
                elseif entry.key == "consumable_flask" then
                    local chosenFlask = (sfui.buffs.consumables and sfui.buffs.consumables.GetSelectedFlask and sfui.buffs.consumables.GetSelectedFlask())
                        or bestFlask
                    if chosenFlask and chosenFlask.itemID and (chosenFlask.count or 0) > 0 then
                        add_item_slice(out, "buff_flask", chosenFlask.itemID, chosenFlask.name, chosenFlask.icon, chosenFlask.count, prefix, tint, selCol)
                    end
                elseif (entry.key == "consumable_weapon_mh" or entry.key == "consumable_weapon_oh") then
                    local targetSlot = entry.slot or 16
                    local chosenStone = (sfui.buffs.consumables and sfui.buffs.consumables.GetSelectedWeaponOil and sfui.buffs.consumables.GetSelectedWeaponOil(targetSlot))
                        or bestWeaponStone
                    if chosenStone and chosenStone.itemID then
                        local stoneId = chosenStone.itemID
                        local itemRef = "item:" .. tostring(stoneId)
                        out[#out + 1] = {
                            id             = "buff_stone_" .. tostring(targetSlot) .. "_" .. tostring(stoneId),
                            itemID         = stoneId,
                            label          = prefix .. string_lower(chosenStone.name or entry.name or "weapon stone"),
                            icon           = chosenStone.icon or entry.fallbackIcon,
                            count          = chosenStone.count or 1,
                            charges        = chosenStone.count or 1,
                            color          = tint,
                            selectionColor = selCol,
                            attrs          = {
                                type            = "item",
                                item            = itemRef,
                                ["target-slot"] = targetSlot,
                            },
                        }
                    end
                else
                    local buffsData = sfui.buffs.data
                    local castSpell, castIcon, castSpellID
                    if buffsData and buffsData.GetBestCastSpell then
                        castSpell, castIcon, castSpellID = buffsData.GetBestCastSpell(entry, rec.activeEnchant)
                    end
                    local spellToCast = (entry.type == "pet" and castSpellID) or castSpell or castSpellID
                    if spellToCast then
                        local extra = nil
                        if entry.type == "weapon_enchant" then
                            extra = { ["target-slot"] = entry.slot or 16 }
                        elseif entry.type ~= "pet" and entry.type ~= "stance" and entry.type ~= "tracking" then
                            extra = { unit = entry.unit or rec.unit or "player" }
                        end
                        local sliceLabel = (entry.type == "party_blessing" and entry.name) or castSpell or entry.name
                        add_spell_slice(
                            out,
                            "buff_" .. tostring(entry.key or "reminder"),
                            castSpellID or spellToCast,
                            spellToCast,
                            sliceLabel,
                            castIcon or rec.icon or entry.fallbackIcon,
                            prefix,
                            tint,
                            selCol,
                            extra
                        )
                    end
                end
            end
        end
    end

    -- ── 3. Healthstones, Well Fed Food, Conjured Food/Water & All Alchemy Potions ─
    if bestHealthstone then
        add_item_slice(out, "cons_hs", bestHealthstone.itemID, bestHealthstone.name, bestHealthstone.icon, bestHealthstone.count, nil, { 0.45, 1.0, 0.55 }, { 0.25, 0.95, 0.40 })
    elseif pClass == "WARLOCK" then
        local hsSpellID, hsSpellName, hsSpellIcon = get_highest_known_spell(CREATE_HEALTHSTONE_SPELLS)
        if hsSpellID then
            add_spell_slice(out, "cons_create_hs", hsSpellID, hsSpellID, hsSpellName or "create healthstone", hsSpellIcon, nil, { 0.45, 1.0, 0.55 }, { 0.25, 0.95, 0.40 })
        end
    end

    -- Well Fed food via sfui.buffs.consumables helpers
    if sfui.buffs and sfui.buffs.consumables then
        local selectedWellFed, allWellFed = nil, nil
        if sfui.buffs.consumables.GetSelectedFood then
            selectedWellFed, allWellFed = sfui.buffs.consumables.GetSelectedFood()
        end
        if selectedWellFed and selectedWellFed.itemID and (selectedWellFed.count or 0) > 0 then
            add_item_slice(out, "cons_wellfed", selectedWellFed.itemID, selectedWellFed.name, selectedWellFed.icon, selectedWellFed.count)
        end
        if allWellFed then
            for i = 1, #allWellFed do
                local wf = allWellFed[i]
                if wf and wf.itemID and (wf.count or 0) > 0 then
                    add_item_slice(out, "cons_wellfed", wf.itemID, wf.name, wf.icon, wf.count)
                end
            end
        end
    end

    -- Conjured food & conjured water (normal food/water omitted)
    if bestConjuredFood then
        add_item_slice(out, "cons_conj_food", bestConjuredFood.itemID, bestConjuredFood.name, bestConjuredFood.icon, bestConjuredFood.count)
    elseif pClass == "MAGE" then
        local cfSpellID, cfSpellName, cfSpellIcon = get_highest_known_spell(CONJURE_FOOD_SPELLS)
        if cfSpellID then
            add_spell_slice(out, "cons_conjure_food", cfSpellID, cfSpellID, cfSpellName or "conjure food", cfSpellIcon)
        end
    end

    if bestConjuredWater then
        add_item_slice(out, "cons_conj_water", bestConjuredWater.itemID, bestConjuredWater.name, bestConjuredWater.icon, bestConjuredWater.count)
    elseif pClass == "MAGE" then
        local cwSpellID, cwSpellName, cwSpellIcon = get_highest_known_spell(CONJURE_WATER_SPELLS)
        if cwSpellID then
            add_spell_slice(out, "cons_conjure_water", cwSpellID, cwSpellID, cwSpellName or "conjure water", cwSpellIcon)
        end
    end

    -- All Alchemy Potions in bags (sorted by item level descending)
    for i = 1, #_potions do
        local pot = _potions[i]
        if pot and pot.itemID then
            add_item_slice(out, "cons_pot", pot.itemID, pot.name, pot.icon, pot.count)
        end
    end

    -- ── 4. Classic Role Context Quick-Switch & Optional Dual Spec Swap ───────
    if sfui.gear and sfui.gear.SelectClassicRole and sfui.gear.CLASSIC_ROLES_BY_SPEC then
        local curSpecID = (sfui.common and sfui.common.get_current_spec_id and sfui.common.get_current_spec_id())
            or (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id())
        local numSpec = tonumber(curSpecID) or 0
        local roleList = sfui.gear.CLASSIC_ROLES_BY_SPEC[curSpecID] or sfui.gear.CLASSIC_ROLES_BY_SPEC[numSpec]
        if roleList and #roleList > 1 then
            local sdb = _G.SfuiDB and _G.SfuiDB.gear and (_G.SfuiDB.gear[curSpecID] or _G.SfuiDB.gear[numSpec])
            local activeRole = sdb and sdb.classic_role
            local iconMap = sfui.gear.CLASSIC_ROLE_ICONS and (sfui.gear.CLASSIC_ROLE_ICONS[curSpecID] or sfui.gear.CLASSIC_ROLE_ICONS[numSpec])
            for rIdx = 1, #roleList do
                local rKey = roleList[rIdx]
                local isRoleActive = (activeRole == rKey)
                local roleLabel = "role: " .. string_lower(tostring(rKey))
                if isRoleActive then
                    roleLabel = roleLabel .. " (active)"
                end
                local roleIcon = (iconMap and iconMap[rKey]) or "Interface\\Icons\\INV_Misc_QuestionMark"
                local targetSpecID = curSpecID or numSpec
                out[#out + 1] = {
                    id            = "classic_role_" .. tostring(rKey),
                    label         = roleLabel,
                    icon          = roleIcon,
                    active        = isRoleActive,
                    color         = isRoleActive and { 0.45, 1.0, 0.65 } or { 0.82, 0.88, 1.0 },
                    insecure_func = function()
                        if InCombatLockdown and InCombatLockdown() then
                            if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                                _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
                            end
                            return
                        end
                        if sfui.gear and sfui.gear.SelectClassicRole then
                            sfui.gear.SelectClassicRole(targetSpecID, rKey)
                        end
                    end,
                }
            end
        end
    end

    local numGroups = (GetNumSpecGroups and GetNumSpecGroups())
        or (GetCombatConfigIDForSpecGroup and GetCombatConfigIDForSpecGroup(2) and 2)
        or 0
    if numGroups > 1 then
        local activeGroup = (GetActiveSpecGroup and GetActiveSpecGroup()) or 1
        local targetGroup = (activeGroup == 1) and 2 or 1
        local groupName = (targetGroup == 1 and (_G.DUAL_SPEC_PRIMARY or "primary spec"))
            or (_G.DUAL_SPEC_SECONDARY or "secondary spec")
        local curSpecID = sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id()
        local icon = (sfui.talents and sfui.talents.get_spec_icon and sfui.talents.get_spec_icon(curSpecID))
            or "Interface\\Icons\\Spell_Nature_WispSplode"

        out[#out + 1] = {
            id          = "spec_group_swap_" .. targetGroup,
            specID      = curSpecID,
            specIndex   = targetGroup,
            label       = "swap to " .. string_lower(groupName),
            icon        = icon,
            color       = { 0.85, 0.85, 1.0 },
            insecure_func = function()
                if InCombatLockdown and InCombatLockdown() then
                    if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                        _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
                    end
                    return
                end
                if SetActiveSpecGroup then
                    SetActiveSpecGroup(targetGroup)
                end
                if sfui.events and sfui.events.SendMessage then
                    sfui.events.SendMessage("SFUI_ROLE_CONTEXT_CHANGED", "spec_group_" .. tostring(targetGroup), curSpecID)
                end
                if PlaySound and SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE then
                    PlaySound(SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE)
                end
            end,
        }
    end
end

local function build_specs_ring(out)
    if not sfui.isRetail then
        build_classic_consumables_and_buffs_ring(out)
        return
    end

    local numSpecs = (GetNumSpecializations and GetNumSpecializations()) or 0
    if numSpecs and numSpecs > 0 then
        local currentSpec = (GetSpecialization and GetSpecialization()) or 0
        for i = 1, numSpecs do
            local specID, name, _, icon = GetSpecializationInfo(i)
            if specID then
                local isActive = (i == currentSpec)
                local labelText = name and name:lower() or ("spec " .. i)
                if isActive then
                    labelText = labelText .. " (active)"
                end

                local specIndex = i
                out[#out + 1] = {
                    id          = "spec_" .. tostring(specID),
                    specID      = specID,
                    specIndex   = specIndex,
                    label       = labelText,
                    icon        = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    active      = isActive,
                    color       = isActive and { 1, 1, 1 } or { 0.8, 0.8, 0.8 },
                    insecure_func = function()
                        if InCombatLockdown and InCombatLockdown() then
                            if _G.UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
                                _G.UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1, 0.1, 0.1)
                            end
                            return
                        end
                        if isActive then return end
                        if SetSpecialization then
                            SetSpecialization(specIndex)
                        end
                        if sfui.events and sfui.events.SendMessage then
                            sfui.events.SendMessage("SFUI_ROLE_CONTEXT_CHANGED", labelText, specID)
                        end
                        if PlaySound and SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE then
                            PlaySound(SOUNDKIT.UI_CLASS_TALENT_SPEC_ACTIVATE)
                        end
                    end,
                }
            end
        end
    end
end

local ringTitle = sfui.isRetail and "specializations" or "consumables & buffs"

sfui.ring.register_provider("specs", {
    name   = ringTitle,
    title  = ringTitle,
    events = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED",
        "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED",
        "BAG_UPDATE_DELAYED",
        "SPELLS_CHANGED",
        "PLAYER_ENTERING_WORLD",
    },
    build  = build_specs_ring,
})

if sfui.events and sfui.events.RegisterMessage then
    local function rebuild_specs_ring()
        if sfui.ring and sfui.ring.request_rebuild then
            sfui.ring.request_rebuild("specs")
        end
    end
    sfui.events.RegisterMessage("SFUI_SPEC_CHANGED", rebuild_specs_ring)
    sfui.events.RegisterMessage("SFUI_GEAR_ROLE_CHANGED", rebuild_specs_ring)
    sfui.events.RegisterMessage("SFUI_ROLE_CONTEXT_CHANGED", rebuild_specs_ring)
end
