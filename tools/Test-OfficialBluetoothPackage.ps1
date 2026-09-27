<#
.SYNOPSIS
    Audits a locally downloaded official Intel Bluetooth EXE without running it.
.DESCRIPTION
    The executable remains unopened by the Windows installer. The check verifies
    Intel's published SHA-256 and a valid Intel Authenticode signer, then compares
    Intel's published AX201 driver version with the locally installed driver.
    It does not inspect INF files inside the executable or prove Windows ranking.
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackageFile,
    [ValidateSet('ru', 'en')][string]$Language = 'ru'
)
$ErrorActionPreference = 'Stop'
function Say([string]$Ru, [string]$En) {
    if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En }
}
$root = Split-Path $PSScriptRoot -Parent
$meta = Get-Content -LiteralPath (Join-Path $root 'data\intel-bluetooth-24.70.0.json') -Raw | ConvertFrom-Json
$pin = '001DF2E294E86D051645EA1367F4A19518CA8C2A52782CDD4C1CB81C3C0F038A'
if ($meta.sha256 -ne $pin -or $meta.fileName -ne 'BT-24.70.0-64UWD-Win10-Win11.exe' -or
    $meta.packageVersion -ne '24.70.0' -or $meta.driverVersionForAx201 -ne '24.70.0.4' -or
    $meta.sourcePage -ne 'https://www.intel.com/content/www/us/en/download/18649/intel-wireless-bluetooth-drivers-for-windows-10-and-windows-11.html') {
    throw 'Reviewed Intel Bluetooth package metadata changed.'
}
Say 'Шаг 1/3. Сверяю SHA-256 файла EXE со значением на странице Intel.' 'Step 1/3. Comparing EXE SHA-256 with Intel published value.'
if ((Get-FileHash -LiteralPath $PackageFile -Algorithm SHA256).Hash -ine $pin) {
    throw 'Intel Bluetooth EXE SHA-256 mismatch. The executable was not launched.'
}
Say 'Шаг 2/3. Проверяю цифровую подпись EXE средствами Windows.' 'Step 2/3. Checking the EXE Authenticode signature with Windows.'
$signature = Get-AuthenticodeSignature -LiteralPath $PackageFile
if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
    $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Intel Corporation(?:,|$)') {
    throw "Bluetooth EXE signature is not a valid Intel Corporation signature: $($signature.Status)."
}
Say 'Шаг 3/3. Сравниваю опубликованную версию AX201 с установленной версией Bluetooth.' 'Step 3/3. Comparing the published AX201 version with the installed Bluetooth driver.'
$wifi = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceClass -eq 'NET' -and $_.DeviceID -like 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086*'
})
if ($wifi.Count -ne 1) { throw 'The reviewed Intel AX201 Wi-Fi device was not found on this PC.' }
$devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceClass -eq 'BLUETOOTH' -and
    $_.DeviceName -eq 'Intel(R) Wireless Bluetooth(R)' -and
    $_.DeviceID -like 'USB\VID_8087*'
})
if ($devices.Count -ne 1) {
    throw "Expected exactly one installed Intel Wireless Bluetooth device with USB VID_8087; found $($devices.Count)."
}
$installed = $devices[0].DriverVersion
if ($installed -notmatch '^\d+(\.\d+){3}$') { throw 'Installed Bluetooth version is not a four-part numeric version.' }
$reference = [version]$meta.driverVersionForAx201
$current = [version]$installed
$status = if ($current -lt $reference) { 'PUBLISHED_NEWER_REVIEW' }
          elseif ($current -eq $reference) { 'SAME_VERSION' }
          else { 'INSTALLED_NEWER_THAN_REFERENCE' }
Say "Установлено: $installed; опубликовано Intel для AX201: $reference; результат: $status." "Installed: $installed; Intel AX201 reference: $reference; result: $status."
Say 'SHA-256 и подпись EXE проверены. INF внутри установщика и его совместимость с точным ID не проверялись. Установщик не запускался; никаких драйверов не установлено.' 'EXE hash and signature passed. The internal INF and its exact ID compatibility were not checked. The installer was not launched and no driver was installed.'
[PSCustomObject]@{
    Status = $status
    InstalledVersion = $installed
    IntelAx201Reference = [string]$reference
    PackageHash = 'PASS'
    AuthenticodeSignature = 'PASS'
    InfCompatibility = 'UNVERIFIED'
    Installation = 'NOT_STARTED'
    SourcePage = $meta.sourcePage
}
