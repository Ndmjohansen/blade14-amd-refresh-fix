<#
.SYNOPSIS
  Remove the EDID override from the Blade 14 (2023) panel and reload the AMD driver.
.EXAMPLE
  .\revert_override.ps1
  .\revert_override.ps1 -NoRestart    # e.g. from Safe Mode; reboot afterwards
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$NoRestart)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $WhatIfPreference) { Assert-Admin }   # -WhatIf only reads

$removed = $false
foreach ($inst in Get-PanelInstances) {
    $key = Join-Path $inst.PSPath 'Device Parameters\EDID_OVERRIDE'
    if (-not (Test-Path $key)) { continue }
    $removed = $true
    if ($PSCmdlet.ShouldProcess("$PanelId\$($inst.PSChildName)", 'remove EDID_OVERRIDE')) {
        Remove-Item $key -Recurse -Force
        Write-Host "Override removed from $PanelId\$($inst.PSChildName)"
    }
}

if (-not $removed) { Write-Host 'No override found.'; return }
if ($NoRestart) { if (-not $WhatIfPreference) { Write-Host 'Done. Reboot to apply.' } }
elseif ($PSCmdlet.ShouldProcess('AMD display driver', 'restart')) { Restart-AmdDisplay; Write-Host 'Done.' }
