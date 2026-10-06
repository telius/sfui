# Changelog

## v12.1.0-75 (2026-10-06)

### Features & Major Improvements

- **Memory Diagnostic Engine & Heap Reporting (`frames/mem.lua`, `frames/options/tabs/tab_debug.lua`)**:
  - **Addon Memory Scan Fix**: Resolved issue where addon memory was reporting `0.0 kb` by automatically triggering `UpdateAddOnMemoryUsage()` whenever uninitialized or on panel `OnShow`, supported by a 15-second periodic update cadence while open and a 1-second throttle for manual refreshes.
  - **Dynamic Multi-Fallback Addon Lookup**: Introduced `GetAddonUsageKB()` with cached index lookup checking chunk `addonName`, `"sfui"`, `"SFUI"`, and iterating `C_AddOns.GetNumAddOns()` / `GetNumAddOns()` to guarantee accurate memory accounting across all environments.
  - **Configured Memory Color Thresholds**: Updated addon memory thresholds to display `< 15mb` in green (`|cff00ff88`), `15–25mb` in yellow (`|cffffaa00`), and `25mb+` in red (`|cffff4444`) across both the KPI metric cards and `/sfui mem print` / `/sfui mem dump` outputs.
  - **Categorized Module Sections**: Grouped module cards under sleek, theme-styled divider banners (`bars & combat`, `tracking & cooldowns`, and `general & utilities`), keeping unit bars (`bars`, `threat`, `target`, `swing`, `castbars`, `vehicle`) and tracking modules (`trackedbars`, `trackedicons`, `cdm`, `glows`) tightly clustered.
  - **Dynamic Scroll Frame Height**: Sized scroll child frame dynamically based on total section row count, eliminating card clipping near the bottom of the list.
  - **Garbage Collection & Profiler Telemetry**: Synchronized baseline and post-collection measurements in `RunGC()`, `StartWatcher()`, and `StopWatcher()` so memory reclamation and allocation rates reflect true addon heap dynamics.

- **Universal Module Memory Telemetry & Debug Diagnostics (`frames/bars/swing.lua`, `frames/bars/threat.lua`, `frames/bars/target.lua`, `frames/gear/lootfeed.lua`, `frames/hide.lua`, `frames/reminders/buffs.lua`, `frames/automation/rankup.lua`, `frames/options/tabs/tab_debug.lua`)**:
  - **Module Memory Telemetry**: Added complete `mem.lua` diagnostic and card metrics across `buffs`, `lootfeed`, `dungeonjournal`, `hide`, `rankup`, `swing`, `threat`, and `target` modules.
  - **Debug Spec & Swing Diagnostics**: Added spec resolver telemetry (`talents_camelot`) and available swing bar diagnostics in `frames/options/tabs/tab_debug.lua` and `frames/bars/swing.lua`.
