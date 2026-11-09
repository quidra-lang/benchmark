const std = @import("std");
const c = @import("bitio.zig");
const top: i64 = 65535;
const half: i64 = 32768;
const quarter: i64 = 16384;
const three: i64 = 49152;
const Context = struct {
    frequency: [257]i64 = @splat(1),
    total: i64 = 257,
    fn cumulative(self: *const Context, symbol: usize) i64 {
        var sum: i64 = 0;
        for (self.frequency[0..symbol]) |value| sum += value;
        return sum;
    }
};
const Contexts = struct {
    tables: [256]?*Context = @splat(null),
    contexts: usize = 0,
    rescales: usize = 0,
    fn get(self: *Contexts, index: usize) *Context {
        if (self.tables[index] == null) {
            const table = c.allocator.create(Context) catch @panic("allocation failed");
            table.* = .{};
            self.tables[index] = table;
            self.contexts += 1;
        }
        return self.tables[index].?;
    }
    fn update(self: *Contexts, table: *Context, symbol: usize) void {
        table.frequency[symbol] += 32;
        table.total += 32;
        if (table.total >= 8192) {
            table.total = 0;
            for (&table.frequency) |*value| {
                value.* = @divFloor(value.* + 1, 2);
                table.total += value.*;
            }
            self.rescales += 1;
        }
    }
};
pub const Statistics = struct { bits: usize = 0, contexts: usize = 0, rescales: usize = 0 };
fn emit(writer: *c.Writer, bit: u32, follow: *usize) void {
    writer.write(bit, 1);
    while (follow.* > 0) {
        writer.write(1 - bit, 1);
        follow.* -= 1;
    }
}
pub fn encode(data: []const u8, stats: *Statistics) []const u8 {
    var contexts: Contexts = .{};
    var writer: c.Writer = .{};
    var low: i64 = 0;
    var high: i64 = top;
    var follow: usize = 0;
    var context: usize = 10;
    for (0..data.len + 1) |i| {
        const symbol: usize = if (i == data.len) 256 else data[i];
        const table = contexts.get(context);
        const range = high - low + 1;
        const total = table.cumulative(symbol);
        const old = low;
        high = old + @divFloor(range * (total + table.frequency[symbol]), table.total) - 1;
        low = old + @divFloor(range * total, table.total);
        while (true) {
            if (high < half) emit(&writer, 0, &follow) else if (low >= half) {
                emit(&writer, 1, &follow);
                low -= half;
                high -= half;
            } else if (low >= quarter and high < three) {
                follow += 1;
                low -= quarter;
                high -= quarter;
            } else break;
            low *= 2;
            high = 2 * high + 1;
        }
        if (symbol != 256) {
            contexts.update(table, symbol);
            context = symbol;
        }
    }
    follow += 1;
    emit(&writer, if (low < quarter) 0 else 1, &follow);
    stats.* = .{ .bits = writer.count, .contexts = contexts.contexts, .rescales = contexts.rescales };
    return writer.bytes.items;
}
pub fn decode(payload: []const u8, size: usize, output: *c.Bytes) c.DecodeError!void {
    var contexts: Contexts = .{};
    var reader: c.Reader = .{ .bytes = payload, .zero_extend = true };
    var low: i64 = 0;
    var high: i64 = top;
    var value: i64 = try reader.read(16);
    var context: usize = 10;
    while (true) {
        const table = contexts.get(context);
        const range = high - low + 1;
        const q = @divFloor((value - low + 1) * table.total - 1, range);
        var symbol: usize = 0;
        var total: i64 = 0;
        while (total + table.frequency[symbol] <= q) : (symbol += 1) total += table.frequency[symbol];
        const old = low;
        high = old + @divFloor(range * (total + table.frequency[symbol]), table.total) - 1;
        low = old + @divFloor(range * total, table.total);
        while (true) {
            if (high < half) {} else if (low >= half) {
                low -= half;
                high -= half;
                value -= half;
            } else if (low >= quarter and high < three) {
                low -= quarter;
                high -= quarter;
                value -= quarter;
            } else break;
            low *= 2;
            high = 2 * high + 1;
            value = 2 * value + try reader.read(1);
        }
        if (symbol == 256) {
            if (output.items.len < size) return error.early_end;
            return;
        }
        if (output.items.len == size) return error.overrun;
        c.append(u8, output, @intCast(symbol));
        contexts.update(table, symbol);
        context = symbol;
    }
}
