<#
.SYNOPSIS
    Запускает официальный Universal Intel Wi-Fi and Bluetooth Drivers Updater.
.DESCRIPTION
    Проверяет наличие адаптеров Intel, метаданные пакета PowerShell Gallery и запускает
    базовую утилиту. В интерактивном режиме базовая утилита сама предлагает обновления.
.PARAMETER Silent
    Автоматическое обновление без запросов. Требует запуска от администратора.
.PARAMETER Graphics
    Интерактивно проверяет и обновляет Intel UHD Graphics для i7-10710U на Windows 11.
.PARAMETER GraphicsInstallerPath
    Необязательный путь к официальному установщику gfx_win_101.2145.exe.
.PARAMETER Inventory
    Показывает сведения об устройствах Intel и платформе без установки драйверов.
.PARAMETER LogPath
    Внутренний параметр для продолжения журнала после запроса UAC.
#>
param(
    [switch]$Silent,
    [switch]$Graphics,
    [string]$GraphicsInstallerPath,
    [switch]$Inventory,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$script:logActive = $false
try {
    $localDataForLog = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localDataForLog)) { throw 'Не удалось определить локальную папку для журнала.' }
    $logsDirectory = [IO.Path]::Combine($localDataForLog, 'IntelWiFiBTManager', 'Logs')
    [IO.Directory]::CreateDirectory($logsDirectory) | Out-Null
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = [IO.Path]::Combine($logsDirectory, ('manager-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8)))
    } elseif ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LogPath)) -ne $logsDirectory) {
        throw 'Путь журнала должен находиться в локальной папке Logs менеджера.'
    }
    Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
    $script:logActive = $true
} catch {
    [Console]::Error.WriteLine("Не удалось начать журнал: $($_.Exception.Message)")
    exit 1
}
Write-Host 'Intel Wi-Fi & Bluetooth Driver Manager v2.2.0 preview' -ForegroundColor Cyan
Write-Host "Журнал: $LogPath"
$updaterName = 'universal-intel-wifi-bt-driver-updater'
$expectedAuthor = 'Marcin Grygiel'
$expectedProject = 'https://github.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater'
$graphicsVersion = [version]'31.0.101.2145'
$graphicsSha512 = 'D30369A17F66A787D477FE77787D934A1E74581F27CB19BA1608DF22E76C8DCE68B589DB327456527AE9228D8788663CE005467DF84C722C03F59A2E9297C2D5'
$graphicsUri = 'https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe'
$script:offerGraphicsRestart = $false

function Close-ManagerLog {
    if ($script:logActive) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        $script:logActive = $false
    }
}

function Exit-Manager([int]$Code) {
    Write-Host "Код завершения: $Code; журнал: $LogPath"
    Close-ManagerLog
    exit $Code
}

function Stop-Manager([string]$Message) {
    Write-Host "Ошибка: $Message" -ForegroundColor Red
    if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' | Out-Null }
    Exit-Manager 1
}

function Test-PackageIdentity($Package) {
    if (-not $Package -or $Package.Name -ne $updaterName -or
        $Package.Author -ne $expectedAuthor -or
        ([string]$Package.ProjectUri).TrimEnd('/') -ne $expectedProject) {
        throw "Метаданные пакета не совпадают с ожидаемыми (имя: $($Package.Name); автор: $($Package.Author); проект: $($Package.ProjectUri))."
    }
}

function Show-IntelInventory {
    $computer = Get-CimInstance Win32_ComputerSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    [PSCustomObject]@{
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        Processor = $processor.Name
        Windows = $os.Caption
        BIOSVersion = $bios.SMBIOSBIOSVersion
    } | Format-List

    $classes = @('DISPLAY', 'NET', 'Bluetooth', 'SYSTEM', 'SoftwareComponent')
    $devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceClass -in $classes -and
        ($_.DeviceID -match 'VEN_8086|VID_8087' -or $_.Manufacturer -match 'Intel') -and
        ($_.DeviceName -match 'Intel|Thunderbolt' -or
            ($_.DeviceClass -in @('DISPLAY', 'NET', 'Bluetooth') -and $_.Manufacturer -match 'Intel'))
    } | Sort-Object DeviceClass, DeviceName)
    if ($devices.Count -eq 0) {
        Write-Host 'Устройства Intel в выбранных категориях не найдены.'
    } else {
        $devices | Select-Object DeviceClass, DriverVersion, DeviceName | Format-Table -AutoSize
    }
    Write-Host 'Этот отчёт не определяет наличие обновлений чипсета, BIOS или микрокода.' -ForegroundColor Yellow
}

function Update-IntelGraphics {
    if ($Silent) { throw 'Режим обновления графики требует интерактивного подтверждения; не используйте -Silent.' }
    $processor = Get-CimInstance Win32_Processor | Where-Object { $_.Name -match 'i7-10710U' } | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    if (-not $processor -or $os.Caption -notmatch 'Windows 11' -or $os.OSArchitecture -notmatch '64') {
        throw 'Этот режим пока проверяет только i7-10710U с 64-разрядной Windows 11.'
    }
    $graphicsDevice = Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceName -match '^Intel.*Graphics' -and
        $_.DeviceID -match 'VEN_8086'
    } | Select-Object -First 1
    if (-not $graphicsDevice) { throw 'Совместимая встроенная графика Intel не обнаружена.' }
    $installedVersion = [version]$graphicsDevice.DriverVersion
    Write-Host "Графика: $($graphicsDevice.DeviceName); установленная версия: $installedVersion; доступный пакет: $graphicsVersion"
    if ($installedVersion -ge $graphicsVersion) {
        Write-Host 'Установленная версия не старее поддерживаемого пакета.' -ForegroundColor Green
        return
    }

    Write-Host 'Универсальный драйвер Intel может заменить драйвер, настроенный производителем ноутбука.' -ForegroundColor Yellow
    Write-Host 'Установщик Intel проверит совместимость и покажет условия лицензии. После установки может понадобиться перезагрузка.' -ForegroundColor Yellow
    $installerPath = $GraphicsInstallerPath
    if ([string]::IsNullOrWhiteSpace($installerPath)) {
        $localData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localData)) { throw 'Не удалось определить локальную папку данных пользователя.' }
        $graphicsCache = [IO.Path]::Combine($localData, 'IntelWiFiBTManager', 'Graphics')
        $installerPath = [IO.Path]::Combine($graphicsCache, 'gfx_win_101.2145.exe')
        Write-Host "Проверка локального пакета: $installerPath"
        if (-not [IO.File]::Exists($installerPath) -or
            (Get-FileHash -LiteralPath $installerPath -Algorithm SHA512).Hash -ne $graphicsSha512) {
            if ((Read-Host "Скачать $graphicsVersion с downloadmirror.intel.com (около 278 МБ)? (Y/N)") -notmatch '^[Yy]$') {
                Write-Host 'Загрузка отменена. Изменений нет.'
                return
            }
            [IO.Directory]::CreateDirectory($graphicsCache) | Out-Null
            $staging = [IO.Path]::Combine($graphicsCache, [guid]::NewGuid().ToString('N') + '.exe')
            try {
                Write-Host "Загрузка с $graphicsUri"
                Invoke-WebRequest -Uri $graphicsUri -OutFile $staging -UseBasicParsing -ErrorAction Stop
                if ((Get-FileHash -LiteralPath $staging -Algorithm SHA512).Hash -ne $graphicsSha512) {
                    throw 'Контрольная сумма загрузки не совпадает с опубликованной Intel.'
                }
                $downloadSignature = Get-AuthenticodeSignature -LiteralPath $staging
                if ($downloadSignature.Status -ne 'Valid' -or
                    $downloadSignature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Intel Corporation(,|$)') {
                    throw 'Загрузка не имеет действительной подписи Intel Corporation.'
                }
                Move-Item -LiteralPath $staging -Destination $installerPath -Force -ErrorAction Stop
                Write-Host "Проверенный пакет сохранён: $installerPath"
            } finally {
                Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $installer = Get-Item -LiteralPath $installerPath -ErrorAction Stop
    if ($installer.Name -ne 'gfx_win_101.2145.exe' -or $installer.PSIsContainer) {
        throw 'Ожидался файл gfx_win_101.2145.exe.'
    }
    $hash = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA512 -ErrorAction Stop).Hash
    if ($hash -ne $graphicsSha512) { throw 'Контрольная сумма установщика не совпадает с опубликованной Intel.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Intel Corporation(,|$)') {
        throw 'Установщик не имеет действительной подписи Intel Corporation.'
    }
    Write-Host "SHA-512 и подпись Intel подтверждены: $($installer.FullName)"
    if ((Read-Host "Запустить проверенный установщик Intel Graphics $graphicsVersion ? (Y/N)") -notmatch '^[Yy]$') {
        Write-Host 'Установка отменена. Драйвер не изменён.'
        return
    }
    Write-Host 'Запуск интерактивного установщика Intel Graphics.'
    $process = Start-Process -FilePath $installer.FullName -Wait -PassThru
    Write-Host "Установщик завершился с кодом $($process.ExitCode)."
    $after = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -eq $graphicsDevice.DeviceID } | Select-Object -First 1
    $versionConfirmed = $after -and [version]$after.DriverVersion -ge $graphicsVersion
    if ($versionConfirmed) {
        Write-Host "Версия драйвера подтверждена: $($after.DriverVersion)." -ForegroundColor Green
    } else {
        Write-Warning "Новая версия пока не обнаружена; текущая: $($after.DriverVersion)."
    }
    # Коды 0, 2 и 14 описаны Intel; 3010 — стандартный код Windows для перезагрузки.
    # Неизвестный код можно принять только если новая версия уже видна в системе.
    if ($process.ExitCode -notin @(0, 2, 14, 3010) -and -not $versionConfirmed) {
        throw "Установщик вернул неизвестный код $($process.ExitCode), новая версия не подтверждена. Проверьте C:\ProgramData\Intel\GFXInstaller\IntelGfx.log."
    }
    $script:offerGraphicsRestart = $true
}

try {
    if ($GraphicsInstallerPath -and -not $Graphics) { throw 'Параметр -GraphicsInstallerPath используется только с -Graphics.' }
    if ($Inventory) {
        if ($Graphics -or $Silent -or $GraphicsInstallerPath) { throw 'Параметр -Inventory используется отдельно от режимов установки.' }
        Show-IntelInventory
        Exit-Manager 0
    }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        if ($Silent) { Stop-Manager 'Для тихого режима нужны права администратора.' }
        $answer = Read-Host 'Требуются права администратора. Перезапустить? (Y/N)'
        if ($answer -notmatch '^[Yy]$') { Stop-Manager 'Запуск отменён.' }
        $elevatedArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
        if ($Graphics) { $elevatedArguments += '-Graphics' }
        if ($GraphicsInstallerPath) { $elevatedArguments += @('-GraphicsInstallerPath', ('"' + $GraphicsInstallerPath + '"')) }
        $elevatedArguments += @('-LogPath', ('"' + $LogPath + '"'))
        Write-Host 'Запрос прав администратора; журнал будет продолжен в повышенном процессе.'
        Close-ManagerLog
        try {
            $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $elevatedArguments
        } finally {
            Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
            $script:logActive = $true
        }
        Write-Host "Повышенный процесс завершился с кодом $($process.ExitCode)."
        Exit-Manager $process.ExitCode
    }

    if ($Graphics) {
        Update-IntelGraphics
        if ($script:offerGraphicsRestart) {
            if ((Read-Host 'Сохраните открытые документы. Перезагрузить компьютер сейчас? (Y/N)') -match '^[Yy]$') {
                Write-Host 'Пользователь подтвердил перезагрузку. Завершаю журнал и передаю команду Windows.'
                Close-ManagerLog
                try {
                    Restart-Computer -ErrorAction Stop
                    exit 0
                } catch {
                    [Console]::Error.WriteLine("Не удалось перезагрузить компьютер: $($_.Exception.Message)")
                    exit 1
                }
            }
            Write-Host 'Перезагрузка отложена пользователем.'
        }
        if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' | Out-Null }
        Exit-Manager 0
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
    Write-Host 'Проверка версии и метаданных базовой утилиты в PSGallery.'
    $available = Find-Script -Name $updaterName -Repository PSGallery
    Test-PackageIdentity $available
    Write-Host "Подтверждён пакет $($available.Name) версии $($available.Version), автор $($available.Author)."
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
            Write-Host "Загрузка базовой утилиты $($available.Version) в локальный кэш."
            # Save-Script не использует записи об установленных скриптах.
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
    Write-Host "Базовая утилита завершилась с кодом $($process.ExitCode)."
    if ($process.ExitCode -ne 0) { throw "Базовая утилита завершилась с кодом $($process.ExitCode)." }
    Write-Host 'Работа завершена.' -ForegroundColor Green
    if (-not $Silent) { Read-Host 'Нажмите Enter для выхода' | Out-Null }
    Exit-Manager 0
} catch {
    Stop-Manager $_.Exception.Message
}
