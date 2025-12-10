#!/bin/bash
# =============================================================================
# 로컬 테스트 스크립트
# =============================================================================
# RTSP 연결, YOLO 모델, Supabase 연결 등을 빠르게 테스트합니다.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "${BLUE}→ $1${NC}"
}

# Check if .env exists
check_env() {
    print_header "환경 설정 확인"

    if [ -f ".env" ]; then
        print_success ".env 파일 존재"

        # Check required variables
        source .env 2>/dev/null || true

        if [ -n "$STORE_ID" ]; then
            print_success "STORE_ID: $STORE_ID"
        else
            print_warning "STORE_ID 미설정 (기본값: oryudong)"
        fi

        if [ -n "$SUPABASE_URL" ] && [ "$SUPABASE_URL" != "https://your-project-ref.supabase.co" ]; then
            print_success "SUPABASE_URL 설정됨"
        else
            print_error "SUPABASE_URL 미설정"
        fi

        if [ -n "$RTSP_HOST" ] && [ "$RTSP_HOST" != "your_rtsp_host" ]; then
            print_success "RTSP_HOST: $RTSP_HOST"
        else
            print_warning "RTSP_HOST 미설정"
        fi
    else
        print_error ".env 파일 없음"
        print_info ".env.example을 복사하세요: cp .env.example .env"
        return 1
    fi
}

# Activate virtual environment
activate_venv() {
    print_header "가상환경 활성화"

    if [ -d "venv" ]; then
        source venv/bin/activate
        print_success "가상환경 활성화됨: $(which python)"
    else
        print_error "venv 디렉토리 없음"
        print_info "python -m venv venv && pip install -r requirements.txt"
        return 1
    fi
}

# Test 1: Config loading
test_config() {
    print_header "테스트 1: 설정 로딩"

    python -c "
from src.config import settings

print(f'  STORE_ID: {settings.STORE_ID}')
print(f'  DEBUG: {settings.DEBUG}')
print(f'  DRY_RUN: {settings.DRY_RUN}')

# Test store-specific config
store = settings.get_store_config()
print(f'  Store Config: {store}')
print(f'  RTSP Host: {store.rtsp_host}')
print(f'  Active Channels: {store.active_channels}')
"
    if [ $? -eq 0 ]; then
        print_success "설정 로딩 성공"
    else
        print_error "설정 로딩 실패"
        return 1
    fi
}

# Test 2: YOLO model
test_yolo() {
    print_header "테스트 2: YOLO 모델"

    python -c "
from src.core import PersonDetector
import time

print('  모델 로딩 중...')
start = time.time()
detector = PersonDetector()
elapsed = time.time() - start
print(f'  모델 로딩 완료: {elapsed:.2f}초')
print(f'  모델 경로: {detector.model_path}')
"
    if [ $? -eq 0 ]; then
        print_success "YOLO 모델 로딩 성공"
    else
        print_error "YOLO 모델 로딩 실패"
        return 1
    fi
}

# Test 3: Supabase connection
test_supabase() {
    print_header "테스트 3: Supabase 연결"

    python -c "
from src.database.supabase_client import get_supabase_client

db = get_supabase_client()
print(f'  Supabase URL: {db.url}')

# Test query
stores = db.list_stores()
print(f'  등록된 지점: {len(stores)}개')
for store in stores:
    print(f'    - {store[\"store_id\"]}: {store[\"store_name\"]}')

if stores:
    store_id = stores[0]['store_id']
    seats = db.get_seats(store_id)
    print(f'  {store_id} 좌석: {len(seats)}개')
"
    if [ $? -eq 0 ]; then
        print_success "Supabase 연결 성공"
    else
        print_error "Supabase 연결 실패"
        return 1
    fi
}

# Test 4: RTSP connection
test_rtsp() {
    print_header "테스트 4: RTSP 연결"

    local channel="${1:-12}"

    python -c "
import sys
from src.config import settings
from src.utils import RTSPClient

store = settings.get_store_config()
channel = int(sys.argv[1]) if len(sys.argv) > 1 else 12
rtsp_url = store.get_rtsp_url(channel)

# Mask password in output
safe_url = rtsp_url.replace(store.rtsp_password, '***') if store.rtsp_password else rtsp_url
print(f'  채널 {channel}: {safe_url}')

client = RTSPClient(rtsp_url)
print('  연결 시도 중...')

if client.connect(timeout=10):
    print('  연결 성공!')
    frame = client.capture_frame()
    if frame is not None:
        print(f'  프레임 캡처 성공: {frame.shape}')
    client.disconnect()
else:
    print('  연결 실패')
    sys.exit(1)
" "$channel"

    if [ $? -eq 0 ]; then
        print_success "RTSP 연결 성공 (채널 $channel)"
    else
        print_error "RTSP 연결 실패 (채널 $channel)"
        return 1
    fi
}

# Test 5: Full detection pipeline
test_detection() {
    print_header "테스트 5: 감지 파이프라인"

    local channel="${1:-12}"

    python -c "
import sys
import time
from src.config import settings
from src.utils import RTSPClient
from src.core import PersonDetector

channel = int(sys.argv[1]) if len(sys.argv) > 1 else 12
store = settings.get_store_config()
rtsp_url = store.get_rtsp_url(channel)

print(f'  채널 {channel} 테스트 시작')

# Connect RTSP
client = RTSPClient(rtsp_url)
if not client.connect(timeout=10):
    print('  RTSP 연결 실패')
    sys.exit(1)
print('  RTSP 연결됨')

# Load detector
detector = PersonDetector()
print('  YOLO 모델 로딩됨')

# Capture and detect
frame = client.capture_frame()
if frame is None:
    print('  프레임 캡처 실패')
    sys.exit(1)
print(f'  프레임 캡처됨: {frame.shape}')

start = time.time()
detections = detector.detect_persons(frame)
elapsed = (time.time() - start) * 1000

print(f'  감지 시간: {elapsed:.1f}ms')
print(f'  감지된 사람: {len(detections)}명')

for i, det in enumerate(detections[:5]):  # Show first 5
    print(f'    [{i+1}] confidence: {det[\"confidence\"]:.2f}, bbox: {det[\"bbox\"]}')

client.disconnect()
print('  테스트 완료')
" "$channel"

    if [ $? -eq 0 ]; then
        print_success "감지 파이프라인 테스트 성공"
    else
        print_error "감지 파이프라인 테스트 실패"
        return 1
    fi
}

# Show usage
usage() {
    echo "사용법: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  all              모든 테스트 실행 (기본값)"
    echo "  env              환경 설정 확인"
    echo "  config           설정 로딩 테스트"
    echo "  yolo             YOLO 모델 테스트"
    echo "  supabase         Supabase 연결 테스트"
    echo "  rtsp [channel]   RTSP 연결 테스트 (기본: 채널 12)"
    echo "  detect [channel] 감지 파이프라인 테스트"
    echo ""
    echo "Examples:"
    echo "  $0               # 모든 테스트 실행"
    echo "  $0 rtsp 1        # 채널 1 RTSP 테스트"
    echo "  $0 detect 12     # 채널 12 감지 테스트"
    echo ""
    echo "환경 변수:"
    echo "  STORE_ID         테스트할 지점 ID (예: oryudong)"
    echo "  DEBUG=true       디버그 모드"
}

# Main
main() {
    local cmd="${1:-all}"

    case "$cmd" in
        all)
            check_env || exit 1
            activate_venv || exit 1
            test_config || exit 1
            test_yolo || exit 1
            test_supabase || true  # Don't fail if Supabase not configured
            test_rtsp "${2:-12}" || true  # Don't fail if RTSP not available

            print_header "테스트 완료"
            print_success "기본 테스트 통과"
            ;;
        env)
            check_env
            ;;
        config)
            activate_venv && test_config
            ;;
        yolo)
            activate_venv && test_yolo
            ;;
        supabase)
            activate_venv && test_supabase
            ;;
        rtsp)
            activate_venv && test_rtsp "${2:-12}"
            ;;
        detect)
            activate_venv && test_detection "${2:-12}"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "알 수 없는 명령: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
