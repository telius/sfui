# Changelog

## v1.98 (2026-10-14)

### improvements & bug fixes

- **esc and casting taint protection**: resolved forbidden errors on protected functions (`SpellStopTargeting`, `SpellStopCasting`) when pressing escape by removing global mixin modifications in `core/map.lua` and `frames/map/pins.lua`, and updating keyboard input propagation in `frames/tracking/trackedoptions.lua`.
- **delve and labyrinth objectives**: restored missing weighted progress objectives (such as "disrupt the vilebranch") in the active delve and scenario hud (`frames/quests/q_mythic.lua`) and quest tracker scenario module (`frames/quests/modules/q_scenarios.lua`).
- **objective bullet icons**: fixed objective row icons in `frames/quests/q_mythic.lua` to render the standard blizzard objective nub atlas (`ui-questtracker-objective-nub`) with bulletpoint fallback.
- **delve percentage formatting**: cleaned up progress bar percentage display in `frames/quests/q_mythic.lua` to show integer values without redundant decimals for delves and scenarios.
- **criteria description fallbacks**: enhanced step-level weighted progress retrieval and fallback mechanisms across `frames/quests/q_mythic.lua` and `frames/quests/modules/q_scenarios.lua` to support delves and tiered entrances without explicit criteria lists.
