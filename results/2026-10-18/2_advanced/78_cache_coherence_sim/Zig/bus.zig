const std = @import("std");
const b = @import("config_io.zig");
const p = @import("protocol.zig");
pub const Transaction = struct {
    number: i64,
    start: i64,
    core: usize,
    kind: p.TransactionKind,
    block: i64,
    snoop_old: [8]u8 = @splat(0),
    snoop_new: [8]u8 = @splat(0),
    copies: [8]u8 = @splat(0),
    snoop_hits: i64 = 0,
    invalidations: usize = 0,
    supplier: ?usize = null,
    flushed: bool = false,
    l2_hit: bool = false,
    evicted: ?i64 = null,
    dirty_eviction: bool = false,
};
pub const Bus = struct {
    latency: i64,
    free: i64 = 0,
    wait: i64 = 0,
    transactions: std.ArrayList(Transaction) = .empty,
    pub fn assign(self: *Bus, core: usize, kind: p.TransactionKind, block: i64, requested: i64) *Transaction {
        const start = @max(requested, self.free);
        self.wait += start - requested;
        self.free = start + self.latency;
        b.append(Transaction, &self.transactions, .{ .number = b.n(self.transactions.items.len) + 1,
             .start = start, .core = core, .kind = kind, .block = block });
        return &self.transactions.items[self.transactions.items.len - 1];
    }
    pub fn logLine(self: *const Bus, tx: Transaction, line_size: i64, cores: usize) []const u8 {
        _ = self;
        var out: b.Text = .{};
        out.add("{d} {d} c{d} {s} {s}", .{ tx.number, tx.start, tx.core, p.transaction_names[@intFromEnum(tx.kind)],
             b.hexAddress(tx.block * line_size) });
        if (tx.kind == .wb) return out.value();
        var snoops: std.ArrayList([]const u8) = .empty;
        for (0..cores) |core| if (tx.snoop_old[core] != 0) b.append([]const u8, &snoops, b.fmt("c{d}:{c}>{c}",
             .{ core, tx.snoop_old[core], tx.snoop_new[core] }));
        out.add(" snoop {s}", .{if (snoops.items.len == 0) "none" else b.join(snoops.items, " ")});
        if (tx.kind == .upgr) return out.value();
        if (tx.kind == .rd or tx.kind == .rdx) out.add(" data {s}", .{if (tx.supplier) |core| b.fmt("c{d}",
             .{core}) else if (tx.l2_hit) "L2" else "mem"});
        out.add(" l2 {s}", .{if (tx.l2_hit) "hit" else "miss"});
        if (tx.evicted) |block| {
            var copies: std.ArrayList([]const u8) = .empty;
            for (0..cores) |core| if (tx.copies[core] != 0) b.append([]const u8, &copies, b.fmt("c{d}:{c}",
                 .{ core, tx.copies[core] }));
            out.add(" evict {s} {s} {s}", .{ b.hexAddress(block * line_size), if (copies.items.len == 0) "none" else b.join(copies.items,
                 " "), if (tx.dirty_eviction) "dirty" else "clean" });
        }
        return out.value();
    }
};
