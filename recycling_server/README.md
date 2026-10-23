# FastAPI 사진 추론 서버

기존 서버의 `best.pt`는 그대로 보존하고 이 소스를 복사하세요. 앱 소스도 함께 업데이트해야 합니다. confidence=0.25, imgsz=640, CPU, 기존 기본 NMS IoU=0.7을 유지합니다.

```powershell
python -m pip install -r requirements.txt
python -m uvicorn server:app --host 127.0.0.1 --port 8000
```

USB 연결: `adb reverse tcp:8000 tcp:8000`. 전체 설명과 API 호환 내용은 [적용방법](../앱_변경기록/적용방법.md)에 있습니다. 클래스가 0 plastic, 1 paper, 2 metal이 아니면 시작하지 않습니다. 모델이 없을 때 임의 모델을 다운로드하지 않습니다.

테스트:

```powershell
python -m pip install -r requirements-dev.txt
python -m pytest tests -q
```
