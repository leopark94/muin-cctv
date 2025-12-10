# Supabase 설정 가이드

## 1. Supabase 프로젝트 생성

1. https://supabase.com 접속
2. "New Project" 클릭
3. 프로젝트 정보 입력:
   - Name: `muin-cctv-seats`
   - Database Password: 안전한 비밀번호 생성
   - Region: `Northeast Asia (Seoul)` 선택 (가장 가까운 리전)

## 2. 데이터베이스 스키마 적용

### 방법 1: SQL Editor 사용 (권장)

1. Supabase Dashboard → SQL Editor
2. `database/schema.sql` 파일 내용 복사
3. SQL Editor에 붙여넣기
4. "Run" 클릭

### 방법 2: Supabase CLI 사용

```bash
# Supabase CLI 설치
npm install -g supabase

# 로그인
supabase login

# 프로젝트 링크
supabase link --project-ref YOUR_PROJECT_REF

# 마이그레이션 적용
supabase db push
```

## 3. 환경 변수 설정

Supabase Dashboard → Settings → API에서 다음 정보 확인:

```bash
# .env 파일에 추가
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_KEY=YOUR_ANON_PUBLIC_KEY
SUPABASE_SERVICE_KEY=YOUR_SERVICE_ROLE_KEY  # 서버용 (주의: 노출 금지)
```

**보안 주의사항**:
- `SUPABASE_KEY` (anon key): 클라이언트에서 사용 가능 (RLS로 보호)
- `SUPABASE_SERVICE_KEY`: 서버에서만 사용, 절대 노출 금지

## 4. Row Level Security (RLS) 설정

기본적으로 RLS가 활성화되어 있어 모든 접근이 차단됩니다.
개발 초기에는 RLS를 비활성화하거나, 정책을 추가해야 합니다.

### 개발용: RLS 비활성화 (임시)

```sql
-- SQL Editor에서 실행
ALTER TABLE stores DISABLE ROW LEVEL SECURITY;
ALTER TABLE seats DISABLE ROW LEVEL SECURITY;
ALTER TABLE seat_status DISABLE ROW LEVEL SECURITY;
ALTER TABLE detection_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE occupancy_stats DISABLE ROW LEVEL SECURITY;
ALTER TABLE system_logs DISABLE ROW LEVEL SECURITY;
```

### 프로덕션용: RLS 정책 설정

```sql
-- 모든 사용자가 읽기 가능
CREATE POLICY "Allow read access for all users" ON stores
  FOR SELECT USING (true);

CREATE POLICY "Allow read access for all users" ON seats
  FOR SELECT USING (true);

CREATE POLICY "Allow read access for all users" ON seat_status
  FOR SELECT USING (true);

-- Service Role만 쓰기 가능 (Python 서버에서 service_key 사용)
CREATE POLICY "Allow write for service role" ON detection_events
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow write for service role" ON seat_status
  FOR UPDATE USING (true);
```

## 5. Real-time 구독 활성화

Supabase Dashboard → Database → Publications:

1. `supabase_realtime` publication 확인
2. 다음 테이블을 realtime에 추가:
   - `seat_status` (실시간 좌석 상태 변경)
   - `detection_events` (실시간 감지 이벤트)

또는 SQL로 추가:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE seat_status;
ALTER PUBLICATION supabase_realtime ADD TABLE detection_events;
```

## 6. Python 클라이언트 설치

```bash
pip install supabase
```

## 7. 테스트

```python
from supabase import create_client

url = "https://YOUR_PROJECT_REF.supabase.co"
key = "YOUR_ANON_KEY"
supabase = create_client(url, key)

# 테스트 쿼리
stores = supabase.table('stores').select('*').execute()
print(stores.data)
```

## 8. 초기 데이터 입력

### Store 데이터 생성

```sql
INSERT INTO stores (store_id, gosca_store_id, store_name, rtsp_host, rtsp_port, total_channels, is_active)
VALUES
  ('oryudong', 'Anding-Oryudongyeok-sca', '앤딩 오류동역점', '218.50.241.157', 8554, 16, true);
```

### Seat 데이터 생성

```python
# src/scripts/import_gosca_seats.py 실행
python -m src.scripts.import_gosca_seats
```

## 9. Supabase 장점 활용

### Real-time 구독 (Redis 대체)

```python
def handle_seat_status_change(payload):
    print(f"Seat status changed: {payload}")

supabase.table('seat_status').on('UPDATE', handle_seat_status_change).subscribe()
```

### Auto-generated API

모든 테이블에 대해 REST API가 자동 생성됩니다:

- `GET /rest/v1/seats?store_id=eq.oryudong`
- `POST /rest/v1/detection_events`
- `PATCH /rest/v1/seat_status?store_id=eq.oryudong&seat_id=eq.A-01`

## 10. 마이그레이션 (PostgreSQL → Supabase)

기존 PostgreSQL에서 Supabase로 마이그레이션:

```bash
# pg_dump로 데이터 백업
pg_dump -h localhost -U postgres cctv_seats > backup.sql

# Supabase로 복원
psql -h db.YOUR_PROJECT_REF.supabase.co -U postgres -d postgres < backup.sql
```

## 비용 관리

### Free Tier 제한
- 500MB database
- 2GB bandwidth/month
- 500MB file storage

### 모니터링
Supabase Dashboard → Settings → Usage에서 사용량 확인

### 최적화 팁
1. 오래된 `detection_events` 정기적으로 삭제
2. 이미지는 Supabase Storage 대신 S3 사용 고려
3. 시간별 통계는 `occupancy_stats`에 집계하여 쿼리 최소화
