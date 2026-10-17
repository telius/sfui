# Changelog

## v1.105 (2026-10-17)

### features

- **character telemetry & gear management buttons**: repositioned and resized launcher buttons on the character sheet to avoid overlapping third-party addon controls (like chonky), while ensuring the info panel only opens on demand or alongside the character frame (`frames/character/infopanel.lua`).
- **radial ring opening & lerp animations**: restored and polished radial ring menu animations with fluid radial expansion easing from center disc on open and smooth hover scale lerping (`frames/ring/ring_view.lua`, `frames/ring/ring_live.lua`, `frames/ring/ring.lua`).
- **borderless circular ring icons**: eliminated square border artifacts on round ring icons by implementing a 12% icon zoom (`0.12, 0.88, 0.12, 0.88`), extending texture quads beneath the circular mask, and securing texture coordinate hooks against unzoomed coordinate resets (`core/widgets.lua`, `frames/ring/ring_view.lua`, `frames/options/tabs/tab_ring.lua`).
- **threat bar auto-enable options**: threat bar is now disabled by default with smart auto-enable options when grouped or when managing an active combat pet (`frames/bars/threat.lua`, `frames/options/tabs/tab_bars.lua`).
- **hunter & warlock pet experience tracking**: integrated full pet experience bar tracking and leveling progress indicators (`frames/experience/pet.lua`, `frames/experience/events.lua`, `frames/experience/experience.lua`).

### improvements & bug fixes

- **character info panel stability**: resolved anchor family connection setpoint failures and added safe combat pause to prevent heavy cpu calculations and combat lockdown errors (`frames/character/infopanel.lua`).
- **shaman totem bar movable fix**: resolved `SfuiTotemBar:StartMoving(): Frame is not movable` error by enabling `SetMovable(true)` during bar initialization, adding combat lockdown safeguards during drag, and releasing user-placed flags on drag stop (`frames/bars/totembar.lua`).
- **system panel guild safeguards**: disabled discord webhook ping checks when the character is not in a guild (`frames/map/system.lua`).
