const std = @import("std");
const d = @import("image_io.zig");
const color = @import("color.zig");
pub const Position = struct { u: usize, v: usize };
pub fn zigzagOrder() [64]Position {
    var out: [64]Position = undefined;
    var index: usize = 0;
    for (0..15) |sum| {
        if (sum % 2 == 1) {
            for (0..8) |u| {
                if (sum >= u and sum - u < 8) {
                    out[index] = .{ .u = u, .v = sum - u };
                    index += 1;
                }
            }
        } else {
            var u: usize = 8;
            while (u > 0) {
                u -= 1;
                if (sum >= u and sum - u < 8) {
                    out[index] = .{ .u = u, .v = sum - u };
                    index += 1;
                }
            }
        }
    }
    return out;
}
fn rnd(value: i64, shift: u6) i64 {
    return @divFloor(value + (@as(i64, 1) << (shift - 1)), @as(i64, 1) << shift);
}
pub fn forward(block: d.Matrix, transform: d.Matrix) d.Matrix {
    var temporary: d.Matrix = std.mem.zeroes(d.Matrix);
    var out: d.Matrix = std.mem.zeroes(d.Matrix);
    for (0..8) |u| for (0..8) |x| {
        var sum: i64 = 0;
        for (0..8) |y| sum += transform[u][y] * (block[y][x] - 128);
        temporary[u][x] = rnd(sum, 11);
    };
    for (0..8) |u| for (0..8) |v| {
        var sum: i64 = 0;
        for (0..8) |x| sum += temporary[u][x] * transform[v][x];
        out[u][v] = rnd(sum, 15);
    };
    return out;
}
pub fn inverse(coefficients: d.Matrix, transform: d.Matrix) d.Matrix {
    var temporary: d.Matrix = std.mem.zeroes(d.Matrix);
    var out: d.Matrix = std.mem.zeroes(d.Matrix);
    for (0..8) |y| for (0..8) |v| {
        var sum: i64 = 0;
        for (0..8) |u| sum += transform[u][y] * coefficients[u][v];
        temporary[y][v] = rnd(sum, 11);
    };
    for (0..8) |y| for (0..8) |x| {
        var sum: i64 = 0;
        for (0..8) |v| sum += temporary[y][v] * transform[v][x];
        out[y][x] = color.clamp(rnd(sum, 15) + 128);
    };
    return out;
}
pub fn quantizationTables(basic: [2]d.Matrix, quality: usize) d.Quantization {
    const scale: i64 = if (quality < 50) @divTrunc(5000, d.n(quality)) else 200 - 2 * d.n(quality);
    var out: d.Quantization = [_]?d.Matrix{null} ** 4;
    for (0..2) |t| {
        var table: d.Matrix = undefined;
        for (0..8) |u| for (0..8) |v| {
            table[u][v] = @min(@max(@divTrunc(basic[t][u][v] * scale + 50, 100), 1), 255);
        };
        out[t] = table;
    }
    return out;
}
pub fn quantize(values: d.Matrix, table: d.Matrix) d.Matrix {
    var out: d.Matrix = undefined;
    for (0..8) |u| for (0..8) |v| {
        const magnitude = @divTrunc(@as(i64, @intCast(@abs(values[u][v]))) + @divTrunc(table[u][v], 2), table[u][v]);
        out[u][v] = if (values[u][v] >= 0) magnitude else -magnitude;
    };
    return out;
}
pub fn zigzag(values: d.Matrix) d.Sequence {
    var out: d.Sequence = undefined;
    for (zigzagOrder(), 0..) |position, k| out[k] = values[position.u][position.v];
    return out;
}
pub fn dequantize(sequence: d.Sequence, table: d.Matrix, keep: usize) d.Matrix {
    var out: d.Matrix = std.mem.zeroes(d.Matrix);
    const order = zigzagOrder();
    for (0..keep) |k| {
        const position = order[k];
        out[position.u][position.v] = sequence[k] * table[position.u][position.v];
    }
    return out;
}
