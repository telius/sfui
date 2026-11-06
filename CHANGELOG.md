# changelog

## v1.140 (2026-11-06)

### features & improvements

- **paladin seals duration tracking (`frames/tracking/auras.lua`, `frames/tracking/cdm.lua`, `frames/tracking/panels.lua`, `frames/tracking/trackedbars.lua`, `frames/tracking/trackedicons.lua`, `sfui.toc`)**:
  - added dedicated aura state tracking (`frames/tracking/auras.lua`) for paladin seals (`cooldownid = 200340`, `spellid = 1323522`) in wow forever so active seal buffs can be assigned to `trackedbars` and `trackedicons`, displaying the active seal's icon, name, and 30-second countdown both out of combat and in combat.
  - guarded `C_UnitAuras` queries with `CanAccessUnitAuras()` to prevent `RequiresUnitAuraAccess` errors when player auras become secret in combat, falling back to `UNIT_SPELLCAST_SUCCEEDED` duration tracking.
- **forever first & last name resolution (`frames/alts/alts.lua`, `frames/alts/alts_camelot.lua`, `frames/alts/recipes.lua`, `frames/professions/filters.lua`, `frames/alts/mail_data.lua`, `frames/alts/mail_ui.lua`, `frames/sync/merge.lua`, `common.lua`)**:
  - resolved and displayed full character names (`first last`) across the alts manager, recipe tooltips, profession browser filters, mail routing, and sync payloads on wow forever without appending or storing server/realm names as surnames.
- **error database version purge (`core.lua`)**:
  - automatically clears `SfuiBugDB` when the addon version changes so stale errors from older releases do not persist across updates.
- **release packaging (`.pkgmeta`)**:
  - disabled `-nolib` archive generation (`enable-nolib-creation: no`).

### bug fixes

- **round minimap diel & weather icon layering (`frames/map/minimap.lua`, `frames/map/indicators.lua`, `frames/map/status.lua`)**:
  - elevated `DielFrame` and `sfui_minimap_weather` above `sfui_minimap_ring` (`framelevel + 10`) so the round minimap border ring no longer occludes the day/night and weather indicators.
- **protected `QuestLogPushQuest()` taint (`frames/sync/quests.lua`, `frames/quests/helpers/q_tooltip.lua`, `compat.lua`)**:
  - removed timer-invoked `QuestLogPushQuest()` fallback on `QUEST_ACCEPTED` and eliminated `SelectQuestLogEntry` selection mutations during objective tracker tooltip hovers.
