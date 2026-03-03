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
