## v0.3.4 (2026-03-05)

### Features
- **Dynamic Mythic 0 Tracking**: Replaced hardcoded dungeon grids with dynamic Encounter Journal querying for current expansion dungeons.
- **Seasonal Crest Caps**: Added tracking for seasonal maximum quantities and "Myth" crest renaming.
- **Alts UI Priority**: Set Alts tracker frame to `DIALOG` strata for visibility over all other UI elements.
- **Improved Key Coloring**: Mythic+ keys level 12 and higher are now highlighted in **Orange** for better visibility in the Alts tracker.

### Optimizations
- **Throttled Layout Rebuilds**: Deferred expensive `trackedicons.lua` layout updates to a 0.1s ticker to prevent combat hitching.
- **OnUpdate Cleanup**: Removed redundant per-frame logic in `castbar.lua` and `cdm.lua` when idle.

## v0.3.3b (2026-03-02)

### Features
- **Alts Module Overhaul**: Complete refactor of the character management system.
- **Character Management**: Introduced "Hide" functionality and a dedicated Manager dropdown ("=") for unhiding or removing characters.
- **Improved UI**: Added character sorting (Name, iLvl, M+), dynamic width dropdowns, and high-strata menus for better visibility.
- **Mythic+ Integration**: Dynamic dungeon list population and color-coded score tracking.

### Optimizations
- **Frame Pooling**: Implemented full pooling for the Alts grid, eliminating frame churn and stutter.
- **Combat Lockdown**: Synchronization is now paused during combat to ensure zero impact on gameplay performance.
- **Event Throttling**: Increased debounce timer to 1.0s for more efficient background processing.

## v0.3.2 (2026-03-01)

### Features
- **Tracking Manager**: New integrated system for managing auras, cooldowns, and custom tracks with real-time visual feedback.
- **Prey Bar**: Performance-optimized API-driven hunt tracker with zone-based visibility and robust text handling.

### Optimizations
- **Minimap Performance**: Comprehensive CPU optimization including global localization, a skinning cache for buttons, and a smarter collection cycle to reduce overhead.
- **Prey Bar**: Localized functions, throttled API calls, and data-change gating to ensure minimal impact on game performance.
