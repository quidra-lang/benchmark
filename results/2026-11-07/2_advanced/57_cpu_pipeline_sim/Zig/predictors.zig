const std = @import("std");
const c = @import("trace_io.zig");
const Entry = struct { pc: i64, target: i64 };
pub const BTB = struct {
    entries: []?Entry,
    pub fn init(count: usize) BTB {
        const entries = c.alloc(?Entry, count);
        @memset(entries, null);
        return .{ .entries = entries };
    }
    pub fn lookup(self: BTB, pc: i64) ?i64 {
        const entry = self.entries[c.u(@divTrunc(pc, 4)) % self.entries.len] orelse return null;
        return if (entry.pc == pc) entry.target else null;
    }
    pub fn insert(self: *BTB, pc: i64, target: i64) void {
        self.entries[c.u(@divTrunc(pc, 4)) % self.entries.len] = .{ .pc = pc, .target = target };
    }
};
pub const RAS = struct {
    depth: usize,
    count: usize = 0,
    stack: [16]i64 = undefined,
    pub fn push(self: *RAS, value: i64) void {
        if (self.depth == 0) return;
        if (self.count == self.depth) {
            std.mem.copyForwards(i64, self.stack[0 .. self.count - 1], self.stack[1..self.count]);
            self.count -= 1;
        }
        self.stack[self.count] = value;
        self.count += 1;
    }
    pub fn pop(self: *RAS) ?i64 {
        if (self.count == 0) return null;
        self.count -= 1;
        return self.stack[self.count];
    }
};
fn updated(counter: i64, taken: bool) i64 {
    return if (taken) @min(3, counter + 1) else @max(0, counter - 1);
}
fn table(count: usize, initial: i64) []i64 {
    const out = c.alloc(i64, count);
    @memset(out, initial);
    return out;
}
pub const Direction = struct {
    definition: c.Predictor,
    values: []i64 = &.{},
    local: []i64 = &.{},
    global_values: []i64 = &.{},
    chooser: []i64 = &.{},
    history: usize = 0,
    pub fn init(definition: c.Predictor) Direction {
        var out: Direction = .{ .definition = definition };
        const s = definition.scheme;
        const p = definition.parameters;
        if (c.eq(s, "ONEBIT") or c.eq(s, "TWOBIT") or c.eq(s, "GSHARE")) out.values = table(p[0],
             if (c.eq(s, "ONEBIT")) 0 else 1);
        if (c.eq(s, "TOURNAMENT")) {
            out.local = table(p[0], 1);
            out.global_values = table(p[1], 1);
            out.chooser = table(p[3], 1);
        }
        return out;
    }
    pub fn prediction(self: Direction, pc: i64, target: i64) bool {
        const s = self.definition.scheme;
        const index = c.u(@divTrunc(pc, 4));
        if (c.eq(s, "STATIC_NT") or c.eq(s, "PERFECT")) return false;
        if (c.eq(s, "BTFN")) return target < pc;
        if (c.eq(s, "ONEBIT")) return self.values[index % self.values.len] == 1;
        if (c.eq(s, "TWOBIT")) return self.values[index % self.values.len] >= 2;
        if (c.eq(s, "GSHARE")) return self.values[(index ^ self.history) % self.values.len] >= 2;
        return if (self.chooser[index % self.chooser.len] >= 2) self.global_values[(index ^ self.history) % self.global_values.len] >= 2 else self.local[index % self.local.len] >= 2;
    }
    pub fn update(self: *Direction, pc: i64, taken: bool) void {
        const s = self.definition.scheme;
        const p = self.definition.parameters;
        const index = c.u(@divTrunc(pc, 4));
        if (c.eq(s, "STATIC_NT") or c.eq(s, "BTFN") or c.eq(s, "PERFECT")) return;
        if (c.eq(s, "TOURNAMENT")) {
            const l = index % self.local.len;
            const g = (index ^ self.history) % self.global_values.len;
            const ch = index % self.chooser.len;
            if ((self.local[l] >= 2) != (self.global_values[g] >= 2)) self.chooser[ch] = updated(self.chooser[ch],
                 (self.global_values[g] >= 2) == taken);
            self.local[l] = updated(self.local[l], taken);
            self.global_values[g] = updated(self.global_values[g], taken);
            self.history = (2 * self.history + @intFromBool(taken)) % (@as(usize, 1) << @intCast(p[2]));
        } else {
            const global = c.eq(s, "GSHARE");
            const t = (if (global) index ^ self.history else index) % self.values.len;
            self.values[t] = if (c.eq(s, "ONEBIT")) @intFromBool(taken) else updated(self.values[t], taken);
            if (global) self.history = (2 * self.history + @intFromBool(taken)) % (@as(usize, 1) << @intCast(p[1]));
        }
    }
    pub fn bits(self: Direction) usize {
        const s = self.definition.scheme;
        const p = self.definition.parameters;
        if (c.eq(s, "ONEBIT")) return p[0];
        if (c.eq(s, "TWOBIT")) return 2 * p[0];
        if (c.eq(s, "GSHARE")) return 2 * p[0] + p[1];
        if (c.eq(s, "TOURNAMENT")) return 2 * (p[0] + p[1] + p[3]) + p[2];
        return 0;
    }
};
