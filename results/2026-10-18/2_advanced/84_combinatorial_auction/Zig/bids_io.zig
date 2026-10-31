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

pub fn zero(comptime T: type, count: usize, value: T) []T {
    const out = alloc(T, count);
    @memset(out, value);
    return out;
}
pub fn indexOf(items: anytype, name: []const u8) usize {
    for (items, 0..) |item, i| if (eq(item.name, name)) return i;
    unreachable;
}

pub fn bit(index: usize) u16 {
    return @as(u16, 1) << @intCast(index);
}
pub const Item = struct { name: []const u8, reserve: i64 };
pub const Bid = struct { number: usize, bidder: usize, bundle: u16, amount: i64, xor: bool };
pub const BidderLine = struct { name: []const u8, language: []const u8, bids: Names };
pub const RawAuction = struct { name: []const u8, items: Names, lines: std.ArrayList(BidderLine) = .empty };
pub const Participant = struct { name: []const u8, value: i64, bid: i64, order: usize };
pub const Group = struct { name: []const u8, slots: bool, arguments: Names, participants: std.ArrayList(Participant) = .empty };
pub const Parameters = struct { runs: Names, max_bundle_size: usize, max_bids_per_bidder: usize,
     core_max_bidders: usize, saa_increment: i64, round_cap: usize, seed: i64, english_increment: i64,
     dutch_start: i64, dutch_decrement: i64 };
pub const Inputs = struct { items: []const Item, auctions: []const RawAuction, groups: []const Group,
     parameters: Parameters };
pub fn read(io: std.Io) !Inputs {
    var items: std.ArrayList(Item) = .empty;
    for (try readLines(io, "input/items.txt")) |line| {
        const f = words(line);
        append(Item, &items, .{ .name = f[0], .reserve = number(f[1]) });
    }
    var auctions: std.ArrayList(RawAuction) = .empty;
    for (try readLines(io, "input/bids.txt")) |line| {
        const f = words(line);
        if (eq(f[0], "auction")) append(RawAuction, &auctions, .{ .name = f[1], .items = f[2..] }) else append(BidderLine,
             &auctions.items[auctions.items.len - 1].lines, .{ .name = f[1], .language = f[2],
             .bids = f[3..] });
    }
    var groups: std.ArrayList(Group) = .empty;
    for (try readLines(io, "input/single_item.txt")) |line| {
        const f = words(line);
        if (eq(f[0], "lot") or eq(f[0], "slots")) append(Group, &groups, .{ .name = f[1], .slots = eq(f[0],
             "slots"), .arguments = f[2..] }) else {
            const group = &groups.items[groups.items.len - 1];
            append(Participant, &group.participants, .{ .name = f[1], .value = number(f[2]),
                 .bid = number(f[3]), .order = group.participants.items.len });
        }
    }
    const params = try readLines(io, "input/params.txt");
    const parameters: Parameters = .{ .runs = words(params[0])[1..], .max_bundle_size = u(number(words(params[1])[1])),
         .max_bids_per_bidder = u(number(words(params[2])[1])), .core_max_bidders = u(number(words(params[3])[1])),
         .saa_increment = number(words(params[4])[1]), .round_cap = u(number(words(params[5])[1])),
         .seed = number(words(params[6])[1]), .english_increment = number(words(params[7])[1]),
         .dutch_start = number(words(params[8])[1]), .dutch_decrement = number(words(params[9])[1]) };
    return .{ .items = items.items, .auctions = auctions.items, .groups = groups.items, .parameters = parameters };
}
pub fn reserve(items: []const Item, mask: u16) i64 {
    var sum: i64 = 0;
    for (items, 0..) |item, index| if (mask & bit(index) != 0) {
        sum += item.reserve;
    };
    return sum;
}
