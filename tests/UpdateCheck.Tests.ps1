$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Manager does not parse' }
foreach ($name in @('Convert-DriverCatalogue', 'Get-DriverCatalogueKey')) {
    $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definitions.Count -ne 1) { throw "Expected one definition of $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$wifiTable = @'
| Device ID | Chipset | Models | Generation | Latest Version | Release Date |
|-----------|---------|--------|------------|----------------|--------------|
| DEV_02F0 | AX201 | Intel AX201 | Wi-Fi 6 | 24.70.0.3 | 29/07/2026 |
| DEV_2723 | AX200 | Intel AX200 | Wi-Fi 6 | 24.20.2.1 | 12/02/2026 |
'@
$btTable = @'
## Supported USB Devices
| PID | Chipset | Generation | Bluetooth | Latest Version | Release Date |
|-----|---------|------------|-----------|----------------|--------------|
| 0026 | AX201 | Wi-Fi 6 | 5.2 | 24.80.0.2 | 01/09/2026 |
## Supported PCI Devices
| DEV | Chipset | Generation | Bluetooth | Latest Version | Release Date |
|-----|---------|------------|-----------|----------------|--------------|
| A876 | AX201 | Wi-Fi 6 | 5.2 | 24.70.0.4 | 31/07/2026 |
'@
$wifi = Convert-DriverCatalogue $wifiTable WiFi
$bt = Convert-DriverCatalogue $btTable Bluetooth
if ($wifi['PCI:02F0'] -ne [version]'24.70.0.3' -or $wifi['PCI:2723'] -ne [version]'24.20.2.1') { throw 'Wi-Fi per-device versions failed' }
if ($bt['USB:0026'] -ne [version]'24.80.0.2' -or $bt['PCI:A876'] -ne [version]'24.70.0.4') { throw 'Bluetooth bus-specific versions failed' }
$device = [pscustomobject]@{ DeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00000000\1' }
if ((Get-DriverCatalogueKey $device WiFi) -ne 'PCI:02F0') { throw 'Wi-Fi hardware ID matching failed' }
$device.DeviceID = 'USB\VID_8087&PID_0026\1'
if ((Get-DriverCatalogueKey $device Bluetooth) -ne 'USB:0026') { throw 'Bluetooth hardware ID matching failed' }
$device.DeviceID = 'USB\VID_1234&PID_0026\1'
if (Get-DriverCatalogueKey $device Bluetooth) { throw 'Non-Intel device was matched' }
try { Convert-DriverCatalogue '| DEV_02F0 | AX201 | Model | Wi-Fi 6 | invalid | date |' WiFi | Out-Null; throw 'Invalid table was accepted' }
catch { if ($_.Exception.Message -eq 'Invalid table was accepted') { throw } }
Write-Host 'Update catalogue checks passed. No network, download or installation was requested.'
