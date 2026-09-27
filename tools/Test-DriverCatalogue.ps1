<#
.SYNOPSIS
    Validates the reviewed, read-only Intel driver candidate catalogue.
.DESCRIPTION
    Checks structure, dates, URLs and hashes. It does not verify that Intel still
    serves the same package, and it does not download, stage or install drivers.
#>
param(
    [string]$Path = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data\driver-packages.json')
)
$ErrorActionPreference = 'Stop'
$data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json
if ($data.schemaVersion -ne 1) { throw 'Unsupported catalogue schema version.' }
$items = @($data.packages | Where-Object { $null -ne $_ })
if (-not $items.Count) { throw 'The catalogue contains no packages.' }
$ids = @{}
foreach ($item in $items) {
    foreach ($field in @('id', 'deviceClass', 'version', 'family', 'sourcePage', 'downloadUrl', 'fileName', 'sha512', 'expectedSigner', 'reviewedOn', 'installMode')) {
        if ([string]::IsNullOrWhiteSpace([string]$item.$field)) { throw "Missing $field in catalogue entry." }
    }
    if ($item.id -notmatch '^[a-z0-9][a-z0-9.-]+$') { throw "Invalid package ID: $($item.id)" }
    if ($ids.ContainsKey($item.id)) { throw "Duplicate package ID: $($item.id)" }
    $ids[$item.id] = $true
    if ($item.deviceClass -ne 'DISPLAY' -or $item.installMode -ne 'graphics-preview') {
        throw "Unsupported candidate type: $($item.id)"
    }
    try { $null = [version]$item.version } catch { throw "Invalid driver version: $($item.id)" }
    if ($item.sha512 -notmatch '^[0-9A-Fa-f]{128}$') { throw "Invalid SHA-512: $($item.id)" }
    if ($item.fileName -notmatch '^[^\\/:*?"<>|]+\.exe$') { throw "Invalid file name: $($item.id)" }
    $date = [datetime]::MinValue
    $style = [Globalization.DateTimeStyles]::None
    if (-not [datetime]::TryParseExact($item.reviewedOn, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$date) -or
        $date.Date -gt [datetime]::UtcNow.Date) { throw "Invalid review date: $($item.id)" }
    foreach ($field in @('sourcePage', 'downloadUrl')) {
        $uri = $null
        if (-not [uri]::TryCreate([string]$item.$field, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -ne 'https' -or
            ($uri.Host -ne 'intel.com' -and -not $uri.Host.EndsWith('.intel.com', [StringComparison]::OrdinalIgnoreCase)) -or
            $uri.UserInfo) { throw "Unexpected source URL in $($item.id): $field" }
    }
    if (([uri]$item.downloadUrl).Segments[-1] -cne $item.fileName) { throw "Download filename mismatch: $($item.id)" }
}
[PSCustomObject]@{ Status = 'VALID_STRUCTURE'; PackageCount = $items.Count; Note = 'Catalogue metadata only. Online availability, signature, package-to-INF link and device compatibility are not verified.' }
