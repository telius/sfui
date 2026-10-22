# changelog

## v1.118 (2026-10-22)

### features

- **bespoke maw and necrolord themes**:
  - implemented full bespoke texture suites and theme handlers for `maw` and `necrolord` styles (`frames/themes/maw.lua`, `frames/themes/necrolord.lua`, `sfui.toc`).
  - integrated themes into theme switcher options with interactive preview cards, palette definitions, and slash commands (`frames/themes/tab_theme.lua`, `frames/themes/nineslice_themes.lua`, `commands.lua`).
  - enhanced stylized framing and banners for `oldgod` and `fallensanctum` themes (`frames/themes/oldgod.lua`, `frames/themes/fallensanctum.lua`).

- **window framing for loot viewer and portals**:
  - applied theme window borders and nine-slice chrome to the standard loot browser (`frames/gear/lootviewer.lua`).
  - added themed window framing to portals browser and portal popup dialogs across retail and classic/camelot (`frames/portals/portals.lua`, `frames/portals/portals_standard.lua`, `frames/portals/portals_camelot.lua`, `frames/portals/portal_popup.lua`).

- **theme backdrop toggle**:
  - added an opt-in toggle in theme options to configure or disable solid background fills across themed frames (`frames/themes/tab_theme.lua`, `frames/themes/engine.lua`).

### improvements & bug fixes

- **quest tracker header vertical accent bar suppression**:
  - suppressed the vertical left accent bar on quest headers when any non-modern theme is active, preserving themed banner art and styling (`frames/quests/engine/q_layout.lua`, `frames/themes/engine.lua`).

- **forbidden targetunit call removal**:
  - removed forbidden `TargetUnit` invocation from unit health bar click handler to prevent combat lockdown taint (`frames/bars/bar.lua`).
