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
