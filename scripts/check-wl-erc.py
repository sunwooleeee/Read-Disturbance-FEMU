#!/usr/bin/env python3
"""Check the V2 TLC page-to-WL mapping and STRAW-inspired ERC validation setup."""

PAGES_PER_WL = 3
PAGES_PER_BLOCK = 256
TARGET_PAGE = 30
ALPHA = 8.4
ERC_MAX = 2150.0
CHECK_INTERVAL = 1


def wl_of(page):
    return page // PAGES_PER_WL


def erc(victim_wl, reads_by_wl, total_reads):
    self_reads = reads_by_wl.get(victim_wl, 0)
    adj = reads_by_wl.get(victim_wl - 1, 0) + reads_by_wl.get(victim_wl + 1, 0)
    nonadj = max(total_reads - self_reads - adj, 0)
    return ALPHA * adj + nonadj


target_wl = wl_of(TARGET_PAGE)
print(f"pages_per_block={PAGES_PER_BLOCK} pages_per_wl={PAGES_PER_WL} modeled_wls={(PAGES_PER_BLOCK + PAGES_PER_WL - 1)//PAGES_PER_WL}")
print(f"target_page={TARGET_PAGE} target_wl={target_wl} adjacent_victims={target_wl-1},{target_wl+1}")
first_trigger = None
for reads in range(1, 1000):
    counts = {target_wl: reads}
    victim_erc = erc(target_wl - 1, counts, reads)
    if victim_erc >= ERC_MAX:
        first_trigger = reads
        break

print(f"first_trigger_reads={first_trigger}")
for reads in (1, 100, 176, 177, 255, 256):
    counts = {target_wl: reads}
    left = erc(target_wl - 1, counts, reads)
    far = erc(target_wl - 3, counts, reads)
    print(f"reads={reads:3d} adjacent_erc={left:7.1f} far_erc={far:7.1f}")

assert first_trigger == 256
assert wl_of(30) == 10
assert wl_of(29) == 9
assert wl_of(32) == 10
print("CHECK=PASS")
