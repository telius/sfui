# changelog

## v1.147 (2026-11-12)

### new features & improvements

- **universal `/sfui find` search & utility modules (`frames/find.lua`, `frames/mem.lua`, `frames/merchant/merchant_utility.lua`, `frames/ring/providers/ring_utility.lua`, `frames/actionbars/movers.lua`, `commands.lua`, `sfui.toc`)**:
  - added `/sfui find` (`frames/find.lua`) to search items across bags, bank, warband, alts, profession recipes, fishing spots, dungeon bosses, and quest rewards from one unified interface, plus `/sfui mem` memory diagnostics (`frames/mem.lua`), merchant utility helpers (`frames/merchant/merchant_utility.lua`), radial ring utility actions (`frames/ring/providers/ring_utility.lua`), and expanded mover snapping/controls (`frames/actionbars/movers.lua`).
- **shared core subsystems & addon interoperability (`core/inventory.lua`, `core/navigation.lua`, `core/queststate.lua`, `core/state.lua`, `core/tooltips.lua`, `core/safety.lua`, `core/module.lua`, `frames/gear/highest.lua`, `frames/fishing/fishing_atlas.lua`, `frames/professions/browser.lua`, `frames/quests/modules/q_recipes.lua`, `frames/quests/modules/q_camelot_recipes.lua`)**:
  - introduced shared inventory indexing (`core/inventory.lua`), combat-safe map/waypoint navigation (`core/navigation.lua`), quest chain state evaluation (`core/queststate.lua`), reactive state pub/sub (`core/state.lua`), centralized tooltip hooks (`core/tooltips.lua`), and module error boundaries (`core/safety.lua`, `core/module.lua`).
  - added `DialogueUI` quest reward upgrade badge support on both retail and forever (`frames/gear/highest.lua`), and bound recipe & fishing atlas quick-open links to `ctrl-click` so `alt` hover item-id inspection never conflicts.
- **camelot dungeon journal, interactive maps & quest chain pins (`frames/dungeonjournal/dungeonjournal.lua`, `frames/dungeonjournal/dj_map.lua`, `frames/dungeonjournal/dj_quests.lua`, `frames/dungeonjournal/dj_bosses.lua`, `frames/map/providers/pins_dungeonjournal.lua`, `data/dj_camelot.lua`, `data/dj_maps_camelot.lua`, `data/fishing_camelot.lua`)**:
  - audited and updated camelot quest chains, faction restrictions, prerequisite gates, and world map quest pins so multi-step chains (such as `a vengeful fate` and `earthen echo`) point to the active starting prerequisite step instead of locked downstream givers (`data/dj_camelot.lua`, `frames/dungeonjournal/dj_quests.lua`, `frames/map/providers/pins_dungeonjournal.lua`).
  - fixed reverse-floor phantom transition ladders on multi-floor dungeon maps, restored hover-only traversal notes (`razorfen kraul` roogug hints and `gnomeregan` jump label), added quest-target boss portrait badges and journal navigation (`highland horror`), and added `C_Map` multi-tile fallback rendering (`frames/dungeonjournal/dj_map.lua`, `data/dj_maps_camelot.lua`).

### bug fixes & safety hardening

- **advisory-only quest reward choices & sync safety (`frames/sync/quests.lua`, `frames/automation/automation.lua`)**:
  - ensured quest completion never auto-picks or accepts a reward whenever multiple reward choices exist, keeping upgrade badges strictly advisory during both solo turn-ins and multibox quest sync.
- **secret-value, tooltip & combat lockdown fixes (`frames/bars/target.lua`, `frames/bars/pet.lua`, `frames/bars/soulfragments.lua`, `frames/bars/swing.lua`, `frames/bars/threat.lua`, `core/items.lua`, `core/tooltips.lua`, `frames/automation/automation.lua`, `core/navigation.lua`, `frames/dungeonjournal/dj_map.lua`)**:
  - fixed secret-key table indexing errors on target bar updates (`frames/bars/target.lua`), guarded invalid/secret arguments before `GetItemInfo` and `C_TooltipInfo` calls (`core/items.lua`, `core/tooltips.lua`, `frames/automation/automation.lua`), and gated world map opening behind `InCombatLockdown()` and `C_Map.OpenWorldMap`.
