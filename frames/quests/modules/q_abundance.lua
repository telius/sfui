local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.abundance = sfui.abundance or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/quests/modules/q_abundance.lua
--  Dedicated Midnight Abundance World Event Scenario Tracker Module
--
--  Features:
--    - Active Abundance Scenario Detection (4 regional caverns & harvests)
--    - Dynamic multi-stage capacity tracking ("Abundance Held" 0 / max per stage)
--    - 3-minute stage countdown timer (ScenarioHeaderTimer widget & timer bar)
--    - Dundun's Blessing of Abundance tracking (spell 1229266: tiers, stats, altar goal)
--    - Altar turn-in alert when bag hits capacity (prevents wasted material drops)
--    - Strict Zero-Inspection / Direct Forwarding for protected & secret values
--    - Complete combat lockdown safety (no comparisons, arithmetic or formats on secret values)
-- ══════════════════════════════════════════════════════════════════════════════

-- ─── Localize Globals for Zero-Taint & High Performance ─────────────────────
local _G                     = _G
local C_Scenario             = _G.C_Scenario
local C_ScenarioInfo         = _G.C_ScenarioInfo
local C_UIWidgetManager      = _G.C_UIWidgetManager
local C_UnitAuras            = _G.C_UnitAuras
local C_TooltipInfo          = _G.C_TooltipInfo
local Enum                   = _G.Enum
local InCombatLockdown       = _G.InCombatLockdown
local ipairs, pairs, type    = _G.ipairs, _G.pairs, _G.type
local tonumber, tostring     = _G.tonumber, _G.tostring
local math_floor, math_max   = _G.math.floor, _G.math.max
local string_format          = _G.string.format
local table_insert           = _G.table.insert
local table_concat           = _G.table.concat
local issecretvalue          = (sfui.common and sfui.common.issecretvalue) or _G.issecretvalue or function() return false end

-- ─── Constants & Spell IDs ──────────────────────────────────────────────────
local BLESSING_SPELL_ID      = 1229266 -- Blessing of Abundance (Dundun's buff)
local SCENARIO_TOP_WIDGET_SET= 514     -- SCENARIO_TRACKER_TOP_WIDGET_SET

-- Widget visualization type constants
local TYPE_STATUS_BAR        = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.StatusBar) or 2
local TYPE_SCENARIO_TIMER    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.ScenarioHeaderTimer) or 20
local TYPE_UNIT_POWER_BAR    = (Enum and Enum.UIWidgetVisualizationType and Enum.UIWidgetVisualizationType.UnitPowerBar) or 23

-- Default carrying capacity thresholds by scenario stage
local STAGE_CAPACITIES       = {
    [1] = 1500,
    [2] = 2500,
    [3] = 5000,
}

local COLOR_ABUNDANCE_GOLD   = { 1.00, 0.78, 0.15, 0.95 }
local COLOR_ABUNDANCE_FULL   = { 1.00, 0.25, 0.20, 0.95 }
local COLOR_SECTION_HEADER   = { 1.00, 0.78, 0.15 }

-- ─── Scenario Active Detection ──────────────────────────────────────────────
function sfui.abundance.IsActive()
    local inScenario = C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
    if not inScenario then
        return false
    end

    local name = nil
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local sInfo = C_ScenarioInfo.GetScenarioInfo()
        name = sInfo and sInfo.name
    elseif C_Scenario and C_Scenario.GetInfo then
        name = C_Scenario.GetInfo()
    end

    if name and not issecretvalue(name) and type(name) == "string" and name:lower():find("abundance") then
        return true
    end

    -- Check if player has Blessing of Abundance active
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(BLESSING_SPELL_ID)
        if aura then
            return true
        end
    end

    return false
end

-- ─── Blessing of Abundance Tooltip Parser ───────────────────────────────────
local function GetBlessingDetails(aura)
    if not aura or InCombatLockdown() then
        return nil
    end

    local tier = nil
    local speed = nil
    local stat = nil
    local radius = nil
    local altarProgress = nil

    if C_TooltipInfo and aura.auraInstanceID then
        local getter = C_TooltipInfo.GetUnitBuffByAuraInstanceID or C_TooltipInfo.GetUnitAuraByAuraInstanceID
        if getter then
            local ok, data = pcall(getter, "player", aura.auraInstanceID)
            if ok and data and data.lines then
                for _, l in ipairs(data.lines) do
                    local txt = l.leftText
                    if txt and txt ~= "" and not issecretvalue(txt) then
                        local tMatch = txt:match("[Tt]ier%s*(%d+)")
                        if tMatch and not tier then
                            tier = tonumber(tMatch)
                        end

                        local spMatch = txt:match("%+(%d+%%%s*Movement%s*Speed)")
                        if spMatch then
                            speed = spMatch:lower()
                        end

                        local stMatch = txt:match("%+(%d+%%%s*Primary%s*Stat)")
                        if stMatch then
                            stat = stMatch:lower()
                        end

                        local rMatch = txt:match("%+(%d+%s*Pickup%s*Yard%s*Radius)")
                        if rMatch then
                            radius = rMatch:lower()
                        end

                        if txt:find("Altar") or txt:find("Contribute") then
                            local cCur, cMax = txt:match("(%d+)%s*/%s*(%d+)")
                            if cCur and cMax then
                                altarProgress = string_format("%d/%d", cCur, cMax)
                            end
                        end
                    end
                end
            end
        end
    end

    return {
        tier          = tier or 1,
        speed         = speed,
        stat          = stat,
        radius        = radius,
        altarProgress = altarProgress,
    }
end

-- ─── Criteria Extractor ─────────────────────────────────────────────────────
local function GetCriteriaInfo(criteriaIndex)
    if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
        local info = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
        if info and type(info) == "table" and (info.description or info.criteriaString or info.string) then
            return info
        end
    end
    if C_Scenario and C_Scenario.GetCriteriaInfo then
        local desc, cType, comp, quant, totQuant, flags, assetID, quantStr = C_Scenario.GetCriteriaInfo(criteriaIndex)
        if desc and desc ~= "" and not issecretvalue(desc) then
            return {
                description    = desc,
                criteriaType   = cType,
                completed      = comp,
                quantity       = quant,
                totalQuantity  = totQuant,
                quantityString = quantStr,
            }
        end
    end
    return nil
end

-- ─── Tracker Content Module Protocol ────────────────────────────────────────
local AbundanceModule = {
    id       = "abundance",
    priority = 8, -- Display at very top above standard scenarios and quests
    events   = {
        "SCENARIO_UPDATE",
        "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_STAGE_UPDATE",
        "SCENARIO_SPELL_UPDATE",
        "SCENARIO_COMPLETED",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_ENTERING_WORLD",
        "UPDATE_UI_WIDGET",
        "UPDATE_ALL_UI_WIDGETS",
        "UNIT_AURA",
    },
}

function AbundanceModule:Init(engine)
    self.engine = engine
end

function AbundanceModule:IsEnabled()
    return true
end

function AbundanceModule:OnEvent(event, arg1, ...)
    if event == "UNIT_AURA" and arg1 ~= "player" then
        return
    end
    self:MarkDirty()
end

local GetQLState = sfui.questlog.GetState

function AbundanceModule:BuildBlocks(container)
    if not sfui.abundance.IsActive() then
        return {}
    end

    local inCombat = InCombatLockdown and InCombatLockdown()

    -- 1. Query Scenario Base Information
    local name, currentStage, numStages, scenarioType = nil, nil, nil, nil
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local sInfo = C_ScenarioInfo.GetScenarioInfo()
        if sInfo then
            name = sInfo.name
            currentStage = sInfo.currentStage
            numStages = sInfo.numStages
            scenarioType = sInfo.scenarioType
        end
    elseif C_Scenario and C_Scenario.GetInfo then
        name, currentStage, numStages, _, _, _, _, _, _, scenarioType = C_Scenario.GetInfo()
    end

    currentStage = (currentStage and not issecretvalue(currentStage) and type(currentStage) == "number") and currentStage or 1
    numStages    = (numStages and not issecretvalue(numStages) and type(numStages) == "number") and numStages or 1

    local stageName, stageDesc, numCriteria, stepFailed = nil, nil, 0, false
    local widgetSetID = nil
    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
        local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
        if stepInfo then
            stageName   = stepInfo.title
            stageDesc   = stepInfo.description
            numCriteria = stepInfo.numCriteria or 0
            stepFailed  = stepInfo.failed
            widgetSetID = stepInfo.widgetSetID
        end
    elseif C_Scenario and C_Scenario.GetStepInfo then
        local _, _, nCrit, sFailed, _, _, _, _, _, _, _, wSet = C_Scenario.GetStepInfo()
        numCriteria = nCrit or 0
        stepFailed  = sFailed
        widgetSetID = wSet
    end

    -- 2. Build Stage Header & Title
    local stageTitle = name or "abundance"
    if stageName and stageName ~= "" and not issecretvalue(stageName) then
        if numStages and numStages > 1 then
            stageTitle = string_format("stage %d/%d: %s", currentStage, numStages, stageName:lower())
        else
            stageTitle = stageName:lower()
        end
    else
        stageTitle = string_format("stage %d/%d", currentStage, numStages)
    end

    -- 3. Collect Widget Set Candidates
    local widgetCandidates = {}
    if widgetSetID and not issecretvalue(widgetSetID) and type(widgetSetID) == "number" and widgetSetID > 0 then
        table_insert(widgetCandidates, widgetSetID)
    end
    if C_UIWidgetManager and C_UIWidgetManager.GetObjectiveTrackerWidgetSetID then
        local otSetID = C_UIWidgetManager.GetObjectiveTrackerWidgetSetID()
        if otSetID and not issecretvalue(otSetID) and type(otSetID) == "number" and otSetID > 0 then
            table_insert(widgetCandidates, otSetID)
        end
    end
    table_insert(widgetCandidates, SCENARIO_TOP_WIDGET_SET)

    -- 4. Process Scenario Widgets (Timer & Carrying Capacity StatusBar)
    local timerInfo = nil
    local capacityInfo = nil
    local seenWidgets = {}

    for _, wSet in ipairs(widgetCandidates) do
        if C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID then
            local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(wSet)
            if widgets and type(widgets) == "table" then
                for _, w in ipairs(widgets) do
                    local wID = (type(w) == "table" and w.widgetID) or (type(w) == "number" and w)
                    local wType = (type(w) == "table" and w.widgetType)
                    if wID and not seenWidgets[wID] then
                        seenWidgets[wID] = true

                        -- A. Scenario Countdown Timer
                        if not timerInfo and (wType == nil or wType == TYPE_SCENARIO_TIMER) and C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo then
                            local tInfo = C_UIWidgetManager.GetScenarioHeaderTimerWidgetVisualizationInfo(wID)
                            if tInfo and tInfo.shownState ~= 0 and tInfo.shownState ~= (Enum and Enum.WidgetShownState and Enum.WidgetShownState.Hidden) then
                                timerInfo = tInfo
                            end
                        end

                        -- B. Abundance Held Status Bar / Unit Power Bar
                        if not capacityInfo and (wType == nil or wType == TYPE_STATUS_BAR or wType == TYPE_UNIT_POWER_BAR) then
                            local sInfo = nil
                            if (wType == TYPE_UNIT_POWER_BAR or wType == nil) and C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo then
                                sInfo = C_UIWidgetManager.GetUnitPowerBarWidgetVisualizationInfo(wID)
                            end
                            if not sInfo and C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo then
                                sInfo = C_UIWidgetManager.GetStatusBarWidgetVisualizationInfo(wID)
                            end

                            if sInfo and sInfo.shownState ~= 0 and sInfo.shownState ~= (Enum and Enum.WidgetShownState and Enum.WidgetShownState.Hidden) then
                                capacityInfo = sInfo
                            end
                        end
                    end
                end
            end
        end
    end

    -- 5. Format Lines, Timer, and Progress Bar
    local lines = {}
    local progressBar = nil
    local timerBar = nil

    -- A. Countdown Timer Display
    if timerInfo then
        local isTimeSec = issecretvalue(timerInfo.timerValue) or issecretvalue(timerInfo.timerMin) or issecretvalue(timerInfo.timerMax)
        if isTimeSec or inCombat then
            table_insert(lines, {
                text      = "|cffffcc00time remaining:|r active",
                completed = false,
            })
        else
            local tMin = timerInfo.timerMin or 0
            local tMax = timerInfo.timerMax or 0
            local tVal = timerInfo.timerValue or 0
            local rem = 0
            if tMax > tMin and tVal >= tMin then
                rem = tVal - tMin
            elseif tVal > 0 then
                rem = tVal
            end
            local timeStr = string_format("%02d:%02d", math_floor(rem / 60), rem % 60)
            table_insert(lines, {
                text      = string_format("|cffffcc00time remaining:|r %s", timeStr),
                completed = (rem <= 0),
            })

            local totalTime = (tMax > tMin and (tMax - tMin)) or 180
            local elapsed = (tMax > tMin and (tMax - tVal)) or math_max(0, 180 - rem)
            if totalTime > 0 then
                timerBar = {
                    timeTotal   = totalTime,
                    timeElapsed = elapsed,
                }
            end
        end
    end

    -- B. Scenario Objectives & Criteria
    if numCriteria and numCriteria > 0 then
        for i = 1, numCriteria do
            local crit = GetCriteriaInfo(i)
            if crit then
                local desc = crit.description or crit.criteriaString or crit.string
                local isComp = (crit.completed == true)
                if desc and desc ~= "" and not issecretvalue(desc) then
                    local cleanDesc = desc:gsub(" / ", "/"):lower()
                    table_insert(lines, {
                        text      = cleanDesc,
                        completed = isComp,
                    })
                end
            end
        end
    elseif stageDesc and stageDesc ~= "" and not issecretvalue(stageDesc) then
        table_insert(lines, {
            text      = stageDesc:lower(),
            completed = false,
        })
    end

    -- C. Dundun's Blessing of Abundance (Spell 1229266)
    local blessingAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and C_UnitAuras.GetPlayerAuraBySpellID(BLESSING_SPELL_ID)
    if blessingAura then
        if inCombat then
            table_insert(lines, {
                text      = "|cff20ff20blessing of abundance:|r active",
                completed = false,
            })
        else
            local bDetails = GetBlessingDetails(blessingAura)
            if bDetails then
                local perks = {}
                if bDetails.speed then table_insert(perks, bDetails.speed) end
                if bDetails.stat then table_insert(perks, bDetails.stat) end
                if bDetails.radius then table_insert(perks, bDetails.radius) end

                local perkStr = (#perks > 0) and (" (" .. table_concat(perks, ", ") .. ")") or ""
                table_insert(lines, {
                    text      = string_format("|cff20ff20blessing:|r tier %d%s", bDetails.tier, perkStr),
                    completed = false,
                })

                if bDetails.altarProgress then
                    table_insert(lines, {
                        text      = string_format("|cff9d9d9daltar goal:|r %s", bDetails.altarProgress),
                        completed = false,
                    })
                end
            end
        end
    end

    -- D. Multi-Stage Carrying Capacity Status Bar ("Abundance Held")
    local defaultCap = STAGE_CAPACITIES[currentStage] or 1500
    if capacityInfo then
        local isCurSec = issecretvalue(capacityInfo.barValue)
        local isMinSec = issecretvalue(capacityInfo.barMin)
        local isMaxSec = issecretvalue(capacityInfo.barMax)

        if isCurSec or isMinSec or isMaxSec or inCombat then
            -- Zero-inspection direct forwarding: never compare, arithmetic or string format secret values!
            local safeBarText = (capacityInfo.overrideBarText and not issecretvalue(capacityInfo.overrideBarText) and capacityInfo.overrideBarText ~= "" and capacityInfo.overrideBarText)
                or (capacityInfo.text and not issecretvalue(capacityInfo.text) and capacityInfo.text ~= "" and capacityInfo.text)
                or "abundance held"

            local isMaxed = (capacityInfo.isCurrencyMaxed == true)
            progressBar = {
                min   = (not isMinSec and capacityInfo.barMin) or 0,
                max   = (not isMaxSec and capacityInfo.barMax and capacityInfo.barMax > 0 and capacityInfo.barMax) or defaultCap,
                value = capacityInfo.barValue,
                text  = safeBarText,
                color = isMaxed and COLOR_ABUNDANCE_FULL or COLOR_ABUNDANCE_GOLD,
            }

            if isMaxed then
                table_insert(lines, {
                    text      = "|cffff3333>> bag full! deposit at an altar! <<|r",
                    completed = false,
                })
            end
        else
            -- Out of combat with validated numbers: format informative capacity progress
            local curVal = capacityInfo.barValue or 0
            local maxVal = (capacityInfo.barMax and capacityInfo.barMax > 0 and capacityInfo.barMax) or defaultCap
            local isMaxed = (curVal >= maxVal) or (capacityInfo.isCurrencyMaxed == true)

            local barLabel = isMaxed
                and string_format("abundance held: %d / %d (full - deposit!)", curVal, maxVal)
                or string_format("abundance held: %d / %d", curVal, maxVal)

            progressBar = {
                min   = 0,
                max   = maxVal,
                value = curVal,
                text  = barLabel,
                color = isMaxed and COLOR_ABUNDANCE_FULL or COLOR_ABUNDANCE_GOLD,
            }

            if isMaxed then
                table_insert(lines, {
                    text      = "|cffff3333>> bag full! deposit at an altar! <<|r",
                    completed = false,
                })
            end
        end
    else
        -- Fallback carrying bar when widget is waiting to initialize
        progressBar = {
            min   = 0,
            max   = defaultCap,
            value = 0,
            text  = string_format("capacity: %d (stage %d)", defaultCap, currentStage),
            color = COLOR_ABUNDANCE_GOLD,
        }
    end

    -- 6. Construct Block & Section
    local state = GetQLState()
    local expandedBlocks = state.expandedBlocks or {}
    local expandKey = "abundance_scenario"
    local isExpanded = (expandedBlocks[expandKey] ~= false)

    local block = {
        title       = stageTitle,
        titleColor  = stepFailed and { 1, 0.2, 0.2, 1 } or { 1, 0.85, 0.20, 1 },
        isScenario  = true,
        isExpanded  = isExpanded,
        lines       = lines,
        progressBar = progressBar,
        timerBar    = timerBar,
        OnClick     = function(b, btn)
            if btn == "RightButton" then
                local st = GetQLState()
                st.expandedBlocks = st.expandedBlocks or {}
                st.expandedBlocks[expandKey] = not isExpanded
                sfui.tracker.RequestRefresh(0.01)
                return
            end

            if sfui.map and sfui.map.ToggleWorldMap then
                sfui.map.ToggleWorldMap()
            end
        end,
    }

    return {
        {
            id     = "abundance",
            title  = "abundance",
            color  = COLOR_SECTION_HEADER,
            blocks = { block },
        }
    }
end

-- ─── Module Registration & Profiler Support ─────────────────────────────────
sfui.abundance.GetDebugInfo = function()
    return {
        isActive = sfui.abundance.IsActive(),
    }
end

sfui.RegisterModule("abundance", sfui.abundance)
sfui.tracker.RegisterModule(AbundanceModule)

return AbundanceModule
