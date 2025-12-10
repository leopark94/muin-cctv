#!/bin/bash
# CCTV Seat Detection System - 통합 시작 스크립트

set -e

echo "🚀 CCTV Seat Detection System Starting..."
echo "=========================================="

# 환경 변수 체크
if [ ! -f .env ]; then
    echo "❌ .env 파일이 없습니다!"
    echo "   .env.example을 복사해서 .env를 만들어주세요."
    exit 1
fi

# Python 가상환경 체크
if [ ! -d "venv" ]; then
    echo "⚠️  가상환경이 없습니다. 생성 중..."
    python -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

# Supabase 설정 체크
SUPABASE_URL=$(grep SUPABASE_URL .env | cut -d '=' -f2)
if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" = "https://your-project-ref.supabase.co" ]; then
    echo "⚠️  Supabase가 설정되지 않았습니다!"
    echo "   docs/SUPABASE_QUICK_START.md를 참고하세요."
    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 로그 디렉토리 생성
mkdir -p logs

# Store ID 파싱 (환경 변수 또는 인자)
STORE_ID=${1:-$(python -c "import os; from dotenv import load_dotenv; load_dotenv(); gosca=os.getenv('GOSCA_STORE_ID',''); parts=gosca.split('-'); print(parts[1].lower() if len(parts)>1 else 'oryudong')")}

echo ""
echo "📍 Store: $STORE_ID"
echo "=========================================="
echo ""

# PID 파일
PID_FILE="logs/cctv.pid"

# 기존 프로세스 체크
if [ -f "$PID_FILE" ]; then
    echo "⚠️  이미 실행 중인 프로세스가 있습니다!"
    echo "   ./stop_all.sh를 먼저 실행하세요."
    exit 1
fi

# 1. API 서버 시작 (백그라운드)
echo "1️⃣ Starting Seats API Server (Port 8001)..."
python -m src.api.seats_api > logs/api.log 2>&1 &
API_PID=$!
echo $API_PID > logs/api.pid
echo "   ✅ API Server started (PID: $API_PID)"

# API 서버 준비 대기
sleep 3

# 2. Detection Worker 시작 (백그라운드)
echo ""
echo "2️⃣ Starting Detection Worker..."
python -m src.workers.detection_worker --store "$STORE_ID" > logs/worker.log 2>&1 &
WORKER_PID=$!
echo $WORKER_PID > logs/worker.pid
echo "   ✅ Worker started (PID: $WORKER_PID)"

# 메인 PID 저장 (stop_all.sh에서 사용)
cat logs/api.pid logs/worker.pid > "$PID_FILE"

echo ""
echo "=========================================="
echo "✅ All services started!"
echo "=========================================="
echo ""
echo "📊 Monitoring:"
echo "   Dashboard:  http://localhost:8001/static/dashboard.html"
echo "   API Docs:   http://localhost:8001/docs"
echo "   Health:     http://localhost:8001/health"
echo ""
echo "📝 Logs:"
echo "   tail -f logs/api.log     # API 서버 로그"
echo "   tail -f logs/worker.log  # Worker 로그"
echo ""
echo "🛑 Stop:"
echo "   ./stop_all.sh"
echo ""

# 로그 tail (Ctrl+C로 종료해도 백그라운드 프로세스는 계속 실행)
echo "📡 Live logs (Ctrl+C to detach):"
echo "=========================================="
tail -f logs/worker.log
