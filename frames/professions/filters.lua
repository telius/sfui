local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.browser = sfui.recipes.browser or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/filters.lua
--  Recipe Catalog Filtering, Spec, Category & Search Engine
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

local B = sfui.recipes.browser

-- Shared configuration & layout constants
B.CFG = B.CFG or {
    FRAME_W      = 820,
    FRAME_H      = 590,
    ROW_H        = 34,
    ROW_PAD      = 2,
    VISIBLE_ROWS = 11,
}

-- UI Elements & Frame registry
B.ui = B.ui or {
    frame           = nil,
    listContainer   = nil,
    scrollFrame     = nil,
    rows            = {},
    searchBox       = nil,
    eventsButton    = nil,
    zoneButton      = nil,
    progressBar     = nil,
    statusText      = nil,
    emptyStateText  = nil,
    profButtons     = {},
    stateButtons    = {},
    sourceButtons   = {},
    specButtons     = {},
    categoryButtons = {},
    profRow         = nil,
    specRow         = nil,
    specLabel       = nil,
    catDivider      = nil,
}

-- State variables
B.filterState          = B.filterState or "unlearned" -- "unlearned" (default) | "all" | "learned"
B.filterText           = B.filterText or ""
B.showEventRecipes     = (B.showEventRecipes ~= nil) and B.showEventRecipes or false
B.showCurrentZoneOnly  = (B.showCurrentZoneOnly ~= nil) and B.showCurrentZoneOnly or false
B.activeCategoryFilter = B.activeCategoryFilter or nil
B.activeSpecFilter     = B.activeSpecFilter or nil
B.filteredRecipes      = B.filteredRecipes or {}
B.playerProfessions    = B.playerProfessions or {}
B.selectedSkillID      = B.selectedSkillID or nil

B.sourceFilters        = B.sourceFilters or {
    vendor        = false,
    trainer       = false,
    quest         = false,
    drop          = false,
    reputation    = false,
    limited_stock = false,
    alt_unlearned = false,
}

B.SOURCE_FILTERS       = B.SOURCE_FILTERS or {
    { key = "vendor",        label = "vendor",        width = 54 },
    { key = "trainer",       label = "trainer",       width = 54 },
    { key = "quest",         label = "quest",         width = 48 },
    { key = "drop",          label = "drop",          width = 48 },
    { key = "reputation",    label = "reputation",    width = 70 },
    { key = "limited_stock", label = "limited stock", width = 86 },
    { key = "alt_unlearned", label = "alt needs",     width = 68 },
}

-- Excluded non-crafting professions (gathering & fishing)
local EXCLUDED_PROFESSIONS = {
    [182] = true, -- herbalism
    [186] = true, -- mining
    [393] = true, -- skinning
    [356] = true, -- fishing
    [794] = true, -- archaeology
}

local EXCLUDED_PROFESSION_NAMES = {
    ["herbalism"]   = true,
    ["mining"]      = true,
    ["skinning"]    = true,
    ["fishing"]     = true,
    ["archaeology"] = true,
}

-- Baseline crafting & secondary professions available in camelot
B.ALL_PROFESSIONS = {
    { skillID = 171, name = "alchemy",        icon = "Interface\\Icons\\Trade_Alchemy" },
    { skillID = 164, name = "blacksmithing",  icon = "Interface\\Icons\\Trade_BlackSmithing" },
    { skillID = 185, name = "cooking",        icon = "Interface\\Icons\\INV_Misc_Food_15" },
    { skillID = 333, name = "enchanting",     icon = "Interface\\Icons\\Trade_Engraving" },
    { skillID = 202, name = "engineering",    icon = "Interface\\Icons\\Trade_Engineering" },
    { skillID = 129, name = "first aid",      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    { skillID = 165, name = "leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking" },
    { skillID = 197, name = "tailoring",      icon = "Interface\\Icons\\Trade_Tailoring" },
}

local CRAFTING_PROFESSION_IDS = {
    [171] = true, -- alchemy
    [164] = true, -- blacksmithing
    [185] = true, -- cooking
    [333] = true, -- enchanting
    [202] = true, -- engineering
    [129] = true, -- first aid
    [165] = true, -- leatherworking
    [197] = true, -- tailoring
}

local CANONICAL_PROFESSION_NAMES = {
    [171] = "alchemy",
    [164] = "blacksmithing",
    [185] = "cooking",
    [333] = "enchanting",
    [202] = "engineering",
    [129] = "first aid",
    [165] = "leatherworking",
    [197] = "tailoring",
}

local SKILL_ID_BY_NAME = {
    ["alchemy"]                     = 171,
    ["blacksmithing"]               = 164,
    ["armorsmith"]                  = 164,
    ["armorsmithing"]               = 164,
    ["weaponsmith"]                 = 164,
    ["weaponsmithing"]              = 164,
    ["axesmith"]                    = 164,
    ["axesmithing"]                 = 164,
    ["swordsmith"]                  = 164,
    ["swordsmithing"]               = 164,
    ["hammersmith"]                 = 164,
    ["hammersmithing"]              = 164,
    ["cooking"]                     = 185,
    ["enchanting"]                  = 333,
    ["engineering"]                 = 202,
    ["goblin engineer"]             = 202,
    ["goblin engineering"]          = 202,
    ["gnomish engineer"]            = 202,
    ["gnomish engineering"]         = 202,
    ["first aid"]                   = 129,
    ["firstaid"]                    = 129,
    ["leatherworking"]              = 165,
    ["dragonscale leatherworking"]  = 165,
    ["elemental leatherworking"]    = 165,
    ["tribal leatherworking"]       = 165,
    ["tailoring"]                   = 197,
    ["shadoweave tailoring"]        = 197,
    ["spellfire tailoring"]         = 197,
    ["mooncloth tailoring"]         = 197,
}

local SKILL_ICONS_BY_ID = {
    [171] = "Interface\\Icons\\Trade_Alchemy",
    [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [185] = "Interface\\Icons\\INV_Misc_Food_15",
    [333] = "Interface\\Icons\\Trade_Engraving",
    [202] = "Interface\\Icons\\Trade_Engineering",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [197] = "Interface\\Icons\\Trade_Tailoring",
}

B.SPEC_SHORT_TAGS = {
    ["goblin engineering"]          = "[goblin]",
    ["gnomish engineering"]         = "[gnomish]",
    ["armorsmith"]                  = "[armorsmith]",
    ["weaponsmith"]                 = "[weaponsmith]",
    ["dragonscale leatherworking"]  = "[dragonscale]",
    ["elemental leatherworking"]    = "[elemental]",
    ["tribal leatherworking"]       = "[tribal]",
}

B.PROFESSION_SPECS = {
    [164] = { -- blacksmithing
        { key = "armorsmith",  label = "armorsmith" },
        { key = "weaponsmith", label = "weaponsmith" },
    },
    [202] = { -- engineering
        { key = "goblin engineering",  label = "goblin" },
        { key = "gnomish engineering", label = "gnomish" },
    },
    [165] = { -- leatherworking
        { key = "dragonscale leatherworking", label = "dragonscale" },
        { key = "elemental leatherworking",   label = "elemental" },
        { key = "tribal leatherworking",      label = "tribal" },
    },
}

B.SPEC_SPELL_IDS = {
    ["goblin engineering"]         = { 20222 },
    ["gnomish engineering"]        = { 20219 },
    ["armorsmith"]                 = { 9788 },
    ["weaponsmith"]                = { 9787, 17041, 17039, 17040 },
    ["dragonscale leatherworking"] = { 10656 },
    ["elemental leatherworking"]   = { 10658 },
    ["tribal leatherworking"]      = { 10660 },
}

-- Sub-category / equipment slot definitions per profession (strictly lowercase)
B.PROFESSION_CATEGORIES = {
    [171] = { -- alchemy
        { key = nil,          label = "all" },
        { key = "potions",    label = "potions" },
        { key = "elixirs",    label = "elixirs" },
        { key = "flasks",     label = "flasks" },
        { key = "transmutes", label = "transmutes" },
        { key = "oils",       label = "oils & stones" },
    },
    [197] = { -- tailoring
        { key = nil,       label = "all" },
        { key = "bags",    label = "bags" },
        { key = "armor",   label = "armor" },
        { key = "shirts",  label = "shirts" },
        { key = "misc",    label = "misc" },
    },
    [164] = { -- blacksmithing
        { key = nil,         label = "all" },
        { key = "weapons",   label = "weapons" },
        { key = "armor",     label = "armor" },
        { key = "utilities", label = "utilities" },
    },
    [202] = { -- engineering
        { key = nil,          label = "all" },
        { key = "explosives", label = "explosives" },
        { key = "devices",    label = "devices" },
        { key = "goggles",    label = "goggles" },
        { key = "guns",       label = "guns & ammo" },
        { key = "parts",      label = "parts" },
    },
    [165] = { -- leatherworking
        { key = nil,     label = "all" },
        { key = "armor", label = "armor" },
        { key = "bags",  label = "bags" },
        { key = "kits",  label = "armor kits" },
        { key = "misc",  label = "misc" },
    },
    [333] = { -- enchanting
        { key = nil,     label = "all" },
        { key = "weapon", label = "weapon" },
        { key = "armor",  label = "armor" },
        { key = "oils",   label = "oils & wands" },
        { key = "rods",   label = "rods & reagents" },
    },
    [185] = { -- cooking
        { key = nil,     label = "all" },
        { key = "stat",  label = "stat food" },
        { key = "regen", label = "health & mana" },
        { key = "fun",   label = "utility & fun" },
    },
    [129] = { -- first aid
        { key = nil,        label = "all" },
        { key = "bandages", label = "bandages" },
        { key = "poison",   label = "anti-venom" },
    },
}

-- Canonical seasonal event recipes mapping (fallback & identification)
B.EVENT_RECIPES = {
    -- Feast of Winter Veil
    [21143] = "winter_veil",    -- gingerbread cookie
    [21144] = "winter_veil",    -- egg nog
    [21913] = "winter_veil",    -- edge of winter
    [21931] = "winter_veil",    -- enchant weapon - winter's might
    [21940] = "winter_veil",    -- snowmaster 9000
    [21943] = "winter_veil",    -- gloves of the greatfather
    [21945] = "winter_veil",    -- green holiday shirt
    [44950] = "winter_veil",    -- green winter clothes
    [44953] = "winter_veil",    -- winter boots
    [44958] = "winter_veil",    -- red winter clothes

    -- Lunar Festival
    [26403] = "lunar_festival", -- festival dress
    [26407] = "lunar_festival", -- festival suit
    [26416] = "lunar_festival", -- small blue rocket
    [26417] = "lunar_festival", -- small green rocket
    [26418] = "lunar_festival", -- small red rocket
    [26420] = "lunar_festival", -- large blue rocket
    [26421] = "lunar_festival", -- large green rocket
    [26422] = "lunar_festival", -- large red rocket
    [26423] = "lunar_festival", -- blue rocket cluster
    [26424] = "lunar_festival", -- green rocket cluster
    [26425] = "lunar_festival", -- red rocket cluster
    [26426] = "lunar_festival", -- large blue rocket cluster
    [26427] = "lunar_festival", -- large green rocket cluster
    [26428] = "lunar_festival", -- large red rocket cluster
    [26442] = "lunar_festival", -- firework launcher
    [26443] = "lunar_festival", -- firework cluster launcher
}

--- Check if any source filter is active
--- @return boolean
function B.HasActiveSourceFilter()
    return B.sourceFilters.vendor
        or B.sourceFilters.trainer
        or B.sourceFilters.quest
        or B.sourceFilters.drop
        or B.sourceFilters.reputation
        or B.sourceFilters.limited_stock
        or B.sourceFilters.alt_unlearned
end

--- Check if a recipe matches a specific source filter
--- @param r table
--- @param filterKey string
--- @return boolean
function B.RecipeMatchesSource(r, filterKey)
    if not r then return false end

    -- Starter recipes (minSkill <= 0) with no explicit source are trainer recipes
    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
    local isStarter = (minSkill <= 0) and ((not r.sources) or (#r.sources == 0) or (r.sources[1] and r.sources[1].type == "trainer"))
    if isStarter then
        return filterKey == "trainer"
    end

    local sources = r.sources
    if (not sources or #sources == 0) and sfui.recipes and sfui.recipes.GetSource then
        local res = sfui.recipes.GetSource(r.id)
        if res and res.sources and #res.sources > 0 then
            sources = res.sources
        end
    end

    if filterKey == "alt_unlearned" then
        return sfui.recipes.IsAltNeeded and sfui.recipes.IsAltNeeded(r)
    end

    -- Special case for drop: check curated drop sources
    if filterKey == "drop" and sfui.recipes and sfui.recipes.GetDropInfo then
        local mob = sfui.recipes.GetDropInfo(r.id)
        if mob then
            return true
        end
    end

    -- Special case for reputation: check recipe and source factions/standing (filtering out hostiles)
    if filterKey == "reputation" then
        if r.faction or r.standing then
            return true
        end
        if sources then
            for _, s in ipairs(sources) do
                if (s.faction or s.standing) and not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
                    return true
                end
            end
        end
        return false
    end

    if not sources or #sources == 0 then return false end

    for _, s in ipairs(sources) do
        -- Skip hostile sources (vendor, trainer, quest)
        if not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
            local st = s.type
            if filterKey == "trainer" and st == "trainer" then
                return true
            elseif filterKey == "vendor" and st == "vendor" then
                return true
            elseif filterKey == "quest" and st == "quest" then
                return true
            elseif filterKey == "drop" and (st == "drop" or st == "object" or st == "pickpocket" or st == "container") then
                return true
            elseif filterKey == "limited_stock" and st == "vendor" then
                -- Limited stock ONLY applies to vendor items (never drops, quests, or trainers)
                local isLim = (s.limited ~= nil and s.limited ~= false and s.limited ~= -1)
                if not isLim and r.recipeItemID and sfui.recipes and sfui.recipes.IsLimitedStock then
                    isLim = sfui.recipes.IsLimitedStock(r.recipeItemID, s.npcID)
                end
                if isLim then
                    return true
                end
            end
        end
    end

    return false
end

--- Check if a world holiday is currently active on the in-game calendar
--- @param eventName string
--- @return boolean
function B.IsHolidayActive(eventName)
    if not eventName then return false end
    if not C_Calendar or not C_Calendar.GetDayEvent then return false end
    local currentCalendarTime = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    local monthDay = currentCalendarTime and currentCalendarTime.monthDay
    if not monthDay then return false end

    local numEvents = C_Calendar.GetNumDayEvents and C_Calendar.GetNumDayEvents(0, monthDay) or 0
    for i = 1, numEvents do
        local event = C_Calendar.GetDayEvent(0, monthDay, i)
        if event and event.title then
            local title = event.title:lower()
            if eventName == "winter_veil" and title:find("winter veil") then
                return true
            elseif eventName == "lunar_festival" and title:find("lunar festival") then
                return true
            elseif eventName == "midsummer" and (title:find("midsummer") or title:find("fire festival")) then
                return true
            elseif eventName == "darkmoon_faire" and title:find("darkmoon") then
                return true
            elseif eventName == "fishing_extravaganza" and (title:find("fishing") or title:find("extravaganza")) then
                return true
            elseif eventName == "harvest_festival" and title:find("harvest") then
                return true
            end
        end
    end
    return false
end

--- Check if the active character has learned a given specialization
--- @param specKey string
--- @return boolean isKnown
function B.PlayerHasSpec(specKey)
    if not specKey then return false end

    local spellIDs = B.SPEC_SPELL_IDS[specKey]
    if spellIDs then
        for _, id in ipairs(spellIDs) do
            if (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id))
            or (C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(id))
            or (_G.IsPlayerSpell and _G.IsPlayerSpell(id))
            or (_G.IsSpellKnown and _G.IsSpellKnown(id)) then
                return true
            end
        end
    end
    if _G.GetNumSpellTabs and _G.GetSpellTabInfo and _G.GetSpellBookItemName then
        local numTabs = _G.GetNumSpellTabs()
        for tab = 1, numTabs do
            local _, _, offset, numSpells = _G.GetSpellTabInfo(tab)
            for s = offset + 1, offset + numSpells do
                local sName = _G.GetSpellBookItemName(s, "spell")
                if sName and sName:lower():find(specKey, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

--- Get available specialization definitions for a profession
--- @param skillID number?
--- @return table? specs
function B.GetSpecsForProfession(skillID)
    if not skillID then return nil end
    if B.PROFESSION_SPECS[skillID] then
        return B.PROFESSION_SPECS[skillID]
    end
    for _, p in ipairs(B.playerProfessions) do
        if p.skillID == skillID and p.name then
            local n = p.name:lower()
            if n:find("blacksmith") then
                return B.PROFESSION_SPECS[164]
            elseif n:find("engineer") then
                return B.PROFESSION_SPECS[202]
            elseif n:find("leatherwork") then
                return B.PROFESSION_SPECS[165]
            end
        end
    end
    return nil
end

--- Check if a recipe matches a specific specialization key
--- @param r table
--- @param specKey string
--- @return boolean
function B.RecipeMatchesSpec(r, specKey)
    if not r or not specKey then return true end
    if not r.spec then return false end
    local s = r.spec:lower()
    local k = specKey:lower()
    return (s == k) or (s:find(k, 1, true) ~= nil)
end

--- Check if a recipe matches a chosen sub-category / equipment slot
--- @param r table
--- @param catKey string?
--- @param skillID number?
--- @return boolean
function B.RecipeMatchesCategory(r, catKey, skillID)
    if not r or not catKey or catKey == "all" then return true end
    local name = r.name and r.name:lower() or ""

    if skillID == 171 then -- alchemy
        if catKey == "potions" then
            return name:find("potion") ~= nil or name:find("draught") ~= nil
        elseif catKey == "elixirs" then
            return name:find("elixir") ~= nil
        elseif catKey == "flasks" then
            return name:find("flask") ~= nil
        elseif catKey == "transmutes" then
            return name:find("transmute") ~= nil
        elseif catKey == "oils" then
            return name:find("oil") ~= nil or name:find("stone") ~= nil
        end
    elseif skillID == 197 then -- tailoring
        if catKey == "bags" then
            return name:find("bag") ~= nil or name:find("pouch") ~= nil or name:find("pack") ~= nil or name:find("sack") ~= nil
        elseif catKey == "shirts" then
            return name:find("shirt") ~= nil
        elseif catKey == "armor" then
            return name:find("robe") ~= nil or name:find("vest") ~= nil or name:find("tunic") ~= nil or name:find("pants") ~= nil
                or name:find("leggings") ~= nil or name:find("gloves") ~= nil or name:find("boots") ~= nil or name:find("belt") ~= nil
                or name:find("shoulders") ~= nil or name:find("cloak") ~= nil or name:find("bracers") ~= nil or name:find("headband") ~= nil
                or name:find("cap") ~= nil or name:find("suit") ~= nil or name:find("dress") ~= nil
        elseif catKey == "misc" then
            return not (name:find("bag") or name:find("pouch") or name:find("shirt") or name:find("robe") or name:find("vest")
                or name:find("pants") or name:find("gloves") or name:find("boots") or name:find("cloak"))
        end
    elseif skillID == 164 then -- blacksmithing
        if catKey == "weapons" then
            return name:find("sword") ~= nil or name:find("axe") ~= nil or name:find("mace") ~= nil or name:find("dagger") ~= nil
                or name:find("blade") ~= nil or name:find("hammer") ~= nil or name:find("polearm") ~= nil or name:find("rapier") ~= nil
        elseif catKey == "armor" then
            return name:find("chestplate") ~= nil or name:find("mail") ~= nil or name:find("helm") ~= nil or name:find("boots") ~= nil
                or name:find("gauntlets") ~= nil or name:find("leggings") ~= nil or name:find("bracers") ~= nil or name:find("belt") ~= nil
                or name:find("shield") ~= nil or name:find("shoulders") ~= nil or name:find("breastplate") ~= nil
        elseif catKey == "utilities" then
            return name:find("key") ~= nil or name:find("rod") ~= nil or name:find("spur") ~= nil or name:find("spike") ~= nil
                or name:find("grinding") ~= nil or name:find("sharpening") ~= nil or name:find("weightstone") ~= nil or name:find("chain") ~= nil
        end
    elseif skillID == 202 then -- engineering
        if catKey == "explosives" then
            return name:find("bomb") ~= nil or name:find("dynamite") ~= nil or name:find("grenade") ~= nil or name:find("charge") ~= nil
                or name:find("mortar") ~= nil or name:find("land mine") ~= nil or name:find("blast") ~= nil
        elseif catKey == "devices" then
            return name:find("trinket") ~= nil or name:find("ray") ~= nil or name:find("reflector") ~= nil or name:find("net") ~= nil
                or name:find("cloak") ~= nil or name:find("teleport") ~= nil or name:find("discombob") ~= nil or name:find("dummy") ~= nil
                or name:find("deflector") ~= nil or name:find("sheep") ~= nil or name:find("dragonling") ~= nil or name:find("chicken") ~= nil
                or name:find("alarm") ~= nil or name:find("repair") ~= nil
        elseif catKey == "goggles" then
            return name:find("goggles") ~= nil or name:find("visor") ~= nil or name:find("helm") ~= nil or name:find("lenses") ~= nil
        elseif catKey == "guns" then
            return name:find("gun") ~= nil or name:find("rifle") ~= nil or name:find("blunderbuss") ~= nil or name:find("bullet") ~= nil
                or name:find("shot") ~= nil or name:find("arrow") ~= nil or name:find("scope") ~= nil or name:find("ammo") ~= nil
        elseif catKey == "parts" then
            return name:find("tube") ~= nil or name:find("gyro") ~= nil or name:find("framework") ~= nil or name:find("fuse") ~= nil
                or name:find("wire") ~= nil or name:find("battery") ~= nil or name:find("wrench") ~= nil or name:find("strut") ~= nil
                or name:find("casing") ~= nil or name:find("core") ~= nil or name:find("trigger") ~= nil
        end
    elseif skillID == 165 then -- leatherworking
        if catKey == "armor" then
            return name:find("vest") ~= nil or name:find("tunic") ~= nil or name:find("pants") ~= nil or name:find("gloves") ~= nil
                or name:find("boots") ~= nil or name:find("belt") ~= nil or name:find("shoulders") ~= nil or name:find("helm") ~= nil
                or name:find("bracers") ~= nil or name:find("cloak") ~= nil or name:find("jerkin") ~= nil or name:find("cap") ~= nil
        elseif catKey == "bags" then
            return name:find("quiver") ~= nil or name:find("pouch") ~= nil or name:find("bag") ~= nil or name:find("pack") ~= nil
        elseif catKey == "kits" then
            return name:find("armor kit") ~= nil
        elseif catKey == "misc" then
            return name:find("hide") ~= nil or name:find("salt") ~= nil or name:find("cure") ~= nil or name:find("leather") ~= nil
        end
    elseif skillID == 333 then -- enchanting
        if catKey == "weapon" then
            return name:find("weapon") ~= nil or name:find("2h") ~= nil or name:find("striking") ~= nil or name:find("slaying") ~= nil
                or name:find("crusader") ~= nil or name:find("lifestealing") ~= nil or name:find("fiery") ~= nil or name:find("icy") ~= nil
                or name:find("unholy") ~= nil
        elseif catKey == "armor" then
            return name:find("chest") ~= nil or name:find("bracer") ~= nil or name:find("cloak") ~= nil or name:find("boots") ~= nil
                or name:find("gloves") ~= nil or name:find("shield") ~= nil
        elseif catKey == "oils" then
            return name:find("oil") ~= nil or name:find("wand") ~= nil
        elseif catKey == "rods" then
            return name:find("rod") ~= nil or name:find("nexus") ~= nil or name:find("enchanted ") ~= nil
        end
    elseif skillID == 185 then -- cooking
        if catKey == "stat" then
            return name:find("stamina") ~= nil or name:find("strength") ~= nil or name:find("agility") ~= nil
                or name:find("squid") ~= nil or name:find("dumpling") ~= nil or name:find("omelet") ~= nil
        elseif catKey == "regen" then
            return name:find("healing") ~= nil or name:find("mana") ~= nil or name:find("soup") ~= nil or name:find("stew") ~= nil
        elseif catKey == "fun" then
            return name:find("delight") ~= nil or name:find("surprise") ~= nil or name:find("grog") ~= nil or name:find("nog") ~= nil
        end
    elseif skillID == 129 then -- first aid
        if catKey == "bandages" then
            return name:find("bandage") ~= nil
        elseif catKey == "poison" then
            return name:find("anti-venom") ~= nil or name:find("antivenom") ~= nil
        end
    end

    return true
end

--- Check if a recipe is obtainable in the player's current map zone
--- @param r table
--- @return boolean
function B.RecipeMatchesCurrentZone(r)
    if not r then return false end
    local currentMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local currentZoneText = (GetZoneText and GetZoneText():lower()) or ""
    local currentSubZoneText = (GetSubZoneText and GetSubZoneText():lower()) or ""

    if currentZoneText == "" and not currentMapID then
        return true
    end

    local sources = sfui.recipes and sfui.recipes.GetAllNonHostileSources and sfui.recipes.GetAllNonHostileSources(r)
    if not sources or #sources == 0 then
        local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
        if minSkill <= 0 then
            local cityZones = {
                ["orgrimmar"] = true, ["stormwind city"] = true, ["ironforge"] = true,
                ["thunder bluff"] = true, ["undercity"] = true, ["darnassus"] = true,
            }
            if cityZones[currentZoneText] then return true end
        end
        return false
    end

    for _, s in ipairs(sources) do
        if currentMapID and s.mapID and s.mapID == currentMapID then
            return true
        end

        if s.zone and currentZoneText ~= "" then
            local sz = s.zone:lower()
            if sz == currentZoneText or sz:find(currentZoneText, 1, true) or currentZoneText:find(sz, 1, true) then
                return true
            end
        end

        if s.zone and currentSubZoneText ~= "" then
            local sz = s.zone:lower()
            if sz == currentSubZoneText or sz:find(currentSubZoneText, 1, true) or currentSubZoneText:find(sz, 1, true) then
                return true
            end
        end

        if s.type == "trainer" and (not s.zone or s.zone == "" or s.zone:lower():find("city")) then
            local cityZones = {
                ["orgrimmar"] = true, ["stormwind city"] = true, ["ironforge"] = true,
                ["thunder bluff"] = true, ["undercity"] = true, ["darnassus"] = true,
            }
            if cityZones[currentZoneText] then
                return true
            end
        end
    end

    return false
end

--- Check if a recipe has at least one obtainable / non-hostile source for the active character
--- @param r table
--- @return boolean isAvailable
function B.HasAnyNonHostileSource(r)
    if not r then return false end
    local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
    if minSkill <= 0 then return true end

    if sfui.recipes and sfui.recipes.GetDropInfo and sfui.recipes.GetDropInfo(r.id) then
        return true
    end

    local sources = r.sources
    if (not sources or #sources == 0) and sfui.recipes and sfui.recipes.GetSource then
        local res = sfui.recipes.GetSource(r.id)
        if res and res.sources and #res.sources > 0 then
            sources = res.sources
        end
    end
    if not sources or #sources == 0 then
        return true
    end

    local allHostile = true
    for _, s in ipairs(sources) do
        local st = s.type
        if st == "drop" or st == "object" or st == "pickpocket" or st == "container" then
            return true
        end
        if not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
            allHostile = false
            break
        end
    end
    return not allHostile
end

--- Query learned crafting professions of the active character
--- @return table list
function B.GetPlayerProfessionsList()
    local list = {}
    local seen = {}

    local function addProfession(skillLine, lowerName, rank, maxRank, icon)
        if not lowerName or lowerName == "" then return end
        local sID = (skillLine and CRAFTING_PROFESSION_IDS[skillLine] and skillLine)
                 or SKILL_ID_BY_NAME[lowerName]
        if not sID or not CRAFTING_PROFESSION_IDS[sID] then return end
        if EXCLUDED_PROFESSIONS[sID] or EXCLUDED_PROFESSION_NAMES[lowerName] then return end
        if seen[sID] then
            for _, p in ipairs(list) do
                if p.skillID == sID then
                    if (rank or 0) > (p.rank or 0) then p.rank = rank end
                    if (maxRank or 0) > (p.maxRank or 0) then p.maxRank = maxRank end
                    break
                end
            end
            return
        end
        seen[sID] = true
        local canonName = CANONICAL_PROFESSION_NAMES[sID] or lowerName
        table.insert(list, {
            skillID = sID,
            name    = canonName,
            rank    = rank or 0,
            maxRank = maxRank or 0,
            icon    = icon or SKILL_ICONS_BY_ID[sID],
        })
    end

    -- 1. Query Camelot/Classic 5-slot GetProfessions (p1, p2, faid, fish, cook) safely
    if _G.GetProfessions and _G.GetProfessionInfo then
        local p1, p2, faid, fish, cook, p6, p7 = _G.GetProfessions()
        local slots = { p1, p2, faid, fish, cook, p6, p7 }
        for i = 1, 7 do
            local idx = slots[i]
            if idx then
                local name, icon, rank, maxRank, _, _, skillLine = _G.GetProfessionInfo(idx)
                local lowerName = name and name:lower()
                local resolvedID = (skillLine and CRAFTING_PROFESSION_IDS[skillLine] and skillLine)
                                or (lowerName and SKILL_ID_BY_NAME[lowerName])
                if resolvedID and CRAFTING_PROFESSION_IDS[resolvedID] then
                    addProfession(resolvedID, lowerName, rank, maxRank, icon)
                end
            end
        end
    end

    -- 2. Direct fallback for secondary professions in Classic / Camelot (Cooking 185, First Aid 129)
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local secIDs = {
            [185] = { name = "cooking",   icon = "Interface\\Icons\\INV_Misc_Food_15" },
            [129] = { name = "first aid", icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
        }
        for sID, def in pairs(secIDs) do
            if not seen[sID] then
                local info = C_SkillInfo.GetSkillLineInfoByID(sID)
                if info and info.rank and info.rank > 0 then
                    local pName = (info.name and info.name:lower()) or def.name
                    addProfession(sID, pName, info.rank, info.maxRank or info.rank, def.icon)
                end
            end
        end
    end

    -- 3. Skill line traversal fallback for classic skill tab (strictly filter to crafting professions)
    if (GetNumSkillLines and GetSkillLineInfo) or (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo) then
        local numSkills = (C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetNumSkillLines())
                       or (GetNumSkillLines and GetNumSkillLines()) or 0
        for i = 1, numSkills do
            local sName, sRank, sMaxRank, sID
            if C_SkillInfo and C_SkillInfo.GetSkillLineInfo then
                local info = C_SkillInfo.GetSkillLineInfo(i)
                if info and not info.isHeader then
                    sName = info.name
                    sRank = info.rank
                    sMaxRank = info.maxRank
                    sID = info.skillID
                end
            elseif GetSkillLineInfo then
                local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
                if not isHeader then
                    sName = name
                    sRank = rank
                    sMaxRank = maxRank
                end
            end

            if sName and (sRank or 0) > 0 then
                local lowerName = sName:lower()
                local mappedID = (sID and CRAFTING_PROFESSION_IDS[sID] and sID)
                              or SKILL_ID_BY_NAME[lowerName]
                if mappedID and CRAFTING_PROFESSION_IDS[mappedID] and not seen[mappedID] then
                    local icon = SKILL_ICONS_BY_ID[mappedID]
                    addProfession(mappedID, lowerName, sRank, sMaxRank, icon)
                end
            end
        end
    end

    -- 4. Check SfuiDB.alts for player if live APIs are still warming up on initial login frame
    if #list == 0 and SfuiDB and SfuiDB.alts and _G.UnitGUID then
        local playerGUID = _G.UnitGUID("player")
        local altData = playerGUID and SfuiDB.alts[playerGUID]
        if altData and altData.professions then
            if altData.professions.primaries then
                for _, p in ipairs(altData.professions.primaries) do
                    local pName = p.name and p.name:lower()
                    local pID = (p.skillID and CRAFTING_PROFESSION_IDS[p.skillID] and p.skillID)
                             or (pName and SKILL_ID_BY_NAME[pName])
                    if pID and CRAFTING_PROFESSION_IDS[pID] and not seen[pID] then
                        addProfession(pID, pName, p.rank, p.maxRank, p.icon or SKILL_ICONS_BY_ID[pID])
                    end
                end
            end
            if altData.professions.cooking and not seen[185] then
                local c = altData.professions.cooking
                addProfession(185, "cooking", c.rank, c.maxRank, "Interface\\Icons\\INV_Misc_Food_15")
            end
            if altData.professions.firstAid and not seen[129] then
                local fa = altData.professions.firstAid
                addProfession(129, "first aid", fa.rank, fa.maxRank, "Interface\\Icons\\Spell_Holy_SealOfSacrifice")
            end
        end
    end

    table.sort(list, function(a, b)
        local aIsSec = (a.skillID == 185 or a.skillID == 129)
        local bIsSec = (b.skillID == 185 or b.skillID == 129)
        if aIsSec ~= bIsSec then
            return not aIsSec
        end
        return (a.name or "") < (b.name or "")
    end)

    return list
end

--- Get the current skill rank of the selected profession
--- @param skillID number?
--- @return number rank
function B.GetCurrentProfessionRank(skillID)
    if not skillID then return 0 end
    for _, p in ipairs(B.playerProfessions) do
        if p.skillID == skillID then
            return p.rank or 0
        end
    end
    return 0
end

-- ─── Player Identity & Recipe State Memoization ──────────────────────────────
local cachedPlayerGUID = nil
local cachedPlayerRealm = nil

local function GetPlayerIdentifiers()
    if not cachedPlayerGUID and _G.UnitGUID then
        cachedPlayerGUID = _G.UnitGUID("player")
    end
    if not cachedPlayerRealm then
        cachedPlayerRealm = (_G.GetNormalizedRealmName and _G.GetNormalizedRealmName()) or (_G.GetRealmName and _G.GetRealmName()) or ""
    end
    return cachedPlayerGUID, cachedPlayerRealm
end

local isLearnedCache = {}

--- Clear memoized recipe learned status
function B.ClearLearnedCache()
    wipe(isLearnedCache)
end

--- Return number of memoized recipe states for telemetry
--- @return number count
function B.GetLearnedCacheSize()
    local count = 0
    for _ in pairs(isLearnedCache) do
        count = count + 1
    end
    return count
end

--- Check if the active character or an alt knows a recipe
--- @param recipeOrSpellID table|number
--- @param rOrGUID table|string?
--- @param optionalRealm string?
--- @return boolean isLearned
function B.IsRecipeLearned(recipeOrSpellID, rOrGUID, optionalRealm)
    if not recipeOrSpellID then return false end

    local spellID, r, targetGUID, targetRealm
    if type(recipeOrSpellID) == "table" then
        r = recipeOrSpellID
        spellID = r.id
        if type(rOrGUID) == "string" then
            targetGUID = rOrGUID
            targetRealm = optionalRealm
        end
    elseif type(recipeOrSpellID) == "number" then
        spellID = recipeOrSpellID
        if type(rOrGUID) == "table" then
            r = rOrGUID
            if type(optionalRealm) == "string" then
                targetGUID = optionalRealm
            end
        elseif type(rOrGUID) == "string" then
            targetGUID = rOrGUID
            targetRealm = optionalRealm
        end
    end

    local playerGUID, playerRealm = GetPlayerIdentifiers()
    local isPlayer = (not targetGUID) or (targetGUID == playerGUID)

    if isPlayer and spellID and isLearnedCache[spellID] ~= nil then
        return isLearnedCache[spellID]
    end

    -- Base / starter recipes (minSkill <= 0) are learned automatically upon learning the profession
    local minSkill = (r and (r.minSkill or (r.colors and r.colors[1]))) or 0
    if minSkill <= 0 then
        local skillID = r and r.skillID or B.selectedSkillID
        if isPlayer then
            if skillID then
                for _, p in ipairs(B.playerProfessions) do
                    if p.skillID == skillID then
                        if spellID then isLearnedCache[spellID] = true end
                        return true
                    end
                end
            end
        else
            if SfuiDB and SfuiDB.alts and targetGUID and SfuiDB.alts[targetGUID] then
                local altData = SfuiDB.alts[targetGUID]
                if altData.professions then
                    if altData.professions.primaries then
                        for _, p in ipairs(altData.professions.primaries) do
                            if p.skillID == skillID then
                                return true
                            end
                        end
                    end
                    if skillID == 185 and altData.professions.cooking then
                        return true
                    elseif skillID == 129 and altData.professions.firstAid then
                        return true
                    end
                end
            end
        end
    end

    if isPlayer and spellID then
        -- 1. Direct spellbook / player spell check
        if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spellID) then
            isLearnedCache[spellID] = true
            return true
        end
        if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook and C_SpellBook.IsSpellKnownOrInSpellBook(spellID) then
            isLearnedCache[spellID] = true
            return true
        end
        if _G.IsPlayerSpell and _G.IsPlayerSpell(spellID) then
            isLearnedCache[spellID] = true
            return true
        end
        if _G.IsSpellKnown and _G.IsSpellKnown(spellID) then
            isLearnedCache[spellID] = true
            return true
        end

        -- 2. C_TradeSkillUI check
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spellID)
            if ok and type(info) == "table" and info.learned ~= nil then
                local learned = info.learned and true or false
                isLearnedCache[spellID] = learned
                return learned
            end
        end
    end

    local queryGUID = isPlayer and playerGUID or targetGUID
    local queryRealm = isPlayer and playerRealm or (targetRealm or playerRealm)

    -- 3. Check SfuiDB.crafts for output item crafter
    if r and r.output and SfuiDB and SfuiDB.crafts and SfuiDB.crafts[r.output] then
        if queryGUID and SfuiDB.crafts[r.output][queryGUID] then
            if isPlayer and spellID then isLearnedCache[spellID] = true end
            return true
        end
    end

    -- 4. Fallback to SfuiDB.recipes alt tracker (by recipe item or spellID)
    if SfuiDB and SfuiDB.recipes and queryRealm and queryGUID then
        local rItemID = r and r.recipeItemID
        if rItemID and SfuiDB.recipes[rItemID] and SfuiDB.recipes[rItemID][queryRealm] and SfuiDB.recipes[rItemID][queryRealm][queryGUID] then
            if isPlayer and spellID then isLearnedCache[spellID] = true end
            return true
        end
        if spellID and SfuiDB.recipes[spellID] and SfuiDB.recipes[spellID][queryRealm] and SfuiDB.recipes[spellID][queryRealm][queryGUID] then
            if isPlayer and spellID then isLearnedCache[spellID] = true end
            return true
        end
    end

    if isPlayer and spellID then isLearnedCache[spellID] = false end
    return false
end

--- Check if at least one alt has the required profession for this recipe and hasn't learned it yet
--- @param recipeOrID table|number
--- @return boolean isNeeded, table|nil altList
function sfui.recipes.IsAltNeeded(recipeOrID)
    if not recipeOrID or not SfuiDB or not SfuiDB.alts then return false end
    local r = recipeOrID
    if type(recipeOrID) == "number" then
        if sfui.recipes_camelot and sfui.recipes_camelot.recipes then
            r = sfui.recipes_camelot.recipes[recipeOrID]
        end
        if not r and sfui.recipes_camelot and sfui.recipes_camelot.items then
            local sID = sfui.recipes_camelot.items[recipeOrID]
            r = sID and sfui.recipes_camelot.recipes and sfui.recipes_camelot.recipes[sID]
        end
    end
    if not r then return false end

    local skillID = r.skillID
    local myGUID, myRealm = GetPlayerIdentifiers()

    local matchingAlts = nil

    for guid, altData in pairs(SfuiDB.alts) do
        if guid ~= myGUID and altData then
            local altRealm = altData.realm or myRealm
            if altRealm == myRealm then
                local hasProf = false
                if altData.professions then
                    if altData.professions.primaries then
                        for _, p in ipairs(altData.professions.primaries) do
                            if p.skillID == skillID or (r.profession and p.name and p.name:lower() == r.profession:lower()) then
                                hasProf = true
                                break
                            end
                        end
                    end
                    if not hasProf and skillID == 185 and altData.professions.cooking then
                        hasProf = true
                    elseif not hasProf and skillID == 129 and altData.professions.firstAid then
                        hasProf = true
                    end
                end

                if hasProf then
                    local isKnown = B.IsRecipeLearned(r, guid, altRealm)
                    if not isKnown then
                        matchingAlts = matchingAlts or {}
                        matchingAlts[#matchingAlts + 1] = altData.name or "alt"
                    end
                end
            end
        end
    end

    if matchingAlts and #matchingAlts > 0 then
        return true, matchingAlts
    end
    return false, nil
end

local candidatesBySkill = {}
local spellExistsCache = {}
local entryPool = {}

--- Check if a spell exists in the client spell database (with cache)
--- @param spellID number
--- @return boolean exists
function B.DoesSpellExistCached(spellID)
    if spellExistsCache[spellID] ~= nil then
        return spellExistsCache[spellID]
    end
    local exists = true
    if C_Spell and C_Spell.DoesSpellExist then
        exists = C_Spell.DoesSpellExist(spellID)
    elseif _G.GetSpellInfo then
        exists = (_G.GetSpellInfo(spellID) ~= nil)
    end
    spellExistsCache[spellID] = exists
    return exists
end

--- Get candidate recipes for a given skill line
--- @param skillID number?
--- @return table list
function B.GetCandidatesForSkill(skillID)
    if not skillID then return {} end
    if candidatesBySkill[skillID] then
        return candidatesBySkill[skillID]
    end

    local db = sfui.recipes_camelot
    if not db or not db.recipes then return {} end

    local spellIDs = (db.by_skill and db.by_skill[skillID])
    local candidatesByName = {}

    if spellIDs then
        for _, spellID in ipairs(spellIDs) do
            local r = db.recipes[spellID]
            if r and B.DoesSpellExistCached(spellID) then
                local rReq = r.minSkill or (r.colors and r.colors[1]) or 0
                if rReq <= 320 then
                    local normName = r.name and r.name:lower() or tostring(spellID)
                    local existing = candidatesByName[normName]
                    if not existing or (spellID < existing.id) then
                        candidatesByName[normName] = r
                    end
                end
            end
        end
    else
        for spellID, r in pairs(db.recipes) do
            if r.skillID == skillID and B.DoesSpellExistCached(spellID) then
                local rReq = r.minSkill or (r.colors and r.colors[1]) or 0
                if rReq <= 320 then
                    local normName = r.name and r.name:lower() or tostring(spellID)
                    local existing = candidatesByName[normName]
                    if not existing or (spellID < existing.id) then
                        candidatesByName[normName] = r
                    end
                end
            end
        end
    end

    local list = {}
    for _, r in pairs(candidatesByName) do
        table.insert(list, r)
    end
    candidatesBySkill[skillID] = list
    return list
end

--- Rebuild the filtered list based on current filters
function B.RebuildFilteredList()
    local db = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    if not db or not B.selectedSkillID then
        wipe(B.filteredRecipes)
        return
    end

    local currentRank = B.GetCurrentProfessionRank(B.selectedSkillID)
    local searchPattern = (B.filterText ~= "") and B.filterText:lower():gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") or nil
    local candidates = B.GetCandidatesForSkill(B.selectedSkillID)
    local resultCount = 0

    -- Apply filters (state, seasonal event, spec, hostile source check, source, and search query)
    for _, r in ipairs(candidates) do
        local spellID = r.id
        local isLearned = B.IsRecipeLearned(spellID, r)
        local passState = (B.filterState == "all")
                       or (B.filterState == "learned" and isLearned)
                       or (B.filterState == "unlearned" and not isLearned)

        if passState then
            -- Faction / hostile source check:
            -- If a recipe only has hostile sources (e.g. Alliance recipe on Horde), skip it
            local passHostile = B.HasAnyNonHostileSource(r)

            if passHostile then
                -- Seasonal event filter:
                local eventHoliday = r.event or B.EVENT_RECIPES[spellID]
                local isEvent = (r.isEvent or eventHoliday ~= nil)
                local passEvent = true
                if isEvent and not B.showEventRecipes and not isLearned then
                    if not (eventHoliday and B.IsHolidayActive(eventHoliday)) then
                        passEvent = false
                    end
                end

                if passEvent then
                    -- Current zone filter:
                    local passZone = true
                    if B.showCurrentZoneOnly then
                        passZone = B.RecipeMatchesCurrentZone(r)
                    end

                    if passZone then
                        -- Sub-category / equipment slot filter:
                        local passCategory = true
                        if B.activeCategoryFilter then
                            passCategory = B.RecipeMatchesCategory(r, B.activeCategoryFilter, B.selectedSkillID)
                        end

                        if passCategory then
                            -- Specialization filter:
                            local passSpec = true
                            if B.activeSpecFilter then
                                if B.activeSpecFilter == "general" then
                                    passSpec = (r.spec == nil)
                                else
                                    passSpec = B.RecipeMatchesSpec(r, B.activeSpecFilter)
                                end
                            end

                            if passSpec then
                                local passSource = true
                                if B.HasActiveSourceFilter() then
                                    passSource = false
                                    if B.sourceFilters.vendor and B.RecipeMatchesSource(r, "vendor") then
                                        passSource = true
                                    elseif B.sourceFilters.trainer and B.RecipeMatchesSource(r, "trainer") then
                                        passSource = true
                                    elseif B.sourceFilters.quest and B.RecipeMatchesSource(r, "quest") then
                                        passSource = true
                                    elseif B.sourceFilters.drop and B.RecipeMatchesSource(r, "drop") then
                                        passSource = true
                                    elseif B.sourceFilters.reputation and B.RecipeMatchesSource(r, "reputation") then
                                        passSource = true
                                    elseif B.sourceFilters.limited_stock and B.RecipeMatchesSource(r, "limited_stock") then
                                        passSource = true
                                    elseif B.sourceFilters.alt_unlearned and sfui.recipes.IsAltNeeded and sfui.recipes.IsAltNeeded(r) then
                                        passSource = true
                                    end
                                end

                                if passSource then
                                    local passSearch = true
                                    if searchPattern then
                                        passSearch = false
                                        local rLower = r._lowerName
                                        if not rLower then
                                            rLower = r.name and r.name:lower() or ""
                                            r._lowerName = rLower
                                        end
                                        if rLower:find(searchPattern) then
                                            passSearch = true
                                        else
                                            local sources = r.sources
                                            if (not sources or #sources == 0) and sfui.recipes and sfui.recipes.GetSource then
                                                local res = sfui.recipes.GetSource(r.id)
                                                if res and res.sources and #res.sources > 0 then
                                                    sources = res.sources
                                                end
                                            end
                                            if sources then
                                                for _, s in ipairs(sources) do
                                                    if not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
                                                        local sName = s._lowerName
                                                        if not sName and s.name then
                                                            sName = s.name:lower()
                                                            s._lowerName = sName
                                                        end
                                                        local sZone = s._lowerZone
                                                        if not sZone and s.zone then
                                                            sZone = s.zone:lower()
                                                            s._lowerZone = sZone
                                                        end
                                                        local sDesc = s._lowerDesc
                                                        if not sDesc and s.desc then
                                                            sDesc = s.desc:lower()
                                                            s._lowerDesc = sDesc
                                                        end
                                                        local sFaction = s._lowerFaction
                                                        if not sFaction and s.faction then
                                                            sFaction = s.faction:lower()
                                                            s._lowerFaction = sFaction
                                                        end
                                                        if (sName and sName:find(searchPattern))
                                                        or (sZone and sZone:find(searchPattern))
                                                        or (sDesc and sDesc:find(searchPattern))
                                                        or (sFaction and sFaction:find(searchPattern)) then
                                                            passSearch = true
                                                            break
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end

                                    if passSearch then
                                        local rReq = r.minSkill or (r.colors and r.colors[1]) or 0
                                        resultCount = resultCount + 1
                                        local entry = entryPool[resultCount]
                                        if not entry then
                                            entry = {}
                                            entryPool[resultCount] = entry
                                        end
                                        entry.recipe = r
                                        entry.isLearned = isLearned
                                        entry.canLearn = not isLearned and (rReq <= currentRank)
                                        B.filteredRecipes[resultCount] = entry
                                    end
                                end
                            end
                        end
                    end
                end

            end
        end
    end

    for i = resultCount + 1, #B.filteredRecipes do
        B.filteredRecipes[i] = nil
    end

    -- Sort:
    -- In "unlearned" mode: recipes the player qualifies for now first, then higher req
    -- In "all" and "learned" modes: sorted by minSkill ascending, then alphabetical by name
    table.sort(B.filteredRecipes, function(a, b)
        if B.filterState == "unlearned" then
            if a.canLearn ~= b.canLearn then
                return a.canLearn -- currently ready to learn first
            end
        end
        local skA = a.recipe.minSkill or (a.recipe.colors and a.recipe.colors[1]) or 0
        local skB = b.recipe.minSkill or (b.recipe.colors and b.recipe.colors[1]) or 0
        if skA ~= skB then
            return skA < skB
        end
        return (a.recipe.name or "") < (b.recipe.name or "")
    end)

    if B.ui.statusText then
        local withWaypoints = 0
        local learnableNow = 0
        for _, entry in ipairs(B.filteredRecipes) do
            if entry.canLearn then
                learnableNow = learnableNow + 1
            end
            if entry.recipe.sources then
                for _, s in ipairs(entry.recipe.sources) do
                    if s.mapID and s.x and s.y then
                        withWaypoints = withWaypoints + 1
                        break
                    end
                end
            end
        end

        local profName = "profession"
        for _, p in ipairs(B.playerProfessions) do
            if p.skillID == B.selectedSkillID then
                profName = p.name
                break
            end
        end

        local countStr = string.format("%d recipes (%s)", #B.filteredRecipes, B.filterState)
        if B.activeSpecFilter then
            countStr = countStr .. " · |cffffa500spec: " .. (B.activeSpecFilter == "general" and "general" or B.activeSpecFilter) .. "|r"
        end
        if B.HasActiveSourceFilter() then
            local activeSrcList = {}
            if B.sourceFilters.vendor then table.insert(activeSrcList, "vendor") end
            if B.sourceFilters.trainer then table.insert(activeSrcList, "trainer") end
            if B.sourceFilters.quest then table.insert(activeSrcList, "quest") end
            if B.sourceFilters.drop then table.insert(activeSrcList, "drop") end
            if B.sourceFilters.reputation then table.insert(activeSrcList, "reputation") end
            if B.sourceFilters.limited_stock then table.insert(activeSrcList, "limited stock") end
            countStr = countStr .. " · |cffffd100" .. table.concat(activeSrcList, ", ") .. "|r"
        end
        if not B.showEventRecipes then
            countStr = countStr .. " · |cff888888events hidden|r"
        end
        if B.showCurrentZoneOnly then
            countStr = countStr .. " · |cff80c0ffcurrent zone only|r"
        end
        if B.activeCategoryFilter then
            countStr = countStr .. " · |cffffa500category: " .. B.activeCategoryFilter .. "|r"
        end
        if learnableNow > 0 and B.filterState == "unlearned" then
            countStr = countStr .. string.format(" · |cff40c040%d ready to learn now|r", learnableNow)
        end
        if withWaypoints > 0 then
            countStr = countStr .. string.format(" · |cff80c0ff%d with waypoints|r", withWaypoints)
        end
        B.ui.statusText:SetText(countStr)
    end

    if B.UpdateProgressBar then
        B.UpdateProgressBar()
    end
end

-- ─── Cache Invalidation on Trade Skill / Learning Events ─────────────────────
if sfui.events and sfui.events.RegisterEvent then
    local function InvalidateLearnedCache()
        wipe(isLearnedCache)
        if B.ui and B.ui.frame and B.ui.frame:IsShown() then
            B.RebuildFilteredList()
            B.UpdateList()
        end
    end
    sfui.events.RegisterEvent("CHAT_MSG_SKILL", InvalidateLearnedCache)
    sfui.events.RegisterEvent("TRADE_SKILL_SHOW", InvalidateLearnedCache)
    sfui.events.RegisterEvent("SKILL_LINES_CHANGED", InvalidateLearnedCache)
    sfui.events.RegisterEvent("CRAFT_SHOW", InvalidateLearnedCache)
    sfui.events.RegisterEvent("SPELLS_CHANGED", InvalidateLearnedCache)
end
