# Sfui

**Sfui** is a modular UI addon for World of Warcraft focusing on a clean, high-performance interface.

## Modules

### Core Bars (`bars.lua`)
- **Centralized Health**: Features healing prediction and total absorb tracking.
- **Dynamic Power Bars**: Specialization-aware resource bars (Mana, Rage, Energy, etc.) that stack around the health bar.
- **Secondary Resources**: Integrated tracking for class-specific mechanics like Runes, Holy Power, Stagger, and Combo Points.
- **Skyriding Suite**: Dedicated Vigor bar with cooldown tracking (Whirling Surge, Second Wind) and a real-time speed percentage display.
- **Intelligent Visibility**: Bars automatically transition and fade based on combat state, targeting, and mount status.

### Merchant
- **4x7 Grid UI**: Replaces the default merchant list with a more compact grid.
- **Advanced Filtering**: Toggle between showing/hiding known appearances, toys, and housing decor.
- **Buyback Mode**: Direct access to buyback items within the custom grid.
- **Shopping Helpers**: Custom stack-split frame for quick quantity purchases with a "Max" button.
- **Automation**: Optional automatic selling of junk (greys) and gear repair (standard or guild funds).
- **Currency Display**: Dynamically lists required tokens and currencies for the current merchant.

### Minimap
- **Button Bar**: Collects and organizes minimap addon icons into a semi-transparent, toggleable bar.
- **Mouseover Control**: Optional mouseover visibility for both the map and the button bar.
- **Utility**: Automatic zoom-out reset and suppressed Blizzard border elements.

### Vehicle UI
- **Secure Action Bar**: 12-button bar for vehicles, possess modes, and override actions.
- **Modern Exit**: Integrated "Leave Vehicle" button with modern textures and keybind support.
- **Safety**: Secure state-driven visibility to prevent combat taint.

### Castbar
- **Player Casting**: Precision castbar with timer, spark, and lingering effects.
- **Empowered Spells**: Visual dividers and stage-based color shifts for charging spells.

### Pre-combat Alerts
- **HUD Warnings**: High-priority alerts for missing pets or augment runes before entering combat.

### Currency Tracker
- **Character Panel**: Integrates a tracked currency display directly into the Character Frame.

## Commands
- `/sfui`: Open the settings panel.
- `/rl`: Reload the UI.

## Installation
Place the `Sfui` folder in your `_retail_/Interface/AddOns/` directory.

## License
MIT
