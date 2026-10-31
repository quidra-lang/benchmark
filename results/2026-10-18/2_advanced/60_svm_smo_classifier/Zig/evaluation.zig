const std = @import("std");
const c = @import("dataset.zig");
pub fn sign(value: f64) i64 {
    return if (value > 0) 1 else -1;
}
pub const Fold = struct { train: []const usize, test_data: []const usize };
pub fn folds(count: usize, k: usize) []Fold {
    const out = c.alloc(Fold, k);
    for (out, 0..) |*fold, phi| {
        var training: std.ArrayList(usize) = .empty;
        var testing: std.ArrayList(usize) = .empty;
        for (0..count) |i| {
            if (i % k == phi) c.append(usize, &testing, i) else c.append(usize, &training, i);
        }
        fold.* = .{ .train = training.items, .test_data = testing.items };
    }
    return out;
}
pub const Evaluation = struct {
    tp: i64 = 0,
    fp: i64 = 0,
    tn: i64 = 0,
    fn_count: i64 = 0,
    pub fn correct(self: Evaluation) i64 {
        return self.tp + self.tn;
    }
};
pub fn evaluate(data: []const c.Example, values: []const f64) Evaluation {
    var out: Evaluation = .{};
    for (data, values) |example, value| {
        const positive = sign(value) == 1;
        if (example.label == 1) {
            if (positive) out.tp += 1 else out.fn_count += 1;
        } else {
            if (positive) out.fp += 1 else out.tn += 1;
        }
    }
    return out;
}
pub fn auc(data: []const c.Example, values: []const f64) f64 {
    var out: f64 = 0;
    var positive: i64 = 0;
    var negative: i64 = 0;
    for (data) |example| {
        positive += @intFromBool(example.label == 1);
        negative += @intFromBool(example.label == -1);
    }
    for (data, 0..) |first, i| if (first.label == 1) {
        for (data, 0..) |second, j| if (second.label == -1) {
            out += if (values[i] > values[j]) @as(f64, 1) else if (values[i] == values[j]) 0.5 else 0;
        };
    };
    return out / c.f(positive * negative);
}
pub fn real(value: f64, digits: usize) []const u8 {
    const text = switch (digits) {
        4 => c.fmt("{d:.4}", .{value}),
        6 => c.fmt("{d:.6}", .{value}),
        else => unreachable,
    };
    if (text.len > 0 and text[0] == '-') {
        var zero = true;
        for (text[1..]) |ch| {
            if (ch != '0' and ch != '.') zero = false;
        }
        if (zero) return text[1..];
    }
    return text;
}
pub fn ratio(numerator: i64, denominator: i64) []const u8 {
    return if (denominator == 0) "-" else real(c.f(numerator) / c.f(denominator), 4);
}
pub fn confusion(data: []const c.Example, predictions: anytype, rest: bool) [3][3]i64 {
    var out = [_][3]i64{.{ 0, 0, 0 }} ** 3;
    for (data, predictions) |example, prediction| out[c.u(example.label - 1)][c.u((if (rest) prediction.ovr else prediction.ovo) - 1)] += 1;
    return out;
}
pub fn save(io: std.Io, name: []const u8, lines: c.Lines) !void {
    var out: c.Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = c.fmt("output/{s}", .{name}), .data = out.value() });
}
