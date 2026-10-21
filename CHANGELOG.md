# changelog

## v1.115 (2026-10-19)

### improvements & bug fixes

- **context-aware combat telemetry**:
  - role-adaptive layout: sections now reorder and resize per role — casters and healers lead with spellcasting & mana, tanks with defense & avoidance, melee with weapon skill, hunters with ranged & ammo. role comes from talents (`core/talents_camelot.lua`), gear manager role picks (`core/bridge.lua`) and live druid forms (bear → tank, cat → melee) (`frames/character/infopanel.lua`).
  - wand users keep a ranged section right under spellcasting — wand skill, wand dps (with damage range / speed tooltip) and wand hit — without the ammo rows.
  - new stats: magic resistances with average mitigation vs the target's level, spell damage per school, bonus healing, melee / ranged attack power, shield block value, haste, and dual-wield white hit cap.
  - corrected math: spell hit caps by level gap (3% same level, 16% vs bosses), yellow hit cap including the >10 skill-gap hit suppression, and native glancing / armor apis preferred over formulas.
  - shared combat math: all formulas moved into `data/stats.lua` (incoming attack table, melee / spell miss, glancing, armor, resistances, spell power, mana regen) — the panel no longer duplicates calculations.
  - added `sfui.gear.GetSpecDB` so spec → camelot tree → class profile lookups aren't duplicated in tank / healer checks (`core/bridge.lua`).
  - event handling moved onto `sfui.events` (no private event frames) with debounced refreshes on stat, resistance, attack power and spell power changes.

- **gamepad pet flyout crash (hunter / warlock)**: silencing blizzard's action button dispatcher left the hidden gamepad pet button without its popup, so `PetActionFlyout.lua:156` errored every time the pet attacked. sfui now drops that button's flash events while its popup is missing (`frames/actionbars/actionbars.lua`).

- **combat memory churn & spike reduction**:
  - radial ring bag-scan elimination: removed heavy bag-scanning and quest item rebuilds during combat entry, preventing ~280kb memory spikes (`frames/ring/ring.lua`, `frames/ring/providers/ring_questitems.lua`).
  - tracked icons aura caching & combat throttle: cached aura applications and missing states so player auras only re-evaluate on dirty events instead of per-frame, and throttled combat icon state processing (`frames/tracking/trackedicons.lua`).
  - target bar allocations & duplication: added target guid caching for quest objectives and unit names, cached creature difficulty colors, and deduplicated redundant updates on target acquisition (`frames/bars/target.lua`).
  - pet bar state driver caching: cached generated visibility macro driver strings to prevent re-compilation churn on target changes (`frames/bars/pet.lua`).
  - tracked bars combat event throttling: enforced a 0.25s combat throttle on sync and events to stabilize memory during high-frequency aura churn (`frames/tracking/trackedbars.lua`, `frames/quests/helpers/q_boons.lua`).
  - options ui: refreshed checkbox state handlers and icon assets (`frames/options/tabs/tab_fishing.lua`, `frames/options/tabs/tab_ring.lua`).

- **codebase audit & logic fixes**:
  - fixed lua multi-return truncation bugs caused by `and` chaining where return values were collapsed to nil (`frames/reminders/buffs.lua` pet cast spell id, `frames/options/tabs/tab_ring.lua` player class check, `frames/bars/pet.lua` pet happiness damage multiplier, `frames/professions/rows.lua` recipe item links).
  - fixed timer handle leaks where `C_Timer.After` return values were passed to `:Cancel()` instead of using `C_Timer.NewTimer` or pending flags (`frames/automation/triage.lua`, `frames/ring/ring.lua`).
  - migrated private event frames to central `sfui.events` dispatcher (`frames/quests/helpers/q_boons.lua`, `frames/actionbars/bind.lua`, `core/safety.lua`, `frames/map/system.lua`).
  - routed all direct `_G.GameTooltip` calls to `sfui.common.get_tooltip()` and `sfui.common.hide_tooltip()` (`frames/experience/pet.lua`, `frames/map/system.lua`, `frames/options/tabs/tab_gear.lua`, `frames/merchant/merchant.lua`).
  - protected objective tracker block clicks, header toggles, and achievement frame lookups with `InCombatLockdown()` to prevent ui action blocked taint errors during combat (`frames/quests/engine/q_layout.lua`, `frames/quests/modules/q_achievements.lua`).
  - deduplicated shared inventory links, tooltip builders, flyout queries, text visibility alpha lookups, quest completion checkers, and dungeon activity lookups across `common.lua`, `frames/gear/`, `frames/experience/`, and `frames/portals/portal_popup.lua`.
  - eliminated dead variables and redundant combat/target checks in swing bar visibility calculations (`frames/bars/swing.lua`, `frames/bars/target.lua`, `frames/quests/modules/q_quests.lua`, `frames/quests/modules/q_scenarios.lua`).
