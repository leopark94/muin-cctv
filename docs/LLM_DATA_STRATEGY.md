# LLM 데이터 분석 전략

## 개요

이 문서는 CCTV 좌석 감지 시스템에서 수집되는 데이터를 LLM이 분석하여 관리자에게 인사이트를 제공하기 위한 전략을 설명합니다.

## 목표

1. **지속적인 데이터 수집**: 의미 있는 이벤트와 메트릭을 구조화된 형태로 저장
2. **지점별 분석**: 각 지점(오류동역, 강남, 홍대 등)의 특성과 패턴 파악
3. **자동 리포팅**: LLM이 데이터를 분석하여 관리자에게 요약 보고서 생성
4. **예측 분석**: 혼잡 시간대, 좌석 회전율 등 예측

---

## 데이터 구조

### 1. 이벤트 로그 (detection_events)

**목적**: 모든 좌석 상태 변화를 시계열로 기록

```sql
detection_events (
    id BIGSERIAL PRIMARY KEY,
    store_id VARCHAR(50),           -- 지점 구분
    seat_id VARCHAR(20),             -- 좌석 번호
    channel_id INTEGER,              -- 카메라 채널
    event_type VARCHAR(50),          -- person_enter, person_leave, abandoned_detected 등
    previous_status VARCHAR(20),     -- empty, occupied, abandoned
    new_status VARCHAR(20),
    person_detected BOOLEAN,
    object_detected BOOLEAN,
    confidence FLOAT,
    created_at TIMESTAMP DEFAULT NOW()
)
```

**LLM 분석 예시**:
- "오류동역점 오후 2-4시에 퇴실이 많습니다"
- "강남점 A01 좌석이 회전율이 높습니다"
- "주말에 abandoned 이벤트가 30% 증가했습니다"

### 2. 시스템 로그 (system_logs)

**목적**: 시스템 동작, 오류, 성능 메트릭 기록

```sql
system_logs (
    id BIGSERIAL PRIMARY KEY,
    store_id VARCHAR(50) NULLABLE,   -- 전체 시스템 로그는 NULL
    log_level VARCHAR(20),            -- DEBUG, INFO, WARNING, ERROR, CRITICAL
    component VARCHAR(100),           -- 'channel_1_worker', 'api_server', 'detection_engine'
    message TEXT,
    metadata JSONB,                   -- 추가 정보 (에러 스택, 성능 메트릭 등)
    created_at TIMESTAMP DEFAULT NOW()
)
```

**메타데이터 예시**:
```json
{
  "frame_count": 1200,
  "fps": 18.5,
  "detection_latency_ms": 55,
  "error_code": "RTSP_TIMEOUT",
  "retry_count": 3
}
```

**LLM 분석 예시**:
- "채널 3번 카메라가 하루 3회 재연결했습니다"
- "오류동역점 평균 FPS가 15 이하로 떨어졌습니다"
- "지난 주 RTSP 타임아웃이 40% 증가했습니다"

### 3. 점유율 통계 (occupancy_stats)

**목적**: 시간대별 집계 데이터 (hourly aggregation)

```sql
occupancy_stats (
    id BIGSERIAL PRIMARY KEY,
    store_id VARCHAR(50),
    hour_slot TIMESTAMP,              -- 시간대 (2024-01-15 14:00:00)
    total_seats INTEGER,
    occupied_count INTEGER,
    empty_count INTEGER,
    abandoned_count INTEGER,
    occupancy_rate FLOAT,
    peak_occupancy INTEGER,           -- 해당 시간대 최대 점유
    avg_vacant_duration_seconds INTEGER,
    total_events INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(store_id, hour_slot)
)
```

**LLM 분석 예시**:
- "오류동역점 평일 오후 7-9시 평균 점유율 85%"
- "강남점 주말 점심시간 회전율이 2배 높습니다"
- "홍대점 저녁 10시 이후 abandoned 좌석 증가 추세"

### 4. 지점 정보 (stores)

**목적**: 지점별 설정과 특성 저장

```json
{
  "store_id": "oryudong",
  "store_name": "앤딩 오류동역점",
  "location": "서울시 구로구",
  "opening_hours": "06:00-24:00",
  "total_seats": 55,
  "pricing": {
    "hourly": 3000,
    "daily": 12000
  },
  "customer_segments": ["대학생", "직장인", "수험생"],
  "nearby_facilities": ["대학교", "도서관", "지하철역"]
}
```

**LLM 분석 예시**:
- "오류동역점은 대학가 근처라 시험 기간에 점유율 상승"
- "홍대점은 직장인이 많아 평일 저녁 수요 집중"

---

## LLM 프롬프트 전략

### 1. 일일 리포트

**데이터 수집**:
```sql
-- 오늘의 이벤트 요약
SELECT
    event_type,
    COUNT(*) as count,
    AVG(confidence) as avg_confidence
FROM detection_events
WHERE store_id = 'oryudong'
  AND created_at >= CURRENT_DATE
GROUP BY event_type;

-- 오늘의 시간대별 점유율
SELECT
    hour_slot,
    occupancy_rate,
    total_events
FROM occupancy_stats
WHERE store_id = 'oryudong'
  AND hour_slot >= CURRENT_DATE
ORDER BY hour_slot;
```

**LLM 프롬프트**:
```
다음은 앤딩 오류동역점의 2024-12-10 운영 데이터입니다:

[데이터 삽입]

위 데이터를 분석하여 다음을 포함한 일일 리포트를 작성하세요:
1. 오늘의 주요 지표 (총 입실/퇴실, 평균 점유율, 피크 시간대)
2. 전일/전주 대비 변화
3. 특이사항 (abandoned 좌석 증가, 시스템 에러 등)
4. 개선 제안

리포트는 관리자가 5분 안에 읽을 수 있도록 간결하게 작성하세요.
```

### 2. 주간 인사이트

**데이터 수집**:
```sql
-- 지난 7일 트렌드
SELECT
    DATE(hour_slot) as date,
    AVG(occupancy_rate) as avg_occupancy,
    MAX(occupancy_rate) as peak_occupancy,
    SUM(total_events) as daily_events
FROM occupancy_stats
WHERE store_id = 'oryudong'
  AND hour_slot >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(hour_slot)
ORDER BY date;

-- 요일별 패턴
SELECT
    EXTRACT(DOW FROM hour_slot) as day_of_week,
    EXTRACT(HOUR FROM hour_slot) as hour,
    AVG(occupancy_rate) as avg_occupancy
FROM occupancy_stats
WHERE store_id = 'oryudong'
  AND hour_slot >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY day_of_week, hour
ORDER BY day_of_week, hour;
```

**LLM 프롬프트**:
```
다음은 앤딩 오류동역점의 지난 7일 운영 데이터입니다:

[데이터 삽입]

다음을 분석하세요:
1. 요일별/시간대별 점유 패턴
2. 피크 시간대와 한산한 시간대 식별
3. 수익 최적화 제안 (가격 조정, 프로모션 시간대)
4. 운영 효율화 제안 (인력 배치, 청소 시간 등)
```

### 3. 지점 간 비교

**데이터 수집**:
```sql
-- 전체 지점 비교
SELECT
    store_id,
    AVG(occupancy_rate) as avg_occupancy,
    AVG(avg_vacant_duration_seconds) as avg_vacancy,
    SUM(total_events) / 7.0 as daily_avg_events
FROM occupancy_stats
WHERE hour_slot >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY store_id;
```

**LLM 프롬프트**:
```
다음은 전체 앤딩 지점들의 지난 7일 데이터입니다:

[데이터 삽입]

지점별 특성을 분석하여:
1. 가장 성과가 좋은 지점과 이유
2. 개선이 필요한 지점과 구체적 방안
3. 지점 간 베스트 프랙티스 공유
4. 신규 지점 입지 선정 시 고려사항
```

### 4. 예측 및 이상 탐지

**데이터 수집**:
```sql
-- 시간대별 기대값 (과거 30일 평균)
WITH baseline AS (
    SELECT
        EXTRACT(HOUR FROM hour_slot) as hour,
        AVG(occupancy_rate) as expected_occupancy,
        STDDEV(occupancy_rate) as std_occupancy
    FROM occupancy_stats
    WHERE store_id = 'oryudong'
      AND hour_slot >= CURRENT_DATE - INTERVAL '30 days'
      AND hour_slot < CURRENT_DATE
    GROUP BY EXTRACT(HOUR FROM hour_slot)
)
SELECT
    os.hour_slot,
    os.occupancy_rate as actual,
    b.expected_occupancy as expected,
    (os.occupancy_rate - b.expected_occupancy) / b.std_occupancy as z_score
FROM occupancy_stats os
JOIN baseline b ON EXTRACT(HOUR FROM os.hour_slot) = b.hour
WHERE os.store_id = 'oryudong'
  AND os.hour_slot >= CURRENT_DATE
ORDER BY ABS((os.occupancy_rate - b.expected_occupancy) / b.std_occupancy) DESC
LIMIT 10;
```

**LLM 프롬프트**:
```
다음은 오류동역점의 오늘 점유율과 예상값(과거 30일 평균) 비교입니다:

[데이터 삽입]

이상치(z-score > 2)를 분석하여:
1. 예상치를 크게 벗어난 시간대와 가능한 원인
2. 외부 요인 (날씨, 이벤트, 휴일 등) 영향 분석
3. 내일 예상 점유율 예측
4. 대응 방안 (추가 좌석 오픈, 프로모션 등)
```

---

## 데이터 수집 개선 사항

### 현재 구현

✅ **잘 되고 있는 것**:
- `detection_events` 테이블에 상태 변화 이벤트 저장
- confidence, bbox 등 상세 정보 포함
- 실시간 업데이트 (3초 간격)

⚠️ **개선 필요**:
- `print()` 대신 구조화된 로깅 (`logging` 모듈 + JSON)
- `system_logs` 테이블 적극 활용
- 성능 메트릭 자동 수집 (FPS, latency, error rate)
- 시간대별 집계 (`occupancy_stats`) 자동화

### 구현 계획

#### 1단계: 구조화된 로깅 (즉시)

**목표**: 모든 `print()` 문을 구조화된 로그로 전환

**구현**:
```python
# src/utils/logger.py
import logging
import json
from datetime import datetime
from typing import Optional, Dict, Any
from src.database.supabase_client import get_supabase_client

class StructuredLogger:
    def __init__(self, component: str, store_id: Optional[str] = None):
        self.component = component
        self.store_id = store_id
        self.logger = logging.getLogger(component)
        self.db = get_supabase_client()

    def log(self, level: str, message: str, metadata: Optional[Dict] = None):
        # File logging (for debugging)
        log_data = {
            'timestamp': datetime.now().isoformat(),
            'component': self.component,
            'level': level,
            'message': message,
            'metadata': metadata or {}
        }
        self.logger.log(getattr(logging, level), json.dumps(log_data, ensure_ascii=False))

        # Database logging (for LLM analysis)
        if level in ['WARNING', 'ERROR', 'CRITICAL']:
            try:
                self.db.log_system_event(
                    store_id=self.store_id,
                    log_level=level,
                    component=self.component,
                    message=message,
                    metadata=metadata
                )
            except:
                pass  # Don't fail on logging errors

    def info(self, message: str, **kwargs):
        self.log('INFO', message, kwargs)

    def warning(self, message: str, **kwargs):
        self.log('WARNING', message, kwargs)

    def error(self, message: str, **kwargs):
        self.log('ERROR', message, kwargs)
```

**사용 예시** (detection_worker.py):
```python
# Before
print(f"[Channel {self.channel_id}] ⚠️  Failed to capture frame ({error_count}/{max_errors})")

# After
logger.warning(
    "Failed to capture frame",
    channel=self.channel_id,
    error_count=error_count,
    max_errors=max_errors
)
```

#### 2단계: 성능 메트릭 수집 (1주 내)

**목표**: FPS, 감지 지연시간, 에러율 등 자동 수집

**구현**:
```python
class PerformanceMonitor:
    def __init__(self, logger: StructuredLogger):
        self.logger = logger
        self.metrics = {
            'frame_count': 0,
            'detection_time_ms': [],
            'error_count': 0,
            'start_time': time.time()
        }

    def record_frame(self, detection_time_ms: float):
        self.metrics['frame_count'] += 1
        self.metrics['detection_time_ms'].append(detection_time_ms)

    def record_error(self):
        self.metrics['error_count'] += 1

    def report(self):
        uptime = time.time() - self.metrics['start_time']
        fps = self.metrics['frame_count'] / uptime if uptime > 0 else 0
        avg_latency = sum(self.metrics['detection_time_ms']) / len(self.metrics['detection_time_ms']) \
                      if self.metrics['detection_time_ms'] else 0

        self.logger.info(
            "Performance report",
            uptime_hours=uptime / 3600,
            total_frames=self.metrics['frame_count'],
            fps=round(fps, 2),
            avg_detection_ms=round(avg_latency, 2),
            error_count=self.metrics['error_count'],
            error_rate=self.metrics['error_count'] / self.metrics['frame_count'] \
                       if self.metrics['frame_count'] > 0 else 0
        )
```

#### 3단계: 시간대별 집계 자동화 (2주 내)

**목표**: 매시간 자동으로 `occupancy_stats` 업데이트

**구현**:
```python
# src/workers/stats_aggregator.py
from datetime import datetime, timedelta
import schedule
import time

class StatsAggregator:
    def __init__(self, store_id: str):
        self.store_id = store_id
        self.db = get_supabase_client()

    def aggregate_hourly(self):
        """Aggregate last hour's data."""
        now = datetime.now()
        hour_slot = now.replace(minute=0, second=0, microsecond=0)

        # Get events from last hour
        events = self.db.get_recent_events(
            store_id=self.store_id,
            limit=10000  # enough for 1 hour
        )

        # Filter to last hour
        events = [e for e in events if e['created_at'] >= hour_slot.isoformat()]

        # Get current status
        statuses = self.db.get_all_seat_statuses(self.store_id)
        total_seats = len(statuses)
        occupied = sum(1 for s in statuses if s['status'] == 'occupied')
        empty = sum(1 for s in statuses if s['status'] == 'empty')
        abandoned = sum(1 for s in statuses if s['status'] == 'abandoned')

        # Calculate metrics
        stat_data = {
            'store_id': self.store_id,
            'hour_slot': hour_slot,
            'total_seats': total_seats,
            'occupied_count': occupied,
            'empty_count': empty,
            'abandoned_count': abandoned,
            'occupancy_rate': occupied / total_seats if total_seats > 0 else 0,
            'total_events': len(events)
        }

        self.db.upsert_hourly_stat(stat_data)

    def run(self):
        """Run scheduler."""
        # Run every hour at :05 (to capture full hour)
        schedule.every().hour.at(":05").do(self.aggregate_hourly)

        while True:
            schedule.run_pending()
            time.sleep(60)

# Add to start_all.sh
# python -m src.workers.stats_aggregator --store oryudong &
```

#### 4단계: LLM 리포트 생성 (미래)

**목표**: 매일/매주 자동으로 LLM 리포트 생성

**구현** (개념):
```python
# src/reporting/llm_reporter.py
from anthropic import Anthropic

class LLMReporter:
    def __init__(self, store_id: str):
        self.store_id = store_id
        self.db = get_supabase_client()
        self.client = Anthropic()

    def generate_daily_report(self, date: datetime):
        # Fetch data
        data = self._collect_daily_data(date)

        # Create prompt
        prompt = self._build_prompt(data, template='daily')

        # Call LLM
        response = self.client.messages.create(
            model="claude-3-5-sonnet-20241022",
            messages=[{"role": "user", "content": prompt}]
        )

        report = response.content[0].text

        # Save to database or send email
        return report
```

---

## 데이터 접근 방법

### Supabase SQL Editor

1. Supabase 대시보드 접속
2. SQL Editor 열기
3. 쿼리 실행:

```sql
-- 오늘의 이벤트 타임라인
SELECT
    created_at,
    seat_id,
    event_type,
    previous_status,
    new_status,
    confidence
FROM detection_events
WHERE store_id = 'oryudong'
  AND created_at >= CURRENT_DATE
ORDER BY created_at DESC
LIMIT 100;
```

### Python API

```python
from src.database.supabase_client import get_supabase_client
from datetime import datetime, timedelta

db = get_supabase_client()

# 최근 이벤트
events = db.get_recent_events('oryudong', limit=100)

# 지난 7일 통계
start_time = datetime.now() - timedelta(days=7)
stats = db.get_occupancy_stats('oryudong', start_time=start_time)

# 현재 점유 현황
summary = db.get_occupancy_summary_view('oryudong')
print(f"점유율: {summary['occupancy_rate']:.1%}")
```

### REST API

```bash
# 현재 상태
curl http://localhost:8001/api/stores/oryudong/status

# 최근 이벤트
curl http://localhost:8001/api/stores/oryudong/events?limit=100

# 통계
curl http://localhost:8001/api/stores/oryudong/stats
```

---

## 다음 단계

### 즉시 구현 (1주):
1. ✅ 데이터 전략 문서 작성 (이 문서)
2. ⏳ 구조화된 로깅 모듈 구현
3. ⏳ 기존 print() 문을 로깅으로 전환
4. ⏳ 성능 메트릭 수집 추가

### 단기 (1개월):
1. 시간대별 집계 자동화
2. 데이터 시각화 대시보드 개선
3. 알림 시스템 (점유율 임계값, 시스템 에러)

### 중기 (3개월):
1. LLM 리포트 생성 파이프라인
2. 예측 모델 (혼잡 시간대, 수요 예측)
3. A/B 테스트 프레임워크 (가격, 레이아웃 등)

### 장기 (6개월+):
1. 다중 지점 통합 대시보드
2. 자동 의사결정 시스템 (동적 가격 조정 등)
3. 고객 행동 패턴 분석

---

## 결론

현재 시스템은 이미 LLM 분석을 위한 좋은 기반을 갖추고 있습니다:
- ✅ 구조화된 데이터베이스 스키마
- ✅ 실시간 이벤트 로깅
- ✅ 멀티 스토어 지원

다음 개선 사항들을 단계적으로 구현하면:
1. **더 풍부한 데이터**: 성능 메트릭, 시스템 로그, 집계 통계
2. **더 나은 접근성**: 구조화된 로깅, API, 쿼리 가이드
3. **자동화**: 리포트 생성, 이상 탐지, 알림

이를 통해 LLM이 데이터를 효과적으로 분석하여 관리자에게 실질적인 인사이트를 제공할 수 있습니다.
