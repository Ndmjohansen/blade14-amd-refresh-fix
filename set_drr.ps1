<#
.SYNOPSIS
  Allow Windows "Dynamic refresh rate" (desktop 60 <-> 120 Hz) on the AMD driver.
.DESCRIPTION
  The AMD driver refuses Windows dynamic refresh rate on this panel because of a flicker check.
  This sets the driver's DalSkipFlickerCheck = 1 to skip that check. It is a safety check, so use at
  your own risk; no flicker was seen in testing. Reboot afterwards, then turn the toggle on under
  Settings > Display > Advanced display.
.EXAMPLE
  .\set_drr.ps1             # enable
  .\set_drr.ps1 -Disable    # remove the setting again
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Disable)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $WhatIfPreference) { Assert-Admin }   # -WhatIf only reads
$null = Get-PanelInstances   # stop unless this is the AUO5DA7 panel

foreach ($k in Get-AmdClassKeys) {
    if ($Disable) {
        if ($PSCmdlet.ShouldProcess($k.PSChildName, 'remove DalSkipFlickerCheck')) {
            Remove-ItemProperty $k.PSPath -Name DalSkipFlickerCheck -ErrorAction SilentlyContinue
        }
    } elseif ($PSCmdlet.ShouldProcess($k.PSChildName, 'set DalSkipFlickerCheck = 1')) {
        New-ItemProperty $k.PSPath -Name DalSkipFlickerCheck -PropertyType DWord -Value 1 -Force | Out-Null
    }
    $v = (Get-Item $k.PSPath).GetValue('DalSkipFlickerCheck')
    Write-Host "$($k.GetValue('DriverDesc')): DalSkipFlickerCheck = $(if ($null -eq $v) { '(not set)' } else { $v })"
}
if (-not $WhatIfPreference) { Write-Host 'Reboot for the driver to pick this up.' }
