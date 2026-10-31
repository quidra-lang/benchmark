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

pub const Names = []const []const u8;
pub fn join(values: Names, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, values) catch @panic("allocation failed");
}
pub fn writeLines(io: std.Io, filename: []const u8, lines: Lines) !void {
    try std.Io.Dir.cwd().createDirPath(io, "output");
    var out: Text = .{};
    for (lines.data.items) |line| out.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{filename}), .data = out.value() });
}

pub fn indexOf(items: anytype, name: []const u8) usize {
    for (items, 0..) |item, i| if (eq(item.name, name)) return i;
    unreachable;
}
pub fn findIndex(items: anytype, name: []const u8) ?usize {
    for (items, 0..) |item, i| if (eq(item.name, name)) return i;
    return null;
}
pub fn bit(index: usize) u64 {
    return @as(u64, 1) << @intCast(index);
}
pub const Direction = enum { up, down };
pub const direction_names = [_][]const u8{ "UP", "DOWN" };
pub const Aspect = enum { red, yellow, green };
pub const aspect_names = [_][]const u8{ "RED", "YELLOW", "GREEN" };
pub const Beyond = struct { kind: enum { section, point, buffer, boundary, impassable }, index: usize = 0 };
pub const Section = struct { name: []const u8, length: i64, row: usize, first: usize, last: usize,
     failed: bool = false, occupants: u32 = 0, route_lock: ?usize = null, overlap_locks: u64 = 0,
     occupied_seconds: i64 = 0, locked_seconds: i64 = 0, trains: u32 = 0 };
pub const Point = struct {
    name: []const u8,
    side: u8,
    common: usize,
    normal: usize,
    reverse: usize,
    row: usize,
    column: usize,
    position: u8 = 'N',
    target: u8 = 'N',
    moving: bool = false,
    failed: bool = false,
    completion: ?i64 = null,
    normal_locks: u64 = 0,
    reverse_locks: u64 = 0,
    throws: i64 = 0,
    locked_seconds: i64 = 0,
    moving_seconds: i64 = 0,
    pub fn detected(self: Point) bool {
        return !self.moving and !self.failed;
    }
    pub fn locks(self: Point) u64 {
        return self.normal_locks | self.reverse_locks;
    }
};
pub const Signal = struct { name: []const u8, section: usize, direction: Direction, row: usize,
     column: usize, aspect: Aspect = .red, seconds: [3]i64 = @splat(0), passes: i64 = 0 };
pub const Buffer = struct { name: []const u8, section: usize, end: u8, row: usize, column: usize };
pub const Boundary = struct { name: []const u8, section: usize, end: u8 };
pub const Label = struct { row: usize, column: usize, text: []const u8 };
pub const Layout = struct {
    sections: []Section,
    points: []Point,
    signals: []Signal,
    buffers: []const Buffer,
    boundaries: []const Boundary,
    labels: []const Label,
    ends: [40][2]Beyond,
    pub fn occupied(self: *const Layout, section: usize) bool {
        return self.sections[section].failed or self.sections[section].occupants != 0;
    }
    pub fn signalAt(self: *const Layout, section: usize, direction: Direction) ?usize {
        for (self.signals, 0..) |signal, i| if (signal.section == section and signal.direction == direction) return i;
        return null;
    }
    pub fn beyond(self: *const Layout, section: usize, direction: Direction) Beyond {
        const end = self.ends[section][if (direction == .up) @as(usize, 1) else 0];
        if (end.kind != .point) return end;
        const point = self.points[end.index];
        const branch = if (point.position == 'N') point.normal else point.reverse;
        if (point.moving or (section != point.common and section != branch)) return .{ .kind = .impassable };
        return .{ .kind = .section, .index = if (section == point.common) branch else point.common };
    }
};
fn endIndex(end: u8) usize {
    return if (end == 'L') 0 else 1;
}
pub fn read(io: std.Io) !Layout {
    const lines = try readLines(io, "input/layout.txt");
    var sections: std.ArrayList(Section) = .empty;
    var points: std.ArrayList(Point) = .empty;
    var signals: std.ArrayList(Signal) = .empty;
    var buffers: std.ArrayList(Buffer) = .empty;
    var boundaries: std.ArrayList(Boundary) = .empty;
    var labels: std.ArrayList(Label) = .empty;
    var ends: [40][2]Beyond = @splat(@splat(.{ .kind = .impassable }));
    for (lines) |line| {
        const f = words(line);
        if (eq(f[0], "SECTION")) append(Section, &sections, .{ .name = f[1], .length = number(f[2]),
             .row = u(number(f[3])), .first = u(number(f[4])), .last = u(number(f[5])) }) else if (eq(f[0],
             "JOINT")) {
            const first = indexOf(sections.items, f[1]);
            const second = indexOf(sections.items, f[2]);
            ends[first][1] = .{ .kind = .section, .index = second };
            ends[second][0] = .{ .kind = .section, .index = first };
        } else if (eq(f[0], "POINT")) {
            const point: Point = .{ .name = f[1], .side = f[2][0], .common = indexOf(sections.items,
                 f[3]), .normal = indexOf(sections.items, f[4]), .reverse = indexOf(sections.items,
                 f[5]), .row = u(number(f[6])), .column = u(number(f[7])) };
            const connection: Beyond = .{ .kind = .point, .index = points.items.len };
            ends[point.common][endIndex(point.side)] = connection;
            ends[point.normal][1 - endIndex(point.side)] = connection;
            ends[point.reverse][1 - endIndex(point.side)] = connection;
            append(Point, &points, point);
        } else if (eq(f[0], "SIGNAL")) append(Signal, &signals, .{ .name = f[1], .section = indexOf(sections.items,
             f[2]), .direction = if (eq(f[3], "UP")) .up else .down, .row = u(number(f[4])),
             .column = u(number(f[5])) }) else if (eq(f[0], "BUFFER")) {
            const section = indexOf(sections.items, f[2]);
            ends[section][endIndex(f[3][0])] = .{ .kind = .buffer, .index = buffers.items.len };
            append(Buffer, &buffers, .{ .name = f[1], .section = section, .end = f[3][0], .row = u(number(f[4])),
                 .column = u(number(f[5])) });
        } else if (eq(f[0], "BOUNDARY")) {
            const section = indexOf(sections.items, f[2]);
            ends[section][endIndex(f[3][0])] = .{ .kind = .boundary, .index = boundaries.items.len };
            append(Boundary, &boundaries, .{ .name = f[1], .section = section, .end = f[3][0] });
        } else append(Label, &labels, .{ .row = u(number(f[1])), .column = u(number(f[2])), .text = f[3] });
    }
    return .{ .sections = sections.items, .points = points.items, .signals = signals.items,
         .buffers = buffers.items, .boundaries = boundaries.items, .labels = labels.items,
         .ends = ends };
}
