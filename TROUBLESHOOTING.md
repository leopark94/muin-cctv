# 트러블슈팅 가이드

## 화질 문제

### 증상
- RTSP 스트림에서 캡처한 이미지가 흐릿하거나 저화질
- 사람 감지가 잘 안되거나 정확도가 떨어짐

### 원인 및 해결 방법

#### 1. DVR 비트레이트 설정이 낮음

**확인 방법:**
```bash
python src/check_stream_quality.py
```

**해결 방법:**
1. DVR 웹 관리 페이지 접속 (http://218.50.241.157)
2. 설정 → 카메라 설정 → 채널 12
3. 인코딩 설정:
   - **해상도**: 1920x1080 (Full HD)
   - **비트레이트**: 2048 Kbps 이상
   - **프레임레이트**: 15~25 fps
   - **비트레이트 제어**: CBR (고정 비트레이트)

#### 2. 잘못된 RTSP 스트림 경로

DVR은 보통 여러 화질의 스트림을 제공합니다:
- **Main Stream (고화질)**: `main_12`, `stream1_12`
- **Sub Stream (저화질)**: `sub_12`, `stream2_12`

**현재 경로:** `live_12`

**시도해볼 경로들:**
```bash
# .env 파일에서 RTSP_PATH 변경 후 테스트
RTSP_PATH=main_12       # 메인 스트림
RTSP_PATH=stream1_12    # 스트림1 (보통 고화질)
RTSP_PATH=h264_12       # H264 스트림
```

**테스트 방법:**
```bash
python src/test_rtsp.py
```

#### 3. 네트워크 대역폭 부족

**확인:**
- DVR과 서버 간 네트워크 속도 측정
- 다른 서비스가 대역폭을 많이 사용하고 있는지 확인

**권장 대역폭:**
- 1080p @ 2Mbps → 최소 3Mbps 여유 필요
- 여러 채널 동시 사용 시 비례하여 증가

#### 4. 카메라 물리적 문제

**확인 사항:**
- 카메라 렌즈 청소
- 카메라 초점 조정
- 조명 상태 (너무 어둡거나 밝지 않은지)
- DVR 웹페이지에서 직접 라이브 화면 확인

## RTSP 연결 문제

### 증상
- RTSP 연결 실패
- 타임아웃 에러

### 해결 방법

#### 1. 네트워크 연결 확인
```bash
ping 218.50.241.157
```

#### 2. RTSP 포트 확인
```bash
telnet 218.50.241.157 8554
# 또는
nc -zv 218.50.241.157 8554
```

#### 3. 인증 정보 확인
`.env` 파일에서:
```
RTSP_USERNAME=admin
RTSP_PASSWORD=00000
```

#### 4. 방화벽 확인
- 서버에서 DVR로 8554 포트 접근 가능한지 확인
- DVR 방화벽 설정 확인

## YOLO 감지 문제

### 증상
- 사람이 있는데 감지가 안됨
- 오탐지가 너무 많음

### 해결 방법

#### 1. Confidence Threshold 조정

`.env` 파일:
```
# 너무 많이 감지되면 높이기 (0.5 → 0.6)
# 너무 적게 감지되면 낮추기 (0.5 → 0.3)
CONFIDENCE_THRESHOLD=0.5
```

#### 2. IoU Threshold 조정

`.env` 파일:
```
# 좌석 점유 판단 기준
# 엄격하게: 0.5
# 느슨하게: 0.2
IOU_THRESHOLD=0.3
```

#### 3. 화질 개선
위의 "화질 문제" 섹션 참조

## ROI 설정 문제

### 증상
- 좌석 영역이 실제 좌석과 맞지 않음
- 사람이 있는데 "empty"로 표시됨

### 해결 방법

#### 1. ROI 좌표 확인
```bash
cat data/roi_configs/example_config.json
```

#### 2. ROI 시각화
```bash
python src/test_seat_detection.py
```
결과 이미지에서 ROI 박스 위치 확인

#### 3. ROI 재설정
`data/roi_configs/example_config.json` 수정:
```json
{
  "id": "9",
  "roi": [x1, y1, x2, y2],  // 좌표 조정
  "label": "9번 좌석"
}
```

좌표 형식: `[좌상단x, 좌상단y, 우하단x, 우하단y]`

## 성능 문제

### 증상
- 처리 속도가 너무 느림
- CPU/메모리 사용률이 높음

### 해결 방법

#### 1. GPU 사용 (있는 경우)
YOLOv8이 자동으로 GPU를 감지하지만, 확인:
```python
from ultralytics import YOLO
model = YOLO('yolov8n.pt')
print(model.device)  # cuda:0 또는 cpu
```

#### 2. 더 가벼운 모델 사용
`.env`:
```
YOLO_MODEL=yolov8n.pt  # 현재 (nano - 가장 가벼움)
```

#### 3. 스냅샷 간격 늘리기
`.env`:
```
SNAPSHOT_INTERVAL=5  # 3초 → 5초
```

## 도움 받기

문제가 계속되면:
1. `src/check_stream_quality.py` 실행 결과 공유
2. 에러 메시지 전체 복사
3. DVR 모델 및 펌웨어 버전 확인
4. 네트워크 구성도 (DVR ↔ 서버)
