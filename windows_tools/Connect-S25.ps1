[CmdletBinding()]
param(
    [string]$DeviceId = '',
    [string]$AppRoot = (Join-Path $env:USERPROFILE 'recycling_app'),
    [switch]$RunApp
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) { $adbPath = $adbCommand.Source }
else { $adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' }
if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
    throw 'adb.exe를 찾지 못했습니다. flutter doctor -v에서 Android SDK 경로를 확인하세요.'
}
$deviceLines = & $adbPath devices
if ($LASTEXITCODE -ne 0) { throw 'adb devices 실패. USB 연결과 Android SDK를 확인하세요.' }
$deviceLines | ForEach-Object { Write-Host $_ }
$phones = @($deviceLines | Where-Object { $_ -match '^\S+\s+device$' } |
    ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -notlike 'emulator-*' })
if (-not $DeviceId) {
    if ($phones.Count -ne 1) {
        throw '승인된 실제 휴대폰이 1대여야 합니다. 폰의 USB 디버깅 허용을 누르거나 -DeviceId로 기기를 지정하세요.'
    }
    $DeviceId = $phones[0]
}
if ($DeviceId -notin $phones) { throw '지정한 휴대폰이 device 상태가 아닙니다. USB 디버깅 허용을 확인하세요.' }
try { $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 5 }
catch { throw 'PC 서버가 응답하지 않습니다. 다른 터미널에서 먼저 uvicorn을 실행하세요.' }
if ($health.status -ne 'ok') { throw '서버 health 상태가 정상이 아닙니다.' }
& $adbPath -s $DeviceId reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'USB 포트 연결 실패. 휴대폰 잠금과 디버깅 허용을 확인하세요.' }
& $adbPath -s $DeviceId reverse --list
if ($LASTEXITCODE -ne 0) { throw 'USB reverse 목록을 확인하지 못했습니다.' }
Write-Host "USB 연결 완료: $DeviceId" -ForegroundColor Green
Write-Host '휴대폰 앱 127.0.0.1:8000 -> USB -> PC 127.0.0.1:8000'
if ($RunApp) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'flutter 명령을 찾지 못했습니다.' }
    Push-Location $AppRoot
    try {
        & flutter run -d $DeviceId
        if ($LASTEXITCODE -ne 0) { throw 'Flutter 실행 실패. 위 오류와 안내 문서를 확인하세요.' }
    } finally { Pop-Location }
} else {
    Write-Host "다음 명령: cd `"$AppRoot`""
    Write-Host "flutter run -d $DeviceId"
}
