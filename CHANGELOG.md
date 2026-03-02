## v0.3.3b (2026-03-02)

### Features
- **Alts Module Overhaul**: Complete refactor of the character management system.
- **Character Management**: Introduced "Hide" functionality and a dedicated Manager dropdown ("=") for unhiding or removing characters.
- **Improved UI**: Added character sorting (Name, iLvl, M+), dynamic width dropdowns, and high-strata menus for better visibility.
- **Mythic+ Integration**: Dynamic dungeon list population and color-coded score tracking.

### Bug Fixes
- **Lua Compatibility**: Fixed `table.unpack` errors in Retail WoW environment.
- **UI Stability**: Added safety guards in `UpdateUI` to prevent crashes during frame initialization.

### Optimizations
- **Frame Pooling**: Implemented full pooling for the Alts grid, eliminating frame churn and stutter.
- **Combat Lockdown**: Synchronization is now paused during combat to ensure zero impact on gameplay performance.
- **Event Throttling**: Increased debounce timer to 1.0s for more efficient background processing.

## v0.3.3a (2026-03-01)

### Features
- **Release Maintenance**: Version bump and repository synchronization.

## v0.3.3 (2026-03-01)

### Features
- **Release Maintenance**: Version bump and repository synchronization.

## v0.3.2 (2026-03-01)

### Features
- **Tracking Manager**: New integrated system for managing auras, cooldowns, and custom tracks with real-time visual feedback.
- **Prey Bar**: Performance-optimized API-driven hunt tracker with zone-based visibility and robust text handling.

### Bug Fixes
- **UI Taint Prevention**: Implemented surgical filtering for Warband World Quests and other protected Blizzard widgets to prevent UI crashes.
- **Vehicle UI**: Added `issecretvalue` guards to action count comparisons, preventing taint when using vehicle bars with protected actions.
- **Minimap Autozoom**: Fixed logic to correctly respect the "enable autozoom" setting on login and mount. Added reactive callbacks to the options panel for immediate feedback.
- **Minimap Collector**: Hardened the button collector to use surgical prefix matching (`^Minimap`, `^AreaPOI`), ensuring legitimate addons (like KnowledgePointsTracker) are collected while Blizzard frames are ignored.

### Optimizations
- **Minimap Performance**: Comprehensive CPU optimization including global localization, a skinning cache for buttons, and a smarter collection cycle to reduce overhead.
- **Prey Bar**: Localized functions, throttled API calls, and data-change gating to ensure minimal impact on game performance.
