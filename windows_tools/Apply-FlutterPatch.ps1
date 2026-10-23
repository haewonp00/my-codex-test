[CmdletBinding()]
param(
    [string]$PatchRoot = '',
    [string]$AppRoot = (Join-Path $env:USERPROFILE 'recycling_app')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PatchRoot)) {
    $scriptFilePath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptFilePath)) { $scriptFilePath = $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptFilePath)) { throw '-PatchRoot로 압축 해제 폴더를 지정하세요.' }
    $PatchRoot = [IO.Path]::GetDirectoryName($scriptFilePath)
}
if (-not (Test-Path -LiteralPath (Join-Path $AppRoot 'pubspec.yaml') -PathType Leaf)) {
    throw "기존 앱 폴더가 아닙니다: $AppRoot"
}
$files = @(
    'lib\main.dart',
    'lib\data\guides.dart',
    'lib\state\photo_controller.dart',
    'lib\ui\guide_page.dart',
    'lib\ui\item_picker.dart',
    'test\widget_test.dart'
)
foreach ($relative in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $PatchRoot 'recycling_app') $relative) -PathType Leaf)) {
        throw "패치 파일이 없습니다: $relative. ZIP을 모두 압축 해제하세요."
    }
}
$backup = Join-Path $env:USERPROFILE ('recycling_flutter_patch_backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($relative in $files) {
    $source = Join-Path (Join-Path $PatchRoot 'recycling_app') $relative
    $target = Join-Path $AppRoot $relative
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $backupFile = Join-Path $backup $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupFile) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backupFile
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
        throw "파일 복사 확인 실패: $relative. 백업 위치: $backup"
    }
}
Write-Host "Flutter 패치 완료. 백업: $backup" -ForegroundColor Green
Write-Host '서버, best.pt, pubspec.yaml, Android 설정은 변경하지 않았습니다.'
Write-Host '다음: cd 앱폴더 / dart format lib test / flutter analyze / flutter test'
