#!/bin/bash
set -euo pipefail

MNT_DIR="/media/nvme"
FILEBENCH_SCRIPT="/home/kjh/test_sh/5m_fileserver.f"
FB_RESULT_DIR="./tmp"
FB_RESULT_FILE="$FB_RESULT_DIR/filebench.txt"
NVME_DEV="/dev/nvme1n1"

echo "[+] Disabling address space randomization"
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space > /dev/null

df -h "$MNT_DIR"

mkdir -p "$FB_RESULT_DIR"

echo "[+] Starting Filebench workload: $FILEBENCH_SCRIPT"
filebench -f "$FILEBENCH_SCRIPT" | tee "$FB_RESULT_FILE"

# Filebench 끝난 후 10초 대기
WAIT_SEC=3
echo "[+] Waiting $WAIT_SEC seconds before NVMe read..."
sleep "$WAIT_SEC"

echo "[+] Reading NVMe info (after Filebench)"
sudo nvme read "$NVME_DEV" -c 77 -s 77 -z 4096 > /dev/null 2>&1 || echo "[!] nvme read (after) failed"
echo "[+] All steps completed successfully"
