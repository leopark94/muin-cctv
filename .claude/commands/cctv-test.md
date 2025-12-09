---
description: CCTV RTSP 연결 및 YOLO 모델 테스트. "연결 테스트", "RTSP 확인", "모델 테스트" 등의 요청 시 사용
tags: [cctv, test, rtsp, yolo]
---

# CCTV System Test

CCTV RTSP 연결과 YOLOv11n 모델을 테스트합니다.

## 테스트 항목

1. **RTSP 연결 테스트**
   - .env 설정 확인
   - 모든 활성 채널 연결 시도
   - TCP/UDP 프로토콜 자동 전환 확인

2. **YOLO 모델 테스트**
   - YOLOv11n 모델 로드
   - 샘플 이미지로 사람 감지
   - 성능 측정 (FPS, 정확도)

3. **시스템 요구사항 검증**
   - Python 패키지 설치 확인
   - OpenCV RTSP 지원 확인
   - GPU/CPU 감지

## 실행 방법

다음 테스트 스크립트를 순서대로 실행:
1. `python src/test_rtsp.py` - RTSP 연결
2. `python src/test_yolo.py` - YOLO 모델

성공 시 data/snapshots/ 디렉토리에 테스트 이미지 저장.

## 문제 해결

- RTSP 연결 실패: VPN/네트워크 확인, .env 설정 검증
- 모델 로드 실패: `pip install ultralytics` 재설치
- 타임아웃 발생: timeout 값 증가 (기본 10초 → 30초)
