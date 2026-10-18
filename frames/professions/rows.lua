local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.recipes = sfui.recipes or {}
sfui.recipes.browser = sfui.recipes.browser or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/professions/rows.lua
--  Recipe Catalog Rows, Item Links, Tooltips & FauxScroll View
-- ══════════════════════════════════════════════════════════════════════════════

if not sfui.isCamelot then return end

local B = sfui.recipes.browser
local common = sfui.common
local theme  = sfui.theme
local GameTooltip = sfui.common.get_tooltip()
local C_Item_GetItemInfoInstant = sfui.common.get_item_instant_info

local TAG_PINNED = " |cffffd100[pinned]|r"
local TAG_ALT_SINGLE = " |cff80c0ff[alt]|r"
local TEXT_LEARNED = "|cff40c040[learned]|r"
local TEXT_STARTER = "|cff40c0400|r"
local TEXT_STARTER_SOURCE = "|cff666666-|r |cff00ccfftrainer|r |cff666666-|r |cffcccccclearned with profession|r"

--- Refresh tooltip under mouse cursor if hovering over a list row
function B.RefreshHoverTooltip()
    local focus = (_G.GetMouseFoci and _G.GetMouseFoci()[1]) or (_G.GetMouseFocus and _G.GetMouseFocus())
    if focus and GameTooltip and GameTooltip:IsOwned(focus) then
        if focus:IsShown() and focus.recipe then
            local onEnter = focus:GetScript("OnEnter")
            if onEnter then
                onEnter(focus)
            end
        else
            GameTooltip:Hide()
        end
    end
end

--- Reset scroll offset to the top
function B.ResetScroll()
    if B.ui.scrollFrame then
        FauxScrollFrame_SetOffset(B.ui.scrollFrame, 0)
        local sb = B.ui.scrollFrame.ScrollBar
        if sb then
            sb:SetValue(0)
        end
    end
end

local itemQualityCache = {}

--- Query item quality with caching
--- @param itemID number?
--- @return number? quality
function B.GetItemQuality(itemID)
    if not itemID then return nil end
    if itemQualityCache[itemID] ~= nil then
        return itemQualityCache[itemID]
    end

    local q = nil
    if C_Item and C_Item.GetItemQualityByID then
        q = C_Item.GetItemQualityByID(itemID)
    end
    if not q then
        if common and common.get_item_info then
            q = select(3, common.get_item_info(itemID))
        end
    end

    local numQ = tonumber(q)
    if numQ then
        itemQualityCache[itemID] = numQ
    end
    return numQ
end

--- Get display icon for a recipe (prefers crafted output item, fallback to spell)
--- @param r table?
--- @return number|string icon
function B.GetRecipeIcon(r)
    if not r then return 134400 end
    if r.output then
        local icon = nil
        if C_Item_GetItemInfoInstant then
            icon = select(5, C_Item_GetItemInfoInstant(r.output))
        end
        if not icon and GetItemIcon then
            icon = GetItemIcon(r.output)
        end
        if icon then return icon end
    end
    if r.id then
        local tex = nil
        if C_Spell and C_Spell.GetSpellTexture then
            tex = C_Spell.GetSpellTexture(r.id)
        elseif GetSpellTexture then
            tex = GetSpellTexture(r.id)
        end
        if tex then return tex end
    end
    return 134400 -- generic question mark icon
end

--- Get the authentic item or spell hyperlink for a recipe
--- @param r table?
--- @return string link, number? itemID
function B.GetRecipeDisplayLink(r)
    if not r then return "[recipe]", nil end

    -- 1. Recipe scroll / book / pattern item
    if r.recipeItemID then
        local iid = r.recipeItemID
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(iid)
        end
        local link = select(2, (common and common.get_item_info and common.get_item_info(iid)) or (_G.GetItemInfo and _G.GetItemInfo(iid)))
        if link and link ~= "" then
            return link, iid
        end

        local quality = (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(iid)) or 1
        local hex = "ffffffff"
        if C_Item and C_Item.GetItemQualityColor then
            local _, _, _, qHex = C_Item.GetItemQualityColor(quality)
            if qHex then hex = qHex end
        end
        local dName = (r.name and ("recipe: " .. r.name)) or ("item #" .. tostring(iid))
        return string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, iid, dName), iid
    end

    -- 2. Crafted output item for trainer-taught abilities
    if r.output then
        local oid = r.output
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(oid)
        end
        local link = select(2, (common and common.get_item_info and common.get_item_info(oid)) or (_G.GetItemInfo and _G.GetItemInfo(oid)))
        if link and link ~= "" then
            return link, oid
        end

        local quality = (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(oid)) or 1
        local hex = "ffffffff"
        if C_Item and C_Item.GetItemQualityColor then
            local _, _, _, qHex = C_Item.GetItemQualityColor(quality)
            if qHex then hex = qHex end
        end
        return string.format("|c%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r", hex, oid, r.name or "item"), oid
    end

    -- 3. Spell link fallback
    if r.id then
        local sLink = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(r.id)) or (_G.GetSpellLink and _G.GetSpellLink(r.id))
        if sLink and sLink ~= "" then
            return sLink, nil
        end
        return string.format("|cff71d5ff|Hspell:%d|h[%s]|h|r", r.id, r.name or "recipe"), nil
    end

    return string.format("[ %s ]", r.name or "recipe"), nil
end

--- Get the best source record for a recipe (prioritizes active filter types and live player sightings, non-hostile)
--- @param r table?
--- @param preferredType string?
--- @return table? source
function B.GetRecipeSource(r, preferredType)
    if not r then return nil end
    local sources = nil
    if sfui.recipes and sfui.recipes.GetSource then
        local res = sfui.recipes.GetSource(r.id)
        if res and res.sources and #res.sources > 0 then
            sources = res.sources
        end
    end
    if not sources or #sources == 0 then
        sources = r.sources
    end
    if not sources or #sources == 0 then return nil end

    if preferredType then
        for _, s in ipairs(sources) do
            if not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
                local matchesPref = (s.type == preferredType)
                if preferredType == "drop" and (s.type == "object" or s.type == "pickpocket" or s.type == "container") then
                    matchesPref = true
                elseif preferredType == "reputation" and (s.faction or s.standing or r.faction) then
                    matchesPref = true
                end
                if matchesPref then
                    if preferredType == "vendor" and B.sourceFilters.limited_stock then
                        local isLim = (s.limited ~= nil and s.limited ~= false and s.limited ~= -1)
                        if not isLim and r.recipeItemID and sfui.recipes and sfui.recipes.IsLimitedStock then
                            isLim = sfui.recipes.IsLimitedStock(r.recipeItemID, s.npcID)
                        end
                        if isLim then return s end
                    else
                        return s
                    end
                end
            end
        end
    end

    -- Pick first non-hostile source (preferring one with map coordinates)
    local best = nil
    for _, s in ipairs(sources) do
        if not (sfui.recipes and sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
            if s.mapID and s.x and s.y then
                return s
            end
            if not best then
                best = s
            end
        end
    end

    return best or sources[1]
end

--- Handle mouse wheel scrolling for list rows, container, and window
--- @param self Frame
--- @param delta number?
function B.OnListMouseWheel(self, delta)
    if not B.ui.scrollFrame or not B.ui.scrollFrame:IsShown() then return end
    if type(self) == "number" and delta == nil then
        delta = self
    end
    if not delta or delta == 0 then return end
    ScrollFrameTemplate_OnMouseWheel(B.ui.scrollFrame, delta)
end

--- Create a single list row
--- @param parent Frame
--- @param index number
--- @return Button row
function B.CreateRow(parent, index)
    local cfg = B.CFG
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -(index - 1) * (cfg.ROW_H + cfg.ROW_PAD) - 4)
    row:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    row:SetHeight(cfg.ROW_H)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", B.OnListMouseWheel)

    -- Background & hover
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.08, 0.08, 0.10, (index % 2 == 0) and 0.40 or 0.20)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints()
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.20)

    -- Icon frame with 1px border
    local icoFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.icoFrame = icoFrame
    icoFrame:SetSize(cfg.ROW_H - 8, cfg.ROW_H - 8)
    icoFrame:SetPoint("LEFT", row, "LEFT", 4, 0)
    common.apply_flat_backdrop(icoFrame, { 0.05, 0.05, 0.07, 0.9 }, { 0.20, 0.20, 0.25, 0.6 })

    row.icon = icoFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- [ Recipe Link ] text
    row.linkText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.linkText:SetPoint("LEFT", icoFrame, "RIGHT", 8, 0)
    row.linkText:SetJustifyH("LEFT")
    row.linkText:SetWidth(190)
    row.linkText:SetWordWrap(false)

    -- Requirement / learned badge
    row.reqText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.reqText:SetPoint("LEFT", row.linkText, "RIGHT", 6, 0)
    row.reqText:SetJustifyH("LEFT")
    row.reqText:SetWidth(100)

    -- Source & location text: - Trainer/Vendor - Location (x, y)
    row.sourceText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sourceText:SetPoint("LEFT", row.reqText, "RIGHT", 4, 0)
    row.sourceText:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    row.sourceText:SetJustifyH("LEFT")
    row.sourceText:SetWordWrap(false)

    -- In-game square target icon (indicates a waypoint can be placed)
    local pinIcon = row:CreateTexture(nil, "ARTWORK")
    pinIcon:SetSize(13, 13)
    pinIcon:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    pinIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_6")
    row.pinIcon = pinIcon

    -- Hover script
    row:SetScript("OnEnter", function(self)
        if not self.recipe then return end
        local r = self.recipe
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip._sfuiInRecipeBrowser = true

        local outputItemID = r.output
        if outputItemID and outputItemID > 0 then
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(outputItemID)
            end
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(outputItemID)
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. outputItemID)
            end
        elseif r.recipeItemID and r.recipeItemID > 0 then
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(r.recipeItemID)
            end
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(r.recipeItemID)
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("item:" .. r.recipeItemID)
            end
        elseif r.id then
            if GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(r.id)
            elseif GameTooltip.SetHyperlink then
                GameTooltip:SetHyperlink("spell:" .. r.id)
            end
        end

        -- Reagents breakdown with live bag availability
        if r.reagents and next(r.reagents) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100reagents:|r", 1, 1, 1)
            for matID, count in pairs(r.reagents) do
                local matName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(matID)) or (common and common.get_item_info and select(1, common.get_item_info(matID))) or ("item #" .. matID)
                local inBag = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(matID)) or (_G.GetItemCount and _G.GetItemCount(matID)) or 0
                local countCol = (inBag >= count) and "|cff00ff88" or "|cffff5555"
                local line = string.format("  |cffffffff%dx|r %s %s(%d in bags)|r", count, matName, countCol, inBag)
                GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true)
            end
        end

        -- Specialization & reputation requirements
        if r.spec then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("|cffffa500specialization:|r %s", r.spec), 1, 0.8, 0)
        end
        if r.faction and r.standing then
            local repStr = string.format("|cff80c0ffreputation:|r %s with %s", r.standing, r.faction)
            if r.tokens then
                repStr = repStr .. string.format(" (tokens: %s)", r.tokens)
            end
            GameTooltip:AddLine(repStr, 0.5, 0.8, 1)
        end

        -- Cross-alt knowledge annotations
        if sfui.recipes and sfui.recipes.AddAltKnowledgeLines then
            sfui.recipes.AddAltKnowledgeLines(GameTooltip, r)
        end

        -- Multi-vendor sources list (when more than 1 friendly source exists)
        if self.availableSources and #self.availableSources > 1 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("|cffffd100available vendors / sources (%d):|r", #self.availableSources), 1, 1, 1)
            for sIdx, s in ipairs(self.availableSources) do
                local sLoc = s.zone or ""
                if s.x and s.y then
                    sLoc = string.format("%s (%.1f, %.1f)", sLoc ~= "" and sLoc or "map", s.x * 100, s.y * 100)
                end
                local sName = s.name or s.desc or s.type or "source"
                local isCur = (sIdx == (self.activeSourceIndex or 1))
                local prefix = isCur and "|cff00ff88>|r " or "  "
                local activeTag = isCur and " |cff00ff88[active waypoint]|r" or ""
                local costFormatted = (s and s.cost and sfui.recipes.FormatMoneyShort) and sfui.recipes.FormatMoneyShort(s.cost)
                local costStr = costFormatted and (" - " .. costFormatted) or ""
                GameTooltip:AddLine(string.format("%s%d. %s, %s%s%s", prefix, sIdx, sName, sLoc ~= "" and sLoc or "world", costStr, activeTag),
                    isCur and 1 or 0.7, isCur and 1 or 0.7, isCur and 1 or 0.7, true)
            end
        end

        local isDropBoss = false
        if self.bestSource and self.bestSource.type == "drop" and sfui.dj_camelot then
            local targetBoss = self.bestSource.name or self.bestSource.desc
            local itemSource = sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(r.recipeItemID or r.id)
            if (itemSource and itemSource.bossName) or (targetBoss and sfui.dj_camelot.GetDungeonByName and sfui.dj_camelot.GetDungeonByName(targetBoss)) then
                isDropBoss = true
            end
        end

        if isDropBoss then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00e5ffclick to view boss encounter in dungeon journal|r", 0.3, 0.85, 1)
        elseif hasCoords then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff80c0ffclick to set map waypoint with super-tracking|r", 0.7, 0.9, 1)
        end
        if self.availableSources and #self.availableSources > 1 then
            GameTooltip:AddLine(string.format("|cffffd100alt-click to cycle to next vendor / waypoint (%d/%d)|r", self.activeSourceIndex or 1, #self.availableSources), 1, 0.85, 0.2)
        end
        local isPinned = sfui.recipes.IsRecipePinned and sfui.recipes.IsRecipePinned(r.id)
        GameTooltip:AddLine(string.format("|cff00ff88ctrl-click to %s objective tracker|r", isPinned and "unpin from" or "track in"), 0.2, 1, 0.4)
        GameTooltip:AddLine("|cff888888shift-click to insert link into chat|r", 0.6, 0.6, 0.6)

        GameTooltip:Show()
    end)

    row:SetScript("OnLeave", function()
        GameTooltip._sfuiInRecipeBrowser = nil
        common.hide_tooltip()
    end)

    row:SetScript("OnClick", function(self)
        if not self.recipe then return end
        local r = self.recipe

        -- Shift-Click: insert recipe hyperlink into chat
        if IsShiftKeyDown() then
            local link = self.displayLink or B.GetRecipeDisplayLink(r)
            if link and sfui.common.insert_link_to_chat(link) then
                return
            end
        end

        -- Ctrl-Click: pin / unpin from objective tracker
        if _G.IsControlKeyDown and _G.IsControlKeyDown() then
            if sfui.recipes and sfui.recipes.TogglePinRecipe and r.id then
                sfui.recipes.TogglePinRecipe(r.id)
                B.UpdateList()
                B.RefreshHoverTooltip()
                return
            end
        end

        -- Alt-Click: cycle to next vendor / source
        if _G.IsAltKeyDown and _G.IsAltKeyDown() then
            if self.availableSources and #self.availableSources > 1 then
                self.activeSourceIndex = (self.activeSourceIndex % #self.availableSources) + 1
                local nextSrc = self.availableSources[self.activeSourceIndex]
                self.bestSource = nextSrc
                if nextSrc and nextSrc.mapID and nextSrc.x and nextSrc.y then
                    sfui.recipes.SetWaypoint(nextSrc)
                end
                B.UpdateList()
                B.RefreshHoverTooltip()
                return
            end
        end

        -- Normal Click: set map waypoint or deep link to Dungeon Journal
        local src = self.bestSource or (self.availableSources and self.availableSources[self.activeSourceIndex or 1])
        if not src or not src.mapID or not src.x or not src.y then
            if sfui.recipes and sfui.recipes.GetSource and r.id then
                local res = sfui.recipes.GetSource(r.id)
                if res and res.sources then
                    for _, s in ipairs(res.sources) do
                        if s.mapID and s.x and s.y and not (sfui.recipes.IsSourceHostile and sfui.recipes.IsSourceHostile(s)) then
                            src = s
                            break
                        end
                    end
                end
            end
        end

        -- Deep link to Dungeon Journal for dungeon/raid drops
        if src and src.type == "drop" and sfui.dungeonjournal and sfui.dungeonjournal.OpenToBoss then
            local targetBoss = src.name or src.desc
            local itemSource = sfui.dj_camelot and sfui.dj_camelot.GetItemSource and sfui.dj_camelot.GetItemSource(r.recipeItemID or r.id)
            if itemSource and itemSource.bossName then
                targetBoss = itemSource.bossName
            end
            if targetBoss and sfui.dungeonjournal.OpenToBoss(targetBoss) then
                return
            end
        end

        if src and src.mapID and src.x and src.y then
            sfui.recipes.SetWaypoint(src)
        elseif sfui.recipes and sfui.recipes.GetDropInfo then
            local _, _, coords = sfui.recipes.GetDropInfo(r.id)
            if coords and coords.mapID and coords.x and coords.y then
                sfui.recipes.SetWaypoint(coords)
            end
        end
    end)

    return row
end

--- Update scroll items view
function B.UpdateList()
    if not B.ui.scrollFrame then return end

    local cfg = B.CFG
    local numItems = #B.filteredRecipes
    FauxScrollFrame_Update(B.ui.scrollFrame, numItems, cfg.VISIBLE_ROWS, cfg.ROW_H + cfg.ROW_PAD)
    local offset = FauxScrollFrame_GetOffset(B.ui.scrollFrame)
    local currentRank = B.GetCurrentProfessionRank(B.selectedSkillID)

    if B.ui.emptyStateText then
        if #B.playerProfessions == 0 then
            B.ui.emptyStateText:SetText("no crafting professions learned on this character\nvisit a trainer in any major city to learn a profession")
            B.ui.emptyStateText:Show()
        elseif numItems == 0 then
            B.ui.emptyStateText:SetText("no matching recipes found")
            B.ui.emptyStateText:Show()
        else
            B.ui.emptyStateText:Hide()
        end
    end

    for i = 1, cfg.VISIBLE_ROWS do
        local row = B.ui.rows[i]
        local idx = offset + i

        if idx <= numItems then
            local entry = B.filteredRecipes[idx]
            local r = entry.recipe
            local isLearned = entry.isLearned

            row.recipe = r
            row.entry = entry

            -- Icon
            row.icon:SetTexture(B.GetRecipeIcon(r))

            -- Recipe link part: authentic item hyperlink
            local displayLink, displayItemID = B.GetRecipeDisplayLink(r)
            row.displayLink = displayLink
            row.displayItemID = displayItemID
            row.linkText:SetText(displayLink)

            local quality = nil
            if displayItemID then
                quality = B.GetItemQuality(displayItemID)
            elseif r.output then
                quality = B.GetItemQuality(r.output)
            end
            if row.icoFrame and row.icoFrame.SetBackdropBorderColor then
                if type(quality) == "number" and quality > 1 and _G.GetItemQualityColor then
                    local qr, qg, qb = _G.GetItemQualityColor(quality)
                    row.icoFrame:SetBackdropBorderColor(qr, qg, qb, 0.8)
                else
                    row.icoFrame:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
                end
            end

            local minSkill = r.minSkill or (r.colors and r.colors[1]) or 0
            local isStarter = (minSkill <= 0)

            local isPinned = sfui.recipes.IsRecipePinned and sfui.recipes.IsRecipePinned(r.id)
            local pinTag = isPinned and TAG_PINNED or ""

            local altNeeds, altList
            if sfui.recipes.IsAltNeeded then
                altNeeds, altList = sfui.recipes.IsAltNeeded(r)
            end
            local altTag = ""
            if altNeeds and altList then
                local numAlts = #altList
                if numAlts > 1 then
                    altTag = string.format(" |cff80c0ff[alt: %d]|r", numAlts)
                elseif numAlts == 1 then
                    altTag = TAG_ALT_SINGLE
                end
            end

            -- Skill requirement / learned badge / specialization
            if isLearned then
                if altTag == "" and pinTag == "" then
                    row.reqText:SetText(TEXT_LEARNED)
                else
                    row.reqText:SetText(TEXT_LEARNED .. altTag .. pinTag)
                end
            elseif isStarter then
                if altTag == "" and pinTag == "" then
                    row.reqText:SetText(TEXT_STARTER)
                else
                    row.reqText:SetText(TEXT_STARTER .. altTag .. pinTag)
                end
            else
                local meetsReq = (currentRank >= minSkill)
                local reqCol = meetsReq and "|cff40c040" or "|cffff5555"
                if r.spec then
                    local specTag = B.SPEC_SHORT_TAGS[r.spec] or ("[" .. r.spec .. "]")
                    row.reqText:SetText(string.format("%s%d|r |cffffa500%s|r%s%s", reqCol, minSkill, specTag, altTag, pinTag))
                elseif altTag == "" and pinTag == "" then
                    row.reqText:SetFormattedText("%s%d|r", reqCol, minSkill)
                else
                    row.reqText:SetText(string.format("%s%d|r%s%s", reqCol, minSkill, altTag, pinTag))
                end
            end

            -- Source & location part: - Trainer/Vendor - Location (x, y)
            local preferredType = nil
            if B.sourceFilters.limited_stock or B.sourceFilters.vendor then
                preferredType = "vendor"
            elseif B.sourceFilters.drop then
                preferredType = "drop"
            elseif B.sourceFilters.quest then
                preferredType = "quest"
            elseif B.sourceFilters.trainer then
                preferredType = "trainer"
            elseif B.sourceFilters.reputation then
                preferredType = "reputation"
            end

            -- Multi-vendor source resolution and cycling
            local sources = sfui.recipes and sfui.recipes.GetAllNonHostileSources and sfui.recipes.GetAllNonHostileSources(r)
            row.availableSources = sources or {}

            if row.lastRecipeID ~= r.id or not row.activeSourceIndex or row.activeSourceIndex > #row.availableSources or row.activeSourceIndex < 1 then
                row.activeSourceIndex = 1
                row.lastRecipeID = r.id
            end

            local firstSource = nil
            if #row.availableSources > 0 then
                firstSource = row.availableSources[row.activeSourceIndex]
            else
                firstSource = B.GetRecipeSource(r, preferredType)
            end

            local multiTag = (#row.availableSources > 1) and string.format(" |cff80c0ff[%d/%d]|r", row.activeSourceIndex, #row.availableSources) or ""
            local eventHoliday = r.event or (B.EVENT_RECIPES and B.EVENT_RECIPES[r.id])
            local isEvent = (r.isEvent or eventHoliday ~= nil)
            local eventTag = ""
            if isEvent then
                local hName = (eventHoliday == "winter_veil" and "winter veil")
                           or (eventHoliday == "lunar_festival" and "lunar festival")
                           or (eventHoliday == "midsummer" and "midsummer")
                           or (eventHoliday == "darkmoon_faire" and "darkmoon faire")
                           or (eventHoliday == "fishing_extravaganza" and "fishing contest")
                           or (eventHoliday == "harvest_festival" and "harvest festival")
                           or (eventHoliday and tostring(eventHoliday):gsub("_", " "))
                           or "event"
                eventTag = string.format("|cffff80df[%s]|r ", hName)
            end

            if isStarter then
                if eventTag == "" then
                    row.sourceText:SetText(TEXT_STARTER_SOURCE)
                else
                    row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ccfftrainer|r |cff666666-|r |cffcccccclearned with profession|r", eventTag))
                end
                row.pinIcon:Hide()
                row.bestSource = nil
            elseif firstSource then
                local st = firstSource.type or "source"
                local sName = firstSource.name or firstSource.desc or st
                local loc = firstSource.zone or (firstSource.mapID and ("map " .. firstSource.mapID)) or ""
                local hasCoords = (firstSource.mapID and firstSource.x and firstSource.y)
                if hasCoords then
                    loc = string.format("%s (%.1f, %.1f)", loc ~= "" and loc or "map", firstSource.x * 100, firstSource.y * 100)
                end

                local typeCol = (st == "vendor" and "|cff00ff88")
                             or (st == "trainer" and "|cff00ccff")
                             or (st == "quest" and "|cffffff00")
                             or "|cffff8040"

                if st == "trainer" then
                    local isGeneric = (not firstSource.name) or (firstSource.name:lower():find("trainer")) or (firstSource.desc and firstSource.desc:lower():find("trainer"))
                    if isGeneric then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ccfftrainer|r |cff666666-|r |cffccccccany major city|r%s", eventTag, multiTag))
                    else
                        local locStr = loc ~= "" and (" |cff666666-|r |cffcccccc" .. loc .. "|r") or ""
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ccfftrainer:|r %s%s%s", eventTag, firstSource.name, locStr, multiTag))
                    end
                elseif st == "vendor" then
                    -- Limited stock detection
                    local isLim, limCount = false, nil
                    if firstSource.limited ~= nil and firstSource.limited ~= false and firstSource.limited ~= -1 then
                        isLim = true
                        limCount = (type(firstSource.limited) == "number" and firstSource.limited > 0) and firstSource.limited or nil
                    elseif r.recipeItemID and sfui.recipes and sfui.recipes.IsLimitedStock then
                        isLim, limCount = sfui.recipes.IsLimitedStock(r.recipeItemID, firstSource.npcID)
                    end
                    local limStr = isLim and (limCount and string.format(" |cffff8040(limited: %d)|r", limCount) or " |cffff8040(limited)|r") or ""

                    local repStr = ""
                    local repFaction = firstSource.faction or r.faction
                    local repStanding = firstSource.standing or r.standing
                    local repTokens = firstSource.tokens or r.tokens
                    if repFaction and repStanding then
                        if repTokens then
                            repStr = string.format(" |cff80c0ff(%s, %s)|r", repTokens, repStanding)
                        else
                            repStr = string.format(" |cff80c0ff(%s with %s)|r", repStanding, repFaction)
                        end
                    elseif repTokens then
                        repStr = string.format(" |cff80c0ff(%s)|r", repTokens)
                    end

                    local locStr = loc ~= "" and (" |cff666666-|r |cffcccccc" .. loc .. "|r") or ""
                    local vName = firstSource.name or firstSource.desc
                    local isGeneric = (not vName) or (vName:lower() == "vendor")
                    if isGeneric then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ff88vendor|r%s%s%s%s", eventTag, locStr, repStr, limStr, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ff88vendor:|r %s%s%s%s%s", eventTag, vName, locStr, repStr, limStr, multiTag))
                    end
                elseif st == "object" then
                    local objName = firstSource.name or "chest / container"
                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ccffobject:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, objName, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff00ccffobject:|r %s%s", eventTag, objName, multiTag))
                    end
                elseif st == "pickpocket" then
                    local ppName = firstSource.name or "lockbox"
                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffffcc00pickpocket:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, ppName, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffffcc00pickpocket:|r %s%s", eventTag, ppName, multiTag))
                    end
                elseif st == "container" then
                    local cName = firstSource.name or "container"
                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff33ff99container:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, cName, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cff33ff99container:|r %s%s", eventTag, cName, multiTag))
                    end
                elseif st == "event" then
                    local evName = firstSource.name or firstSource.desc or "seasonal event"
                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffff80dfevent:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, evName, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffff80dfevent:|r %s%s", eventTag, evName, multiTag))
                    end
                elseif st == "drop" then
                    local dropTarget = firstSource.name
                    local isGeneric = (not dropTarget) or (dropTarget == "world / creature drop") or (dropTarget == "drop")
                    if isGeneric and firstSource.desc and firstSource.desc ~= "world / creature drop" then
                        dropTarget = firstSource.desc
                        isGeneric = false
                    end
                    if isGeneric and sfui.recipes and sfui.recipes.GetDropInfo then
                        local curMob, curLoc, curCoords = sfui.recipes.GetDropInfo(r.id)
                        if curMob then
                            dropTarget = curMob
                            isGeneric = false
                        end
                        if curLoc and (loc == "") then
                            loc = curLoc
                        end
                        if curCoords and not hasCoords then
                            hasCoords = true
                            firstSource.mapID = curCoords.mapID
                            firstSource.x = curCoords.x
                            firstSource.y = curCoords.y
                        end
                    end
                    if isGeneric and _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeSourceText then
                        local blizzSrc = _G.C_TradeSkillUI.GetRecipeSourceText(r.id)
                        if blizzSrc and blizzSrc ~= "" then
                            dropTarget = blizzSrc:lower():gsub("^drop:%s*", "")
                            isGeneric = false
                        end
                    end

                    if not dropTarget or dropTarget == "" then
                        dropTarget = "world drop"
                    end

                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffff8040drop:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, dropTarget, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffff8040drop:|r %s%s", eventTag, dropTarget, multiTag))
                    end
                elseif st == "quest" then
                    local qName = firstSource.name or (firstSource.questID and ("quest #" .. firstSource.questID)) or "quest"
                    if loc ~= "" then
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffffff00quest:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, qName, loc, multiTag))
                    else
                        row.sourceText:SetText(string.format("|cff666666-|r %s|cffffff00quest:|r %s%s", eventTag, qName, multiTag))
                    end
                elseif loc ~= "" then
                    row.sourceText:SetText(string.format("|cff666666-|r %s%s%s:|r %s |cff666666-|r |cffcccccc%s|r%s", eventTag, typeCol, st, sName, loc, multiTag))
                else
                    row.sourceText:SetText(string.format("|cff666666-|r %s%s%s:|r %s%s", eventTag, typeCol, st, sName, multiTag))
                end

                row.pinIcon:SetShown(hasCoords and not isLearned)
                row.bestSource = firstSource
            else
                row.sourceText:SetText("|cff666666- source unknown (explore to discover)|r")
                row.pinIcon:Hide()
                row.bestSource = nil
            end

            row:Show()
        else
            row.recipe = nil
            row.entry = nil
            row:Hide()
        end
    end

    B.RefreshHoverTooltip()
end
