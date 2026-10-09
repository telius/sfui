# Changelog

## v1.87 (2026-10-09)

### features

- **triage food without well fed cycling**: bag triage in `frames/automation/triage.lua` now evaluates and cycles through food items without the "Well Fed" buff alongside grey junk, while strictly protecting stat-granting buff food when `protectFoodWater` is active.
- **food & well fed scanner engine**: implemented `get_food_drink_info` and `is_buff_food` in `core/items.lua` with localized spell and tooltip inspection (`C_TooltipInfo` and dedicated `sfuiTooltip` fallback) shared between `frames/automation/triage.lua` and `frames/reminders/buffs_consumables.lua`.
- **bidirectional triage candidate navigation**: added mouse wheel scroll cycling (`OnMouseWheel`) and right-click backward navigation to the triage prompt frame and next button in `frames/automation/triage.lua`.

### improvements & bug fixes

- **portals frame icon resolution**: resolved fatal Lua crash `attempt to call a nil value` in `frames/portals/portals_camelot.lua` when opening the travel hub on characters with hearthstones or engineering items. Added `sfui.api.GetItemIcon` alias in `compat.lua` along with a multi-tier fallback chain (`C_Item.GetItemIconByID`, `GetItemIcon`, and `GetItemInfoInstant`), and safeguarded item and toy icon lookups in `frames/portals/portals_camelot.lua` and `frames/portals/portals.lua`.
- **shaman class travel**: added Astral Recall (spell ID 556) to classic/camelot class travel tracking in `frames/portals/portals_camelot.lua`.
- **tab_portals cleanup**: cleaned up options tab descriptions in `frames/options/tabs/tab_portals.lua`, removed redundant role status labels, streamlined bullet points, and polished travel hub preview and command triggers.
- **empty travel hub state**: added graceful empty state messaging in `frames/portals/portals_camelot.lua` when no travel items, spells, or portals are available.
