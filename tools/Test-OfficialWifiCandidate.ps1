<#
.SYNOPSIS
    Read-only audit of Intel's official Wi-Fi 24.70.0 IT ZIP for AX201.
.DESCRIPTION
    Requires a locally obtained ZIP. Its SHA-256 is checked against Intel's
    published value before reading any INF. Does not download or install.
#>
param(
    [Parameter(Mandatory = $true)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackageFile,
    [ValidateSet('ru', 'en')][string]$Language = 'ru'
)
$ErrorActionPreference = 'Stop'
function Get-ExactWifiInfRows([string]$ReportPath, [string]$BaseId) {
    $json = Get-Content -LiteralPath $ReportPath -Raw
    if ([string]::IsNullOrWhiteSpace($json)) { return }
    # Windows PowerShell 5.1 may pass the JSON array as one pipeline item.
    # Explicitly enumerate it before comparing each HardwareId.
    $allRows = @($json | ConvertFrom-Json | ForEach-Object { $_ })
    $allRows | Where-Object { [string]$_.HardwareId -ieq $BaseId }
}

function Say([string]$Ru, [string]$En) { if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En } }
$root = Split-Path $PSScriptRoot -Parent
$metadataPath = Join-Path $root 'data\intel-wifi-it-24.70.0.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json
$publishedHash = 'E74843C855580659559A6D9DB55E1864121E756026F9B543FB8A792DA2EB92A9'
if ($metadata.sha256 -ne $publishedHash -or $metadata.driverVersion -ne '24.70.0.3' -or
    $metadata.deviceIdPrefix -ne 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086' -or
    $metadata.sourcePage -ne 'https://www.intel.com/content/www/us/en/download/18231/intel-proset-wireless-software-and-wi-fi-drivers-for-it-administrators.html' -or
    $metadata.downloadUrl -ne 'https://downloadmirror.intel.com/926940/WiFi-24.70.0-Driver64-Win10-Win11.zip') {
    throw 'Pinned Intel ZIP metadata differs from the reviewed package.'
}
Say 'Этап 1/4. Сверяю SHA-256 ZIP с хешем на странице Intel.' 'Step 1/4. Comparing ZIP SHA-256 with the hash on the Intel page.'
$actualHash = (Get-FileHash -LiteralPath $PackageFile -Algorithm SHA256).Hash
if ($actualHash -ine $publishedHash) { throw 'Intel ZIP SHA-256 mismatch. No archive content was used.' }
$devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceClass -eq 'NET' -and $_.DeviceID -like "$($metadata.deviceIdPrefix)*"
})
if ($devices.Count -ne 1) { throw 'Expected exactly one installed Intel AX201 with the reviewed DEV and SUBSYS.' }
$device = $devices[0]
if ($device.InfName -notmatch '(?i)^oem[0-9]+\.inf$') { throw 'The installed device has no expected Windows OEM INF.' }
$installedInf = Join-Path (Join-Path $env:windir 'INF') $device.InfName
if (-not (Test-Path -LiteralPath $installedInf -PathType Leaf)) { throw 'The installed Windows INF is unavailable.' }
$manager = Join-Path $root 'IntelWiFiBTManager.ps1'
$generator = Join-Path $root 'tools\Get-InfDriverReport.ps1'
foreach ($required in @($manager, $generator, (Join-Path $root 'tools\Test-DriverCandidate.ps1'),
        (Join-Path $root 'tools\Compare-InfDriverReports.ps1'), (Join-Path $root 'tools\Test-DriverPackage.ps1'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing program file: $required" }
}
$workBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Work'
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$work = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression
    $source = [IO.File]::OpenRead((Resolve-Path -LiteralPath $PackageFile).ProviderPath)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($source, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            Say 'Этап 2/4. Ищу в проверенном ZIP INF для точного ID устройства.' 'Step 2/4. Finding the exact device ID in the verified ZIP INF files.'
            $selected = @()
            $index = 0
            $baseId = $metadata.deviceIdPrefix
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -notmatch '(?i)\.inf$') { continue }
                if ($entry.Length -gt 16777216) { throw 'Unexpectedly large INF in Intel ZIP.' }
                $folder = Join-Path $work ([string]$index)
                $index++
                [IO.Directory]::CreateDirectory($folder) | Out-Null
                $target = Join-Path $folder ([IO.Path]::GetFileName($entry.FullName.Replace('\', '/')))
                $stream = $entry.Open()
                $output = [IO.File]::Create($target)
                try { $stream.CopyTo($output) } finally { $output.Dispose(); $stream.Dispose() }
                $report = Join-Path $folder 'models.json'
                & $generator -Path $target -OutputPath $report
                $rows = @(Get-ExactWifiInfRows $report $baseId)
                if ($rows.Count) {
                    $selected += [PSCustomObject]@{ Entry = $entry.FullName; InfPath = $target; Report = $report; Rows = $rows.Count }
                }
            }
            if ($selected.Count -ne 1) {
                throw "Expected one INF with exact AX201 DEV/SUBSYS; found $($selected.Count). Inspect package manually."
            }
            $candidate = $selected[0]
            # The INF's declared CAT is copied only when the exact sibling ZIP
            # entry exists; no catalog is inferred from a different directory.
            $catalogNames = @()
            $inVersion = $false
            foreach ($raw in (Get-Content -LiteralPath $candidate.InfPath)) {
                $line = ([string]$raw -split ';', 2)[0].Trim()
                if ($line -match '^\[([^\]]+)\]$') { $inVersion = ($Matches[1] -ieq 'Version'); continue }
                if ($inVersion -and $line -match '^CatalogFile(?:\.[A-Za-z0-9.]+)?\s*=\s*"?([^";]+?)"?\s*$') {
                    $catalogNames += $Matches[1].Trim()
                }
            }
            $catalogNames = @($catalogNames | Select-Object -Unique)
            if ($catalogNames.Count -eq 1 -and $catalogNames[0] -match '^[^\\/:*?"<>|]+\.cat$') {
                $normalized = $candidate.Entry.Replace('\', '/')
                $parent = [IO.Path]::GetDirectoryName($normalized).Replace('\', '/').TrimEnd('/')
                $expectedEntry = if ($parent) { "$parent/$($catalogNames[0])" } else { $catalogNames[0] }
                $cats = @($zip.Entries | Where-Object { $_.FullName.Replace('\', '/') -ieq $expectedEntry })
                if ($cats.Count -eq 1) {
                    $catStream = $cats[0].Open()
                    $catFile = [IO.File]::Create((Join-Path (Split-Path $candidate.InfPath -Parent) $catalogNames[0]))
                    try { $catStream.CopyTo($catFile) } finally { $catFile.Dispose(); $catStream.Dispose() }
                }
            }
        } finally { $zip.Dispose() }
    } finally { $source.Dispose() }
    Say "Этап 3/4. Совпадение найдено: $($candidate.Entry). Сравниваю с установленным INF." "Step 3/4. Matched $($candidate.Entry). Comparing with the installed INF."
    $installedReport = Join-Path $work 'installed.json'
    & $generator -Path $installedInf -OutputPath $installedReport
    $manifest = Join-Path $work 'manifest.json'
    [PSCustomObject]@{
        entries = @([PSCustomObject]@{
            deviceId = $device.DeviceID
            installedReport = $installedReport
            candidateReport = $candidate.Report
            candidateInf = $candidate.InfPath
            packageFile = (Resolve-Path -LiteralPath $PackageFile).ProviderPath
            expectedSha256 = $publishedHash
            archiveEntry = $candidate.Entry
            sourceUrl = $metadata.sourcePage
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding UTF8
    Say 'Этап 4/4. Запускаю менеджер только в режиме чтения. Временные файлы будут удалены, журнал сохранится.' 'Step 4/4. Running the manager in read-only mode. Temporary files will be removed; the log remains.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -CheckUpdates -CandidateManifest $manifest -Language $Language
    if ($LASTEXITCODE -ne 0) { throw "Manager returned exit code $LASTEXITCODE." }
    Say 'Проверка официального ZIP завершена. Этот запуск ничего не устанавливал.' 'Official ZIP check complete. Nothing was installed.'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
