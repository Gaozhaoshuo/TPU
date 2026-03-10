#!/usr/bin/env python3
"""
Simple roofline/performance model for TPU-like GEMM accelerator.

Inputs:
- M, N, K
- frequency (MHz)
- memory bandwidth (GB/s)
- tile sizes (tm, tn, tk)
Optional:
- bytes per element
- array size (for peak compute)
- PE MACs per cycle
- C read/write behavior

Outputs:
- Arithmetic intensity (OI)
- Roofline point and bound type (compute-bound or bandwidth-bound)
- Peak compute, bandwidth roof, predicted attainable performance
- A simple cycle estimate (compute cycles vs memory cycles)
"""

import argparse
import math

class ModelConfig(object):
    def __init__(
        self,
        m,
        n,
        k,
        freq_mhz,
        bw_gbps,
        tm,
        tn,
        tk,
        bpe,
        array_size,
        mac_per_pe_per_cycle,
        c_read,
        c_write,
    ):
        self.m = m
        self.n = n
        self.k = k
        self.freq_mhz = freq_mhz
        self.bw_gbps = bw_gbps
        self.tm = tm
        self.tn = tn
        self.tk = tk
        self.bpe = bpe
        self.array_size = array_size
        self.mac_per_pe_per_cycle = mac_per_pe_per_cycle
        self.c_read = c_read
        self.c_write = c_write


def ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


def gemm_ops(m: int, n: int, k: int) -> float:
    # GEMM: 2 * M * N * K operations (FMA counted as 2 ops)
    return 2.0 * m * n * k


def bytes_naive(cfg: ModelConfig) -> float:
    # A + B + optional C read + optional C write
    bytes_a = cfg.m * cfg.k * cfg.bpe
    bytes_b = cfg.k * cfg.n * cfg.bpe
    bytes_c_read = cfg.m * cfg.n * cfg.bpe if cfg.c_read else 0
    bytes_c_write = cfg.m * cfg.n * cfg.bpe if cfg.c_write else 0
    return float(bytes_a + bytes_b + bytes_c_read + bytes_c_write)


def bytes_tiled_lower_bound(cfg: ModelConfig) -> float:
    # Coarse lower bound for tiled blocking traffic between memory and on-chip store.
    mt = ceil_div(cfg.m, cfg.tm)
    nt = ceil_div(cfg.n, cfg.tn)
    kt = ceil_div(cfg.k, cfg.tk)

    # A tile loaded per (mt, kt) and reused across nt tiles if kept on-chip.
    # B tile loaded per (kt, nt) and reused across mt tiles if kept on-chip.
    bytes_a = mt * kt * cfg.tm * cfg.tk * cfg.bpe
    bytes_b = kt * nt * cfg.tk * cfg.tn * cfg.bpe

    # C: read+write at output tile granularity.
    bytes_c_read = mt * nt * cfg.tm * cfg.tn * cfg.bpe if cfg.c_read else 0
    bytes_c_write = mt * nt * cfg.tm * cfg.tn * cfg.bpe if cfg.c_write else 0

    # Guard against over-idealization: cannot be less than full tensor raw size lower bound.
    floor_a = cfg.m * cfg.k * cfg.bpe
    floor_b = cfg.k * cfg.n * cfg.bpe
    floor_c_read = cfg.m * cfg.n * cfg.bpe if cfg.c_read else 0
    floor_c_write = cfg.m * cfg.n * cfg.bpe if cfg.c_write else 0

    bytes_a = max(bytes_a, floor_a)
    bytes_b = max(bytes_b, floor_b)
    bytes_c_read = max(bytes_c_read, floor_c_read)
    bytes_c_write = max(bytes_c_write, floor_c_write)

    return float(bytes_a + bytes_b + bytes_c_read + bytes_c_write)


def analyze(cfg):
    ops = gemm_ops(cfg.m, cfg.n, cfg.k)

    # Use tiled lower-bound traffic model; also compute naive for reference in print.
    traffic_bytes = bytes_tiled_lower_bound(cfg)

    oi = ops / traffic_bytes if traffic_bytes > 0 else math.inf

    freq_hz = cfg.freq_mhz * 1e6
    pe_count = cfg.array_size * cfg.array_size

    # If each PE does 1 MAC/cycle -> 2 ops/cycle
    peak_compute_ops_s = pe_count * cfg.mac_per_pe_per_cycle * 2.0 * freq_hz
    peak_compute_gops = peak_compute_ops_s / 1e9

    bw_bytes_s = cfg.bw_gbps * 1e9
    bw_roof_ops_s = oi * bw_bytes_s
    bw_roof_gops = bw_roof_ops_s / 1e9

    attainable_gops = min(peak_compute_gops, bw_roof_gops)
    bound = "compute-bound" if peak_compute_gops <= bw_roof_gops else "bandwidth-bound"

    # Simple cycle estimates
    compute_cycles = ops / (pe_count * cfg.mac_per_pe_per_cycle * 2.0) if pe_count > 0 else math.inf
    memory_cycles = traffic_bytes / (bw_bytes_s / freq_hz) if bw_bytes_s > 0 else math.inf
    est_cycles = max(compute_cycles, memory_cycles)

    return {
        "ops": ops,
        "bytes_total": traffic_bytes,
        "oi": oi,
        "peak_compute_gops": peak_compute_gops,
        "bw_roof_gops": bw_roof_gops,
        "attainable_gops": attainable_gops,
        "bound": bound,
        "compute_cycles": compute_cycles,
        "memory_cycles": memory_cycles,
        "est_cycles": est_cycles,
    }


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="TPU roofline/performance model for GEMM")
    p.add_argument("--M", type=int, required=True)
    p.add_argument("--N", type=int, required=True)
    p.add_argument("--K", type=int, required=True)
    p.add_argument("--freq-mhz", type=float, required=True, help="Clock frequency in MHz")
    p.add_argument("--bw-gbps", type=float, required=True, help="Sustained memory bandwidth in GB/s")

    p.add_argument("--tm", type=int, required=True, help="Tile M")
    p.add_argument("--tn", type=int, required=True, help="Tile N")
    p.add_argument("--tk", type=int, required=True, help="Tile K")

    p.add_argument("--bpe", type=int, default=4, help="Bytes per element (FP32=4, FP16=2, INT8=1)")
    p.add_argument("--array-size", type=int, default=8, help="Systolic array dimension (NxN)")
    p.add_argument("--mac-per-pe-per-cycle", type=float, default=1.0, help="MAC throughput per PE per cycle")

    p.add_argument("--no-c-read", action="store_true", help="Do not count C read traffic")
    p.add_argument("--no-c-write", action="store_true", help="Do not count C write traffic")

    return p


def validate(args):
    ints = [args.M, args.N, args.K, args.tm, args.tn, args.tk, args.bpe, args.array_size]
    if any(v <= 0 for v in ints):
        raise ValueError("M/N/K/tm/tn/tk/bpe/array-size must be positive")
    if args.freq_mhz <= 0 or args.bw_gbps <= 0:
        raise ValueError("freq-mhz and bw-gbps must be positive")
    if args.mac_per_pe_per_cycle <= 0:
        raise ValueError("mac-per-pe-per-cycle must be positive")


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    validate(args)

    cfg = ModelConfig(
        m=args.M,
        n=args.N,
        k=args.K,
        freq_mhz=args.freq_mhz,
        bw_gbps=args.bw_gbps,
        tm=args.tm,
        tn=args.tn,
        tk=args.tk,
        bpe=args.bpe,
        array_size=args.array_size,
        mac_per_pe_per_cycle=args.mac_per_pe_per_cycle,
        c_read=not args.no_c_read,
        c_write=not args.no_c_write,
    )

    res = analyze(cfg)
    naive_bytes = bytes_naive(cfg)
    ridge_oi = res["peak_compute_gops"] / cfg.bw_gbps

    print("=== Input ===")
    print(f"M,N,K                : {cfg.m}, {cfg.n}, {cfg.k}")
    print(f"Tile (tm,tn,tk)      : ({cfg.tm}, {cfg.tn}, {cfg.tk})")
    print(f"Freq                 : {cfg.freq_mhz:.3f} MHz")
    print(f"Bandwidth            : {cfg.bw_gbps:.3f} GB/s")
    print(f"Element bytes (bpe)  : {cfg.bpe}")
    print(f"Array size           : {cfg.array_size}x{cfg.array_size}")
    print(f"MAC/PE/cycle         : {cfg.mac_per_pe_per_cycle}")
    print(f"Count C read/write   : {cfg.c_read}/{cfg.c_write}")

    print("\n=== Roofline Point ===")
    print(f"Ops                  : {res['ops']:,.0f}")
    print(f"Bytes (naive)        : {naive_bytes:,.0f}")
    print(f"Bytes (tiled model)  : {res['bytes_total']:,.0f}")
    print(f"OI (ops/byte)        : {res['oi']:.6f}")

    print("\n=== Performance Bounds ===")
    print(f"Peak compute         : {res['peak_compute_gops']:.6f} GOPS")
    print(f"Bandwidth roof       : {res['bw_roof_gops']:.6f} GOPS")
    print(f"Attainable perf      : {res['attainable_gops']:.6f} GOPS")
    print(f"Ridge point OI*      : {ridge_oi:.6f} ops/byte")
    print(f"Bottleneck           : {res['bound']}")

    print("\n=== Cycle Estimate ===")
    print(f"Compute cycles       : {res['compute_cycles']:,.2f}")
    print(f"Memory cycles        : {res['memory_cycles']:,.2f}")
    print(f"Estimated cycles     : {res['est_cycles']:,.2f}")


if __name__ == "__main__":
    main()
