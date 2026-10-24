# changelog

## v1.122 (2026-10-24)

### features

- **sfuibug companion integration (`dispatcher.lua`, `core/module.lua`, `commands.lua`, `frames/options/tabs/tab_debug.lua`, `scripts/bugjar-autofix.py`)**:
  - integrated standalone `sfuibug` companion error tracker for lightweight, dedicated savedvariables captures and telemetry.
  - upgraded `dispatcher.lua` to capture caller registration metadata and preserve live stack traces in `xpcall` handlers.
  - routed module lifecycle exceptions in `core/module.lua` to `sfuibug`.
  - added `/sfui bug`, `/sfui bugs`, and `/sfui errors` slash command routing to `sfuibug`.
  - added debug tab controls in `frames/options/tabs/tab_debug.lua` with error inspection, database reset, minimap toggle, and live status.
  - updated `scripts/bugjar-autofix.py` to prioritize native parsing of `WTF/.../SavedVariables/sfuibug.lua`.

- **minimap mail indicator alignment (`frames/map/indicators.lua`, `frames/map/buttons.lua`, `config.lua`)**:
  - repositioned docked mail indicator to the far-left of the minimap button bar, isolating it completely from the system stats area.
  - updated `ButtonManager:arrange_buttons()` to dynamically offset collected addon icons when the mail indicator is active and visible.
  - hooked retail `IndicatorFrame.MailFrame` and `IndicatorFrame.CraftingOrderFrame` visibility changes for instant layout updates.
  - set `button_bar.pad_x` default to 8px in `config.lua` for symmetrical padding.

### improvements & bug fixes

- **action bars & experience hud (`frames/actionbars/actionbars.lua`, `frames/actionbars/bars.lua`, `frames/experience/experience.lua`, `frames/hide.lua`, `frames/options/tabs/tab_experience.lua`, `frames/tracking/trackedoptions.lua`)**:
  - refined action bar mover handling and bar state management.
  - enhanced experience bar updates and tracking options.
