#!/usr/bin/env nu
# Reproducible multi-language benchmark runner for edva-lang/benchmarks.
#
# Compares Edva, Clang (C), Rust, Zig (-lc dynamic), and Go across standardized
# workloads, verifying identical stdout checksums across every language and measuring:
#   - Cold compile time (ms)
#   - Linked binary size (bytes)
#   - Runtime latency (min / p50 / p95 / max ms, CoV %)
#   - Peak RSS (KiB via wait4 ru_maxrss)
#   - Throughput (items/s)

const PROBE_C = '#define _GNU_SOURCE
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
'

def find_bin [env_key: string, default_name: string, extras: list<string> = []] {
    let from_env = ($env | get -o $env_key | default "")
    if ($from_env | str length) > 0 {
        return $from_env
    }
    let w = (which $default_name | get -o 0.path | default "")
    if ($w | str length) > 0 {
        return $w
    }
    for cand in $extras {
        if ($cand | path exists) {
            return $cand
        }
    }
    ""
}

def cmd_version [bin: string, flag: string] {
    let r = (^$bin $flag | complete)
    let txt = (if ($r.stdout | str trim | str length) > 0 { $r.stdout } else { $r.stderr })
    $txt | str trim | lines | get -o 0 | default "unknown"
}

def cpu_info [] {
    let model = if ("/proc/cpuinfo" | path exists) {
        open --raw /proc/cpuinfo
        | lines
        | where {|l| $l | str starts-with "model name" }
        | get -o 0
        | default ": unknown"
        | split row ":"
        | get -o 1
        | default "unknown"
        | str trim
    } else {
        "unknown"
    }
    let cores = ((^nproc | complete).stdout | str trim | into int)
    let mem_mib = if ("/proc/meminfo" | path exists) {
        let kb = (
            open --raw /proc/meminfo
            | lines
            | where {|l| $l | str starts-with "MemTotal:" }
            | get -o 0
            | default "MemTotal: 0 kB"
            | split words
            | get -o 1
            | default "0"
            | into int
        )
        ($kb // 1024)
    } else {
        0
    }
    { model: $model, cores: $cores, mem_mib: $mem_mib }
}

def percentile [sorted_vals: list<float>, p: float] {
    let n = ($sorted_vals | length)
    if $n == 0 { return 0.0 }
    let idx = (($n - 1) * $p)
    let lo = ($idx | math floor | into int)
    let hi = ($idx | math ceil | into int)
    if $lo == $hi {
        $sorted_vals | get $lo
    } else {
        let vlo = ($sorted_vals | get $lo)
        let vhi = ($sorted_vals | get $hi)
        $vlo + (($vhi - $vlo) * ($idx - $lo))
    }
}

def fmt_fixed [val: float, decimals: int] {
    let factor = (10 ** $decimals)
    let scaled = (($val * $factor) | math round | into int)
    let neg = ($scaled < 0)
    let abs_s = (if $neg { -$scaled } else { $scaled })
    if $decimals == 0 {
        return (if $neg { $"-($abs_s)" } else { $"($abs_s)" })
    }
    let ip = ($abs_s // $factor)
    let fp = ($abs_s mod $factor | into string | fill -a right -c '0' -w $decimals)
    if $neg { $"-($ip).($fp)" } else { $"($ip).($fp)" }
}

def fmt_commas [val: float] {
    let n = ($val | math round | into int)
    let s = ($n | into string)
    let chars = ($s | split chars | reverse)
    $chars
    | chunks 3
    | each {|g| $g | reverse | str join "" }
    | reverse
    | str join ","
}

def compile_target [lang: string, wdir: string, out_bin: string, bins: record] {
    let t0 = (date now)
    let res = (do {
        cd $wdir
        match $lang {
            "edva" => (^($bins.edva) --opt 2 --no-cache -o $out_bin ($wdir | path join "edva.dva") | complete),
            "clang" => (^($bins.clang) -O2 ($wdir | path join "c.c") -lm -o $out_bin | complete),
            "rust" => (^($bins.rust) -C opt-level=3 ($wdir | path join "rust.rs") -o $out_bin | complete),
            "zig" => (^($bins.zig) build-exe -OReleaseFast -lc -fstrip $"-femit-bin=($out_bin)" ($wdir | path join "zig.zig") | complete),
            "go" => (^($bins.go) build -o $out_bin ($wdir | path join "go.go") | complete),
            _ => (error make { msg: $"unknown language: ($lang)" })
        }
    })
    let elapsed_ms = (((date now) - $t0) | into int) / 1_000_000.0
    if $res.exit_code != 0 {
        error make { msg: $"Compile failed for ($lang) in ($wdir):\n($res.stdout)\n($res.stderr)" }
    }
    let bin_bytes = (ls $out_bin | get 0.size | into int)
    { compile_ms: (($elapsed_ms * 100.0 | math round) / 100.0), binary_bytes: $bin_bytes }
}

def run_probe [probe_bin: string, target_bin: string, n: int] {
    let res = (^$probe_bin $target_bin ($n | into string) | complete)
    if $res.exit_code != 0 {
        error make { msg: $"Run failed for ($target_bin): exit ($res.exit_code)\n($res.stderr)" }
    }
    let pline = (
        $res.stderr
        | lines
        | where {|l| $l | str starts-with "PROBE_NS=" }
        | get -o 0
        | default "PROBE_NS=0 PROBE_RSS_KB=0 PROBE_CODE=0"
    )
    mut ns = 0
    mut rss_kb = 0
    for tok in ($pline | str trim | split row " ") {
        let kv = ($tok | split row "=")
        if ($kv | length) == 2 {
            if $kv.0 == "PROBE_NS" { $ns = ($kv.1 | into int) }
            if $kv.0 == "PROBE_RSS_KB" { $rss_kb = ($kv.1 | into int) }
        }
    }
    { stdout: ($res.stdout | str trim), ms: ($ns / 1_000_000.0), rss_kb: $rss_kb }
}

def render_readme [data: record] {
    let env_r = $data.environment
    let tc = $env_r.toolchains
    mut lines = [
        "# Edva Multi-Language Benchmarks"
        ""
        "Reproducible native benchmarks comparing **Edva**, **Clang (C)**, **Rust**, **Zig**, and **Go** across identical workloads with strict stdout checksum verification."
        ""
        "## Environment & Pinned Toolchains"
        ""
        "| Component | Version / Spec | Flags |"
        "|---|---|---|"
        $"| Host | `($env_r.os) ($env_r.arch)` | — |"
        $"| CPU | `($env_r.cpu)` \(($env_r.cores) threads\) | — |"
        $"| Memory | `($env_r.memory_mib) MiB` | — |"
        $"| Edva | `($tc.edva)` | `edva --opt 2 --no-cache` |"
        $"| Clang \(C\) | `($tc.clang)` | `clang -O2` |"
        $"| Rust | `($tc.rust)` | `rustc -C opt-level=3` |"
        $"| Zig | `($tc.zig)` | `zig build-exe -OReleaseFast -lc -fstrip` |"
        $"| Go | `($tc.go)` | `go build` |"
        ""
        "## Methodology"
        ""
        "- **Correctness**: Every language must emit the exact same stdout checksum for each workload before timing is accepted."
        $"- **Timing**: ($data.config.warmup) warmup runs + ($data.config.runs) measured runs via a minimal POSIX `fork`/`exec`/`wait4` + `clock_gettime\(CLOCK_MONOTONIC\)` probe measuring per-process wall time and `ru_maxrss` peak RSS."
        "- **Reproduce**: `nu run.nu` (writes `results/latest.json` and regenerates this `README.md`)."
        ""
        "## Results"
        ""
    ]
    for w in $data.workloads {
        $lines = ($lines | append [
            $"### `($w.id)` — ($w.title) \(`N = ($w.n)` ($w.unit)\)"
            ""
            $"($w.description) Verified checksum: `($w.checksum)`."
            ""
            "| Language | p50 (ms) | p95 (ms) | CoV (%) | Peak RSS (KiB) | Binary (KiB) | Cold Compile (ms) | Throughput |"
            "|---|---:|---:|---:|---:|---:|---:|---:|"
        ])
        for lang in $data.languages {
            let r = ($w.results | get -o $lang)
            if $r != null {
                let p50_s = (fmt_fixed $r.p50_ms 2)
                let p95_s = (fmt_fixed $r.p95_ms 2)
                let cov_s = (fmt_fixed $r.cov_pct 1)
                let bin_s = (fmt_fixed ($r.binary_bytes / 1024.0) 1)
                let cmp_s = (fmt_fixed $r.compile_ms 0)
                let thr_s = (fmt_commas $r.throughput_per_s)
                $lines = ($lines | append $"| **($lang)** | ($p50_s) | ($p95_s) | ($cov_s) | ($r.peak_rss_kb) | ($bin_s) | ($cmp_s) | ($thr_s) ($w.unit)/s |")
            }
        }
        $lines = ($lines | append "")
    }
    ($lines | str join "\n") + "\n"
}

def main [
    --warmup: int = 2
    --runs: int = 7
    --out: string = ""
    --copy-site: string = ""
] {
    let root = ($env.FILE_PWD | path expand)
    let workloads_dir = ($root | path join "workloads")
    let results_dir = ($root | path join "results")
    let out_path = if ($out | str length) > 0 { $out } else { $results_dir | path join "latest.json" }

    let workloads = [
        {
            id: "wasm_numeric_kernel"
            title: "8-Body 3D Kinematics Kernel"
            description: "Unboxed 64-bit integer 8-body 3D kinematics step loop testing tight numeric codegen and register allocation."
            n: 400000
            unit: "steps"
        }
        {
            id: "server_http_router"
            title: "In-Memory HTTP/1.1 Router"
            description: "HTTP/1.1 request line, header, and query parsing, route matching (/health, /items/:id, /users/:id, 404), and response serialization."
            n: 200000
            unit: "requests"
        }
        {
            id: "cli_log_json"
            title: "JSON Log Format & Parse"
            description: "Deterministic JSON log record formatting, RFC 8259 parsing, and checksum aggregation."
            n: 100000
            unit: "records"
        }
        {
            id: "collections_closures_generics"
            title: "Collections, Closures & Generics"
            description: "Batched filter-map, map, higher-order composition, and seeded fold pipelines over structured records."
            n: 800000
            unit: "items"
        }
    ]
    let languages = ["edva", "clang", "rust", "zig", "go"]

    let bins = {
        edva: (find_bin "EDVA" "edva" ["/home/ike/Z/edva/edva"])
        clang: (find_bin "CLANG" "clang")
        rust: (find_bin "RUSTC" "rustc")
        zig: (find_bin "ZIG" "zig")
        go: (find_bin "GO_BIN" "go" ["/nix/store/fkz7zn1a0yiryf9kri2yh1s12k1sv557-go-1.26.10/bin/go"])
    }
    let missing = ($languages | where {|k| ($bins | get $k | str length) == 0 })
    if ($missing | length) > 0 {
        error make { msg: $"ERROR: missing toolchains: ($missing | str join ', ')" }
    }

    let toolchains = {
        edva: (cmd_version $bins.edva "--version")
        clang: (cmd_version $bins.clang "--version")
        rust: (cmd_version $bins.rust "--version")
        zig: $"zig (cmd_version $bins.zig 'version')"
        go: (cmd_version $bins.go "version")
    }
    let ci = (cpu_info)
    let host = ((^hostname | complete).stdout | str trim)
    let os_name = $"((^uname -s | complete).stdout | str trim) ((^uname -r | complete).stdout | str trim)"
    let arch = ((^uname -m | complete).stdout | str trim)

    mkdir $results_dir
    let tmp_dir = ((^mktemp -d /tmp/edva_bench_XXXXXX | complete).stdout | str trim)
    let probe_src = ($tmp_dir | path join "probe.c")
    let probe_bin = ($tmp_dir | path join "probe")
    $PROBE_C | save -f $probe_src
    let pr = (^($bins.clang) -O2 $probe_src -o $probe_bin | complete)
    if $pr.exit_code != 0 {
        rm -rf $tmp_dir
        error make { msg: $"Failed to compile probe.c:\n($pr.stderr)" }
    }

    mut workload_reports = []
    for w in $workloads {
        let wid = $w.id
        let wdir = ($workloads_dir | path join $wid)
        let n = $w.n
        print $"==> Workload: ($wid) \(N=($n)\)"
        mut expected_checksum = ""
        mut lang_results = {}

        for lang in $languages {
            let out_bin = ($tmp_dir | path join $"($wid)_($lang)")
            let cres = (compile_target $lang $wdir $out_bin $bins)

            for _ in 0..<$warmup {
                let wr = (run_probe $probe_bin $out_bin $n)
                if ($expected_checksum | str length) == 0 {
                    $expected_checksum = $wr.stdout
                } else if $wr.stdout != $expected_checksum {
                    rm -rf $tmp_dir
                    error make { msg: $"Checksum mismatch in ($wid) for ($lang): got '($wr.stdout)', expected '($expected_checksum)'" }
                }
            }

            mut samples_ms = []
            mut rss_samples = []
            for _ in 0..<$runs {
                let rr = (run_probe $probe_bin $out_bin $n)
                if $rr.stdout != $expected_checksum {
                    rm -rf $tmp_dir
                    error make { msg: $"Non-deterministic output in ($wid) for ($lang): '($rr.stdout)'" }
                }
                $samples_ms = ($samples_ms | append $rr.ms)
                $rss_samples = ($rss_samples | append $rr.rss_kb)
            }

            let s_sorted = ($samples_ms | sort)
            let p50 = (percentile $s_sorted 0.50)
            let p95 = (percentile $s_sorted 0.95)
            let mean = ($s_sorted | math avg)
            let stddev = if ($s_sorted | length) > 1 { $s_sorted | math stddev -s } else { 0.0 }
            let cov = if $mean > 0.0 { ($stddev / $mean) * 100.0 } else { 0.0 }
            let peak_rss = ($rss_samples | math median | math round | into int)
            let rate = if $p50 > 0.0 { ($n / ($p50 / 1000.0)) } else { 0.0 }

            let entry = {
                compile_ms: $cres.compile_ms
                binary_bytes: $cres.binary_bytes
                min_ms: ((($s_sorted | first) * 1000.0 | math round) / 1000.0)
                p50_ms: (($p50 * 1000.0 | math round) / 1000.0)
                p95_ms: (($p95 * 1000.0 | math round) / 1000.0)
                max_ms: ((($s_sorted | last) * 1000.0 | math round) / 1000.0)
                cov_pct: (($cov * 100.0 | math round) / 100.0)
                peak_rss_kb: $peak_rss
                throughput_per_s: (($rate * 10.0 | math round) / 10.0)
            }
            $lang_results = ($lang_results | insert $lang $entry)
            let lpad = ($lang | fill -a left -w 6)
            print $"    ($lpad) p50=(fmt_fixed $p50 2 | fill -a right -w 6)ms  p95=(fmt_fixed $p95 2 | fill -a right -w 6)ms  rss=($peak_rss | into string | fill -a right -w 6)KiB  bin=(fmt_fixed ($cres.binary_bytes / 1024.0) 1 | fill -a right -w 7)KiB  compile=(fmt_fixed $cres.compile_ms 0 | fill -a right -w 6)ms"
        }

        $workload_reports = ($workload_reports | append {
            id: $wid
            title: $w.title
            description: $w.description
            n: $n
            unit: $w.unit
            checksum: $expected_checksum
            results: $lang_results
        })
    }

    rm -rf $tmp_dir

    let report = {
        generated_at: (date now | date to-timezone utc | format date "%Y-%m-%dT%H:%M:%SZ")
        repo_url: "https://github.com/edva-lang/benchmarks"
        config: { warmup: $warmup, runs: $runs }
        environment: {
            host: $host
            os: $os_name
            arch: $arch
            cpu: $ci.model
            cores: $ci.cores
            memory_mib: $ci.mem_mib
            toolchains: $toolchains
        }
        languages: $languages
        workloads: $workload_reports
    }

    mkdir ($out_path | path dirname)
    ($report | to json --indent 2) + "\n" | save -f $out_path
    render_readme $report | save -f ($root | path join "README.md")
    if ($copy_site | str length) > 0 {
        mkdir ($copy_site | path dirname)
        cp -f $out_path $copy_site
    }
    print $"\nWrote ($out_path) and ($root | path join 'README.md')"
}
