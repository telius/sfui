# changelog

## v1.139 (2026-11-05)

### bug fixes

- **pet action bar combat taint & button suppression (`frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`)**:
  - detached `PetActionBar` event registrations, `OnEvent` / `OnUpdate` scripts, and `UpdateShownButtons` when `sfui` actionbars are active so `PetActionBar` never calls `PetActionButton1:SetShown()` during combat.
  - preserved untainted `index`, `commandName`, and `ID` fields on `PetActionButton1`..`10` when reparenting them to `sfui_PetBar`.
  - removed `PetActionButton` from `BAR_BUTTON_PATTERNS` so `suppress_blizzard_actionbars` only silences `PetActionBarButtonContainer1`..`10` without zeroing alpha or disabling mouse interaction on `sfui_PetBar`'s buttons.
- **micro menu offscreen hiding layout crash (`frames/hide.lua`)**:
  - kept individual `MICRO_BUTTON_NAMES` parented to `MicroMenu` and `MicroMenu` parented to `MicroMenuContainer` when parking `MicroMenuContainer` offscreen on `HiddenFrame`, preventing `MicroMenuMixin:GetEdgeButton()` from encountering unanchored hidden child buttons during `OnHide` layout callbacks.
