# YOLO 분리수거 오류 수정 v2

이번 수정은 **학습 데이터 일부와 재현·평가 코드의 수정**이다. 재학습하지 않았으며 기존 best.pt가 개선됐다고 주장하지 않는다. 기존 원본 ZIP, 기존 27개 패치, GitHub 원본 노트북, best.pt/last.pt는 변경하지 않았다.

## 실제 바꾼 라벨

실제 starter 이미지를 직접 보고 train의 다음 두 장만 수정했다.

| 파일 | 기존 라벨 | 수정 | 근거 |
|---|---|---|---|
| 0_0000.jpg | 병 전체 1개 + 부착된 뚜껑 1개 | 병 전체 1개만 유지 | 같은 병의 뚜껑을 별도 객체로 중복 표시 |
| 0_0005.jpg | 병 전체 1개 + 부착된 뚜껑 1개 | 병 전체 1개만 유지 | 같은 병의 뚜껑을 별도 객체로 중복 표시 |

새 박스 좌표를 추측해 만들지 않았다. 원래 존재하던 전체 물체 박스를 유지했다. `reviewed_label_fix_v2.json`에 이미지 SHA256, 변경 전후의 실제 텍스트, 검토 이유가 있다. `검토_근거/`에는 이 두 장의 실제 원본 이미지와 수정된 라벨을 포함했다. 이 라벨은 원본 위에 직접 덮어쓰지 말고 apply-reviewed로 별도 사본에 적용한다.

기존 label_fix_v1 구성(train 731장, plastic/paper/metal 객체 390/342/393개)을 재현한 뒤 두 수정을 적용했다. 새 사본의 객체 수는 **388/342/393개**, 사진 수와 클래스 수는 같다. val/test 전체 이미지·라벨은 해시로 동일함을 확인했다.

큰 박스가 작은 박스를 포함한다고 모두 오류인 것은 아니다. 두 장 이외에는 자동 수정하지 않았다. 수정 후에도 train 79장에 포함 관계의 검토 후보가 남으며, 전체 라벨 감사가 끝난 상태가 아니다. val/test에도 각각 12장 후보가 있다. 이 숫자는 오류 수가 아니다. 본 코드는 사용자가 원본을 보존하도록 val/test 라벨을 바꾸지 않으며, 추후 정답 기준 감사가 필요하면 평가 데이터 버전을 별도로 기록해야 한다.

## 코드에서 바꾼 부분

1. **재현 가능한 데이터 준비:** 실제 starter + supplement ZIP + 기존 v1 JSON만 사용한다. 새 사본에만 쓴다. ZIP 경로, 클래스 매핑, 라벨 형식, 이미지·라벨 대응, 파일 충돌을 검사한다. 실패하면 임시 준비 폴더가 정리되고 원본은 보존된다.
2. **전체/부분 라벨 검토:** 자동 합치기 대신 실제 좌표에 근거한 CSV 후보 목록과 노트북 시각 검토 기능을 제공한다. 확인된 v2 패치는 원본 이미지 해시와 before 텍스트가 정확히 맞아야 적용된다.
3. **배경 오탐의 별도 평가:** 독립 배경 사진에서 '오탐 사진 비율'과 '사진당 오탐 수'를 기록한다. 배경만 있는 사진에서 mAP/Recall을 억지로 계산하지 않는다. 자료가 없으면 미실행/null로 남긴다. 학습에 사용한 동일 배경을 평가에 넣으면 차단한다.
4. **추론 재현 기록:** 실제 best.pt의 SHA256, 클래스 매핑, EXIF 보정 후 크기, confidence, 박스 좌표, 화면 면적을 저장한다. PIL RGB로 입력하며 임의의 좌우 늘리기나 중복 정규화를 하지 않는다. 탐지가 없으면 결과는 그대로 빈 목록이다.
5. **재학습 기본 차단:** train-plan은 계획만 출력한다. 실제 학습에는 별도 --execute와 --reviewed, 실제 사전학습 가중치가 필요하다. 노트북에는 --execute가 없다. 초기 비교의 epochs=20, imgsz=640, batch=8, seed=42를 유지한다.

단순히 confidence를 올리거나, 큰 paper 박스를 모두 지우거나, 캔처럼 보이는 물체를 강제로 metal로 바꾸는 규칙은 넣지 않았다. 그런 규칙은 실제 paper를 놓치거나 성능을 좋아 보이게 만들 수 있다.

## 실행 방법

가장 쉬운 방법은 **오류수정_v2_실행.ipynb**를 열어 상단 경로를 설정하고 순서대로 실행하는 것이다. 현재 환경 Python은 `/workspace/onboarding/venv/bin/python`이다. 다른 환경에서는 requirements.txt를 참고한다. requirements는 기존 Colab CUDA 환경의 완전한 잠금 파일이 아니며 CPU 개발 환경과 원래 GPU 학습 환경은 다르다.

명령행 예시(파일 경로와 출력 폴더는 실제 위치로 바꾼다):

```bash
python recycling_fix.py prepare \
  --starter '/실제경로/recycling_yolo_starter (1).zip' \
  --supplement '/실제경로/recycling_supplement_v1.zip' \
  --patch '/실제경로/recycling_label_patch_v1 (1).json' \
  --out /새경로/baseline_data

python recycling_fix.py apply-reviewed \
  --data /새경로/baseline_data/data.yaml \
  --patch reviewed_label_fix_v2.json \
  --out /새경로/reviewed_data

python recycling_fix.py audit \
  --data /새경로/reviewed_data/data.yaml --out /새경로/audit

python recycling_fix.py predict \
  --weights /실제경로/best.pt --images /실제경로/원본사진.jpg \
  --out /새경로/photo_results

python recycling_fix.py evaluate \
  --weights /실제경로/best.pt --data /새경로/reviewed_data/data.yaml \
  --split val --out /새경로/val_results

python recycling_fix.py train-plan \
  --data /새경로/reviewed_data/data.yaml \
  --pretrained /실제경로/yolo11n.pt --out /새경로/future_training
```

prepare와 apply-reviewed는 기존 출력 폴더를 덮어쓰지 않는다. 동일 출력에 다시 실행하면 중단한다. 새 버전·실험에는 새 출력 경로를 쓴다.

독립 배경을 평가할 때는 evaluate에 `--negative-eval-dir /실제경로/독립배경 --confirm-negatives`를 추가한다. 디렉터리 안의 모든 사진에 대상 물체가 0개인지 사람이 확인해야 한다. 학습 배경과 평가 배경을 분리한다.

추후 실제로 확인된 새 배경을 학습에 추가하려면 prepare에 `--negative-dir /실제경로/학습배경 --confirm-negatives`를 사용한다. **실제 제공된 이미지가 있어야만** RGB/EXIF를 정리한 학습 사본과 그 이미지의 빈 라벨을 만든다. 없는 이미지나 기존 물체의 라벨을 발명하지 않는다. 현재는 새 배경 원본이 없어서 이 기능으로 어떤 자료도 추가하지 않았다.

정량 평가는 confidence 0.001로 후보를 수집하고, 실제 사진과 배경 오탐은 기본 confidence 0.25에서 측정한다. 두 값의 목적이 다르므로 비교할 때 기록된 설정을 함께 확인한다.

## 이번에 검증한 결과와 한계

- 실제 업로드 ZIP으로 baseline 데이터 재구성, v2 두 장 패치 적용, 전체 클래스·객체 수 검사 통과.
- val/test 이미지·라벨 파일의 해시 동일성, 원본 가중치와 ZIP 보존 확인.
- 라벨 좌표·클래스 매핑·학습 차단 등의 단위 테스트 통과. 구체 결과는 검증기록/verification.json에 있다.
- 실제 기존 best.pt로 val 90장 / 객체 153개 평가: Precision 0.6430, Recall 0.6363, mAP50 0.6436, mAP50-95 0.5208. 이는 **수정 전부터 있던 모델**의 CPU 평가이며 개선 수치가 아니다.
- 실제 predict 명령의 로딩·추론·결과 저장을 기존 supplement train 사진 1장으로 확인했다. 학습에 쓰인 사진이므로 독립 정확도 평가가 아니다.
- 재학습을 실행하지 않았다. Test 세트에서 추론하지 않았다.
- 새 배경 오탐률은 아직 측정하지 않았다. 채팅의 원본 사진은 여기서 파일로 접근할 수 없고 오류 분석 ZIP에는 박스·글자가 그려진 JPG만 있다. **annotated JPG를 원본 대신 모델에 다시 입력하지 않았다.** 실제 원본 사진 파일을 별도로 제공해야 통제된 재실행이 가능하다.
- Flutter·서버 코드는 없으므로 앱 전처리를 수정했다고 주장하지 않는다.

기존 label_fix_v1과 라벨 변경 실험을 비교할 때는 같은 사전학습 yolo11n.pt·seed·학습 설정을 사용한다. 기존 가중치에 이어 학습하면 데이터 수정 효과와 추가 학습 효과가 섞인다. Negative Sample 효과는 라벨 수정 효과와 별도로 비교한다. 실패 사진 3장은 개발용 자료이며 최종 성능은 새로 분리한 사진에서 평가한다.

## 데이터 출처

검토 근거 이미지는 사용자가 제공한 starter ZIP에서 바이트 그대로 복사했다. starter README의 출처 표기: https://universe.roboflow.com/material-identification/garbage-classification-3/dataset/2 (CC BY 4.0로 표기). 원출처의 material-identification / garbage-classification-3 데이터셋에서 제공된 plastic 이미지다. 전체 이미지와 원저작권·추가 속성 정보는 원본 자료를 참조한다. v2의 변경은 위 두 train 라벨의 부착 뚜껑 박스 제거뿐이다.
