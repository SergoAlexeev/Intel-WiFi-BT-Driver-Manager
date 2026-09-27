$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$validator = Join-Path $root 'tools\Test-DriverCatalogue.ps1'
$manifest = Join-Path $root 'data\driver-packages.json'
$report = & $validator -Path $manifest
if ($report.Status -ne 'VALID_STRUCTURE' -or $report.PackageCount -ne 1) { throw 'Curated catalogue failed validation.' }
$item = (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).packages[0]
$manager = Get-Content -LiteralPath (Join-Path $root 'IntelWiFiBTManager.ps1') -Raw
foreach ($value in @($item.version, $item.sha512, $item.downloadUrl)) {
    if (-not $manager.Contains([string]$value)) { throw "Catalogue does not match pinned manager package: $value" }
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('catalogue-test-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $data.packages[0].sha512 = ('0' * 127)
    $data | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding UTF8
    try { $null = & $validator -Path $temp; throw 'Malformed hash was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'Invalid SHA-512') { throw } }

    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $data.packages[0].downloadUrl = 'https://intel.com.evil.example/file.exe'
    $data | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding UTF8
    try { $null = & $validator -Path $temp; throw 'Untrusted host was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'Unexpected source URL') { throw } }
    Write-Host 'Driver catalogue checks passed. No network or installation was requested.'
} finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
