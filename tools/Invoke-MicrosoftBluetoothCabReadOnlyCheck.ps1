<#
.SYNOPSIS
    Read-only audit of the AX201 Bluetooth CAB from Microsoft delivery.
.DESCRIPTION
    Downloads only with consent, or accepts a local CAB. Checks pinned SHA-256,
    extracts to LOCALAPPDATA/Work, inspects INF IDs/version and CAT signature,
    compares with the installed device, then deletes temporary files.
    No driver is staged or installed. Hash pin is backed by a third-party
    release record and a separately obtained byte-identical Microsoft-hosted CAB;
    no Microsoft Update Catalog record ID has been independently established.
#>
param(
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackageFile,
    [ValidateSet('ru', 'en')][string]$Language = 'ru',
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SignToolPath,
    [switch]$PrepareSignTool
)
$ErrorActionPreference = 'Stop'
function Say([string]$Ru, [string]$En) {
    if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En }
}
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'ConsoleUi.ps1')
$meta = Get-Content -LiteralPath (Join-Path $root 'data\microsoft-bluetooth-24.80.0.2-pid0026.json') -Raw | ConvertFrom-Json
$pin = 'BE7997BF8526144830B9C17D89FFCB5951DB78847D37FD63BA167F104040AEBF'
$url = 'http://download.windowsupdate.com/d/msdownload/update/driver/drvs/2026/09/a8be4af6-6f95-46a1-aaa7-41e7e4df0671_74dfa0104d18a5f1252caca5312155b8043bde4a.cab'
if ($meta.sha256 -ne $pin -or $meta.microsoftDeliveryUrl -ne $url -or
    $meta.driverVersion -ne '24.80.0.2' -or
    $meta.deviceIdPrefix -ne 'USB\VID_8087&PID_0026') {
    throw 'Reviewed Bluetooth CAB metadata differs from the pinned values.'
}
$workBase = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'IntelWiFiBTManager\Work'
[IO.Directory]::CreateDirectory($workBase) | Out-Null
$work = Join-Path $workBase ([guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
    $cabPath = $PackageFile
    if (-not $cabPath) {
        $approved = Read-ManagerChoice -Title $(if ($Language -eq 'ru') { 'Проверка Bluetooth CAB: около 2,5 МБ с download.windowsupdate.com. Драйвер не устанавливается.' } else { 'Bluetooth CAB check: about 2.5 MB from download.windowsupdate.com. No driver is installed.' }) -Accept $(if ($Language -eq 'ru') { 'Скачать и проверить CAB' } else { 'Download and check CAB' }) -Decline $(if ($Language -eq 'ru') { 'Пропустить загрузку' } else { 'Skip download' }) -Language $Language
        if (-not $approved) {
            Say 'Загрузка отменена.' 'Download cancelled.'
            return
        }
        $cabPath = Join-Path $work 'candidate.cab'
        Say 'Загрузка CAB Microsoft по HTTP. Перед чтением INF проверяется SHA-256; установка не выполняется.' 'Downloading Microsoft-hosted CAB via HTTP. SHA-256 is checked before reading INF; no installation.'
        Invoke-WebRequest -Uri $url -OutFile $cabPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    }
    Say 'Этап 1/3. Проверяю хеш CAB.' 'Step 1/3. Checking CAB SHA-256.'
    if ((Get-FileHash -LiteralPath $cabPath -Algorithm SHA256).Hash -ine $pin) {
        throw 'Bluetooth CAB SHA-256 mismatch. No CAB content was used.'
    }
    $devices = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.DeviceClass -eq 'BLUETOOTH' -and
        $_.DeviceID -like 'USB\VID_8087&PID_0026*' -and
        $_.DeviceName -eq 'Intel(R) Wireless Bluetooth(R)'
    })
    if ($devices.Count -ne 1) { throw "Expected exactly one Intel Bluetooth PID_0026; found $($devices.Count)." }
    Say 'Этап 2/3. Распаковываю проверенный CAB во временную папку и читаю INF/CAT.' 'Step 2/3. Extracting the verified CAB to a temporary folder and reading INF/CAT.'
    $extract = Join-Path $work 'extracted'
    [IO.Directory]::CreateDirectory($extract) | Out-Null
    $output = & expand.exe $cabPath '-F:*' $extract 2>&1
    if ($LASTEXITCODE -ne 0) { throw "CAB extraction failed: $output" }
    $infs = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter '*.inf')
    $cats = @(Get-ChildItem -LiteralPath $extract -Recurse -File -Filter '*.cat')
    if ($infs.Count -ne 1 -or $cats.Count -ne 1 -or
        $infs[0].Name -ine 'ibtusb.inf' -or $cats[0].Name -ine 'ibtusb.cat') {
        throw "Unexpected CAB contents: INF $($infs.Count), CAT $($cats.Count)."
    }
    $generator = Join-Path $PSScriptRoot 'Get-InfDriverReport.ps1'
    if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) { throw "Missing INF parser: $generator" }
    $report = Join-Path $work 'models.json'
    & $generator -Path $infs[0].FullName -OutputPath $report
    $rows = @((Get-Content -LiteralPath $report -Raw | ConvertFrom-Json) | ForEach-Object { $_ } |
        Where-Object { $_.HardwareId -match '^USB\\VID_8087&PID_0026&REV_000[012]$' -and $_.DriverVersion -eq '24.80.0.2' })
    if ($rows.Count -lt 1) { throw 'CAB INF has no expected Intel USB VID/PID/REV with pinned driver version.' }
    if ($PrepareSignTool -and -not $SignToolPath) {
        $installer = Join-Path $PSScriptRoot 'Install-LocalSignTool.ps1'
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw "Missing SignTool preparation helper: $installer"
        }
        $prepared = & $installer -Language $Language
        if ($prepared -and (Test-Path -LiteralPath $prepared -PathType Leaf)) {
            $SignToolPath = [string]$prepared
            Say 'SignTool готов; проверяю принадлежность INF извлечённому CAT.' 'SignTool is ready; checking extracted INF membership in CAT.'
        } else {
            Say 'SignTool не подготовлен; связь извлечённых INF/CAT останется непроверенной.' 'SignTool was not prepared; extracted INF/CAT membership remains unverified.'
        }
    }
    $auditor = Join-Path $PSScriptRoot 'Test-DriverPackage.ps1'
    if (-not (Test-Path -LiteralPath $auditor -PathType Leaf)) { throw "Missing package auditor: $auditor" }
    $auditArgs = @{ InfPath = $infs[0].FullName; PackageFile = $cabPath; ExpectedSha256 = $pin; ArchiveEntry = 'ibtusb.inf' }
    if ($SignToolPath) { $auditArgs.SignToolPath = $SignToolPath }
    $audit = & $auditor @auditArgs
    if ($audit.CatalogSignature -ne 'PASS' -or $audit.ArchiveInfLink -ne 'PASS' -or $audit.InfCatalogMembership -eq 'FAIL') {
        throw "CAB INF/CAT validation failed: catalog $($audit.CatalogSignature), membership $($audit.InfCatalogMembership)."
    }
    $installed = $devices[0]
    $installedInfPath = Join-Path (Join-Path $env:windir 'INF') $installed.InfName
    $sameBytes = $null
    if ($installed.InfName -match '(?i)^oem[0-9]+\.inf$' -and
        (Test-Path -LiteralPath $installedInfPath -PathType Leaf)) {
        $sameBytes = (Get-FileHash -LiteralPath $installedInfPath -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $infs[0].FullName -Algorithm SHA256).Hash
    }
    $nativeCatalogForSameBytes = 'UNVERIFIED'
    if ($sameBytes -eq $true) {
        $installedSignature = Get-AuthenticodeSignature -LiteralPath $installedInfPath
        if ($installedSignature.Status -eq 'Valid' -and $installedSignature.SignatureType -eq 'Catalog') {
            $nativeCatalogForSameBytes = 'PASS'
        }
    }
    $candidateVerdict = 'NOT_CHECKED'
    $candidateMatch = 'NOT_CHECKED'
    if ($installed.InfName -match '(?i)^oem[0-9]+\.inf$' -and
        (Test-Path -LiteralPath $installedInfPath -PathType Leaf)) {
        $installedReport = Join-Path $work 'installed.json'
        & $generator -Path $installedInfPath -OutputPath $installedReport
        $checker = Join-Path $PSScriptRoot 'Test-DriverCandidate.ps1'
        if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) { throw "Missing candidate checker: $checker" }
        $candidateArgs = @{
            InstalledReport = $installedReport
            CandidateReport = $report
            CandidateInf = $infs[0].FullName
            HardwareId = $installed.DeviceID
            Architecture = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'x86' }
            OsBuild = [Environment]::OSVersion.Version.Build
            PackageFile = $cabPath
            ExpectedSha256 = $pin
            ArchiveEntry = 'ibtusb.inf'
            Language = $Language
            VerifyInstalledDevice = $true
        }
        if ($SignToolPath) { $candidateArgs.SignToolPath = $SignToolPath }
        $decision = & $checker @candidateArgs
        $candidateVerdict = $decision.Verdict
        $candidateMatch = $decision.CandidateMatch
        if ($decision.ArchiveInfLink -ne 'PASS' -or $decision.InfCatalogMembership -eq 'FAIL') {
            throw "Combined candidate audit failed: $candidateVerdict"
        }
    }
    $version = [version]$installed.DriverVersion
    $candidate = [version]$meta.driverVersion
    $result = if ($version -eq $candidate) { 'SAME_VERSION' }
              elseif ($version -gt $candidate) { 'INSTALLED_NEWER_THAN_REFERENCE' }
              else { 'CANDIDATE_REQUIRES_REVIEW' }
    Say 'Этап 3/3. Сравниваю версию и байты INF с установленным драйвером.' 'Step 3/3. Comparing the version and INF bytes with the installed driver.'
    Say "Установлено: $version; CAB INF: $candidate; совпадение INF по байтам: $sameBytes; результат: $result." "Installed: $version; CAB INF: $candidate; installed INF bytes match: $sameBytes; result: $result."
    Say "Каталог Windows для побайтно совпадающего установленного INF: $nativeCatalogForSameBytes (не удостоверяет извлечённый CAT)." "Windows catalog for the identical installed INF: $nativeCatalogForSameBytes (does not verify the extracted CAT)."
    Say "Общий вывод по устройству: $candidateVerdict; совпадение ID: $candidateMatch. Это не разрешение на установку." "Combined device verdict: $candidateVerdict; ID match: $candidateMatch. This does not authorize installation."
    Say "INF из проверенного CAB: $($audit.ArchiveInfLink); подпись CAT: $($audit.CatalogSignature); принадлежность INF этому CAT: $($audit.InfCatalogMembership). Каталожная запись Microsoft и публикация Intel для этого пакета пока не установлены. Никакой драйвер не устанавливался." "INF from hashed CAB: $($audit.ArchiveInfLink); CAT signature: $($audit.CatalogSignature); INF/CAT membership: $($audit.InfCatalogMembership). No Microsoft Catalog record or Intel release page for this CAB has been confirmed. No driver was installed."
    [PSCustomObject]@{
        Status = $result
        CandidateVerdict = $candidateVerdict
        CandidateMatch = $candidateMatch
        Comparison = if ($decision) { $decision.Comparison } else { 'NOT_CHECKED' }
        CandidateOsSection = if ($decision) { $decision.CandidateOsSection } else { 'NOT_CHECKED' }
        CandidateReportMatchesInf = if ($decision) { $decision.CandidateReportMatchesInf } else { $null }
        ReportInfMatchesAuditedFile = if ($decision) { $decision.ReportInfMatchesAuditedFile } else { $null }
        InstalledDeviceCheck = if ($decision) { $decision.InstalledDeviceCheck } else { 'NOT_CHECKED' }
        PackageStatus = if ($decision) { $decision.PackageStatus } else { 'NOT_CHECKED' }
        InstalledVersion = [string]$version
        CandidateInfVersion = [string]$candidate
        HardwareIdRows = $rows.Count
        CabHash = 'PASS'
        ArchiveInfLink = $audit.ArchiveInfLink
        CatalogSignature = $audit.CatalogSignature
        InfCatalogMembership = $audit.InfCatalogMembership
        WindowsCatalogForSameBytes = $nativeCatalogForSameBytes
        InstalledInfSameBytes = $sameBytes
        Installation = 'NOT_STARTED'
        SourceHost = 'download.windowsupdate.com'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
