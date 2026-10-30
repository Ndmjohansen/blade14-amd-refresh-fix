<#
.SYNOPSIS
  Install the refresh-rate EDID override for the Blade 14 (2023) panel and reload the AMD driver.
.EXAMPLE
  .\apply_override.ps1                      # 60 / 120 / 144 Hz (override_edid_60_120_144h2640.bin)
  .\apply_override.ps1 -BinPath .\custom.bin  # an override built with build_override.py
  .\apply_override.ps1 -NoRestart           # reboot instead of reloading the driver
  .\apply_override.ps1 -WhatIf              # show what would be written (no admin needed)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BinPath,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $WhatIfPreference) { Assert-Admin }   # -WhatIf only reads
# Default set here, not in param(): Windows PowerShell 5.1 leaves $PSScriptRoot empty in param defaults.
if (-not $BinPath) { $BinPath = Join-Path $PSScriptRoot 'override_edid_60_120_144h2640.bin' }

$bytes = [IO.File]::ReadAllBytes((Resolve-Path $BinPath))
if ($bytes.Length -ne 256) { throw "$BinPath is $($bytes.Length) bytes, expected 256." }
foreach ($block in 0, 1) {
    $sum = ($bytes[($block * 128)..($block * 128 + 127)] | Measure-Object -Sum).Sum
    if ($sum % 256 -ne 0) { throw "$BinPath block $block has a bad checksum." }
}
$id = ($bytes[8..11] | ForEach-Object { $_.ToString('X2') }) -join ''
if ($id -ne '06AFA75D') { throw "$BinPath is not an EDID for the $PanelId panel." }

$targets = 0
foreach ($inst in Get-PanelInstances) {
    $key = Join-Path $inst.PSPath 'Device Parameters\EDID_OVERRIDE'
    $targets++
    if ($PSCmdlet.ShouldProcess("$PanelId\$($inst.PSChildName)", 'write EDID_OVERRIDE')) {
        if (-not (Test-Path $key)) { New-Item $key | Out-Null }
        # One 128-byte value per EDID block ("0", "1"); a single 256-byte value is ignored.
        # Written in place, so a failure part-way leaves the previous override intact.
        foreach ($block in 0, 1) {
            New-ItemProperty $key -Name "$block" -PropertyType Binary -Force `
                -Value ([byte[]]$bytes[($block * 128)..($block * 128 + 127)]) | Out-Null
        }
        $extra = (Get-Item $key).GetValueNames() | Where-Object { $_ -notin '0', '1' }
        foreach ($name in $extra) { Remove-ItemProperty $key -Name $name }
        Write-Host "Override written to $PanelId\$($inst.PSChildName)"
    }
}

if ($targets -eq 0) { return }
if ($NoRestart) { if (-not $WhatIfPreference) { Write-Host 'Done. Reboot to apply.' } }
elseif ($PSCmdlet.ShouldProcess('AMD display driver', 'restart')) {
    Restart-AmdDisplay
    Write-Host 'Done. Pick the refresh rate in Settings > Display > Advanced display.'
}
