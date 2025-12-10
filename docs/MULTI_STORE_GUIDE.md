# 다지점 관리 가이드

## 🏢 아키텍처 옵션

### 옵션 1: **독립 운영** (현재 구조)
각 지점이 별도의 서버에서 독립적으로 운영

```
오류동점: Server A (독립)
강남점: Server B (독립)
홍대점: Server C (독립)
```

**장점**:
- 간단한 구조
- 한 지점 장애가 다른 지점에 영향 없음
- 지점별 커스터마이징 쉬움

**단점**:
- 통합 관리 어려움
- 서버 비용 증가

**설정 방법**:
```bash
# 각 지점 서버의 .env
GOSCA_STORE_ID=Anding-Oryudongyeok-sca  # 지점마다 다르게
RTSP_HOST=218.50.241.157                # 지점별 CCTV 서버
```

---

### 옵션 2: **통합 서버** (권장)
하나의 서버에서 여러 지점 동시 모니터링

```
┌─────────────────────────────────────┐
│      통합 모니터링 서버              │
│  ┌──────────┬──────────┬──────────┐ │
│  │ 오류동점 │ 강남점   │ 홍대점   │ │
│  └──────────┴──────────┴──────────┘ │
└─────────────────────────────────────┘
```

**장점**:
- 모든 지점 한눈에 파악
- 비용 효율적
- 통합 데이터 분석 가능

**단점**:
- 서버 부하 증가 (지점 수 x 채널 수)
- 장애 시 전체 영향

**구현 방법**:

#### A. API 파라미터로 지점 선택
```python
# API 엔드포인트
GET /api/stores                    # 전체 지점 목록
GET /api/stores/{store_id}/seats   # 특정 지점 좌석
GET /api/stores/{store_id}/channels/{channel_id}/snapshot
```

#### B. DB 스키마 - store_id 추가
```sql
CREATE TABLE seats (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) NOT NULL,  -- ✅ 지점 구분자
    seat_id VARCHAR(20) NOT NULL,
    channel_id INT,
    roi_polygon JSONB,
    -- ...
    UNIQUE(store_id, seat_id)  -- 지점별로 좌석 번호 겹쳐도 OK
);

CREATE TABLE detection_events (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) NOT NULL,  -- ✅ 지점 구분자
    seat_id VARCHAR(20),
    -- ...
);

-- 인덱스
CREATE INDEX idx_seats_store ON seats(store_id);
CREATE INDEX idx_events_store ON detection_events(store_id, created_at DESC);
```

#### C. 설정 파일 - 여러 지점 정의
```python
# src/config/stores.py
STORES = {
    'oryudong': {
        'gosca_id': 'Anding-Oryudongyeok-sca',
        'rtsp_host': '218.50.241.157',
        'rtsp_port': 8554,
        'channels': list(range(1, 17)),  # 16채널
        'name': '앤딩스터디카페 오류동역점'
    },
    'gangnam': {
        'gosca_id': 'Anding-Gangnam-sca',
        'rtsp_host': '192.168.1.100',
        'rtsp_port': 8554,
        'channels': list(range(1, 9)),   # 8채널
        'name': '앤딩스터디카페 강남점'
    },
    'hongdae': {
        'gosca_id': 'Anding-Hongdae-sca',
        'rtsp_host': '192.168.2.100',
        'rtsp_port': 8554,
        'channels': list(range(1, 13)),  # 12채널
        'name': '앤딩스터디카페 홍대점'
    }
}
```

---

## 🖥️ UI 구조

### 통합 대시보드 레이아웃
```
┌─────────────────────────────────────────────────────────┐
│  앤딩스터디카페 - 전체 지점 현황                          │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐                   │
│  │ 오류동점│ │ 강남점  │ │ 홍대점  │ ← 지점 선택 탭   │
│  │ ●●●●●   │ │ ○○○○○  │ │ ●●○○○  │                   │
│  │ 45/55석 │ │ 28/35석 │ │ 38/48석 │                   │
│  └─────────┘ └─────────┘ └─────────┘                   │
├─────────────────────────────────────────────────────────┤
│  선택된 지점: 오류동점                                    │
│  ┌────────┬────────┬────────┬────────┐                 │
│  │ CH 1   │ CH 2   │ CH 3   │ CH 4   │                 │
│  │ 5/10석 │ 8/12석 │ 3/8석  │ 10/10석│                 │
│  └────────┴────────┴────────┴────────┘                 │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 실시간 감지 워커

### 멀티 프로세스 구조
```python
# 지점별로 워커 그룹 분리
for store_id, config in STORES.items():
    for channel_id in config['channels']:
        process = mp.Process(
            target=monitor_channel,
            args=(store_id, channel_id)
        )
        process.start()

# 예: 3개 지점 x 평균 12채널 = 36개 프로세스
```

### Redis 키 구조
```
seat:{store_id}:{seat_id}:status    -> "occupied" | "empty" | "abandoned"
seat:{store_id}:{seat_id}:updated   -> timestamp
store:{store_id}:occupancy          -> {"total": 55, "occupied": 45}
```

---

## 🔄 운영 시나리오

### 시나리오 1: 신규 지점 추가
```bash
# 1. stores.py에 지점 추가
STORES['sinsa'] = {...}

# 2. ROI 설정
# 웹 UI에서 신사점 선택 → 채널별 ROI 그리기

# 3. 워커 재시작
systemctl restart muin-cctv

# 끝!
```

### 시나리오 2: 본사에서 전체 모니터링
```
본사 대시보드:
- 실시간 전체 지점 점유율
- 지점별 비교 차트
- 이상 상황 알림 (짐 방치, 장시간 부재)
```

### 시나리오 3: 지점별 독립 운영
```
각 지점 직원:
- 자기 지점만 보는 대시보드
- 지점별 접근 권한 제어
```

---

## 💾 데이터 구조 예시

### PostgreSQL
```sql
-- 오류동점 좌석
INSERT INTO seats VALUES
    ('oryudong', '1-0-0', 12, '[...]', ...),
    ('oryudong', '1-0-2', 12, '[...]', ...);

-- 강남점 좌석 (같은 seat_id여도 OK)
INSERT INTO seats VALUES
    ('gangnam', '1-0-0', 1, '[...]', ...),
    ('gangnam', '1-0-2', 1, '[...]', ...);

-- 쿼리 예시
SELECT * FROM seats WHERE store_id = 'oryudong';
SELECT store_id, COUNT(*) FROM seats GROUP BY store_id;
```

---

## 🚀 구현 우선순위

### Phase 1: 단일 지점 완성 (현재)
- ✅ GoSca API 연동
- ✅ RTSP 연결
- ✅ 실시간 감지
- ⬜ DB 구축

### Phase 2: 멀티 지점 준비
- ⬜ store_id 컬럼 추가
- ⬜ API에 store 파라미터
- ⬜ 설정 파일 리팩토링

### Phase 3: 통합 대시보드
- ⬜ 지점 선택 탭
- ⬜ 전체 통계
- ⬜ 지점 간 비교

---

## 🤔 추천 방식

### 소규모 (1~3개 지점)
→ **옵션 2: 통합 서버**
- 관리 편함
- 비용 효율적

### 대규모 (10개+ 지점)
→ **하이브리드**
- 지역별로 서버 분산 (서울권, 경기권 등)
- 중앙 통합 대시보드는 별도

---

## 💡 현재 구조로 멀티 지점 지원 방법

### 즉시 가능:
```bash
# .env 파일만 바꿔서 다른 지점 운영
GOSCA_STORE_ID=Anding-Gangnam-sca
RTSP_HOST=192.168.1.100
```

### 코드 수정 필요:
```python
# MultiStoreManager 사용
from src.utils.multi_store_manager import MultiStoreManager

manager = MultiStoreManager()
summary = manager.get_total_occupancy()

# Output:
# oryudong: 45/55 (81.8%)
# gangnam: 28/35 (80.0%)
# hongdae: 38/48 (79.2%)
```

---

질문 있으시면 말씀해주세요! 🙋‍♂️
