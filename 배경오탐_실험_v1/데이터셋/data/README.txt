초기 분리수거 YOLO 탐지 데이터셋
출처: 사용자가 제공한 archive.zip
원본: https://universe.roboflow.com/material-identification/garbage-classification-3/dataset/2
원본 data.yaml 표기 라이선스: CC BY 4.0. 원저작자와 위 출처를 표시하세요.
변경: PLASTIC→plastic, PAPER와 CARDBOARD→paper, METAL→metal. 다른 범주가 라벨에 함께 있는 이미지는 제외.
최대 클래스별 300장. 단일 대상 범주만 포함하며 바운딩박스 1~5개, 각 박스 면적 1% 이상인 이미지 선별.
동일 원본 파일명으로 보이는 변형 이미지와 동일 이미지 바이트 중복 제거 후 80/10/10 분할. 서로 다른 파일명의 시각적 유사 이미지까지 검증하지는 않음.
주의: metal에는 캔 이외의 금속도 포함될 수 있음. paper에는 판지도 포함. 라벨의 의미·정확성을 전수 수작업 검사하지 않은 초기 실험용 선별본.
이미지에서 인식한 재질이 실제 재활용 가능 여부를 뜻하지 않음.

Colab 실행 예시 (ZIP을 /content에 업로드한 뒤):
!pip -q install ultralytics
!unzip -q /content/recycling_yolo_starter.zip -d /content
from pathlib import Path
import yaml
from ultralytics import YOLO
root = Path('/content/recycling_yolo_starter')
p = root / 'data.yaml'
config = yaml.safe_load(p.read_text())
config['path'] = str(root)
p.write_text(yaml.safe_dump(config, sort_keys=False))
model = YOLO('yolov8n.pt')
model.train(data=str(p), epochs=20, imgsz=640, batch=8)

20 epochs는 첫 작동 확인을 위한 설정이며 성능을 보장하지 않습니다.
