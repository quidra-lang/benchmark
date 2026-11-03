const std = @import("std");
const b = @import("bids_io.zig");
pub const Candidate = struct { number: usize, bundle: u16, value: i64 };
pub fn candidates(bids: []const b.Bid, xor: bool) []const Candidate {
    var out: std.ArrayList(Candidate) = .empty;
    const end = @as(usize, 1) << @intCast(bids.len);
    for (1..end) |number| {
        if (xor and @popCount(number) != 1) continue;
        var bundle: u16 = 0;
        var value: i64 = 0;
        var valid = true;
        for (bids, 0..) |bid, index| if (number & (@as(usize, 1) << @intCast(index)) != 0) {
            if (bundle & bid.bundle != 0) {
                valid = false;
                break;
            }
            bundle |= bid.bundle;
            value += bid.amount;
        };
        if (valid) b.append(Candidate, &out, .{ .number = number, .bundle = bundle, .value = value });
    }
    return out.items;
}
pub fn valueOf(choices: []const Candidate, items: u16) i64 {
    var value: i64 = 0;
    for (choices) |candidate| if (candidate.bundle & items == candidate.bundle) {
        value = @max(value, candidate.value);
    };
    return value;
}
pub const Clock = struct { winner: ?usize = null, price: i64 = 0, steps: usize = 0, drops: []const ?i64 = &.{} };
pub fn english(participants: []const b.Participant, reserve: i64, increment: i64) Clock {
    var price = reserve;
    var result: Clock = .{};
    while (true) {
        var count: usize = 0;
        var first: ?usize = null;
        for (participants, 0..) |participant, index| if (participant.value >= price) {
            count += 1;
            if (first == null) first = index;
        };
        if (count < 2) {
            result.winner = first;
            result.price = if (first != null) price else 0;
            break;
        }
        const previous = first;
        price += increment;
        result.steps += 1;
        var remaining: usize = 0;
        for (participants) |participant| remaining += @intFromBool(participant.value >= price);
        if (remaining == 0) {
            result.winner = previous;
            result.price = price - increment;
            break;
        }
    }
    const drops = b.alloc(?i64, participants.len);
    for (participants, drops) |participant, *drop| {
        const value = if (participant.value < reserve) reserve else reserve + (@divTrunc(participant.value - reserve,
             increment) + 1) * increment;
        drop.* = if (value <= price) value else null;
    }
    result.drops = drops;
    return result;
}
pub fn dutch(participants: []const b.Participant, reserve: i64, start: i64, decrement: i64) Clock {
    var price = start;
    var result: Clock = .{};
    while (price >= reserve) {
        var winner: ?usize = null;
        for (participants, 0..) |participant, index| if (participant.bid >= price and (winner == null or participant.bid > participants[winner.?].bid)) {
            winner = index;
        };
        if (winner != null) {
            result.winner = winner;
            result.price = price;
            return result;
        }
        price -= decrement;
        result.steps += 1;
    }
    return result;
}
