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
- **Terminology**: Updated "Dragonriding" to **"Skyriding"** across all options and tooltips.

### Cleanup
- **Codebase**: Fully removed all legacy Dragonflight-specific logic, trait requirements, and trait tree IDs.
- **Reminders**: Removed legacy Draconic Augment Rune; system now only tracks current TWW runes.
- **Config**: Optimized repair node handling for TWW and upcoming expansions (Midnight).

## v0.1.3.c (2026-01-31)

### Features
- **Decor Filter**: Added option to disable decor caching/filtering in Merchant settings (clears cache when enabled).
- **Automation**: Consolidated "Auto-Sell Greys" and "Auto-Repair" into the Automation tab.
- **UI**: Lowercased all text in the Options Panel for a cleaner aesthetic.

### Code Cleanup
- **Optimization**: Added aliases for global API functions in `castbar.lua` and `options.lua`.
- **Refactor**: Cleaned up duplicate code and resolved lint warnings in `options.lua`.

## v0.1.3.b (2026-01-31)

### Refactor
- Centralized configuration: Moved hardcoded settings (frame positions, sizes, throttles) from `bars.lua`, `castbar.lua` (added position config), and `reminders.lua` to `config.lua`.
- Centralized utility functions: Added `sfui.common` helpers for group iteration, class checking, and item ID extraction.
- Optimized merchant frame: Implemented table reuse and hoisted invariant logic.
- Code cleanup: Removed unused variables and dead code from `research.lua`.

### Automation
- Added `automation.lua`: Includes auto-accept functionality for role checks and enhanced LFG signup (double-click to sign up, auto-confirm dialog).

## v0.1.3.a (2026-01-30)

### Refactor
- Standardized all custom functions and methods to lowercase snake_case for codebase consistency.
- Standardized addon namespace and folder references to lowercase "sfui".
- Fixed various "nil value" errors resulting from capitalization mismatches.
- Removed redundant configuration lines in merchant frame logic.

### Bug Fixes
- Add package-as directive for WowUp compatibility (addon folder now named sfui)

## v0.1.2 (2026-01-30)

### Documentation
- Add Masque support information and screenshot attribution
- Clarify dynamic group composition detection for buffs
- Expand buff abbreviations for readability (Mark of the Wild, Evoker buffs)
- Add healthbar and stagger screenshot
- Remove dragonflying_warning.png (character name exposure)

## v0.1.1 (2026-01-29)

### Features
- Custom options header and README cleanup
- Use individual AceDB-3.0 library to reduce package size

### Bug Fixes
- Correct color code to 6600FF (purple) instead of 0066FF (blue)
- Refine README tone, remove hype and bolding
- Update player status section

## v0.1.0

### Features
- Add `ignoreThreshold` option to buff checks to bypass duration requirements for specific buffs like Soulstone
- Add tracking for Soulstone and Healthstone reminders, and update the weapon oil icon
- Add a new reminders system, enhance bar customization with texture selection and visibility options, and enable draggable positioning for the minimap button bar

### Bug Fixes
- Fix merchant filters, set addon icon, move decor cache status to debug, and update castbar colors
- Refactor: Merchant filters, Vehicle UI refinements, and README overhaul. Corrected IsItemKnown bug and namespaced merchant state
- Implement warning system and refactor merchant frame and bar layout configurations
