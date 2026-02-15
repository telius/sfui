## v0.2.14 (2026-02-15)
### Maintenance
- **Release Automation**: Triggering new release workflow.

## v0.2.13 (2026-02-15)
### Optimizations
- **Memory Leak Fixes**: Implemented a comprehensive widget pooling system in the options panel, eliminating memory growth caused by repeated frame creation.
    - Added object pools for Sliders, Checkboxes, Buttons, Headers, and EditBoxes.
    - Refactored `UpdateSettings` and `UpdatePanelList` to intelligently reuse existing UI frames.
- **Performance**:
    - Added local aliases for WoW API globals (`CreateFrame`, `UIParent`, etc.) in `trackedbars.lua` and `trackedoptions.lua` to reduce lookup overhead.
    - Replaced deprecated `unpack` calls with local aliases.

## v0.2.12 (2026-02-15)

### Major Improvements
- **Options UI Overhaul**:
    - **Global Tab**: Removed the scroll frame from the Global settings tab for a cleaner, static layout.
    - **Left Panel (Icons)**: 
        - Removed the scroll frame from the panel list.
        - Redesigned "Add" and "Del" buttons to be compact and positioned side-by-side at the bottom.
        - Resized panel selection buttons to perfectly fit the panel width.
        - **Active State Styling**: Selected panel buttons now highlight with a **#6600FF** (purple) border and text for clear visibility.

### Bug Fixes
- **Glow Logic**:
    - **"Glow Pop" Fix**: Implemented `_pendingGlow` logic to prevent unwanted glows when regaining control after CC (e.g., Stun, Fear). Glows now only trigger after a valid cooldown cycle (> 0.1s).
    - **Taint Fix**: Added safety checks for "secret values" in cooldown durations to prevent crashes in restricted environments (M+, combat).
    - **Sustained Glows**: Fixed an issue where glows would flash for a split second; they now sustain correctly for their full duration.
- **Desaturation**:
    - Restored `HasFullControl()` check to ensure icons remain **saturated** (colored) during temporary loss-of-control events, improving visibility while CC'd.

## v0.2.11 (2026-02-14)
### Bug Fixes
- **Tracked Bars**: Fixed default Blizzard bar hiding logic to correctly use the `category` API, ensuring Essential and Utility bars remain hidden as intended.
- **Tracking Manager**: Improved first-load reliability by refining the data provider ticker, resolving the "blank tab" issue after UI reloads.
- **Hiding Stability**: Added persistent alpha overrides to prevent Blizzard frames from reappearing after certain UI events.

## v0.2.10a (2026-02-11)
### Improvements
- **Security Hardening**: Implemented robust detection and handling for "secret values" in restricted combat environments (Mythic+), preventing UI crashes when accessing protected cooldown data.
- **Tracked Icons**: Improved cooldown detection logic to correctly exclude the Global Cooldown (GCD), ensuring icons only desaturate for actual ability cooldowns.
- **Performance**: Optimized aura event handling to utilize the latest `UNIT_AURA` update signals for more efficient tracking.

## v0.2.10 (2026-02-09)
### Build
- **CI**: Fixed YAML syntax error in release workflow.
- **Packaging**: Removed redundant packager arguments and disabled nolib creation to fix WowUp installation issues.


### Changes
- **Configuration Defaults**: Updated Bone Shield to default to green (`0, 0.8, 0.067`) and hidden title. Updated Ignore Pain to default to orange (`1, 0.533, 0`).
- **Positioning Improvements**: Improved tracked bars anchoring logic to check for Rune Bar existence rather than visibility, fixing positioning delays for Death Knights.
- **Safety**: Added combat lockdown check to the Tracking Manager to prevent errors when opening it during combat.
- **Bug Fixes**:
    - Fixed the "Reset" button in Tracking Manager to properly clear and reload default settings.
    - Fixed Color Swatch not loading default colors correctly in the options panel.
    - Reverted recent "secret value" sanitization changes that caused crashes.
- **Code Cleanup**: Removed redundant comments and unused code in `trackedbars.lua` and `trackedoptions.lua`.

## v0.2.0 (2026-02-07)

### Major Features
- **Tracked Bars System**: Complete implementation of customizable buff/debuff tracking bars.
    - **Individual Bar Customization**: Each tracked spell has its own color picker, enable toggle, and max stack override.
    - **Intelligent Visibility**: Bars automatically show/hide based on combat state, talent selection, and player spec.
    - **Stack Display**: Visual segments for stacking buffs (e.g., Bone Shield showing 12 stacks).
    - **Integration**: Seamlessly integrates with Blizzard's Cooldown Viewer addon for advanced configuration.
    - **Memory Optimized**: Frame pooling and table reuse for high-performance updates.
    - **Configuration Panel**: Dedicated UI in options for managing all tracked bars.
    - **Smart Attachment**: New option to stack bars above Health Frame or Secondary Power Bar.
    - **Text Mode**: Option to display stack counts as centered text instead of duration.
    - **Refinements**: Improved text positioning, hidden icons for attached bars, and flicker-free updates.

### Improvements
- **Code Optimization**: Comprehensive refactor across 8 files for improved performance and maintainability:
    - **Configuration Centralization**: Moved all magic numbers to `config.lua` (8 new config values).
    - **Common Utilities**: Added 3 reusable helper functions to `common.lua`:
        - `scan_player_auras()` - Centralized aura scanning.
        - `create_styled_button()` - Consistent button creation.
        - `VEHICLE_KEYBIND_MAP` - Keybind lookup table.
    - **Performance**: Eliminated redundant aura scanning (~30 lines), reusable tables to reduce GC pressure.
    - **Consistency**: Unified color system using `sfui.config.colors` across all files.
    - **Configurable Throttle**: Cast bar text updates now use configurable throttle value.

### Technical Details
- Refactored `reminders.lua`, `research.lua`, `minimap.lua`, `vehicle.lua`, `castbar.lua`, `automation.lua`.
- Total: ~183 lines modified, ~77 lines reduced through consolidation.
- Zero performance regressions, full backward compatibility maintained.

## v0.1.5 (2026-02-04)

### Features
- **Automation**: Added **Match Target Mount** functionality.
    - Check target's mount and summon the same one if owned.
    - Added keybinding under SFUI category.
    - Fallback to random favorite mount if no match found.
- **Default Settings**: Enabled several convenience features by default:
    - **Auto Sell Greys**: Automatically sell poor quality items at vendors.
    - **Auto Repair**: Automatically repair gear at vendors (prioritizing guild funds).
    - **Reminders**: Enabled Solo and Everywhere reminders by default.
- **Minimap**:
    - **Cooldown Viewer**: Shift-Clicking the SFUI minimap icon now correctly opens the Blizzard Advanced Cooldown Settings panel, dynamically loading the Blizzard_CooldownViewer addon if needed.
    - **Data Broker**: Improved integration with Broker plugins.
- **Cleanup**: Removed deprecated `sfui/cooldowns.lua` module.

## v0.1.4 (2026-01-31)

### Features
- **Master's Hammer**: Complete overhaul of the repair system.
    - Implemented **Sequential Rotation**: Automatically targets damaged gear in a logical priority (Weapons/Shields first).
    - **Spam Protection**: Advances rotation immediately on click, enabling lightning-fast repairs without double-casting or cast cancellation.
    - **Keybind Support**: Added a secure click binding for Master's Hammer repair, available in the main Bindings menu.
    - UI aesthetics are now fully customizable (X/Y position and border color).
- **Castbars**:
    - New **Player Castbar**: Features **Instant Cast Tracking** (visual confirmation of instant spells). Supports Empowered stages for Evokers.
    - New **Target Castbar**: Improved visibility and distinct interruptible/non-interruptible states.
