# Changelog

## v12.1.0-81 (2026-10-08)

### features & enhancements

- **buff reminders (resource tracking)**: added gathering tracking reminders for "find minerals" (mining) and "find herbs" (herbalism) in `frames/reminders/buffs_data.lua` and `frames/reminders/buffs_scan.lua` with mutual exclusivity handling for dual gatherers, click-to-cast support, and options toggles in `frames/options/tabs/tab_buffs.lua`.
- **buff reminders (scrollable food selection)**: made the "well fed" food reminder icon scrollable through all food items in inventory providing buffs in `frames/reminders/buffs_consumables.lua` and `frames/reminders/buffs.lua`, with matching item tooltips, counts, and click-to-eat support.
- **shaman totem bar**: added standalone totem bar in `frames/bars/totembar.lua` with mousewheel spell selection per element, right-click destruction, and automated cast sequencing with keybinding support.
- **cooldown manager (span width threshold)**: updated `frames/tracking/cdm.lua` to only span width across 4 or more icons.
- **mage portals & teleports (camelot / classic)**: added `frames/portals/portals_camelot.lua` providing a travel hub for camelot/classic with real-time rune reagent tracking (rune of teleportation, rune of portals), left-click self teleport, right-click party portal casting, hearthstone with inn binding display, and engineering teleporter support.
- **modular portals architecture**: split `frames/portals/portals.lua` into a shared core foundation, `frames/portals/portals_standard.lua` for retail (m+ season portals, midnight portals, travel toys, cosmetic hearthstone wheel, legacy dropdowns), and `frames/portals/portals_camelot.lua` for classic/camelot.
- **dedicated portals keybind & options tab**: added dedicated `frames/options/tabs/tab_portals.lua` and unified portal keybinding management (`sfui.keybinds.GetPortalsKey`, `SetPortalsKey`, `UnbindPortalsKey`) across both retail and camelot clients, keeping `frames/options/tabs/tab_classutility.lua` dedicated exclusively to classic class mechanics (shaman totem sequencing and warlock soul shard purge).
- **keybindings engine separation & dynamic filtering**: added native client-specific bindings files (`Bindings_Standard.xml` for retail and `Bindings_Camelot.xml` for classic/camelot) alongside root `Bindings.xml` so retail excludes class utility keybinds while camelot receives the single unified keybind, unified portal keybinding to `SFUI_PORTALS` across all clients, dynamically filtered blizzard's keybindings settings menu in `commands.lua`, and removed deprecated pet manager, obsolete better fishing, and duplicate portal bindings.

### bug fixes & improvements

- **totem sequencer keybind display**: fixed a lua binary operator expression in `frames/options/tabs/tab_bars.lua` where multi-value returns from `sfui.totembar.GetBoundKey()` were truncated by an `and` guard, causing bound keys to incorrectly display as "not bound".
- **totem bar learned ability filtering**: filtered totem bar icons in `frames/bars/totembar.lua` to hide totem elements until their corresponding totem type spells are learned.
- **secret value tooltip taint fix**: added secret-value checks and `is_valid_id` guards across tooltip id annotation in `frames/automation/automation.lua` and `frames/alts/recipes.lua` to prevent lua comparison errors when hovering over private/secret auras in delves and restricted combat encounters.
- **gear manager pawn string relocated to options**: removed the pawn string input box and label from the gear manager card window in `frames/gear/gear.lua` to fix overflow outside the frame boundary, and moved dedicated pawn string import with live validation, stat weight parsing, and save/clear actions into `frames/options/tabs/tab_gear.lua` for retail specs.
- **gear manager stat & operator button positioning**: fixed anchoring chain and spacing for the bottom stat row in `frames/gear/gear.lua`, resolving operator button overlap on the first stat, restoring the missing operator before the final stat, and re-enabling interactive clicking on operator buttons to toggle between strict priority (`>`) and equal priority (`=`).

