<#
.SYNOPSIS
    Менеджер Wi-Fi и Bluetooth Intel – автоматическая проверка и обновление драйверов.
.DESCRIPTION
    Скрипт определяет адаптеры Intel Wi-Fi и Bluetooth, сравнивает текущие версии с актуальными
    из официальных источников и устанавливает обновления.
.PARAMETER Silent
    Запуск в тихом режиме (без запросов к пользователю). Все обновления устанавливаются автоматически.
.EXAMPLE
    .\IntelWiFiBTManager.ps1
    Интерактивный режим.
.EXAMPLE
    .\IntelWiFiBTManager.ps1 -Silent
    Автоматическая установка обновлений без вопросов.
#>
param([switch]$Silent)

# =============================================
# МЕНЕДЖЕР WI-FI И BLUETOOTH INTEL
# Версия: 1.9 (исправления для тихого режима)
# =============================================

# --- 1. ИНФОРМАЦИОННОЕ СООБЩЕНИЕ ---
if (-not $Silent) {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "   МЕНЕДЖЕР WI-FI И BLUETOOTH INTEL" -ForegroundColor Cyan
    Write-Host "   Версия 1.9" -ForegroundColor Gray
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Назначение: автоматическая проверка и установка"
    Write-Host "актуальных драйверов для беспроводных адаптеров Intel."
    Write-Host ""
    Write-Host "Будут проверены и при необходимости обновлены:"
    Write-Host "  • Wi-Fi адаптер (любая модель Intel, поддерживаемая утилитой)"
    Write-Host "  • Bluetooth адаптер (любая модель Intel)"
    Write-Host ""
    Write-Host "Для работы скрипта требуются права администратора."
    Write-Host "Это необходимо для установки драйверов и создания"
    Write-Host "точки восстановления системы."
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
}

# --- 2. ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА ---
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    if ($Silent) {
        Write-Error "Критическая ошибка: Недостаточно прав для работы в тихом режиме."
        exit 1
    } else {
        Write-Host "Для установки драйверов требуются права администратора." -ForegroundColor Yellow
        $response = Read-Host "Перезапустить скрипт с правами администратора? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Wait
        }
        exit
    }
}

# --- 3. ФУНКЦИЯ ПРОВЕРКИ ИНТЕРНЕТА ---
function Test-InternetConnection {
    Write-Host "Проверка подключения к интернету..." -ForegroundColor Gray
    if (-not (Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Host "Интернет-соединение отсутствует." -ForegroundColor Red
        Write-Host "Для работы скрипта требуется доступ к интернету." -ForegroundColor Yellow
        if ($Silent) {
            Write-Error "Тихий режим: выход из-за отсутствия интернета."
            exit 1
        } else {
            $continue = Read-Host "Продолжить без интернета? (Y/N)"
            if ($continue -ne 'Y' -and $continue -ne 'y') { exit }
        }
        return $false
    }
    Write-Host "Интернет доступен." -ForegroundColor Green
    return $true
}

# --- 4. ФУНКЦИЯ ВЫВОДА АДАПТЕРОВ И ПРОВЕРКИ НАЛИЧИЯ INTEL ---
function Show-WirelessAdaptersInfo {
    Write-Host "`n--- Обнаруженные беспроводные адаптеры ---" -ForegroundColor Cyan
    Write-Host "Сканирование устройств..." -ForegroundColor Gray

    $adapters = Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        ($_.DeviceName -match "Wi-Fi|Wireless|Bluetooth") -and
        ($_.DeviceName -notmatch "Virtual|VPN|WAN|Miniport|Kernel|Debug|Loopback")
    }

    if (-not $adapters) {
        Write-Host "Беспроводные адаптеры не обнаружены." -ForegroundColor Yellow
        Write-Host "Возможно, у вас нет Wi-Fi или Bluetooth адаптеров," -ForegroundColor Yellow
        Write-Host "или они отключены в BIOS/Диспетчере устройств." -ForegroundColor Yellow
        Write-Host "`nСкрипт предназначен для систем с адаптерами Intel." -ForegroundColor Red
        if (-not $Silent) {
            Read-Host "`nНажмите Enter для выхода"
        }
        exit 1
    }

    Write-Host "Найдено $($adapters.Count) адаптеров.`n" -ForegroundColor Gray

    $table = @()
    foreach ($adapter in $adapters) {
        $type = if ($adapter.DeviceName -match "Bluetooth") { "Bluetooth" } else { "Wi-Fi" }
        $manufacturer = if ($adapter.Manufacturer -match "Intel") { "Intel" } else { $adapter.Manufacturer }
        $table += [PSCustomObject]@{
            "Имя" = $adapter.DeviceName
            "Производитель" = $manufacturer
            "Тип" = $type
            "Версия драйвера" = $adapter.DriverVersion
        }
    }

    Write-Host ("{0,-35} {1,-20} {2,-10} {3}" -f "Имя", "Производитель", "Тип", "Версия драйвера") -ForegroundColor Gray
    Write-Host ("{0,-35} {1,-20} {2,-10} {3}" -f "----", "-------------", "----", "---------------") -ForegroundColor Gray
    foreach ($row in $table) {
        $color = if ($row.Производитель -match "Intel") { "Green" } else { "Gray" }
        Write-Host ("{0,-35} {1,-20} {2,-10} {3}" -f $row.Имя, $row.Производитель, $row.Тип, $row."Версия драйвера") -ForegroundColor $color
    }

    Write-Host ""

    $hasIntel = $table | Where-Object { $_.Производитель -match "Intel" }
    if (-not $hasIntel) {
        Write-Host "Адаптеры Intel не обнаружены." -ForegroundColor Red
        Write-Host "Данный скрипт предназначен только для адаптеров Intel." -ForegroundColor Yellow
        Write-Host "Завершение работы." -ForegroundColor Gray
        if (-not $Silent) {
            Read-Host "`nНажмите Enter для выхода"
        }
        exit 1
    } else {
        Write-Host "Обнаружены адаптеры Intel. Продолжаем проверку..." -ForegroundColor Green
        return $true
    }
}

# --- 5. ФУНКЦИЯ ПРОВЕРКИ И УСТАНОВКИ NUGET ---
function Ensure-NuGetProvider {
    Write-Host "`n--- Установка компонентов ---" -ForegroundColor Cyan
    Write-Host "Проверка наличия поставщика NuGet..." -ForegroundColor Gray
    $provider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $provider) {
        Write-Host "Поставщик NuGet не найден. Устанавливаю..." -ForegroundColor Yellow
        try {
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop
            Write-Host "NuGet успешно установлен." -ForegroundColor Green
        } catch {
            Write-Host "ОШИБКА: Не удалось установить NuGet." -ForegroundColor Red
            Write-Host "Попробуйте выполнить вручную от администратора:" -ForegroundColor Yellow
            Write-Host "  Install-PackageProvider -Name NuGet -Force -Scope CurrentUser" -ForegroundColor Yellow
            if (-not $Silent) { Read-Host "Нажмите Enter для выхода" }
            exit 1
        }
    } else {
        Write-Host "NuGet уже установлен." -ForegroundColor Green
    }
    try {
        Write-Host "Обновляю NuGet до последней версии..." -ForegroundColor Gray
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction Stop
        Write-Host "NuGet обновлён." -ForegroundColor Green
    } catch {
        Write-Host "Не удалось обновить NuGet (продолжаем с текущей версией)." -ForegroundColor Yellow
    }
}

# --- 6. ФУНКЦИЯ ПРОВЕРКИ УСТАНОВКИ/ОБНОВЛЕНИЯ УТИЛИТЫ ---
function Ensure-UpdaterInstalled {
    $updaterName = "universal-intel-wifi-bt-driver-updater"
    $installed = Get-InstalledScript -Name $updaterName -ErrorAction SilentlyContinue
    
    if (-not $installed) {
        Write-Host "`nУтилита для обновления Wi-Fi и Bluetooth не найдена." -ForegroundColor Yellow
        if ($Silent) {
            Write-Host "Тихий режим: устанавливаю утилиту автоматически..." -ForegroundColor Gray
            try {
                Install-Script -Name $updaterName -Force -Scope CurrentUser -ErrorAction Stop
                Write-Host "Утилита успешно установлена." -ForegroundColor Green
                return $true
            } catch {
                Write-Error "Не удалось установить утилиту."
                exit 1
            }
        } else {
            $installResponse = Read-Host "Установить её сейчас? (Y/N)"
            if ($installResponse -eq 'Y' -or $installResponse -eq 'y') {
                Write-Host "Устанавливаю $updaterName ..." -ForegroundColor Cyan
                try {
                    Install-Script -Name $updaterName -Force -Scope CurrentUser -ErrorAction Stop
                    Write-Host "Утилита успешно установлена." -ForegroundColor Green
                    return $true
                } catch {
                    Write-Host "ОШИБКА: Не удалось установить утилиту." -ForegroundColor Red
                    Write-Host "Попробуйте выполнить вручную от администратора:" -ForegroundColor Yellow
                    Write-Host "  Install-Script -Name $updaterName -Force" -ForegroundColor Yellow
                    Read-Host "Нажмите Enter для выхода"
                    exit 1
                }
            } else {
                Write-Host "Установка отменена. Работа скрипта невозможна без этой утилиты." -ForegroundColor Red
                Read-Host "Нажмите Enter для выхода"
                exit 1
            }
        }
    }

    # Проверка версии утилиты
    try {
        $installedVersion = $installed.Version
        Write-Host "`nУстановленная версия утилиты: $installedVersion" -ForegroundColor Gray
        $latestInfo = Find-Script -Name $updaterName -ErrorAction Stop
        $latestVersion = $latestInfo.Version
        Write-Host "Доступная версия утилиты: $latestVersion" -ForegroundColor Gray
        if ($installedVersion -lt $latestVersion) {
            Write-Host "`nДоступно обновление утилиты." -ForegroundColor Yellow
            if ($Silent) {
                Write-Host "Тихий режим: обновляю утилиту автоматически..." -ForegroundColor Gray
                Update-Script -Name $updaterName -Force -ErrorAction Stop
                Write-Host "Утилита обновлена до версии $latestVersion." -ForegroundColor Green
            } else {
                $updateResponse = Read-Host "Обновить утилиту до версии $latestVersion? (Y/N)"
                if ($updateResponse -eq 'Y' -or $updateResponse -eq 'y') {
                    Write-Host "Обновляю утилиту..." -ForegroundColor Cyan
                    Update-Script -Name $updaterName -Force -ErrorAction Stop
                    Write-Host "Утилита обновлена до версии $latestVersion." -ForegroundColor Green
                } else {
                    Write-Host "Обновление утилиты пропущено." -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "Утилита актуальна." -ForegroundColor Green
        }
    } catch {
        Write-Host "Не удалось проверить версию утилиты: $_" -ForegroundColor Yellow
        Write-Host "Продолжаем с текущей версией." -ForegroundColor Gray
    }
    return $true
}

# --- 7. ФУНКЦИЯ ПОЛУЧЕНИЯ ТЕКУЩИХ ВЕРСИЙ ---
function Get-CurrentVersions {
    $result = @{}
    $wifi = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match "Wi-Fi" -and $_.Manufacturer -like "*Intel*" } | Select-Object -First 1
    $result["WiFi_Current"] = if ($wifi) { $wifi.DriverVersion } else { "не найден" }
    $bt = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -match "Bluetooth" -and $_.Manufacturer -like "*Intel*" } | Select-Object -First 1
    $result["BT_Current"] = if ($bt) { $bt.DriverVersion } else { "не найден" }
    return $result
}

# --- 8. ФУНКЦИЯ ПОЛУЧЕНИЯ ПОСЛЕДНИХ ВЕРСИЙ (JSON + FALLBACK) ---
function Get-LatestInfoFromUpdater {
    $updaterName = "universal-intel-wifi-bt-driver-updater"
    $updaterPath = (Get-InstalledScript -Name $updaterName).InstalledLocation
    if (-not $updaterPath) {
        Write-Host "Не удалось найти путь к утилите." -ForegroundColor Red
        return $null
    }
    $updaterFullPath = Join-Path -Path $updaterPath -ChildPath "$updaterName.ps1"
    if (-not (Test-Path $updaterFullPath)) {
        Write-Host "Файл утилиты не найден: $updaterFullPath" -ForegroundColor Red
        return $null
    }

    Write-Host "Запускаю утилиту для получения информации о драйверах..." -ForegroundColor Gray

    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        # Сначала пытаемся получить JSON-вывод
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$updaterFullPath`" -auto -json" -Wait -NoNewWindow -RedirectStandardOutput $tempFile
        $output = Get-Content -Path $tempFile -Raw
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }

    $result = @{}
    $jsonParsed = $false

    # Пытаемся разобрать JSON
    if ($output -match '^\s*\{') {
        try {
            $json = $output | ConvertFrom-Json
            if ($json -and $json.Devices) {
                foreach ($dev in $json.Devices) {
                    if ($dev.Type -eq "WiFi") {
                        $result["WiFi_Model"] = $dev.Name
                        $result["WiFi_Current"] = $dev.CurrentVersion
                        $result["WiFi_Latest"] = $dev.LatestVersion
                    } elseif ($dev.Type -eq "Bluetooth") {
                        $result["BT_Model"] = $dev.Name
                        $result["BT_Current"] = $dev.CurrentVersion
                        $result["BT_Latest"] = $dev.LatestVersion
                    }
                }
                if ($result.ContainsKey("WiFi_Latest") -or $result.ContainsKey("BT_Latest")) {
                    Write-Host "Информация получена в формате JSON." -ForegroundColor Green
                    $jsonParsed = $true
                }
            }
        } catch {
            Write-Host "Ошибка парсинга JSON, использую резервный метод." -ForegroundColor Yellow
        }
    }

    # --- РЕЗЕРВНЫЙ МЕТОД (регулярные выражения) ---
    if (-not $jsonParsed) {
        Write-Host "Использую резервный метод парсинга (регулярные выражения)." -ForegroundColor Yellow

        $wifiModelMatch = [regex]::Match($output, 'Chipset:\s*(Intel.*?Wi-Fi[^\n]+)')
        if ($wifiModelMatch.Success) {
            $result["WiFi_Model"] = $wifiModelMatch.Groups[1].Value.Trim()
        } else {
            $wifiModelMatch = [regex]::Match($output, 'Model:\s*(Intel.*?Wi-Fi[^\n]+)')
            if ($wifiModelMatch.Success) {
                $result["WiFi_Model"] = $wifiModelMatch.Groups[1].Value.Trim()
            } else {
                $result["WiFi_Model"] = "Intel Wi-Fi (модель не определена)"
            }
        }

        $btModelMatch = [regex]::Match($output, 'Device:\s*(Intel.*?Bluetooth[^\n]*)')
        if ($btModelMatch.Success) {
            $result["BT_Model"] = $btModelMatch.Groups[1].Value.Trim()
        } else {
            $btModelMatch = [regex]::Match($output, 'Chipset:\s*(Intel.*?Wi-Fi.*?\(CNVi\).*?)[\n\r]')
            if ($btModelMatch.Success) {
                $result["BT_Model"] = "Intel Wireless Bluetooth (модель не определена)"
            } else {
                $result["BT_Model"] = "Intel Bluetooth (модель не определена)"
            }
        }

        $matchesAll = [regex]::Matches($output, 'Current Version: ([\d.]+) ---> Latest Version: ([\d.]+)')
        if ($matchesAll.Count -ge 2) {
            $result["WiFi_Current"] = $matchesAll[0].Groups[1].Value
            $result["WiFi_Latest"] = $matchesAll[0].Groups[2].Value
            $result["BT_Current"] = $matchesAll[1].Groups[1].Value
            $result["BT_Latest"] = $matchesAll[1].Groups[2].Value
        } else {
            $wifiMatch = [regex]::Match($output, 'Wi-Fi.*?Current Version: ([\d.]+).*?Latest Version: ([\d.]+)')
            $btMatch = [regex]::Match($output, 'Bluetooth.*?Current Version: ([\d.]+).*?Latest Version: ([\d.]+)')
            if ($wifiMatch.Success) {
                $result["WiFi_Current"] = $wifiMatch.Groups[1].Value
                $result["WiFi_Latest"] = $wifiMatch.Groups[2].Value
            }
            if ($btMatch.Success) {
                $result["BT_Current"] = $btMatch.Groups[1].Value
                $result["BT_Latest"] = $btMatch.Groups[2].Value
            }
        }
    }

    if ($result.ContainsKey("WiFi_Latest") -or $result.ContainsKey("BT_Latest")) {
        Write-Host "Версии и модели успешно получены." -ForegroundColor Green
        return $result
    } else {
        Write-Host "Не удалось извлечь информацию из вывода утилиты." -ForegroundColor Red
        return $null
    }
}

# --- 9. ОСНОВНАЯ ЛОГИКА ---
# Проверка интернета
Test-InternetConnection | Out-Null

# Вывод адаптеров и проверка Intel
Show-WirelessAdaptersInfo | Out-Null

Write-Host "`n--- Подготовка к проверке драйверов ---" -ForegroundColor Cyan

Ensure-NuGetProvider
Ensure-UpdaterInstalled | Out-Null

$current = Get-CurrentVersions

Write-Host "`n--- Получение информации о драйверах ---" -ForegroundColor Cyan
$info = Get-LatestInfoFromUpdater

if (-not $info) {
    Write-Host "Не удалось получить информацию о драйверах." -ForegroundColor Red
    Write-Host "Возможные причины:" -ForegroundColor Yellow
    Write-Host "  • Адаптеры Intel не обнаружены (проверьте Диспетчер устройств)." -ForegroundColor Yellow
    Write-Host "  • Утилита не поддерживает вашу модель адаптера." -ForegroundColor Yellow
    Write-Host "  • Проблемы с подключением к интернету." -ForegroundColor Yellow
    if (-not $Silent) { Read-Host "`nНажмите Enter для выхода" }
    exit 1
}

$wifiModel = if ($info.ContainsKey("WiFi_Model")) { $info["WiFi_Model"] } else { "Intel Wi-Fi" }
$btModel = if ($info.ContainsKey("BT_Model")) { $info["BT_Model"] } else { "Intel Bluetooth" }
$wifiCurrent = $current["WiFi_Current"]
$wifiLatest = $info["WiFi_Latest"]
$btCurrent = $current["BT_Current"]
$btLatest = $info["BT_Latest"]

# --- 10. ВЫВОД ТАБЛИЦЫ ---
Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "   СРАВНЕНИЕ ВЕРСИЙ ДРАЙВЕРОВ" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ("{0,-35} {1,-15} {2,-15} {3}" -f "УСТРОЙСТВО", "ТЕКУЩАЯ", "ДОСТУПНАЯ", "СТАТУС") -ForegroundColor Gray
Write-Host ("{0,-35} {1,-15} {2,-15} {3}" -f "---------", "--------", "---------", "------") -ForegroundColor Gray

if ($wifiCurrent -eq $wifiLatest) {
    $wifiStatus = "Актуален"
    $wifiColor = "Green"
} else {
    $wifiStatus = "Доступно обновление"
    $wifiColor = "Yellow"
}
Write-Host ("{0,-35} {1,-15} {2,-15} {3}" -f $wifiModel, $wifiCurrent, $wifiLatest, $wifiStatus) -ForegroundColor $wifiColor

if ($btCurrent -eq $btLatest) {
    $btStatus = "Актуален"
    $btColor = "Green"
} else {
    $btStatus = "Доступно обновление"
    $btColor = "Yellow"
}
Write-Host ("{0,-35} {1,-15} {2,-15} {3}" -f $btModel, $btCurrent, $btLatest, $btStatus) -ForegroundColor $btColor

Write-Host "=========================================" -ForegroundColor Cyan

# --- 11. ОБРАБОТКА ОБНОВЛЕНИЙ ---
$needUpdateWiFi = ($wifiCurrent -ne $wifiLatest)
$needUpdateBT = ($btCurrent -ne $btLatest)

if (-not $needUpdateWiFi -and -not $needUpdateBT) {
    Write-Host "`nВсе драйверы актуальны. Обновление не требуется." -ForegroundColor Green
    if (-not $Silent) { Read-Host "`nНажмите Enter для выхода" }
    exit 0
}

if (-not $Silent) {
    Write-Host "`nОбнаружены обновления для следующих драйверов:" -ForegroundColor Yellow
    if ($needUpdateWiFi) { Write-Host "  - $wifiModel (с $wifiCurrent на $wifiLatest)" -ForegroundColor Yellow }
    if ($needUpdateBT) { Write-Host "  - $btModel (с $btCurrent на $btLatest)" -ForegroundColor Yellow }
    $response = Read-Host "`nУстановить все обновления? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Установка отменена." -ForegroundColor Gray
        Read-Host "Нажмите Enter для выхода"
        exit 0
    }
} else {
    Write-Host "`nТихий режим: устанавливаю все доступные обновления..." -ForegroundColor Gray
}

# --- 12. ЗАПУСК УСТАНОВКИ ---
Write-Host "`n--- Запуск установки обновлений Wi-Fi и Bluetooth ---" -ForegroundColor Cyan
$updaterName = "universal-intel-wifi-bt-driver-updater"
$updaterPath = (Get-InstalledScript -Name $updaterName).InstalledLocation
$updaterFullPath = Join-Path -Path $updaterPath -ChildPath "$updaterName.ps1"
Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$updaterFullPath`" -auto" -Wait -NoNewWindow
Write-Host "Установка завершена." -ForegroundColor Green

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "Операция завершена." -ForegroundColor Green
Write-Host "Рекомендуется перезагрузить компьютер." -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Cyan

if (-not $Silent) { Read-Host "`nНажмите Enter для выхода" }
exit 0