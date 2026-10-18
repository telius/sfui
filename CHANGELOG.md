# changelog

## v1.109 (2026-10-18)

### features

- **comprehensive hunter pet experience & progression bar in camelot**: full redesign and feature integration for the hunter pet experience bar (`frames/experience/pet.lua`), displaying live level, xp progress, loyalty rank with sub-rank loyalty progression points, pet happiness with damage modifier breakdowns (125% happy / 100% content / 75% unhappy), pet diet preferences with supported food categories, and unspent/total pet training points. left-clicking opens the pet character panel (with camelot sidebar tab 4 support), and right-clicking opens the pet context menu.
- **player health bar unitframe menu**: right-clicking the player health bar now triggers the player context menu via secure action button template (`core/widgets.lua`, `frames/bars/bars.lua`), mirroring standard unitframe behavior.

### improvements & bug fixes

- **highest gear weapon selection based on weapon dps**: resolved an issue in `frames/gear/highest.lua` where missing off-hand weapons unconditionally forced 2-handed weapons over superior 1-handers; camelot hunters and classic/camelot retribution paladins now choose 1-handed weapons over 2-handers whenever weapon dps or overall item score is higher.
- **retail retribution paladin 2-hander enforcement**: in retail, retribution paladins are strictly constrained to 2-handed weapons exclusively (`frames/gear/highest.lua`).
- **pet bar tooltip placement**: anchored the pet bar tooltip to the right of the pet unit frame (`frames/bars/pet.lua`), preventing overlap with default game world tooltips.
- **multi-bar experience switcher synchronization**: ensured smooth integration and tracking updates between player xp, reputation, challenges, and hunter pet experience across events and bar switching (`frames/experience/bar.lua`, `frames/experience/experience.lua`, `frames/experience/events.lua`, `frames/experience/challenges.lua`, `frames/experience/reputation.lua`).
