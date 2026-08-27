#!/bin/bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-$HOME/FEMU-RD/build-femu}"
OSIMGF="${OSIMGF:-$HOME/images/u20s.qcow2}"
QEMU="$BUILD_DIR/qemu-system-x86_64"
RD_RECLAIM_THRESHOLD="${RD_RECLAIM_THRESHOLD:-0}"

if [[ ! -x "$QEMU" ]]; then
    echo "Missing FEMU binary: $QEMU" >&2
    exit 1
fi
if [[ ! -f "$OSIMGF" ]]; then
    echo "Missing VM image: $OSIMGF" >&2
    exit 1
fi

# Tiny BlackBox SSD geometry for focused RD validation:
# 1 ch x 1 LUN x 64 blocks x 256 pages x 4 KiB = 64 MiB physical.
FEMU_OPTIONS="-device femu,devsz_mb=48,namespaces=1,femu_mode=1"
FEMU_OPTIONS+=",secsz=512,secs_per_pg=8,pgs_per_blk=256,blks_per_pl=64"
FEMU_OPTIONS+=",pls_per_lun=1,luns_per_ch=1,nchs=1"
FEMU_OPTIONS+=",pg_rd_lat=40000,pg_wr_lat=200000,blk_er_lat=2000000"
FEMU_OPTIONS+=",ch_xfer_lat=0,gc_thres_pcent=75,gc_thres_pcent_high=95"
FEMU_OPTIONS+=",rd_enable=1,rd_debug=1"
FEMU_OPTIONS+=",rd_reclaim_threshold=${RD_RECLAIM_THRESHOLD}"

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ACCEL_OPTS=(-accel kvm -cpu host)
    echo "Using KVM acceleration"
else
    ACCEL_OPTS=(-accel tcg,thread=multi -cpu max)
    echo "KVM unavailable; falling back to TCG"
fi
cd "$BUILD_DIR"
exec "$QEMU" \
    -name "FEMU-RD-VALIDATION" \
    "${ACCEL_OPTS[@]}" \
    -smp 2 \
    -m 2G \
    -device virtio-scsi-pci,id=scsi0 \
    -device scsi-hd,drive=hd0 \
    -drive file="$OSIMGF",if=none,aio=threads,cache=none,format=qcow2,id=hd0 \
    $FEMU_OPTIONS \
    -net user,hostfwd=tcp::8080-:22 \
    -net nic,model=virtio \
    -nographic
