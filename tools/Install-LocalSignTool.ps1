<#
.SYNOPSIS
    Optionally installs a local SignTool copy from Microsoft SDK BuildTools.
.DESCRIPTION
    Downloads pinned Microsoft NuGet package only after consent, checks SHA-512,
    extracts x64 SDK tools under LOCALAPPDATA, and validates the SignTool
    Authenticode signature. Does not install the Windows SDK system-wide.
#>
param([ValidateSet('ru', 'en')][string]$Language = 'ru')
$ErrorActionPreference = 'Stop'
function Say([string]$Ru, [string]$En) {
    if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En }
}
$version = '10.0.28000.2705'
$packageUrl = 'https://api.nuget.org/v3-flatcontainer/microsoft.windows.sdk.buildtools/10.0.28000.2705/microsoft.windows.sdk.buildtools.10.0.28000.2705.nupkg'
$expectedHash = 'E3B929E3678C6FCAC5DDB8C3B991D59331916FD16BEF0C85643213DAC5ABDD2B709D30A80C7222B037B448F586C1EAF0554C3F79040EFCEC436F46181DB7CDBC'
$base = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Tools\SignTool'
$target = Join-Path $base $version
$binary = Join-Path $target 'signtool.exe'
if (Test-Path -LiteralPath $binary -PathType Leaf) {
    $signature = Get-AuthenticodeSignature -LiteralPath $binary
    if ($signature.Status -eq 'Valid' -and $signature.SignerCertificate.Subject -match '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        Say "SignTool уже найден: $binary" "SignTool is already available: $binary"
        Write-Output $binary
        return
    }
    throw 'Existing local SignTool did not pass Microsoft signature validation.'
}
Say 'Зачем нужен SignTool: штатная проверка Windows подтверждает подпись установленного INF и отдельно подпись извлечённого CAT, но не связывает именно эти два извлечённых файла. SignTool проверяет, что INF содержится в данном CAT; это дополнительная проверка кандидата, а не установка драйвера.' 'Why SignTool is needed: Windows verifies the installed INF and extracted CAT separately, but does not link this exact extracted pair. SignTool checks that the INF belongs to this CAT; this audits a candidate and does not install a driver.'
Say "Что будет скачано: пакет Microsoft Windows SDK BuildTools (около 21 МБ) из NuGet. Сверю SHA-512 пакета и подпись Microsoft у signtool.exe; сохраню инструменты только в $target. Системный SDK и драйверы не устанавливаются. При отказе проверка продолжится, а связь INF/CAT останется UNVERIFIED." "What is downloaded: Microsoft Windows SDK BuildTools NuGet package (about 21 MB). Its SHA-512 and the Microsoft signature on signtool.exe are checked; tools are kept only in $target. No system-wide SDK or drivers are installed. If declined, the audit continues with INF/CAT membership UNVERIFIED."
$question = if ($Language -eq 'ru') {
    'Скачать около 21 МБ официального Microsoft SDK BuildTools NuGet и сохранить SignTool локально? (Y/N)'
} else {
    'Download about 21 MB of official Microsoft SDK BuildTools NuGet and save SignTool locally? (Y/N)'
}
if ((Read-Host $question) -notmatch '^[Yy]$') {
    Say 'Установка SignTool отменена.' 'SignTool setup cancelled.'
    return
}
[IO.Directory]::CreateDirectory($base) | Out-Null
$work = Join-Path $base ('work-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$staging = Join-Path $work 'x64'
[IO.Directory]::CreateDirectory($staging) | Out-Null
try {
    $package = Join-Path $work 'sdk.nupkg'
    Say 'Скачиваю пакет Microsoft в рабочую папку.' 'Downloading Microsoft package to a temporary folder.'
    Invoke-WebRequest -Uri $packageUrl -OutFile $package -UseBasicParsing -TimeoutSec 180 -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $package -Algorithm SHA512).Hash -ine $expectedHash) {
        throw 'SDK BuildTools NuGet SHA-512 mismatch. No files were extracted.'
    }
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead($package)
    try {
        $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $prefix = 'bin/10.0.28000.0/x64/'
            $count = 0
            foreach ($entry in $zip.Entries) {
                $normalized = $entry.FullName.Replace('\', '/')
                if (-not $normalized.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
                $relative = $normalized.Substring($prefix.Length)
                if (-not $relative -or $relative.EndsWith('/') -or
                    $relative -match '(^|/)\.\.?(/|$)' -or $relative -match '[:*?"<>|]') { continue }
                $destination = [IO.Path]::GetFullPath((Join-Path $staging ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))))
                $safeRoot = [IO.Path]::GetFullPath($staging).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                if (-not $destination.StartsWith($safeRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe NuGet entry path.' }
                [IO.Directory]::CreateDirectory((Split-Path $destination -Parent)) | Out-Null
                $source = $entry.Open()
                $output = [IO.File]::Create($destination)
                try { $source.CopyTo($output) } finally { $output.Dispose(); $source.Dispose() }
                $count++
            }
            if ($count -lt 2) { throw 'Expected x64 SDK tools were not found in the package.' }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    $stagedBinary = Join-Path $staging 'signtool.exe'
    if (-not (Test-Path -LiteralPath $stagedBinary -PathType Leaf)) { throw 'SignTool executable missing from the verified package.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $stagedBinary
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw 'Extracted SignTool lacks a valid Microsoft Authenticode signature.'
    }
    if (Test-Path -LiteralPath $target) { throw 'SignTool target directory already exists.' }
    Move-Item -LiteralPath $staging -Destination $target -ErrorAction Stop
    Say "Проверенный SignTool сохранён: $binary" "Verified SignTool saved: $binary"
    Write-Output $binary
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
