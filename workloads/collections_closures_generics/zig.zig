const std = @import("std");

const Sample = struct {
    id: i64,
    group: i64,
    weight: i64,
    tag: i64,
};

const Pair = struct {
    a: i64,
    b: i64,
};

fn scaleFn(x: i64, _: i64) i64 {
    return @rem(x * 3 + 7, 10007);
}

fn shiftFn(x: i64, b_idx: i64) i64 {
    return @rem(x + @rem(b_idx, 97) + 11, 10007);
}

noinline fn composeTwice(
    f: *const fn (i64, i64) i64,
    g: *const fn (i64, i64) i64,
    b_idx: i64,
    x: i64,
) i64 {
    const y1 = g(f(x, b_idx), b_idx);
    return g(f(y1, b_idx), b_idx);
}

noinline fn runBatch(b_idx: i64) struct { i64, i64, i64 } {
    var samples: [64]Sample = undefined;
    var filtered: [64]Pair = undefined;
    var scores: [64]i64 = undefined;
    var n_filtered: usize = 0;

    for (0..64) |ku| {
        const k: i64 = @intCast(ku);
        const idx = b_idx * 64 + k;
        samples[ku] = .{
            .id = idx,
            .group = @rem(idx * 7 + 3, 8),
            .weight = @rem(idx * 31 + 17, 251) + 1,
            .tag = @rem(idx * 13 + 5, 16),
        };
    }

    for (samples) |s| {
        if (@rem(s.group, 2) == 0 or s.tag >= 11) {
            filtered[n_filtered] = .{
                .a = @rem(s.id, 997),
                .b = s.weight * (s.group + 1),
            };
            n_filtered += 1;
        }
    }

    for (0..n_filtered) |i| {
        scores[i] = composeTwice(&scaleFn, &shiftFn, b_idx, filtered[i].a + filtered[i].b);
    }

    var fold_sum: i64 = 0;
    for (0..n_filtered) |i| {
        fold_sum = @rem(fold_sum * 33 + scores[i], 1000000007);
    }

    var weighted_sum: i64 = 0;
    for (0..n_filtered) |i| {
        weighted_sum = @rem(weighted_sum + filtered[i].a * 5 + filtered[i].b * 3, 1000000007);
    }

    var heavy_cnt: i64 = 0;
    for (samples) |s| {
        if (s.weight > 125) heavy_cnt += 1;
    }

    const nf: i64 = @intCast(n_filtered);
    const bonus: i64 = if (heavy_cnt > 20) heavy_cnt * 19 + nf * 7 else 13;
    const digest = @rem(fold_sum + weighted_sum * 17 + bonus, 1000000007);
    return .{ digest, nf, heavy_cnt };
}

pub fn main(init: std.process.Init) !void {
    var n: i64 = 16000;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    if (args.next()) |arg| {
        if (std.fmt.parseInt(i64, arg, 10)) |parsed| {
            if (parsed > 0) n = parsed;
        } else |_| {}
    }

    const batches_raw = @divTrunc(n, 64);
    const batches: i64 = if (batches_raw > 0) batches_raw else 1;
    var digest: i64 = 0;
    var kept: i64 = 0;
    var heavy: i64 = 0;
    var b: i64 = 0;
    while (b < batches) : (b += 1) {
        const res = runBatch(b);
        digest = @rem(digest * 131 + res[0], 1000000007);
        kept += res[1];
        heavy += res[2];
    }

    var out_buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buf);
    try stdout.interface.print("pipeline={d},kept={d},heavy={d}\n", .{ digest, kept, heavy });
    try stdout.interface.flush();
}
