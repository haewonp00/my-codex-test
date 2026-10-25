[CmdletBinding()]
param(
    [string]$AppRoot = (Join-Path $env:USERPROFILE 'recycling_app'),
    [string]$ServerRoot = (Join-Path $env:USERPROFILE 'recycling_server'),
    [string]$DeviceId = '',
    [string]$PythonExe = '',
    [ValidateRange(5,300)][int]$StartupTimeoutSeconds = 60
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $AppRoot 'pubspec.yaml') -PathType Leaf)) {
    throw "앱 폴더를 찾지 못했습니다: $AppRoot"
}
foreach ($name in @('server.py','best.pt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ServerRoot $name) -PathType Leaf)) {
        throw "서버 파일이 필요합니다: $(Join-Path $ServerRoot $name)"
    }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'flutter 명령을 찾지 못했습니다. 기존 Flutter를 실행하던 VS Code 터미널에서 실행하세요.'
}
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if ($adbCommand) { $adbPath = $adbCommand.Source }
else { $adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe' }
if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
    throw 'adb.exe를 찾지 못했습니다. Android SDK platform-tools 설치 위치를 확인하세요.'
}
Write-Host '[1/4] 휴대폰 USB 디버깅 확인'
$deviceLines = & $adbPath devices
if ($LASTEXITCODE -ne 0) { throw 'adb devices 실패. USB와 Android SDK를 확인하세요.' }
$deviceLines | ForEach-Object { Write-Host $_ }
$phones = @($deviceLines | Where-Object { $_ -match '^\S+\s+device$' } |
    ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ -notlike 'emulator-*' })
if (-not $DeviceId) {
    if ($phones.Count -ne 1) {
        throw '승인된 휴대폰 한 대가 필요합니다. S25를 USB로 연결하고 디버깅 허용을 누르세요. 여러 대면 -DeviceId로 지정하세요.'
    }
    $DeviceId = $phones[0]
}
if ($DeviceId -notin $phones) { throw '휴대폰이 device 상태가 아닙니다. USB 디버깅 허용을 확인하세요.' }
function Read-ServerHealth {
    try {
        $response = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 2
        if ($response.status -eq 'ok') { return $response }
    } catch { }
    return $null
}
function Assert-Classes {
    param($Health)
    $expected = @{'0'='plastic'; '1'='paper'; '2'='metal'}
    if (-not $Health.PSObject.Properties['classes']) { throw '서버 /health에 classes가 없습니다. 제공한 server.py인지 확인하세요.' }
    foreach ($pair in $expected.GetEnumerator()) {
        $property = $Health.classes.PSObject.Properties[$pair.Key]
        if ($null -eq $property -or $property.Value -ne $pair.Value) {
            throw '서버 모델의 클래스 매핑이 plastic(0), paper(1), metal(2)와 다릅니다.'
        }
    }
    if (@($Health.classes.PSObject.Properties).Count -ne 3) {
        throw '서버 모델의 클래스 개수가 3개가 아닙니다.'
    }
}
Write-Host '[2/4] PC 사진 분석 서버 확인'
$health = Read-ServerHealth
if ($null -eq $health) {
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $listeners = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
        if ($listeners.Count -gt 0) {
            throw '8000 포트는 사용 중이지만 분석 서버 /health가 정상 응답하지 않습니다. 기존 서버 터미널의 오류를 확인하세요.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($PythonExe)) {
        foreach ($candidate in @(
            (Join-Path $ServerRoot '.venv\Scripts\python.exe'),
            (Join-Path $ServerRoot 'venv\Scripts\python.exe')
        )) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $PythonExe = $candidate; break }
        }
        if ([string]::IsNullOrWhiteSpace($PythonExe)) {
            $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
            if ($pythonCommand) { $PythonExe = $pythonCommand.Source }
        }
    }
    if ([string]::IsNullOrWhiteSpace($PythonExe) -or -not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
        throw '서버용 Python을 찾지 못했습니다. -PythonExe로 실제 python.exe 경로를 지정하세요.'
    }
    Write-Host "서버용 Python: $PythonExe"
    & $PythonExe -c 'import fastapi, uvicorn, ultralytics, PIL, multipart'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "설치 명령: & `"$PythonExe`" -m pip install -r `"$(Join-Path $ServerRoot 'requirements.txt')`""
        throw '선택한 Python에 서버 패키지가 없습니다. 위 명령으로 설치하거나 -PythonExe로 기존 서버 환경을 지정하세요.'
    }
    $serverProcess = Start-Process -FilePath $PythonExe -ArgumentList @(
        '-m','uvicorn','server:app','--host','127.0.0.1','--port','8000'
    ) -WorkingDirectory $ServerRoot -WindowStyle Normal -PassThru
    Write-Host "서버를 새 창에서 시작했습니다. PID: $($serverProcess.Id)"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($null -eq $health -and $watch.Elapsed.TotalSeconds -lt $StartupTimeoutSeconds) {
        $serverProcess.Refresh()
        if ($serverProcess.HasExited) {
            throw '서버가 종료됐습니다. 서버 창의 오류와 Python 환경/best.pt를 확인하세요.'
        }
        Start-Sleep -Milliseconds 500
        $health = Read-ServerHealth
    }
    if ($null -eq $health) { throw '서버 시작을 기다리다 시간이 초과됐습니다. 서버 창의 모델 로딩 오류를 확인하세요.' }
} else {
    Write-Host '이미 실행 중인 서버를 사용합니다. 모델 파일을 교체했다면 기존 서버를 먼저 재시작해야 합니다.'
}
Assert-Classes -Health $health
Write-Host '[3/4] 휴대폰 -> USB -> PC 8000 포트 연결'
& $adbPath -s $DeviceId reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'adb reverse 실패. USB 연결과 디버깅 허용을 확인하세요.' }
& $adbPath -s $DeviceId reverse --list
if ($LASTEXITCODE -ne 0) { throw 'USB 포트 연결 목록 확인 실패.' }
Write-Host '[4/4] S25에 현재 Flutter 앱 설치 및 실행' -ForegroundColor Green
Write-Host '앱에서 사진 촬영 -> 촬영 완료 -> 분석하기를 누르세요.'
Write-Host '지원: 플라스틱/종이/금속. 비닐/복합재질은 직접 안내 찾기를 사용하세요.'
Write-Host '사진 분석 중에는 USB와 PC 서버를 유지하세요.'
Push-Location $AppRoot
try {
    & flutter run -d $DeviceId
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 실행 실패. 위 빌드/기기 오류를 확인하세요.' }
} finally { Pop-Location }
