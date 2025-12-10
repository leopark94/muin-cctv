#!/bin/bash
# CCTV Seat Detection System - 상태 확인 스크립트

echo "📊 CCTV Seat Detection System Status"
echo "=========================================="

PID_FILE="logs/cctv.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "❌ System is NOT running"
    exit 0
fi

PIDS=$(cat "$PID_FILE")
all_running=true

for PID in $PIDS; do
    if ps -p $PID > /dev/null 2>&1; then
        COMMAND=$(ps -p $PID -o command=)
        echo "✅ Process $PID: Running"
        echo "   Command: $COMMAND"
    else
        echo "❌ Process $PID: Stopped"
        all_running=false
    fi
done

echo ""
echo "=========================================="

# API 서버 체크
if curl -s http://localhost:8001/health > /dev/null 2>&1; then
    echo "✅ API Server: Healthy (Port 8001)"
else
    echo "❌ API Server: Not responding"
    all_running=false
fi

echo ""
echo "📝 Recent logs:"
echo "=========================================="
echo "--- API Log (last 5 lines) ---"
tail -n 5 logs/api.log 2>/dev/null || echo "No logs yet"
echo ""
echo "--- Worker Log (last 5 lines) ---"
tail -n 5 logs/worker.log 2>/dev/null || echo "No logs yet"

echo ""
echo "=========================================="
if [ "$all_running" = true ]; then
    echo "✅ System Status: HEALTHY"
else
    echo "⚠️  System Status: DEGRADED"
fi
