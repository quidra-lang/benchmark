const std = @import("std");
const b = @import("config_io.zig");
pub const Entry = struct { block: i64, state: u8 };
pub const CacheSet = struct { entries: [16]?Entry = @splat(null), touched: [16]i64 = @splat(0),
     bits: [16]u8 = @splat(0), fills: i64 = 0, evictions: i64 = 0 };
pub const Cache = struct {
    ways: usize,
    replacement: b.Replacement,
    sets: []CacheSet,
    clock: i64 = 0,
    pub fn init(sets: usize, ways: usize, replacement: b.Replacement) Cache {
        return .{ .ways = ways, .replacement = replacement, .sets = b.zero(CacheSet, sets, .{}) };
    }
    fn row(self: *const Cache, block: i64) usize {
        return b.u(@mod(block, b.n(self.sets.len)));
    }
    pub fn locate(self: *const Cache, block: i64) ?usize {
        for (self.sets[self.row(block)].entries[0..self.ways], 0..) |entry, i| if (entry) |value| if (value.block == block) return i;
        return null;
    }
    pub fn state(self: *const Cache, block: i64) u8 {
        return if (self.locate(block)) |way| self.sets[self.row(block)].entries[way].?.state else 'I';
    }
    pub fn change(self: *Cache, block: i64, state_value: u8) void {
        if (self.locate(block)) |way| self.sets[self.row(block)].entries[way].?.state = state_value;
    }
    fn touchWay(self: *Cache, row_index: usize, way: usize, fill_value: bool) void {
        const set = &self.sets[row_index];
        if (self.replacement == .lru or (self.replacement == .fifo and fill_value)) {
            self.clock += 1;
            set.touched[way] = self.clock;
        } else if (self.replacement == .plru) {
            var lo: usize = 0;
            var hi = self.ways;
            var node: usize = 1;
            while (hi - lo > 1) {
                const mid = (lo + hi) / 2;
                if (way < mid) {
                    set.bits[node] = 1;
                    hi = mid;
                    node *= 2;
                } else {
                    set.bits[node] = 0;
                    lo = mid;
                    node = 2 * node + 1;
                }
            }
        }
    }
    pub fn touch(self: *Cache, block: i64) void {
        if (self.locate(block)) |way| self.touchWay(self.row(block), way, false);
    }
    fn victim(self: *const Cache, row_index: usize) usize {
        const set = &self.sets[row_index];
        if (self.replacement == .plru) {
            var lo: usize = 0;
            var hi = self.ways;
            var node: usize = 1;
            while (hi - lo > 1) {
                const mid = (lo + hi) / 2;
                if (set.bits[node] == 0) {
                    hi = mid;
                    node *= 2;
                } else {
                    lo = mid;
                    node = node * 2 + 1;
                }
            }
            return lo;
        }
        var best: usize = 0;
        for (1..self.ways) |way| if (set.touched[way] < set.touched[best]) {
            best = way;
        };
        return best;
    }
    pub fn fill(self: *Cache, block: i64, state_value: u8) ?Entry {
        const row_index = self.row(block);
        const set = &self.sets[row_index];
        var chosen: ?usize = null;
        for (set.entries[0..self.ways], 0..) |entry, way| if (entry == null) {
            chosen = way;
            break;
        };
        const way = chosen orelse self.victim(row_index);
        const old = set.entries[way];
        if (old != null) set.evictions += 1;
        set.entries[way] = .{ .block = block, .state = state_value };
        set.fills += 1;
        self.touchWay(row_index, way, true);
        return old;
    }
    pub fn remove(self: *Cache, block: i64) ?Entry {
        const way = self.locate(block) orelse return null;
        const entry = &self.sets[self.row(block)].entries[way];
        const old = entry.*;
        entry.* = null;
        return old;
    }
    pub fn order(self: *const Cache, row_index: usize) []const u8 {
        const set: *const CacheSet = &self.sets[row_index];
        if (self.replacement == .plru) {
            if (self.ways == 1) return "-";
            const out = b.alloc(u8, self.ways - 1);
            for (out, 1..) |*digit, i| digit.* = '0' + set.bits[i];
            return out;
        }
        var active: [16]usize = undefined;
        var count: usize = 0;
        for (set.entries[0..self.ways], 0..) |entry, way| if (entry != null) {
            active[count] = way;
            count += 1;
        };
        std.mem.sort(usize, active[0..count], set, struct {
            fn less(row_value: *const CacheSet, left: usize, right: usize) bool {
                return if (row_value.touched[left] != row_value.touched[right]) row_value.touched[left] > row_value.touched[right] else left < right;
            }
        }.less);
        var values: std.ArrayList([]const u8) = .empty;
        for (active[0..count]) |way| b.append([]const u8, &values, b.fmt("{d}", .{way}));
        return if (count == 0) "-" else b.join(values.items, " ");
    }
};
