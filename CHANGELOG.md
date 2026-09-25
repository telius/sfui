# Changelog

## v12.1.0-54 (2026-09-25)

### Features & Automation
- **Continuous 1-Key Fishing Automation & Auto-Loot (`frames/fishing.lua`, `frames/options/tabs/tab_fishing.lua`)**:
  - Implemented continuous 1-key fishing cycle: single keybind casts, interacts with soft-target bobber to reel in, and loots fish automatically without keybind disarming delays or wasted keypresses.
  - Eliminated full-time mouse intercept listeners (`GLOBAL_MOUSE_DOWN`, `GLOBAL_MOUSE_UP`) and removed legacy double-click tracking, reducing idle CPU consumption to strictly 0.000%.
  - Added dedicated auto-loot configuration toggle and clean sound volume slider layout in options panel.

### Major Code Cleanup & Optimization
- **Pruned Legacy Defensive APIs & Bloat (`frames/fishing.lua`)**:
  - Removed obsolete 3rd-party legacy checks: eliminated `C_Secrets`, `C_UnitAuras`, `IsFlying`, `is_flying_safe()`, Dragonflight lunker checks, and 15 redundant `pcall` wrappers in favor of direct Blizzard API calls.
  - Replaced polling `ChannelInfo()` and `UnitChannelInfo()` with low-overhead reactive event tracking via `UNIT_SPELLCAST_CHANNEL_START` and `UNIT_SPELLCAST_CHANNEL_STOP`.
  - Cleaned up unused and redundant locals and frame references across the module.
- **Memory Profiler Observer Isolation (`frames/mem.lua`)**:
  - Gated live GUI ticker updates during active profiling runs to prevent self-profiling observer table churn.
  - Restored and streamlined live fishing telemetry in `/sfui mem` diagnostic view.
- **Quest & Alt Frame Polish (`frames/quests/`, `frames/alts/`)**:
  - Refined layout, block rendering, and quest tracker sizing heuristics.
