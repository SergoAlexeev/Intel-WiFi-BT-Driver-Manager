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
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$SignToolPath
)
$ErrorActionPreference = 'Stop'
function Say([string]$Ru, [string]$En) {
    if ($Language -eq 'ru') { Write-Host $Ru } else { Write-Host $En }
}
$root = Split-Path $PSScriptRoot -Parent
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
        $question = if ($Language -eq 'ru') {
            'Скачать около 2,5 МБ CAB с download.windowsupdate.com для проверки без установки? (Y/N)'
        } else {
            'Download about 2.5 MB CAB from download.windowsupdate.com for a read-only check? (Y/N)'
        }
        if ((Read-Host $question) -notmatch '^[Yy]$') {
            Say 'Загрузка отменена.' 'Download cancelled.'
            return
        }
        $cabPath = Join-Path $work 'candidate.cab'
        Say 'Скачиваю CAB Microsoft по HTTP. До чтения INF обязательно сверю SHA-256; файл не будет установлен.' 'Downloading Microsoft-hosted CAB via HTTP. SHA-256 is checked before reading INF; no installation.'
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
    $auditor = Join-Path $PSScriptRoot 'Test-DriverPackage.ps1'
    if (-not (Test-Path -LiteralPath $auditor -PathType Leaf)) { throw "Missing package auditor: $auditor" }
    $auditArgs = @{ InfPath = $infs[0].FullName; PackageFile = $cabPath; ExpectedSha256 = $pin }
    if ($SignToolPath) { $auditArgs.SignToolPath = $SignToolPath }
    $audit = & $auditor @auditArgs
    if ($audit.CatalogSignature -ne 'PASS' -or $audit.InfCatalogMembership -eq 'FAIL') {
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
    $version = [version]$installed.DriverVersion
    $candidate = [version]$meta.driverVersion
    $result = if ($version -eq $candidate) { 'SAME_VERSION' }
              elseif ($version -gt $candidate) { 'INSTALLED_NEWER_THAN_REFERENCE' }
              else { 'CANDIDATE_REQUIRES_REVIEW' }
    Say 'Этап 3/3. Сравниваю версию и байты INF с установленным драйвером.' 'Step 3/3. Comparing the version and INF bytes with the installed driver.'
    Say "Установлено: $version; CAB INF: $candidate; совпадение INF по байтам: $sameBytes; результат: $result." "Installed: $version; CAB INF: $candidate; installed INF bytes match: $sameBytes; result: $result."
    Say "Подпись CAT: $($audit.CatalogSignature); принадлежность INF этому CAT: $($audit.InfCatalogMembership). Каталожная запись Microsoft и публикация Intel для этого пакета пока не установлены. Никакой драйвер не устанавливался." "CAT signature: $($audit.CatalogSignature); INF/CAT membership: $($audit.InfCatalogMembership). No Microsoft Catalog record or Intel release page for this CAB has been confirmed. No driver was installed."
    [PSCustomObject]@{
        Status = $result
        InstalledVersion = [string]$version
        CandidateInfVersion = [string]$candidate
        HardwareIdRows = $rows.Count
        CabHash = 'PASS'
        CatalogSignature = $audit.CatalogSignature
        InfCatalogMembership = $audit.InfCatalogMembership
        InstalledInfSameBytes = $sameBytes
        Installation = 'NOT_STARTED'
        SourceHost = 'download.windowsupdate.com'
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
