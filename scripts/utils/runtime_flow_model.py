#!/usr/bin/env python3
"""
Runtime-level traffic model for current TPU command flows.

This script focuses on end-to-end command sequences that already exist in RTL:
- baseline_gemm: DMA_LOAD -> GEMM(writeback)
- fused_gemm_relu: DMA_LOAD -> GEMM(relu_fuse, implicit EWISE, writeback)
- explicit_ewise: DMA_LOAD -> GEMM(writeback) -> EWISE -> DMA_STORE
- dep_token_explicit_ewise: same data movement as explicit_ewise, but ordered by dep tokens instead of BARRIER

The goal is not cycle-accurate modeling. It is a design-stage traffic model that makes
tradeoffs visible:
- how many off-chip bytes move
- what arithmetic intensity each flow achieves
- which flows save bandwidth by avoiding an extra off-chip round-trip
"""

import argparse
from typing import List


def ceil_div(a: int, b: int) -> int:
    return (a + b - 1) // b


class FlowConfig:
    def __init__(self, m, n, k, bpe, freq_mhz, bw_gbps, array_size, mac_per_pe_per_cycle, tm, tn, tk):
        self.m = m
        self.n = n
        self.k = k
        self.bpe = bpe
        self.freq_mhz = freq_mhz
        self.bw_gbps = bw_gbps
        self.array_size = array_size
        self.mac_per_pe_per_cycle = mac_per_pe_per_cycle
        self.tm = tm
        self.tn = tn
        self.tk = tk


class FlowResult:
    def __init__(self, name, ops, offchip_bytes, arithmetic_intensity, peak_compute_gops, bw_roof_gops, attainable_gops, bottleneck, notes):
        self.name = name
        self.ops = ops
        self.offchip_bytes = offchip_bytes
        self.arithmetic_intensity = arithmetic_intensity
        self.peak_compute_gops = peak_compute_gops
        self.bw_roof_gops = bw_roof_gops
        self.attainable_gops = attainable_gops
        self.bottleneck = bottleneck
        self.notes = notes


def gemm_ops(m: int, n: int, k: int) -> float:
    return 2.0 * m * n * k


def ewise_relu_ops(m: int, n: int) -> float:
    # Treat RELU as 1 op/element for high-level comparison.
    return 1.0 * m * n


def tensor_bytes(m: int, n: int, bpe: int) -> int:
    return m * n * bpe


def peak_compute_gops(cfg: FlowConfig) -> float:
    freq_hz = cfg.freq_mhz * 1e6
    pe_count = cfg.array_size * cfg.array_size
    return pe_count * cfg.mac_per_pe_per_cycle * 2.0 * freq_hz / 1e9


def roofline(cfg: FlowConfig, ops: float, offchip_bytes: float):
    oi = ops / offchip_bytes if offchip_bytes > 0 else float("inf")
    peak = peak_compute_gops(cfg)
    bw_roof = oi * cfg.bw_gbps
    attainable = min(peak, bw_roof)
    bottleneck = "compute-bound" if peak <= bw_roof else "bandwidth-bound"
    return oi, peak, bw_roof, attainable, bottleneck


def baseline_gemm(cfg: FlowConfig) -> FlowResult:
    # Current baseline path:
    # off-chip in: A + B + C
    # off-chip out: D
    ops = gemm_ops(cfg.m, cfg.n, cfg.k)
    bytes_in = tensor_bytes(cfg.m, cfg.k, cfg.bpe) + tensor_bytes(cfg.k, cfg.n, cfg.bpe) + tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    bytes_out = tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    total = bytes_in + bytes_out
    oi, peak, bw_roof, attainable, bottleneck = roofline(cfg, ops, total)
    return FlowResult(
        name="baseline_gemm",
        ops=ops,
        offchip_bytes=total,
        arithmetic_intensity=oi,
        peak_compute_gops=peak,
        bw_roof_gops=bw_roof,
        attainable_gops=attainable,
        bottleneck=bottleneck,
        notes="DMA_LOAD -> GEMM(writeback). One output writeback to off-chip.",
    )


def fused_gemm_relu(cfg: FlowConfig) -> FlowResult:
    # Fused EWISE happens on-chip after GEMM, so off-chip traffic is the same as baseline,
    # while useful ops increase slightly.
    ops = gemm_ops(cfg.m, cfg.n, cfg.k) + ewise_relu_ops(cfg.m, cfg.n)
    bytes_in = tensor_bytes(cfg.m, cfg.k, cfg.bpe) + tensor_bytes(cfg.k, cfg.n, cfg.bpe) + tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    bytes_out = tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    total = bytes_in + bytes_out
    oi, peak, bw_roof, attainable, bottleneck = roofline(cfg, ops, total)
    return FlowResult(
        name="fused_gemm_relu",
        ops=ops,
        offchip_bytes=total,
        arithmetic_intensity=oi,
        peak_compute_gops=peak,
        bw_roof_gops=bw_roof,
        attainable_gops=attainable,
        bottleneck=bottleneck,
        notes="DMA_LOAD -> GEMM(relu_fuse) -> implicit EWISE -> writeback. Saves an extra off-chip output round-trip.",
    )


def explicit_ewise(cfg: FlowConfig) -> FlowResult:
    # Current explicit path writes baseline GEMM output once, then writes post-op output again.
    # It does not reload from off-chip because EWISE reads SRAM-D on-chip.
    ops = gemm_ops(cfg.m, cfg.n, cfg.k) + ewise_relu_ops(cfg.m, cfg.n)
    bytes_in = tensor_bytes(cfg.m, cfg.k, cfg.bpe) + tensor_bytes(cfg.k, cfg.n, cfg.bpe) + tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    bytes_out = 2 * tensor_bytes(cfg.m, cfg.n, cfg.bpe)
    total = bytes_in + bytes_out
    oi, peak, bw_roof, attainable, bottleneck = roofline(cfg, ops, total)
    return FlowResult(
        name="explicit_ewise",
        ops=ops,
        offchip_bytes=total,
        arithmetic_intensity=oi,
        peak_compute_gops=peak,
        bw_roof_gops=bw_roof,
        attainable_gops=attainable,
        bottleneck=bottleneck,
        notes="DMA_LOAD -> GEMM(writeback) -> EWISE -> DMA_STORE. Two output writebacks to off-chip.",
    )


def dep_token_explicit_ewise(cfg: FlowConfig) -> FlowResult:
    res = explicit_ewise(cfg)
    res.name = "dep_token_explicit_ewise"
    res.notes = "Same traffic as explicit_ewise; ordering uses dep tokens instead of BARRIER. Improves control semantics, not off-chip bytes."
    return res


def build_report(cfg: FlowConfig, results):
    lines = []
    lines.append("# P3 Runtime Flow Analysis")
    lines.append("")
    lines.append("## Input")
    lines.append("")
    lines.append(f"- M/N/K: `{cfg.m}/{cfg.n}/{cfg.k}`")
    lines.append(f"- BPE: `{cfg.bpe}`")
    lines.append(f"- Freq: `{cfg.freq_mhz} MHz`")
    lines.append(f"- Bandwidth: `{cfg.bw_gbps} GB/s`")
    lines.append(f"- Array: `{cfg.array_size}x{cfg.array_size}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Flow | Ops | Off-chip Bytes | OI | Peak GOPS | BW Roof GOPS | Attainable GOPS | Bottleneck |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---|")
    for r in results:
        lines.append(
            f"| {r.name} | {r.ops:.0f} | {r.offchip_bytes:.0f} | {r.arithmetic_intensity:.6f} | "
            f"{r.peak_compute_gops:.6f} | {r.bw_roof_gops:.6f} | {r.attainable_gops:.6f} | {r.bottleneck} |"
        )
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    fused = [r for r in results if r.name == "fused_gemm_relu"][0]
    explicit = [r for r in results if r.name == "explicit_ewise"][0]
    baseline = [r for r in results if r.name == "baseline_gemm"][0]
    saved = explicit.offchip_bytes - fused.offchip_bytes
    lines.append(f"- `fused_gemm_relu` and `baseline_gemm` have the same off-chip bytes in the current RTL, but fused path performs more useful work on the same bytes.")
    lines.append(f"- `explicit_ewise` costs one extra output writeback, so compared with fused it adds `{saved:.0f}` bytes of off-chip traffic.")
    lines.append(f"- Relative to baseline, fused path raises OI from `{baseline.arithmetic_intensity:.6f}` to `{fused.arithmetic_intensity:.6f}` without increasing off-chip traffic.")
    lines.append(f"- `dep_token_explicit_ewise` changes control semantics, but not traffic; its value is scheduling correctness, not byte reduction.")
    lines.append("")
    lines.append("## Design Notes")
    lines.append("")
    for r in results:
        lines.append(f"- `{r.name}`: {r.notes}")
    lines.append("")
    lines.append("## P3 Takeaway")
    lines.append("")
    lines.append("- For post-op heavy workloads, fusion is valuable primarily because it avoids extra off-chip output traffic.")
    lines.append("- Explicit opcode chaining is architecturally cleaner and more general, but without output-residency policy it costs more bandwidth.")
    lines.append("- The next P3 step should therefore focus on layout/residency/buffering, not more opcode surface area.")
    lines.append("")
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser(description="Runtime flow traffic model for current TPU command paths")
    p.add_argument("--M", type=int, default=16)
    p.add_argument("--N", type=int, default=16)
    p.add_argument("--K", type=int, default=16)
    p.add_argument("--bpe", type=int, default=4)
    p.add_argument("--freq-mhz", type=float, default=200.0)
    p.add_argument("--bw-gbps", type=float, default=6.4)
    p.add_argument("--array-size", type=int, default=8)
    p.add_argument("--mac-per-pe-per-cycle", type=float, default=1.0)
    p.add_argument("--tm", type=int, default=16)
    p.add_argument("--tn", type=int, default=16)
    p.add_argument("--tk", type=int, default=16)
    p.add_argument("--out", default="docs/P3_RUNTIME_FLOW_ANALYSIS.md")
    args = p.parse_args()

    cfg = FlowConfig(
        m=args.M,
        n=args.N,
        k=args.K,
        bpe=args.bpe,
        freq_mhz=args.freq_mhz,
        bw_gbps=args.bw_gbps,
        array_size=args.array_size,
        mac_per_pe_per_cycle=args.mac_per_pe_per_cycle,
        tm=args.tm,
        tn=args.tn,
        tk=args.tk,
    )

    results = [
        baseline_gemm(cfg),
        fused_gemm_relu(cfg),
        explicit_ewise(cfg),
        dep_token_explicit_ewise(cfg),
    ]

    report = build_report(cfg, results)
    with open(args.out, "w") as f:
        f.write(report)
    print(f"Wrote report: {args.out}")


if __name__ == "__main__":
    main()
