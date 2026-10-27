# changelog

## v1.124 (2026-10-27)

### features

- **independent reputation bar toggle (`frames/options/tabs/tab_experience.lua`, `frames/experience/bar.lua`, `frames/experience/reputation.lua`, `config.lua`)**:
  - added dedicated `enable reputation bar` checkbox at the top of the reputation tracking options section, completely decoupling the reputation bar from the experience bar.
  - unchecking `enable experience bar` (`showXP`) now hides the player experience bar without disabling the reputation bar, allowing the reputation bar to smoothly take the primary bar position when active.
  - removed the ambiguous `disable reputation tracking` flat button in favor of the standard checkbox.

- **hunter pet tracking controls (`frames/options/tabs/tab_experience.lua`, `frames/experience/pet.lua`)**:
  - added hunter pet controls for classic and camelot hunter characters in the experience options tab:
    - checkbox: `always show pet experience bar` (`petBarAlwaysShow`).
    - slider: `pet bar height (pixels)` (`petHeight`).
  - integrated pet bar layout and value updates into the central `sfui.experience.Update` and layout refresh loops.

### improvements & bug fixes

- **options panel reactivity & widget refresh (`core/widgets.lua`, `frames/options/tabs/tab_experience.lua`)**:
  - exposed `update` methods on `create_checkbox` and `create_slider_input` widgets so option panels can refresh dynamically.
  - registered `SFUI_SETTING_CHANGED` listener in the experience options tab to refresh all controls whenever settings change from commands, blizzard ui tracking, or other tabs.
  - standardized mover unlock button to `lock ui` and `unlock / move ui`.
  - updated `resetDefaults` to route through `sfui.db.Set`, reset bar position, and update layouts.

- **text visibility mode fix (`frames/experience/bar.lua`)**:
  - resolved missing module `data` scope in `UpdateTextVisibility`, fixing a bug where `showText = "ALWAYS"` was ignored and fell back to mouseover fading.

- **reputation tracking desynchronization fixes (`frames/experience/events.lua`, `frames/experience/reputation.lua`, `frames/experience/data.lua`)**:
  - removed rogue `OnReputationTracked` calls from `OnEnteringWorld` and `OnQuestOrFactionUpdate` that were overriding user settings and resetting `repOnlyAtMaxLevel` to false on every quest turn-in or reload.
  - hooked `SetWatchedFactionByID`, `SetWatchedFactionByIndex`, and `SetWatchedFactionIndex` to track explicit user actions and refresh/hide immediately on untrack.
  - updated `repModule.UpdateValues` to strictly respect `repOnlyAtMaxLevel` without stomping the saved variable.

- **blizzard bar suppression & combat fading (`frames/experience/events.lua`)**:
  - unchecking `suppress default blizzard bar` now cleanly restores blizzard's native `StatusTrackingBarManager` and `MainMenuExpBar`.
  - added `OnCombatSettingChanged` to immediately update bar alpha when toggling `hide bar during combat`.
