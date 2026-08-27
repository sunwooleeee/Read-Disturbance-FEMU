# Read-Disturbance-FEMU

FEMU prototype for modeling read-disturbance overhead inside an SSD.

The `main` branch contains the validated block-level V1. This branch adds a STRAW-inspired wordline-aware reclaim path for a controlled comparison with the V1 BLOCK policy.

## Motivation

The 2026 study *Experimental Study on System-Level Performance Impact of Read Disturbance in Modern SSDs* reports that read-disturbance management can noticeably affect SSD performance and discusses more realistic SSD simulation as one useful direction.

V1 adds this path to clean FEMU:

`host read -> block read count -> RBER -> ECC threshold -> read retry -> block/line reclaim`

V2 keeps the same FEMU timing and FTL path, but adds WL-level read counters and selective reclaim. STRAW is used as the reference for the WL-aware stress model. This is not a full STRAW reproduction.

References:
- Experimental Study on System-Level Performance Impact of Read Disturbance in Modern SSDs: https://arxiv.org/abs/2608.14073
- STRAW, ASPLOS 2026: DOI 10.1145/3779212.3790228

## Architecture

![FEMU read-disturbance architecture](figures/architecture-overview.svg)

The block-level path drives the RBER/ECC/read-retry model. The WL-aware path maps physical pages to modeled TLC wordlines, tracks per-WL reads, and calculates ERC for the reclaim decision.

## WL mapping and ERC

The validation geometry has 256 FEMU pages per block. V2 groups three FEMU pages into one modeled TLC wordline:

`wl = physical_page / 3`

![Page-to-WL mapping and disturbance relationship](figures/page-to-wl-mapping.svg)

For victim WL `i`:

`adj = RC[i-1] + RC[i+1]`

`nonadj = block_RC - RC[i] - adj`

`ERC[i] = alpha * adj + nonadj`

The default `alpha` is 8.4. `ERC_MAX` is configurable because the project does not include STRAW's full device-characterization tables.

![WL-level ERC under repeated reads to WL10](figures/erc-progression.svg)

Under the controlled validation workload, repeated reads to modeled WL10 make the ERC of adjacent victim WL9/WL11 grow as `8.4 * RC`, while a non-adjacent WL grows as `RC`. At `RC=256`, the adjacent-victim ERC reaches `2150.4`, crossing the configured `ERC_MAX=2150`.

## Implemented

- Per-block and per-WL read counters.
- FEMU physical-page to modeled-WL mapping.
- STRAW-inspired ERC calculation.
- Policy switch: `BLOCK` or `STRAW-inspired`.
- Selective migration of valid pages on WLs that cross `ERC_MAX`.
- Shared RBER/ECC/read-retry model for both policies.
- Runtime controls for WL size, alpha, ERC threshold, and check interval.

## Controlled A/B mechanism validation

Both policies used the same 1-channel / 1-LUN geometry. One 256-page line was filled, then physical page 30 (modeled WL10) was read 256 times with direct I/O.

BLOCK configuration:
- reclaim threshold: 256 block reads
- migrated pages: 256
- immediate erases: 1

STRAW-inspired configuration:
- 3 pages per modeled WL
- `alpha = 8.4`
- `ERC_MAX = 2150`
- check interval: 8 reads
- adjacent victims: WL9 and WL11
- migrated pages: 6 total
- immediate erases: 0

![BLOCK vs STRAW-inspired reclaim](figures/block-vs-straw-reclaim.svg)

Observed markers:

```text
RD reclaim: line=0 trigger_blk=0 reads=256 pages=256 erases=1 events=1
RD STRAW WL reclaim: blk=0 wl=9 erc=2150.4 pages=3 total_pages=3
RD STRAW WL reclaim: blk=0 wl=11 erc=2150.4 pages=3 total_pages=6
RD STRAW event: blk=0 reads=256 wls=2 pages=6 events=1
```

In this controlled validation workload, immediate page copies dropped from 256 to 6, or 97.7%. This result only demonstrates the difference in reclaim granularity; it is not a reproduction of STRAW's published performance numbers.

The shared ECC model triggered the first read retry at block RC=177 in both runs.

## Limits

- The RBER parameters are not calibrated to a specific modern NAND device.
- The 3-pages-per-WL mapping is a TLC simulator abstraction, not a vendor-specific program order.
- This branch implements a simplified ERC/selective-reclaim path, not STRAW's full RPT/REC/PVT structures.
- Selective WL migration does not immediately erase the source block. Old pages are invalidated and normal FEMU GC reclaims the block later.
- The controlled microbenchmark shows a reduction in immediate internal page migration for this workload. It does not establish a general host-latency or throughput improvement.

## Files

- `figures/architecture-overview.svg`: V1/V2 data path and reclaim-policy overview.
- `figures/page-to-wl-mapping.svg`: TLC page-to-WL mapping used by the validation workload.
- `figures/erc-progression.svg`: ERC progression for adjacent and non-adjacent WLs under repeated reads to WL10.
- `figures/block-vs-straw-reclaim.svg`: controlled BLOCK vs STRAW-inspired result.
- `docs/development-log.md`: implementation and validation history.
- `docs/wl-aware-design.md`: V2 mapping, ERC, and policy design.
- `patches/read-disturbance-femu.patch`: initial V1 source changes.
- `patches/read-reclaim-v1.patch`: V1 GC-backed reclaim addition.
- `patches/wl-aware-straw-v2.patch`: V2 WL-aware source and validation-workload changes.
- `results/wl-policy-comparison.txt`: BLOCK vs STRAW-inspired result summary.
- `results/wl-block-policy-smoke.txt`: BLOCK runtime evidence from the controlled validation workload.
- `results/wl-straw-policy-smoke.txt`: STRAW-inspired runtime evidence from the controlled validation workload.
- `scripts/check-wl-erc.py`: deterministic WL/ERC checker.
- `scripts/guest-wl-policy-smoke.sh`: guest workload used for the controlled A/B comparison.

## Runtime controls

```text
rd_reclaim_policy=0|1        # 0=BLOCK, 1=STRAW-inspired
rd_reclaim_threshold=N       # BLOCK trigger
rd_pages_per_wl=3
rd_straw_erc_max=N
rd_straw_alpha_x1000=8400
rd_straw_check_interval=N
```

V1 is preserved at tag `rd-v1` in the development tree. The public `main` branch remains the validated V1 artifact; this `wl-aware-straw` branch contains V2.
