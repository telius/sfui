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
local registered_cards         = setmetatable({}, { __mode = "k" })
local registered_headers       = setmetatable({}, { __mode = "k" })
local registered_inputs        = setmetatable({}, { __mode = "k" })
local registered_tabs          = setmetatable({}, { __mode = "k" })
local registered_bars          = setmetatable({}, { __mode = "k" }) -- { [barObj] = barType }

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
    if sfui.isForever or (sfui.compat and sfui.compat.is_wow_forever) then
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

    local isCamelot = (activeID == "camelot")

    if isCamelot then
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            btn:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
            if btn.SetBackdropBorderColor then
                btn:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85)
            end
        end
        local fs = btn:GetFontString() or btn.text
        if fs then
            fs:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3], 1)
        end
    else
        if btn.SetBackdrop then
            btn:SetBackdrop({
                bgFile   = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeFile = (sfui.config and sfui.config.textures and sfui.config.textures.white) or "Interface\\Buttons\\WHITE8x8",
                edgeSize = mult,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 }
            })
        end
        if btn.SetBackdropColor then
            btn:SetBackdropColor(isStyled and 0.2 or 0, isStyled and 0.2 or 0, isStyled and 0.2 or 0, 1)
        end
        if btn.SetBackdropBorderColor then
            btn:SetBackdropBorderColor(0, 0, 0, 1)
        end
        local fs = btn:GetFontString() or btn.text
        if fs then
            fs:SetTextColor(1, 1, 1, 1)
        end
    end

    if not btn.sfuiThemeHooksInstalled then
        btn.sfuiThemeHooksInstalled = true
        btn:HookScript("OnEnter", function(self)
            if self.isCloseButton or self.isSubmenuButton or self.isDropdownButton or self.isDropdownOption then return end
            local p = sfui.theme.GetPalette()
            if sfui.theme.IsCamelotActive() then
                self:SetBackdropColor(0.22, 0.18, 0.12, 0.98)
                if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.85, 0.70, 0.35, 1.0) end
                local sfs = self:GetFontString() or self.text
                if sfs then sfs:SetTextColor(0.98, 0.92, 0.70, 1) end
            else
                local hl = p.highlightColor or { 0.4, 0, 1, 1 }
                self:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1)
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if self.isCloseButton or self.isSubmenuButton or self.isDropdownButton or self.isDropdownOption or self.isSelected or self.lockColor or self.customOnLeave then return end
            if self.menu and self.menu:IsShown() then return end
            local p = sfui.theme.GetPalette()
            if sfui.theme.IsCamelotActive() then
                self:SetBackdropColor(0.12, 0.10, 0.08, 0.95)
                if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.28, 0.22, 0.14, 0.85) end
                local sfs = self:GetFontString() or self.text
                if sfs then sfs:SetTextColor(p.tabNormal[1], p.tabNormal[2], p.tabNormal[3], 1) end
            else
                self:SetBackdropBorderColor(0, 0, 0, 1)
                local sfs = self:GetFontString() or self.text
                if sfs then sfs:SetTextColor(1, 1, 1, 1) end
            end
        end)
    end
end

function sfui.theme.RegisterButton(btn, isStyled)
    if not btn or btn.isCloseButton or btn.isSubmenuButton or btn.isDropdownButton or btn.isDropdownOption then return end
    btn.isStyledButton = isStyled or false
    registered_buttons[btn] = isStyled or false
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

-- 6. Navigation / Spec Tab Styling
function sfui.theme.ApplyTabStyle(btn, isSelected)
    if not btn then return end
    registered_tabs[btn] = isSelected or false
    local pal = sfui.theme.GetPalette()
    local fs = btn:GetFontString()

    if fs then
        if isSelected then
            fs:SetTextColor(pal.tabSelected[1], pal.tabSelected[2], pal.tabSelected[3], 1)
        else
            fs:SetTextColor(pal.tabNormal[1], pal.tabNormal[2], pal.tabNormal[3], 1)
        end
    end

    if btn.indicator then
        btn.indicator:SetColorTexture(pal.accentColor[1], pal.accentColor[2], pal.accentColor[3], 1)
        if isSelected then
            btn.indicator:Show()
        else
            btn.indicator:Hide()
        end
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
function sfui.theme.ApplyLootfeedRowStyle(row, color, quality)
    if not row then return end
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
            -- CAMELOT OPTION A: Sculpted Inset Card
            -- ─────────────────────────────────────────────────────────────────
            row.lootfeedStyle = "outfit_card"

            if row.SetBackdrop then
                row:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = mult,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                row:SetBackdropColor(pal.containerColor[1], pal.containerColor[2], pal.containerColor[3], 0.92)
                if row.SetBackdropBorderColor then
                    row:SetBackdropBorderColor(0.38, 0.28, 0.12, 0.85)
                end
            end

            if row.cardBg then
                row.cardBg:SetAtlas("UI-Character-Info-OutfitCard")
                row.cardBg:ClearAllPoints()
                row.cardBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 2)
                row.cardBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -2)
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

            -- Hide corner brackets in card mode
            if row.cornerTL then
                row.cornerTL:Hide()
                row.cornerTR:Hide()
                row.cornerBL:Hide()
                row.cornerBR:Hide()
            end
        else
            -- ─────────────────────────────────────────────────────────────────
            -- CAMELOT OPTION B: Architectural Slate & Sculpted Corner Brackets
            -- (Also serves as safe authentic fallback if card atlas is missing)
            -- ─────────────────────────────────────────────────────────────────
            row.lootfeedStyle = "architectural"

            if row.cardBg then row.cardBg:Hide() end
            if row.hoverOverlay then row.hoverOverlay:Hide() end

            if row.SetBackdrop then
                row:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = mult,
                    insets   = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                row:SetBackdropColor(pal.backdropColor[1], pal.backdropColor[2], pal.backdropColor[3], 0.94)
                if row.SetBackdropBorderColor then
                    row:SetBackdropBorderColor(0.38, 0.28, 0.12, 0.90)
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

                if sfui.theme.HasAtlas(tlAtlas) then
                    row.cornerTL:SetAtlas(tlAtlas, false)
                    row.cornerTL:ClearAllPoints()
                    row.cornerTL:SetPoint("TOPLEFT", row, "TOPLEFT", -1, 1)
                    row.cornerTL:SetSize(bSize, bSize)
                    row.cornerTL:Show()
                else row.cornerTL:Hide() end

                if sfui.theme.HasAtlas(trAtlas) then
                    row.cornerTR:SetAtlas(trAtlas, false)
                    row.cornerTR:ClearAllPoints()
                    row.cornerTR:SetPoint("TOPRIGHT", row, "TOPRIGHT", 1, 1)
                    row.cornerTR:SetSize(bSize, bSize)
                    row.cornerTR:Show()
                else row.cornerTR:Hide() end

                if sfui.theme.HasAtlas(blAtlas) then
                    row.cornerBL:SetAtlas(blAtlas, false)
                    row.cornerBL:ClearAllPoints()
                    row.cornerBL:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -1, -1)
                    row.cornerBL:SetSize(bSize, bSize)
                    row.cornerBL:Show()
                else row.cornerBL:Hide() end

                if sfui.theme.HasAtlas(brAtlas) then
                    row.cornerBR:SetAtlas(brAtlas, false)
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
        end

        -- Inlaid Enamel Quality Strip (Present in BOTH Camelot styles so loot rarity is unmistakable)
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

        if row.iconBorder then
            row.iconBorder:Hide()
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
            row:SetBackdropColor(0, 0, 0, 0.50)
            if row.SetBackdropBorderColor then
                row:SetBackdropBorderColor(0, 0, 0, 0.50)
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
    return isCamelot and "heavy" or "thin"
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
    return (activeID == "camelot") and "heavy" or "thin"
end

--- Set the bar style and refresh all registered bars
--- @param style string "thin" | "glow" | "heavy"
--- @return boolean, string?
function sfui.theme.SetBarStyle(style)
    if style ~= "thin" and style ~= "glow" and style ~= "heavy" then
        return false, "Invalid bar style. Valid styles: thin, glow, heavy"
    end
    SfuiDB = SfuiDB or {}
    SfuiDB.camelotBarStyle = style
    SfuiDB.themeBarStyle = style
    if SfuiDB.theme then
        SfuiDB.theme.barStyle = style
    end
    if sfui.config.theme then
        sfui.config.theme.barStyle = style
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
            elseif style == "glow" then
                -- Option B: Borderless recessed amber well
                backdrop:SetBackdropBorderColor(0, 0, 0, 0)
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
            backdrop._sfuiDecorFrame:Hide()
        end
        return
    end

    -- Apply / update decorative texture layers for Option B (glow) and Option C (heavy)
    local decorFrame = backdrop._sfuiDecorFrame
    if not isCamelot or style == "thin" then
        if decorFrame then
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

    if style == "glow" then
        -- ═════════════════════════════════════════════════════════════════════
        -- OPTION B: Recessed Amber Inner Glow & Shadow Vignette
        -- ═════════════════════════════════════════════════════════════════════
        if decorFrame.topHL then decorFrame.topHL:Hide() end
        if decorFrame.cornerTL then decorFrame.cornerTL:Hide() end
        if decorFrame.cornerTR then decorFrame.cornerTR:Hide() end
        if decorFrame.cornerBL then decorFrame.cornerBL:Hide() end
        if decorFrame.cornerBR then decorFrame.cornerBR:Hide() end

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
        if decorFrame.topGlow then decorFrame.topGlow:Hide() end
        if decorFrame.leftGlow then decorFrame.leftGlow:Hide() end
        if decorFrame.rightGlow then decorFrame.rightGlow:Hide() end

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
end

-- ─── Database Defaults ────────────────────────────────────────────────────────
sfui.db.RegisterDefaults("theme", {
    mode             = "auto",
    cornerBrackets   = true,
    texturedBackdrop = true,
    minimapArt       = true,
    barStyle         = "heavy",
})

-- Export public API alias
sfui.ApplyTheme = sfui.theme.ApplyCurrentTheme
