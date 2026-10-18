# changelog

## v1.111 (2026-10-18)

### features

- **dedicated hunter pet ring for camelot**:
  - added dedicated pet ring provider in `frames/ring/providers/ring_pet.lua` containing beast lore, pet training, eyes of the beast, mend pet, revive pet, dismiss pet, feed pet, and call pet 1-5.
  - bound to `alt-x` by default for hunters in camelot, while `shift-alt-x` opens specs (`frames/ring/ring.lua`).
  - all other classes in camelot and standard expansions retain `alt-x` as their default specs keybind without conflict (`frames/ring/ring.lua`, `frames/options/tabs/tab_ring.lua`).
- **pet experience bar & training points integration**:
  - integrated centered pet portrait and dynamic training points counter in `frames/experience/pet.lua`.
  - right-clicking the pet experience bar opens the beast training craft menu.
  - middle-clicking the pet experience bar or pet unit frame triggers fast pet feeding (`frames/experience/pet.lua`, `frames/bars/pet.lua`).
  - left-clicking toggles the pet character sheet.

### improvements & bug fixes

- **raw api value forwarding & secret value safety**:
  - resolved `Blizzard_TextStatusBar/TextStatusBar.lua:110` secret number comparison crash on character frame hide by forwarding raw api values directly to status bar fontstrings without lua-side arithmetic or relational comparisons (`core/safety.lua`).
  - resolved `frames/bars/target.lua:638` secret number comparison crash by directly forwarding raw health and power values to target bar elements without value inspection.
  - eliminated value inspections and redundant `pcall`s across `core/safety.lua`, `frames/bars/bars.lua`, `frames/bars/pet.lua`, and `frames/bars/target.lua`.
  - simplified active marker logic in `frames/ring/providers/ring_markers.lua` and `frames/ring/providers/ring_worldmarkers.lua`.
- **secure frame script taint prevention**:
  - converted all `HookScript("OnShow")` and `HookScript("OnHide")` calls on blizzard secure frames (`CharacterFrame`, `PlayerFrame`, `PetFrame`) to `hooksecurefunc` across `frames/character/infopanel.lua`, `common.lua`, `frames/automation/currency.lua`, and `frames/hide.lua`.
  - wrapped panel toggle actions in `securecall` to prevent propagation of execution taint into `UIParentPanelManager` (`frames/experience/pet.lua`).
- **camelot dungeon journal & navigation**:
  - expanded dungeon journal bosses and quest mappings for camelot instances in `data/dj_camelot.lua`.
  - improved sidebar tooltips, quest listings, and map pin discovery (`frames/dungeonjournal/`, `frames/map/providers/pins_dungeonjournal.lua`).
