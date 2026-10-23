# Flutter 앱 교체용 소스

기존 Windows Flutter 프로젝트에 `lib`, `test`, `pubspec.yaml`을 합쳐 적용하세요. Android/iOS 플랫폼 폴더는 포함하지 않았습니다. 기존 권한과 USB 연결 설정을 유지합니다.

전체 설명은 [적용방법](../앱_변경기록/적용방법.md)을 참고하세요. 새 서버와 함께 적용해야 탐지 번호와 이미지가 일치합니다.

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run
```

Flutter 테스트는 클라우드 환경에서 실행하지 못했습니다. 모델 성능을 수정하거나 재학습하는 앱 변경이 아닙니다.
