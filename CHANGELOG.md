# Changelog

## v12.1.0-68 (2026-10-04)

### Features & Major Improvements

- **Objective Tracker Blizzard Edit Mode Integration (`frames/quests/engine/q_tracker.lua`, `q_layout.lua`)**:
  - **Native Anchor to ObjectiveTrackerFrame**: The SFUI objective tracker now anchors directly to Blizzard's `ObjectiveTrackerFrame` (`TOPLEFT` & `TOPRIGHT`) instead of static `UIParent` coordinates.
  - **Full Edit Mode Repositioning**: Reposition, snap, and adjust the objective tracker seamlessly using Blizzard's native Edit Mode (`/editmode` or Game Menu → Edit Mode). Moves in real-time along with layout dragging.
  - **Unblocked Edit Mode Selection Frame**: Safely unsuppressed `ObjectiveTrackerFrame` itself (keeping default quest blocks, headers, and modules hidden) so Blizzard's Edit Mode selection box and drag handles are fully interactive.
  - **Edit Mode Height Synchronization**: Honors `editModeHeight` configured via the Edit Mode height slider as the maximum height budget before scrolling kicks in.
  - **Options Panel Shortcut**: Added an **"open edit mode"** button alongside "reset position" in SFUI Options under Objectives.

- **Dungeon Journal Quest Chain & Map Pin Tracking (`frames/dungeonjournal/dj_pins.lua`, `dungeonjournal.lua`, `dj_quests.lua`)**:
  - **Dynamic Chain Step Tracking**: Dungeon quests with prerequisite chains (e.g. *Leaders of the Fang* chain starting with *The Forgotten Pools*) now dynamically place the World Map pin on the exact step the player is currently on.
  - **Step Progress Badges**: Map pin tooltips and dungeon journal quest views now indicate `step X of Y` in the quest chain.
  - **Quest Level Filtering Integrity**: Ensured "Filter Quests by Level" strictly displays all quests with a lower or equal level requirement (including low-level / gray quests), only hiding quests that require a higher level than your character.

- **Dungeon Journal Granular Hiding System (`frames/dungeonjournal/dungeonjournal.lua`, `dj_sidebar.lua`, `dj_pins.lua`)**:
  - **Context Menus for Dungeons & Pins**: Right-click context menus on sidebar dungeons and World Map pins allow hiding specific dungeons, dungeon pins, or individual quest pins.
  - **Shift-Right-Click Fast Hide**: Instantly hide any map pin with Shift + Right-Click, complete with a clickable chat `[Undo]` link.
  - **Hidden Items Manager**: Added a dedicated management panel to view, search, unhide individual items, or restore all hidden dungeons and pins.
  - **Sidebar Visual Feedback**: Added an eye icon button in the search bar to toggle visibility of hidden dungeons (rendered dimmed with `[hidden]` tags) and an empty-state restore button.

- **Class Quest Tracking Module (`frames/quests/modules/q_camelot_class.lua`, `sfui.toc`)**:
  - Added dedicated Camelot class quest tracker module to highlight class-specific quest objectives.

- **Loot & Guide Sync Automation (`scripts/sync-dj-loot.py`, `data/dj_camelot.lua`)**:
  - Synchronized boss loot drop rates, quest rewards, and chain configurations against the official Wowhead Forever guide.
