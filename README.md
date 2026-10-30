# Blade 14 (2023) refresh-rate workaround for AMD drivers

Since AMD Adrenalin 24.9.1, the Razer Blade 14 (2023) internal 240 Hz panel only offers 60 Hz on the AMD iGPU.

Implemented and tested on AMD Adrenalin 26.10.2 (driver 32.0.32015.12012).

These scripts add **120 Hz and 144 Hz** on current drivers:

- 8-bit colour
- FreeSync
- Windows dynamic refresh rate

**This is a workaround, not a fix.** The choice is between:

| Driver | Max refresh |
|---|---|
| Adrenalin 24.9.1 or newer + this workaround | 144 Hz |
| Adrenalin 24.8.1 (latest driver with 240 Hz), no driver updates | 240 Hz |

240 Hz on current drivers needs a fix from AMD.

## Cause

- The panel's 240 Hz mode (1175.05 MHz pixel clock) needs about 28 Gbps uncompressed.
- The internal eDP link carries about 17 Gbps (4 × 5.4 Gbps).
- 240 Hz therefore requires display compression (DSC), which brings it to about 9.4 Gbps.
- Adrenalin 24.8.1 validates the 240 Hz mode with DSC and accepts it.
- Adrenalin 26.10.2 rejects the DSC version with `DC_FAIL_DP_LINK_BANDWIDTH`, as if it were uncompressed (seen in AMD's driver debug log).
- 24.9.1 and 26.6.x show the same symptom; their cause was not traced.
- The panel only advertises 60 and 240 Hz, so 60 Hz is left.

How the workaround gets around it:

- Current drivers accept modes whose *uncompressed* bandwidth fits the link (pixel clock up to about 690 MHz), and then run them with DSC.
- The scripts add such modes to the panel's EDID through Windows' standard `EDID_OVERRIDE` registry key.

AMD's automatic refresh-rate switching (DLRC/SPRS) is not the cause: disabling it changes nothing.

## Requirements

- Razer Blade 14 (2023) with the **AUO B140QAN06.U** panel (Windows monitor ID `AUO5DA7`). All three scripts stop if that panel is not present.
- AMD Adrenalin 24.9.1 or newer. Tested on 26.10.2 (driver 32.0.32015.12012).
- Hybrid graphics mode, so the AMD iGPU drives the panel.
- Python 3, only to build a different set of rates.

## Use

From an **administrator** PowerShell in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\apply_override.ps1
```

The screen blanks for a few seconds while the AMD driver reloads.

Then pick 120 or 144 Hz in Settings > Display > Advanced display.

Options:

- `-WhatIf` shows what would be written, without admin rights.
- `-NoRestart` skips the driver reload; reboot instead.

The override is written to every `AUO5DA7` monitor instance Windows knows about, including the one used when the dGPU drives the panel.

### Undo

```powershell
powershell -ExecutionPolicy Bypass -File .\revert_override.ps1
```

### If the screen stays black

- A newly selected refresh rate reverts by itself after 15 seconds if not confirmed.
- If the screen is black at boot: start Windows in Safe Mode (it uses a basic display driver), run `revert_override.ps1 -NoRestart` from an administrator PowerShell, and reboot.

### Optional: Windows dynamic refresh rate

The AMD driver blocks Windows' "Dynamic refresh rate" (desktop 60 ↔ 120 Hz) on this panel with a flicker check.

`set_drr.ps1` skips that check by setting `DalSkipFlickerCheck = 1` on the AMD driver's registry key. It removes a safety check; no flicker was seen in testing.

```powershell
powershell -ExecutionPolicy Bypass -File .\set_drr.ps1
```

Reboot afterwards and turn the toggle on.

`set_drr.ps1 -Disable` removes the setting.

### Other rates

```powershell
python build_override.py --rates 120,140
powershell -ExecutionPolicy Bypass -File .\apply_override.ps1 -BinPath .\override_edid_60_120_140.bin
```

- A rate `R` uses the panel's own 2720×1800 timing totals.
- `R@H` uses a horizontal total of `H` (reduced blanking), e.g. `144@2640`.
- Rates must be 60–240 Hz.

Test results on 26.10.2:

| Rate | Pixel clock | Result |
|---|---|---|
| 120 Hz | 587.52 MHz | 8-bit, DSC, FreeSync |
| 140 Hz | 685.44 MHz | 8-bit, DSC, FreeSync |
| 144 Hz (2640 total) | 684.29 MHz | 8-bit, DSC, FreeSync |
| 144–185 Hz (2720 total) | 705–906 MHz | offered, but at 6-bit colour without DSC |
| 200 Hz and up | 979 MHz and up | rejected |
| 30 Hz | 146.88 MHz | garbled picture (the builder refuses rates below 60) |

## Tested result

Blade 14 (2023), Ryzen 9 7940HS, Radeon 780M, Adrenalin 26.10.2:

- 60 / 120 / 144 Hz at 8-bit with DSC
- FreeSync 60–144 with LFC
- Windows dynamic refresh 60 ↔ 120
- The eDP link trains cleanly with zero symbol errors.

## Notes

- Tested on one laptop.
- Adrenalin 26.10.2 with this workaround appears stable so far, but YMMV.
- The override is stored per monitor instance. A driver reinstall or BIOS update can create a new instance, which brings back 60 Hz; run `apply_override.ps1` again.
- A driver update can also remove `DalSkipFlickerCheck`; run `set_drr.ps1` again.
- `WHEA_UNCORRECTABLE_ERROR` crashes occurred on Adrenalin 26.3.1 on the test laptop. None have occurred on 26.10.2 so far.
- The scripts change the registry and come with no warranty (MIT licence).

## For AMD

- Since 24.9.1, eDP modes that require DSC (here 2560×1600 @ 240 Hz, 1175.05 MHz) fail mode validation with `DC_FAIL_DP_LINK_BANDWIDTH`.
- The panel supports DSC 1.1 (8 bpp, 2 or 4 slices), and the compressed stream fits a 4 × 5.4 Gbps link.
- 24.8.1 accepts the same mode with DSC.
