#!/usr/bin/env bash
# run_filebench_blktrace.sh
set -euo pipefail

############################
# 0. 경로 / 설정
############################
LOG_FILE="./tmp/filebench.txt"     # filebench 로그가 찍히는 파일
LOG_DIR="./logs"
NVME_DEV="/dev/nvme1n1"            # 실험하는 NVMe 디바이스로 수정
DMESG_OUT="${LOG_DIR}/dmesg_delaytrim.txt"

mkdir -p "./tmp" "$LOG_DIR"

BLKTRACE_PREFIX="${LOG_DIR}/blktrace"     # raw blktrace 파일 prefix
BLKPARSE_OUT="${LOG_DIR}/blktrace.parsed" # 시간순 정렬된 최종 로그
BLKTRACE_PID=""

############################
# 1. 보조 함수 (dmesg 캡처)
############################
DMESG_PID=""

start_dmesg_capture() {
  echo "[$(date '+%F %T')] Resetting kernel ring buffer and starting dmesg capture -> ${DMESG_OUT}"
  # 기존 dmesg 비우기 (이후 메시지만 저장)
  sudo dmesg -C || true
  # 출력 파일 초기화
  : > "${DMESG_OUT}"
  # 새로 발생하는 dmesg를 팔로우하여 파일로 저장
  sudo dmesg --follow --human --color=never > "${DMESG_OUT}" 2>&1 &
  DMESG_PID=$!
}

stop_dmesg_capture() {
  if [[ -n "${DMESG_PID}" ]] && kill -0 "${DMESG_PID}" 2>/dev/null; then
    echo "[$(date '+%F %T')] Stopping dmesg capture (pid=${DMESG_PID})"
    kill "${DMESG_PID}" 2>/dev/null || true
    wait "${DMESG_PID}" 2>/dev/null || true
  fi
  DMESG_PID=""
}

############################
# 1-1. 보조 함수 (blktrace 캡처)
############################
start_blktrace() {
  if [[ -n "${BLKTRACE_PID}" ]] && kill -0 "${BLKTRACE_PID}" 2>/dev/null; then
    # 이미 돌고 있으면 재시작 안 함
    return
  fi

  echo "[$(date '+%F %T')] ▶ starting blktrace on ${NVME_DEV}"
  # raw .blktrace.* 파일들 생성
  sudo blktrace -d "${NVME_DEV}" -o "${BLKTRACE_PREFIX}" > /dev/null 2>&1 &
  BLKTRACE_PID=$!
}

stop_blktrace() {
  if [[ -n "${BLKTRACE_PID}" ]] && kill -0 "${BLKTRACE_PID}" 2>/dev/null; then
    echo "[$(date '+%F %T')] ▶ stopping blktrace (pid=${BLKTRACE_PID})"
    sudo kill "${BLKTRACE_PID}" 2>/dev/null || true
    wait "${BLKTRACE_PID}" 2>/dev/null || true
  fi
  BLKTRACE_PID=""

  # raw trace → 시간순 텍스트 로그로 파싱
  if ls "${BLKTRACE_PREFIX}".blktrace.* > /dev/null 2>&1; then
    echo "[$(date '+%F %T')] ▶ parsing blktrace to ${BLKPARSE_OUT}"
    sudo blkparse -i "${BLKTRACE_PREFIX}".blktrace.* -o "${BLKPARSE_OUT}"
    echo "[$(date '+%F %T')] ▶ blkparse done"
  else
    echo "[!] no blktrace files found for prefix ${BLKTRACE_PREFIX}"
  fi
}

############################
# 1-2. 종료 시 정리
############################
cleanup() {
  # 스크립트 종료 시 백그라운드 정리
  stop_dmesg_capture
  stop_blktrace
}
trap cleanup INT TERM EXIT

############################
# 2. 모니터 루프
############################
monitor_and_control_filebench() {
  echo "[$(date '+%F %T')] Monitoring ${LOG_FILE} for 'Running' / 'Shutting down'..."
  local nvme_read_done=false
  local capture_started=false

  while true; do
    # 1) Running 감지 시: dmesg 캡처 시작 + blktrace 시작 + 1회 NVMe read
    if ! $capture_started && grep -q "Running" "$LOG_FILE"; then
      echo "[+] 'Running' detected"
      start_dmesg_capture
      start_blktrace
      capture_started=true

      if ! $nvme_read_done; then
        echo "[$(date '+%F %T')] Executing one-time NVMe read"
        sudo nvme read "$NVME_DEV" -c 77 -s 77 -z 4096 > /dev/null 2>&1 || echo "[!] nvme read (before) failed"
        nvme_read_done=true
      fi
    fi

    # 2) Shutting down 감지 시: dmesg 캡처 중지 + blktrace 정지/파싱 후 종료
    if $capture_started && grep -q "Shutting down" "$LOG_FILE"; then
      echo "[+] 'Shutting down' detected"
      stop_dmesg_capture
      stop_blktrace
      echo "[$(date '+%F %T')] dmesg captured to ${DMESG_OUT}"
      echo "[$(date '+%F %T')] blktrace parsed to ${BLKPARSE_OUT}"
      break
    fi

    sleep 1
  done
}

############################
# 3. 시작
############################
echo "[+] Waiting for log file: ${LOG_FILE}"
while [ ! -f "$LOG_FILE" ]; do sleep 1; done
echo "[+] Log file found"

monitor_and_control_filebench

