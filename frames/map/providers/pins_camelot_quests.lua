local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/map/providers/pins_camelot_quests.lua
--  worldmap pin provider: camelot iconic questlines & discoveries
--  - cozy sleeping bag questline (alliance & horde progression)
--  - an unfortunate end (duskwood night watchman's torch)
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local pins = sfui.pins
if not pins then return end

local _G                  = _G
local ipairs              = _G.ipairs
local tostring            = _G.tostring
local string_format       = string.format
local table_insert        = _G.table.insert

-- ─── Player Faction Detection ─────────────────────────────────────────────────
local playerFaction = "Alliance"
if _G.UnitFactionGroup then
    local f = _G.UnitFactionGroup("player")
    if f and f ~= "" then
        playerFaction = f
    end
end

-- ─── Configuration & Options ──────────────────────────────────────────────────
if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("camelot_quests", {
        hideCompleted   = true,
        showSleepingBag = true,
        showTorch       = true,
    })
end

local function GetOption(key)
    if sfui.db and sfui.db.Get then
        local val = sfui.db.Get("camelot_quests", key)
        if val ~= nil then return val end
    end
    if SfuiDB and SfuiDB.camelotQuests and SfuiDB.camelotQuests[key] ~= nil then
        return SfuiDB.camelotQuests[key]
    end
    if key == "hideCompleted" then return true end
    if key == "showSleepingBag" then return true end
    if key == "showTorch" then return true end
    return true
end

local function SetOption(key, val)
    if sfui.db and sfui.db.Set then
        sfui.db.Set("camelot_quests", key, val)
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.camelotQuests = SfuiDB.camelotQuests or {}
    SfuiDB.camelotQuests[key] = val
    pins.RequestRefresh(0)
end

sfui.camelot_quests = sfui.camelot_quests or {}
sfui.camelot_quests.GetOption = GetOption
sfui.camelot_quests.SetOption = SetOption
function sfui.camelot_quests.UpdatePins() pins.RequestRefresh(0) end

-- ─── Quest Progression Data: Cozy Sleeping Bag ────────────────────────────────
-- alliance: westfall (cart) -> the barrens (tower) -> stonetalon -> loch modan -> hillsbrad
-- horde:    the barrens (tower) -> westfall (cart) -> stonetalon -> loch modan -> hillsbrad

local SLEEPING_BAG_STEPS = {
    Alliance = {
        [1] = {
            stepNumber   = 1,
            title        = "alexston farmstead wreckage",
            zoneName     = "westfall",
            mapID        = 1436,
            x            = 0.374,
            y            = 0.508,
            objectName   = "burned-out remains",
            questID      = 79008,
            questName    = "... and that note you found",
            locationName = "alexston farmstead",
            action       = "inspect the burned-out remains in the cart wreckage to accept quest",
            notes        = "requires level 14. smoldering rubble in the farmstead courtyard",
        },
        [2] = {
            stepNumber   = 2,
            title        = "burnt tower rubble",
            zoneName     = "the barrens",
            mapID        = 1413,
            x            = 0.460,
            y            = 0.740,
            objectName   = "burned-out remains",
            questID      = 79192,
            questName    = "stepping stones",
            locationName = "south of camp taurajo",
            action       = "turn in '... and that note you found' and accept 'stepping stones'",
            notes        = "follow the high road south of camp taurajo to the burnt tower ruins",
        },
    },
    Horde = {
        [1] = {
            stepNumber   = 1,
            title        = "burnt tower rubble",
            zoneName     = "the barrens",
            mapID        = 1413,
            x            = 0.460,
            y            = 0.740,
            objectName   = "burned-out remains",
            questID      = 79007,
            questName    = "... and that note you found",
            locationName = "south of camp taurajo",
            action       = "inspect the burned-out remains in the tower rubble to accept quest",
            notes        = "requires level 14. ruins along the road south of camp taurajo",
        },
        [2] = {
            stepNumber   = 2,
            title        = "alexston farmstead wreckage",
            zoneName     = "westfall",
            mapID        = 1436,
            x            = 0.374,
            y            = 0.508,
            objectName   = "burned-out remains",
            questID      = 79192,
            questName    = "stepping stones",
            locationName = "alexston farmstead",
            action       = "turn in '... and that note you found' and accept 'stepping stones'",
            notes        = "in the cart rubble at alexston farmstead in westfall",
        },
    },
    Shared = {
        [3] = {
            stepNumber   = 3,
            title        = "abandoned peak camp",
            zoneName     = "stonetalon mountains",
            mapID        = 1442,
            x            = 0.406,
            y            = 0.524,
            objectName   = "pocket litter",
            questID      = 79980,
            questName    = "scramble",
            locationName = "sun rock retreat ridge",
            action       = "turn in 'stepping stones' and accept 'scramble' by clicking pocket litter on the crate",
            notes        = "path begins northeast of sun rock retreat at (50.9, 52.3). optional: click campfire to complete 'rekindle'",
            trailX       = 0.509,
            trailY       = 0.523,
        },
        [4] = {
            stepNumber   = 4,
            title        = "mountain ridge mound of dirt",
            zoneName     = "stonetalon mountains",
            mapID        = 1442,
            x            = 0.396,
            y            = 0.498,
            objectName   = "mound of dirt",
            questID      = 79974,
            questName    = "wet job",
            locationName = "ridge north of abandoned camp",
            action       = "climb the hill north of camp, jump the ledge gap, and click the mound of dirt",
            notes        = "complete 'scramble' and accept 'wet job'",
        },
        [5] = {
            stepNumber   = 5,
            title        = "stonewrought dam eagle heads",
            zoneName     = "loch modan",
            mapID        = 1432,
            x            = 0.494,
            y            = 0.129,
            objectName   = "eagle figurine",
            questID      = 79975,
            questName    = "eagle's fist",
            locationName = "loch modan dam",
            action       = "jump down onto the stone carved eagle heads facing wetlands to click the eagle figurine",
            notes        = "complete 'wet job' and accept 'eagle's fist'",
        },
        [6] = {
            stepNumber   = 6,
            title        = "thoradin's wall pocket",
            zoneName     = "hillsbrad foothills",
            mapID        = 1424,
            x            = 0.873,
            y            = 0.496,
            altMapID     = 1417,
            altX         = 0.224,
            altY         = 0.728,
            objectName   = "messenger bag & satchel",
            questID      = 79976,
            questName    = "this must be the place",
            locationName = "thoradin's wall",
            action       = "climb the cart on the hillsbrad side into the wall room. click hanging messenger bag, then loot satchel below it",
            reward       = "cozy sleeping bag (item 211527) & student fodder",
            notes        = "awards cozy sleeping bag (+3% exp buff and rested generation) and 5x student fodder",
        },
    },
}

-- ─── Sleeping Bag Step Progression Resolver ───────────────────────────────────
local function GetCurrentSleepingBagStep()
    local isAlliance = (playerFaction == "Alliance")
    local startQ = isAlliance and 79008 or 79007

    if pins.GetItemCountInBags(211527) > 0 or pins.IsQuestCompleted(79976) then
        return 7 -- fully completed
    end

    if pins.IsQuestCompleted(79975) or pins.IsQuestActive(79976) or pins.IsQuestActive(79975) then
        return 6
    end

    if pins.IsQuestCompleted(79974) or pins.IsQuestActive(79974) then
        return 5
    end

    if pins.IsQuestCompleted(79980) or pins.IsQuestActive(79980) then
        return 4
    end

    if pins.IsQuestCompleted(79192) or pins.IsQuestActive(79192) then
        return 3
    end

    if pins.IsQuestCompleted(startQ) or pins.IsQuestActive(startQ) then
        return 2
    end

    return 1
end
sfui.camelot_quests.GetCurrentSleepingBagStep = GetCurrentSleepingBagStep

-- ─── Quest Progression Data: An Unfortunate End ───────────────────────────────
-- duskwood (mapid 1431): patrol spawns of fallen night watch guard corpse
-- quest 98372 (horde/neutral) / 99267 (alliance)
-- reward: night watchman's torch (item 280612)

local TORCH_SPAWNS = {
    {
        id          = "duskwood_torch_1",
        mapID       = 1431,
        x           = 0.171,
        y           = 0.546,
        description = "western road near the raven hill cemetery fork",
    },
    {
        id          = "duskwood_torch_2",
        mapID       = 1431,
        x           = 0.235,
        y           = 0.333,
        description = "north road near raven hill by the river boundary",
    },
    {
        id          = "duskwood_torch_3",
        mapID       = 1431,
        x           = 0.455,
        y           = 0.793,
        description = "southern border road near the mountain pass",
    },
    {
        id          = "duskwood_torch_4",
        mapID       = 1431,
        x           = 0.475,
        y           = 0.596,
        description = "central crossroads south of darkshire and addle's stead",
    },
    {
        id          = "duskwood_torch_5",
        mapID       = 1431,
        x           = 0.660,
        y           = 0.338,
        description = "eastern road heading north towards manor mistmantle",
    },
    {
        id          = "duskwood_torch_6",
        mapID       = 1431,
        x           = 0.688,
        y           = 0.694,
        description = "south-eastern road leading to twilight grove / darkened bank",
    },
}

local function IsTorchCompleted()
    return pins.IsQuestCompleted(98372)
        or pins.IsQuestCompleted(99267)
        or pins.GetItemCountInBags(280612) > 0
end
sfui.camelot_quests.IsTorchCompleted = IsTorchCompleted

-- ─── Interactive Tooltip Handlers ─────────────────────────────────────────────
local function OnEnterSleepingBagPin(pin, tooltip, data)
    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    local step = data.step
    local status = data.status
    local isCurrent = data.isCurrent

    tooltip:AddLine(string_format("cozy sleeping bag  ·  step %d", step.stepNumber), 1.0, 0.82, 0.0)
    tooltip:AddLine(step.title, 0.20, 0.85, 1.0)
    tooltip:AddLine(string_format("%s  ·  %s", step.locationName, step.zoneName), 0.70, 0.70, 0.70)
    tooltip:AddLine(" ")

    if status == "completed" then
        tooltip:AddLine("|cff00ff00status: completed|r")
    elseif isCurrent then
        tooltip:AddLine("|cffffcc00status: current objective|r")
    else
        tooltip:AddLine("|cff888888status: upcoming step|r")
    end

    if step.action then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cfffffffftask:|r " .. step.action, 0.90, 0.90, 0.90, true)
    end
    if step.notes then
        tooltip:AddLine("|cffaaaaaanotes:|r " .. step.notes, 0.75, 0.75, 0.75, true)
    end
    if step.reward then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cff00ff00reward:|r " .. step.reward, 0.20, 1.00, 0.40)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff80c0ffshift-click: set map waypoint|r", 0.70, 0.70, 0.70)
    tooltip:Show()
end

local function OnEnterSleepingBagTrailhead(pin, tooltip, data)
    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    tooltip:AddLine("cozy sleeping bag  ·  trailhead", 1.0, 0.82, 0.0)
    tooltip:AddLine("path to abandoned peak camp", 0.20, 0.85, 1.0)
    tooltip:AddLine("stonetalon mountains  ·  northeast of sun rock retreat", 0.70, 0.70, 0.70)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cfffffffffollow this mountain incline northeast to reach the abandoned camp for step 3.|r", 0.85, 0.85, 0.85, true)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff80c0ffshift-click: set map waypoint|r", 0.70, 0.70, 0.70)
    tooltip:Show()
end

local function OnEnterTorchPin(pin, tooltip, data)
    tooltip:SetOwner(pin, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    local spawn = data.spawn
    local isCompleted = data.isCompleted

    tooltip:AddLine("an unfortunate end", 1.0, 0.60, 0.15)
    tooltip:AddLine("fallen night watch guard corpse", 0.20, 0.85, 1.0)
    tooltip:AddLine("duskwood patrol spawn point", 0.70, 0.70, 0.70)
    tooltip:AddLine(" ")

    if isCompleted then
        tooltip:AddLine("|cff00ff00status: torch acquired / completed|r")
    else
        tooltip:AddLine("|cffff9900status: available (patrol spawn)|r")
    end

    if spawn.description then
        tooltip:AddLine(" ")
        tooltip:AddLine("|cffaaaaaalocation:|r " .. spawn.description, 0.85, 0.85, 0.85, true)
    end

    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff00reward:|r night watchman's torch (item 280612)", 0.20, 1.00, 0.40)
    tooltip:AddLine("|cffaaaaaareveals things hidden by darkness across duskwood.|r", 0.65, 0.65, 0.65, true)
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff80c0ffshift-click: set map waypoint|r", 0.70, 0.70, 0.70)
    tooltip:Show()
end

-- ─── Pin Provider Implementation ──────────────────────────────────────────────
local function GetCamelotQuestPins(mapID)
    local out = {}
    local hideCompleted = GetOption("hideCompleted")

    -- 1. Cozy Sleeping Bag Questline
    if GetOption("showSleepingBag") then
        local currentStep = GetCurrentSleepingBagStep()
        local factionSteps = SLEEPING_BAG_STEPS[playerFaction] or SLEEPING_BAG_STEPS.Alliance
        local sharedSteps  = SLEEPING_BAG_STEPS.Shared

        local allSteps = {
            factionSteps[1],
            factionSteps[2],
            sharedSteps[3],
            sharedSteps[4],
            sharedSteps[5],
            sharedSteps[6],
        }

        for idx, step in ipairs(allSteps) do
            local matchesMap = (step.mapID == mapID) or (step.altMapID == mapID)
            if matchesMap then
                local isStepDone = (idx < currentStep)
                local isCurrent  = (idx == currentStep)

                if not (hideCompleted and isStepDone) then
                    local targetX = (step.altMapID == mapID) and step.altX or step.x
                    local targetY = (step.altMapID == mapID) and step.altY or step.y

                    local borderColor
                    local countColor
                    local desaturated = false
                    local vertexColor = { 1, 1, 1, 1 }
                    local size = 20

                    if isStepDone then
                        borderColor = { 0.35, 0.35, 0.35, 0.8 }
                        desaturated = true
                        vertexColor = { 0.60, 0.60, 0.60, 0.8 }
                        countColor  = { 0.50, 0.50, 0.50, 0.8 }
                        size        = 18
                    elseif isCurrent then
                        borderColor = { 1.00, 0.82, 0.00, 1.0 }
                        countColor  = { 1.00, 0.90, 0.20, 1.0 }
                        size        = 22
                    else
                        borderColor = { 0.20, 0.75, 1.00, 0.9 }
                        countColor  = { 0.70, 0.85, 1.00, 1.0 }
                        size        = 20
                    end

                    local pinData = {
                        id          = string_format("sleeping_bag_%d_%d", idx, mapID),
                        provider    = "camelot_quests",
                        mapID       = mapID,
                        x           = targetX,
                        y           = targetY,
                        size        = size,
                        icon        = "Interface\\Icons\\INV_Misc_Bag_BigBagOfEnchantments",
                        desaturated = desaturated,
                        vertexColor = vertexColor,
                        borderColor = borderColor,
                        countText   = tostring(step.stepNumber),
                        countColor  = countColor,
                        title       = string_format("cozy sleeping bag: step %d", step.stepNumber),
                        step        = step,
                        status      = isStepDone and "completed" or (isCurrent and "active" or "future"),
                        isCurrent   = isCurrent,
                        OnEnter     = OnEnterSleepingBagPin,
                    }
                    table_insert(out, pinData)

                    -- Trailhead helper pin on Stonetalon Mountains for step 3
                    if idx == 3 and mapID == 1442 and step.trailX and step.trailY then
                        local trailDone = isStepDone
                        if not (hideCompleted and trailDone) then
                            local trailPin = {
                                id          = "sleeping_bag_trailhead_1442",
                                provider    = "camelot_quests",
                                mapID       = mapID,
                                x           = step.trailX,
                                y           = step.trailY,
                                size        = 18,
                                icon        = "Interface\\Icons\\INV_Misc_Map02",
                                desaturated = trailDone,
                                vertexColor = trailDone and { 0.6, 0.6, 0.6, 0.8 } or { 1, 1, 1, 1 },
                                borderColor = isCurrent and { 1.00, 0.82, 0.00, 1.0 } or { 0.20, 0.75, 1.00, 0.9 },
                                countText   = "3",
                                countColor  = isCurrent and { 1.00, 0.90, 0.20, 1.0 } or { 0.70, 0.85, 1.00, 1.0 },
                                title       = "trailhead to abandoned camp",
                                step        = step,
                                OnEnter     = OnEnterSleepingBagTrailhead,
                            }
                            table_insert(out, trailPin)
                        end
                    end
                end
            end
        end
    end

    -- 2. An Unfortunate End (Night Watchman's Torch in Duskwood)
    if GetOption("showTorch") and mapID == 1431 then
        local torchDone = IsTorchCompleted()
        if not (hideCompleted and torchDone) then
            for _, spawn in ipairs(TORCH_SPAWNS) do
                local borderColor
                local desaturated = false
                local vertexColor = { 1, 1, 1, 1 }

                if torchDone then
                    borderColor = { 0.35, 0.35, 0.35, 0.8 }
                    desaturated = true
                    vertexColor = { 0.60, 0.60, 0.60, 0.8 }
                else
                    borderColor = { 1.00, 0.55, 0.10, 1.0 }
                end

                local pinData = {
                    id          = spawn.id,
                    provider    = "camelot_quests",
                    mapID       = mapID,
                    x           = spawn.x,
                    y           = spawn.y,
                    size        = torchDone and 18 or 20,
                    icon        = "Interface\\Icons\\INV_Torch_Lit",
                    desaturated = desaturated,
                    vertexColor = vertexColor,
                    borderColor = borderColor,
                    title       = "an unfortunate end",
                    spawn       = spawn,
                    isCompleted = torchDone,
                    OnEnter     = OnEnterTorchPin,
                }
                table_insert(out, pinData)
            end
        end
    end

    return out
end

-- ─── Provider & WorldMap Tracking Menu Registration ───────────────────────────
pins.RegisterProvider("camelot_quests", {
    priority    = 15,
    defaultSize = 20,
    enabled     = function()
        return GetOption("showSleepingBag") or GetOption("showTorch")
    end,
    GetPins     = GetCamelotQuestPins,
})

pins.RegisterTrackingCategory("camelot quests", {
    {
        text = "cozy sleeping bag questline",
        get  = function() return GetOption("showSleepingBag") end,
        set  = function(v) SetOption("showSleepingBag", v) end,
    },
    {
        text = "an unfortunate end (torch)",
        get  = function() return GetOption("showTorch") end,
        set  = function(v) SetOption("showTorch", v) end,
    },
    {
        text = "hide completed quests",
        get  = function() return GetOption("hideCompleted") end,
        set  = function(v) SetOption("hideCompleted", v) end,
    },
})

-- ─── Event Invalidation Hook ──────────────────────────────────────────────────
if sfui.events and sfui.events.RegisterEvent then
    sfui.events.RegisterEvent("QUEST_TURNED_IN", function()
        pins.InvalidateQuestCache()
        pins.RequestRefresh(0)
    end)
    sfui.events.RegisterEvent("BAG_UPDATE_DELAYED", function()
        pins.RequestRefresh(0)
    end)
end
