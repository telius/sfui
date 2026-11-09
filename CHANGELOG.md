# changelog

## v1.143 (2026-11-09)

### improvements & bug fixes

- **recipe vendor source accuracy & database compilation (`frames/professions/sources.lua`, `data/recipes_camelot.lua`, `scripts/sync-recipes.py`)**:
  - corrected recipe vendor attributions for `enchant 2h weapon - lesser intellect` (`6349`), moving it off lilly in silverpine forest and mapping it to authentic classic trainers/vendors (`nata dawnstrider` in thunder bluff, `kithas` in orgrimmar, `leo sarn` in silverpine forest, and `tilli thistlefuzz` in ironforge).
  - corrected lilly's curated inventory to chest formulas (`enchant chest - minor/lesser intellect`) and mana/wizard oils.
  - pruned 20 non-vendor world/chest drop recipes mistakenly classified as limited vendor stock from `sfui.recipes.LIMITED_RECIPE_ITEMS` and `sfui.recipes.CURATED_LIMITED_VENDORS`.
  - fixed a sourcemore parser bug in `scripts/sync-recipes.py` that erroneously tagged creature drop mobs and dungeon bosses (`mekgineer thermaplugg`, `general drakkisath`, `ras frostwhisper`, `darkmaster gandling`, `dragonmaw scout`, etc.) as vendors on dual-source `[2, 5]` recipes.
  - resolved id collisions in `REPUTATION_RECIPES` and `SPECIALIZATION_RECIPES` in `scripts/sync-recipes.py`, ensuring reputation standings and specializations map strictly to valid spells without polluting unrelated recipes.
  - added `VENDOR_FACTIONS` so contested-zone vendors have explicit faction tags for host-faction safety checks (`sfui.recipes.IsSourceHostile`).
  - recompiled `data/recipes_camelot.lua` with updated source pools and verified syntax.
- **multibox loot & quest item secret-value protection (`frames/sync/multibox.lua`, `common.lua`)**:
  - exported `sfui.common.issecretvalue` in `common.lua` and added defensive `is_secret(v)` guards throughout `frames/sync/multibox.lua`.
  - prevents `"attempt to compare a secret string value"` errors during `LOOT_OPENED` corpse tooltip scanning on restricted loot and tainted execution contexts.
- **themes close button robustness (`frames/themes/engine.lua`)**:
  - safeguarded `fs.SetTextColor` and `sfs.SetTextColor` invocations in `ApplyCloseButtonStyle` and `OnEnter`/`OnLeave` hooks with method presence checks to eliminate `"attempt to call a nil value"` on non-standard close buttons.
- **quest tracker shift-click untrack & link separation (`common.lua`, `frames/quests/helpers/q_common.lua`, `frames/quests/modules/q_camelot.lua`, `frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_quests.lua`, `frames/quests/modules/q_worldquests.lua`, `frames/quests/engine/q_layout.lua`)**:
  - resolved keybind conflict between shift-clicking to untrack/hide quests vs. inserting item/quest links into active chat edit boxes.
  - shift-clicking a quest row now seamlessly prioritizes inserting chat links when an edit box is focused, while untracking/hiding when no edit box is active.
  - added untrack and hide support for class quests and camelot milestone quests.
- **totem bar instance secret safety & performance (`frames/bars/totembar.lua`, `frames/hide.lua`, `frames/tracking/tracking_classic.lua`, `frames/bars/swing_classic.lua`, `frames/tracking/trackedbars.lua`, `frames/gear/hammer.lua`)**:
  - secured totem slot queries and duration formatting against secret values during instance combat.
  - throttled and event-driven updates for classic totem bar, swing timers, and tracked bars, significantly lowering per-frame cpu usage in instances.
