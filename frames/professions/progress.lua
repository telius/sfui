local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.browser = sfui.recipes.browser or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/progress.lua
--  Recipe Catalog Completionist Progress Bar & Breakdown Tooltip
-- ══════════════════════════════════════════════════════════════════════════════

if sfui.isRetail then return end

local B = sfui.recipes.browser
local common = sfui.common
local GameTooltip = sfui.common.get_tooltip()

--- Get the active status bar texture configured in config.lua / theme engine
--- @return string texturePath
B.GetBarTexture = sfui.widgets.get_bar_texture

--- Set status bar texture directly across recipe catalog progress bar
--- @param texturePath string?
function sfui.recipes.SetBarTexture(texturePath)
    local tex = texturePath or B.GetBarTexture()
    if B.ui and B.ui.progressBar and B.ui.progressBar.SetStatusBarTexture then
        B.ui.progressBar:SetStatusBarTexture(tex)
    end
end

local function OnProgressBarEnter(self)
    local d = self._pbData
    if not d or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(string.format("%s catalogue completion", d.profName), 1, 0.82, 0)
    GameTooltip:AddDoubleLine("total known:", string.format("%d / %d (%.1f%%)", d.knownCount, d.totalCount, d.pct), 1, 1, 1, 0.2, 1, 0.4)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("source breakdown:", 0.8, 0.8, 0.8)

    local function AddBreakdown(label, known, total, r, g, b)
        if total > 0 then
            local p = (known / total) * 100
            GameTooltip:AddDoubleLine("  " .. label .. ":", string.format("%d / %d (%.1f%%)", known, total, p), 0.9, 0.9, 0.9, r, g, b)
        end
    end

    AddBreakdown("trainers", d.knownTrainer, d.totalTrainer, 0.4, 0.8, 1)
    AddBreakdown("vendors", d.knownVendor, d.totalVendor, 1, 0.82, 0)
    AddBreakdown("quests", d.knownQuest, d.totalQuest, 0.2, 1, 0.4)
    AddBreakdown("world drops", d.knownDrop, d.totalDrop, 0.7, 0.4, 1)
    AddBreakdown("reputation", d.knownRep, d.totalRep, 0.4, 0.7, 1)
    AddBreakdown("limited stock", d.knownLimited, d.totalLimited, 1, 0.6, 0.2)
    AddBreakdown("seasonal events", d.knownEvent, d.totalEvent, 1, 0.4, 0.7)

    GameTooltip:Show()
end

local function OnProgressBarLeave()
    if GameTooltip then GameTooltip:Hide() end
end

--- Create the completionist progress bar frame
--- @param parent Frame
--- @param anchorBelow Frame
--- @return Frame progressBar
function B.CreateProgressBar(parent, anchorBelow)
    local pb = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
    B.ui.progressBar = pb
    parent.progressBar = pb
    pb:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
    pb:SetPoint("TOPRIGHT", anchorBelow, "BOTTOMRIGHT", 0, -4)
    pb:SetHeight(12)
    pb:SetStatusBarTexture(B.GetBarTexture())
    pb:SetStatusBarColor(0.15, 0.70, 0.40, 0.90)
    common.apply_flat_backdrop(pb, { 0.06, 0.06, 0.08, 0.85 }, { 0.18, 0.18, 0.22, 0.85 })

    local progressText = pb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progressText:SetPoint("CENTER", pb, "CENTER", 0, 0)
    pb.text = progressText

    pb._pbData = {}
    pb:SetScript("OnEnter", OnProgressBarEnter)
    pb:SetScript("OnLeave", OnProgressBarLeave)

    return pb
end

--- Update progress bar values and tooltip breakdown
function B.UpdateProgressBar()
    local pb = B.ui.progressBar
    if not pb or not B.selectedSkillID then
        if pb then pb:Hide() end
        return
    end

    pb:SetStatusBarTexture(B.GetBarTexture())

    local candidates = B.GetCandidatesForSkill(B.selectedSkillID)
    if #candidates == 0 then
        pb:Hide()
        return
    end

    local totalCount = 0
    local knownCount = 0
    local knownTrainer, totalTrainer = 0, 0
    local knownVendor, totalVendor = 0, 0
    local knownQuest, totalQuest = 0, 0
    local knownDrop, totalDrop = 0, 0
    local knownRep, totalRep = 0, 0
    local knownLimited, totalLimited = 0, 0
    local knownEvent, totalEvent = 0, 0
    local isSourceHostile = sfui.recipes and sfui.recipes.IsSourceHostile
    local getDropInfo = sfui.recipes and sfui.recipes.GetDropInfo

    for _, r in ipairs(candidates) do
        local isKnown = B.IsRecipeLearned(r.id, r)
        if isKnown or B.HasAnyNonHostileSource(r) then
            totalCount = totalCount + 1
            if isKnown then
                knownCount = knownCount + 1
            end

            local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
            local isStarter = (minSkill <= 0) and ((not r.sources) or (#r.sources == 0) or (r.sources[1] and r.sources[1].type == "trainer"))

            local isTr = isStarter
            local isVn = false
            local isQst = false
            local isDrp = (not isStarter) and getDropInfo and (getDropInfo(r.id) ~= nil) or false
            local isRp = (not isStarter) and ((r.faction ~= nil) or (r.standing ~= nil))
            local isLim = false

            if not isStarter then
                local sources = B.GetRecipeSources(r)
                if sources then
                    for _, s in ipairs(sources) do
                        local hostile = isSourceHostile and isSourceHostile(s)
                        if not hostile then
                            local st = s.type
                            if st == "trainer" then
                                isTr = true
                            elseif st == "vendor" then
                                isVn = true
                            elseif st == "quest" then
                                isQst = true
                            elseif st == "drop" or st == "object" or st == "pickpocket" or st == "container" then
                                isDrp = true
                            end
                            if s.faction or s.standing then
                                isRp = true
                            end
                            if s.limited then
                                isLim = true
                            end
                        end
                    end
                end
            end

            if isTr then
                totalTrainer = totalTrainer + 1
                if isKnown then knownTrainer = knownTrainer + 1 end
            end
            if isVn then
                totalVendor = totalVendor + 1
                if isKnown then knownVendor = knownVendor + 1 end
            end
            if isQst then
                totalQuest = totalQuest + 1
                if isKnown then knownQuest = knownQuest + 1 end
            end
            if isDrp then
                totalDrop = totalDrop + 1
                if isKnown then knownDrop = knownDrop + 1 end
            end
            if isRp then
                totalRep = totalRep + 1
                if isKnown then knownRep = knownRep + 1 end
            end
            if isLim then
                totalLimited = totalLimited + 1
                if isKnown then knownLimited = knownLimited + 1 end
            end

            local isEv = (r.isEvent or r.event or (B.EVENT_RECIPES and B.EVENT_RECIPES[r.id] ~= nil))
            if isEv then
                totalEvent = totalEvent + 1
                if isKnown then knownEvent = knownEvent + 1 end
            end
        end
    end

    if totalCount == 0 then
        pb:Hide()
        return
    end
    pb:Show()

    local pct = totalCount > 0 and (knownCount / totalCount * 100) or 0
    pb:SetMinMaxValues(0, math.max(1, totalCount))
    pb:SetValue(knownCount)

    local profName = "profession"
    for _, p in ipairs(B.playerProfessions) do
        if p.skillID == B.selectedSkillID then
            profName = p.name
            break
        end
    end

    pb.text:SetText(string.format("%s: %d / %d known (%.1f%%)", profName, knownCount, totalCount, pct))

    local d = pb._pbData
    d.profName = profName
    d.knownCount, d.totalCount, d.pct = knownCount, totalCount, pct
    d.knownTrainer, d.totalTrainer = knownTrainer, totalTrainer
    d.knownVendor, d.totalVendor = knownVendor, totalVendor
    d.knownQuest, d.totalQuest = knownQuest, totalQuest
    d.knownDrop, d.totalDrop = knownDrop, totalDrop
    d.knownRep, d.totalRep = knownRep, totalRep
    d.knownLimited, d.totalLimited = knownLimited, totalLimited
    d.knownEvent, d.totalEvent = knownEvent, totalEvent
end
