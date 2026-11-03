const std = @import("std");
const d = @import("eventlog.zig");
pub const Net = struct {
    places: []const []const u8,
    transitions: []const []const u8,
    inputs: []bool,
    outputs: []bool,
    initial: usize,
    final: usize,
    arc_count: usize = 0,
    pub fn init(places: []const []const u8, transitions: []const []const u8, initial: []const u8,
         final: []const u8) Net {
        const ordered = d.dupe([]const u8, transitions);
        std.mem.sort([]const u8, ordered, {}, d.nameLess);
        const inputs = d.alloc(bool, places.len * transitions.len);
        const outputs = d.alloc(bool, inputs.len);
        @memset(inputs, false);
        @memset(outputs, false);
        return .{ .places = places, .transitions = ordered, .inputs = inputs, .outputs = outputs,
             .initial = d.indexOf(places, initial).?, .final = d.indexOf(places, final).? };
    }
    pub fn arc(self: *Net, from: []const u8, to: []const u8) void {
        const source = d.indexOf(self.transitions, from);
        const t = source orelse d.indexOf(self.transitions, to).?;
        const p = d.indexOf(self.places, if (source == null) from else to).?;
        const location = t * self.places.len + p;
        const data = if (source == null) self.inputs else self.outputs;
        if (!data[location]) {
            data[location] = true;
            self.arc_count += 1;
        }
    }
    pub fn enabled(self: Net, marking: []const u8, t: usize) bool {
        for (marking, 0..) |tokens, p| if (self.inputs[t * self.places.len + p] and tokens == 0) return false;
        return true;
    }
    pub fn fire(self: Net, before: []const u8, t: usize, after: []u8) void {
        for (before, after, 0..) |tokens, *value, p| value.* = tokens - @as(u8, @intFromBool(self.inputs[t * self.places.len + p])) + @as(u8,
             @intFromBool(self.outputs[t * self.places.len + p]));
    }
    pub fn initialMarking(self: Net) []u8 {
        const out = d.alloc(u8, self.places.len);
        @memset(out, 0);
        out[self.initial] = 1;
        return out;
    }
    pub fn finalMarking(self: Net) []u8 {
        const out = d.alloc(u8, self.places.len);
        @memset(out, 0);
        out[self.final] = 1;
        return out;
    }
};
pub fn readModel(io: std.Io) !Net {
    var places: std.ArrayList([]const u8) = .empty;
    var transitions: std.ArrayList([]const u8) = .empty;
    var arcs: std.ArrayList([2][]const u8) = .empty;
    var initial: []const u8 = undefined;
    var final: []const u8 = undefined;
    for (try d.readLines(io, "input/model.txt")) |line| {
        const row = d.words(line);
        if (d.eq(row[0], "PLACE")) d.append([]const u8, &places, row[1]) else if (d.eq(row[0],
             "TRANSITION")) d.append([]const u8, &transitions, row[1]) else if (d.eq(row[0],
             "ARC")) d.append([2][]const u8, &arcs, .{ row[1], row[2] }) else if (d.eq(row[0],
             "INITIAL")) initial = row[1] else final = row[1];
    }
    var net = Net.init(places.items, transitions.items, initial, final);
    for (arcs.items) |arc| net.arc(arc[0], arc[1]);
    return net;
}
pub const Replay = struct {
    missing: i64 = 0,
    remaining: i64 = 0,
    consumed: i64 = 0,
    produced: i64 = 0,
    skipped: i64 = 0,
    place_missing: []i64,
    place_remaining: []i64,
    deviating: []i64,
    wait_count: []i64,
    wait_sum: []i64,
    wait_max: []i64,
    routes: []i64,
    pub fn init(net: Net) Replay {
        var out: Replay = .{ .place_missing = d.alloc(i64, net.places.len), .place_remaining = d.alloc(i64,
             net.places.len), .deviating = d.alloc(i64, net.places.len), .wait_count = d.alloc(i64,
             net.places.len), .wait_sum = d.alloc(i64, net.places.len), .wait_max = d.alloc(i64,
             net.places.len), .routes = d.alloc(i64, net.places.len * net.transitions.len) };
        out.clear();
        return out;
    }
    pub fn clear(self: *Replay) void {
        self.missing = 0;
        self.remaining = 0;
        self.consumed = 0;
        self.produced = 0;
        self.skipped = 0;
        for ([_][]i64{ self.place_missing, self.place_remaining, self.deviating, self.wait_count,
             self.wait_sum, self.wait_max, self.routes }) |values| @memset(values, 0);
    }
    pub fn fitness(self: Replay) d.Fraction {
        const one = d.Fraction.init(1, 1);
        const half = d.Fraction.init(1, 2);
        return half.mul(one.sub(d.Fraction.init(self.missing, self.consumed))).add(half.mul(one.sub(d.Fraction.init(self.remaining,
             self.produced))));
    }
};
