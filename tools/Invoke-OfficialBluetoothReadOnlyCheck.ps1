<#
.SYNOPSIS
    Downloads and audits Intel's pinned Bluetooth EXE without executing it.
.DESCRIPTION
    Asks before download, verifies Intel's published SHA-256, checks the
    Authenticode signature, compares AX201 reference and installed versions,
    then deletes the temporary EXE. Never runs a driver installer.
#>
param([ValidateSet('ru', 'en')][string]$Language = 'ru')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$data = Get-Content -LiteralPath (Join-Path $root 'data\intel-bluetooth-24.70.0.json') -Raw | ConvertFrom-Json
$url = 'https://downloadmirror.intel.com/927576/BT-24.70.0-64UWD-Win10-Win11.exe'
$hash = '001DF2E294E86D051645EA1367F4A19518CA8C2A52782CDD4C1CB81C3C0F038A'
if ($data.downloadUrl -ne $url -or $data.sha256 -ne $hash -or
    $data.fileName -ne 'BT-24.70.0-64UWD-Win10-Win11.exe') {
    throw 'Reviewed Bluetooth download metadata changed.'
}
$question = if ($Language -eq 'ru') {
    'Скачать около 61 МБ с downloadmirror.intel.com для проверки Bluetooth AX201 без установки? (Y/N)'
} else {
    'Download about 61 MB from downloadmirror.intel.com to check AX201 Bluetooth without installation? (Y/N)'
}
if ((Read-Host $question) -notmatch '^[Yy]$') {
    Write-Host $(if ($Language -eq 'ru') { 'Загрузка отменена.' } else { 'Download cancelled.' })
    return
}
$checker = Join-Path $PSScriptRoot 'Test-OfficialBluetoothPackage.ps1'
if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) { throw "Missing local checker: $checker" }
$workBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Work'
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$work = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    $package = Join-Path $work $data.fileName
    Write-Host $(if ($Language -eq 'ru') { 'Загрузка EXE во временную папку. Установщик не запускается и после проверки удаляется.' } else { 'Downloading the EXE to a temporary folder. It will not be launched and will be deleted after the check.' })
    Invoke-WebRequest -Uri $url -OutFile $package -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ine $hash) {
        throw 'Downloaded Intel Bluetooth EXE SHA-256 differs from the hash on Intel page.'
    }
    & $checker -PackageFile $package -Language $Language
    Write-Host $(if ($Language -eq 'ru') { 'Проверка завершена. Временный EXE удаляется; установка не запускалась.' } else { 'Audit complete. The temporary EXE is being deleted; installation was never started.' })
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
