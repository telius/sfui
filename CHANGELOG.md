# Changelog

## v1.94 (2026-10-12)

### improvements & bug fixes

- **triage arithmetic error**: fixed a nil arithmetic crash in `frames/automation/triage.lua` where `lastPurgeSuccessTime` was referenced in the delete button click handler prior to its local declaration. `lastPurgeSuccessTime` and `lastNoExcessNoticeTime` are now declared at file-level scope with nil-safe fallback guards.
- **strict combat blocking**: added comprehensive combat safety guards across triage evaluation, button click handlers, and event listeners (`frames/automation/triage.lua` and `core.lua`). the triage prompt is automatically dismissed when combat is detected (`PLAYER_REGEN_DISABLED`, `InCombatLockdown`, or `UnitAffectingCombat`), background scan timers are cancelled on combat entry, and clicks on `deleteBtn` or `SfuiPurgeSoulShards` are blocked in combat.
- **loot window & busy state safety**: updated `is_player_busy()` to recognize open loot windows (`LootFrame:IsShown()` and `GetNumLootItems() > 0`) to prevent background shard deletion while actively looting, and added bank, trade, and mail window checks to `triage.EvaluateTriage()`.
