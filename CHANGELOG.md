# Changelog

## v12.1.0-60 (2026-09-29)

### Features & Major Improvements
- **Spec Resolution & Authoritative Spec Bridge (`data/stats.lua`, `core/bridge.lua`, `core/talents.lua`, `core/talents_camelot.lua`)**:
  - Precomputed bidirectional mapping (`sfui.talents.SPEC_BRIDGE`) across all 27 Camelot talent tree specs (`14821`–`14913`) and Retail DB2 spec IDs (`62`–`1480`).
  - Added zero-allocation $O(1)$ translation helpers: `to_retail_spec_id`, `to_camelot_spec_id`, `is_spec_match`, and `is_spec_in_list`.
  - Unified role detection and `TANK_SPECS` registration, ensuring instant resolution for both Retail and Camelot tanks.

- **High-Performance Color Pipeline Overhaul (`core/colors.lua`)**:
  - Hot paths for castbars, power bars, and UI elements now operate with zero table allocations via symmetric cross-caching (`specID`, `retailID`, `camelotID`, and `classID`).
  - Added immutable static fallback color table (`_defaultFallbackColor`).
  - Streamlined event architecture to eliminate redundant cache wipes, centralizing talent/spec updates to `SFUI_SPEC_CHANGED`.

- **Gear Comparison & Stat Engine De-duplication (`data/stats.lua`, `frames/gear/`)**:
  - Eliminated ~350 lines of duplicate stat table definitions by dynamically populating `sfui.default_stats` and `sfui.classic_default_stats` from single-source spec metadata.
  - Removed duplicate `TANK_SPECS` definitions and redundant trampoline functions across `gear.lua`, `highest.lua`, and `engine.lua`.
  - Replaced inline fallback tables in gear scoring loops with immutable static constants (`STATIC_CLASSIC_FALLBACK_ORDER`, `STATIC_RETAIL_FALLBACK_ORDER`, `STATIC_DEFAULT_EQUALS`).

- **Classic / Camelot Offline Rested XP Engine (`frames/alts/alts_camelot.lua`)**:
  - Implemented authentic Vanilla/Classic rested XP accumulation simulation (1 bubble/8h in rest areas vs 1 bubble/32h in the wild), capped at 150%.
  - Added interactive tooltip breakdown with live calculation, time-to-max, and offline gained XP.
  - Added "Rested XP" sorting option and instant sync via `PLAYER_UPDATE_RESTING`.

- **Modular Frame Management & UI Themes (`frames/hide.lua`, `frames/options/tabs/tab_hide.lua`, `frames/themes/`)**:
  - Added dedicated frame hiding controls and options tab (`tab_hide.lua`).
  - Added theme switching infrastructure supporting Modern and Camelot aesthetic profiles.
