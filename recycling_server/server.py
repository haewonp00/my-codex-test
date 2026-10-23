"""Photo detection API; numbered boxes and stable IDs per response. No training."""
from contextlib import asynccontextmanager
from pathlib import Path
from threading import Lock
from uuid import uuid4
import base64
import io
import logging
import warnings

from fastapi import FastAPI, HTTPException, UploadFile
from PIL import Image, ImageDraw, ImageFont, ImageOps, UnidentifiedImageError

EXPECTED_NAMES = {0: 'plastic', 1: 'paper', 2: 'metal'}
KOREAN_NAMES = {'plastic': '플라스틱', 'paper': '종이', 'metal': '금속'}
LIMIT = 10 * 1024 * 1024
CONFIDENCE = 0.25
NMS_IOU = 0.7  # Original Ultralytics default; now recorded explicitly.
logger = logging.getLogger(__name__)


def _numbered_image(photo, detections):
    """Use the same EXIF-corrected image/xyxy coordinates as inference."""
    annotated = photo.copy()
    draw = ImageDraw.Draw(annotated)
    size = max(16, round(min(photo.size) / 45))
    font = ImageFont.load_default(size=size)
    width = max(2, round(min(photo.size) / 350))
    colors = {0: '#20845A', 1: '#1769AA', 2: '#9B4D00'}
    for item in detections:
        x1, y1, x2, y2 = item['bbox']
        color = colors[item['class_id']]
        draw.rectangle((x1, y1, x2, y2), outline=color, width=width)
        # ASCII numbers work without Korean/circled-number font installation.
        text = f"#{item['number']} {item['label']} {item['confidence']:.2f}"
        left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
        tw, th = right - left + 10, bottom - top + 8
        tx = max(0, min(x1, photo.width - tw))
        ty = max(0, min(y1 - th if y1 >= th else y1, photo.height - th))
        draw.rectangle((tx, ty, tx + tw, ty + th), fill=color)
        draw.text((tx + 5 - left, ty + 4 - top), text, fill='white', font=font)
    buffer = io.BytesIO()
    annotated.save(buffer, format='JPEG', quality=90)
    return base64.b64encode(buffer.getvalue()).decode('ascii')


def create_app(injected_model=None, model_path=None):
    """injected_model is for contract tests; production loads only local best.pt."""
    @asynccontextmanager
    async def lifespan(app):
        model = injected_model
        if model is None:
            path = Path(model_path) if model_path else Path(__file__).resolve().parent / 'best.pt'
            if not path.is_file():
                raise RuntimeError(f'실제 모델 파일이 필요합니다: {path}')
            from ultralytics import YOLO
            model = YOLO(str(path))
        names = model.names
        names = dict(enumerate(names)) if isinstance(names, list) else {int(k):v for k,v in names.items()}
        if names != EXPECTED_NAMES:
            raise RuntimeError(f'모델 클래스가 일치하지 않습니다: {names}')
        app.state.model = model
        app.state.model_lock = Lock()
        yield

    app = FastAPI(title='분리수거 AI 서버', lifespan=lifespan)

    @app.get('/health')
    def health():
        return {'status': 'ok', 'classes': app.state.model.names}

    @app.post('/predict')
    def predict(file: UploadFile):
        data = file.file.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise HTTPException(status_code=413, detail='10MB 이하 사진을 선택해 주세요.')
        try:
            with warnings.catch_warnings():
                warnings.simplefilter('error', Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as original:
                    photo = ImageOps.exif_transpose(original).convert('RGB')
        except (UnidentifiedImageError, OSError, ValueError,
                Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise HTTPException(status_code=400, detail='사진을 읽을 수 없습니다. JPG 또는 PNG 사진을 다시 선택해 주세요.')
        batch_id = uuid4().hex
        detections = []
        try:
            with app.state.model_lock:
                result = app.state.model.predict(photo, conf=CONFIDENCE,
                    iou=NMS_IOU, imgsz=640, device='cpu', verbose=False)[0]
                for index, box in enumerate(result.boxes, 1):
                    class_id = int(box.cls.item())
                    label = EXPECTED_NAMES[class_id]
                    detections.append({
                        'detection_id': f'{batch_id}:{index}', 'number': index,
                        'class_id': class_id, 'label': label,
                        'label_ko': KOREAN_NAMES[label],
                        'confidence': float(box.conf.item()),
                        'bbox': [float(v) for v in box.xyxy[0].tolist()],
                    })
            annotated = _numbered_image(photo, detections)
        except Exception:
            logger.exception('Photo inference failed')
            raise HTTPException(status_code=500, detail='분석에 실패했습니다. 잠시 후 다시 분석해 주세요.')
        return {'count': len(detections), 'image_width': photo.width,
                'image_height': photo.height, 'detections': detections,
                'annotated_image': annotated}

    return app


app = create_app()
