# changelog

## v1.112 (2026-10-18)

### features

- **pet experience bar & portrait layout**:
  - enlarged the pet portrait to twice the bar height and centered it directly in the middle of the pet experience bar (`frames/experience/pet.lua`).
  - anchored the dynamic training points indicator immediately to the right of the centered portrait (`frames/experience/pet.lua`).
- **player healthbar stance badge refactor**:
  - refactored warrior stance and druid shapeshift form indicators attached to the player healthbar into a unified stance badge system (`frames/bars/bars.lua`).
  - removed paladin aura indicators from attaching to the player healthbar (`frames/bars/bars.lua`).

### improvements & bug fixes

- **gamepad action bar taint & protected function prevention**:
  - resolved `[blocked] sfui tried to call the protected function '...:SetEnabled()'` by disarming blizzard's gamepad action buttons and target override bars (`GamepadMainActionBarFramePageUnitHostileTargetingActionBar`, `FriendlyTargetingActionBar`, `ShortcutsActionBar`) (`compat.lua`, `frames/actionbars/actionbars.lua`).
  - stubbed `:SetEnabled()`, `:Enable()`, `:Disable()`, and `:SetAttribute()` across all gamepad action buttons, preventing protected method calls from triggering under addon execution taint (`compat.lua`, `frames/actionbars/actionbars.lua`).
  - unregistered all `GamepadMode` callbacks and `EventRegistry` callbacks (`PLAYER_TARGET_CHANGED`, `RAID_TARGET_UPDATE`) on target override action bars (`compat.lua`, `frames/actionbars/actionbars.lua`).
- **action bar events & secret cooldown crash guard**:
  - resolved `bad argument #1 to 'SetCooldown' (... Secret values are only allowed during untainted execution for this argument.)` in `Blizzard_ActionBar/Shared/ActionButton.lua:891` by:
    - purging all gamepad action buttons from blizzard's central `ActionBarButtonEventsFrame.frames` list and hooking `RegisterFrame` so gamepad buttons never receive global action bar events (`compat.lua`, `frames/actionbars/actionbars.lua`).
    - stubbing `OnEvent`, `UpdateCooldown`, `Update`, `UpdateAction`, `UpdateState`, and `UpdateUsable` across `GamepadActionBarStandardButtonMixin`, `GamepadActionBarButtonFlyoutMixin`, and `GamepadActionBarButtonMixin` (`compat.lua`).
    - stubbing `:SetCooldown()` and `:Clear()` on gamepad button cooldown sub-frames (`cooldown`, `chargeCooldown`, `lossOfControlCooldown`) to guard against secret value propagation (`compat.lua`, `frames/actionbars/actionbars.lua`).
- **gamepad secret boolean test safety**:
  - resolved `attempt to perform boolean test on a secret boolean value (execution tainted by 'sfui')` in `Blizzard_GamepadActionBars/ActionBarButton.lua:965` by wrapping `C_Spell.IsActiveSpell` in secret-safe checks across gamepad flyouts (`compat.lua`).
