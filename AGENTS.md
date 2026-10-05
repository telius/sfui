# Agent Guidelines & Rules

## Communication Style
- Strictly lowercase text in all chat responses, user-facing text, labels, and tooltips ("no caps").

## Changelog Formatting
- **NEVER put full filesystem paths or `file://` URLs in `CHANGELOG.md`**.
- Always use clean relative paths in backticks (e.g. `config.lua`, `frames/tracking/panels.lua`).
- In `CHANGELOG.md`, only keep the CURRENT release patch notes. When bumping/releasing a new version, replace/overwrite past release notes.

## WoW UI & Addon Development
- Always use the in-house Blizzard Interface APIs / source code for authoritative API reference, frame templates, mixins, and taint analysis (never make external web requests when local extracts are available):
  - **Camelot / Forever / Classic UI**: `/home/james/projects/wow-ui-source-forever/Interface`
  - **Retail / Midnight / Live UI**: `/home/james/projects/wow-ui-source-live/Interface`
- Do NOT automatically commit, tag, or push version updates to Git without explicit user instruction.
