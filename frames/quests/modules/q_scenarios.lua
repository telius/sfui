--[[
    SFUI Tracker Module: Scenarios, Delves, Dungeons & World Events
    frames/quests/modules/scenarios.lua

    Unified scenario & outdoor world event tracker.
    Handles:
      - Active Scenarios & Dungeon objectives
      - Delves: Lives counter, tier, and stage progress
      - Scenario criteria and weighted progress bars
      - Outdoor World Events & POIs (Superbloom, Radiant Echoes, Theatre Troupe, etc.)
      - UIWidget progress and capture bars
]]

local addonName, addon = ...
local sfui = _G.sfui or {}
sfui.tracker = sfui.tracker or {}
sfui.questlog = sfui.questlog or {}

local _G = _G
local C_Scenario = _G.C_Scenario
local C_ScenarioInfo = _G.C_ScenarioInfo
local C_DelvesUI = _G.C_DelvesUI
local C_Spell = _G.C_Spell
local Enum = _G.Enum
local ipairs, pairs, type, tonumber, tostring = _G.ipairs, _G.pairs, _G.type, _G.tonumber, _G.tostring
local math_floor, math_max = _G.math.floor, _G.math.max
local table_insert = _G.table.insert
local table_concat = _G.table.concat
local string_format = string.format

local issecretvalue = sfui.common.issecretvalue

-- ─────────────────────────────────────────────────────────
--  CRITERIA EXTRACTOR
-- ─────────────────────────────────────────────────────────
local function GetScenarioCriteria(criteriaIndex, stepID)
    if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
        local info = C_ScenarioInfo.GetCriteriaInfo(criteriaIndex)
        if info and type(info) == "table" and (info.description or info.criteriaString or info.string) then
            return info
        end
    end
    if C_Scenario and C_Scenario.GetCriteriaInfo then
        local desc, cType, comp, quant, totQuant, flags, assetID, quantStr = C_Scenario.GetCriteriaInfo(criteriaIndex)
        if desc and desc ~= "" then
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

-- ─────────────────────────────────────────────────────────
--  SCENARIOS MODULE SPECIFICATION
-- ─────────────────────────────────────────────────────────
local ScenariosModule = {
    id       = "scenarios",
    priority = 10, -- Display at very top above normal quests
    events   = {
        "SCENARIO_UPDATE",
        "SCENARIO_CRITERIA_UPDATE",
        "SCENARIO_STAGE_UPDATE",
        "SCENARIO_SPELL_UPDATE",
        "SCENARIO_COMPLETED",
        "ACTIVE_DELVE_DATA_UPDATE",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_ENTERING_WORLD",
    },
}

function ScenariosModule:Init(engine)
    self.engine = engine
end

function ScenariosModule:IsEnabled()
    return true
end

local GetQLState = sfui.questlog.GetState

function ScenariosModule:BuildBlocks(container)
    local sections = {}

    -- ═════════════════════════════════════════════════════════
    -- 1. ACTIVE SCENARIOS / DELVES / DUNGEONS
    -- ═════════════════════════════════════════════════════════
    local inScenario = C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario()
    if inScenario then
        local name, currentStage, numStages, flags, _, _, _, xp, money, scenarioType = nil
        if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
            local sInfo = C_ScenarioInfo.GetScenarioInfo()
            if sInfo then
                name = sInfo.name
                currentStage = sInfo.currentStage
                numStages = sInfo.numStages
                scenarioType = sInfo.scenarioType
            end
        elseif C_Scenario and C_Scenario.GetInfo then
            name, currentStage, numStages, flags, _, _, _, xp, money, scenarioType = C_Scenario.GetInfo()
        end

        local stageName, stageDesc, numCriteria, stepFailed, isBonusStep, isWaitStep = nil, nil, 0, false, false, false
        local weightedProgress = false
        if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
            local stepInfo = C_ScenarioInfo.GetScenarioStepInfo()
            if stepInfo then
                stageName = stepInfo.title
                stageDesc = stepInfo.description
                numCriteria = stepInfo.numCriteria or 0
                stepFailed = stepInfo.failed
                isBonusStep = stepInfo.isBonusStep
                weightedProgress = stepInfo.weightedProgress
            end
        elseif C_Scenario and C_Scenario.GetStepInfo then
            stageName, stageDesc, numCriteria, stepFailed, isBonusStep, isWaitStep, _, _, _, weightedProgress =
            C_Scenario.GetStepInfo()
        end

        -- Check if this is a Delve or Tiered Entrance (including Labyrinths)
        local isTiered = (C_ScenarioInfo and C_ScenarioInfo.IsTieredEntranceScenario and C_ScenarioInfo.IsTieredEntranceScenario())
        local isDelve = (C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve())
            or isTiered
            or (scenarioType == 8)

        local isLabyrinth = isDelve and ((name and name:lower():find("labyrinth"))
            or (C_DelvesUI and C_DelvesUI.GetTieredEntranceType and C_DelvesUI.GetTieredEntranceType() == 4))

        local delveTier = nil
        if isDelve and C_DelvesUI and C_DelvesUI.GetActiveDelveTier then
            local tInfo = C_DelvesUI.GetActiveDelveTier()
            if tInfo and tInfo.tier and tInfo.tier > 0 then
                delveTier = tInfo.tier
            end
        end

        local delveLives = nil
        if isDelve and C_DelvesUI and C_DelvesUI.GetLives then
            delveLives = C_DelvesUI.GetLives()
        end

        local headerTitle = isLabyrinth and "labyrinth" or (isDelve and "delve" or "scenario")
        local headerColor = isLabyrinth and { 0.85, 0.4, 1.0 } or (isDelve and { 0.4, 0.8, 1.0 } or { 0.40, 0.00, 1.00 })

        local stageTitle = name or (isLabyrinth and "Labyrinth" or "Scenario")
        if stageName and stageName ~= "" then
            if numStages and numStages > 1 and currentStage then
                local stagePrefix = isLabyrinth and "Chamber" or "Stage"
                stageTitle = string_format("%s %d/%d: %s", stagePrefix, currentStage, numStages, stageName)
            else
                stageTitle = stageName
            end
        end

        if delveTier then
            stageTitle = stageTitle .. string_format(" |cffa864ff[Tier %d]|r", delveTier)
        end
        if isDelve and delveLives then
            local livesColor = (delveLives == 0) and "|cffff4444" or "|cffffcc00"
            stageTitle = stageTitle .. string_format(" %s[Lives: %d]|r", livesColor, delveLives)
        end

        local state = GetQLState()
        local expandedBlocks = state.expandedBlocks or {}
        local expandKey = isLabyrinth and "labyrinth" or (isDelve and "delve" or "scenario")
        local isExpanded = (expandedBlocks[expandKey] ~= false)

        local lines = {}
        local progressBar = nil

        if isExpanded then
            if isDelve and C_ScenarioInfo and C_ScenarioInfo.GetTieredEntranceActiveSpells then
                local activeSpells = C_ScenarioInfo.GetTieredEntranceActiveSpells()
                if activeSpells and #activeSpells > 0 then
                    local affixNames = {}
                    for _, sID in ipairs(activeSpells) do
                        local sInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sID)
                        local sName = sInfo and sInfo.name
                        if sName and sName ~= "" and not issecretvalue(sName) then
                            table_insert(affixNames, sName)
                        end
                    end
                    if #affixNames > 0 then
                        table_insert(lines, {
                            text      = string_format("|cff00ccffAffixes:|r %s", table_concat(affixNames, ", ")),
                            completed = false,
                        })
                    end
                end
            end

            if numCriteria and numCriteria > 0 then
                for i = 1, numCriteria do
                    local crit = GetScenarioCriteria(i)
                    if crit then
                        local desc = crit.description or crit.criteriaString or crit.string
                        local isComp = (crit.completed == true)
                        local isWeight = crit.isWeightedProgress or weightedProgress or (crit.criteriaType == 8)

                        if isWeight then
                            local pct = crit.quantity or 0
                            progressBar = {
                                min   = 0,
                                max   = 100,
                                value = pct,
                                text  = string_format("%d%%", pct),
                            }
                        elseif desc and desc ~= "" and not issecretvalue(desc) then
                            local cleanDesc = desc:gsub(" / ", "/")
                            table_insert(lines, {
                                text      = cleanDesc,
                                completed = isComp,
                            })
                        end
                    end
                end
            elseif stageDesc and stageDesc ~= "" and not issecretvalue(stageDesc) then
                table_insert(lines, {
                    text      = stageDesc,
                    completed = false,
                    color     = { 0.85, 0.85, 0.85, 1 },
                })
            end
        end

        local scenarioBlock = {
            title       = stageTitle,
            titleColor  = stepFailed and { 1, 0.2, 0.2, 1 } or { 1, 1, 1, 1 },
            isScenario  = true,
            isExpanded  = isExpanded,
            lines       = lines,
            progressBar = progressBar,
            OnClick     = function(block, btn)
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

        table_insert(sections, {
            id     = "scenario",
            title  = headerTitle,
            color  = headerColor,
            blocks = { scenarioBlock },
        })
    end

    return sections
end

sfui.tracker.RegisterModule(ScenariosModule)
return ScenariosModule
