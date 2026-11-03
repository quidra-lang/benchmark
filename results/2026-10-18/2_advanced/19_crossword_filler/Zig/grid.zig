const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub const Strings = []const []const u8;
pub fn alloc(comptime T: type, count: usize) []T { return allocator.alloc(T, count) catch @panic("allocation failed"); }
pub fn append(comptime T: type, list: *std.ArrayList(T), value: T) void { list.append(allocator, value) catch @panic("allocation failed"); }
pub fn fmt(comptime pattern: []const u8, arguments: anytype) []const u8 { return std.fmt.allocPrint(allocator, pattern, arguments) catch @panic("allocation failed"); }
pub fn eq(first: []const u8, second: []const u8) bool { return std.mem.eql(u8, first, second); }
pub fn number(source: []const u8) usize { return std.fmt.parseInt(usize, source, 10) catch unreachable; }
pub fn n(value: anytype) i64 { return @intCast(value); }
pub fn u(value: i64) usize { return @intCast(value); }
pub fn split(source: []const u8, separator: u8) Strings {
    var result: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, source, separator);
    while (iterator.next()) |part| append([]const u8, &result, part);
    return result.items;
}
pub fn lines(source: []const u8) Strings { const result = split(source, '\n'); return result[0 .. result.len - 1]; }
pub const Text = struct {
    data: std.ArrayList(u8) = .empty,
    pub fn write(self: *Text, source: []const u8) void { self.data.appendSlice(allocator, source) catch @panic("allocation failed"); }
    pub fn add(self: *Text, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn value(self: Text) []const u8 { return self.data.items; }
};
pub const Lines = struct {
    data: std.ArrayList([]const u8) = .empty,
    pub fn write(self: *Lines, source: []const u8) void { append([]const u8, &self.data, source); }
    pub fn add(self: *Lines, comptime pattern: []const u8, arguments: anytype) void { self.write(fmt(pattern, arguments)); }
    pub fn paragraph(self: *Lines, other: Lines) void {
        if (self.data.items.len > 0) self.write("");
        self.data.appendSlice(allocator, other.data.items) catch @panic("allocation failed");
    }
};
pub const Grid = struct {
    width: usize, height: usize, cells: []const u8,
    pub fn init(rows: Strings) Grid {
        const cells = alloc(u8, rows.len * rows[0].len);
        for (rows, 0..) |row, i| @memcpy(cells[i * row.len .. (i + 1) * row.len], row);
        return .{ .width = rows[0].len, .height = rows.len, .cells = cells };
    }
    pub fn isOpen(self: Grid, row: i64, column: i64) bool {
        return row >= 0 and column >= 0 and row < n(self.height) and column < n(self.width) and self.cells[u(row) * self.width + u(column)] != '#';
    }
    pub fn asymmetricCell(self: Grid, symmetry: []const u8) ?usize {
        for (0..self.height) |row| {
            for (0..self.width) |column| {
                const other_row = if (eq(symmetry, "rot180")) self.height - row - 1 else row;
                const other_column = self.width - column - 1;
                if (self.isOpen(n(row), n(column)) != self.isOpen(n(other_row), n(other_column))) return row * self.width + column;
            }
        }
        return null;
    }
    pub fn componentCount(self: Grid) usize {
        var seen = [_]bool{false} ** 225;
        const dr = [_]i64{ -1, 1, 0, 0 };
        const dc = [_]i64{ 0, 0, -1, 1 };
        var count: usize = 0;
        for (self.cells, 0..) |value, start| {
            if (value == '#' or seen[start]) continue;
            count += 1;
            seen[start] = true;
            var stack: [225]usize = undefined;
            var length: usize = 1;
            stack[0] = start;
            while (length > 0) {
                length -= 1;
                const cell = stack[length];
                const row = n(cell / self.width);
                const column = n(cell % self.width);
                for (dr, dc) |drow, dcolumn| {
                    const nr = row + drow;
                    const nc = column + dcolumn;
                    if (!self.isOpen(nr, nc)) continue;
                    const next = u(nr) * self.width + u(nc);
                    if (!seen[next]) { seen[next] = true; stack[length] = next; length += 1; }
                }
            }
        }
        return count;
    }
    pub fn cellText(self: Grid, cell: usize) []const u8 { return fmt("{d},{d}", .{ cell / self.width + 1, cell % self.width + 1 }); }
};
