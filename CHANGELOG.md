# Changelog

## v12.1.0-58 (2026-09-27)

### Features & Major Architecture
- **Decoupled Client Talent Architecture (`core/talents.lua`, `core/talents_standard.lua`, `core/talents_camelot.lua`)**:
  - Divided talent handling into dedicated environment modules with TOC game-type guards (`[AllowLoadGameType standard]` vs `[AllowLoadGameType camelot, classic]`).
  - Added Camelot dominant talent tree solver inspecting modern trait tree currency (`C_Traits`) and classic talent tab info, accurately resolving dominant specialization IDs across expansions.
  - Implemented high-efficiency hot-path color cache with zero table allocation in `core/colors.lua`.

- **Event-Driven Module Bus & Decoupled Color Pipeline (`core/module.lua`, `frames/options/options.lua`)**:
  - Replaced hardcoded notifications with `SFUI_SPEC_COLORS_UPDATED` message and `sfui.BroadcastSpecChanged()`.
  - Implemented `OnSpecChanged(self, specID)` lifecycle hooks across castbars, tracking bars, tracking icons, cursor rings, quest trackers, gear managers, and loot viewers.
  - Streamlined settings updates through `SFUI_SETTING_CHANGED` to eliminate duplicate module update dispatches.

- **Options Panel Performance & UX Overhaul (`frames/options/options.lua`)**:
  - Added real-time tab search/filtering input (`filter tabs...`) with instant layout repositioning and keyboard navigation.
  - Added sleek 2px vertical accent indicator on active tab buttons for enhanced visual hierarchy.
  - Implemented lazy tab construction (`ensure_tab_built`) to eliminate upfront frame allocation and significantly reduce initial options panel open time.
  - Replaced recursive DOM scanning in `update_scroll_height` with zero-allocation `select("#", ...)` traversal, plus direct `SetContentHeight` support.
  - Added session persistence for last active options tab (`SfuiDB.lastOptionsTab`) and standardized tab reset API (`sfui.options.ResetTab`).

### Bug Fixes & Refinements
- **Classic / Camelot Power Bar Visibility (`frames/bars/bars.lua`)**:
  - Gated `powerBar.hiddenSpecs` and `secondaryPowerBar.hiddenSpecs` strictly behind `sfui.isRetail`, ensuring Warlocks, Mages, and Retribution Paladins in Camelot/Classic retain their primary mana bar and 5-second rule (FSR) regeneration timer.
- **Quest Tracker Modularization (`frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_quests.lua`)**:
  - Separated Camelot/Forever quest classification and level badge logic into a dedicated module file with game-type load directives.
  - Fixed quest bulletpoint characters and updated spec color queries to project-standard API.
