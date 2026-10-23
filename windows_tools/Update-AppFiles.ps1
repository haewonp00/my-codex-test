[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModelPath,
    [string]$PackageRoot = '',
    [string]$AppRoot = (Join-Path $env:USERPROFILE 'recycling_app'),
    [string]$ServerRoot = (Join-Path $env:USERPROFILE 'recycling_server')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve automatic script paths only after parameter binding has completed.
# Some Windows PowerShell invocations expose an empty PSScriptRoot in defaults.
if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $scriptFilePath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptFilePath)) {
        $scriptFilePath = $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($scriptFilePath)) {
        throw '압축 해제 폴더를 -PackageRoot로 직접 지정하세요.'
    }
    $PackageRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($scriptFilePath))
}

if (-not (Test-Path -LiteralPath (Join-Path $AppRoot 'pubspec.yaml') -PathType Leaf)) {
    throw "기존 앱 경로를 확인하세요: $AppRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $ServerRoot 'server.py') -PathType Leaf)) {
    throw "기존 서버 경로를 확인하세요: $ServerRoot"
}
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw "새 모델 파일이 없습니다: $ModelPath"
}
if ([IO.Path]::GetExtension($ModelPath) -ne '.pt') { throw '새 best.pt를 지정하세요.' }
$appSource = Join-Path $PackageRoot 'recycling_app'
$serverSource = Join-Path $PackageRoot 'recycling_server'
if (-not (Test-Path -LiteralPath (Join-Path $appSource 'lib\main.dart')) -or
    -not (Test-Path -LiteralPath (Join-Path $serverSource 'server.py'))) {
    throw 'ZIP 전체를 압축 해제한 폴더에서 실행하세요. PackageRoot를 확인하세요.'
}
if ((Get-Item -LiteralPath $appSource).FullName -eq (Get-Item -LiteralPath $AppRoot).FullName -or
    (Get-Item -LiteralPath $serverSource).FullName -eq (Get-Item -LiteralPath $ServerRoot).FullName) {
    throw '교체용 압축 파일은 기존 프로젝트 밖에 풀어야 합니다.'
}
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    $listeners = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) {
        throw '8000 포트가 사용 중입니다. 서버 터미널에서 Ctrl+C로 종료한 뒤 다시 실행하세요.'
    }
}
$newHash = (Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($newHash -eq '2f65acc39ad05d21ef3531e64a727adfd5e1f003215c49be5e1f2640c336bc47') {
    throw '선택한 파일은 이전 label_fix_v1 모델입니다. Colab background35_v1의 새 best.pt를 선택하세요.'
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$backup = Join-Path $env:USERPROFILE "recycling_backup_$stamp"
New-Item -ItemType Directory -Path $backup | Out-Null
# Stage first, so using a model already in the server folder is also safe.
$stagedModel = Join-Path $backup 'incoming_new_model.pt'
Copy-Item -LiteralPath $ModelPath -Destination $stagedModel
$modelTarget = Join-Path $ServerRoot 'best.pt'
$oldHash = $null
if (Test-Path -LiteralPath $modelTarget -PathType Leaf) {
    $oldHash = (Get-FileHash -LiteralPath $modelTarget -Algorithm SHA256).Hash.ToLowerInvariant()
}
$copied = [System.Collections.Generic.List[string]]::new()
function Install-BackedUpFile {
    param([string]$Source, [string]$Target, [string]$BackupRelative)
    if (Test-Path -LiteralPath $Target -PathType Leaf) {
        $backupFile = Join-Path $backup $BackupRelative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
        Copy-Item -LiteralPath $Target -Destination $backupFile
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    $copied.Add($Target)
}
foreach ($project in @(
    @{Source=$appSource; Target=$AppRoot; Name='recycling_app'},
    @{Source=$serverSource; Target=$ServerRoot; Name='recycling_server'}
)) {
    $sourceRoot = (Get-Item -LiteralPath $project.Source).FullName
    foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart([char[]]'\/')
        # The package contains source files only. Never copy weights from this loop.
        if ($file.Extension -eq '.pt') { continue }
        Install-BackedUpFile -Source $file.FullName `
            -Target (Join-Path $project.Target $relative) `
            -BackupRelative (Join-Path $project.Name $relative)
    }
}
Install-BackedUpFile -Source $stagedModel -Target $modelTarget -BackupRelative 'recycling_server\best.pt'
$installedHash = (Get-FileHash -LiteralPath $modelTarget -Algorithm SHA256).Hash.ToLowerInvariant()
if ($installedHash -ne $newHash) { throw "모델 복사를 확인하지 못했습니다. 백업: $backup" }
@{
    app=$AppRoot; server=$ServerRoot; backup=$backup;
    old_model_sha256=$oldHash; new_model_sha256=$newHash;
    copied_files=$copied.ToArray()
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'replacement_record.json') -Encoding UTF8
Write-Host "교체 완료. 백업 폴더: $backup" -ForegroundColor Green
Write-Host "새 모델: $modelTarget"
Write-Host "새 모델 SHA256: $newHash"
Write-Host '다음: 앱 flutter pub get / 서버 pip 설치 후 서버와 앱을 모두 다시 실행하세요.'
Write-Host '기존 Android 설정과 Python 가상환경은 수정하지 않았습니다.'
