#!/bin/bash

# Disk Read/Write Benchmark Script (Safe & Portable)
# Author: CoolManTheCool

TARGET_SIZE_MB=64
BLOCK_SIZES=("4K" "64K" "1M" "16M")
RUNS=3
DEFAULT_OUTPUT="./disk_speed_test.tmp"
TEST_PATH=${1:-$DEFAULT_OUTPUT}

# Check for tmpfs
if mountpoint -q "$(dirname "$TEST_PATH")" && \
   mount | grep -q "$(dirname "$TEST_PATH")" | grep -q "tmpfs"; then
    echo "❌ Error: The selected path ($(dirname "$TEST_PATH")) is on tmpfs (RAM)."
    echo "   Please choose a disk-backed path to ensure valid benchmarking."
    exit 1
fi

echo "Disk Read/Write Speed Benchmark (dd)"
echo "Target File: $TEST_PATH"
echo "Total Size per Test: ${TARGET_SIZE_MB} MB"
echo "------------------------------------------------"

for bs in "${BLOCK_SIZES[@]}"; do
    bs_bytes=$(numfmt --from=iec "$bs" 2>/dev/null)
    if [ -z "$bs_bytes" ]; then
        echo "⚠️ Skipping invalid block size: $bs"
        continue
    fi

    count=$(( (TARGET_SIZE_MB * 1024 * 1024) / bs_bytes ))
    echo "📝 Write Test: bs=$bs count=$count (~${TARGET_SIZE_MB} MB)"
    total_speed=0
    valid_runs=0

    for i in $(seq 1 $RUNS); do
        output=$(dd if=/dev/zero of="$TEST_PATH" bs=$bs count=$count conv=fdatasync 2>&1)
        speed=$(echo "$output" | sed -n 's/.*, \([0-9.]\+\) MB\/s.*/\1/p')
        if [ -n "$speed" ]; then
            echo "  Run $i: $speed MB/s"
            total_speed=$(echo "$total_speed + $speed" | bc)
            valid_runs=$((valid_runs + 1))
        else
            echo "  Run $i: ⚠️ Failed to read write speed"
        fi
    done

    if [ "$valid_runs" -gt 0 ]; then
        avg_speed=$(echo "scale=2; $total_speed / $valid_runs" | bc)
        echo "  → Average Write: $avg_speed MB/s"
    else
        echo "  → All write runs failed."
    fi

    echo "📖 Read Test: bs=$bs count=$count (~${TARGET_SIZE_MB} MB)"
    sync && echo 3 | sudo tee /proc/sys/vm/drop_caches  # Flush file system cache

    total_speed=0
    valid_runs=0

    for i in $(seq 1 $RUNS); do
        output=$(dd if="$TEST_PATH" of=/dev/null bs=$bs count=$count iflag=direct 2>&1)
        speed=$(echo "$output" | sed -n 's/.*, \([0-9.]\+\) MB\/s.*/\1/p')
        if [ -n "$speed" ]; then
            echo "  Run $i: $speed MB/s"
            total_speed=$(echo "$total_speed + $speed" | bc)
            valid_runs=$((valid_runs + 1))
        else
            echo "  Run $i: ⚠️ Failed to read read speed"
        fi
    done

    if [ "$valid_runs" -gt 0 ]; then
        avg_speed=$(echo "scale=2; $total_speed / $valid_runs" | bc)
        echo "  → Average Read: $avg_speed MB/s"
    else
        echo "  → All read runs failed."
    fi

    echo "------------------------------------------------"
done

rm -f "$TEST_PATH"
