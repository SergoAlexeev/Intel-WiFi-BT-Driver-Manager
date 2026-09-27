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
    [Parameter(Mandatory = $true)][string]$HardwareId
)
$ErrorActionPreference = 'Stop'

function Get-InfIdMatch($Rows, [string]$Id) {
    # Ignore instance suffix and revision when comparing the INF's PCI/USB IDs.
    $normalized = ($Id -split '\\', 3)
    if ($normalized.Count -lt 2) { throw 'Expected a PCI or USB hardware ID.' }
    $baseId = "$($normalized[0])\$($normalized[1])".ToUpperInvariant()
    $baseId = $baseId -replace '&REV_[0-9A-F]{2,4}(?=&|$)', ''
    $exact = @($Rows | Where-Object {
        $candidateId = ([string]$_.HardwareId).ToUpperInvariant() -replace '&REV_[0-9A-F]{2,4}(?=&|$)', ''
        $candidateId -eq $baseId
    })
    if ($exact.Count) { return [PSCustomObject]@{ Rank = 'Exact'; Rows = $exact } }
    if ($baseId -match '^(PCI\\VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}|USB\\VID_[0-9A-F]{4}&PID_[0-9A-F]{4})') {
        $genericId = $Matches[1]
        $generic = @($Rows | Where-Object { ([string]$_.HardwareId).ToUpperInvariant() -eq $genericId })
        if ($generic.Count) { return [PSCustomObject]@{ Rank = 'Generic'; Rows = $generic } }
    }
    return [PSCustomObject]@{ Rank = 'None'; Rows = @() }
}

$installed = @(Get-Content -LiteralPath $InstalledReport -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$candidate = @(Get-Content -LiteralPath $CandidateReport -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$old = Get-InfIdMatch $installed $HardwareId
$new = Get-InfIdMatch $candidate $HardwareId
Write-Host "Requested hardware ID: $HardwareId"
foreach ($pair in @(@('Installed', $old), @('Candidate', $new))) {
    $match = $pair[1]
    Write-Host "$($pair[0]): match $($match.Rank); rows $(@($match.Rows).Count)"
    $match.Rows | Select-Object DeviceName, HardwareId, DriverVersion, DriverDate, ModelSection, InfFile | Format-List
}
if ($new.Rank -eq 'None') {
    Write-Host 'No matching candidate INF ID. Do not use this report to propose an update.'
} elseif ($old.Rank -eq 'None') {
    Write-Host 'Installed INF ID was not found in the report. Verify the input files and device ID.'
} elseif (@($old.Rows).Count -ne 1 -or @($new.Rows).Count -ne 1) {
    Write-Host 'Multiple matching rows: inspect the INF manually before comparing versions.'
} else {
    try {
        $a = [version]$old.Rows[0].DriverVersion
        $b = [version]$new.Rows[0].DriverVersion
        if ($b -gt $a) { Write-Host "Candidate INF version $b is newer than installed INF version $a." }
        elseif ($b -eq $a) { Write-Host "INF versions match: $a." }
        else { Write-Host "Candidate INF version $b is older than installed INF version $a. Do not downgrade." }
    } catch { Write-Host 'DriverVer could not be compared; inspect both INF files manually.' }
}
Write-Host 'This is an INF comparison only. Package origin, hash, signature, OS support, OEM policy, and Windows driver ranking are not verified. No driver was installed.'
