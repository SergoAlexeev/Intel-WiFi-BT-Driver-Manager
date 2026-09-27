$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$metadata = Get-Content -LiteralPath (Join-Path $root 'data\intel-wifi-it-24.70.0.json') -Raw | ConvertFrom-Json
if ($metadata.sha256 -ne 'E74843C855580659559A6D9DB55E1864121E756026F9B543FB8A792DA2EB92A9' -or
    $metadata.driverVersion -ne '24.70.0.3' -or
    $metadata.sourcePage -notmatch '^https://www\.intel\.com/') { throw 'Reviewed Wi-Fi ZIP metadata changed.' }
$checker = Join-Path $root 'tools\Test-OfficialWifiCandidate.ps1'
$fake = Join-Path ([IO.Path]::GetTempPath()) ('wifi-zip-negative-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
    Set-Content -LiteralPath $fake -Encoding ASCII -Value 'not the Intel package'
    try {
        & $checker -PackageFile $fake -Language en | Out-Null
        throw 'Unverified ZIP was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw }
    }
    Write-Host 'Official Intel ZIP pin and wrong-hash rejection passed. No driver was downloaded or installed.'
} finally {
    Remove-Item -LiteralPath $fake -Force -ErrorAction SilentlyContinue
}
