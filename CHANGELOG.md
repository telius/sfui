# Changelog

## v1.104 (2026-10-17)

### features

- **minimap performance & clock databar widget**: replaced the static time manager clock on the button collection frame with a clean, low-profile performance databar widget displaying real-time framerate and latency (`60 fps  24 ms`) with click-to-cycle toggling between clock time and system metrics (`frames/map/system.lua`, `frames/map/buttons.lua`, `frames/options/tabs/tab_minimap.lua`, `config.lua`, `common.lua`, `sfui.toc`).
- **specialization-colored performance telemetry**: tinted `"fps"` and `"ms"` metric unit labels with the player's active specialization / class color while keeping numerical values clean and uncolored with flat typography, zero outline, and zero shadow (`frames/map/system.lua`).
- **rich system & memory breakdown tooltip**: on hover, displays local and realm time, framerate, home and world latency, total addon memory, total lua garbage memory, and a sorted per-addon memory consumption table with suite aggregation (details, dbm, bigwigs, raider.io, etc.), shift-to-expand, and highlighted sfui memory footprint (`frames/map/system.lua`).
- **interactive clock & utility actions**: right-click toggles the stopwatch and alarm, middle-click opens the calendar, and shift-click triggers garbage collection with chat reporting on freed memory (`frames/map/system.lua`).
- **minimap options configuration**: added a system info display dropdown in the minimap options tab allowing players to configure default startup mode between `fps & latency` and `clock` (`frames/options/tabs/tab_minimap.lua`, `config.lua`, `common.lua`).

### improvements & bug fixes

- **zero-overhead background monitoring**: lightweight 1.0s background timer only polls cheap c-engine counters (`GetFramerate()`, `GetNetStats()`) and keeps expensive `UpdateAddOnMemoryUsage()` strictly lazy on hover (`frames/map/system.lua`).
- **dynamic button collection bar layout**: dynamic width reservation and anchoring in `ButtonManager:arrange_buttons()` smoothly accounts for the system widget width alongside collected minimap buttons and docked indicators, cleanly restoring blizzard's clock when the button collection bar is disabled (`frames/map/buttons.lua`).
