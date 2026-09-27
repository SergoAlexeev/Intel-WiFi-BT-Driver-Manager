<#
.SYNOPSIS
    Connects one INF compatibility comparison with a local package audit.
.DESCRIPTION
    Read-only. CANDIDATE_FOR_REVIEW is not permission to install.
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$InstalledReport,
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$CandidateReport,
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$CandidateInf,
    [Parameter(Mandatory = $true)][string]$HardwareId,
    [ValidateSet('amd64', 'x86', 'arm64')][string]$Architecture,
    [ValidateRange(0, 999999)][int]$OsBuild,
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackageFile,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [ValidatePattern('^[A-Fa-f0-9]{128}$')][string]$ExpectedSha512,
    [string]$ArchiveEntry,
    [ValidatePattern('^https://')][string]$SourceUrl,
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SignToolPath,
    [ValidateSet('ru', 'en')][string]$Language = 'ru',
    [switch]$VerifyInstalledDevice
)
$ErrorActionPreference = 'Stop'
$toolFolder = Split-Path $MyInvocation.MyCommand.Path -Parent
$compare = Join-Path $toolFolder 'Compare-InfDriverReports.ps1'
$audit = Join-Path $toolFolder 'Test-DriverPackage.ps1'
$comparisonParams = @{
    InstalledReport = $InstalledReport
    CandidateReport = $CandidateReport
    HardwareId = $HardwareId
    PassThru = $true
}
if ($Architecture) { $comparisonParams.Architecture = $Architecture }
if ($OsBuild) { $comparisonParams.OsBuild = $OsBuild }
$generator = Join-Path $toolFolder 'Get-InfDriverReport.ps1'
$workBase = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'IntelWiFiBTManager', 'Work')
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$workPath = [IO.Path]::Combine($workBase, [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workPath) | Out-Null
$reportMatchesInf = $false
try {
    $generatedReport = Join-Path $workPath 'candidate.json'
    & $generator -Path $CandidateInf -OutputPath $generatedReport
    # The caller's JSON is advisory: compare all relevant model rows to freshly
    # parsed bytes of the INF, not just the InfFile field in one selected row.
    $suppliedRows = @(Get-Content -LiteralPath $CandidateReport -Raw | ConvertFrom-Json)
    $actualRows = @(Get-Content -LiteralPath $generatedReport -Raw | ConvertFrom-Json)
    $fields = @('HardwareId', 'DriverVersion', 'DriverDate', 'ModelSection', 'InstallSection', 'DeviceName', 'Provider', 'Class')
    $suppliedKeys = @($suppliedRows | ForEach-Object {
        $row = $_
        (@($fields | ForEach-Object { $field = $_; $field + '=' + [string]$row.$field }) -join [char]31)
    } | Sort-Object)
    $actualKeys = @($actualRows | ForEach-Object {
        $row = $_
        (@($fields | ForEach-Object { $field = $_; $field + '=' + [string]$row.$field }) -join [char]31)
    } | Sort-Object)
    $reportMatchesInf = ($suppliedKeys.Count -gt 0 -and $suppliedKeys.Count -eq $actualKeys.Count -and
        (($suppliedKeys -join [char]30) -ceq ($actualKeys -join [char]30)))
} finally {
    Remove-Item -LiteralPath $workPath -Recurse -Force -ErrorAction Stop
}
$comparison = & $compare @comparisonParams
$auditParams = @{ InfPath = $CandidateInf }
foreach ($key in @('PackageFile', 'ExpectedSha256', 'ExpectedSha512', 'ArchiveEntry', 'SourceUrl', 'SignToolPath')) {
    if ($PSBoundParameters.ContainsKey($key)) { $auditParams[$key] = $PSBoundParameters[$key] }
}
$package = & $audit @auditParams
$reportInfMatches = $false
if ($comparison.CandidateInfPath) {
    $expected = (Resolve-Path -LiteralPath $CandidateInf).ProviderPath
    $reported = $comparison.CandidateInfPath
    if (Test-Path -LiteralPath $reported -PathType Leaf) {
        $reportInfMatches = ((Resolve-Path -LiteralPath $reported).ProviderPath -ieq $expected)
    }
}
$deviceCheck = 'NOT_CHECKED'
if ($VerifyInstalledDevice) {
    $devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -ieq $HardwareId })
    if ($devices.Count -ne 1) {
        $deviceCheck = 'DEVICE_NOT_FOUND'
    } elseif (-not $comparison.InstalledVersion) {
        $deviceCheck = 'UNVERIFIED'
    } elseif ($devices[0].DriverVersion -eq $comparison.InstalledVersion) {
        $deviceCheck = 'PASS'
    } else {
        $deviceCheck = 'VERSION_MISMATCH'
    }
}
$verdict = 'MANUAL_REVIEW'
if ($comparison.Assessment -eq 'NO_ID_MATCH' -or $comparison.Assessment -eq 'OLDER_CANDIDATE' -or
    $package.Status -eq 'FAIL' -or -not $reportMatchesInf -or $deviceCheck -eq 'VERSION_MISMATCH' -or
    ($comparison.CandidateInfPath -and -not $reportInfMatches)) {
    $verdict = 'REJECT'
} elseif ($comparison.Assessment -eq 'SAME_VERSION') {
    $verdict = 'NO_NEWER_VERSION'
} elseif ($comparison.Assessment -eq 'NEWER_CANDIDATE' -and $reportInfMatches -and
    $comparison.CandidateMatch -eq 'Exact' -and $package.Status -eq 'LOCAL_CHECKS_PASSED' -and
    $deviceCheck -eq 'PASS') {
    # Even all local checks cannot establish full driver package completeness,
    # Windows PnP ranking, OEM restrictions, or current online availability.
    $verdict = 'CANDIDATE_FOR_REVIEW'
}
if ($Language -eq 'ru') {
    Write-Host "Устройство: $HardwareId"
    Write-Host "Версии INF: установлена $($comparison.InstalledVersion); кандидат $($comparison.CandidateVersion)."
    Write-Host "Совпадение ID: $($comparison.CandidateMatch); секция Windows: $($comparison.CandidateOsSection)."
    Write-Host "Хеш пакета: $($package.HashCheck); INF в ZIP: $($package.ArchiveInfLink); подпись CAT: $($package.CatalogSignature); связь INF с CAT: $($package.InfCatalogMembership)."
    Write-Host "Отчёт соответствует содержимому INF: $reportMatchesInf; путь INF совпадает: $reportInfMatches; установленное устройство Windows: $deviceCheck."
    Write-Host "Вывод: $verdict. Это локальная предварительная проверка. На этом этапе драйвер не загружается и не устанавливается."
} else {
    Write-Host "Device: $HardwareId"
    Write-Host "INF versions: installed $($comparison.InstalledVersion); candidate $($comparison.CandidateVersion)."
    Write-Host "ID match: $($comparison.CandidateMatch); Windows section: $($comparison.CandidateOsSection)."
    Write-Host "Package hash: $($package.HashCheck); INF in ZIP: $($package.ArchiveInfLink); CAT signature: $($package.CatalogSignature); INF/CAT membership: $($package.InfCatalogMembership)."
    Write-Host "Report matches INF contents: $reportMatchesInf; INF path matches: $reportInfMatches; Windows installed device: $deviceCheck."
    Write-Host "Result: $verdict. This is a preliminary local check. No driver is downloaded or installed at this stage."
}
[PSCustomObject]@{
    HardwareId = $HardwareId
    Verdict = $verdict
    Comparison = $comparison.Assessment
    InstalledVersion = $comparison.InstalledVersion
    CandidateVersion = $comparison.CandidateVersion
    CandidateMatch = $comparison.CandidateMatch
    CandidateOsSection = $comparison.CandidateOsSection
    ReportInfMatchesAuditedFile = $reportInfMatches
    CandidateReportMatchesInf = $reportMatchesInf
    InstalledDeviceCheck = $deviceCheck
    PackageStatus = $package.Status
    HashCheck = $package.HashCheck
    ArchiveInfLink = $package.ArchiveInfLink
    CatalogSignature = $package.CatalogSignature
    InfCatalogMembership = $package.InfCatalogMembership
    Note = 'CANDIDATE_FOR_REVIEW does not authorize installation; source freshness, full package and Windows/OEM policy remain unverified.'
}
