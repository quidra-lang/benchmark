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
pub fn bit(index: usize) u32 {
    return @as(u32, 1) << @intCast(index);
}
pub fn indexOf(values: []const []const u8, value: []const u8) ?usize {
    for (values, 0..) |name, i| if (eq(name, value)) return i;
    return null;
}
pub fn baseIndex(character: u8) ?usize {
    return switch (character) {
        'A' => 0,
        'C' => 1,
        'G' => 2,
        'T' => 3,
        else => null,
    };
}
pub fn baseSet(character: u8) u8 {
    return switch (character) {
        'A' => 1,
        'C' => 2,
        'G' => 4,
        'T' => 8,
        'R' => 5,
        'Y' => 10,
        'S' => 6,
        'W' => 9,
        'K' => 12,
        'M' => 3,
        'B' => 14,
        'D' => 13,
        'H' => 11,
        'V' => 7,
        'N', '-' => 15,
        else => 0,
    };
}
pub const Record = struct { line: usize, name: []const u8, sequence: []const u8 };
pub fn readFasta(io: std.Io) ![]const Record {
    var records: std.ArrayList(Record) = .empty;
    var sequence: Text = .{};
    for (try readLines(io, "input/alignment.fasta"), 1..) |line, line_number| {
        if (line[0] == '>') {
            if (records.items.len > 0) records.items[records.items.len - 1].sequence = sequence.value();
            sequence = .{};
            const finish = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
            append(Record, &records, .{ .line = line_number, .name = line[1..finish], .sequence = "" });
        } else for (line) |character| {
            const upper = if (character >= 'a' and character <= 'z') character - 32 else character;
            sequence.add("{c}", .{upper});
        };
    }
    records.items[records.items.len - 1].sequence = sequence.value();
    return records.items;
}
pub const Patterns = struct {
    text: []const []const u8,
    encoded: []const [16]u8,
    weights: []const i64,
    columns: []const usize,
    pub fn init(sequences: []const []const u8) Patterns {
        var texts: std.ArrayList([]const u8) = .empty;
        var encoded: std.ArrayList([16]u8) = .empty;
        var weights: std.ArrayList(i64) = .empty;
        const columns = alloc(usize, sequences[0].len);
        for (columns, 0..) |*column, c| {
            const pattern = alloc(u8, sequences.len);
            for (sequences, pattern) |sequence, *character| character.* = sequence[c];
            var index = indexOf(texts.items, pattern);
            if (index == null) {
                index = texts.items.len;
                append([]const u8, &texts, pattern);
                var values = [_]u8{0} ** 16;
                for (pattern, 0..) |character, t| values[t] = baseSet(character);
                append([16]u8, &encoded, values);
                append(i64, &weights, 0);
            }
            column.* = index.?;
            weights.items[index.?] += 1;
        }
        return .{ .text = texts.items, .encoded = encoded.items, .weights = weights.items, .columns = columns };
    }
};
pub const Classes = struct { constant: usize = 0, variable: usize = 0, informative: usize = 0,
     gapped: usize = 0, empty: usize = 0 };
pub fn classify(sequences: []const []const u8) Classes {
    var out: Classes = .{};
    for (0..sequences[0].len) |column| {
        var counts = [_]usize{0} ** 4;
        var gapped = false;
        for (sequences) |sequence| {
            if (baseIndex(sequence[column])) |base| counts[base] += 1;
            gapped = gapped or sequence[column] == '-';
        }
        var kinds: usize = 0;
        var multiple: usize = 0;
        for (counts) |count| {
            kinds += @intFromBool(count > 0);
            multiple += @intFromBool(count >= 2);
        }
        out.empty += @intFromBool(kinds == 0);
        out.constant += @intFromBool(kinds == 1);
        out.variable += @intFromBool(kinds >= 2);
        out.informative += @intFromBool(multiple >= 2);
        out.gapped += @intFromBool(gapped);
    }
    return out;
}
