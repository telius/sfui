# sfui

Modular, high-performance UI suite and quality-of-life additions for World of Warcraft (Retail & Classic / Forever).

SFUI replaces bulky addon suites, complex WeakAuras, and heavy frameworks with clean, lightweight native components. Everything is driven by a single **central event dispatcher** — instead of dozens of standalone addons running separate timers and eating CPU in the background, sfui coordinates all events and updates through one engine that sleeps when frames are idle and guarantees zero combat taint.

---

## What's Included

### HUD & Combat
- **Unit & Power Bars**: Clean health and power bars with class colors, secondary resources (runes, combo points, stagger, soul fragments), and aura tracking.
- **Castbars**: Player and target castbars with spell channel ticks, empowered spell stages, and interrupt indicators.
- **Experience & Reputation**: Smooth progression bar with rested XP, quest turn-in previews, floating XP gains, and auto-switching to faction reputation, renown, or paragon tracking at max level.
- **Cooldown & Aura Tracking**: Dynamic cooldown manager (CDM) and tracked buff/debuff bars.
- **Vehicle & Skyriding**: Combat-safe vehicle interface and minimal skyriding / dragonriding vigor HUD.

### World & Questing
- **Dungeon Journal (Classic / Camelot)**: Full in-game encounter and dungeon journal (`/dj`) with boss ability breakdowns, loot tables, drop chances, and interactive WorldMap entrance and quest pickup pins.
- **Recipe Catalogue & Crafting Compendium (Classic / Camelot)**: Comprehensive crafting recipe database (`/recipe`) covering trainers, vendors, quest rewards, and drops. Includes completionist progress bars, interactive WorldMap recipe pins, cross-alt shopping filters, and merchant deep-linking.
- **Objective Tracker**: Lightweight quest and scenario tracker with clickable quest item buttons, recipe shopping lists with live bag counts, and group finder shortcuts.
- **Minimap**: Minimalist square minimap with player coordinates, zone info, and clean addon icon handling.
- **Currency & Items**: Tracked currency display, token overviews, and crafting material counts.

### Quality of Life & Automation
- **Bag Triage & Inventory Management**: Automated inventory triage (`/triage`) alerting when bags are nearly full, with quick junk selling, deposit to bank, or item deletion safeguards.
- **Spell Rank-Up**: Automatically updates lower rank spells on your action bars as soon as you train higher ranks at class trainers.
- **Tracking Manager & Utility Bar**: Sleek collapsible micro-bar providing one-click access to consumables, hearthstones, and utilities with auto-hiding out of combat.
- **Fishing (One-Key)**: Cast and reel-in with a single keybind, dynamic soft-targeting, and splash audio amplification.
- **Companion Pets**: Automatically re-summons your pet after dismounting, with timed favorites rotation.
- **Merchant & Vendors**: 1-click grey item selling, automated guild repairs, stack purchases, and recipe catalogue inspection.
- **Loot Feed & Wishlist**: Real-time loot toast feed and an in-game dungeon/raid encounter loot browser with spec swapper and cross-character wishlist alerts.
- **Gear Manager**: Bag upgrade recommendations, role-based stat weighting, and smart auto-equipping.
- **Portals Hub**: Quick-access popup menu for all your character's hearthstones, teleport toys, and dungeon portals.
- **Alts & Warband**: Track your alts' item levels, weekly lockouts, Great Vault progress, currencies, and crafting recipe knowledge.
- **Automations**: Cinematic skipping, target mount matching, and master's hammer repair popup.

### System & Customization
- **Options Panel (`/sfui`)**: Tabbed in-game settings panel with 18 categories. Jump directly to any category with `/sfui <tab>` (e.g. `/sfui experience`, `/sfui bars`, `/sfui dj`, `/sfui recipes`).
- **Memory & Diagnostics Profiler (`/sfmem` or `/sfui mem`)**: Real-time telemetry dashboard monitoring allocation rates, garbage collection cycles, and live subsystem states across all modules.
- **Frame Hiding**: Granular toggles to cleanly hide default Blizzard UI elements you don't need.
- **Button Skinning**: Native support for [Masque](https://www.curseforge.com/wow/addons/masque) (e.g. *Masque: Caith*).

---

## Slash Commands

| Command | Description |
| :--- | :--- |
| `/sfui` | Opens the options panel (or `/sfui <tab>` to jump directly to a tab) |
| `/dj` or `/sfui dj` | Opens the Classic / Camelot Dungeon Journal |
| `/recipe` or `/sfui recipes` | Opens the Recipe Catalogue & Crafting Compendium |
| `/triage` or `/sfui triage` | Opens the automated Bag Triage manager |
| `/sfmem` or `/sfui mem` | Opens the real-time Memory & Diagnostics Profiler (`/sfmem gc` to force garbage collection) |
| `/rl` | Reloads the UI |

---

## Keybindings

Configure keybindings in **Game Menu -> Options -> Keybindings -> SFUI**:
- **Cast & Catch Fishing**: One-key fishing cast and reel-in
- **Summon / Rotate Companion Pet**: Call or cycle your active companion pet
- **Toggle Pet Manager**: Open the companion pet manager
- **Master's Hammer Repair**: Instant blacksmith repair popup
- **Portals Hub**: Open the teleport and hearthstone menu
- **Alts & Warband**: Open the cross-character dashboard
- **Loot Browser / Dungeon Journal**: Open the encounter journal loot browser
- **Match Target Mount**: Automatically summon the same mount as your target
