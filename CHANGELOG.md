## v0.1.5 (2026-02-04)

### Features
- **Automation**: Added **Match Target Mount** functionality.
    - Check target's mount and summon the same one if owned.
    - Added keybinding under SFUI category.
    - Fallback to random favorite mount if no match found.
- **Default Settings**: Enabled several convenience features by default:
    - **Auto Sell Greys**: Automatically sell poor quality items at vendors.
    - **Auto Repair**: Automatically repair gear at vendors (prioritizing guild funds).
    - **Reminders**: Enabled Solo and Everywhere reminders by default.
- **Minimap**:
    - **Cooldown Viewer**: Shift-Clicking the SFUI minimap icon now correctly opens the Blizzard Advanced Cooldown Settings panel, dynamically loading the Blizzard_CooldownViewer addon if needed.
    - **Data Broker**: Improved integration with Broker plugins.
- **Cleanup**: Removed deprecated `sfui/cooldowns.lua` module.

## v0.1.4 (2026-01-31)

### Features
- **Master's Hammer**: Complete overhaul of the repair system.
    - Implemented **Sequential Rotation**: Automatically targets damaged gear in a logical priority (Weapons/Shields first).
    - **Spam Protection**: Advances rotation immediately on click, enabling lightning-fast repairs without double-casting or cast cancellation.
    - **Keybind Support**: Added a secure click binding for Master's Hammer repair, available in the main Bindings menu.
    - UI aesthetics are now fully customizable (X/Y position and border color).
- **Castbars**:
    - New **Player Castbar**: Features **Instant Cast Tracking** (visual confirmation of instant spells). Supports Empowered stages for Evokers.
    - New **Target Castbar**: Improved visibility and distinct interruptible/non-interruptible states.

