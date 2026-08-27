# Patch layout

The project was developed incrementally from a clean MoatLab/FEMU baseline.

- `read-disturbance-femu.patch`: initial block read-count, RBER, ECC-threshold, and read-retry prototype.
- `read-reclaim-v1.patch`: incremental V1 read-reclaim changes applied on top of the initial prototype. It adds the reclaim threshold, GC-backed migration, reclaim statistics, and runtime control.
- `wl-aware-straw-v2.patch`: incremental V2 changes applied on top of V1. It adds the TLC page-to-WL abstraction, per-WL read counters, STRAW-inspired ERC calculation, policy selection, selective WL migration, and the WL-aware validation scripts.

The local development history preserves the same milestones as separate commits. `docs/development-log.md` records the implementation path and runtime validation, while `docs/wl-aware-design.md` documents the V2 mapping and policy assumptions.
