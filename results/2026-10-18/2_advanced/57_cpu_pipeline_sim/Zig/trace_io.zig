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
pub const Class = enum { alu, multiply, load, store, branch, jump, nop };
pub const classes = [_][]const u8{ "ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP" };
pub const causes = [_][]const u8{ "control", "structural", "load_use", "raw" };
pub const miss_names = [_][]const u8{ "direction", "btb_miss", "wrong_target" };
pub const stages = [_][]const u8{ "IF", "ID", "EX", "MEM", "WB" };
pub const Instruction = struct {
    pc: i64 = 0,
    target: i64 = 0,
    address: i64 = 0,
    next: i64 = 0,
    kind: Class = .alu,
    rd: i64 = -1,
    rs1: i64 = -1,
    rs2: i64 = -1,
    line: usize = 0,
    static_id: usize = 0,
    taken: bool = false,
    pub fn control(self: Instruction) bool {
        return self.kind == .branch or self.kind == .jump;
    }
};
pub const Predictor = struct { name: []const u8, scheme: []const u8, parameters: [4]usize = .{ 0, 0, 0, 0 } };
pub const Variant = struct { name: []const u8, forwarding: bool, id: bool, latency: i64 };
pub const Config = struct { btb: usize = 0, ras: usize = 0, start: i64 = 0, end: i64 = 0, top: usize = 0, interval: usize = 0, predictors: std.ArrayList(Predictor) = .empty, variants: std.ArrayList(Variant) = .empty, primary_variant: []const u8 = "", primary_predictor: []const u8 = "" };
pub const Input = struct { trace: []const []const u8, config: Config };
pub fn parseHex(value: []const u8) ?i64 {
    if (value.len != 8) return null;
    var out: i64 = 0;
    for (value) |ch| {
        if (!((ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f'))) return null;
        out = 16 * out + (if (ch <= '9') @as(i64, ch - '0') else @as(i64, ch - 'a' + 10));
    }
    return out;
}
pub fn parseRegister(value: []const u8) i64 {
    if (eq(value, "-")) return -1;
    if (value.len < 2 or value.len > 3 or value[0] != 'r' or (value.len == 3 and value[1] == '0')) return -2;
    var out: i64 = 0;
    for (value[1..]) |ch| {
        if (ch < '0' or ch > '9') return -2;
        out = 10 * out + ch - '0';
    }
    return if (out <= 31) out else -2;
}
pub fn load(io: std.Io) !Input {
    var config: Config = .{};
    for (try readLines(io, "input/config.txt")) |line| {
        const row = words(line);
        const key = row[0];
        if (eq(key, "BTB")) config.btb = u(number(row[1])) else if (eq(key, "RAS")) config.ras = u(number(row[1])) else if (eq(key, "PREDICTOR")) {
            var p: Predictor = .{ .name = row[1], .scheme = row[2] };
            for (row[3..], 0..) |field, i| p.parameters[i] = u(number(field));
            append(Predictor, &config.predictors, p);
        } else if (eq(key, "VARIANT")) append(Variant, &config.variants, .{ .name = row[1], .forwarding = eq(row[2], "ON"), .id = eq(row[3], "ID"), .latency = number(row[4]) }) else if (eq(key, "PRIMARY")) {
            config.primary_variant = row[1];
            config.primary_predictor = row[2];
        } else if (eq(key, "WINDOW")) {
            config.start = number(row[1]);
            config.end = number(row[2]);
        } else if (eq(key, "TOP")) config.top = u(number(row[1])) else if (eq(key, "INTERVAL")) config.interval = u(number(row[1]));
    }
    return .{ .trace = try readLines(io, "input/trace.txt"), .config = config };
}
