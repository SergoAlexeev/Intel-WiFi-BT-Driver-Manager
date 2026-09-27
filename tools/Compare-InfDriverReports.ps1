<#
.SYNOPSIS
    Compare installed and candidate INF reports for one hardware ID.
.DESCRIPTION
    Read-only comparison. Does not establish package trust or final Windows
    compatibility, and does not download or install drivers.
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$InstalledReport,
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$CandidateReport,
    [Parameter(Mandatory = $true)][string]$HardwareId,
    [ValidateSet("amd64", "x86", "arm64")][string]$Architecture,
    [ValidateRange(0, 999999)][int]$OsBuild,
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'

function Get-InfIdMatch($Rows, [string]$Id) {
    # The instance suffix follows the second backslash; retain SUBSYS/MI before it.
    $parts = $Id -split '\\', 3
    if ($parts.Count -lt 2 -or $parts[0] -notin @('PCI', 'USB')) { throw 'Expected a PCI or USB hardware ID.' }
    $baseId = "$($parts[0])\$($parts[1])".ToUpperInvariant()
    $baseId = $baseId -replace '&REV_[0-9A-F]{2,4}(?=&|$)', ''
    $same = @($Rows | Where-Object {
        (([string]$_.HardwareId).ToUpperInvariant() -replace '&REV_[0-9A-F]{2,4}(?=&|$)', '') -eq $baseId
    })
    if ($same.Count) { return [PSCustomObject]@{ Rank = 'Exact'; Rows = $same } }
    if ($baseId -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') {
        $genericId = $Matches[1]
        $generic = @($Rows | Where-Object { ([string]$_.HardwareId).ToUpperInvariant() -eq $genericId })
        if ($generic.Count) { return [PSCustomObject]@{ Rank = 'Generic'; Rows = $generic } }
    }
    return [PSCustomObject]@{ Rank = 'None'; Rows = @() }
}

function Test-ModelSection([string]$Section, [string]$TargetArchitecture, [int]$TargetBuild) {
    # Conservative subset of TargetOSVersion: NT, architecture, major.minor,
    # optional ProductType/SuiteMask and BuildNumber. Unsupported fields remain unknown.
    if (-not $Section) { return 'Unknown' }
    if ($Section -notmatch '(?i)\.NT(?<arch>amd64|x86|arm64)?(?<suffix>(?:\.[0-9]*)*)$') { return 'Unknown' }
    $arch = $Matches['arch']
    $suffix = $Matches['suffix']
    if ($arch -and $TargetArchitecture -and $arch -ine $TargetArchitecture) { return 'Incompatible' }
    if ($arch -and -not $TargetArchitecture) { return 'Unknown' }
    if (-not $TargetBuild) { return 'Unknown' }
    if (-not $suffix) { return 'Compatible' }
    $numbers = @($suffix.TrimStart('.').Split('.'))
    if ($numbers.Count -lt 2 -or $numbers.Count -gt 5) { return 'Unknown' }
    if (-not $TargetBuild) { return 'Unknown' }
    if ($numbers[0] -ne '10' -or $numbers[1] -ne '0') { return 'Unknown' }
    if ($numbers.Count -ge 3 -and $numbers[2] -notin @('', '0')) { return 'Unknown' } # ProductType
    if ($numbers.Count -ge 4 -and $numbers[3] -notin @('', '0')) { return 'Unknown' } # SuiteMask
    if ($numbers.Count -eq 5) {
        if (-not $TargetBuild) { return 'Unknown' }
        if ($TargetBuild -lt [int]$numbers[4]) { return 'Incompatible' }
    }
    return 'Compatible'
}

function Collapse-EquivalentRevisionRows($Rows) {
    # An instance ID may omit REV while an INF lists several REV-specific IDs.
    # Collapse only if every candidate is the same device, version and install
    # section; conflicting rows remain ambiguous for manual review.
    $items = @($Rows)
    if ($items.Count -le 1) { return $items }
    $keys = @($items | ForEach-Object {
        $r = $_
        @([string]$r.DriverVersion, [string]$r.DriverDate, [string]$r.ModelSection,
          [string]$r.InstallSection, [string]$r.DeviceName, [string]$r.Provider,
          [string]$r.Class, [string]$r.InfFile) -join [char]31
    } | Select-Object -Unique)
    if ($keys.Count -eq 1) { return @($items[0]) }
    return $items
}

function Select-ApplicableRows($Match, [string]$TargetArchitecture, [int]$TargetBuild) {
    $compatible = @(Collapse-EquivalentRevisionRows @($Match.Rows | Where-Object { (Test-ModelSection ([string]$_.ModelSection) $TargetArchitecture $TargetBuild) -eq 'Compatible' }))
    $unknown = @(Collapse-EquivalentRevisionRows @($Match.Rows | Where-Object { (Test-ModelSection ([string]$_.ModelSection) $TargetArchitecture $TargetBuild) -eq 'Unknown' }))
    # Do not silently discard an unknown row: it may be a better Windows match.
    if ($unknown.Count) { return [PSCustomObject]@{ Status = 'Unknown'; Rows = @($compatible + $unknown) } }
    if ($compatible.Count) { return [PSCustomObject]@{ Status = 'Compatible'; Rows = $compatible } }
    return [PSCustomObject]@{ Status = 'Incompatible'; Rows = @() }
}

$installed = @(Get-Content -LiteralPath $InstalledReport -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$candidate = @(Get-Content -LiteralPath $CandidateReport -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$old = Get-InfIdMatch $installed $HardwareId
$new = Get-InfIdMatch $candidate $HardwareId
$oldApplicable = Select-ApplicableRows $old $Architecture $OsBuild
$newApplicable = Select-ApplicableRows $new $Architecture $OsBuild
Write-Host "Requested hardware ID: $HardwareId"
Write-Host "Target: architecture $Architecture; Windows build $OsBuild (supply -Architecture and -OsBuild for decorated sections)."
foreach ($pair in @(@('Installed', $old), @('Candidate', $new))) {
    $match = $pair[1]
    Write-Host "$($pair[0]): match $($match.Rank); rows $(@($match.Rows).Count)"
    $match.Rows | Select-Object DeviceName, HardwareId, DriverVersion, DriverDate, ModelSection, InfFile | Format-List
}
$assessment = 'MANUAL_REVIEW'
$reason = ''
$installedVersion = $null
$candidateVersion = $null
$candidateInf = $null
if ($new.Rank -eq 'None') {
    $assessment = 'NO_ID_MATCH'
    $reason = 'No matching candidate INF ID. Do not use this report to propose an update.'
} elseif ($old.Rank -eq 'None') {
    $reason = 'Installed INF ID was not found in the report. Verify the input files and device ID.'
} elseif ($oldApplicable.Status -ne 'Compatible' -or $newApplicable.Status -ne 'Compatible') {
    $reason = "OS section assessment: installed $($oldApplicable.Status); candidate $($newApplicable.Status). No update recommendation; supply architecture/build or inspect the INF manually."
} elseif (@($oldApplicable.Rows).Count -ne 1 -or @($newApplicable.Rows).Count -ne 1) {
    $reason = 'Multiple matching rows: inspect the INF manually before comparing versions.'
} else {
    $candidateInf = [string]$newApplicable.Rows[0].InfFile
    try {
        $a = [version]$oldApplicable.Rows[0].DriverVersion
        $b = [version]$newApplicable.Rows[0].DriverVersion
        $installedVersion = [string]$a
        $candidateVersion = [string]$b
        if ($b -gt $a) {
            $assessment = 'NEWER_CANDIDATE'
            $reason = "Candidate INF version $b is newer than installed INF version $a."
        } elseif ($b -eq $a) {
            $assessment = 'SAME_VERSION'
            $reason = "INF versions match: $a."
        } else {
            $assessment = 'OLDER_CANDIDATE'
            $reason = "Candidate INF version $b is older than installed INF version $a. Do not downgrade."
        }
    } catch { $reason = 'DriverVer could not be compared; inspect both INF files manually.' }
}
Write-Host $reason
if ($PassThru) {
    [PSCustomObject]@{
        HardwareId = $HardwareId
        Assessment = $assessment
        Reason = $reason
        InstalledVersion = $installedVersion
        CandidateVersion = $candidateVersion
        CandidateInfPath = $candidateInf
        CandidateMatch = $new.Rank
        CandidateOsSection = $newApplicable.Status
        CandidateRows = @($newApplicable.Rows).Count
    }
}
Write-Host 'This is an INF comparison only. Package origin, hash, signature, full OS support, OEM policy, and Windows driver ranking are not verified. No driver was installed.'
