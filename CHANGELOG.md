# changelog

## v1.137 (2026-11-05)

### bug fixes

- **minimap border & geometry (`frames/map/minimap.lua`, `frames/map/square.lua`, `frames/map/indicators.lua`, `frames/map/status.lua`)**:
  - restored accurate camelot round minimap aperture sizing (`192 * scale`) and optical centering (`-4 * scale, 4 * scale`) inside `MinimapHolder` so `MinimapCompassTexture` (`UI-HUD-Minimap-Frame` / `UI-HUD-Minimap-Frame-Pointer`) fits flush around the circular map without clipping or gaps.
  - reparented `MinimapCluster.DielFrame` to `Minimap` and anchored it into the top-right compass bezel socket in round mode while suppressing it in square mode.
  - elevated `bronzeOverlay` above `Minimap` in square camelot bronze mode and replaced the padded `heavybronze-frame-basic` slice with a flush chiseled bronze bevel and corner brackets.
- **bag bar & micro menu offscreen hiding (`frames/hide.lua`)**:
  - updated `SuppressFrame` to park `MicroMenuContainer`, `MicroMenu`, `MainMenuBarMicroButtons`, `BagsBar`, and `MainMenuBarBagButtons` offscreen inside `HiddenFrame` (`0, -10000`), disable mouse input on all child micro and bag slot buttons, and guard against fullscreen panel reparenting (`MicroMenuBar_ClearFullScreenFrame`, `ContainerFrame_ClearFullScreenFrame`).
- **aura container & swing timer taint safety (`frames/bars/target.lua`, `frames/bars/swing.lua`)**:
  - removed forbidden `UnregisterEvent` calls on native `AuraContainer` frames (`SfuiTargetBuffs` and `SfuiTargetDebuffs`) and switched `SwingTimerManagerFrame` suppression to pure alpha suppression without `UnregisterAllEvents()`.
