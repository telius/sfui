local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.sync = sfui.sync or {}
sfui.sync.merge = sfui.sync.merge or {}

local merge = sfui.sync.merge

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/sync/merge.lua
--  Content-Only CRDT / Timestamp Merger for Multi-Account Synchronization
--
--  Strictly syncs content modules only:
--    1. SfuiDB.alts[guid]
--    2. SfuiDB.recipes[itemID][realm][guid]
--    3. SfuiDB.contacts & SfuiDB.recipe_finds
--    4. SfuiDB.fishing.chars[guid] (+ aggregate rebuild)
--    5. SfuiDB.altMailRouting.routes[guid]
--  Never touches UI layout, frame positions, or visual settings.
-- ══════════════════════════════════════════════════════════════════════════════

local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local tonumber = _G.tonumber
local tostring = _G.tostring
local table_insert = table.insert
local math_max = math.max
local UnitGUID = _G.UnitGUID
local GetRealmName = _G.GetRealmName
local GetServerTime = _G.GetServerTime
local time = _G.time

local function deep_copy(orig)
    if sfui.common and sfui.common.copy then
        return sfui.common.copy(orig)
    end
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[deep_copy(k)] = deep_copy(v)
    end
    return copy
end

-- ── 1. Alts Snapshot (`SfuiDB.alts[guid]`) ────────────────────────────────────
function merge.BuildAltPayload(guid)
    if not guid or not SfuiDB or not SfuiDB.alts or not SfuiDB.alts[guid] then
        return nil
    end
    local d = deep_copy(SfuiDB.alts[guid])
    if SfuiDB.sync then
        if SfuiDB.sync.accountLabel and SfuiDB.sync.accountLabel ~= "" then
            d.accountLabel = d.accountLabel or SfuiDB.sync.accountLabel
        end
        if SfuiDB.sync.accountID and SfuiDB.sync.accountID ~= "" then
            d.accountID = d.accountID or SfuiDB.sync.accountID
        end
    end
    return {
        guid = guid,
        data = d,
    }
end

function merge.MergeAlt(guid, incomingData, peerAccountLabel, peerAccountID)
    if type(guid) ~= "string" or type(incomingData) ~= "table" then
        return false
    end
    -- Never overwrite active player's live record with older remote data
    local myGUID = UnitGUID and UnitGUID("player")
    SfuiDB = SfuiDB or {}
    SfuiDB.alts = SfuiDB.alts or {}

    local existing = SfuiDB.alts[guid]
    local inTime = tonumber(incomingData.lastUpdate) or 0
    local exTime = existing and (tonumber(existing.lastUpdate) or 0) or 0

    if guid == myGUID and existing then
        return false
    end

    if not existing or inTime >= exTime then
        local merged = deep_copy(incomingData)
        if peerAccountLabel and peerAccountLabel ~= "" and (not merged.accountLabel or merged.accountLabel == "") then
            merged.accountLabel = peerAccountLabel
        elseif existing and existing.accountLabel and (not merged.accountLabel or merged.accountLabel == "") then
            merged.accountLabel = existing.accountLabel
        end
        if peerAccountID and peerAccountID ~= "" then
            merged.accountID = peerAccountID
        elseif existing and existing.accountID then
            merged.accountID = existing.accountID
        end
        SfuiDB.alts[guid] = merged
        if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.InvalidatePeerCache then
            sfui.sync.multibox.InvalidatePeerCache()
        end
        if sfui.alts and sfui.alts.UpdateUI then
            sfui.alts.UpdateUI(true)
        end
        return true
    end

    return false
end

-- ── 2. Recipes Known Matrix (`SfuiDB.recipes[itemID][realm][guid]`) ───────────
local function InvalidateAllRecipeCaches()
    if sfui.recipes then
        if sfui.recipes.InvalidateCache then
            sfui.recipes.InvalidateCache()
        end
        if sfui.recipes.InvalidateLiveIndices then
            sfui.recipes.InvalidateLiveIndices()
        end
        local B = sfui.recipes.browser
        if B then
            if B.ClearLearnedCache then
                B.ClearLearnedCache()
            end
            if B.ui and B.ui.frame and B.ui.frame:IsShown() then
                if B.RebuildFilteredList then B.RebuildFilteredList() end
                if B.UpdateList then B.UpdateList() end
            end
        end
    end
end

function merge.GetCharKnownRecipes(realm, guid)
    local list = {}
    if not guid or not SfuiDB then
        return list
    end
    local seen = {}
    if type(SfuiDB.recipes) == "table" then
        for itemID, realmMap in pairs(SfuiDB.recipes) do
            if type(itemID) == "number" and type(realmMap) == "table" then
                for _, guidMap in pairs(realmMap) do
                    if type(guidMap) == "table" and guidMap[guid] then
                        if not seen[itemID] then
                            seen[itemID] = true
                            table_insert(list, itemID)
                        end
                        break
                    end
                end
            end
        end
    end
    if type(SfuiDB.crafts) == "table" and sfui.recipes_camelot and sfui.recipes_camelot.outputs then
        local outputs = sfui.recipes_camelot.outputs
        local recipes = sfui.recipes_camelot.recipes
        for outID, crafters in pairs(SfuiDB.crafts) do
            if type(crafters) == "table" and crafters[guid] then
                local sID = outputs[outID]
                if sID then
                    if not seen[sID] then
                        seen[sID] = true
                        table_insert(list, sID)
                    end
                    local r = recipes and recipes[sID]
                    if r and r.recipeItemID and not seen[r.recipeItemID] then
                        seen[r.recipeItemID] = true
                        table_insert(list, r.recipeItemID)
                    end
                end
            end
        end
    end
    return list
end

function merge.BuildCharRecipesPayload(realm, guid)
    if not realm or not guid then return nil end
    local items = merge.GetCharKnownRecipes(realm, guid)
    return {
        realm = realm,
        guid  = guid,
        items = items,
    }
end

local function MarkSingleKnownRecipeWithCrossLinks(id, realm, guid)
    SfuiDB.recipes[id] = SfuiDB.recipes[id] or {}
    SfuiDB.recipes[id][realm] = SfuiDB.recipes[id][realm] or {}
    local changed = false
    if not SfuiDB.recipes[id][realm][guid] then
        SfuiDB.recipes[id][realm][guid] = true
        changed = true
    end

    local db = sfui.recipes_camelot
    if db then
        local r = db.recipes and db.recipes[id]
        if not r and db.items and db.items[id] then
            local sID = db.items[id]
            r = sID and db.recipes and db.recipes[sID]
        end
        if r then
            if r.id and r.id ~= id then
                SfuiDB.recipes[r.id] = SfuiDB.recipes[r.id] or {}
                SfuiDB.recipes[r.id][realm] = SfuiDB.recipes[r.id][realm] or {}
                if not SfuiDB.recipes[r.id][realm][guid] then
                    SfuiDB.recipes[r.id][realm][guid] = true
                    changed = true
                end
            end
            if r.recipeItemID and r.recipeItemID ~= id then
                SfuiDB.recipes[r.recipeItemID] = SfuiDB.recipes[r.recipeItemID] or {}
                SfuiDB.recipes[r.recipeItemID][realm] = SfuiDB.recipes[r.recipeItemID][realm] or {}
                if not SfuiDB.recipes[r.recipeItemID][realm][guid] then
                    SfuiDB.recipes[r.recipeItemID][realm][guid] = true
                    changed = true
                end
            end
            if r.output then
                SfuiDB.crafts = SfuiDB.crafts or {}
                SfuiDB.crafts[r.output] = SfuiDB.crafts[r.output] or {}
                if not SfuiDB.crafts[r.output][guid] then
                    SfuiDB.crafts[r.output][guid] = true
                    changed = true
                end
            end
        end
    end
    return changed
end

function merge.MergeCharRecipes(realm, guid, items)
    if type(realm) ~= "string" or type(guid) ~= "string" or type(items) ~= "table" then
        return 0
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.recipes = SfuiDB.recipes or {}
    SfuiDB.crafts = SfuiDB.crafts or {}

    local added = 0
    for _, itemID in ipairs(items) do
        local id = tonumber(itemID)
        if id and MarkSingleKnownRecipeWithCrossLinks(id, realm, guid) then
            added = added + 1
        end
    end

    if added > 0 then
        InvalidateAllRecipeCaches()
    end
    return added
end

function merge.MergeSingleRecipe(itemID, realm, guid, isKnown)
    local id = tonumber(itemID)
    if not id or type(realm) ~= "string" or type(guid) ~= "string" then
        return false
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.recipes = SfuiDB.recipes or {}
    SfuiDB.crafts = SfuiDB.crafts or {}

    if isKnown then
        local changed = MarkSingleKnownRecipeWithCrossLinks(id, realm, guid)
        if changed then
            InvalidateAllRecipeCaches()
        end
        return changed
    else
        if type(SfuiDB.recipes[id]) == "table" and type(SfuiDB.recipes[id][realm]) == "table" and SfuiDB.recipes[id][realm][guid] then
            SfuiDB.recipes[id][realm][guid] = nil
            InvalidateAllRecipeCaches()
            return true
        end
        return false
    end
end

-- ── 3. Profession Contacts & Recipe Finds (`SfuiDB.contacts`, `recipe_finds`) ─
function merge.BuildContactsPayload()
    if not SfuiDB then return nil end
    return {
        vendors  = (SfuiDB.contacts and SfuiDB.contacts.vendors) and deep_copy(SfuiDB.contacts.vendors) or {},
        trainers = (SfuiDB.contacts and SfuiDB.contacts.trainers) and deep_copy(SfuiDB.contacts.trainers) or {},
        drops    = (SfuiDB.recipe_finds and SfuiDB.recipe_finds.drops) and deep_copy(SfuiDB.recipe_finds.drops) or {},
        quests   = (SfuiDB.recipe_finds and SfuiDB.recipe_finds.quests) and deep_copy(SfuiDB.recipe_finds.quests) or {},
    }
end

function merge.MergeContacts(payload)
    if type(payload) ~= "table" then return 0 end
    SfuiDB = SfuiDB or {}
    SfuiDB.contacts = SfuiDB.contacts or {}
    SfuiDB.contacts.vendors = SfuiDB.contacts.vendors or {}
    SfuiDB.contacts.trainers = SfuiDB.contacts.trainers or {}
    SfuiDB.recipe_finds = SfuiDB.recipe_finds or {}
    SfuiDB.recipe_finds.drops = SfuiDB.recipe_finds.drops or {}
    SfuiDB.recipe_finds.quests = SfuiDB.recipe_finds.quests or {}

    local changes = 0

    -- Merge vendors
    if type(payload.vendors) == "table" then
        for npcID, vEntry in pairs(payload.vendors) do
            local id = tonumber(npcID) or npcID
            if type(vEntry) == "table" then
                local loc = SfuiDB.contacts.vendors[id]
                if not loc then
                    SfuiDB.contacts.vendors[id] = deep_copy(vEntry)
                    changes = changes + 1
                else
                    loc.name = loc.name or vEntry.name
                    loc.mapID = loc.mapID or vEntry.mapID
                    loc.zone = loc.zone or vEntry.zone
                    loc.subzone = loc.subzone or vEntry.subzone
                    loc.x = loc.x or vEntry.x
                    loc.y = loc.y or vEntry.y
                    loc.items = loc.items or {}
                    if type(vEntry.items) == "table" then
                        for itemID, itemData in pairs(vEntry.items) do
                            local iid = tonumber(itemID) or itemID
                            local curItem = loc.items[iid]
                            if not curItem or ((tonumber(itemData.lastSeen) or 0) > (tonumber(curItem.lastSeen) or 0)) then
                                loc.items[iid] = deep_copy(itemData)
                                changes = changes + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Merge trainers
    if type(payload.trainers) == "table" then
        for npcID, tEntry in pairs(payload.trainers) do
            local id = tonumber(npcID) or npcID
            if type(tEntry) == "table" then
                local loc = SfuiDB.contacts.trainers[id]
                if not loc then
                    SfuiDB.contacts.trainers[id] = deep_copy(tEntry)
                    changes = changes + 1
                else
                    loc.name = loc.name or tEntry.name
                    loc.mapID = loc.mapID or tEntry.mapID
                    loc.zone = loc.zone or tEntry.zone
                    loc.subzone = loc.subzone or tEntry.subzone
                    loc.x = loc.x or tEntry.x
                    loc.y = loc.y or tEntry.y
                    loc.spells = loc.spells or {}
                    if type(tEntry.spells) == "table" then
                        for spellKey, sData in pairs(tEntry.spells) do
                            local curSpell = loc.spells[spellKey]
                            if not curSpell or ((tonumber(sData.lastSeen) or 0) > (tonumber(curSpell.lastSeen) or 0)) then
                                loc.spells[spellKey] = deep_copy(sData)
                                changes = changes + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Merge drops
    if type(payload.drops) == "table" then
        for cleanName, dropList in pairs(payload.drops) do
            if type(cleanName) == "string" and type(dropList) == "table" then
                SfuiDB.recipe_finds.drops[cleanName] = SfuiDB.recipe_finds.drops[cleanName] or {}
                local locList = SfuiDB.recipe_finds.drops[cleanName]
                for _, inEntry in ipairs(dropList) do
                    if type(inEntry) == "table" then
                        local found = false
                        for _, exEntry in ipairs(locList) do
                            if exEntry.mob == inEntry.mob and exEntry.zone == inEntry.zone then
                                found = true
                                local newCnt = math_max(tonumber(exEntry.count) or 1, tonumber(inEntry.count) or 1)
                                if newCnt > (tonumber(exEntry.count) or 1) then
                                    exEntry.count = newCnt
                                    changes = changes + 1
                                end
                                exEntry.lastSeen = math_max(tonumber(exEntry.lastSeen) or 0, tonumber(inEntry.lastSeen) or 0)
                                exEntry.mapID = exEntry.mapID or inEntry.mapID
                                exEntry.x = exEntry.x or inEntry.x
                                exEntry.y = exEntry.y or inEntry.y
                                break
                            end
                        end
                        if not found then
                            table_insert(locList, deep_copy(inEntry))
                            changes = changes + 1
                        end
                    end
                end
            end
        end
    end

    -- Merge quests
    if type(payload.quests) == "table" then
        for cleanName, questList in pairs(payload.quests) do
            if type(cleanName) == "string" and type(questList) == "table" then
                SfuiDB.recipe_finds.quests[cleanName] = SfuiDB.recipe_finds.quests[cleanName] or {}
                local locList = SfuiDB.recipe_finds.quests[cleanName]
                for _, inEntry in ipairs(questList) do
                    if type(inEntry) == "table" and inEntry.title then
                        local found = false
                        for _, exEntry in ipairs(locList) do
                            if exEntry.title == inEntry.title then
                                found = true
                                exEntry.giver = exEntry.giver or inEntry.giver
                                exEntry.zone = exEntry.zone or inEntry.zone
                                exEntry.lastSeen = math_max(tonumber(exEntry.lastSeen) or 0, tonumber(inEntry.lastSeen) or 0)
                                break
                            end
                        end
                        if not found then
                            table_insert(locList, deep_copy(inEntry))
                            changes = changes + 1
                        end
                    end
                end
            end
        end
    end

    if changes > 0 and sfui.recipes and sfui.recipes.InvalidateLiveIndices then
        sfui.recipes.InvalidateLiveIndices()
    end
    return changes
end

-- ── 4. Fishing Per-Character Ledger (`SfuiDB.fishing.chars[guid]`) ────────────
function merge.BuildFishingCharPayload(guid)
    if sfui.fishing and sfui.fishing.EnsureCharLedger then
        sfui.fishing.EnsureCharLedger()
    end
    if not guid or not SfuiDB or not SfuiDB.fishing or not SfuiDB.fishing.chars then
        return nil
    end
    local cData = SfuiDB.fishing.chars[guid]
    if not cData then return nil end
    return {
        guid = guid,
        data = deep_copy(cData),
    }
end

function merge.MergeFishingChar(guid, incomingData)
    if type(guid) ~= "string" or type(incomingData) ~= "table" then
        return false
    end
    if sfui.fishing and sfui.fishing.EnsureCharLedger then
        sfui.fishing.EnsureCharLedger()
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.fishing = SfuiDB.fishing or {}
    SfuiDB.fishing.chars = SfuiDB.fishing.chars or {}

    local cur = SfuiDB.fishing.chars[guid]
    local changed = false

    if not cur then
        SfuiDB.fishing.chars[guid] = deep_copy(incomingData)
        changed = true
    else
        local inRev = tonumber(incomingData.rev) or 0
        local curRev = tonumber(cur.rev) or 0
        if inRev > curRev then
            cur.rev = inRev
            changed = true
        end

        if (tonumber(incomingData.longestStreak) or 0) > (tonumber(cur.longestStreak) or 0) then
            cur.longestStreak = tonumber(incomingData.longestStreak)
            changed = true
        end
        if (tonumber(incomingData.bestRate) or 0) > (tonumber(cur.bestRate) or 0) then
            cur.bestRate = tonumber(incomingData.bestRate)
            changed = true
        end

        -- Merge zones (max counters per character GUID)
        cur.zones = cur.zones or {}
        if type(incomingData.zones) == "table" then
            for mapID, inZ in pairs(incomingData.zones) do
                local mid = tonumber(mapID) or mapID
                if type(inZ) == "table" then
                    local cz = cur.zones[mid]
                    if not cz then
                        cur.zones[mid] = deep_copy(inZ)
                        changed = true
                    else
                        local newCasts = math_max(tonumber(cz.casts) or 0, tonumber(inZ.casts) or 0)
                        local newCatches = math_max(tonumber(cz.catches) or 0, tonumber(inZ.catches) or 0)
                        local newGetaways = math_max(tonumber(cz.getaways) or 0, tonumber(inZ.getaways) or 0)
                        if newCasts ~= (cz.casts or 0) or newCatches ~= (cz.catches or 0) or newGetaways ~= (cz.getaways or 0) then
                            cz.casts = newCasts
                            cz.catches = newCatches
                            cz.getaways = newGetaways
                            changed = true
                        end
                        cz.fish = cz.fish or {}
                        if type(inZ.fish) == "table" then
                            for itemID, cnt in pairs(inZ.fish) do
                                local iid = tonumber(itemID) or itemID
                                local nCnt = tonumber(cnt) or 0
                                if nCnt > (tonumber(cz.fish[iid]) or 0) then
                                    cz.fish[iid] = nCnt
                                    changed = true
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Merge species (max count per character GUID)
        cur.species = cur.species or {}
        if type(incomingData.species) == "table" then
            for itemID, inSp in pairs(incomingData.species) do
                local iid = tonumber(itemID) or itemID
                if type(inSp) == "table" then
                    local csp = cur.species[iid]
                    if not csp then
                        cur.species[iid] = deep_copy(inSp)
                        changed = true
                    else
                        local nCnt = tonumber(inSp.n) or 0
                        if nCnt > (tonumber(csp.n) or 0) then
                            csp.n = nCnt
                            changed = true
                        end
                        if inSp.first and (not csp.first or inSp.first < csp.first) then
                            csp.first = inSp.first
                            csp.fz = inSp.fz or csp.fz
                            changed = true
                        end
                        if inSp.last and (not csp.last or inSp.last > csp.last) then
                            csp.last = inSp.last
                            csp.lz = inSp.lz or csp.lz
                            changed = true
                        end
                    end
                end
            end
        end
    end

    if changed and sfui.fishing and sfui.fishing.RebuildAggregates then
        sfui.fishing.RebuildAggregates()
    end
    return changed
end

-- ── 5. Auto-Mail Routing Rules (`SfuiDB.altMailRouting`) ──────────────────────
function merge.BuildMailPayload()
    if not SfuiDB or type(SfuiDB.altMailRouting) ~= "table" then
        return nil
    end
    return {
        routes           = deep_copy(SfuiDB.altMailRouting.routes or {}),
        ignoredItems     = deep_copy(SfuiDB.altMailRouting.ignoredItems or {}),
        disenchanterGUID = SfuiDB.altMailRouting.disenchanterGUID,
    }
end

function merge.MergeMail(payload)
    if type(payload) ~= "table" then return false end
    SfuiDB = SfuiDB or {}
    if sfui.alts and sfui.alts.mail and sfui.alts.mail.GetSettings then
        sfui.alts.mail.GetSettings()
    else
        SfuiDB.altMailRouting = SfuiDB.altMailRouting or { routes = {}, ignoredItems = {} }
    end

    local s = SfuiDB.altMailRouting
    s.routes = s.routes or {}
    s.ignoredItems = s.ignoredItems or {}
    local changed = false

    if payload.disenchanterGUID and not s.disenchanterGUID then
        s.disenchanterGUID = payload.disenchanterGUID
        changed = true
    end

    if type(payload.ignoredItems) == "table" then
        for itemID, val in pairs(payload.ignoredItems) do
            local iid = tonumber(itemID) or itemID
            if val and not s.ignoredItems[iid] then
                s.ignoredItems[iid] = true
                changed = true
            end
        end
    end

    if type(payload.routes) == "table" then
        for guid, inRoute in pairs(payload.routes) do
            if type(guid) == "string" and type(inRoute) == "table" then
                local curRoute = s.routes[guid]
                if not curRoute then
                    s.routes[guid] = deep_copy(inRoute)
                    changed = true
                else
                    for k, v in pairs(inRoute) do
                        if k == "items" and type(v) == "table" then
                            curRoute.items = curRoute.items or {}
                            for itemID, flag in pairs(v) do
                                local iid = tonumber(itemID) or itemID
                                if flag and not curRoute.items[iid] then
                                    curRoute.items[iid] = flag
                                    changed = true
                                end
                            end
                        elseif type(v) == "boolean" and v == true and not curRoute[k] then
                            curRoute[k] = true
                            changed = true
                        end
                    end
                end
            end
        end
    end

    return changed
end

-- ── 6. Active Quests & Dungeon Journal Quests (`SfuiDB.alts[guid]`) ──────────
local djQuestIDSet = nil
local function get_dj_quest_id_set()
    if djQuestIDSet then return djQuestIDSet end
    local db = sfui.dj_camelot or (sfui.data and sfui.data.dj_camelot)
    if not db then return nil end
    djQuestIDSet = {}
    local function add_list(list)
        if type(list) ~= "table" then return end
        for _, inst in ipairs(list) do
            if type(inst) == "table" and type(inst.quests) == "table" then
                for _, q in ipairs(inst.quests) do
                    if type(q) == "table" and q.id then
                        djQuestIDSet[q.id] = true
                        if type(q.chain) == "table" then
                            for _, s in ipairs(q.chain) do
                                if type(s) == "table" and s.id then
                                    djQuestIDSet[s.id] = true
                                end
                            end
                        elseif type(q.chainStart) == "table" and q.chainStart.id then
                            djQuestIDSet[q.chainStart.id] = true
                        end
                    end
                end
            end
        end
    end
    add_list(db.dungeons)
    add_list(db.raids)
    return djQuestIDSet
end

function merge.ScanLocalQuestsAndDJ(justCompletedQuestID)
    local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
        or (UnitGUID and UnitGUID("player"))
    if not myGUID then return nil end

    SfuiDB = SfuiDB or {}
    SfuiDB.alts = SfuiDB.alts or {}
    local alt = SfuiDB.alts[myGUID]
    if type(alt) ~= "table" then
        alt = {
            name  = _G.UnitName and _G.UnitName("player") or nil,
            realm = (GetRealmName and GetRealmName()) or "",
            class = _G.UnitClass and select(2, _G.UnitClass("player")) or nil,
            level = _G.UnitLevel and _G.UnitLevel("player") or nil,
        }
        SfuiDB.alts[myGUID] = alt
    end

    alt.completedQuests = alt.completedQuests or {}
    if justCompletedQuestID and tonumber(justCompletedQuestID) then
        alt.completedQuests[tonumber(justCompletedQuestID)] = 1
    end

    local activeQuests = {}
    local C_QuestLog = _G.C_QuestLog
    local GetNumQuestLogEntries = _G.GetNumQuestLogEntries
    local GetQuestLogTitle = _G.GetQuestLogTitle

    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries())
        or 0
    local numQuests = 0

    for i = 1, numEntries do
        local questID, title, isHeader, isComplete = nil, nil, false, false
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info then
                isHeader = info.isHeader
                questID = info.questID
                title = info.title
            end
        elseif GetQuestLogTitle then
            local qTitle, _, _, qHeader, _, qComp, _, qID = GetQuestLogTitle(i)
            title = qTitle
            isHeader = qHeader
            isComplete = (qComp == 1)
            questID = qID
        end

        if not isHeader and questID and questID > 0 then
            numQuests = numQuests + 1
            if C_QuestLog and C_QuestLog.IsComplete then
                isComplete = C_QuestLog.IsComplete(questID) or isComplete
            end

            local objList = {}
            local progSummary = nil
            if C_QuestLog and C_QuestLog.GetQuestObjectives then
                local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
                if ok and type(objs) == "table" then
                    for _, obj in ipairs(objs) do
                        if type(obj) == "table" and obj.text and obj.text ~= "" then
                            local clean = tostring(obj.text):gsub(" / ", "/")
                            table_insert(objList, clean)
                            if not progSummary and obj.numRequired and obj.numRequired > 0 and obj.numFulfilled then
                                progSummary = tostring(obj.numFulfilled) .. "/" .. tostring(obj.numRequired)
                            end
                        end
                    end
                end
            elseif _G.GetNumQuestLeaderBoards and _G.GetQuestLogLeaderBoard then
                local numLB = _G.GetNumQuestLeaderBoards(i) or 0
                for objIdx = 1, numLB do
                    local desc = _G.GetQuestLogLeaderBoard(objIdx, i)
                    if desc and desc ~= "" then
                        local clean = tostring(desc):gsub(" / ", "/")
                        table_insert(objList, clean)
                        if not progSummary then
                            progSummary = clean:match("(%d+/%d+)")
                        end
                    end
                end
            end

            activeQuests[questID] = {
                t = title,
                c = isComplete and 1 or 0,
                p = progSummary,
                o = #objList > 0 and objList or nil,
            }
        end
    end

    local maxQuests = (_G.Constants and _G.Constants.QuestLogConsts and _G.Constants.QuestLogConsts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT)
        or (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
        or (C_QuestLog and C_QuestLog.GetMaxNumQuests and C_QuestLog.GetMaxNumQuests())
        or 20

    alt.activeQuests = activeQuests
    alt.questCap = { n = numQuests, m = maxQuests }

    -- Scan Camelot / Classic Dungeon Journal quests & chain steps
    local djSet = get_dj_quest_id_set()
    if djSet then
        local djQuests = alt.djQuests or {}
        local isDoneFn = (sfui.dungeonjournal and sfui.dungeonjournal.IsQuestCompleted)
            or (sfui.common and sfui.common.is_quest_completed)
        for qID in pairs(djSet) do
            if activeQuests[qID] then
                djQuests[qID] = 1
            elseif (isDoneFn and isDoneFn(qID)) or alt.completedQuests[qID] then
                djQuests[qID] = 2
                alt.completedQuests[qID] = 1
            else
                djQuests[qID] = nil
            end
        end
        alt.djQuests = djQuests
    end

    local now = (GetServerTime and GetServerTime()) or time()
    alt.questsRev = now
    return myGUID
end

function merge.BuildQuestsPayload(guid)
    if not guid or not SfuiDB or not SfuiDB.alts or type(SfuiDB.alts[guid]) ~= "table" then
        return nil
    end
    local alt = SfuiDB.alts[guid]
    return {
        guid            = guid,
        name            = alt.name,
        realm           = alt.realm,
        class           = alt.class,
        level           = alt.level,
        rev             = tonumber(alt.questsRev) or tonumber(alt.lastUpdate) or 1,
        questCap        = deep_copy(alt.questCap or {}),
        activeQuests    = deep_copy(alt.activeQuests or {}),
        completedQuests = deep_copy(alt.completedQuests or {}),
        djQuests        = deep_copy(alt.djQuests or {}),
    }
end

function merge.MergeQuests(guid, incomingData)
    if type(guid) ~= "string" or type(incomingData) ~= "table" then return false end
    local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
        or (UnitGUID and UnitGUID("player"))
    if guid == myGUID then return false end

    SfuiDB = SfuiDB or {}
    SfuiDB.alts = SfuiDB.alts or {}
    local alt = SfuiDB.alts[guid]
    if type(alt) ~= "table" then
        alt = {
            name  = incomingData.name,
            realm = incomingData.realm,
            class = incomingData.class,
            level = incomingData.level,
        }
        SfuiDB.alts[guid] = alt
    else
        if incomingData.name and not alt.name then alt.name = incomingData.name end
        if incomingData.class and not alt.class then alt.class = incomingData.class end
        if incomingData.level then alt.level = incomingData.level end
    end

    local inRev = tonumber(incomingData.rev) or 0
    local curRev = tonumber(alt.questsRev) or 0
    if inRev < curRev then
        return false
    end

    alt.questsRev = inRev
    if type(incomingData.questCap) == "table" then
        alt.questCap = deep_copy(incomingData.questCap)
    end
    if type(incomingData.activeQuests) == "table" then
        local normActive = {}
        for k, v in pairs(incomingData.activeQuests) do
            local qid = tonumber(k)
            if qid and type(v) == "table" then
                normActive[qid] = deep_copy(v)
            end
        end
        alt.activeQuests = normActive
    end
    alt.completedQuests = alt.completedQuests or {}
    if type(incomingData.completedQuests) == "table" then
        for k, v in pairs(incomingData.completedQuests) do
            local qid = tonumber(k)
            if qid and v then
                alt.completedQuests[qid] = 1
            end
        end
    end
    alt.djQuests = alt.djQuests or {}
    if type(incomingData.djQuests) == "table" then
        for k, v in pairs(incomingData.djQuests) do
            local qid = tonumber(k)
            local st = tonumber(v)
            if qid and st then
                if st == 2 or (alt.djQuests[qid] ~= 2) then
                    alt.djQuests[qid] = st
                end
            end
        end
        -- Clear any djQuests that were previously 1 (in log) if no longer in activeQuests and not 2 (completed)
        for qid, st in pairs(alt.djQuests) do
            if st == 1 and (not alt.activeQuests or not alt.activeQuests[qid]) then
                alt.djQuests[qid] = nil
            end
        end
    end

    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0.05)
    end
    if sfui.dungeonjournal and sfui.dungeonjournal.Rebuild then
        local djFrame = sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
        if djFrame and djFrame:IsShown() then
            sfui.dungeonjournal.Rebuild()
        end
    end
    return true
end

-- ── 7. Dungeon Journal Per-Character Wishlist (`SfuiDB.dungeonjournal`) ──────
function merge.BuildDJWishlistPayload()
    if not SfuiDB or type(SfuiDB.dungeonjournal) ~= "table" then return nil end
    local dj = SfuiDB.dungeonjournal
    if type(dj.charWishlist) ~= "table" and type(dj.wishlist) ~= "table" then
        return nil
    end

    local myGUID = (sfui.alts and sfui.alts.GetCurrentCharacterGUID and sfui.alts.GetCurrentCharacterGUID())
        or (UnitGUID and UnitGUID("player"))
    dj.charWishlist = dj.charWishlist or {}
    dj.charWishlistRev = dj.charWishlistRev or {}

    if myGUID and type(dj.wishlist) == "table" and not dj.charWishlist[myGUID] then
        dj.charWishlist[myGUID] = deep_copy(dj.wishlist)
        dj.charWishlistRev[myGUID] = (GetServerTime and GetServerTime()) or time()
    end

    return {
        charWishlist = deep_copy(dj.charWishlist),
        revs         = deep_copy(dj.charWishlistRev),
    }
end

function merge.MergeDJWishlist(payload)
    if type(payload) ~= "table" or type(payload.charWishlist) ~= "table" then return false end
    SfuiDB = SfuiDB or {}
    SfuiDB.dungeonjournal = SfuiDB.dungeonjournal or {}
    local dj = SfuiDB.dungeonjournal
    dj.charWishlist = dj.charWishlist or {}
    dj.charWishlistRev = dj.charWishlistRev or {}
    dj.wishlist = dj.wishlist or {}

    local inRevs = type(payload.revs) == "table" and payload.revs or {}
    local changed = false

    for guid, items in pairs(payload.charWishlist) do
        if type(guid) == "string" and type(items) == "table" then
            local inRev = tonumber(inRevs[guid]) or 1
            local curRev = tonumber(dj.charWishlistRev[guid]) or 0
            if inRev >= curRev then
                dj.charWishlistRev[guid] = inRev
                local normItems = {}
                for k, v in pairs(items) do
                    local iid = tonumber(k)
                    if iid and v then
                        normItems[iid] = true
                        dj.wishlist[iid] = true
                    end
                end
                dj.charWishlist[guid] = normItems
                changed = true
            end
        end
    end

    if changed and sfui.dungeonjournal and sfui.dungeonjournal.Rebuild then
        local djFrame = sfui.dungeonjournal.GetFrame and sfui.dungeonjournal.GetFrame()
        if djFrame and djFrame:IsShown() then
            sfui.dungeonjournal.Rebuild()
        end
    end
    return changed
end

-- ── 8. Manifest / Digest Builder ──────────────────────────────────────────────
local function count_all_char_known_recipes()
    local seenByGuid = {}
    local counts = {}
    local function mark(guid, id)
        local s = seenByGuid[guid]
        if not s then
            s = {}
            seenByGuid[guid] = s
        end
        if not s[id] then
            s[id] = true
            counts[guid] = (counts[guid] or 0) + 1
        end
    end

    if type(SfuiDB.recipes) == "table" then
        for itemID, realmMap in pairs(SfuiDB.recipes) do
            if type(itemID) == "number" and type(realmMap) == "table" then
                for _, guidMap in pairs(realmMap) do
                    if type(guidMap) == "table" then
                        for guid, known in pairs(guidMap) do
                            if known then mark(guid, itemID) end
                        end
                    end
                end
            end
        end
    end

    if type(SfuiDB.crafts) == "table" and sfui.recipes_camelot and sfui.recipes_camelot.outputs then
        local outputs = sfui.recipes_camelot.outputs
        local recipes = sfui.recipes_camelot.recipes
        for outID, crafters in pairs(SfuiDB.crafts) do
            if type(crafters) == "table" then
                local sID = outputs[outID]
                if sID then
                    local r = recipes and recipes[sID]
                    local rItemID = r and r.recipeItemID
                    for guid, known in pairs(crafters) do
                        if known then
                            mark(guid, sID)
                            if rItemID then mark(guid, rItemID) end
                        end
                    end
                end
            end
        end
    end

    return counts
end

function merge.GetContactsCounts()
    SfuiDB = SfuiDB or {}
    local vCount, tCount, dCount, qCount = 0, 0, 0, 0
    if SfuiDB.contacts then
        if type(SfuiDB.contacts.vendors) == "table" then
            for _ in pairs(SfuiDB.contacts.vendors) do vCount = vCount + 1 end
        end
        if type(SfuiDB.contacts.trainers) == "table" then
            for _ in pairs(SfuiDB.contacts.trainers) do tCount = tCount + 1 end
        end
    end
    if SfuiDB.recipe_finds then
        if type(SfuiDB.recipe_finds.drops) == "table" then
            for _ in pairs(SfuiDB.recipe_finds.drops) do dCount = dCount + 1 end
        end
        if type(SfuiDB.recipe_finds.quests) == "table" then
            for _ in pairs(SfuiDB.recipe_finds.quests) do qCount = qCount + 1 end
        end
    end
    return { v = vCount, t = tCount, d = dCount, q = qCount }
end

function merge.BuildManifest(syncCfg)
    SfuiDB = SfuiDB or {}
    syncCfg = syncCfg or (SfuiDB.sync or {})
    local myAccountID = syncCfg.accountID or ""

    if sfui.fishing and sfui.fishing.EnsureCharLedger then
        sfui.fishing.EnsureCharLedger()
    end
    merge.ScanLocalQuestsAndDJ()

    local manifest = {
        accountID    = myAccountID,
        accountLabel = syncCfg.accountLabel or "",
        settings     = (sfui.sync and sfui.sync.BuildSharedSettingsPayload and sfui.sync.BuildSharedSettingsPayload(syncCfg)) or nil,
        alts         = {},
        quests       = {},
        djWishlist   = {},
        recipes      = {},
        fishing      = {},
        roster       = {},
    }

    local recipeCountsByGuid = (syncCfg.syncRecipes ~= false) and count_all_char_known_recipes() or nil
    local defaultRealm = (GetRealmName and GetRealmName()) or ""

    if SfuiDB.alts then
        for guid, d in pairs(SfuiDB.alts) do
            if type(d) == "table" then
                manifest.alts[guid] = tonumber(d.lastUpdate) or 0
                if d.questsRev or (d.activeQuests and next(d.activeQuests)) or (d.djQuests and next(d.djQuests)) then
                    manifest.quests[guid] = tonumber(d.questsRev) or tonumber(d.lastUpdate) or 1
                end
                local isOwnAlt = (not d.accountID or d.accountID == "" or d.accountID == myAccountID)
                if isOwnAlt and d.name and d.name ~= "" then
                    table_insert(manifest.roster, {
                        guid         = guid,
                        name         = d.name,
                        realm        = d.realm or defaultRealm,
                        class        = d.class,
                        level        = d.level,
                        accountID    = myAccountID,
                        accountLabel = d.accountLabel or syncCfg.accountLabel or "",
                    })
                end
                local realm = d.realm or defaultRealm
                local rCount = recipeCountsByGuid and recipeCountsByGuid[guid] or 0
                if realm ~= "" and rCount > 0 then
                    manifest.recipes[guid] = {
                        r = realm,
                        n = rCount,
                    }
                end
            end
        end
    end

    if SfuiDB.dungeonjournal and type(SfuiDB.dungeonjournal.charWishlist) == "table" then
        local revs = SfuiDB.dungeonjournal.charWishlistRev or {}
        for guid, items in pairs(SfuiDB.dungeonjournal.charWishlist) do
            if type(items) == "table" and next(items) ~= nil then
                manifest.djWishlist[guid] = tonumber(revs[guid]) or 1
            end
        end
    end

    if SfuiDB.fishing and type(SfuiDB.fishing.chars) == "table" then
        for guid, cData in pairs(SfuiDB.fishing.chars) do
            if type(cData) == "table" then
                manifest.fishing[guid] = tonumber(cData.rev) or 1
            end
        end
    end

    manifest.contacts = merge.GetContactsCounts()

    return manifest
end

