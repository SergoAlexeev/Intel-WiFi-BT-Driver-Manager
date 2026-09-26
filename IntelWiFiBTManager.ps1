<#
.SYNOPSIS
    Запускает официальный Universal Intel Wi-Fi and Bluetooth Drivers Updater.
.DESCRIPTION
    Проверяет наличие адаптеров Intel, метаданные пакета PowerShell Gallery и запускает
    базовую утилиту. В интерактивном режиме базовая утилита сама предлагает обновления.
.PARAMETER Silent
    Автоматическое обновление без запросов. Требует запуска от администратора.
.PARAMETER Graphics
    Интерактивно проверяет графику Intel Core 7-10 поколений на Windows 10/11 x64.
.PARAMETER GraphicsInstallerPath
    Необязательный путь к официальному установщику gfx_win_101.2145.exe.
.PARAMETER Inventory
    Показывает сведения об устройствах Intel и платформе без установки драйверов.
.PARAMETER Language
    Язык сообщений менеджера: ru или en. Без параметра предлагается выбор.
.PARAMETER LogPath
    Внутренний параметр для продолжения журнала после запроса UAC.
#>
param(
    [switch]$Silent,
    [switch]$Graphics,
    [string]$GraphicsInstallerPath,
    [switch]$Inventory,
    [ValidateSet('ru', 'en')][string]$Language,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$script:uiLanguage = $Language
if (-not $script:uiLanguage) {
    if ($Silent) { $script:uiLanguage = 'ru' }
    else {
        do {
            $selection = Read-Host 'Язык / Language: 1 - Русский, 2 - English [1/2, Enter = 1]'
        } while ($selection -notin @('', '1', '2'))
        $script:uiLanguage = if ($selection -eq '2') { 'en' } else { 'ru' }
    }
}
function L([string]$Ru, [string]$En) {
    if ($script:uiLanguage -eq 'en') { return $En }
    return $Ru
}
$script:logActive = $false
try {
    $localDataForLog = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localDataForLog)) { throw (L 'Не удалось определить локальную папку для журнала.' 'Cannot locate the local folder for the session log.') }
    $logsDirectory = [IO.Path]::Combine($localDataForLog, 'IntelWiFiBTManager', 'Logs')
    [IO.Directory]::CreateDirectory($logsDirectory) | Out-Null
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = [IO.Path]::Combine($logsDirectory, ('manager-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8)))
    } elseif ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LogPath)) -ne $logsDirectory) {
        throw (L 'Путь журнала должен находиться в локальной папке Logs менеджера.' 'The log path must be inside the manager local Logs folder.')
    }
    Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
    $script:logActive = $true
} catch {
    [Console]::Error.WriteLine((L "Не удалось начать журнал: $($_.Exception.Message)" "Could not start session log: $($_.Exception.Message)"))
    exit 1
}
Write-Host 'Intel Wi-Fi & Bluetooth Driver Manager v2.2.0 preview' -ForegroundColor Cyan
Write-Host (L 'Язык сообщений менеджера: русский.' 'Manager message language: English.')
Write-Host (L "Журнал: $LogPath" "Session log: $LogPath")
$updaterName = 'universal-intel-wifi-bt-driver-updater'
$expectedAuthor = 'Marcin Grygiel'
$expectedProject = 'https://github.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater'
$graphicsVersion = [version]'31.0.101.2145'
$graphicsSha512 = 'D30369A17F66A787D477FE77787D934A1E74581F27CB19BA1608DF22E76C8DCE68B589DB327456527AE9228D8788663CE005467DF84C722C03F59A2E9297C2D5'
$graphicsUri = 'https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe'
$script:offerGraphicsRestart = $false

function Test-GraphicsPackageMatch($Processor, $Device, $Os) {
    # The Intel release notes group Core 7th-10th Gen HD/UHD/Iris Plus graphics
    # in this package. Intel's signed installer makes the final compatibility check.
    if (-not $Processor -or -not $Device -or -not $Os) { return $false }
    if ($Os.OSArchitecture -notmatch '64' -or $Os.Caption -notmatch 'Windows (10|11)') { return $false }
    if ($Os.Caption -match 'Windows 10' -and [version]$Os.Version -lt [version]'10.0.17763') { return $false }
    if ($Processor.Name -notmatch '(?i)\bi[3579]-(?:[789]\d{3}|10\d{3})[A-Z0-9]*\b') { return $false }
    if ($Device.DeviceClass -ne 'DISPLAY' -or $Device.DeviceID -notmatch '(?i)^PCI\\VEN_8086&DEV_[0-9A-F]{4}') { return $false }
    return ($Device.DeviceName -match '(?i)^Intel(?:\(R\))?\s+(?:HD|UHD|Iris(?:\(R\))?\s+Plus)\s+Graphics')
}

function Close-ManagerLog {
    if ($script:logActive) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        $script:logActive = $false
    }
}

function Test-GraphicsRestartEligible([int]$InstallerExitCode, [bool]$VersionConfirmed) {
    return ($VersionConfirmed -or $InstallerExitCode -in @(0, 2, 14, 3010))
}

function Invoke-GraphicsRestartPrompt {
    if ((Read-Host (L 'Этап 5/5. Сохраните открытые документы. Перезагрузить компьютер сейчас? (Y/N)' 'Step 5/5. Save open work. Restart the computer now? (Y/N)')) -notmatch '^[Yy]$') {
        Write-Host (L 'Перезагрузка отложена. Вы сможете перезагрузить компьютер позже вручную.' 'Restart postponed. You can restart the computer manually later.')
        return $false
    }
    Write-Host (L 'Перезагрузка подтверждена. Закрываю журнал и передаю команду Windows.' 'Restart confirmed. Closing the log and asking Windows to restart.')
    Close-ManagerLog
    Restart-Computer -ErrorAction Stop
    return $true
}

function Exit-Manager([int]$Code) {
    Write-Host (L "Код завершения: $Code; журнал: $LogPath" "Exit code: $Code; log: $LogPath")
    Close-ManagerLog
    exit $Code
}

function Stop-Manager([string]$Message) {
    Write-Host (L "Ошибка: $Message" "Error: $Message") -ForegroundColor Red
    if (-not $Silent) { Read-Host (L 'Нажмите Enter для выхода' 'Press Enter to exit') | Out-Null }
    Exit-Manager 1
}

function Test-PackageIdentity($Package) {
    if (-not $Package -or $Package.Name -ne $updaterName -or
        $Package.Author -ne $expectedAuthor -or
        ([string]$Package.ProjectUri).TrimEnd('/') -ne $expectedProject) {
        throw (L "Метаданные пакета не совпадают с ожидаемыми (имя: $($Package.Name); автор: $($Package.Author); проект: $($Package.ProjectUri))." "Package identity does not match (name: $($Package.Name); author: $($Package.Author); project: $($Package.ProjectUri)).")
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
        Write-Host (L 'Устройства Intel в выбранных категориях не найдены.' 'No Intel devices were found in the selected categories.')
    } else {
        $devices | Select-Object DeviceClass, DriverVersion, DeviceName | Format-Table -AutoSize
    }
    Write-Host (L 'Этот отчёт не определяет наличие обновлений чипсета, BIOS или микрокода.' 'This inventory does not check for chipset, BIOS, or microcode updates.') -ForegroundColor Yellow
}

function Update-IntelGraphics {
    if ($Silent) { throw (L 'Режим графики требует интерактивного подтверждения; не используйте -Silent.' 'Graphics updates require interactive confirmation; do not use -Silent.') }
    Write-Host (L 'Этап 1/5. Проверяю процессор, Windows и графическое устройство Intel.' 'Step 1/5. Checking the processor, Windows, and Intel graphics device.') -ForegroundColor Cyan
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    $graphicsDevices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceClass -eq 'DISPLAY' -and $_.DeviceID -match '(?i)^PCI\\VEN_8086&DEV_[0-9A-F]{4}'
    })
    if ($graphicsDevices.Count -ne 1) {
        throw (L "Ожидалось одно графическое устройство Intel; найдено: $($graphicsDevices.Count). Выбор пакета отменён." "Expected exactly one Intel graphics device; found: $($graphicsDevices.Count). No package was selected.")
    }
    $graphicsDevice = $graphicsDevices[0]
    if (-not (Test-GraphicsPackageMatch $processor $graphicsDevice $os)) {
        throw (L "Пакет 31.0.101.2145 не подобран для этого сочетания процессора, Windows и графики (ID: $($graphicsDevice.DeviceID)). Установка не запускалась." "Package 31.0.101.2145 was not selected for this processor, Windows version, and graphics device (ID: $($graphicsDevice.DeviceID)). Nothing was installed.")
    }
    Write-Host (L "Распознано: $($processor.Name); $($graphicsDevice.DeviceName); $($os.Caption); ID: $($graphicsDevice.DeviceID)." "Matched: $($processor.Name); $($graphicsDevice.DeviceName); $($os.Caption); ID: $($graphicsDevice.DeviceID).")
    Write-Host (L 'Выбрана ветка Intel Graphics для Core 7–10 поколений. Окончательную совместимость проверит установщик Intel.' 'Selected Intel Graphics for 7th–10th Gen Core. The Intel installer makes the final compatibility decision.')
    $installedVersion = [version]$graphicsDevice.DriverVersion
    Write-Host (L "Установлено: $installedVersion; доступный проверяемый пакет: $graphicsVersion." "Installed: $installedVersion; available pinned package: $graphicsVersion.")
    if ($installedVersion -ge $graphicsVersion) {
        Write-Host (L 'Установленная версия не старее этого пакета. Загрузка и установка не требуются.' 'The installed version is not older than this package. No download or installation is needed.') -ForegroundColor Green
        return
    }

    Write-Host (L 'Этап 2/5. Подготовка пакета. Универсальный драйвер Intel может заменить настройки драйвера производителя ПК.' 'Step 2/5. Preparing the package. Intel generic graphics may replace computer manufacturer driver customizations.') -ForegroundColor Yellow
    Write-Host (L 'Установщик Intel отдельно покажет условия лицензии и проверит совместимость. Во время установки экран может мигнуть; после неё может потребоваться перезагрузка.' 'Intel setup displays its license and checks compatibility. The display may flicker during installation, and a restart may be needed afterward.') -ForegroundColor Yellow
    $installerPath = $GraphicsInstallerPath
    if ([string]::IsNullOrWhiteSpace($installerPath)) {
        $localData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localData)) { throw (L 'Не удалось определить локальную папку данных пользователя.' 'Cannot locate the local application data folder.') }
        $graphicsCache = [IO.Path]::Combine($localData, 'IntelWiFiBTManager', 'Graphics')
        $installerPath = [IO.Path]::Combine($graphicsCache, 'gfx_win_101.2145.exe')
        Write-Host (L "Проверяю, есть ли ранее загруженный пакет: $installerPath" "Checking for a previously downloaded package: $installerPath")
        if (-not [IO.File]::Exists($installerPath) -or
            (Get-FileHash -LiteralPath $installerPath -Algorithm SHA512).Hash -ne $graphicsSha512) {
            if ((Read-Host (L "Скачать Intel Graphics $graphicsVersion с downloadmirror.intel.com (около 278 МБ) в локальный кэш? (Y/N)" "Download Intel Graphics $graphicsVersion from downloadmirror.intel.com (about 278 MB) into the local cache? (Y/N)")) -notmatch '^[Yy]$') {
                Write-Host (L 'Загрузка отменена. Изменений нет.' 'Download declined. Nothing was changed.')
                return
            }
            [IO.Directory]::CreateDirectory($graphicsCache) | Out-Null
            $staging = [IO.Path]::Combine($graphicsCache, [guid]::NewGuid().ToString('N') + '.exe')
            try {
                Write-Host (L "Загружаю файл с официального адреса $graphicsUri" "Downloading from the official URL $graphicsUri")
                Invoke-WebRequest -Uri $graphicsUri -OutFile $staging -UseBasicParsing -ErrorAction Stop
                if ((Get-FileHash -LiteralPath $staging -Algorithm SHA512).Hash -ne $graphicsSha512) {
                    throw (L 'Контрольная сумма загрузки не совпадает с опубликованной Intel.' 'The download SHA-512 does not match the value published by Intel.')
                }
                $downloadSignature = Get-AuthenticodeSignature -LiteralPath $staging
                if ($downloadSignature.Status -ne 'Valid' -or
                    $downloadSignature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Intel Corporation(,|$)') {
                    throw (L 'Загрузка не имеет действительной подписи Intel Corporation.' 'The download does not have a valid Intel Corporation signature.')
                }
                Move-Item -LiteralPath $staging -Destination $installerPath -Force -ErrorAction Stop
                Write-Host (L "Проверенный пакет сохранён: $installerPath" "Verified package saved: $installerPath")
            } finally {
                Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
            }
        }
    }
    $installer = Get-Item -LiteralPath $installerPath -ErrorAction Stop
    if ($installer.Name -ne 'gfx_win_101.2145.exe' -or $installer.PSIsContainer) {
        throw (L 'Ожидался файл gfx_win_101.2145.exe.' 'Expected a file named gfx_win_101.2145.exe.')
    }
    $hash = (Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA512 -ErrorAction Stop).Hash
    if ($hash -ne $graphicsSha512) { throw (L 'Контрольная сумма установщика не совпадает с опубликованной Intel.' 'The installer SHA-512 does not match the Intel published value.') }
    $signature = Get-AuthenticodeSignature -LiteralPath $installer.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Intel Corporation(,|$)') {
        throw (L 'Установщик не имеет действительной подписи Intel Corporation.' 'The installer does not have a valid Intel Corporation signature.')
    }
    Write-Host (L "Этап 3/5. SHA-512 и подпись Intel подтверждены: $($installer.FullName)" "Step 3/5. Intel SHA-512 and signature verified: $($installer.FullName)")
    if ((Read-Host (L "Запустить установщик Intel Graphics $graphicsVersion? Откроется отдельное окно Intel. (Y/N)" "Launch Intel Graphics $graphicsVersion setup? A separate Intel window will open. (Y/N)")) -notmatch '^[Yy]$') {
        Write-Host (L 'Установка отменена. Драйвер не изменён.' 'Installation declined. The driver was not changed.')
        return
    }
    Write-Host (L 'Запускаю интерактивный установщик Intel и ожидаю его завершения.' 'Launching Intel interactive setup and waiting for it to finish.')
    $process = Start-Process -FilePath $installer.FullName -Wait -PassThru
    Write-Host (L "Этап 4/5. Установщик закрыт, код: $($process.ExitCode). Повторно читаю версию драйвера из Windows." "Step 4/5. Installer closed with exit code $($process.ExitCode). Checking the driver version in Windows again.")
    $after = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -eq $graphicsDevice.DeviceID } | Select-Object -First 1
    $versionConfirmed = $after -and [version]$after.DriverVersion -ge $graphicsVersion
    if ($versionConfirmed) {
        Write-Host (L "Новая версия драйвера подтверждена: $($after.DriverVersion)." "New driver version confirmed: $($after.DriverVersion).") -ForegroundColor Green
    } else {
        Write-Warning (L "Новая версия пока не обнаружена; текущая: $($after.DriverVersion)." "The new version is not visible yet; currently reported: $($after.DriverVersion).")
    }
    # Коды 0, 2 и 14 описаны Intel; 3010 — стандартный код Windows для перезагрузки.
    # Неизвестный код можно принять только если новая версия уже видна в системе.
    $script:offerGraphicsRestart = Test-GraphicsRestartEligible $process.ExitCode ([bool]$versionConfirmed)
    if (-not $script:offerGraphicsRestart) {
        throw (L "Установщик вернул неизвестный код $($process.ExitCode), новая версия не подтверждена. Проверьте C:\ProgramData\Intel\GFXInstaller\IntelGfx.log." "Installer exit code $($process.ExitCode) is unrecognized and the new version was not confirmed. Check C:\ProgramData\Intel\GFXInstaller\IntelGfx.log.")
    }
}

try {
    if ($GraphicsInstallerPath -and -not $Graphics) { throw (L 'Параметр -GraphicsInstallerPath используется только с -Graphics.' 'Use -GraphicsInstallerPath only together with -Graphics.') }
    if ($Inventory) {
        if ($Graphics -or $Silent -or $GraphicsInstallerPath) { throw (L 'Параметр -Inventory используется отдельно от режимов установки.' 'Use -Inventory separately from installation modes.') }
        Write-Host (L 'Инвентаризация: только просмотр устройств; скачивания и установки не будет.' 'Inventory: read-only device listing; no downloads or installation.') -ForegroundColor Cyan
        Show-IntelInventory
        Exit-Manager 0
    }
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $admin) {
        if ($Silent) { Stop-Manager (L 'Для тихого режима нужны права администратора.' 'Administrator rights are required for -Silent.') }
        Write-Host (L 'Для установки нужны права администратора. После подтверждения UAC менеджер продолжит работу и запись в тот же журнал.' 'Administrator rights are needed to install drivers. After UAC confirmation, the manager will continue using the same log.')
        $answer = Read-Host (L 'Перезапустить с правами администратора? (Y/N)' 'Restart with administrator rights? (Y/N)')
        if ($answer -notmatch '^[Yy]$') { Stop-Manager (L 'Запуск отменён.' 'Run cancelled.') }
        $elevatedArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
        if ($Graphics) { $elevatedArguments += '-Graphics' }
        if ($GraphicsInstallerPath) { $elevatedArguments += @('-GraphicsInstallerPath', ('"' + $GraphicsInstallerPath + '"')) }
        $elevatedArguments += @('-Language', $script:uiLanguage)
        $elevatedArguments += @('-LogPath', ('"' + $LogPath + '"'))
        Write-Host (L 'Запрашиваю права администратора; журнал продолжится в повышенном процессе.' 'Requesting administrator rights; the elevated process will continue the log.')
        Close-ManagerLog
        try {
            $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $elevatedArguments
        } finally {
            Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
            $script:logActive = $true
        }
        Write-Host (L "Повышенный процесс завершился с кодом $($process.ExitCode)." "Elevated process finished with exit code $($process.ExitCode).")
        Exit-Manager $process.ExitCode
    }

    if ($Graphics) {
        Update-IntelGraphics
        if ($script:offerGraphicsRestart) {
            try {
                if (Invoke-GraphicsRestartPrompt) { exit 0 }
            } catch {
                [Console]::Error.WriteLine((L "Не удалось перезагрузить компьютер: $($_.Exception.Message)" "Could not restart the computer: $($_.Exception.Message)"))
                exit 1
            }
        }
        if (-not $Silent) { Read-Host (L 'Нажмите Enter для выхода' 'Press Enter to exit') | Out-Null }
        Exit-Manager 0
    }

    $devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.Manufacturer -match 'Intel' -and $_.DeviceName -match 'Wi-Fi|Wireless|Bluetooth'
    })
    if ($devices.Count -eq 0) { Stop-Manager (L 'Беспроводные адаптеры Intel не обнаружены.' 'No Intel Wi-Fi or Bluetooth adapters were detected.') }
    if (-not $Silent) {
        Write-Host (L 'Этап 1/4. Обнаруженные беспроводные адаптеры Intel и их установленные версии:' 'Step 1/4. Detected Intel wireless adapters and installed versions:') -ForegroundColor Cyan
        $devices | Select-Object DeviceName, DriverVersion | Format-Table -AutoSize
    }

    # На чистой Windows PowerShell 5.1 PowerShellGet может требовать поставщик NuGet.
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Host (L 'Этап 2/4. Устанавливаю поставщик NuGet, который нужен PowerShellGet для поиска в PSGallery.' 'Step 2/4. Installing the NuGet provider required by PowerShellGet to query PSGallery.')
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    # Find-Script проверяет метаданные записи PSGallery; это не криптографическая подпись.
    Write-Host (L 'Этап 2/4. Проверяю версию, автора и страницу проекта базовой утилиты в PSGallery.' 'Step 2/4. Checking the base tool version, author, and project URL in PSGallery.')
    $available = Find-Script -Name $updaterName -Repository PSGallery
    Test-PackageIdentity $available
    Write-Host (L "Подтверждён пакет $($available.Name) версии $($available.Version), автор $($available.Author)." "Package verified: $($available.Name), version $($available.Version), author $($available.Author).")
    # Собственное хранилище не зависит от перенесённых записей InstalledLocation.
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw (L 'Не удалось определить локальную папку данных пользователя.' 'Cannot locate the local application data folder.')
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
        Write-Host (L 'Этап 3/4. Локальная копия отсутствует или отличается от версии в PSGallery.' 'Step 3/4. The cached copy is missing or differs from the PSGallery version.')
        if (-not $Silent -and (Read-Host (L "Скачать базовую утилиту $($available.Version) в $cachePath? (Y/N)" "Download base tool $($available.Version) into $cachePath? (Y/N)")) -notmatch '^[Yy]$') {
            Stop-Manager (L 'Загрузка отменена.' 'Download declined.')
        }
        [IO.Directory]::CreateDirectory($cachePath) | Out-Null
        $staging = [IO.Path]::Combine($cachePath, [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        try {
            Write-Host (L "Загружаю базовую утилиту $($available.Version) в локальный кэш." "Downloading base tool $($available.Version) to the local cache.")
            # Save-Script не использует записи об установленных скриптах.
            Save-Script -Name $updaterName -Repository PSGallery -RequiredVersion $available.Version -Path $staging -Force -ErrorAction Stop
            $downloadedPath = [IO.Path]::Combine($staging, "$updaterName.ps1")
            $downloaded = Test-ScriptFileInfo -Path $downloadedPath -ErrorAction Stop
            if ($downloaded.Author -ne $expectedAuthor -or
                ([string]$downloaded.ProjectUri).TrimEnd('/') -ne $expectedProject -or
                [version]$downloaded.Version -ne [version]$available.Version) {
                throw (L 'Метаданные скачанного скрипта не совпадают с ожидаемыми.' 'Downloaded script metadata do not match the expected identity.')
            }
            Move-Item -LiteralPath $downloadedPath -Destination $scriptPath -Force -ErrorAction Stop
        } finally {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host (L 'Этап 3/4. Проверенная локальная копия актуальна; повторная загрузка не нужна.' 'Step 3/4. The verified cached copy is current; no download is needed.')
    }
    if ($Silent) {
        Write-Host (L 'Этап 4/4. Запускаю базовую утилиту в автоматическом режиме -auto. Её экраны и сообщения остаются английскими.' 'Step 4/4. Starting the base tool in automatic -auto mode. Its own screens and messages remain in English.') -ForegroundColor Cyan
    } else {
        Write-Host (L 'Этап 4/4. Запускаю базовую утилиту. Она откроет свои экраны на английском и запросит согласие перед установкой.' 'Step 4/4. Starting the base tool. Its own screens are in English and it will request confirmation before installing.') -ForegroundColor Cyan
        Write-Host (L 'Если все драйверы актуальны, вопрос «force reinstall ... (Y/N)» означает принудительную переустановку: N — оставить драйверы без изменений.' 'If all drivers are current, the base tool may ask “force reinstall ... (Y/N)”: N keeps the installed drivers unchanged.')
    }
    # Ее интерактивный режим показывает версии и запрашивает согласие; -auto устанавливает без вопросов.
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $scriptPath + '"'))
    if ($Silent) { $arguments += '-auto' }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    Write-Host (L "Базовая утилита завершилась с кодом $($process.ExitCode)." "Base tool finished with exit code $($process.ExitCode).")
    if ($process.ExitCode -ne 0) { throw (L "Базовая утилита завершилась с кодом $($process.ExitCode)." "Base tool failed with exit code $($process.ExitCode).") }
    Write-Host (L 'Работа завершена. Если драйвер устанавливался, проверьте его версию в Windows после завершения.' 'Finished. If a driver was installed, check its version in Windows afterward.') -ForegroundColor Green
    if (-not $Silent) { Read-Host (L 'Нажмите Enter для выхода' 'Press Enter to exit') | Out-Null }
    Exit-Manager 0
} catch {
    Stop-Manager $_.Exception.Message
}
