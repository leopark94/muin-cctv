---
description: YOLO 모델 성능 벤치마크 및 비교. "성능 측정", "모델 비교", "FPS 확인" 등의 요청 시 사용
tags: [cctv, benchmark, performance, yolo]
---

# CCTV Performance Benchmark

YOLO 모델 성능을 측정하고 비교합니다.

## 벤치마크 항목

1. **추론 속도 (FPS)**
   - 단일 이미지 처리 시간
   - 배치 처리 성능
   - CPU vs GPU 비교

2. **정확도 (mAP)**
   - 사람 감지 정확도
   - False Positive/Negative 비율
   - IoU 임계값별 성능

3. **메모리 사용량**
   - 모델 크기
   - 런타임 메모리
   - VRAM 사용량 (GPU)

## 모델 비교 스크립트

```python
from ultralytics import YOLO
import time
import cv2

models = ['yolo8n.pt', 'yolo11n.pt', 'yolo11s.pt']

for model_name in models:
    model = YOLO(model_name)
    img = cv2.imread('test.jpg')

    # Warmup
    for _ in range(10):
        model(img)

    # Benchmark
    start = time.time()
    for _ in range(100):
        results = model(img)
    end = time.time()

    fps = 100 / (end - start)
    print(f"{model_name}: {fps:.2f} FPS")
```

## 실시간 감지 벤치마크

```bash
# 채널 12에서 30초간 감지, FPS 측정
python -c "
import time
from src.config import settings
from src.utils import RTSPClient
from src.core import PersonDetector

client = RTSPClient(settings.get_rtsp_url('live_12'))
client.connect()

detector = PersonDetector()

frames = 0
start = time.time()
duration = 30

while time.time() - start < duration:
    frame = client.capture_frame()
    detections = detector.detect_persons(frame)
    frames += 1

fps = frames / duration
print(f'Average FPS: {fps:.2f}')
"
```

## 최적화 가이드

### CPU 최적화
```bash
# OpenMP 스레드 수 설정
export OMP_NUM_THREADS=8
export OPENBLAS_NUM_THREADS=8
```

### GPU 사용 (CUDA 설치 시)
```python
model = YOLO('yolo11n.pt')
model.to('cuda')  # GPU 사용
```

### 배치 처리
```python
# 여러 프레임 동시 처리
results = model([frame1, frame2, frame3])
```

## 권장 설정

| 환경 | 모델 | Confidence | 예상 FPS |
|------|------|------------|----------|
| CPU (4 cores) | yolo11n | 0.3 | 10-15 |
| CPU (8 cores) | yolo11n | 0.3 | 20-30 |
| GPU (RTX 3060) | yolo11n | 0.3 | 100+ |
| GPU (RTX 3060) | yolo11s | 0.5 | 60+ |
