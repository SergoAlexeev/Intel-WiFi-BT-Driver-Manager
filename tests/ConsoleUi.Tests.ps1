$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\ConsoleUi.ps1')
$script:lines = New-Object System.Collections.ArrayList
function Write-Host {
    param([object]$Object, [string]$ForegroundColor, [switch]$NoNewline)
    [void]$script:lines.Add([pscustomobject]@{ Text=[string]$Object; Color=$ForegroundColor })
}
Write-ManagerStage -Number 2 -Total 4 -Title 'Проверка файла' -Detail 'Без установки.' -Language ru
Write-ManagerStatus -Code Pass -Message 'Хеш совпал.' -Language ru
Write-ManagerStatus -Code Advisory -Message 'Справочное совпадение.' -Language ru
Write-ManagerStatus -Code Review -Message 'Нужен SignTool.' -Language ru
Write-ManagerStatus -Code Reject -Message 'Хеш неверен.' -Language ru
Write-ManagerStatus -Code Skip -Message 'Загрузка отклонена.' -Language ru
Write-ManagerStatus -Code Pass -Message 'Hash matches.' -Language en
$joined = ($script:lines | ForEach-Object Text) -join ' '
foreach ($value in @('Этап 2/4', '[ПРОЙДЕНО]', '[СПРАВОЧНО]', '[НУЖНА ПРОВЕРКА]', '[ОТКЛОНЕНО]', '[ПРОПУЩЕНО]', '[PASS]')) {
    if (-not $joined.Contains($value)) { throw "Missing readable status: $value" }
}
$script:answers = @('', 'other', '1')
function Read-Host { param([string]$Prompt) $value = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1); return $value }
if (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en) { throw 'Empty answer must decline.' }
if (-not (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en)) { throw 'Invalid answer must reprompt, then accept 1.' }
$script:answers = @('Y', 'N')
if (-not (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en)) { throw 'Y must remain an accepted choice.' }
if (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en) { throw 'N must decline.' }
if ((@($script:lines | Where-Object { $_.Text -like '*Enter 1 or 2.*' })).Count -lt 1) { throw 'Invalid choice was not explained.' }
# Exercise manager delegation and the standalone fallback without its main flow.
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$errors)
if ($errors) { throw 'Manager has parse errors.' }
foreach ($name in @('L', 'Confirm-ManagerAction')) {
    $definition = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true))
    if ($definition.Count -ne 1) { throw "Expected one function: $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$script:uiLanguage = 'en'
$script:answers = @('', 'bad', '1')
if (Confirm-ManagerAction -Title 'Download' -Accept 'Download' -Decline 'Cancel') { throw 'Manager must decline on Enter.' }
if (-not (Confirm-ManagerAction -Title 'Download' -Accept 'Download' -Decline 'Cancel')) { throw 'Manager must retry invalid input.' }
Remove-Item Function:\Read-ManagerChoice
$script:answers = @('', 'bad', 'Y', 'N')
if (Confirm-ManagerAction -Title 'Standalone' -Accept 'Continue' -Decline 'Cancel') { throw 'Standalone must decline on Enter.' }
if (-not (Confirm-ManagerAction -Title 'Standalone' -Accept 'Continue' -Decline 'Cancel')) { throw 'Standalone must retry invalid input and accept Y.' }
if (Confirm-ManagerAction -Title 'Standalone' -Accept 'Continue' -Decline 'Cancel') { throw 'Standalone must decline N.' }
[Console]::WriteLine('Console UI labels and safe choices passed. Nothing downloaded or installed.')
