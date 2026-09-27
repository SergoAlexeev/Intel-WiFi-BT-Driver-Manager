$ErrorActionPreference = 'Stop'
$checker = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Test-DriverCandidate.ps1'
$folder = Join-Path ([IO.Path]::GetTempPath()) ('candidate-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
try {
    $inf = Join-Path $folder 'new.inf'
    $other = Join-Path $folder 'other.inf'
    $installed = Join-Path $folder 'old.json'
    $candidate = Join-Path $folder 'new.json'
    $archive = Join-Path $folder 'sample.zip'
    Set-Content -LiteralPath $inf -Value '[Version]' -Encoding ASCII
    Set-Content -LiteralPath $other -Value '[Version]' -Encoding ASCII
    Set-Content -LiteralPath $archive -Value 'placeholder' -Encoding ASCII
    $id = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'
    $old = [PSCustomObject]@{ HardwareId=$id; DriverVersion='24.70.0.3'; ModelSection='Intel.NTamd64'; InfFile='old.inf' }
    $new = [PSCustomObject]@{ HardwareId=$id; DriverVersion='24.80.0.1'; ModelSection='Intel.NTamd64'; InfFile=$inf }
    @($old) | ConvertTo-Json | Set-Content -LiteralPath $installed -Encoding UTF8
    @($new) | ConvertTo-Json | Set-Content -LiteralPath $candidate -Encoding UTF8
    $base = @{ InstalledReport=$installed; CandidateReport=$candidate; CandidateInf=$inf; HardwareId="$id\1"; Architecture='amd64'; OsBuild=26200; Language='en' }
    $result = & $checker @base
    if ($result.Verdict -ne 'MANUAL_REVIEW' -or $result.Comparison -ne 'NEWER_CANDIDATE' -or -not $result.ReportInfMatchesAuditedFile) {
        throw "Incomplete package checks must require review: $($result | ConvertTo-Json -Compress)"
    }
    $base.HardwareId = 'PCI\VEN_8086&DEV_02F0&SUBSYS_00308086\1'
    $wrongId = & $checker @base
    $base.HardwareId = "$id\1"
    if ($wrongId.Verdict -ne 'REJECT') { throw 'Different SUBSYS was accepted.' }
    $new.InfFile = $other
    @($new) | ConvertTo-Json | Set-Content -LiteralPath $candidate -Encoding UTF8
    $swapped = & $checker @base
    if ($swapped.Verdict -ne 'REJECT' -or $swapped.ReportInfMatchesAuditedFile) { throw 'Different audited INF was accepted.' }
    $new.InfFile = $inf
    @($new) | ConvertTo-Json | Set-Content -LiteralPath $candidate -Encoding UTF8
    $sha = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    $hashed = & $checker @base -PackageFile $archive -ExpectedSha256 $sha
    if ($hashed.HashCheck -ne 'PASS' -or $hashed.Verdict -ne 'MANUAL_REVIEW') { throw 'Hash alone was treated as sufficient.' }
    $bad = & $checker @base -PackageFile $archive -ExpectedSha256 ('0' * 64)
    if ($bad.Verdict -ne 'REJECT') { throw 'Bad package hash was accepted.' }
    $new.DriverVersion = '24.60.0.1'
    @($new) | ConvertTo-Json | Set-Content -LiteralPath $candidate -Encoding UTF8
    $older = & $checker @base
    if ($older.Verdict -ne 'REJECT') { throw 'Older candidate was accepted.' }
    # Mock CIM only inside this test. The audited tool remains read-only.
    function Get-CimInstance {
        param([string]$ClassName)
        if ($ClassName -ne 'Win32_PnPSignedDriver') { throw 'Unexpected CIM class.' }
        [PSCustomObject]@{ DeviceID = "$id\1"; DriverVersion = '24.70.0.3' }
    }
    $new.DriverVersion = '24.80.0.1'
    @($new) | ConvertTo-Json | Set-Content -LiteralPath $candidate -Encoding UTF8
    $live = & $checker @base -VerifyInstalledDevice
    if ($live.InstalledDeviceCheck -ne 'PASS' -or $live.Verdict -ne 'MANUAL_REVIEW') {
        throw 'Live device match or incomplete package handling failed.'
    }
    function Get-CimInstance {
        param([string]$ClassName)
        if ($ClassName -ne 'Win32_PnPSignedDriver') { throw 'Unexpected CIM class.' }
        [PSCustomObject]@{ DeviceID = "$id\1"; DriverVersion = '24.90.0.1' }
    }
    $stale = & $checker @base -VerifyInstalledDevice
    if ($stale.InstalledDeviceCheck -ne 'VERSION_MISMATCH' -or $stale.Verdict -ne 'REJECT') {
        throw 'Stale installed driver report was accepted.'
    }
    Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    Write-Host 'Combined candidate checks passed. No driver was downloaded or installed.'
} finally {
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
