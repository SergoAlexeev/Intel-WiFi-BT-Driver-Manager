$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $root 'tools\Install-LocalSignTool.ps1'
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors) { throw "SignTool helper parse errors: $errors" }
$text = Get-Content -LiteralPath $installer -Raw
if ($text -notmatch 'E3B929E3678C6FCAC5DDB8C3B991D59331916FD16BEF0C85643213DAC5ABDD2B709D30A80C7222B037B448F586C1EAF0554C3F79040EFCEC436F46181DB7CDBC') {
    throw 'SDK NuGet SHA-512 pin changed.'
}
Write-Host 'SignTool helper parser and pinned package hash passed. No download was requested.'
