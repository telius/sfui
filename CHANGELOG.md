# changelog

## v1.131 (2026-11-02)

### features & improvements

- **classic era (`1.15.9`) compatibility & dedicated modules (`sfui.toc`, `compat.lua`, `common.lua`, `frames/tracking/tracking_classic.lua`, `frames/bars/swing_classic.lua`, `frames/character/infopanel_classic.lua`, `frames/bars/target.lua`, `frames/merchant/merchant.lua`, `frames/merchant/merchant_filter.lua`, `frames/merchant/merchant_utility.lua`, `data/stats.lua`, `frames/gear/gear_camelot.lua`)**:
  - added dedicated classic era (`[AllowLoadGameType classic]`, `sfui.isEra`) tracked icons & tracked bars provider (`frames/tracking/tracking_classic.lua`) driven by `C_Spell`, `C_UnitAuras`, and `COMBAT_LOG_EVENT_UNFILTERED`, with an in-panel spell id / name catalog manager.
  - added dedicated classic era swing timer adapter (`frames/bars/swing_classic.lua`) building on `frames/bars/swing.lua` via `COMBAT_LOG_EVENT_UNFILTERED`, `UNIT_SPELLCAST_SUCCEEDED`, `START_AUTOREPEAT_SPELL`, and parry-haste math.
  - added dedicated classic era character info panel adapter (`frames/character/infopanel_classic.lua`) building on `frames/character/infopanel.lua`, with `CharacterFrame` & season of discovery `EngravingFrame` side-by-side anchoring and classic era `UnitAttackBothHands` / `UnitRangedAttack` / `UnitDefense` / `UnitResistance` / per-school `GetSpellCritChance` telemetry.
  - added classic era target & target-of-target bars, castbar, and aura icons support (`frames/bars/target.lua`) and hardened merchant frame hooks and item info queries (`frames/merchant/merchant.lua`, `frames/merchant/merchant_filter.lua`, `frames/merchant/merchant_utility.lua`).
- **inventory triage for common white equippable gear (`frames/automation/triage.lua`, `frames/options/tabs/tab_automation.lua`)**:
  - added safe triage and deletion support for common (white quality) equippable items while protecting non-equippable items, quest items, hearthstones, profession tools, fishing poles, tabards, shirts, bags, and locked/set items.
- **bonus roll external sync & luacheck cleanup (`frames/gear/bonusroll.lua`)**:
  - fixed `UnitFullName("player")` multi-return realm handling, retail `12.1.0` secret value guards, and normalized/display realm key matching in `SyncFromExternalAddons`.
