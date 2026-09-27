<#
.SYNOPSIS
    Downloads the pinned Intel Wi-Fi IT ZIP with consent and audits it read-only.
.DESCRIPTION
    Fetches directly from Intel's download mirror, checks Intel's published
    SHA-256, invokes the local AX201 candidate checker, and deletes the ZIP.
    Never stages or installs a driver.
#>
param([ValidateSet('ru', 'en')][string]$Language = 'ru')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$metadataPath = Join-Path $root 'data\intel-wifi-it-24.70.0.json'
$data = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$url = 'https://downloadmirror.intel.com/926940/WiFi-24.70.0-Driver64-Win10-Win11.zip'
$hash = 'E74843C855580659559A6D9DB55E1864121E756026F9B543FB8A792DA2EB92A9'
if ($data.downloadUrl -ne $url -or $data.sha256 -ne $hash -or
    $data.fileName -ne 'WiFi-24.70.0-Driver64-Win10-Win11.zip') {
    throw 'The reviewed Intel URL, file name or SHA-256 was changed.'
}
$question = if ($Language -eq 'ru') {
    'Скачать около 50 МБ с downloadmirror.intel.com для проверки AX201 без установки? (Y/N)'
} else {
    'Download about 50 MB from downloadmirror.intel.com to check AX201 without installation? (Y/N)'
}
if ((Read-Host $question) -notmatch '^[Yy]$') {
    Write-Host $(if ($Language -eq 'ru') { 'Загрузка отменена.' } else { 'Download cancelled.' })
    return
}
$checker = Join-Path $PSScriptRoot 'Test-OfficialWifiCandidate.ps1'
if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) { throw "Missing local checker: $checker" }
$workBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Work'
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$work = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    $package = Join-Path $work $data.fileName
    Write-Host $(if ($Language -eq 'ru') { 'Загружаю ZIP Intel во временную папку; после проверки он будет удалён.' } else { 'Downloading Intel ZIP to a temporary folder; it will be deleted after the check.' })
    Invoke-WebRequest -Uri $url -OutFile $package -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ine $hash) {
        throw 'Downloaded ZIP SHA-256 differs from the value published by Intel.'
    }
    & $checker -PackageFile $package -Language $Language
    Write-Host $(if ($Language -eq 'ru') { 'Файл ZIP удаляется; журнал проверки сохранён.' } else { 'The ZIP is being removed; the session log remains.' })
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
