local addonName, addon = ...
sfui = sfui or {}
sfui.pets = sfui.pets or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/pets_ui.lua
--  Dedicated Standalone Companion Pet Manager UI
--  Zero-Allocation, Frame-Pooled, Drag & Drop Character Favorites Window
-- ══════════════════════════════════════════════════════════════════════════════

-- Guard against game clients without Pet Journal API (e.g. Classic Era / Vanilla / older Camelot)
if not _G.C_PetJournal or not _G.C_PetJournal.GetNumPets then
    return
end

local g      = sfui.config
local common = sfui.common

local CreateFrame                     = _G.CreateFrame
local UIParent                        = _G.UIParent
local InCombatLockdown                = _G.InCombatLockdown
local C_PetJournal_GetPetInfoByPetID  = _G.C_PetJournal.GetPetInfoByPetID
local C_PetJournal_GetSummonedPetGUID = _G.C_PetJournal.GetSummonedPetGUID
local wipe                            = _G.wipe or table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local _petsFrame = nil

function sfui.pets.CreateFrame()
    if _petsFrame then return _petsFrame end

    local f = CreateFrame("Frame", "SfuiPetsFrame", UIParent, "BackdropTemplate")
    table.insert(_G.UISpecialFrames, "SfuiPetsFrame")
    f:SetFrameStrata("DIALOG")
    f:SetSize(540, 600)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Header Icon & Title
    local header_icon = f:CreateTexture(nil, "ARTWORK")
    header_icon:SetSize(22, 22)
    header_icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header_icon:SetTexture("Interface\\Icons\\INV_Box_PetCarrier_01")
    header_icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = f:CreateFontString(nil, "OVERLAY", g.font_large or "GameFontNormalLarge")
    title:SetPoint("LEFT", header_icon, "RIGHT", 8, 0)
    title:SetText("sfui companion pet manager")
    title:SetTextColor(0, 1, 1, 1)

    local close_btn = common.create_flat_button(f, "✕", 22, 22)
    close_btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    close_btn:SetScript("OnClick", function() f:Hide() end)

    -- Section 1: Options & Rotation
    local opt_header = f:CreateFontString(nil, "OVERLAY", g.font or "GameFontNormal")
    opt_header:SetPoint("TOPLEFT", header_icon, "BOTTOMLEFT", 0, -12)
    opt_header:SetTextColor(1, 1, 1, 1)
    opt_header:SetText("automation & rotation settings")

    local COL_OFFSET_X = 260
    local create_checkbox = common.create_checkbox
    local create_slider_input = common.create_slider_input

    local pets_enable_cb = create_checkbox(f, "enable companion auto-summon", "petsEnabled", function(checked)
        if sfui.pets.RebuildPools then sfui.pets.RebuildPools() end
    end, "automatically summons your companion pet when lost after dismounting, taxi, or zoning.")
    pets_enable_cb:SetPoint("TOPLEFT", opt_header, "BOTTOMLEFT", 0, -8)

    local pets_resummon_cb = create_checkbox(f, "auto-restore previous pet", "petsAutoResummon", nil,
        "re-summons your last active companion if dismissed.")
    pets_resummon_cb:SetPoint("LEFT", pets_enable_cb, "LEFT", COL_OFFSET_X, 0)

    local pets_suppress_cb = create_checkbox(f, "suppress in M+ & raids", "petsSuppressInInstances", nil,
        "prevents companion summoning inside Mythic+, Raids, and Arenas.")
    pets_suppress_cb:SetPoint("TOPLEFT", pets_enable_cb, "BOTTOMLEFT", 0, -8)

    local pets_char_favs_cb = create_checkbox(f, "use character favorites", function()
        local charDB = sfui.pets.GetCharDB and sfui.pets.GetCharDB()
        return (charDB and charDB.charFavsEnabled) or false
    end, function(checked)
        local charDB = sfui.pets.GetCharDB and sfui.pets.GetCharDB()
        if charDB then
            charDB.charFavsEnabled = checked
            if sfui.pets.RebuildPools then sfui.pets.RebuildPools() end
        end
        if f.refresh_list then f.refresh_list() end
    end, "use this character's custom favorite list instead of account-wide Pet Journal favorites.")
    pets_char_favs_cb:SetPoint("LEFT", pets_suppress_cb, "LEFT", COL_OFFSET_X, 0)
    f.char_favs_cb = pets_char_favs_cb

    if SfuiDB.petsRotationTimer == nil then SfuiDB.petsRotationTimer = 720 end
    local pets_rot_slider = create_slider_input(f, "rotation timer (secs):", "petsRotationTimer", 0, 3600, 60, nil,
        "periodic timer in seconds to rotate to a new pet (0 to disable).")
    pets_rot_slider:SetPoint("TOPLEFT", pets_suppress_cb, "BOTTOMLEFT", 0, -10)

    if SfuiDB.petsFavProbability == nil then SfuiDB.petsFavProbability = 50 end
    if SfuiDB.petsFavProbability <= 1 and SfuiDB.petsFavProbability > 0 then
        SfuiDB.petsFavProbability = math.floor(SfuiDB.petsFavProbability * 100)
    end
    local pets_prob_slider = create_slider_input(f, "favorite chance (%):", "petsFavProbability", 0, 100, 5, nil,
        "chance to pick a favorite pet over a random pet when in weighted mode.")
    pets_prob_slider:SetPoint("LEFT", pets_rot_slider, "LEFT", COL_OFFSET_X, 0)

    local function GetPetModeOptions()
        return {
            { text = "Favorites Only", value = "favs" },
            { text = "All Collected Pets", value = "all" },
            { text = "Weighted (Favs + All)", value = "weighted" },
        }
    end

    local mode_label = f:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontNormalSmall")
    mode_label:SetPoint("TOPLEFT", pets_rot_slider, "BOTTOMLEFT", 0, -12)
    mode_label:SetTextColor(1, 1, 1, 0.8)
    mode_label:SetText("summon pool mode:")

    if SfuiDB.petsMode == nil then SfuiDB.petsMode = "favs" end
    local mode_dropdown = common.create_dropdown(f, 180, GetPetModeOptions, function(val)
        SfuiDB.petsMode = val
        if sfui.pets.RebuildPools then sfui.pets.RebuildPools() end
    end, SfuiDB.petsMode)
    mode_dropdown:SetPoint("LEFT", mode_label, "RIGHT", 10, 0)

    -- Section 2: Character Favorites List
    local favs_sep = f:CreateTexture(nil, "ARTWORK")
    favs_sep:SetHeight(1)
    favs_sep:SetPoint("TOPLEFT", 10, -188)
    favs_sep:SetPoint("TOPRIGHT", -10, -188)
    favs_sep:SetColorTexture(0.2, 0.2, 0.2, 1)

    local favs_header = f:CreateFontString(nil, "OVERLAY", g.font or "GameFontNormal")
    favs_header:SetPoint("TOPLEFT", favs_sep, "BOTTOMLEFT", 0, -10)
    favs_header:SetTextColor(1, 1, 1, 1)

    local function get_char_title()
        local charKey = (sfui.pets.GetCharacterKey and sfui.pets.GetCharacterKey()) or "character"
        return "character favorites (" .. charKey .. ")"
    end
    favs_header:SetText(get_char_title())

    local favs_sub = f:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontNormalSmall")
    favs_sub:SetPoint("TOPLEFT", favs_header, "BOTTOMLEFT", 0, -4)
    favs_sub:SetTextColor(0.65, 0.65, 0.65, 1)
    favs_sub:SetText("drag pets from your Pet Journal (Shift+P) into the drop box, or use the action buttons.")

    local add_current_btn = common.create_flat_button(f, "add current pet", 110, 22)
    add_current_btn:SetPoint("TOPLEFT", favs_sub, "BOTTOMLEFT", 0, -10)
    add_current_btn:SetScript("OnClick", function()
        if sfui.pets.AddCurrentPetToCharFavs then sfui.pets.AddCurrentPetToCharFavs() end
        if f.char_favs_cb and f.char_favs_cb.SetChecked then
            f.char_favs_cb:SetChecked(true)
        end
        if f.refresh_list then f.refresh_list() end
    end)

    local summon_next_btn = common.create_flat_button(f, "summon next", 95, 22)
    summon_next_btn:SetPoint("LEFT", add_current_btn, "RIGHT", 8, 0)
    summon_next_btn:SetScript("OnClick", function()
        if sfui.pets.SummonNext then sfui.pets.SummonNext(true) end
    end)

    local clear_all_btn = common.create_flat_button(f, "clear all", 75, 22)
    clear_all_btn:SetPoint("LEFT", summon_next_btn, "RIGHT", 8, 0)
    clear_all_btn:SetScript("OnClick", function()
        if sfui.pets.ClearCharFavs then sfui.pets.ClearCharFavs() end
        if f.refresh_list then f.refresh_list() end
    end)

    local drop_box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    drop_box:SetPoint("LEFT", clear_all_btn, "RIGHT", 10, 0)
    drop_box:SetSize(140, 22)
    drop_box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    drop_box:SetBackdropColor(0.12, 0.12, 0.12, 0.8)
    drop_box:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local drop_text = drop_box:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontNormalSmall")
    drop_text:SetPoint("CENTER")
    drop_text:SetTextColor(0.8, 0.8, 0.8, 1)
    drop_text:SetText("+ drop pet here")

    drop_box:EnableMouse(true)
    drop_box:RegisterForDrag("LeftButton")

    local function handle_pet_drop()
        local cType, petGUID = _G.GetCursorInfo()
        if (cType == "battlepet" or cType == "companion") and petGUID then
            local charDB = sfui.pets.GetCharDB and sfui.pets.GetCharDB()
            if charDB then
                charDB.charFavs[petGUID] = true
                charDB.charFavsEnabled = true
                if sfui.pets.RebuildPools then sfui.pets.RebuildPools() end
                if f.char_favs_cb and f.char_favs_cb.SetChecked then
                    f.char_favs_cb:SetChecked(true)
                end
                if f.refresh_list then f.refresh_list() end
                local name = (C_PetJournal_GetPetInfoByPetID and select(8, C_PetJournal_GetPetInfoByPetID(petGUID))) or "Companion"
                if sfui.common and sfui.common.print then
                    sfui.common.print("sfui: Added |cff00ffff" .. tostring(name) .. "|r to character favorites.")
                end
            end
            if _G.ClearCursor then _G.ClearCursor() end
        end
    end
    drop_box:SetScript("OnReceiveDrag", handle_pet_drop)
    drop_box:SetScript("OnMouseUp", handle_pet_drop)
    drop_box:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 1, 1, 1)
        local tip = sfui.tooltip or _G.GameTooltip
        if tip then
            tip:SetOwner(self, "ANCHOR_RIGHT")
            tip:SetText("drop pet here", 1, 1, 1)
            tip:AddLine("Drag any pet from your Pet Journal (Shift+P) and drop it here to add it to this character's favorites.", 0.8, 0.8, 0.8, true)
            tip:Show()
        end
    end)
    drop_box:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
        local tip = sfui.tooltip or _G.GameTooltip
        if tip then tip:Hide() end
    end)

    -- Scroll Frame & Row Pool
    local scroll_container = CreateFrame("Frame", nil, f, "BackdropTemplate")
    scroll_container:SetPoint("TOPLEFT", add_current_btn, "BOTTOMLEFT", 0, -10)
    scroll_container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
    scroll_container:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    scroll_container:SetBackdropColor(0.03, 0.03, 0.03, 0.8)
    scroll_container:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)

    local scroll_frame = CreateFrame("ScrollFrame", "SfuiPetsScrollFrame", scroll_container, "UIPanelScrollFrameTemplate")
    scroll_frame:SetPoint("TOPLEFT", 4, -4)
    scroll_frame:SetPoint("BOTTOMRIGHT", -4, 4)
    scroll_frame:EnableMouseWheel(true)
    if common.style_scrollbar and scroll_frame.ScrollBar then
        common.style_scrollbar(scroll_frame.ScrollBar)
    end

    local scroll_child = CreateFrame("Frame", nil, scroll_frame)
    scroll_child:SetSize(490, 100)
    scroll_frame:SetScrollChild(scroll_child)

    local empty_text = scroll_child:CreateFontString(nil, "OVERLAY", g.font or "GameFontNormal")
    empty_text:SetPoint("CENTER", scroll_container, "CENTER", 0, 0)
    empty_text:SetTextColor(0.5, 0.5, 0.5, 1)
    empty_text:SetJustifyH("CENTER")
    empty_text:SetText("No character favorites set.\nClick 'Add Current Pet', drag from Pet Journal,\nor type '/sfpet add'.")

    local row_pool = {}
    local active_rows = {}
    local sorted_guids = {}

    local function create_pet_row(index)
        local row = CreateFrame("Frame", nil, scroll_child, "BackdropTemplate")
        row:SetSize(488, 26)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
        row:SetBackdropBorderColor(0.16, 0.16, 0.16, 0.9)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.icon = icon

        local icon_border = row:CreateTexture(nil, "BORDER")
        icon_border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        icon_border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
        icon_border:SetColorTexture(0, 0, 0, 1)

        local name_text = row:CreateFontString(nil, "OVERLAY", g.font or "GameFontNormal")
        name_text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        name_text:SetWidth(200)
        name_text:SetJustifyH("LEFT")
        name_text:SetWordWrap(false)
        row.name_text = name_text

        local type_text = row:CreateFontString(nil, "OVERLAY", g.font_small or "GameFontDisableSmall")
        type_text:SetPoint("LEFT", name_text, "RIGHT", 6, 0)
        type_text:SetWidth(110)
        type_text:SetJustifyH("LEFT")
        type_text:SetTextColor(0.65, 0.65, 0.65, 1)
        row.type_text = type_text

        local remove_btn = common.create_flat_button(row, "✕", 22, 20)
        remove_btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        remove_btn:SetScript("OnClick", function()
            if row.petGUID and sfui.pets.RemovePetFromCharFavs then
                sfui.pets.RemovePetFromCharFavs(row.petGUID)
                f.refresh_list()
            end
        end)
        remove_btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.2, 0.2, 1)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then
                tip:SetOwner(self, "ANCHOR_RIGHT")
                tip:SetText("remove from character favorites", 1, 0.3, 0.3)
                tip:Show()
            end
        end)
        remove_btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)
        row.remove_btn = remove_btn

        local summon_btn = common.create_flat_button(row, "summon", 55, 20)
        summon_btn:SetPoint("RIGHT", remove_btn, "LEFT", -6, 0)
        summon_btn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                if sfui.common and sfui.common.print then
                    sfui.common.print("sfui: Cannot summon pets in combat.")
                end
                return
            end
            if row.petGUID and sfui.pets.SummonPetByGUID then
                sfui.pets.SummonPetByGUID(row.petGUID)
                f.refresh_list()
            end
        end)
        row.summon_btn = summon_btn

        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.14, 0.14, 0.14, 0.9)
            local tip = sfui.tooltip or _G.GameTooltip
            if self.petGUID and tip and C_PetJournal_GetPetInfoByPetID then
                local speciesID, customName, level, _, _, _, _, name, _, petType = C_PetJournal_GetPetInfoByPetID(self.petGUID)
                if speciesID then
                    tip:SetOwner(self, "ANCHOR_RIGHT")
                    tip:SetText(customName or name or "Companion", 1, 1, 1)
                    if customName and customName ~= name then
                        tip:AddLine(name, 0.8, 0.8, 0.8)
                    end
                    local typeName = (petType and _G["BATTLE_PET_NAME_" .. petType]) or ""
                    tip:AddLine(string.format("Level %d %s", level or 1, typeName), 0.9, 0.9, 0.3)
                    tip:Show()
                end
            end
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
            local tip = sfui.tooltip or _G.GameTooltip
            if tip then tip:Hide() end
        end)

        return row
    end

    local function refresh_pet_list()
        favs_header:SetText(get_char_title())
        for _, row in ipairs(active_rows) do
            row:Hide()
        end
        wipe(active_rows)
        wipe(sorted_guids)

        local charDB = sfui.pets.GetCharDB and sfui.pets.GetCharDB()
        if charDB and charDB.charFavs then
            for guid, enabled in pairs(charDB.charFavs) do
                if enabled and C_PetJournal_GetPetInfoByPetID then
                    table.insert(sorted_guids, guid)
                end
            end
        end

        local count = #sorted_guids
        local activeGUID = C_PetJournal_GetSummonedPetGUID and C_PetJournal_GetSummonedPetGUID()

        if count == 0 then
            empty_text:Show()
            scroll_child:SetHeight(100)
        else
            empty_text:Hide()
            table.sort(sorted_guids, function(a, b)
                local nameA = (select(8, C_PetJournal_GetPetInfoByPetID(a))) or a
                local nameB = (select(8, C_PetJournal_GetPetInfoByPetID(b))) or b
                return nameA < nameB
            end)

            local ROW_HEIGHT = 28
            for i, guid in ipairs(sorted_guids) do
                local row = row_pool[i]
                if not row then
                    row = create_pet_row(i)
                    row_pool[i] = row
                end

                local speciesID, customName, level, _, _, _, _, name, iconTex, petType = C_PetJournal_GetPetInfoByPetID(guid)
                row.petGUID = guid
                row.icon:SetTexture(iconTex or "Interface/Icons/INV_Misc_QuestionMark")

                local displayName = name or "Unknown Pet"
                if customName and customName ~= "" and customName ~= name then
                    displayName = customName .. " (" .. name .. ")"
                end
                row.name_text:SetText(displayName)

                local typeName = (petType and _G["BATTLE_PET_NAME_" .. petType]) or ""
                local lvlStr = level and ("Lv " .. level) or ""
                if lvlStr ~= "" and typeName ~= "" then
                    row.type_text:SetText(lvlStr .. " · " .. typeName)
                elseif lvlStr ~= "" then
                    row.type_text:SetText(lvlStr)
                else
                    row.type_text:SetText(typeName)
                end

                local isSummoned = (activeGUID and activeGUID == guid)
                if isSummoned then
                    row:SetBackdropBorderColor(0, 1, 0, 0.8)
                    if row.summon_btn and row.summon_btn.text then
                        row.summon_btn.text:SetText("active")
                        row.summon_btn.text:SetTextColor(0, 1, 0, 1)
                    end
                else
                    row:SetBackdropBorderColor(0.16, 0.16, 0.16, 0.9)
                    if row.summon_btn and row.summon_btn.text then
                        row.summon_btn.text:SetText("summon")
                        row.summon_btn.text:SetTextColor(1, 1, 1, 1)
                    end
                end

                row:SetPoint("TOPLEFT", scroll_child, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
                row:Show()
                table.insert(active_rows, row)
            end

            scroll_child:SetHeight(math.max(count * ROW_HEIGHT + 10, 100))
        end

        scroll_frame:UpdateScrollChildRect()
    end

    f.refresh_list = refresh_pet_list
    f:SetScript("OnShow", refresh_pet_list)

    if sfui.events and sfui.events.RegisterEvent then
        sfui.events.RegisterEvent("COMPANION_UPDATE", function()
            if _petsFrame and _petsFrame:IsVisible() then
                refresh_pet_list()
            end
        end)
    end

    _petsFrame = f
    return f
end

function sfui.pets.Toggle()
    local f = sfui.pets.CreateFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

_G["SFUI_PET_MANAGER"] = function() sfui.pets.Toggle() end
