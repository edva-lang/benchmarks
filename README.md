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
| Zig | `zig 0.17.0` | `zig build-exe -OReleaseFast -lc` |
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
| **edva** | 73.39 | 73.94 | 0.6 | 2064 | 78.3 | 366 | 5,450,420 steps/s |
| **clang** | 72.87 | 73.66 | 0.7 | 2116 | 15.6 | 97 | 5,489,371 steps/s |
| **rust** | 221.11 | 222.33 | 1.2 | 2064 | 517.5 | 212 | 1,809,069 steps/s |
| **zig** | 72.93 | 73.31 | 0.4 | 1820 | 3683.6 | 10761 | 5,484,525 steps/s |
| **go** | 264.92 | 276.10 | 1.8 | 2336 | 2373.1 | 98 | 1,509,900 steps/s |

### `server_http_router` — In-Memory HTTP/1.1 Router (`N = 200000` requests)

HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization. Verified checksum: `digest=905190980,200=100000,201=50000,404=50000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 20.56 | 20.73 | 3.9 | 4920 | 87.6 | 559 | 9,729,411 requests/s |
| **clang** | 36.01 | 36.51 | 1.3 | 2068 | 15.6 | 96 | 5,554,296 requests/s |
| **rust** | 35.45 | 36.05 | 1.2 | 2196 | 518.4 | 305 | 5,641,598 requests/s |
| **zig** | 18.61 | 18.76 | 0.5 | 1888 | 3728.1 | 10947 | 10,747,507 requests/s |
| **go** | 80.09 | 85.69 | 3.5 | 7776 | 2384.1 | 108 | 2,497,138 requests/s |

### `cli_log_json` — JSON Log Format & Parse (`N = 100000` records)

Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation. Verified checksum: `checksum=95139755,ok=80000,err=20000`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 10.90 | 10.97 | 0.5 | 5092 | 91.8 | 644 | 9,177,511 records/s |
| **clang** | 13.81 | 13.99 | 0.9 | 2068 | 15.6 | 107 | 7,243,030 records/s |
| **rust** | 13.39 | 13.43 | 0.5 | 2060 | 518.2 | 245 | 7,470,210 records/s |
| **zig** | 29.41 | 29.85 | 0.8 | 2008 | 3891.5 | 11610 | 3,399,986 records/s |
| **go** | 126.50 | 140.25 | 6.1 | 8492 | 2883.8 | 110 | 790,523 records/s |

### `collections_closures_generics` — Collections, Closures & Generics (`N = 800000` items)

Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records. Verified checksum: `pipeline=857016143,kept=550000,heavy=401593`.

| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |
|---|---:|---:|---:|---:|---:|---:|---:|
| **edva** | 11.95 | 12.13 | 0.8 | 3524 | 87.2 | 500 | 66,920,759 items/s |
| **clang** | 8.98 | 9.00 | 0.2 | 2096 | 15.7 | 98 | 89,139,986 items/s |
| **rust** | 11.53 | 11.60 | 0.3 | 2192 | 518.1 | 255 | 69,362,414 items/s |
| **zig** | 8.89 | 8.95 | 0.5 | 2080 | 3762.4 | 11036 | 90,011,310 items/s |
| **go** | 14.95 | 15.09 | 0.7 | 6432 | 2374.0 | 97 | 53,497,378 items/s |

