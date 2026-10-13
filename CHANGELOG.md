# Changelog

## v1.96 (2026-10-14)

### features

- **standalone action bars module**: introduced a dedicated, fully modular action bar system (`frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`, `frames/actionbars/style.lua`) supporting bars 1 through 8, pet bar, and stance/shapeshift bar with customizable button sizing, padding, orientation, mouseover fading (`frames/actionbars/mouseover.lua`), and interactive mover frames (`frames/actionbars/movers.lua`).
- **alt mail routing system**: added automated mailbox routing management (`frames/alts/mail_data.lua`, `frames/alts/mail_engine.lua`, `frames/alts/mail_mailbox.lua`, `frames/alts/mail_ui.lua`) allowing one-click dispatching and automated recipient sorting by item category, profession material, and consumable type.
- **camelot challenges tracking**: integrated hardcore and challenge milestone tracking directly into the experience bar and quest objective tracker (`frames/experience/challenges.lua`, `frames/quests/modules/q_camelot_challenges.lua`) with custom visuals and detailed progress tooltips.
- **minimap pins**: expanded the unified map pin system (`frames/map/pins.lua`) to project pins onto the minimap with edge radius clamping and coordinate conversion.
- **standardized circular icon styling**: added a reusable circular masking utility in `core/widgets.lua` (`sfui.widgets.MakeCircleIcon`) used across map pins, tracking frames, and action bar controls.

### improvements & bug fixes

- **shapeshift & stance keybind paging**: fixed action bar keybind pagination during combat shapeshifting (`frames/actionbars/paging.lua`), binding stance state transitions cleanly to the active bar.
- **memory & frame pool optimizations**: implemented texture mask caching and pooled reusable frame tables in `frames/map/pins.lua` and `core/widgets.lua` to minimize garbage collection spikes during high-frequency pin updates.
- **consumables scanning**: refined food, drink, and buff consumable detection in `frames/reminders/buffs_consumables.lua` and `core/items.lua`, ensuring accurate detection for camelot items.
- **configuration & options**: added an action bars settings tab in `frames/options/tabs/tab_actionbars.lua` with live previews and granular bar toggles.
