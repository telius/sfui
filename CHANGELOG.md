# changelog

## v1.144 (2026-11-10)

### new features & improvements

- **camelot dungeon journal interactive maps, world map overlay & routes (`frames/dungeonjournal/dj_map.lua`, `frames/dungeonjournal/dungeonjournal.lua`, `frames/dungeonjournal/dj_bosses.lua`, `frames/dungeonjournal/dj_quests.lua`, `frames/map/providers/pins_dungeonjournal.lua`, `data/dj_camelot.lua`, `data/dj_maps_camelot.lua`, `media/dungeonmaps/`, `sfui.toc`)**:
  - integrated self-contained pre-patched classic dungeon floor maps and custom forever dungeon maps (`ruins of lordaeron`, `darkwhisper gorge`, `mount hyjal`, `outland`, `timbermaw hold`, `uldamar`, `winterveil vale`, and full `wailing caverns` map) across `30` mapped dungeons.
  - added a new `map` tab (set as the default tab when opening the dungeon journal) featuring multi-floor selector pills, `181` interactive boss pins with loot/ability tooltips and shift-click chat links, `49` in-dungeon quest pins, floor transition/entrance markers, and a collapsible travel route guide (`sfui.dj_camelot.routes`).
  - added an automatic world map (`m` key) in-dungeon overlay that displays the active dungeon floor map, boss pins, quest pins, and live player position arrow when opening the world map inside a mapped instance.
  - added `locate on map` buttons to boss cards in the `bosses` tab and quest rows in the `quests` tab, supporting both in-dungeon map pin highlighting and external zone questgiver / turn-in world map waypoints.
  - expanded `data/dj_camelot.lua` with boss rosters and loot tables for `ruins of lordaeron`, `uldamar`, and `winterveil vale`.
- **paladin righteous fury gearset-only reminder (`frames/reminders/buffs_data.lua`, `frames/reminders/buffs_scan.lua`, `core/talents.lua`, `frames/gear/gear.lua`, `frames/gear/gear_camelot.lua`, `frames/gear/engine.lua`)**:
  - updated the paladin `righteous_fury` (`25780`) buff reminder check so it evaluates only whether the protection gearset is active (`prot` / `tank` role in the gear manager or an equipped protection set in `C_EquipmentSet`), regardless of talent specialization, protection spells, or group/lfg role.
  - synchronized gear manager role switches, equipment set swaps (`EQUIPMENT_SETS_CHANGED`, `EQUIPMENT_SWAP_FINISHED`, `SFUI_GEAR_ROLE_CHANGED`), and naked mode toggles to immediately refresh buff reminder eligibility and scan auras.
- **buff scanner & radial ring cpu/memory optimizations (`frames/reminders/buffs_scan.lua`, `frames/ring/ring.lua`, `core/talents.lua`)**:
  - pre-computed lowercased buff and spellbook names once in `RefreshSpellKnowledge` to eliminate per-scan string allocations during aura checks.
  - added scan result change detection (`prevResultKeys`) in `sfui.buffs.scan.RunScan` and deferred radial ring rebuilds (`sfui.ring.request_rebuild`) via a dirty flag while the ring is closed, avoiding background bag scans on routine aura updates.
