# P3 Runtime Flow Analysis

## Input

- M/N/K: `16/16/16`
- BPE: `4`
- Freq: `200.0 MHz`
- Bandwidth: `6.4 GB/s`
- Array: `8x8`

## Summary

| Flow | Ops | Off-chip Bytes | OI | Peak GOPS | BW Roof GOPS | Attainable GOPS | Bottleneck |
|---|---:|---:|---:|---:|---:|---:|---|
| baseline_gemm | 8192 | 4096 | 2.000000 | 25.600000 | 12.800000 | 12.800000 | bandwidth-bound |
| fused_gemm_relu | 8448 | 4096 | 2.062500 | 25.600000 | 13.200000 | 13.200000 | bandwidth-bound |
| explicit_ewise | 8448 | 5120 | 1.650000 | 25.600000 | 10.560000 | 10.560000 | bandwidth-bound |
| dep_token_explicit_ewise | 8448 | 5120 | 1.650000 | 25.600000 | 10.560000 | 10.560000 | bandwidth-bound |

## Interpretation

- `fused_gemm_relu` and `baseline_gemm` have the same off-chip bytes in the current RTL, but fused path performs more useful work on the same bytes.
- `explicit_ewise` costs one extra output writeback, so compared with fused it adds `1024` bytes of off-chip traffic.
- Relative to baseline, fused path raises OI from `2.000000` to `2.062500` without increasing off-chip traffic.
- `dep_token_explicit_ewise` changes control semantics, but not traffic; its value is scheduling correctness, not byte reduction.

## Design Notes

- `baseline_gemm`: DMA_LOAD -> GEMM(writeback). One output writeback to off-chip.
- `fused_gemm_relu`: DMA_LOAD -> GEMM(relu_fuse) -> implicit EWISE -> writeback. Saves an extra off-chip output round-trip.
- `explicit_ewise`: DMA_LOAD -> GEMM(writeback) -> EWISE -> DMA_STORE. Two output writebacks to off-chip.
- `dep_token_explicit_ewise`: Same traffic as explicit_ewise; ordering uses dep tokens instead of BARRIER. Improves control semantics, not off-chip bytes.

## P3 Takeaway

- For post-op heavy workloads, fusion is valuable primarily because it avoids extra off-chip output traffic.
- Explicit opcode chaining is architecturally cleaner and more general, but without output-residency policy it costs more bandwidth.
- The next P3 step should therefore focus on layout/residency/buffering, not more opcode surface area.
