local addonName, addon = ...
sfui = sfui or {}
sfui.theme = sfui.theme or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/themes/engine.lua
--  Extensible Driver-Based Theme Engine
-- ══════════════════════════════════════════════════════════════════════════════

local C_Texture = _G.C_Texture
local unpack = _G.unpack or table.unpack
local type = _G.type
local pairs = _G.pairs
local ipairs = _G.ipairs
local table_insert = table.insert
local table_remove = table.remove
local pcall = _G.pcall
local CreateFrame = _G.CreateFrame
local math_max = math.max

-- ─── Internal Theme Store ─────────────────────────────────────────────────────
local registeredThemes = {}
local themeOrder = {}

-- ─── Widget Tracking (Weak Metatables for Automatic Garbage Collection) ───────
local registered_windows       = {} -- Array of { frame = frame, callback = cb, options = opt }
local registered_buttons       = setmetatable({}, { __mode = "k" })
local registered_close_buttons = setmetatable({}, { __mode = "k" })
local registered_dropdowns     = setmetatable({}, { __mode = "k" })
local registered_cards         = setmetatable({}, { __mode = "k" })
local registered_headers       = setmetatable({}, { __mode = "k" })
local registered_inputs        = setmetatable({}, { __mode = "k" })
local registered_tabs          = setmetatable({}, { __mode = "k" })
local registered_bars          = setmetatable({}, { __mode = "k" }) -- { [barObj] = barType }
local registered_scrollbars    = setmetatable({}, { __mode = "k" })

-- ─── Public Theme Registration API ────────────────────────────────────────────
--- Register a new theme definition with the engine.
--- @param themeDef table
function sfui.theme.RegisterTheme(themeDef)
    if not themeDef or not themeDef.id then return end
    registeredThemes[themeDef.id] = themeDef

    local exists = false
    for _, id in ipairs(themeOrder) do
        if id == themeDef.id then
            exists = true
            break
        end
    end
    if not exists then
        table_insert(themeOrder, themeDef.id)
    end

    -- Keep legacy sfui.theme.palettes in sync for backwards compatibility
    sfui.theme.palettes = sfui.theme.palettes or {}
    if themeDef.colors then
        sfui.theme.palettes[themeDef.id] = themeDef.colors
    end
end

--- Get a registered theme definition by ID.
--- @param id string
--- @return table|nil
function sfui.theme.GetTheme(id)
    return registeredThemes[id]
end

--- Get all registered themes and their insertion order.
--- @return table, table
function sfui.theme.GetRegisteredThemes()
    return registeredThemes, themeOrder
end

-- ─── Atlas Validation Helpers ─────────────────────────────────────────────────
function sfui.theme.HasAtlas(atlasName)
    if not atlasName then return false end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlasName)
        return ok and (info ~= nil)
    end
    return false
end

function sfui.theme.GetCornerBracketAtlas(corner, themeDef)
    themeDef = themeDef or sfui.theme.GetTheme(sfui.theme.GetActiveThemeID())
    local atlases = themeDef and themeDef.atlases
    if not atlases then return nil end

    local nativeKey = "corner" .. corner .. "Native"
    local fallbackKey = "corner" .. corner .. "Fallback"
    if atlases[nativeKey] and sfui.theme.HasAtlas(atlases[nativeKey]) then
        return atlases[nativeKey]
    end
    if atlases[fallbackKey] and sfui.theme.HasAtlas(atlases[fallbackKey]) then
        return atlases[fallbackKey]
    end
    return nil
end

function sfui.theme.IsCamelotSupported()
    if sfui.isCamelot or (sfui.compat and sfui.compat.is_camelot) then
        return true
    end
    -- Fallback: check if the client actually has the native bronze frame atlas
    return sfui.theme.HasAtlas("heavybronze-frame-basic")
end

-- ─── Active Theme Resolution & Setting ────────────────────────────────────────
function sfui.theme.GetActiveThemeID()
    if sfui.theme.forcedMode then
        if sfui.theme.forcedMode == "camelot" and not sfui.theme.IsCamelotSupported() then
            return "modern"
        end
        return sfui.theme.forcedMode
    end

    local mode
    if SfuiDB then
        mode = SfuiDB.themeMode or (SfuiDB.theme and SfuiDB.theme.mode)
    end
    if not mode and sfui.config and sfui.config.theme then
        mode = sfui.config.theme.mode
    end
    mode = mode or "auto"

    if mode == "auto" then
        -- Query registered themes to see if one claims auto-detect for current client
        for _, id in ipairs(themeOrder) do
            local def = registeredThemes[id]
            if def and def.autoDetect and def.autoDetect() then
                if id == "camelot" and not sfui.theme.IsCamelotSupported() then
                    -- Cannot use camelot if bronze assets are not present
                else
                    return def.id
                end
            end
        end
        -- Default fallbacks if no autoDetect claims it
        if sfui.theme.IsCamelotSupported() then
            return "camelot"
        end
        return "modern"
    end

    if mode == "camelot" and not sfui.theme.IsCamelotSupported() then
        return "modern"
    end

    if registeredThemes[mode] then
        return mode
    end
    return "modern"
end

--- Apply a bar texture to all SFUI status bars, saving it to database and updating configs/options.
--- @param textureName string e.g. "Blizzard Nameplate", "Flat", or an atlas/path
function sfui.theme.ApplyThemeBarTexture(textureName)
    if not textureName or textureName == "" then return end

    local val = textureName
    local texturePath = sfui.widgets.resolve_statusbar_texture(val)

    SfuiDB = SfuiDB or {}
    SfuiDB.barTexture = val
    sfui.config.barTexture = texturePath

    sfui.bars.set_bar_texture(texturePath)
    sfui.castbar.set_bar_texture(texturePath)
    sfui.vehicle.set_bar_texture(texturePath)
    sfui.trackedbars.SetBarTexture(texturePath)
    sfui.tracker.blocks.SetBarTexture(texturePath)
    sfui.tracker.helpers.timerbars.SetBarTexture(texturePath)
    sfui.tracker.RequestRefresh()

    if sfui.isRetail then
        if sfui.soulfragments and sfui.soulfragments.SetBarTexture then
            sfui.soulfragments.SetBarTexture(texturePath)
        end
    else
        if sfui.swing and sfui.swing.SetBarTexture then
            sfui.swing.SetBarTexture(texturePath)
        end
        if sfui.target and sfui.target.SetBarTexture then
            sfui.target.SetBarTexture(texturePath)
        end
        if sfui.threat and sfui.threat.SetBarTexture then
            sfui.threat.SetBarTexture(texturePath)
        end
    end

    sfui.options.notify_setting_changed("bars", "barTexture", val)
    sfui.options.notify_setting_changed("castbar", "barTexture", val)
    sfui.options.notify_setting_changed("trackedbars", "barTexture", val)
    if not sfui.isRetail then
        sfui.options.notify_setting_changed("target", "barTexture", val)
    end

    if sfui.options.mainTab and sfui.options.mainTab.texture_dropdown then
        sfui.options.mainTab.texture_dropdown.SetSelectedTexture(val)
    end
end
sfui.ApplyThemeBarTexture = sfui.theme.ApplyThemeBarTexture

function sfui.theme.SetTheme(mode)
    mode = mode and mode:lower()
    if mode == "camelot" and not sfui.theme.IsCamelotSupported() then
        return false, "Camelot Heavy Bronze theme is exclusive to Camelot (bronze assets are not in Retail)."
    end

    if mode ~= "auto" and not registeredThemes[mode] then
        return false, "Unknown theme mode: " .. tostring(mode)
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.themeMode = mode
    if SfuiDB.theme then
        SfuiDB.theme.mode = mode
    end
    sfui.db.Set("theme", "mode", mode)

    local activeID = sfui.theme.GetActiveThemeID()
    local themeDef = registeredThemes[activeID]
    local themeBarTex = themeDef and (themeDef.barTexture or (themeDef.bars and themeDef.bars.texture))
    if themeBarTex then
        SfuiDB._barTextureCustomized = nil
        sfui.theme.ApplyThemeBarTexture(themeBarTex)
    end

    sfui.theme.ApplyCurrentTheme()
    return true, mode
end

function sfui.theme.IsCamelotActive()
    return sfui.theme.IsCamelotSupported() and (sfui.theme.GetActiveThemeID() == "camelot")
end

function sfui.theme.IsFlatButtonActive()
    if not sfui.theme.IsCamelotActive() then return true end
    if SfuiDB then
        if SfuiDB.themeFlatButtons ~= nil then
            return (SfuiDB.themeFlatButtons == true)
        end
        if SfuiDB.themeButtonStyle ~= nil then
            return (SfuiDB.themeButtonStyle == "flat")
        end
    end
    if sfui.config and sfui.config.theme and sfui.config.theme.buttonStyle ~= nil then
        return (sfui.config.theme.buttonStyle == "flat")
    end
    return false
end

function sfui.theme.IsAuctionHouseButtonActive()
    return sfui.theme.IsCamelotActive() and not sfui.theme.IsFlatButtonActive()
end

function sfui.theme.SetFlatButtons(isFlat)
    if not SfuiDB then SfuiDB = {} end
    SfuiDB.themeFlatButtons = (isFlat == true)
    SfuiDB.themeButtonStyle = isFlat and "flat" or "auctionhouse"
    SfuiDB.themeAuctionHouseButtons = not isFlat
    SfuiDB.themeBronzeButtons = nil
end

function sfui.theme.IsBronzeButtonActive()
    return sfui.theme.IsAuctionHouseButtonActive()
end

local function SetupAuctionHouseTextures(btn, isSelected)
    -- 1. Normal Background Texture (Auction House beveled pill texture)
    if not btn._sfuiAHBg then
        btn._sfuiAHBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    end

    if sfui.theme.HasAtlas("auctionhouse-nav-button") then
        btn._sfuiAHBg:SetAtlas("auctionhouse-nav-button", false)
        btn._sfuiAHBg:ClearAllPoints()
        btn._sfuiAHBg:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 0)
        btn._sfuiAHBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 2, 0)
        local btnH = btn:GetHeight()
        if not btnH or btnH <= 0 then btnH = 20 end
        btn._sfuiAHBg:SetHeight(btnH * (32 / 21))
    else
        btn._sfuiAHBg:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
        btn._sfuiAHBg:SetTexCoord(0, 0.53125, 0, 0.625)
        btn._sfuiAHBg:ClearAllPoints()
        btn._sfuiAHBg:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 0)
        btn._sfuiAHBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, 0)
    end
    btn._sfuiAHBg:Show()
    if not btn:IsEnabled() then
        btn._sfuiAHBg:SetVertexColor(0.45, 0.45, 0.45, 0.70)
        btn._sfuiAHBg:SetDesaturated(true)
    else
        btn._sfuiAHBg:SetVertexColor(1.0, 1.0, 1.0, 1.0)
        btn._sfuiAHBg:SetDesaturated(false)
    end

    if not btn._sfuiAHSizeHook then
        btn._sfuiAHSizeHook = true
        btn:HookScript("OnSizeChanged", function(self, _, newH)
            if self._sfuiAHBg and newH and newH > 0 and sfui.theme.HasAtlas("auctionhouse-nav-button") then
                self._sfuiAHBg:SetHeight(newH * (32 / 21))
            end
        end)
    end

    -- 2. Mouseover Highlight Texture (Blueish glow: auctionhouse-nav-button-highlight or UI-Character-Tab-Highlight)
    if not btn._sfuiAHHighlight then
        btn._sfuiAHHighlight = btn:CreateTexture(nil, "BORDER", nil, 1)
        btn._sfuiAHHighlight:SetBlendMode("ADD")
        if sfui.theme.HasAtlas("auctionhouse-nav-button-highlight") then
            btn._sfuiAHHighlight:SetAtlas("auctionhouse-nav-button-highlight", false)
        else
            btn._sfuiAHHighlight:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
        end
    end
    btn._sfuiAHHighlight:ClearAllPoints()
    btn._sfuiAHHighlight:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 1)
    btn._sfuiAHHighlight:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -1)
    if btn:IsMouseOver() and btn:IsEnabled() then
        btn._sfuiAHHighlight:Show()
    else
        btn._sfuiAHHighlight:Hide()
    end

    -- 3. Selected Texture (Gold glowing outline: auctionhouse-nav-button-select with ADD blend mode)
    if not btn._sfuiAHSelected then
        btn._sfuiAHSelected = btn:CreateTexture(nil, "BORDER", nil, 2)
        btn._sfuiAHSelected:SetBlendMode("ADD")
        if sfui.theme.HasAtlas("auctionhouse-nav-button-select") then
            btn._sfuiAHSelected:SetAtlas("auctionhouse-nav-button-select", false)
        else
            btn._sfuiAHSelected:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
            btn._sfuiAHSelected:SetTexCoord(0, 0.53125, 0, 0.625)
            btn._sfuiAHSelected:SetVertexColor(1.0, 0.85, 0.25, 0.85)
        end
    end
    btn._sfuiAHSelected:ClearAllPoints()
    btn._sfuiAHSelected:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 1)
    btn._sfuiAHSelected:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -1)

    local sel = (isSelected == true) or (btn.isSelected == true) or (btn.isSelectedTab == true)
    btn._sfuiAHSelected:SetShown(sel)

    local fs = btn:GetFontString() or btn.text or btn.fs
    if fs then
        fs:SetDrawLayer("OVERLAY", 1)
    end

    if btn._sfuiCamelotBg then btn._sfuiCamelotBg:Hide() end
    if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 0) end
    if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
end

function sfui.theme.SetButtonSelected(btn, isSelected)
    if not btn then return end
    btn.isSelected = (isSelected == true)
    local useAH = sfui.theme.IsAuctionHouseButtonActive()
    if useAH then
        if not btn._sfuiAHBg then
            SetupAuctionHouseTextures(btn, isSelected)
        elseif btn._sfuiAHSelected then
            btn._sfuiAHSelected:SetShown(isSelected == true)
            if not isSelected then
                btn._sfuiAHSelected:SetVertexColor(1.0, 1.0, 1.0, 1.0)
            end
        end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
        if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 0) end
    end
    local fs = btn:GetFontString() or btn.text or btn.fs
    if fs then
        if isSelected then
            fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
        else
            local pal = sfui.theme.GetPalette()
            local col = pal.accentColor or pal.tabNormal or { 0.95, 0.85, 0.55, 1.0 }
            fs:SetTextColor(col[1], col[2], col[3], 1.0)
        end
    end
    if not useAH then
        local pal = sfui.theme.GetPalette()
        if isSelected then
            local hl = pal.accentColor or pal.highlightColor or { 0.82, 0.65, 0.32, 1.0 }
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0) end
            if btn.SetBackdropColor then btn:SetBackdropColor(0.18, 0.14, 0.10, 0.98) end
        else
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85) end
            if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.10, 0.08, 0.95) end
        end
    end
end

function sfui.theme.GetPalette()
    local themeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[themeID] or registeredThemes.modern
    if theme and theme.colors then
        return theme.colors
    end
    return sfui.config.appearance
end

-- ─── Component Style Providers ────────────────────────────────────────────────

-- 0. Window Layer Elevation & Header Helpers
--- Create a dedicated header child frame that is properly elevated above theme layers.
--- @param parent Frame
--- @param height number?
--- @return Frame
function sfui.theme.CreateHeaderFrame(parent, height)
    if not parent then return end
    local base = parent:GetFrameLevel() or 1
    local headerFrame = CreateFrame("Frame", nil, parent)
    headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(height or 40)
    headerFrame:SetFrameLevel(base + 15)
    headerFrame:EnableMouse(false)
    parent.headerFrame = headerFrame
    return headerFrame
end

--- Elevate child headers, close buttons, and tab panels above the theme borderFrame layer.
--- In WoW, any child frame (borderFrame at base + 1) renders after all regions on the parent frame (base).
--- Elevating headers to base + 15 and close buttons to base + 20 prevents them from being occluded.
--- @param frame Frame
function sfui.theme.ElevateWindowContents(frame)
    if not frame then return end
    local base = frame:GetFrameLevel() or 1
    if frame.sfuiThemeLayers and frame.sfuiThemeLayers.borderFrame then
        frame.sfuiThemeLayers.borderFrame:SetFrameLevel(base + 1)
    end
    local h = frame.headerFrame or frame.headerBar or frame.header
    if h and h.SetFrameLevel then
        h:SetFrameLevel(base + 15)
    end
    local cb = frame.closeBtn or frame.close_button or frame.close or frame.closeButton
    if cb and cb.SetFrameLevel then
        cb:SetFrameLevel(base + 20)
    end
    local topButtons = {
        frame.collapseBtn, frame.mapOptBtn, frame.navWpBtn, frame.showMapBtn,
    }
    for _, btn in ipairs(topButtons) do
        if btn and btn.SetFrameLevel then
            btn:SetFrameLevel(base + 20)
        end
    end
    if frame.tabs then
        for _, tab_data in ipairs(frame.tabs) do
            if tab_data.panel and tab_data.panel.SetFrameLevel then
                tab_data.panel:SetFrameLevel(base + 5)
            end
            if tab_data.button and tab_data.button.SetFrameLevel then
                tab_data.button:SetFrameLevel(base + 10)
            end
        end
    end
end

-- 1. Window Styling (Frames / Dialogs / Windows)
function sfui.theme.ApplyWindowStyle(frame, options)
    if not frame then return end
    options = options or {}

    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()

    -- Allow theme definition to supply custom ApplyWindow hook
    if theme.ApplyWindow then
        theme.ApplyWindow(frame, options, theme)
        return
    end

    local style = theme.window and theme.window.style
    local isSculptedWindow = (style == "bronze" or style == "heavy_bronze" or style == "metal_pieces") and sfui.theme.IsCamelotSupported()
    local showBrackets = (options.cornerBrackets ~= false)
    if SfuiDB and SfuiDB.themeCornerBrackets == false then
        showBrackets = false
    end

    if isSculptedWindow then
        if not frame.sfuiThemeLayers then
            frame.sfuiThemeLayers = {}

            -- Container frame for metal/bronze borders and corner brackets
            local borderFrame = CreateFrame("Frame", nil, frame)
            borderFrame:SetAllPoints(frame)
            borderFrame:SetFrameLevel(math_max(1, (frame:GetFrameLevel() or 1) + 1))
            borderFrame:EnableMouse(false)
            frame.sfuiThemeLayers.borderFrame = borderFrame

            local nativeBorder = borderFrame:CreateTexture(nil, "BORDER", nil, 1)
            frame.sfuiThemeLayers.nativeBorder = nativeBorder

            -- Native Backdrop (sits on BACKGROUND layer)
            local nativeBackdrop = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
            nativeBackdrop:SetAllPoints(borderFrame)
            frame.sfuiThemeLayers.nativeBackdrop = nativeBackdrop

            -- Interior background texture fallback (sits behind metal frame in BACKGROUND layer)
            local innerBg = borderFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
            innerBg:SetAllPoints(borderFrame)
            frame.sfuiThemeLayers.innerBg = innerBg

            -- 8 pieces for sculpted Blizzard metal frame fallback
            local pTL = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pTR = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pBL = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pBR = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pTop = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pBot = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pLeft = borderFrame:CreateTexture(nil, "BORDER", nil, 2)
            local pRight = borderFrame:CreateTexture(nil, "BORDER", nil, 2)

            pTop:SetPoint("TOPLEFT", pTL, "TOPRIGHT", 0, 0)
            pTop:SetPoint("TOPRIGHT", pTR, "TOPLEFT", 0, 0)
            pTop:SetHeight(75)

            pBot:SetPoint("BOTTOMLEFT", pBL, "BOTTOMRIGHT", 0, 0)
            pBot:SetPoint("BOTTOMRIGHT", pBR, "BOTTOMLEFT", 0, 0)
            pBot:SetHeight(32)

            pLeft:SetPoint("TOPLEFT", pTL, "BOTTOMLEFT", 0, 0)
            pLeft:SetPoint("BOTTOMLEFT", pBL, "TOPLEFT", 0, 0)
            pLeft:SetWidth(32)

            pRight:SetPoint("TOPRIGHT", pTR, "BOTTOMRIGHT", 0, 0)
            pRight:SetPoint("BOTTOMRIGHT", pBR, "TOPRIGHT", 0, 0)
            pRight:SetWidth(32)

            frame.sfuiThemeLayers.metalPieces = {
                tl = pTL, tr = pTR, bl = pBL, br = pBR,
                top = pTop, bot = pBot, left = pLeft, right = pRight,
            }

            -- Four sculpted corner brackets
            local cornerTL = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.sfuiThemeLayers.cornerTL = cornerTL

            local cornerTR = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.sfuiThemeLayers.cornerTR = cornerTR

            local cornerBL = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.sfuiThemeLayers.cornerBL = cornerBL

            local cornerBR = borderFrame:CreateTexture(nil, "OVERLAY", nil, 6)
            frame.sfuiThemeLayers.cornerBR = cornerBR
        end

        local layers = frame.sfuiThemeLayers
        layers.borderFrame:Show()

        local atlases = theme.atlases or {}
        local hasBorder = false

        -- Priority: Authentic Camelot Heavy Bronze (heavybronze-frame-basic)
        local useBronze = (style == "bronze" or style == "heavy_bronze") or (atlases.frameBorderNative and style ~= "metal_pieces")

        -- Ensure metal pieces are completely stripped and hidden when not in metal_pieces mode
        if style ~= "metal_pieces" and layers.metalPieces then
            for _, p in pairs(layers.metalPieces) do
                p:SetTexture(nil)
                p:ClearAllPoints()
                p:Hide()
            end
        end

        if useBronze and atlases.frameBorderNative and sfui.theme.HasAtlas(atlases.frameBorderNative) then
            -- Authentic Blizzard offset (CharacterSelectListBackground pattern: x=-9..-10, y=15)
            -- This accounts for the 10-12px internal atlas padding of heavybronze-frame-basic
            -- and cleanly encompasses the content window and close button.
            layers.nativeBorder:ClearAllPoints()
            layers.nativeBorder:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", -10, 15)
            layers.nativeBorder:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", 10, -15)
            layers.nativeBorder:SetAtlas(atlases.frameBorderNative)
            layers.nativeBorder:Show()

            if layers.metalPieces then
                for _, p in pairs(layers.metalPieces) do
                    p:SetTexture(nil)
                    p:ClearAllPoints()
                    p:Hide()
                end
            end
            hasBorder = true

            -- Corner brackets anchored to the 4 corners of nativeBorder (Blizzard CharacterCreate pattern)
            layers.cornerTL:ClearAllPoints()
            layers.cornerTL:SetPoint("TOPLEFT", layers.nativeBorder, "TOPLEFT", 0, 0)
            layers.cornerTR:ClearAllPoints()
            layers.cornerTR:SetPoint("TOPRIGHT", layers.nativeBorder, "TOPRIGHT", 0, 0)
            layers.cornerBL:ClearAllPoints()
            layers.cornerBL:SetPoint("BOTTOMLEFT", layers.nativeBorder, "BOTTOMLEFT", 0, 0)
            layers.cornerBR:ClearAllPoints()
            layers.cornerBR:SetPoint("BOTTOMRIGHT", layers.nativeBorder, "BOTTOMRIGHT", 0, 0)

            -- Native Backdrop (heavybronze-frame-background)
            -- Tucked under nativeBorder bevel (Blizzard CharacterCreate pattern: x=10, y=-10..-12)
            -- so the background cannot bleed past the bronze frame into the game world
            if atlases.frameBackdropNative and sfui.theme.HasAtlas(atlases.frameBackdropNative) then
                if not layers.nativeBackdrop then
                    layers.nativeBackdrop = layers.borderFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
                end
                layers.nativeBackdrop:ClearAllPoints()
                layers.nativeBackdrop:SetPoint("TOPLEFT", layers.nativeBorder, "TOPLEFT", 10, -12)
                layers.nativeBackdrop:SetPoint("BOTTOMRIGHT", layers.nativeBorder, "BOTTOMRIGHT", -10, 12)
                layers.nativeBackdrop:SetAtlas(atlases.frameBackdropNative)
                layers.nativeBackdrop:Show()
                if layers.innerBg then layers.innerBg:Hide() end
            else
                if layers.nativeBackdrop then layers.nativeBackdrop:Hide() end
                if layers.innerBg then
                    layers.innerBg:ClearAllPoints()
                    layers.innerBg:SetPoint("TOPLEFT", layers.nativeBorder, "TOPLEFT", 10, -12)
                    layers.innerBg:SetPoint("BOTTOMRIGHT", layers.nativeBorder, "BOTTOMRIGHT", -10, 12)
                    layers.innerBg:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], pal.backdropColor[4] or 0.94)
                    layers.innerBg:Show()
                end
            end
        else
            layers.nativeBorder:Hide()
            if layers.nativeBackdrop then layers.nativeBackdrop:Hide() end
            local mp = layers.metalPieces
            if style == "metal_pieces" and atlases.metalCornerTL and sfui.theme.HasAtlas(atlases.metalCornerTL) then
                mp.tl:ClearAllPoints()
                mp.tl:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", -8, 16)
                mp.tr:ClearAllPoints()
                mp.tr:SetPoint("TOPRIGHT", layers.borderFrame, "TOPRIGHT", 2, 16)
                mp.bl:ClearAllPoints()
                mp.bl:SetPoint("BOTTOMLEFT", layers.borderFrame, "BOTTOMLEFT", -8, -8)
                mp.br:ClearAllPoints()
                mp.br:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", 2, -8)

                layers.cornerTL:ClearAllPoints()
                layers.cornerTL:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", -2, 2)
                layers.cornerTR:ClearAllPoints()
                layers.cornerTR:SetPoint("TOPRIGHT", layers.borderFrame, "TOPRIGHT", 2, 2)
                layers.cornerBL:ClearAllPoints()
                layers.cornerBL:SetPoint("BOTTOMLEFT", layers.borderFrame, "BOTTOMLEFT", -2, -2)
                layers.cornerBR:ClearAllPoints()
                layers.cornerBR:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", 2, -2)

                mp.tl:SetAtlas(atlases.metalCornerTL, true)
                mp.tr:SetAtlas(atlases.metalCornerTR, true)
                mp.bl:SetAtlas(atlases.metalCornerBL, true)
                mp.br:SetAtlas(atlases.metalCornerBR, true)

                mp.top:SetAtlas(atlases.metalEdgeTop)
                mp.top:SetTexCoord(0, 1, 0, 1)
                mp.top:SetHorizTile(true)
                mp.top:SetVertexColor(1, 1, 1, 1)

                -- Bottom edge piece: bronze-tinted to avoid grey metal bottom
                local botColor = pal.metalBottomColor or pal.highlightColor or { 0.82, 0.65, 0.32, 1.0 }
                if atlases.metalEdgeBottom and atlases.metalEdgeBottom == atlases.metalEdgeTop then
                    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlases.metalEdgeTop)
                    if info and (info.file or info.filename) then
                        mp.bot:SetTexture(info.file or info.filename)
                        mp.bot:SetTexCoord(info.leftTexCoord, info.rightTexCoord, info.bottomTexCoord, info.topTexCoord)
                        mp.bot:SetHorizTile(info.tilesHorizontally)
                    else
                        mp.bot:SetAtlas(atlases.metalEdgeTop)
                        mp.bot:SetTexCoord(0, 1, 1, 0)
                    end
                    mp.bot:SetVertexColor(botColor[1], botColor[2], botColor[3], botColor[4] or 1)
                elseif atlases.metalEdgeBottom then
                    mp.bot:SetAtlas(atlases.metalEdgeBottom)
                    mp.bot:SetTexCoord(0, 1, 0, 1)
                    mp.bot:SetHorizTile(true)
                    mp.bot:SetVertexColor(botColor[1], botColor[2], botColor[3], botColor[4] or 1)
                end

                mp.left:SetAtlas(atlases.metalEdgeLeft)
                mp.left:SetTexCoord(0, 1, 0, 1)
                mp.left:SetVertTile(true)
                mp.left:SetVertexColor(1, 1, 1, 1)

                mp.right:SetAtlas(atlases.metalEdgeRight)
                mp.right:SetTexCoord(0, 1, 0, 1)
                mp.right:SetVertTile(true)
                mp.right:SetVertexColor(1, 1, 1, 1)

                for _, p in pairs(mp) do p:Show() end
                hasBorder = true
            elseif style == "metal_pieces" and atlases.simpleCornerTL and sfui.theme.HasAtlas(atlases.simpleCornerTL) then
                mp.tl:ClearAllPoints()
                mp.tl:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", -3, 3)
                mp.tr:ClearAllPoints()
                mp.tr:SetPoint("TOPRIGHT", layers.borderFrame, "TOPRIGHT", 3, 3)
                mp.bl:ClearAllPoints()
                mp.bl:SetPoint("BOTTOMLEFT", layers.borderFrame, "BOTTOMLEFT", -3, -3)
                mp.br:ClearAllPoints()
                mp.br:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", 3, -3)

                mp.tl:SetAtlas(atlases.simpleCornerTL, true)
                mp.tr:SetAtlas(atlases.simpleCornerTL, true)
                mp.tr:SetTexCoord(1, 0, 0, 1)
                mp.bl:SetAtlas(atlases.simpleCornerTL, true)
                mp.bl:SetTexCoord(0, 1, 1, 0)
                mp.br:SetAtlas(atlases.simpleCornerTL, true)
                mp.br:SetTexCoord(1, 0, 1, 0)
                mp.top:SetAtlas(atlases.simpleEdgeTop)
                mp.bot:SetAtlas(atlases.simpleEdgeTop)
                mp.bot:SetTexCoord(0, 1, 1, 0)
                mp.left:SetAtlas(atlases.simpleEdgeLeft)
                mp.right:SetAtlas(atlases.simpleEdgeLeft)
                mp.right:SetTexCoord(1, 0, 0, 1)
                for _, p in pairs(mp) do p:Show() end
                hasBorder = true
            else
                if mp then
                    for _, p in pairs(mp) do
                        p:SetTexture(nil)
                        p:ClearAllPoints()
                        p:Hide()
                    end
                end
                if useBronze then
                    layers.cornerTL:ClearAllPoints()
                    layers.cornerTL:SetPoint("TOPLEFT", layers.borderFrame, "TOPLEFT", -3, 3)
                    layers.cornerTR:ClearAllPoints()
                    layers.cornerTR:SetPoint("TOPRIGHT", layers.borderFrame, "TOPRIGHT", 3, 3)
                    layers.cornerBL:ClearAllPoints()
                    layers.cornerBL:SetPoint("BOTTOMLEFT", layers.borderFrame, "BOTTOMLEFT", -3, -3)
                    layers.cornerBR:ClearAllPoints()
                    layers.cornerBR:SetPoint("BOTTOMRIGHT", layers.borderFrame, "BOTTOMRIGHT", 3, -3)
                    hasBorder = true
                end
            end
        end

        local atlasTL = sfui.theme.GetCornerBracketAtlas("TL", theme)
        local atlasTR = sfui.theme.GetCornerBracketAtlas("TR", theme)
        local atlasBL = sfui.theme.GetCornerBracketAtlas("BL", theme)
        local atlasBR = sfui.theme.GetCornerBracketAtlas("BR", theme)
        if showBrackets and atlasTL and atlasTR and atlasBL and atlasBR then
            layers.cornerTL:SetAtlas(atlasTL, true)
            layers.cornerTR:SetAtlas(atlasTR, true)
            layers.cornerBL:SetAtlas(atlasBL, true)
            layers.cornerBR:SetAtlas(atlasBR, true)
            layers.cornerTL:Show()
            layers.cornerTR:Show()
            layers.cornerBL:Show()
            layers.cornerBR:Show()
        else
            layers.cornerTL:Hide()
            layers.cornerTR:Hide()
            layers.cornerBL:Hide()
            layers.cornerBR:Hide()
        end

        if hasBorder then
            if not layers.nativeBackdrop or not layers.nativeBackdrop:IsShown() then
                if layers.innerBg then
                    layers.innerBg:ClearAllPoints()
                    if layers.nativeBorder and layers.nativeBorder:IsShown() then
                        layers.innerBg:SetPoint("TOPLEFT", layers.nativeBorder, "TOPLEFT", 10, -12)
                        layers.innerBg:SetPoint("BOTTOMRIGHT", layers.nativeBorder, "BOTTOMRIGHT", -10, 12)
                    else
                        layers.innerBg:SetAllPoints(layers.borderFrame)
                    end
                    layers.innerBg:SetColorTexture(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], pal.backdropColor[4] or 0.94)
                    layers.innerBg:Show()
                end
            end
            if frame.SetBackdrop then
                frame:SetBackdrop(nil)
            end
        else
            if layers and layers.innerBg then
                layers.innerBg:Hide()
            end
            if frame.SetBackdrop then
                frame:SetBackdrop({
                    bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                    edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                    tile     = true,
                    tileSize = 32,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                frame:SetBackdropColor(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], pal.backdropColor[4] or 0.94)
                if frame.SetBackdropBorderColor then
                    frame:SetBackdropBorderColor(0.40, 0.30, 0.15, 0.9)
                end
            end
        end

        frame.isCamelotThemed = true
    else
        -- Flat Border / Minimalist Window Styling
        if frame.sfuiThemeLayers then
            if frame.sfuiThemeLayers.borderFrame then
                frame.sfuiThemeLayers.borderFrame:Hide()
            end
            if frame.sfuiThemeLayers.nativeBorder then
                frame.sfuiThemeLayers.nativeBorder:Hide()
            end
            if frame.sfuiThemeLayers.nativeBackdrop then
                frame.sfuiThemeLayers.nativeBackdrop:Hide()
            end
            if frame.sfuiThemeLayers.innerBg then
                frame.sfuiThemeLayers.innerBg:Hide()
            end
            if frame.sfuiThemeLayers.metalPieces then
                for _, p in pairs(frame.sfuiThemeLayers.metalPieces) do
                    p:SetTexture(nil)
                    p:ClearAllPoints()
                    p:Hide()
                end
            end
            if frame.sfuiThemeLayers.cornerTL then
                frame.sfuiThemeLayers.cornerTL:Hide()
                frame.sfuiThemeLayers.cornerTR:Hide()
                frame.sfuiThemeLayers.cornerBL:Hide()
                frame.sfuiThemeLayers.cornerBR:Hide()
            end
        end

        if frame.SetBackdrop then
            local edgeCol = (theme.window and theme.window.borderColor) or pal.borderColor or { 0, 0, 0, 1 }
            frame:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = (theme.window and theme.window.borderSize) or 1,
                tile     = true,
                tileSize = 32,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            frame:SetBackdropColor(unpack(pal.backdropColor))
            if frame.SetBackdropBorderColor then
                frame:SetBackdropBorderColor(edgeCol[1], edgeCol[2], edgeCol[3], edgeCol[4] or 1)
            end
        end

        frame.isCamelotThemed = false
    end

    sfui.theme.ElevateWindowContents(frame)
end

-- 2. Container / Card Styling (Panels, Sections, Insets)
function sfui.theme.ApplyContainerStyle(containerPanel)
    if not containerPanel or not containerPanel.SetBackdrop then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()

    if theme.ApplyContainer then
        theme.ApplyContainer(containerPanel, theme)
        return
    end

    local isCamelot = (activeID == "camelot")
    if isCamelot then
        if containerPanel.nineSliceInset then
            if NineSliceUtil and NineSliceUtil.HideLayout then
                NineSliceUtil.HideLayout(containerPanel.nineSliceInset)
            end
            containerPanel.nineSliceInset:Hide()
        end
        containerPanel:SetBackdrop({
            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            tile     = true,
            tileSize = 32,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        containerPanel:SetBackdropColor(pal.containerColor[1], pal.containerColor[2], pal.containerColor[3], 0.88)
        if containerPanel.SetBackdropBorderColor then
            containerPanel:SetBackdropBorderColor(0, 0, 0, 0)
        end
    else
        if containerPanel.nineSliceInset then
            if NineSliceUtil and NineSliceUtil.HideLayout then
                NineSliceUtil.HideLayout(containerPanel.nineSliceInset)
            end
            containerPanel.nineSliceInset:Hide()
        end
        containerPanel:SetBackdrop({
            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            tile     = true,
            tileSize = 32,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        containerPanel:SetBackdropColor(unpack(pal.containerColor))
        if containerPanel.SetBackdropBorderColor then
            containerPanel:SetBackdropBorderColor(unpack(pal.borderColor))
        end
    end
end

function sfui.theme.ApplyCardStyle(card, depth)
    if not card then return end
    sfui.theme.ApplyContainerStyle(card)
    registered_cards[card] = depth or 1
end

-- 3. Header Styling (Window Banners / Section Dividers)
function sfui.theme.ApplyQuestHeaderStyle(header)
    if not header then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()

    if theme.ApplyHeader then
        theme.ApplyHeader(header, theme)
        return
    end

    local atlases = theme.atlases or {}
    local isCamelot = (activeID == "camelot")
    local canUseBanner = isCamelot and atlases.headerBanner and sfui.theme.HasAtlas(atlases.headerBanner)

    if canUseBanner then
        if not header.bgBanner then
            header.bgBanner = header:CreateTexture(nil, "BACKGROUND", nil, 1)
            header.bgBanner:SetAllPoints(header)
        end
        header.bgBanner:SetAtlas(atlases.headerBanner)
        header.bgBanner:Show()

        if header.SetBackdrop then header:SetBackdrop(nil) end
        if header.accent then header.accent:Hide() end

        header:SetHeight(24)
        if header.title then
            header.title:ClearAllPoints()
            header.title:SetPoint("CENTER", header, "CENTER", 0, 1)
            header.title:SetJustifyH("CENTER")
            header.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
        end
        if header.count then
            header.count:ClearAllPoints()
            header.count:SetPoint("RIGHT", header, "RIGHT", -28, 1)
            header.count:SetJustifyH("RIGHT")
            header.count:SetTextColor(pal.dimTextColor[1], pal.dimTextColor[2], pal.dimTextColor[3], 1)
        end
        header.isCamelotHeader = true
    else
        if header.bgBanner then header.bgBanner:Hide() end
        local mult = (sfui.pixelScale or 1)
        if header.SetBackdrop then
            header:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
            })
            header:SetBackdropColor(0, 0, 0, 0.50)
            header:SetBackdropBorderColor(0, 0, 0, 0.50)
        end
        if header.accent then
            header.accent:Show()
            local col = header.defColor or pal.accentColor
            header.accent:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
        end

        header:SetHeight(20)
        if header.title then
            header.title:ClearAllPoints()
            header.title:SetPoint("LEFT", header, "LEFT", 8, 0)
            if header.count then
                header.title:SetPoint("RIGHT", header.count, "LEFT", -4, 0)
            end
            header.title:SetJustifyH("LEFT")
            local col = header.defColor or pal.headerColor
            header.title:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, 1)
        end
        if header.count then
            header.count:ClearAllPoints()
            header.count:SetPoint("RIGHT", header, "RIGHT", -8, 0)
            header.count:SetJustifyH("RIGHT")
            local col = header.defColor or pal.dimTextColor
            header.count:SetTextColor((col[1] or 1) * 0.65, (col[2] or 1) * 0.65, (col[3] or 1) * 0.65, 1)
        end
        header.isCamelotHeader = false
    end
end

function sfui.theme.ApplyHeaderStyle(header, titleText)
    if not header then return end
    registered_headers[header] = titleText or true

    if not header.accent then
        local accent = header:CreateTexture(nil, "OVERLAY")
        accent:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
        accent:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        accent:SetWidth(3)
        header.accent = accent
    end

    if not header.title then
        local title = header:CreateFontString(nil, "OVERLAY", sfui.config and sfui.config.font or "GameFontHighlight")
        local fontPath = (sfui.config and sfui.config.fontFile) or "Fonts\\FRIZQT__.TTF"
        title:SetFont(fontPath, 12, "")
        title:SetPoint("LEFT", header, "LEFT", 8, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        header.title = title
    end

    sfui.theme.ApplyQuestHeaderStyle(header)
    if titleText and header.title then
        header.title:SetText(titleText)
    end
end

-- 4. Button Styling


function sfui.theme.ApplyButtonStyle(btn, isStyled)
    if not btn or btn.isCloseButton or btn.isSubmenuButton or btn.isDropdownButton or btn.isDropdownOption then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()
    local mult = sfui.pixelScale or 1

    if theme.ApplyButton then
        theme.ApplyButton(btn, isStyled, theme)
        return
    end

    btn.SetSelected = sfui.theme.SetButtonSelected

    local isCamelot = (activeID == "camelot")
    local useAH = sfui.theme.IsAuctionHouseButtonActive()

    if useAH then
        SetupAuctionHouseTextures(btn, btn.isSelected)
        local fs = btn:GetFontString() or btn.text or btn.fs
        if fs then
            if btn.isSelected or btn.isSelectedTab then
                fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
            elseif not btn:IsEnabled() then
                fs:SetTextColor(0.55, 0.50, 0.45, 1.0)
            elseif btn:IsMouseOver() then
                fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
            else
                local textColor = pal.accentColor or pal.tabNormal or { 0.95, 0.85, 0.55, 1.0 }
                fs:SetTextColor(textColor[1], textColor[2], textColor[3], textColor[4] or 1.0)
            end
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.9)
        end
        btn:SetPushedTextOffset(1, -1)
    else
        if btn._sfuiAHBg then btn._sfuiAHBg:Hide() end
        if btn._sfuiAHHighlight then btn._sfuiAHHighlight:Hide() end
        if btn._sfuiAHSelected then btn._sfuiAHSelected:Hide() end
        if btn._sfuiCamelotBg then btn._sfuiCamelotBg:Hide() end

        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
        end
        if isCamelot then
            if btn.SetBackdropColor then
                btn:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
            end
            if btn.SetBackdropBorderColor then
                btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
            end
            local fs = btn:GetFontString() or btn.text or btn.fs
            if fs then
                fs:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3], 1.0)
                fs:SetShadowOffset(0, 0)
            end
        else
            if btn.SetBackdropColor then
                btn:SetBackdropColor(isStyled and 0.2 or 0, isStyled and 0.2 or 0, isStyled and 0.2 or 0, 1.0)
            end
            if btn.SetBackdropBorderColor then
                btn:SetBackdropBorderColor(0, 0, 0, 1.0)
            end
            local fs = btn:GetFontString() or btn.text or btn.fs
            if fs then
                fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                fs:SetShadowOffset(0, 0)
            end
        end
        btn:SetPushedTextOffset(0, 0)
    end

    if not btn.sfuiThemeHooksInstalled then
        btn.sfuiThemeHooksInstalled = true
        btn:HookScript("OnEnter", function(self)
            if self.isCloseButton or self.isSubmenuButton or self.isDropdownButton or self.isDropdownOption then return end
            if sfui.theme.IsAuctionHouseButtonActive() then
                if self:IsEnabled() then
                    if self._sfuiAHHighlight then self._sfuiAHHighlight:Show() end
                    local sfs = self:GetFontString() or self.text or self.fs
                    if sfs then sfs:SetTextColor(1.0, 1.0, 1.0, 1.0) end
                end
            else
                local p = sfui.theme.GetPalette()
                local hl = p.highlightColor or { 0.4, 0, 1, 1 }
                self:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0)
                local sfs = self:GetFontString() or self.text or self.fs
                if sfs and (sfui.theme.GetActiveThemeID() == "camelot") then
                    sfs:SetTextColor(1.0, 0.95, 0.70, 1.0)
                end
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.isCloseButton or self.isSubmenuButton or self.isDropdownButton or self.isDropdownOption or self.customOnLeave then return end
            if self.menu and self.menu:IsShown() then return end
            if sfui.theme.IsAuctionHouseButtonActive() then
                if self._sfuiAHHighlight then self._sfuiAHHighlight:Hide() end
                local sfs = self:GetFontString() or self.text or self.fs
                if sfs then
                    if not self:IsEnabled() then
                        sfs:SetTextColor(0.55, 0.50, 0.45, 1.0)
                    elseif self.isSelected or self.isSelectedTab then
                        sfs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                    else
                        local p = sfui.theme.GetPalette()
                        local col = p.accentColor or p.tabNormal or { 0.95, 0.85, 0.55, 1.0 }
                        sfs:SetTextColor(col[1], col[2], col[3], 1.0)
                    end
                end
            else
                if not (self.isSelected or self.lockColor) then
                    if sfui.theme.GetActiveThemeID() == "camelot" then
                        self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
                        local sfs = self:GetFontString() or self.text or self.fs
                        if sfs then
                            local p = sfui.theme.GetPalette()
                            sfs:SetTextColor(p.tabNormal[1], p.tabNormal[2], p.tabNormal[3], 1.0)
                        end
                    else
                        self:SetBackdropBorderColor(0, 0, 0, 1.0)
                        local sfs = self:GetFontString() or self.text or self.fs
                        if sfs then sfs:SetTextColor(1.0, 1.0, 1.0, 1.0) end
                    end
                end
            end
        end)
        btn:HookScript("OnMouseDown", function(self)
            self._sfuiMouseDown = true
            if sfui.theme.IsAuctionHouseButtonActive() and self:IsEnabled() then
                if self._sfuiAHBg then self._sfuiAHBg:SetVertexColor(0.80, 0.80, 0.80, 1.0) end
            end
        end)
        btn:HookScript("OnMouseUp", function(self)
            self._sfuiMouseDown = false
            if sfui.theme.IsAuctionHouseButtonActive() and self:IsEnabled() then
                if self._sfuiAHBg then self._sfuiAHBg:SetVertexColor(1.0, 1.0, 1.0, 1.0) end
            end
        end)
        if btn.HasScript and btn:HasScript("OnEnable") then
            btn:HookScript("OnEnable", function(self)
                if sfui.theme.IsAuctionHouseButtonActive() then
                    if self._sfuiAHBg then
                        self._sfuiAHBg:SetVertexColor(1.0, 1.0, 1.0, 1.0)
                        self._sfuiAHBg:SetDesaturated(false)
                    end
                    local sfs = self:GetFontString() or self.text or self.fs
                    if sfs then
                        local p = sfui.theme.GetPalette()
                        local col = self:IsMouseOver() and { 1.0, 1.0, 1.0, 1.0 } or (p.accentColor or p.tabNormal or { 0.95, 0.85, 0.55, 1.0 })
                        sfs:SetTextColor(col[1], col[2], col[3], 1.0)
                    end
                end
            end)
        end
        if btn.HasScript and btn:HasScript("OnDisable") then
            btn:HookScript("OnDisable", function(self)
                if sfui.theme.IsAuctionHouseButtonActive() then
                    if self._sfuiAHHighlight then self._sfuiAHHighlight:Hide() end
                    if self._sfuiAHBg then
                        self._sfuiAHBg:SetVertexColor(0.45, 0.45, 0.45, 0.70)
                        self._sfuiAHBg:SetDesaturated(true)
                    end
                    local sfs = self:GetFontString() or self.text or self.fs
                    if sfs then sfs:SetTextColor(0.55, 0.50, 0.45, 1.0) end
                end
            end)
        end
    end
end

function sfui.theme.RegisterButton(btn, isStyled)
    if not btn or btn.isCloseButton or btn.isSubmenuButton or btn.isDropdownButton or btn.isDropdownOption then return end
    btn.isStyledButton = isStyled or false
    registered_buttons[btn] = isStyled or false
end

function sfui.theme.RegisterDropdown(btn)
    if not btn then return end
    registered_dropdowns[btn] = true
end

function sfui.theme.ApplyDropdownStyle(btn)
    if not btn then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()
    local mult = sfui.pixelScale or 1
    local isCamelot = (activeID == "camelot")
    local useAH = sfui.theme.IsAuctionHouseButtonActive()

    btn.SetSelected = sfui.theme.SetButtonSelected

    if useAH then
        local isMenuOpen = (btn.menu and btn.menu:IsShown())
        SetupAuctionHouseTextures(btn, isMenuOpen)
        if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 0) end
        if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 0) end
        local fs = btn:GetFontString() or btn.text or btn.fs
        if fs then
            local textColor = pal.accentColor or pal.tabNormal or { 0.95, 0.85, 0.55, 1.0 }
            fs:SetTextColor(textColor[1], textColor[2], textColor[3], 1.0)
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.9)
        end
        btn:SetPushedTextOffset(1, -1)

        if btn.menu then
            btn.menu:SetBackdropColor(0.08, 0.07, 0.06, 0.98)
            btn.menu:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.90)
        end
    else
        if btn._sfuiAHBg then btn._sfuiAHBg:Hide() end
        if btn._sfuiAHHighlight then btn._sfuiAHHighlight:Hide() end
        if btn._sfuiAHSelected then btn._sfuiAHSelected:Hide() end
        if btn._sfuiCamelotBg then btn._sfuiCamelotBg:Hide() end

        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
        end
        if isCamelot then
            if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.10, 0.08, 0.95) end
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85) end
            local fs = btn:GetFontString() or btn.text or btn.fs
            if fs then
                fs:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3], 1.0)
                fs:SetShadowOffset(0, 0)
            end
            if btn.menu then
                btn.menu:SetBackdropColor(0.08, 0.07, 0.06, 0.98)
                btn.menu:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.90)
            end
        else
            if btn.SetBackdropColor then btn:SetBackdropColor(0, 0, 0, 1.0) end
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0, 0, 0, 1.0) end
            local fs = btn:GetFontString() or btn.text or btn.fs
            if fs then
                fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                fs:SetShadowOffset(0, 0)
            end
            if btn.menu then
                btn.menu:SetBackdropColor(0.06, 0.06, 0.06, 0.98)
                btn.menu:SetBackdropBorderColor(0.25, 0.25, 0.25, 1.0)
            end
        end
        btn:SetPushedTextOffset(0, 0)
    end
end

-- 5. Close Button Styling
function sfui.theme.ApplyCloseButtonStyle(btn)
    if not btn then return end
    btn.isCloseButton = true
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local atlases = theme.atlases or {}

    local normalAtlas = (atlases.closeNormal and sfui.theme.HasAtlas(atlases.closeNormal) and atlases.closeNormal)
        or (atlases.closeMini and sfui.theme.HasAtlas(atlases.closeMini) and atlases.closeMini)
    local canUseAtlas = (activeID == "camelot") and (normalAtlas ~= nil)

    if canUseAtlas then
        local pushedAtlas = (atlases.closePressed and sfui.theme.HasAtlas(atlases.closePressed) and atlases.closePressed)
            or (atlases.closeMiniPress and sfui.theme.HasAtlas(atlases.closeMiniPress) and atlases.closeMiniPress)
        local disabledAtlas = (atlases.closeDisabled and sfui.theme.HasAtlas(atlases.closeDisabled) and atlases.closeDisabled)
            or (atlases.closeMiniDis and sfui.theme.HasAtlas(atlases.closeMiniDis) and atlases.closeMiniDis)
        local hlAtlas = atlases.closeHighlight and sfui.theme.HasAtlas(atlases.closeHighlight) and atlases.closeHighlight

        if btn.SetNormalAtlas then btn:SetNormalAtlas(normalAtlas) end
        if pushedAtlas and btn.SetPushedAtlas then btn:SetPushedAtlas(pushedAtlas) end
        if disabledAtlas and btn.SetDisabledAtlas then btn:SetDisabledAtlas(disabledAtlas) end
        if hlAtlas and btn.SetHighlightAtlas then btn:SetHighlightAtlas(hlAtlas, "ADD") end

        if btn.SetBackdrop then btn:SetBackdrop(nil) end
        local fs = btn:GetFontString()
        if fs then
            fs:SetText("")
            fs:Hide()
        end
        btn.isThemedClose = true
    else
        local nt = btn.GetNormalTexture and btn:GetNormalTexture()
        if nt then nt:SetTexture(nil) end
        local pt = btn.GetPushedTexture and btn:GetPushedTexture()
        if pt then pt:SetTexture(nil) end
        local dt = btn.GetDisabledTexture and btn:GetDisabledTexture()
        if dt then dt:SetTexture(nil) end
        local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if ht then ht:SetTexture(nil) end

        local mult = sfui.pixelScale or 1
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            if activeID == "camelot" then
                btn:SetBackdropColor(0.20, 0.08, 0.08, 0.95)
                btn:SetBackdropBorderColor(0.65, 0.50, 0.25, 1)
            else
                btn:SetBackdropColor(0, 0, 0, 1)
                btn:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end

        local fs = btn:GetFontString()
        if fs then
            fs:Show()
            fs:SetText("X")
            if activeID == "camelot" then
                fs:SetTextColor(1.0, 0.85, 0.55, 1)
            else
                fs:SetTextColor(1, 1, 1, 1)
            end
        end
        btn.isThemedClose = false
    end
end

function sfui.theme.RegisterCloseButton(btn)
    if not btn then return end
    btn.isCloseButton = true
    registered_close_buttons[btn] = true
end

-- 6. Navigation / Spec / Mode Tab Styling
function sfui.theme.ApplyTabStyle(btn, isSelected)
    if not btn then return end
    btn.isSelectedTab = (isSelected == true)
    registered_tabs[btn] = btn.isSelectedTab
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()
    local isCamelot = (activeID == "camelot")
    local useAH = sfui.theme.IsAuctionHouseButtonActive()

    btn.SetSelected = sfui.theme.SetButtonSelected

    local fs = btn:GetFontString() or btn.fs or btn.text

    if useAH then
        SetupAuctionHouseTextures(btn, btn.isSelectedTab)
        if btn.isSelectedTab then
            if fs then
                fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                fs:SetShadowOffset(1, -1)
                fs:SetShadowColor(0, 0, 0, 0.9)
            end
        else
            if btn:IsMouseOver() then
                if btn._sfuiAHHighlight then btn._sfuiAHHighlight:Show() end
                if fs then
                    fs:SetTextColor(1.0, 1.0, 1.0, 1.0)
                    fs:SetShadowOffset(1, -1)
                    fs:SetShadowColor(0, 0, 0, 0.9)
                end
            else
                if btn._sfuiAHHighlight then btn._sfuiAHHighlight:Hide() end
                if fs then
                    local normColor = pal.tabNormal or { 0.78, 0.70, 0.55, 1.0 }
                    fs:SetTextColor(normColor[1], normColor[2], normColor[3], 1.0)
                    fs:SetShadowOffset(1, -1)
                    fs:SetShadowColor(0, 0, 0, 0.9)
                end
            end
        end
    else
        if btn._sfuiAHBg then btn._sfuiAHBg:Hide() end
        if btn._sfuiAHHighlight then btn._sfuiAHHighlight:Hide() end
        if btn._sfuiAHSelected then btn._sfuiAHSelected:Hide() end
        if btn._sfuiCamelotBg then btn._sfuiCamelotBg:Hide() end

        local mult = sfui.pixelScale or 1
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
        end
        if isCamelot then
            if btn.isSelectedTab then
                if btn.SetBackdropColor then btn:SetBackdropColor(0.18, 0.14, 0.10, 0.98) end
                if btn.SetBackdropBorderColor then
                    local hl = pal.highlightColor or { 0.82, 0.65, 0.32, 1.0 }
                    btn:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0)
                end
                if fs then
                    local selColor = pal.tabSelected or pal.accentColor or { 0.95, 0.85, 0.55, 1.0 }
                    fs:SetTextColor(selColor[1], selColor[2], selColor[3], 1.0)
                    fs:SetShadowOffset(0, 0)
                end
            else
                if btn.SetBackdropColor then btn:SetBackdropColor(0.10, 0.08, 0.06, 0.90) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.22, 0.18, 0.12, 0.85) end
                if fs then
                    local normColor = pal.tabNormal or { 0.78, 0.70, 0.55, 1.0 }
                    fs:SetTextColor(normColor[1], normColor[2], normColor[3], 1.0)
                    fs:SetShadowOffset(0, 0)
                end
            end
        else
            if btn.isSelectedTab then
                if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 0.95) end
                if btn.SetBackdropBorderColor then
                    local hl = pal.highlightColor or { 0.4, 0, 1, 1 }
                    btn:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0)
                end
                if fs then
                    local selColor = pal.tabSelected or { 1, 1, 1, 1 }
                    fs:SetTextColor(selColor[1], selColor[2], selColor[3], 1.0)
                    fs:SetShadowOffset(0, 0)
                end
            else
                if btn.SetBackdropColor then btn:SetBackdropColor(0.08, 0.08, 0.10, 0.9) end
                if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.18, 0.18, 0.20, 1.0) end
                if fs then
                    local normColor = pal.tabNormal or { 0.6, 0.6, 0.6, 1.0 }
                    fs:SetTextColor(normColor[1], normColor[2], normColor[3], 1.0)
                    fs:SetShadowOffset(0, 0)
                end
            end
        end
    end

    if btn.indicator then
        btn.indicator:SetColorTexture(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1.0)
        if btn.isSelectedTab then
            btn.indicator:Show()
        else
            btn.indicator:Hide()
        end
    end

    if not btn.sfuiTabHooksInstalled then
        btn.sfuiTabHooksInstalled = true
        btn:HookScript("OnEnter", function(self)
            if self.isSelectedTab then return end
            if sfui.theme.IsAuctionHouseButtonActive() then
                if self._sfuiAHHighlight then self._sfuiAHHighlight:Show() end
                local sfs = self:GetFontString() or self.fs or self.text
                if sfs then sfs:SetTextColor(1.0, 1.0, 1.0, 1.0) end
            else
                local p = sfui.theme.GetPalette()
                local hl = p.highlightColor or { 0.4, 0, 1, 1 }
                if self.SetBackdropBorderColor then
                    self:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1.0)
                end
                if sfui.theme.IsCamelotActive() then
                    local sfs = self:GetFontString() or self.fs or self.text
                    if sfs then sfs:SetTextColor(1.0, 0.95, 0.70, 1.0) end
                end
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.isSelectedTab then return end
            if sfui.theme.IsAuctionHouseButtonActive() then
                if self._sfuiAHHighlight then self._sfuiAHHighlight:Hide() end
                local sfs = self:GetFontString() or self.fs or self.text
                if sfs then
                    local p = sfui.theme.GetPalette()
                    local col = p.tabNormal or { 0.78, 0.70, 0.55, 1.0 }
                    sfs:SetTextColor(col[1], col[2], col[3], 1.0)
                end
            else
                local p = sfui.theme.GetPalette()
                if sfui.theme.IsCamelotActive() then
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.22, 0.18, 0.12, 0.85)
                    end
                    local sfs = self:GetFontString() or self.fs or self.text
                    if sfs then
                        local col = p.tabNormal or { 0.78, 0.70, 0.55, 1.0 }
                        sfs:SetTextColor(col[1], col[2], col[3], 1.0)
                    end
                else
                    if self.SetBackdropBorderColor then
                        self:SetBackdropBorderColor(0.18, 0.18, 0.20, 1.0)
                    end
                    local sfs = self:GetFontString() or self.fs or self.text
                    if sfs then
                        local col = p.tabNormal or { 0.6, 0.6, 0.6, 1.0 }
                        sfs:SetTextColor(col[1], col[2], col[3], 1.0)
                    end
                end
            end
        end)
        btn:HookScript("OnMouseDown", function(self)
            if sfui.theme.IsAuctionHouseButtonActive() and self:IsEnabled() then
                if self._sfuiAHBg then self._sfuiAHBg:SetVertexColor(0.80, 0.80, 0.80, 1.0) end
            end
        end)
        btn:HookScript("OnMouseUp", function(self)
            if sfui.theme.IsAuctionHouseButtonActive() and self:IsEnabled() then
                if self._sfuiAHBg then self._sfuiAHBg:SetVertexColor(1.0, 1.0, 1.0, 1.0) end
            end
        end)
    end
end

-- 7. Input / EditBox Styling
function sfui.theme.ApplyInputStyle(editBox)
    if not editBox or not editBox.SetBackdrop then return end
    registered_inputs[editBox] = true
    local pal = sfui.theme.GetPalette()
    local isCamelot = sfui.theme.IsCamelotActive()

    editBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 }
    })

    if isCamelot then
        editBox:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
        editBox:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.8)
    else
        editBox:SetBackdropColor(0.05, 0.05, 0.05, 0.90)
        editBox:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
    end

    if not editBox.sfuiInputHooksInstalled then
        editBox.sfuiInputHooksInstalled = true
        editBox:HookScript("OnEditFocusGained", function(self)
            local p = sfui.theme.GetPalette()
            self:SetBackdropBorderColor(p.accentColor[1], p.accentColor[2], p.accentColor[3], 1)
        end)
        editBox:HookScript("OnEditFocusLost", function(self)
            local p = sfui.theme.GetPalette()
            if sfui.theme.IsCamelotActive() then
                self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.8)
            else
                self:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
            end
        end)
    end
end

-- 7.5 ScrollBar Styling (Bronze MinimalScrollBar for Camelot, Flat Bar for Modern)
local function SetButtonAtlasSafe(btn, normalAtlas, pushedAtlas, hlAtlas, disAtlas)
    if not btn then return end
    pcall(function()
        if btn.SetNormalAtlas then
            btn:SetNormalAtlas(normalAtlas)
            btn:SetPushedAtlas(pushedAtlas or normalAtlas)
            btn:SetHighlightAtlas(hlAtlas or normalAtlas)
            btn:SetDisabledAtlas(disAtlas or normalAtlas)
        else
            local nt = btn:GetNormalTexture()
            if nt and nt.SetAtlas then nt:SetAtlas(normalAtlas) end
            local pt = btn:GetPushedTexture()
            if pt and pt.SetAtlas then pt:SetAtlas(pushedAtlas or normalAtlas) end
            local ht = btn:GetHighlightTexture()
            if ht and ht.SetAtlas then ht:SetAtlas(hlAtlas or normalAtlas) end
            local dt = btn:GetDisabledTexture()
            if dt and dt.SetAtlas then dt:SetAtlas(disAtlas or normalAtlas) end
        end
    end)
end

function sfui.theme.ApplyScrollBarStyle(scrollBar)
    if not scrollBar then return end
    registered_scrollbars[scrollBar] = true

    local parent = scrollBar:GetParent()
    if parent then
        parent.scrollBarHideable = 1
        if not parent._sfuiScrollHooked then
            parent._sfuiScrollHooked = true
            parent:HookScript("OnScrollRangeChanged", function()
                if scrollBar.UpdateVisibility then
                    scrollBar:UpdateVisibility()
                end
            end)
            parent:HookScript("OnSizeChanged", function()
                if scrollBar.UpdateVisibility then
                    scrollBar:UpdateVisibility()
                end
            end)
            parent:HookScript("OnShow", function()
                if scrollBar.UpdateVisibility then
                    scrollBar:UpdateVisibility()
                end
            end)
        end
    end

    local name = scrollBar.GetName and scrollBar:GetName()
    local upBtn = (name and _G[name .. "ScrollUpButton"]) or scrollBar.ScrollUpButton
    local downBtn = (name and _G[name .. "ScrollDownButton"]) or scrollBar.ScrollDownButton
    scrollBar.upBtn = upBtn
    scrollBar.downBtn = downBtn

    -- Clean up default background textures from UIPanelScrollBarTemplate
    if scrollBar.GetNumRegions then
        for i = 1, scrollBar:GetNumRegions() do
            local region = select(i, scrollBar:GetRegions())
            if region and region:IsObjectType("Texture") and region ~= scrollBar:GetThumbTexture() then
                region:SetTexture(nil)
            end
        end
    end

    if not scrollBar.SetBackdrop and BackdropTemplateMixin then
        Mixin(scrollBar, BackdropTemplateMixin)
    end

    local thumb = scrollBar:GetThumbTexture()
    if not thumb and scrollBar.CreateTexture then
        thumb = scrollBar:CreateTexture(nil, "ARTWORK")
        scrollBar:SetThumbTexture(thumb)
    end

    -- Hook stepper buttons to stay hidden in modern mode even if Blizzard's OnScrollRangeChanged shows them
    if not scrollBar._hookedBtnShow then
        scrollBar._hookedBtnShow = true
        if upBtn and upBtn.HookScript then
            upBtn:HookScript("OnShow", function(btn)
                if not sfui.theme.IsCamelotActive() then
                    btn:Hide()
                end
            end)
        end
        if downBtn and downBtn.HookScript then
            downBtn:HookScript("OnShow", function(btn)
                if not sfui.theme.IsCamelotActive() then
                    btn:Hide()
                end
            end)
        end
    end

    local isCamelot = sfui.theme.IsCamelotActive()

    -- ── Visibility Updater Function ──
    scrollBar.UpdateVisibility = function(self)
        local p = self:GetParent()
        if not p then return end
        if p.UpdateScrollChildRect then
            pcall(p.UpdateScrollChildRect, p)
        end
        local range = (p.GetVerticalScrollRange and p:GetVerticalScrollRange()) or 0
        local minVal, maxVal = self:GetMinMaxValues()
        local maxRange = maxVal and (maxVal - (minVal or 0)) or 0
        local child = p.GetScrollChild and p:GetScrollChild()
        local childH = (child and child.GetHeight and child:GetHeight()) or 0
        local frameH = (p.GetHeight and p:GetHeight()) or 0

        local isScrollable = (range > 0.5) or (maxRange > 0.5) or (childH > (frameH + 1) and frameH > 0)
        local camelotActive = sfui.theme.IsCamelotActive()

        if isScrollable then
            self:Show()
            if camelotActive then
                if self.upBtn then self.upBtn:Show() end
                if self.downBtn then self.downBtn:Show() end
                if self.trackFrame then self.trackFrame:Show() end
                if self.thumbSkin then self.thumbSkin:Show() end
            else
                if self.upBtn then self.upBtn:Hide() end
                if self.downBtn then self.downBtn:Hide() end
                if self.trackFrame then self.trackFrame:Hide() end
                if self.thumbSkin then self.thumbSkin:Hide() end
            end
        else
            self:Hide()
            if self.upBtn then self.upBtn:Hide() end
            if self.downBtn then self.downBtn:Hide() end
            if self.trackFrame then self.trackFrame:Hide() end
            if self.thumbSkin then self.thumbSkin:Hide() end
        end
    end

    if isCamelot then
        -- ══════════════════════════════════════════════════════════════════════
        --  Camelot Bronze Trim ScrollBar (MinimalScrollBar / CharacterStatsPane)
        -- ══════════════════════════════════════════════════════════════════════
        scrollBar:SetWidth(10)
        if parent and scrollBar.ClearAllPoints then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, -14)
            scrollBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 4, 14)
        end

        if scrollBar.SetBackdrop then
            scrollBar:SetBackdrop(nil)
        end

        -- Track Frame (Subtle bronze track behind slider)
        local trackFrame = scrollBar.trackFrame
        if not trackFrame then
            trackFrame = CreateFrame("Frame", nil, scrollBar)
            scrollBar.trackFrame = trackFrame
            trackFrame:EnableMouse(false)
            trackFrame:SetFrameLevel(math.max(1, (scrollBar:GetFrameLevel() or 1) - 1))
            trackFrame:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 1, 0)
            trackFrame:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", -1, 0)

            local trackTop = trackFrame:CreateTexture(nil, "BACKGROUND")
            trackTop:SetPoint("TOPLEFT", trackFrame, "TOPLEFT", 0, 0)
            trackTop:SetPoint("TOPRIGHT", trackFrame, "TOPRIGHT", 0, 0)
            trackTop:SetHeight(8)
            trackFrame.top = trackTop

            local trackBot = trackFrame:CreateTexture(nil, "BACKGROUND")
            trackBot:SetPoint("BOTTOMLEFT", trackFrame, "BOTTOMLEFT", 0, 0)
            trackBot:SetPoint("BOTTOMRIGHT", trackFrame, "BOTTOMRIGHT", 0, 0)
            trackBot:SetHeight(8)
            trackFrame.bot = trackBot

            local trackMid = trackFrame:CreateTexture(nil, "BACKGROUND")
            trackMid:SetPoint("TOPLEFT", trackTop, "BOTTOMLEFT", 0, 0)
            trackMid:SetPoint("BOTTOMRIGHT", trackBot, "TOPRIGHT", 0, 0)
            trackFrame.mid = trackMid
        end
        trackFrame:Show()
        pcall(function()
            trackFrame.top:SetAtlas("minimal-scrollbar-track-top", false)
            trackFrame.bot:SetAtlas("minimal-scrollbar-track-bottom", false)
            trackFrame.mid:SetAtlas("!minimal-scrollbar-track-middle", false)
        end)

        -- Thumb Skin (Smooth 3-part rounded bronze pill)
        if thumb then
            thumb:SetAlpha(0) -- invisible drag handle
            thumb:SetSize(8, 26)

            local thumbSkin = scrollBar.thumbSkin
            if not thumbSkin then
                thumbSkin = CreateFrame("Frame", nil, scrollBar)
                scrollBar.thumbSkin = thumbSkin
                thumbSkin:EnableMouse(false)
                thumbSkin:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
                thumbSkin:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)

                local tTop = thumbSkin:CreateTexture(nil, "ARTWORK")
                tTop:SetPoint("TOPLEFT", thumbSkin, "TOPLEFT", 0, 0)
                tTop:SetPoint("TOPRIGHT", thumbSkin, "TOPRIGHT", 0, 0)
                tTop:SetHeight(8)
                thumbSkin.top = tTop

                local tBot = thumbSkin:CreateTexture(nil, "ARTWORK")
                tBot:SetPoint("BOTTOMLEFT", thumbSkin, "BOTTOMLEFT", 0, 0)
                tBot:SetPoint("BOTTOMRIGHT", thumbSkin, "BOTTOMRIGHT", 0, 0)
                tBot:SetHeight(8)
                thumbSkin.bot = tBot

                local tMid = thumbSkin:CreateTexture(nil, "ARTWORK")
                tMid:SetPoint("TOPLEFT", tTop, "BOTTOMLEFT", 0, 0)
                tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT", 0, 0)
                thumbSkin.mid = tMid
            end
            thumbSkin:Show()
            pcall(function()
                thumbSkin.top:SetAtlas("minimal-scrollbar-small-thumb-top", false)
                thumbSkin.mid:SetAtlas("minimal-scrollbar-small-thumb-middle", false)
                thumbSkin.bot:SetAtlas("minimal-scrollbar-small-thumb-bottom", false)
            end)
        end

        -- Stepper Buttons
        if upBtn then
            upBtn:Show()
            upBtn:SetAlpha(1)
            upBtn:EnableMouse(true)
            upBtn:SetSize(17, 11)
            upBtn:ClearAllPoints()
            upBtn:SetPoint("BOTTOM", scrollBar, "TOP", 0, 2)
            SetButtonAtlasSafe(upBtn,
                "minimal-scrollbar-arrow-top",
                "minimal-scrollbar-arrow-top-down",
                "minimal-scrollbar-arrow-top-over",
                "minimal-scrollbar-arrow-top"
            )
            if not upBtn:GetScript("OnClick") then
                upBtn:SetScript("OnClick", function()
                    local cur = scrollBar:GetValue()
                    local step = scrollBar:GetHeight() / 3
                    scrollBar:SetValue(math.max(0, cur - step))
                end)
            end
        end

        if downBtn then
            downBtn:Show()
            downBtn:SetAlpha(1)
            downBtn:EnableMouse(true)
            downBtn:SetSize(17, 11)
            downBtn:ClearAllPoints()
            downBtn:SetPoint("TOP", scrollBar, "BOTTOM", 0, -2)
            SetButtonAtlasSafe(downBtn,
                "minimal-scrollbar-arrow-bottom",
                "minimal-scrollbar-arrow-bottom-down",
                "minimal-scrollbar-arrow-bottom-over",
                "minimal-scrollbar-arrow-bottom"
            )
            if not downBtn:GetScript("OnClick") then
                downBtn:SetScript("OnClick", function()
                    local cur = scrollBar:GetValue()
                    local minV, maxV = scrollBar:GetMinMaxValues()
                    local step = scrollBar:GetHeight() / 3
                    scrollBar:SetValue(math.min(maxV or (cur + step), cur + step))
                end)
            end
        end

        -- Interactions: Hover states and value changed button enabling
        if not scrollBar._hookedInteractions then
            scrollBar._hookedInteractions = true

            local function setThumbState(state)
                if not sfui.theme.IsCamelotActive() then return end
                local skin = scrollBar.thumbSkin
                if not skin or not skin.top then return end
                local suffix = (state == "down" and "-down") or (state == "over" and "-over") or ""
                pcall(function()
                    skin.top:SetAtlas("minimal-scrollbar-small-thumb-top" .. suffix, false)
                    skin.mid:SetAtlas("minimal-scrollbar-small-thumb-middle" .. suffix, false)
                    skin.bot:SetAtlas("minimal-scrollbar-small-thumb-bottom" .. suffix, false)
                end)
            end

            scrollBar:HookScript("OnEnter", function() setThumbState("over") end)
            scrollBar:HookScript("OnLeave", function() setThumbState("normal") end)
            scrollBar:HookScript("OnMouseDown", function() setThumbState("down") end)
            scrollBar:HookScript("OnMouseUp", function() setThumbState("over") end)

            scrollBar:HookScript("OnValueChanged", function(bar, val)
                if sfui.theme.IsCamelotActive() then
                    local minV, maxV = bar:GetMinMaxValues()
                    minV = minV or 0
                    maxV = maxV or 0
                    if bar.upBtn then
                        local nt = bar.upBtn:GetNormalTexture()
                        if val <= minV + 0.1 then
                            bar.upBtn:Disable()
                            if nt and nt.SetDesaturated then nt:SetDesaturated(true) end
                        else
                            bar.upBtn:Enable()
                            if nt and nt.SetDesaturated then nt:SetDesaturated(false) end
                        end
                    end
                    if bar.downBtn then
                        local nt = bar.downBtn:GetNormalTexture()
                        if val >= maxV - 0.1 then
                            bar.downBtn:Disable()
                            if nt and nt.SetDesaturated then nt:SetDesaturated(true) end
                        else
                            bar.downBtn:Enable()
                            if nt and nt.SetDesaturated then nt:SetDesaturated(false) end
                        end
                    end
                end
            end)
        end
    else
        -- ══════════════════════════════════════════════════════════════════════
        --  Modern Flat Minimal ScrollBar
        -- ══════════════════════════════════════════════════════════════════════
        scrollBar:SetWidth(6)
        if parent and scrollBar.ClearAllPoints then
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, -2)
            scrollBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", 8, 2)
        end

        if upBtn then
            upBtn:Hide()
            upBtn:SetAlpha(0)
            upBtn:EnableMouse(false)
        end
        if downBtn then
            downBtn:Hide()
            downBtn:SetAlpha(0)
            downBtn:EnableMouse(false)
        end

        if scrollBar.trackFrame then
            scrollBar.trackFrame:Hide()
        end
        if scrollBar.thumbSkin then
            scrollBar.thumbSkin:Hide()
        end

        if scrollBar.SetBackdrop then
            scrollBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            scrollBar:SetBackdropColor(0, 0, 0, 0.3)
        end

        if thumb then
            thumb:SetAlpha(0.75)
            thumb:SetSize(6, 30)
            thumb:SetColorTexture(1, 1, 1, 0.75)
        end
    end

    scrollBar:UpdateVisibility()
end

-- 8. Minimap Bar Styling (Styled like Quest Headers)
function sfui.theme.ApplyMinimapButtonBarStyle(bar)
    if not bar then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()
    local atlases = theme.atlases or {}
    local isCamelot = (activeID == "camelot")
    local canUseBanner = isCamelot and atlases.headerBanner and sfui.theme.HasAtlas(atlases.headerBanner)

    -- Hide any stray window border layers if button_bar was ever previously registered as a window
    if bar.sfuiThemeLayers and bar.sfuiThemeLayers.borderFrame then
        bar.sfuiThemeLayers.borderFrame:Hide()
    end

    if canUseBanner then
        if not bar.bgBanner then
            bar.bgBanner = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
            bar.bgBanner:SetAllPoints(bar)
        end
        bar.bgBanner:SetAtlas(atlases.headerBanner)
        bar.bgBanner:Show()

        if bar.SetBackdrop then bar:SetBackdrop(nil) end
        if bar.accent then bar.accent:Hide() end
        bar:SetHeight(36)
    else
        if bar.bgBanner then bar.bgBanner:Hide() end
        local mult = sfui.pixelScale or 1
        if bar.SetBackdrop then
            bar:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                tile     = true,
                tileSize = 16,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            bar:SetBackdropColor(0, 0, 0, 0.50)
            bar:SetBackdropBorderColor(0, 0, 0, 0.50)
        end
        if not bar.accent then
            local accent = bar:CreateTexture(nil, "OVERLAY")
            accent:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            accent:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            accent:SetWidth(3)
            bar.accent = accent
        end
        local col = pal.accentColor or { 0, 1, 1, 1 }
        bar.accent:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
        bar.accent:Show()
        bar:SetHeight(32)
    end
end

-- 9. Loot Feed Row Styling (Camelot: Architectural Slate vs Sculpted Bronze Card | Modern: Minimalist)
function sfui.theme.ApplyLootfeedRowStyle(row, color, quality, isOther)
    if not row then return end
    if isOther ~= nil then
        row.isOther = (isOther == true)
    end
    local otherLoot = (row.isOther == true)

    local isCamelot = sfui.theme.IsCamelotActive()
    local pal = sfui.theme.GetPalette()
    local col = color or { 1, 1, 1 }

    row.lastColor = col
    row.lastQuality = quality

    local mult = sfui.pixelScale or 1

    if isCamelot then
        row.isCamelotRow = true

        local camelotStyle = (SfuiDB and (SfuiDB.camelotLootfeedStyle or (SfuiDB.theme and SfuiDB.theme.lootfeedStyle)))
            or (sfui.config and sfui.config.theme and sfui.config.theme.lootfeedStyle)
            or "architectural"

        local canUseOutfitCard = sfui.theme.HasAtlas("UI-Character-Info-OutfitCard")
        local useCard = (camelotStyle == "outfit_card" and canUseOutfitCard)

        if useCard then
            -- ─────────────────────────────────────────────────────────────────
            -- CAMELOT OPTION A: Sculpted Inset Card (UI-Character-Info-OutfitCard)
            -- ─────────────────────────────────────────────────────────────────
            row.lootfeedStyle = "outfit_card"

            -- Remove flat solid backdrop so the carved bronze card is the frame
            if row.SetBackdrop then
                row:SetBackdrop(nil)
            end

            if row.cardBg then
                row.cardBg:SetAtlas("UI-Character-Info-OutfitCard")
                row.cardBg:ClearAllPoints()
                row.cardBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 2)
                row.cardBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
                if otherLoot then
                    row.cardBg:SetDesaturated(true)
                    row.cardBg:SetVertexColor(0.72, 0.74, 0.80, 1.0)
                else
                    row.cardBg:SetDesaturated(false)
                    row.cardBg:SetVertexColor(1, 1, 1, 1)
                end
                row.cardBg:Show()
            end

            if row.hoverOverlay then
                if sfui.theme.HasAtlas("UI-Character-Info-OutfitCard-Hover") then
                    row.hoverOverlay:SetAtlas("UI-Character-Info-OutfitCard-Hover")
                    row.hoverOverlay:ClearAllPoints()
                    row.hoverOverlay:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 2)
                    row.hoverOverlay:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
                    row.hoverOverlay:SetBlendMode("ADD")
                    row.hoverOverlay:SetAlpha(0.45)
                end
            end

            -- Hide corner brackets, flat accent strip, and gear slot in card mode
            if row.cornerTL then
                row.cornerTL:Hide()
                row.cornerTR:Hide()
                row.cornerBL:Hide()
                row.cornerBR:Hide()
            end
            if row.accent then row.accent:Hide() end
            if row.iconSlot then row.iconSlot:Hide() end

            -- Icon and ornate carved bezel
            if row.icon then
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            if row.iconBorder then
                if sfui.theme.HasAtlas("UI-Character-Info-OutfitIcon-Frame") then
                    row.iconBorder:SetAtlas("UI-Character-Info-OutfitIcon-Frame")
                    row.iconBorder:ClearAllPoints()
                    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
                    local iW, iH = row.icon:GetSize()
                    if not iW or iW == 0 then iW = 28 end
                    if not iH or iH == 0 then iH = 28 end
                    row.iconBorder:SetSize(iW + 8, iH + 8)
                    row.iconBorder:SetVertexColor(1, 1, 1, 1)
                    row.iconBorder:Show()
                else
                    row.iconBorder:Hide()
                end
            end

            -- Clean Right-Aligned Radiant Gold Badge
            if row.badge then
                row.badge:ClearAllPoints()
                row.badge:SetPoint("RIGHT", row, "RIGHT", -12, 0)
                row.badge:SetJustifyH("RIGHT")
                row.badge:SetTextColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
            end

            -- Title FontString (Colored by Quality / col)
            if row.title then
                row.title:ClearAllPoints()
                row.title:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
                local bText = row.badge and row.badge:GetText()
                if bText and bText ~= "" then
                    row.title:SetPoint("RIGHT", row.badge, "LEFT", -8, 0)
                else
                    row.title:SetPoint("RIGHT", row, "RIGHT", -12, 0)
                end
                if col then
                    row.title:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, 1)
                else
                    row.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
                end
            end
        else
            -- ─────────────────────────────────────────────────────────────────
            -- CAMELOT OPTION B: Architectural Slate & Sculpted Corner Brackets
            -- (Also serves as safe authentic fallback if card atlas is missing)
            -- ─────────────────────────────────────────────────────────────────
            row.lootfeedStyle = "architectural"

            if row.cardBg then row.cardBg:Hide() end
            if row.hoverOverlay then row.hoverOverlay:Hide() end
            if row.iconBorder then row.iconBorder:Hide() end

            if row.SetBackdrop then
                row:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = mult,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                if otherLoot then
                    row:SetBackdropColor(0.20, 0.20, 0.23, 0.92)
                    if row.SetBackdropBorderColor then
                        row:SetBackdropBorderColor(0.45, 0.45, 0.48, 0.90)
                    end
                else
                    row:SetBackdropColor(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.94)
                    if row.SetBackdropBorderColor then
                        row:SetBackdropBorderColor(0.38, 0.28, 0.12, 0.90)
                    end
                end
            end

            -- Sculpted Corner Brackets (Blizzard heavybronze corner brackets)
            local showBrackets = (SfuiDB and SfuiDB.themeCornerBrackets ~= false)
            if showBrackets then
                if not row.cornerTL then
                    row.cornerTL = row:CreateTexture(nil, "OVERLAY", nil, 6)
                    row.cornerTR = row:CreateTexture(nil, "OVERLAY", nil, 6)
                    row.cornerBL = row:CreateTexture(nil, "OVERLAY", nil, 6)
                    row.cornerBR = row:CreateTexture(nil, "OVERLAY", nil, 6)
                end

                local tlAtlas = sfui.theme.GetCornerBracketAtlas("TL") or "heavybronze-horz-cornerbracket-TL"
                local trAtlas = sfui.theme.GetCornerBracketAtlas("TR") or "heavybronze-horz-cornerbracket-TR"
                local blAtlas = sfui.theme.GetCornerBracketAtlas("BL") or "heavybronze-horz-cornerbracket-BL"
                local brAtlas = sfui.theme.GetCornerBracketAtlas("BR") or "heavybronze-horz-cornerbracket-BR"
                local bSize = 10

                local bracketR, bracketG, bracketB = 1, 1, 1
                if otherLoot then
                    bracketR, bracketG, bracketB = 0.80, 0.80, 0.85
                end

                if sfui.theme.HasAtlas(tlAtlas) then
                    row.cornerTL:SetAtlas(tlAtlas, false)
                    row.cornerTL:SetVertexColor(bracketR, bracketG, bracketB, 1)
                    row.cornerTL:ClearAllPoints()
                    row.cornerTL:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 1)
                    row.cornerTL:SetSize(bSize, bSize)
                    row.cornerTL:Show()
                else row.cornerTL:Hide() end

                if sfui.theme.HasAtlas(trAtlas) then
                    row.cornerTR:SetAtlas(trAtlas, false)
                    row.cornerTR:SetVertexColor(bracketR, bracketG, bracketB, 1)
                    row.cornerTR:ClearAllPoints()
                    row.cornerTR:SetPoint("TOPRIGHT", row, "TOPRIGHT", 1, 1)
                    row.cornerTR:SetSize(bSize, bSize)
                    row.cornerTR:Show()
                else row.cornerTR:Hide() end

                if sfui.theme.HasAtlas(blAtlas) then
                    row.cornerBL:SetAtlas(blAtlas, false)
                    row.cornerBL:SetVertexColor(bracketR, bracketG, bracketB, 1)
                    row.cornerBL:ClearAllPoints()
                    row.cornerBL:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -1, -1)
                    row.cornerBL:SetSize(bSize, bSize)
                    row.cornerBL:Show()
                else row.cornerBL:Hide() end

                if sfui.theme.HasAtlas(brAtlas) then
                    row.cornerBR:SetAtlas(brAtlas, false)
                    row.cornerBR:SetVertexColor(bracketR, bracketG, bracketB, 1)
                    row.cornerBR:ClearAllPoints()
                    row.cornerBR:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, -1)
                    row.cornerBR:SetSize(bSize, bSize)
                    row.cornerBR:Show()
                else row.cornerBR:Hide() end
            elseif row.cornerTL then
                row.cornerTL:Hide()
                row.cornerTR:Hide()
                row.cornerBL:Hide()
                row.cornerBR:Hide()
            end

            -- Inlaid Enamel Quality Strip (Unique to Architectural Slate)
            if row.accent then
                row.accent:ClearAllPoints()
                row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
                row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
                row.accent:SetWidth(3)
                row.accent:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
                row.accent:Show()
            end

            -- Sunken GearSlot Icon Socket
            if row.icon then
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 7, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            if row.iconSlot then
                if sfui.theme.HasAtlas("UI-Character-Info-GearSlot") then
                    row.iconSlot:SetAtlas("UI-Character-Info-GearSlot")
                    row.iconSlot:ClearAllPoints()
                    row.iconSlot:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
                    local iW, iH = row.icon:GetSize()
                    if not iW or iW == 0 then iW = 28 end
                    if not iH or iH == 0 then iH = 28 end
                    row.iconSlot:SetSize(iW + 4, iH + 4)
                    row.iconSlot:Show()
                else
                    row.iconSlot:Hide()
                end
            end

            -- Clean Right-Aligned Radiant Gold Badge
            if row.badge then
                row.badge:ClearAllPoints()
                row.badge:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.badge:SetJustifyH("RIGHT")
                row.badge:SetTextColor(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
            end

            -- Title FontString (Colored by Quality / col)
            if row.title then
                row.title:ClearAllPoints()
                row.title:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
                local bText = row.badge and row.badge:GetText()
                if bText and bText ~= "" then
                    row.title:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)
                else
                    row.title:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                end
                if col then
                    row.title:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, 1)
                else
                    row.title:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
                end
            end
        end

    else
        -- ═════════════════════════════════════════════════════════════════════
        -- MODERN MINIMALIST (Clean dark flat card)
        -- ═════════════════════════════════════════════════════════════════════
        row.isCamelotRow = false
        row.lootfeedStyle = nil

        if row.cardBg then row.cardBg:Hide() end
        if row.hoverOverlay then row.hoverOverlay:Hide() end
        if row.iconSlot then row.iconSlot:Hide() end
        if row.iconBorder then row.iconBorder:Hide() end
        if row.badgeBox then row.badgeBox:Hide() end
        if row.cornerTL then
            row.cornerTL:Hide()
            row.cornerTR:Hide()
            row.cornerBL:Hide()
            row.cornerBR:Hide()
        end

        if row.SetBackdrop then
            row:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            if otherLoot then
                row:SetBackdropColor(0.22, 0.22, 0.26, 0.75)
                if row.SetBackdropBorderColor then
                    row:SetBackdropBorderColor(0.42, 0.42, 0.48, 0.85)
                end
            else
                row:SetBackdropColor(0, 0, 0, 0.50)
                if row.SetBackdropBorderColor then
                    row:SetBackdropBorderColor(0, 0, 0, 0.50)
                end
            end
        end

        if row.accent then
            row.accent:ClearAllPoints()
            row.accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.accent:SetWidth(3)
            row.accent:SetColorTexture(col[1] or 1, col[2] or 1, col[3] or 1, 1)
            row.accent:Show()
        end

        if row.icon then
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        if row.badge then
            row.badge:ClearAllPoints()
            row.badge:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.badge:SetJustifyH("RIGHT")
            row.badge:SetTextColor(1, 1, 1, 1)
        end

        if row.title then
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
            local bText = row.badge and row.badge:GetText()
            if bText and bText ~= "" then
                row.title:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
            else
                row.title:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            end
            if col then
                row.title:SetTextColor(col[1] or 1, col[2] or 1, col[3] or 1, 1)
            else
                row.title:SetTextColor(1, 1, 1, 1)
            end
        end
    end
end

function sfui.theme.ApplyLootfeedPendingHeaderStyle(pendingHeader)
    if not pendingHeader then return end
    local isCamelot = sfui.theme.IsCamelotActive()
    local pal = sfui.theme.GetPalette()
    local mult = sfui.pixelScale or 1

    if isCamelot then
        if pendingHeader.SetBackdrop then
            pendingHeader:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            pendingHeader:SetBackdropColor(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.94)
            if pendingHeader.SetBackdropBorderColor then
                pendingHeader:SetBackdropBorderColor(0.38, 0.28, 0.12, 0.90)
            end
        end
        if pendingHeader.text then
            pendingHeader.text:SetTextColor(pal.headerColor[1], pal.headerColor[2], pal.headerColor[3], 1)
        end
    else
        if pendingHeader.SetBackdrop then
            pendingHeader:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            pendingHeader:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
            if pendingHeader.SetBackdropBorderColor then
                pendingHeader:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.90)
            end
        end
        if pendingHeader.text then
            pendingHeader.text:SetTextColor(0.85, 0.85, 0.85, 1)
        end
    end
end

-- ─── Bar / StatusBar Theming API ──────────────────────────────────────────────
--
-- bar types passed to ApplyStatusBarStyle / RegisterBar:
--   "health"       – player health bar (bar0)
--   "power"        – player primary power (bar_minus_1)
--   "secondary"    – player secondary resource (bar1: combo points, holy power…)
--   "rune"         – individual DK rune segment
--   "vigor"        – dragonriding vigor
--   "mountspeed"   – dragonriding mount speed
--   "threat"       – threat status bar
--   "castbar"      – any cast-bar backdrop/bar
--   "swing"        – swing timer bar (main-hand, off-hand, ranged)
--   "target"       – target health / power bar
--

-- bar styles (set via theme.bars.style, config.theme.barStyle, or SfuiDB.themeBarStyle):
--   "thin"   – Option A: 1px colored edge only (classic minimal)
--   "glow"   – Option B: borderless recessed amber inner-glow / vignette
--   "heavy"  – Option C: chiseled heavy bronze frame with bright gold top highlight,
--              dark bottom shadow, and authentic corner brackets

--- Hide all decor elements on a bar decorFrame
local function _HideDecorElements(decorFrame)
    if not decorFrame then return end
    if decorFrame.topHL then decorFrame.topHL:Hide() end
    if decorFrame.botShadow then decorFrame.botShadow:Hide() end
    if decorFrame.topGlow then decorFrame.topGlow:Hide() end
    if decorFrame.leftGlow then decorFrame.leftGlow:Hide() end
    if decorFrame.rightGlow then decorFrame.rightGlow:Hide() end
    if decorFrame.topInset then decorFrame.topInset:Hide() end
    if decorFrame.leftInset then decorFrame.leftInset:Hide() end
    if decorFrame.botRim then decorFrame.botRim:Hide() end
    if decorFrame.cornerTL then decorFrame.cornerTL:Hide() end
    if decorFrame.cornerTR then decorFrame.cornerTR:Hide() end
    if decorFrame.cornerBL then decorFrame.cornerBL:Hide() end
    if decorFrame.cornerBR then decorFrame.cornerBR:Hide() end
    if decorFrame.nameplateBG then decorFrame.nameplateBG:Hide() end
    if decorFrame.cornerCutTL then decorFrame.cornerCutTL:Hide() end
    if decorFrame.cornerCutTR then decorFrame.cornerCutTR:Hide() end
    if decorFrame.cornerCutBL then decorFrame.cornerCutBL:Hide() end
    if decorFrame.cornerCutBR then decorFrame.cornerCutBR:Hide() end
end

--- Resolve active bar style
--- @param bars_def table
--- @param barType string
--- @param isCamelot boolean
--- @return string
local function _ResolveBarStyle(bars_def, barType, isCamelot)
    if bars_def[barType] and bars_def[barType].style then
        return bars_def[barType].style
    end
    local dbStyle = (SfuiDB and (SfuiDB.camelotBarStyle or SfuiDB.themeBarStyle or (SfuiDB.theme and SfuiDB.theme.barStyle)))
    if dbStyle then
        return dbStyle
    end
    if sfui.config.theme and sfui.config.theme.barStyle then
        return sfui.config.theme.barStyle
    end
    if bars_def.style then
        return bars_def.style
    end
    return isCamelot and "castbar" or "thin"
end

--- Get the current bar style setting
--- @return string
function sfui.theme.GetBarStyle()
    local dbStyle = (SfuiDB and (SfuiDB.camelotBarStyle or SfuiDB.themeBarStyle or (SfuiDB.theme and SfuiDB.theme.barStyle)))
    if dbStyle then return dbStyle end
    if sfui.config.theme and sfui.config.theme.barStyle then
        return sfui.config.theme.barStyle
    end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[activeID] or {}
    if theme.bars and theme.bars.style then
        return theme.bars.style
    end
    return (activeID == "camelot") and "castbar" or "thin"
end

--- Set the bar style and refresh all registered bars
--- @param style string "inset" | "bezel" | "darkbronze" | "castbar" | "heavy" | "thin" | "glow"
--- @return boolean, string?
function sfui.theme.SetBarStyle(style)
    local s = style and style:lower() or ""
    if s == "inset" or s == "darkinset" or s == "dark" then
        s = "inset"
    elseif s == "bezel" or s == "nameplate" or s == "hud" or s == "blizzard" then
        s = "bezel"
    elseif s == "darkbronze" or s == "bronze" then
        s = "darkbronze"
    elseif s == "castbar" or s == "cast" then
        s = "castbar"
    elseif s == "heavy" or s == "chiseled" or s == "brackets" then
        s = "heavy"
    elseif s == "thin" or s == "flat" or s == "minimal" then
        s = "thin"
    elseif s == "glow" or s == "recessed" then
        s = "glow"
    else
        return false, "Invalid bar style. Valid styles: inset, bezel, darkbronze, castbar, heavy, thin, glow"
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.camelotBarStyle = s
    SfuiDB.themeBarStyle = s
    if SfuiDB.theme then
        SfuiDB.theme.barStyle = s
    end
    if sfui.config.theme then
        sfui.config.theme.barStyle = s
    end
    for bar, barType in pairs(registered_bars) do
        if bar then
            sfui.theme.ApplyStatusBarStyle(bar, barType)
        end
    end
    return true
end

--- Apply theme colors and decorative styling to a status-bar backdrop.
--- Touches ONLY backdrop color & border — never the bar fill color, which
--- is managed by each bar's own combat-update logic.
--- @param bar Frame   the StatusBar (must have a .backdrop child, or be a backdrop frame itself)
--- @param barType string
function sfui.theme.ApplyStatusBarStyle(bar, barType)
    if not bar then return end
    local backdrop = bar.backdrop or bar
    if not backdrop then return end

    local activeID = sfui.theme.GetActiveThemeID()
    local theme    = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal      = theme.colors or sfui.theme.GetPalette()
    local bars_def = theme.bars or {}
    local isCamelot = (activeID == "camelot")

    -- Resolve per-type override from theme definition, fall back to palette
    local bgCol    = (bars_def[barType] and bars_def[barType].backdropColor) or pal.backdropColor or { 0, 0, 0, 0.55 }
    local bdCol    = (bars_def[barType] and bars_def[barType].borderColor)   or pal.borderColor   or { 0, 0, 0, 1 }
    local bdSize   = (bars_def[barType] and bars_def[barType].borderSize)    or 1
    local style    = _ResolveBarStyle(bars_def, barType, isCamelot)

    if backdrop.SetBackdrop then
        backdrop:SetBackdrop({
            bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
            edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
            edgeSize = bdSize,
            tile     = true,
            tileSize = 32,
            insets   = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        backdrop:SetBackdropColor(bgCol[1], bgCol[2], bgCol[3], bgCol[4] or 0.55)

        if backdrop.SetBackdropBorderColor then
            if not isCamelot then
                backdrop:SetBackdropBorderColor(bdCol[1], bdCol[2], bdCol[3], bdCol[4] or 1)
            elseif style == "bezel" then
                -- Native Blizzard bezel manages its own border via atlas
                backdrop:SetBackdropBorderColor(0, 0, 0, 0)
            elseif style == "glow" then
                -- Borderless recessed amber well
                backdrop:SetBackdropBorderColor(0, 0, 0, 0)
            elseif style == "castbar" then
                -- Pure crisp pitch black border matching Screenshot 2 castbar
                backdrop:SetBackdropBorderColor(0, 0, 0, 1)
            elseif style == "inset" then
                -- Dark antique bronze / deep charcoal border
                local bc = (bars_def[barType] and bars_def[barType].borderColor) or { 0.14, 0.10, 0.06, 0.98 }
                backdrop:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 0.98)
            elseif style == "darkbronze" then
                -- Rich muted antique bronze
                local bc = (bars_def[barType] and bars_def[barType].borderColor) or { 0.24, 0.18, 0.09, 0.90 }
                backdrop:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 0.90)
            else
                -- Option A (thin) & Option C (heavy): Warm bronze edge
                local bc = (bars_def[barType] and bars_def[barType].borderColor) or { 0.40, 0.30, 0.15, 0.90 }
                backdrop:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 0.90)
            end
        end
    end

    -- Target bar with native Nameplate bezel: preserve nameplateBorder & hide generic decor
    if barType == "target" then
        if backdrop.nameplateBorder and backdrop.nameplateBorder:IsShown() then
            if backdrop.SetBackdropBorderColor then
                backdrop:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end
        if backdrop._sfuiDecorFrame then
            _HideDecorElements(backdrop._sfuiDecorFrame)
            backdrop._sfuiDecorFrame:Hide()
        end
        return
    end

    -- Apply / update decorative texture layers
    local decorFrame = backdrop._sfuiDecorFrame
    if not isCamelot or style == "thin" or style == "castbar" then
        if decorFrame then
            _HideDecorElements(decorFrame)
            decorFrame:Hide()
        end
        return
    end

    if not decorFrame then
        decorFrame = CreateFrame("Frame", nil, backdrop)
        decorFrame:SetAllPoints(backdrop)
        backdrop._sfuiDecorFrame = decorFrame
    end
    decorFrame:Show()
    local targetLevel = (bar.GetFrameLevel and bar:GetFrameLevel() or backdrop:GetFrameLevel()) + 1
    decorFrame:SetFrameLevel(targetLevel)
    _HideDecorElements(decorFrame)

    if style == "inset" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION 1: Dark Inset Well with Softened (Rounded) Corners & Antique Bronze Rim
        -- Matches the sleek, recessed aesthetic of the castbar in Screenshot 2
        -- ═════════════════════════════════════════════════════════════════════
        -- 1. Top dark inset shadow (1px)
        if not decorFrame.topInset then
            decorFrame.topInset = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.topInset:ClearAllPoints()
        decorFrame.topInset:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 1, -1)
        decorFrame.topInset:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -1, -1)
        decorFrame.topInset:SetHeight(1)
        decorFrame.topInset:SetColorTexture(0.01, 0.01, 0.01, 0.75)
        decorFrame.topInset:Show()

        -- 2. Left dark inset shadow (1px)
        if not decorFrame.leftInset then
            decorFrame.leftInset = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.leftInset:ClearAllPoints()
        decorFrame.leftInset:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 1, -1)
        decorFrame.leftInset:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 1, 1)
        decorFrame.leftInset:SetWidth(1)
        decorFrame.leftInset:SetColorTexture(0.01, 0.01, 0.01, 0.65)
        decorFrame.leftInset:Show()

        -- 3. Bottom subtle antique bronze metallic reflection (1px)
        if not decorFrame.botRim then
            decorFrame.botRim = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.botRim:ClearAllPoints()
        decorFrame.botRim:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 1, 1)
        decorFrame.botRim:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 1)
        decorFrame.botRim:SetHeight(1)
        decorFrame.botRim:SetColorTexture(0.30, 0.22, 0.11, 0.45)
        decorFrame.botRim:Show()

        -- 4. Micro corner softening (rounds off the harsh 90° corner pixels)
        local cornerCuts = {
            { key = "cornerCutTL", point = "TOPLEFT",     x = 0, y = 0 },
            { key = "cornerCutTR", point = "TOPRIGHT",    x = 0, y = 0 },
            { key = "cornerCutBL", point = "BOTTOMLEFT",  x = 0, y = 0 },
            { key = "cornerCutBR", point = "BOTTOMRIGHT", x = 0, y = 0 },
        }
        for _, cc in ipairs(cornerCuts) do
            if not decorFrame[cc.key] then
                decorFrame[cc.key] = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            end
            local cut = decorFrame[cc.key]
            cut:ClearAllPoints()
            cut:SetPoint(cc.point, backdrop, cc.point, cc.x, cc.y)
            cut:SetSize(1, 1)
            cut:SetColorTexture(0, 0, 0, 0.75)
            cut:Show()
        end

    elseif style == "bezel" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION 2: Blizzard Native Nameplate HUD Inset Atlas
        -- ═════════════════════════════════════════════════════════════════════
        local hasNameplateAtlas = sfui.theme.HasAtlas and sfui.theme.HasAtlas("UI-HUD-CoolDownManager-Bar-BG")
        if hasNameplateAtlas then
            if not decorFrame.nameplateBG then
                decorFrame.nameplateBG = decorFrame:CreateTexture(nil, "BACKGROUND", nil, -5)
            end
            decorFrame.nameplateBG:SetAtlas("UI-HUD-CoolDownManager-Bar-BG", false)
            decorFrame.nameplateBG:ClearAllPoints()
            decorFrame.nameplateBG:SetPoint("TOPLEFT", backdrop, "TOPLEFT", -2, 3)
            decorFrame.nameplateBG:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 6, -6)
            decorFrame.nameplateBG:Show()
        end

    elseif style == "darkbronze" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION 3: Sculpted Dark Bronze Inset with Muted Sheen
        -- ═════════════════════════════════════════════════════════════════════
        -- 1. Top metallic sheen (muted, not bright gold)
        if not decorFrame.topHL then
            decorFrame.topHL = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        end
        decorFrame.topHL:ClearAllPoints()
        decorFrame.topHL:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 1, 0)
        decorFrame.topHL:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -1, 0)
        decorFrame.topHL:SetHeight(1)
        decorFrame.topHL:SetColorTexture(0.40, 0.30, 0.14, 0.65)
        decorFrame.topHL:Show()

        -- 2. Bottom shadow
        if not decorFrame.botShadow then
            decorFrame.botShadow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        end
        decorFrame.botShadow:ClearAllPoints()
        decorFrame.botShadow:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 1, 0)
        decorFrame.botShadow:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -1, 0)
        decorFrame.botShadow:SetHeight(1)
        decorFrame.botShadow:SetColorTexture(0.04, 0.03, 0.01, 0.90)
        decorFrame.botShadow:Show()

        -- 3. Micro corner softening
        local cornerCuts = {
            { key = "cornerCutTL", point = "TOPLEFT",     x = 0, y = 0 },
            { key = "cornerCutTR", point = "TOPRIGHT",    x = 0, y = 0 },
            { key = "cornerCutBL", point = "BOTTOMLEFT",  x = 0, y = 0 },
            { key = "cornerCutBR", point = "BOTTOMRIGHT", x = 0, y = 0 },
        }
        for _, cc in ipairs(cornerCuts) do
            if not decorFrame[cc.key] then
                decorFrame[cc.key] = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
            end
            local cut = decorFrame[cc.key]
            cut:ClearAllPoints()
            cut:SetPoint(cc.point, backdrop, cc.point, cc.x, cc.y)
            cut:SetSize(1, 1)
            cut:SetColorTexture(0, 0, 0, 0.65)
            cut:Show()
        end

    elseif style == "glow" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION B: Recessed Amber Inner Glow & Shadow Vignette
        -- ═════════════════════════════════════════════════════════════════════
        -- 1. Top inner-glow (warm amber)
        if not decorFrame.topGlow then
            decorFrame.topGlow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.topGlow:ClearAllPoints()
        decorFrame.topGlow:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        decorFrame.topGlow:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", 0, 0)
        decorFrame.topGlow:SetHeight(2)
        decorFrame.topGlow:SetColorTexture(0.55, 0.38, 0.12, 0.60)
        decorFrame.topGlow:Show()

        -- 2. Bottom shadow (deep recessed well)
        if not decorFrame.botShadow then
            decorFrame.botShadow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.botShadow:ClearAllPoints()
        decorFrame.botShadow:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 0)
        decorFrame.botShadow:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        decorFrame.botShadow:SetHeight(2)
        decorFrame.botShadow:SetColorTexture(0.04, 0.03, 0.01, 0.70)
        decorFrame.botShadow:Show()

        -- 3. Left vignette
        if not decorFrame.leftGlow then
            decorFrame.leftGlow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.leftGlow:ClearAllPoints()
        decorFrame.leftGlow:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 0, -2)
        decorFrame.leftGlow:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 2)
        decorFrame.leftGlow:SetWidth(2)
        decorFrame.leftGlow:SetColorTexture(0.45, 0.30, 0.08, 0.45)
        decorFrame.leftGlow:Show()

        -- 4. Right vignette
        if not decorFrame.rightGlow then
            decorFrame.rightGlow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 1)
        end
        decorFrame.rightGlow:ClearAllPoints()
        decorFrame.rightGlow:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", 0, -2)
        decorFrame.rightGlow:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 2)
        decorFrame.rightGlow:SetWidth(2)
        decorFrame.rightGlow:SetColorTexture(0.45, 0.30, 0.08, 0.45)
        decorFrame.rightGlow:Show()

    elseif style == "heavy" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION C: Chiseled Heavy Bronze Frame & Corner Brackets
        -- ═════════════════════════════════════════════════════════════════════
        -- 1. Top specular highlight — bright burnished gold (#E8C060)
        if not decorFrame.topHL then
            decorFrame.topHL = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        end
        decorFrame.topHL:ClearAllPoints()
        decorFrame.topHL:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 0, 0)
        decorFrame.topHL:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", 0, 0)
        decorFrame.topHL:SetHeight(1)
        decorFrame.topHL:SetColorTexture(0.91, 0.75, 0.38, 0.95)
        decorFrame.topHL:Show()

        -- 2. Bottom cast shadow — deep bronze/black (#1E1008)
        if not decorFrame.botShadow then
            decorFrame.botShadow = decorFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        end
        decorFrame.botShadow:ClearAllPoints()
        decorFrame.botShadow:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 0)
        decorFrame.botShadow:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
        decorFrame.botShadow:SetHeight(1)
        decorFrame.botShadow:SetColorTexture(0.12, 0.08, 0.02, 0.95)
        decorFrame.botShadow:Show()

        -- 3. Corner brackets
        local cs = (bars_def[barType] and bars_def[barType].cornerSize) or 7
        local barHeight = backdrop:GetHeight()
        if barHeight and barHeight > 4 then
            cs = math.min(cs, math.floor(barHeight))
        elseif barHeight and barHeight > 0 and barHeight <= 4 then
            cs = math.max(3, math.floor(barHeight))
        end

        local corners = {
            { key = "cornerTL", atlas = "heavybronze-horz-cornerbracket-TL", point = "TOPLEFT",     x = 0, y = 0 },
            { key = "cornerTR", atlas = "heavybronze-horz-cornerbracket-TR", point = "TOPRIGHT",    x = 0, y = 0 },
            { key = "cornerBL", atlas = "heavybronze-horz-cornerbracket-BL", point = "BOTTOMLEFT",  x = 0, y = 0 },
            { key = "cornerBR", atlas = "heavybronze-horz-cornerbracket-BR", point = "BOTTOMRIGHT", x = 0, y = 0 },
        }

        local hasBrackets = sfui.theme.HasAtlas and sfui.theme.HasAtlas("heavybronze-horz-cornerbracket-TL")
        for _, c in ipairs(corners) do
            if not decorFrame[c.key] then
                decorFrame[c.key] = decorFrame:CreateTexture(nil, "OVERLAY", nil, 3)
            end
            local t = decorFrame[c.key]
            if hasBrackets and cs >= 4 then
                t:ClearAllPoints()
                t:SetPoint(c.point, backdrop, c.point, c.x, c.y)
                t:SetSize(cs, cs)
                t:SetAtlas(c.atlas, false)
                t:Show()
            else
                t:Hide()
            end
        end
    end
end

--- Apply themed decorations to a cast-bar (icon border, spark color).
--- Safe to call every time the cast bar is shown; only styles static elements.
--- @param bar Frame   the cast StatusBar (must have .IconFrame and/or .Spark)
function sfui.theme.ApplyCastBarDecoration(bar)
    if not bar then return end
    local activeID = sfui.theme.GetActiveThemeID()
    local theme    = registeredThemes[activeID] or registeredThemes.modern or {}
    local pal      = theme.colors or sfui.theme.GetPalette()
    local bars_def = theme.bars or {}
    local isCamelot = (activeID == "camelot")

    -- Style the icon frame border
    local iconFrame = bar.IconFrame
    if iconFrame and iconFrame.SetBackdrop then
        if isCamelot then
            local bc = (bars_def.castbar and bars_def.castbar.iconBorderColor) or { 0.50, 0.38, 0.18, 1.0 }
            iconFrame:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            iconFrame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        else
            iconFrame:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    -- Style the cast spark / leading pip
    local spark = bar.Spark
    if spark then
        if isCamelot then
            -- Warm gold radiant spark for Camelot
            local sc = (bars_def.castbar and bars_def.castbar.sparkColor) or { 1.0, 0.85, 0.55, 1.0 }
            spark:SetVertexColor(sc[1], sc[2], sc[3], sc[4] or 1.0)
        else
            spark:SetVertexColor(1, 1, 1, 0.9)
        end
    end
end

--- Register a bar (StatusBar + its .backdrop) with the theme engine.
--- The engine will call ApplyStatusBarStyle(bar, barType) on every theme switch.
--- @param bar Frame      the StatusBar that has a .backdrop field
--- @param barType string one of the bar type strings listed above
function sfui.theme.RegisterBar(bar, barType)
    if not bar or not barType then return end
    registered_bars[bar] = barType
    sfui.theme.ApplyStatusBarStyle(bar, barType)
end

-- ─── Window Registration API ──────────────────────────────────────────────────
function sfui.theme.RegisterWindow(frame, callback, options)
    if not frame then return end
    if not frame.sfuiLevelHookInstalled and frame.HookScript then
        frame.sfuiLevelHookInstalled = true
        frame:HookScript("OnShow", function(self)
            sfui.theme.ElevateWindowContents(self)
        end)
    end
    for _, item in ipairs(registered_windows) do
        if item.frame == frame then
            item.callback = callback or item.callback
            item.options = options or item.options
            sfui.theme.ApplyWindowStyle(frame, item.options)
            sfui.theme.ElevateWindowContents(frame)
            if item.callback then
                pcall(item.callback, frame, sfui.theme.GetPalette())
            end
            return
        end
    end
    table_insert(registered_windows, { frame = frame, callback = callback, options = options })
    sfui.theme.ApplyWindowStyle(frame, options)
    sfui.theme.ElevateWindowContents(frame)
    if callback then
        pcall(callback, frame, sfui.theme.GetPalette())
    end
end

function sfui.theme.UnregisterWindow(frame)
    if not frame then return end
    for i = #registered_windows, 1, -1 do
        if registered_windows[i].frame == frame then
            table_remove(registered_windows, i)
            break
        end
    end
end

-- ─── Master Live Theme Refresh ────────────────────────────────────────────────
function sfui.theme.ApplyCurrentTheme()
    local themeID = sfui.theme.GetActiveThemeID()
    local theme = registeredThemes[themeID] or registeredThemes.modern or {}
    local pal = theme.colors or sfui.theme.GetPalette()

    -- Sync global config appearance tokens
    sfui.config.appearance.highlightColor = pal.highlightColor
    sfui.config.appearance.accentColor    = pal.accentColor
    sfui.config.appearance.backdropColor  = pal.backdropColor
    sfui.config.appearance.borderColor    = pal.borderColor
    sfui.config.header_color              = { pal.headerColor[1], pal.headerColor[2], pal.headerColor[3] }

    -- Theme lifecycle hook if defined
    if theme.OnApply then
        pcall(theme.OnApply, theme)
    end

    -- 1. Re-style all registered windows
    for _, item in ipairs(registered_windows) do
        if item.frame then
            sfui.theme.ApplyWindowStyle(item.frame, item.options)
            sfui.theme.ElevateWindowContents(item.frame)
            if item.callback then
                pcall(item.callback, item.frame, pal)
            end
        end
    end

    -- 2. Re-style all active registered cards
    for card, depth in pairs(registered_cards) do
        if card then
            sfui.theme.ApplyCardStyle(card, depth)
        end
    end

    -- 3. Re-style all active registered headers
    for header, titleText in pairs(registered_headers) do
        if header then
            sfui.theme.ApplyQuestHeaderStyle(header)
            if type(titleText) == "string" and header.title then
                header.title:SetText(titleText)
            end
        end
    end

    -- 4. Re-style all active registered buttons
    for btn, isStyled in pairs(registered_buttons) do
        if btn then
            sfui.theme.ApplyButtonStyle(btn, isStyled)
        end
    end

    -- 4b. Re-style all active registered dropdown buttons
    for ddBtn, _ in pairs(registered_dropdowns) do
        if ddBtn then
            sfui.theme.ApplyDropdownStyle(ddBtn)
        end
    end

    -- 5. Re-style all active registered close buttons
    for btn, _ in pairs(registered_close_buttons) do
        if btn then
            sfui.theme.ApplyCloseButtonStyle(btn)
        end
    end

    -- 6. Re-style all active registered inputs
    for editBox, _ in pairs(registered_inputs) do
        if editBox then
            sfui.theme.ApplyInputStyle(editBox)
        end
    end

    -- 7. Re-style all active registered navigation tabs
    for tabBtn, isSelected in pairs(registered_tabs) do
        if tabBtn then
            sfui.theme.ApplyTabStyle(tabBtn, isSelected)
        end
    end

    -- 8. Refresh Minimap theme
    sfui.minimap.UpdateMinimapTheme()

    -- 9. Refresh quest trackers
    sfui.tracker.RequestRefresh(0.01)
    sfui.questlog.RequestRefresh()

    -- 10. Refresh loot feed theme
    sfui.lootfeed.UpdateTheme()

    -- 11. Refresh target frame theme (Classic/Camelot)
    if not sfui.isRetail and sfui.target.UpdateTheme then
        sfui.target.UpdateTheme()
    end

    -- 12. Broadcast message to any listening modules
    sfui.events.SendMessage("SFUI_THEME_CHANGED", pal.id, pal, theme)

    -- 13. Re-style all registered bars
    for bar, barType in pairs(registered_bars) do
        if bar then
            sfui.theme.ApplyStatusBarStyle(bar, barType)
        end
    end

    -- 14. Re-style all registered scrollbars
    for scrollBar in pairs(registered_scrollbars) do
        if scrollBar then
            sfui.theme.ApplyScrollBarStyle(scrollBar)
        end
    end
end

-- ─── Database Defaults ────────────────────────────────────────────────────────
sfui.db.RegisterDefaults("theme", {
    mode             = "auto",
    cornerBrackets   = true,
    texturedBackdrop = true,
    minimapArt       = true,
    barStyle         = "castbar",
})

-- Export public API alias
sfui.ApplyTheme = sfui.theme.ApplyCurrentTheme
