<#
.SYNOPSIS
    Read-only rehearsal on one installed Intel device. No driver download or install.
.DESCRIPTION
    Copies an already installed Windows INF into a temporary ZIP, creates
    two reports and a one-entry local candidate manifest, then runs
    IntelWiFiBTManager -CheckUpdates. The ZIP hash is calculated locally:
    it is deliberately NOT an official package or proof of provenance.
#>
param(
    [ValidateSet('ru', 'en')][string]$Language = 'ru'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$manager = Join-Path $repo 'IntelWiFiBTManager.ps1'
$generator = Join-Path $repo 'tools\Get-InfDriverReport.ps1'
foreach ($file in @($manager, $generator)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing required file: $file" }
}
$device = Get-CimInstance Win32_PnPSignedDriver |
    Where-Object {
        $_.DeviceClass -in @('NET', 'DISPLAY', 'Bluetooth') -and
        $_.DeviceID -match '(?i)^(PCI\\VEN_8086|USB\\VID_8087)&' -and
        $_.InfName -match '(?i)^oem[0-9]+\.inf$'
    } |
    Sort-Object @{ Expression = { if ($_.DeviceClass -eq 'NET') { 0 } elseif ($_.DeviceClass -eq 'DISPLAY') { 1 } else { 2 } } } |
    Select-Object -First 1
if (-not $device) { throw 'No installed Intel network, graphics or Bluetooth device with an OEM INF was found.' }
$installedInf = Join-Path (Join-Path $env:windir 'INF') $device.InfName
if (-not (Test-Path -LiteralPath $installedInf -PathType Leaf)) { throw "Installed INF is missing: $installedInf" }
$workBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Work'
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$work = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    $source = Join-Path $work 'source'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    $candidateInf = Join-Path $source $device.InfName
    Copy-Item -LiteralPath $installedInf -Destination $candidateInf -ErrorAction Stop
    $installedReport = Join-Path $work 'installed.json'
    $candidateReport = Join-Path $work 'candidate.json'
    & $generator -Path $installedInf -OutputPath $installedReport
    & $generator -Path $candidateInf -OutputPath $candidateReport
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $package = Join-Path $work 'local-rehearsal.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($source, $package)
    $manifest = Join-Path $work 'manifest.json'
    [PSCustomObject]@{
        entries = @([PSCustomObject]@{
            deviceId = $device.DeviceID
            installedReport = $installedReport
            candidateReport = $candidateReport
            candidateInf = $candidateInf
            packageFile = $package
            expectedSha256 = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
            archiveEntry = $device.InfName
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding UTF8
    Write-Host "Selected device: $($device.DeviceName); installed version: $($device.DriverVersion); INF: $($device.InfName)."
    Write-Host 'This ZIP was made locally from the installed INF. Its hash does not prove an Intel release.'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -CheckUpdates -CandidateManifest $manifest -Language $Language 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Write-Host $output
    if ($exitCode -ne 0) { throw "Read-only manager check failed with code $exitCode." }
    if ($output -notmatch 'NO_NEWER_VERSION' -or $output -notmatch 'INF (?:в ZIP|in ZIP): PASS' -or
        $output -notmatch '(?:установленное устройство Windows|Windows installed device): PASS') {
        throw 'Expected same-version, archive-link and installed-device checks were not all observed. Inspect the manager log.'
    }
    Write-Host 'Real-device read-only rehearsal passed. No driver was downloaded or installed.'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
