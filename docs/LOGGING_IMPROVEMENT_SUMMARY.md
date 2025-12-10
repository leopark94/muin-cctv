# 로깅 시스템 개선 요약

## 개선 내용

### 1. 구조화된 로깅 시스템 구현 ✅

**목적**: LLM이 분석하기 쉬운 구조화된 데이터 수집

**구현 파일**: `src/utils/logger.py`

**주요 기능**:
- `StructuredLogger`: JSON 형식 로그 + 데이터베이스 저장
- `PerformanceMonitor`: 성능 메트릭 자동 수집 (FPS, latency, error rate)
- 로그 레벨별 자동 처리:
  - DEBUG/INFO: 파일로만 저장
  - WARNING/ERROR/CRITICAL: 파일 + 데이터베이스 저장

**로그 형식**:
```json
{
  "timestamp": "2024-12-10T15:30:45.123456",
  "level": "INFO",
  "component": "channel_1_worker",
  "message": "Status changed",
  "metadata": {
    "channel": 1,
    "seat_id": "A01",
    "previous_status": "empty",
    "new_status": "occupied",
    "confidence": 0.892
  }
}
```

### 2. Detection Worker 로깅 전환 ✅

**변경 파일**: `src/workers/detection_worker.py`

**Before**:
```python
print(f"[Channel {self.channel_id}] ⚠️  Failed to capture frame")
```

**After**:
```python
self.logger.warning(
    "Failed to capture frame",
    channel=self.channel_id,
    error_count=error_count,
    max_errors=max_errors
)
self.perf_monitor.record_error()
```

**개선 효과**:
- 모든 이벤트가 구조화된 형식으로 저장
- 성능 메트릭 자동 수집 (매 프레임)
- 데이터베이스에 WARNING 이상 로그 자동 저장
- 1분마다 성능 리포트 자동 생성

### 3. LLM 데이터 분석 전략 문서 ✅

**파일**: `docs/LLM_DATA_STRATEGY.md`

**내용**:
1. **데이터 구조 설명**:
   - `detection_events`: 좌석 상태 변화 이벤트
   - `system_logs`: 시스템 로그 (에러, 성능 등)
   - `occupancy_stats`: 시간대별 집계 통계
   - `stores`: 지점 정보

2. **LLM 프롬프트 전략**:
   - 일일 리포트 생성
   - 주간 인사이트 분석
   - 지점 간 비교
   - 예측 및 이상 탐지

3. **구현 로드맵**:
   - 1단계 (완료): 구조화된 로깅
   - 2단계 (1주): 성능 메트릭 수집
   - 3단계 (2주): 시간대별 집계 자동화
   - 4단계 (미래): LLM 리포트 자동 생성

## 데이터 수집 개선 사항

### 현재 수집 중인 데이터:

#### 1. 이벤트 로그 (실시간)
- 좌석 상태 변화 (person_enter, person_leave, abandoned_detected)
- 감지 신뢰도, bounding box, IOU 값
- 이벤트 타임스탬프

#### 2. 시스템 로그 (자동)
- WARNING 이상 이벤트 (RTSP 실패, DB 에러 등)
- 성능 메트릭 (매 1분)
- 워커 시작/종료 통계

#### 3. 성능 메트릭 (자동)
- 처리 FPS
- 프레임당 감지 시간 (ms)
- 에러 발생 횟수 및 비율
- 업타임

## 로그 파일 구조

```
logs/
├── channel_1_worker.log         # 채널 1 워커 로그 (JSON)
├── channel_2_worker.log         # 채널 2 워커 로그 (JSON)
├── channel_3_worker.log         # 채널 3 워커 로그 (JSON)
├── channel_4_worker.log         # 채널 4 워커 로그 (JSON)
├── multi_channel_orchestrator.log  # 오케스트레이터 로그 (JSON)
├── api.log                      # API 서버 로그 (텍스트)
└── worker.log                   # 통합 워커 로그 (텍스트, 기존)
```

## 데이터베이스 테이블

### system_logs
```sql
CREATE TABLE system_logs (
    id BIGSERIAL PRIMARY KEY,
    store_id VARCHAR(50),          -- 지점 ID (NULL이면 전체 시스템)
    log_level VARCHAR(20),          -- DEBUG, INFO, WARNING, ERROR, CRITICAL
    component VARCHAR(100),         -- 컴포넌트 이름
    message TEXT,                   -- 로그 메시지
    metadata JSONB,                 -- 구조화된 추가 정보
    created_at TIMESTAMP DEFAULT NOW()
);

-- 인덱스
CREATE INDEX idx_system_logs_store_time ON system_logs(store_id, created_at DESC);
CREATE INDEX idx_system_logs_level ON system_logs(log_level);
CREATE INDEX idx_system_logs_component ON system_logs(component);
```

## LLM 분석 활용 예시

### 1. 성능 분석
```sql
-- 지난 24시간 채널별 평균 FPS
SELECT
    metadata->>'channel_id' as channel,
    AVG((metadata->>'fps')::float) as avg_fps,
    AVG((metadata->>'avg_detection_ms')::float) as avg_latency_ms,
    SUM((metadata->>'error_count')::int) as total_errors
FROM system_logs
WHERE component LIKE 'channel_%_worker'
  AND message = 'Performance report'
  AND created_at >= NOW() - INTERVAL '24 hours'
GROUP BY metadata->>'channel_id';
```

**LLM 프롬프트**:
```
다음은 지난 24시간 채널별 성능 데이터입니다:
[쿼리 결과]

다음을 분석하세요:
1. 성능이 저하된 채널 식별
2. 에러가 많이 발생한 채널과 원인
3. 개선 방안 제시
```

### 2. 시스템 안정성 분석
```sql
-- 시간대별 에러 발생 빈도
SELECT
    DATE_TRUNC('hour', created_at) as hour,
    COUNT(*) as error_count,
    COUNT(DISTINCT component) as affected_components,
    ARRAY_AGG(DISTINCT message) as error_types
FROM system_logs
WHERE log_level IN ('ERROR', 'CRITICAL')
  AND created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', created_at)
ORDER BY hour DESC;
```

**LLM 프롬프트**:
```
다음은 지난 7일간 시간대별 에러 발생 현황입니다:
[쿼리 결과]

다음을 분석하세요:
1. 에러 발생 패턴 (특정 시간대 집중 여부)
2. 반복되는 에러 타입
3. 시스템 안정성 평가
4. 예방 조치 제안
```

### 3. 운영 인사이트
```sql
-- 좌석 상태 변화 패턴 (시간대별)
SELECT
    EXTRACT(HOUR FROM created_at) as hour,
    event_type,
    COUNT(*) as event_count,
    AVG(confidence) as avg_confidence
FROM detection_events
WHERE store_id = 'oryudong'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY EXTRACT(HOUR FROM created_at), event_type
ORDER BY hour, event_type;
```

**LLM 프롬프트**:
```
다음은 오류동역점의 지난 30일 시간대별 좌석 이용 패턴입니다:
[쿼리 결과]

다음을 분석하세요:
1. 피크 시간대 식별
2. 회전율이 높은 시간대
3. 운영 최적화 방안 (청소 시간, 인력 배치 등)
4. 매출 증대 기회 (프로모션 시간대 등)
```

## 다음 단계

### 즉시 가능 (현재 구조로):
- ✅ 구조화된 로그 수집
- ✅ 성능 메트릭 자동 추적
- ✅ 데이터베이스 저장
- ✅ SQL 쿼리로 데이터 추출

### 1주 내 구현:
- [ ] 시간대별 집계 자동화 (`stats_aggregator.py`)
- [ ] 알림 시스템 (Slack/Email)
- [ ] 대시보드 개선 (실시간 성능 그래프)

### 1개월 내 구현:
- [ ] LLM 리포트 생성 파이프라인
- [ ] 자동 일일/주간 리포트 발송
- [ ] 이상 탐지 시스템

### 장기 (3-6개월):
- [ ] 예측 모델 (혼잡도, 수요 예측)
- [ ] 다중 지점 비교 분석
- [ ] 자동 의사결정 지원

## 사용 방법

### 로그 확인
```bash
# 실시간 로그 확인 (JSON)
tail -f logs/channel_1_worker.log | jq .

# 에러만 필터링
tail -f logs/channel_1_worker.log | jq 'select(.level == "ERROR")'

# 성능 리포트만 보기
tail -f logs/channel_1_worker.log | jq 'select(.message == "Performance report")'
```

### 데이터베이스 쿼리
```python
from src.database.supabase_client import get_supabase_client

db = get_supabase_client()

# 최근 에러 로그
response = db.client.table('system_logs').select('*') \
    .eq('log_level', 'ERROR') \
    .order('created_at', desc=True) \
    .limit(10) \
    .execute()

for log in response.data:
    print(f"{log['created_at']} - {log['component']}: {log['message']}")
```

## 결론

이제 시스템은 LLM 분석에 최적화된 구조화된 데이터를 수집합니다:

1. **이벤트 로그**: 모든 좌석 변화 기록 (실시간)
2. **시스템 로그**: 에러, 경고, 성능 메트릭
3. **성능 추적**: FPS, latency, error rate 자동 수집
4. **JSON 형식**: 파싱 쉽고 LLM이 이해하기 좋음
5. **데이터베이스 저장**: 장기 분석 가능

향후 LLM을 활용한 자동 리포트 생성 시, 별도의 데이터 전처리 없이 바로 활용 가능합니다.
