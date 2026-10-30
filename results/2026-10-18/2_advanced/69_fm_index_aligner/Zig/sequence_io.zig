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

pub const Reference = struct { name: []const u8, bases: []const u8 = "", masked: i64 = 0 };
pub const Read = struct { name: []const u8, bases: []const u8, quality: []const u8 };
pub const Input = struct { references: []const Reference, reads: []const Read, parameters: [16][]const i64 };
pub fn readInputs(io: std.Io) !Input {
    var references: std.ArrayList(Reference) = .empty;
    var sequence: Text = .{};
    for (try readLines(io, "input/reference.fasta")) |line| {
        if (line[0] == '>') {
            if (references.items.len > 0) references.items[references.items.len - 1].bases = sequence.value();
            sequence = .{};
            const end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
            append(Reference, &references, .{ .name = line[1..end] });
        } else for (line) |character| {
            const lower = character >= 'a' and character <= 'z';
            references.items[references.items.len - 1].masked += @intFromBool(lower);
            sequence.add("{c}", .{if (lower) character - 32 else character});
        };
    }
    references.items[references.items.len - 1].bases = sequence.value();
    const lines = try readLines(io, "input/reads.fastq");
    const reads = alloc(Read, lines.len / 4);
    for (reads, 0..) |*read, i| read.* = .{ .name = lines[4 * i][1..], .bases = lines[4 * i + 1],
         .quality = lines[4 * i + 3] };
    var parameters: [16][]const i64 = undefined;
    for (try readLines(io, "input/params.txt"), &parameters) |line, *values| {
        const row = words(line);
        const numbers = alloc(i64, row.len - 1);
        for (row[1..], numbers) |value, *parsed| parsed.* = number(value);
        values.* = numbers;
    }
    return .{ .references = references.items, .reads = reads, .parameters = parameters };
}
pub fn reverseComplement(sequence: []const u8) []const u8 {
    const out = alloc(u8, sequence.len);
    for (out, 0..) |*base, i| base.* = switch (sequence[sequence.len - i - 1]) {
        'A' => 'T',
        'C' => 'G',
        'G' => 'C',
        'T' => 'A',
        else => 'N',
    };
    return out;
}
pub const AlignedPair = struct { read: usize, reference: usize };
pub const Alignment = struct { reference: usize, position: usize, strand: usize, nm: i64 = 0,
     operations: []const u8, oriented: []const u8, cigar: []const u8 = "", md: []const u8 = "",
     pairs: []const AlignedPair = &.{} };
pub const Result = struct { read: Read, core: []const u8, qualities: []const i64, length: usize,
     trimmed: usize, mapped: bool = false, reason: []const u8 = "SHORT", method: []const u8 = "",
     primary: Alignment = undefined, others: []const Alignment = &.{}, other_count: usize = 0,
     score: i64 = 0, mapq: i64 = 0, x0: i64 = 0, x1: i64 = 0, targets: u16 = 0 };
