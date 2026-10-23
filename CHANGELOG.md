# changelog

## v1.120 (2026-10-23)

### features

- **blizzard cdm tracked buffs socket (`frames/tracking/buffs.lua`)**:
  - added a dedicated, centered socket for blizzard cooldown manager category 2 (tracked buffs) items with sfui square icon skinning, 1px black borders, and pandemic glow.
  - zero-inspection architecture compliant with retail secret values (`issecretvalue`).
  - integrated with `/sfui unlock` and `/sfui cdm` for interactive positioning and moving.
  - added interactive preview dummy buffs mode with live slider updates for x offset, y offset, icon size, and icon spacing.
  - added a new "buffs" options tab in `frames/tracking/trackedoptions.lua` with configuration for visibility, combat filters, pandemic glow, coordinates, and live preview.

- **midnight abundance scenario tracker (`frames/quests/modules/q_abundance.lua`)**:
  - added dedicated midnight abundance world event scenario tracking across regional caverns.
  - dynamic multi-stage capacity tracking, stage countdown timers, altar turn-in capacity alerts, and dundun's blessing of abundance tracking.

### improvements & bug fixes

- **actionbars & pet bar grid adjustments**:
  - refined pet bar and action bar positioning, spacing, and grid snapping (`frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`).
- **minimap & square map enhancements**:
  - polished square map layout, borders, and tracking display (`frames/map/minimap.lua`, `frames/map/square.lua`).
- **quest tracker boons & scenarios**:
  - updated boon tracking helpers and scenario progress indicators (`frames/quests/helpers/q_boons.lua`, `frames/quests/modules/q_scenarios.lua`, `frames/quests/engine/q_tracker.lua`).
- **target frame styling**:
  - refined target frame elements and hide rules (`frames/bars/target.lua`, `frames/hide.lua`).
