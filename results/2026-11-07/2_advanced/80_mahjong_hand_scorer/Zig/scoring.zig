const std = @import("std");
const t = @import("tiles.zig");
const d = @import("decomposition.zig");
pub const Triplet = struct { block: t.Block, concealed: bool, kan: bool };
pub const FuItem = struct { name: []const u8, value: i64 };
pub const Fu = struct { items: []const FuItem, total: i64, value: i64 };
pub fn tripletFu(triplet: Triplet) FuItem {
    const kind = if (triplet.kan) (if (triplet.concealed) "closed_kan" else "open_kan") else (if (triplet.concealed) "closed_triplet" else "open_triplet");
    const value: i64 = (if (triplet.kan) (if (triplet.concealed) @as(i64, 16) else 8) else (if (triplet.concealed) @as(i64,
         4) else 2)) * (if (t.yaochuu(triplet.block.first)) @as(i64, 2) else 1);
    return .{ .name = t.fmt("{s} {s}", .{ kind, triplet.block.text() }), .value = value };
}
pub fn fuBreakdown(seven: bool, pair: usize, triplets: []const Triplet, wait: d.Wait, closed: bool,
     tsumo: bool, seat: usize, round: usize, pinfu: bool) Fu {
    var items: std.ArrayList(FuItem) = .empty;
    if (seven) {
        t.append(FuItem, &items, .{ .name = "chiitoitsu", .value = 25 });
        return .{ .items = items.items, .total = 25, .value = 25 };
    }
    t.append(FuItem, &items, .{ .name = "base", .value = 20 });
    if (closed and !tsumo) t.append(FuItem, &items, .{ .name = "closed_ron", .value = 10 });
    if (tsumo and !pinfu) t.append(FuItem, &items, .{ .name = "tsumo", .value = 2 });
    const pair_value = 2 * (@as(i64, @intFromBool(pair >= 31)) + @as(i64, @intFromBool(pair == seat)) + @as(i64,
         @intFromBool(pair == round)));
    if (pair_value > 0) t.append(FuItem, &items, .{ .name = t.fmt("pair {s}", .{(t.Block{ .first = pair,
         .size = 2 }).text()}), .value = pair_value });
    for (triplets) |triplet| t.append(FuItem, &items, tripletFu(triplet));
    if (wait == .kanchan or wait == .penchan or wait == .tanki) t.append(FuItem, &items, .{ .name = t.fmt("wait {s}",
         .{d.wait_names[@intFromEnum(wait)]}), .value = 2 });
    var total: i64 = 0;
    for (items.items) |item| total += item.value;
    if (!closed and total == 20) {
        t.append(FuItem, &items, .{ .name = "open_pinfu", .value = 10 });
        total += 10;
    }
    return .{ .items = items.items, .total = total, .value = @divTrunc(total + 9, 10) * 10 };
}
pub fn limit(han: i64, fu: i64, kazoe: bool, kiriage: bool) struct { category: usize, base: i64 } {
    if (han >= 13 and kazoe) return .{ .category = 5, .base = 8000 };
    if (han >= 11) return .{ .category = 4, .base = 6000 };
    if (han >= 8) return .{ .category = 3, .base = 4000 };
    if (han >= 6) return .{ .category = 2, .base = 3000 };
    const base = fu * (@as(i64, 1) << @intCast(han + 2));
    return if (han == 5 or base >= 2000 or (kiriage and base == 1920)) .{ .category = 1, .base = 2000 } else .{ .category = 0,
         .base = base };
}
pub fn roundHundred(value: i64) i64 {
    return @divTrunc(value + 99, 100) * 100;
}
pub const Payments = struct { ron: i64 = 0, dealer: i64 = 0, nondealer: i64 = 0, total: i64 = 0 };
pub fn payments(base: i64, dealer: bool, tsumo: bool) Payments {
    if (!tsumo) {
        const ron = roundHundred(base * (if (dealer) @as(i64, 6) else 4));
        return .{ .ron = ron, .total = ron };
    }
    if (dealer) {
        const nondealer = roundHundred(base * 2);
        return .{ .nondealer = nondealer, .total = 3 * nondealer };
    }
    const dp = roundHundred(base * 2);
    const nd = roundHundred(base);
    return .{ .dealer = dp, .nondealer = nd, .total = dp + 2 * nd };
}
