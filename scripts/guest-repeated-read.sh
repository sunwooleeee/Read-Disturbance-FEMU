#!/bin/bash
set -euo pipefail

DEV="${1:-/dev/nvme0n1}"
READS="${2:-400}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: sudo $0 [device] [reads]" >&2
    exit 1
fi
if [[ ! -b "$DEV" ]]; then
    echo "Block device not found: $DEV" >&2
    exit 1
fi

echo "WARNING: overwriting the first 4 KiB of $DEV for the FEMU smoke test."
dd if=/dev/zero of="$DEV" bs=4096 count=1 oflag=direct conv=fsync status=none
for _ in $(seq 1 "$READS"); do
    dd if="$DEV" of=/dev/null bs=4096 count=1 iflag=direct status=none
done
echo "Completed $READS direct 4 KiB reads from $DEV"
