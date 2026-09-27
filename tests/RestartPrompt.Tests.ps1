# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RestartPrompt.Tests.ps1
# Only two functions are loaded from the manager. Its main flow is not executed.
$ErrorActionPreference = 'Stop'
$manager = Join-Path (Split-Path $PSScriptRoot -Parent) 'IntelWiFiBTManager.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($manager, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Manager parse error: $($parseErrors[0].Message)" }

foreach ($name in @('L', 'Test-GraphicsPackageMatch', 'Test-GraphicsRestartEligible', 'Invoke-GraphicsRestartPrompt')) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if ($definition.Count -ne 1) { throw "Expected one definition of $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function Assert-Equal($Actual, $Expected, [string]$Case) {
    if ($Actual -ne $Expected) { throw "Failed '$Case': actual '$Actual', expected '$Expected'." }
}

$script:uiLanguage = 'en'
$os = [pscustomobject]@{ Caption = 'Microsoft Windows 11 Pro'; OSArchitecture = '64-bit'; Version = '10.0.26200' }
$device = [pscustomobject]@{ DeviceClass = 'DISPLAY'; DeviceID = 'PCI\VEN_8086&DEV_9B41&SUBSYS_00000000'; DeviceName = 'Intel(R) UHD Graphics' }
Assert-Equal (Test-GraphicsPackageMatch ([pscustomobject]@{ Name = 'Intel Core i7-10710U' }) $device $os) $true '10th Gen Intel graphics'
Assert-Equal (Test-GraphicsPackageMatch ([pscustomobject]@{ Name = 'Intel Core i5-8250U' }) $device $os) $true '8th Gen Intel graphics'
Assert-Equal (Test-GraphicsPackageMatch ([pscustomobject]@{ Name = 'Intel Core i7-1165G7' }) $device $os) $false '11th Gen rejected'
Assert-Equal (Test-GraphicsPackageMatch ([pscustomobject]@{ Name = 'Intel Core i7-10710U' }) ([pscustomobject]@{ DeviceClass = 'DISPLAY'; DeviceID = 'PCI\VEN_10DE&DEV_1234'; DeviceName = 'NVIDIA Graphics' }) $os) $false 'non-Intel GPU rejected'
Assert-Equal (Test-GraphicsPackageMatch ([pscustomobject]@{ Name = 'Intel Core i7-10710U' }) $device ([pscustomobject]@{ Caption = 'Windows 10'; OSArchitecture = '64-bit'; Version = '10.0.17134' })) $false 'unsupported Windows build'

Assert-Equal (Test-GraphicsRestartEligible 1000 $true) $true 'version confirmed, unknown exit code'
foreach ($code in @(0, 2, 14, 3010)) {
    Assert-Equal (Test-GraphicsRestartEligible $code $false) $true "accepted exit code $code"
}
Assert-Equal (Test-GraphicsRestartEligible 1000 $false) $false 'unknown code without new version'

# Shadow Restart-Computer. The system command is never invoked.
$script:answer = 'N'
$script:restartCalls = 0
$script:closeCalls = 0
$script:cleanupCalls = 0
function Read-Host { param([string]$Prompt) return $script:answer }
function Close-ManagerLog { $script:closeCalls++ }
function Clear-ManagerWorkDirectory { $script:cleanupCalls++ }
function Restart-Computer { [CmdletBinding()] param() $script:restartCalls++ }

Assert-Equal (Invoke-GraphicsRestartPrompt) $false 'declined restart'
Assert-Equal $script:restartCalls 0 'declined: no restart call'
Assert-Equal $script:closeCalls 0 'declined: log stays open'
Assert-Equal $script:cleanupCalls 0 'declined: work files stay until exit'

$script:answer = 'Y'
Assert-Equal (Invoke-GraphicsRestartPrompt) $true 'accepted restart'
Assert-Equal $script:restartCalls 1 'accepted: mocked restart called'
Assert-Equal $script:closeCalls 1 'accepted: log closed'
Write-Host 'Restart prompt checks passed. No actual restart was requested.' -ForegroundColor Green
Write-Host 'Graphics family matching checks passed. No driver was downloaded or installed.' -ForegroundColor Green
