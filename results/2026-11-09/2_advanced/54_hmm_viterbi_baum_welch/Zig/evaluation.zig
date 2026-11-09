const std = @import("std");
const c = @import("model_io.zig");
pub fn fraction(source_numerator: i64, source_denominator: i64) []const u8 {
    if (source_denominator == 0) return "-";
    const numerator = if (source_denominator < 0) -source_numerator else source_numerator;
    const denominator = if (source_denominator < 0) -source_denominator else source_denominator;
    var a = if (numerator < 0) -numerator else numerator;
    var b = denominator;
    while (b != 0) {
        const remainder = @mod(a, b);
        a = b;
        b = remainder;
    }
    return c.fmt("{d}/{d}", .{ @divExact(numerator, a), @divExact(denominator, a) });
}
pub fn accumulate(matrix: *c.Confusion, truth: c.Path, predicted: c.Path) void {
    for (truth, predicted) |actual, prediction| matrix[actual][prediction] += 1;
}
pub fn correct(truth: c.Path, predicted: c.Path) i64 {
    var out: i64 = 0;
    for (truth, predicted) |actual, prediction| out += @intFromBool(actual == prediction);
    return out;
}
fn padded(value: []const u8, width: usize) []const u8 {
    const spaces = c.alloc(u8, width - value.len);
    @memset(spaces, ' ');
    return c.fmt("{s}{s}", .{ spaces, value });
}
pub fn matrixLines(model: c.Model, matrix: c.Confusion) c.Lines {
    var width: usize = 1;
    for (0..model.k()) |i| for (0..model.k()) |j| {
        width = @max(width, c.fmt("{d}", .{matrix[i][j]}).len);
    };
    var out: c.Lines = .{};
    var header: c.Text = .{};
    header.add(" ", .{});
    for (model.states) |state| header.add(" {s}", .{padded(&.{state}, width)});
    out.add("{s}", .{header.value()});
    for (model.states, 0..) |state, i| {
        var row: c.Text = .{};
        row.add("{c}", .{state});
        for (matrix[i][0..model.k()]) |value| row.add(" {s}", .{padded(c.fmt("{d}", .{value}), width)});
        out.add("{s}", .{row.value()});
    }
    return out;
}
pub fn metricLines(model: c.Model, matrix: c.Confusion) c.Lines {
    var rows = [_]i64{0} ** 4;
    var columns = [_]i64{0} ** 4;
    var total: i64 = 0;
    var correct_count: i64 = 0;
    var expected: i64 = 0;
    for (0..model.k()) |i| for (0..model.k()) |j| {
        rows[i] += matrix[i][j];
        columns[j] += matrix[i][j];
    };
    for (0..model.k()) |i| {
        total += rows[i];
        correct_count += matrix[i][i];
        expected += rows[i] * columns[i];
    }
    var out: c.Lines = .{};
    out.add("ACCURACY {s}", .{fraction(correct_count, total)});
    out.add("KAPPA {s}", .{fraction(total * correct_count - expected, total * total - expected)});
    for (model.states, 0..) |state, i| out.add("STATE {c} precision {s} recall {s} f1 {s}", .{ state,
         fraction(matrix[i][i], columns[i]), fraction(matrix[i][i], rows[i]), fraction(2 * matrix[i][i],
         columns[i] + rows[i]) });
    return out;
}
pub const Run = struct { state: usize, start: usize, end: usize };
pub const Region = struct {
    start: usize,
    end: usize,
    pub fn length(self: Region) usize {
        return self.end - self.start + 1;
    }
};
pub const MatchCounts = struct { predicted: i64 = 0, truth: i64 = 0, matched_predicted: i64 = 0, matched_truth: i64 = 0 };
pub fn runs(path: c.Path) []const Run {
    var out: std.ArrayList(Run) = .empty;
    if (path.len == 0) return out.items;
    var start: usize = 1;
    var state = path[0];
    for (path[1..], 1..) |value, t| if (value != state) {
        c.append(Run, &out, .{ .state = state, .start = start, .end = t });
        start = t + 1;
        state = value;
    };
    c.append(Run, &out, .{ .state = state, .start = start, .end = path.len });
    return out.items;
}
pub fn regionCounts(predicted: []const Region, truth: []const Region) MatchCounts {
    var out: MatchCounts = .{ .predicted = c.n(predicted.len), .truth = c.n(truth.len) };
    for (predicted) |first| for (truth) |second| {
        if (first.start <= second.end and second.start <= first.end) {
            out.matched_predicted += 1;
            break;
        }
    };
    for (truth) |first| for (predicted) |second| {
        if (first.start <= second.end and second.start <= first.end) {
            out.matched_truth += 1;
            break;
        }
    };
    return out;
}
pub fn boundaryCounts(predicted: c.Path, truth: c.Path, tolerance: usize) MatchCounts {
    var a: std.ArrayList(usize) = .empty;
    var b: std.ArrayList(usize) = .empty;
    for (predicted[1..], 1..) |value, i| if (value != predicted[i - 1]) c.append(usize, &a, i + 1);
    for (truth[1..], 1..) |value, i| if (value != truth[i - 1]) c.append(usize, &b, i + 1);
    var out: MatchCounts = .{ .predicted = c.n(a.items.len), .truth = c.n(b.items.len) };
    for (a.items) |first| for (b.items) |second| {
        const difference = if (first >= second) first - second else second - first;
        if (difference <= tolerance) {
            out.matched_predicted += 1;
            break;
        }
    };
    for (b.items) |first| for (a.items) |second| {
        const difference = if (first >= second) first - second else second - first;
        if (difference <= tolerance) {
            out.matched_truth += 1;
            break;
        }
    };
    return out;
}
