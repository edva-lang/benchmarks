# Edva Multi-Language Benchmarks

Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification.

## Environment & Pinned Toolchains

| Component | Version / Spec | Flags |
|---|---|---|
| Host | `Linux 6.18.60 x86_64` | — |
| CPU | `Intel(R) Core(TM) i5-10600KF CPU @ 4.10GHz` (12 threads) | — |
| Memory | `15922 MiB` | — |
| Edva | `edva 1.6.3+9200f34-dirty` | `edva --opt 2 --no-cache` |
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
| **edva** | 73.25 | 73.98 | 0.6 | 1952 | 25.9 | 350 | 5,461,021 steps/s |
| **clang** | 73.13 | 79.48 | 4.3 | 2096 | 15.6 | 97 | 5,470,112 steps/s |
| **rust** | 220.05 | 231.90 | 2.4 | 2160 | 517.5 | 492 | 1,817,784 steps/s |
| **zig** | 72.67 | 73.58 | 0.8 | 1828 | 185.3 | 2299 | 5,504,355 steps/s |
| **go** | 264.72 | 265.66 | 0.2 | 2336 | 2373.1 | 176 | 1,511,034 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 200000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=905190980,200=100000,201=50000,404=50000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 20.37 | 20.60 | 0.7 | 4920 | 35.5 | 511 | 9,819,280 requests/s |
| **clang** | 36.01 | 36.83 | 1.6 | 2068 | 15.6 | 96 | 5,553,324 requests/s |
| **rust** | 35.54 | 36.03 | 1.4 | 2196 | 518.4 | 316 | 5,627,471 requests/s |
| **zig** | 18.25 | 19.35 | 3.2 | 1836 | 191.2 | 2379 | 10,957,653 requests/s |
| **go** | 80.55 | 86.59 | 4.7 | 8104 | 2384.1 | 102 | 2,482,926 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 100000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=95139755,ok=80000,err=20000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 11.30 | 14.22 | 11.9 | 4920 | 35.7 | 615 | 8,849,665 records/s |
| **clang** | 14.33 | 15.34 | 4.5 | 2100 | 15.6 | 109 | 6,976,210 records/s |
| **rust** | 14.34 | 16.67 | 10.1 | 2064 | 518.2 | 241 | 6,973,067 records/s |
| **zig** | 29.46 | 30.27 | 1.2 | 1824 | 231.2 | 2896 | 3,394,950 records/s |
| **go** | 121.73 | 132.68 | 4.3 | 8320 | 2883.8 | 116 | 821,472 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 800000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=857016143,kept=550000,heavy=401593`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 11.63 | 12.03 | 1.8 | 3384 | 35.1 | 489 | 68,798,722 items/s |
| **clang** | 9.00 | 9.05 | 0.5 | 2068 | 15.7 | 96 | 88,924,627 items/s |
| **rust** | 11.63 | 12.44 | 3.3 | 2188 | 518.1 | 259 | 68,765,989 items/s |
| **zig** | 8.91 | 9.10 | 1.2 | 1840 | 194.9 | 2508 | 89,818,692 items/s |
| **go** | 14.75 | 14.95 | 0.8 | 6432 | 2374.0 | 99 | 54,226,910 items/s |

