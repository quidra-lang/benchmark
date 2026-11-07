const std = @import("std");
const t = @import("tiles.zig");
pub const Ordinary = struct { name: []const u8, closed: i64, opened: i64 };
pub const Yakuman = struct { name: []const u8, multiplier: i64 };
pub const Entry = struct { index: usize, name: []const u8, value: i64 };
pub const ordinary_table = [_]Ordinary{
    .{ .name = "riichi", .closed = 1, .opened = 0 },
    .{ .name = "double_riichi", .closed = 2, .opened = 0 },
    .{ .name = "ippatsu", .closed = 1, .opened = 0 },
    .{ .name = "menzen_tsumo", .closed = 1, .opened = 0 },
    .{ .name = "pinfu", .closed = 1, .opened = 0 },
    .{ .name = "tanyao", .closed = 1, .opened = 1 },
    .{ .name = "iipeikou", .closed = 1, .opened = 0 },
    .{ .name = "haku", .closed = 1, .opened = 1 },
    .{ .name = "hatsu", .closed = 1, .opened = 1 },
    .{ .name = "chun", .closed = 1, .opened = 1 },
    .{ .name = "jikaze", .closed = 1, .opened = 1 },
    .{ .name = "bakaze", .closed = 1, .opened = 1 },
    .{ .name = "haitei", .closed = 1, .opened = 1 },
    .{ .name = "houtei", .closed = 1, .opened = 1 },
    .{ .name = "rinshan", .closed = 1, .opened = 1 },
    .{ .name = "chankan", .closed = 1, .opened = 1 },
    .{ .name = "chiitoitsu", .closed = 2, .opened = 0 },
    .{ .name = "toitoi", .closed = 2, .opened = 2 },
    .{ .name = "sanankou", .closed = 2, .opened = 2 },
    .{ .name = "sanshoku_doujun", .closed = 2, .opened = 1 },
    .{ .name = "sanshoku_doukou", .closed = 2, .opened = 2 },
    .{ .name = "ittsu", .closed = 2, .opened = 1 },
    .{ .name = "chanta", .closed = 2, .opened = 1 },
    .{ .name = "sankantsu", .closed = 2, .opened = 2 },
    .{ .name = "shousangen", .closed = 2, .opened = 2 },
    .{ .name = "honroutou", .closed = 2, .opened = 2 },
    .{ .name = "honitsu", .closed = 3, .opened = 2 },
    .{ .name = "junchan", .closed = 3, .opened = 2 },
    .{ .name = "ryanpeikou", .closed = 3, .opened = 0 },
    .{ .name = "chinitsu", .closed = 6, .opened = 5 },
};
pub const yakuman_table = [_]Yakuman{
    .{ .name = "tenhou", .multiplier = 1 },
    .{ .name = "chiihou", .multiplier = 1 },
    .{ .name = "kokushi", .multiplier = 1 },
    .{ .name = "kokushi_13", .multiplier = 2 },
    .{ .name = "suuankou", .multiplier = 1 },
    .{ .name = "suuankou_tanki", .multiplier = 2 },
    .{ .name = "daisangen", .multiplier = 1 },
    .{ .name = "shousuushii", .multiplier = 1 },
    .{ .name = "daisuushii", .multiplier = 2 },
    .{ .name = "tsuuiisou", .multiplier = 1 },
    .{ .name = "chinroutou", .multiplier = 1 },
    .{ .name = "ryuuiisou", .multiplier = 1 },
    .{ .name = "chuuren", .multiplier = 1 },
    .{ .name = "junsei_chuuren", .multiplier = 2 },
    .{ .name = "suukantsu", .multiplier = 1 },
};
pub const flags = [_][]const u8{ "riichi", "double_riichi", "ippatsu", "haitei", "houtei",
     "rinshan", "chankan", "tenhou", "chiihou" };
pub const categories = [_][]const u8{ "none", "mangan", "haneman", "baiman", "sanbaiman", "kazoe_yakuman", "yakuman" };

pub fn ordinary(holds: [30]bool, closed: bool) []const Entry {
    var out: std.ArrayList(Entry) = .empty;
    for (ordinary_table, holds, 0..) |item, has, i| {
        const value = if (closed) item.closed else item.opened;
        if (has and value > 0) t.append(Entry, &out, .{ .index = i, .name = item.name, .value = value });
    }
    return out.items;
}
pub fn yakuman(holds: [15]bool, double: bool) []const Entry {
    var out: std.ArrayList(Entry) = .empty;
    for (yakuman_table, holds, 0..) |item, has, i| if (has) t.append(Entry, &out, .{ .index = i,
         .name = item.name, .value = if (double) item.multiplier else 1 });
    return out.items;
}
pub fn names(entries: []const Entry, separator: []const u8) []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| t.append([]const u8, &out, entry.name);
    return t.join(out.items, separator);
}
