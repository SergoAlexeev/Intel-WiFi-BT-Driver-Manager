<#
.SYNOPSIS
    Audits a local driver INF and optional downloaded archive without installation.
.DESCRIPTION
    Read-only. SourceUrl is caller-provided provenance, not proof of download origin.
    A Valid catalog signature alone does not prove the INF belongs to that catalog.
    SignTool from the Windows SDK verifies catalog membership under kernel signing policy.
.EXAMPLE
    .\tools\Test-DriverPackage.ps1 -InfPath C:\Drivers\netwtw08.inf -SignToolPath C:\SDK\signtool.exe
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$InfPath,
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackageFile,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [ValidatePattern('^https://')][string]$SourceUrl,
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SignToolPath
)
$ErrorActionPreference = 'Stop'
if ($ExpectedSha256 -and -not $PackageFile) { throw 'ExpectedSha256 requires PackageFile.' }
$inf = Get-Item -LiteralPath $InfPath
if ($inf.Extension -ine '.inf') { throw 'InfPath must point to an INF file.' }

$hash = 'UNVERIFIED'
$actualHash = $null
if ($PackageFile) {
    $actualHash = (Get-FileHash -LiteralPath $PackageFile -Algorithm SHA256).Hash
    if ($ExpectedSha256) {
        $hash = if ($actualHash -ieq $ExpectedSha256) { 'PASS' } else { 'FAIL' }
    }
}

$catalogNames = @()
$inVersion = $false
foreach ($raw in (Get-Content -LiteralPath $inf.FullName -ErrorAction Stop)) {
    $line = ([string]$raw -split ';', 2)[0].Trim()
    if ($line -match '^\[([^\]]+)\]$') { $inVersion = ($Matches[1] -ieq 'Version'); continue }
    if ($inVersion -and $line -match '^CatalogFile(?:\.[A-Za-z0-9.]+)?\s*=\s*"?([^";]+?)"?\s*$') {
        $catalogNames += $Matches[1].Trim()
    }
}
$catalogNames = @($catalogNames | Select-Object -Unique)
$catalogSignature = 'UNVERIFIED'
$membership = 'UNVERIFIED'
$catalogPath = $null
if ($catalogNames.Count -eq 1 -and $catalogNames[0] -match '^[^\\/:*?"<>|]+\.cat$') {
    $catalogPath = Join-Path $inf.DirectoryName $catalogNames[0]
    if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
        $signature = Get-AuthenticodeSignature -FilePath $catalogPath
        $catalogSignature = if ($signature.Status -eq 'Valid') { 'PASS' } else { 'FAIL' }
        if (-not $SignToolPath) {
            $tool = Get-Command signtool.exe -ErrorAction SilentlyContinue
            if ($tool) { $SignToolPath = $tool.Source }
        }
        if ($SignToolPath) {
            # /kp applies kernel-mode policy; /c checks this INF against this CAT.
            $null = & $SignToolPath verify /kp /c $catalogPath $inf.FullName 2>&1
            $membership = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
        }
    }
}
$status = if ($hash -eq 'FAIL' -or $catalogSignature -eq 'FAIL' -or $membership -eq 'FAIL') {
    'FAIL'
} elseif ($hash -eq 'PASS' -and $catalogSignature -eq 'PASS' -and $membership -eq 'PASS') {
    'VERIFIED_LOCAL_PACKAGE'
} else { 'UNVERIFIED' }

[PSCustomObject]@{
    InfPath = $inf.FullName
    CatalogPath = $catalogPath
    CatalogCandidates = $catalogNames
    SourceUrlDeclared = $SourceUrl
    PackageSha256 = $actualHash
    ExpectedSha256 = $ExpectedSha256
    HashCheck = $hash
    CatalogSignature = $catalogSignature
    InfCatalogMembership = $membership
    Status = $status
    Note = 'A declared URL is not proof of origin. Verify the expected hash from a trusted release record. No driver was installed.'
}
