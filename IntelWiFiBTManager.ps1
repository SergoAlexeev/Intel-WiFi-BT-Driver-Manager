<#
.SYNOPSIS
    Запускает официальный Universal Intel Wi-Fi and Bluetooth Drivers Updater.
.DESCRIPTION
    Проверяет наличие адаптеров Intel, метаданные пакета PowerShell Gallery и запускает
    базовую утилиту. В интерактивном режиме базовая утилита сама предлагает обновления.
.PARAMETER Silent
    Автоматическое обновление без запросов. Требует запуска от администратора.
#>
param([switch]$Silent)

Write-Host 'Intel Wi-Fi & Bluetooth Driver Manager v2.1.0' -ForegroundColor Cyan
$ErrorActionPreference = 'Stop'
$updaterName = 'universal-intel-wifi-bt-driver-updater'
$expectedAuthor = 'Marcin Grygiel'
$expectedProject = 'https://github.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater'

function Stop-Manager([string]$Message) {
    [Console]::Error.WriteLine("Ошибка: $Message")
    if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' | Out-Null }
    exit 1
}

function Test-PackageIdentity($Package) {
    if (-not $Package -or $Package.Name -ne $updaterName -or
        $Package.Author -ne $expectedAuthor -or
        ([string]$Package.ProjectUri).TrimEnd('/') -ne $expectedProject) {
        throw "Метаданные пакета не совпадают с ожидаемыми (имя: $($Package.Name); автор: $($Package.Author); проект: $($Package.ProjectUri))."
    }
}

try {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        if ($Silent) { Stop-Manager 'Для тихого режима нужны права администратора.' }
        $answer = Read-Host 'Требуются права администратора. Перезапустить? (Y/N)'
        if ($answer -notmatch '^[Yy]$') { Stop-Manager 'Запуск отменён.' }
        $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
        exit $process.ExitCode
    }

    $devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.Manufacturer -match 'Intel' -and $_.DeviceName -match 'Wi-Fi|Wireless|Bluetooth'
    })
    if ($devices.Count -eq 0) { Stop-Manager 'Беспроводные адаптеры Intel не обнаружены.' }
    if (-not $Silent) {
        Write-Host 'Обнаруженные адаптеры Intel:' -ForegroundColor Cyan
        $devices | Select-Object DeviceName, DriverVersion | Format-Table -AutoSize
    }

    # На чистой Windows PowerShell 5.1 PowerShellGet может требовать поставщик NuGet.
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    # Find-Script проверяет метаданные записи PSGallery; это не криптографическая подпись.
    $available = Find-Script -Name $updaterName -Repository PSGallery
    Test-PackageIdentity $available
    # Собственное хранилище не зависит от перенесённых записей InstalledLocation.
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Не удалось определить локальную папку данных пользователя.'
    }
    $cachePath = [IO.Path]::Combine($localData, 'IntelWiFiBTManager', 'Updater')
    $scriptPath = [IO.Path]::Combine($cachePath, "$updaterName.ps1")
    $needsDownload = $true
    if ([IO.File]::Exists($scriptPath)) {
        try {
            $cached = Test-ScriptFileInfo -Path $scriptPath -ErrorAction Stop
            $needsDownload = ($cached.Author -ne $expectedAuthor -or
                ([string]$cached.ProjectUri).TrimEnd('/') -ne $expectedProject -or
                [version]$cached.Version -ne [version]$available.Version)
        } catch {
            $needsDownload = $true
        }
    }

    if ($needsDownload) {
        if (-not $Silent -and (Read-Host "Скачать базовую утилиту $($available.Version) в $cachePath ? (Y/N)") -notmatch '^[Yy]$') {
            Stop-Manager 'Загрузка отменена.'
        }
        [IO.Directory]::CreateDirectory($cachePath) | Out-Null
        $staging = [IO.Path]::Combine($cachePath, [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        try {
            # Save-Script не использует записи об установленных скриптах старого ПК.
            Save-Script -Name $updaterName -Repository PSGallery -RequiredVersion $available.Version -Path $staging -Force -ErrorAction Stop
            $downloadedPath = [IO.Path]::Combine($staging, "$updaterName.ps1")
            $downloaded = Test-ScriptFileInfo -Path $downloadedPath -ErrorAction Stop
            if ($downloaded.Author -ne $expectedAuthor -or
                ([string]$downloaded.ProjectUri).TrimEnd('/') -ne $expectedProject -or
                [version]$downloaded.Version -ne [version]$available.Version) {
                throw 'Метаданные скачанного скрипта не совпадают с ожидаемыми.'
            }
            Move-Item -LiteralPath $downloadedPath -Destination $scriptPath -Force -ErrorAction Stop
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host 'Запуск базовой утилиты...' -ForegroundColor Cyan
    # Ее интерактивный режим показывает версии и запрашивает согласие; -auto устанавливает без вопросов.
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptPath + '"'))
    if ($Silent) { $arguments += '-auto' }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { throw "Базовая утилита завершилась с кодом $($process.ExitCode)." }
    Write-Host 'Работа завершена.' -ForegroundColor Green
    if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' | Out-Null }
    exit 0
} catch {
    Stop-Manager $_.Exception.Message
}
