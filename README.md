# Edva Multi-Language Benchmarks

Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification.

## Environment & Pinned Toolchains

| Component | Version / Spec | Flags |
|---|---|---|
| Host | `Linux 6.18.60 x86_64` | — |
| CPU | `Intel(R) Core(TM) i5-10600KF CPU @ 4.10GHz` (12 threads) | — |
| Memory | `15922 MiB` | — |
| Edva | `edva 1.6.3+ade0ce7` | `edva --opt 2 --no-cache` |
| Clang (C) | `clang version 21.1.8` | `clang -O2` |
| Rust | `rustc 1.99.0 (b940084d7 2026-09-28) (built from a source tarball)` | `rustc -C opt-level=3` |
| Zig | `zig 0.17.0` | `zig build-exe -OReleaseFast -lc -fstrip` |
| Go | `go version go1.26.10 linux/amd64` | `go build` |

## Methodology

- **Correctness**: Every language must emit the exact same stdout checksum for each workload before timing is accepted.
- **Timing**: 2 warmup runs + 9 measured runs via a minimal POSIX `fork`/`exec`/`wait4` + `clock_gettime(CLOCK_MONOTONIC)` probe measuring per-process wall time and `ru_maxrss` peak RSS.
- **Reproduce**: `nu run.nu` (writes `results/latest.json` and regenerates this `README.md`).

## Results

### `wasm_numeric_kernel` — 8-Body 3D Kinematics Kernel (`N = 400000` steps)

Unboxed 64-bit integer 8-body 3D kinematics step loop testing tight numeric codegen and register allocation. Verified checksum: `kernel=4439989`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 73.16 | 73.81 | 0.5 | 2012 | 78.3 | 365 | 5,467,137 steps/s |
| **clang** | 72.73 | 73.48 | 0.6 | 2116 | 15.6 | 96 | 5,499,626 steps/s |
| **rust** | 219.05 | 221.75 | 0.7 | 2060 | 517.5 | 215 | 1,826,051 steps/s |
| **zig** | 73.05 | 82.57 | 6.7 | 1828 | 185.3 | 2192 | 5,475,553 steps/s |
| **go** | 267.48 | 275.59 | 1.8 | 2336 | 2373.1 | 104 | 1,495,469 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 200000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=905190980,200=100000,201=50000,404=50000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 18.79 | 18.89 | 0.4 | 4972 | 87.6 | 548 | 10,646,854 requests/s |
| **clang** | 35.67 | 36.50 | 2.0 | 2068 | 15.6 | 95 | 5,607,216 requests/s |
| **rust** | 35.74 | 36.34 | 1.1 | 2260 | 518.4 | 308 | 5,596,522 requests/s |
| **zig** | 18.30 | 18.34 | 0.4 | 1836 | 191.2 | 2317 | 10,927,717 requests/s |
| **go** | 79.96 | 89.82 | 5.8 | 7976 | 2384.1 | 99 | 2,501,138 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 100000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=95139755,ok=80000,err=20000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 11.08 | 11.26 | 1.1 | 5136 | 91.8 | 636 | 9,026,434 records/s |
| **clang** | 14.33 | 15.97 | 6.3 | 2116 | 15.6 | 108 | 6,977,562 records/s |
| **rust** | 13.36 | 13.66 | 1.1 | 2060 | 518.2 | 242 | 7,487,588 records/s |
| **zig** | 29.38 | 30.01 | 1.0 | 1824 | 231.2 | 2864 | 3,403,707 records/s |
| **go** | 124.80 | 139.44 | 6.2 | 8464 | 2883.8 | 112 | 801,265 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 800000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=857016143,kept=550000,heavy=401593`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 11.96 | 12.11 | 1.9 | 3564 | 87.2 | 499 | 66,866,659 items/s |
| **clang** | 8.99 | 9.01 | 0.1 | 2068 | 15.7 | 97 | 88,937,805 items/s |
| **rust** | 11.56 | 11.78 | 0.9 | 2192 | 518.1 | 252 | 69,187,801 items/s |
| **zig** | 8.92 | 9.07 | 0.8 | 1840 | 194.9 | 2491 | 89,704,211 items/s |
| **go** | 14.79 | 15.09 | 1.2 | 6560 | 2374.0 | 99 | 54,106,816 items/s |

