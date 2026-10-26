local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local GetProfessions        = _G.GetProfessions
local GetProfessionInfo     = _G.GetProfessionInfo
local C_SpellBook           = _G.C_SpellBook
local C_Spell               = _G.C_Spell
local C_TradeSkillUI        = _G.C_TradeSkillUI
local GetSpellBookItemName  = _G.GetSpellBookItemName
local GetSpellBookItemTexture = _G.GetSpellBookItemTexture
local BOOKTYPE_SPELL        = _G.BOOKTYPE_SPELL or "spell"

local RUNEFORGING_SPELL_ID  = 53428
local ARCHAEOLOGY_SKILL_LINE = 794
local COOKING_SKILL_LINE     = 185
local FIRST_AID_SKILL_LINE   = 129
local FISHING_SKILL_LINE     = 356

local COOKING_SPELL_IDS   = { 2550, 3102, 3413, 18260, 33359, 51296, 88053, 104381 }
local FIRST_AID_SPELL_IDS = { 3273, 3274, 7924, 10846, 27028, 45542, 88893, 110406 }
local FISHING_SPELL_IDS   = { 7620, 7731, 7732, 18248, 33095, 51294, 88868, 110410, 131474, 131476, 131490 }

local BLACKLISTED_PATTERNS = {
    "cooking fire",
    "campfire",
    "disenchant",
    "survey",
    "specialization",
}

local function is_blacklisted(name)
    if not name then return false end
    local lower = name:lower()
    for i = 1, #BLACKLISTED_PATTERNS do
        if lower:find(BLACKLISTED_PATTERNS[i], 1, true) then
            return true
        end
    end
    return false
end

local is_spell_known = sfui.common.is_spell_known

local function get_spell_info_compat(spellID, fallbackName, fallbackIcon)
    local name = sfui.common.get_spell_name(spellID)
    local icon = sfui.common.get_spell_icon(spellID)
    return name or fallbackName, icon or fallbackIcon
end

local function get_ability_spell(slot)
    if not slot or slot <= 0 then return nil, nil, nil end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1

    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
        if ok and info then
            local spellID = info.spellID or info.actionID
            local name = info.name
            local icon = info.iconID
            if (spellID and spellID > 0) or (name and name ~= "") then
                if not icon and spellID then
                    icon = sfui.common.get_spell_icon(spellID)
                end
                return spellID or name, name or (spellID and tostring(spellID)), icon
            end
        end
    end

    if C_SpellBook and C_SpellBook.GetSpellBookItemType then
        local tOk, itemType, actionID, spellID = pcall(C_SpellBook.GetSpellBookItemType, slot, bank)
        local nOk, name = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
        local icon
        if C_SpellBook.GetSpellBookItemTexture then
            local iOk, iTex = pcall(C_SpellBook.GetSpellBookItemTexture, slot, bank)
            if iOk then icon = iTex end
        end
        local resolvedID = spellID or actionID
        if (tOk and resolvedID and resolvedID > 0) or (nOk and name and name ~= "") then
            if not icon and resolvedID then
                icon = sfui.common.get_spell_icon(resolvedID)
            end
            return resolvedID or name, name or (resolvedID and tostring(resolvedID)), icon
        end
    end

    if GetSpellBookItemName then
        local name = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
        local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(slot, BOOKTYPE_SPELL)
        if name then
            return name, name, icon
        end
    end

    return nil, nil, nil
end

local function is_archaeology(skillLine, profName)
    if skillLine and skillLine == ARCHAEOLOGY_SKILL_LINE then
        return true
    end
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionSkillLineID and Enum and Enum.Profession and Enum.Profession.Archaeology then
        local ok, archID = pcall(C_TradeSkillUI.GetProfessionSkillLineID, Enum.Profession.Archaeology)
        if ok and archID and skillLine == archID then
            return true
        end
    end
    if profName and profName:lower():find("archaeolog", 1, true) then
        return true
    end
    return false
end

sfui.ring.register_provider("professions", {
    name   = "professions",
    title  = "tradeskills & professions",
    events = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" },
    build  = function(out)
        local seenSpells = {}
        local seenCooking = false
        local seenFirstAid = false
        local seenFishing = false

        local isCamelot = (sfui.isCamelot == true) or (sfui.compat and sfui.compat.is_camelot == true)
        local candidateProfs = {}

        if GetProfessions and GetProfessionInfo then
            if isCamelot then
                -- Camelot native 5-slot GetProfessions API: (prof1, prof2, faid, fish, cook)
                -- Order matches Camelot ProfessionsBook: primaries, cooking, fishing, first aid
                local p1, p2, faid, fish, cook = GetProfessions()
                candidateProfs = { p1, p2, cook, fish, faid }
            else
                local numReturns = select("#", GetProfessions())
                for p = 1, numReturns do
                    local profIndex = select(p, GetProfessions())
                    if profIndex then
                        candidateProfs[#candidateProfs + 1] = profIndex
                    end
                end
            end

            for p = 1, #candidateProfs do
                local profIndex = candidateProfs[p]
                if profIndex then
                    local profName, profIcon, _, _, numSpells, spellOffset, skillLine = GetProfessionInfo(profIndex)
                    if not is_archaeology(skillLine, profName) then
                        local isCook = (skillLine == COOKING_SKILL_LINE) or (profName and profName:lower():find("cooking", 1, true))
                        local isFaid = (skillLine == FIRST_AID_SKILL_LINE) or (profName and profName:lower():find("first aid", 1, true))
                        local isFish = (skillLine == FISHING_SKILL_LINE) or (profName and profName:lower():find("fishing", 1, true))

                        if isCook then seenCooking = true end
                        if isFaid then seenFirstAid = true end
                        if isFish then seenFishing = true end

                        local spellVal, spellIcon
                        local sName = ""
                        local spellCount = numSpells or 0

                        if spellCount > 0 and spellOffset then
                            for s = 1, math.min(spellCount, 2) do
                                local slot = spellOffset + s
                                local v, n, ic = get_ability_spell(slot)
                                local candidateName = (n or profName or ""):lower()
                                if candidateName ~= "" and not is_blacklisted(candidateName) then
                                    spellVal, spellIcon = v, ic
                                    sName = candidateName
                                    break
                                end
                            end
                        end

                        if sName == "" and profName then
                            spellVal = profName
                            spellIcon = profIcon
                            sName = profName:lower()
                        end

                        if sName ~= "" and not is_blacklisted(sName) and not seenSpells[sName] then
                            seenSpells[sName] = true
                            out[#out + 1] = {
                                id    = "prof_" .. tostring(spellVal or profIndex),
                                label = sName,
                                icon  = spellIcon or profIcon,
                                attrs = {
                                    type  = "spell",
                                    spell = spellVal or profName,
                                },
                            }
                        end
                    end
                end
            end
        end

        -- Secondary profession fallbacks: cooking, first aid, fishing
        if not seenCooking then
            for i = 1, #COOKING_SPELL_IDS do
                local sid = COOKING_SPELL_IDS[i]
                if is_spell_known(sid) then
                    local name, icon = get_spell_info_compat(sid, "cooking", "Interface\\Icons\\INV_Misc_Food_15")
                    local sName = (name or "cooking"):lower()
                    if not seenSpells[sName] then
                        seenSpells[sName] = true
                        seenCooking = true
                        out[#out + 1] = {
                            id    = "prof_cooking",
                            label = sName,
                            icon  = icon or "Interface\\Icons\\INV_Misc_Food_15",
                            attrs = {
                                type  = "spell",
                                spell = sid,
                            },
                        }
                    end
                    break
                end
            end
        end

        if not seenFirstAid then
            for i = 1, #FIRST_AID_SPELL_IDS do
                local sid = FIRST_AID_SPELL_IDS[i]
                if is_spell_known(sid) then
                    local name, icon = get_spell_info_compat(sid, "first aid", "Interface\\Icons\\Spell_Holy_SealOfSacrifice")
                    local sName = (name or "first aid"):lower()
                    if not seenSpells[sName] then
                        seenSpells[sName] = true
                        seenFirstAid = true
                        out[#out + 1] = {
                            id    = "prof_firstaid",
                            label = sName,
                            icon  = icon or "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
                            attrs = {
                                type  = "spell",
                                spell = sid,
                            },
                        }
                    end
                    break
                end
            end
        end

        if not seenFishing then
            for i = 1, #FISHING_SPELL_IDS do
                local sid = FISHING_SPELL_IDS[i]
                if is_spell_known(sid) then
                    local name, icon = get_spell_info_compat(sid, "fishing", "Interface\\Icons\\Trade_Fishing")
                    local sName = (name or "fishing"):lower()
                    if not seenSpells[sName] then
                        seenSpells[sName] = true
                        seenFishing = true
                        out[#out + 1] = {
                            id    = "prof_fishing",
                            label = sName,
                            icon  = icon or "Interface\\Icons\\Trade_Fishing",
                            attrs = {
                                type  = "spell",
                                spell = sid,
                            },
                        }
                    end
                    break
                end
            end
        end

        -- Runeforging for Death Knights
        if is_spell_known(RUNEFORGING_SPELL_ID) then
            local rfName, rfIcon = get_spell_info_compat(RUNEFORGING_SPELL_ID, "runeforging", "Interface\\Icons\\Spell_DeathKnight_Runeforging")
            local rfLower = (rfName or "runeforging"):lower()
            if not seenSpells[rfLower] then
                seenSpells[rfLower] = true
                out[#out + 1] = {
                    id    = "prof_runeforging",
                    label = rfLower,
                    icon  = rfIcon,
                    attrs = {
                        type  = "spell",
                        spell = RUNEFORGING_SPELL_ID,
                    },
                }
            end
        end
    end,
})
