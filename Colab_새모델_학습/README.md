# 새 모델 Colab 학습

`배경오탐_새모델_Colab.ipynb`를 Colab에서 열고 GPU(T4)를 선택한 뒤 위에서 아래로 실행합니다. 기본은 배경 35장을 추가한 766장 데이터로 새 YOLO11n 모델 1개를 학습합니다. 기존 best.pt는 필요하지 않으며 COCO 사전학습 yolo11n.pt에서 시작합니다. epochs=20, imgsz=640, batch=8, seed=42입니다. 배경으로 인한 개선 여부를 판단하려면 RUN_CONTROL=True로 같은 조건의 원래 731장 대조군도 학습하세요.

결과는 기본적으로 Google Drive의 `MyDrive/recycling_experiments/<고유실험번호>/background35_v1/weights/best.pt`에 저장됩니다. 마지막 셀에서 전체 실험 ZIP을 다운로드할 수 있습니다. SAVE_TO_DRIVE=False이면 Colab 종료 전 ZIP을 반드시 다운로드하세요.

데이터 커밋을 6eefd2426392645d35653c23a422c86a1e626136으로 고정하고 이미지와 기존 val/test 해시를 검사합니다. 원본 저장소 대신 /content의 별도 사본으로 학습하며, 기존 모델·원본 파일은 덮어쓰지 않습니다. 데이터의 장소 독립성은 미확인입니다. val 및 개발용 배경 16장을 평가하며 test 90장은 사용하지 않습니다. 같은 16장으로 반복 튜닝한 결과를 최종 독립 성능으로 주장하지 마세요.

이번에 제공하는 것은 실행 코드입니다. 작성 환경에서는 모델을 학습하거나 새 성능 수치를 만들지 않았습니다. 기존 실패 모델의 13/16 배경 오탐 기록은 참고이며 배경 추가 효과의 유일한 근거가 될 수 없습니다. 오탐과 객체 Precision/Recall/mAP를 함께 비교하세요. 라벨 수정안 v2는 이번 학습에 적용하지 않았습니다.

`colab_training.py`는 코드 검토용 Python 내보내기입니다. Google Colab 전용 Drive/다운로드 함수가 있으므로 로컬 PC용 스크립트가 아닙니다.
