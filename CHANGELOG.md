# Changelog

## v12.1.0-70 (2026-10-05)

### Features & Major Improvements

- **Gear Manager Architectural Modularization & Split (`frames/gear/`)**:
  - **4-File Modular Separation**: Refactored the monolithic 3,350-line `gear.lua` into four specialized, maintainable components matching the repository's `frames/alts/` architecture standard:
    - **`frames/gear/engine.lua`**: Pure non-visual auto-equip engine, combat/casting queues, bag debounces, `sfui.events` dispatchers, module registration, and CharacterFrame/Paperdoll shift-click hooks.
    - **`frames/gear/gear.lua`**: Base UI window framework, title bar, collapse mechanics, consolidated Row 1 controls, shared Row 3 stat drag/drop prioritization, Pawn weights input, and UI orchestration.
    - **`frames/gear/gear_standard.lua` (`[AllowLoadGameType standard]`)**: Retail spec tabs at `HEADER_H = 56`, `2s`/`4s`/`2e`/`ilvl` tier modifier buttons, and modern secondary stat models.
    - **`frames/gear/gear_camelot.lua` (`[AllowLoadGameType camelot, classic][ExcludeLoadGameType standard]`)**: Classic shorthand role icon buttons (28x28 with 4px spacing), `naked` button, corpse-run durability unequip engine, ranged/ammo slot handling, and Classic stat cleansing (`ArP`/`Exp`).
  - **TOC Game-Type Filtering**: Updated `sfui.toc` so Retail and Classic clients exclusively parse their relevant game-type modules with zero runtime overhead or taint.

- **Gear Subsystem CPU Optimizations & Logic Bug Fixes (`frames/gear/`)**:
  - **Item Level & Tooltip Caching (`highest.lua`)**: Moved Timewalking/Event scaled tooltip parsing inside `IsItemValidForSpec_Internal`, storing the resolved effective item level inside `validationCache`. Completely eliminated 100+ uncached `C_TooltipInfo.GetHyperlink` queries on every bag scan.
  - **Pre-cached Item IDs & Set IDs (`highest.lua`)**: Pre-populated `itemData.itemID` and `itemData.setID` on candidate evaluation, eliminating repeated string regex matches (`link:match("item:(%d+)")`) and repeated 16-variable `GetItemInfo` queries across unique weapon, embellishment, and tier drafting loops.
  - **Pawn Scratch List Nil-Indexing Fix (`gear.lua`)**: Resolved a fatal runtime crash where trimming `pawnScratchList` caused future spec switches with larger stat counts to index nil entries. Deduplicated stat resolution logic across the UI into `sfui.gear.GetResolvedStatOrder`.
  - **Retail Button & Engine Key Sync (`gear_standard.lua` & `highest.lua`)**:
    - **Embellishments (`2e`)**: Synchronized `force_embellishment` and `force_2emb` so the drafting engine properly activates when clicking the UI button.
    - **Item Level Override (`ilvl`)**: Wired `specDB.force_ilvl` directly into the scoring multiplier (100,000x ilvl) to strictly enforce raw item level upgrades across all slots.
    - **Tier Set 4-Set (`4s`)**: Synchronized default state evaluation between UI button highlight and engine drafting.
  - **Event & Update Throttling (`engine.lua`, `compare.lua`, `hammer.lua`)**:
    - Removed redundant `BAG_UPDATE` registration in `engine.lua` (relying cleanly on `BAG_UPDATE_DELAYED`).
    - Short-circuited `scanEquippedForChanges()` when `SfuiGearManagerFrame` is closed to eliminate unneeded inventory lookups.
    - Removed redundant `PLAYER_EQUIPMENT_CHANGED` CVar checks in `compare.lua`.
    - Added hammer/expansion item filtering to `GET_ITEM_INFO_RECEIVED` in `hammer.lua`.

- **Gear Manager Row 1 Consolidated Controls (`frames/gear/gear.lua`)**:
  - **Unified Single-Row Layout**: Moved `pve set:` and `pvp set:` dropdowns onto the exact same row (Row 1, `y = -6`) as the quick action buttons (`[pve]`, `[pvp]`, `[auto: on/off]`).
  - **Balanced Geometry & Spacing**: Left-aligned the PvE and PvP dropdowns (96px width each) with 12px separation, and right-aligned `autoToggle` (72px), `highPvP` (34px), and `highPvE` (34px) with crisp 4-6px spacing, maintaining an open 10px divider between groups.
  - **Header Status Label**: Relocated `statusLabel` into `gearFrame.headerBar` right-aligned before the collapse button, displaying active gear modes cleanly without competing for body space.
  - **Seamless Collapse Parenting**: Parented quick action buttons to `gearFrame.content` so they hide cleanly when collapsing the window to header height (`HEADER_H`).

- **Gear Manager Spec & Naked Icon Buttons in Classic & Camelot (`frames/gear/gear_camelot.lua`)**:
  - **Centered Role & Naked Cluster**: Dynamically calculates the free space between the last lock button and the right frame margin, placing the role icons and naked button cluster exactly in the horizontal center of the available space.
  - **Large 28x28 Icon Buttons with 4px Spacing**: Configured Row 2B role and `naked` buttons as large 28x28 square icons separated by a clean 4px gap, utilizing cropped textures `(0.08, 0.92, 0.08, 0.92)` and crisp 1px borders vertically centered at `y = -56`.
  - **Easily Adjustable Layout Parameters**: Centralized `ROLE_ICON_SIZE` (28), `ROLE_ICON_SPACING` (4), and `ROLE_ICON_Y` (-56) at the head of the role layout section, eliminating hardcoded offsets and enabling effortless manual tuning.
  - **Authentic Form & Spec Icons**:
    - **Druid**: Dedicated form icons for `cat` (`Ability_Druid_CatForm`), `bear` (`Ability_Racial_BearForm`), `moon` (Balance Starfall), and `resto` (Healing Touch).
    - **Other Classes**: Authentic 3-tree spec icons across Paladin, Warrior, Shaman, Priest, Rogue, Mage, Warlock, and Hunter.
    - **Naked Mode**: Matching 28x28 Blizzard wardrobe chest silhouette icon (`Interface\Icons\inv_chest_cloth_17`) anchored seamlessly after the active role buttons; strictly leaves shirt (slot 4), tabard (slot 19), and non-durability jewelry (neck, rings, trinkets) equipped.
  - **Desaturation & Alpha States**: Inactive buttons are desaturated at `0.40` alpha; active selected spec/role buttons illuminate at full saturation and `1.0` alpha with theme accent or role color border highlights (e.g. amber for active naked mode).
  - **Lowercase Tooltips**: Maintained concise, lowercase tooltip naming convention (`cat`, `bear`, `moon`, `resto`, `prot`, `ret`, `naked (unequip gear)`, etc.) without any appended "role" suffix, providing clean configuration guides on mouseover.

- **Classic / Camelot Stat Cleanse (`data/stats.lua`, `frames/gear/gear.lua`)**:
  - **Removed Non-Existent Stats**: Removed Armor Penetration (`ArP`) and Expertise (`Exp`) from all Classic and Camelot stat orders and default role priorities across Warrior, Paladin, Hunter, Rogue, and Druid (cat) definitions, ensuring 100% authentic Vanilla / Camelot stat prioritization.
  - **SavedVariables Sanitization**: Dynamically scrubs legacy `ArP` and `Exp` tokens from character `stat_order` tables upon load, backfilling with valid secondary/defensive stats from the class stat pool.

- **Gear Manager Spec Icon Tab Suppression in Camelot & Vanilla (`frames/gear/gear.lua`)**:
  - **Spec Icon Hidden in Classic & Camelot**: Suppressed redundant header spec icon buttons (`tabBtns`) in Camelot and Vanilla since all specializations and roles are now managed and differentiated directly via the row 2B shorthand buttons (`prot`, `ret`, `holy`, `cat`, `bear`, `moon`, `resto`, `naked`, etc.).
  - **Compact Header Height**: Reduced `HEADER_H` from 56 to 34 in Classic / Vanilla, eliminating empty dead space and cleanly anchoring the content container directly beneath the title bar (collapsed height 34, expanded height 210).
  - **Class Spec Sync**: Clicking any shorthand role button on row 2B automatically propagates and synchronizes the selected role and default stat orders across all spec entries for that class in Classic.

- **Gear Manager Classic Shorthand Spec Roles (`frames/gear/gear.lua`, `frames/gear/highest.lua`, `core/bridge.lua`, `data/stats.lua`, `core/talents.lua`)**:
  - **Class-Specific Lowercase Shorthand Buttons**: Added dedicated, strictly lowercase shorthand role/spec buttons across all 9 classes in Classic / Camelot:
    - **Paladin**: `prot`, `ret`, `holy`, `naked`
    - **Warrior**: `arms`, `fury`, `prot`, `naked`
    - **Druid**: `cat`, `bear`, `moon`, `resto`, `naked`
    - **Shaman**: `ele`, `enh`, `resto`, `naked`
    - **Priest**: `disc`, `holy`, `shad`, `naked`
    - **Rogue**: `sin`, `combat`, `sub`, `naked`
    - **Mage**: `arc`, `fire`, `frost`, `naked`
    - **Warlock**: `aff`, `demo`, `destro`, `naked`
    - **Hunter**: `bm`, `mm`, `surv`, `naked`
  - **Dynamic Naked Button Placement**: Anchored the `naked` button dynamically after the last active role button for all classes across Row 2B.
  - **Spec & Role Scoring Integration**: Mapped each shorthand role to its tailored stat order, item scoring rules, weapon allowances, and stat pools.
  - **Case-Insensitive Role Normalization**: Fully backwards-compatible with legacy role storage (`DPS`, `TANK`, `HEAL`, uppercase keys), automatically resolving and mapping to canonical lowercase shorthands.

- **Dropdown Menu Global Interaction Fix (`core/widgets.lua`)**:
  - **Dropdown Click & Dismissal**: Resolved dropdown menus failing to open or close by updating theme hooks to handle outside clicks synchronously and fixing menu frame level and visibility state.

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
