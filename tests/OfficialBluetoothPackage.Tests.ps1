$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$meta = Get-Content -LiteralPath (Join-Path $root 'data\intel-bluetooth-24.70.0.json') -Raw | ConvertFrom-Json
if ($meta.sha256 -ne '001DF2E294E86D051645EA1367F4A19518CA8C2A52782CDD4C1CB81C3C0F038A' -or
    $meta.driverVersionForAx201 -ne '24.70.0.4' -or
    $meta.sourcePage -notmatch '^https://www\.intel\.com/') { throw 'Reviewed Intel Bluetooth metadata changed.' }
$checker = Join-Path $root 'tools\Test-OfficialBluetoothPackage.ps1'
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($checker, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) { throw "Bluetooth checker parse errors: $errors" }
$fake = Join-Path ([IO.Path]::GetTempPath()) ('bluetooth-negative-' + [guid]::NewGuid().ToString('N') + '.exe')
try {
    Set-Content -LiteralPath $fake -Value 'not an Intel executable' -Encoding ASCII
    try {
        & $checker -PackageFile $fake -Language en | Out-Null
        throw 'A file with an invalid SHA-256 was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'SHA-256 mismatch') { throw }
    }
    Write-Host 'Bluetooth pin, parser and invalid-file rejection passed. No executable was launched.'
} finally {
    Remove-Item -LiteralPath $fake -Force -ErrorAction SilentlyContinue
}
