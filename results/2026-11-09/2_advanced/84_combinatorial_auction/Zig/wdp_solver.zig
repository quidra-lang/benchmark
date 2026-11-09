const std = @import("std");
const b = @import("bids_io.zig");
const f = @import("report.zig");
pub const Share = struct { value: f.Fraction, source: ?usize = null };
pub const Shares = struct { values: [12]Share = undefined, bound: f.Fraction = .{} };
pub fn shares(items: []const b.Item, remaining: u16, bids: []const b.Bid) Shares {
    var out: Shares = .{};
    for (items, 0..) |item, index| if (remaining & b.bit(index) != 0) {
        var share: Share = .{ .value = f.Fraction.integer(item.reserve) };
        for (bids) |bid| if (bid.bundle & b.bit(index) != 0) {
            const value = f.Fraction.init(bid.amount, @popCount(bid.bundle));
            if (share.value.less(value)) share = .{ .value = value, .source = bid.number };
        };
        out.values[index] = share;
        out.bound = out.bound.add(share.value);
    };
    return out;
}
pub const Improvement = struct { nodes: i64, welfare: i64, numbers: [12]usize, count: usize };
pub const Result = struct { welfare: ?i64 = null, winning: []const b.Bid = &.{}, nodes: i64 = 0,
     pruned: i64 = 0, leaves: i64 = 0, improvements: std.ArrayList(Improvement) = .empty, root: Shares,
     best: [12]usize = @splat(0), best_count: usize = 0 };
const Search = struct {
    items: []const b.Item,
    offered: u16,
    bids: []const b.Bid,
    record: bool,
    result: *Result,
    fn visit(self: *Search, decided: u16, used: u16, welfare: i64, chosen: [12]usize, count: usize) void {
        self.result.nodes += 1;
        if (decided == self.offered) {
            self.result.leaves += 1;
            var ordered = chosen;
            std.mem.sort(usize, ordered[0..count], self.bids, struct {
                fn less(bids: []const b.Bid, a: usize, c: usize) bool {
                    return bids[a].number < bids[c].number;
                }
            }.less);
            var earlier = false;
            var equal = true;
            const common = @min(count, self.result.best_count);
            for (0..common) |i| {
                const a = self.bids[ordered[i]].number;
                const c = self.bids[self.result.best[i]].number;
                if (a != c) {
                    earlier = a < c;
                    equal = false;
                    break;
                }
            }
            if (equal) earlier = count < self.result.best_count;
            if (self.result.welfare == null or welfare > self.result.welfare.? or (welfare == self.result.welfare.? and earlier)) {
                self.result.welfare = welfare;
                self.result.best = ordered;
                self.result.best_count = count;
                if (self.record) {
                    var numbers: [12]usize = @splat(0);
                    for (ordered[0..count], 0..) |index, i| numbers[i] = self.bids[index].number;
                    b.append(Improvement, &self.result.improvements, .{ .nodes = self.result.nodes,
                         .welfare = welfare, .numbers = numbers, .count = count });
                }
            }
            return;
        }
        var available: [150]b.Bid = undefined;
        var indices: [150]usize = undefined;
        var available_count: usize = 0;
        for (self.bids, 0..) |bid, index| if (bid.bundle & decided == 0 and (!bid.xor or used & b.bit(bid.bidder) == 0)) {
            available[available_count] = bid;
            indices[available_count] = index;
            available_count += 1;
        };
        const remaining = self.offered & ~decided;
        const bound = shares(self.items, remaining, available[0..available_count]).bound.add(f.Fraction.integer(welfare));
        if (self.result.welfare) |incumbent| if (bound.less(f.Fraction.integer(incumbent))) {
            self.result.pruned += 1;
            return;
        };
        const first: usize = @ctz(remaining);
        for (available[0..available_count], indices[0..available_count]) |bid, index| if (bid.bundle & b.bit(first) != 0) {
            var next = chosen;
            next[count] = index;
            self.visit(decided | bid.bundle, if (bid.xor) used | b.bit(bid.bidder) else used,
                 welfare + bid.amount, next, count + 1);
        };
        self.visit(decided | b.bit(first), used, welfare + self.items[first].reserve, chosen, count);
    }
};
pub fn solve(items: []const b.Item, offered: u16, source: []const b.Bid, record: bool) Result {
    const bids = b.dupe(b.Bid, source);
    std.mem.sort(b.Bid, bids, {}, struct {
        fn less(_: void, a: b.Bid, c: b.Bid) bool {
            return a.number < c.number;
        }
    }.less);
    var result: Result = .{ .root = shares(items, offered, bids) };
    var search: Search = .{ .items = items, .offered = offered, .bids = bids, .record = record, .result = &result };
    search.visit(0, 0, 0, @splat(0), 0);
    const winning = b.alloc(b.Bid, result.best_count);
    for (result.best[0..result.best_count], winning) |index, *bid| bid.* = bids[index];
    result.winning = winning;
    return result;
}
pub fn greedyOrder(bids: []const b.Bid) []const b.Bid {
    const ordered = b.dupe(b.Bid, bids);
    std.mem.sort(b.Bid, ordered, {}, struct {
        fn less(_: void, a: b.Bid, c: b.Bid) bool {
            const left = a.amount * a.amount * @as(i64, @popCount(c.bundle));
            const right = c.amount * c.amount * @as(i64, @popCount(a.bundle));
            return if (left == right) a.number < c.number else left > right;
        }
    }.less);
    return ordered;
}
pub fn greedySelect(bids: []const b.Bid, excluded: ?usize) []const b.Bid {
    var chosen: std.ArrayList(b.Bid) = .empty;
    var occupied: u16 = 0;
    var used: u16 = 0;
    for (bids) |bid| {
        if (excluded == bid.number or bid.bundle & occupied != 0 or (bid.xor and used & b.bit(bid.bidder) != 0)) continue;
        b.append(b.Bid, &chosen, bid);
        occupied |= bid.bundle;
        if (bid.xor) used |= b.bit(bid.bidder);
    }
    return chosen.items;
}
