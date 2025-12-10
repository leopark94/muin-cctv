# 실시간 좌석 모니터링 시스템 개발 플랜

## 📋 요구사항 분석

### 핵심 기능
1. **실시간 계속 분석**: 16채널 무중단 감지 (1~5초 간격)
2. **좌석 맵핑**: 물리적 좌석 번호 ↔ ROI 매칭
3. **점유 여부**: 현재 사람 앉아있는지 확인
4. **부재 시간 추적**: 비어있는 시간 측정 (청소 시기, 미사용 좌석 파악)
5. **짐 감지**: 사람 없는데 물건만 있는 좌석 감지 → 자리 맡기 의심

---

## 🏗️ 시스템 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                   Web Dashboard                      │
│  (실시간 좌석 맵, 점유율, 알림)                        │
└────────────────┬────────────────────────────────────┘
                 │ WebSocket
┌────────────────┴────────────────────────────────────┐
│              FastAPI Server                          │
│  - REST API (설정, 히스토리 조회)                     │
│  - WebSocket (실시간 상태 브로드캐스트)                │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────┴────────────────────────────────────┐
│          Background Worker (Celery/Thread)          │
│  ┌──────────────────────────────────────┐           │
│  │  Channel 1-16 Detection Loop         │           │
│  │  - RTSP 연결 유지                     │           │
│  │  - YOLO 추론 (3초마다)                │           │
│  │  - 상태 변화 감지                     │           │
│  └──────────────────────────────────────┘           │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────┴────────────────────────────────────┐
│          State Management Layer                      │
│  - 현재 점유 상태 (Redis/메모리)                     │
│  - 부재 시간 카운터                                  │
│  - 짐 감지 로직                                      │
└────────────────┬────────────────────────────────────┘
                 │
┌────────────────┴────────────────────────────────────┐
│              Database (PostgreSQL)                   │
│  - detection_events (이벤트 로그)                    │
│  - seat_status_history (상태 변화 히스토리)          │
│  - occupancy_stats (집계 통계)                       │
└─────────────────────────────────────────────────────┘
```

---

## 🗄️ 데이터베이스 스키마

### 1. `seats` - 좌석 마스터 테이블
```sql
CREATE TABLE seats (
    seat_id VARCHAR(20) PRIMARY KEY,        -- "1A", "2B" 등
    channel_id INT NOT NULL,                 -- RTSP 채널 (1-16)
    roi_polygon JSONB NOT NULL,              -- [[x1,y1], [x2,y2], ...]
    seat_type VARCHAR(20) DEFAULT 'normal',  -- 'normal', 'premium', 'vip'
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 예시 데이터
INSERT INTO seats VALUES
    ('1A', 12, '[[100,100],[200,100],[200,200],[100,200]]', 'normal', true),
    ('1B', 12, '[[250,100],[350,100],[350,200],[250,200]]', 'normal', true);
```

### 2. `seat_status` - 현재 상태 (실시간)
```sql
CREATE TABLE seat_status (
    seat_id VARCHAR(20) PRIMARY KEY REFERENCES seats(seat_id),
    status VARCHAR(20) NOT NULL,             -- 'empty', 'occupied', 'abandoned'
    person_detected BOOLEAN DEFAULT FALSE,   -- 사람 감지 여부
    object_detected BOOLEAN DEFAULT FALSE,   -- 물건 감지 여부
    last_person_seen TIMESTAMP,              -- 마지막 사람 목격 시간
    last_empty_time TIMESTAMP,               -- 마지막 비움 시간
    vacant_duration_seconds INT DEFAULT 0,   -- 부재 시간 (초)
    confidence FLOAT,                        -- 감지 신뢰도
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### 3. `detection_events` - 이벤트 로그
```sql
CREATE TABLE detection_events (
    id SERIAL PRIMARY KEY,
    seat_id VARCHAR(20) REFERENCES seats(seat_id),
    event_type VARCHAR(20) NOT NULL,         -- 'person_enter', 'person_leave', 'abandoned_detected'
    person_detected BOOLEAN,
    object_detected BOOLEAN,
    confidence FLOAT,
    snapshot_path VARCHAR(255),              -- 스냅샷 경로
    metadata JSONB,                          -- 추가 정보 (bbox 좌표 등)
    created_at TIMESTAMP DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_events_seat_time ON detection_events(seat_id, created_at DESC);
CREATE INDEX idx_events_type ON detection_events(event_type, created_at DESC);
```

### 4. `occupancy_stats` - 집계 통계 (시간대별)
```sql
CREATE TABLE occupancy_stats (
    id SERIAL PRIMARY KEY,
    seat_id VARCHAR(20) REFERENCES seats(seat_id),
    hour_slot TIMESTAMP NOT NULL,            -- 시간대 (매 시간 정각)
    occupied_minutes INT DEFAULT 0,          -- 점유 분
    vacant_minutes INT DEFAULT 0,            -- 비어있던 분
    abandoned_minutes INT DEFAULT 0,         -- 짐만 있던 분
    total_entries INT DEFAULT 0,             -- 입장 횟수
    avg_stay_minutes INT,                    -- 평균 체류 시간
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(seat_id, hour_slot)
);

-- 시간대별 점유율 조회
CREATE INDEX idx_stats_hour ON occupancy_stats(hour_slot DESC);
```

---

## 🔍 짐 감지 로직

### 전략: 다단계 감지
```python
class AbandonedDetector:
    """사람은 없는데 물건만 있는 좌석 감지"""

    def detect_abandoned_seat(self, current_frame, seat_roi):
        """
        3단계 짐 감지:
        1. 사람 감지 → 없음
        2. 객체 변화 감지 → 있음 (배경과 다름)
        3. 시간 조건 → 10분 이상 지속
        """

        # 1단계: 사람 있나?
        person_detections = yolo.detect_person(frame, roi)
        if len(person_detections) > 0:
            return False  # 사람 있으면 정상

        # 2단계: 배경과 비교해서 물건이 있나?
        roi_region = extract_roi(frame, seat_roi)
        baseline_frame = get_baseline_empty_frame(seat_id)

        diff = cv2.absdiff(roi_region, baseline_frame)
        diff_score = np.sum(diff) / diff.size

        # 차이가 크면 물건 있음
        if diff_score > OBJECT_THRESHOLD:
            # 3단계: 얼마나 오래 지속되었나?
            vacant_duration = get_vacant_duration(seat_id)

            if vacant_duration > 600:  # 10분
                return True  # 짐 감지!

        return False
```

### 배경 이미지 자동 갱신
```python
# 매일 새벽 3시, 확실히 빈 좌석일 때 배경 이미지 업데이트
if current_time.hour == 3 and all_seats_empty():
    for seat in seats:
        save_baseline_frame(seat.id, capture_frame())
```

---

## 🔄 실시간 감지 워커

### Worker 구조 (멀티프로세싱)
```python
# src/workers/realtime_detector.py

import multiprocessing as mp
from typing import Dict, List
import time
import redis

class RealtimeDetectionWorker:
    """16채널 병렬 실시간 감지"""

    def __init__(self):
        self.redis_client = redis.Redis(host='localhost', port=6379)
        self.db = PostgreSQLConnection()
        self.interval = 3  # 3초마다

    def start_all_channels(self):
        """모든 활성 채널에 대해 워커 시작"""
        channels = get_active_channels()

        # 각 채널당 별도 프로세스
        processes = []
        for channel_id in channels:
            p = mp.Process(
                target=self.monitor_channel,
                args=(channel_id,)
            )
            p.start()
            processes.append(p)

        # 모든 프로세스 종료 대기
        for p in processes:
            p.join()

    def monitor_channel(self, channel_id: int):
        """단일 채널 모니터링 루프"""
        rtsp_url = get_rtsp_url(channel_id)
        client = RTSPClient(rtsp_url)
        detector = PersonDetector(model='yolo11n.pt')

        # 연결 유지
        max_retries = 3
        retry_count = 0

        while True:
            try:
                # RTSP 연결
                if not client.is_connected:
                    if not client.connect(timeout=10):
                        retry_count += 1
                        if retry_count >= max_retries:
                            log.error(f"Channel {channel_id} 연결 실패, 재시도 중단")
                            time.sleep(60)  # 1분 대기
                            retry_count = 0
                        continue
                    retry_count = 0

                # 프레임 캡처
                frame = client.capture_frame()
                if frame is None:
                    continue

                # 해당 채널의 모든 좌석 감지
                seats = self.db.get_seats_by_channel(channel_id)

                for seat in seats:
                    # YOLO 추론
                    detections = detector.detect_persons(frame, seat.roi)

                    # 상태 업데이트
                    self.update_seat_status(seat.id, detections, frame)

                # 대기
                time.sleep(self.interval)

            except Exception as e:
                log.error(f"Channel {channel_id} 오류: {e}")
                time.sleep(5)

    def update_seat_status(self, seat_id: str, detections: List, frame):
        """좌석 상태 업데이트 및 이벤트 기록"""
        person_detected = len(detections) > 0

        # 현재 상태 조회
        current_status = self.db.get_seat_status(seat_id)
        previous_person = current_status.person_detected if current_status else False

        # 상태 변화 감지
        if person_detected and not previous_person:
            # 사람 입장
            self.log_event(seat_id, 'person_enter', frame)
            self.update_redis(seat_id, 'occupied')

        elif not person_detected and previous_person:
            # 사람 퇴장
            self.log_event(seat_id, 'person_leave', frame)

            # 짐 감지 체크
            if self.check_abandoned(seat_id, frame):
                self.log_event(seat_id, 'abandoned_detected', frame)
                self.update_redis(seat_id, 'abandoned')
            else:
                self.update_redis(seat_id, 'empty')

        # DB 업데이트
        self.db.update_seat_status(
            seat_id=seat_id,
            person_detected=person_detected,
            timestamp=datetime.now()
        )

    def check_abandoned(self, seat_id: str, frame) -> bool:
        """짐 감지 체크"""
        detector = AbandonedDetector()
        seat = self.db.get_seat(seat_id)
        return detector.detect_abandoned_seat(frame, seat.roi)

    def update_redis(self, seat_id: str, status: str):
        """Redis에 실시간 상태 저장 (빠른 조회용)"""
        self.redis_client.hset(
            f"seat:{seat_id}",
            mapping={
                'status': status,
                'updated_at': time.time()
            }
        )

        # WebSocket 브로드캐스트
        self.broadcast_to_websocket(seat_id, status)
```

---

## 🌐 실시간 대시보드 (WebSocket)

### FastAPI WebSocket 엔드포인트
```python
# src/api/realtime_api.py

from fastapi import WebSocket, WebSocketDisconnect
import asyncio
import json

class ConnectionManager:
    """WebSocket 연결 관리"""

    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        """모든 클라이언트에게 메시지 전송"""
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

@app.websocket("/ws/realtime")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)

    try:
        # 초기 상태 전송
        initial_state = get_all_seat_status()
        await websocket.send_json({
            'type': 'initial_state',
            'data': initial_state
        })

        # 연결 유지
        while True:
            # 클라이언트 메시지 대기 (ping/pong)
            data = await websocket.receive_text()

            # 주기적 상태 업데이트는 Redis pub/sub으로 처리

    except WebSocketDisconnect:
        manager.disconnect(websocket)
```

### 프론트엔드 (JavaScript)
```javascript
// static/realtime.js

const ws = new WebSocket('ws://localhost:8000/ws/realtime');

ws.onmessage = (event) => {
    const message = JSON.parse(event.data);

    switch(message.type) {
        case 'initial_state':
            renderSeatMap(message.data);
            break;

        case 'seat_update':
            updateSeat(message.data.seat_id, message.data.status);
            break;

        case 'abandoned_alert':
            showAlert(message.data.seat_id, '짐만 있음 감지');
            break;
    }
};

function renderSeatMap(seats) {
    const grid = document.getElementById('seat-grid');
    grid.innerHTML = '';

    seats.forEach(seat => {
        const div = document.createElement('div');
        div.className = `seat seat-${seat.status}`;
        div.innerHTML = `
            <div class="seat-id">${seat.seat_id}</div>
            <div class="status">${getStatusText(seat.status)}</div>
            <div class="vacant-time">${formatVacantTime(seat.vacant_duration)}</div>
        `;
        grid.appendChild(div);
    });
}

function getStatusText(status) {
    const map = {
        'empty': '빈 좌석',
        'occupied': '사용 중',
        'abandoned': '짐만 있음'
    };
    return map[status] || status;
}
```

---

## 📊 대시보드 UI 레이아웃

```
┌─────────────────────────────────────────────────────────┐
│  앤딩스터디카페 - 실시간 좌석 모니터링                    │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐    │
│  │ 전체 좌석    │ │ 점유 중      │ │ 짐만 있음    │    │
│  │   120석      │ │   85석 (71%) │ │   5석        │    │
│  └──────────────┘ └──────────────┘ └──────────────┘    │
├─────────────────────────────────────────────────────────┤
│  좌석 맵                                                 │
│  ┌─────┬─────┬─────┬─────┐ ┌─────┬─────┬─────┬─────┐  │
│  │ 1A  │ 1B  │ 1C  │ 1D  │ │ 2A  │ 2B  │ 2C  │ 2D  │  │
│  │ 🟢  │ 🔴  │ 🔴  │ 🟢  │ │ 🔴  │ 🟡  │ 🔴  │ 🔴  │  │
│  │ 2h  │     │     │ 5h  │ │     │ 15m │     │     │  │
│  └─────┴─────┴─────┴─────┘ └─────┴─────┴─────┴─────┘  │
│  🟢 빈자리  🔴 사용중  🟡 짐만 있음                     │
│  (숫자 = 부재 시간)                                     │
├─────────────────────────────────────────────────────────┤
│  ⚠️ 알림                                                │
│  • 좌석 2B - 짐만 15분째 (사람 없음)                    │
│  • 좌석 3C - 3시간 넘게 비어있음 (청소 필요?)           │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 구현 단계 (4주 계획)

### Week 1: 인프라 구축
- [ ] PostgreSQL 설치 및 스키마 생성
- [ ] Redis 설치 (실시간 상태 캐시)
- [ ] 데이터 모델 구현 (SQLAlchemy ORM)
- [ ] 테스트 데이터 생성

### Week 2: 백그라운드 워커
- [ ] RealtimeDetectionWorker 구현
- [ ] 멀티프로세싱 채널 감지
- [ ] 상태 추적 로직 (점유, 부재 시간)
- [ ] 자동 재연결 + 에러 핸들링
- [ ] 짐 감지 로직 기본 구현

### Week 3: API + WebSocket
- [ ] FastAPI WebSocket 엔드포인트
- [ ] Redis Pub/Sub 통합
- [ ] REST API 확장 (히스토리 조회)
- [ ] 통계 집계 API

### Week 4: 프론트엔드 + 배포
- [ ] 실시간 좌석 맵 UI
- [ ] WebSocket 클라이언트
- [ ] 알림 시스템
- [ ] Docker Compose 배포
- [ ] 부하 테스트

---

## 🔧 기술 스택

| 계층 | 기술 | 용도 |
|------|------|------|
| ML | YOLOv11n | 사람 감지 |
| 영상 처리 | OpenCV | RTSP, 이미지 처리 |
| 백그라운드 | Python multiprocessing | 16채널 병렬 처리 |
| 캐시 | Redis | 실시간 상태 저장 |
| DB | PostgreSQL | 이벤트/통계 저장 |
| API | FastAPI + WebSocket | REST + 실시간 통신 |
| 프론트엔드 | Vanilla JS + WebSocket | 실시간 UI |
| 배포 | Docker Compose | 컨테이너화 |

---

## ⚡ 성능 목표

- **감지 주기**: 3초 (채널당)
- **전체 처리 시간**: <2초 (16채널 동시)
- **WebSocket 지연**: <100ms
- **DB 쓰기**: 비동기 배치 (10초마다)
- **메모리**: <2GB (전체 시스템)

---

## 🎯 핵심 메트릭

### 운영 지표
1. **실시간 점유율**: 현재 몇 % 사용 중?
2. **평균 체류 시간**: 사용자가 평균 몇 시간 앉아있나?
3. **회전율**: 하루에 좌석당 몇 명 사용?
4. **피크 타임**: 가장 붐비는 시간대?
5. **짐 방치 빈도**: 하루 몇 건 발생?

### 기술 지표
1. **RTSP 연결 안정성**: 24시간 uptime
2. **감지 정확도**: Person detection mAP
3. **처리 속도**: 초당 프레임 수
4. **시스템 부하**: CPU/메모리 사용률

---

## 🔐 보안 고려사항

1. **개인정보 보호**
   - 얼굴 블러 처리 (선택)
   - 스냅샷 자동 삭제 (7일 후)
   - 접근 로그 기록

2. **데이터 암호화**
   - DB 연결 SSL
   - WebSocket WSS (프로덕션)

3. **접근 제어**
   - 관리자 인증 (JWT)
   - 대시보드 IP 화이트리스트

---

## 📝 다음 단계

1. **이 플랜 리뷰 및 피드백**
2. **Week 1 시작: DB 스키마 생성**
3. **프로토타입 구현 (1-2채널만)**
4. **전체 확장**

질문이나 수정 사항 있으시면 알려주세요!
