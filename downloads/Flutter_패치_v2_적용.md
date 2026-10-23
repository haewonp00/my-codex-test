# Flutter 화면 테스트·분석 경고 수정 패치 v2

사용자 Windows 로그: flutter pub get 성공, flutter analyze info 5개, flutter test 13개 통과/4개 실패.

원인과 수정:

1. ListView는 화면 밖 위젯을 아직 만들지 않을 수 있습니다. 기존 테스트의 ensureVisible은 존재하지 않는 Element를 찾으려 해 Bad state: No element로 실패했습니다. 화면별 스크롤에 고유 Key를 붙이고 해당 목록을 scrollUntilVisible로 스크롤한 뒤 조작하도록 수정했습니다. 요약 개수·안내·12번째 카드도 먼저 스크롤하여 찾습니다.
2. 품목 선택 직후 새 프레임을 기다리지 않고 확인 버튼을 눌러 이전의 비활성 버튼이 유지되는 문제가 있었습니다. 선택마다 pumpAndSettle 후 버튼이 활성화됐는지 검사하고 누릅니다. 검증을 삭제하거나 실패를 무시하지 않았습니다.
3. if 본문을 중괄호로 감싸고 foundation.dart가 이미 제공하는 Uint8List의 중복 import를 제거했습니다.

앱 동작을 바꾸는 로직 수정 없이 테스트용 Key와 구문 스타일을 수정합니다. 서버·best.pt·pubspec.yaml·Android 설정은 교체하지 않습니다.

## 다운로드와 적용

1. GitHub downloads/recycling_flutter_patch_v2.zip 파일 화면의 Download raw file(↓) 또는 View raw로 받습니다.
2. 다운로드 폴더에서 모두 압축 풀기 합니다. 예시 폴더는 C:\Users\haewo\Downloads\recycling_flutter_patch_v2 입니다.
3. 실행 중인 flutter run이 있다면 종료하고 PowerShell에서 실행합니다.

```powershell
$patch = "$env:USERPROFILE\Downloads\recycling_flutter_patch_v2"
Test-Path "$patch\Apply-FlutterPatch.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$patch\Apply-FlutterPatch.ps1" -PatchRoot $patch -AppRoot 'C:\Users\haewo\recycling_app'
```

스크립트는 아래 6개 파일을 백업 후 복사합니다.

- lib/main.dart
- lib/data/guides.dart
- lib/state/photo_controller.dart
- lib/ui/guide_page.dart
- lib/ui/item_picker.dart
- test/widget_test.dart

기존 파일 백업은 사용자 폴더의 recycling_flutter_patch_backup_날짜시간에 있습니다.

```powershell
cd C:\Users\haewo\recycling_app
dart format lib test
flutter analyze
flutter test
```

패키지 버전 변경이 없으므로 flutter pub upgrade를 실행할 필요는 없습니다. 패키지 최신 버전 알림은 설치 실패가 아닙니다.

## 확인 범위

변경 후 Dart 구문 및 PowerShell 구문 검사를 완료했습니다. 이 Linux 환경에는 Flutter SDK/Windows PowerShell이 없어 수정 후 flutter analyze/test와 Windows 스크립트 실행은 수행하지 못했습니다. 수정 후 모든 테스트가 통과했다고 주장하지 않습니다. 위 명령 결과를 확인해야 합니다. 모델 재학습이나 새 성능 측정은 하지 않았습니다.
