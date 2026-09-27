$ErrorActionPreference = 'Stop'
$generator = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Get-InfDriverReport.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('inf-report-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $inf = @'
[Version]
Signature="$WINDOWS NT$"
Class=Net
Provider=%Intel%
DriverVer=07/29/2026,24.70.0.3

[Manufacturer]
%Intel%=Intel,NTamd64.10.0

[Intel.NTamd64.10.0]
%AX201%=Install, PCI\VEN_8086&DEV_02F0&SUBSYS_12345678, PCI\VEN_8086&DEV_02F0
%Other%=Install, PCI\VEN_8086&DEV_06F0 ; ignored comment
%Other%=Install, PCI\VEN_8086&DEV_02F0&SUBSYS_87654321

[Strings]
Intel="Intel Corporation"
AX201="Intel Wi-Fi 6 AX201"
Other="Other Intel device"
'@
    Set-Content -LiteralPath (Join-Path $root 'example.inf') -Value $inf -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $root 'not-a-driver.inf') -Value '[Version]' -Encoding ASCII
    $json = Join-Path $root 'report.json'
    & $generator -Path $root -OutputPath $json | Out-Null
    $rows = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
    if ($rows.Count -ne 4) { throw "Expected 4 hardware IDs, got $($rows.Count)" }
    if (@($rows | Where-Object { $_.HardwareId -eq 'PCI\VEN_8086&DEV_02F0&SUBSYS_12345678' -and $_.DriverVersion -eq '24.70.0.3' -and $_.Provider -eq 'Intel Corporation' -and $_.DeviceName -eq 'Intel Wi-Fi 6 AX201' -and $_.ModelSection -eq 'Intel.NTamd64.10.0' }).Count -ne 1) { throw 'INF parsing or string resolution failed' }
    if (@($rows | Where-Object { $_.HardwareId -eq 'PCI\VEN_8086&DEV_02F0&SUBSYS_87654321' -and $_.DeviceName -eq 'Other Intel device' }).Count -ne 1) { throw 'SUBSYS-specific model mapping failed' }
    Write-Host 'INF report checks passed. No driver was downloaded or installed.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
