#!/bin/bash
# CCTV Seat Detection System - 통합 중지 스크립트

echo "🛑 Stopping CCTV Seat Detection System..."
echo "=========================================="

PID_FILE="logs/cctv.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "⚠️  실행 중인 프로세스가 없습니다."
    exit 0
fi

# PID 읽기
PIDS=$(cat "$PID_FILE")

# 각 PID에 SIGTERM 전송
for PID in $PIDS; do
    if ps -p $PID > /dev/null 2>&1; then
        echo "   Stopping process $PID..."
        kill -TERM $PID
    fi
done

# Graceful shutdown 대기 (최대 10초)
echo "   Waiting for graceful shutdown..."
for i in {1..10}; do
    all_stopped=true
    for PID in $PIDS; do
        if ps -p $PID > /dev/null 2>&1; then
            all_stopped=false
            break
        fi
    done

    if [ "$all_stopped" = true ]; then
        break
    fi

    sleep 1
done

# 강제 종료 (아직 살아있는 프로세스)
for PID in $PIDS; do
    if ps -p $PID > /dev/null 2>&1; then
        echo "   ⚠️  Force killing process $PID..."
        kill -9 $PID
    fi
done

# PID 파일 삭제
rm -f "$PID_FILE" logs/api.pid logs/worker.pid

echo ""
echo "✅ All services stopped!"
echo "=========================================="
