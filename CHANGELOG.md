# changelog

## v1.135 (2026-11-04)

### features & improvements

- **edit mode movers, live magnet snapping & precision inspector (`frames/actionbars/movers.lua`, `frames/options/options.lua`)**:
  - upgraded magnet snapping to a `14px` default snap radius (`SfuiDB.editMode_snapThreshold`) and `4px` edge-to-edge anchor gap (`SfuiDB.editMode_anchorGap`).
  - fixed adjacent edge docking so `0px` touching-edge checks no longer steal the `4px` anchor gap when dragging frames close together, while keeping parallel edge and center-axis alignment flush (`0px`).
  - added perpendicular span-overlap filtering for `4px` edge docking and proximity gating (`<= 300px`) for parallel alignment to prevent cross-screen phantom snaps.
  - removed forced `8px` grid quantization outside magnet snap zones for `1px` exact free placement, and added `shift`-drag support to temporarily bypass magnet snapping while dragging.
  - replaced blind drag-stop snapping with a live cursor-delta `OnUpdate` drag controller that snaps in real time, draws cyan alignment guide lines, highlights the anchor neighbor mover, displays live `x, y` coordinates and snap tags on the mover, and repositions target frames in real time while dragging.
  - expanded `sfui_EditModeDialog` into a two-row floating toolbar and inspector featuring configurable `snap` (`14px` / `18px` / `10px` / `off`) and `gap` (`4px` / `2px` / `0px` / `6px` / `8px`) buttons, a two-click `"confirm?"` safety guard on `reset all`, live selected-frame coordinate readout, lossless 9-point `anchor` cycling (`bottom`, `top`, `center`, `left`, `right`, `bottomleft`, `bottomright`, `topleft`, `topright`), `<` `^` `v` `>` `1px` nudge buttons (`shift`-click for gap step), mousewheel `1px` nudging on hovered movers (`shift` + wheel for `x`, `ctrl` + wheel for gap step), and per-frame `reset`.
  - added a quick-access `edit mode` button in the `/sfui` options window header (`frames/options/options.lua`) next to the close button.
