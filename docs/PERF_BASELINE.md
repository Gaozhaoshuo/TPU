# TPU Performance Baseline Report

Generated at: `2026-03-05 00:28:44`

## Summary

| Case | M/N/K | OI (ops/byte) | Peak (GOPS) | BW Roof (GOPS) | Attainable (GOPS) | Bottleneck |
|---|---:|---:|---:|---:|---:|---|
| small_fp32 | 16/16/16 | 2.000000 | 25.600000 | 12.800000 | 12.800000 | bandwidth-bound |
| medium_fp32 | 64/64/64 | 8.000000 | 25.600000 | 51.200000 | 25.600000 | compute-bound |
| large_fp32 | 256/256/256 | 32.000000 | 25.600000 | 204.800000 | 25.600000 | compute-bound |

## Details

### small_fp32

- Description: Small GEMM, likely bandwidth-sensitive
- M/N/K: `16/16/16`
- Tile: `(16, 16, 16)`
- Frequency: `200.0 MHz`
- Bandwidth: `6.4 GB/s`
- BPE: `4`
- Array: `8x8`
- Ops: `8192`
- Bytes naive/tiled: `4096` / `4096`
- OI: `2.000000`
- Ridge OI*: `4.000000`
- Peak Compute: `25.600000 GOPS`
- BW Roof: `12.800000 GOPS`
- Attainable: `12.800000 GOPS`
- Bottleneck: `bandwidth-bound`
- Cycles (compute/memory/est): `64.00` / `128.00` / `128.00`

### medium_fp32

- Description: Medium GEMM around ridge transition
- M/N/K: `64/64/64`
- Tile: `(32, 32, 16)`
- Frequency: `200.0 MHz`
- Bandwidth: `6.4 GB/s`
- BPE: `4`
- Array: `8x8`
- Ops: `524288`
- Bytes naive/tiled: `65536` / `65536`
- OI: `8.000000`
- Ridge OI*: `4.000000`
- Peak Compute: `25.600000 GOPS`
- BW Roof: `51.200000 GOPS`
- Attainable: `25.600000 GOPS`
- Bottleneck: `compute-bound`
- Cycles (compute/memory/est): `4096.00` / `2048.00` / `4096.00`

### large_fp32

- Description: Large GEMM, typically compute-bound
- M/N/K: `256/256/256`
- Tile: `(32, 32, 16)`
- Frequency: `200.0 MHz`
- Bandwidth: `6.4 GB/s`
- BPE: `4`
- Array: `8x8`
- Ops: `33554432`
- Bytes naive/tiled: `1048576` / `1048576`
- OI: `32.000000`
- Ridge OI*: `4.000000`
- Peak Compute: `25.600000 GOPS`
- BW Roof: `204.800000 GOPS`
- Attainable: `25.600000 GOPS`
- Bottleneck: `compute-bound`
- Cycles (compute/memory/est): `262144.00` / `32768.00` / `262144.00`

## Notes

- 该模型是 roofline + 粗粒度周期估算，用于设计期 tradeoff 判断。
- 若要贴近实测，请把 `bw-gbps` 改成链路实测可持续带宽，并加入 DMA/调度开销。
