# changelog

## v1.121 (2026-10-23)

### features

- **tracked buffs static bar anchoring (`frames/tracking/trackedbars.lua`, `frames/tracking/buffs.lua`, `frames/tracking/trackedoptions.lua`)**:
  - added `SfuiTrackedBarsTopAnchor` to calculate and maintain a static top anchor for the highest attached tracked bar slot above the health/resource frame stack.
  - anchored tracked buffs by default to sit 4px above the highest tracked bar slot, maintaining a consistent static position without jumping as temporary buff bars show or hide.
  - added automatic anchor recalculation upon changing talent specializations.
  - added a "reset default" button in the tracked buffs options tab alongside the mover toggle to quickly revert to the default anchor position.

- **retail currency limit differentiation (`frames/alts/alts_standard.lua`)**:
  - safely extracted `canEarnPerWeek` and `quantityEarnedThisWeek` directly from `C_CurrencyInfo.GetCurrencyInfo`.
  - distinguished true weekly capped currencies from cumulative seasonal caps (e.g. crests, spark dust), inventory holding caps (e.g. valorstones), and uncapped currencies in tooltips and cap warnings.

### improvements & bug fixes

- **tracked buffs preview & sync fix (`frames/tracking/buffs.lua`)**:
  - resolved a nil value error in `SetPreviewMode` by adding forward declaration for `SyncWithBlizzard`.
