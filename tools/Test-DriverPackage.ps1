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
    [ValidatePattern('^[A-Fa-f0-9]{128}$')][string]$ExpectedSha512,
    [ValidatePattern('^https://')][string]$SourceUrl,
    [string]$ArchiveEntry,
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SignToolPath
)
$ErrorActionPreference = 'Stop'
if (($ExpectedSha256 -or $ExpectedSha512) -and -not $PackageFile) { throw 'Expected hash requires PackageFile.' }
if ($ExpectedSha256 -and $ExpectedSha512) { throw 'Choose one expected hash algorithm.' }
if ($ArchiveEntry -and -not $PackageFile) { throw 'ArchiveEntry requires PackageFile.' }
$inf = Get-Item -LiteralPath $InfPath
if ($inf.Extension -ine '.inf') { throw 'InfPath must point to an INF file.' }

$hash = 'UNVERIFIED'
$actualHash = $null
if ($PackageFile) {
    $algorithm = if ($ExpectedSha512) { 'SHA512' } else { 'SHA256' }
    $actualHash = (Get-FileHash -LiteralPath $PackageFile -Algorithm $algorithm).Hash
    $expectedHash = if ($ExpectedSha512) { $ExpectedSha512 } else { $ExpectedSha256 }
    if ($expectedHash) { $hash = if ($actualHash -ieq $expectedHash) { 'PASS' } else { 'FAIL' } }
}

$systemInfSignature = Get-AuthenticodeSignature -FilePath $inf.FullName
$systemInfCatalog = if ($systemInfSignature.Status -eq 'Valid' -and
    $systemInfSignature.SignatureType -eq 'Catalog') { 'PASS' } else { 'UNVERIFIED' }
$systemInfSigner = if ($systemInfCatalog -eq 'PASS' -and $systemInfSignature.SignerCertificate) {
    $systemInfSignature.SignerCertificate.Subject
} else { $null }

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
            $previousAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $null = & $SignToolPath verify /kp /c $catalogPath $inf.FullName 2>&1
                $signToolExit = $LASTEXITCODE
                $global:LASTEXITCODE = 0
            } finally { $ErrorActionPreference = $previousAction }
            $membership = if ($signToolExit -eq 0) { 'PASS' } else { 'FAIL' }
        }
    }
}
$archiveInfLink = 'UNVERIFIED'
$archiveNote = 'Archive-to-INF link was not checked.'
if ($ArchiveEntry) {
    # ZIP is the only container currently supported. An explicit entry avoids
    # guessing which INF to trust when an archive contains multiple copies.
    $archiveType = [IO.Path]::GetExtension($PackageFile).ToLowerInvariant()
    if ($archiveType -notin @('.zip', '.cab')) {
        throw 'ArchiveEntry is supported only for ZIP and CAB PackageFile.'
    }
    $entryName = $ArchiveEntry.Replace('\', '/')
    if ($entryName.StartsWith('/') -or $entryName -match '(^|/)\.\.?(/|$)' -or $entryName -match '^[A-Za-z]:') {
        throw 'ArchiveEntry must be a relative path inside the ZIP.'
    }
    if ($archiveType -eq '.cab') {
        # expand.exe extracts only the named file. A private directory prevents
        # inherited files from making a missing CAB entry appear to match.
        if ($entryName -match '/' -or $entryName -notmatch '^[A-Za-z0-9_.-]+\\.inf
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($archiveStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $entries = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -ceq $entryName })
            if ($entries.Count -ne 1) {
                $archiveInfLink = 'FAIL'
                $archiveNote = "Expected exactly one ZIP entry '$entryName'; found $($entries.Count)."
            } else {
                $entryStream = $entries[0].Open()
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try {
                    $entryHash = [BitConverter]::ToString($sha256.ComputeHash($entryStream)).Replace('-', '')
                } finally {
                    $sha256.Dispose()
                    $entryStream.Dispose()
                }
                $localHash = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256).Hash
                $archiveInfLink = if ($entryHash -ieq $localHash) { 'PASS' } else { 'FAIL' }
                $archiveNote = "ZIP entry '$entryName' SHA-256 compared with the local INF."
            }
        } finally { $zip.Dispose() }
    } catch {
        $archiveInfLink = 'FAIL'
        $archiveNote = "ZIP could not be checked: $($_.Exception.Message)"
    } finally { $archiveStream.Dispose() }
    }
}

$status = if ($archiveInfLink -eq 'FAIL' -or $hash -eq 'FAIL' -or $catalogSignature -eq 'FAIL' -or $membership -eq 'FAIL') {
    'FAIL'
} elseif ($hash -eq 'PASS' -and $catalogSignature -eq 'PASS' -and $membership -eq 'PASS' -and $archiveInfLink -eq 'PASS') {
    'LOCAL_CHECKS_PASSED'
} else { 'UNVERIFIED' }

[PSCustomObject]@{
    InfPath = $inf.FullName
    CatalogPath = $catalogPath
    CatalogCandidates = $catalogNames
    SourceUrlDeclared = $SourceUrl
    PackageHash = $actualHash
    ExpectedHash = $expectedHash
    HashAlgorithm = $algorithm
    HashCheck = $hash
    CatalogSignature = $catalogSignature
    InfCatalogMembership = $membership
    SystemInfCatalogSignature = $systemInfCatalog
    SystemInfSigner = $systemInfSigner
    ArchiveEntry = $ArchiveEntry
    ArchiveInfLink = $archiveInfLink
    Status = $status
    Note = "A declared URL is not proof of origin. A system catalog signature does not identify the exported CAT. $archiveNote Verify expected hashes from trusted release records. No driver was installed."
}
) {
            throw 'CAB ArchiveEntry must be one plain INF filename.'
        }
        $cabWork = Join-Path ([IO.Path]::GetTempPath()) ('cab-inf-check-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($cabWork) | Out-Null
        try {
            $previousAction = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $null = & expand.exe (Resolve-Path -LiteralPath $PackageFile).ProviderPath "-F:$entryName" $cabWork 2>&1
                $expandExit = $LASTEXITCODE
                $global:LASTEXITCODE = 0
            } finally { $ErrorActionPreference = $previousAction }
            $extracted = @(Get-ChildItem -LiteralPath $cabWork -Recurse -File)
            if ($expandExit -ne 0 -or $extracted.Count -ne 1 -or $extracted[0].Name -ine $entryName) {
                $archiveInfLink = 'FAIL'
                $archiveNote = "CAB entry '$entryName' could not be extracted exactly once."
            } else {
                $fromCab = (Get-FileHash -LiteralPath $extracted[0].FullName -Algorithm SHA256).Hash
                $local = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256).Hash
                $archiveInfLink = if ($fromCab -ieq $local) { 'PASS' } else { 'FAIL' }
                $archiveNote = "CAB entry '$entryName' SHA-256 compared with the local INF."
            }
        } finally {
            Remove-Item -LiteralPath $cabWork -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
    Add-Type -AssemblyName System.IO.Compression
    $archiveStream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $PackageFile).ProviderPath)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($archiveStream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $entries = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -ceq $entryName })
            if ($entries.Count -ne 1) {
                $archiveInfLink = 'FAIL'
                $archiveNote = "Expected exactly one ZIP entry '$entryName'; found $($entries.Count)."
            } else {
                $entryStream = $entries[0].Open()
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try {
                    $entryHash = [BitConverter]::ToString($sha256.ComputeHash($entryStream)).Replace('-', '')
                } finally {
                    $sha256.Dispose()
                    $entryStream.Dispose()
                }
                $localHash = (Get-FileHash -LiteralPath $inf.FullName -Algorithm SHA256).Hash
                $archiveInfLink = if ($entryHash -ieq $localHash) { 'PASS' } else { 'FAIL' }
                $archiveNote = "ZIP entry '$entryName' SHA-256 compared with the local INF."
            }
        } finally { $zip.Dispose() }
    } catch {
        $archiveInfLink = 'FAIL'
        $archiveNote = "ZIP could not be checked: $($_.Exception.Message)"
    } finally { $archiveStream.Dispose() }
}

$status = if ($archiveInfLink -eq 'FAIL' -or $hash -eq 'FAIL' -or $catalogSignature -eq 'FAIL' -or $membership -eq 'FAIL') {
    'FAIL'
} elseif ($hash -eq 'PASS' -and $catalogSignature -eq 'PASS' -and $membership -eq 'PASS' -and $archiveInfLink -eq 'PASS') {
    'LOCAL_CHECKS_PASSED'
} else { 'UNVERIFIED' }

[PSCustomObject]@{
    InfPath = $inf.FullName
    CatalogPath = $catalogPath
    CatalogCandidates = $catalogNames
    SourceUrlDeclared = $SourceUrl
    PackageHash = $actualHash
    ExpectedHash = $expectedHash
    HashAlgorithm = $algorithm
    HashCheck = $hash
    CatalogSignature = $catalogSignature
    InfCatalogMembership = $membership
    SystemInfCatalogSignature = $systemInfCatalog
    SystemInfSigner = $systemInfSigner
    ArchiveEntry = $ArchiveEntry
    ArchiveInfLink = $archiveInfLink
    Status = $status
    Note = "A declared URL is not proof of origin. A system catalog signature does not identify the exported CAT. $archiveNote Verify expected hashes from trusted release records. No driver was installed."
}
