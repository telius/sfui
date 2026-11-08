# changelog

## v1.142 (2026-11-08)

### new features

- **reagent usage tooltips & recipes options tab (`frames/professions/reagents.lua`, `frames/options/tabs/tab_recipes.lua`, `frames/professions/tooltips.lua`, `frames/alts/recipes.lua`, `frames/quests/modules/q_camelot_recipes.lua`, `frames/options/options.lua`, `commands.lua`, `sfui.toc`)**:
  - added a lazy-indexed reagent usage tooltip engine (`frames/professions/reagents.lua`) for classic/camelot that displays which recipes consume a hovered reagent item, grouped by profession with skill difficulty coloring (`orange` / `yellow` / `green` / `grey` / `can learn`), reagent counts (`xN`), and cross-alt character attribution across local and synced accounts.
  - holding `shift` while hovering a reagent expands all recipes (including unlearned and non-matching professions).
  - added a dedicated `recipes` options tab (`frames/options/tabs/tab_recipes.lua`, `/sfui recipes`) consolidating reagent tooltip settings, recipe scroll & crafted item tooltip lines, bag/merchant icon tinting, acquisition sources, world map pins, and objective tracker pinned recipe shopping list controls.
- **cross-account sync & objective tracker enhancements (`frames/quests/modules/q_camelot_class.lua`, `frames/quests/modules/q_camelot_recipes.lua`, `frames/quests/helpers/q_common.lua`, `frames/quests/helpers/q_tooltip.lua`, `frames/alts/alts.lua`, `frames/sync/sync.lua`, `frames/sync/multibox.lua`)**:
  - added cross-class synced peer class quest tracking in the objective tracker and synced pinned recipe & shared reagent shopping lists across linked accounts.
  - added complete character data purging (`sfui.alts.PurgeCharacter`) and full `first last` character name resolution for forever realms across alts, sync, trade, and fishing modules.

### improvements & bug fixes

- **quest status synchronization reliability (`frames/sync/sync.lua`, `frames/sync/merge.lua`)**:
  - added full active quest snapshot reconciliation (`delta.all`), `ScanActiveQuestsDelta(true)` full-resync support on handshake and periodic heartbeats, collapsed quest log header recovery, completed-quest pruning for peer active quests, and live `C_QuestLog.IsUnitOnQuest` party fallback in `GetQuestMemberStates`.
- **actionbar page scrolling lockdown (`frames/actionbars/paging.lua`, `frames/actionbars/actionbars.lua`)**:
  - removed manual actionbar page conditionals (`[bar:2]`..`[bar:10]`) from `sfui_Bar1`'s secure state driver so bar 1 only pages for stances, shapeshift forms, stealth, possess, vehicle, and override bars.
  - automatically resets `ActionBarPage` to `1` and unbinds default `SHIFT-MOUSEWHEELUP` / `SHIFT-MOUSEWHEELDOWN` from `PREVIOUSACTIONPAGE` / `NEXTACTIONPAGE`.
- **dungeon journal quest chains (`data/dj_camelot.lua`)**:
  - added prerequisite quest chain definitions and step coordinates for `95216` (*the new plague* — requires 3-part *a recipe for death* chain `447` → `450` → `451`), `92422` (*the wrath of rath'mael* — requires 2-part *rear guard patrol* chain `356` → `99156`), and `1491` (*smart drinks* — requires `865` *raptor horns*).
- **secret value & ui theme safety (`frames/themes/engine.lua`, `frames/professions/contacts.lua`, `frames/merchant/merchant_utility.lua`, `frames/sync/quests.lua`, `frames/sync/multibox.lua`, `frames/reminders/buffs_scan.lua`, `frames/bars/threat.lua`, `frames/tracking/trackedbars.lua`)**:
  - fixed `ApplyCloseButtonStyle` and `ApplyButtonStyle` in `frames/themes/engine.lua` when styling `UIPanelCloseButton` instances under non-atlas themes.
  - guarded `UnitName`, `UnitGUID`, loot links, and aura slots against secret values across `frames/professions/contacts.lua`, `frames/merchant/merchant_utility.lua`, `frames/sync/quests.lua`, `frames/sync/multibox.lua`, and `frames/reminders/buffs_scan.lua`.
  - fixed threat bar overlap with attached tracked bars above the health bar.
