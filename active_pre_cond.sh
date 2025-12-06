#!/bin/bash
set -euo pipefail

############################
# 0. 기본 설정
############################
JOB_FIO="/home/kjh/test_sh/pre_write.fio"
NVME_DEV="/dev/nvme1n1"
MNT_DIR="/media/nvme"
KERNEL_F2FS_DIR="/home/kjh/linux-hwe-5.4-5.4.0/fs/f2fs"
############################
# 1. pre-write 단계
############################
echo "[+] Running pre-write workload: $JOB_FIO"
sudo fio "$JOB_FIO" || { echo "fio pre-write failed"; exit 1; }

ORIGINAL_DIR=$(pwd)
echo "[+] Switching to $KERNEL_F2FS_DIR"
cd "$KERNEL_F2FS_DIR" || { echo "Failed to enter f2fs directory"; exit 1; }
sudo modprobe f2fs || true
sudo rmmod f2fs || true
sudo insmod f2fs.ko || { echo "insmod failed"; cd "$ORIGINAL_DIR"; exit 1; }

echo "[+] Formatting $NVME_DEV with f2fs"
sudo mkfs.f2fs -E discard "$NVME_DEV" || { echo "mkfs.f2fs failed"; exit 1; }

echo "[+] Creating mount point $MNT_DIR (if absent)"
sudo mkdir -p "$MNT_DIR"

echo "[+] Mounting $NVME_DEV to $MNT_DIR"
sudo mount -t f2fs -o mode=lfs "$NVME_DEV" "$MNT_DIR" || { echo "mount failed"; exit 1; }

echo "[+] Disabling address space randomization"
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space > /dev/null

echo "[+] Returned to original directory: $ORIGINAL_DIR"
cd "$ORIGINAL_DIR" || { echo "Failed to enter origin dir"; exit 1; }

df -h "$MNT_DIR"

echo "[+] Reading NVMe info (before Filebench)"
sudo nvme read "$NVME_DEV" -c 77 -s 77 -z 4096 > /dev/null 2>&1 || echo "[!] nvme read (before) failed"


