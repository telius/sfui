# Changelog

## v12.1.0-61 (2026-09-30)

### Fixes & Major Improvements
- **Alt Persistence & Teardown Guard Overhaul (`frames/alts/alts.lua`, `frames/alts/alts_camelot.lua`)**:
  - Eliminated data corruption caused by world teardown API queries on `PLAYER_LEAVING_WORLD` during logout, quit, or zoning.
  - Added robust guards to prevent `level`, `xp`, `xpMax`, `restedXP`, `isResting`, `money`, and PvP statistics from being overwritten with zero or nil.
  - Added authentic Classic XP-per-level fallback table (`CLASSIC_XP_PER_LEVEL`) to self-heal uninitialized or corrupted alt entries.
  - Fixed false-positive max-level detection in the Classic/Camelot alts sheet (`RenderCell`), ensuring non-level-60 characters always display XP and rested XP bars.
  - Registered `UPDATE_EXHAUSTION` to keep rested XP synchronized in real time while resting in inns or capital cities.

- **Lootfeed & Taint Protection (`frames/gear/lootfeed.lua`, `frames/options/tabs/tab_lootfeed.lua`)**:
  - Protected loot link formatting and string conversion against tainted secret values in WoW 1.60.1 / Camelot.
  - Added Camelot-specific lootfeed theme selection option directly in the Lootfeed options tab.

- **UI Themes & Visual Styling (`frames/themes/`, `core/widgets.lua`)**:
  - Expanded theme engine infrastructure for Modern and Camelot aesthetic profiles, including statusbar textures and borders.
  - Refined theme switcher logic and option visibility based on active game client flavor.

- **Tracker & Minimap Refinements (`frames/minimap.lua`, `frames/quests/`)**:
  - Exposed Blizzard objective tracker helper functions and improved minimap coordinate formatting and frame handling.
