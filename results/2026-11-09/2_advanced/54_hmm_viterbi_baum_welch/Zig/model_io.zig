const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const out = allocator.create(T) catch @panic("allocation failed");
    out.* = value;
    return out;
}
pub fn dupe(comptime T: type, values: []const T) []T {
    return allocator.dupe(T, values) catch @panic("allocation failed");
}
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(allocator, value) catch @panic("allocation failed");
}
pub fn fmt(comptime pattern: []const u8, args: anytype) []const u8 {
    return std.fmt.allocPrint(allocator, pattern, args) catch @panic("allocation failed");
}
pub fn n(value: anytype) i64 {
    return @intCast(value);
}
pub fn u(value: i64) usize {
    return @intCast(value);
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn number(value: []const u8) i64 {
    return std.fmt.parseInt(i64, value, 10) catch unreachable;
}
pub fn split(value: []const u8, delimiter: u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, value, delimiter);
    while (fields.next()) |field| append([]const u8, &out, field);
    return out.items;
}
pub fn words(value: []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (split(value, ' ')) |field| if (field.len > 0) append([]const u8, &out, field);
    return out.items;
}
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn add(self: *Text, comptime pattern: []const u8, args: anytype) void {
        self.data.appendSlice(allocator, fmt(pattern, args)) catch @panic("allocation failed");
    }
    pub fn value(self: Text) []const u8 {
        return self.data.items;
    }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn add(self: *Lines, comptime pattern: []const u8, args: anytype) void {
        append([]const u8, &self.data, fmt(pattern, args));
    }
    pub fn extend(self: *Lines, lines: Lines) void {
        for (lines.data.items) |line| self.add("{s}", .{line});
    }
};
pub fn readLines(io: std.Io, path: []const u8) ![]const []const u8 {
    const value = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    const lines = split(value, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn f(value: anytype) f64 {
    return @floatFromInt(value);
}
pub fn real(value: []const u8) f64 {
    return std.fmt.parseFloat(f64, value) catch unreachable;
}
pub var backing_allocator: std.mem.Allocator = undefined;
pub const Observation = []const i64;
pub const Path = []const usize;
pub const StateValues = [4]f64;
pub const Matrix = [4][4]f64;
pub const Emissions = [4][8]f64;
pub const Confusion = [4][4]i64;
pub const Model = struct {
    name: []const u8,
    states: []const u8,
    symbols: []const u8,
    missing: u8,
    initial: StateValues = .{ 0, 0, 0, 0 },
    transition: Matrix = [_][4]f64{.{ 0, 0, 0, 0 }} ** 4,
    emission: Emissions = [_][8]f64{.{ 0, 0, 0, 0, 0, 0, 0, 0 }} ** 4,
    pub fn k(self: Model) usize {
        return self.states.len;
    }
    pub fn m(self: Model) usize {
        return self.symbols.len;
    }
};
pub const Rows = []const []const []const u8;
pub const Input = struct { model: Model, sequences: Rows, labeled: Rows, parameters: Rows };
pub const Sequence = struct { name: []const u8, role: []const u8 = "", observation: Observation = &.{}, truth: Path = &.{} };
pub const Params = struct { iterations: usize, folds: usize, min_length: usize, max_missing: usize,
     segment_state: usize, merge_gap: usize, min_segment: usize, first_motif: i64, second_motif: i64,
     min_rich: i64, min_motif: i64, boundary_tolerance: usize, posterior_samples: usize, sample_count: usize,
     sample_length: usize, posterior_seed: i64, sample_seed: i64, pseudocount: f64, confidence: f64,
     smoothing: []const f64, candidates: []const []const u8, rich: Observation };
pub const Pair = struct { observation: Observation, path: Path };
fn readRows(io: std.Io, name: []const u8) !Rows {
    const lines = try readLines(io, fmt("input/{s}", .{name}));
    const out = alloc([]const []const u8, lines.len);
    for (lines, out) |line, *row| row.* = words(line);
    return out;
}
pub fn normalize(values: []f64) void {
    var sum: f64 = 0;
    for (values) |value| sum += value;
    for (values) |*value| value.* /= sum;
}
pub fn load(io: std.Io) !Input {
    const rows = try readRows(io, "model.txt");
    const states = alloc(u8, rows[0].len - 1);
    for (rows[0][1..], states) |field, *state| state.* = field[0];
    const symbols = alloc(u8, rows[1].len - 1);
    for (rows[1][1..], symbols) |field, *symbol| symbol.* = field[0];
    var model: Model = .{ .name = "INITIAL", .states = states, .symbols = symbols, .missing = rows[2][1][0] };
    for (0..model.k()) |i| model.initial[i] = real(rows[3][i + 1]);
    normalize(model.initial[0..model.k()]);
    for (0..model.k()) |i| {
        for (0..model.k()) |j| model.transition[i][j] = real(rows[4 + i][j + 2]);
        normalize(model.transition[i][0..model.k()]);
        for (0..model.m()) |j| model.emission[i][j] = real(rows[4 + model.k() + i][j + 2]);
        normalize(model.emission[i][0..model.m()]);
    }
    return .{ .model = model, .sequences = try readRows(io, "sequences.txt"), .labeled = try readRows(io,
         "labeled.txt"), .parameters = try readRows(io, "params.txt") };
}
pub fn decimal(value: f64, places: usize) []const u8 {
    var factor: i64 = 1;
    for (0..places) |_| factor *= 10;
    const amount: i64 = @intFromFloat(@floor(@abs(value) * f(factor) + 0.5));
    const tail = fmt("{d}", .{@mod(amount, factor)});
    const zeroes = alloc(u8, places - tail.len);
    @memset(zeroes, '0');
    return fmt("{s}{d}.{s}{s}", .{ if (value < 0 and amount != 0) "-" else "", @divTrunc(amount, factor), zeroes, tail });
}
pub fn modelLines(model: Model) Lines {
    var out: Lines = .{};
    out.add("MODEL {s}", .{model.name});
    var states: Text = .{};
    states.add("STATES", .{});
    for (model.states) |state| states.add(" {c}", .{state});
    out.add("{s}", .{states.value()});
    var symbols: Text = .{};
    symbols.add("SYMBOLS", .{});
    for (model.symbols) |symbol| symbols.add(" {c}", .{symbol});
    out.add("{s}", .{symbols.value()});
    out.add("MISSING {c}", .{model.missing});
    var initial: Text = .{};
    initial.add("INITIAL", .{});
    for (model.initial[0..model.k()]) |value| initial.add(" {s}", .{decimal(value, 4)});
    out.add("{s}", .{initial.value()});
    for (model.states, 0..) |state, i| {
        var row: Text = .{};
        row.add("TRANSITION {c}", .{state});
        for (model.transition[i][0..model.k()]) |value| row.add(" {s}", .{decimal(value, 4)});
        out.add("{s}", .{row.value()});
    }
    for (model.states, 0..) |state, i| {
        var row: Text = .{};
        row.add("EMISSION {c}", .{state});
        for (model.emission[i][0..model.m()]) |value| row.add(" {s}", .{decimal(value, 4)});
        out.add("{s}", .{row.value()});
    }
    return out;
}
pub fn save(io: std.Io, name: []const u8, lines: Lines) !void {
    var text_value: Text = .{};
    for (lines.data.items) |line| text_value.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text_value.value() });
}
