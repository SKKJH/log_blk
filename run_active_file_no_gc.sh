#!/usr/bin/env bash
# ----------------------------------------------------------
# 1) active_pre_cond.sh 실행이 끝나면
# 2) work_fb.sh 와 check_running.sh 를 **동시에** 실행
# ----------------------------------------------------------

set -euo pipefail          # 스크립트 오류 즉시 중단

echo "[`date '+%F %T'`] ▶ removing files in /home/kjh/tmp and /home/kjh/logs"
rm -f ./tmp/*
rm -f ./logs/*

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

echo "[`date '+%F %T'`] ▶ running active_pre_cond.sh"
./active_pre_cond_nogc.sh | tee "$LOG_DIR/active_pre_cond.log"

echo "[`date '+%F %T'`] ▶ launching work_fb.sh & check_running.sh"
./5m_fs.sh       2>&1 | tee "$LOG_DIR/work_fb.log"       &
pid_work=$!

./check_running.sh 2>&1 | tee "$LOG_DIR/check_running.log" &
pid_check=$!

# 두 프로세스가 모두 끝날 때까지 대기
wait $pid_work $pid_check

echo "[`date '+%F %T'`] ▶ ALL DONE"

