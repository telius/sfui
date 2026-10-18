# changelog

## v1.108 (2026-10-18)

### features

- **companion pet frame for camelot hunters & warlocks**: added a dedicated pet unit frame anchored to the right of the player health bar with matching theme, borders, health, power, level, and pet happiness tracking (`frames/bars/pet.lua`, `sfui.toc`, `config.lua`, `frames/options/tabs/tab_bars.lua`).
- **out-of-combat visibility options**: added dynamic visibility controls for player health, power, and pet bars with options to always show out of combat, show on missing health (player or pet), show on missing power or rage, show while casting/channeling, and show on friendly target (`frames/bars/bars.lua`, `frames/bars/pet.lua`, `config.lua`, `common.lua`, `frames/options/tabs/tab_bars.lua`).
- **hunter ammo counter on power bar**: added live ammo count indicator anchored on the mana bar for hunters in camelot (`frames/bars/bars.lua`).

### improvements & bug fixes

- **auto-equip lower level ammo on depletion**: resolved an issue where empty equipped ammo slots outscored bag ammo and failed to auto-equip lower-level reserve ammo stacks upon running out of ammo; implemented direct slot 0 cursor equipping and hooked inventory change events (`frames/gear/highest.lua`, `frames/gear/engine.lua`).
- **target-based defense & avoidance calculations**: defense rating, armor damage reduction, miss, dodge, parry, block, and crit reduction are now calculated dynamically against the current target's level (defaulting to +3 boss when no target is selected), with shortened row descriptions to eliminate text overlap (`frames/character/infopanel.lua`).
- **pet action button secure handling**: resolved protected action button state errors on pet action bars (`frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`).
- **minimap system text font size**: reduced the system fps/ms text in the minimap button collection bar by 2 points (`frames/map/system.lua`).
