# Changelog

## v12.1.0-76 (2026-10-06)

### fixes

- **quest expand state reset**: `sfui.questlog.GetState()` (`frames/quests/engine/q_tracker.lua`) is now the single quest log state source. it no longer deletes the table that achievements, activities and collectables used for expand/collapse (renamed to `expandedBlocks`), so their state survives tracker refreshes.
- **broken debounces / throttles**: `C_Timer.After` returns nil, so the timer handles in `frames/dungeonjournal/dj_sidebar.lua`, `frames/dungeonjournal/dj_quests.lua`, `frames/dungeonjournal/dj_pins.lua` and the scan throttle in `frames/reminders/buffs_scan.lua` never debounced anything. they now use `sfui.common.debounce` or a pending flag.
- **recipe tooltip hook**: the legacy fallback in `frames/alts/recipes.lua` hooks both the blizzard tooltip and the private addon tooltip again. `frames/dungeonjournal/dj_tooltips.lua` also annotates the private tooltip.
- **alts manager header**: the header no longer sits below the theme frame (`frames/alts/alts.lua`, `frames/themes/engine.lua`).
- **merchant max buy**: `max` in the quantity dialog now fills exactly one stack (`frames/merchant/merchant_utility.lua`). it uses the merchant's per-purchase stack cap, counts in items, and limits to what you can afford in gold, items or currency and to limited stock. it rounds down to whole merchant bundles. the dialog now opens with one bundle filled in, and its buttons are lowercase.
- **assigned spell alert**: the `alert` option in assigned spell overrides now works. the icon glows while its buff is missing from you (`frames/tracking/trackedicons.lua`). in combat it reads blizzard's hidden cooldown manager, and when auras can't be read it keeps the last known state. the section is now retail only, and its labels and tooltips are lowercase and match what the options do (`frames/tracking/trackedoptions.lua`).
- **camelot spec resolver**: resolved error where `C_SpecializationInfo.GetTalentInfo` required `query.tier` on the camelot client build (`core/talents_camelot.lua`). talent trees and points spent are now evaluated using blizzard's native camelot talent architecture (`C_SpecializationInfo.GetCombatConfigIDForSpecGroup` and `C_Traits.GetGroupCurrencyInfo`), accurately resolving tree dominance, points spent, and canonical spec ids.
- **camelot bear spec id & role differentiation**: added dedicated camelot spec id `14844` for guardian bear (`core/talents.lua`, `core/talents_camelot.lua`, `core/bridge.lua`, `data/rules.lua`, `data/stats.lua`, `config.lua`, `frames/gear/highest.lua`, `frames/gear/gear_camelot.lua`). druid feral combat now automatically differentiates between cat (`14842`, dps) and bear (`14844`, tank) based on thick hide, primal bite, or auto-signup/dungeon finder tank roles with hot-track caching.
- **druid powerbars spec colors**: druid primary and secondary powerbars now resolve directly from `spec_colors` across all shapeshift forms (`frames/bars/bars.lua`, `config.lua`, `core.lua`, `core/talents_camelot.lua`). bear rage uses `14844` (crimson), cat energy and combo points use `14842` (amber), and humanoid mana uses `1484` (configurable white default in `spec_colors`).
- **tracked icons secret aura safety & combat initialization**:
  - resolved secret boolean crash in `frames/tracking/trackedicons.lua` (`attempt to perform boolean test on field 'isFullUpdate'`) triggered on death/wipes during raid and m+ encounters by removing unsafe `updateInfo` boolean evaluation from `UNIT_AURA` and safely throttling out-of-combat aura ticks to 0.5s.
  - fixed combat initialization and visibility latency where tracked icons could take multiple combat cycles to show up: `UpdatePanelLayout` now constructs and positions icon child frames during initial setup regardless of visibility, visibility events hook immediately in `initialize()`, and combat transition events pass directly to `CheckPanelVisibility`, `Update`, and `UpdateIconState` for instantaneous combat display.

### features

- **dungeon journal level filter**: the sidebar shows only dungeons in your level range by default. the new `all` toggle (and the context menu) shows every dungeon.
- **nine-slice theme infrastructure (parked)**: `frames/themes/engine.lua` gains a `nineslice` window style built on blizzard frame layouts, plus `sfui.theme.IsThemeAvailable` / `HasNineSliceLayout` art checks. two sets, maw and corrupted, are kept in `frames/themes/nineslice_themes.lua` but not registered, so the theme picker doesn't offer them yet. the theme picker in `frames/themes/tab_theme.lua` now lays its buttons out in a grid and shows each theme's description on hover.
- **theme accent colours**: the accent / highlight colour pickers now take effect. `sfui.theme.GetPalette()` lays your colours over the active theme's palette.
- **tracking manager theming**: the window, tabs, sections, anchor/growth pickers and the assignments panel follow the active theme (`frames/tracking/trackedoptions.lua`, `frames/tracking/cdm.lua`).
- **minimap resting tooltip**: the resting icon shows a minimal hover tooltip (`frames/automation/minimap.lua`).

### architecture

- **private tooltip everywhere**: all addon tooltips now go through `sfui.common.get_tooltip()` (`SfuiGameTooltip`). they're hidden with the new `sfui.common.hide_tooltip()`, and comparison tooltips are wired up in `core/items.lua`.
- **new shared helpers**:
  - in `common.lua`: `is_addon_loaded`, `ensure_addon_loaded`, `get_addon_metadata`, `get_player_faction` and `debounce`.
  - in `core/widgets.lua`: `attach_tooltip`, `apply_flat_backdrop`, `create_pool` and `create_icon_toggle`.
- **shared quest helpers**: duplicate `IsQuestWatched`, `IsWorldQuest`, `AutoTrackQuest`, `TryInsertQuestLink`, `FormatQuestTimer` and `IsClassQuest` code from `frames/quests/modules/q_quests.lua`, `frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_camelot_class.lua` and `frames/quests/modules/q_worldquests.lua` now lives in the new `frames/quests/helpers/q_common.lua`.
- **api standardization**:
  - item info goes through `sfui.common.get_item_info` / `sfui.common.get_item_instant_info`.
  - player class goes through `sfui.common.get_player_class` / `sfui.common.get_player_class_id`.
  - addon loading goes through the new addon wrappers.
  - cvars go through `sfui.common.get_cvar` / `sfui.common.set_cvar`.
  - bar textures go through `sfui.widgets.get_bar_texture`.
  - dead raw-api fallbacks were removed.
- **dungeon journal cleanup**:
  - inline backdrop literals use `apply_flat_backdrop`.
  - eye and `all` buttons use `create_icon_toggle`.
  - character-scoped options persist through one `PersistCharOption` path.
- **portals**: cooldown border and text code is hoisted into `set_cd_border` / `set_cd_text`.
- **lowercase pass**: about 200 capitalized ui labels and tooltip lines were lowercased.
- **docs**: `.agent/workflows/methods.md` now settles the tooltip rule and documents the dropdown `GLOBAL_MOUSE_DOWN` exception, the `C_Timer.After` pitfall and a shared-helper reference table.
