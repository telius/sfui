-- Luacheck configuration for SFUI

stds.wow = {
    globals = {
        -- Blizzard Core Engine & Frame Globals
        "_G", "hooksecurefunc", "CreateFrame", "UIParent", "GameTooltip", "ItemRefTooltip",
        "Settings", "SettingsPanel", "Enum", "Constants", "SlashCmdList",
        "InCombatLockdown", "UnitGUID", "UnitName", "UnitClass", "UnitSex", "UnitLevel", "UnitXP",
        "UnitXPMax", "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitHealth", "UnitHealthMax",
        "UnitIsDeadOrGhost", "UnitIsPlayer", "UnitCanAttack", "UnitIsUnit", "UnitExists", "UnitInRaid",
        "UnitInParty", "UnitGroupRolesAssigned", "UnitGetAvailableRoles", "GetMoney", "GetTime",
        "GetFramerate", "GetNetStats", "GetZoneText", "GetSubZoneText", "GetRealZoneText",
        "GetSpecialization", "GetSpecializationInfo", "GetSpecializationRole", "GetActiveSpecGroup",
        "GetNumSpecializations", "GetNumClasses", "GetClassInfo", "GetInventoryItemLink",
        "GetInventoryItemID", "GetInventoryItemTexture", "GetInventoryItemQuality", "GetInventoryItemDurability",
        "GetItemInfo", "GetItemInfoInstant", "GetItemQualityColor", "GetSpellInfo", "GetSpellLink",
        "GetSpellTexture", "GetSpellCooldown", "GetSpellCharges", "GetSpellCount", "IsSpellKnown",
        "IsPlayerSpell", "IsUsableSpell", "IsConsumableSpell", "IsCurrentSpell", "IsAutoRepeatSpell",
        "IsPassiveSpell", "GetShapeshiftForm", "GetShapeshiftFormInfo", "GetNumShapeshiftForms",
        "GetRaidRosterInfo", "GetNumGroupMembers", "IsInRaid", "IsInGroup", "IsShiftKeyDown",
        "IsControlKeyDown", "IsAltKeyDown", "PlaySound", "SOUNDKIT", "StaticPopup_Show",
        "StaticPopup_Hide", "StaticPopupDialogs", "ToggleDropDownMenu", "UIDropDownMenu_Initialize",
        "UIDropDownMenu_CreateInfo", "UIDropDownMenu_AddButton", "UIDropDownMenu_SetSelectedValue",
        "UIDropDownMenu_GetSelectedValue", "UIDropDownMenu_SetText", "CloseDropDownMenus",
        "SecondsToTime", "BreakUpLargeNumbers", "CombatLogGetCurrentEventInfo", "issecretvalue",
        "CopyTable", "wipe", "FastRandom", "random", "time", "date", "difftime",
        "SetLFGRoles", "GetLFGRoles", "CompleteLFGRoleCheck",
        "CanMerchantRepair", "CanGuildBankRepair", "GetRepairAllCost", "GetGuildBankWithdrawMoney",
        "RepairAllItems", "ChallengesKeystoneFrame", "GameTooltip_ShowCompareItem",
        "CUSTOM_CLASS_COLORS", "RAID_CLASS_COLORS",

        -- Blizzard C_* Namespaces
        "C_Timer", "C_Spell", "C_Item", "C_Container", "C_CurrencyInfo", "C_QuestLog",
        "C_MythicPlus", "C_ChallengeMode", "C_Scenario", "C_Map", "C_Navigation",
        "C_SuperTrack", "C_TooltipInfo", "C_UnitAuras", "C_MountJournal", "C_PetJournal",
        "C_TransmogCollection", "C_ToyBox", "C_Heirloom", "C_PlayerInfo", "C_ClassColor",
        "C_SpecializationInfo", "C_Traits", "C_ItemUpgrade", "C_EncounterJournal",
        "C_LFGList", "C_PartyInfo", "C_AddOns", "C_UI", "C_Cursor", "C_HousingCatalog",
        "C_SkillInfo",

        -- Addon SavedVariables & Top-level Tables
        "sfui", "SfuiDB",
    },
    read_globals = {
        "LibStub",
    }
}

std = "lua51+wow"

exclude_files = {
    "Libs/**",
    "scratch/**",
    ".agent/**",
    ".release/**",
}

max_line_length = false
self = false

ignore = {
    "211",      -- Unused variable (e.g. addonName, addon)
    "212",      -- Unused argument
    "631",      -- Line too long
}
