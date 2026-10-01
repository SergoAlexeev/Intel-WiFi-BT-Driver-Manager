$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$checker = Join-Path $root 'tools\Invoke-MicrosoftBluetoothCabReadOnlyCheck.ps1'
$data = Get-Content -LiteralPath (Join-Path $root 'data\microsoft-bluetooth-24.80.0.2-pid0026.json') -Raw | ConvertFrom-Json
if ($data.sha256 -ne 'BE7997BF8526144830B9C17D89FFCB5951DB78847D37FD63BA167F104040AEBF' -or
    $data.driverVersion -ne '24.80.0.2' -or
    $data.deviceIdPrefix -ne 'USB\VID_8087&PID_0026') { throw 'Bluetooth CAB pin changed.' }
$fake = Join-Path ([IO.Path]::GetTempPath()) ('bluetooth-cab-negative-' + [guid]::NewGuid().ToString('N') + '.cab')
try {
    Set-Content -LiteralPath $fake -Value 'not a driver' -Encoding ASCII
    try {
        & $checker -PackageFile $fake -Language en | Out-Null
        throw 'Invalid CAB was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw }
    }
} finally { Remove-Item -LiteralPath $fake -Force -ErrorAction SilentlyContinue }
function Read-Host { param([string]$Prompt) return 'N' }
function Invoke-WebRequest { throw 'Network accessed after decline.' }
$output = & $checker -Language en 6>&1 | Out-String
if ($output -notmatch 'Download cancelled') { throw 'Declining CAB download did not stop the check.' }
function Read-Host { param([string]$Prompt) return 'Y' }
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing, [int]$TimeoutSec)
    Set-Content -LiteralPath $OutFile -Value 'invalid downloaded CAB' -Encoding ASCII
}
try {
    & $checker -Language en | Out-Null
    throw 'Invalid downloaded CAB was accepted.'
} catch {
    if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw }
}
Write-Host 'Bluetooth CAB pin, invalid local and downloaded files, and decline checks passed. No driver installed.'
