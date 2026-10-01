# Проверки разработки

Команды выполняются из корня рабочей копии v2.2.0 preview в Windows PowerShell 5.1. Актуальный состав CI: [.github/workflows/windows-powershell.yml](../.github/workflows/windows-powershell.yml). Workflow запускается для pull request или вручную; одного push в произвольную ветку недостаточно.

## Синтаксис без выполнения

```powershell
$ErrorActionPreference = 'Stop'
$files = @((Get-Item .\IntelWiFiBTManager.ps1)) +
    @(Get-ChildItem .\tools, .\tests -Filter *.ps1 -File -Recurse)
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
```

Разбор синтаксиса не запускает установщики или сетевые операции. Он не заменяет проверку поведения.

## Безопасный набор CI

Это сценарии с подменами или временными данными; они не устанавливают драйверы и не перезагружают компьютер. В отличие от запуска всех файлов по маске, список ниже исключает интеграционные сценарии. Каждый тест запускается отдельным процессом, чтобы подмены команд не влияли на следующий тест.

```powershell
$tests = @(
    'tests\ConsoleUi.Tests.ps1',
    'tests\RestartPrompt.Tests.ps1',
    'tests\UpdateCheck.Tests.ps1',
    'tests\InfReport.Tests.ps1',
    'tests\InfCompare.Tests.ps1',
    'tests\PackageAudit.Tests.ps1',
    'tests\DriverCandidate.Tests.ps1',
    'tests\OfficialWifiCandidate.Tests.ps1',
    'tests\OfficialWifiDownload.Tests.ps1',
    'tests\OfficialBluetoothPackage.Tests.ps1',
    'tests\OfficialBluetoothDownload.Tests.ps1',
    'tests\MicrosoftBluetoothCab.Tests.ps1',
    'tests\LocalSignTool.Tests.ps1',
    'tests\WorkDirectory.Tests.ps1',
    'tests\DriverCatalogue.Tests.ps1'
)
foreach ($test in $tests) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $test
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $test ($LASTEXITCODE)" }
}
```

CI также выполняет `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\IntelWiFiBTManager.ps1 -Inventory -Language en`. Этот режим читает CIM и пишет локальный журнал.

Для точечной задачи сначала достаточно затронутых тестов: UI/подтверждения — ConsoleUi и RestartPrompt; версия/каталог — UpdateCheck и DriverCatalogue; разбор INF — InfReport и InfCompare; доверие пакету — PackageAudit и DriverCandidate. При изменении общих функций нужен полный набор CI.

## Ручная проверка интерфейса

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\IntelWiFiBTManager.ps1 -Inventory -Language ru
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\IntelWiFiBTManager.ps1 -CheckUpdates -Language ru
```

Проверить русский/английский язык, узкое окно, длинные названия, отсутствие Intel-устройств, неизвестное устройство, недоступный источник. `-CheckUpdates` может получать сетевые справочные таблицы; он не является полностью офлайн-режимом. Подробности визуального прогона и незавершённые пункты — в Issue #5.

Журнал подтверждает текст и код завершения, снимок — расположение и цвета. Перед публикацией журнала удалить персональные пути, имена ПК и идентификаторы. Зеленый CI не заменяет реальную проверку установки на подходящем ПК.

## Отдельные испытания, не входящие в безопасный набор

| Сценарий | Действия |
| --- | --- |
| `tests/LiveInstalledCandidate.ps1` | Читает реальное установленное устройство, создаёт временный ZIP из его INF, вызывает проверку. Локальный ZIP не доказывает происхождение выпуска Intel. |
| `tests/OfficialWifiArchive.Integration.ps1` | Без запроса скачивает закреплённый ZIP Intel и проверяет INF. Драйвер не устанавливает. |
| `tests/SignToolCab.Integration.ps1` | Подменяет ответ на Y, скачивает/сохраняет SignTool при необходимости, получает CAB и проверяет оригинальный и изменённый INF. Инструмент остаётся локально. |
| `tools/Invoke-*ReadOnlyCheck.ps1` | Предлагает загрузку реального пакета; проверка зависит от сети и, для части сценариев, оборудования. |
| Обычный менеджер, `-Graphics`, `-Silent` | Могут запускать установку, изменять систему; не использовать как автоматические тесты. |

Интеграционные сценарии запускаются осознанно под конкретную задачу. Реальное обновление или перезагрузка требуют отдельного задания владельца машины. В тесте перезагрузки системная команда должна оставаться подменённой.

## Среда без Windows

Можно редактировать файлы и проверять ссылки/JSON/изменения, но нельзя объявлять CIM, Authenticode, SignTool, UAC или Windows PowerShell 5.1 проверенными на Linux. Указать ограничение и использовать Windows CI. Не устанавливать пакет драйвера для проверки документации.
