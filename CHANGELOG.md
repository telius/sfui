# Changelog

## v12.1.0-74 (2026-10-06)

### Features & Major Improvements

- **Buff Reminders Module for Camelot & Classic (`frames/reminders/`, `frames/options/tabs/tab_buffs.lua`, `sfui.toc`)**:
  - **Dynamic Class & Consumable Tracking**: Introduced dedicated reminder buttons for missing or expiring class auras, stances, paladin seals, shaman shields and weapon imbues, rogue poisons, and warlock/hunter pets.
  - **Combat & Active Presence Filtering**: Buttons automatically suppress during combat encounters (`InCombatLockdown` and combat callbacks) and stay hidden while buffs are active with sufficient duration remaining.
  - **Expiration Timers**: Automatically displays live expiration countdown timers when buffs fall below configurable thresholds (short buffs warn slider for fast-expiring spells, long buffs warn slider for standard auras).
  - **Click-to-Cast Integration**: Secure action buttons bind out of combat to the highest available rank of missing spells for immediate one-click rebuffing.
  - **High-Performance Architecture**: Aura scanning leverages player-only unit events (`RegisterUnitEvent("UNIT_AURA", "player")`), hash-indexed spell lookups, and reusable table pools to eliminate runtime memory allocation and garbage collection pauses.
  - **Layout & Options Tab**: Integrated options tab (`tab_buffs.lua`) with unlockable move overlay, interactive test preview mode, per-buff toggles, and size sliders defaulted to 36x36 pixels at bottom screen center (`y = 42`).

- **Dungeon Journal Character-Scoped Hidden State & Persistence (`frames/dungeonjournal/dungeonjournal.lua`)**:
  - **Character Storage**: Scoped hidden dungeons, pins, and quest pin overrides to character-specific saved variables (`SfuiDB.chars[playerGUID].dungeonjournal`) so exploration preferences do not leak across alts.
  - **Safe Logout Flush**: Implemented clean persistence handlers on `PLAYER_LOGOUT` and `SFUI_PERSISTENCE_FLUSH` to guarantee integrity of saved states across sessions.

- **Gear Manager Collapsed Role Bar & Naked Mode (`frames/gear/gear_camelot.lua`, `frames/gear/lootspec.lua`, `commands.lua`)**:
  - **Collapsed Role Bar**: Added quick-switch role buttons to the gear manager frame on Camelot for fast spec/role transitions.
  - **Naked Mode**: Added one-click naked action to safely unequip armor and weapons while temporarily pausing gear manager auto-equip rules.
  - **Retail Specialization Gating**: Strictly gated retail loot spec logic in `frames/gear/lootspec.lua` and `/sfui lootspec` to prevent execution on Camelot and Classic.

- **Standardized Window Headers & Castbar Decoration (`core/widgets.lua`, `frames/themes/engine.lua`, `frames/themes/camelot.lua`)**:
  - **Standardized Window Headers**: Unified window banners via `sfui.theme.CreateWindowHeader` and `sfui.widgets.create_window_header` with frame level elevation to ensure clean rendering over backdrop borders.
  - **Castbar Icon Borders**: Refined icon border backdrops and styling for crisp borders across both modern and Camelot themes.

### Bug Fixes

- **Quest Sharing API Harmonization (`compat.lua`, `frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_quests.lua`, `frames/dungeonjournal/dj_quests.lua`)**:
  - **Multi-Client Quest Sharing**: Standardized quest sharing through `sfui.api.IsQuestPushable` and `sfui.api.ShareQuest`, cascading `QuestUtil.ShareQuest`, `SelectQuestLogEntry` with `QuestLogPushQuest`, and push button handlers across all supported clients.
