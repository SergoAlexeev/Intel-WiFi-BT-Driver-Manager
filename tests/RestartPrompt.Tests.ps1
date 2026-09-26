# Запуск: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RestartPrompt.Tests.ps1
# Тест извлекает только две функции из менеджера; основной сценарий не запускается.
$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Синтаксическая ошибка в менеджере: $($parseErrors[0].Message)" }

foreach ($name in @('Test-GraphicsRestartEligible', 'Invoke-GraphicsRestartPrompt')) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($definition.Count -ne 1) { throw "Не найдена единственная функция $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function Assert-Equal($Actual, $Expected, [string]$Case) {
    if ($Actual -ne $Expected) { throw "Проверка '$Case' не пройдена: получено '$Actual', ожидалось '$Expected'." }
}

Assert-Equal (Test-GraphicsRestartEligible 1000 $true) $true 'версия подтверждена, код неизвестен'
foreach ($code in @(0, 2, 14, 3010)) {
    Assert-Equal (Test-GraphicsRestartEligible $code $false) $true "документированный код $code"
}
Assert-Equal (Test-GraphicsRestartEligible 1000 $false) $false 'неизвестный код без новой версии'

# Безусловно заменяем Restart-Computer в области теста. Системная команда не вызывается.
$script:answer = 'N'
$script:restartCalls = 0
$script:closeCalls = 0
function Read-Host { param([string]$Prompt) return $script:answer }
function Close-ManagerLog { $script:closeCalls++ }
function Restart-Computer { [CmdletBinding()] param() $script:restartCalls++ }

Assert-Equal (Invoke-GraphicsRestartPrompt) $false 'отказ от перезагрузки'
Assert-Equal $script:restartCalls 0 'отказ: нет команды перезагрузки'
Assert-Equal $script:closeCalls 0 'отказ: журнал открыт'

$script:answer = 'Y'
Assert-Equal (Invoke-GraphicsRestartPrompt) $true 'согласие на перезагрузку'
Assert-Equal $script:restartCalls 1 'согласие: вызвана подменённая команда'
Assert-Equal $script:closeCalls 1 'согласие: журнал закрыт'
Write-Host 'Проверки запроса перезагрузки пройдены; настоящая перезагрузка не вызывалась.' -ForegroundColor Green
