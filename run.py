#!/usr/bin/env python3
"""Reproducible multi-language benchmark runner for edva-lang/benchmarks.

Compares Edva, Clang (C), Rust, Zig, and Go across standardized workloads,
verifying identical stdout checksums across every language and measuring:
  - Cold compile time (ms)
  - Linked binary size (bytes)
  - Runtime latency (min / p50 / p95 / max ms, CoV %)
  - Peak RSS (KiB via wait4 ru_maxrss)
  - Throughput (items/s)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import platform
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WORKLOADS_DIR = ROOT / "workloads"
RESULTS_DIR = ROOT / "results"

WORKLOADS = [
    {
        "id": "wasm_numeric_kernel",
        "title": "8-Body 3D Kinematics Kernel",
        "description": "Unboxed 64-bit integer 8-body 3D kinematics step loop testing tight numeric codegen and register allocation.",
        "n": 400000,
        "unit": "steps",
    },
    {
        "id": "server_http_router",
        "title": "In-Memory HTTP/1.1 Router",
        "description": "HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization.",
        "n": 40000,
        "unit": "requests",
    },
    {
        "id": "cli_log_json",
        "title": "JSON Log Format & Parse",
        "description": "Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation.",
        "n": 20000,
        "unit": "records",
    },
    {
        "id": "collections_closures_generics",
        "title": "Collections, Closures & Generics",
        "description": "Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records.",
        "n": 16000,
        "unit": "items",
    },
]

LANGUAGES = ["edva", "clang", "rust", "zig", "go"]

PROBE_C = r"""
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static long long mono_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    long long t0 = mono_ns();
    pid_t pid = fork();
    if (pid < 0) return 3;
    if (pid == 0) {
        execvp(argv[1], &argv[1]);
        _exit(127);
    }
    int status = 0;
    struct rusage ru;
    while (wait4(pid, &status, 0, &ru) < 0) {
        if (errno != EINTR) return 4;
    }
    long long t1 = mono_ns();
    int code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    fprintf(stderr, "PROBE_NS=%lld PROBE_RSS_KB=%ld PROBE_CODE=%d\n",
            t1 - t0, ru.ru_maxrss, code);
    return code;
}
"""


def find_bin(env_key: str, default_name: str, extra_candidates: list[str] | None = None) -> str | None:
    if os.environ.get(env_key):
        return os.environ[env_key]
    found = shutil.which(default_name)
    if found:
        return found
    for cand in (extra_candidates or []):
        if Path(cand).is_file() and os.access(cand, os.X_OK):
            return cand
    return None


def cmd_version(cmd: list[str]) -> str:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True, timeout=10)
        return out.strip().splitlines()[0]
    except Exception:
        return "unknown"


def cpu_info() -> tuple[str, int, int]:
    model = platform.processor() or "unknown"
    cores = os.cpu_count() or 1
    mem_mib = 0
    if Path("/proc/cpuinfo").exists():
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                model = line.split(":", 1)[1].strip()
                break
    if Path("/proc/meminfo").exists():
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                mem_mib = int(line.split()[1]) // 1024
                break
    return model, cores, mem_mib


def build_probe(clang_bin: str, build_dir: Path) -> Path:
    src = build_dir / "probe.c"
    exe = build_dir / "probe"
    src.write_text(PROBE_C)
    subprocess.run([clang_bin, "-O2", str(src), "-o", str(exe)], check=True)
    return exe


def compile_target(
    lang: str,
    wdir: Path,
    out_bin: Path,
    bins: dict[str, str],
) -> tuple[float, int]:
    t0 = time.perf_counter()
    if lang == "edva":
        cmd = [bins["edva"], "--opt", "2", "--no-cache", "-o", str(out_bin), str(wdir / "edva.dva")]
        cwd = wdir
    elif lang == "clang":
        cmd = [bins["clang"], "-O2", str(wdir / "c.c"), "-lm", "-o", str(out_bin)]
        cwd = wdir
    elif lang == "rust":
        cmd = [bins["rust"], "-C", "opt-level=3", str(wdir / "rust.rs"), "-o", str(out_bin)]
        cwd = wdir
    elif lang == "zig":
        cmd = [bins["zig"], "build-exe", "-OReleaseFast", f"-femit-bin={out_bin}", str(wdir / "zig.zig")]
        cwd = wdir
    elif lang == "go":
        cmd = [bins["go"], "build", "-o", str(out_bin), str(wdir / "go.go")]
        cwd = wdir
    else:
        raise ValueError(f"unknown lang: {lang}")

    proc = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    if proc.returncode != 0:
        raise RuntimeError(f"Compile failed for {lang} in {wdir.name}:\n{proc.stdout}\n{proc.stderr}")
    return round(elapsed_ms, 2), out_bin.stat().st_size


def run_probe(probe_bin: Path, target_bin: Path, n: int) -> tuple[str, float, int]:
    proc = subprocess.run(
        [str(probe_bin), str(target_bin), str(n)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    ns = 0
    rss_kb = 0
    for line in proc.stderr.splitlines():
        if line.startswith("PROBE_NS="):
            parts = dict(tok.split("=", 1) for tok in line.strip().split())
            ns = int(parts["PROBE_NS"])
            rss_kb = int(parts["PROBE_RSS_KB"])
    return proc.stdout.strip(), ns / 1_000_000.0, rss_kb


def percentile(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = (len(sorted_vals) - 1) * p
    lo = math.floor(idx)
    hi = math.ceil(idx)
    if lo == hi:
        return sorted_vals[lo]
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (idx - lo)


def render_readme(data: dict) -> str:
    env = data["environment"]
    lines = [
        "# Edva Multi-Language Benchmarks",
        "",
        "Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification.",
        "",
        "## Environment & Pinned Toolchains",
        "",
        "| Component | Version / Spec | Flags |",
        "|---|---|---|",
        f"| Host | `{env['os']} {env['arch']}` | — |",
        f"| CPU | `{env['cpu']}` ({env['cores']} threads) | — |",
        f"| Memory | `{env['memory_mib']} MiB` | — |",
        f"| Edva | `{env['toolchains']['edva']}` | `edva build -O2 --no-cache` |",
        f"| Clang (C) | `{env['toolchains']['clang']}` | `clang -O2` |",
        f"| Rust | `{env['toolchains']['rust']}` | `rustc -C opt-level=3` |",
        f"| Zig | `{env['toolchains']['zig']}` | `zig build-exe -OReleaseFast` |",
        f"| Go | `{env['toolchains']['go']}` | `go build` |",
        "",
        "## Methodology",
        "",
        f"- **Correctness**: Every language must emit the exact same stdout checksum for each workload before timing is accepted.",
        f"- **Timing**: {data['config']['warmup']} warmup runs + {data['config']['runs']} measured runs via a minimal POSIX `fork`/`exec`/`wait4` + `clock_gettime(CLOCK_MONOTONIC)` probe measuring per-process wall time and `ru_maxrss` peak RSS.",
        "- **Reproduce**: `python3 run.py` (writes `results/latest.json` and regenerates this `README.md`).",
        "",
        "## Results",
        "",
    ]
    for w in data["workloads"]:
        lines.append(f"### `{w['id']}` — {w['title']} (`N = {w['n']}` {w['unit']})")
        lines.append("")
        lines.append(f"{w['description']} Verified checksum: `{w['checksum']}`.")
        lines.append("")
        lines.append("| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
        for lang in LANGUAGES:
            r = w["results"].get(lang)
            if not r:
                continue
            lines.append(
                f"| **{lang}** | {r['p50_ms']:.2f} | {r['p95_ms']:.2f} | {r['cov_pct']:.1f} "
                f"| {r['peak_rss_kb']} | {r['binary_bytes'] / 1024:.1f} | {r['compile_ms']:.0f} "
                f"| {r['throughput_per_s']:,.0f} {w['unit']}/s |"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Run edva-lang multi-language benchmarks")
    ap.add_argument("--warmup", type=int, default=2)
    ap.add_argument("--runs", type=int, default=7)
    ap.add_argument("--out", type=Path, default=RESULTS_DIR / "latest.json")
    ap.add_argument("--copy-site", type=Path, default=None, help="Optional path to copy results JSON (e.g. edva-lang.github.io/benchmarks/results.json)")
    args = ap.parse_args()

    bins = {
        "edva": find_bin("EDVA", "edva", ["/home/ike/Z/edva/edva"]),
        "clang": find_bin("CLANG", "clang"),
        "rust": find_bin("RUSTC", "rustc"),
        "zig": find_bin("ZIG", "zig"),
        "go": find_bin("GO_BIN", "go", ["/nix/store/fkz7zn1a0yiryf9kri2yh1s12k1sv557-go-1.26.10/bin/go"]),
    }
    missing = [k for k, v in bins.items() if not v]
    if missing:
        print(f"ERROR: missing toolchains: {', '.join(missing)}", file=sys.stderr)
        return 1

    toolchains = {
        "edva": cmd_version([bins["edva"], "--version"]),
        "clang": cmd_version([bins["clang"], "--version"]),
        "rust": cmd_version([bins["rust"], "--version"]),
        "zig": "zig " + cmd_version([bins["zig"], "version"]),
        "go": cmd_version([bins["go"], "version"]),
    }
    cpu_model, cores, mem_mib = cpu_info()

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="edva_bench_") as tmp:
        bdir = Path(tmp)
        probe_bin = build_probe(bins["clang"], bdir)

        workload_reports = []
        for w in WORKLOADS:
            wid = w["id"]
            wdir = WORKLOADS_DIR / wid
            n = w["n"]
            print(f"==> Workload: {wid} (N={n})", flush=True)
            expected_checksum: str | None = None
            lang_results: dict[str, dict] = {}

            for lang in LANGUAGES:
                out_bin = bdir / f"{wid}_{lang}"
                compile_ms, binary_bytes = compile_target(lang, wdir, out_bin, bins)

                # Warmup + checksum check
                for _ in range(args.warmup):
                    stdout, _, _ = run_probe(probe_bin, out_bin, n)
                    if expected_checksum is None:
                        expected_checksum = stdout
                    elif stdout != expected_checksum:
                        raise RuntimeError(
                            f"Checksum mismatch in {wid} for {lang}: got {stdout!r}, expected {expected_checksum!r}"
                        )

                samples_ms: list[float] = []
                rss_samples: list[int] = []
                for _ in range(args.runs):
                    stdout, ms, rss_kb = run_probe(probe_bin, out_bin, n)
                    if stdout != expected_checksum:
                        raise RuntimeError(f"Non-deterministic output in {wid} for {lang}: {stdout!r}")
                    samples_ms.append(ms)
                    rss_samples.append(rss_kb)

                s_sorted = sorted(samples_ms)
                p50 = percentile(s_sorted, 0.50)
                p95 = percentile(s_sorted, 0.95)
                mean = statistics.fmean(s_sorted)
                stddev = statistics.stdev(s_sorted) if len(s_sorted) > 1 else 0.0
                cov = (stddev / mean * 100.0) if mean > 0 else 0.0
                peak_rss = int(statistics.median(rss_samples))
                rate = (n / (p50 / 1000.0)) if p50 > 0 else 0.0

                lang_results[lang] = {
                    "compile_ms": compile_ms,
                    "binary_bytes": binary_bytes,
                    "min_ms": round(s_sorted[0], 3),
                    "p50_ms": round(p50, 3),
                    "p95_ms": round(p95, 3),
                    "max_ms": round(s_sorted[-1], 3),
                    "cov_pct": round(cov, 2),
                    "peak_rss_kb": peak_rss,
                    "throughput_per_s": round(rate, 1),
                }
                print(
                    f"    {lang:<6} p50={p50:6.2f}ms  p95={p95:6.2f}ms  rss={peak_rss:6d}KiB  "
                    f"bin={binary_bytes/1024:7.1f}KiB  compile={compile_ms:6.0f}ms",
                    flush=True,
                )

            workload_reports.append({
                "id": wid,
                "title": w["title"],
                "description": w["description"],
                "n": n,
                "unit": w["unit"],
                "checksum": expected_checksum,
                "results": lang_results,
            })

    report = {
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_url": "https://github.com/edva-lang/benchmarks",
        "config": {"warmup": args.warmup, "runs": args.runs},
        "environment": {
            "host": platform.node(),
            "os": f"{platform.system()} {platform.release()}",
            "arch": platform.machine(),
            "cpu": cpu_model,
            "cores": cores,
            "memory_mib": mem_mib,
            "toolchains": toolchains,
        },
        "languages": LANGUAGES,
        "workloads": workload_reports,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n")
    (ROOT / "README.md").write_text(render_readme(report))
    if args.copy_site:
        args.copy_site.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.out, args.copy_site)
    print(f"\nWrote {args.out} and {ROOT / 'README.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
