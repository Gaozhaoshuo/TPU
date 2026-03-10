#!/usr/bin/env python3
"""
Batch runner for perf_model.py.
Generates a markdown report with multiple benchmark cases.
"""

import datetime
import os
import sys

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if THIS_DIR not in sys.path:
    sys.path.insert(0, THIS_DIR)

import perf_model  # noqa: E402


CASES = [
    {
        "name": "small_fp32",
        "desc": "Small GEMM, likely bandwidth-sensitive",
        "cfg": {
            "m": 16,
            "n": 16,
            "k": 16,
            "freq_mhz": 200.0,
            "bw_gbps": 6.4,
            "tm": 16,
            "tn": 16,
            "tk": 16,
            "bpe": 4,
            "array_size": 8,
            "mac_per_pe_per_cycle": 1.0,
            "c_read": True,
            "c_write": True,
        },
    },
    {
        "name": "medium_fp32",
        "desc": "Medium GEMM around ridge transition",
        "cfg": {
            "m": 64,
            "n": 64,
            "k": 64,
            "freq_mhz": 200.0,
            "bw_gbps": 6.4,
            "tm": 32,
            "tn": 32,
            "tk": 16,
            "bpe": 4,
            "array_size": 8,
            "mac_per_pe_per_cycle": 1.0,
            "c_read": True,
            "c_write": True,
        },
    },
    {
        "name": "large_fp32",
        "desc": "Large GEMM, typically compute-bound",
        "cfg": {
            "m": 256,
            "n": 256,
            "k": 256,
            "freq_mhz": 200.0,
            "bw_gbps": 6.4,
            "tm": 32,
            "tn": 32,
            "tk": 16,
            "bpe": 4,
            "array_size": 8,
            "mac_per_pe_per_cycle": 1.0,
            "c_read": True,
            "c_write": True,
        },
    },
]


def fmt(v):
    if isinstance(v, float):
        return f"{v:.6f}"
    return str(v)


def run_case(case):
    cfg = perf_model.ModelConfig(**case["cfg"])
    res = perf_model.analyze(cfg)
    naive_bytes = perf_model.bytes_naive(cfg)
    ridge_oi = res["peak_compute_gops"] / cfg.bw_gbps
    return cfg, res, naive_bytes, ridge_oi


def build_markdown(results):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = []
    lines.append("# TPU Performance Baseline Report")
    lines.append("")
    lines.append(f"Generated at: `{now}`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Case | M/N/K | OI (ops/byte) | Peak (GOPS) | BW Roof (GOPS) | Attainable (GOPS) | Bottleneck |")
    lines.append("|---|---:|---:|---:|---:|---:|---|")

    for item in results:
        case, cfg, res, _, _ = item
        mnk = f"{cfg.m}/{cfg.n}/{cfg.k}"
        lines.append(
            "| {name} | {mnk} | {oi} | {peak} | {bw} | {att} | {bound} |".format(
                name=case["name"],
                mnk=mnk,
                oi=fmt(res["oi"]),
                peak=fmt(res["peak_compute_gops"]),
                bw=fmt(res["bw_roof_gops"]),
                att=fmt(res["attainable_gops"]),
                bound=res["bound"],
            )
        )

    lines.append("")
    lines.append("## Details")
    lines.append("")

    for item in results:
        case, cfg, res, naive_bytes, ridge_oi = item
        lines.append(f"### {case['name']}")
        lines.append("")
        lines.append(f"- Description: {case['desc']}")
        lines.append(f"- M/N/K: `{cfg.m}/{cfg.n}/{cfg.k}`")
        lines.append(f"- Tile: `({cfg.tm}, {cfg.tn}, {cfg.tk})`")
        lines.append(f"- Frequency: `{cfg.freq_mhz} MHz`")
        lines.append(f"- Bandwidth: `{cfg.bw_gbps} GB/s`")
        lines.append(f"- BPE: `{cfg.bpe}`")
        lines.append(f"- Array: `{cfg.array_size}x{cfg.array_size}`")
        lines.append(f"- Ops: `{res['ops']:.0f}`")
        lines.append(f"- Bytes naive/tiled: `{naive_bytes:.0f}` / `{res['bytes_total']:.0f}`")
        lines.append(f"- OI: `{res['oi']:.6f}`")
        lines.append(f"- Ridge OI*: `{ridge_oi:.6f}`")
        lines.append(f"- Peak Compute: `{res['peak_compute_gops']:.6f} GOPS`")
        lines.append(f"- BW Roof: `{res['bw_roof_gops']:.6f} GOPS`")
        lines.append(f"- Attainable: `{res['attainable_gops']:.6f} GOPS`")
        lines.append(f"- Bottleneck: `{res['bound']}`")
        lines.append(f"- Cycles (compute/memory/est): `{res['compute_cycles']:.2f}` / `{res['memory_cycles']:.2f}` / `{res['est_cycles']:.2f}`")
        lines.append("")

    lines.append("## Notes")
    lines.append("")
    lines.append("- 该模型是 roofline + 粗粒度周期估算，用于设计期 tradeoff 判断。")
    lines.append("- 若要贴近实测，请把 `bw-gbps` 改成链路实测可持续带宽，并加入 DMA/调度开销。")
    lines.append("")

    return "\n".join(lines)


def main():
    out_path = os.path.join(os.path.dirname(THIS_DIR), "docs", "PERF_BASELINE.md")

    results = []
    for case in CASES:
        cfg, res, naive_bytes, ridge_oi = run_case(case)
        results.append((case, cfg, res, naive_bytes, ridge_oi))

    report = build_markdown(results)
    with open(out_path, "w") as f:
        f.write(report)

    print(f"Wrote report: {out_path}")


if __name__ == "__main__":
    main()
