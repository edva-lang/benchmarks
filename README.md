# Edva Multi-Language Benchmarks

Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification.

## Environment & Pinned Toolchains

| Component | Version / Spec | Flags |
|---|---|---|
| Host | `Linux 6.18.60 x86_64` | — |
| CPU | `Intel(R) Core(TM) i5-10600KF CPU @ 4.10GHz` (12 threads) | — |
| Memory | `15922 MiB` | — |
| Edva | `edva 1.6.2+d06c996-dirty` | `edva build -O2 --no-cache` |
| Clang (C) | `clang version 21.1.8` | `clang -O2` |
| Rust | `rustc 1.99.0 (b940084d7 2026-09-28) (built from a source tarball)` | `rustc -C opt-level=3` |
| Zig | `zig 0.17.0` | `zig build-exe -OReleaseFast` |
| Go | `go version go1.26.10 linux/amd64` | `go build` |

## Methodology

- **Correctness**: Every language must emit the exact same stdout checksum for each workload before timing is accepted.
- **Timing**: 2 warmup runs + 7 measured runs via a minimal POSIX `fork`/`exec`/`wait4` + `clock_gettime(CLOCK_MONOTONIC)` probe measuring per-process wall time and `ru_maxrss` peak RSS.
- **Reproduce**: `python3 run.py` (writes `results/latest.json` and regenerates this `README.md`).

## Results

### `wasm_numeric_kernel` — 8-Body 3D Kinematics Kernel (`N = 400000` steps)

Unboxed 64-bit integer 8-body 3D kinematics step loop testing tight numeric codegen and register allocation. Verified checksum: `kernel=4439989`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 76.98 | 84.49 | 5.1 | 2076 | 78.0 | 379 | 5,196,344 steps/s |
| **clang** | 75.58 | 77.41 | 1.2 | 2112 | 15.6 | 109 | 5,292,342 steps/s |
| **rust** | 230.12 | 236.29 | 1.4 | 2060 | 517.5 | 498 | 1,738,262 steps/s |
| **zig** | 75.94 | 79.07 | 2.1 | 736 | 3911.1 | 13440 | 5,267,575 steps/s |
| **go** | 276.35 | 295.06 | 3.2 | 2336 | 2373.1 | 2996 | 1,447,436 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 40000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=77124860,200=20000,201=10000,404=10000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 4.84 | 5.54 | 7.4 | 2532 | 87.5 | 597 | 8,264,579 requests/s |
| **clang** | 7.62 | 7.82 | 1.3 | 2068 | 15.6 | 99 | 5,248,692 requests/s |
| **rust** | 7.80 | 8.45 | 4.2 | 2132 | 518.4 | 347 | 5,124,893 requests/s |
| **zig** | 4.37 | 4.47 | 1.2 | 736 | 3956.5 | 13705 | 9,149,179 requests/s |
| **go** | 17.62 | 20.62 | 8.4 | 6628 | 2384.1 | 188 | 2,269,814 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 20000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=419027993,ok=16000,err=4000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 2.53 | 2.62 | 2.2 | 2556 | 91.6 | 682 | 7,903,967 records/s |
| **clang** | 3.14 | 3.21 | 1.6 | 2068 | 15.6 | 115 | 6,363,380 records/s |
| **rust** | 3.08 | 3.18 | 2.2 | 2044 | 518.2 | 270 | 6,494,580 records/s |
| **zig** | 5.90 | 7.01 | 9.4 | 784 | 4122.5 | 14410 | 3,388,638 records/s |
| **go** | 26.32 | 27.38 | 2.0 | 7552 | 2883.8 | 424 | 759,845 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 16000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=490586550,kept=11000,heavy=8031`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 0.72 | 0.75 | 3.0 | 2072 | 82.9 | 525 | 22,199,499 items/s |
| **clang** | 0.61 | 0.65 | 5.6 | 2068 | 15.7 | 103 | 26,390,403 items/s |
| **rust** | 0.71 | 0.78 | 4.5 | 2188 | 518.1 | 282 | 22,534,354 items/s |
| **zig** | 0.58 | 0.59 | 3.6 | 800 | 4001.2 | 14080 | 27,469,132 items/s |
| **go** | 1.06 | 1.12 | 3.8 | 2336 | 2374.0 | 125 | 15,055,097 items/s |
