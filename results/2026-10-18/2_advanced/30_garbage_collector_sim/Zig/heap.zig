const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T: type, count: usize) []T {
    return allocator.alloc(T, count) catch @panic("allocation failed");
}
pub fn create(comptime T: type, value: T) *T {
    const result = allocator.create(T) catch @panic("allocation failed");
    result.* = value;
    return result;
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
pub fn number(text: []const u8) i64 {
    return std.fmt.parseInt(i64, text, 10) catch unreachable;
}
pub fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
pub fn split(text: []const u8, delimiter: u8) []const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var fields = std.mem.splitScalar(u8, text, delimiter);
    while (fields.next()) |field| append([]const u8, &result, field);
    return result.items;
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
    pub fn extend(self: *Lines, other: Lines) void {
        for (other.data.items) |line| self.add("{s}", .{line});
    }
    pub fn blank(self: *Lines) void {
        self.add("", .{});
    }
};
pub fn readLines(io: std.Io, name: []const u8) ![]const []const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, fmt("input/{s}", .{name}), allocator, .unlimited);
    const lines = split(text, '\n');
    return lines[0 .. lines.len - 1];
}
pub fn writeLines(io: std.Io, name: []const u8, lines: Lines) !void {
    var text: Text = .{};
    for (lines.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().createDirPath(io, "output");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fmt("output/{s}", .{name}), .data = text.value() });
}
pub const CollectorType = enum { MARK_SWEEP, MARK_COMPACT, COPYING, GENERATIONAL, REFCOUNT };
pub const Collector = struct { name: []const u8, kind: CollectorType, young: usize = 0, promotion_age: usize = 0 };
pub const Pair = struct {
    count: i64 = 0,
    words: i64 = 0,
    pub fn add(self: *Pair, size: usize) void {
        self.count += 1;
        self.words += n(size);
    }
    pub fn merge(self: *Pair, other: Pair) void {
        self.count += other.count;
        self.words += other.words;
    }
    pub fn text(self: Pair) []const u8 {
        return fmt("{d} {d}", .{ self.count, self.words });
    }
};
pub const Object = struct {
    id: usize,
    p: usize,
    d: usize,
    fields: []usize,
    address: usize = 0,
    age: usize = 0,
    moves: usize = 0,
    references: i64 = 0,
    present: bool = true,
    marked: bool = false,
    pub fn size(self: Object) usize {
        return 1 + self.p + self.d;
    }
    pub fn init(id: usize, p: usize, data: usize, address: usize) Object {
        const fields = alloc(usize, p);
        @memset(fields, 0);
        return .{ .id = id, .p = p, .d = data, .fields = fields, .address = address };
    }
};
pub const Collection = struct { number: usize, line: usize, request: usize, kind: []const u8, live: Pair = .{},
     freed: Pair = .{}, moved: Pair = .{}, promoted: Pair = .{}, stack: usize = 0, work: i64 = 0,
     before: [2]i64 = .{ 0, 0 }, after: [2]i64 = .{ 0, 0 } };
pub const Heap = struct {
    size: usize,
    collector: Collector,
    base: usize = 0,
    top: usize = 0,
    objects: std.ArrayList(Object) = .empty,
    roots: std.ArrayList(usize) = .empty,
    remembered: [5000]bool = @splat(false),
    barriers: i64 = 0,
    remembers: i64 = 0,
    pub fn object(self: *Heap, id: usize) *Object {
        return &self.objects.items[id - 1];
    }
    pub fn get(self: *const Heap, id: usize) Object {
        return self.objects.items[id - 1];
    }
};
fn addressLess(heap: *const Heap, a: usize, b: usize) bool {
    return heap.get(a).address < heap.get(b).address;
}
pub fn addressOrder(heap: *const Heap) []usize {
    var ids: std.ArrayList(usize) = .empty;
    for (heap.objects.items) |object| if (object.present) append(usize, &ids, object.id);
    std.mem.sort(usize, ids.items, heap, addressLess);
    return ids.items;
}
pub const Block = struct { address: usize, length: usize };
pub fn rangeBlocks(heap: *const Heap, first: usize, end: usize) []Block {
    var result: std.ArrayList(Block) = .empty;
    var cursor = first;
    for (addressOrder(heap)) |id| {
        const object = heap.get(id);
        if (object.address < first or object.address >= end) continue;
        if (object.address > cursor) append(Block, &result, .{ .address = cursor, .length = object.address - cursor });
        cursor = object.address + object.size();
    }
    if (cursor < end) append(Block, &result, .{ .address = cursor, .length = end - cursor });
    return result.items;
}
pub fn freeBlocks(heap: *const Heap) []Block {
    var result: std.ArrayList(Block) = .empty;
    switch (heap.collector.kind) {
        .MARK_SWEEP, .REFCOUNT => return rangeBlocks(heap, 0, heap.size),
        .MARK_COMPACT, .COPYING => {
            const end = if (heap.collector.kind == .COPYING) heap.base + heap.size / 2 else heap.size;
            if (heap.top < end) append(Block, &result, .{ .address = heap.top, .length = end - heap.top });
        },
        .GENERATIONAL => {
            const end = heap.base + heap.collector.young / 2;
            if (heap.top < end) append(Block, &result, .{ .address = heap.top, .length = end - heap.top });
            for (rangeBlocks(heap, heap.collector.young, heap.size)) |block| append(Block, &result, block);
        },
    }
    return result.items;
}
pub fn freeAmount(heap: *const Heap) [2]i64 {
    var result = [2]i64{ 0, 0 };
    for (freeBlocks(heap)) |block| {
        result[0] += n(block.length);
        result[1] = @max(result[1], n(block.length));
    }
    return result;
}
pub fn firstFit(heap: *const Heap, size: usize, first: usize, end: usize) ?usize {
    for (rangeBlocks(heap, first, end)) |block| if (block.length >= size) return block.address;
    return null;
}
pub fn used(heap: *const Heap) i64 {
    var total: i64 = 0;
    for (heap.objects.items) |object| if (object.present) {
        total += n(object.size());
    };
    return total;
}
pub fn dec2(a: i64, b: i64) []const u8 {
    const value = @divTrunc(200 * a + b, 2 * b);
    return fmt("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) });
}
pub fn pct(a: i64, b: i64) []const u8 {
    return if (b == 0) "-" else dec2(100 * a, b);
}
pub fn classTable(sizes: []const usize) []const u8 {
    var counts: [5]usize = @splat(0);
    for (sizes) |size| counts[if (size == 1) 0 else if (size < 4) 1 else if (size < 8) 2 else if (size < 16) 3 else 4] += 1;
    return fmt("1:{d} 2-3:{d} 4-7:{d} 8-15:{d} 16+:{d}", .{ counts[0], counts[1], counts[2], counts[3], counts[4] });
}
pub fn heapMap(heap: *const Heap, reachable: []const bool) []const u8 {
    const map = alloc(u8, heap.size);
    @memset(map, '.');
    const half = if (heap.collector.kind == .COPYING) heap.size / 2 else if (heap.collector.kind == .GENERATIONAL) heap.collector.young / 2 else 0;
    if (half > 0) @memset(map[half - heap.base .. 2 * half - heap.base], '-');
    for (heap.objects.items, 0..) |object, index| if (object.present) {
        const live = reachable[index];
        map[object.address] = if (live) 'A' + @as(u8, @intCast(index % 26)) else '#';
        @memset(map[object.address + 1 .. object.address + object.size()], if (live) 'a' + @as(u8,
             @intCast(index % 26)) else '=');
    };
    return map;
}
