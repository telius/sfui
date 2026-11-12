local addonName, addon = ...
sfui = sfui or {}
sfui.find = sfui.find or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/find.lua
--  Universal Omnibox & Command Palette (/sf find, /sffind)
--  Searches options, commands, layout profiles, dungeons, bosses, loot, quests,
--  recipes, fishing species/waters, and synced/account alts.
-- ══════════════════════════════════════════════════════════════════════════════

local _G = _G
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local tostring = _G.tostring
local tonumber = _G.tonumber
local string_lower = string.lower
local string_format = string.format
local table_sort = table.sort
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local wipe = _G.wipe or function(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

local F = sfui.find
local common = sfui.common
local theme = sfui.theme

local findFrame = nil
local staticIndex = nil
local pendingLootItems = nil -- array of { itemID, dungeonID, dungeonName, bossName } awaiting GetItemInfo cache
local dynamicEntries = {}
local matchedResults = {}
local selectedIndex = 1
local scrollOffset = 0

local VISIBLE_ROWS = 10
local ROW_H = 30
local MAX_RESULTS = 60

local CATEGORY_COLORS = {
    command = { 1.00, 0.55, 1.00 },
    option  = { 0.45, 0.82, 1.00 },
    layout  = { 0.35, 1.00, 0.75 },
    dungeon = { 0.85, 0.68, 0.32 },
    boss    = { 1.00, 0.48, 0.38 },
    loot    = { 0.78, 0.52, 1.00 },
    quest   = { 1.00, 0.85, 0.28 },
    recipe  = { 1.00, 0.72, 0.30 },
    fishing = { 0.30, 0.85, 1.00 },
    alt     = { 0.60, 0.95, 0.55 },
}

local OPTION_KEYWORDS = {
    main         = "general scale font ui reload profile",
    theme        = "colors palette style modern camelot oldgod maw necrolord fallensanctum",
    automation   = "auto repair selljunk gossip resurrection summon release",
    bars         = "unitframes health power player target resource",
    actionbars   = "bars keybind paging mouseover movers buttons",
    classutility = "totems class utility tracker",
    portals      = "teleports hearthstone mage wormhole",
    ring         = "radial wheel quickdraw slices markers utility specs",
    buffs        = "reminders missing buffs blessings auras consumables food flask weapon oil",
    castbars     = "castbar interrupt latency empower",
    combattext   = "scrolling combat text floating damage healing",
    currency     = "gold tokens badges honor arena",
    fishing      = "pole bobber double click lure session hud auto fish",
    gear         = "auto equip highest ilvl stat weights role pawn",
    lootfeed     = "loot toast upgrades wishlist roll",
    experience   = "xp bar reputation rested challenges",
    merchant     = "vendor buy reagents filter junk",
    minimap      = "map square pins clock coords",
    objectives   = "quest tracker mythic scenario achievements",
    pets         = "hunter warlock pet bar mend feed",
    recipes      = "professions crafting reagents pinned browser",
    research     = "talent research order hall",
    sync         = "multibox peers follow quest reward trade wishlist",
    hide         = "blizzard frames clutter hide",
    debug        = "diagnostics errors memory cpu profiler",
}

local function safe_lower(v)
    if v == nil then return "" end
    return string_lower(tostring(v))
end

local function make_entry(cat, title, subtitle, icon, action, itemID, extraKeywords, baseBoost)
    local tLow = safe_lower(title)
    local sLow = safe_lower(subtitle)
    local kLow = safe_lower(extraKeywords)
    return {
        cat      = cat,
        title    = tLow,
        subtitle = sLow,
        icon     = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        action   = action,
        itemID   = itemID,
        boost    = baseBoost or 0,
        search   = cat .. " " .. tLow .. " " .. sLow .. " " .. kLow,
    }
end

local function resolve_pending_loot_items()
    if not pendingLootItems or #pendingLootItems == 0 or not staticIndex then return end
    local writeIdx = 0
    for i = 1, #pendingLootItems do
        local p = pendingLootItems[i]
        local name, _, _, _, _, _, _, _, _, icon = common.get_item_info(p.itemID)
        if name and name ~= "" then
            local dID, bName = p.dungeonID, p.bossName
            staticIndex[#staticIndex + 1] = make_entry(
                "loot",
                name,
                safe_lower(bName) .. " · " .. safe_lower(p.dungeonName),
                icon or (common.get_item_icon and common.get_item_icon(p.itemID)) or "Interface\\Icons\\INV_Misc_Bag_08",
                function()
                    if sfui.nav and sfui.nav.OpenDungeon then
                        sfui.nav.OpenDungeon(dID, "bosses", bName)
                    end
                end,
                p.itemID,
                tostring(p.itemID),
                -2
            )
        else
            writeIdx = writeIdx + 1
            pendingLootItems[writeIdx] = p
        end
    end
    for i = #pendingLootItems, writeIdx + 1, -1 do
        pendingLootItems[i] = nil
    end
end

local function build_static_index()
    if staticIndex then
        resolve_pending_loot_items()
        return staticIndex
    end

    staticIndex = {}
    pendingLootItems = {}

    -- 1. Core SFUI Quick Commands & Windows
    staticIndex[#staticIndex + 1] = make_entry("command", "edit mode (unlock / lock movers)", "/sf edit · drag hud frames & layout profiles", "Interface\\Icons\\INV_Gizmo_02", function()
        if sfui.movers and sfui.movers.Toggle then
            sfui.movers.Toggle()
        end
    end, nil, "move movers unlock lock layout grid snap", 25)

    staticIndex[#staticIndex + 1] = make_entry("command", "tracking manager (cdm buffs & bars)", "configure tracked cooldowns, buffs & bars", "Interface\\Icons\\Spell_Holy_BorrowedTime", function()
        if sfui.trackedoptions and sfui.trackedoptions.toggle_viewer then
            sfui.trackedoptions.toggle_viewer()
        end
    end, nil, "tracked icons tracked bars cooldown viewer", 22)

    staticIndex[#staticIndex + 1] = make_entry("command", "alts & account inventory", "inspect characters, professions, bags & banks", "Interface\\Icons\\Achievement_Character_Human_Male", function()
        if sfui.nav and sfui.nav.OpenAlts then
            sfui.nav.OpenAlts()
        end
    end, nil, "characters bank gold professions", 22)

    staticIndex[#staticIndex + 1] = make_entry("command", "mail routing configuration", "/sf mail · configure alt mail rules & presets", "Interface\\Icons\\INV_Letter_15", function()
        if sfui.alts and sfui.alts.ToggleMailConfig then
            sfui.alts.ToggleMailConfig()
        end
    end, nil, "mailbox postal send mats boe", 18)

    if not sfui.isRetail and sfui.dungeonjournal then
        staticIndex[#staticIndex + 1] = make_entry("command", "dungeon journal", "open maps, bosses, loot & dungeon quests", "Interface\\Icons\\INV_Misc_Book_09", function()
            sfui.dungeonjournal.Toggle()
        end, nil, "atlas lootviewer instances raids wishlist", 24)
    elseif sfui.isRetail and sfui.lootviewer and sfui.lootviewer.Toggle then
        staticIndex[#staticIndex + 1] = make_entry("command", "loot browser", "open retail encounter loot viewer", "Interface\\Icons\\INV_Misc_Book_09", function()
            sfui.lootviewer.Toggle()
        end, nil, "dungeon journal loot", 24)
    end

    if not sfui.isRetail and sfui.recipes and sfui.recipes.ToggleBrowser then
        staticIndex[#staticIndex + 1] = make_entry("command", "recipe browser", "/sf recipes · browse profession recipes & sources", "Interface\\Icons\\INV_Scroll_03", function()
            sfui.recipes.ToggleBrowser()
        end, nil, "crafting professions patterns plans schematics", 23)
    end

    if not sfui.isRetail and sfui.fishing and sfui.fishing.atlas and sfui.fishing.atlas.Toggle then
        staticIndex[#staticIndex + 1] = make_entry("command", "fishing atlas", "/sf atlas · browse fish species, zones & logbook", "Interface\\Icons\\INV_Misc_Fish_02", function()
            sfui.fishing.atlas.Toggle()
        end, nil, "waters anglers catch", 21)
    end

    if sfui.portals and sfui.portals.Toggle then
        staticIndex[#staticIndex + 1] = make_entry("command", "portals & teleports", "/sf portals · hearthstones, mage portals & toys", "Interface\\Icons\\Spell_Arcane_PortalStormwind", function()
            sfui.portals.Toggle()
        end, nil, "teleport tp wormhole", 20)
    end

    staticIndex[#staticIndex + 1] = make_entry("command", "sync all multibox peers now", "/sf sync now · broadcast full state to peers", "Interface\\Icons\\Spell_Shadow_MindTwisting", function()
        if sfui.sync and sfui.sync.SyncAllNow then sfui.sync.SyncAllNow() end
    end, nil, "multibox sync broadcast", 14)

    staticIndex[#staticIndex + 1] = make_entry("command", "form synced party", "/sf party · invite paired multibox characters", "Interface\\Icons\\Spell_Holy_PrayerOfSpirit", function()
        if sfui.sync and sfui.sync.FormSyncedParty then sfui.sync.FormSyncedParty() end
    end, nil, "invite group multibox", 14)

    staticIndex[#staticIndex + 1] = make_entry("command", "memory & diagnostics (/sfmem)", "print sfui module memory & pool telemetry", "Interface\\Icons\\INV_Gizmo_01", function()
        if sfui.mem and sfui.mem.HandleSlash then sfui.mem.HandleSlash("") end
    end, nil, "gc cpu benchmark debug", 12)

    -- 2. Dungeons, Raids, Bosses, Loot & Dungeon Quests (Classic / Camelot)
    local djData = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if djData then
        local seenLoot = {}
        local lists = {
            { items = djData.dungeons or {}, kind = "dungeon" },
            { items = djData.raids or {},    kind = "raid" },
        }
        for _, grp in ipairs(lists) do
            for _, d in ipairs(grp.items) do
                local dID = d.id
                local dName = d.name or dID or "dungeon"
                local lvlStr = d.level and ("lvl " .. tostring(d.level)) or grp.kind
                staticIndex[#staticIndex + 1] = make_entry(
                    "dungeon",
                    dName,
                    grp.kind .. " · " .. lvlStr,
                    "Interface\\Icons\\INV_Misc_Map_01",
                    function()
                        if sfui.nav and sfui.nav.OpenDungeon then
                            sfui.nav.OpenDungeon(dID, "map")
                        end
                    end,
                    nil,
                    tostring(dID or ""),
                    10
                )

                for _, boss in ipairs(d.bosses or {}) do
                    local bName = boss.name
                    if bName and bName ~= "" then
                        staticIndex[#staticIndex + 1] = make_entry(
                            "boss",
                            bName,
                            dName,
                            "Interface\\Icons\\Ability_Creature_Cursed_02",
                            function()
                                if sfui.nav and sfui.nav.OpenDungeon then
                                    sfui.nav.OpenDungeon(dID, "bosses", bName)
                                end
                            end,
                            nil,
                            "",
                            6
                        )

                        for _, rawItem in ipairs(boss.items or {}) do
                            local itemID = tonumber(type(rawItem) == "table" and (rawItem.id or rawItem[1]) or rawItem)
                            if itemID and not seenLoot[itemID] then
                                seenLoot[itemID] = true
                                local iName, _, _, _, _, _, _, _, _, iIcon = common.get_item_info(itemID)
                                if iName and iName ~= "" then
                                    staticIndex[#staticIndex + 1] = make_entry(
                                        "loot",
                                        iName,
                                        safe_lower(bName) .. " · " .. safe_lower(dName),
                                        iIcon or (common.get_item_icon and common.get_item_icon(itemID)) or "Interface\\Icons\\INV_Misc_Bag_08",
                                        function()
                                            if sfui.nav and sfui.nav.OpenDungeon then
                                                sfui.nav.OpenDungeon(dID, "bosses", bName)
                                            end
                                        end,
                                        itemID,
                                        tostring(itemID),
                                        -2
                                    )
                                else
                                    pendingLootItems[#pendingLootItems + 1] = {
                                        itemID      = itemID,
                                        dungeonID   = dID,
                                        dungeonName = dName,
                                        bossName    = bName,
                                    }
                                end
                            end
                        end
                    end
                end

                for _, q in ipairs(d.quests or {}) do
                    if q.name and q.name ~= "" then
                        local qID = q.id
                        staticIndex[#staticIndex + 1] = make_entry(
                            "quest",
                            q.name,
                            dName .. (q.level and (" · lvl " .. tostring(q.level)) or ""),
                            "Interface\\GossipFrame\\AvailableQuestIcon",
                            function()
                                if sfui.nav and sfui.nav.OpenDungeon then
                                    sfui.nav.OpenDungeon(dID, "quests", qID)
                                end
                            end,
                            nil,
                            tostring(qID or ""),
                            4
                        )
                    end
                end
            end
        end
    end

    -- 3. Profession Recipes (Classic / Camelot)
    local rdb = sfui.recipes_camelot
    if rdb then
        local SKILL_NAMES = {
            [129] = "first aid",
            [164] = "blacksmithing",
            [165] = "leatherworking",
            [171] = "alchemy",
            [185] = "cooking",
            [197] = "tailoring",
            [202] = "engineering",
            [333] = "enchanting",
            [356] = "fishing",
            [755] = "jewelcrafting",
            [773] = "inscription",
        }
        if type(rdb._raw) == "table" then
            for spellID, raw in pairs(rdb._raw) do
                local rName = type(raw) == "table" and raw[1]
                if rName and rName ~= "" then
                    local sID = spellID
                    local skillID = tonumber(raw[2])
                    local minSkill = tonumber(raw[3])
                    local outItem = tonumber(raw[5])
                    if outItem and outItem <= 0 then outItem = nil end
                    local recItem = tonumber(raw[6])
                    if recItem and recItem <= 0 then recItem = nil end
                    local iconItem = outItem or recItem
                    local prof = (skillID and SKILL_NAMES[skillID]) or "profession"
                    local icon = (iconItem and common.get_item_icon and common.get_item_icon(iconItem))
                        or (common.get_spell_icon and common.get_spell_icon(sID))
                        or "Interface\\Icons\\INV_Scroll_03"
                    staticIndex[#staticIndex + 1] = make_entry(
                        "recipe",
                        rName,
                        prof .. ((minSkill and minSkill > 0) and (" · skill " .. tostring(minSkill)) or ""),
                        icon,
                        function()
                            if sfui.nav and sfui.nav.OpenRecipe then
                                sfui.nav.OpenRecipe(sID)
                            end
                        end,
                        iconItem,
                        tostring(sID),
                        0
                    )
                end
            end
        elseif type(rdb.IterateRecipes) == "function" then
            for spellID, r in rdb.IterateRecipes() do
                if type(r) == "table" and r.name and r.name ~= "" then
                    local sID = spellID
                    local outItem = tonumber(r.output or r.itemID or r.createdItemID or r.recipeItemID)
                    if outItem and outItem <= 0 then outItem = nil end
                    local prof = (r.skillID and SKILL_NAMES[r.skillID]) or r.profession or "profession"
                    local minSkill = r.minSkill or r.skill
                    local icon = (outItem and common.get_item_icon and common.get_item_icon(outItem))
                        or (common.get_spell_icon and common.get_spell_icon(sID))
                        or "Interface\\Icons\\INV_Scroll_03"
                    staticIndex[#staticIndex + 1] = make_entry(
                        "recipe",
                        r.name,
                        safe_lower(prof) .. (minSkill and (" · skill " .. tostring(minSkill)) or ""),
                        icon,
                        function()
                            if sfui.nav and sfui.nav.OpenRecipe then
                                sfui.nav.OpenRecipe(sID)
                            end
                        end,
                        outItem,
                        tostring(sID),
                        0
                    )
                end
            end
        end
    end

    -- 4. Fishing Species & Waters
    local fData = sfui.fishing_data
    if fData then
        if fData.GetAllSpecies and fData.GetSpeciesDisplay then
            local allSpecies = fData.GetAllSpecies() or {}
            for itemID, sp in pairs(allSpecies) do
                local sName, sTex = fData.GetSpeciesDisplay(itemID, false)
                if sName and sName ~= "" then
                    local id = itemID
                    staticIndex[#staticIndex + 1] = make_entry(
                        "fishing",
                        sName,
                        "fish species · min skill " .. tostring(sp.minSkill or 1),
                        sTex or "Interface\\Icons\\INV_Misc_Fish_02",
                        function()
                            if sfui.nav and sfui.nav.OpenFishingSpecies then
                                sfui.nav.OpenFishingSpecies(id)
                            end
                        end,
                        id,
                        tostring(id),
                        0
                    )
                end
            end
        end
        if fData.GetAllWaters and fData.GetZoneName then
            local waters = fData.GetAllWaters() or {}
            for _, w in ipairs(waters) do
                local zName = fData.GetZoneName(w.mapID)
                if zName and zName ~= "" then
                    local mID = w.mapID
                    staticIndex[#staticIndex + 1] = make_entry(
                        "fishing",
                        zName,
                        "fishing waters · skill " .. tostring(w.fishingLevel or w.minSkill or 1),
                        "Interface\\Icons\\Spell_Frost_Stun",
                        function()
                            if sfui.nav and sfui.nav.OpenFishingWater then
                                sfui.nav.OpenFishingWater(mID)
                            end
                        end,
                        nil,
                        "water zone",
                        2
                    )
                end
            end
        end
    end

    return staticIndex
end

local function rebuild_dynamic_entries()
    wipe(dynamicEntries)

    -- 1. Registered Options Tabs
    if sfui.options and sfui.options.GetRegisteredTabs then
        local tabs = sfui.options.GetRegisteredTabs()
        for _, tabDef in ipairs(tabs) do
            local tabID = tabDef.id
            if tabID then
                local label = tabDef.label or tabDef.title or tabDef.name or tabID
                local icon = (sfui.options.GetTabIcon and sfui.options.GetTabIcon(tabID)) or "Interface\\Icons\\INV_Misc_Gear_01"
                local kw = OPTION_KEYWORDS[tabID] or ""
                dynamicEntries[#dynamicEntries + 1] = make_entry(
                    "option",
                    "options: " .. safe_lower(label),
                    "/sf " .. safe_lower(tabID),
                    icon,
                    function()
                        if sfui.nav and sfui.nav.OpenOption then
                            sfui.nav.OpenOption(tabID)
                        end
                    end,
                    nil,
                    tabID .. " " .. kw,
                    20
                )
            end
        end
    end

    -- 2. Contextual Fishing Weapon Restore
    if sfui.fishing and ((sfui.fishing.IsPoleEquipped and sfui.fishing.IsPoleEquipped()) or (sfui.fishing.HasSavedWeapons and sfui.fishing.HasSavedWeapons())) then
        dynamicEntries[#dynamicEntries + 1] = make_entry(
            "command",
            "restore combat weapons",
            "reequip saved main-hand / off-hand weapons after fishing",
            "Interface\\Icons\\INV_Sword_04",
            function()
                if sfui.fishing and sfui.fishing.RestoreWeapons then
                    sfui.fishing.RestoreWeapons()
                end
            end,
            nil,
            "fishing pole swap weapon",
            35
        )
    end

    -- 3. Named Mover Layout Profiles
    if sfui.movers and sfui.movers.GetProfileNames then
        local names = sfui.movers.GetProfileNames()
        local activeProf = sfui.movers.GetActiveProfileName and sfui.movers.GetActiveProfileName()
        for _, pName in ipairs(names) do
            local targetName = pName
            local isActive = (activeProf == targetName)
            dynamicEntries[#dynamicEntries + 1] = make_entry(
                "layout",
                "layout profile: " .. safe_lower(targetName) .. (isActive and " (active)" or ""),
                "apply saved hud mover positions",
                "Interface\\Icons\\INV_Gizmo_02",
                function()
                    if sfui.movers and sfui.movers.LoadProfile then
                        sfui.movers.LoadProfile(targetName)
                    end
                end,
                nil,
                "profile movers hud",
                isActive and 12 or 15
            )
        end
        if sfui.sync and sfui.movers.BroadcastActiveLayout then
            dynamicEntries[#dynamicEntries + 1] = make_entry(
                "layout",
                "sync active layout profile to peers",
                "broadcast current mover layout over multibox sync",
                "Interface\\Icons\\Spell_Shadow_MindTwisting",
                function()
                    sfui.movers.BroadcastActiveLayout()
                end,
                nil,
                "broadcast movers profile multibox",
                11
            )
        end
    end

    -- 4. Account Alts
    local altsDB = _G.SfuiDB and _G.SfuiDB.alts
    if type(altsDB) == "table" then
        for _, alt in pairs(altsDB) do
            if type(alt) == "table" and alt.name then
                local lvl = alt.level and ("lvl " .. tostring(alt.level)) or ""
                local cls = safe_lower(alt.class or "")
                local rlm = safe_lower(alt.realm or "")
                dynamicEntries[#dynamicEntries + 1] = make_entry(
                    "alt",
                    safe_lower(alt.name),
                    lvl .. (cls ~= "" and (" · " .. cls) or "") .. (rlm ~= "" and (" · " .. rlm) or ""),
                    "Interface\\Icons\\Achievement_Character_Human_Male",
                    function()
                        if sfui.nav and sfui.nav.OpenAlts then
                            sfui.nav.OpenAlts()
                        end
                    end,
                    nil,
                    "character bank bags",
                    8
                )
            end
        end
    end
end

local queryTokens = {}

local function score_entry(entry, rawQuery)
    if rawQuery == "" then
        -- Empty query: show high-utility commands, options, and layouts first
        if entry.cat == "command" or entry.cat == "option" or entry.cat == "layout" then
            return 100 + (entry.boost or 0)
        end
        return nil
    end

    for i = 1, #queryTokens do
        local tok = queryTokens[i]
        if not entry.search:find(tok, 1, true) then
            return nil
        end
    end

    local score = entry.boost or 0
    if entry.title == rawQuery then
        score = score + 120
    elseif entry.title:sub(1, #rawQuery) == rawQuery then
        score = score + 80
    elseif entry.title:find(rawQuery, 1, true) then
        score = score + 45
    end
    if entry.cat == queryTokens[1] then
        score = score + 30
    end
    return score
end

local scoredPool = {}

local function run_search(queryText)
    local base = build_static_index()
    local q = safe_lower(queryText or ""):gsub("^%s+", ""):gsub("%s+$", "")

    wipe(queryTokens)
    if q ~= "" then
        for tok in q:gmatch("%S+") do
            queryTokens[#queryTokens + 1] = tok
        end
    end

    local count = 0
    local function consider(entry)
        local sc = score_entry(entry, q)
        if sc then
            count = count + 1
            local slot = scoredPool[count]
            if not slot then
                slot = {}
                scoredPool[count] = slot
            end
            slot.entry = entry
            slot.score = sc
        end
    end

    for i = 1, #dynamicEntries do
        consider(dynamicEntries[i])
    end
    for i = 1, #base do
        consider(base[i])
    end

    -- Trim active slice for sorting
    for i = count + 1, #scoredPool do
        scoredPool[i] = nil
    end

    table_sort(scoredPool, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return a.entry.title < b.entry.title
    end)

    wipe(matchedResults)
    local limit = math_min(count, MAX_RESULTS)
    for i = 1, limit do
        matchedResults[i] = scoredPool[i].entry
    end

    selectedIndex = (limit > 0) and 1 or 0
    scrollOffset = 0
    return count
end

local function RefreshRows()
    if not findFrame then return end
    local total = #matchedResults

    if selectedIndex > total then selectedIndex = total end
    if selectedIndex < 1 and total > 0 then selectedIndex = 1 end

    if selectedIndex > 0 then
        if selectedIndex <= scrollOffset then
            scrollOffset = selectedIndex - 1
        elseif selectedIndex > scrollOffset + VISIBLE_ROWS then
            scrollOffset = selectedIndex - VISIBLE_ROWS
        end
    else
        scrollOffset = 0
    end

    local maxOffset = math_max(0, total - VISIBLE_ROWS)
    if scrollOffset > maxOffset then scrollOffset = maxOffset end
    if scrollOffset < 0 then scrollOffset = 0 end

    for r = 1, VISIBLE_ROWS do
        local row = findFrame.rows[r]
        local idx = scrollOffset + r
        local entry = matchedResults[idx]
        if entry then
            row.entry = entry
            row.index = idx
            local isSel = (idx == selectedIndex)

            row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.titleFs:SetText(entry.title)
            row.subFs:SetText(entry.subtitle or "")

            local catCol = CATEGORY_COLORS[entry.cat] or { 0.75, 0.75, 0.80 }
            row.badgeFs:SetText("[" .. entry.cat .. "]")
            row.badgeFs:SetTextColor(catCol[1], catCol[2], catCol[3], 1)

            if isSel then
                row:SetBackdropColor(0.20, 0.16, 0.28, 0.92)
                row:SetBackdropBorderColor(catCol[1], catCol[2], catCol[3], 0.85)
                row.titleFs:SetTextColor(1, 1, 1, 1)
            else
                row:SetBackdropColor(0.08, 0.08, 0.11, 0.72)
                row:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.65)
                row.titleFs:SetTextColor(0.90, 0.90, 0.92, 1)
            end
            row:Show()
        else
            row.entry = nil
            row.index = nil
            row:Hide()
        end
    end

    if findFrame.emptyFs then
        findFrame.emptyFs:SetShown(total == 0)
    end
    if findFrame.statusFs then
        if total == 0 then
            findFrame.statusFs:SetText("no matching entries")
        else
            findFrame.statusFs:SetText(string_format("%d/%d · up/down select · enter open · esc close", selectedIndex, total))
        end
    end
end

local function ExecuteEntry(entry)
    if not entry then return end
    if _G.IsShiftKeyDown and _G.IsShiftKeyDown() and entry.itemID and common and common.insert_link_to_chat then
        local _, link = common.get_item_info(entry.itemID)
        if link and common.insert_link_to_chat(link) then
            return
        end
    end
    if findFrame then
        findFrame:Hide()
    end
    if entry.action then
        entry.action()
    end
end

local function MoveSelection(delta)
    local total = #matchedResults
    if total == 0 then return end
    selectedIndex = selectedIndex + delta
    if selectedIndex < 1 then
        selectedIndex = total
    elseif selectedIndex > total then
        selectedIndex = 1
    end
    RefreshRows()
end

local function CreateFindFrame()
    if findFrame then return findFrame end

    local f = CreateFrame("Frame", "SfuiFindFrame", UIParent, "BackdropTemplate")
    findFrame = f
    f:SetSize(540, 396)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    if common and common.register_special_frame then
        common.register_special_frame(f)
    end

    if theme and theme.ApplyWindowStyle then
        theme.ApplyWindowStyle(f)
    elseif common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(f, { 0.06, 0.06, 0.09, 0.96 }, { 0.45, 0.25, 0.75, 0.90 })
    end

    if theme and theme.CreateWindowHeader then
        theme.CreateWindowHeader(f, "sfui find", 220)
    else
        local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
        hdr:SetText("sfui find")
        hdr:SetTextColor(1, 0.82, 0, 1)
    end

    local closeBtn
    if common and common.create_close_button then
        closeBtn = common.create_close_button(f, function() f:Hide() end, 22)
    else
        closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
    end
    closeBtn:ClearAllPoints()
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    if f.headerBar then
        closeBtn:SetFrameLevel(f.headerBar:GetFrameLevel() + 5)
    end

    -- Search Input Box
    local searchWrap = CreateFrame("Frame", nil, f, "BackdropTemplate")
    searchWrap:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
    searchWrap:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
    searchWrap:SetHeight(28)
    if common and common.apply_flat_backdrop then
        common.apply_flat_backdrop(searchWrap, { 0.04, 0.04, 0.06, 0.95 }, { 0.32, 0.32, 0.40, 0.90 })
    end

    local magTex = searchWrap:CreateTexture(nil, "ARTWORK")
    magTex:SetSize(14, 14)
    magTex:SetPoint("LEFT", searchWrap, "LEFT", 8, 0)
    magTex:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    magTex:SetVertexColor(0.7, 0.7, 0.8, 0.9)

    local eb = CreateFrame("EditBox", nil, searchWrap)
    f.editBox = eb
    eb:SetPoint("LEFT", magTex, "RIGHT", 6, 0)
    eb:SetPoint("RIGHT", searchWrap, "RIGHT", -8, 0)
    eb:SetHeight(24)
    eb:SetFontObject("GameFontHighlight")
    eb:SetAutoFocus(false)

    local placeholder = searchWrap:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.placeholder = placeholder
    placeholder:SetPoint("LEFT", eb, "LEFT", 2, 0)
    placeholder:SetText("search options, commands, dungeons, bosses, loot, quests, recipes, fish, alts...")
    placeholder:SetTextColor(0.48, 0.48, 0.54, 1)

    eb:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        placeholder:SetShown(txt == "")
        run_search(txt)
        RefreshRows()
    end)

    eb:SetScript("OnEnterPressed", function()
        local entry = matchedResults[selectedIndex]
        if entry then
            ExecuteEntry(entry)
        end
    end)

    eb:SetScript("OnEscapePressed", function(self)
        local txt = self:GetText() or ""
        if txt ~= "" then
            self:SetText("")
        else
            f:Hide()
        end
    end)

    eb:SetScript("OnTabPressed", function()
        if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
            MoveSelection(-1)
        else
            MoveSelection(1)
        end
    end)

    eb:SetScript("OnKeyDown", function(_, key)
        if key == "DOWN" then
            MoveSelection(1)
        elseif key == "UP" then
            MoveSelection(-1)
        elseif key == "PAGEDOWN" then
            MoveSelection(VISIBLE_ROWS)
        elseif key == "PAGEUP" then
            MoveSelection(-VISIBLE_ROWS)
        end
    end)
    if eb.SetPropagateKeyboardInput then
        -- Keep typing exclusively inside the focused EditBox
        eb:SetPropagateKeyboardInput(false)
    end

    f:SetScript("OnMouseWheel", function(_, delta)
        if delta < 0 then
            scrollOffset = math_min(math_max(0, #matchedResults - VISIBLE_ROWS), scrollOffset + 2)
        else
            scrollOffset = math_max(0, scrollOffset - 2)
        end
        RefreshRows()
    end)

    -- Rows Container
    f.rows = {}
    local startY = -70
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, f, "BackdropTemplate")
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, startY - ((i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, startY - ((i - 1) * ROW_H))
        row:SetHeight(ROW_H - 2)
        if common and common.apply_flat_backdrop then
            common.apply_flat_backdrop(row, { 0.08, 0.08, 0.11, 0.72 }, { 0.20, 0.20, 0.25, 0.65 })
        end

        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(20, 20)
        ico:SetPoint("LEFT", row, "LEFT", 6, 0)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = ico

        local badgeFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        badgeFs:SetJustifyH("RIGHT")
        row.badgeFs = badgeFs

        local titleFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        titleFs:SetPoint("LEFT", ico, "RIGHT", 8, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        row.titleFs = titleFs

        local subFs = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        subFs:SetPoint("LEFT", titleFs, "RIGHT", 8, 0)
        subFs:SetPoint("RIGHT", badgeFs, "LEFT", -8, 0)
        subFs:SetJustifyH("LEFT")
        subFs:SetWordWrap(false)
        subFs:SetTextColor(0.58, 0.58, 0.64, 1)
        row.subFs = subFs

        row:SetScript("OnEnter", function(self)
            if self.index then
                selectedIndex = self.index
                RefreshRows()
            end
            if self.entry and self.entry.itemID and _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                _G.GameTooltip:SetItemByID(self.entry.itemID)
                _G.GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            if _G.GameTooltip then _G.GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            if self.entry then
                ExecuteEntry(self.entry)
            end
        end)

        f.rows[i] = row
    end

    local emptyFs = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.emptyFs = emptyFs
    emptyFs:SetPoint("CENTER", f, "CENTER", 0, -10)
    emptyFs:SetText("no matching sfui results.")
    emptyFs:Hide()

    local statusFs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.statusFs = statusFs
    statusFs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 7)
    statusFs:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 7)
    statusFs:SetJustifyH("RIGHT")
    statusFs:SetTextColor(0.55, 0.55, 0.62, 1)

    f:SetScript("OnShow", function()
        rebuild_dynamic_entries()
        local curTxt = eb:GetText() or ""
        run_search(curTxt)
        RefreshRows()
        eb:SetFocus()
        eb:HighlightText()
    end)

    f:Hide()
    return f
end

function F.Open(initialQuery)
    local f = CreateFindFrame()
    if initialQuery ~= nil then
        f.editBox:SetText(safe_lower(initialQuery))
    end
    if not f:IsShown() then
        f:Show()
    else
        rebuild_dynamic_entries()
        run_search(f.editBox:GetText() or "")
        RefreshRows()
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end
end

function F.Close()
    if findFrame and findFrame:IsShown() then
        findFrame:Hide()
    end
end

function F.Toggle(initialQuery)
    if initialQuery and initialQuery ~= "" then
        F.Open(initialQuery)
        return
    end
    local f = CreateFindFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

if sfui.events and sfui.events.RegisterMessage then
    sfui.events.RegisterMessage("SFUI_THEME_CHANGED", function()
        if findFrame and theme and theme.ApplyWindowStyle then
            theme.ApplyWindowStyle(findFrame)
            if findFrame.headerBar and theme.ApplyHeaderStyle then
                theme.ApplyHeaderStyle(findFrame.headerBar, "sfui find")
            end
        end
    end)
end

local _findDebug = {}
function sfui.find_debug_info()
    _findDebug.isCreated   = (findFrame ~= nil)
    _findDebug.isShown     = (findFrame ~= nil and findFrame:IsShown() == true)
    _findDebug.staticCount = staticIndex and #staticIndex or 0
    _findDebug.dynCount    = #dynamicEntries
    _findDebug.results     = #matchedResults
    return _findDebug
end

