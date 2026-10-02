# Changelog

## v12.1.0-66 (2026-10-03)

### Features & Major Improvements

- **Loot Feed Polish & Dynamic Denominations (`frames/gear/lootfeed.lua`)**:
  - **Dynamic Denomination Tiering**: Automatically adapts the row icon, accent color, and tooltip header to the highest looted denomination:
    - **Gold Drops ($\ge$ 1g)**: Gold coin pile (`INV_Misc_Coin_01`), radiant gold accent (`#FFD600`), and `"Gold Earned"` header.
    - **Silver Drops ($\ge$ 1s)**: Silver coin pile (`INV_Misc_Coin_03`), lustrous silver accent (`#D1D9E6`), and `"Silver Earned"` header.
    - **Copper Drops (< 1s)**: Copper coin pile (`INV_Misc_Coin_05`), warm bronze accent (`#D98C59`), and `"Copper Earned"` header.
  - **Contextual Wealth Badge**: Total wealth badge now properly formats silver and copper balances when total player gold is below 1g instead of displaying `0 [Gold]`.
  - **Party Loot Distinction**: Party member loot events now display a distinct desaturated grey backdrop and toned borders to clearly differentiate them from personal loot.

- **Dungeon Journal Interface & Layout Refinements (`frames/dungeonjournal/`, `frames/themes/engine.lua`)**:
  - **Header Banner Optimization**: Re-anchored and constrained the ornate title plaque (`headerBar`) to `280x26` at `TOP 0, -8`, centering the banner nicely below the frame top edge and providing a ~180px gap from the top-right button group.
  - **Top-Right Option Buttons Visibility**: Explicitly elevated `mapOptBtn` (Map Pin Options), `navWpBtn` (Set Waypoint), and `showMapBtn` (Show on World Map) to frame level `base + 20` alongside `closeBtn` in both local frame setup and `ElevateWindowContents` to prevent occlusion under the header artwork.
  - **Quest Breadcrumbs & Encounter Loot Sync**: Refined quest objective tracker navigation, loot drop syncing, and tooltip interaction stability.

- **Theme Engine & Widget Standardization (`frames/themes/engine.lua`, `frames/themes/camelot.lua`, `core/widgets.lua`)**:
  - **Dropdown & Selection Menus**: Integrated comprehensive theme styling for custom dropdown menus, including toggle button atlases, arrow indicators, hover states, and backdrop borders for both Camelot and Modern profiles.
  - **Elevated Window Content Hierarchy**: Unified frame level escalation for window headers, close buttons, utility controls, and child tab buttons across all registered frames.
