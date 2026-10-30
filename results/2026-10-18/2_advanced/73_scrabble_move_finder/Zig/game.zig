const b = @import("board.zig");
pub const Minstd = struct {
    state: i64,
    pub fn next(self: *Minstd) i64 {
        self.state = @mod(48271 * self.state, 2147483647);
        return self.state;
    }
};
pub const Bag = struct { data: [200]u8 = undefined, count: usize = 0 };
pub fn shuffle(bag: *Bag, random: *Minstd) void {
    var i = bag.count;
    while (i > 1) {
        i -= 1;
        const j = b.u(@mod(random.next(), b.n(i + 1)));
        const tile = bag.data[i];
        bag.data[i] = bag.data[j];
        bag.data[j] = tile;
    }
}
pub fn makeBag(counts: b.Counts, random: *Minstd) Bag {
    var out: Bag = .{};
    for (counts, 0..) |count, tile| for (0..b.u(count)) |_| {
        out.data[out.count] = b.tile_order[tile];
        out.count += 1;
    };
    shuffle(&out, random);
    return out;
}
pub fn draw(bag: *Bag, count: usize) b.Word {
    var out: b.Word = .{};
    for (0..@min(count, bag.count)) |_| {
        bag.count -= 1;
        out.add(bag.data[bag.count]);
    }
    return out;
}
pub fn exchange(bag: *Bag, returned: []const u8, random: *Minstd) b.Word {
    const drawn = draw(bag, returned.len);
    var counts = [_]usize{0} ** 128;
    for (returned) |tile| counts[tile] += 1;
    for (counts, 0..) |count, tile| for (0..count) |_| {
        bag.data[bag.count] = @intCast(tile);
        bag.count += 1;
    };
    shuffle(bag, random);
    return drawn;
}
pub fn points(collection: []const u8, values: b.Counts) i64 {
    var total: i64 = 0;
    for (collection) |tile| total += values[b.tileIndex(tile)];
    return total;
}
