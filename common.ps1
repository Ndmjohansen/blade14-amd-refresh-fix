# Shared helpers, dot-sourced by the other scripts. Nothing here is machine-specific: the panel's
# monitor instances and the AMD GPU are looked up at runtime.

$PanelId  = 'AUO5DA7'   # AUO B140QAN06.U, Razer Blade 14 (2023)
$PanelKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\$PanelId"
$ClassKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this from an administrator PowerShell.'
    }
}

# Every monitor instance Windows has created for the panel. The override is stored per instance and
# Windows can create new ones (driver reinstall, BIOS update), so write to all of them.
function Get-PanelInstances {
    $instances = Get-ChildItem $PanelKey -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.PSPath 'Device Parameters') }
    if (-not $instances) { throw "No $PanelId monitor found. This only works on the AUO B140QAN06.U panel." }
    $instances
}

# AMD display adapter driver keys (where DAL registry settings live).
function Get-AmdClassKeys {
    # GetValue rather than Get-ItemProperty: these keys hold binary values that make Get-ItemProperty throw.
    $keys = Get-ChildItem $ClassKey -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue('ProviderName') -match 'Advanced Micro Devices' }
    if (-not $keys) { throw 'No AMD display driver found.' }
    $keys
}

# Reload the AMD display driver so it re-reads the EDID (the screen blanks for a few seconds).
function Restart-AmdDisplay {
    $gpu = Get-PnpDevice -Class Display -PresentOnly |
        Where-Object { $_.Manufacturer -match 'Advanced Micro Devices' } | Select-Object -First 1
    if (-not $gpu) { Write-Warning 'AMD GPU not found; reboot instead.'; return }
    Write-Host "Restarting $($gpu.FriendlyName) (screen will blank briefly)..."
    pnputil /restart-device $gpu.InstanceId | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "pnputil returned $LASTEXITCODE; reboot to apply." }
}
