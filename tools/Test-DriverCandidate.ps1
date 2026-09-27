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
    [ValidateSet('ru', 'en')][string]$Language = 'ru'
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
$verdict = 'MANUAL_REVIEW'
if ($comparison.Assessment -eq 'NO_ID_MATCH' -or $comparison.Assessment -eq 'OLDER_CANDIDATE' -or
    $package.Status -eq 'FAIL' -or ($comparison.CandidateInfPath -and -not $reportInfMatches)) {
    $verdict = 'REJECT'
} elseif ($comparison.Assessment -eq 'SAME_VERSION') {
    $verdict = 'NO_NEWER_VERSION'
} elseif ($comparison.Assessment -eq 'NEWER_CANDIDATE' -and $reportInfMatches -and
    $comparison.CandidateMatch -eq 'Exact' -and $package.Status -eq 'LOCAL_CHECKS_PASSED') {
    # Even all local checks cannot establish full driver package completeness,
    # Windows PnP ranking, OEM restrictions, or current online availability.
    $verdict = 'CANDIDATE_FOR_REVIEW'
}
if ($Language -eq 'ru') {
    Write-Host "Устройство: $HardwareId"
    Write-Host "Версии INF: установлена $($comparison.InstalledVersion); кандидат $($comparison.CandidateVersion)."
    Write-Host "Совпадение ID: $($comparison.CandidateMatch); секция Windows: $($comparison.CandidateOsSection)."
    Write-Host "Хеш пакета: $($package.HashCheck); INF в ZIP: $($package.ArchiveInfLink); подпись CAT: $($package.CatalogSignature); связь INF с CAT: $($package.InfCatalogMembership)."
    Write-Host "INF отчёта соответствует проверенному файлу: $reportInfMatches."
    Write-Host "Вывод: $verdict. Это локальная предварительная проверка. Драйвер не скачивался и не устанавливался."
} else {
    Write-Host "Device: $HardwareId"
    Write-Host "INF versions: installed $($comparison.InstalledVersion); candidate $($comparison.CandidateVersion)."
    Write-Host "ID match: $($comparison.CandidateMatch); Windows section: $($comparison.CandidateOsSection)."
    Write-Host "Package hash: $($package.HashCheck); INF in ZIP: $($package.ArchiveInfLink); CAT signature: $($package.CatalogSignature); INF/CAT membership: $($package.InfCatalogMembership)."
    Write-Host "Report INF matches the audited file: $reportInfMatches."
    Write-Host "Result: $verdict. This is a preliminary local check. No driver was downloaded or installed."
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
    PackageStatus = $package.Status
    HashCheck = $package.HashCheck
    ArchiveInfLink = $package.ArchiveInfLink
    CatalogSignature = $package.CatalogSignature
    InfCatalogMembership = $package.InfCatalogMembership
    Note = 'CANDIDATE_FOR_REVIEW does not authorize installation; source freshness, full package and Windows/OEM policy remain unverified.'
}
