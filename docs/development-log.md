# FEMU Read-Disturbance Development Log

This is a short implementation log for the Read-Disturbance FEMU project. It records what baseline was used, what was changed, and why, so the implementation can be explained and reproduced later.

## 2026-08-27 — Clean FEMU baseline

- Base repository: `MoatLab/FEMU`
- Base branch: `master`
- Base commit: `e2d5413ffe432d0b3ed6fef025c611c630e0cded`
- Development branch: `rd-model`
- The previous Hot/Cold FTL experiment was kept separate so its FTL/GC changes do not affect the read-disturbance experiments.
- The clean FEMU tree was built successfully with `ninja -C build-femu`; `qemu-system-x86_64` was generated.

## Modeling approach

The first goal is not to emulate transistor-level NAND physics. The project models the system-level path by which read disturbance can create SSD-internal overhead:

`host read -> physical read count / disturbance stress -> RBER estimate -> ECC capability -> read retry -> reclaim/internal I/O -> host latency`

The implementation is being added incrementally so each mechanism can be validated separately.

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
- This first version tracks stress at block granularity. A later WL-aware model can refine the victim/aggressor relationship.

## Reference model examined

FAST'24 CVSS FEMU (`ZiyangJiao/FAST24_CVSS_FEMU`) was inspected as a reference rather than used as the project base. Its code already contains reliability-related state such as ECC correction strength, RBER parameters, block read counters, and read-retry accounting. The current project reimplements only the relevant mechanisms on clean upstream FEMU so the contribution boundary stays clear.

Observed reference behavior includes:
- ECC correction-strength parameterization.
- RBER-related parameters (`epsilon`, `alpha`, `k`, `gamma`, `p`, `q`).
- Host-read counting at the NAND block level.
- Read retry modeled as additional NAND read latency.

## Step 2 — RBER, ECC, and read-retry abstraction

Added a configurable reliability path on top of the block read counter. The model is disabled by default and can be enabled with:

`-device femu,...,rd_enable=1,rd_debug=1`

Modified files:
- `hw/femu/nvme.h`: added `rd_enable` and `rd_debug` BlackBox parameters.
- `hw/femu/femu.c`: exposed both parameters as QEMU device properties.
- `hw/femu/bbssd/ftl.h`: added RD model parameters and retry statistics.
- `hw/femu/bbssd/ftl.c`: added RBER calculation, ECC threshold check, and retry latency.

Initial RBER form follows the FAST'24 CVSS FEMU reliability artifact:

`RBER = epsilon + alpha * EC^k + gamma * EC^p * RC^q`

Here `RC` is the actual FEMU block `read_cnt`; the reference artifact contains paths where RC is fixed or simplified, so this project explicitly reconnects the formula to the measured block read count for read-disturbance experiments.

Current prototype parameters:
- ECC correction strength: 50 bits per 4 KiB page.
- epsilon = 0.00148
- alpha = 5.16375983e-7, k = 2.05
- gamma = 6.51773564e-9, p = 0.435025976, q = 1.71

ECC is an abstraction, not an actual BCH/LDPC implementation. The expected number of raw bit errors is `page_bits * RBER`. If that exceeds the ECC strength, effective RBER is halved per retry until the page is considered correctable. Each retry adds one NAND page-read latency, so read latency becomes `pg_rd_lat * (1 + retry_count)`.

For a block with `erase_cnt == 0`, EC is floored to 1. This is an explicit modeling assumption so that a freshly programmed block still has a non-zero read-disturbance term; it should later be calibrated or replaced by a more detailed wear state.

## Validation

- Incremental FEMU build completed with `BUILD_RC=0`.
- `qemu-system-x86_64 -device femu,help` exposes `rd_enable` and `rd_debug`.
- The existing VM image at `~/images/u20s.qcow2` was reused.
- The smoke runner prefers KVM and falls back to TCG only when KVM is unavailable.
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

The result validates the current block-level abstraction only. It does not yet model aggressor/victim wordlines, neighboring-WL stress, read reclaim, or a calibrated modern 3D NAND device model.

## Next steps

1. Add read-reclaim/internal-copy behavior and internal-I/O statistics.
2. Measure host average/tail latency and throughput under read-intensive workloads.
3. Refine block-level stress toward WL-aware aggressor/victim modeling.
4. Compare read-disturbance management policies after the baseline model is stable.
