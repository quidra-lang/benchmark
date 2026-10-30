const std = @import("std");
const b = @import("bids_io.zig");
const w = @import("wdp_solver.zig");
const f = @import("report.zig");
pub const Vcg = struct { payment: i64, alternative: w.Result };
pub fn vcgPayments(items: []const b.Item, offered: u16, bids: []const b.Bid, optimal: w.Result,
     bidder_count: usize) []const ?Vcg {
    const out = b.zero(?Vcg, bidder_count, null);
    for (0..bidder_count) |id| {
        var value: i64 = 0;
        var winner = false;
        for (optimal.winning) |bid| if (bid.bidder == id) {
            winner = true;
            value += bid.amount;
        };
        if (!winner) continue;
        var remaining: std.ArrayList(b.Bid) = .empty;
        for (bids) |bid| if (bid.bidder != id) b.append(b.Bid, &remaining, bid);
        const alternative = w.solve(items, offered, remaining.items, false);
        out[id] = .{ .payment = alternative.welfare.? - (optimal.welfare.? - value), .alternative = alternative };
    }
    return out;
}
pub const Critical = struct { number: usize, payment: i64, rival: ?usize };
pub fn criticalPayments(order: []const b.Bid, winning: []const b.Bid, items: []const b.Item) []const Critical {
    const out = b.alloc(Critical, winning.len);
    for (winning, out) |bid, *result| {
        var rival: ?b.Bid = null;
        for (w.greedySelect(order, bid.number)) |other| if (bid.bundle & other.bundle != 0 or (bid.xor and bid.bidder == other.bidder)) {
            rival = other;
            break;
        };
        var payment = b.reserve(items, bid.bundle);
        if (rival) |other| {
            const threshold = other.amount * other.amount * @as(i64, @popCount(bid.bundle));
            var low: i64 = 1;
            var high: i64 = 1;
            while (true) {
                const score = high * high * @as(i64, @popCount(other.bundle));
                if (score > threshold or (score == threshold and bid.number < other.number)) break;
                high *= 2;
            }
            while (low < high) {
                const middle = @divTrunc(low + high, 2);
                const score = middle * middle * @as(i64, @popCount(other.bundle));
                if (score > threshold or (score == threshold and bid.number < other.number)) high = middle else low = middle + 1;
            }
            payment = @max(payment, low);
        }
        result.* = .{ .number = bid.number, .payment = payment, .rival = if (rival) |other| other.number else null };
    }
    return out;
}
pub const Coalition = struct { mask: u16, welfare: i64, winning: []const b.Bid };
pub fn coalitionWelfares(items: []const b.Item, offered: u16, bids: []const b.Bid, count: usize) []const Coalition {
    const masks = b.alloc(u16, @as(usize, 1) << @intCast(count));
    for (masks, 0..) |*mask, i| mask.* = @intCast(i);
    std.mem.sort(u16, masks, {}, struct {
        fn less(_: void, a: u16, c: u16) bool {
            if (@popCount(a) != @popCount(c)) return @popCount(a) < @popCount(c);
            if (a == c) return false;
            const first = @as(u16, 1) << @intCast(@ctz(a ^ c));
            return a & first != 0;
        }
    }.less);
    const out = b.alloc(Coalition, masks.len);
    for (masks, out) |mask, *coalition| {
        var eligible: std.ArrayList(b.Bid) = .empty;
        for (bids) |bid| if (mask & b.bit(bid.bidder) != 0) b.append(b.Bid, &eligible, bid);
        const result = w.solve(items, offered, eligible.items, false);
        coalition.* = .{ .mask = mask, .welfare = result.welfare.?, .winning = result.winning };
    }
    return out;
}
pub const Blocking = struct { coalition: Coalition, payoff: i64, deficit: i64, minimal: bool };
pub fn blockingCoalitions(coalitions: []const Coalition, seller: i64, utilities: []const i64) []const Blocking {
    var out: std.ArrayList(Blocking) = .empty;
    for (coalitions) |coalition| {
        var payoff = seller;
        for (utilities, 0..) |utility, id| if (coalition.mask & b.bit(id) != 0) {
            payoff += utility;
        };
        if (coalition.welfare <= payoff) continue;
        var minimal = true;
        for (out.items) |earlier| minimal = minimal and earlier.coalition.mask & coalition.mask != earlier.coalition.mask;
        b.append(Blocking, &out, .{ .coalition = coalition, .payoff = payoff, .deficit = coalition.welfare - payoff,
             .minimal = minimal });
    }
    return out.items;
}
pub fn gspPrice(ranking: []const b.Participant, rank: usize) i64 {
    return if (rank + 1 < ranking.len) ranking[rank + 1].bid else 0;
}
pub fn slotVcgPayment(ranking: []const b.Participant, rates: []const f.Fraction, rank: usize) f.Fraction {
    var payment: f.Fraction = .{};
    for (rank + 1..@min(ranking.len, rates.len + 1)) |following| {
        const next = if (following < rates.len) rates[following] else f.Fraction{};
        payment = payment.add(rates[following - 1].subtract(next).scale(ranking[following].value));
    }
    return payment;
}
