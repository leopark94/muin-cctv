# Supabase 빠른 시작 가이드

## 📋 체크리스트

### 1. Supabase 프로젝트 생성 (5분)
- [ ] https://supabase.com 접속 및 회원가입
- [ ] "New Project" 클릭
- [ ] 프로젝트 이름: `muin-cctv-seats`
- [ ] Database Password 설정 (저장해두기!)
- [ ] Region: `Northeast Asia (Seoul)` 선택
- [ ] Free Plan 선택

### 2. 스키마 적용 (2분)
- [ ] Supabase Dashboard → SQL Editor 열기
- [ ] `database/schema.sql` 파일 내용 복사
- [ ] SQL Editor에 붙여넣고 "Run" 클릭
- [ ] 성공 메시지 확인

### 3. 환경 변수 설정 (1분)
- [ ] Dashboard → Settings → API 페이지 열기
- [ ] `.env` 파일에 다음 값 추가:
  ```bash
  SUPABASE_URL=https://xxxxx.supabase.co
  SUPABASE_KEY=eyJxxx...  # anon public key
  SUPABASE_SERVICE_KEY=eyJxxx...  # service_role key
  ```

### 4. RLS 설정 (1분)
개발 초기에는 RLS 비활성화:
```sql
ALTER TABLE stores DISABLE ROW LEVEL SECURITY;
ALTER TABLE seats DISABLE ROW LEVEL SECURITY;
ALTER TABLE seat_status DISABLE ROW LEVEL SECURITY;
ALTER TABLE detection_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE occupancy_stats DISABLE ROW LEVEL SECURITY;
ALTER TABLE system_logs DISABLE ROW LEVEL SECURITY;
```

### 5. Real-time 활성화 (1분)
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE seat_status;
ALTER PUBLICATION supabase_realtime ADD TABLE detection_events;
```

### 6. 초기 데이터 임포트 (2분)
```bash
# Supabase 패키지 설치
pip install supabase

# GoSca 좌석 데이터 임포트
python -m src.scripts.import_gosca_seats
```

### 7. 연결 테스트 (1분)
```bash
python -m src.database.supabase_client
```

성공 시 다음과 같이 출력:
```
Found 1 stores:
  - oryudong: 앤딩 Oryudongyeok점

Found 55 seats in oryudong
Found 55 seat statuses
Occupancy: 0/55
```

## 🚀 완료!

이제 다음 단계로 진행:
1. API 서버 시작: `python -m src.api.roi_config_api`
2. 웹 UI 접속: http://localhost:8000
3. CCTV ROI 설정
4. 실시간 감지 시작

## 💡 유용한 명령어

### Supabase 대시보드 확인
```bash
# Table Editor: 데이터 직접 확인/수정
# SQL Editor: SQL 쿼리 실행
# Logs: API 호출 로그 확인
```

### Python에서 데이터 조회
```python
from src.database.supabase_client import get_supabase_client

client = get_supabase_client()

# 지점 목록
stores = client.list_stores()

# 좌석 상태
statuses = client.get_all_seat_statuses('oryudong')

# 최근 이벤트
events = client.get_recent_events('oryudong', limit=10)
```

## 🔍 문제 해결

### "Invalid API key" 오류
→ `.env`의 `SUPABASE_KEY` 또는 `SUPABASE_SERVICE_KEY` 확인

### "relation does not exist" 오류
→ `database/schema.sql` 실행 확인

### "permission denied" 오류
→ RLS 비활성화 또는 정책 추가

### 연결 느림
→ Region을 Seoul로 설정했는지 확인

## 📊 비용

**Free Tier 제한**:
- 500MB database
- 2GB bandwidth/month
- 50,000 monthly active users
- Unlimited API requests

**현재 예상 사용량**:
- DB 크기: ~50MB (좌석 55개 × 3개 지점 × 1년 데이터)
- 월간 대역폭: ~500MB (실시간 업데이트)
- → **Free Tier로 충분!** 🎉
