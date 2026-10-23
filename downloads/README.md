# 받을 파일과 정확한 위치

## 이미 설치했고 Flutter 화면 테스트 4개가 실패한 경우

서버·모델을 다시 설치하지 말고 **recycling_flutter_patch_v2.zip**만 받으세요.

- 패치 파일: https://github.com/haewonp00/my-codex-test/blob/main/downloads/recycling_flutter_patch_v2.zip
- 단계별 적용: [Flutter_패치_v2_적용.md](Flutter_패치_v2_적용.md)

이 패치는 Dart 파일 6개만 백업 후 교체하며, best.pt·서버·pubspec.yaml·Android 설정은 변경하지 않습니다. 수정 후 Flutter 검사는 본인의 Windows에서 실행해야 합니다.

## 1. 앱·서버·USB 연결 도구 ZIP

GitHub에서 이 폴더의 **recycling_s25_update_v1.zip** 파일을 엽니다.

- 파일 페이지: https://github.com/haewonp00/my-codex-test/blob/main/downloads/recycling_s25_update_v1.zip
- 다운로드 링크: https://github.com/haewonp00/my-codex-test/raw/refs/heads/main/downloads/recycling_s25_update_v1.zip

파일 화면의 Download raw file(아래 화살표) 또는 View raw로 ZIP을 받습니다. 받은 파일을 탐색기 → 다운로드에서 찾아 ‘모두 압축 풀기’ 합니다. 아래 실행 명령은 압축 해제 위치가 `C:\Users\haewo\Downloads\recycling_s25_update_v1`일 때의 예시입니다. 브라우저가 (1) 등을 붙였거나 다른 경로에 풀었으면 실제 폴더명에 맞춰 바꾸세요.

ZIP 안에는 recycling_app, recycling_server, windows_tools, 앱_변경기록이 있습니다. 개별 소스 파일을 하나씩 다운로드할 필요가 없습니다. 모델은 별도입니다.

## 2. 새 모델 best.pt는 Google Drive의 이 위치

작성한 학습 노트북의 기본값 SAVE_TO_DRIVE=True로 학습한 경우:

**Google Drive → 내 드라이브 → recycling_experiments → 학습 실행 때 생성된 날짜시간_식별자 폴더 → background35_v1 → weights → best.pt**

1. https://drive.google.com/drive/my-drive 를 엽니다. 학습 때 연결한 Google 계정인지 확인합니다.
2. 내 드라이브에서 recycling_experiments 폴더를 더블클릭합니다.
3. 그 안에서 해당 학습 실행의 날짜시간_식별자 폴더를 엽니다. 생성 형식은 yyyyMMdd_HHmmss_8자리식별자입니다. 날짜시간은 UTC이므로 한국 시간과 9시간 차이가 납니다. 실행이 여러 개면 해당 학습 기록을 확인하고 선택하세요.
4. background35_v1 폴더를 엽니다.
5. weights 폴더를 엽니다.
6. best.pt를 마우스 오른쪽 클릭 → 다운로드합니다.
7. PC 탐색기의 다운로드 폴더에서 받은 파일을 best_background35.pt로 이름을 바꿉니다.

선택할 파일은 **background35_v1/weights/best.pt**입니다. control_v1이나 last.pt를 선택하지 않습니다. 폴더/모델이 실제로 생성됐는지는 본인 Drive에서 확인해야 합니다. 사용자의 Drive에는 이 환경이 접근할 수 없습니다.

새 학습 모델은 이 작업 공간으로 업로드되지 않았기 때문에 GitHub에 포함되어 있지 않습니다. 소스 ZIP을 받는 것과 새 모델을 받는 것은 별개의 단계입니다.

## 3. Colab 왼쪽 파일 창에서 찾는 경우

학습한 노트북으로 돌아가 Google Drive를 연결한 상태에서:

1. 왼쪽 세로 메뉴의 폴더 모양 ‘파일’을 누릅니다.
2. drive → MyDrive → recycling_experiments 순서로 엽니다.
3. 해당 날짜시간_식별자 → background35_v1 → weights를 엽니다.
4. best.pt 오른쪽 ⋮ → 다운로드합니다.

전체 경로는 다음 구조입니다. ‘학습실행폴더’는 설명용 자리이며 실제로는 생성된 날짜시간_식별자입니다.

```text
/content/drive/MyDrive/recycling_experiments/학습실행폴더/background35_v1/weights/best.pt
```

Colab 파일 창에 drive가 없다면 다음 셀을 실행하고 같은 Google 계정의 Drive 접근을 허용한 뒤 파일 창을 새로고침합니다.

```python
from google.colab import drive
drive.mount('/content/drive')
```

## 4. Drive에 폴더가 없을 때

- 학습 노트북에서 SAVE_TO_DRIVE=False로 바꿨다면 Colab 파일 창 → content → recycling_experiments → 해당 학습 폴더 → background35_v1 → weights → best.pt를 확인합니다.
- 이 경우 경로는 `/content/recycling_experiments/학습실행폴더/background35_v1/weights/best.pt`입니다.
- Drive 저장을 껐고 런타임이 초기화됐다면 Colab 임시 파일은 사라졌을 수 있습니다. PC에 이미 다운로드한 결과 ZIP을 확인하세요. 파일이 실제로 남아 있지 않다면 새 모델을 있다고 가정할 수 없습니다.
- 기본값은 Drive 저장이 켜져 있습니다. 먼저 학습한 Google 계정과 Drive 폴더를 확인하세요.

학습 노트북의 ‘4. 새 모델 파일 받기’ 셀은 전체 실험 결과 ZIP을 다운로드합니다. 그 ZIP을 이미 받은 경우 압축을 풀고 **background35_v1 → weights → best.pt**를 찾으면 됩니다.

## 5. 두 파일을 받은 다음 실행

필요한 두 가지:

1. 앱·서버·USB 도구: recycling_s25_update_v1.zip → 압축 해제
2. 새 모델: best.pt → 다운로드 폴더에서 best_background35.pt로 이름 변경

PowerShell에서:

```powershell
$package = "$env:USERPROFILE\Downloads\recycling_s25_update_v1"
$newModel = "$env:USERPROFILE\Downloads\best_background35.pt"
Test-Path "$package\windows_tools\Update-AppFiles.ps1"
Test-Path $newModel
```

둘 다 True여야 합니다. 기존 서버와 flutter run을 종료한 다음:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$package\windows_tools\Update-AppFiles.ps1" -ModelPath $newModel -PackageRoot $package
```

기존 소스와 모델을 백업하고 새 모델을 `C:\Users\haewo\recycling_server\best.pt`에 설치합니다. 나머지 설치·서버 실행·S25 USB 연결은 ZIP의 windows_tools/S25_USB_실행안내.md를 순서대로 따르세요.
