# Changelog

## v1.102 (2026-10-16)

### features

- **dynamic minimap dimension controls**: dynamically adapts the minimap configuration tab based on shape selection, displaying independent width and height controls for square minimaps and a single unified diameter scale slider for round minimaps (`frames/options/tabs/tab_minimap.lua`).
- **conjoined ambient weather indicator**: conjoined the weather status indicator to the southeast of the camelot day/night diel frame along the natural curvature of the bronze compass rim (`frames/map/status.lua`).
- **docked mail indicator & options toggle**: added a dedicated toggle in the minimap options tab to dock the mail notification icon directly into the minimap button collection frame by default, cleanly positioning it alongside the clock with automatic width reservation and fallback to the minimap top-left corner when the button collection bar is inactive (`frames/options/tabs/tab_minimap.lua`, `frames/map/indicators.lua`, `frames/map/buttons.lua`, `config.lua`, `common.lua`).
- **experience & reputation defaults**: configured reputation tracking to automatically display at max level and dynamically switch to newly gained reputations by default (`config.lua`, `common.lua`, `frames/experience/reputation.lua`).

### improvements & bug fixes

- **camelot minimap optical centering & scaling**: resolved geometry desynchronization where opening the options panel shrank the border and exposed protruding map terrain; restored native container points, applied optical center offsets to compensate for texture asymmetry, tucked the circular aperture flush inside the inner bronze rim, and delegated uniform scaling to blizzard's native edit mode scale pipeline (`frames/map/minimap.lua`, `frames/map/square.lua`, `core/widgets.lua`).
- **action bar default layout & mouseover toggle**: enabled action bars 1 through 6 by default with mouseover fading disabled, and corrected bulk toggle synchronization across all bars (`config.lua`, `common.lua`, `frames/actionbars/actionbars.lua`, `frames/actionbars/mouseover.lua`, `frames/options/tabs/tab_actionbars.lua`).
- **button collection bar positioning**: adjusted default vertical positioning of the minimap button collection bar to 30 to prevent overlapping the compass rim, with automatic database migration for existing profiles (`config.lua`, `common.lua`, `frames/map/buttons.lua`, `frames/options/tabs/tab_minimap.lua`).
- **square minimap pin boundary clipping**: updated minimap canvas pin placement to respect rectangular boundaries when square minimap mode is enabled, preventing corner pin culling (`frames/map/pins.lua`).
- **experience bar tick dividers & challenges**: hidden 20-segment tick dividers and legacy challenges bar by default (`config.lua`, `common.lua`, `frames/experience/bar.lua`, `frames/experience/challenges.lua`).
- **documentation & media gallery**: integrated new camelot UI previews across the readme documentation, highlighting the classic dungeon journal, recipe compendium, alt shipping mail dispatcher, pet manager, and real-time memory profiler (`README.md`).
