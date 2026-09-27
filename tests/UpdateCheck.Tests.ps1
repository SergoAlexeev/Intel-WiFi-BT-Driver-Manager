$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Manager does not parse' }
foreach ($name in @('Convert-DriverCatalogue', 'Get-DriverCatalogueKey', 'Get-LocalWirelessKey', 'Get-LocalWirelessCatalogue', 'Get-GraphicsCandidateMetadata', 'Test-Graphics6thGenReference', 'Get-GraphicsReferenceFamily', 'Show-UpdateCheck')) {
    $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definitions.Count -ne 1) { throw "Expected one definition of $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$script:graphicsVersion = [version]'31.0.101.2145'
$script:graphicsSha512 = 'D30369A17F66A787D477FE77787D934A1E74581F27CB19BA1608DF22E76C8DCE68B589DB327456527AE9228D8788663CE005467DF84C722C03F59A2E9297C2D5'
$script:graphicsUri = 'https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe'
function L($Ru, $En) { return $En }
$manifest = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\driver-packages.json'
$reviewed = Get-GraphicsCandidateMetadata -CataloguePath $manifest
if (-not $reviewed.Catalogue -or $reviewed.ReviewedOn -ne '2026-09-27' -or $reviewed.Source -notmatch 'intel.com') { throw ('Reviewed graphics candidate metadata failed: ' + ($reviewed | ConvertTo-Json -Compress)) }
$standalone = Get-GraphicsCandidateMetadata -CataloguePath (Join-Path $PSScriptRoot 'missing-catalogue.json')
if ($standalone.Catalogue -or $standalone.Detail -notmatch 'Embedded pinned') { throw 'Standalone manager fallback failed.' }

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
$snapshot = Get-LocalWirelessCatalogue
if ($snapshot['WiFi:PCI:02F0:SUBSYS_00748086'].Version -ne [version]'24.70.0.3' -or
    $snapshot['Bluetooth:USB:0026'].Version -ne [version]'24.80.0.2' -or
    $snapshot.ContainsKey('WiFi:PCI:2723')) { throw 'Local catalogue coverage is incorrect' }
$device.DeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086&REV_00\1'
if ((Get-LocalWirelessKey $device WiFi) -ne 'WiFi:PCI:02F0:SUBSYS_00748086') { throw 'Exact Wi-Fi local key failed' }
$device.DeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00308086\1'
if ($snapshot.ContainsKey((Get-LocalWirelessKey $device WiFi))) { throw 'Different SUBSYS matched local catalogue' }
$sixthDevice = [pscustomobject]@{ DeviceClass = 'DISPLAY'; DeviceID = 'PCI\VEN_8086&DEV_191B&SUBSYS_00000000\1'; DeviceName = 'Intel(R) HD Graphics 530' }
$sixthCpu = [pscustomobject]@{ Name = 'Intel(R) Core(TM) i7-6700HQ CPU @ 2.60GHz' }
$sixthOs = [pscustomobject]@{ Caption = 'Windows 11 Home'; OSArchitecture = '64-bit' }
if (-not (Test-Graphics6thGenReference $sixthCpu $sixthDevice $sixthOs)) { throw '6th Gen graphics read-only identification failed' }
$sixthDevice.DeviceID = 'PCI\VEN_10DE&DEV_191B\1'
if (Test-Graphics6thGenReference $sixthCpu $sixthDevice $sixthOs) { throw 'Non-Intel display was identified' }
$sixthDevice.DeviceID = 'PCI\VEN_8086&DEV_191B\1'
$sixthCpu.Name = 'Intel(R) Core(TM) i7-10710U CPU'
if (Test-Graphics6thGenReference $sixthCpu $sixthDevice $sixthOs) { throw '10th Gen was identified as 6th Gen' }
$sixthCpu.Name = 'Intel(R) Core(TM) i7-1165G7 CPU'
$sixthDevice.DeviceName = 'Intel(R) Iris(R) Xe Graphics'
if ((Get-GraphicsReferenceFamily $sixthCpu $sixthDevice $sixthOs) -ne 'Core11to14') { throw '11th Gen family identification failed' }
$sixthCpu.Name = 'Intel(R) Core(TM) Ultra 7 155H'
$sixthDevice.DeviceName = 'Intel(R) Arc Graphics'
if ((Get-GraphicsReferenceFamily $sixthCpu $sixthDevice $sixthOs) -ne 'ArcUltra') { throw 'Core Ultra family identification failed' }
$sixthDevice.DeviceID = 'PCI\VEN_10DE&DEV_191B\1'
if ((Get-GraphicsReferenceFamily $sixthCpu $sixthDevice $sixthOs) -ne 'Unknown') { throw 'Non-Intel display family identification failed' }
$sixthDevice.DeviceID = 'PCI\VEN_8086&DEV_191B\1'
$sixthDevice.DeviceName = 'Intel(R) HD Graphics 530'
try { Convert-DriverCatalogue '| DEV_02F0 | AX201 | Model | Wi-Fi 6 | invalid | date |' WiFi | Out-Null; throw 'Invalid table was accepted' }
catch { if ($_.Exception.Message -eq 'Invalid table was accepted') { throw } }

# A laptop with Intel graphics and non-Intel wireless must cause no catalogue requests.
$sixthCpu.Name = 'Intel(R) Core(TM) i7-6700HQ CPU'
$script:graphics6thReferenceVersion = [version]'31.0.101.2115'
$script:graphics6thReferenceUri = 'https://www.intel.com/content/www/us/en/download/762755/intel-6th-gen-processor-graphics-windows.html'
$script:graphics11to14ReferenceUri = 'https://www.intel.com/content/www/us/en/download/864990/intel-11th-14th-gen-processor-graphics-windows.html'
$script:graphicsArcReferenceUri = 'https://www.intel.com/content/www/us/en/download/785597/intel-arc-graphics-windows.html'
$script:wifiCatalogueUri = 'https://example.invalid/wifi'
$script:bluetoothCatalogueUri = 'https://example.invalid/bt'
function L($Ru, $En) { return $En }
function Test-GraphicsPackageMatch { return $false }
$script:mockIntelWireless = $false
function Get-CimInstance($ClassName) {
    switch ($ClassName) {
        'Win32_ComputerSystem' { return [pscustomobject]@{ Manufacturer = 'Example'; Model = 'ExampleModel' } }
        'Win32_Processor' { return $sixthCpu }
        'Win32_OperatingSystem' { return $sixthOs }
        'Win32_PnPSignedDriver' {
            [pscustomobject]@{ DeviceClass = 'DISPLAY'; DeviceID = 'PCI\VEN_8086&DEV_191B\1'; DeviceName = 'Intel(R) HD Graphics 530'; DriverVersion = '31.0.101.2125' }
            [pscustomobject]@{ DeviceClass = 'NET'; DeviceID = 'PCI\VEN_168C&DEV_0042\1'; DeviceName = 'Qualcomm Wireless'; DriverVersion = '12.0.0.1259' }
            if ($script:mockIntelWireless) {
                [pscustomobject]@{ DeviceClass = 'NET'; DeviceID = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086\1'; DeviceName = 'Intel(R) Wi-Fi 6 AX201'; DriverVersion = '24.70.0.3' }
                [pscustomobject]@{ DeviceClass = 'BLUETOOTH'; DeviceID = 'USB\VID_8087&PID_0026\1'; DeviceName = 'Intel(R) Wireless Bluetooth(R)'; DriverVersion = '24.80.0.2' }
            }
        }
    }
}
function Invoke-WebRequest { throw 'Unexpected network request' }
Show-UpdateCheck | Out-Null
$script:mockIntelWireless = $true
Show-UpdateCheck | Out-Null
$sixthCpu.Name = 'Intel(R) Core(TM) i7-10710U CPU'
function Test-GraphicsPackageMatch { return $true }
$output = Show-UpdateCheck 6>&1 | Out-String
if ($output -notmatch 'Update available' -or $output -notmatch 'Newer\s+online releases are not checked') {
    throw "Graphics candidate details or version status were lost: $output"
}
Write-Host 'Update catalogue checks passed. No network, download or installation was requested.'
