<#
.SYNOPSIS
    Reads driver versions and hardware IDs from extracted Windows INF files.
.DESCRIPTION
    Read-only report. It does not download, verify, stage, or install a driver.
    OS decorations are reported as written in the INF, not interpreted as a
    guarantee of compatibility. Inspect package signature and OEM conditions
    separately before considering installation.
.EXAMPLE
    powershell.exe -NoProfile -File .\tools\Get-InfDriverReport.ps1 -Path C:\Drivers\Extracted
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ })][string]$Path,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-InfReport([string]$InfPath) {
    $sections = @{}
    $current = ''
    $continuation = ''
    foreach ($rawLine in (Get-Content -LiteralPath $InfPath -ErrorAction Stop)) {
        # INF comments start at a semicolon outside quoted text.
        $line = [string]$rawLine
        $quoted = $false
        $token = $false
        $end = $line.Length
        for ($i = 0; $i -lt $line.Length; $i++) {
            if ($line[$i] -eq '"') { $quoted = -not $quoted }
            if ($line[$i] -eq '%' -and -not $quoted) { $token = -not $token }
            if ($line[$i] -eq ';' -and -not $quoted -and -not $token) { $end = $i; break }
        }
        $line = $line.Substring(0, $end).Trim()
        if (-not $line) { continue }
        if ($line.EndsWith('\') -and -not $quoted) {
            $continuation += $line.Substring(0, $line.Length - 1).TrimEnd() + ' '
            continue
        }
        if ($continuation) { $line = $continuation + $line; $continuation = '' }
        if ($line -match '^\[([^\]]+)\]$') {
            $current = $Matches[1].Trim()
            if (-not $sections.ContainsKey($current)) { $sections[$current] = New-Object System.Collections.ArrayList }
            continue
        }
        if ($current) { [void]$sections[$current].Add($line) }
    }
    if ($continuation) { throw "Unterminated INF line continuation: $InfPath" }
    if (-not $sections.ContainsKey('Version') -or -not $sections.ContainsKey('Manufacturer')) { return }

    $version = $null
    $driverDate = $null
    $provider = ''
    $class = ''
    foreach ($line in $sections['Version']) {
        if ($line -match '^\s*DriverVer\s*=\s*([^,]+)\s*,\s*([0-9]+(?:\.[0-9]+){1,3})\s*$') {
            $driverDate = $Matches[1].Trim(); $version = $Matches[2]
        } elseif ($line -match '^\s*Provider\s*=\s*(.+)$') { $provider = $Matches[1].Trim() }
        elseif ($line -match '^\s*Class\s*=\s*(.+)$') { $class = $Matches[1].Trim() }
    }
    if (-not $version) { return }

    $strings = @{}
    if ($sections.ContainsKey('Strings')) {
        foreach ($line in $sections['Strings']) {
            if ($line -match '^\s*([^=]+?)\s*=\s*"?(.*?)"?\s*$') {
                # INF strings may concatenate quoted fragments, e.g. "Graphics" "530".
                $strings[$Matches[1].Trim()] = ($Matches[2].Trim('"') -replace '"\s+"', ' ')
            }
        }
    }
    $modelSections = New-Object System.Collections.ArrayList
    foreach ($line in $sections['Manufacturer']) {
        if ($line -notmatch '^\s*[^=]+\s*=\s*(.+)$') { continue }
        $parts = @($Matches[1].Split(',') | ForEach-Object { $_.Trim().Trim('"') })
        if (-not $parts[0]) { continue }
        # [Manufacturer] can list one or more TargetOSVersion decorations.
        if ($parts.Count -eq 1 -and $sections.ContainsKey($parts[0])) { [void]$modelSections.Add($parts[0]) }
        for ($i = 1; $i -lt $parts.Count; $i++) {
            $name = "$($parts[0]).$($parts[$i])"
            if ($sections.ContainsKey($name)) { [void]$modelSections.Add($name) }
        }
    }
    $seen = @{}
    foreach ($section in $modelSections) {
        foreach ($line in $sections[$section]) {
            if ($line -notmatch '^\s*([^=]+?)\s*=\s*([^,]+)\s*,\s*(.+)$') { continue }
            $description = $Matches[1].Trim()
            $installSection = $Matches[2].Trim()
            $ids = $Matches[3]
            if ($description -match '^%([^%]+)%$' -and $strings.ContainsKey($Matches[1])) { $description = $strings[$Matches[1]] }
            foreach ($id in ($ids.Split(',') | ForEach-Object { $_.Trim().Trim('"') })) {
                if ($id -notmatch '^(?i:(PCI\\VEN_|USB\\VID_))[A-Z0-9_&]+$') { continue }
                $key = "$section|$installSection|$description|$id"
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [PSCustomObject]@{
                    InfFile = $InfPath
                    Class = $class
                    Provider = if ($provider -match '^%([^%]+)%$' -and $strings.ContainsKey($Matches[1])) { $strings[$Matches[1]] } else { $provider }
                    DriverDate = $driverDate
                    DriverVersion = $version
                    ModelSection = $section
                    DeviceName = $description
                    HardwareId = $id
                    InstallSection = $installSection
                }
            }
        }
    }
}

$item = Get-Item -LiteralPath $Path -ErrorAction Stop
$files = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $item.FullName -Filter '*.inf' -File -Recurse) } elseif ($item.Extension -ieq '.inf') { @($item) } else { throw 'Expected an INF file or a directory containing INF files.' }
if (-not $files.Count) { throw 'No INF files found.' }
$report = @($files | ForEach-Object { Get-InfReport $_.FullName })
if ($OutputPath) {
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "JSON report: $OutputPath"
} else {
    $report | Format-Table InfFile, Class, DriverVersion, DriverDate, ModelSection, HardwareId -Wrap -AutoSize
}
Write-Host "INF files: $($files.Count); matching model IDs: $($report.Count). No driver was installed."
