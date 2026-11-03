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

pub fn bit(index: usize) u16 {
    return @as(u16, 1) << @intCast(index);
}
pub fn indexOf(values: []const []const u8, name: []const u8) ?usize {
    for (values, 0..) |value, i| {
        if (eq(value, name)) return i;
    }
    return null;
}
pub fn nameLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
pub fn uniqueNames(values: []const []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (values) |value| if (indexOf(out.items, value) == null) append([]const u8, &out, value);
    std.mem.sort([]const u8, out.items, {}, nameLess);
    return out.items;
}
fn gcd(a_value: i64, b_value: i64) i64 {
    var a = if (a_value < 0) -a_value else a_value;
    var b = b_value;
    while (b != 0) {
        const next = @mod(a, b);
        a = b;
        b = next;
    }
    return a;
}
pub const Fraction = struct {
    numerator: i64 = 0,
    denominator: i64 = 1,
    pub fn init(n_value: i64, d_value: i64) Fraction {
        const numerator = if (d_value < 0) -n_value else n_value;
        const denominator = if (d_value < 0) -d_value else d_value;
        const divisor = gcd(numerator, denominator);
        return .{ .numerator = @divTrunc(numerator, divisor), .denominator = @divTrunc(denominator, divisor) };
    }
    pub fn add(a: Fraction, b: Fraction) Fraction {
        const divisor = gcd(a.denominator, b.denominator);
        return init(a.numerator * @divTrunc(b.denominator, divisor) + b.numerator * @divTrunc(a.denominator,
             divisor), @divTrunc(a.denominator, divisor) * b.denominator);
    }
    pub fn sub(a: Fraction, b: Fraction) Fraction {
        return a.add(init(-b.numerator, b.denominator));
    }
    pub fn mul(a: Fraction, b: Fraction) Fraction {
        const x = gcd(a.numerator, b.denominator);
        const y = gcd(b.numerator, a.denominator);
        return init(@divTrunc(a.numerator, x) * @divTrunc(b.numerator, y), @divTrunc(a.denominator,
             y) * @divTrunc(b.denominator, x));
    }
    pub fn cmp(a: Fraction, b: Fraction) std.math.Order {
        const left = a.numerator * b.denominator;
        const right = b.numerator * a.denominator;
        return if (left < right) .lt else if (left > right) .gt else .eq;
    }
};
pub const Row = struct { line: usize, case_id: []const u8, activity: []const u8, timestamp: []const u8,
     resource: []const u8 };
pub const Event = struct { row: Row, time: i64 };
pub const Case = struct { id: []const u8, events: std.ArrayList(Event) = .empty, trace: []const usize = &.{},
     duration: i64 = 0 };
pub const Input = struct { rows: []const Row, parameters: [8][]const u8 };
pub fn readInputs(io: std.Io) !Input {
    const rows = try readLines(io, "input/eventlog.csv");
    const values = alloc(Row, rows.len - 1);
    for (rows[1..], values, 2..) |line, *value, number_value| {
        const fields = split(line, ',');
        value.* = .{ .line = number_value, .case_id = fields[0], .activity = fields[1], .timestamp = fields[2],
             .resource = fields[3] };
    }
    var parameters: [8][]const u8 = undefined;
    for (try readLines(io, "input/params.txt"), 0..) |line, i| parameters[i] = words(line)[1];
    return .{ .rows = values, .parameters = parameters };
}
pub fn timestampMinutes(value: []const u8) ?i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const month = number(value[5..7]);
    const day = number(value[8..10]);
    const hour = number(value[11..13]);
    const minute = number(value[14..16]);
    if (month < 1 or month > 12 or day < 1 or day > days[u(month - 1)] or hour > 23 or minute > 59) return null;
    var before: i64 = 0;
    for (days[0..u(month - 1)]) |length| before += length;
    return ((before + day - 1) * 24 + hour) * 60 + minute;
}
fn eventLess(_: void, a: Event, b: Event) bool {
    return if (a.time != b.time) a.time < b.time else a.row.line < b.row.line;
}
fn caseLess(_: void, a: Case, b: Case) bool {
    return nameLess({}, a.id, b.id);
}
pub fn groupCases(events: []const Event) []Case {
    var out: std.ArrayList(Case) = .empty;
    for (events) |event| {
        var found: ?usize = null;
        for (out.items, 0..) |item, i| {
            if (eq(item.id, event.row.case_id)) {
                found = i;
                break;
            }
        }
        if (found == null) {
            found = out.items.len;
            append(Case, &out, .{ .id = event.row.case_id });
        }
        append(Event, &out.items[found.?].events, event);
    }
    std.mem.sort(Case, out.items, {}, caseLess);
    for (out.items) |*item| {
        std.mem.sort(Event, item.events.items, {}, eventLess);
        item.duration = item.events.items[item.events.items.len - 1].time - item.events.items[0].time;
    }
    return out.items;
}
fn valueLess(_: void, a: i64, b: i64) bool {
    return a < b;
}
pub fn median(values: []const i64) Fraction {
    const sorted = dupe(i64, values);
    std.mem.sort(i64, sorted, {}, valueLess);
    const middle = sorted.len / 2;
    return if (sorted.len % 2 == 1) Fraction.init(sorted[middle], 1) else Fraction.init(sorted[middle - 1] + sorted[middle],
         2);
}
