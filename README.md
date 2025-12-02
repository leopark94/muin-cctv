# 앤딩스터디카페 CCTV 좌석 감지 시스템

RTSP 연결된 DVR 카메라를 통해 스터디카페 좌석 점유 상태를 실시간으로 감지하는 시스템

## 기술 스택

- **ML 모델**: YOLOv8n (사람 감지)
- **영상 처리**: OpenCV
- **API**: FastAPI
- **언어**: Python 3.14+

## 프로젝트 구조

```
muin-cctv/
├── src/
│   ├── core/           # 핵심 로직 (YOLO, ROI 매칭)
│   ├── api/            # FastAPI 서버
│   ├── utils/          # 유틸리티 함수
│   └── config/         # 설정 관리
├── data/
│   ├── roi_configs/    # 좌석 ROI 설정 JSON
│   └── snapshots/      # RTSP 스냅샷 임시 저장
├── tests/              # 테스트 코드
└── logs/               # 로그 파일

## 설치 및 실행

### 1. 가상환경 생성
```bash
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
```

### 2. 패키지 설치
```bash
pip install -r requirements.txt
```

### 3. 환경 변수 설정
```bash
cp .env.example .env
# .env 파일 편집하여 RTSP 정보 입력
```

### 4. 스트림 화질 진단
```bash
python src/check_stream_quality.py
```

### 5. RTSP 연결 테스트
```bash
python src/test_rtsp.py
```

### 6. YOLO 감지 테스트
```bash
python src/test_yolo.py
```

## 참고 문서

- [기술 명세서](./CCTV_SEAT_DETECTION_SPEC.md)
