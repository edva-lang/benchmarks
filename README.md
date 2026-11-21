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
| Zig | `zig 0.17.0` | `zig build-exe -OReleaseFast` |
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
| **edva** | 76.25 | 77.47 | 1.3 | 2056 | 78.0 | 361 | 5,245,669 steps/s |
| **clang** | 75.66 | 77.65 | 1.2 | 2100 | 15.6 | 100 | 5,286,919 steps/s |
| **rust** | 224.12 | 228.03 | 1.0 | 2108 | 517.5 | 232 | 1,784,780 steps/s |
| **zig** | 72.46 | 75.21 | 1.7 | 780 | 3911.1 | 11949 | 5,519,989 steps/s |
| **go** | 267.47 | 277.70 | 2.0 | 2208 | 2373.1 | 137 | 1,495,507 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 40000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=77124860,200=20000,201=10000,404=10000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 4.91 | 4.96 | 1.7 | 2492 | 87.5 | 520 | 8,150,426 requests/s |
| **clang** | 8.51 | 9.41 | 9.6 | 2068 | 15.6 | 95 | 4,701,789 requests/s |
| **rust** | 7.93 | 8.12 | 3.3 | 2264 | 518.4 | 314 | 5,044,299 requests/s |
| **zig** | 4.31 | 4.48 | 1.9 | 736 | 3956.5 | 11870 | 9,271,942 requests/s |
| **go** | 17.31 | 18.18 | 2.7 | 6500 | 2384.1 | 100 | 2,311,350 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 20000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=419027993,ok=16000,err=4000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 2.43 | 2.98 | 11.6 | 2532 | 91.6 | 656 | 8,236,812 records/s |
| **clang** | 3.06 | 3.12 | 1.1 | 2068 | 15.6 | 108 | 6,532,602 records/s |
| **rust** | 3.04 | 3.08 | 1.1 | 2096 | 518.2 | 247 | 6,584,429 records/s |
| **zig** | 6.01 | 6.26 | 2.3 | 736 | 4122.5 | 14295 | 3,326,682 records/s |
| **go** | 26.65 | 27.51 | 1.4 | 7360 | 2883.8 | 138 | 750,424 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 16000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=490586550,kept=11000,heavy=8031`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 0.74 | 0.77 | 3.6 | 2080 | 82.9 | 547 | 21,568,342 items/s |
| **clang** | 0.60 | 0.62 | 4.8 | 2104 | 15.7 | 103 | 26,665,600 items/s |
| **rust** | 0.73 | 0.76 | 3.1 | 2188 | 518.1 | 276 | 21,990,558 items/s |
| **zig** | 0.56 | 0.61 | 6.4 | 784 | 4001.2 | 13850 | 28,543,191 items/s |
| **go** | 1.07 | 1.15 | 4.4 | 2336 | 2374.0 | 108 | 14,976,071 items/s |
