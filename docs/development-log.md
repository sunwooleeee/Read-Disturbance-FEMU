# FEMU Read-Disturbance Development Log

This log records the FEMU baseline, implementation changes, and validation decisions used in the project.

## Clean FEMU baseline

- Base repository: `MoatLab/FEMU`
- Base branch: `master`
- Base commit: `e2d5413ffe432d0b3ed6fef025c611c630e0cded`
- Development branch: `rd-model`
- The previous Hot/Cold FTL experiment was kept separate so its FTL/GC changes do not affect the read-disturbance experiments.
- The clean FEMU tree was built successfully with `ninja -C build-femu`; `qemu-system-x86_64` was generated.

## Modeling approach

The first goal is not to emulate transistor-level NAND physics. The project models the system-level path by which read disturbance can create SSD-internal overhead:

`host read -> physical read count / disturbance stress -> RBER estimate -> ECC capability -> read retry -> reclaim/internal I/O -> host latency`

The mechanisms were added in stages so each one could be validated independently.

## Step 1 — NAND block read-count tracking

Commit: `38bf4ff84 feat: add NAND block read-count tracking`

Modified files:
- `hw/femu/bbssd/ftl.h`
- `hw/femu/bbssd/ftl.c`

Changes:
1. Added `uint64_t read_cnt` to `struct nand_block`.
2. Initialized `read_cnt = 0` when a NAND block is created.
3. Reset `read_cnt = 0` when the block is erased/freed.
4. In `ssd_read()`, after LPN-to-PPA translation and PPA validation, increment the mapped physical block's `read_cnt` for each host read.

Reasoning:
- Read disturbance is accumulated by repeated physical NAND reads, so a physical-location counter is the minimum state required before adding an RBER/retry model.
- The counter is reset at erase because erase removes the accumulated disturbance state in this abstraction.
- V1 tracks stress at block granularity. V2 adds per-WL counters and an explicit aggressor/victim abstraction.

## Reference model examined

FAST'24 CVSS FEMU (`ZiyangJiao/FAST24_CVSS_FEMU`) was inspected as a reference rather than used as the project base. Its code already contains reliability-related state such as ECC correction strength, RBER parameters, block read counters, and read-retry accounting. The current project reimplements only the relevant mechanisms on clean upstream FEMU so the contribution boundary stays clear.

Observed reference behavior includes:
- ECC correction-strength parameterization.
- RBER-related parameters (`epsilon`, `alpha`, `k`, `gamma`, `p`, `q`).
- Host-read counting at the NAND block level.
- Read retry modeled as additional NAND read latency.

## Validation milestone after Step 1

- Clean upstream baseline verified.
- Step-1 code compiled successfully.
- The existing FEMU guest image was later found at `~/images/u20s.qcow2`; no restoration was needed.
- Runtime validation continued in Steps 2 and 3 below.

## Step 2 — RBER, ECC, and read-retry abstraction

Added a configurable reliability path on top of the block read counter.
The model is disabled by default and can be enabled with:

`-device femu,...,rd_enable=1,rd_debug=1`

Modified files:
- `hw/femu/nvme.h`: added `rd_enable` and `rd_debug` BlackBox parameters.
- `hw/femu/femu.c`: exposed both parameters as QEMU device properties.
- `hw/femu/bbssd/ftl.h`: added RD model parameters and retry statistics.
- `hw/femu/bbssd/ftl.c`: added RBER calculation, ECC threshold check, and retry latency.

Initial RBER form follows the FAST'24 CVSS FEMU reliability artifact:
`RBER = epsilon + alpha * EC^k + gamma * EC^p * RC^q`.
Here `RC` is the actual FEMU block `read_cnt`; the reference artifact contains paths where RC is fixed or simplified, so this project explicitly reconnects the formula to the measured block read count for read-disturbance experiments.

Model parameters currently match the reference artifact values:
- ECC correction strength: 50 bits per 4 KiB page.
- epsilon = 0.00148
- alpha = 5.16375983e-7, k = 2.05
- gamma = 6.51773564e-9, p = 0.435025976, q = 1.71

ECC is an abstraction, not an actual BCH/LDPC implementation. The expected number of raw bit errors is `page_bits * RBER`. If that exceeds the ECC strength, one read-retry is added and effective RBER is halved repeatedly until it is correctable. Each retry adds one NAND page-read latency, so read latency becomes `pg_rd_lat * (1 + retry_count)`.

For a block with `erase_cnt == 0`, EC is floored to 1. This is an explicit modeling assumption so that a freshly programmed block still has a non-zero read-disturbance term. The current model is not calibrated to a specific NAND device.

Validation:
- Incremental FEMU build completed with `BUILD_RC=0`.
- `qemu-system-x86_64 -device femu,help` exposes `rd_enable` and `rd_debug`.
- KVM-accelerated guest boot completed successfully and guest Linux detected `/dev/nvme0n1`.
- A deterministic model checker predicts the first retry at `RC=177`: `RC=176` gives 49.991 expected raw errors; `RC=177` gives 50.005.

## End-to-end runtime smoke test — PASS

The KVM smoke test wrote one 4 KiB page to `/dev/nvme0n1`, then issued 400 direct 4 KiB reads to the same LBA so guest page cache would not hide the device reads.

Observed FEMU log:

```text
RD retry: blk=0 pg=1 reads=177 erase=0 rber=0.00152603 retries=1 total=1
RD retry: blk=0 pg=1 reads=178 erase=0 rber=0.00152647 retries=1 total=2
...
RD retry: blk=0 pg=1 reads=304 erase=0 rber=0.00159528 retries=1 total=128
```

The runtime first-retry point exactly matches the independent checker at RC=177. This validates the current chain:

`host read -> physical block read_cnt -> RBER -> ECC threshold -> read retry -> extra NAND read latency`

## Step 3 — GC-backed read reclaim (V1)

Read reclaim reuses FEMU's conventional GC data-movement primitives instead of duplicating migration logic.

New control:
- `rd_reclaim_threshold`: host-read count that triggers reclaim; `0` disables reclaim.

Implementation path:
`read_cnt threshold -> reliability-selected line -> clean_one_block() -> gc_read_page()/gc_write_page() -> block erase -> mark_line_free()`.

The trigger differs from normal GC: GC selects a victim because free space is low, while RD reclaim selects the line containing the block whose read stress crossed the configured threshold.

FEMU BlackBox allocation is line-based. Therefore V1 only reclaims a **closed full line**. If the threshold is reached while the line is still the active write line or is only partially written, reclaim is deferred rather than forcing an unsafe partial-line erase. This keeps FEMU's existing line/free-list invariants intact.

Added reclaim statistics:
- `rd_reclaim_events`
- `rd_reclaim_pages`
- `rd_reclaim_erases`
- `rd_reclaim_deferred`

Build validation: PASS after the Step-3 source changes.

## Step 3 validation — GC-backed read reclaim PASS

The reclaim smoke test filled one complete 256-page FEMU line, then repeatedly read the same 4 KiB LBA with `rd_reclaim_threshold=256`.

Observed sequence:
- `read_cnt=177`: first ECC/read-retry event, matching the existing RBER checker.
- `read_cnt=256`: the reliability threshold triggered read reclaim for line 0.
- The reclaim path reused `clean_one_block()`, `gc_read_page()`, and `gc_write_page()` to migrate all 256 valid pages.
- `mark_block_free()` then reset block state/read stress and the normal NAND erase timing path was executed.

Observed log:

```text
RD retry: blk=0 pg=0 reads=177 erase=0 rber=0.00152603 retries=1 total=1
RD reclaim: line=0 trigger_blk=0 reads=256 pages=256 erases=1 events=1
```

This validates the V1 management chain:

`repeated host read -> read stress -> RBER/ECC retry -> reliability-triggered reclaim -> GC-backed page migration -> erase`

Important limitation: V1 reclaims only a closed, fully valid FEMU line. Threshold hits on the active or partially written line are deferred to preserve FEMU's line-management invariants.

## V2 — WL-aware policy comparison

V2 adds a simple TLC page-to-WL mapping, per-WL read counters, and a STRAW-inspired effective read count (ERC). The implementation compares the existing BLOCK reclaim path against selective migration of WLs whose ERC crosses the configured threshold.

The controlled runtime test filled one 256-page line and issued 256 direct reads to physical page 30 (modeled WL10). Under BLOCK, the threshold at `read_cnt=256` migrated all 256 valid pages and erased one block. Under the STRAW-inspired policy (`3 pages/WL`, `alpha=8.4`, `ERC_MAX=2150`, check interval 8), adjacent victim WL9 and WL11 each reached ERC 2150.4 and were selectively migrated. Three pages were copied from each WL, for six immediate page copies total, with no immediate block erase.

This smoke test validates the management-granularity difference: 256 immediate page copies for BLOCK versus 6 for the WL-aware policy (97.7% fewer immediate copies in this controlled case). It does not establish a general host-latency or throughput improvement.

The V2 design, assumptions, and architecture are documented in `docs/wl-aware-design.md`.
