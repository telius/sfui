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
    return true
end

-- ─── Active Theme Resolution & Setting ────────────────────────────────────────
function sfui.theme.GetActiveThemeID()
    if sfui.theme.forcedMode then
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
                return def.id
            end
        end
        -- Default fallbacks if no autoDetect claims it
        if sfui.isForever or (sfui.compat and sfui.compat.is_wow_forever) then
            return "camelot"
        end
        return "modern"
    end

    if registeredThemes[mode] then
        return mode
    end
    return "modern"
end

function sfui.theme.SetTheme(mode)
    mode = mode and mode:lower()
    if mode ~= "auto" and not registeredThemes[mode] then
        return false, "Unknown theme mode: " .. tostring(mode)
    end

    SfuiDB = SfuiDB or {}
    SfuiDB.themeMode = mode
    if SfuiDB.theme then
        SfuiDB.theme.mode = mode
    end
    if sfui.db and sfui.db.Set then
        sfui.db.Set("theme", "mode", mode)
    end

    sfui.theme.ApplyCurrentTheme()
    return true, mode
end

function sfui.theme.IsCamelotActive()
    return sfui.theme.GetActiveThemeID() == "camelot"
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
    local isSculptedWindow = (style == "bronze" or style == "heavy_bronze" or style == "metal_pieces")
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
    if not btn or btn.isCloseButton then return end
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
            if self.isCloseButton then return end
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
            if self.isCloseButton or self.isSelected or self.lockColor or self.customOnLeave then return end
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
    if not btn then return end
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

-- ─── Window Registration API ──────────────────────────────────────────────────
function sfui.theme.RegisterWindow(frame, callback, options)
    if not frame then return end
    for _, item in ipairs(registered_windows) do
        if item.frame == frame then
            item.callback = callback or item.callback
            item.options = options or item.options
            sfui.theme.ApplyWindowStyle(frame, item.options)
            if item.callback then
                pcall(item.callback, frame, sfui.theme.GetPalette())
            end
            return
        end
    end
    table_insert(registered_windows, { frame = frame, callback = callback, options = options })
    sfui.theme.ApplyWindowStyle(frame, options)
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
    if sfui.config and sfui.config.appearance then
        sfui.config.appearance.highlightColor = pal.highlightColor
        sfui.config.appearance.accentColor    = pal.accentColor
        sfui.config.appearance.backdropColor  = pal.backdropColor
        sfui.config.appearance.borderColor    = pal.borderColor
        sfui.config.header_color              = { pal.headerColor[1], pal.headerColor[2], pal.headerColor[3] }
    end

    -- Theme lifecycle hook if defined
    if theme.OnApply then
        pcall(theme.OnApply, theme)
    end

    -- 1. Re-style all registered windows
    for _, item in ipairs(registered_windows) do
        if item.frame then
            sfui.theme.ApplyWindowStyle(item.frame, item.options)
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
    if sfui.minimap and sfui.minimap.UpdateMinimapTheme then
        pcall(sfui.minimap.UpdateMinimapTheme)
    end

    -- 9. Refresh quest trackers if loaded
    if sfui.tracker and sfui.tracker.RequestRefresh then
        sfui.tracker.RequestRefresh(0.01)
    end
    if sfui.questlog and sfui.questlog.RequestRefresh then
        sfui.questlog.RequestRefresh()
    end

    -- 10. Broadcast message to any listening modules
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_THEME_CHANGED", pal.id, pal, theme)
    end
end

-- ─── Database Defaults ────────────────────────────────────────────────────────
if sfui.db and sfui.db.RegisterDefaults then
    sfui.db.RegisterDefaults("theme", {
        mode             = "auto",
        cornerBrackets   = true,
        texturedBackdrop = true,
        minimapArt       = true,
    })
end

-- Export public API alias
sfui.ApplyTheme = sfui.theme.ApplyCurrentTheme
