# Exported from the Colab notebook. Run in Google Colab with GPU.


# # 배경 오탐 개선 후보 모델 — Google Colab 학습
# 
# Colab 메뉴 **런타임 → 런타임 유형 변경 → T4 GPU**를 선택한 뒤 순서대로 실행하세요. 이 노트북은 실제 학습을 실행합니다. 기존 best.pt를 업로드할 필요 없이 COCO 사전학습 `yolo11n.pt`에서 새로 시작합니다.
# 
# 기본: 학습 후보 766장(기존 731 + 빈 배경 35), val 90장, 별도 빈 배경 평가 16장, 20 epochs. 기존 두 장의 라벨 수정안은 섞지 않습니다. 클래스는 plastic(0), paper(1), metal(2)입니다. 기존 모델과 원본 데이터는 덮어쓰지 않습니다.
# 
# **장소 묶음은 추정입니다.** 촬영자가 같은 장소의 사진이 학습/평가 양쪽에 들어간 것을 확인하면 분리를 먼저 고치고 새 데이터 버전으로 실험하세요. 아래 평가는 개발용이며 최종 독립 테스트가 아닙니다. 재학습이 오탐 감소를 보장하지는 않습니다.

# GPU용 torch는 Colab이 제공하는 것을 유지합니다.
import subprocess, sys
subprocess.run([sys.executable, '-m', 'pip', 'install', '-q', 'ultralytics==8.4.182', 'PyYAML', 'Pillow', 'pandas'], check=True)

from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
import csv, hashlib, json, shutil, subprocess, sys, uuid
import torch, yaml, pandas as pd
import ultralytics
from ultralytics import YOLO
from PIL import Image, ImageOps
assert ultralytics.__version__ == '8.4.182'
assert torch.cuda.is_available(), 'GPU 런타임으로 변경한 뒤 다시 실행하세요.'
print('GPU:', torch.cuda.get_device_name(0))
print('ultralytics:', ultralytics.__version__, 'torch:', torch.__version__)

SAVE_TO_DRIVE = True  # 런타임이 종료되어도 모델을 보존하도록 권장
RUN_CONTROL = False  # True: 배경 추가 없는 대조군도 같은 조건으로 학습(총 2회)
EPOCHS, IMGSZ, BATCH, SEED = 20, 640, 8, 42
CONF, IOU = 0.25, 0.7
NAMES = {0: 'plastic', 1: 'paper', 2: 'metal'}
DATA_COMMIT = '6eefd2426392645d35653c23a422c86a1e626136'
REPOSITORY = 'https://github.com/haewonp00/my-codex-test.git'
EXPERIMENT_ID = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]
if SAVE_TO_DRIVE:
    from google.colab import drive
    drive.mount('/content/drive')
    OUTPUT = Path('/content/drive/MyDrive/recycling_experiments') / EXPERIMENT_ID
else:
    OUTPUT = Path('/content/recycling_experiments') / EXPERIMENT_ID
OUTPUT.mkdir(parents=True, exist_ok=False)
print('새 모델 저장 위치:', OUTPUT)
print('학습 횟수:', 2 if RUN_CONTROL else 1)

# ## 1. 기록된 버전의 데이터 받기
# 
# 실험 데이터 버전을 고정합니다. 소스 저장소는 읽기만 하고, 학습용 사본은 Colab 임시 디스크에 만듭니다. 재실행은 새 출력 폴더를 사용합니다.

SOURCE = Path('/content/recycling_source_6eefd24')
if not SOURCE.exists():
    SOURCE.mkdir()
    subprocess.run(['git', 'init', '-q', str(SOURCE)], check=True)
    subprocess.run(['git', '-C', str(SOURCE), 'remote', 'add', 'origin', REPOSITORY], check=True)
    subprocess.run(['git', '-C', str(SOURCE), 'fetch', '--depth', '1', 'origin', DATA_COMMIT], check=True)
    subprocess.run(['git', '-C', str(SOURCE), 'checkout', '--detach', '-q', 'FETCH_HEAD'], check=True)
actual_commit = subprocess.check_output(['git', '-C', str(SOURCE), 'rev-parse', 'HEAD'], text=True).strip()
assert actual_commit == DATA_COMMIT, '소스 버전이 다릅니다. 다른 빈 폴더를 사용하세요.'
DATA_SOURCE = SOURCE / '배경오탐_실험_v1/데이터셋'
WORK = Path('/content/recycling_work') / EXPERIMENT_ID
WORK.mkdir(parents=True, exist_ok=False)
sys.path.insert(0, str(SOURCE / '배경오탐_실험_v1'))
from recycling_fix import inspect_dataset, split_hashes, image_files

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def pixel_hash(path):
    with Image.open(path) as raw:
        image = ImageOps.exif_transpose(raw).convert('RGB')
        return hashlib.sha256(str(image.size).encode() + image.tobytes()).hexdigest()

preparation = json.loads((DATA_SOURCE / 'preparation.json').read_text())
assert len(preparation['images']) == 55
# Verify all 55 received background images against their original hashes.
for row in preparation['images']:
    role = row['proposed_role']
    folder = DATA_SOURCE / ('data/images/train' if role == 'train_proposal' else
                            'development_eval/images' if role == 'development_evaluation_proposal' else
                            'quality_hold/images')
    image = folder / f"background_{row['index']:02d}.jpg"
    assert row['zero_target_confirmed'] and row['ground_truth_object_count'] == 0
    assert sha256(image) == row['sha256'], f'사진 해시 불일치: {image}'
assert split_hashes(DATA_SOURCE / 'data') == preparation['val_test_hashes']
print('배경 55장 및 기존 val/test 해시 확인 완료')

DATASETS = {}
candidate = WORK / 'background35_data'
shutil.copytree(DATA_SOURCE / 'data', candidate)
DATASETS['background35_v1'] = candidate
if RUN_CONTROL:
    control = WORK / 'control_data'
    shutil.copytree(DATA_SOURCE / 'data', control)
    for row in preparation['images']:
        if row['proposed_role'] == 'train_proposal':
            # Only delete new backgrounds from the NEW control copy.
            (control / 'images/train' / f"background_{row['index']:02d}.jpg").unlink()
            (control / 'labels/train' / f"background_{row['index']:02d}.txt").unlink()
    DATASETS = {'control_v1': control, **DATASETS}

NEGATIVE_DIR = DATA_SOURCE / 'development_eval/images'
negative_images = sorted(NEGATIVE_DIR.glob('*.jpg'))
assert len(negative_images) == 16
negative_pixels = {pixel_hash(p) for p in negative_images}
TRAIN_GROUPS = {r['proposed_group'] for r in preparation['images'] if r['proposed_role'] == 'train_proposal'}
EVAL_GROUPS = {r['proposed_group'] for r in preparation['images'] if r['proposed_role'] == 'development_evaluation_proposal'}
assert not TRAIN_GROUPS & EVAL_GROUPS  # Physical locations remain unverified.
audits = {}
for name, data in DATASETS.items():
    for cache in (data / 'labels').rglob('*.cache'):
        cache.unlink()
    config = {'path': str(data), 'train': 'images/train', 'val': 'images/val',
              'test': 'images/test', 'names': NAMES}
    (data / 'data.yaml').write_text(yaml.safe_dump(config))
    audit, _ = inspect_dataset(data / 'data.yaml')
    expected = 766 if name == 'background35_v1' else 731
    assert audit['splits']['train']['images'] == expected
    assert audit['splits']['train']['negative_images'] == (38 if name == 'background35_v1' else 3)
    assert split_hashes(data) == preparation['val_test_hashes']
    assert not negative_pixels & {pixel_hash(p) for p in image_files(data / 'images/train')}
    audits[name] = audit
    print(name, {s: v['images'] for s,v in audit['splits'].items()})
(OUTPUT / 'dataset_audits.json').write_text(json.dumps(audits, ensure_ascii=False, indent=2))

# ## 2. 새 모델 학습
# 
# 기존 label_fix_v1의 핵심 설정(20 epochs, imgsz 640, batch 8, seed 42)을 사용합니다. 시작 가중치와 설정을 기록합니다. COCO 사전학습 모델의 클래스는 학습 시작 시 데이터의 3개 클래스로 바뀝니다.
# 
# 기본은 배경 추가 모델 1개입니다. `RUN_CONTROL=True`이면 같은 사전학습 가중치에서 대조군 731장과 실험군 766장을 각각 학습합니다. 이 비교가 배경 추가 효과를 판단하는 데 더 적합합니다. 원래 Colab의 버전·GPU 차이로 과거 결과와 숫자가 완전히 같아지지는 않습니다.

# Download the standard pretrained model into this experiment's local workspace.
import os
previous_cwd = Path.cwd()
try:
    os.chdir(WORK)
    pretrained = YOLO('yolo11n.pt')
finally:
    os.chdir(previous_cwd)
PRETRAINED = WORK / 'yolo11n.pt'
assert PRETRAINED.is_file()
del pretrained
COMMON = dict(epochs=EPOCHS, imgsz=IMGSZ, batch=BATCH, seed=SEED,
              deterministic=True, device=0, workers=2, optimizer='auto',
              patience=100, cache=False, pretrained=True, resume=False,
              close_mosaic=10, amp=True, plots=True, exist_ok=False,
              hsv_h=0.015, hsv_s=0.7, hsv_v=0.4, degrees=0.0,
              translate=0.1, scale=0.5, shear=0.0, perspective=0.0,
              flipud=0.0, fliplr=0.5, mosaic=1.0, mixup=0.0,
              copy_paste=0.0, iou=IOU)
manifest = {'repository': REPOSITORY, 'data_commit': DATA_COMMIT,
            'pretrained_sha256': sha256(PRETRAINED), 'settings': COMMON,
            'run_control': RUN_CONTROL, 'ultralytics': ultralytics.__version__,
            'torch': torch.__version__, 'gpu': torch.cuda.get_device_name(0),
            'negative_eval_conf': CONF, 'negative_eval_images': 16,
            'location_independence_confirmed': False}
(OUTPUT / 'experiment.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
BEST = {}
for name, data in DATASETS.items():
    run = OUTPUT / name
    assert not run.exists(), '기존 실험을 덮어쓰지 않습니다. 새 실험 폴더를 사용하세요.'
    model = YOLO(str(PRETRAINED))
    model.train(data=str(data / 'data.yaml'), project=str(OUTPUT), name=name, **COMMON)
    best = Path(model.trainer.save_dir) / 'weights/best.pt'
    assert best.is_file()
    BEST[name] = best
    print('생성된 새 모델:', best)
    del model
    torch.cuda.empty_cache()
(OUTPUT / 'new_weights.json').write_text(json.dumps({k: str(v) for k,v in BEST.items()}, indent=2))

# ## 3. 객체 성능과 배경 오탐 평가
# 
# 객체 val의 Precision·Recall·mAP와 빈 배경의 오탐을 따로 기록합니다. 오탐만 줄고 실제 물체를 못 찾게 되는지 함께 확인하세요. Test 90장은 여기서 사용하지 않습니다. 배경 평가에서는 confidence=0.25로 고정하고 임의의 박스 크기 필터를 적용하지 않습니다.

evaluations = []
for name, best in BEST.items():
    weight_hash = sha256(best)
    model = YOLO(str(best))
    assert {int(k):v for k,v in model.names.items()} == NAMES
    result = model.val(data=str(DATASETS[name] / 'data.yaml'), split='val',
                       imgsz=IMGSZ, batch=BATCH, device=0, workers=2,
                       conf=0.001, iou=IOU, project=str(OUTPUT),
                       name=f'{name}_object_val', plots=True, exist_ok=False)
    predictions = []
    negative_out = OUTPUT / f'{name}_negative_eval'
    negative_out.mkdir(exist_ok=False)
    classes = Counter()
    for path in negative_images:
        with Image.open(path) as raw:
            image = ImageOps.exif_transpose(raw).convert('RGB')
        pred = model.predict(image, imgsz=IMGSZ, conf=CONF, iou=IOU,
                             device=0, verbose=False)[0]
        boxes = []
        for b in pred.boxes:
            cls = model.names[int(b.cls.item())]
            classes[cls] += 1
            boxes.append({'class': cls, 'confidence': float(b.conf.item()),
                          'xyxy_px': [float(x) for x in b.xyxy[0].tolist()]})
        predictions.append({'photo': path.name, 'sha256': sha256(path),
                            'ground_truth_objects': 0, 'false_positive_boxes': len(boxes),
                            'detections': boxes})
        pred.save(filename=str(negative_out / path.name))
    bad = sum(p['false_positive_boxes'] > 0 for p in predictions)
    box_count = sum(p['false_positive_boxes'] for p in predictions)
    report = {'model': name, 'best_pt': str(best), 'weights_sha256': weight_hash,
              'object_val': {k: float(v) for k,v in result.results_dict.items()},
              'negative_conf': CONF, 'negative_images': len(predictions),
              'images_with_false_positives': bad, 'false_positive_image_rate': bad/len(predictions),
              'false_positive_boxes': box_count, 'false_positive_classes': dict(classes),
              'predictions': predictions, 'final_independent_test': False}
    assert sha256(best) == weight_hash
    (negative_out / 'evaluation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
    pd.DataFrame([{'photo': p['photo'], 'gt_objects': 0,
                   'false_positive_boxes': p['false_positive_boxes']} for p in predictions]).to_csv(
                       negative_out / 'per_image.csv', index=False, encoding='utf-8-sig')
    evaluations.append(report)
    del model
    torch.cuda.empty_cache()
summary = pd.DataFrame([{'model': r['model'],
    'Precision': r['object_val']['metrics/precision(B)'],
    'Recall': r['object_val']['metrics/recall(B)'],
    'mAP50': r['object_val']['metrics/mAP50(B)'],
    'mAP50-95': r['object_val']['metrics/mAP50-95(B)'],
    'FP_images/16': r['images_with_false_positives'],
    'FP_image_rate': r['false_positive_image_rate']} for r in evaluations])
summary.to_csv(OUTPUT / 'comparison.csv', index=False, encoding='utf-8-sig')
display(summary)
print('기존 모델 참고 기록: 16장 중 13장 오탐(81.25%). 같은 조건의 새 대조군을 대신하지는 않습니다.')
print('학습 결과는 수치와 예측 사진을 확인한 뒤 판단하세요. 새 모델이 반드시 더 좋아지는 것은 아닙니다.')

# ## 4. 새 모델 파일 받기
# 
# 아래 ZIP에는 **배경 추가 모델의 best.pt와 last.pt**, 학습 설정·곡선·CSV·평가 기록이 들어갑니다. Google Drive의 실험 폴더에도 저장됩니다. Flutter/Python 서버에 적용하는 작업은 별도이며, 실제 물체 사진에서도 확인한 후 적용하세요.

MODEL_DIR = OUTPUT / 'background35_v1'
print('새 모델 best.pt:', BEST['background35_v1'])
# Preserve training and evaluation records. ZIP is created outside OUTPUT.
archive = shutil.make_archive(str(OUTPUT.parent / f'recycling_{EXPERIMENT_ID}'), 'zip', root_dir=OUTPUT)
print('결과 ZIP:', archive)
from google.colab import files
files.download(archive)

# ## 선택: 직접 찍은 물체 사진 테스트
# 
# 다음 셀은 기본적으로 실행하지 않습니다. `TEST_MY_PHOTOS=True`로 바꾸고 캔·플라스틱·종이가 있는 **원본** 사진을 올리세요. 이미 박스가 그려진 결과 이미지를 원본 대신 넣지 마세요. 실제 물체의 정답 박스를 입력하지 않았으므로 이 셀은 시각 확인용이며 mAP를 산출하지 않습니다.

TEST_MY_PHOTOS = False
if TEST_MY_PHOTOS:
    from google.colab import files
    import io
    from IPython.display import display
    uploaded = files.upload()
    model = YOLO(str(BEST['background35_v1']))
    photo_out = OUTPUT / ('my_photos_' + uuid.uuid4().hex[:8])
    photo_out.mkdir(exist_ok=False)
    for i, (filename, contents) in enumerate(uploaded.items(), 1):
        with Image.open(io.BytesIO(contents)) as raw:
            photo = ImageOps.exif_transpose(raw).convert('RGB')
        result = model.predict(photo, conf=CONF, iou=IOU, imgsz=IMGSZ, device=0, verbose=False)[0]
        result.save(filename=str(photo_out / f'{i:02d}_predicted.jpg'))
        print(filename, [{'class': model.names[int(b.cls.item())], 'confidence': float(b.conf.item())}
                         for b in result.boxes])
        display(Image.open(photo_out / f'{i:02d}_predicted.jpg'))
    print('사진 결과 저장 위치:', photo_out)
