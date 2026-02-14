-- sfui Glow Module - LibCustomGlow-1.0 Integration
-- Based on ArcUI's pattern with alpha hooks for smooth transitions

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

if not LCG then
    -- Fallback: LibCustomGlow not available
    print("|cff6600ffsfui|r: LibCustomGlow-1.0 not found, glow effects disabled")
    print("|cff6600ffsfui|r: LibStub available:", LibStub and "YES" or "NO")

    -- Create stub module to prevent errors
    sfui.glows = {
        start_glow = function() end,
        stop_glow = function() end,
        set_glow_alpha = function() end
    }
    return
end

print("|cff6600ffsfui|r: LibCustomGlow-1.0 loaded successfully")

sfui.glows = {}

-- Alpha hook system (prevents LCG from overriding our alpha)
local function HookGlowAlpha(glowFrame, parentIcon)
    if not glowFrame or glowFrame._sfuiAlphaHooked then return end
    glowFrame._sfuiAlphaHooked = true

    local origSetAlpha = glowFrame.SetAlpha
    glowFrame.SetAlpha = function(self, alpha)
        -- Look up parent dynamically (LCG reuses frames from pool)
        local parent = self:GetParent()
        if parent and parent._sfuiForcedGlowAlpha then
            origSetAlpha(self, parent._sfuiForcedGlowAlpha)
        else
            origSetAlpha(self, alpha)
        end
    end
end

-- Start glow with specified configuration
function sfui.glows.start_glow(icon, config)
    if not icon or not config then
        print("|cff6600ffsfui|r: start_glow called with nil icon or config")
        return
    end

    local glowType = config.glowType or "pixel"
    local color = config.glowColor or { r = 1, g = 0.85, b = 0.1 }
    local key = "sfui_ReadyGlow"

    -- Build color array for LCG
    local colorArray = { color.r, color.g, color.b, config.glowIntensity or 1.0 }

    -- Stop any existing glow first
    sfui.glows.stop_glow(icon)

    local success, err
    -- Start appropriate glow type
    if glowType == "pixel" then
        success, err = pcall(LCG.PixelGlow_Start,
            icon,
            colorArray,
            config.glowLines or 8,
            config.glowSpeed or 0.25,
            nil,  -- length (nil = default)
            config.glowThickness or 2,
            0,    -- xOffset
            0,    -- yOffset
            true, -- border
            key
        )

        if not success then
            print("|cff6600ffsfui|r: PixelGlow_Start failed:", err)
            return
        end

        local glow = icon["_PixelGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
            if config.glowScale and config.glowScale ~= 1.0 then
                pcall(glow.SetScale, glow, config.glowScale)
            end
        else
            print("|cff6600ffsfui|r: PixelGlow started but frame not found")
        end
    elseif glowType == "autocast" then
        success, err = pcall(LCG.AutoCastGlow_Start,
            icon,
            colorArray,
            config.glowParticles or 4,
            config.glowSpeed or 0.25,
            config.glowScale or 1.0,
            0, -- xOffset
            0, -- yOffset
            key
        )

        if not success then
            print("|cff6600ffsfui|r: AutoCastGlow_Start failed:", err)
            return
        end

        local glow = icon["_AutoCastGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
        else
            print("|cff6600ffsfui|r: AutoCastGlow started but frame not found")
        end
    elseif glowType == "proc" then
        success, err = pcall(LCG.ProcGlow_Start, icon, {
            color = colorArray,
            startAnim = false,
            xOffset = 0,
            yOffset = 0,
            key = key
        })

        if not success then
            print("|cff6600ffsfui|r: ProcGlow_Start failed:", err)
            return
        end

        local glow = icon["_ProcGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
            if config.glowScale and config.glowScale ~= 1.0 then
                pcall(glow.SetScale, glow, config.glowScale)
            end
            -- Fix initial state
            if glow.ProcStart then glow.ProcStart:Hide() end
            if glow.ProcLoop then
                glow.ProcLoop:Show()
                glow.ProcLoop:SetAlpha(config.glowIntensity or 1.0)
            end
        else
            print("|cff6600ffsfui|r: ProcGlow started but frame not found")
        end
    else -- "button" (default)
        success, err = pcall(LCG.ButtonGlow_Start, icon, colorArray, config.glowSpeed or 0.25)

        if not success then
            print("|cff6600ffsfui|r: ButtonGlow_Start failed:", err)
            return
        end

        local glow = icon._ButtonGlow
        if glow then
            HookGlowAlpha(glow, icon)
            if config.glowScale and config.glowScale ~= 1.0 then
                pcall(glow.SetScale, glow, config.glowScale)
            end
        else
            print("|cff6600ffsfui|r: ButtonGlow started but frame not found")
        end
    end

    icon._glowActive = true
    icon._lastGlowType = glowType
    icon._sfuiForcedGlowAlpha = 1.0
end

-- Stop all glows on an icon
function sfui.glows.stop_glow(icon)
    if not icon then return end

    local key = "sfui_ReadyGlow"

    -- Stop all glow types
    LCG.PixelGlow_Stop(icon, key)
    LCG.AutoCastGlow_Stop(icon, key)
    LCG.ProcGlow_Stop(icon, key)
    LCG.ButtonGlow_Stop(icon)

    icon._glowActive = false
    icon._lastGlowType = nil
    icon._sfuiForcedGlowAlpha = nil
end

-- Set glow alpha (for fading effects)
function sfui.glows.set_glow_alpha(icon, alpha)
    if not icon then return end

    icon._sfuiForcedGlowAlpha = alpha

    -- Find active glow frame and trigger alpha update
    local key = "sfui_ReadyGlow"
    local glowFrame = icon["_PixelGlow" .. key]
        or icon["_AutoCastGlow" .. key]
        or icon["_ProcGlow" .. key]
        or icon._ButtonGlow

    if glowFrame then
        glowFrame:SetAlpha(alpha)
    end
end
