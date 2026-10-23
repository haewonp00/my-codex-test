# 포트폴리오 성능 비교 (평가만 실행)

이전 기록: label_fix_v1, Val 90장/153개 객체. Precision 64.30%, Recall 63.63%, mAP50 64.36%, mAP50–95 52.08%. 클래스별 기록은 `수정안_v2/검증기록/existing_model_val_evaluation.json`에 있습니다. 기존 Test 수치는 없으며 mAP75도 과거 기록에는 없습니다.

Colab 노트북을 열고 새 best.pt를 업로드하거나 Drive 경로를 지정하세요. 기본 CPU에서 같은 Val 90장과 배경 16장을 평가합니다. 실제 모델 해시와 데이터 해시·환경을 기록합니다. 이전 best.pt도 함께 제공하면 두 모델을 같은 환경에서 재평가합니다. 이전 모델 SHA256이 기록된 실제 label_fix_v1과 일치해야 하며, 새 모델로 이전 모델을 잘못 선택하면 차단합니다.

출력: 전체/클래스별 P·R·F1·mAP50·mAP75·mAP50–95, % 단위 표와 pp 변화량, AP@IoU 0.50~0.95, 혼동행렬 CSV·PNG, PR/F1/P/R 곡선, val 예측 샘플, 배경 오탐 지표·탐지 박스·사진, 모델/데이터 해시·환경 JSON, 비교 그래프 PNG/SVG, 한국어 보고서 및 결과 ZIP. mAP75·곡선·혼동행렬은 과거 기록만으로 복원하지 않습니다. 이전 모델을 재평가하면 새로 생성됩니다.

객체 P/R은 Ultralytics의 PR/F1 운용점 지표로, confidence=0.25 고정 P/R이 아닙니다. F1은 표시된 P/R의 조화평균이며 ALL의 F1을 클래스 평균 F1이라고 부르지 않습니다. 배경만 confidence=0.25로 고정합니다. 혼동행렬 CSV 행은 예측, 열은 정답입니다. 배경 사진에서 mAP·Recall을 계산하지 않습니다. 추론 시간은 장비 의존 진단용 JSON으로 저장하며 과거와 속도 향상을 비교하지 않습니다.

이전 모델이 없으면 기록 참조 비교입니다. CPU여도 Python/torch 버전 차이가 있으므로 가능하면 두 체크포인트를 같은 환경에서 재평가하세요. 기본 split은 val이며 최종 독립 테스트가 아닙니다. split=test를 선택하면서 이전 모델을 제공하지 않으면 새 Test 값만 출력하고 과거 Val 값을 Test 비교에 섞지 않습니다. 배경 16장 역시 개발 평가이며 장소 독립성은 미확인입니다. 이 작업은 재학습하지 않습니다.

명령행 실행 예:

```bash
pip install ultralytics==8.4.182 'pandas>=2,<3' PyYAML Pillow matplotlib
python portfolio_evaluate.py --repo /프로젝트/데이터버전6eefd24 --new /새모델/best.pt --old /기존label_fix_v1/best.pt --split val --device cpu --out /새결과폴더
```

`--old`는 선택입니다. 새로운 결과 폴더를 사용해야 하며 소스 val/test는 임시 사본에서 평가합니다.
