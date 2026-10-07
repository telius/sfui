# Changelog

## v12.1.0-81 (2026-10-08)

### features & enhancements

- **buff reminders (resource tracking)**: added gathering tracking reminders for "find minerals" (mining) and "find herbs" (herbalism) in `frames/reminders/buffs_data.lua` and `frames/reminders/buffs_scan.lua` with mutual exclusivity handling for dual gatherers, click-to-cast support, and options toggles in `frames/options/tabs/tab_buffs.lua`.
- **buff reminders (scrollable food selection)**: made the "well fed" food reminder icon scrollable through all food items in inventory providing buffs in `frames/reminders/buffs_consumables.lua` and `frames/reminders/buffs.lua`, with matching item tooltips, counts, and click-to-eat support.
- **shaman totem bar**: added standalone totem bar in `frames/bars/totembar.lua` with mousewheel spell selection per element, right-click destruction, and automated cast sequencing with keybinding support.
- **cooldown manager (span width threshold)**: updated `frames/tracking/cdm.lua` to only span width across 4 or more icons.

### bug fixes & improvements

- **totem sequencer keybind display**: fixed a lua binary operator expression in `frames/options/tabs/tab_bars.lua` where multi-value returns from `sfui.totembar.GetBoundKey()` were truncated by an `and` guard, causing bound keys to incorrectly display as "not bound".
- **totem bar learned ability filtering**: filtered totem bar icons in `frames/bars/totembar.lua` to hide totem elements until their corresponding totem type spells are learned.
