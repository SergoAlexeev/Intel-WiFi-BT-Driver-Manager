# Shared console presentation for Windows PowerShell 5.1.
# Plain labels carry the meaning; colors are optional visual cues.
function Write-ManagerStage {
    param(
        [Parameter(Mandatory)][ValidateRange(1, 100)][int]$Number,
        [Parameter(Mandatory)][ValidateRange(1, 100)][int]$Total,
        [Parameter(Mandatory)][string]$Title,
        [string]$Detail,
        [ValidateSet('ru', 'en')][string]$Language = 'ru'
    )
    if ($Number -gt $Total) { throw 'Stage number exceeds total.' }
    $heading = if ($Language -eq 'ru') { "Этап $Number/$Total — $Title" } else { "Step $Number/$Total — $Title" }
    Write-Host ''
    Write-Host $heading -ForegroundColor Cyan
    if ($Detail) { Write-Host $Detail }
}

function Write-ManagerStatus {
    param(
        [Parameter(Mandatory)][ValidateSet('Pass', 'Advisory', 'Review', 'Reject', 'Skip')][string]$Code,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Message,
        [ValidateSet('ru', 'en')][string]$Language = 'ru'
    )
    $labels = @{
        ru = @{ Pass='ПРОЙДЕНО'; Advisory='СПРАВОЧНО'; Review='НУЖНА ПРОВЕРКА'; Reject='ОТКЛОНЕНО'; Skip='ПРОПУЩЕНО' }
        en = @{ Pass='PASS'; Advisory='ADVISORY'; Review='REVIEW'; Reject='REJECTED'; Skip='SKIPPED' }
    }
    $colors = @{ Pass='Green'; Advisory='Gray'; Review='Yellow'; Reject='Red'; Skip='Gray' }
    Write-Host "[$($labels[$Language][$Code])] " -ForegroundColor $colors[$Code] -NoNewline
    Write-Host $Message
}

function Read-ManagerChoice {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Accept,
        [Parameter(Mandatory)][string]$Decline,
        [ValidateSet('ru', 'en')][string]$Language = 'ru'
    )
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "[1] $Accept"
    Write-Host "[2] $Decline " -NoNewline
    Write-Host $(if ($Language -eq 'ru') { '(по умолчанию)' } else { '(default)' }) -ForegroundColor Gray
    while ($true) {
        $answer = Read-Host $(if ($Language -eq 'ru') { 'Введите 1 или 2' } else { 'Enter 1 or 2' })
        if ($answer -eq '1') { return $true }
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq '2') { return $false }
        Write-ManagerStatus -Code Review -Language $Language -Message $(if ($Language -eq 'ru') { 'Введите 1 или 2.' } else { 'Enter 1 or 2.' })
    }
}
