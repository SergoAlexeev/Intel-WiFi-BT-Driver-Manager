$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\ConsoleUi.ps1')
$script:lines = New-Object System.Collections.ArrayList
function Write-Host {
    param([object]$Object, [string]$ForegroundColor, [switch]$NoNewline)
    [void]$script:lines.Add([pscustomobject]@{ Text=[string]$Object; Color=$ForegroundColor })
}
Write-ManagerStage -Number 2 -Total 4 -Title 'Проверка файла' -Detail 'Без установки.' -Language ru
Write-ManagerStatus -Code Pass -Message 'Хеш совпал.' -Language ru
Write-ManagerStatus -Code Review -Message 'Нужен SignTool.' -Language ru
Write-ManagerStatus -Code Reject -Message 'Хеш неверен.' -Language ru
Write-ManagerStatus -Code Skip -Message 'Загрузка отклонена.' -Language ru
Write-ManagerStatus -Code Pass -Message 'Hash matches.' -Language en
$joined = ($script:lines | ForEach-Object Text) -join ' '
foreach ($value in @('Этап 2/4', '[ПРОЙДЕНО]', '[НУЖНА ПРОВЕРКА]', '[ОТКЛОНЕНО]', '[ПРОПУЩЕНО]', '[PASS]')) {
    if (-not $joined.Contains($value)) { throw "Missing readable status: $value" }
}
$script:answers = @('', 'other', '1')
function Read-Host { param([string]$Prompt) $value = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1); return $value }
if (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en) { throw 'Empty answer must decline.' }
if (-not (Read-ManagerChoice -Title 'Test' -Accept 'Continue' -Decline 'Cancel' -Language en)) { throw 'Invalid answer must reprompt, then accept 1.' }
if ((@($script:lines | Where-Object { $_.Text -like '*Enter 1 or 2.*' })).Count -lt 1) { throw 'Invalid choice was not explained.' }
[Console]::WriteLine('Console UI labels and safe choices passed. Nothing downloaded or installed.')
