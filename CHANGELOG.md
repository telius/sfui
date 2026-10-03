# Changelog

## v12.1.0-67 (2026-10-03)

### Features & Major Improvements

- **Camelot Skills Objective Tracker Module (`frames/quests/modules/q_camelot_skills.lua`)**:
  - **Character Panel Shift-Click Tracking**: Added native support to Shift-Click any weapon skill, primary profession, or secondary skill from the Character Panel (`SkillsFrame`) to display as a progress bar in the SFUI objective tracker.
  - **Dynamic Tracking Indicators**: Displays a crisp gold checkmark icon (`checkmark-minimal`) next to tracked skills in `SkillsFrame`, and dynamically adjusts title indentation.
  - **Native Detail Pane Toggle**: Integrated a Blizzard-styled **"Track in Objectives"** checkbox in `SkillDetailFrame` and mouse-enabled the large detail `RankBar` for Shift-Click tracking toggling.
  - **Categorized Progression Bars**: Progress bars dynamically format `rank (+modifier) / maxRank`, color-coding leveling skills with vibrant blue (`#3894fa`) and capped skills with vivid green (`#33d94d`), with gold, cyan, and amber category badges.
  - **Interactive Navigation & Untracking**: Left-clicking a skill bar opens `SkillsFrame`, selects the skill, and smoothly scrolls to it in the list. Right-clicking or Shift-clicking untracks the skill. Shift-clicking the section header untracks all skills.
  - **Top-of-Tracker Priority**: Configured `priority = 1` and `sectionRanks.skills = 5` so tracked character skills always render at the very top of the objective tracker.
  - **Zero-Taint Combat Safety**: Uses pure Lua state toggles with secure hooks; combat guards prevent tainted UI panel calls during combat while skill gains and progress bar updates refresh in real-time mid-combat.

- **Objective Tracker Layout & Usable Screen Area (`config.lua`, `frames/quests/engine/q_layout.lua`)**:
  - **Expanded Vertical Usable Area**: Increased `questlog.maxScreenHeight` from `0.45` to `0.50` (50% of the screen height), allowing more objectives to display before scrolling.
  - **Header Tooltip Category Awareness**: Updated header tooltip generation in `frames/quests/engine/q_blocks.lua` to recognize `skills` for category untrack prompts.

- **Error Frame Filtering (`frames/hide.lua`, `frames/options/tabs/tab_hide.lua`)**:
  - **"Spell is not ready yet" Filter**: Added option to filter `ERR_SPELL_NOT_READY` red error messages from `UIErrorsFrame`, configurable under the Hide options tab.

- **Target Bar Layout Tuning (`config.lua`, `frames/bars/target.lua`)**:
  - **Precise Center Anchoring**: Re-anchored the target bar to the `TOP` of `UIParent` at `(0, -35)`.
  - **Dimension Refinements**: Adjusted dimensions to `230x13` with 1px backdrop padding and 3px power bar.
