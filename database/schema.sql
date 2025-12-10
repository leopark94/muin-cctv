-- CCTV Seat Detection System - Multi-Store Database Schema
-- PostgreSQL 14+

-- Extension for UUID generation (optional)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- 1. Stores (지점 정보)
-- ============================================================================
CREATE TABLE stores (
    store_id VARCHAR(50) PRIMARY KEY,           -- 'oryudong', 'gangnam', etc.
    gosca_store_id VARCHAR(100) NOT NULL,       -- 'Anding-Oryudongyeok-sca'
    store_name VARCHAR(100) NOT NULL,           -- '앤딩스터디카페 오류동역점'
    rtsp_host VARCHAR(100),                     -- RTSP 서버 주소
    rtsp_port INT DEFAULT 8554,
    total_channels INT DEFAULT 16,
    is_active BOOLEAN DEFAULT TRUE,
    metadata JSONB,                             -- 추가 정보 (주소, 연락처 등)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE stores IS '스터디카페 지점 정보';

-- 샘플 데이터
INSERT INTO stores (store_id, gosca_store_id, store_name, rtsp_host, total_channels) VALUES
    ('oryudong', 'Anding-Oryudongyeok-sca', '앤딩스터디카페 오류동역점', '218.50.241.157', 16),
    ('gangnam', 'Anding-Gangnam-sca', '앤딩스터디카페 강남점', '192.168.1.100', 12),
    ('hongdae', 'Anding-Hongdae-sca', '앤딩스터디카페 홍대점', '192.168.2.100', 8)
ON CONFLICT (store_id) DO NOTHING;

-- ============================================================================
-- 2. Seats (좌석 마스터 테이블)
-- ============================================================================
CREATE TABLE seats (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,
    seat_id VARCHAR(20) NOT NULL,               -- GoSca cell_id (e.g., '1-0-0')
    chairtbl_id VARCHAR(50),                    -- GoSca chair table ID

    -- 좌석 위치
    grid_row INT,
    grid_col INT,

    -- CCTV 매핑
    channel_id INT,                              -- RTSP 채널 (1-16)
    roi_polygon JSONB NOT NULL,                  -- [[x1,y1], [x2,y2], ...]

    -- 좌석 속성
    seat_type VARCHAR(20) DEFAULT 'daily',       -- 'fixed', 'daily', 'charging'
    seat_label VARCHAR(100),                     -- 좌석 이름

    -- 상태
    is_active BOOLEAN DEFAULT TRUE,

    -- 메타데이터
    walls JSONB,                                 -- {top: bool, bottom: bool, left: bool, right: bool}
    metadata JSONB,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(store_id, seat_id)                    -- 지점별로 좌석 ID 고유
);

COMMENT ON TABLE seats IS '좌석 마스터 정보 (GoSca + CCTV ROI 매핑)';
COMMENT ON COLUMN seats.roi_polygon IS 'CCTV 화면에서의 좌석 영역 폴리곤 좌표';

-- 인덱스
CREATE INDEX idx_seats_store ON seats(store_id);
CREATE INDEX idx_seats_channel ON seats(store_id, channel_id);
CREATE INDEX idx_seats_active ON seats(store_id, is_active);

-- ============================================================================
-- 3. Seat Status (현재 상태 - 실시간 업데이트)
-- ============================================================================
CREATE TABLE seat_status (
    store_id VARCHAR(50) NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,
    seat_id VARCHAR(20) NOT NULL,

    -- 현재 상태
    status VARCHAR(20) NOT NULL DEFAULT 'empty', -- 'empty', 'occupied', 'abandoned'

    -- 감지 정보
    person_detected BOOLEAN DEFAULT FALSE,       -- 사람 감지 여부
    object_detected BOOLEAN DEFAULT FALSE,       -- 물건 감지 여부 (짐)
    detection_confidence FLOAT,                  -- 감지 신뢰도 (0-1)

    -- 시간 추적
    last_person_seen TIMESTAMP,                  -- 마지막 사람 목격 시간
    last_empty_time TIMESTAMP,                   -- 마지막 비움 시간
    vacant_duration_seconds INT DEFAULT 0,       -- 부재 시간 (초)

    -- GoSca 데이터 (최신)
    gosca_occupied BOOLEAN,                      -- GoSca API 점유 상태
    gosca_user_name VARCHAR(100),                -- 사용자 이름
    gosca_synced_at TIMESTAMP,                   -- GoSca 마지막 동기화 시간

    updated_at TIMESTAMP DEFAULT NOW(),

    PRIMARY KEY (store_id, seat_id),
    FOREIGN KEY (store_id, seat_id) REFERENCES seats(store_id, seat_id) ON DELETE CASCADE
);

COMMENT ON TABLE seat_status IS '좌석 실시간 상태 (CCTV 감지 + GoSca 동기화)';
COMMENT ON COLUMN seat_status.status IS 'empty: 빈자리, occupied: 사용중, abandoned: 짐만 있음';

-- 인덱스
CREATE INDEX idx_status_store ON seat_status(store_id);
CREATE INDEX idx_status_status ON seat_status(store_id, status);
CREATE INDEX idx_status_vacant ON seat_status(store_id, vacant_duration_seconds DESC);

-- ============================================================================
-- 4. Detection Events (감지 이벤트 로그)
-- ============================================================================
CREATE TABLE detection_events (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,
    seat_id VARCHAR(20) NOT NULL,
    channel_id INT,

    -- 이벤트 타입
    event_type VARCHAR(30) NOT NULL,             -- 'person_enter', 'person_leave', 'abandoned_detected', 'status_change'

    -- 상태 변화
    previous_status VARCHAR(20),
    new_status VARCHAR(20),

    -- 감지 정보
    person_detected BOOLEAN,
    object_detected BOOLEAN,
    confidence FLOAT,

    -- 바운딩 박스 (사람 위치)
    bbox_x1 INT,
    bbox_y1 INT,
    bbox_x2 INT,
    bbox_y2 INT,

    -- 스냅샷
    snapshot_path VARCHAR(255),                  -- 이미지 파일 경로

    -- 메타데이터
    metadata JSONB,                              -- 추가 정보 (FPS, 처리 시간 등)

    created_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE detection_events IS '좌석 감지 이벤트 로그 (모든 변화 기록)';

-- 인덱스
CREATE INDEX idx_events_store_time ON detection_events(store_id, created_at DESC);
CREATE INDEX idx_events_seat ON detection_events(store_id, seat_id, created_at DESC);
CREATE INDEX idx_events_type ON detection_events(store_id, event_type, created_at DESC);
CREATE INDEX idx_events_channel ON detection_events(store_id, channel_id, created_at DESC);

-- ============================================================================
-- 5. Occupancy Stats (점유율 통계 - 시간대별 집계)
-- ============================================================================
CREATE TABLE occupancy_stats (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) NOT NULL REFERENCES stores(store_id) ON DELETE CASCADE,
    seat_id VARCHAR(20),                         -- NULL이면 전체 지점 통계

    -- 시간 슬롯
    hour_slot TIMESTAMP NOT NULL,                -- 시간대 (매 시간 정각, e.g., 2025-01-10 14:00:00)

    -- 집계 데이터 (분 단위)
    occupied_minutes INT DEFAULT 0,              -- 점유 분
    vacant_minutes INT DEFAULT 0,                -- 비어있던 분
    abandoned_minutes INT DEFAULT 0,             -- 짐만 있던 분

    -- 출입 통계
    total_entries INT DEFAULT 0,                 -- 입장 횟수
    total_exits INT DEFAULT 0,                   -- 퇴장 횟수

    -- 체류 시간
    avg_stay_minutes INT,                        -- 평균 체류 시간
    max_stay_minutes INT,                        -- 최대 체류 시간

    created_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(store_id, seat_id, hour_slot)         -- 중복 방지
);

COMMENT ON TABLE occupancy_stats IS '시간대별 좌석 점유율 통계';

-- 인덱스
CREATE INDEX idx_stats_store_hour ON occupancy_stats(store_id, hour_slot DESC);
CREATE INDEX idx_stats_seat ON occupancy_stats(store_id, seat_id, hour_slot DESC);

-- ============================================================================
-- 6. System Logs (시스템 로그)
-- ============================================================================
CREATE TABLE system_logs (
    id SERIAL PRIMARY KEY,
    store_id VARCHAR(50) REFERENCES stores(store_id) ON DELETE CASCADE,
    log_level VARCHAR(20) NOT NULL,              -- 'INFO', 'WARNING', 'ERROR', 'CRITICAL'
    component VARCHAR(50),                       -- 'worker', 'api', 'detector'
    message TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_logs_store_time ON system_logs(store_id, created_at DESC);
CREATE INDEX idx_logs_level ON system_logs(log_level, created_at DESC);

-- ============================================================================
-- Triggers (자동 업데이트)
-- ============================================================================

-- updated_at 자동 업데이트 함수
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Stores 테이블 트리거
CREATE TRIGGER update_stores_updated_at
    BEFORE UPDATE ON stores
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Seats 테이블 트리거
CREATE TRIGGER update_seats_updated_at
    BEFORE UPDATE ON seats
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Views (편의용 뷰)
-- ============================================================================

-- 실시간 전체 좌석 현황
CREATE OR REPLACE VIEW v_realtime_seats AS
SELECT
    s.store_id,
    st.store_name,
    s.seat_id,
    s.seat_label,
    s.seat_type,
    s.channel_id,
    ss.status,
    ss.person_detected,
    ss.vacant_duration_seconds,
    ss.gosca_occupied,
    ss.gosca_user_name,
    ss.updated_at
FROM seats s
JOIN stores st ON s.store_id = st.store_id
LEFT JOIN seat_status ss ON s.store_id = ss.store_id AND s.seat_id = ss.seat_id
WHERE s.is_active = TRUE AND st.is_active = TRUE;

-- 지점별 점유율 요약
CREATE OR REPLACE VIEW v_store_occupancy_summary AS
SELECT
    s.store_id,
    st.store_name,
    COUNT(*) as total_seats,
    SUM(CASE WHEN ss.status = 'occupied' THEN 1 ELSE 0 END) as occupied_seats,
    SUM(CASE WHEN ss.status = 'empty' THEN 1 ELSE 0 END) as empty_seats,
    SUM(CASE WHEN ss.status = 'abandoned' THEN 1 ELSE 0 END) as abandoned_seats,
    ROUND(100.0 * SUM(CASE WHEN ss.status = 'occupied' THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 1) as occupancy_rate
FROM seats s
JOIN stores st ON s.store_id = st.store_id
LEFT JOIN seat_status ss ON s.store_id = ss.store_id AND s.seat_id = ss.seat_id
WHERE s.is_active = TRUE AND st.is_active = TRUE
GROUP BY s.store_id, st.store_name;

-- ============================================================================
-- Sample Queries (사용 예시)
-- ============================================================================

/*
-- 특정 지점의 현재 좌석 현황
SELECT * FROM v_realtime_seats WHERE store_id = 'oryudong';

-- 전체 지점 점유율
SELECT * FROM v_store_occupancy_summary ORDER BY occupancy_rate DESC;

-- 오늘 특정 좌석의 이벤트 히스토리
SELECT * FROM detection_events
WHERE store_id = 'oryudong'
  AND seat_id = '1-0-0'
  AND created_at >= CURRENT_DATE
ORDER BY created_at DESC;

-- 시간대별 점유율 트렌드 (최근 24시간)
SELECT
    hour_slot,
    SUM(occupied_minutes) as total_occupied,
    SUM(vacant_minutes) as total_vacant,
    ROUND(100.0 * SUM(occupied_minutes) / NULLIF(SUM(occupied_minutes + vacant_minutes), 0), 1) as occupancy_rate
FROM occupancy_stats
WHERE store_id = 'oryudong'
  AND hour_slot >= NOW() - INTERVAL '24 hours'
GROUP BY hour_slot
ORDER BY hour_slot;

-- 짐 방치 의심 좌석 (10분 이상 사람 없음)
SELECT
    store_id,
    seat_id,
    seat_label,
    vacant_duration_seconds / 60 as vacant_minutes,
    last_person_seen
FROM seat_status
WHERE status = 'abandoned'
  AND vacant_duration_seconds >= 600
ORDER BY vacant_duration_seconds DESC;
*/
