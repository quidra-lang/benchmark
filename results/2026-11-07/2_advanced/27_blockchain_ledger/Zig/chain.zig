const std = @import("std");
const h = @import("hashing.zig");
const t = @import("transactions.zig");
const b = @import("blocks.zig");
pub const Record = struct {
    block: b.Block,
    parent: ?*Record,
    utxo: t.Utxo,
    transaction_fees: []const i64,
    source: []const u8,
    fees: i64 = 0,
    work: i64 = 1,
    pub fn create(block: b.Block, parent: ?*Record, utxo: t.Utxo, fees: []const i64, source: []const u8) *Record {
        var record: Record = .{ .block = block, .parent = parent, .utxo = utxo, .transaction_fees = fees, .source = source };
        for (fees) |fee| record.fees += fee;
        if (parent) |previous| {
            var work: i64 = 1;
            for (0..h.u(block.difficulty)) |_| work *= 16;
            record.work = previous.work + work;
        }
        return h.create(Record, record);
    }
};
pub fn reward(height: i64, initial: i64, interval: i64) i64 {
    var value = initial;
    for (0..h.u(@divTrunc(height, interval))) |_| value = @divTrunc(value, 2);
    return value;
}
pub fn ancestor(record: *Record, height: i64) *Record {
    var current = record;
    while (current.block.height > height) current = current.parent.?;
    return current;
}
pub fn chainTo(record: *Record) []*Record {
    const result = h.alloc(*Record, h.u(record.block.height + 1));
    var current: ?*Record = record;
    var index = result.len;
    while (current) |value| {
        index -= 1;
        result[index] = value;
        current = value.parent;
    }
    return result;
}
pub fn forkPoint(first: *Record, second: *Record) *Record {
    const height = @min(first.block.height, second.block.height);
    var a = ancestor(first, height);
    var z = ancestor(second, height);
    while (a != z) {
        a = a.parent.?;
        z = z.parent.?;
    }
    return a;
}
fn timeOrder(_: void, a: i64, z: i64) bool {
    return a < z;
}
pub fn medianTime(record: *Record) i64 {
    var times: [3]i64 = undefined;
    var count: usize = 0;
    var current: ?*Record = record;
    while (current != null and count < 3) {
        times[count] = current.?.block.time;
        count += 1;
        current = current.?.parent;
    }
    std.mem.sort(i64, times[0..count], {}, timeOrder);
    return times[(count - 1) / 2];
}
pub fn requiredDifficulty(parent: *Record, initial: i64, interval: i64, target: i64) i64 {
    const height = parent.block.height + 1;
    const bits = parent.block.difficulty;
    if (height == 1) return initial;
    if (@mod(height, interval) != 0) return bits;
    const span = parent.block.time - ancestor(parent, height - interval).block.time;
    const expected = target * (interval - 1);
    if (2 * span < expected) return @min(bits + 1, 2);
    if (span > 2 * expected) return @max(bits - 1, 0);
    return bits;
}
