local addonName, addon = ...
sfui = sfui or {}
sfui.trackedicons = sfui.trackedicons or {}
sfui.trackedicons._aura = sfui.trackedicons._aura or {}

-- ══════════════════════════════════════════════════════════════════════════════
--  sfui/frames/tracking/icon_aura.lua
--  revision-gated aura duration, seal icon override, opt-in stack badge, and
--  missing-buff alert evaluation for tracked icons.
--
--  runs BEFORE icon_cooldown so active aura durations keep ownership of
--  `icon.cooldown` across SPELL_UPDATE_COOLDOWN / UNIT_POWER_UPDATE ticks
--  without re-resolving or clobbering the swipe, while handing off cleanly in
--  the same frame when an aura expires.
-- ══════════════════════════════════════════════════════════════════════════════

local IA = sfui.trackedicons._aura
local A = sfui.tracking and sfui.tracking.auras

local C_UnitAuras = C_UnitAuras
local C_Secrets = _G.C_Secrets
local GetTime = GetTime
local ipairs = ipairs
local type = type
local issecretvalue = sfui.common.issecretvalue

function IA.Clear(icon)
    icon._auraDurationObj = nil
    icon._auraIcon = nil
    icon._shownAuraTex = nil
    icon._auraStacks = nil
    icon._auraExpTime = nil
    icon._auraState = false
    icon._auraRev = (A and A.GetRevision and A.GetRevision()) or 0
    if icon._auraTextureShown then
        icon._auraTextureShown = nil
        if icon.texture and icon._currentTexture then
            icon.texture:SetTexture(icon._currentTexture)
        end
    end
end

function IA.Reset(icon)
    IA.Clear(icon)
    icon._auraState = nil
    icon._auraRev = nil
    icon._auraStackRev = nil
    icon._missingRev = nil
    icon._cachedAuraStacks = nil
    icon._cachedAuraMissing = nil
    icon._auraMissing = nil
end

-- returns true (missing), false (present), or nil (inconclusive while secret)
local function IsTrackedAuraMissing(desc)
    local activeID = desc.activeID
    if sfui.isEra and sfui.tracking and sfui.tracking.FindClassicAura then
        return sfui.tracking.FindClassicAura(activeID, false) == nil
    end

    if A and A.Resolve and desc.auraCandidates then
        local iid, aura, present = A.Resolve(desc.cooldownID, desc.auraCandidates)
        if present or aura or iid then
            return false
        end
    end

    if A and A.FindBlizzItem and desc.cooldownID then
        local blizz, isAuraViewer = A.FindBlizzItem(desc.cooldownID)
        if blizz then
            if sfui.common.HasAuraInstanceID(blizz.auraInstanceID) and blizz.auraDataUnit ~= "target" then
                return false
            end
            if isAuraViewer then
                return true
            end
        end
    end

    local getBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if getBySpellID then
        local checkSpellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
        if activeID and activeID ~= 0 and not (checkSpellSecret and checkSpellSecret(activeID)) then
            if getBySpellID(activeID) then
                return false
            end
        end
        local linked = desc.linkedSpellIDs
        if linked then
            for i = 1, #linked do
                local lid = linked[i]
                if lid and not (checkSpellSecret and checkSpellSecret(lid)) and getBySpellID(lid) then
                    return false
                end
            end
        end
    end

    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return nil
    end
    return true
end

-- resolves aura application display (>1 stacks only; never forwards raw secret 0/1)
local function ExtractSafeAuraStacks(desc, iid, aura)
    local rawApps = aura and aura.applications
    if rawApps ~= nil and not issecretvalue(rawApps) then
        if type(rawApps) == "number" and rawApps > 1 then
            return rawApps
        end
        return nil
    end

    -- In restricted combat, use Blizzard's untainted CDM Applications FontString (returns "" when <= 1)
    if A and A.FindBlizzItem and desc.cooldownID then
        local blizz = A.FindBlizzItem(desc.cooldownID)
        if blizz and blizz.GetApplicationsFontString then
            local fs = blizz:GetApplicationsFontString()
            local txt = fs and fs:GetText()
            if txt ~= nil then
                return txt
            end
        end
    end

    if iid and not issecretvalue(iid)
        and (not A or not A.CanAccessUnitAuras or A.CanAccessUnitAuras())
        and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        return C_UnitAuras.GetAuraApplicationDisplayCount("player", iid, 2)
    end

    return nil
end

local function ResolveOptInAuraStacks(desc)
    local activeID = desc.activeID
    if not activeID or activeID == 0 then return nil end

    local getBySpellID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local checkSpellSecret = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    local aura = nil

    if desc.isAuraType then
        if getBySpellID and not (checkSpellSecret and checkSpellSecret(activeID)) then
            aura = getBySpellID(activeID)
        end
        if not aura and sfui.isEra and sfui.tracking and sfui.tracking.FindClassicAura then
            aura = sfui.tracking.FindClassicAura(activeID, false)
        end
    end

    if not aura and desc.linkedSpellIDs and getBySpellID then
        for _, lid in ipairs(desc.linkedSpellIDs) do
            if lid and not (checkSpellSecret and checkSpellSecret(lid)) then
                local linkedAura = getBySpellID(lid)
                if linkedAura then
                    aura = linkedAura
                    break
                end
            end
        end
    end

    return ExtractSafeAuraStacks(desc, aura and aura.auraInstanceID, aura)
end

-- returns auraActive, auraStacks, missingAlert
function IA.Evaluate(icon, desc)
    if not A or (not desc.wantsAura and not desc.trackBuffs and not desc.glowWhenMissing) then
        if icon._auraState then
            IA.Clear(icon)
        end
        icon._cachedAuraStacks = nil
        icon._cachedAuraMissing = nil
        desc._rebuilt = false
        return false, nil, false
    end

    local rev = A.GetRevision()
    local rebuilt = (desc._rebuilt == true)

    -- 1. aura duration & dynamic seal icon override
    if desc.wantsAura then
        local expiredFallback = icon._auraState
            and icon._auraExpTime
            and icon._auraExpTime > 0
            and GetTime() >= icon._auraExpTime

        if rebuilt or icon._auraRev ~= rev or expiredFallback or icon._auraState == nil then
            icon._auraRev = rev
            local iid, aura, present = A.Resolve(desc.cooldownID, desc.auraCandidates)
            if aura or iid then
                local dObj = A.GetDuration(iid, aura) or icon._auraDurationObj
                icon._auraDurationObj = dObj

                local tex = A.PlainField(aura, "icon")
                if tex then
                    icon._auraIcon = tex
                end

                local exp = A.PlainField(aura, "expirationTime")
                icon._auraExpTime = (exp and exp > 0) and exp or nil

                icon._auraStacks = ExtractSafeAuraStacks(desc, iid, aura)
                icon._auraState = true

                if dObj and icon.cooldown.SetCooldownFromDurationObject then
                    if icon._chargeSwipeHidden then
                        icon._chargeSwipeHidden = nil
                        icon.cooldown:SetDrawSwipe(true)
                    end
                    icon.cooldown:SetCooldownFromDurationObject(dObj)
                end
                if icon._auraIcon and icon.texture and icon._shownAuraTex ~= icon._auraIcon then
                    icon.texture:SetTexture(icon._auraIcon)
                    icon._shownAuraTex = icon._auraIcon
                    icon._auraTextureShown = true
                end
            elseif present and not rebuilt and icon._auraState then
                -- aura up in restricted combat: keep existing duration object ticking
                icon._auraState = true
            else
                IA.Clear(icon)
            end
        end
    elseif icon._auraState then
        IA.Clear(icon)
    end

    local auraActive = (icon._auraState == true)

    -- 2. opt-in buff stack count (never scanned when trackBuffs is disabled)
    local auraStacks = auraActive and icon._auraStacks or nil
    if not auraStacks and desc.trackBuffs and (desc.isAuraType or desc.linkedSpellIDs) then
        if rebuilt or icon._auraStackRev ~= rev then
            icon._auraStackRev = rev
            icon._cachedAuraStacks = ResolveOptInAuraStacks(desc) or false
        end
        if icon._cachedAuraStacks then
            auraStacks = icon._cachedAuraStacks
        end
    end

    -- 3. missing-buff glow alert
    local missingAlert = false
    if desc.glowWhenMissing then
        if rebuilt or icon._missingRev ~= rev or icon._cachedAuraMissing == nil then
            icon._missingRev = rev
            local missing = IsTrackedAuraMissing(desc)
            if missing == nil then
                missing = icon._auraMissing or false
            end
            if missing and auraActive then
                missing = false
            end
            icon._cachedAuraMissing = missing
        end
        icon._auraMissing = icon._cachedAuraMissing
        missingAlert = (icon._cachedAuraMissing == true)
    end

    desc._rebuilt = false
    return auraActive, auraStacks, missingAlert
end

