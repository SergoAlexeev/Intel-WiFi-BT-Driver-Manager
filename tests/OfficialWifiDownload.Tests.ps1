$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $root 'tools\Invoke-OfficialWifiReadOnlyCheck.ps1'
function Read-Host { param([string]$Prompt) return 'N' }
function Invoke-WebRequest { throw 'Network was accessed after the user declined.' }
$output = & $scriptPath -Language en 6>&1 | Out-String
if ($output -notmatch 'Download cancelled' -or $output -match 'Downloading Intel ZIP') {
    throw 'Declining download did not stop the read-only pilot.'
}
Write-Host 'Intel ZIP consent check passed. No network or installation was requested.'
