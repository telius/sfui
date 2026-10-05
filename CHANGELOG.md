# Changelog

## v12.1.0-69 (2026-10-05)

### Features & Major Improvements

- **Auto-Gear Engine & Classic Ammo Integration (`frames/gear/highest.lua`, `frames/gear/gear.lua`)**:
  - **Identical Ammo Swap & Loop Prevention**: Fixed an issue where the auto-gear engine repeatedly queued and swapped identical ammo stacks from bags into the ammo slot (slot 0). Added candidate sorting tie-breakers that always favor currently equipped items on equal scores and identical item ID guards in `EquipHighestILvl`.
  - **Ranged Weapon Ammo Compatibility**: Ranged weapons (slot 18) are now resolved prior to the ammo slot, strictly enforcing weapon-matching ammo types (Arrows for Bows/Crossbows, Bullets for Guns, none for Thrown weapons/Wands/Relics, and honoring `C_PaperDollInfo.AmmoNeeded()`).
  - **Ammo Slot Locking & Stat Exemption**: Added locked ammo slot support (`Locked Ammo`) and exempted projectiles from requiring primary stats in Classic. Added Item Class 6 (Projectile) validation in spec filtering.
  - **Naked Mode Starter Weapon Unequipping**: Ensured the `/sf naked` and unequip actions reliably remove weapons for low-level characters even when weapons have 0 durability.

- **Swing Timer Hunter Ranged & Layout Improvements (`frames/bars/swing.lua`)**:
  - **Ranged Swing Detection**: Restored ranged swing tracking for Hunters and ranged weapon wielders by properly checking `UnitAttackSpeed` and ranged slot item info.
  - **Dynamic Bar Stacking & Positioning**: Improved docking and dynamic vertical spacing when ranged or off-hand swing bars hide or show during combat.
  - **Blizzard Swing Timer Suppression**: Suppressed default Blizzard swing timer frames cleanly without disabling the client's internal event dispatch.

- **Combat Lockdown CVar & Taint Protection (`common.lua`, `frames/quests/modules/`)**:
  - **Central Safe CVar Accessors**: Implemented `sfui.common.set_cvar` with combat lockdown queuing to eliminate protected function `SetCVar()` errors during combat.
  - **Secret Boolean & Taint Prevention**: Safely avoided force-loading unsupported Blizzard Cooldown Viewer modules on Classic/Forever that triggered secret boolean errors on totem checks.
  - **Quest Tracker In-Combat Collapse**: Allowed collapsing and expanding quest objectives freely during combat lockdown without taint or errors.

- **Target Bar Range & Interaction Enhancements (`frames/bars/target.lua`)**:
  - **Multi-Spell Range Checking**: Dynamic class-specific friendly and hostile range checking with dead-target bypass.
  - **UnitWatch Combat Hardening**: Protected `RegisterUnitWatch` against combat lockdown collisions.

- **Dungeon Journal Boss Loot Usability Filtering (`frames/dungeonjournal/dj_bosses.lua`)**:
  - **Loot Usability Filters**: Added quick filter pills for "usable", "armor", "weapons", "trinkets", "other", and "wishlist", with active spec vs all class spec evaluation.

- **Pet Automation Refinements (`frames/automation/pets.lua`)**:
  - **User Dismissal Memory**: Prevents auto-summoning immediately after a player manually dismisses their companion pet.
  - **Filter-Proof Journal Queries**: Leveraged `C_PetJournal.GetOwnedPetIDs()` to prevent UI search and filter states from clearing the pet pool.
  - **Stealth & Resurrection Restores**: Added automatic companion restores on exiting stealth and player resurrects.
