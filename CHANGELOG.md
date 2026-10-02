# Changelog

## v12.1.0-65 (2026-10-02)

### Features & Major Improvements
- **Theme Engine Overhaul (`frames/themes/engine.lua`, `frames/themes/camelot.lua`)**:
  - Overhauled core theme management with dynamic theme switching, window registration (`RegisterWindow`), custom backdrop styles, border textures, status bar skins, and font presets.
  - Implemented comprehensive Camelot theme support with classic-authentic parchment textures, ornate stone borders, and retro UI styling.
  - Added real-time theme propagation across registered addon frames upon active theme profile changes.

- **Target Frame & Threat System Polish (`frames/bars/target.lua`, `frames/bars/threat.lua`, `frames/bars/bars.lua`)**:
  - Refined layout, buff/debuff display, threat indicators, elite/boss dragon crests, and dynamic class/reaction power bar colors.
  - Hardened unit values and combat comparisons against secret number comparisons to eliminate UI taint in combat and PvP.
  - Improved vehicle seat transitions, swing timer responsiveness, and player incoming heal prediction synchronization.

- **Dispatcher & Event Subsystem (`dispatcher.lua`)**:
  - Replaced single snapshot table with a re-entrant snapshot pool (`_snapPool`, `_snapDepth`) to eliminate nil-slot errors during nested event dispatching.
  - Added defensive callback validation and universal messaging aliases (`RegisterCallback`, `RegisterMessage`, `SendMessage`).

- **Gear, Stats & Proficiencies (`frames/gear/`)**:
  - Enhanced item caching, weapon proficiency checks, stat score calculations, and bonus roll automation.
  - Restored battle-tested Encounter Journal and Mythic+ loot browser architecture in `frames/gear/`.

- **Quests & Objective Tracker (`frames/quests/`)**:
  - Optimized quest tracker blocks, layout management, objective item usability, world quests, scenario criteria, and Camelot quest log integration.

- **Options & Interface Controls**:
  - Updated theme options tab, bars customization, and automation preferences.
