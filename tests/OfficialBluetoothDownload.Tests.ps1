$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $root 'tools\Invoke-OfficialBluetoothReadOnlyCheck.ps1'
function Read-Host { param([string]$Prompt) return 'N' }
function Invoke-WebRequest { throw 'Network was accessed after the user declined.' }
$output = & $scriptPath -Language en 6>&1 | Out-String
if ($output -notmatch 'Download cancelled' -or $output -match 'Downloading the EXE') {
    throw 'Declining Bluetooth download did not stop the check.'
}
Write-Host 'Bluetooth download consent check passed. No network or installation was requested.'
