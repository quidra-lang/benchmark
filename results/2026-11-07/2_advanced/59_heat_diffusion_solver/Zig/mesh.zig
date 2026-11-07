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
pub const CellFace = struct { point: usize, direction: usize };
pub const Mesh = struct {
    width: usize,
    height: usize,
    count: usize,
    dx: f64,
    thickness: f64,
    codes: []const u8,
    neighbors: [][4]?usize,
    pub fn cell(self: Mesh, row: usize, column: usize) usize {
        return row * self.width + column;
    }
    pub fn coordinates(self: Mesh, point: usize) []const u8 {
        return fmt("{d} {d}", .{ point / self.width, point % self.width });
    }
    pub fn segmentFaces(self: Mesh, edge: []const u8, start: usize, end: usize) []const CellFace {
        var out: std.ArrayList(CellFace) = .empty;
        const direction: usize = if (eq(edge, "left")) 0 else if (eq(edge, "right")) 1 else if (eq(edge,
             "top")) 2 else 3;
        for (start..end + 1) |i| {
            const point = if (direction == 0) self.cell(i, 0) else if (direction == 1) self.cell(i,
                 self.width - 1) else if (direction == 2) self.cell(0, i) else self.cell(self.height - 1,
                 i);
            append(CellFace, &out, .{ .point = point, .direction = direction });
        }
        return out.items;
    }
    pub fn sourceCells(self: Mesh, r1: usize, c1: usize, r2: usize, c2: usize) []const usize {
        var out: std.ArrayList(usize) = .empty;
        for (r1..r2 + 1) |row| for (c1..c2 + 1) |column| append(usize, &out, self.cell(row, column));
        return out.items;
    }
};
pub fn load(io: std.Io) !Mesh {
    const lines = try readLines(io, "input/plate.txt");
    const header = words(lines[0]);
    const width = u(number(header[0]));
    const height = u(number(header[1]));
    const count = width * height;
    const codes = alloc(u8, count);
    for (lines[1..], 0..) |row, i| @memcpy(codes[i * width .. (i + 1) * width], row);
    const neighbors = alloc([4]?usize, count);
    for (0..height) |row| for (0..width) |column| {
        const point = row * width + column;
        neighbors[point] = .{ if (column > 0) point - 1 else null, if (column + 1 < width) point + 1 else null,
             if (row > 0) point - width else null, if (row + 1 < height) point + width else null };
    };
    return .{ .width = width, .height = height, .count = count, .dx = real(header[2]), .thickness = real(header[3]),
         .codes = codes, .neighbors = neighbors };
}
pub const Material = struct { code: u8, name: []const u8, k: f64, rho: f64, cp: f64 };
pub const Face = struct { neighbor: ?usize = null, g: f64 = 0, theta: ?f64 = null };
pub const Segment = struct { name: []const u8, edge: []const u8, kind: []const u8, faces: []const CellFace,
     coefficient: f64 = 0, theta: f64 = 0 };
pub const Interval = struct { on: i64, off: i64 };
pub const Source = struct { name: []const u8, cells: []const usize, power: f64, intervals: []const Interval };
pub const System = struct { mesh: Mesh, materials: []const Material, segments: []const Segment,
     sources: []const Source, faces: [][4]Face, cell_material: []usize, material_cells: []std.ArrayList(usize),
     capacity: []f64, diagonal: []f64, beta: []f64, source_all: []f64, total_power: f64 = 0,
     dt_max: f64 = 0 };
