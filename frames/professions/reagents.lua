local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/reagents.lua
--  Reagent Usage Tooltips (Camelot / Classic Forever)
--
--  Adds a "used in" section to reagent item tooltips: which recipes consume the
--  item, grouped per profession, for the active character and every synced alt
--  in SfuiDB.alts that has the profession.
--
--  Data flow:
--    - reverse index [reagentItemID] = { spellID, ... } is built lazily on the
--      first reagent hover by scanning the raw reagent strings in
--      sfui.recipes_camelot._raw (no full recipe decode).
--    - profession roster [skillID] = { holder, ... } is derived from
--      SfuiDB.alts via sfui.recipes.CheckAltEligibility.
--    - known state comes from sfui.recipes.browser.IsRecipeLearned (live spell
--      check for the active character, SfuiDB.recipes / SfuiDB.crafts for alts).
--    - finished lines are cached per item and shift state; caches are dropped on
--      recipe, skill, alt and sync updates.
--
--  Rendered from SetItemTooltip in frames/alts/recipes.lua so it shares the
--  same tooltip filtering, combat guard and item resolution.
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local _G             = _G
local pairs          = _G.pairs
local ipairs         = _G.ipairs
local type           = _G.type
local tonumber       = _G.tonumber
local tostring       = _G.tostring
local wipe           = _G.wipe
local string_format  = string.format
local table_sort     = table.sort
local math_min       = math.min
local UnitGUID       = _G.UnitGUID
local IsShiftKeyDown = _G.IsShiftKeyDown

local DEFAULT_MAX_LINES = 4   -- recipe rows per profession (collapsed)
local SHIFT_MAX_LINES   = 30  -- recipe rows per profession (shift held)
local MAX_ROW_NAMES     = 2   -- character names on a single recipe row
local MAX_HEADER_NAMES  = 3   -- character names on a profession header
local ICON_FMT          = "|T%s:14:14:0:0:64:64:5:59:5:59|t"
local FALLBACK_ICON     = "Interface\\Icons\\INV_Misc_QuestionMark"

-- trade skill difficulty colors (orange, yellow, green, gray)
local DIFFICULTY_HEX = {
    [0] = "ff8040",
    [1] = "ffff00",
    [2] = "40bf40",
    [3] = "808080",
}
local HEX_UNKNOWN = "9d9d9d"
local HEX_DIM     = "888888"

local STATE_KNOWN       = 1
local STATE_LEARNABLE   = 2
local STATE_NEEDS_SKILL = 3

local R = {}
sfui.recipes.reagents = R

-- ── 1. Reverse Reagent Index (lazy) ───────────────────────────────────────────
local reagentIndex = nil -- [itemID] = { spellID, ... }

local function BuildReagentIndex()
    reagentIndex = {}
    local db = sfui.recipes_camelot
    local raw = db and db._raw
    if type(raw) ~= "table" then return end
    for sid, rec in pairs(raw) do
        local rStr = rec[8]
        if rStr and rStr ~= "" then
            for idStr in rStr:gmatch("(%d+):%d+") do
                local id = tonumber(idStr)
                local list = reagentIndex[id]
                if not list then
                    list = {}
                    reagentIndex[id] = list
                end
                list[#list + 1] = sid
            end
        end
    end
end

--- Recipe spell IDs that consume the given reagent item (or nil)
--- @param itemID number
--- @return table|nil spellIDs
function sfui.recipes.GetRecipesUsingReagent(itemID)
    if not itemID then return nil end
    if not reagentIndex then BuildReagentIndex() end
    return reagentIndex[itemID]
end

-- ── 2. Profession Metadata ────────────────────────────────────────────────────
local profMetaCache = {} -- [skillID] = { name = string, icon = string }

local function GetProfessionMeta(skillID)
    local meta = profMetaCache[skillID]
    if meta then return meta end
    local B = sfui.recipes.browser
    if B and B.ALL_PROFESSIONS then
        for _, p in ipairs(B.ALL_PROFESSIONS) do
            if p.skillID == skillID then
                meta = { name = p.name, icon = p.icon or FALLBACK_ICON }
                break
            end
        end
    end
    meta = meta or { name = tostring(skillID), icon = FALLBACK_ICON }
    profMetaCache[skillID] = meta
    return meta
end

-- ── 3. Crafter Roster (active character + synced alts) ────────────────────────
local roster = nil -- [skillID] = { { guid, alt, rank, isMe, label }, ... }

local function FormatCharacterName(alt, guid)
    local fmt = sfui.recipes.GetColoredCharacterName
    if fmt then
        return fmt(alt.name, alt.class, alt.realm, alt, guid)
    end
    return (sfui.alts and sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(alt, guid)) or alt.name or "?"
end

local function CompareHolders(a, b)
    if a.isMe ~= b.isMe then return a.isMe end
    if a.rank ~= b.rank then return a.rank > b.rank end
    return (a.alt.name or "") < (b.alt.name or "")
end

local function BuildRoster()
    roster = {}
    local alts = SfuiDB and SfuiDB.alts
    local bySkill = sfui.recipes_camelot and sfui.recipes_camelot.by_skill
    local checkAlt = sfui.recipes.CheckAltEligibility
    if type(alts) ~= "table" or type(bySkill) ~= "table" or not checkAlt then
        return roster
    end

    local myGUID = UnitGUID and UnitGUID("player")
    for guid, alt in pairs(alts) do
        if type(alt) == "table" and alt.professions and (guid == myGUID or not alt.isHidden) then
            for skillID in pairs(bySkill) do
                local hasProf, _, rank = checkAlt(alt, nil, nil, nil, skillID)
                if hasProf then
                    local list = roster[skillID]
                    if not list then
                        list = {}
                        roster[skillID] = list
                    end
                    list[#list + 1] = {
                        guid  = guid,
                        alt   = alt,
                        rank  = rank or 0,
                        isMe  = (guid == myGUID),
                        label = FormatCharacterName(alt, guid),
                    }
                end
            end
        end
    end

    for _, list in pairs(roster) do
        table_sort(list, CompareHolders)
    end
    return roster
end

-- ── 4. Recipe State Helpers ───────────────────────────────────────────────────
local function GetDifficulty(colors, rank)
    if not colors or not rank then return nil end
    if colors[4] and rank >= colors[4] then return 3 end
    if colors[3] and rank >= colors[3] then return 2 end
    if colors[2] and rank >= colors[2] then return 1 end
    return 0
end

local function IsKnownBy(r, minSkill, holder)
    -- starter recipes (minSkill <= 0) come with the profession itself
    if minSkill <= 0 then return true end
    local B = sfui.recipes.browser
    if B and B.IsRecipeLearned then
        return B.IsRecipeLearned(r, holder.guid, holder.alt.realm) and true or false
    end
    local inDB = sfui.recipes.IsRecipeKnownInDB
    if inDB and (inDB(r.id, holder.guid) or (r.recipeItemID and inDB(r.recipeItemID, holder.guid))) then
        return true
    end
    local crafts = SfuiDB and SfuiDB.crafts
    return (r.output and crafts and crafts[r.output] and crafts[r.output][holder.guid]) and true or false
end

local function JoinNames(list, maxNames)
    local count = #list
    if count == 0 then return "" end
    local out = list[1]
    for i = 2, math_min(count, maxNames) do
        out = out .. ", " .. list[i]
    end
    if count > maxNames then
        out = string_format("%s |cff%s+%d|r", out, HEX_DIM, count - maxNames)
    end
    return out
end

local function CompareEntries(a, b)
    if a.state ~= b.state then return a.state < b.state end
    if a.diff ~= b.diff then return a.diff < b.diff end
    if a.minSkill ~= b.minSkill then return a.minSkill > b.minSkill end
    return (a.r.name or "") < (b.r.name or "")
end

local function CompareGroups(a, b)
    if a.hasMe ~= b.hasMe then return a.hasMe end
    if a.knownCount ~= b.knownCount then return a.knownCount > b.knownCount end
    return a.meta.name < b.meta.name
end

-- ── 5. Line Builder ───────────────────────────────────────────────────────────
local function FormatRow(entry, itemID, multi)
    local r = entry.r
    local count = r.reagents and r.reagents[itemID] or 1
    local hex = (entry.state == STATE_KNOWN and DIFFICULTY_HEX[entry.diff]) or HEX_UNKNOWN
    local left = string_format("  |cff%s%s|r |cff%sx%d|r", hex, r.name or ("#" .. r.id), HEX_DIM, count)

    local right
    if entry.state == STATE_KNOWN then
        right = multi and JoinNames(entry.known, MAX_ROW_NAMES) or ""
    elseif entry.state == STATE_LEARNABLE then
        right = "|cff00ff88can learn|r"
        if multi then right = right .. " " .. JoinNames(entry.learn, MAX_ROW_NAMES) end
    else
        right = string_format("|cffffbb33needs %d|r", entry.minSkill)
        if multi then right = right .. " " .. JoinNames(entry.needs, MAX_ROW_NAMES) end
    end
    return { left, right }
end

local function BuildLines(itemID, expanded)
    local sids = sfui.recipes.GetRecipesUsingReagent(itemID)
    local recipes = sfui.recipes_camelot and sfui.recipes_camelot.recipes
    if not sids or not recipes then return false end

    local ros = roster or BuildRoster()
    local groups, groupList = {}, {}

    for _, sid in ipairs(sids) do
        local r = recipes[sid]
        local holders = r and r.skillID and ros[r.skillID]
        if holders then
            local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
            local entry = { r = r, minSkill = minSkill, known = {}, learn = {}, needs = {} }
            local bestRank = nil

            for _, h in ipairs(holders) do
                if IsKnownBy(r, minSkill, h) then
                    entry.known[#entry.known + 1] = h.label
                    if not bestRank or h.rank > bestRank then bestRank = h.rank end
                elseif h.rank >= minSkill then
                    entry.learn[#entry.learn + 1] = h.label
                else
                    entry.needs[#entry.needs + 1] = string_format("%s |cff%s(%d)|r", h.label, HEX_DIM, h.rank)
                end
            end

            entry.state = (#entry.known > 0 and STATE_KNOWN) or (#entry.learn > 0 and STATE_LEARNABLE) or STATE_NEEDS_SKILL
            entry.diff = GetDifficulty(r.colors, bestRank) or 4

            local g = groups[r.skillID]
            if not g then
                g = {
                    skillID    = r.skillID,
                    meta       = GetProfessionMeta(r.skillID),
                    holders    = holders,
                    hasMe      = holders[1] and holders[1].isMe or false,
                    entries    = {},
                    knownCount = 0,
                }
                groups[r.skillID] = g
                groupList[#groupList + 1] = g
            end
            g.entries[#g.entries + 1] = entry
            if entry.state == STATE_KNOWN then
                g.knownCount = g.knownCount + 1
            end
        end
    end

    if #groupList == 0 then return false end
    table_sort(groupList, CompareGroups)

    local maxCollapsed = (SfuiDB and tonumber(SfuiDB.recipesReagentMaxLines)) or DEFAULT_MAX_LINES
    local maxLines = expanded and SHIFT_MAX_LINES or maxCollapsed
    local lines = {}
    local expandable = false

    for _, g in ipairs(groupList) do
        table_sort(g.entries, CompareEntries)
        local multi = #g.holders > 1

        -- header: profession icon, name, known/total; holders with their rank
        local holderNames = {}
        for i = 1, #g.holders do
            local h = g.holders[i]
            holderNames[i] = string_format("%s |cff%s%d|r", h.label, HEX_DIM, h.rank)
        end
        lines[#lines + 1] = {
            string_format("%s |cffffd100%s|r |cff%s%d/%d|r", string_format(ICON_FMT, g.meta.icon), g.meta.name, HEX_DIM, g.knownCount, #g.entries),
            JoinNames(holderNames, MAX_HEADER_NAMES),
        }

        local shown, hidden, collapsedVisible = 0, 0, 0
        for _, entry in ipairs(g.entries) do
            local visible = expanded or entry.state ~= STATE_NEEDS_SKILL
            if entry.state ~= STATE_NEEDS_SKILL then
                collapsedVisible = collapsedVisible + 1
            else
                expandable = true
            end
            if visible and shown < maxLines then
                lines[#lines + 1] = FormatRow(entry, itemID, multi)
                shown = shown + 1
            elseif visible then
                hidden = hidden + 1
            end
        end
        if collapsedVisible > maxCollapsed then
            expandable = true
        end
        if hidden > 0 then
            lines[#lines + 1] = { string_format("  |cff%s+%d more|r", HEX_DIM, hidden), "" }
        end
    end

    if expandable and not expanded then
        lines[#lines + 1] = { string_format("|cff%shold shift to show all recipes|r", HEX_DIM), "" }
    end
    lines.expandable = expandable
    return lines
end

-- ── 6. Tooltip Rendering & Cache ──────────────────────────────────────────────
local lineCache = {} -- [itemID] = { [1] = lines|false, [2] = lines|false } (2 = shift held)

function R.InvalidateCache()
    wipe(lineCache)
    roster = nil
end
sfui.recipes.InvalidateReagentCache = R.InvalidateCache

--- Append the "used in" reagent section to an item tooltip
--- @param tooltip table GameTooltip-like frame
--- @param itemID number
--- @return boolean added
function sfui.recipes.AddReagentUseLines(tooltip, itemID)
    if not tooltip or not itemID then return false end
    if SfuiDB and SfuiDB.recipesShowReagentUses == false then return false end
    -- fast exit for the vast majority of items that are not reagents
    if not sfui.recipes.GetRecipesUsingReagent(itemID) then return false end

    local expanded = (IsShiftKeyDown and IsShiftKeyDown()) and true or false
    local slot = expanded and 2 or 1
    local entry = lineCache[itemID]
    if not entry then
        entry = {}
        lineCache[itemID] = entry
    end
    local lines = entry[slot]
    if lines == nil then
        lines = BuildLines(itemID, expanded)
        entry[slot] = lines
    end
    if not lines then return false end

    tooltip:AddLine(" ")
    for i = 1, #lines do
        local l = lines[i]
        if l[2] ~= "" then
            tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1)
        else
            tooltip:AddLine(l[1], 1, 1, 1)
        end
    end
    tooltip._sfuiReagentExpandable = lines.expandable or nil
    -- TooltipDataHandlerMixin:InternalProcessInfo shows the tooltip itself after running
    -- post-calls; only re-show (resize) an already visible tooltip for legacy hook paths,
    -- never pop up a hidden one.
    if tooltip:IsShown() then
        tooltip:Show()
    end
    return true
end

-- ── 7. Events: Shift Expand & Cache Invalidation ──────────────────────────────
local function ClearTooltipFlag(tooltip)
    if tooltip then tooltip._sfuiReagentExpandable = nil end
end

local function GetTrackedTooltips()
    return _G.GameTooltip, _G.ItemRefTooltip, sfui.tooltip
end

local tooltipsHooked = false
local function HookTooltipClears()
    if tooltipsHooked then return end
    tooltipsHooked = true
    local a, b, c = GetTrackedTooltips()
    if a then a:HookScript("OnTooltipCleared", ClearTooltipFlag) end
    if b and b ~= a then b:HookScript("OnTooltipCleared", ClearTooltipFlag) end
    if c and c ~= a and c ~= b then c:HookScript("OnTooltipCleared", ClearTooltipFlag) end
end
HookTooltipClears()

local function RefreshIfExpandable(tooltip)
    if tooltip and tooltip._sfuiReagentExpandable and tooltip:IsShown() and tooltip.RefreshData then
        tooltip:RefreshData()
    end
end

if sfui.events then
    sfui.events.RegisterEvent("MODIFIER_STATE_CHANGED", function(_, key)
        if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
        local a, b, c = GetTrackedTooltips()
        RefreshIfExpandable(a)
        if b ~= a then RefreshIfExpandable(b) end
        if c ~= a and c ~= b then RefreshIfExpandable(c) end
    end)

    local function OnDataChanged()
        R.InvalidateCache()
    end
    sfui.events.RegisterEvent("SKILL_LINES_CHANGED", OnDataChanged)
    sfui.events.RegisterEvent("NEW_RECIPE_LEARNED", OnDataChanged)
    sfui.events.RegisterEvent("SPELLS_CHANGED", OnDataChanged)
    if sfui.events.RegisterMessage then
        sfui.events.RegisterMessage("SFUI_ALT_SYNCED", OnDataChanged)
        sfui.events.RegisterMessage("SFUI_RECIPE_KNOWN_UPDATED", OnDataChanged)
        sfui.events.RegisterMessage("SFUI_RECIPE_BATCH_UPDATED", OnDataChanged)
        sfui.events.RegisterMessage("SFUI_SYNC_STATUS_UPDATED", OnDataChanged)
    end
end

-- ── 8. Telemetry ──────────────────────────────────────────────────────────────
local _debug = {}
function R.GetDebugInfo()
    local reagents, links = 0, 0
    if reagentIndex then
        for _, list in pairs(reagentIndex) do
            reagents = reagents + 1
            links = links + #list
        end
    end
    local cached = 0
    for _ in pairs(lineCache) do cached = cached + 1 end
    _debug.indexBuilt = reagentIndex ~= nil
    _debug.reagents = reagents
    _debug.links = links
    _debug.cachedItems = cached
    return _debug
end
