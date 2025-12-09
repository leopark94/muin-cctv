---
description: CCTV 시스템 프로덕션 배포. "배포해줘", "서버 올려", "운영 설정" 등의 요청 시 사용
tags: [cctv, deploy, production, docker]
---

# CCTV System Deployment

CCTV 좌석 감지 시스템을 프로덕션 환경에 배포합니다.

## 배포 전 체크리스트

- [ ] .env 파일 설정 (RTSP 정보, 모델 설정)
- [ ] ROI 설정 완료 (모든 활성 채널)
- [ ] RTSP 연결 테스트 성공
- [ ] YOLO 모델 다운로드 완료
- [ ] 방화벽 포트 오픈 (8000)

## Docker 배포 (권장)

### 1. Dockerfile 작성

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Download YOLO model
RUN python -c "from ultralytics import YOLO; YOLO('yolo11n.pt')"

EXPOSE 8000

CMD ["uvicorn", "src.api.roi_config_api:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 2. 빌드 및 실행

```bash
# 이미지 빌드
docker build -t muin-cctv:latest .

# 컨테이너 실행
docker run -d \
  --name muin-cctv \
  -p 8000:8000 \
  -v $(pwd)/data:/app/data \
  -v $(pwd)/.env:/app/.env \
  --restart unless-stopped \
  muin-cctv:latest
```

### 3. Docker Compose

```yaml
version: '3.8'

services:
  cctv:
    build: .
    container_name: muin-cctv
    ports:
      - "8000:8000"
    volumes:
      - ./data:/app/data
      - ./.env:/app/.env
    restart: unless-stopped
    environment:
      - TZ=Asia/Seoul
```

## 일반 배포 (Systemd)

### 1. Systemd 서비스 생성

```bash
sudo nano /etc/systemd/system/muin-cctv.service
```

```ini
[Unit]
Description=MUIN CCTV Seat Detection System
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/muin-cctv
Environment="PATH=/opt/muin-cctv/venv/bin"
ExecStart=/opt/muin-cctv/venv/bin/uvicorn src.api.roi_config_api:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 2. 서비스 시작

```bash
sudo systemctl daemon-reload
sudo systemctl enable muin-cctv
sudo systemctl start muin-cctv
sudo systemctl status muin-cctv
```

## Nginx 리버스 프록시

```nginx
server {
    listen 80;
    server_name cctv.yourdomain.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts for long-running requests
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
```

## 모니터링

### 로그 확인

```bash
# Docker
docker logs -f muin-cctv

# Systemd
sudo journalctl -u muin-cctv -f
```

### 헬스 체크

```bash
# API 응답 확인
curl http://localhost:8000/api/channels

# 특정 채널 스냅샷 테스트
curl -I http://localhost:8000/api/channels/12/snapshot
```

## 백업

```bash
# ROI 설정 백업
tar -czf cctv-backup-$(date +%Y%m%d).tar.gz data/roi_configs/

# 자동 백업 (cron)
0 2 * * * cd /opt/muin-cctv && tar -czf backup/roi-$(date +\%Y\%m\%d).tar.gz data/roi_configs/
```

## 보안 설정

1. **환경 변수 보호**
   ```bash
   chmod 600 .env
   ```

2. **방화벽 설정**
   ```bash
   sudo ufw allow 8000/tcp
   sudo ufw enable
   ```

3. **HTTPS 적용** (Let's Encrypt)
   ```bash
   sudo certbot --nginx -d cctv.yourdomain.com
   ```
