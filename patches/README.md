# Patch layout

The project was developed incrementally from a clean MoatLab/FEMU baseline.

- `read-disturbance-femu.patch`: initial block read-count, RBER, ECC-threshold, and read-retry prototype.
- `read-reclaim-v1.patch`: incremental V1 read-reclaim changes applied on top of the initial prototype. It adds the reclaim threshold, GC-backed migration, reclaim statistics, and runtime control.

The local development history preserves the same milestones as separate commits. The development log documents the rationale and runtime validation for each step.
