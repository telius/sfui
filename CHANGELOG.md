# changelog

## v1.133 (2026-11-04)

### features & improvements

- **wow forever launch raids & attunements (`frames/alts/alts_camelot.lua`, `data/dj_camelot.lua`, `frames/map/providers/pins_dungeonjournal.lua`)**:
  - updated forever raid lockouts in `frames/alts/alts_camelot.lua` to the 3 launch raids: the barrow deeps (10-player, 7-day reset), hyjal summit (20-player, 7-day reset), and onyxia's lair (40-player, 5-day reset).
  - removed the legacy classic dungeon/raid attunement grid from `frames/alts/alts_camelot.lua` and replaced it with a dedicated `onyxia attune` row under raid lockouts tracking drakefire amulet (`16309`) and alliance/horde onyxia attunement quest completion (`6502` / `4974` / `6602` / `6584` / `4875`).
  - updated `sfui.dj_camelot.raids` and `sfui.dj_camelot.questCoords` in `data/dj_camelot.lua` to add the barrow deeps, hyjal summit, and onyxia's lair (with full boss rosters, entrance coordinates, and drakefire amulet quest chains) while pruning unimplemented raid definitions and world map pins.
- **classic & forever consumables & buffs radial ring (`frames/ring/providers/ring_specs.lua`, `frames/options/tabs/tab_ring.lua`)**:
  - repurposed the `specs` (`ALT-X` / `SHIFT-ALT-X`) quickdraw ring on classic and forever (`not sfui.isRetail`) into a `"consumables & buffs"` ring (`MAX_SLICES = 12`).
  - populated the ring with missing/expiring class & tracking buffs (`sfui.buffs.scan`), the player's selected or highest well fed food (`sfui.buffs.consumables.GetSelectedFood`), conjured food & water (`C_Item.IsItemConjured`), warlock healthstones, and all alchemy potions found in bags.
- **module architecture, event consolidation & cleanup (`core/module.lua`, `dispatcher.lua`, `common.lua`, `frames/themes/engine.lua`, `frames/portals/portal_popup.lua`, `frames/map/system.lua`)**:
  - consolidated duplicate standalone `CreateFrame("Frame")` event listeners across `common.lua`, `frames/map/location.lua`, `frames/map/minimap.lua`, `frames/map/square.lua`, `frames/map/status.lua`, `frames/map/buttons.lua`, and `frames/actionbars/mouseover.lua` into `sfui.events.RegisterEvent`.
  - removed legacy unused `frames/character/charactersheet.lua` and unused `NineSliceThemes` table in `frames/themes/engine.lua`.
  - fixed `InitModule` signature mismatch in `frames/map/system.lua`, added nil-safe method forwarders in `frames/themes/engine.lua`, and replaced deprecated `C_Container.GetContainerItemLink` call in `frames/portals/portal_popup.lua`.

### bug fixes

- **multi-account sync `ERR_NOT_IN_GROUP` chat spam fix (`frames/sync/codec.lua`, `frames/sync/sync.lua`, `frames/sync/merge.lua`, `frames/sync/multibox.lua`)**:
  - added `codec.ResolveGroupChannel()` and `codec.PurgeGroupQueue()` in `frames/sync/codec.lua` with pre-flight channel validation in `dispatch_raw_packet()` so queued `PARTY` / `RAID` / `INSTANCE_CHAT` packets are dropped cleanly instead of firing `SendAddonMessage` when not in a group.
  - gated group sync broadcasts in `frames/sync/sync.lua` on active synced party members (or explicit pairing/passcode discovery) and added quest-log diff detection in `frames/sync/merge.lua` so `QUEST_LOG_UPDATE` only broadcasts `DATA_QUESTS` when quest progress actually changes.
