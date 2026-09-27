$ErrorActionPreference = 'Stop'
$comparer = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Compare-InfDriverReports.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('inf-compare-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $oldPath = Join-Path $root 'old.json'
    $newPath = Join-Path $root 'new.json'
    @([PSCustomObject]@{ HardwareId='PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; DriverVersion='24.70.0.3'; DeviceName='AX201'; DriverDate='07/29/2026'; ModelSection='Intel.NTamd64'; InfFile='old.inf' }) | ConvertTo-Json | Set-Content -LiteralPath $oldPath -Encoding UTF8
    @([PSCustomObject]@{ HardwareId='PCI\VEN_8086&DEV_02F0&SUBSYS_00748086'; DriverVersion='24.80.0.1'; DeviceName='AX201'; DriverDate='09/01/2026'; ModelSection='Intel.NTamd64'; InfFile='new.inf' }) | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086&REV_00\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'Candidate: match Exact; rows 1' -or $result -notmatch 'Candidate INF version 24\.80\.0\.1 is newer') { throw "Exact ID comparison failed: $result" }
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00308086\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'Candidate: match None' -or $result -match 'Candidate INF version') { throw "Different SUBSYS was incorrectly matched: $result" }
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086\1' -Architecture x86 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'candidate Incompatible' -or $result -match 'Candidate INF version') { throw "Architecture mismatch was accepted: $result" }
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086\1' 6>&1 | Out-String)
    if ($result -notmatch 'candidate Unknown' -or $result -match 'Candidate INF version') { throw "Missing target data was accepted: $result" }
    $new = Get-Content -LiteralPath $newPath -Raw | ConvertFrom-Json
    $new.ModelSection = 'Intel.NTamd64.10.0...30000'
    $new | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'candidate Incompatible' -or $result -match 'Candidate INF version') { throw "Newer Windows build requirement was accepted: $result" }
    $new.ModelSection = 'Device.NTamd64.10.0...17735'
    $new | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'Candidate INF version 24\.80\.0\.1 is newer') { throw "Real Wi-Fi INF OS section was rejected: $result" }
    $new.ModelSection = 'IntelGfx.NTamd64.10.0...16225'
    $new.HardwareId = 'PCI\VEN_8086&DEV_191B'
    $new | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $old = Get-Content -LiteralPath $oldPath -Raw | ConvertFrom-Json
    $old.HardwareId = 'PCI\VEN_8086&DEV_191B'
    $old.ModelSection = 'IntelGfx.NTamd64.10.0...16225'
    $old | ConvertTo-Json | Set-Content -LiteralPath $oldPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_191B&SUBSYS_380217AA\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'Candidate: match Generic; rows 1' -or $result -notmatch 'Candidate INF version') { throw "Generic Graphics 530 ID was rejected: $result" }
    $other = $new | Select-Object *
    $other | Add-Member -NotePropertyName InstallSection -NotePropertyValue DifferentInstall -Force
    @($new, $other) | ConvertTo-Json | Set-Content -LiteralPath $newPath -Encoding UTF8
    $result = (& $comparer -InstalledReport $oldPath -CandidateReport $newPath -HardwareId 'PCI\VEN_8086&DEV_191B&SUBSYS_380217AA\1' -Architecture amd64 -OsBuild 26200 6>&1 | Out-String)
    if ($result -notmatch 'Multiple matching rows' -or $result -match 'Candidate INF version') { throw "Ambiguous install mappings were accepted: $result" }
    Write-Host 'INF comparison checks passed. No download or installation was requested.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
