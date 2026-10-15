local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}

local GetProfessions        = _G.GetProfessions
local GetProfessionInfo     = _G.GetProfessionInfo
local C_SpellBook           = _G.C_SpellBook
local C_Spell               = _G.C_Spell
local GetSpellBookItemName  = _G.GetSpellBookItemName
local GetSpellBookItemTexture = _G.GetSpellBookItemTexture
local BOOKTYPE_SPELL        = _G.BOOKTYPE_SPELL or "spell"

local RUNEFORGING_SPELL_ID = 53428

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

local is_spell_known = function(spellID)
    if sfui.common and sfui.common.is_spell_known then
        return sfui.common.is_spell_known(spellID)
    end
    return false
end

local function get_spell_info_compat(spellID)
    local name, icon
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and info then
            name = info.name
            icon = info.iconID
        end
    end
    if not name and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok then name = n end
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then
        local ok, i = pcall(C_Spell.GetSpellTexture, spellID)
        if ok then icon = i end
    end
    if not name and _G.GetSpellInfo then
        local n, _, i = _G.GetSpellInfo(spellID)
        name = n
        icon = icon or i
    end
    return name or "runeforging", icon or "Interface\\Icons\\Spell_DeathKnight_Runeforging"
end

local function get_ability_spell(slot)
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 1
    if C_SpellBook and C_SpellBook.GetSpellBookItemType then
        local tOk, _, _, spellID = pcall(C_SpellBook.GetSpellBookItemType, slot, bank)
        local nOk, name = pcall(C_SpellBook.GetSpellBookItemName, slot, bank)
        local iOk, icon
        if C_SpellBook.GetSpellBookItemTexture then
            iOk, icon = pcall(C_SpellBook.GetSpellBookItemTexture, slot, bank)
        end
        if (tOk and spellID) or (nOk and name) then
            if not icon and spellID and C_Spell and C_Spell.GetSpellTexture then
                icon = C_Spell.GetSpellTexture(spellID)
            end
            return spellID or name, name or (spellID and tostring(spellID)), icon
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

sfui.ring.register_provider("professions", {
    name   = "professions",
    title  = "tradeskills & professions",
    events = { "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" },
    build  = function(out)
        local seenSpells = {}

        if GetProfessions and GetProfessionInfo then
            -- GetProfessions returns: prof1, prof2, arch, fish, cook
            -- Per design: primary (prof1, prof2), secondary (cook, fish). arch is omitted.
            local prof1, prof2, _, fish, cook = GetProfessions()
            local candidateProfs = { prof1, prof2, cook, fish }

            for p = 1, #candidateProfs do
                local profIndex = candidateProfs[p]
                if profIndex then
                    local profName, profIcon, _, _, numSpells, spellOffset = GetProfessionInfo(profIndex)
                    if numSpells and numSpells > 0 and spellOffset then
                        -- Only take ability 1 (the main tradeskill window), skipping sub-abilities
                        -- (e.g. cooking fire, profession specialization, disenchant, survey)
                        local slot = spellOffset + 1
                        local spellVal, spellName, spellIcon = get_ability_spell(slot)
                        local sName = (spellName or profName or ""):lower()
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

        -- Runeforging for Death Knights
        if is_spell_known(RUNEFORGING_SPELL_ID) then
            local rfName, rfIcon = get_spell_info_compat(RUNEFORGING_SPELL_ID)
            local rfLower = rfName:lower()
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
