use std::env;

#[derive(Clone, Copy)]
struct Sample {
    id: i64,
    group: i64,
    weight: i64,
    tag: i64,
}

#[derive(Clone, Copy)]
struct Pair {
    a: i64,
    b: i64,
}

#[inline(never)]
fn compose_twice<F, G>(f: F, g: G, x: i64) -> i64
where
    F: Fn(i64) -> i64,
    G: Fn(i64) -> i64,
{
    let y1 = g(f(x));
    g(f(y1))
}

#[inline(never)]
fn run_batch(b_idx: i64) -> (i64, i64, i64) {
    let mut samples = Vec::with_capacity(64);
    for k in 0..64i64 {
        let idx = b_idx * 64 + k;
        samples.push(Sample {
            id: idx,
            group: (idx * 7 + 3) % 8,
            weight: (idx * 31 + 17) % 251 + 1,
            tag: (idx * 13 + 5) % 16,
        });
    }

    let filtered: Vec<Pair> = samples
        .iter()
        .filter(|s| s.group % 2 == 0 || s.tag >= 11)
        .map(|s| Pair {
            a: s.id % 997,
            b: s.weight * (s.group + 1),
        })
        .collect();

    let scale = |x: i64| (x * 3 + 7) % 10007;
    let shift = |x: i64| (x + (b_idx % 97) + 11) % 10007;

    let scores: Vec<i64> = filtered
        .iter()
        .map(|p| compose_twice(scale, shift, p.a + p.b))
        .collect();

    let fold_sum = scores
        .iter()
        .fold(0i64, |acc, &v| (acc * 33 + v) % 1_000_000_007);

    let weighted_sum = filtered
        .iter()
        .fold(0i64, |acc, p| (acc + p.a * 5 + p.b * 3) % 1_000_000_007);

    let heavy_cnt = samples.iter().filter(|s| s.weight > 125).count() as i64;
    let n_filtered = filtered.len() as i64;
    let bonus = if heavy_cnt > 20 {
        heavy_cnt * 19 + n_filtered * 7
    } else {
        13
    };
    let digest = (fold_sum + weighted_sum * 17 + bonus) % 1_000_000_007;
    (digest, n_filtered, heavy_cnt)
}

fn main() {
    let n: i64 = env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .filter(|&v| v > 0)
        .unwrap_or(16000);
    let batches = (n / 64).max(1);
    let mut digest = 0i64;
    let mut kept = 0i64;
    let mut heavy = 0i64;
    for b in 0..batches {
        let (bd, bk, bh) = run_batch(b);
        digest = (digest * 131 + bd) % 1_000_000_007;
        kept += bk;
        heavy += bh;
    }
    println!("pipeline={},kept={},heavy={}", digest, kept, heavy);
}
