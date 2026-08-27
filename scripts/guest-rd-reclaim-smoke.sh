#!/bin/bash
set -euo pipefail

DEV="${1:-/dev/nvme0n1}"
FILL_PAGES="${2:-256}"
READS="${3:-400}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: sudo $0 [device] [fill_pages] [reads]" >&2
    exit 1
fi
if [[ ! -b "$DEV" ]]; then
    echo "Block device not found: $DEV" >&2
    exit 1
fi

echo "WARNING: overwriting the first $((FILL_PAGES * 4)) KiB of $DEV."
# Fill one FEMU line in the 1-channel/1-LUN smoke geometry so it becomes a
# closed full line that can safely reuse the existing GC migration path.
dd if=/dev/zero of="$DEV" bs=4096 count="$FILL_PAGES" oflag=direct conv=fsync status=none

# Re-read the first LBA directly so host page cache does not hide device reads.
for _ in $(seq 1 "$READS"); do
    dd if="$DEV" of=/dev/null bs=4096 count=1 iflag=direct status=none
done

echo "Completed: fill_pages=$FILL_PAGES repeated_reads=$READS device=$DEV"
