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
.PARAMETER CheckUpdates
    Проверяет версии Wi-Fi, Bluetooth и Graphics без скачивания драйверов и установки.
.PARAMETER VerifyBluetoothCab
    При -CheckUpdates с согласия скачивает и проверяет закреплённый Bluetooth CAB для PID_0026 без установки.
.PARAMETER PrepareSignTool
    При -VerifyBluetoothCab предлагает локально подготовить проверенный Microsoft SignTool для проверки INF/CAT.
.PARAMETER CandidateManifest
    Необязательный JSON со скачанными кандидатами для локальной проверки обнаруженных устройств.
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
    [switch]$CheckUpdates,
    [switch]$VerifyBluetoothCab,
    [switch]$PrepareSignTool,
    [string]$CandidateManifest,
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
$graphics6thReferenceVersion = [version]'31.0.101.2115'
$graphics6thReferenceUri = 'https://www.intel.com/content/www/us/en/download/762755/intel-6th-gen-processor-graphics-windows.html'
$graphics11to14ReferenceUri = 'https://www.intel.com/content/www/us/en/download/864990/intel-11th-14th-gen-processor-graphics-windows.html'
$graphicsArcReferenceUri = 'https://www.intel.com/content/www/us/en/download/785597/intel-arc-graphics-windows.html'
$graphicsSha512 = 'D30369A17F66A787D477FE77787D934A1E74581F27CB19BA1608DF22E76C8DCE68B589DB327456527AE9228D8788663CE005467DF84C722C03F59A2E9297C2D5'
$graphicsUri = 'https://downloadmirror.intel.com/929187/gfx_win_101.2145.exe'
$wifiCatalogueUri = 'https://raw.githubusercontent.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater/main/data/intel-wifi-driver-latest.md'
$bluetoothCatalogueUri = 'https://raw.githubusercontent.com/FirstEverTech/Universal-Intel-WiFi-BT-Updater/main/data/intel-bt-driver-latest.md'
$script:offerGraphicsRestart = $false
$script:workDirectory = $null
$script:workRoot = $null
$script:managerRoot = $PSScriptRoot
$uiModule = Join-Path $PSScriptRoot 'tools\ConsoleUi.ps1'
if (Test-Path -LiteralPath $uiModule -PathType Leaf) { . $uiModule }

function New-ManagerWorkDirectory([string]$LocalDataBase) {
    if ($script:workDirectory) { return $script:workDirectory }
    if (-not $LocalDataBase) { $LocalDataBase = [Environment]::GetFolderPath('LocalApplicationData') }
    if ([string]::IsNullOrWhiteSpace($LocalDataBase)) { throw (L 'Не удалось определить папку локальных данных для временных файлов.' 'Cannot locate local application data for temporary files.') }
    $script:workRoot = [IO.Path]::Combine($LocalDataBase, 'IntelWiFiBTManager', 'Work')
    [IO.Directory]::CreateDirectory($script:workRoot) | Out-Null
    $script:workDirectory = [IO.Path]::Combine($script:workRoot, [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($script:workDirectory) | Out-Null
    Write-Host (L "Временные файлы этого запуска: $($script:workDirectory)" "Temporary files for this run: $($script:workDirectory)")
    return $script:workDirectory
}

function Clear-ManagerWorkDirectory {
    $path = $script:workDirectory
    $script:workDirectory = $null
    if (-not $path) { return }
    $directory = [IO.DirectoryInfo]::new($path)
    if ($directory.Parent.FullName -ne $script:workRoot -or $directory.Name -notmatch '^[a-f0-9]{32}$') {
        Write-Warning (L 'Временная папка не соответствует ожидаемому пути; автоматическая очистка пропущена.' 'Temporary folder path was unexpected; automatic cleanup was skipped.')
        return
    }
    try {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop }
        Write-Host (L 'Временные файлы этого запуска удалены; журнал сохранён.' 'Temporary files for this run were removed; the log was kept.')
    } catch {
        Write-Warning (L "Не удалось удалить временную папку $path : $($_.Exception.Message)" "Could not remove temporary folder $path : $($_.Exception.Message)")
    }
}

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

function Test-Graphics6thGenReference($Processor, $Device, $Os) {
    # Read-only historical reference. Never use this match to launch an installer.
    if (-not $Processor -or -not $Device -or -not $Os) { return $false }
    if ($Os.OSArchitecture -notmatch '64' -or $Os.Caption -notmatch 'Windows (10|11)') { return $false }
    if ($Processor.Name -notmatch '(?i)\bi[3579]-6\d{3}[A-Z0-9]*\b') { return $false }
    return ($Device.DeviceClass -eq 'DISPLAY' -and
        $Device.DeviceID -match '(?i)^PCI\\VEN_8086&DEV_[0-9A-F]{4}' -and
        $Device.DeviceName -match '(?i)^Intel(?:\(R\))?\s+(?:HD|Iris(?:\(R\))?)\s+Graphics')
}

function Get-GraphicsReferenceFamily($Processor, $Device, $Os) {
    # Advisory family selection only. It must never enable an installer.
    if (-not $Processor -or -not $Device -or -not $Os -or
        $Device.DeviceClass -ne 'DISPLAY' -or
        $Device.DeviceID -notmatch '(?i)^PCI\\VEN_8086&DEV_[0-9A-F]{4}' -or
        $Os.OSArchitecture -notmatch '64' -or $Os.Caption -notmatch 'Windows (10|11)') { return 'Unknown' }
    if ($Processor.Name -match '(?i)\bCore\s*(?:\(TM\)\s*)?Ultra\b' -or
        $Device.DeviceName -match '(?i)^Intel(?:\(R\))?\s+Arc\b') { return 'ArcUltra' }
    if ($Processor.Name -match '(?i)\bi[3579]-(?:11\d{2,3}|(?:12|13|14)\d{3})[A-Z0-9]*\b' -and
        $Device.DeviceName -match '(?i)^Intel(?:\(R\))?\s+(?:UHD|Iris(?:\(R\))?\s+Xe)\s+Graphics') { return 'Core11to14' }
    return 'Unknown'
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
    Write-Host (L 'Перезагрузка подтверждена. Журнал закрывается; команда перезагрузки передаётся Windows.' 'Restart confirmed. The log is closing and Windows will receive the restart request.')
    Clear-ManagerWorkDirectory
    Close-ManagerLog
    Restart-Computer -ErrorAction Stop
    return $true
}

function Exit-Manager([int]$Code) {
    Write-Host (L "Код завершения: $Code; журнал: $LogPath" "Exit code: $Code; log: $LogPath")
    Clear-ManagerWorkDirectory
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
    if (Get-Command Write-ManagerStage -ErrorAction SilentlyContinue) {
        Write-ManagerStage -Number 1 -Total 1 -Title (L 'Инвентаризация устройств Intel' 'Intel device inventory') -Detail (L 'Только просмотр. Загрузки и установки нет.' 'Read-only. No downloads or installation.') -Language $script:uiLanguage
    }
    $computer = Get-CimInstance Win32_ComputerSystem
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    $bios = Get-CimInstance Win32_BIOS
    [PSCustomObject]@{
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        Processor = ([string]$processor.Name).Trim()
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
    if (Get-Command Write-ManagerStatus -ErrorAction SilentlyContinue) {
        Write-ManagerStatus -Code Skip -Message (L 'Поиск обновлений в режиме инвентаризации не выполнялся.' 'Inventory did not search for updates.') -Language $script:uiLanguage
    }
}

function Convert-DriverCatalogue([string]$Content, [ValidateSet('WiFi', 'Bluetooth')][string]$Kind) {
    $versions = @{}
    $section = ''
    foreach ($line in ($Content -split '\r?\n')) {
        if ($Kind -eq 'Bluetooth' -and $line -match '^## Supported (USB|PCI) Devices') { $section = $Matches[1]; continue }
        if ($Kind -eq 'Bluetooth' -and $line -match '^## ') { $section = ''; continue }
        if ($line -notmatch '^\|') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($Kind -eq 'WiFi') {
            if ($cells.Count -lt 6 -or $cells[0] -notmatch '^DEV_([0-9A-Fa-f]{4})$') { continue }
            $key = "PCI:$($Matches[1].ToUpperInvariant())"
            $value = $cells[4]
        } else {
            if ($cells.Count -lt 6 -or $section -notin @('USB', 'PCI') -or $cells[0] -notmatch '^[0-9A-Fa-f]{4}$') { continue }
            $key = "${section}:$($cells[0].ToUpperInvariant())"
            $value = $cells[4]
        }
        try { $parsed = [version]$value } catch { continue }
        if ($versions.ContainsKey($key) -and $versions[$key] -ne $parsed) {
            throw "Conflicting catalogue versions for $key"
        }
        $versions[$key] = $parsed
    }
    if ($versions.Count -eq 0) { throw "No valid entries in $Kind catalogue" }
    return $versions
}

function Get-DriverCatalogueKey($Device, [ValidateSet('WiFi', 'Bluetooth')][string]$Kind) {
    if ($Kind -eq 'WiFi' -and $Device.DeviceID -match '(?i)^PCI\\VEN_8086&DEV_([0-9A-F]{4})(?:&|\\|$)') {
        return "PCI:$($Matches[1].ToUpperInvariant())"
    }
    if ($Kind -eq 'Bluetooth') {
        if ($Device.DeviceID -match '(?i)^USB\\VID_8087&PID_([0-9A-F]{4})(?:&|\\|$)') {
            return "USB:$($Matches[1].ToUpperInvariant())"
        }
        if ($Device.DeviceID -match '(?i)^PCI\\VEN_8086&DEV_([0-9A-F]{4})(?:&|\\|$)') {
            return "PCI:$($Matches[1].ToUpperInvariant())"
        }
    }
    return $null
}

function Get-LocalWirelessKey($Device, [ValidateSet('WiFi', 'Bluetooth')][string]$Kind) {
    if ($Kind -eq 'WiFi' -and $Device.DeviceID -match '(?i)^PCI\\VEN_8086&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{8})(?:&|\\|$)') {
        return "WiFi:PCI:$($Matches[1].ToUpperInvariant()):SUBSYS_$($Matches[2].ToUpperInvariant())"
    }
    $key = Get-DriverCatalogueKey $Device $Kind
    if ($Kind -eq 'Bluetooth' -and $key) { return "Bluetooth:$key" }
    return $null
}

function Get-LocalWirelessCatalogue {
    # Curated snapshot, not a live Intel feed. Review each exact ID/version before changing it.
    # These versions were observed on AX201 hardware on 2026-09-27 and cross-checked
    # with the FirstEverTech tables. The Wi-Fi row is matched by full DEV + SUBSYS,
    # because DEV_02F0 also appears with other model names in the exported INF.
    return @{
        'WiFi:PCI:02F0:SUBSYS_00748086' = [PSCustomObject]@{ Version = [version]'24.70.0.3'; Checked = '2026-09-27'; Source = 'https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html' }
        'Bluetooth:USB:0026' = [PSCustomObject]@{ Version = [version]'24.80.0.2'; Checked = '2026-09-27'; Source = 'https://www.intel.com/content/www/us/en/download/18649/intel-wireless-bluetooth-drivers-for-windows-10-and-windows-11.html' }
    }
}

function Get-GraphicsCandidateMetadata([string]$CataloguePath) {
    # The standalone manager still works when the optional data folder is absent.
    $path = if ($CataloguePath) { $CataloguePath } else { [IO.Path]::Combine($PSScriptRoot, 'data', 'driver-packages.json') }
    if (-not [IO.File]::Exists($path)) {
        return [PSCustomObject]@{ Source = $graphicsUri; ReviewedOn = ''; Detail = (L 'Встроенный закреплённый пакет; файл каталога рядом со скриптом не найден.' 'Embedded pinned package; the catalogue file was not found next to the script.'); Catalogue = $false }
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($data.schemaVersion -ne 1) { throw 'Unexpected schema version' }
        $candidateRows = @($data.packages | Where-Object { $_.id -eq 'intel-graphics-core-7-10-31.0.101.2145' })
        if ($candidateRows.Count -ne 1 -or
            $candidateRows[0].version -ne [string]$graphicsVersion -or
            $candidateRows[0].sha512 -ne $graphicsSha512 -or
            $candidateRows[0].downloadUrl -ne $graphicsUri -or
            $candidateRows[0].installMode -ne 'graphics-preview' -or
            $candidateRows[0].sourcePage -notmatch '^https://[^/]+[.]intel[.]com/') {
            throw 'Catalogue entry differs from the pinned installer'
        }
        return [PSCustomObject]@{ Source = $candidateRows[0].sourcePage; ReviewedOn = $candidateRows[0].reviewedOn; Detail = (L 'Данные каталога совпадают со встроенными в программу версией, адресом и ожидаемым SHA-512. Сам файл драйвера в этом режиме не скачивается и не проверяется.' 'Catalogue metadata matches the version, URL and expected SHA-512 embedded in the program. No driver file is downloaded or verified in this mode.'); Catalogue = $true }
    } catch {
        Write-Warning (L "Файл каталога не прошёл проверку: $($_.Exception.Message). Использую встроенный закреплённый пакет." "Catalogue file failed validation: $($_.Exception.Message). Using the embedded pinned package.")
        return [PSCustomObject]@{ Source = $graphicsUri; ReviewedOn = ''; Detail = (L 'Встроенный закреплённый пакет; файл каталога не подтверждён.' 'Embedded pinned package; the catalogue file is unverified.'); Catalogue = $false }
    }
}

function Show-LocalCandidateChecks($DetectedDevices, $TargetOs) {
    if (-not $CandidateManifest) { return }
    $manifestPath = (Resolve-Path -LiteralPath $CandidateManifest -ErrorAction Stop).ProviderPath
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $manifest.entries -or @($manifest.entries).Count -eq 0) {
        throw (L 'Список кандидатов пуст или отсутствует поле entries.' 'Candidate list is empty or missing entries.')
    }
    $checker = Join-Path $script:managerRoot 'tools\Test-DriverCandidate.ps1'
    if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) {
        throw (L 'Модуль проверки пакета не найден рядом с менеджером в папке tools.' 'Package check module is missing from the tools folder next to the manager.')
    }
    Write-Host (L "Локальные кандидаты из ${manifestPath}: проверка точных ID обнаруженных устройств Intel." "Local candidates in ${manifestPath}: exact Intel device IDs only.") -ForegroundColor Cyan
    $seen = @{}
    foreach ($entry in @($manifest.entries)) {
        $deviceId = [string]$entry.deviceId
        if (-not $deviceId -or $seen.ContainsKey($deviceId)) {
            throw (L 'В списке есть пустой или повторяющийся ID устройства.' 'Candidate list has a missing or duplicate device ID.')
        }
        $seen[$deviceId] = $true
        $deviceMatches = @($DetectedDevices | Where-Object { $_.DeviceID -ieq $deviceId })
        if ($deviceMatches.Count -ne 1) {
            Write-Warning (L "Кандидат для $deviceId пропущен: устройство Intel с точным ID не найдено." "Candidate for $deviceId skipped: no Intel device with that exact ID was detected.")
            continue
        }
        $arguments = @{ HardwareId = $deviceId; VerifyInstalledDevice = $true; Language = $script:uiLanguage }
        if ($TargetOs -and $TargetOs.OSArchitecture -match '(?i)ARM64') { $arguments.Architecture = 'arm64' }
        elseif ($TargetOs -and $TargetOs.OSArchitecture -match '64') { $arguments.Architecture = 'amd64' }
        elseif ($TargetOs -and $TargetOs.OSArchitecture -match '32|86') { $arguments.Architecture = 'x86' }
        if ($TargetOs -and $TargetOs.Version) {
            try { $arguments.OsBuild = ([version]$TargetOs.Version).Build } catch {
                Write-Warning (L 'Не удалось определить сборку Windows для проверки INF.' 'Could not determine Windows build for INF assessment.')
            }
        }
        foreach ($field in @('installedReport', 'candidateReport', 'candidateInf', 'packageFile')) {
            $value = [string]$entry.$field
            if (-not $value -or -not [IO.Path]::IsPathRooted($value) -or -not (Test-Path -LiteralPath $value -PathType Leaf)) {
                throw (L "Для $deviceId требуется существующий абсолютный путь $field." "$deviceId requires an existing absolute path for $field.")
            }
            $parameter = @{ installedReport='InstalledReport'; candidateReport='CandidateReport'; candidateInf='CandidateInf'; packageFile='PackageFile' }[$field]
            $arguments[$parameter] = $value
        }
        foreach ($field in @('expectedSha256', 'expectedSha512', 'archiveEntry', 'sourceUrl', 'signToolPath')) {
            if ($entry.$field) {
                $parameter = @{ expectedSha256='ExpectedSha256'; expectedSha512='ExpectedSha512'; archiveEntry='ArchiveEntry'; sourceUrl='SourceUrl'; signToolPath='SignToolPath' }[$field]
                $arguments[$parameter] = [string]$entry.$field
            }
        }
        if (-not $entry.expectedSha256 -and -not $entry.expectedSha512) {
            Write-Warning (L "Для $deviceId нет заранее известного хеша; источник пакета остаётся непроверенным." "$deviceId has no pre-established hash; package provenance remains unverified.")
        }
        $decision = & $checker @arguments
        Write-Host (L "Проверка $($deviceMatches[0].DeviceName): $($decision.Verdict). Установка не выполнялась." "Assessment for $($deviceMatches[0].DeviceName): $($decision.Verdict). No installation occurred.")
    }
}

function Show-UpdateCheck {
    if (Get-Command Write-ManagerStage -ErrorAction SilentlyContinue) {
        Write-ManagerStage -Number 1 -Total 2 -Title (L 'Обнаружение устройств и источников' 'Devices and sources') -Detail (L 'Проверка версий. Установка отключена.' 'Version check. Installation is disabled.') -Language $script:uiLanguage
    }
    if ($VerifyBluetoothCab) {
        Write-Host (L 'Проверка обновлений: дополнительный CAB загружается только после согласия и удаляется после проверки. Установки драйвера нет.' 'Update check: an additional CAB is downloaded only with consent and removed afterward. No driver is installed.') -ForegroundColor Cyan
    } else {
    Write-Host (L 'Проверка обновлений: анализ установленных версий и доступных сведений о кандидатах. Загрузка и установка драйверов на этом этапе не выполняются.' 'Update check: analysis of installed versions and available candidate details. No drivers are downloaded or installed at this stage.') -ForegroundColor Cyan
    }
    $processor = Get-CimInstance Win32_Processor | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    Write-Host (L "Компьютер: $($computer.Manufacturer) $($computer.Model)." "Computer: $($computer.Manufacturer) $($computer.Model).")
    Write-Host (L "Система: процессор $(([string]$processor.Name).Trim()); $($os.Caption) ($($os.OSArchitecture))." "System: processor $(([string]$processor.Name).Trim()); $($os.Caption) ($($os.OSArchitecture)).")
    Write-Host (L 'Для каждого устройства: установленная версия, источник сравнения, результат и следующий шаг.' 'For each device: installed version, comparison source, result, and next step.')
    $allDevices = @(Get-CimInstance Win32_PnPSignedDriver)
    $devices = @($allDevices | Where-Object {
        ($_.DeviceClass -in @('NET', 'Bluetooth', 'DISPLAY')) -and
        ($_.DeviceID -match '(?i)^(PCI\\VEN_8086|USB\\VID_8087)&') -and
        ($_.DeviceClass -ne 'NET' -or $_.DeviceName -match '(?i)Wi-Fi|Wireless')
    } | Sort-Object DeviceClass, DeviceName)
    $otherWireless = @($allDevices | Where-Object {
        $_.DeviceClass -in @('NET', 'Bluetooth') -and
        $_.DeviceID -match '(?i)^(PCI\\VEN_|USB\\VID_)' -and
        $_.DeviceID -notmatch '(?i)^(PCI\\VEN_8086|USB\\VID_8087)&' -and
        $_.DeviceName -match '(?i)Wi-Fi|Wireless|Bluetooth'
    } | Sort-Object DeviceClass, DeviceName)
    $localCatalogue = Get-LocalWirelessCatalogue
    $graphicsCandidate = Get-GraphicsCandidateMetadata
    $catalogues = @{}
    foreach ($source in @(@('WiFi', $wifiCatalogueUri), @('Bluetooth', $bluetoothCatalogueUri))) {
        $deviceClass = if ($source[0] -eq 'WiFi') { 'NET' } else { 'Bluetooth' }
        $unmapped = @($devices | Where-Object {
            $candidate = Get-LocalWirelessKey $_ $source[0]
            $_.DeviceClass -eq $deviceClass -and
            -not ($candidate -and $localCatalogue.ContainsKey($candidate))
        })
        if (-not $unmapped.Count) { continue }
        try {
            $response = Invoke-WebRequest -Uri $source[1] -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $catalogues[$source[0]] = Convert-DriverCatalogue ([string]$response.Content) $source[0]
        } catch {
            Write-Warning (L "Источник $($source[0]) недоступен или его формат изменился: $($source[1]); $($_.Exception.Message)" "The $($source[0]) source is unavailable or its format changed: $($source[1]); $($_.Exception.Message)")
        }
    }
    $cabAssessment = $null
    if ($VerifyBluetoothCab) {
        $matches = @($devices | Where-Object {
            $_.DeviceClass -eq 'BLUETOOTH' -and $_.DeviceID -like 'USB\VID_8087&PID_0026*' -and
            $_.DeviceName -eq 'Intel(R) Wireless Bluetooth(R)'
        })
        if ($matches.Count -eq 1) {
            $pilot = Join-Path $script:managerRoot 'tools\Invoke-MicrosoftBluetoothCabReadOnlyCheck.ps1'
            if (-not (Test-Path -LiteralPath $pilot -PathType Leaf)) {
                throw (L 'Модуль проверки Bluetooth CAB отсутствует в папке tools.' 'Bluetooth CAB audit module is missing from tools.')
            }
            Write-Host (L 'Дополнительная проверка: закреплённый Bluetooth CAB для PID_0026. Загрузка только после согласия, установки нет.' 'Additional check: pinned Bluetooth CAB for PID_0026. Download requires consent; nothing is installed.')
            if ($PrepareSignTool) { $cabAssessment = & $pilot -Language $script:uiLanguage -PrepareSignTool }
            else { $cabAssessment = & $pilot -Language $script:uiLanguage }
            if ($cabAssessment -and ($cabAssessment.CandidateVerdict -ne 'NO_NEWER_VERSION' -or
                $cabAssessment.CabHash -ne 'PASS' -or $cabAssessment.ArchiveInfLink -ne 'PASS' -or
                $cabAssessment.InstalledDeviceCheck -ne 'PASS' -or $cabAssessment.CandidateMatch -ne 'Exact')) {
                Write-Warning (L 'Закреплённый CAB не подтвердил совпадение версии; таблица остаётся основанной на обычных источниках.' 'Pinned CAB did not establish a matching version; the table retains its normal sources.')
                $cabAssessment = $null
            }
        } else {
            Write-Host (L 'Подходящее устройство Bluetooth PID_0026 не найдено; специальная проверка CAB пропущена.' 'No matching Bluetooth PID_0026 found; the CAB check was skipped.')
        }
    }
    $results = foreach ($device in $devices) {
        $kind = switch ($device.DeviceClass.ToUpperInvariant()) {
            'NET' { 'WiFi' }
            'BLUETOOTH' { 'Bluetooth' }
            'DISPLAY' { 'Graphics' }
        }
        $available = $null
        $installed = $null
        $localKey = ''
        $sourceLabel = ''
        $note = ''
        if ($kind -eq 'Graphics') {
            if (Test-GraphicsPackageMatch $processor $device $os) {
                $available = $graphicsVersion
                $sourceLabel = "$($graphicsCandidate.Source) (Intel Graphics $graphicsVersion)"
                $note = "$($graphicsCandidate.Detail) "
                if ($graphicsCandidate.Catalogue) { $note += (L "Дата проверки записи: $($graphicsCandidate.ReviewedOn). " "Entry reviewed: $($graphicsCandidate.ReviewedOn). ") }
                $note += (L 'Наличие более нового выпуска онлайн не проверяется. Совместимость с конкретным ПК окончательно проверит установщик Intel; на ноутбуке учитывайте драйвер производителя.' 'Newer online releases are not checked. Intel setup makes the final device compatibility decision; consider the laptop OEM driver.')
            } elseif (Test-Graphics6thGenReference $processor $device $os) {
                $sourceLabel = "Intel 6th Gen historical reference $graphics6thReferenceVersion : $graphics6thReferenceUri"
                $note = L 'Шестое поколение: пакет Intel 31.0.101.2115 — архивный ориентир, не подтверждённое обновление для этой Windows. Установка не предлагается.' '6th Gen: Intel 31.0.101.2115 is a historical reference, not a verified update for this Windows version. No installation is offered.'
            } else {
                $family = Get-GraphicsReferenceFamily $processor $device $os
                if ($family -eq 'Core11to14') {
                    $sourceLabel = $graphics11to14ReferenceUri
                    $note = L 'Графика Core 11–14 поколений: определена ветка Intel для ручной проверки. Совместимость и версия пакета для этого ID пока не подтверждены; установка отключена.' 'Core 11th–14th Gen graphics: identified an Intel family for manual review. Package compatibility and version for this ID are unverified; installation is disabled.'
                } elseif ($family -eq 'ArcUltra') {
                    $sourceLabel = $graphicsArcReferenceUri
                    $note = L 'Графика Arc/Core Ultra: определена ветка Intel для ручной проверки. Конкретный пакет и версия для этого ID пока не подтверждены; установка отключена.' 'Arc/Core Ultra graphics: identified an Intel family for manual review. The package and version for this ID are unverified; installation is disabled.'
                }
            }
        } else {
            $key = Get-DriverCatalogueKey $device $kind
            $localKey = Get-LocalWirelessKey $device $kind
            if ($localKey -and $localCatalogue.ContainsKey($localKey)) {
                $entry = $localCatalogue[$localKey]
                $sourceLabel = "$($entry.Source) ($($entry.Checked); local snapshot)"
                if ((Get-Date).Date -le ([datetime]::ParseExact($entry.Checked, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).AddDays(30)) {
                    $available = $entry.Version
                    $note = L 'Источник — сохранённые данные Intel. Более новые выпуски после указанной даты здесь не проверяются.' 'Source: saved Intel data. Releases after the stated date are not checked here.'
                } else {
                    $note = L 'Локальный снимок старше 30 дней; сравнение версий отключено до повторной проверки каталога.' 'Local snapshot is older than 30 days; version comparison is disabled until the catalogue is reviewed.'
                }
                if ($kind -eq 'WiFi') {
                    $note += L ' ID устройства совпал с сохранённым INF; совместимость будущего пакета не подтверждена.' ' Device ID matches the saved INF; compatibility of a future package is unverified.'
                }
            } elseif ($key -and $catalogues.ContainsKey($kind) -and $catalogues[$kind].ContainsKey($key)) {
                $available = $catalogues[$kind][$key]
                $sourceLabel = if ($kind -eq 'WiFi') { $wifiCatalogueUri } else { $bluetoothCatalogueUri }
            }
        }
        if ($kind -eq 'Bluetooth' -and $cabAssessment -and
            $device.DeviceID -like 'USB\VID_8087&PID_0026*') {
            $available = [version]$cabAssessment.CandidateInfVersion
            $sourceLabel = 'download.windowsupdate.com (pinned CAB SHA-256; checked ' + (Get-Date -Format 'yyyy-MM-dd') + ')'
            $note = L 'Для точного ID проверены версия, байты INF в CAB и подпись CAT. Этот CAB не доказывает отсутствие более новых выпусков. Установка не выполнялась.' 'Version, INF bytes in CAB and CAT signature were checked for the exact ID. This CAB does not rule out newer releases. Nothing was installed.'
            if ($cabAssessment.InfCatalogMembership -eq 'PASS') {
                $note += L ' SignTool подтвердил принадлежность INF извлечённому CAT.' ' SignTool confirmed INF membership in the extracted CAT.'
            } else {
                $note += L ' Принадлежность INF извлечённому CAT не проверена; для этого нужен SignTool.' ' INF membership in the extracted CAT is unverified; SignTool is needed.'
            }
        }
        $status = L 'Не удалось определить' 'Unknown'
        try {
            $installed = [version]$device.DriverVersion
            if ($available) {
                if ($installed -lt $available) { $status = L 'Доступно обновление' 'Update available' }
                elseif ($installed -eq $available) { $status = L 'Версия совпадает' 'Version matches' }
                else { $status = L 'Установлена более новая версия' 'Newer version installed' }
            }
        } catch { }
        if ($kind -in @('WiFi', 'Bluetooth') -and $available -and $installed -and
            $installed -lt $available -and
            $sourceLabel -in @($wifiCatalogueUri, $bluetoothCatalogueUri)) {
            $status = L 'Требуется ручная проверка' 'Manual review needed'
            $note += L ' Более высокая версия указана в сторонней таблице. Конкретный пакет, точный ID, подпись и применимость к этому ПК ещё не проверены; запуск обновления по одному этому значению не предлагается.' 'A higher version is listed in a third-party table. The exact package, device ID, signature and suitability for this PC have not been checked; this value alone does not trigger an update recommendation.'
        }
        if ($kind -eq 'WiFi' -and $localKey -and $available -and $installed -lt $available) {
            $status = L 'Требуется ручная проверка' 'Manual review needed'
        }
        if ($note -and $kind -eq 'Graphics' -and -not $available) {
            $status = L 'Требуется ручная проверка' 'Manual review needed'
            if ($sourceLabel -like "*762755*") { try {
                if ([version]$device.DriverVersion -gt $graphics6thReferenceVersion) {
                    $note += L ' Установленная версия новее архивного ориентира; актуальность драйвера этим не подтверждается.' ' Installed version is newer than the historical reference; this does not establish that the driver is current.'
                }
            } catch { } }
        }
        [PSCustomObject]@{
            Type = $kind
            Device = $device.DeviceName
            Installed = $device.DriverVersion
            Available = if ($available) { [string]$available } else { '-' }
            Status = $status
            Source = $sourceLabel
            Note = $note
        }
    }
    if (Get-Command Write-ManagerStage -ErrorAction SilentlyContinue) {
        Write-ManagerStage -Number 2 -Total 2 -Title (L 'Результаты по устройствам' 'Results by device') -Language $script:uiLanguage
    }
    if (@($results).Count -eq 0) { Write-Host (L 'Устройства Intel Wi-Fi, Bluetooth или Graphics не обнаружены.' 'No Intel Wi-Fi, Bluetooth or Graphics devices found.') }
    else {
        $width = 120
        try { $width = $Host.UI.RawUI.WindowSize.Width } catch { }
        if ($width -lt 95) {
            foreach ($result in $results) {
                Write-Host ''
                Write-Host "$($result.Type): $($result.Device)" -ForegroundColor Cyan
                Write-Host (L "Установлено: $($result.Installed); в источнике: $($result.Available)." "Installed: $($result.Installed); source version: $($result.Available).")
                Write-Host (L "Результат: $($result.Status)" "Result: $($result.Status)")
            }
        } elseif ($script:uiLanguage -eq 'ru') {
            $results | Format-Table @{Label='Тип';Expression={$_.Type}}, @{Label='Устройство';Expression={$_.Device}}, @{Label='Установлено';Expression={$_.Installed}}, @{Label='В источнике';Expression={$_.Available}}, @{Label='Результат';Expression={$_.Status}} -AutoSize -Wrap
        } else {
            $results | Format-Table Type, Device, Installed, Available, Status -AutoSize -Wrap
        }
    }
    foreach ($result in $results) {
        if (Get-Command Write-ManagerStatus -ErrorAction SilentlyContinue) {
            $uiCode = if ($result.Status -eq (L 'Версия совпадает' 'Version matches') -and $cabAssessment -and $result.Type -eq 'Bluetooth' -and $result.Source -like 'download.windowsupdate.com*') { 'Pass' }
                elseif ($result.Status -eq (L 'Версия совпадает' 'Version matches')) { 'Advisory' }
                elseif ($result.Status -in @((L 'Доступно обновление' 'Update available'), (L 'Требуется ручная проверка' 'Manual review needed'))) { 'Review' }
                else { 'Skip' }
            $statusText = if ($uiCode -eq 'Advisory' -and $result.Status -eq (L 'Версия совпадает' 'Version matches')) { L 'Версия совпала со справочным источником; наличие новых выпусков не проверено.' 'Version matches an advisory source; newer releases were not checked.' } else { $result.Status }
            Write-ManagerStatus -Code $uiCode -Message "$($result.Device): $statusText" -Language $script:uiLanguage
        }
        if ($result.Source) { Write-Host "$($result.Type): $($result.Source)" }
        if ($result.Note) { Write-Host "$($result.Device): $($result.Note)" -ForegroundColor Yellow }
        if ($result.Status -eq (L 'Доступно обновление' 'Update available')) {
            if ($result.Type -eq 'Graphics') {
                Write-Host (L "Следующий шаг для $($result.Device): запустите этот файл с параметром -Graphics. Программа запросит согласие на скачивание и установку; заранее сохраните документы. На ноутбуке сначала сравните вариант драйвера производителя устройства." "Next for $($result.Device): run this file with -Graphics. The manager asks permission before download and installation; save your work first. On a laptop, compare the computer manufacturer's driver first.")
            } else {
                Write-Host (L "Следующий шаг для $($result.Device): запустите этот файл без параметров. Базовая утилита проверит совместимость и запросит подтверждение; Wi-Fi и Bluetooth проверяются вместе." "Next for $($result.Device): run this file without parameters. The base utility checks compatibility and asks for confirmation; Wi-Fi and Bluetooth are checked together.")
            }
        } elseif ($result.Status -eq (L 'Установлена более новая версия' 'Newer version installed')) {
            Write-Host (L "$($result.Device): установленная версия новее значения источника; откат не требуется." "$($result.Device): installed version exceeds the source value; no downgrade is needed.")
        } else {
            Write-Host (L "$($result.Device): автоматическое обновление не предлагается. Сверьте точную модель ПК, ID устройства и вашу Windows с документацией производителя ПК и указанным источником Intel." "$($result.Device): automatic update is not offered. Check the exact computer model, device ID and Windows version against the computer manufacturer's guidance and the listed Intel source.") -ForegroundColor Yellow
        }
    }
    if ($otherWireless.Count) {
        Write-Host (L 'Беспроводные устройства других производителей:' 'Wireless devices from other manufacturers:') -ForegroundColor Cyan
        $otherWireless | Select-Object DeviceClass, DeviceName, DriverVersion | Format-Table -AutoSize -Wrap
        Write-Host (L 'Это оборудование другого производителя. Обновления для него здесь не проверяются; установка не предлагается. При необходимости используйте поддержку производителя ПК.' 'These devices are from other manufacturers. Their updates are not checked here, and no installation is offered. Consult the computer manufacturer if needed.') -ForegroundColor Yellow
    }
    if (@($results).Count -eq 0) {
        Write-Host (L 'Итог: подходящих устройств Intel нет; сравнение версий и поиск кандидатов не выполнялись.' 'Summary: no supported Intel devices found; no version comparison or candidate search was performed.') -ForegroundColor Cyan
        return
    }
    Show-LocalCandidateChecks $devices $os
    $matchedCount = @($results | Where-Object { $_.Status -eq (L 'Версия совпадает' 'Version matches') }).Count
    $newerCount = @($results | Where-Object { $_.Status -eq (L 'Доступно обновление' 'Update available') }).Count
    $manualCount = @($results | Where-Object { $_.Status -eq (L 'Требуется ручная проверка' 'Manual review needed') }).Count
    $unknownCount = @($results | Where-Object { $_.Status -eq (L 'Не удалось определить' 'Unknown') }).Count
    Write-Host (L "Итог: совпадений с источниками — $matchedCount; кандидатов с более высокой версией — $newerCount; нужна ручная проверка — $manualCount; версия не определена — $unknownCount." "Summary: versions matching sources: $matchedCount; candidates with a higher version: $newerCount; manual review: $manualCount; version unknown: $unknownCount.") -ForegroundColor Cyan
    Write-Host (L 'Сравнение выполнено с доступными источниками. Новые выпуски Intel вне этих источников могут существовать.' 'This compares against available sources; it is not a complete search for all new Intel releases. Matching versions do not prove that no newer update exists.') -ForegroundColor Yellow
    if ($cabAssessment) {
        Write-Host (L 'Bluetooth PID_0026: версия сопоставлена с закреплённым CAB, проверенным в этом запуске; другие Bluetooth ID используют справочные источники. Состояние проверки связи INF/CAT показано в строке устройства. Wi-Fi использует локальный снимок или таблицу стороннего проекта. Установка Wi-Fi/Bluetooth пока зависит от базовой утилиты. Чипсет, BIOS и микрокод не проверяются.' 'Bluetooth PID_0026: version compared with the pinned CAB checked in this run; other Bluetooth IDs use advisory sources. INF/CAT membership status is shown for the device. Wi-Fi uses a local snapshot or third-party table. Wi-Fi/Bluetooth installation still depends on the base tool. Chipset, BIOS and microcode are not checked.') -ForegroundColor Yellow
    } else {
    Write-Host (L 'Wi-Fi/Bluetooth: используются сохранённые данные и справочные таблицы стороннего проекта. Актуальность и совместимость пакета не подтверждены. Установка выполняется отдельной базовой утилитой. Чипсет, BIOS и микрокод не проверяются.' 'Wi-Fi/Bluetooth: saved data and third-party reference tables are used. Package freshness and compatibility are unverified. Installation uses the separate base tool. Chipset, BIOS and microcode are not checked.') -ForegroundColor Yellow
    }
}

function Update-IntelGraphics {
    if ($Silent) { throw (L 'Режим графики требует интерактивного подтверждения; не используйте -Silent.' 'Graphics updates require interactive confirmation; do not use -Silent.') }
    Write-Host (L 'Этап 1/5. Проверка процессора, Windows и графического устройства Intel.' 'Step 1/5. Processor, Windows, and Intel graphics check.') -ForegroundColor Cyan
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
        $graphicsCache = New-ManagerWorkDirectory
        $installerPath = [IO.Path]::Combine($graphicsCache, 'gfx_win_101.2145.exe')
        Write-Host (L "Проверка ранее загруженного пакета: $installerPath" "Previously downloaded package check: $installerPath")
        if (-not [IO.File]::Exists($installerPath) -or
            (Get-FileHash -LiteralPath $installerPath -Algorithm SHA512).Hash -ne $graphicsSha512) {
            if ((Read-Host (L "Скачать Intel Graphics $graphicsVersion с downloadmirror.intel.com (около 278 МБ) во временную папку этого запуска? (Y/N)" "Download Intel Graphics $graphicsVersion from downloadmirror.intel.com (about 278 MB) into this run's temporary folder? (Y/N)")) -notmatch '^[Yy]$') {
                Write-Host (L 'Загрузка отменена. Изменений нет.' 'Download declined. Nothing was changed.')
                return
            }
            [IO.Directory]::CreateDirectory($graphicsCache) | Out-Null
            $staging = [IO.Path]::Combine($graphicsCache, [guid]::NewGuid().ToString('N') + '.exe')
            try {
                Write-Host (L "Загрузка файла с официального адреса: $graphicsUri" "Downloading from the official URL: $graphicsUri")
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
                Write-Host (L "Проверенный пакет сохранён до завершения работы: $installerPath" "Verified package retained until this run finishes: $installerPath")
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
    Write-Host (L 'Запуск установщика Intel. После его закрытия проверка продолжится.' 'Intel installer is starting. The check will continue after it closes.')
    $process = Start-Process -FilePath $installer.FullName -Wait -PassThru
    Write-Host (L "Этап 4/5. Установщик закрыт, код: $($process.ExitCode). Повторная проверка версии драйвера в Windows." "Step 4/5. Installer closed with exit code $($process.ExitCode). Driver version is being checked in Windows again.")
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
    if ($PrepareSignTool -and -not $VerifyBluetoothCab) { throw (L 'Параметр -PrepareSignTool требует -VerifyBluetoothCab.' 'PrepareSignTool requires VerifyBluetoothCab.') }
    if ($VerifyBluetoothCab -and -not $CheckUpdates) { throw (L 'Параметр -VerifyBluetoothCab требует -CheckUpdates.' 'VerifyBluetoothCab requires CheckUpdates.') }
    if ($CandidateManifest -and -not $CheckUpdates) { throw (L 'Параметр -CandidateManifest требует -CheckUpdates.' 'CandidateManifest requires CheckUpdates.') }
    if ($CheckUpdates) {
        if ($Inventory -or $Graphics -or $Silent -or $GraphicsInstallerPath) { throw (L 'Параметр -CheckUpdates используется отдельно от других режимов.' 'Use -CheckUpdates separately from other modes.') }
        Show-UpdateCheck
        Exit-Manager 0
    }
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
        Write-Host (L 'Запрос прав администратора. Запись журнала продолжится в процессе с повышенными правами.' 'Administrator rights requested. The elevated process will continue the log.')
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
        Write-Host (L 'Для поиска базовой утилиты в PowerShell Gallery нужен поставщик NuGet для PowerShellGet. Он будет добавлен только для текущего пользователя; это не драйвер и не установщик Windows. Если отказаться, поиск пакета и этот режим работы завершатся.' 'PowerShellGet needs the NuGet provider to find the base utility in PowerShell Gallery. It is added for the current user only; it is not a driver or Windows installer. Declining ends package lookup and this mode.')
        if (-not $Silent -and (Read-Host (L 'Добавить поставщик NuGet для текущего пользователя? (Y/N)' 'Add the NuGet provider for this user? (Y/N)')) -notmatch '^[Yy]$') {
            Stop-Manager (L 'Добавление NuGet отменено.' 'NuGet provider setup declined.')
        }
        Write-Host (L 'Этап 2/4. Добавляю поставщик NuGet для PowerShellGet.' 'Step 2/4. Adding the NuGet provider for PowerShellGet.')
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    # Find-Script проверяет метаданные записи PSGallery; это не криптографическая подпись.
    Write-Host (L 'Этап 2/4. Проверка версии, автора и страницы проекта базовой утилиты в PSGallery.' 'Step 2/4. Base tool version, author, and project URL check in PSGallery.')
    $available = Find-Script -Name $updaterName -Repository PSGallery
    Test-PackageIdentity $available
    Write-Host (L "Подтверждён пакет $($available.Name) версии $($available.Version), автор $($available.Author)." "Package verified: $($available.Name), version $($available.Version), author $($available.Author).")
    # Собственное хранилище не зависит от перенесённых записей InstalledLocation.
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw (L 'Не удалось определить локальную папку данных пользователя.' 'Cannot locate the local application data folder.')
    }
    $cachePath = New-ManagerWorkDirectory
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

    Write-Host (L 'Базовая утилита — отдельный скрипт FirstEverTech из PowerShell Gallery. Она нужна только для установки Wi-Fi/Bluetooth, пока собственный модуль установки не готов. Загрузка во временную папку сама по себе не меняет драйверы; после запуска утилита выполняет собственную проверку совместимости.' 'The base utility is a separate FirstEverTech script from PowerShell Gallery. It is used only for Wi-Fi/Bluetooth installation until the native installer module is ready. Downloading it to a temporary folder does not change drivers; after launch, the utility performs its own compatibility checks.')
    Write-Host (L 'Имя автора, адрес проекта и версия сверяются с метаданными PSGallery и скачанного файла. Эти метаданные не являются цифровой подписью или независимым доказательством происхождения кода. Перед запуском будет отдельное подтверждение; автоматический режим -Silent подтверждений не запрашивает.' 'Author name, project URL and version are compared with PSGallery metadata and the downloaded file. These fields are not a digital signature or independent proof of code origin. A separate launch confirmation follows; -Silent does not prompt.')
    if ($needsDownload) {
        Write-Host (L 'Этап 3/4. Локальная копия отсутствует или отличается от версии в PSGallery.' 'Step 3/4. The cached copy is missing or differs from the PSGallery version.')
        if (-not $Silent -and (Read-Host (L "Скачать базовую утилиту $($available.Version) во временную папку $cachePath? (Y/N)" "Download base tool $($available.Version) into temporary folder $cachePath? (Y/N)")) -notmatch '^[Yy]$') {
            Stop-Manager (L 'Загрузка отменена.' 'Download declined.')
        }
        [IO.Directory]::CreateDirectory($cachePath) | Out-Null
        $staging = [IO.Path]::Combine($cachePath, [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($staging) | Out-Null
        try {
            Write-Host (L "Загрузка базовой утилиты $($available.Version) во временную папку." "Base tool $($available.Version) is being downloaded to the temporary folder.")
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
        Write-Host (L 'Этап 3/4. Локальная копия совпала по метаданным; повторная загрузка не нужна.' 'Step 3/4. The local copy matches metadata; no download is needed.')
    }
    if (-not $Silent) {
        if ((Read-Host (L 'Запустить скрипт FirstEverTech? Его интерактивный режим отдельно спросит согласие перед установкой драйверов. (Y/N)' 'Run the FirstEverTech script? Its interactive mode asks separately before installing drivers. (Y/N)')) -notmatch '^[Yy]$') {
            Stop-Manager (L 'Запуск базовой утилиты отменён; драйверы не изменены.' 'Base utility launch declined; drivers were not changed.')
        }
    }
    if ($Silent) {
        Write-Host (L 'Этап 4/4. Запуск базовой утилиты в режиме -auto. Её экраны и сообщения отображаются на английском.' 'Step 4/4. Base tool starts in automatic -auto mode. Its screens and messages are in English.') -ForegroundColor Cyan
    } else {
        Write-Host (L 'Этап 4/4. Запуск базовой утилиты. Её экраны отображаются на английском; перед установкой она запросит согласие.' 'Step 4/4. Base tool starts. Its screens are in English; it will ask for confirmation before installation.') -ForegroundColor Cyan
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
