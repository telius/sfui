-- sfui Glow Module - LibCustomGlow-1.0 Integration
-- Based on ArcUI's pattern with alpha hooks for smooth transitions

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

if not LCG then
    -- Fallback: LibCustomGlow not available
    sfui.common.print("libcustomglow-1.0 not found, glow effects disabled")
    sfui.common.print("libstub available:", LibStub and "yes" or "no")

    -- Create stub module to prevent errors
    sfui.glows = {
        start_glow = function() end,
        stop_glow = function() end,
        set_glow_alpha = function() end
    }
    return
end


sfui.glows = {}

-- Helper: Get value from entry → panel → global → hardcoded default
local function GetValue(entrySettings, panelConfig, key, default)
    if entrySettings and entrySettings[key] ~= nil then return entrySettings[key] end
    if panelConfig and panelConfig[key] ~= nil then return panelConfig[key] end

    local globalCfg = SfuiDB and SfuiDB.iconGlobalSettings
    if globalCfg and globalCfg[key] ~= nil then return globalCfg[key] end

    local g = sfui.config
    local configDefault = g and g.icon_panel_global_defaults
    if configDefault and configDefault[key] ~= nil then return configDefault[key] end

    return default
end

local DEFAULT_GLOW_COLOR = { 1, 0.85, 0.1, 1 }

-- Shared resolver to ensure consistent visuals across active icons and global preview
function sfui.glows.resolve_config(entrySettings, panelConfig, targetTable)
    local cfg = targetTable or {}
    local defaults = sfui.config.icon_panel_global_defaults or {}

    cfg.glowType = GetValue(entrySettings, panelConfig, "glowType", "pixel")
    cfg.useSpecColor = GetValue(entrySettings, panelConfig, "useSpecColor", true)

    local color = GetValue(entrySettings, panelConfig, "glowColor", DEFAULT_GLOW_COLOR)
    if cfg.useSpecColor then
        color = sfui.common.get_spec_color_table()
    end
    cfg.glowColor = color

    cfg.glowScale = GetValue(entrySettings, panelConfig, "glowScale", defaults.glowScale or 1.0)
    cfg.glow_max_duration = GetValue(entrySettings, panelConfig, "glow_max_duration", defaults.glow_max_duration or 5.0)
    cfg.glowIntensity = GetValue(entrySettings, panelConfig, "glowIntensity", defaults.glowIntensity or 1.0)
    cfg.glowSpeed = GetValue(entrySettings, panelConfig, "glowSpeed", defaults.glowSpeed or 0.25)
    cfg.glowLines = GetValue(entrySettings, panelConfig, "glowLines", defaults.glowLines or 8)
    cfg.glowThickness = GetValue(entrySettings, panelConfig, "glowThickness", defaults.glowThickness or 2)
    cfg.glowParticles = GetValue(entrySettings, panelConfig, "glowParticles", defaults.glowParticles or 4)

    return cfg
end

-- Alpha hook system (prevents LCG from overriding our alpha)
local function HookGlowAlpha(glowFrame, parentIcon)
    if not glowFrame or glowFrame._sfuiAlphaHooked then return end

    -- Safely hook — LibCustomGlow internals may change between versions
    local ok = pcall(function()
        glowFrame._sfuiAlphaHooked = true

        local origSetAlpha = glowFrame.SetAlpha
        if not origSetAlpha then return end

        glowFrame.SetAlpha = function(self, alpha)
            local parent = self:GetParent()
            if parent and parent._sfuiForcedGlowAlpha then
                origSetAlpha(self, parent._sfuiForcedGlowAlpha)
            else
                origSetAlpha(self, alpha)
            end
        end
    end)

    if not ok then
        -- Silently fail — glow will work, just without alpha control
        glowFrame._sfuiAlphaHooked = false
    end
end

-- Start glow with specified configuration
function sfui.glows.start_glow(icon, config)
    if not icon or not config then
        sfui.common.print("start_glow called with nil icon or config")
        return
    end

    local glowType = config.glowType or "pixel"
    local color = config.glowColor or DEFAULT_GLOW_COLOR
    local r, g, b = sfui.common.unpack_color(color)
    local scale = config.glowScale or 1.0
    local speed = config.glowSpeed or 0.25
    local intensity = config.glowIntensity or 1.0
    local lines = config.glowLines or 8
    local particles = config.glowParticles or 4
    local thickness = config.glowThickness or 2
    local key = "sfui_ReadyGlow"

    -- Performance: Detect if we are already showing this EXACT glow without string formatting
    if icon._glowActive
        and icon._lastGlowType == glowType
        and icon._lastGlowR == r
        and icon._lastGlowG == g
        and icon._lastGlowB == b
        and icon._lastGlowScale == scale
        and icon._lastGlowSpeed == speed
        and icon._lastGlowIntensity == intensity
        and icon._lastGlowLines == lines
        and icon._lastGlowParticles == particles
        and icon._lastGlowThickness == thickness then
        return -- Already showing this exact glow, skip restart
    end

    -- Stop existing surgically
    sfui.glows.stop_glow(icon)

    -- Reuse per-icon color array for LCG (ButtonGlow retains reference on glow frame)
    local colorArray = icon._lcgColor
    if not colorArray then
        colorArray = { r, g, b, 1.0 }
        icon._lcgColor = colorArray
    else
        colorArray[1], colorArray[2], colorArray[3], colorArray[4] = r, g, b, 1.0
    end

    local success, err
    -- Start appropriate glow type
    if glowType == "pixel" then
        success, err = pcall(LCG.PixelGlow_Start,
            icon,
            colorArray,
            lines,
            speed,
            nil,  -- length (nil = default)
            thickness,
            0,    -- xOffset
            0,    -- yOffset
            true, -- border
            key
        )

        if not success then
            sfui.common.print("pixelglow_start failed:", err)
            return
        end

        local glow = icon["_PixelGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
            if scale ~= 1.0 then
                glow:SetScale(scale)
            end
        else
            sfui.common.print("pixelglow started but frame not found")
        end
    elseif glowType == "autocast" then
        success, err = pcall(LCG.AutoCastGlow_Start,
            icon,
            colorArray,
            particles,
            speed,
            scale,
            0, -- xOffset
            0, -- yOffset
            key
        )

        if not success then
            sfui.common.print("autocastglow_start failed:", err)
            return
        end

        local glow = icon["_AutoCastGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
        else
            sfui.common.print("autocastglow started but frame not found")
        end
    elseif glowType == "proc" then
        local procOpts = icon._lcgProcOpts
        if not procOpts then
            procOpts = {
                color = colorArray,
                startAnim = false,
                xOffset = 0,
                yOffset = 0,
                key = key,
            }
            icon._lcgProcOpts = procOpts
        else
            procOpts.color = colorArray
            procOpts.key = key
        end
        success, err = pcall(LCG.ProcGlow_Start, icon, procOpts)

        if not success then
            sfui.common.print("procglow_start failed:", err)
            return
        end

        local glow = icon["_ProcGlow" .. key]
        if glow then
            HookGlowAlpha(glow, icon)
            if scale ~= 1.0 then
                glow:SetScale(scale)
            end
            -- Fix initial state
            if glow.ProcStart then glow.ProcStart:Hide() end
            if glow.ProcLoop then
                glow.ProcLoop:Show()
                glow.ProcLoop:SetAlpha(intensity)
            end
        else
            sfui.common.print("procglow started but frame not found")
        end
    else -- "button" (default)
        success, err = pcall(LCG.ButtonGlow_Start, icon, colorArray, speed)

        if not success then
            sfui.common.print("buttonglow_start failed:", err)
            return
        end

        local glow = icon._ButtonGlow
        if glow then
            HookGlowAlpha(glow, icon)
            if scale ~= 1.0 then
                glow:SetScale(scale)
            end
        else
            sfui.common.print("buttonglow started but frame not found")
        end
    end

    icon._glowActive = true
    icon._lastGlowType = glowType
    icon._lastGlowR = r
    icon._lastGlowG = g
    icon._lastGlowB = b
    icon._lastGlowScale = scale
    icon._lastGlowSpeed = speed
    icon._lastGlowIntensity = intensity
    icon._lastGlowLines = lines
    icon._lastGlowParticles = particles
    icon._lastGlowThickness = thickness
    icon._sfuiForcedGlowAlpha = 1.0
end

-- Stop all glows on an icon
function sfui.glows.stop_glow(icon)
    if not icon then return end

    local key = "sfui_ReadyGlow"

    -- Stop all glow types (Surgical stop based on last state to prevent Blizzard Pool errors)
    local lastType = icon._lastGlowType
    if lastType == "pixel" then
        pcall(LCG.PixelGlow_Stop, icon, key)
    elseif lastType == "autocast" then
        pcall(LCG.AutoCastGlow_Stop, icon, key)
    elseif lastType == "proc" then
        pcall(LCG.ProcGlow_Stop, icon, key)
    elseif lastType == "button" then
        pcall(LCG.ButtonGlow_Stop, icon)
    else
        -- Fallback if type is unknown: stop all (pcall protected)
        pcall(LCG.PixelGlow_Stop, icon, key)
        pcall(LCG.AutoCastGlow_Stop, icon, key)
        pcall(LCG.ProcGlow_Stop, icon, key)
        pcall(LCG.ButtonGlow_Stop, icon)
    end

    icon._glowActive = false
    icon._lastGlowType = nil
    icon._lastGlowR = nil
    icon._lastGlowG = nil
    icon._lastGlowB = nil
    icon._lastGlowScale = nil
    icon._lastGlowSpeed = nil
    icon._lastGlowIntensity = nil
    icon._lastGlowLines = nil
    icon._lastGlowParticles = nil
    icon._lastGlowThickness = nil
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

local _glowsDebug = {}
function sfui.glows_debug_info()
    _glowsDebug.lcgAvailable = LCG ~= nil
    return _glowsDebug
end

if sfui.RegisterModule then
    sfui.glows = sfui.glows or {}
    sfui.glows.GetDebugInfo = sfui.glows_debug_info
    sfui.RegisterModule("glows", sfui.glows)
end
