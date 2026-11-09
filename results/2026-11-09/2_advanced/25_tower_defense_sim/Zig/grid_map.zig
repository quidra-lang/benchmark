const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(text: []const u8) i64 { return std.fmt.parseInt(i64, text, 10) catch unreachable; }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn splitFields(text: []const u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.tokenizeScalar(u8, text, ' ');
    while (iterator.next()) |field| append([]const u8, &result, field);
    return result.items;
}
pub fn lines(text: []const u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| append([]const u8, &result, line);
    result.items.len -= 1;
    return result.items;
}
pub const Point = struct {
    x: i64 = 0,
    y: i64 = 0,
    pub fn same(self: Point, other: Point) bool { return self.x == other.x and self.y == other.y; }
};
pub const Cell = Point;
pub fn cellCenter(cell: Cell) Point { return .{ .x = 100 * cell.x, .y = 100 * cell.y }; }
pub const Targets = enum { ground, air, both };
pub fn parseTargets(text: []const u8) Targets {
    return if (eq(text, "ground")) .ground else if (eq(text, "air")) .air else .both;
}
pub const GridMap = struct {
    width: usize,
    height: usize,
    rows: []const []const u8,
    exit: Cell,
    spawns: []Cell,

    pub fn read(io: std.Io) !GridMap {
        const source = lines(try std.Io.Dir.cwd().readFileAlloc(io, "input/map.txt", allocator, .unlimited));
        const dimensions = splitFields(source[0]);
        const width = u(number(dimensions[0]));
        const height = u(number(dimensions[1]));
        var exit: Cell = .{};
        var found: [9]Cell = undefined;
        var count: usize = 0;
        for (source[1 .. height + 1], 0..) |row, y| {
            for (row, 0..) |terrain_code, x| {
                const cell: Cell = .{ .x = n(x), .y = n(y) };
                if (terrain_code >= '1' and terrain_code <= '9') {
                    found[terrain_code - '1'] = cell;
                    count += 1;
                } else if (terrain_code == 'E') exit = cell;
            }
        }
        const spawns = alloc(Cell, count);
        @memcpy(spawns, found[0..count]);
        return .{ .width = width, .height = height, .rows = source[1 .. height + 1], .exit = exit, .spawns = spawns };
    }
    pub fn inside(self: GridMap, cell: Cell) bool { return cell.x >= 0 and cell.y >= 0 and cell.x < n(self.width) and cell.y < n(self.height); }
    pub fn index(self: GridMap, cell: Cell) usize { return u(cell.y) * self.width + u(cell.x); }
    pub fn terrain(self: GridMap, cell: Cell) u8 { return self.rows[u(cell.y)][u(cell.x)]; }
    pub fn rock(self: GridMap, cell: Cell) bool { return self.terrain(cell) == '#'; }
    pub fn water(self: GridMap, cell: Cell) bool { return self.terrain(cell) == '~'; }
    pub fn buildable(self: GridMap, cell: Cell) bool { return self.terrain(cell) == '.'; }
};
