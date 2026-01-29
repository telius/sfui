# Sfui

**Sfui** is a modular UI addon for World of Warcraft focusing on a clean, high-performance interface.

## Modules

### Core Bars 
- **Centralized Health**: Features healing prediction and total absorb tracking. Customizable position and visibility toggle.
- **Dynamic Power Bars**: Specialization-aware resource bars (Mana, Rage, Energy, etc.) with independent enable/disable toggles.
- **Secondary Resources**: Integrated tracking for class-specific mechanics like Runes, Holy Power, Stagger, and Combo Points.
- **Skyriding Suite**: Dedicated Vigor bar and real-time speed display, both toggleable in settings.
- **Intelligent Visibility**: Bars automatically transition based on combat/targeting. Now features coordinate-based positioning in the options panel.

### Merchant
- **4x7 Grid UI**: Compact grid replacement for the default merchant list.
- **Advanced Filtering**: Toggle known appearances, toys, and housing decor.
- **Automation**: Optional auto-sell junk and gear repair (standard/guild).
- **Currency System**: Dynamic listing of required items for the current merchant.

### Minimap Button Container
- **Button Bar**: Collects addon icons into a semi-transparent bar.
- **Full Customization**: Adjustable X/Y position with a dedicated reset button to return it to the top of the map.
- **Mouseover Support**: Optional fading for both the map and the button bar.

### Vehicle UI
- **Secure Action Bar**: 12-button bar for vehicles and possess modes.
- **Modern Exit**: Integrated "Leave Vehicle" button with modern textures.

### Castbar
- **Precision Casting**: Player castbar with timer, spark, and empowered spell stage coloring.

### Reminders & Warnings 
- **HUD Alerts**: High-priority warnings for missing pets or augment runes.
- **Buff Tracker**: Icon bar for raid buffs (Fortitude, Intellect, etc.) and personal buffs (Food, Flasks, Poisons).
- **Combat Optimized**: Strict `InCombatLockdown` checks ensure zero processing overhead during combat.
- **Granular Controls**: Independent toggles for individual modules and repositioning support.

## Commands
- `/sfui`: Open the settings panel.
- `/rl`: Reload the UI.

## Installation
Place the `Sfui` folder in your `_retail_/Interface/AddOns/` directory.

## License
MIT
