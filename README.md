# Read-Disturbance-FEMU

A focused prototype for modeling the system-level performance impact of NAND read disturbance in FEMU.

The project starts from a clean `MoatLab/FEMU` baseline and adds reliability mechanisms incrementally rather than using a full reliability artifact as the base.

## Research question

How can read disturbance be represented in FEMU so that SSD-internal reliability management overhead is visible at the host level?

The current abstraction follows this path:

`host read -> physical read count -> RBER estimate -> ECC threshold -> read retry -> NAND read latency`

Read reclaim and finer-grained WL-aware stress modeling are planned extensions.

## Baseline

- Upstream: `MoatLab/FEMU`
- Baseline commit: `e2d5413ffe432d0b3ed6fef025c611c630e0cded`
- Development branch used locally: `rd-model`
- Existing Hot/Cold FTL experiments are kept separate from this project.

## Implemented

1. **Physical NAND block read counting**
   - Added `read_cnt` to `struct nand_block`.
   - Incremented after LPN-to-PPA translation on host reads.
   - Reset on block erase.

2. **RBER / ECC / read-retry abstraction**
   - Uses `RBER = epsilon + alpha * EC^k + gamma * EC^p * RC^q`.
   - `RC` is FEMU's measured block `read_cnt`.
   - ECC correction strength is modeled as 50 raw-bit errors per 4 KiB page.
   - Retry is triggered when `page_bits * RBER` exceeds the correction strength.
   - Each retry adds one NAND page-read latency.

3. **Runtime controls**
   - `rd_enable=0/1`: disable or enable the reliability model.
   - `rd_debug=0/1`: emit sampled read-retry diagnostics.

The model is disabled by default so baseline FEMU behavior remains available for A/B comparison.

## Validation status

- FEMU incremental build: **PASS**
- `qemu-system-x86_64 -device femu,help`: **PASS** (`rd_enable`, `rd_debug` exposed)
- Guest boot with modified FEMU: **PASS**
- Guest Linux detects FEMU NVMe device: **PASS**
- Repeated-read trigger of RD retry: **PASS**
- First retry boundary under the current prototype parameters: **RC = 177**

The final smoke test ran with KVM acceleration. A 4 KiB page was mapped in the FEMU guest, then repeatedly read. The first retry was logged at `reads=177`, matching the standalone model check (`50.005` expected raw-bit errors versus a 50-bit ECC threshold). Sampled logs continued to show increasing retry events through `reads=304`.

## Important limitation

This is a system-level reliability abstraction, not a transistor-level NAND model. The current `RC` is block-level read stress. Real read disturbance is caused by repeated read operations stressing non-selected cells/wordlines, so a future version should model aggressor/victim WL relationships explicitly.

## Reference implementation

FAST'24 CVSS FEMU (`ZiyangJiao/FAST24_CVSS_FEMU`) was examined as a reference for reliability parameters and read-retry modeling. This repository does not use that full artifact as its base; relevant mechanisms are reimplemented on clean upstream FEMU.

See `docs/development-log.md` for the implementation rationale and `patches/read-disturbance-femu.patch` for the focused source changes.

## Reproducing the current smoke test

1. Apply `patches/read-disturbance-femu.patch` to the baseline FEMU commit.
2. Build FEMU and start the small RD-enabled guest with `scripts/run-rd-smoke.sh`.
3. Inside the guest, run `sudo scripts/guest-repeated-read.sh /dev/nvme0n1 400` after copying the script into the guest.
4. Check the host FEMU log for `RD retry:` messages.

The standalone equation check is available as:

```bash
python3 scripts/check-rd-model.py
```

Expected first retry boundary with the current prototype parameters: `RC=177`.

See `results/runtime-smoke-test.txt` for the observed runtime log and `results/status.txt` for the current validation summary.
