# Changelog

## v12.1.0-59 (2026-09-27)

### Features & Major Improvements
- **High-Performance Loot & Reward Feed (`frames/gear/lootfeed.lua`, `frames/options/tabs/tab_lootfeed.lua`, `config.lua`)**:
  - Implemented an elegant, zero-allocation loot and reward feed styled after SFUI quest headers (1px border, 3px quality accent bar).
  - Multi-category real-time tracking for items, currencies, gold/money gains, level experience (with progress %), faction reputation, and party member loot.
  - Added skill increase and profession tracking (`CHAT_MSG_SKILL` and `SKILL_LINES_CHANGED`) with warm amber/orange accent (`{1.0, 0.65, 0.15}`), curated texture resolution for gathering, crafting, secondary skills (Fishing, Cooking, First Aid), and weapon skills, dynamic multi-skill stacking (e.g. `+1 Fishing` → `+2 Fishing`), and rank badges (`75/150`).
  - Defaulted minimum item quality to `0` (Poor / Gray) with vendor sell price badges on trade goods and junk items (`showSellPrice`).
  - Added dedicated options tab with real-time preview trigger (`sfui.lootfeed.TriggerTestFeed()`), position reset, and granular tracking and sizing controls.

- **Fishing Session Management & Weapon Restoration (`frames/fishing.lua`, `frames/gear/gear.lua`, `frames/gear/highest.lua`)**:
  - Implemented a 30-second fishing session safeguard: equips fishing poles seamlessly and pauses automated gear/weapon swaps during active sessions.
  - Silent auto-restoration of highest item level combat weapons on session timeout (30 seconds of inactivity), mounting, or taking flight paths without chat spam.
  - Added manual session exit and instant weapon swap via `Shift` + fishing keybind.
  - Added bag-scanning auto-equip in Classic/Vanilla using item class and subclass IDs (`classID == 2 and subclassID == 20`).
  - Purged in-combat weapon equip hooks and removed experimental camera nudges to preserve clean, jitter-free camera control.
