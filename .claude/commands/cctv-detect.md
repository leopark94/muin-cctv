---
description: 특정 채널에서 실시간 사람 감지 실행. "채널 12 감지", "좌석 확인", "Detection 돌려" 등의 요청 시 사용
tags: [cctv, detection, yolo, seat]
---

# CCTV Person Detection

지정된 채널에서 YOLOv11n을 사용하여 사람을 감지하고 좌석 점유율을 분석합니다.

## 단일 채널 감지

```bash
# 채널 12 감지
python src/test_seat_detection.py --channel 12
```

## 전체 채널 감지

```bash
# .env의 ACTIVE_CHANNELS 기준으로 모든 채널 감지
python src/run_detection_all.py
```

## 감지 파라미터

.env에서 설정:
```bash
YOLO_MODEL=yolo11n.pt        # 모델 (v8n, v11n)
CONFIDENCE_THRESHOLD=0.3      # 신뢰도 (0.1~0.9)
IOU_THRESHOLD=0.3             # IoU 임계값
```

## 결과 해석

- **초록색 ROI**: 빈 좌석 (사람 없음)
- **빨간색 ROI**: 점유된 좌석 (사람 감지)
- **분홍색 점**: 사람 바운딩 박스 중심점

## 성능 최적화

1. **모델 선택**
   - `yolo11n.pt`: 빠름, 정확도 중간 (권장)
   - `yolo11s.pt`: 중간 속도, 높은 정확도
   - `yolo11m.pt`: 느림, 최고 정확도

2. **Confidence 조정**
   - 너무 높음 (>0.7): 사람 놓침
   - 너무 낮음 (<0.2): 오탐 증가
   - 권장: 0.3~0.5

3. **멀티프로세싱**
   ```bash
   MAX_WORKERS=8  # CPU 코어 수에 맞게 조정
   ```

## ROI 설정 필요

감지 전 웹 UI에서 각 채널의 좌석 ROI를 먼저 설정해야 합니다:
1. http://localhost:8000 접속
2. 채널 선택
3. "Draw Polygon"으로 좌석 영역 그리기
4. "Save Config" 저장
