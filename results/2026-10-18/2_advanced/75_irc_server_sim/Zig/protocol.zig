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

pub fn join(items: []const []const u8, separator: []const u8) []const u8 {
    return std.mem.join(allocator, separator, items) catch @panic("allocation failed");
}
pub fn foldCharacter(c: u8) u8 {
    return switch (c) {
        'A'...'Z' => c - 'A' + 'a',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        '^' => '~',
        else => c,
    };
}
pub fn fold(value: []const u8) []const u8 {
    const out = dupe(u8, value);
    for (out) |*c| c.* = foldCharacter(c.*);
    return out;
}
pub fn same(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (foldCharacter(x) != foldCharacter(y)) return false;
    return true;
}
pub fn digits(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| if (c < '0' or c > '9') return false;
    return true;
}
pub fn letter(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}
fn special(c: u8) bool {
    return std.mem.indexOfScalar(u8, "[]\\`_^{}|", c) != null;
}
pub fn validNickname(value: []const u8) bool {
    if (value.len == 0 or (!letter(value[0]) and !special(value[0]))) return false;
    for (value[1..]) |c| if (!letter(c) and !special(c) and !(c >= '0' and c <= '9') and c != '-') return false;
    return true;
}
pub fn validChannel(value: []const u8, maximum: usize) bool {
    return value.len >= 2 and value.len <= maximum and value[0] == '#' and std.mem.indexOfScalar(u8,
         value, ':') == null;
}
pub const Parsed = struct {
    command: []const u8 = "",
    parameters: [15][]const u8 = undefined,
    count: usize = 0,
    pub fn params(self: *const Parsed) []const []const u8 {
        return self.parameters[0..self.count];
    }
};
pub fn parse(raw: []const u8) Parsed {
    var out: Parsed = .{};
    var pos: usize = 0;
    if (raw.len > 0 and raw[0] == ':') pos = std.mem.indexOfScalar(u8, raw, ' ') orelse return out;
    while (pos < raw.len and raw[pos] == ' ') : (pos += 1) {}
    var start = pos;
    while (pos < raw.len and raw[pos] != ' ') : (pos += 1) {}
    const command = dupe(u8, raw[start..pos]);
    for (command) |*c| if (c.* >= 'a' and c.* <= 'z') {
        c.* = c.* - 'a' + 'A';
    };
    out.command = command;
    if (command.len == 0) return out;
    while (pos < raw.len) {
        while (pos < raw.len and raw[pos] == ' ') : (pos += 1) {}
        if (pos == raw.len) break;
        if (raw[pos] == ':' or out.count == 14) {
            out.parameters[out.count] = raw[pos + @intFromBool(raw[pos] == ':') ..];
            out.count += 1;
            break;
        }
        start = pos;
        while (pos < raw.len and raw[pos] != ' ') : (pos += 1) {}
        out.parameters[out.count] = raw[start..pos];
        out.count += 1;
    }
    return out;
}
pub fn erase(list: *std.ArrayList(usize), value: usize) void {
    for (list.items, 0..) |item, i| if (item == value) {
        _ = list.orderedRemove(i);
        return;
    };
}
pub fn contains(list: []const usize, value: usize) bool {
    for (list) |item| if (item == value) return true;
    return false;
}
