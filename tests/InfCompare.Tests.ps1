$ErrorActionPreference = 'Stop'
$comparer = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Compare-InfDriverReports.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('inf-compare-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $oldPath = Join-Path $root 'old.json'
    $newPath = Join-Path $root 'new.json'
    @([PSCustomObject]@{ HardwareId='PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; DriverVersion='24.70.0.3'; DeviceName='AX201'; DriverDate='07/29/2026'; ModelSection='Intel.NTamd64'; InfFile='old.inf' }) | ConvertTo-Json | Set-Content -LiteralPath $oldPath -Encoding UTF8
    @([PSCustomObject]@{ HardwareId='PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; DriverVersion='24.80.0.1'; DeviceName='AX201'; DriverDate='09/01/2026'; ModelSection='Intel.NTamd64'; InfFile='new.inf' }) | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086&REV_00\1' 6>&1 | Out-String)
    if ($result -notmatch 'Candidate: match Exact; rows 1' -or $result -notmatch 'Candidate INF version 24\.80\.0\.1 is newer') { throw "Exact ID comparison failed: $result" }
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00308086\1' 6>&1 | Out-String)
    if ($result -notmatch 'Candidate: match None' -or $result -match 'Candidate INF version') { throw "Different SUBSYS was incorrectly matched: $result" }
    Write-Host 'INF comparison checks passed. No download or installation was requested.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
