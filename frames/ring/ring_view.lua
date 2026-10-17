local addonName, addon = ...
sfui = sfui or {}
sfui.ring = sfui.ring or {}
sfui.ring.view = sfui.ring.view or {}

local view = sfui.ring.view
local geom = sfui.ring.geom

local CreateFrame  = _G.CreateFrame
local UIParent     = _G.UIParent
local type         = _G.type
local pairs        = _G.pairs
local ipairs       = _G.ipairs
local unpack       = _G.unpack
local math_max     = math.max
local math_min     = math.min
local math_abs     = math.abs
local math_ceil    = math.ceil
local math_floor   = math.floor
local string_format = string.format
local GetTime      = _G.GetTime
local tonumber     = _G.tonumber
local tostring     = _G.tostring
local UnitExists   = _G.UnitExists
local C_Item       = _G.C_Item
local C_Spell      = _G.C_Spell
local C_Container  = _G.C_Container
local C_Minimap    = _G.C_Minimap
local C_QuestLog   = _G.C_QuestLog
local InCombatLockdown = _G.InCombatLockdown
local issecretvalue   = _G.issecretvalue
local GetQuestLogSpecialItemCooldown = _G.GetQuestLogSpecialItemCooldown

local rootFrame
local slotPool
local activeSlots = {}
local activeSlotIndex = nil
local currentRingID = nil
local currentSlotsData = nil

local openAnimActive = false
local openAnimTimer = 0
local openAnimDuration = 0.10

local function get_config()
    local db = sfui.db and sfui.db.Get
    local radius   = (db and db("ring", "radius", 95)) or 95
    local deadzone = (db and db("ring", "deadzone", 28)) or 28
    local slotSize = (db and db("ring", "slot_size", 40)) or 40
    local labels   = (db and db("ring", "show_labels", true)) ~= false
    local showCooldowns = (db and db("ring", "show_cooldowns", true)) ~= false
    local animations = (db and db("ring", "animations", true)) ~= false
    return radius, deadzone, slotSize, labels, showCooldowns, animations
end

local function format_cooldown_text(rem)
    if not rem or rem <= 0 then return "" end
    if rem > 86400 then
        return math_ceil(rem / 86400) .. "d"
    elseif rem > 3600 then
        return math_ceil(rem / 3600) .. "h"
    elseif rem > 90 then
        return math_ceil(rem / 60) .. "m"
    elseif rem >= 10 then
        return math_ceil(rem) .. "s"
    else
        return string_format("%.1fs", rem)
    end
end

local function resolve_item_id(data)
    if not data then return nil end
    if data.itemID and tonumber(data.itemID) then
        return tonumber(data.itemID)
    end
    local attrs = data.attrs
    if attrs and attrs.type == "item" and attrs.item then
        local num = tonumber(attrs.item)
        if num then return num end
        local str = tostring(attrs.item):match("item:(%d+)") or tostring(attrs.item):match("(%d+)")
        if str then return tonumber(str) end
    end
    if attrs and attrs.type == "macro" and attrs.macrotext then
        local str = tostring(attrs.macrotext):match("item:(%d+)")
        if str then return tonumber(str) end
    end
    if data.id and type(data.id) == "string" then
        local str = data.id:match("^qi_(%d+)$") or data.id:match("^util_item_(%d+)$") or data.id:match("^item:(%d+)$")
        if str then return tonumber(str) end
    end
    return nil
end

local function check_slot_range(data)
    if not data or not (UnitExists and UnitExists("target")) then return nil end
    local attrs = data.attrs or {}
    if attrs.type == "spell" and attrs.spell then
        if C_Spell and C_Spell.IsSpellInRange then
            return C_Spell.IsSpellInRange(attrs.spell, "target")
        elseif _G.IsSpellInRange then
            local res = _G.IsSpellInRange(attrs.spell, "target")
            if res == 1 then return true elseif res == 0 then return false end
            return nil
        end
    end
    -- C_Item.IsItemInRange has SecretArguments = "AllowedWhenUntainted" in 1.60.1 / 11+
    if InCombatLockdown and InCombatLockdown() then return nil end
    local itemID = resolve_item_id(data)
    if itemID then
        if C_Item and C_Item.IsItemInRange then
            return C_Item.IsItemInRange(itemID, "target")
        elseif _G.IsItemInRange then
            return _G.IsItemInRange(itemID, "target")
        end
    end
    return nil
end

local function check_slot_usable(data)
    if not data then return true end
    if InCombatLockdown and InCombatLockdown() then
        local attrs = data.attrs or {}
        if attrs.type == "spell" and attrs.spell and C_Spell and C_Spell.IsSpellUsable then
            local isUsable, notEnoughMana = C_Spell.IsSpellUsable(attrs.spell)
            if isUsable ~= nil then return isUsable and not notEnoughMana end
        end
        return true
    end
    local itemID = resolve_item_id(data)
    if itemID then
        if C_Item and C_Item.IsUsableItem then
            local isUsable = C_Item.IsUsableItem(itemID)
            if isUsable ~= nil then return isUsable end
        elseif _G.IsUsableItem then
            local isUsable = _G.IsUsableItem(itemID)
            if isUsable ~= nil then return isUsable end
        end
    end
    local attrs = data.attrs or {}
    if attrs.type == "spell" and attrs.spell then
        if C_Spell and C_Spell.IsSpellUsable then
            local isUsable, notEnoughMana = C_Spell.IsSpellUsable(attrs.spell)
            if isUsable ~= nil then return isUsable and not notEnoughMana end
        elseif _G.IsUsableSpell then
            local isUsable, notEnoughMana = _G.IsUsableSpell(attrs.spell)
            if isUsable ~= nil then return isUsable and not notEnoughMana end
        end
    end
    return true
end

local function check_quest_blob(data)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not data or not data.questID then return false end
    if C_Minimap and C_Minimap.IsInsideQuestBlob then
        return C_Minimap.IsInsideQuestBlob(data.questID) or false
    end
    return false
end

local function get_slot_cooldown(data)
    if not data then return 0, 0, 0, false, false end
    local start, duration, enable = 0, 0, 0
    local isActive, isSecret = false, false
    local attrs = data.attrs or {}
    local inCombat = InCombatLockdown and InCombatLockdown()

    -- 1. item cooldown
    local itemID = resolve_item_id(data)
    if itemID then
        if inCombat then
            -- in combat: C_Spell.GetItemCooldown is AllowedWhenTainted
            -- C_Item / C_Container / GetQuestLogSpecialItemCooldown are AllowedWhenUntainted
            if C_Spell and C_Spell.GetItemCooldown then
                local cd = C_Spell.GetItemCooldown(itemID)
                if cd then
                    start = cd.startTime or 0
                    duration = cd.duration or 0
                    enable = cd.isEnabled and 1 or 0
                    isActive = cd.isActive or false
                end
            end
        else
            -- out of combat: quest log special items and bag slots
            if data.questLogIndex and GetQuestLogSpecialItemCooldown then
                local realIndex = data.questLogIndex
                if data.questID and C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
                    local li = C_QuestLog.GetLogIndexForQuestID(data.questID)
                    if li and li > 0 then realIndex = li end
                end
                start, duration, enable = GetQuestLogSpecialItemCooldown(realIndex)
                if start and duration and duration > 0 then
                    return start, duration, enable, true, false
                end
            end

            if data.bag and data.slot and C_Container and C_Container.GetContainerItemCooldown then
                start, duration, enable = C_Container.GetContainerItemCooldown(data.bag, data.slot)
                if start and duration and duration > 0 then
                    return start, duration, enable, true, false
                end
            end

            if C_Spell and C_Spell.GetItemCooldown then
                local cd = C_Spell.GetItemCooldown(itemID)
                if cd then
                    start = cd.startTime or 0
                    duration = cd.duration or 0
                    enable = cd.isEnabled and 1 or 0
                    isActive = cd.isActive or false
                end
            end

            if (not start or duration == 0) and sfui.api and sfui.api.GetItemCooldown then
                start, duration, enable = sfui.api.GetItemCooldown(itemID)
            end
        end

        if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
            return start, duration, enable, isActive, true
        end
        if start and duration and duration > 0 then
            return start, duration, enable, (isActive or true), false
        end
        return 0, 0, 0, false, false
    end

    -- 2. spell cooldown
    if attrs.type == "spell" and attrs.spell then
        if C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(attrs.spell)
            if cdInfo then
                start = cdInfo.startTime or 0
                duration = cdInfo.duration or 0
                enable = cdInfo.isEnabled and 1 or 0
                isActive = cdInfo.isActive or false
            end
        elseif sfui.api and sfui.api.GetSpellCooldown then
            start, duration, enable = sfui.api.GetSpellCooldown(attrs.spell)
        elseif _G.GetSpellCooldown then
            start, duration, enable = _G.GetSpellCooldown(attrs.spell)
        end
    -- 3. toy cooldown
    elseif attrs.type == "toy" and (attrs.toy or data.id) then
        local toyID = tonumber(attrs.toy) or tonumber(tostring(attrs.toy or data.id):match("(%d+)"))
        if toyID then
            if inCombat then
                if C_Spell and C_Spell.GetItemCooldown then
                    local cd = C_Spell.GetItemCooldown(toyID)
                    if cd then
                        start = cd.startTime or 0
                        duration = cd.duration or 0
                        enable = cd.isEnabled and 1 or 0
                        isActive = cd.isActive or false
                    end
                end
            else
                if C_Spell and C_Spell.GetItemCooldown then
                    local cd = C_Spell.GetItemCooldown(toyID)
                    if cd then
                        start = cd.startTime or 0
                        duration = cd.duration or 0
                        enable = cd.isEnabled and 1 or 0
                        isActive = cd.isActive or false
                    end
                end
                if (not start or duration == 0) and sfui.api and sfui.api.GetItemCooldown then
                    start, duration, enable = sfui.api.GetItemCooldown(toyID)
                end
            end
        end
    end

    if issecretvalue and (issecretvalue(start) or issecretvalue(duration)) then
        return start, duration, enable, isActive, true
    end
    return start or 0, duration or 0, enable or 0, isActive, false
end

local function format_active_label(data)
    if not data then return "cancel" end
    local label = (data.label or data.id or ""):lower()
    if InCombatLockdown and InCombatLockdown() then
        return label
    end
    local start, duration, enable, isActive, isSecret = get_slot_cooldown(data)
    if isSecret then
        return label
    end
    local now = GetTime()
    local rem = (start and duration and duration > 0) and ((start + duration) - now) or 0
    if rem > 0.1 and duration > 1.5 and (enable == nil or enable == 1) then
        return label .. " |cffff5555(" .. format_cooldown_text(rem) .. ")|r"
    elseif check_slot_range(data) == false then
        return label .. " |cffff4444(out of range)|r"
    end
    return label
end

local function create_slot_frame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(40, 40)

    -- icon texture
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)
    f.icon = icon

    -- round icon style
    sfui.widgets.apply_round_icon_style(f, icon, 1.5, { 0, 0, 0, 0.85 })

    -- cooldown frame
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    if sfui.widgets and sfui.widgets.apply_round_cooldown_style then
        sfui.widgets.apply_round_cooldown_style(cd, f, 1.5)
    else
        cd:SetAllPoints(f)
        if cd.SetUseCircularEdge then
            cd:SetUseCircularEdge(true)
        end
        if cd.SetHideCountdownNumbers then
            cd:SetHideCountdownNumbers(true)
        end
        if cd.SetSwipeTexture then
            cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", 0, 0, 0, 0.65)
        end
    end
    f.cooldown = cd

    -- text overlay frame (positioned above cooldown swipe so numbers never get obscured)
    local textOverlay = CreateFrame("Frame", nil, f)
    textOverlay:SetAllPoints(f)
    textOverlay:SetFrameLevel((cd:GetFrameLevel() or 1) + 4)
    f.textOverlay = textOverlay

    -- count / charges text
    local count = textOverlay:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    count:SetPoint("BOTTOMRIGHT", textOverlay, "BOTTOMRIGHT", -2, 2)
    count:SetTextColor(1, 1, 1, 1)
    if count.SetShadowOffset then
        count:SetShadowOffset(1, -1)
        count:SetShadowColor(0, 0, 0, 1)
    end
    f.count = count

    -- cd timer countdown text
    local cdText = textOverlay:CreateFontString(nil, "OVERLAY", sfui.config.font or "GameFontNormal")
    cdText:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)
    cdText:SetTextColor(1, 0.85, 0.2, 1)
    if cdText.GetFont then
        local fontPath, fontSize = cdText:GetFont()
        if fontPath then
            cdText:SetFont(fontPath, 13, "OUTLINE")
        end
    end
    if cdText.SetShadowOffset then
        cdText:SetShadowOffset(1, -1)
        cdText:SetShadowColor(0, 0, 0, 1)
    end
    f.cdText = cdText

    -- quest starter "!" exclamation badge
    local questMark = textOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    questMark:SetSize(16, 16)
    questMark:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", 3, 3)
    if _G.TEXTURE_ITEM_QUEST_BANG then
        questMark:SetTexture(_G.TEXTURE_ITEM_QUEST_BANG)
    elseif C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("QuestNormal") then
        questMark:SetAtlas("QuestNormal")
    else
        questMark:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBang")
    end
    questMark:Hide()
    f.questMark = questMark

    -- slice label text
    local label = f:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    label:SetPoint("TOP", f, "BOTTOM", 0, -4)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetWidth(80)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    f.label = label

    return f
end

local function get_selection_color(slot)
    if slot then
        if slot.selectionColor then
            local sc = slot.selectionColor
            return sc[1] or sc.r or 1, sc[2] or sc.g or 1, sc[3] or sc.b or 1
        end
        if (currentRingID == "targetmarkers" or currentRingID == "worldmarkers") and slot.color then
            local sc = slot.color
            return sc[1] or sc.r or 1, sc[2] or sc.g or 1, sc[3] or sc.b or 1
        end
    end

    local specID = slot and slot.specID
    if sfui.common and sfui.common.get_spec_color then
        local r, g, b = sfui.common.get_spec_color(specID)
        if r and g and b then
            return r, g, b
        end
    end
    if sfui.colors and sfui.colors.get_spec_color then
        local r, g, b = sfui.colors.get_spec_color(specID)
        if r and g and b then
            return r, g, b
        end
    end
    local sID = specID or (sfui.talents and sfui.talents.get_current_spec_id and sfui.talents.get_current_spec_id())
    local cfg = sfui.config and sfui.config.spec_colors
    if sID and cfg and cfg[sID] then
        local c = cfg[sID]
        return c[1] or c.r or 0, c[2] or c.g or 0.8, c[3] or c.b or 1
    end
    return 0, 0.8, 1
end

local function update_slot_border(frame, isSelected, activeData)
    if not frame or not frame.roundBorder then return end
    if isSelected then
        local sr, sg, sb = get_selection_color(activeData)
        frame.roundBorder:SetColorTexture(sr, sg, sb, 1)
    else
        local sData = frame._slotData
        if sData and sData.active then
            local ar, ag, ab = get_selection_color(sData)
            frame.roundBorder:SetColorTexture(ar, ag, ab, 0.45)
        elseif check_quest_blob(sData) then
            frame.roundBorder:SetColorTexture(1.0, 0.82, 0.0, 0.95)
        else
            frame.roundBorder:SetColorTexture(0, 0, 0, 0.85)
        end
    end
end

local function reset_slot_frame(f)
    f:Hide()
    f:ClearAllPoints()
    f:SetScale(1.0)
    f:SetAlpha(1.0)
    f._targetScale = 1.0
    f._currentScale = 1.0
    f._targetDx = nil
    f._targetDy = nil
    f.icon:SetTexture(nil)
    if sfui.widgets and sfui.widgets.set_round_icon_coords then
        sfui.widgets.set_round_icon_coords(f.icon, nil)
    else
        f.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
    end
    f.icon:SetVertexColor(1, 1, 1, 1)
    f.icon:SetDesaturated(false)
    if f.cooldown then
        f.cooldown:Clear()
        f.cooldown:Hide()
    end
    if f.cdText then
        f.cdText:SetText("")
        f.cdText:Hide()
    end
    if f.questMark then
        f.questMark:Hide()
    end
    f.count:SetText("")
    f.label:SetText("")
    f.label:Hide()
    if f.roundBorder then
        f.roundBorder:SetColorTexture(0, 0, 0, 0.85)
    end
    f._slotData = nil
    f._index = nil
end

local function ensure_root_frame()
    if rootFrame then return rootFrame end

    rootFrame = CreateFrame("Frame", "SfuiRingView", UIParent)
    rootFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    rootFrame:SetSize(400, 400)
    rootFrame:EnableMouse(false)
    rootFrame:Hide()

    rootFrame:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if sfui.ring.live and sfui.ring.live.is_open and sfui.ring.live.is_open() then
            sfui.ring.live.close()
        end
    end)

    -- center deadzone disc
    local dz = CreateFrame("Frame", nil, rootFrame)
    dz:SetPoint("CENTER", rootFrame, "CENTER", 0, 0)
    sfui.widgets.apply_round_icon_style(dz, nil, 1, { 0.3, 0.3, 0.3, 0.4 })
    if dz.roundBg then
        dz.roundBg:SetColorTexture(0.05, 0.05, 0.05, 0.55)
    end
    rootFrame.deadzoneDisc = dz

    -- center active action label
    local activeText = rootFrame:CreateFontString(nil, "OVERLAY", sfui.config.font or "GameFontNormal")
    activeText:SetPoint("CENTER", rootFrame, "CENTER", 0, 0)
    activeText:SetTextColor(1, 1, 1, 1)
    activeText:SetWidth(120)
    activeText:SetJustifyH("CENTER")
    rootFrame.activeText = activeText

    -- title label at top of ring
    local titleText = rootFrame:CreateFontString(nil, "OVERLAY", sfui.config.font_small or "GameFontHighlightSmall")
    titleText:SetPoint("BOTTOM", dz, "TOP", 0, 10)
    local tr, tg, tb = get_selection_color(nil)
    titleText:SetTextColor(tr, tg, tb, 0.85)
    titleText:SetJustifyH("CENTER")
    rootFrame.titleText = titleText

    slotPool = sfui.common.create_pool(function()
        return create_slot_frame(rootFrame)
    end, reset_slot_frame)

    return rootFrame
end

--- clear all active slot frames back to the pool.
function view.clear_slots()
    openAnimActive = false
    openAnimTimer = 0
    if slotPool then
        slotPool:release_all()
    end
    for k in pairs(activeSlots) do
        activeSlots[k] = nil
    end
    activeSlotIndex = nil
end

function view.update_slot_state(frame, data, showCooldowns)
    if not frame or not data then return end

    local inCombat = InCombatLockdown and InCombatLockdown()
    local start, duration, enable, isActive, isSecret = get_slot_cooldown(data)
    local now = GetTime()
    local onCD = false
    local rem = 0

    if isSecret or inCombat then
        onCD = (isActive == true)
        if isActive == nil and start and duration then
            onCD = true
        end
    else
        if start and duration and duration > 0 then
            rem = (start + duration) - now
            onCD = (rem > 0.1) and (duration > 1.5) and (enable == nil or enable == 1)
        end
    end

    local inRange = check_slot_range(data)
    local isUsable = check_slot_usable(data)
    local inBlob = check_quest_blob(data)

    -- 1. Cooldown swipe & countdown timer
    if frame.cooldown then
        if onCD then
            frame.cooldown:SetCooldown(start, duration)
            if frame.cooldown.SetSwipeColor then
                frame.cooldown:SetSwipeColor(0, 0, 0, 0.65)
            end
            frame.cooldown:Show()
            if frame.cdText then
                if showCooldowns ~= false and not isSecret and not inCombat then
                    frame.cdText:SetText(format_cooldown_text(rem))
                    frame.cdText:Show()
                else
                    frame.cdText:SetText("")
                    frame.cdText:Hide()
                end
            end
            frame.icon:SetDesaturated(true)
            frame.icon:SetVertexColor(0.4, 0.4, 0.4, 1)
        else
            frame.cooldown:Clear()
            frame.cooldown:Hide()
            if frame.cdText then
                frame.cdText:SetText("")
                frame.cdText:Hide()
            end
            frame.icon:SetDesaturated(false)
            if inRange == false then
                frame.icon:SetVertexColor(0.9, 0.25, 0.25, 1)
            elseif isUsable == false then
                frame.icon:SetVertexColor(0.45, 0.45, 0.45, 1)
            elseif data.color then
                frame.icon:SetVertexColor(data.color[1] or 1, data.color[2] or 1, data.color[3] or 1)
            else
                frame.icon:SetVertexColor(1, 1, 1, 1)
            end
        end
    end

    -- 2. Quest starter exclamation badge ("!")
    if frame.questMark then
        frame.questMark:SetShown(data.startsQuest == true)
    end

    -- 3. Dynamic border coloring
    if frame._index ~= activeSlotIndex then
        update_slot_border(frame, false, nil)
    end
end

function view.update_live_state()
    local _, _, _, _, showCooldowns = get_config()
    for _, frame in pairs(activeSlots) do
        if frame._slotData then
            view.update_slot_state(frame, frame._slotData, showCooldowns)
        end
    end

    if activeSlotIndex and currentSlotsData and currentSlotsData[activeSlotIndex] then
        local root = ensure_root_frame()
        root.activeText:SetText(format_active_label(currentSlotsData[activeSlotIndex]))
    end
end

--- render a ring definition around the center point.
--- @param ringID string
--- @param slots table list of slot definition tables
--- @param title string|nil optional title text
function view.render_ring(ringID, slots, title)
    local root = ensure_root_frame()
    view.clear_slots()

    currentRingID = ringID
    currentSlotsData = slots or {}
    local num = #currentSlotsData
    if num == 0 then return end

    local radius, deadzone, slotSize, showLabels, showCooldowns, animations = get_config()
    if num > 10 then
        local minCircumference = num * (slotSize + 8)
        local minRadius = math.floor(minCircumference / (2 * math.pi))
        if minRadius > radius then
            radius = minRadius
        end
    end

    -- update deadzone circle size
    local dzSize = deadzone * 2
    root.deadzoneDisc:SetSize(dzSize, dzSize)
    if root.deadzoneDisc.roundInnerMask then
        root.deadzoneDisc.roundInnerMask:SetPoint("TOPLEFT", root.deadzoneDisc, "TOPLEFT", 1, -1)
        root.deadzoneDisc.roundInnerMask:SetPoint("BOTTOMRIGHT", root.deadzoneDisc, "BOTTOMRIGHT", -1, 1)
    end

    -- update title
    root.titleText:SetText(title and title:lower() or ringID:lower())
    local tr, tg, tb = get_selection_color(nil)
    root.titleText:SetTextColor(tr, tg, tb, 0.85)
    root.activeText:SetText("cancel")
    root.activeText:SetTextColor(0.5, 0.5, 0.5, 0.8)

    if animations then
        openAnimActive = true
        openAnimTimer = 0
        root.deadzoneDisc:SetScale(0.70)
        root.deadzoneDisc:SetAlpha(0.2)
        root.titleText:SetAlpha(0)
        root.activeText:SetAlpha(0)
    else
        openAnimActive = false
        openAnimTimer = 0
        root.deadzoneDisc:SetScale(1.0)
        root.deadzoneDisc:SetAlpha(1.0)
        root.titleText:SetAlpha(1.0)
        root.activeText:SetAlpha(1.0)
    end

    -- position each slot
    for i = 1, num do
        local data = currentSlotsData[i]
        local frame = slotPool:acquire(root)
        frame._index = i
        frame._slotData = data
        frame:SetSize(slotSize, slotSize)

        -- Scale fonts and badge with slotSize
        if frame.cdText and frame.cdText.GetFont then
            local fontPath = frame.cdText:GetFont()
            if fontPath then
                local cdFontSize = math_max(10, math_floor(slotSize * 0.32))
                frame.cdText:SetFont(fontPath, cdFontSize, "OUTLINE")
            end
        end
        if frame.count and frame.count.GetFont then
            local fontPath = frame.count:GetFont()
            if fontPath then
                local countFontSize = math_max(9, math_floor(slotSize * 0.26))
                frame.count:SetFont(fontPath, countFontSize, "OUTLINE")
            end
        end
        if frame.questMark then
            local qMarkSize = math_max(12, math_floor(slotSize * 0.40))
            frame.questMark:SetSize(qMarkSize, qMarkSize)
        end
        if frame.cooldown then
            local mult = sfui.pixelScale or 1
            local thickness = 1.5 * mult
            frame.cooldown:ClearAllPoints()
            frame.cooldown:SetPoint("TOPLEFT", frame, "TOPLEFT", thickness, -thickness)
            frame.cooldown:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -thickness, thickness)
        end

        local dx, dy = geom.get_slot_offset(i, num, radius)
        frame._targetDx = dx
        frame._targetDy = dy
        frame._targetScale = 1.0
        frame._currentScale = 1.0

        frame:ClearAllPoints()
        if animations then
            frame:SetPoint("CENTER", root, "CENTER", dx * 0.40, dy * 0.40)
            frame:SetAlpha(0)
            frame:SetScale(1.0)
        else
            frame:SetPoint("CENTER", root, "CENTER", dx, dy)
            frame:SetAlpha(1.0)
            frame:SetScale(1.0)
        end

        -- set icon
        if data.icon then
            frame.icon:SetTexture(data.icon)
            if sfui.widgets and sfui.widgets.set_round_icon_coords then
                sfui.widgets.set_round_icon_coords(frame.icon, data.texCoords)
            elseif data.texCoords then
                frame.icon:SetTexCoord(unpack(data.texCoords))
            else
                frame.icon:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            end
        else
            frame.icon:SetTexture(nil)
        end

        -- set vertex tint if specified
        if data.color then
            frame.icon:SetVertexColor(data.color[1] or 1, data.color[2] or 1, data.color[3] or 1)
        else
            frame.icon:SetVertexColor(1, 1, 1)
        end

        -- set count / charges
        if data.charges and data.charges > 0 then
            frame.count:SetText(data.charges)
        elseif data.count and data.count > 1 then
            frame.count:SetText(data.count)
        else
            frame.count:SetText("")
        end

        -- set label
        if showLabels and data.label then
            frame.label:SetText(data.label:lower())
            frame.label:Show()
        else
            frame.label:Hide()
        end

        view.update_slot_state(frame, data, showCooldowns)

        frame:Show()
        activeSlots[i] = frame
    end
end

--- highlight the currently selected slot, or cancel state if nil.
--- @param index number|nil 1-based slot index or nil
function view.set_active_slot(index)
    if activeSlotIndex == index then return end
    activeSlotIndex = index

    local root = ensure_root_frame()
    local activeSlotData = (index and currentSlotsData and currentSlotsData[index])
    local sr, sg, sb = get_selection_color(activeSlotData)
    local _, _, _, _, _, animations = get_config()

    for i, frame in pairs(activeSlots) do
        local isSelected = (i == index)
        frame._targetScale = isSelected and 1.20 or 1.0
        if not animations then
            frame._currentScale = frame._targetScale
            frame:SetScale(frame._targetScale)
        end
        update_slot_border(frame, isSelected, activeSlotData)
    end

    if activeSlotData then
        root.activeText:SetText(format_active_label(activeSlotData))
        root.activeText:SetTextColor(sr, sg, sb, 1)
        if root.deadzoneDisc.roundBorder then
            root.deadzoneDisc.roundBorder:SetColorTexture(sr, sg, sb, 0.6)
        end
    else
        root.activeText:SetText("cancel")
        root.activeText:SetTextColor(0.5, 0.5, 0.5, 0.8)
        if root.deadzoneDisc.roundBorder then
            root.deadzoneDisc.roundBorder:SetColorTexture(0.3, 0.3, 0.3, 0.4)
        end
    end
end

--- update opening expansion and hover scale lerp animations every frame.
--- @param elapsed number frame delta time in seconds
function view.update_animations(elapsed)
    elapsed = elapsed or 0
    local root = rootFrame
    if not root or not root:IsShown() then return end

    local _, _, _, _, _, animations = get_config()
    if not animations then return end

    -- 1. opening radial expansion animation
    if openAnimActive then
        openAnimTimer = openAnimTimer + elapsed
        local p = math_min(1, openAnimTimer / openAnimDuration)
        -- cubic ease-out
        local ease = 1 - (1 - p) * (1 - p) * (1 - p)

        local distMult = 0.40 + 0.60 * ease
        for _, frame in pairs(activeSlots) do
            if frame._targetDx and frame._targetDy then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", root, "CENTER", frame._targetDx * distMult, frame._targetDy * distMult)
            end
            frame:SetAlpha(ease)
        end

        if root.deadzoneDisc then
            root.deadzoneDisc:SetScale(0.70 + 0.30 * ease)
            root.deadzoneDisc:SetAlpha(0.2 + 0.8 * ease)
        end
        if root.titleText then
            root.titleText:SetAlpha(ease)
        end
        if root.activeText then
            root.activeText:SetAlpha(ease)
        end

        if p >= 1 then
            openAnimActive = false
            for _, frame in pairs(activeSlots) do
                if frame._targetDx and frame._targetDy then
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", root, "CENTER", frame._targetDx, frame._targetDy)
                end
                frame:SetAlpha(1.0)
            end
            if root.deadzoneDisc then
                root.deadzoneDisc:SetScale(1.0)
                root.deadzoneDisc:SetAlpha(1.0)
            end
            if root.titleText then root.titleText:SetAlpha(1.0) end
            if root.activeText then root.activeText:SetAlpha(1.0) end
        end
    end

    -- 2. smooth slot scale lerping
    for _, frame in pairs(activeSlots) do
        local cur = frame._currentScale or 1.0
        local target = frame._targetScale or 1.0
        if cur ~= target then
            local diff = target - cur
            if math_abs(diff) < 0.005 then
                frame._currentScale = target
            else
                frame._currentScale = cur + diff * math_min(1, elapsed * 24)
            end
            frame:SetScale(frame._currentScale)
        end
    end
end

--- reset animation states when ring closes.
function view.on_close()
    openAnimActive = false
    openAnimTimer = 0
    local root = rootFrame
    if root then
        if root.deadzoneDisc then
            root.deadzoneDisc:SetScale(1.0)
            root.deadzoneDisc:SetAlpha(1.0)
        end
        if root.titleText then root.titleText:SetAlpha(1.0) end
        if root.activeText then root.activeText:SetAlpha(1.0) end
    end
    for _, frame in pairs(activeSlots) do
        frame._targetScale = 1.0
        frame._currentScale = 1.0
        frame:SetScale(1.0)
        frame:SetAlpha(1.0)
    end
end

--- get the root view frame.
--- @return Frame
function view.get_frame()
    return ensure_root_frame()
end

--- get currently rendered ring ID.
--- @return string|nil
function view.get_current_ring_id()
    return currentRingID
end

--- get active rendered slot count.
--- @return number
function view.get_active_slots_count()
    local count = 0
    for _ in pairs(activeSlots) do
        count = count + 1
    end
    return count
end
