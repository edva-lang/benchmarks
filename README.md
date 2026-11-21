# Edva Multi-Language Benchmarks

Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification.

## Environment & Pinned Toolchains

| Component | Version / Spec | Flags |
|---|---|---|
| Host | `Linux 6.18.60 x86_64` | — |
| CPU | `Intel(R) Core(TM) i5-10600KF CPU @ 4.10GHz` (12 threads) | — |
| Memory | `15922 MiB` | — |
| Edva | `edva 1.6.2+dce57be-dirty` | `edva build -O2 --no-cache` |
| Clang (C) | `clang version 21.1.8` | `clang -O2` |
| Rust | `rustc 1.99.0 (b940084d7 2026-09-28) (built from a source tarball)` | `rustc -C opt-level=3` |
| Zig | `zig 0.17.0` | `zig build-exe -OReleaseFast -lc` |
| Go | `go version go1.26.10 linux/amd64` | `go build` |

## Methodology

- **Correctness**: Every language must emit the exact same stdout checksum for each workload before timing is accepted.
- **Timing**: 2 warmup runs + 9 measured runs via a minimal POSIX `fork`/`exec`/`wait4` + `clock_gettime(CLOCK_MONOTONIC)` probe measuring per-process wall time and `ru_maxrss` peak RSS.
- **Reproduce**: `python3 run.py` (writes `results/latest.json` and regenerates this `README.md`).

## Results

### `wasm_numeric_kernel` — 8-Body 3D Kinematics Kernel (`N = 400000` steps)

Unboxed 64-bit integer 8-body 3D kinematics step loop testing tight numeric codegen and register allocation. Verified checksum: `kernel=4439989`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 75.63 | 76.77 | 1.0 | 2012 | 78.0 | 385 | 5,289,064 steps/s |
| **clang** | 74.51 | 75.72 | 1.1 | 2116 | 15.6 | 102 | 5,368,725 steps/s |
| **rust** | 228.65 | 232.24 | 1.1 | 2164 | 517.5 | 234 | 1,749,374 steps/s |
| **zig** | 76.84 | 82.27 | 3.8 | 1820 | 3683.6 | 12697 | 5,205,526 steps/s |
| **go** | 279.15 | 290.12 | 2.1 | 2336 | 2373.1 | 115 | 1,432,941 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 40000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=77124860,200=20000,201=10000,404=10000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 5.30 | 5.44 | 1.7 | 2532 | 87.5 | 583 | 7,541,141 requests/s |
| **clang** | 7.71 | 7.84 | 1.0 | 2108 | 15.6 | 100 | 5,190,760 requests/s |
| **rust** | 7.75 | 9.26 | 8.3 | 2196 | 518.4 | 348 | 5,164,162 requests/s |
| **zig** | 4.11 | 4.67 | 6.7 | 1824 | 3728.1 | 12795 | 9,728,769 requests/s |
| **go** | 17.15 | 18.55 | 3.6 | 6372 | 2384.1 | 109 | 2,331,770 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 20000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=419027993,ok=16000,err=4000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 2.49 | 2.62 | 3.0 | 2572 | 91.6 | 666 | 8,032,693 records/s |
| **clang** | 3.11 | 3.16 | 1.0 | 2100 | 15.6 | 111 | 6,433,222 records/s |
| **rust** | 3.06 | 3.16 | 1.8 | 2172 | 518.2 | 254 | 6,530,757 records/s |
| **zig** | 6.81 | 11.04 | 25.0 | 2008 | 3891.5 | 16306 | 2,936,593 records/s |
| **go** | 29.38 | 35.74 | 10.3 | 7232 | 2883.8 | 175 | 680,793 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 16000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=490586550,kept=11000,heavy=8031`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 0.83 | 0.88 | 5.2 | 2000 | 82.9 | 671 | 19,358,742 items/s |
| **clang** | 0.60 | 0.66 | 5.9 | 2108 | 15.7 | 123 | 26,473,148 items/s |
| **rust** | 0.73 | 0.87 | 8.0 | 2172 | 518.1 | 330 | 21,842,198 items/s |
| **zig** | 0.74 | 0.94 | 15.2 | 2012 | 3762.4 | 16758 | 21,682,479 items/s |
| **go** | 1.41 | 1.62 | 8.6 | 2336 | 2374.0 | 159 | 11,391,087 items/s |
