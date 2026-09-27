$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$checker = Join-Path $root 'tools\Test-OfficialWifiCandidate.ps1'
$generator = Join-Path $root 'tools\Get-InfDriverReport.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($checker, [ref]$tokens, [ref]$errors)
if ($errors) { throw 'Official ZIP checker does not parse.' }
$fn = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ExactWifiInfRows' }, $true))
if ($fn.Count -ne 1) { throw 'Cannot locate INF selection helper.' }
. ([scriptblock]::Create($fn[0].Extent.Text))
$work = Join-Path ([IO.Path]::GetTempPath()) ('intel-zip-real-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zipPath = Join-Path $work 'intel.zip'
    $url = 'https://downloadmirror.intel.com/926940/WiFi-24.70.0-Driver64-Win10-Win11.zip'
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    $expected = 'E74843C855580659559A6D9DB55E1864121E756026F9B543FB8A792DA2EB92A9'
    if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $expected) { throw 'Official ZIP hash mismatch.' }
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead($zipPath)
    try {
        $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $infEntries = @($zip.Entries | Where-Object { $_.FullName -match '(?i)\.inf$' })
            $found = @()
            foreach ($entry in $infEntries) {
                $infPath = Join-Path $work ([IO.Path]::GetFileName($entry.FullName))
                $inputStream = $entry.Open()
                $outputStream = [IO.File]::Create($infPath)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
                $report = "$infPath.json"
                & $generator -Path $infPath -OutputPath $report
                $rows = @(Get-ExactWifiInfRows $report 'PCI\VEN_8086&DEV_02F0&SUBSYS_00748086')
                if ($rows.Count) { $found += $entry.FullName }
            }
            if ($found.Count -ne 1 -or $found[0] -notmatch '(?i)netwtw08\.inf$') {
                throw "Unexpected matching INFs: $($found -join ', ')"
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    Write-Host 'Official Intel ZIP hash and AX201 INF selection passed. Nothing was installed.'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
