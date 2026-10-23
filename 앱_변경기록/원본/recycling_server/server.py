from pathlib import Path
from threading import Lock
import io
import base64

from fastapi import FastAPI, UploadFile, HTTPException
from PIL import Image, ImageOps, UnidentifiedImageError
from ultralytics import YOLO

app = FastAPI(title="분리수거 AI 서버")

# 이 파이썬 파일과 같은 폴더의 모델을 불러옵니다.
model_path = Path(__file__).resolve().parent / "best.pt"
model = YOLO(str(model_path))
model_lock = Lock()

KOREAN_NAMES = {
    "plastic": "플라스틱",
    "paper": "종이",
    "metal": "금속",
}


@app.get("/health")
def health():
    return {"status": "ok", "classes": model.names}


@app.post("/predict")
def predict(file: UploadFile):
    # 최대 10MB까지 읽습니다.
    limit = 10 * 1024 * 1024
    data = file.file.read(limit + 1)

    if len(data) > limit:
        raise HTTPException(
            status_code=413,
            detail="10MB 이하 사진을 선택해 주세요.",
        )

    try:
        with Image.open(io.BytesIO(data)) as original:
            # 휴대폰 사진의 회전 정보를 반영합니다.
            photo = ImageOps.exif_transpose(original).convert("RGB")
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError):
        raise HTTPException(
            status_code=400,
            detail="사진을 읽을 수 없습니다. JPG 또는 PNG를 사용해 주세요.",
        )

    # 요청이 겹쳐도 모델은 한 번에 하나씩 실행합니다.
    with model_lock:
        result = model.predict(
            photo,
            conf=0.25,
            imgsz=640,
            device="cpu",
            verbose=False,
        )[0]

    detections = []

    for box in result.boxes:
        class_id = int(box.cls.item())
        label = result.names[class_id]

        detections.append({
            "class_id": class_id,
            "label": label,
            "label_ko": KOREAN_NAMES.get(label, label),
            "confidence": float(box.conf.item()),
            "bbox": box.xyxy[0].tolist(),
        })

       # 모델이 찾은 위치에 사각형과 이름을 그립니다.
    annotated_bgr = result.plot()

    # 이미지 색상 순서를 BGR에서 RGB로 바꿉니다.
    annotated_rgb = Image.fromarray(annotated_bgr[:, :, ::-1])

    # 이미지를 메모리 안에서 JPEG 형식으로 저장합니다.
    buffer = io.BytesIO()
    annotated_rgb.save(buffer, format="JPEG", quality=90)

    # JSON에 담아 보낼 수 있도록 이미지 데이터를 문자열로 바꿉니다.
    annotated_base64 = base64.b64encode(
        buffer.getvalue()
    ).decode("ascii")

    return {
        "count": len(detections),
        "image_width": photo.width,
        "image_height": photo.height,
        "detections": detections,
        "annotated_image": annotated_base64
    }

