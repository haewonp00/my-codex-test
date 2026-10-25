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


안내 이미지 업데이트: 사용자 제공 PNG 6장을 assets/guides에 포함했습니다. 9개 세부 품목에서 로컬 이미지와 확대 기능을 사용합니다. 나머지 품목은 준비 중입니다. [이미지 적용 순서](../downloads/비닐_복합재질_직접안내_v5.md)를 참고하세요. 원문 출처·이용 조건은 이미지 내 표기이며 독립 검증되지 않았습니다.
