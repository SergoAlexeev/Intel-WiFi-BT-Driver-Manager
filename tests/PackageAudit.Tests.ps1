$ErrorActionPreference = 'Stop'
$auditor = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Test-DriverPackage.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('package-audit-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $inf = Join-Path $root 'sample.inf'
    $archive = Join-Path $root 'sample.zip'
    Set-Content -LiteralPath $inf -Encoding ASCII -Value @'
[Version]
Signature="$WINDOWS NT$"
CatalogFile=sample.cat
DriverVer=09/01/2026,24.80.0.1
'@
    Set-Content -LiteralPath $archive -Encoding ASCII -Value 'synthetic bytes'
    $sha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $report = & $auditor -InfPath $inf -PackageFile $archive -ExpectedSha256 $sha -SourceUrl 'https://example.invalid/sample.zip'
    if ($report.HashCheck -ne 'PASS' -or $report.Status -ne 'UNVERIFIED' -or $report.InfCatalogMembership -ne 'UNVERIFIED' -or $report.SystemInfCatalogSignature -ne 'UNVERIFIED') {
        throw 'Missing catalog was treated as verified.'
    }
    $sha512 = (Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash
    $shaReport = & $auditor -InfPath $inf -PackageFile $archive -ExpectedSha512 $sha512
    if ($shaReport.HashCheck -ne 'PASS' -or $shaReport.HashAlgorithm -ne 'SHA512') { throw 'Expected SHA-512 was not checked.' }
    $report = & $auditor -InfPath $inf -PackageFile $archive -ExpectedSha256 ('0' * 64)
    if ($report.HashCheck -ne 'FAIL' -or $report.Status -ne 'FAIL') { throw 'Wrong hash was accepted.' }
    Set-Content -LiteralPath (Join-Path $root 'sample.cat') -Encoding ASCII -Value 'not a signed catalog'
    $report = & $auditor -InfPath $inf
    if ($report.CatalogSignature -ne 'FAIL' -or $report.Status -ne 'FAIL') { throw 'Unsigned catalog was accepted.' }
    Write-Host 'Driver package audit checks passed. No download or installation was requested.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
