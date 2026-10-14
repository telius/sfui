# ellesmere ui investigation: phase 1 & 2

what sfui can borrow from ellesmere ui `v9.5.4` (`~/Downloads/EllesmereUI-v9.5.4`). scope is limited to secret-value hardening (phase 1) and combat enhancements (phase 2). every sfui target listed below has been checked against the current tree.

> [!NOTE]
> sfui has no nameplate, unitframe, or central pixel-scaling module. items that only apply to those systems in ellesmere have been dropped or changed to fit what sfui actually has.

---

## phase 1: secret-value hardening

### 1.1 native heal prediction calculator
- **ellesmere**: [EUI_Nameplates_PlatePool.lua:63-71](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUINameplates/EUI_Nameplates_PlatePool.lua#L63-L71), [EUI_Nameplates_Health.lua:114-118](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUINameplates/EUI_Nameplates_Health.lua#L114-L118)
  - creates the calculator once with `CreateUnitHealPredictionCalculator()`, sets `SetMaximumHealthMode(Default)` and `SetDamageAbsorbClampMode(MaximumHealth)`.
  - each update calls `UnitGetDetailedHealPrediction(unit, nil, calc)`, then reads `GetCurrentHealth()`, `GetMaximumHealth()`, `GetDamageAbsorbs()`.
- **sfui target**: [frames/bars/bars.lua:567-581](file:///home/james/projects/sfui/frames/bars/bars.lua#L567-L581) (`update_bar0`)
  - currently calls `UnitGetIncomingHeals("player")` and `UnitGetTotalAbsorbs("player")` separately and falls back to `or 0`.
  - the clamp mode stops the absorb from running past max health on the engine side.
- **api check**: `CreateUnitHealPredictionCalculator` and `UnitGetDetailedHealPrediction` (`SecretArguments = AllowedWhenUntainted`) are both in [UnitDocumentation.lua](file:///home/james/projects/wow-ui-source-live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua#L1229-L1239).
- **camelot**: keep the current calls as a fallback when the calculator global doesn't exist.

### 1.2 absorb overflow clipping
- **ellesmere**: [EUI_Nameplates_PlatePool.lua:53-62](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUINameplates/EUI_Nameplates_PlatePool.lua#L53-L62). a `CreateMaskTexture()` sized to the health bar clips the absorb textures.
- **sfui target**: [frames/bars/bars.lua:528-539](file:///home/james/projects/sfui/frames/bars/bars.lua#L528-L539)
  - `healPredBar` and `absorbBar` are chained off the fill texture's `TOPRIGHT`, at full bar width. near full health they draw past the bar's right edge.
  - the simplest fix is `bar:SetClipsChildren(true)`. a mask is only needed if clipping cuts into the backdrop or border.
  - this overlaps with 1.1: the clamp mode limits the amount, and clipping limits where it draws.

### 1.3 `SetAlphaFromBoolean` for secret visibility
- **ellesmere**: [EllesmereUICdmBuffBars.lua:4306-4328](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua#L4306-L4328). `fs:SetAlphaFromBoolean(btn:IsShown(), 1, 0)` instead of testing the secret boolean in lua.
- **sfui status**: sfui already uses the color form (`EvaluateColorValueFromBoolean`) in [frames/bars/castbar.lua:191-200](file:///home/james/projects/sfui/frames/bars/castbar.lua#L191-L200). no `SetAlphaFromBoolean` usage yet.
- **sfui target**: audit [frames/tracking/cdm.lua](file:///home/james/projects/sfui/frames/tracking/cdm.lua), [trackedbars.lua](file:///home/james/projects/sfui/frames/tracking/trackedbars.lua) and [trackedicons.lua](file:///home/james/projects/sfui/frames/tracking/trackedicons.lua) for any `if x:IsShown()` / boolean branch on blizzard viewer state. only convert sites that can actually go secret.

### 1.4 pixel snapping guards (low priority)
- **ellesmere**: [EllesmereUI_PixelPerfect.lua:44-127](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUI/EllesmereUI_PixelPerfect.lua#L44-L127)
  - caches the last good height when `GetPhysicalScreenSize()` returns 0 during a display change. otherwise `768/0` spreads NaN through every frame size.
  - adds a `+0.001` epsilon to the floor so float error doesn't drop a whole pixel.
- **sfui status**: no `GetPhysicalScreenSize` / `PixelUtil` usage, so this doesn't apply today. it only matters if a pixel helper is added (e.g. in [core/widgets.lua](file:///home/james/projects/sfui/core/widgets.lua)).

---

## phase 2: combat enhancements

### 2.1 kick-ready cast bar tint
- **ellesmere**: [EllesmereUI_Kick.lua:8-137](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUI/EllesmereUI_Kick.lua#L8-L137)
  - per-class interrupt table, with pet spellbook lookup taking precedence (felhunter / felguard).
  - `C_Spell.GetSpellCooldownDuration(kick)` returns a duration object. `:IsZero()` gives a (possibly secret) boolean, which goes straight into `C_CurveUtil.EvaluateColorValueFromBoolean`. no lua branch on cooldown state.
- **sfui target**: [frames/bars/castbar.lua:182-209](file:///home/james/projects/sfui/frames/bars/castbar.lua#L182-L209) (`UpdateTargetCastBarColor`)
  - already uses the same secret-safe color pattern for `notInterruptible`, so this is a small extension: a "kick ready" color plus a refresh on `SPELL_UPDATE_COOLDOWN` while a target cast is active.
  - when combining, shielded should win over kick-ready. nest the two evaluations: kick tint first, then the shielded override.
- **api note**: per [CurveUtilDocumentation.lua:49-65](file:///home/james/projects/wow-ui-source-live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CurveUtilDocumentation.lua#L49-L65) the arguments are `(bool, valueIfTrue, valueIfFalse)`. sfui's call order is correct. ellesmere passes `(offCooldown, baseTint, readyTint)`, which looks inverted, so don't copy its argument order directly.
- **camelot**: use the `foreverKicksByClass` rank/stance table at [EllesmereUI_Kick.lua:36-51](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUI/EllesmereUI_Kick.lua#L36-L51) as reference, or disable the tint there.
- **mid-cast "kick ready here" tick**: deferred. it needs cooldown-remaining vs cast-remaining comparisons, which go secret in combat.

### 2.2 bloodlust timer via sated debuff
- **ellesmere**: [EllesmereUICdmBuffBars.lua:4330-4345](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUICooldownManager/EllesmereUICdmBuffBars.lua#L4330-L4345)
  - another player's lust buff is secret, but the player's own sated / exhaustion debuff is not.
  - ids: `57723, 57724, 80354, 95809, 160455, 264689, 390435`.
  - the 40s bar starts on the debuff's rising edge (player-only `UNIT_AURA`). a zone-in guard suppresses false edges. no reconstruction after `/reload`.
- **sfui target**: no lust tracking exists. it fits as a special entry in [frames/tracking/trackedbars.lua](file:///home/james/projects/sfui/frames/tracking/trackedbars.lua). register through `sfui.events` per [dispatcher.lua](file:///home/james/projects/sfui/dispatcher.lua). retail only.

### 2.3 shared range cache (low priority)
- **ellesmere**: [EllesmereUI_Range.lua](file:///home/james/Downloads/EllesmereUI-v9.5.4/EllesmereUI/EllesmereUI_Range.lua). a spell and item ladder with a 0.1s result cache shared by four consumers.
- **sfui status**: one consumer, [frames/bars/target.lua:1036-1111](file:///home/james/projects/sfui/frames/bars/target.lua#L1036-L1111) (`SafeIsSpellInRange` with cached help/harm spells). a shared cache only pays off once a second range consumer exists. revisit then.

---

## suggested order

| # | item | file | effort | value |
| :- | :--- | :--- | :- | :- |
| 1 | absorb clipping | `frames/bars/bars.lua` | small | visible bug fix |
| 2 | heal prediction calculator | `frames/bars/bars.lua` | small | secret-safe, clamped |
| 3 | kick-ready tint | `frames/bars/castbar.lua` | medium | new feature |
| 4 | sated lust bar | `frames/tracking/trackedbars.lua` | medium | new feature |
| 5 | `SetAlphaFromBoolean` audit | `frames/tracking/*` | audit | hardening |
| 6 | pixel guards / range cache | n/a | skip for now | low |
