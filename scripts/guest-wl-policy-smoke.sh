#!/bin/bash
set -euo pipefail

DEV="${1:-/dev/nvme0n1}"
FILL_PAGES="${2:-256}"
TARGET_PAGE="${3:-30}"
READS="${4:-256}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run with sudo: sudo $0 [device] [fill_pages] [target_page] [reads]" >&2
    exit 1
fi
if [[ ! -b "$DEV" ]]; then
    echo "Block device not found: $DEV" >&2
    exit 1
fi
if (( TARGET_PAGE < 0 || TARGET_PAGE >= FILL_PAGES )); then
    echo "target_page must be inside the filled range" >&2
    exit 1
fi

echo "WARNING: overwriting the first $((FILL_PAGES * 4)) KiB of $DEV."
dd if=/dev/zero of="$DEV" bs=4096 count="$FILL_PAGES" \
   oflag=direct conv=fsync status=none
echo "Reading 4 KiB page $TARGET_PAGE from $DEV for $READS iterations."
start_ns=$(date +%s%N)
for _ in $(seq 1 "$READS"); do
    dd if="$DEV" of=/dev/null bs=4096 skip="$TARGET_PAGE" count=1 \
       iflag=direct status=none
done
end_ns=$(date +%s%N)
elapsed_ns=$((end_ns - start_ns))

printf 'Completed: fill_pages=%d target_page=%d reads=%d elapsed_ns=%d device=%s\n' \
       "$FILL_PAGES" "$TARGET_PAGE" "$READS" "$elapsed_ns" "$DEV"
