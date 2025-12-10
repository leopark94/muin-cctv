# CCTV Seat Detection System - 배포 가이드

## 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      Supabase Cloud                         │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ PostgreSQL  │  │  Real-time   │  │  Storage     │      │
│  │  Database   │  │  Subscriptions│  │  (Snapshots) │      │
│  └─────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTPS
                            │
┌───────────────────────────┼─────────────────────────────────┐
│                   Server (VPS or Local)                     │
│                                                              │
│  ┌─────────────────┐     ┌────────────────────────────┐   │
│  │   Web Server    │     │   Detection Workers        │   │
│  │                 │     │                            │   │
│  │  FastAPI (8000) │     │  Worker 1 → Channel 1-4   │   │
│  │  - ROI Config   │     │  Worker 2 → Channel 5-8   │   │
│  │  - Seat Status  │     │  Worker 3 → Channel 9-12  │   │
│  │  - Statistics   │     │  Worker 4 → Channel 13-16 │   │
│  └─────────────────┘     └────────────────────────────┘   │
│                                      │                      │
│                                      │ RTSP                 │
└──────────────────────────────────────┼──────────────────────┘
                                       │
                            ┌──────────▼──────────┐
                            │  CCTV NVR System    │
                            │  16 Channels        │
                            │  RTSP Streaming     │
                            └─────────────────────┘
```

## 1. Supabase 설정 (5-10분)

### 1.1 프로젝트 생성
```bash
# 1. https://supabase.com 접속
# 2. New Project 생성
#    - Name: muin-cctv-seats
#    - Region: Northeast Asia (Seoul)
#    - Plan: Free
```

### 1.2 스키마 적용
```sql
-- Supabase Dashboard → SQL Editor에서 실행
-- database/schema.sql 파일 내용 복사/붙여넣기
```

### 1.3 RLS 설정 (개발용)
```sql
-- 개발 단계에서는 RLS 비활성화
ALTER TABLE stores DISABLE ROW LEVEL SECURITY;
ALTER TABLE seats DISABLE ROW LEVEL SECURITY;
ALTER TABLE seat_status DISABLE ROW LEVEL SECURITY;
ALTER TABLE detection_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE occupancy_stats DISABLE ROW LEVEL SECURITY;
ALTER TABLE system_logs DISABLE ROW LEVEL SECURITY;
```

### 1.4 Real-time 활성화
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE seat_status;
ALTER PUBLICATION supabase_realtime ADD TABLE detection_events;
```

## 2. 서버 설정

### 2.1 의존성 설치
```bash
# Python 가상환경 생성
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 패키지 설치
pip install -r requirements.txt
```

### 2.2 환경 변수 설정
```bash
# .env 파일 생성
cp .env.example .env

# 필수 항목 설정
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_KEY=your_anon_public_key
SUPABASE_SERVICE_KEY=your_service_role_key

RTSP_USERNAME=admin
RTSP_PASSWORD=your_password
RTSP_HOST=218.50.241.157
RTSP_PORT=8554

GOSCA_STORE_ID=Anding-Oryudongyeok-sca
YOLO_MODEL=yolo11n.pt
```

### 2.3 초기 데이터 임포트
```bash
# GoSca에서 좌석 데이터 가져오기
python -m src.scripts.import_gosca_seats

# 성공 시:
# ✅ Import completed successfully!
# Found 55 seats
```

## 3. 서비스 시작

### 3.1 API 서버 시작
```bash
# 터미널 1: 좌석 상태 API 서버
python -m src.api.seats_api

# 포트: 8001
# 접속: http://localhost:8001/docs
```

### 3.2 Detection Worker 시작
```bash
# 터미널 2: 실시간 감지 워커
python -m src.workers.detection_worker --store oryudong --channels 1,2,3,4

# 옵션:
# --store: 지점 ID (oryudong, gangnam 등)
# --channels: 모니터링할 채널 (기본: 모든 활성 채널)
```

### 3.3 ROI 설정 UI (선택)
```bash
# 터미널 3: ROI 설정 웹 UI
python -m src.api.roi_config_api

# 포트: 8000
# 접속: http://localhost:8000
```

## 4. ROI 설정

각 좌석에 대해 CCTV 화면의 ROI(관심영역)를 설정해야 합니다.

### 4.1 웹 UI로 설정 (권장)
```
1. http://localhost:8000 접속
2. 채널 선택 (1-16)
3. 스냅샷 로드
4. 좌석별 ROI 폴리곤 그리기
5. 저장
```

### 4.2 API로 직접 설정
```bash
curl -X PATCH "http://localhost:8001/api/stores/oryudong/seats/A-01/roi" \
  -H "Content-Type: application/json" \
  -d '{
    "channel_id": 1,
    "roi_polygon": [[100, 100], [200, 100], [200, 200], [100, 200]]
  }'
```

## 5. 프로덕션 배포

### 5.1 Systemd 서비스 (Linux)

#### API 서버 서비스
```ini
# /etc/systemd/system/cctv-api.service
[Unit]
Description=CCTV Seat Detection API
After=network.target

[Service]
Type=simple
User=cctv
WorkingDirectory=/home/cctv/muin-cctv
Environment="PATH=/home/cctv/muin-cctv/venv/bin"
ExecStart=/home/cctv/muin-cctv/venv/bin/python -m src.api.seats_api
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### Detection Worker 서비스
```ini
# /etc/systemd/system/cctv-worker.service
[Unit]
Description=CCTV Detection Worker
After=network.target

[Service]
Type=simple
User=cctv
WorkingDirectory=/home/cctv/muin-cctv
Environment="PATH=/home/cctv/muin-cctv/venv/bin"
ExecStart=/home/cctv/muin-cctv/venv/bin/python -m src.workers.detection_worker --store oryudong
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### 서비스 시작
```bash
sudo systemctl daemon-reload
sudo systemctl enable cctv-api cctv-worker
sudo systemctl start cctv-api cctv-worker
sudo systemctl status cctv-api cctv-worker
```

### 5.2 Docker (선택)
```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Run
CMD ["python", "-m", "src.api.seats_api"]
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "8001:8001"
    env_file:
      - .env
    restart: unless-stopped

  worker:
    build: .
    command: python -m src.workers.detection_worker
    env_file:
      - .env
    restart: unless-stopped
```

### 5.3 Nginx 리버스 프록시
```nginx
# /etc/nginx/sites-available/cctv
server {
    listen 80;
    server_name cctv.yourdomain.com;

    location / {
        proxy_pass http://localhost:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /ws {
        proxy_pass http://localhost:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## 6. 모니터링

### 6.1 로그 확인
```bash
# Systemd 로그
sudo journalctl -u cctv-api -f
sudo journalctl -u cctv-worker -f

# Docker 로그
docker-compose logs -f api
docker-compose logs -f worker
```

### 6.2 Supabase 대시보드
```
Dashboard → Database → Tables
- seat_status: 실시간 좌석 상태
- detection_events: 이벤트 로그
- system_logs: 시스템 로그
```

### 6.3 API 헬스체크
```bash
curl http://localhost:8001/health
```

## 7. 다중 지점 배포

### 7.1 지점별 Worker 실행
```bash
# 오류동역점
python -m src.workers.detection_worker --store oryudong --channels 1,2,3,4,5,6,7,8

# 강남점
python -m src.workers.detection_worker --store gangnam --channels 1,2,3,4,5,6,7,8

# 홍대점
python -m src.workers.detection_worker --store hongdae --channels 1,2,3,4,5,6,7,8
```

### 7.2 중앙 집중식 서버
```
단일 서버에서 모든 지점의 CCTV를 모니터링하려면:

1. 각 지점의 RTSP 접근 가능하도록 네트워크 설정
2. Supabase에 모든 지점 데이터 등록
3. Worker 프로세스를 지점별로 실행
```

## 8. 유지보수

### 8.1 오래된 데이터 정리
```sql
-- 30일 이상 된 이벤트 삭제
DELETE FROM detection_events
WHERE created_at < NOW() - INTERVAL '30 days';

-- Supabase Dashboard에서 정기적으로 실행
```

### 8.2 백업
```bash
# Supabase 자동 백업 (Pro 플랜)
# 또는 pg_dump로 수동 백업
pg_dump -h db.your-project.supabase.co -U postgres > backup.sql
```

### 8.3 업데이트
```bash
git pull
pip install -r requirements.txt
sudo systemctl restart cctv-api cctv-worker
```

## 9. 문제 해결

### Worker가 RTSP 연결 실패
```bash
# VLC로 먼저 테스트
vlc rtsp://admin:password@host:8554/live_01

# 네트워크 확인
ping 218.50.241.157
telnet 218.50.241.157 8554
```

### Detection이 부정확
```bash
# Confidence threshold 조정
# .env 파일에서:
CONFIDENCE_THRESHOLD=0.3  # 낮추면 더 많이 감지, 높이면 엄격하게
```

### Supabase 용량 초과
```bash
# Free tier: 500MB
# 해결: 오래된 데이터 삭제 또는 Pro 플랜 업그레이드
```

## 10. 성능 최적화

### 10.1 채널당 Worker 수
```
권장:
- 4 channels/worker (총 4 workers)
- CPU: 4 cores 이상
- RAM: 8GB 이상
- GPU: 선택 (YOLO 속도 향상)
```

### 10.2 스냅샷 간격
```bash
# .env에서 조정
SNAPSHOT_INTERVAL=3  # 초 단위 (기본: 3초)
# 낮출수록 실시간성 증가, CPU 사용 증가
```

## 비용 예상

**Supabase Free Tier**:
- $0/월
- 500MB DB
- Unlimited API calls
- 2GB bandwidth

**VPS 서버 (예: Vultr, DigitalOcean)**:
- $10-20/월 (2 CPU, 4GB RAM)

**총 예상 비용**: $10-20/월

**확장 시 (Pro Tier)**:
- Supabase Pro: $25/월
- VPS 업그레이드: $40-80/월
- 총: $65-105/월
