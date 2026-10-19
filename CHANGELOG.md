# changelog

## v1.113 (2026-10-19)

### features

- **dark gloomy options tab icons**:
  - assigned a unique, dark gloomy death knight, shadow priest, and affliction warlock themed spell icon to all 23 tabs in the options panel (`config.lua`, `frames/options/options.lua`, `frames/options/tabs/tab_*.lua`, `frames/themes/tab_theme.lua`).
  - verified all tab icon textures across both classic forever and retail clients, updating class utility (`Spell_Shadow_GhostKey`), combat text (`Spell_Shadow_ShadowWordPain`), gear swapper (`inv_chest_cloth_17`), research (`INV_Misc_Book_09`), and theme (`Spell_Shadow_AntiShadow`) to ensure universal cross-client availability (`frames/options/options.lua`, `frames/options/tabs/tab_classutility.lua`, `frames/options/tabs/tab_combattext.lua`, `frames/options/tabs/tab_gear.lua`, `frames/options/tabs/tab_research.lua`, `frames/themes/tab_theme.lua`).
  - integrated moody atmospheric icon lighting with gloomy resting vertex tinting, hover illumination, and full brightness on tab selection (`frames/options/options.lua`).
  - widened tab buttons and the options container slightly to fit icons with clean 1px dark borders and edge-cropped textures without text clipping (`config.lua`, `frames/options/options.lua`).
- **account-wide theme settings & camelot bronze default**:
  - configured theme settings to persist account-wide in `SfuiDB.theme` across all characters (`core.lua`, `frames/themes/engine.lua`, `frames/themes/tab_theme.lua`).
  - set the default theme mode on classic forever / camelot to bronze instead of modern (`config.lua`, `core.lua`, `common.lua`, `frames/themes/engine.lua`).
  - added full support for bronze as a first-class theme identifier and camelot alias across the theme engine, options tab, and database (`frames/themes/engine.lua`, `frames/themes/tab_theme.lua`).
  - synchronized corner brackets, textured backgrounds, button styles, minimap art, and custom accent/highlight swatches with account-wide settings (`frames/themes/engine.lua`, `frames/themes/tab_theme.lua`).

### improvements & bug fixes

- **minimap system bar discord removal**:
  - removed discord integration status, guild channel indicators, and voice engine displays from the minimap system button tooltip (`frames/map/system.lua`).
  - removed alt-click context menu options for discord authorization and voice provider toggling (`frames/map/system.lua`).
  - unregistered discord and voice chat status update events (`frames/map/system.lua`).
- **buff & consumable tracking updates**:
  - updated buff reminder data tables and consumable item scan filters (`frames/reminders/buffs.lua`, `frames/reminders/buffs_data.lua`, `frames/reminders/buffs_scan.lua`).
- **quest log & layout cleanup**:
  - streamlined objective tracking and quest block layout handling (`frames/quests/engine/q_layout.lua`, `frames/quests/engine/q_tracker.lua`).
