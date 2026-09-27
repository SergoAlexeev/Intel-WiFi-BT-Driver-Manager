$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $root 'tools\Install-LocalSignTool.ps1'
function Read-Host { param([string]$Prompt) return 'Y' }
$tool = & $installer -Language en | Select-Object -Last 1
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'Local Microsoft SignTool was not provisioned.' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('signed-bt-cab-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    $cab = Join-Path $work 'bluetooth.cab'
    $url = 'http://download.windowsupdate.com/d/msdownload/update/driver/drvs/2026/09/a8be4af6-6f95-46a1-aaa7-41e7e4df0671_74dfa0104d18a5f1252caca5312155b8043bde4a.cab'
    Invoke-WebRequest -Uri $url -OutFile $cab -UseBasicParsing -TimeoutSec 120
    if ((Get-FileHash -LiteralPath $cab -Algorithm SHA256).Hash -ne 'BE7997BF8526144830B9C17D89FFCB5951DB78847D37FD63BA167F104040AEBF') {
        throw 'Bluetooth CAB hash mismatch.'
    }
    $extract = Join-Path $work 'files'
    [IO.Directory]::CreateDirectory($extract) | Out-Null
    $null = & expand.exe $cab '-F:*' $extract 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'CAB extraction failed.' }
    $inf = Join-Path $extract 'ibtusb.inf'
    $cat = Join-Path $extract 'ibtusb.cat'
    $auditor = Join-Path $root 'tools\Test-DriverPackage.ps1'
    $audit = & $auditor -InfPath $inf -PackageFile $cab -ExpectedSha256 'BE7997BF8526144830B9C17D89FFCB5951DB78847D37FD63BA167F104040AEBF' -ArchiveEntry 'ibtusb.inf' -SignToolPath $tool
    if ($audit.HashCheck -ne 'PASS' -or $audit.ArchiveInfLink -ne 'PASS' -or $audit.CatalogSignature -ne 'PASS' -or $audit.InfCatalogMembership -ne 'PASS') {
        throw "Real CAB audit did not pass: $($audit | ConvertTo-Json -Compress)"
    }
    $result = & $tool verify /kp /v /c $cat $inf 2>&1 | Out-String
    $originalExit = $LASTEXITCODE
    Write-Host "Original extracted INF/CAT: exit $originalExit; $result"
    Add-Content -LiteralPath $inf -Value '; deliberate test modification'
    $ErrorActionPreference = 'Continue'
    try {
        $tampered = & $tool verify /kp /v /c $cat $inf 2>&1 | Out-String
        $tamperedExit = $LASTEXITCODE
        $global:LASTEXITCODE = 0
    } finally { $ErrorActionPreference = 'Stop' }
    Write-Host "Modified INF/CAT: exit $tamperedExit; $tampered"
    if ($tamperedExit -eq 0) { throw 'Tampered INF was accepted by SignTool.' }
    $tamperedAudit = & $auditor -InfPath $inf -PackageFile $cab -ExpectedSha256 'BE7997BF8526144830B9C17D89FFCB5951DB78847D37FD63BA167F104040AEBF' -ArchiveEntry 'ibtusb.inf' -SignToolPath $tool
    if ($tamperedAudit.ArchiveInfLink -ne 'FAIL' -or $tamperedAudit.InfCatalogMembership -ne 'FAIL' -or $tamperedAudit.Status -ne 'FAIL') {
        throw 'Tampered INF was accepted by candidate package audit.'
    }
    if ($originalExit -ne 0) {
        Write-Host 'Extracted INF/CAT membership was NOT confirmed by SignTool. No driver installed.'
    } else {
        Write-Host 'Extracted INF/CAT membership passed; modified INF rejected. Nothing installed.'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
