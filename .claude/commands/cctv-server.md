---
description: CCTV 웹 UI 서버 시작/중지. "서버 시작", "웹 실행", "UI 켜줘" 등의 요청 시 사용
tags: [cctv, server, web, ui]
---

# CCTV Web Server Control

CCTV 좌석 감지 웹 UI 서버를 관리합니다.

## 서버 시작

```bash
source venv/bin/activate
cd src/api
uvicorn roi_config_api:app --host 0.0.0.0 --port 8000
```

백그라운드 실행:
```bash
uvicorn roi_config_api:app --host 0.0.0.0 --port 8000 &
```

## 접속 정보

- **로컬**: http://localhost:8000
- **네트워크**: http://<your-ip>:8000
- **API 문서**: http://localhost:8000/docs

## 주요 기능

1. **16채널 관리** - 모든 RTSP 채널 선택 가능
2. **ROI 설정** - 좌석 영역 폴리곤 그리기
3. **자동 감지** - AI 기반 좌석 영역 자동 추출
4. **실시간 감지** - YOLOv11n으로 사람 감지
5. **설정 저장** - 채널별 ROI 설정 JSON 저장

## 포트 변경

.env 파일에서 수정:
```
API_PORT=9000
```

## 문제 해결

- 포트 이미 사용 중: `lsof -ti:8000 | xargs kill -9`
- RTSP 연결 안 됨: TCP/UDP 프로토콜 자동 전환 확인
- 느린 응답: MAX_WORKERS 값 증가
