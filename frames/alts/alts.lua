local addonName, addon = ...
---@diagnostic disable: undefined-global, undefined-field
sfui = sfui or {}
sfui.alts = sfui.alts or {}

local cfg = sfui.config.alts or {}

-- Localized APIs
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local UnitGUID = _G.UnitGUID
local UnitName = _G.UnitName
local UnitClass = _G.UnitClass
local UnitRace = _G.UnitRace
local UnitLevel = _G.UnitLevel
local GetAverageItemLevel = _G.GetAverageItemLevel
local GetServerTime = _G.GetServerTime
local GetMoney = _G.GetMoney
local table = _G.table
local math = _G.math
local wipe = _G.wipe
local C_Timer = _G.C_Timer
local unpack = _G.unpack or table.unpack
local tostring = _G.tostring
local tonumber = _G.tonumber
local string = _G.string
local ipairs = _G.ipairs
local pairs = _G.pairs
local type = _G.type
local GameTooltip = sfui.common.get_tooltip()
local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local CloseDropDownMenus = _G.CloseDropDownMenus
local GetGuildInfo = _G.GetGuildInfo
local RequestTimePlayed = _G.RequestTimePlayed
local GetRealmName = _G.GetRealmName or _G.GetNormalizedRealmName
local StaticPopupDialogs = _G.StaticPopupDialogs
local StaticPopup_Show = _G.StaticPopup_Show

-- Frame & Table Pooling
local columnPool = {}
local cellPool = {}
local tablePool = {}

local function AcquireTable()
    local t = table.remove(tablePool) or {}
    t.isDynamic = true
    return t
end

local function ReleaseTable(t)
    if not t then return end
    wipe(t)
    tablePool[#tablePool + 1] = t
end

local function ReleaseTableRecursive(t)
    if not t then return end
    for k, v in pairs(t) do
        if type(v) == "table" then
            ReleaseTableRecursive(v)
        end
    end
    ReleaseTable(t)
end

local function AcquireColumn(parent)
    local f = table.remove(columnPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
    else
        f:SetParent(parent)
        f:Show()
    end
    return f
end

local function ReleaseColumn(f)
    f:Hide()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    columnPool[#columnPool + 1] = f
end

local function AcquireCell(parent)
    local f = table.remove(cellPool)
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("CENTER")
        f.text:SetJustifyH("CENTER")
        f.text:SetWidth(0)
    else
        f:SetParent(parent)
        f:Show()
        if f.text then
            f.text:Show()
            f.text:ClearAllPoints()
            f.text:SetText("")
            f.text:SetTextColor(unpack(sfui.config.colors.white))
            f.text:SetFontObject("GameFontHighlightSmall")
            f.text:SetPoint("CENTER")
            f.text:SetJustifyH("CENTER")
            f.text:SetWidth(0)
            f.text:SetWordWrap(true)
        end
        if f.rightText then
            f.rightText:Hide()
            f.rightText:ClearAllPoints()
            f.rightText:SetText("")
            f.rightText:SetJustifyH("RIGHT")
            f.rightText:SetWidth(0)
        end
        local regions = { f:GetRegions() }
        for _, r in ipairs(regions) do
            if r ~= f.text and r ~= f.rightText then
                if r:IsObjectType("Texture") or r:IsObjectType("FontString") then
                    r:Hide()
                end
            end
        end
        local children = { f:GetChildren() }
        for _, c in ipairs(children) do
            c:Hide()
        end
    end
    return f
end

local function ReleaseCell(f)
    f:Hide()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    f:EnableMouse(false)
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:SetScript("OnMouseUp", nil)
    if f.text then
        f.text:ClearAllPoints()
        f.text:SetWidth(0)
        f.text:SetJustifyH("CENTER")
        f.text:SetText("")
    end
    if f.rightText then
        f.rightText:Hide()
        f.rightText:ClearAllPoints()
        f.rightText:SetWidth(0)
        f.rightText:SetText("")
    end
    if f.diamondIcon then
        f.diamondIcon:Hide()
    end
    cellPool[#cellPool + 1] = f
end

-- Expose pooling utilities to providers
sfui.alts.AcquireTable = AcquireTable
sfui.alts.ReleaseTable = ReleaseTable
sfui.alts.ReleaseTableRecursive = ReleaseTableRecursive
sfui.alts.AcquireCell = AcquireCell
sfui.alts.ReleaseCell = ReleaseCell
sfui.alts.AcquireColumn = AcquireColumn
sfui.alts.ReleaseColumn = ReleaseColumn

local function IsCamelotNameSystem()
    return sfui.isCamelot
        or (_G.RegionalUniqueNamesEnabled and _G.RegionalUniqueNamesEnabled())
        or (_G.NameUtil and _G.NameUtil.FormatUnitNameForDisplay ~= nil)
end

local function NormalizeRealmToken(s)
    if type(s) ~= "string" or s == "" then return "" end
    return s:gsub("[%s%-']", ""):lower()
end

local function IsServerRealmName(s)
    if type(s) ~= "string" or s == "" then return false end
    local norm = NormalizeRealmToken(s)
    if norm == "" then return false end
    if norm:find("^camwow") or norm:find("realm") or norm:find("%d") then
        return true
    end
    local r1 = _G.GetRealmName and _G.GetRealmName()
    if r1 and NormalizeRealmToken(r1) == norm then return true end
    local r2 = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
    if r2 and NormalizeRealmToken(r2) == norm then return true end
    local r3 = _G.GetCVar and _G.GetCVar("realmName")
    if r3 and NormalizeRealmToken(r3) == norm then return true end
    if norm == "forever" or norm == "camelot" or norm == "global" then
        return true
    end
    return false
end
sfui.alts.IsServerRealmName = IsServerRealmName

local function GetSurnameSeparator()
    return (_G.Constants and _G.Constants.CharacterNameSeparatorConsts and _G.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR) or " "
end

local function ResolveNameAndSurname(rawName, rawSecond, guid, isPlayer)
    local firstName = (type(rawName) == "string" and rawName ~= "") and rawName:gsub("^%s+", ""):gsub("%s+$", "") or nil
    local surname = (type(rawSecond) == "string" and rawSecond ~= "") and rawSecond:gsub("^%s+", ""):gsub("%s+$", "") or nil
    if firstName == "" then firstName = nil end
    if surname == "" then surname = nil end

    if not IsCamelotNameSystem() then
        return firstName, nil
    end

    if surname and surname:find("-", 1, true) then
        local sLeft, sRight = surname:match("^([^%-]+)%-(.+)$")
        if sLeft and sLeft ~= "" and (not sRight or IsServerRealmName(sRight)) then
            surname = sLeft:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    if surname and IsServerRealmName(surname) then
        surname = nil
    end

    -- Strip any accidental "-Realm" suffix or extract a hyphenated surname
    if firstName and firstName:find("-", 1, true) then
        local left, right = firstName:match("^([^%-]+)%-(.+)$")
        if left and left ~= "" then
            firstName = left:gsub("^%s+", ""):gsub("%s+$", "")
            if right and right ~= "" and not IsServerRealmName(right) and not surname then
                surname = right:gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
    end

    -- Split "First Last" if UnitName already returned a combined string
    local sep = GetSurnameSeparator()
    if firstName and sep ~= "" then
        local sIdx, eIdx = firstName:find(sep, 1, true)
        if sIdx and sIdx > 1 then
            local fPart = firstName:sub(1, sIdx - 1):gsub("^%s+", ""):gsub("%s+$", "")
            local sPart = firstName:sub(eIdx + 1):gsub("^%s+", ""):gsub("%s+$", "")
            if fPart ~= "" then
                firstName = fPart
                if sPart ~= "" and not IsServerRealmName(sPart) and (not surname or surname == "") then
                    surname = sPart
                end
            end
        end
    end

    -- Fallback 1: Live player query via UnitNameUnmodified / UnitName
    if (not surname or surname == "") and (isPlayer or (guid and UnitGUID and guid == UnitGUID("player"))) then
        if _G.UnitNameUnmodified then
            local uFirst, uSecond = _G.UnitNameUnmodified("player")
            if uSecond and uSecond ~= "" and not IsServerRealmName(uSecond) then
                surname = uSecond
                if not firstName or firstName == "" then firstName = uFirst end
            elseif uFirst and sep ~= "" and uFirst:find(sep, 1, true) then
                local sIdx, eIdx = uFirst:find(sep, 1, true)
                if sIdx and sIdx > 1 then
                    local sPart = uFirst:sub(eIdx + 1)
                    if sPart ~= "" and not IsServerRealmName(sPart) then
                        surname = sPart
                    end
                end
            end
        end
        if (not surname or surname == "") and UnitName then
            local uFirst, uSecond = UnitName("player")
            if uSecond and uSecond ~= "" and not IsServerRealmName(uSecond) then
                surname = uSecond
                if not firstName or firstName == "" then firstName = uFirst end
            elseif uFirst and sep ~= "" and uFirst:find(sep, 1, true) then
                local sIdx, eIdx = uFirst:find(sep, 1, true)
                if sIdx and sIdx > 1 then
                    local sPart = uFirst:sub(eIdx + 1)
                    if sPart ~= "" and not IsServerRealmName(sPart) then
                        surname = sPart
                    end
                end
            end
        end
    end

    -- Fallback 2: Client GUID cache via UnitNameFromGUID / GetPlayerInfoByGUID
    if (not surname or surname == "") and type(guid) == "string" and guid ~= "" then
        if _G.UnitNameFromGUID then
            local gFirst, gSecond = _G.UnitNameFromGUID(guid)
            if gSecond and gSecond ~= "" and not IsServerRealmName(gSecond) then
                surname = gSecond
                if not firstName or firstName == "" then firstName = gFirst end
            elseif gFirst and sep ~= "" and gFirst:find(sep, 1, true) then
                local sIdx, eIdx = gFirst:find(sep, 1, true)
                if sIdx and sIdx > 1 then
                    local fPart = gFirst:sub(1, sIdx - 1)
                    local sPart = gFirst:sub(eIdx + 1)
                    if not firstName or firstName == "" then firstName = fPart end
                    if sPart ~= "" and not IsServerRealmName(sPart) then
                        surname = sPart
                    end
                end
            end
        end
        if (not surname or surname == "") and _G.GetPlayerInfoByGUID then
            local _, _, _, _, _, pFirst, pSecond = _G.GetPlayerInfoByGUID(guid)
            if pSecond and pSecond ~= "" and not IsServerRealmName(pSecond) then
                surname = pSecond
                if not firstName or firstName == "" then firstName = pFirst end
            elseif pFirst and sep ~= "" and pFirst:find(sep, 1, true) then
                local sIdx, eIdx = pFirst:find(sep, 1, true)
                if sIdx and sIdx > 1 then
                    local sPart = pFirst:sub(eIdx + 1)
                    if sPart ~= "" and not IsServerRealmName(sPart) then
                        surname = sPart
                    end
                end
            end
        end
    end

    -- Fallback 3: Recover surname from synced peer roster (`SfuiDB.sync.peers`) if known
    if (not surname or surname == "") and firstName and SfuiDB and type(SfuiDB.sync) == "table" and type(SfuiDB.sync.peers) == "table" then
        local lowerFirst = firstName:lower()
        for _, p in pairs(SfuiDB.sync.peers) do
            if type(p) == "table" and type(p.name) == "string" then
                local pClean = p.name:match("^([^%-]+)") or p.name
                local sIdx, eIdx = pClean:find(sep, 1, true)
                if sIdx and sIdx > 1 then
                    local pf = pClean:sub(1, sIdx - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local ps = pClean:sub(eIdx + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    if ps ~= "" and not IsServerRealmName(ps) and ((guid and p.guid == guid) or pf:lower() == lowerFirst) then
                        surname = ps
                        break
                    end
                end
            end
        end
    end

    if surname and surname ~= "" and firstName and surname:lower() == firstName:lower() then
        surname = nil
    end

    return firstName, surname
end
sfui.alts.ResolveNameAndSurname = ResolveNameAndSurname

local function GetCurrentCharacterGUID()
    local guid = UnitGUID("player")
    if guid then return guid end
    local name, realm = UnitName("player")
    realm = (realm and realm ~= "") and realm or (GetRealmName and GetRealmName())
    if name and realm then
        return string.format("Player-%s-%s", realm, name)
    end
    return nil
end

-- Expose canonical GUID resolver so providers don't duplicate the logic
sfui.alts.GetCurrentCharacterGUID = GetCurrentCharacterGUID

local RULESET_ORDER = { "normal", "pvp", "rp", "rppvp" }
local RULESET_COLORS = {
    normal = "|cff88ccff",
    pvp    = "|cffff5555",
    rp     = "|cff66dd88",
    rppvp  = "|cffff9944",
}
local RULESET_RGB = {
    normal = { 0.53, 0.80, 1.00 },
    pvp    = { 1.00, 0.33, 0.33 },
    rp     = { 0.40, 0.87, 0.53 },
    rppvp  = { 1.00, 0.60, 0.27 },
}
sfui.alts.RULESETS = RULESET_ORDER
sfui.alts.RULESET_COLORS = RULESET_COLORS
sfui.alts.RULESET_RGB = RULESET_RGB

local function ParseCamelotRuleset(raw)
    if sfui.common and sfui.common.parse_camelot_ruleset then
        return sfui.common.parse_camelot_ruleset(raw)
    end
    if type(raw) ~= "string" or raw == "" then return nil end
    local low = raw:lower():gsub("[%s%-_]", "")
    if low == "normal" or low == "pve" then return "normal" end
    if low == "pvp" or low == "rp" or low == "rppvp" then return low end
    return nil
end

local function GetCurrentRuleset()
    if not IsCamelotNameSystem() then return nil end
    if sfui.common and sfui.common.get_camelot_ruleset then
        return sfui.common.get_camelot_ruleset()
    end
    local C_GR = _G.C_GameRules
    local GR = _G.Enum and _G.Enum.GameRule
    if C_GR and C_GR.IsGameRuleActive and GR then
        local isPvP = (GR.PvPRuleset ~= nil) and (C_GR.IsGameRuleActive(GR.PvPRuleset) == true) or false
        local isRP  = (GR.RPRuleset ~= nil) and (C_GR.IsGameRuleActive(GR.RPRuleset) == true) or false
        if isPvP and isRP then return "rppvp" end
        if isPvP then return "pvp" end
        if isRP then return "rp" end
        return "normal"
    end
    return ParseCamelotRuleset((_G.GetRealmName and _G.GetRealmName()) or "") or "normal"
end
sfui.alts.GetCurrentRuleset = GetCurrentRuleset

local SYNDICATOR_SUFFIXES = {
    { suffix = "-PvE",   ruleset = "normal" },
    { suffix = "-PvP",   ruleset = "pvp" },
    { suffix = "-RP",    ruleset = "rp" },
    { suffix = "-RPPvP", ruleset = "rppvp" },
}

local function InferRulesetFromSyndicator(altData, guid)
    if type(altData) ~= "table" or not altData.name or altData.name == "" then return nil end
    local syn = _G.SYNDICATOR_DATA
    local chars = type(syn) == "table" and syn.Characters
    if type(chars) ~= "table" then return nil end

    if type(guid) == "string" and guid ~= "" then
        for charKey, rec in pairs(chars) do
            if type(rec) == "table" and type(rec.details) == "table" and rec.details.guid == guid then
                local fromDetails = ParseCamelotRuleset(rec.details.realm)
                    or ParseCamelotRuleset(rec.details.realmNormalized)
                    or ParseCamelotRuleset(type(charKey) == "string" and charKey:match("%-(.+)$") or nil)
                if fromDetails then
                    return fromDetails
                end
            end
        end
    end

    local fullName = altData.name
    if altData.surname and altData.surname ~= "" and not IsServerRealmName(altData.surname) then
        local sep = GetSurnameSeparator()
        if not fullName:find(sep, 1, true) then
            fullName = fullName .. sep .. altData.surname
        end
    end

    local candidates = (fullName ~= altData.name) and { fullName, altData.name } or { fullName }
    for _, baseName in ipairs(candidates) do
        local matched = nil
        local count = 0
        for _, entry in ipairs(SYNDICATOR_SUFFIXES) do
            local rec = chars[baseName .. entry.suffix]
            if type(rec) == "table" then
                local detClass = type(rec.details) == "table" and rec.details.className
                if not altData.class or not detClass or detClass == altData.class then
                    matched = entry.ruleset
                    count = count + 1
                end
            end
        end
        if count == 1 then
            return matched
        end
    end
    return nil
end

local function InferRulesetFromSync(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local peers = SfuiDB and type(SfuiDB.sync) == "table" and SfuiDB.sync.peers
    local p = type(peers) == "table" and peers[guid]
    if type(p) ~= "table" then return nil end
    return ParseCamelotRuleset(p.ruleset) or ParseCamelotRuleset(p.realm)
end

local function GetAltRuleset(altData, guid)
    if not IsCamelotNameSystem() then return nil end
    local myGuid = GetCurrentCharacterGUID()
    if guid and myGuid and guid == myGuid then
        local cur = GetCurrentRuleset() or "normal"
        if type(altData) == "table" then
            altData.ruleset = cur
        end
        return cur
    end
    if type(altData) ~= "table" then
        return GetCurrentRuleset() or "normal"
    end
    local saved = ParseCamelotRuleset(altData.ruleset)
    if saved then
        if altData.ruleset ~= saved then
            altData.ruleset = saved
        end
        return saved
    end
    local fromSyn = InferRulesetFromSyndicator(altData, guid)
    if fromSyn then
        altData.ruleset = fromSyn
        return fromSyn
    end
    local fromSync = InferRulesetFromSync(guid)
    if fromSync then
        altData.ruleset = fromSync
        return fromSync
    end
    local fromRealm = ParseCamelotRuleset(altData.realm)
    if fromRealm then
        altData.ruleset = fromRealm
        return fromRealm
    end
    return "normal"
end
sfui.alts.GetAltRuleset = GetAltRuleset

local function IsSameRuleset(altData, guid, targetRuleset)
    if not IsCamelotNameSystem() then return true end
    local want = (targetRuleset and ParseCamelotRuleset(targetRuleset)) or GetCurrentRuleset() or "normal"
    return GetAltRuleset(altData, guid) == want
end
sfui.alts.IsSameRuleset = IsSameRuleset

local activeRulesetFilter = nil
local userChangedRulesetFilter = false

function sfui.alts.GetRulesetFilter()
    if not IsCamelotNameSystem() then return nil end
    if activeRulesetFilter == "all" then return "all" end
    local parsed = activeRulesetFilter and ParseCamelotRuleset(activeRulesetFilter)
    if parsed then return parsed end
    activeRulesetFilter = GetCurrentRuleset() or "normal"
    return activeRulesetFilter
end

function sfui.alts.SetRulesetFilter(filterKey, isAuto)
    if not IsCamelotNameSystem() then return end
    if filterKey == "all" then
        activeRulesetFilter = "all"
    else
        activeRulesetFilter = ParseCamelotRuleset(filterKey) or GetCurrentRuleset() or "normal"
    end
    if not isAuto then
        userChangedRulesetFilter = true
    end
    if sfui.alts.UpdateUI then
        sfui.alts.UpdateUI(true)
    end
    if sfui.alts.RefreshSettingsPanel then
        sfui.alts.RefreshSettingsPanel()
    end
end

local function RepairAltEntry(altData, guid, isPlayer)
    if type(altData) ~= "table" then return end
    if not IsCamelotNameSystem() then return end

    if altData.surname then
        if IsServerRealmName(altData.surname) or ParseCamelotRuleset(altData.surname) then
            altData.surname = nil
        end
    end
    if (not altData.surname or altData.surname == "") and altData.realm and altData.realm ~= "" and not IsServerRealmName(altData.realm) then
        local realmAsRuleset = ParseCamelotRuleset(altData.realm)
        if realmAsRuleset then
            altData.ruleset = altData.ruleset or realmAsRuleset
        else
            altData.surname = altData.realm
        end
    end

    local fName, sName = ResolveNameAndSurname(altData.name, altData.surname, guid, isPlayer)
    if fName and fName ~= "" then
        altData.name = fName
    end
    if sName and sName ~= "" and not IsServerRealmName(sName) and not ParseCamelotRuleset(sName) then
        altData.surname = sName
    end

    if isPlayer then
        local currentRealm = (_G.GetRealmName and _G.GetRealmName()) or ""
        if currentRealm ~= "" then
            altData.realm = currentRealm
        end
        local currentRuleset = GetCurrentRuleset()
        if currentRuleset then
            altData.ruleset = currentRuleset
        end
    elseif not altData.ruleset then
        local inferred = InferRulesetFromSyndicator(altData, guid)
            or InferRulesetFromSync(guid)
            or ParseCamelotRuleset(altData.realm)
        if inferred then
            altData.ruleset = inferred
        end
    end
end
sfui.alts.RepairAltEntry = RepairAltEntry

--- Get display name for an alt, incorporating surname on Camelot/Forever
--- @param altData table
--- @param guid string?
--- @return string displayName
function sfui.alts.GetDisplayName(altData, guid)
    if not altData then return "Unknown" end
    if type(altData) == "table" then
        RepairAltEntry(altData, guid)
    end
    local firstName = altData.name or "Unknown"
    local surname = altData.surname
    if surname and surname ~= "" and not IsServerRealmName(surname) then
        local sep = GetSurnameSeparator()
        if firstName:find(sep, 1, true) then
            return firstName
        end
        local NameUtil = _G.NameUtil
        if NameUtil and NameUtil.GetFullNameWithoutRealm then
            local fn = NameUtil.GetFullNameWithoutRealm(firstName, surname)
            if fn and fn ~= "" then return fn end
        end
        return string.format("%s%s%s", firstName, sep, surname)
    end
    return firstName
end
sfui.common.get_alt_display_name = sfui.alts.GetDisplayName

--- Get valid mail recipient string for an alt (First Last on Forever; name or name-realm on Retail)
--- @param altData table
--- @param guid string?
--- @return string recipient
function sfui.alts.GetMailRecipient(altData, guid)
    if not altData then return "" end
    if type(altData) == "table" then
        RepairAltEntry(altData, guid)
    end
    local name = sfui.alts.GetDisplayName(altData, guid)
    if name == "Unknown" then
        name = altData.name or ""
    end
    if IsCamelotNameSystem() then
        return name
    end
    local myRealm = (GetRealmName and GetRealmName()) or ""
    local myNormRealm = NormalizeRealmToken(myRealm)
    local targetRealm = (altData.realm or ""):gsub("%s+", "")
    if targetRealm ~= "" and NormalizeRealmToken(targetRealm) ~= myNormRealm then
        return string.format("%s-%s", name, targetRealm)
    end
    return name
end
sfui.common.get_alt_mail_recipient = sfui.alts.GetMailRecipient

-- Provider Architecture
sfui.alts.provider = nil
function sfui.alts.RegisterProvider(provider)
    sfui.alts.provider = provider
    if sfui.alts.provider and sfui.alts.provider.RegisterEvents and sfui.alts._initialized then
        sfui.alts.provider.RegisterEvents()
    end
end

local DEFAULT_CATEGORIES = {
    { name = "GENERAL",   label = "Character",    type = "header" },
    { name = "ILVL",      label = "Level / iLvl", type = "stat",   key = "iLvl", format = "%.1f" },
}

local function GetCategories()
    if sfui.alts.provider and sfui.alts.provider.GetCategories then
        return sfui.alts.provider.GetCategories() or DEFAULT_CATEGORIES
    end
    return DEFAULT_CATEGORIES
end

function sfui.alts.RefreshDynamicCategories(force)
    if sfui.alts.provider and sfui.alts.provider.RefreshDynamicCategories then
        sfui.alts.provider.RefreshDynamicCategories(force)
    end
end

local syncTimer = nil
local needsSync = true
local leavingWorld = false

function sfui.alts.SyncCurrentCharacter()
    if syncTimer then return end
    needsSync = true
    syncTimer = C_Timer.NewTimer(1.0, function()
        syncTimer = nil
        if not needsSync then return end
        needsSync = false
        sfui.alts.PerformSync()
        sfui.alts.UpdateUI()
    end)
end

function sfui.alts.CheckWeeklyResets()
    if sfui.alts.provider and sfui.alts.provider.CheckWeeklyResets then
        return sfui.alts.provider.CheckWeeklyResets()
    end
    return nil
end

function sfui.alts.PerformSync(isLogout)
    if not isLogout and leavingWorld then return end

    if syncTimer then
        syncTimer:Cancel()
        syncTimer = nil
    end

    local guid = GetCurrentCharacterGUID()
    if not guid then return end

    local name, arg2 = UnitName("player")
    if not name or name == "Unknown" then return end

    SfuiDB.alts = SfuiDB.alts or {}
    local d = SfuiDB.alts[guid] or {}

    if IsCamelotNameSystem() then
        local fName, sName = ResolveNameAndSurname(name, arg2, guid, true)
        d.name = fName or name
        if sName and sName ~= "" and not IsServerRealmName(sName) and not ParseCamelotRuleset(sName) then
            d.surname = sName
        elseif d.surname and (IsServerRealmName(d.surname) or ParseCamelotRuleset(d.surname)) then
            d.surname = nil
        end
        d.realm = (_G.GetRealmName and _G.GetRealmName()) or ""
        local curRuleset = GetCurrentRuleset()
        if curRuleset then
            d.ruleset = curRuleset
            if not userChangedRulesetFilter then
                activeRulesetFilter = curRuleset
            end
        end

        -- Repair all existing alt entries (scrub server names from surname & recover surnames by GUID)
        for altGuid, alt in pairs(SfuiDB.alts) do
            if type(alt) == "table" then
                RepairAltEntry(alt, altGuid, altGuid == guid)
            end
        end
    else
        d.name = name
        local r = (arg2 and arg2 ~= "") and arg2 or (GetRealmName and GetRealmName())
        if r and r ~= "" then
            d.realm = r
        end
    end
    local englishClass = sfui.common.get_player_class()
    if englishClass and englishClass ~= "" then
        d.class = englishClass
    end
    if sfui.talents and sfui.talents.get_current_spec_id then
        local curSpecID = sfui.talents.get_current_spec_id()
        if curSpecID and curSpecID > 0 then
            d.spec = curSpecID
        end
    end
    local _, englishRace = UnitRace("player")
    if englishRace and englishRace ~= "" then
        d.race = englishRace
    end
    local curLevel = UnitLevel("player")
    if curLevel and curLevel > 0 then
        d.level = curLevel
    end
    local curMoney = GetMoney and GetMoney()
    if curMoney and curMoney >= 0 then
        if not ((isLogout or leavingWorld) and curMoney == 0 and (d.money or 0) > 0) then
            d.money = curMoney
        end
    end
    local now = (GetServerTime and GetServerTime()) or time()
    d.lastUpdate = now
    d.lastSeen = now

    if GetGuildInfo then
        local g = GetGuildInfo("player")
        if g and g ~= "" then
            d.guild = g
        end
    end

    if GetAverageItemLevel then
        local avg, avgEquipped = GetAverageItemLevel()
        local curIlvl = (avgEquipped and avgEquipped > 0 and avgEquipped) or (avg and avg > 0 and avg)
        if curIlvl and curIlvl > 0 then
            d.iLvl = curIlvl
        end
    end

    -- Persist lightweight bag item counts for Warband / Alt reagent & tooltip summaries
    if sfui.inventory and sfui.inventory.GetAllBagCounts then
        local liveBags = sfui.inventory.GetAllBagCounts()
        if liveBags then
            local savedBags = d.bagItems or {}
            wipe(savedBags)
            for itemID, cnt in pairs(liveBags) do
                if type(itemID) == "number" and type(cnt) == "number" and cnt > 0 then
                    savedBags[itemID] = cnt
                end
            end
            d.bagItems = savedBags
        end
    end

    -- Hook into client provider for flavor-specific data sync
    if sfui.alts.provider and sfui.alts.provider.PerformSync then
        sfui.alts.provider.PerformSync(d, isLogout)
    end

    if SfuiDB.sync and SfuiDB.sync.accountLabel and SfuiDB.sync.accountLabel ~= "" then
        d.accountLabel = SfuiDB.sync.accountLabel
    end

    SfuiDB.alts[guid] = d
    if sfui.events and sfui.events.SendMessage then
        sfui.events.SendMessage("SFUI_ALT_SYNCED", guid, isLogout)
    end
end

-- UI Implementation
local frame = nil
local settingsPanel = nil
local sortButtons = {}
local sectionCheckboxes = {}
local charRows = {}

local function updateSettingsPosition()
    if not settingsPanel or not frame then return end
    settingsPanel:ClearAllPoints()
    local frameRight = frame:GetRight() or 0
    local screenWidth = UIParent:GetWidth() or 1920
    if (frameRight + 260) > screenWidth then
        settingsPanel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -4, 0)
        settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -4, 0)
    else
        settingsPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 4, 0)
        settingsPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 4, 0)
    end
end
sfui.alts.UpdateSettingsPosition = updateSettingsPosition

local function RefreshSettingsPanel()
    if not settingsPanel or not settingsPanel:IsShown() then return end

    -- 1. Refresh Sort button highlights
    local curSort = SfuiDB.altsSort or "name"
    local hl = (sfui.config and sfui.config.appearance and sfui.config.appearance.highlightColor) or { 0.4, 0, 1, 1 }
    for _, sBtn in ipairs(sortButtons) do
        if sBtn.sortKey == curSort then
            sBtn:SetBackdropColor(hl[1], hl[2], hl[3], 0.8)
            if sBtn.SetBackdropBorderColor then sBtn:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1) end
        else
            sBtn:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
            if sBtn.SetBackdropBorderColor then sBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 1) end
        end
    end

    -- 2. Refresh Sections checkboxes
    local cats = GetCategories()
    local secY = 0
    local secIdx = 1

    local function setupSecCb(label, isChecked, onToggle)
        local cb = sectionCheckboxes[secIdx]
        if not cb then
            cb = sfui.common.create_checkbox(settingsPanel.sectionsContainer, label, nil, nil)
            sectionCheckboxes[secIdx] = cb
        end
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", 0, -secY)
        if cb.text then cb.text:SetText(label) end
        cb:SetChecked(isChecked)
        cb:SetScript("OnClick", function(self)
            onToggle(self:GetChecked())
        end)
        cb:Show()
        secY = secY + 22
        secIdx = secIdx + 1
    end

    for _, cat in ipairs(cats) do
        if cat.type == "header" and cat.name ~= "GENERAL" then
            local isHidden = SfuiDB.altsHiddenSections and (SfuiDB.altsHiddenSections[cat.name] == true)
            local catName = cat.name
            setupSecCb(cat.label, not isHidden, function(checked)
                SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
                SfuiDB.altsHiddenSections[catName] = not checked
                sfui.alts.UpdateUI(true)
            end)
        end
    end

    if sfui.alts.provider and sfui.alts.provider.name == "standard" then
        local isM0Hidden = (SfuiDB.showM0Dungeons == false)
        setupSecCb("m0 dungeons", not isM0Hidden, function(checked)
            SfuiDB.showM0Dungeons = checked
            sfui.alts.RefreshDynamicCategories(true)
            sfui.alts.UpdateUI(true)
        end)
    end

    for i = secIdx, #sectionCheckboxes do
        sectionCheckboxes[i]:Hide()
    end

    settingsPanel.sectionsContainer:SetHeight(math.max(1, secY))

    -- 3. Position and layout Characters
    settingsPanel.charHeader:ClearAllPoints()
    settingsPanel.charHeader:SetPoint("TOPLEFT", settingsPanel.sectionsContainer, "BOTTOMLEFT", 0, -14)

    local isCamelot = IsCamelotNameSystem()
    settingsPanel.charHeader:SetText(isCamelot and "characters (all rulesets)" or "characters")

    settingsPanel.charScroll:ClearAllPoints()
    settingsPanel.charScroll:SetPoint("TOPLEFT", settingsPanel.charHeader, "BOTTOMLEFT", 0, -6)
    settingsPanel.charScroll:SetPoint("BOTTOMRIGHT", -10, 10)

    local myGuid = GetCurrentCharacterGUID()
    local chars = {}
    for guid, data in pairs(SfuiDB.alts or {}) do
        if type(data) == "table" then
            chars[#chars + 1] = { guid = guid, data = data }
        end
    end
    table.sort(chars, function(a, b)
        local nA = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(a.data, a.guid)) or a.data.name or ""
        local nB = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(b.data, b.guid)) or b.data.name or ""
        return nA < nB
    end)

    local charY = 0
    for i, cInfo in ipairs(chars) do
        local row = charRows[i]
        if not row then
            row = CreateFrame("Frame", nil, settingsPanel.charContent)
            row:SetHeight(22)

            local del = sfui.common.create_flat_button(row, "x", 18, 16)
            del:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            local delFs = del:GetFontString()
            if delFs then delFs:SetTextColor(1, 0.3, 0.3, 1) end
            del.tooltip = "remove character"
            row.del = del

            local rsBtn = sfui.common.create_flat_button(row, "normal", 46, 16)
            rsBtn:SetPoint("RIGHT", del, "LEFT", -3, 0)
            row.rsBtn = rsBtn

            local cb = sfui.common.create_checkbox(row, "", nil, nil)
            cb:SetPoint("LEFT", 0, 0)
            if cb.text then
                cb.text:SetPoint("RIGHT", del, "LEFT", -4, 0)
                cb.text:SetWordWrap(false)
                cb.text:SetJustifyH("LEFT")
            end
            row.cb = cb

            charRows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -charY)
        row:SetPoint("RIGHT", settingsPanel.charContent, "RIGHT", 0, 0)

        local d = cInfo.data
        local classColor = RAID_CLASS_COLORS[d.class] or NORMAL_FONT_COLOR
        local colorStr = classColor and classColor.colorStr or "ffffffff"
        local name = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(d, cInfo.guid)) or d.name or "Unknown"

        if isCamelot and row.rsBtn then
            local altRs = GetAltRuleset(d, cInfo.guid) or "normal"
            local rgb = RULESET_RGB[altRs] or RULESET_RGB.normal
            row.rsBtn:SetText(altRs)
            local rsFs = row.rsBtn:GetFontString()
            if rsFs then
                rsFs:SetTextColor(rgb[1], rgb[2], rgb[3], 1)
            end
            local isLivePlayer = (myGuid and cInfo.guid == myGuid)
            if isLivePlayer then
                row.rsBtn.tooltip = "active character ruleset (detected from server)"
                row.rsBtn:SetScript("OnClick", nil)
            else
                row.rsBtn.tooltip = "click to cycle character ruleset (normal / pvp / rp / rppvp)"
                row.rsBtn:SetScript("OnClick", function()
                    local cur = GetAltRuleset(d, cInfo.guid) or "normal"
                    local nextRs = "normal"
                    for idx, key in ipairs(RULESET_ORDER) do
                        if key == cur then
                            nextRs = RULESET_ORDER[(idx % #RULESET_ORDER) + 1]
                            break
                        end
                    end
                    d.ruleset = nextRs
                    sfui.alts.UpdateUI(true)
                    RefreshSettingsPanel()
                end)
            end
            row.rsBtn:Show()
            if row.cb.text then
                row.cb.text:SetPoint("RIGHT", row.rsBtn, "LEFT", -4, 0)
            end
        else
            if row.rsBtn then row.rsBtn:Hide() end
            if row.cb.text then
                row.cb.text:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
            end
        end

        if row.cb.text then
            row.cb.text:SetText(string.format("|c%s%s|r", colorStr, name))
        end
        row.cb:SetChecked(not d.isHidden)
        row.cb:SetScript("OnClick", function(self)
            d.isHidden = not self:GetChecked()
            sfui.alts.UpdateUI(true)
        end)

        local capturedGuid = cInfo.guid
        local capturedName = name
        row.del:SetScript("OnClick", function()
            if StaticPopup_Show then
                StaticPopup_Show("SFUI_ALTS_REMOVE_CHARACTER", capturedName, nil, { guid = capturedGuid })
            else
                sfui.alts.PurgeCharacter(capturedGuid)
                sfui.alts.UpdateUI(true)
                RefreshSettingsPanel()
            end
        end)

        row:Show()
        charY = charY + 22
    end

    for i = #chars + 1, #charRows do
        charRows[i]:Hide()
    end

    settingsPanel.charContent:SetHeight(math.max(1, charY))
end
sfui.alts.RefreshSettingsPanel = RefreshSettingsPanel

local function CreateSettingsPanel()
    if settingsPanel then return settingsPanel end

    settingsPanel = CreateFrame("Frame", "SfuiAltsSettingsPanel", frame, "BackdropTemplate")
    settingsPanel:SetFrameStrata("DIALOG")
    settingsPanel:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)
    settingsPanel:SetWidth(260)
    settingsPanel:EnableMouse(true)

    local headerFrame = CreateFrame("Frame", nil, settingsPanel)
    headerFrame:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", settingsPanel, "TOPRIGHT", 0, 0)
    headerFrame:SetHeight(30)
    headerFrame:SetFrameLevel((settingsPanel:GetFrameLevel() or 1) + 15)
    headerFrame:EnableMouse(false)
    settingsPanel.headerFrame = headerFrame

    sfui.theme.ApplyWindowStyle(settingsPanel)
    sfui.theme.RegisterWindow(settingsPanel)

    local pClose = sfui.common.create_close_button(settingsPanel, function()
        settingsPanel:Hide()
    end, 20)
    pClose:ClearAllPoints()
    pClose:SetPoint("TOPRIGHT", -6, -6)
    pClose:SetFrameLevel((settingsPanel:GetFrameLevel() or 1) + 20)
    pClose.tooltip = "close settings"
    settingsPanel.closeBtn = pClose

    -- Title
    local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("alts configuration")
    title:SetTextColor(unpack((sfui.config and sfui.config.appearance and sfui.config.appearance.highlightColor) or { 0.4, 0, 1, 1 }))

    -- 1. SORT BY
    local sortHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sortHeader:SetPoint("TOPLEFT", 12, -36)
    sortHeader:SetText("sort by")
    sortHeader:SetTextColor(1, 0.82, 0)

    local sortDefs = {
        { label = "name", key = "name", width = 74 },
        { label = "ilvl", key = "ilvl", width = 74 },
        { label = "time", key = "timeplayed", width = 80 },
    }
    local prevSortBtn = nil
    for _, sDef in ipairs(sortDefs) do
        local sBtn = sfui.common.create_flat_button(settingsPanel, sDef.label, sDef.width, 20)
        sBtn.sortKey = sDef.key
        if not prevSortBtn then
            sBtn:SetPoint("TOPLEFT", 12, -54)
        else
            sBtn:SetPoint("LEFT", prevSortBtn, "RIGHT", 4, 0)
        end
        sBtn:SetScript("OnClick", function()
            SfuiDB.altsSort = sDef.key
            sfui.alts.UpdateUI(true)
            if sfui.alts.RefreshSettingsPanel then
                sfui.alts.RefreshSettingsPanel()
            end
        end)
        sortButtons[#sortButtons + 1] = sBtn
        prevSortBtn = sBtn
    end

    -- 2. SECTIONS
    local secHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    secHeader:SetPoint("TOPLEFT", 12, -84)
    secHeader:SetText("sections")
    secHeader:SetTextColor(1, 0.82, 0)

    local sectionsContainer = CreateFrame("Frame", nil, settingsPanel)
    sectionsContainer:SetPoint("TOPLEFT", 12, -102)
    sectionsContainer:SetPoint("RIGHT", -12, 0)
    sectionsContainer:SetHeight(1)
    settingsPanel.sectionsContainer = sectionsContainer

    -- 3. CHARACTERS
    local charHeader = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charHeader:SetText("characters")
    charHeader:SetTextColor(1, 0.82, 0)
    settingsPanel.charHeader = charHeader

    local charScroll = CreateFrame("ScrollFrame", nil, settingsPanel)
    charScroll:EnableMouseWheel(true)
    charScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - (delta * 22))))
    end)
    settingsPanel.charScroll = charScroll

    local charContent = CreateFrame("Frame", nil, charScroll)
    charContent:SetSize(236, 1)
    charScroll:SetScrollChild(charContent)
    settingsPanel.charContent = charContent

    settingsPanel:Hide()
    return settingsPanel
end

--- Purge a character and all associated recipe, craft, fishing, mail, and sync data by GUID
--- @param guid string
function sfui.alts.PurgeCharacter(guid)
    if not guid or not SfuiDB then return end

    local altData = SfuiDB.alts and SfuiDB.alts[guid]
    local charName = altData and altData.name
    local charRealm = altData and altData.realm

    -- 1. Alts record (includes active/completed quests, professions, currencies, vault)
    if SfuiDB.alts then
        SfuiDB.alts[guid] = nil
    end

    -- 2. Known recipes matrix (`SfuiDB.recipes[id][realm][guid]`)
    local recipesChanged = false
    if type(SfuiDB.recipes) == "table" then
        for id, realmMap in pairs(SfuiDB.recipes) do
            if type(realmMap) == "table" then
                for rKey, guidMap in pairs(realmMap) do
                    if type(guidMap) == "table" and guidMap[guid] ~= nil then
                        guidMap[guid] = nil
                        recipesChanged = true
                        if next(guidMap) == nil then
                            realmMap[rKey] = nil
                        end
                    end
                end
                if next(realmMap) == nil then
                    SfuiDB.recipes[id] = nil
                end
            end
        end
    end

    -- 3. Craft outputs matrix (`SfuiDB.crafts[outputItemID][guid]`)
    if type(SfuiDB.crafts) == "table" then
        for outID, crafters in pairs(SfuiDB.crafts) do
            if type(crafters) == "table" and crafters[guid] ~= nil then
                crafters[guid] = nil
                recipesChanged = true
                if next(crafters) == nil then
                    SfuiDB.crafts[outID] = nil
                end
            end
        end
    end

    if recipesChanged and sfui.recipes then
        if sfui.recipes.InvalidateCache then
            sfui.recipes.InvalidateCache()
        end
        if sfui.recipes.InvalidateLiveIndices then
            sfui.recipes.InvalidateLiveIndices()
        end
        local B = sfui.recipes.browser
        if B then
            if B.ClearLearnedCache then
                B.ClearLearnedCache()
            end
            if B.ui and B.ui.frame and B.ui.frame:IsShown() then
                if B.RebuildFilteredList then B.RebuildFilteredList() end
                if B.UpdateList then B.UpdateList() end
            end
        end
    end

    -- 4. Fishing ledger (`SfuiDB.fishing.chars[guid]` + machine store + aggregate rebuild)
    local fishingChanged = false
    if type(SfuiDB.fishing) == "table" and type(SfuiDB.fishing.chars) == "table" and SfuiDB.fishing.chars[guid] ~= nil then
        SfuiDB.fishing.chars[guid] = nil
        fishingChanged = true
    end
    local bcs = _G.Blizzard_Console_SavedVars
    if type(bcs) == "table" and type(bcs.sfui_sync) == "table" then
        if type(bcs.sfui_sync.fishing_chars) == "table" and bcs.sfui_sync.fishing_chars[guid] ~= nil then
            bcs.sfui_sync.fishing_chars[guid] = nil
            fishingChanged = true
        end
        if type(bcs.sfui_sync.peers) == "table" then
            for k, mp in pairs(bcs.sfui_sync.peers) do
                if type(mp) == "table" and mp.guid == guid then
                    bcs.sfui_sync.peers[k] = nil
                end
            end
        end
    end
    if fishingChanged and sfui.fishing and sfui.fishing.RebuildAggregates then
        sfui.fishing.RebuildAggregates(true)
    end

    -- 5. Auto-mail routing rules (`SfuiDB.altMailRouting`)
    if type(SfuiDB.altMailRouting) == "table" then
        if type(SfuiDB.altMailRouting.routes) == "table" then
            SfuiDB.altMailRouting.routes[guid] = nil
        end
        if SfuiDB.altMailRouting.disenchanterGUID == guid then
            SfuiDB.altMailRouting.disenchanterGUID = nil
        end
        if type(SfuiDB.altMailRouting.disenchanterByRuleset) == "table" then
            for rsKey, dGuid in pairs(SfuiDB.altMailRouting.disenchanterByRuleset) do
                if dGuid == guid then
                    SfuiDB.altMailRouting.disenchanterByRuleset[rsKey] = nil
                end
            end
        end
        if sfui.alts and sfui.alts.mail and sfui.alts.mail.ui and sfui.alts.mail.ui.Refresh then
            sfui.alts.mail.ui.Refresh()
        end
    end

    -- 6. Per-character skills, gear, and pet settings
    if type(SfuiDB.characterSkills) == "table" then
        SfuiDB.characterSkills[guid] = nil
        if charName and charName ~= "" then
            SfuiDB.characterSkills[charName] = nil
            if charRealm and charRealm ~= "" then
                SfuiDB.characterSkills[charName .. "-" .. charRealm] = nil
            end
        end
    end
    if type(SfuiDB.gear_char) == "table" then
        SfuiDB.gear_char[guid] = nil
        if charName and charName ~= "" then
            SfuiDB.gear_char[charName] = nil
            if charRealm and charRealm ~= "" then
                SfuiDB.gear_char[charName .. "-" .. charRealm] = nil
            end
        end
    end
    if type(SfuiDB.pets_per_char) == "table" and charName and charName ~= "" then
        SfuiDB.pets_per_char[charName] = nil
        if charRealm and charRealm ~= "" then
            SfuiDB.pets_per_char[charName .. "-" .. charRealm] = nil
        end
    end

    -- 7. Sync peer roster & multibox cache
    if type(SfuiDB.sync) == "table" and type(SfuiDB.sync.peers) == "table" then
        for k, p in pairs(SfuiDB.sync.peers) do
            if type(p) == "table" and p.guid == guid then
                SfuiDB.sync.peers[k] = nil
            end
        end
    end
    if sfui.sync and sfui.sync.multibox and sfui.sync.multibox.InvalidatePeerCache then
        sfui.sync.multibox.InvalidatePeerCache()
    end
end
sfui.alts.RemoveCharacter = sfui.alts.PurgeCharacter

-- Confirmation Dialog for Removing Characters
if StaticPopupDialogs then
    StaticPopupDialogs["SFUI_ALTS_REMOVE_CHARACTER"] = {
        text = "are you sure you want to remove |cff9966ff%s|r from the alts list? this will delete all saved data for this character.",
        button1 = "remove",
        button2 = "cancel",
        OnAccept = function(self, data)
            if data and data.guid then
                sfui.alts.PurgeCharacter(data.guid)
                sfui.alts.UpdateUI(true)
                if sfui.alts.RefreshSettingsPanel then
                    sfui.alts.RefreshSettingsPanel()
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local RULESET_FILTER_DEFS = {
    { key = "normal", label = "normal" },
    { key = "pvp",    label = "pvp" },
    { key = "rp",     label = "rp" },
    { key = "rppvp",  label = "rppvp" },
    { key = "all",    label = "all" },
}

local function RefreshRulesetBar()
    if not frame or not frame.rulesetBar or not frame.rulesetButtons then return end
    local curFilter = sfui.alts.GetRulesetFilter() or "normal"
    local counts = { normal = 0, pvp = 0, rp = 0, rppvp = 0, all = 0 }
    for guid, data in pairs(SfuiDB.alts or {}) do
        if type(data) == "table" and not data.isHidden then
            local rs = GetAltRuleset(data, guid) or "normal"
            counts[rs] = (counts[rs] or 0) + 1
            counts.all = counts.all + 1
        end
    end

    local hl = (sfui.config and sfui.config.appearance and sfui.config.appearance.highlightColor) or { 0.4, 0, 1, 1 }
    local prevBtn = nil
    for _, btn in ipairs(frame.rulesetButtons) do
        local k = btn.rulesetKey
        local cnt = counts[k] or 0
        local textLabel = (cnt > 0) and string.format("%s (%d)", btn.baseLabel, cnt) or btn.baseLabel
        btn:SetText(textLabel)
        local fs = btn:GetFontString()
        local textW = (fs and fs.GetStringWidth and fs:GetStringWidth()) or (#textLabel * 6)
        btn:SetWidth(math.max(44, math.ceil(textW) + 14))
        btn:ClearAllPoints()
        if not prevBtn then
            btn:SetPoint("LEFT", frame.rulesetBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        end

        local isActive = (curFilter == k)
        if isActive then
            btn:SetBackdropColor(hl[1], hl[2], hl[3], 0.85)
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(hl[1], hl[2], hl[3], 1) end
            if fs then fs:SetTextColor(1, 1, 1, 1) end
        else
            btn:SetBackdropColor(0.10, 0.10, 0.12, 0.85)
            if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(0.24, 0.24, 0.28, 1) end
            if fs then
                local rgb = RULESET_RGB[k]
                if cnt > 0 and rgb then
                    fs:SetTextColor(rgb[1], rgb[2], rgb[3], 0.95)
                elseif cnt > 0 then
                    fs:SetTextColor(0.85, 0.85, 0.85, 0.95)
                else
                    fs:SetTextColor(0.50, 0.50, 0.54, 0.75)
                end
            end
        end
        prevBtn = btn
    end

    if frame.title then
        frame.title:SetText(string.format("alts manager · %s", curFilter))
    end
end

function sfui.alts.CreateFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "SfuiAltsFrame", UIParent, "BackdropTemplate")
    if sfui.common and sfui.common.register_special_frame then
        sfui.common.register_special_frame(frame)
    end
    frame:SetFrameStrata("DIALOG")
    frame:SetSize(cfg.width or 1000, cfg.height or 650)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if sfui.alts.UpdateSettingsPosition then
            sfui.alts.UpdateSettingsPosition()
        end
    end)
    frame:SetScript("OnHide", function()
        CloseDropDownMenus()
        if settingsPanel and settingsPanel:IsShown() then
            settingsPanel:Hide()
        end
    end)
    frame:SetScript("OnShow", function()
        if sfui.theme and sfui.theme.ElevateWindowContents then
            sfui.theme.ElevateWindowContents(frame)
        end
        if frame.close then
            frame.close:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        end
        if frame.settingsBtn then
            frame.settingsBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        end
        if frame.mailBtn then
            frame.mailBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        end
        if frame.rulesetBar then
            frame.rulesetBar:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
            if frame.rulesetButtons then
                for _, b in ipairs(frame.rulesetButtons) do
                    b:SetFrameLevel((frame:GetFrameLevel() or 1) + 21)
                end
            end
        end
        if sfui.alts.provider and sfui.alts.provider.OnFrameShow then
            sfui.alts.provider.OnFrameShow()
        end
        sfui.alts.RefreshDynamicCategories()
        sfui.alts.PerformSync()
        sfui.alts.UpdateUI(true)
        if settingsPanel and settingsPanel:IsShown() and sfui.alts.RefreshSettingsPanel then
            sfui.alts.UpdateSettingsPosition()
            sfui.alts.RefreshSettingsPanel()
        end
    end)

    sfui.theme.ApplyWindowStyle(frame)
    sfui.theme.RegisterWindow(frame)

    -- Standardized Window Header (Elevated above theme layers)
    local headerBar = (sfui.theme and sfui.theme.CreateWindowHeader) and sfui.theme.CreateWindowHeader(frame, "alts manager")
    frame.headerBar = headerBar

    local close = sfui.common.create_close_button(frame, function() frame:Hide() end, 24)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    close:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    close.tooltip = "close"
    frame.close = close

    -- Settings Button (gear icon)
    local settingsBtn = sfui.common.create_flat_button(frame, "", 24, 24)
    settingsBtn:ClearAllPoints()
    settingsBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -5, 0)
    settingsBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    settingsBtn.tooltip = "alts configuration (sort, sections, characters)"
    settingsBtn:SetScript("OnClick", function()
        local panel = CreateSettingsPanel()
        if panel:IsShown() then
            panel:Hide()
        else
            updateSettingsPosition()
            panel:Show()
            RefreshSettingsPanel()
        end
    end)
    sfui.common.set_button_settings_icon(settingsBtn, 16)
    frame.settingsBtn = settingsBtn

    -- Mail Routing Button (Mail Icon)
    local mailBtn = sfui.common.create_flat_button(frame, "", 24, 24)
    mailBtn:ClearAllPoints()
    mailBtn:SetPoint("TOPRIGHT", settingsBtn, "TOPLEFT", -5, 0)
    mailBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    mailBtn.tooltip = "alts mail routing"
    mailBtn:SetScript("OnClick", function()
        if settingsPanel and settingsPanel:IsShown() then
            settingsPanel:Hide()
        end
        frame:Hide()
        if sfui.alts.OpenMailConfig then
            sfui.alts.OpenMailConfig()
        elseif sfui.alts.ToggleMailConfig then
            sfui.alts.ToggleMailConfig()
        end
    end)
    sfui.common.set_button_mail_icon(mailBtn, 16)
    frame.mailBtn = mailBtn

    local isCamelot = IsCamelotNameSystem()
    local topOffset = isCamelot and -62 or -35

    if isCamelot then
        local rulesetBar = CreateFrame("Frame", nil, frame)
        rulesetBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
        rulesetBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -37)
        rulesetBar:SetHeight(20)
        rulesetBar:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        frame.rulesetBar = rulesetBar
        frame.rulesetButtons = {}

        for _, def in ipairs(RULESET_FILTER_DEFS) do
            local rBtn = sfui.common.create_flat_button(rulesetBar, def.label, 54, 18)
            rBtn.rulesetKey = def.key
            rBtn.baseLabel = def.label
            rBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 21)
            rBtn.tooltip = (def.key == "all")
                and "show characters across all forever rulesets"
                or string.format("show %s ruleset characters", def.label)
            local capturedKey = def.key
            rBtn:SetScript("OnClick", function()
                sfui.alts.SetRulesetFilter(capturedKey, false)
            end)
            frame.rulesetButtons[#frame.rulesetButtons + 1] = rBtn
        end
    end

    -- Sidebar (Category labels)
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 10, topOffset)
    sidebar:SetPoint("BOTTOMLEFT", 10, 10)
    sidebar:SetWidth(140)
    frame.sidebar = sidebar

    -- Scrollable Content Area for Alt Columns
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 10)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetHorizontalScroll()
        local maxScroll = self:GetHorizontalScrollRange()
        local step = cfg.columnWidth or 140
        self:SetHorizontalScroll(math.max(0, math.min(maxScroll, cur - (delta * step))))
    end)
    frame.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(1, 1)
    scrollFrame:SetScrollChild(content)
    frame.content = content

    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:Hide()
    frame.emptyText = emptyText

    frame:Hide()
    return frame
end

local altsList = {}
local visibleCats = {}

local function SortAlts(a, b)
    local sortKey = SfuiDB.altsSort or "name"
    if sfui.alts.provider and sfui.alts.provider.SortAlts then
        local customResult = sfui.alts.provider.SortAlts(a, b, sortKey)
        if customResult ~= nil then return customResult end
    end

    if sortKey == "ilvl" then
        local iA = tonumber(a.data and a.data.iLvl) or 0
        local iB = tonumber(b.data and b.data.iLvl) or 0
        if iA ~= iB then return iA > iB end
    elseif sortKey == "timeplayed" then
        local tA = tonumber(a.data and a.data.timeplayed) or 0
        local tB = tonumber(b.data and b.data.timeplayed) or 0
        if tA ~= tB then return tA > tB end
    end
    local nA = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(a.data, a.guid)) or tostring(a.data and a.data.name or "")
    local nB = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(b.data, b.guid)) or tostring(b.data and b.data.name or "")
    return nA < nB
end

local updateRequested = false
function sfui.alts.UpdateUI(force)
    if not frame or (not force and not frame:IsShown()) then return end

    if not force then
        if updateRequested then return end
        updateRequested = true
        C_Timer.After(0, function()
            updateRequested = false
            if frame and frame:IsShown() then
                sfui.alts.UpdateUI(true)
            end
        end)
        return
    end

    local cats = GetCategories()
    wipe(visibleCats)
    local currentHeader = nil
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}

    for _, cat in ipairs(cats) do
        if cat.type == "header" then
            if not SfuiDB.altsHiddenSections[cat.name] then
                currentHeader = cat.name
                table.insert(visibleCats, cat)
            else
                currentHeader = nil
            end
        else
            if currentHeader and not SfuiDB.altsCollapsed[currentHeader] then
                table.insert(visibleCats, cat)
            end
        end
    end

    -- Update Sidebar
    if frame.sidebar then
        local children = { frame.sidebar:GetChildren() }
        for _, cell in ipairs(children) do
            ReleaseCell(cell)
        end
        local visY = 0
        for _, cat in ipairs(visibleCats) do
            local row = AcquireCell(frame.sidebar)
            row:SetSize(140, cfg.rowHeight or 25)
            row:SetPoint("TOPLEFT", 0, -visY)

            local text = row.text
            text:Show()
            text:ClearAllPoints()
            text:SetPoint("LEFT", 5, 0)

            if cat.type == "header" then
                text:SetFontObject("GameFontNormal")
                text:SetTextColor(unpack(sfui.config.appearance.highlightColor or { 0.4, 0, 1, 1 }))
                text:SetText(cat.label)

                row:EnableMouse(true)
                row:SetScript("OnMouseUp", function()
                    SfuiDB.altsCollapsed[cat.name] = not SfuiDB.altsCollapsed[cat.name]
                    sfui.alts.UpdateUI(true)
                end)

                if cat.name == "GENERAL" then
                    row:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local curRsFilter = IsCamelotNameSystem() and sfui.alts.GetRulesetFilter() or nil
                        if curRsFilter then
                            GameTooltip:AddLine(string.format("all characters (%s)", curRsFilter), 1, 0.82, 0)
                        else
                            GameTooltip:AddLine("all characters", 1, 0.82, 0)
                        end
                        GameTooltip:AddLine(" ")

                        local totalGold = 0
                        local totalPlayed = 0
                        for _, entry in ipairs(altsList) do
                            totalGold = totalGold + (entry.data.money or 0)
                            totalPlayed = totalPlayed + (entry.data.timeplayed or 0)
                        end

                        if totalGold > 0 then
                            GameTooltip:AddDoubleLine("total gold:", _G.GetMoneyString(totalGold, true),
                                NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 0.82, 0)
                        end
                        if totalPlayed > 0 and (not sfui.alts.provider or sfui.alts.provider.showTimePlayedTooltip ~= false) then
                            local hours = math.floor(totalPlayed / 3600)
                            GameTooltip:AddDoubleLine("total time played:", string.format("%d hours", hours),
                                NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 1, 1)
                        end

                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    row:SetScript("OnEnter", nil)
                    row:SetScript("OnLeave", nil)
                end
            else
                text:SetFontObject("GameFontHighlightSmall")
                text:SetTextColor(unpack(sfui.config.colors.white))
                text:SetText(cat.label)
                row:EnableMouse(false)
                row:SetScript("OnMouseUp", nil)
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)

                if sfui.alts.provider and sfui.alts.provider.OnSidebarRow then
                    sfui.alts.provider.OnSidebarRow(row, cat)
                end
            end
            visY = visY + (cfg.rowHeight or 25)
        end
    end

    -- Release existing columns
    if not frame.content then return end
    local columns = { frame.content:GetChildren() }
    for _, col in ipairs(columns) do
        local cells = { col:GetChildren() }
        for _, cell in ipairs(cells) do
            ReleaseCell(cell)
        end
        ReleaseColumn(col)
    end

    for i = #altsList, 1, -1 do
        local entry = table.remove(altsList, i)
        ReleaseTable(entry)
    end
    local isCamelot = IsCamelotNameSystem()
    local curFilter = isCamelot and sfui.alts.GetRulesetFilter() or nil
    for guid, data in pairs(SfuiDB.alts or {}) do
        if type(data) == "table" and not data.isHidden then
            if not isCamelot or curFilter == "all" or GetAltRuleset(data, guid) == curFilter then
                local entry = AcquireTable()
                entry.guid = guid
                entry.data = data
                altsList[#altsList + 1] = entry
            end
        end
    end

    if isCamelot then
        RefreshRulesetBar()
    end

    table.sort(altsList, SortAlts)

    local xOffset = 0
    local colW = cfg.columnWidth or 140
    local rowH = cfg.rowHeight or 25

    for _, alt in ipairs(altsList) do
        local col = AcquireColumn(frame.content)
        col:SetSize(colW, #visibleCats * rowH)
        col:SetPoint("TOPLEFT", xOffset, 0)

        local classColor = RAID_CLASS_COLORS[alt.data.class] or NORMAL_FONT_COLOR
        local y = 0

        for _, cat in ipairs(visibleCats) do
            local cell = AcquireCell(col)
            cell:SetSize(colW, rowH)
            cell:SetPoint("TOPLEFT", 0, -y)

            local text = cell.text
            text:ClearAllPoints()
            text:SetPoint("CENTER")
            text:SetJustifyH("CENTER")
            text:SetWidth(0)
            text:Show()

            local handled = false
            if sfui.alts.provider and sfui.alts.provider.RenderCell then
                handled = sfui.alts.provider.RenderCell(cell, cat, alt.data, classColor, col, alt.guid)
            end

            if not handled then
                if cat.type == "header" then
                    if cat.name == "GENERAL" then
                        text:SetFontObject("GameFontNormal")
                        text:SetWidth(colW - 6)
                        text:SetWordWrap(false)

                        local mailTag = ""
                        if alt.data.inboxCount and alt.data.inboxCount > 0 then
                            local days = alt.data.inboxDaysLeft or 30
                            local color = "|cff88ccff"
                            if days < 3 then
                                color = "|cffff3333"
                            elseif days < 7 then
                                color = "|cffffaa00"
                            end
                            mailTag = string.format(" %s[%d]|r", color, alt.data.inboxCount)
                        end

                        local rsTag = ""
                        if isCamelot and curFilter == "all" then
                            local altRs = GetAltRuleset(alt.data, alt.guid) or "normal"
                            local rsCol = RULESET_COLORS[altRs] or "|cff88ccff"
                            rsTag = string.format(" %s[%s]|r", rsCol, altRs)
                        end

                        text:SetText(string.format("%s%s%s", sfui.alts.GetDisplayName(alt.data, alt.guid), rsTag, mailTag))
                        text:SetTextColor(classColor.r, classColor.g, classColor.b)

                        local altSnap = alt
                        local myGuid = GetCurrentCharacterGUID()
                        local isLivePlayer = (myGuid and altSnap.guid == myGuid)
                        cell:EnableMouse(true)
                        if isCamelot and not isLivePlayer then
                            cell:SetScript("OnMouseUp", function(_, button)
                                if button ~= "RightButton" then return end
                                local cur = GetAltRuleset(altSnap.data, altSnap.guid) or "normal"
                                local nextRs = "normal"
                                for idx, key in ipairs(RULESET_ORDER) do
                                    if key == cur then
                                        nextRs = RULESET_ORDER[(idx % #RULESET_ORDER) + 1]
                                        break
                                    end
                                end
                                altSnap.data.ruleset = nextRs
                                sfui.alts.UpdateUI(true)
                                if sfui.alts.RefreshSettingsPanel then
                                    sfui.alts.RefreshSettingsPanel()
                                end
                            end)
                        else
                            cell:SetScript("OnMouseUp", nil)
                        end
                        cell:SetScript("OnEnter", function(self)
                            local d = altSnap.data
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            local cc = RAID_CLASS_COLORS[d.class] or NORMAL_FONT_COLOR
                            GameTooltip:AddLine(string.format("|c%s%s|r", cc.colorStr or "ffffffff", sfui.alts.GetDisplayName(d, altSnap.guid)), 1, 1, 1)
                            if IsCamelotNameSystem() then
                                local altRs = GetAltRuleset(d, altSnap.guid) or "normal"
                                local rgb = RULESET_RGB[altRs] or RULESET_RGB.normal
                                GameTooltip:AddDoubleLine("ruleset:", altRs, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, rgb[1], rgb[2], rgb[3])
                            elseif d.realm and d.realm ~= "" then
                                GameTooltip:AddLine(d.realm, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
                            end
                            if d.guild then
                                GameTooltip:AddLine(string.format("<%s>", d.guild), 0.2, 1.0, 0.4)
                            end
                            if d.money and d.money > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine(_G.GetMoneyString(d.money, true), 1, 0.82, 0)
                            end
                            if d.inboxCount and d.inboxCount > 0 then
                                GameTooltip:AddLine(" ")
                                local days = d.inboxDaysLeft or 30
                                local daysStr = string.format("%.1f days left", days)
                                local r, g, b = 0.5, 0.8, 1.0
                                if days < 3 then
                                    r, g, b = 1.0, 0.2, 0.2
                                    daysStr = daysStr .. " (expiring soon!)"
                                elseif days < 7 then
                                    r, g, b = 1.0, 0.7, 0.0
                                end
                                GameTooltip:AddDoubleLine("inbox mail:", string.format("%d letter(s) (%s)", d.inboxCount, daysStr),
                                    NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, r, g, b)
                                if d.inboxMoney and d.inboxMoney > 0 then
                                    GameTooltip:AddDoubleLine("inbox gold:", _G.GetMoneyString(d.inboxMoney, true),
                                        NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, 1, 0.82, 0)
                                end
                            end
                            if sfui.alts.provider and sfui.alts.provider.showTimePlayedTooltip ~= false and d.timeplayed and d.timeplayed > 0 then
                                local hours = math.floor(d.timeplayed / 3600)
                                GameTooltip:AddLine(string.format("time played: %d hours", hours), 0.7, 0.7, 0.7)
                            end
                            if isCamelot and not isLivePlayer then
                                GameTooltip:AddLine("right-click to cycle ruleset", 0.65, 0.65, 0.68)
                            end

                            GameTooltip:Show()
                        end)
                        cell:SetScript("OnLeave", function()
                            GameTooltip:Hide()
                        end)

                    else
                        text:Hide()
                        local line = cell.line or cell:CreateTexture(nil, "BACKGROUND")
                        cell.line = line
                        line:Show()
                        line:SetHeight(1)
                        line:SetPoint("LEFT", 5, -5)
                        line:SetPoint("RIGHT", -5, -5)
                        line:SetColorTexture(0.2, 0.2, 0.2, 0.5)
                    end
                elseif cat.type == "stat" then
                    local val = alt.data[cat.key] or 0
                    text:SetText(cat.format and string.format(cat.format, val) or tostring(val))
                    text:SetTextColor(unpack(sfui.config.colors.white))
                else
                    text:SetText("-")
                    text:SetTextColor(0.5, 0.5, 0.5)
                end
            end

            y = y + rowH
        end

        xOffset = xOffset + colW
    end

    if frame.emptyText then
        if #altsList == 0 then
            if isCamelot and curFilter and curFilter ~= "all" then
                frame.emptyText:SetText(string.format("no characters tracked on %s ruleset", curFilter))
            else
                frame.emptyText:SetText("no characters tracked")
            end
            frame.emptyText:Show()
        else
            frame.emptyText:Hide()
        end
    end

    local minWidth = isCamelot and 420 or 310
    local topPad = isCamelot and 62 or 35
    local totalWidth = math.max(minWidth, 140 + 20 + xOffset + 10)
    local totalHeight = topPad + (#visibleCats * rowH) + 10
    frame:SetSize(totalWidth, totalHeight)
end

local lastAltToggleTime = 0

function sfui.alts.Open()
    sfui.alts.RefreshDynamicCategories()
    if not frame then
        frame = sfui.alts.CreateFrame()
    end
    if not frame:IsShown() then
        sfui.alts.CheckWeeklyResets()
        if sfui.alts.provider and sfui.alts.provider.OnFrameShow then
            sfui.alts.provider.OnFrameShow()
        end
        sfui.alts.PerformSync()
        needsSync = false
        frame:Show()
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.Toggle()
    local now = GetTime()
    if (now - lastAltToggleTime) < 0.15 then return end
    lastAltToggleTime = now

    sfui.alts.RefreshDynamicCategories()
    if not frame then
        frame = sfui.alts.CreateFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        sfui.alts.CheckWeeklyResets()
        if sfui.alts.provider and sfui.alts.provider.OnFrameShow then
            sfui.alts.provider.OnFrameShow()
        end
        sfui.alts.PerformSync()
        needsSync = false
        frame:Show()
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.ResetWeeklies()
    if sfui.alts.provider and sfui.alts.provider.ResetWeeklies then
        sfui.alts.provider.ResetWeeklies()
    else
        for _, d in pairs(SfuiDB.alts or {}) do
            if d.quests then wipe(d.quests) end
            if d.vault then wipe(d.vault) end
            if d.m0 then wipe(d.m0) end
            if d.raids then wipe(d.raids) end
        end
        sfui.alts.UpdateUI(true)
    end
end

function sfui.alts.initialize()
    if sfui.alts._initialized then return end
    sfui.alts._initialized = true

    SfuiDB.alts = SfuiDB.alts or {}
    SfuiDB.altsCollapsed = SfuiDB.altsCollapsed or {}
    SfuiDB.altsHiddenSections = SfuiDB.altsHiddenSections or {}

    sfui.alts.RefreshDynamicCategories()
    sfui.alts.SyncCurrentCharacter()

    -- Central Event Dispatcher
    sfui.events.RegisterEvent("PLAYER_ENTERING_WORLD", function()
        leavingWorld = false
        sfui.alts.leavingWorld = false
        if IsCamelotNameSystem() and not userChangedRulesetFilter then
            activeRulesetFilter = GetCurrentRuleset() or "normal"
        end
        sfui.alts.SyncCurrentCharacter()
    end)

    sfui.events.RegisterEvent("PLAYER_LEAVING_WORLD", function()
        leavingWorld = true
        sfui.alts.leavingWorld = true
        if syncTimer then
            syncTimer:Cancel()
            syncTimer = nil
        end
        local guid = GetCurrentCharacterGUID()
        if guid and SfuiDB.alts and SfuiDB.alts[guid] then
            local now = (GetServerTime and GetServerTime()) or time()
            SfuiDB.alts[guid].lastSeen = now
            SfuiDB.alts[guid].lastUpdate = now
        end
    end)

    sfui.events.RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if frame and frame:IsShown() then
            sfui.alts.SyncCurrentCharacter()
        end
    end)

    sfui.events.RegisterEvent("TIME_PLAYED_MSG", function(_, totalTime, currentLevelTime)
        local guid = GetCurrentCharacterGUID()
        if guid and SfuiDB.alts and SfuiDB.alts[guid] then
            SfuiDB.alts[guid].timeplayed = totalTime or 0
        end
    end)

    if RequestTimePlayed and (not sfui.alts.provider or sfui.alts.provider.showTimePlayedTooltip ~= false) then
        RequestTimePlayed()
    end

    local function on_sync_event()
        if sfui.safety and sfui.safety.DeferOutOfCombat then
            sfui.safety.DeferOutOfCombat("alts_char_sync", sfui.safety.OOC_P2, sfui.alts.SyncCurrentCharacter)
        else
            sfui.alts.SyncCurrentCharacter()
        end
    end
    sfui.events.RegisterEvent("PLAYER_LEVEL_UP",              on_sync_event)
    sfui.events.RegisterEvent("PLAYER_XP_UPDATE",             on_sync_event)
    sfui.events.RegisterEvent("UPDATE_EXHAUSTION",            on_sync_event)
    sfui.events.RegisterEvent("PLAYER_UPDATE_RESTING",        on_sync_event)
    sfui.events.RegisterEvent("PLAYER_EQUIPMENT_CHANGED",     on_sync_event)
    sfui.events.RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE", on_sync_event)
    sfui.events.RegisterEvent("PLAYER_MONEY",                 on_sync_event)

    sfui.events.RegisterMessage("SFUI_INVENTORY_DELTA", function()
        local guid = GetCurrentCharacterGUID()
        if guid and SfuiDB and SfuiDB.alts and SfuiDB.alts[guid] and sfui.inventory and sfui.inventory.GetAllBagCounts then
            local liveBags = sfui.inventory.GetAllBagCounts()
            if liveBags then
                local savedBags = SfuiDB.alts[guid].bagItems or {}
                wipe(savedBags)
                for itemID, cnt in pairs(liveBags) do
                    if type(itemID) == "number" and type(cnt) == "number" and cnt > 0 then
                        savedBags[itemID] = cnt
                    end
                end
                SfuiDB.alts[guid].bagItems = savedBags
            end
        end
    end)

    local _isBankOpen = false
    local function ScanCharacterBank()
        if not _isBankOpen then return end
        local guid = GetCurrentCharacterGUID()
        if not guid or not SfuiDB or not SfuiDB.alts then return end
        SfuiDB.alts[guid] = SfuiDB.alts[guid] or {}
        local bankCounts = SfuiDB.alts[guid].bankItems or {}
        wipe(bankCounts)

        local C_Cont = _G.C_Container
        local getNumSlots = (C_Cont and C_Cont.GetContainerNumSlots) or _G.GetContainerNumSlots
        local getItemInfo = (C_Cont and C_Cont.GetContainerItemInfo) or _G.GetContainerItemInfo
        if not getNumSlots or not getItemInfo then return end

        local bankContainers = { -1 }
        if _G.REAGENTBANK_CONTAINER and type(_G.REAGENTBANK_CONTAINER) == "number" then
            bankContainers[#bankContainers + 1] = _G.REAGENTBANK_CONTAINER
        end
        local firstBankBag = (_G.NUM_BAG_SLOTS or 4) + 1
        local lastBankBag = firstBankBag + (_G.NUM_BANKBAGSLOTS or 7) - 1
        if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.CharacterBankTab_1 then
            for i = 1, 6 do
                local tabIdx = _G.Enum.BagIndex["CharacterBankTab_" .. i]
                if type(tabIdx) == "number" then
                    bankContainers[#bankContainers + 1] = tabIdx
                end
            end
        else
            for b = firstBankBag, lastBankBag do
                bankContainers[#bankContainers + 1] = b
            end
        end

        local issecret = (sfui.safety and sfui.safety.issecretvalue) or _G.issecretvalue
        for _, bagID in ipairs(bankContainers) do
            local nSlots = getNumSlots(bagID) or 0
            for slot = 1, nSlots do
                local info = getItemInfo(bagID, slot)
                if type(info) == "table" then
                    local id = info.itemID
                    local cnt = info.stackCount or 1
                    if id and not (issecret and issecret(id)) and not (issecret and issecret(cnt)) and cnt > 0 then
                        bankCounts[id] = (bankCounts[id] or 0) + cnt
                    end
                elseif info ~= nil and _G.GetContainerItemLink then
                    local _, cnt = _G.GetContainerItemInfo(bagID, slot)
                    local lnk = _G.GetContainerItemLink(bagID, slot)
                    local id = lnk and tonumber(lnk:match("item:(%d+)"))
                    if id and type(cnt) == "number" and cnt > 0 then
                        bankCounts[id] = (bankCounts[id] or 0) + cnt
                    end
                end
            end
        end
        SfuiDB.alts[guid].bankItems = bankCounts
    end

    sfui.events.RegisterEvent("BANKFRAME_OPENED", function()
        _isBankOpen = true
        ScanCharacterBank()
    end)
    sfui.events.RegisterEvent("BANKFRAME_CLOSED", function()
        _isBankOpen = false
    end)
    sfui.events.RegisterEvent("PLAYERBANKSLOTS_CHANGED", function()
        if _isBankOpen then
            if sfui.safety and sfui.safety.DeferOutOfCombat then
                sfui.safety.DeferOutOfCombat("alts_bank_scan", sfui.safety.OOC_P2, ScanCharacterBank)
            else
                ScanCharacterBank()
            end
        end
    end)

    -- Register flavor-specific events from provider
    if sfui.alts.provider and sfui.alts.provider.RegisterEvents then
        sfui.alts.provider.RegisterEvents()
    end
end

function sfui.alts.GetAccountItemSummary(itemID, excludeCurrent)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 or not SfuiDB or type(SfuiDB.alts) ~= "table" then
        return nil
    end

    local myGUID = GetCurrentCharacterGUID()
    local totalAll = 0
    local totalAlts = 0
    local list = {}

    for guid, alt in pairs(SfuiDB.alts) do
        if type(alt) == "table" and IsSameRuleset(alt, guid) then
            local isMe = (myGUID and guid == myGUID)
            local bCnt = 0
            if isMe and sfui.inventory and sfui.inventory.GetCount then
                bCnt = sfui.inventory.GetCount(itemID) or 0
            elseif type(alt.bagItems) == "table" then
                bCnt = tonumber(alt.bagItems[itemID]) or 0
            end
            local kCnt = (type(alt.bankItems) == "table" and tonumber(alt.bankItems[itemID])) or 0
            local sum = bCnt + kCnt
            if sum > 0 then
                totalAll = totalAll + sum
                if not isMe then
                    totalAlts = totalAlts + sum
                end
                if not (excludeCurrent and isMe) then
                    local disp = (sfui.alts.GetDisplayName and sfui.alts.GetDisplayName(alt, guid)) or alt.name or "alt"
                    local colored = (sfui.common and sfui.common.class_color_name and sfui.common.class_color_name(disp:lower(), alt.class)) or disp:lower()
                    list[#list + 1] = {
                        guid        = guid,
                        name        = disp:lower(),
                        coloredName = colored,
                        bags        = bCnt,
                        bank        = kCnt,
                        total       = sum,
                    }
                end
            end
        end
    end

    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return (a.name or "") < (b.name or "")
    end)
    return {
        total     = totalAll,
        totalAlts = totalAlts,
        alts      = list,
    }
end

local _altsDebug = {}
function sfui.alts_debug_info()
    local altCount = 0
    if SfuiDB and SfuiDB.alts then
        for _ in pairs(SfuiDB.alts) do altCount = altCount + 1 end
    end
    _altsDebug.columnPool   = #columnPool
    _altsDebug.cellPool     = #cellPool
    _altsDebug.tablePool    = #tablePool
    _altsDebug.trackedAlts  = altCount
    _altsDebug.frameCreated = frame ~= nil
    _altsDebug.frameShown   = frame and frame:IsShown() or false
    _altsDebug.provider     = sfui.alts.provider and sfui.alts.provider.name or "none"
    return _altsDebug
end

-- Stable alias: external code (db.lua, slash commands) may call SaveCurrentCharacter
-- to request a forced logout-safe flush without knowing the internal API.
sfui.alts.SaveCurrentCharacter = function()
    sfui.alts.PerformSync(false)
end


if sfui.RegisterModule then
    sfui.alts.OnEnable = function(self) self.initialize() end
    sfui.alts.GetDebugInfo = sfui.alts_debug_info
    sfui.RegisterModule("alts", sfui.alts)
end

