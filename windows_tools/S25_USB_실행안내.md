# Galaxy S25 USB 연결·새 모델·앱 파일 교체

현재 구조는 **S25의 Flutter 앱 → USB(adb reverse) → PC의 Python 서버 → 새 best.pt**입니다. 앱과 서버 주소는 그대로 `http://127.0.0.1:8000/predict`를 사용합니다. 같은 Wi-Fi에 연결하거나 PC IP로 앱 주소를 바꿀 필요가 없습니다. USB와 PC 서버가 연결되어 있어야 사진 분석이 됩니다.

## 1. 준비 파일

1. `recycling_s25_update_v1.zip`을 다운로드하고 탐색기의 ‘모두 압축 풀기’로 풉니다. 예시 위치는 `C:\Users\haewo\Downloads\recycling_s25_update_v1`입니다. `recycling_app`, `recycling_server`, `windows_tools`가 그 폴더 안에 있어야 합니다.
2. Colab 새 학습 결과의 `background35_v1/weights/best.pt`를 다운로드합니다. 대조군 `control_v1`이나 `last.pt`를 선택하지 마세요.
3. 새 모델을 Downloads에 복사하고 혼동을 줄이기 위해 **`best_background35.pt`**로 이름을 바꿉니다. 실제 이름이 다르면 아래 ModelPath를 그 이름으로 바꿔야 합니다. 파일 확장명 숨김이 켜져 있어도 이름을 best.pt.pt로 만들지 않도록 주의하세요.
4. 휴대폰 USB 케이블은 충전뿐 아니라 **데이터 통신이 가능한 케이블**을 사용합니다.

ZIP에는 가중치가 없습니다. 새 모델은 본인이 Colab에서 만든 실제 파일을 별도로 지정해야 합니다.

### 새 모델의 실제 다운로드 위치

Google Drive 웹사이트에서 **내 드라이브 → recycling_experiments → 해당 학습 실행의 날짜시간_식별자 폴더 → background35_v1 → weights → best.pt**를 찾습니다. best.pt를 오른쪽 클릭 → 다운로드합니다.

Colab 왼쪽 폴더 모양 ‘파일’에서는 **drive → MyDrive → recycling_experiments → 해당 학습 폴더 → background35_v1 → weights → best.pt**입니다. 오른쪽 ⋮ → 다운로드를 누릅니다. 파일 창에 drive가 없으면 학습 때 쓴 Google 계정으로 Drive를 연결해야 합니다.

새 모델은 사용자 Drive에 있으며 GitHub에는 업로드되지 않았습니다. 이 ZIP만 받아서는 새 모델 파일이 생기지 않습니다. 더 자세한 찾기 설명은 ZIP의 `처음읽기_다운로드와모델위치.md`에 있습니다.

## 2. S25에서 USB 디버깅 켜기

1. 설정 → 휴대전화 정보 → 소프트웨어 정보 → **빌드번호를 7번** 누릅니다.
2. 잠금 PIN 등을 입력하면 개발자 옵션이 활성화됩니다.
3. 설정으로 돌아가 → 개발자 옵션 → **USB 디버깅 켜기**.
4. S25를 USB로 PC에 연결하고 잠금을 해제합니다.
5. ‘USB 디버깅을 허용하시겠습니까?’가 뜨면 **허용**합니다.

무선 디버깅이나 USB 테더링을 켤 필요는 없습니다. Windows에서 장치를 인식하지 못하면 케이블/USB 포트를 먼저 바꿔 보고, 필요하면 Samsung Android USB 드라이버 설치 상태를 확인하세요. 개발자 옵션이 조직 정책 등으로 잠겨 있으면 먼저 그 제한을 해결해야 합니다.

## 3. 기존 서버와 앱 실행 중지

- 서버 터미널에서 **Ctrl+C**를 눌러 uvicorn을 종료합니다.
- 실행 중인 `flutter run`도 종료합니다.
- VS Code는 열어 둬도 됩니다.

가중치는 서버가 시작할 때 읽습니다. 파일만 교체하고 서버를 계속 실행하면 이전 모델을 계속 사용할 수 있으므로 서버를 먼저 종료합니다.

## 4. 앱·서버·모델을 백업 후 자동 교체

PowerShell 터미널에서 다음을 실행합니다. 예시 폴더와 파일 이름이 실제 다운로드 위치와 같은지 먼저 확인하세요.

```powershell
$package = "$env:USERPROFILE\Downloads\recycling_s25_update_v1"
$newModel = "$env:USERPROFILE\Downloads\best_background35.pt"

Test-Path "$package\windows_tools\Update-AppFiles.ps1"
Test-Path $newModel
```

둘 다 `True`여야 합니다. False면 파일명 또는 압축을 푼 위치를 수정하세요. 그다음:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$package\windows_tools\Update-AppFiles.ps1" -ModelPath $newModel
```

이 실행 정책 옵션은 **해당 스크립트 프로세스에만 적용**하며 PC의 정책을 영구 변경하지 않습니다.

기본 설치 위치:

- 앱: `C:\Users\haewo\recycling_app` (현재 Windows 사용자 프로필 아래 recycling_app)
- 서버: `C:\Users\haewo\recycling_server` (현재 사용자 프로필 아래 recycling_server)

다른 위치라면 명시합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$package\windows_tools\Update-AppFiles.ps1" -ModelPath $newModel -AppRoot 'C:\Users\haewo\recycling_app' -ServerRoot 'C:\Users\haewo\recycling_server'
```

스크립트가 하는 일:

1. 앱/서버/새 모델 경로와 8000 포트 사용 여부 검사. 서버가 실행 중이면 중단 안내.
2. 새 모델이 알려진 이전 label_fix_v1 파일과 같은지 해시 검사. 같으면 잘못 선택한 것으로 중단.
3. 사용자 폴더에 `recycling_backup_날짜시간` 생성.
4. 실제 교체 대상인 기존 파일들만 백업.
5. 새 `lib/`, `test/`, `pubspec.yaml`, 서버 코드와 requirements 등을 복사.
6. 기존 서버 `best.pt`도 백업한 뒤 새 모델을 **서버의 best.pt라는 이름으로 설치**.
7. 복사 전후 새 모델 SHA256을 비교하고 백업 폴더에 `replacement_record.json` 저장.

기존 Android/iOS 설정, Python 가상환경, YOLO 클래스는 수정하지 않습니다. 모델을 재학습하지 않습니다. 모델의 내용이 실제로 올바른 3개 클래스인지는 서버 시작 시 한 번 더 검사합니다. 새 모델의 성능을 이 파일 복사 스크립트가 평가하지는 않습니다.

교체 결과의 주요 파일:

| PC 대상 | 역할 |
|---|---|
| `recycling_app\lib\main.dart` | 사진·번호 카드·직접 안내 찾기 화면 |
| `recycling_app\lib\data\items.dart` | 4종류·16개 안내 선택 품목 |
| `recycling_app\lib\data\guides.dart` | 공식 안내 등록 위치, 현재 등록 없음 |
| `recycling_app\lib\models\`, `services\`, `state\`, `ui\` | 응답 처리·독립 확인 상태·안내 화면 등, 전부 복사 필요 |
| `recycling_app\pubspec.yaml` | url_launcher 의존성 추가 |
| `recycling_app\test\` | 기존 카운터 테스트를 새 기능 테스트로 교체 |
| `recycling_server\server.py` | 동일 번호를 박스 이미지·응답에 넣는 서버 |
| `recycling_server\requirements*.txt`, `tests\` | 서버 실행/테스트 의존성 및 테스트 |
| **`recycling_server\best.pt`** | **본인이 지정한 새 학습 모델** |

main.dart 하나만 복사하면 필요한 import 파일이 빠지므로 lib 하위 파일을 함께 적용해야 합니다. 서버만 또는 앱만 교체하지 말고 둘 다 교체하세요.

## 5. 앱 의존성 설치와 검사

새 VS Code 터미널(PowerShell)에서:

```powershell
cd C:\Users\haewo\recycling_app
flutter --version
flutter pub get
dart format lib test
flutter analyze
flutter test
```

`url_launcher`는 `flutter pub get`으로 설치됩니다. Flutter SDK의 Dart 버전이 첨부 원본 조건 `^3.13.4`와 맞아야 합니다. 이 요구사항은 원본대로 보존했습니다. 버전 오류가 있으면 표시된 요구 버전과 `flutter --version` 결과를 확인하세요.

여기서 오류가 나면 앱 실행 전에 해당 오류를 확인하세요. 이 클라우드 환경에는 Flutter SDK가 없어 실제 analyze/test를 실행하지 못했습니다.

## 6. 서버 실행 — 터미널 A

기존에 서버를 실행하던 Python 인터프리터/가상환경을 사용하세요. VS Code의 Python 인터프리터 선택도 확인합니다.

```powershell
cd C:\Users\haewo\recycling_server
python -c "import sys; print(sys.executable)"
python -m pip install -r requirements.txt
python -m uvicorn server:app --host 127.0.0.1 --port 8000
```

기존 환경이 `.venv`이고 활성화가 번거로우면 실행 파일을 직접 지정할 수도 있습니다. 실제로 `.venv` 폴더가 있을 때만 사용하세요.

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn server:app --host 127.0.0.1 --port 8000
```

둘 중 실제 환경에 맞는 **한 가지 방식만** 사용합니다. `Application startup complete` 등이 표시되면 서버 터미널은 그대로 켜 둡니다. 오류가 난 상태에서 다음 단계로 넘어가지 마세요.

새 터미널 또는 PC 브라우저에서 확인:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8000/health' | ConvertTo-Json -Depth 4
```

기대하는 클래스:

```json
{"status":"ok","classes":{"0":"plastic","1":"paper","2":"metal"}}
```

health는 실행 상태·클래스 확인용입니다. 새 파일인지 확인하려면 모델 해시를 봅니다.

```powershell
Get-FileHash 'C:\Users\haewo\Downloads\best_background35.pt' -Algorithm SHA256
Get-FileHash 'C:\Users\haewo\recycling_server\best.pt' -Algorithm SHA256
```

두 Hash가 같아야 합니다. 그리고 **교체 후 새로 시작한 서버**여야 합니다. health의 클래스가 같다는 사실만으로 모델 버전까지 확인되는 것은 아닙니다.

## 7. S25 USB 연결과 앱 실행 — 터미널 B

서버 터미널 A는 닫지 말고, **별도 PowerShell 터미널 B**에서:

```powershell
$package = "$env:USERPROFILE\Downloads\recycling_s25_update_v1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$package\windows_tools\Connect-S25.ps1" -RunApp
```

스크립트는 adb를 PATH 또는 기본 Android SDK 위치에서 찾고, 승인된 실제 기기 한 대를 선택한 뒤 서버 health를 확인합니다. 그다음 다음 연결을 만들고 `flutter run -d 기기ID`를 실행합니다.

```text
휴대폰 앱의 127.0.0.1:8000
             ↓ adb reverse / USB
PC의 127.0.0.1:8000 (FastAPI)
```

기기가 여러 대이면 지정하세요.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$package\windows_tools\Connect-S25.ps1" -DeviceId '실제_adb_기기ID' -RunApp
```

`실제_adb_기기ID`라는 글자를 그대로 쓰는 것이 아니라 아래 adb devices에 표시되는 ID로 바꿉니다.

### 자동 스크립트 대신 직접 연결하는 코드

adb가 PATH에 있으면:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
adb reverse --list
cd C:\Users\haewo\recycling_app
flutter devices
flutter run
```

기기 선택이 나오면 S25를 고릅니다. 기기 ID를 알고 있으면 명시합니다.

```powershell
adb -s '실제_기기ID' reverse tcp:8000 tcp:8000
flutter run -d '실제_기기ID'
```

adb 명령을 찾지 못하면 기본 설치 경로를 직접 사용합니다.

```powershell
$adbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
Test-Path $adbPath
& $adbPath devices
& $adbPath reverse tcp:8000 tcp:8000
& $adbPath reverse --list
```

Test-Path가 False면 Android SDK를 설치한 위치가 다를 수 있습니다. `flutter doctor -v` 또는 Android Studio의 SDK 설정에서 실제 SDK 경로를 확인하고 adbPath를 바꾸세요.

## 8. 실제 휴대폰에서 확인

1. S25에서 앱이 실행되는지 확인.
2. 갤러리에서 물건 1개가 있는 원본 사진을 선택 → 분석하기.
3. 사진의 #1과 카드 #1이 일치하는지 확인.
4. 여러 물건 사진에서도 각각 확인/수정/제외/복원하고 다른 카드가 유지되는지 확인.
5. 확인한 품목의 안내를 열고 뒤로 돌아와도 상태가 남는지 확인.
6. 공식 안내는 아직 등록하지 않았으므로 **준비 중 표시가 정상**입니다.
7. 사진 없이 직접 배출 방법 찾기도 확인.
8. 새 사진 선택은 초기화, 선택 취소는 기존 상태 유지인지 확인.

휴대폰 브라우저에서 `http://127.0.0.1:8000/health`를 직접 열어 볼 수도 있습니다. PC에서는 열리는데 S25에서 열리지 않으면 먼저 adb reverse/USB 연결을 확인하세요.

USB를 뽑았다가 다시 연결하면 다음 명령을 다시 실행하세요.

```powershell
adb reverse tcp:8000 tcp:8000
```

서버 코드를 바꾸거나 best.pt를 교체했으면 서버를 Ctrl+C로 종료 후 다시 시작합니다. Dart 패키지/소스 교체 후에는 앱도 완전히 다시 실행합니다.

## 9. 자주 막히는 상황

| 증상 | 확인 |
|---|---|
| adb devices에 아무것도 없음 | 데이터 케이블·USB 포트·휴대폰 USB 디버깅·Windows 드라이버 |
| unauthorized | 휴대폰 잠금 해제 후 디버깅 허용. 필요하면 케이블 재연결 |
| offline | USB 재연결 후 adb devices 재확인 |
| more than one device | adb -s 기기ID / Connect-S25.ps1 -DeviceId 지정 |
| adb 명령을 찾지 못함 | SDK platform-tools의 adb.exe 경로 직접 사용 |
| 연결 스크립트가 서버 미실행이라고 함 | 터미널 A의 Python 환경·uvicorn 오류 확인 |
| 8000 포트 사용 중 | 이전 서버 종료. 다른 프로세스를 무조건 종료하지 말고 실행 중 터미널 확인 |
| 새 모델인데 결과가 이전 같음 | 파일 해시 비교, 정확한 서버 폴더, 서버 재시작 확인 |
| 응답 형식/업데이트 오류 | 앱과 새 server.py를 모두 적용했는지 확인 |
| Cleartext HTTP traffic 오류 | 아래 Android 설정을 기존 manifest에서 확인 |
| USB 연결 뒤 분석 실패 | adb reverse 다시 적용, PC/휴대폰 health 각각 확인 |
| 안내 준비 중 | 아직 공식 안내 등록 전이므로 정상 |

### HTTP 권한 오류가 실제로 있을 때만 Android 설정 확인

원래 앱이 이미 연결되었다면 기존 설정을 유지하세요. 다음 파일의 내용을 **통째로 덮어쓰지 마세요**.

```text
C:\Users\haewo\recycling_app\android\app\src\main\AndroidManifest.xml
```

`<manifest ...>` 안에서 `<application ...>` 밖에 다음 권한이 있는지 확인합니다. 없으면 추가합니다.

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

기존 `<application` 시작 태그의 다른 속성은 유지한 채 개발용 HTTP가 필요한 경우 아래 속성을 추가/확인합니다.

```xml
android:usesCleartextTraffic="true"
```

같은 속성을 두 번 추가하지 마세요. 변경했다면 앱을 다시 빌드/실행합니다. 이 ZIP은 기존 Android 설정을 자동 변경하지 않습니다.

## 검증 범위

앱/서버 소스의 테스트·구문 검사 결과는 `앱_변경기록/검증결과.json`에 있습니다. 서버 계약 테스트 8개 및 기존 실제 모델 API 연결 검사는 통과했습니다. Flutter analyze/test, Windows PowerShell 스크립트 실행, S25 실기기 실행은 이 Linux 클라우드에서 수행하지 못했습니다. 아래 스크립트는 본인의 Windows에서 실행해야 하며, 실행 전 ModelPath와 프로젝트 경로를 확인하세요. 안내 문서와 파일 교체만으로 새 모델의 성능이 검증되는 것은 아닙니다.
