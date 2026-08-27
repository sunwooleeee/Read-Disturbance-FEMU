#!/usr/bin/env python3
"""Deterministic check for the current FEMU RD/ECC abstraction."""

PAGE_BITS = 4096 * 8
ECC = 50
EPSILON = 0.00148
ALPHA = 0.000000516375983
K = 2.05
GAMMA = 0.00000000651773564
P = 0.435025976
Q = 1.71


def retry_count(erase_count, read_count):
    ec = max(erase_count, 1)
    rber = EPSILON + ALPHA * ec**K + GAMMA * ec**P * read_count**Q
    rber = min(rber, 1.0)
    effective = rber
    retries = 0
    while PAGE_BITS * effective > ECC and retries < 16:
        effective /= 2.0
        retries += 1
    return rber, retries


first = next(rc for rc in range(1, 100000) if retry_count(0, rc)[1])
print(f"first_retry_rc={first}")
for rc in (0, 100, first - 1, first, 200, 1000):
    rber, retries = retry_count(0, rc)
    print(f"rc={rc:4d} rber={rber:.9f} errors={PAGE_BITS*rber:.3f} retries={retries}")
