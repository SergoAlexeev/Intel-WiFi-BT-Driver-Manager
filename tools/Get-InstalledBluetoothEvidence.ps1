<#
.SYNOPSIS
    Reports read-only evidence for the currently installed Intel Bluetooth driver.
.DESCRIPTION
    Reads Windows PnP records, the active OEM INF and its Windows catalog
    signature. An installed INF signature does not identify the download URL,
    installer, or the organization that distributed the driver package.
#>
param([ValidateSet('ru', 'en')][string]$Language = 'ru')
$ErrorActionPreference = 'Stop'
function Say([string]$Ru, [string]$En) {
    if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En }
}
$devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceClass -eq 'BLUETOOTH' -and
    $_.DeviceName -eq 'Intel(R) Wireless Bluetooth(R)' -and
    $_.DeviceID -like 'USB\VID_8087&PID_0026*'
})
if ($devices.Count -ne 1) {
    throw "Expected exactly one Intel Wireless Bluetooth device; found $($devices.Count)."
}
$device = $devices[0]
if ($device.InfName -notmatch '(?i)^oem[0-9]+\.inf$') {
    throw 'Windows did not report a valid installed OEM INF name.'
}
$inf = Join-Path (Join-Path $env:windir 'INF') $device.InfName
if (-not (Test-Path -LiteralPath $inf -PathType Leaf)) {
    throw "The active OEM INF was not found: $inf"
}
$signature = Get-AuthenticodeSignature -LiteralPath $inf
$versionLines = @(Get-Content -LiteralPath $inf | Where-Object {
    $_ -match '^\s*DriverVer\s*=\s*[^,]+,\s*[0-9]+(?:\.[0-9]+){1,3}\s*(?:;.*)?$'
})
$infVersion = if ($versionLines.Count -eq 1 -and
    $versionLines[0] -match '^\s*DriverVer\s*=\s*[^,]+,\s*([0-9]+(?:\.[0-9]+){1,3})') {
    $Matches[1]
} else { $null }
$versionMatch = if ($infVersion) { $infVersion -eq $device.DriverVersion } else { $null }
$signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
Say 'Считываю установленный драйвер из Windows. Скачивания и установки нет.' 'Reading the active Windows driver. No download or installation.'
Say "Устройство: $($device.DeviceName); версия Windows: $($device.DriverVersion); INF: $($device.InfName)." "Device: $($device.DeviceName); Windows version: $($device.DriverVersion); INF: $($device.InfName)."
Say "Версия в INF: $infVersion; совпадает с Windows: $versionMatch; подпись INF: $($signature.Status) ($($signature.SignatureType))." "INF version: $infVersion; matches Windows: $versionMatch; INF signature: $($signature.Status) ($($signature.SignatureType))."
Say 'Подпись подтверждает файл в установленной системе. По ней нельзя восстановить адрес загрузки или доказать, какой установщик использовался.' 'The signature validates the installed file. It does not recover the download URL or establish which installer was used.'
[PSCustomObject]@{
    DeviceName = $device.DeviceName
    DeviceId = $device.DeviceID
    InstalledVersion = $device.DriverVersion
    InfName = $device.InfName
    InfDriverVersion = $infVersion
    VersionMatches = $versionMatch
    InfSignatureStatus = [string]$signature.Status
    InfSignatureType = [string]$signature.SignatureType
    InfSigner = $signer
    ReportedManufacturer = $device.Manufacturer
    SourcePackageUrl = 'UNKNOWN'
    InstallerIdentity = 'UNKNOWN'
}
