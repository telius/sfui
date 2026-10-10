# Changelog

## v1.89 (2026-10-10)

### features

- **tracking manager utility bar defaults**: updated default configuration for the utility bar to have "hide out of combat" enabled by default (`hideOOC = true`, `hideInVehicle = true`) in `config.lua`. added fallback default resolution in `frames/tracking/trackedicons.lua` and `frames/tracking/trackedoptions.lua`, plus a one-time migration (`SfuiDB.utilityDefaultsV1`) in `frames/tracking/panels.lua` for existing profiles.
- **bag triage threshold default**: updated default trigger threshold for the automated bag triage system from 0 (bags full) to 1 (1 free slot remaining before bags are completely full) across `config.lua`, `frames/automation/triage.lua`, and `frames/options/tabs/tab_automation.lua`. included a one-time migration (`SfuiDB.triageThresholdDefaultV1`) to update uncustomized profiles.

### improvements & bug fixes

- **gear auto-equip combat lockdown & taint protection**: added strict `InCombatLockdown()` guards to `EquipItemByName`, deferred timers, unequip sequences, bind confirmation dialog tickers, and container item swaps in `frames/gear/highest.lua`. registered a `PLAYER_REGEN_DISABLED` listener to cancel pending equip requests, clear the cursor, and eliminate `ACTIONBAR_SLOT_CHANGED` taint that previously caused action bar container blocks (`MainActionBarButtonContainer1:SetShown()`) during combat.
