## v0.4.1 (2026-03-06)

### Features
- **Merchant UI Refactor**: Completely rebuilt the merchant frame into a **2-column vertical scrolling list**. Replaced paged navigation with intuitive row-by-row scrolling.
- **Improved Merchant Frame**: Adjusted dimensions (425x620) for a cleaner list view, fitting 20 items per view with a vertical scrollbar.
- **Alts UI Profession Tracking**: Integrated standalone weekly Knowledge Point tracking for The War Within and Midnight expansions.
- **Profession Display**: Tracks Treatises, Weekly Quests, and Treasures/Drops. Shows skill level, done/total progress, and detailed tooltips.
- **Dynamic Alts Frame Sizing**: Frame height naturally shrinks/expands when categories in the sidebar are collapsed/expanded.

### Optimizations
- **Frame-Rate Stability**: Implemented frame-level debouncing for `Prey` and `Alts` UI updates, eliminating redundant redraws during high-frequency events.
- **EJ Data Caching**: Cached Encounter Journal (EJ) lookups in `alts.lua` for significant performance gains when syncing multiple characters.
- **Resource Management**: Localized and cached character-specific data within synchronization loops to minimize API overhead.

### Bug Fixes
- **Alts Grid Collision**: Fixed a rendering bug where M0 grid icons and Vault slots would overlap.
- **C_Timer Linting**: Standardized `C_Timer` references across all frames to prevent potential script errors.

## v0.4.0 (2026-03-05)
- **Comprehensive Code Audit**: Addressed multiple core execution bottlenecks to stabilize baseline memory footprint.
- **UI Element Pooling**: Rewrote dropdown menus to reuse elements natively, eliminating a persistent memory leak.
- **Event Debouncing**: Throttled high-frequency events like `QUEST_LOG_UPDATE` for the Prey tracker.
- **Resource Caching**: Implemented a per-tick cache for cooldown APIs, reducing `pcall` barrage down to one call per unique ID per cycle.
- **Memory Management**: Hoisted allocations and reused stable tables across the Merchant, Minimap, and Options modules.
