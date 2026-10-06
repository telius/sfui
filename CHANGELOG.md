# Changelog

## unreleased

### fixes

- **quest expand state reset**: `sfui.questlog.GetState()` (`frames/quests/engine/q_tracker.lua`) is now the single quest log state source. it no longer deletes the table that achievements, activities and collectables used for expand/collapse (renamed to `expandedBlocks`), so their state survives tracker refreshes.
- **broken debounces / throttles**: `C_Timer.After` returns nil, so the "timer handles" in `frames/dungeonjournal/dj_sidebar.lua`, `dj_quests.lua`, `dj_pins.lua` and the scan throttle in `frames/reminders/buffs_scan.lua` never debounced anything. they now use `sfui.common.debounce` or a pending flag.
- **recipe tooltip hook**: the legacy fallback in `frames/alts/recipes.lua` hooks both the blizzard tooltip and the private addon tooltip again. `frames/dungeonjournal/dj_tooltips.lua` also annotates the private tooltip.
- **alts manager header**: the header no longer sits below the theme frame (`frames/alts/alts.lua`, `frames/themes/engine.lua`).

### features

- **dungeon journal level filter**: the sidebar shows only dungeons in your level range by default. the new `all` toggle (and the context menu) shows every dungeon.

### architecture

- **private tooltip everywhere**: all addon tooltips now go through `sfui.common.get_tooltip()` (`SfuiGameTooltip`). they're hidden with the new `sfui.common.hide_tooltip()`, and comparison tooltips are wired up in `core/items.lua`.
- **new shared helpers**:
  - in `common.lua`: `is_addon_loaded`, `ensure_addon_loaded`, `get_addon_metadata`, `get_player_faction` and `debounce`.
  - in `core/widgets.lua`: `attach_tooltip`, `apply_flat_backdrop`, `create_pool` and `create_icon_toggle`.
- **shared quest helpers**: the duplicate `IsQuestWatched`, `IsWorldQuest`, `AutoTrackQuest`, `TryInsertQuestLink`, `FormatQuestTimer` and `IsClassQuest` code from `q_quests.lua`, `q_camelot.lua`, `q_camelot_class.lua` and `q_worldquests.lua` now lives in the new `frames/quests/helpers/q_common.lua`.
- **api standardization**:
  - item info goes through `sfui.common.get_item_info` / `get_item_instant_info`.
  - player class goes through `get_player_class` / `get_player_class_id`.
  - addon loading goes through the new addon wrappers.
  - cvars go through `get_cvar` / `set_cvar`.
  - bar textures go through `sfui.widgets.get_bar_texture`.
  - dead raw-api fallbacks were removed.
- **dungeon journal cleanup**:
  - the inline backdrop literals use `apply_flat_backdrop`.
  - the eye and `all` buttons use `create_icon_toggle`.
  - character-scoped options persist through one `PersistCharOption` path.
- **portals**: cooldown border and text code is hoisted into `set_cd_border` / `set_cd_text`.
- **lowercase pass**: about 200 capitalized ui labels and tooltip lines were lowercased.
- **docs**: `.agent/workflows/methods.md` now settles the tooltip rule and documents the dropdown `GLOBAL_MOUSE_DOWN` exception, the `C_Timer.After` pitfall and a shared-helper reference table.

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
