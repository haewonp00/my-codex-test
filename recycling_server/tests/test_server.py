import base64
import io
from types import SimpleNamespace
import numpy as np
import pytest
from PIL import Image
from fastapi.testclient import TestClient
from server import create_app, EXPECTED_NAMES


def photo_bytes(size=(160, 120), orientation=None):
    image = Image.new('RGB', size, (240, 240, 240))
    output = io.BytesIO()
    exif = Image.Exif()
    if orientation: exif[274] = orientation
    image.save(output, format='JPEG', exif=exif)
    return output.getvalue()


class FakeModel:
    names = EXPECTED_NAMES
    def __init__(self, classes=(0, 1, 2)):
        self.classes = classes
        self.calls = []
    def predict(self, image, **kwargs):
        self.calls.append((image.copy(), kwargs))
        boxes = [SimpleNamespace(cls=np.array([c]), conf=np.array([.38 + i*.1]),
                 xyxy=np.array([[10+i*20, 15, 25+i*20, 60]], dtype=float))
                 for i,c in enumerate(self.classes)]
        return [SimpleNamespace(boxes=boxes)]


@pytest.mark.parametrize('classes', [(), (0,), (0, 1, 2)])
def test_contract_and_stable_numbering(classes):
    model = FakeModel(classes)
    with TestClient(create_app(model)) as client:
        response = client.post('/predict', files={'file': ('photo.jpg', photo_bytes(), 'image/jpeg')})
        assert response.status_code == 200
        body = response.json()
        assert body['count'] == len(classes)
        assert [d['number'] for d in body['detections']] == list(range(1,len(classes)+1))
        assert len({d['detection_id'] for d in body['detections']}) == len(classes)
        for d,c in zip(body['detections'], classes):
            assert d['label'] == EXPECTED_NAMES[c]
            assert len(d['bbox']) == 4
        with Image.open(io.BytesIO(base64.b64decode(body['annotated_image']))) as image:
            assert image.size == (160,120)
        assert model.calls[0][1] == dict(conf=.25, iou=.7, imgsz=640, device='cpu', verbose=False)
        if classes:
            other = client.post('/predict', files={'file': ('photo.jpg',photo_bytes())}).json()
            assert body['detections'][0]['detection_id'] != other['detections'][0]['detection_id']


def test_exif_rotation_uses_same_inference_and_response_dimensions():
    model = FakeModel(())
    with TestClient(create_app(model)) as client:
        body = client.post('/predict', files={'file': ('rotated.jpg',photo_bytes((160,100),6))}).json()
        assert (body['image_width'], body['image_height']) == (100,160)
        assert model.calls[0][0].size == (100,160)


def test_invalid_and_too_large_photos_do_not_run_inference():
    model = FakeModel()
    with TestClient(create_app(model)) as client:
        assert client.post('/predict',files={'file': ('x.jpg', b'not a photo')}).status_code == 400
        assert client.post('/predict',files={'file': ('x.jpg', b'x'*(10*1024*1024+1))}).status_code == 413
        assert not model.calls


def test_wrong_mapping_refuses_to_start():
    model = FakeModel(); model.names = {0:'paper',1:'plastic',2:'metal'}
    with pytest.raises(RuntimeError,match='클래스'):
        with TestClient(create_app(model)): pass


def test_inference_failure_is_user_readable():
    class Broken(FakeModel):
        def predict(self, *args, **kwargs): raise RuntimeError('internal detail')
    with TestClient(create_app(Broken())) as client:
        response = client.post('/predict',files={'file': ('x.jpg', photo_bytes())})
        assert response.status_code == 500
        assert response.json()['detail'] == '분석에 실패했습니다. 잠시 후 다시 분석해 주세요.'


def test_missing_local_weight_does_not_auto_download(tmp_path):
    with pytest.raises(RuntimeError,match='모델 파일'):
        with TestClient(create_app(model_path=tmp_path/'best.pt')): pass
