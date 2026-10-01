$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$errors)
if ($errors) { throw 'Manager syntax is invalid.' }
foreach ($name in @('New-ManagerWorkDirectory', 'Clear-ManagerWorkDirectory')) {
    $found = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    if ($found.Count -ne 1) { throw "Expected exactly one function: $name" }
    Invoke-Expression $found[0].Extent.Text
}
function L([string]$Ru, [string]$En) { return $En }
$root = Join-Path ([IO.Path]::GetTempPath()) ('manager-work-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
try {
    $script:workDirectory = $null
    $script:workRoot = $null
    $work = New-ManagerWorkDirectory -LocalDataBase $root
    $workAgain = New-ManagerWorkDirectory -LocalDataBase $root
    if ($work -ne $workAgain) { throw 'More than one work directory was created for a run.' }
    $logs = Join-Path $root 'IntelWiFiBTManager\Logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    Set-Content -LiteralPath (Join-Path $logs 'manager.log') -Value 'keep log'
    Set-Content -LiteralPath (Join-Path $work 'download.tmp') -Value 'remove this'
    Clear-ManagerWorkDirectory
    if (Test-Path -LiteralPath $work) { throw 'Temporary directory was not removed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $logs 'manager.log'))) { throw 'Session log was deleted.' }
    $other = Join-Path $root 'IntelWiFiBTManager\Work\other-folder'
    New-Item -ItemType Directory -Force -Path $other | Out-Null
    $script:workDirectory = $other
    Clear-ManagerWorkDirectory 3>$null
    if (-not (Test-Path -LiteralPath $other)) { throw 'Unowned directory was deleted.' }
    Write-Host 'Temporary workspace checks passed. Logs and unowned files were retained.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
