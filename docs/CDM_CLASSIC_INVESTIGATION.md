# SFUI Cooldown Manager (CDM) Classic Beta Investigation Report

**Date:** 2026-09-18  
**Environment:** World of Warcraft Classic Beta / "Camelot" / Warcraft Forever (`wow_classic_beta`, build `1.60.1.69913`, TOC `16001`)  
**Target Character:** Level 8 Paladin (Class ID `2`, Realm "Classic Beta PvP 2")  
**Affects:** Tracked Icons (`frames/tracking/trackedicons.lua`), Cooldown Manager UI (`frames/tracking/cdm.lua`), and Common Initialization (`common.lua`)

---

## 1. Executive Summary

On the modern Classic Beta client (running on engine version 1.60.1 with Classic Era rules), SFUI's Tracked Icons and Cooldown Manager (CDM) suffer from empty panel states, failed automated imports, and data loss across `/reload`.

Two distinct issues cause this behavior:
1. **Blizzard CDM Architectural Failure on Classic**: Blizzard's `Blizzard_CooldownViewer` addon code is loaded by the client engine, but its layout manager and data providers refuse to initialize because the Classic ruleset lacks modern specializations (`GetSpecialization()` returns `nil`). As a result, Blizzard's `C_CooldownViewer` API returns empty datasets (`{}`) for categories `0` (Essential), `1` (Utility), and `2` (Buffs).
2. **SavedVariables In-Memory Flush**: When WoW is running, modifying `WTF/.../SavedVariables/sfui.lua` directly on disk does not update the active session. Issuing a `/reload` causes the WoW engine to flush its in-memory tables (`SfuiDB`, which had empty panels) back to disk, immediately overwriting any external edits.

---

## 2. Detailed Technical Breakdown

### A. Why Blizzard's CDM Backend Fails on Classic Beta

1. **`GetSpecialization()` Returns `nil`**:
   In `CooldownViewerUtil.lua`:
   ```lua
   local specialization = C_SpecializationInfo.GetSpecialization();
   ```
   On Classic / Camelot (and for any character below level 10 without a Retail specialization tree), this API returns `nil`.

2. **Spec Tag Generation Failure**:
   `CooldownViewerUtil.GetCurrentClassAndSpecTag()` calls `MakeClassAndSpecTag(classID, specialization)`. With `specialization = nil`, the function returns `nil`.

3. **Layout Manager Assertion / Abort**:
   In `CooldownViewerSettingsLayoutManager.lua`:
   ```lua
   function CooldownViewerLayoutManagerMixin:AddLayout(layoutName, classAndSpecTag, desiredLayoutID)
       assertsafe(classAndSpecTag ~= nil, "Unable to add layout without valid class and spec");
   ```
   Without a spec tag, Blizzard's Layout Manager refuses to create, load, or activate layouts. `GetActiveLayout(Enum.CDMLayoutMode.AllowCreate)` returns `nil`.

4. **Category Sets Return Empty**:
   Calls to:
   - `C_CooldownViewer.GetCooldownViewerCategorySet(0, false)` (Essential)
   - `C_CooldownViewer.GetCooldownViewerCategorySet(1, false)` (Utility)
   - `dp:GetOrderedCooldownIDs()` / `dp:GetOrderedCooldownIDsForCategory(...)`
   all return empty tables (`{}`) or `nil`.

---

### B. Cascading Impact on SFUI

#### 1. Empty Default Panel Initialization
In [`common.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/common.lua):
* `ensure_panels_initialized()` defines default panels:
  - `CENTER`: `populateFunc = sfui.common.populate_center_panel_from_cdm`
  - `UTILITY`: `populateFunc = sfui.common.populate_utility_panel_from_cdm`
* Both functions call `get_all_cdm_entries()`, which queries Blizzard's `C_CooldownViewer`.
* Because `C_CooldownViewer` returns `{}`, both panels are created with `entries = {}`.
* `SfuiDB.iconsInitializedBySpec[specID]` is set to `true`.
* Subsequent reloads match the existing panels by name. At line 1911 of `common.lua`:
  ```lua
  if not panel.entries then
      panel.entries = {}
  end
  -- Removing automatic population of existing empty panels to give user full control.
  ```
  Because automatic population of existing empty panels is commented out, panels remain permanently empty (`entries = {}`).

#### 2. CDM Window: Blank Assignments Pool and Non-Functional Import Dropdowns
In [`frames/tracking/cdm.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/frames/tracking/cdm.lua):
* **Right-Side Assignments Pool (`RenderAssignmentsIconPool`, line 1258)**:
  Queries `C_CooldownViewer.GetCooldownViewerCategorySet(0)` and `(1)`. Since these return `{}`, the pool displays 0 icons.
* **Panel Import Dropdown (`importBtn`, line 917)**:
  Options (*"Import: Essential"*, *"Import: Utility"*, *"Import: Buffs"*) query `C_CooldownViewer.GetCooldownViewerCategorySet(gId)`. Because the backend returns empty, selecting any import option is a no-op.

#### 3. SavedVariables Disk Overwrite on `/reload`
* The WoW client loads `SavedVariables` once on startup / addon load into Lua memory (`SfuiDB`).
* During gameplay, mutations occur in-memory.
* Upon `/reload` or logout, the client serializes `SfuiDB` from Lua memory to disk.
* Editing the file on disk while the game client is running is overwritten on the next `/reload`.

---

## 3. Potential Solutions & Investigation Areas

When examining how other addons (or Blizzard Classic implementations) handle this, consider the following architectural paths:

### Option 1: Spellbook-Driven Fallback Engine (Recommended for Hybrid Clients)
Decouple SFUI from Blizzard's `C_CooldownViewer` when running under Classic rules or when `GetSpecialization()` returns `nil`:
1. **Spellbook Iteration**:
   - Iterate player spellbook tabs and skill lines (`C_SpellBook.GetSpellBookSkillLineInfo` / `sfui.api.GetSpellBookItemSpellID`).
   - Filter out passives (`IsPassiveSpell`).
2. **Classification**:
   - Query `sfui.common.is_known_aura_spell(spellID)` or regex match against aura tables in [`data/spells.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/data/spells.lua).
   - **Auras / Buffs / Seals / Blessings**: Assign to `cat1` (Utility) with `type = "buff", trackAsAura = true, settings = { glowWhenMissing = true }`.
   - **Combat Cooldowns / Attacks**: Assign to `cat0` (Essential/CENTER) with `type = "spell", settings = { showText = true }`.
3. **Feed CDM UI and Auto-Population**:
   - Supply this list to `get_all_cdm_entries()`, `RenderAssignmentsIconPool`, and the Import dropdown so all UI surfaces populate naturally.

### Option 2: Pure Local Database (`SfuiDB`) Authority
* Disable calls to `layoutManager:SaveLayouts()` and `dp:SetCooldownToCategory()` on Classic clients.
* Rely entirely on `SfuiDB.cooldownPanelsBySpec[fallbackSpecID]` as the single source of truth.
* Provide custom drag-and-drop registration directly from the Classic spellbook frame (`SpellButton` dragging).

### Option 3: Empty-Panel Healing Check
* In `ensure_panels_initialized()`, if `#panel.entries == 0` for default panels (`CENTER`, `UTILITY`), allow a fallback population mechanism to re-check if spellbook abilities have become known, rather than locking the empty table indefinitely.

---

## 4. Key Code Locations in SFUI

| File | Lines | Function / Responsibility |
| :--- | :--- | :--- |
| [`common.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/common.lua) | 1618–1665 | `get_all_cdm_entries()` — Queries Blizzard CDM categories 0 and 1. |
| [`common.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/common.lua) | 1792–2038 | `ensure_panels_initialized()` — Spec ID resolution, default panel creation, and deduplication. |
| [`frames/tracking/cdm.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/frames/tracking/cdm.lua) | 910–960 | Import dropdown handler for panel zones. |
| [`frames/tracking/cdm.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/frames/tracking/cdm.lua) | 1244–1320 | `RenderAssignmentsIconPool()` — Populates right-side pool from CDM. |
| [`frames/tracking/cdm.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/frames/tracking/cdm.lua) | 1750–1885 | `HandleExternalDrop()` — Spellbook / cursor drop handler. |
| [`frames/tracking/trackedicons.lua`](file:///home/james/Games/World%20of%20Warcraft/_retail_/Interface/AddOns/sfui/frames/tracking/trackedicons.lua) | 230–270 | `UpdateIconCooldown()` — Cooldown API querying and Classic numeric tuple handling. |
