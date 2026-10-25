const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var out: std.ArrayList(u8) = .empty;

var why: S = "";

var error_line: usize = 0;

fn eq(a: S, b: S) bool {
    return std.mem.eql(u8, a, b);
}

fn fmt(comptime f: S, a: anytype) !S {
    return std.fmt.allocPrint(A, f, a);
}

fn fail(comptime f: S, a: anytype) anyerror {
    why = fmt(f, a) catch unreachable;
    return error.Invalid;
}

fn put(s: S) !void {
    try out.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}

fn words(s: S) ![]S {
    var a: std.ArrayList(S) = .empty;
    var it = std.mem.tokenizeScalar(u8, s, ' ');
    while (it.next()) |w| try a.append(A, w);
    return a.toOwnedSlice(A);
}

fn contains(a: []const S, s: S) bool {
    for (a) |x| if (eq(x, s)) return true;
    return false;
}

fn name(s: S, upper: bool) bool {
    if (s.len == 0 or s.len > 16 or !(if (upper) std.ascii.isUpper(s[0]) else std.ascii.isLower(s[0]))) return false;
    for (s) |c| if (!(if (upper) std.ascii.isUpper(c) else std.ascii.isLower(c)) and !std.ascii.isDigit(c) and c != '_') return false;
    return true;
}

fn number(s: S, positive: bool) !u64 {
    if (s.len == 0 or s.len > 9 or (s.len > 1 and s[0] == '0')) return fail("bad number {s}", .{ s });
    for (s) |c| if (!std.ascii.isDigit(c)) return fail("bad number {s}", .{ s });
    const n = std.fmt.parseInt(u64, s, 10) catch return fail("bad number {s}", .{ s });
    if (positive and n == 0) return fail("bad number {s}", .{ s });
    return n;
}

fn value(s: S) !u8 {
    if (s.len != 1 or std.mem.indexOfScalar(u8, "01X", s[0]) == null) return fail("bad value {s}", .{ s });
    return s[0];
}

const Kind = enum {
    AND,
    OR,
    NAND,
    NOR,
    XOR,
    XNOR,
    NOT,
    BUF,
    MUX2,
    DFF
};

const Body = struct {
    w: []S,
    ln: usize
};

const Module = struct {
    name: S,
    inputs: []S,
    outputs: []S,
    body: []Body
};

var modules: std.ArrayList(Module) = .empty;

fn lookup(s: S) ?usize {
    for (modules.items, 0..) |m, i| if (eq(m.name, s)) return i;
    return null;
}

fn module(s: S) !usize {
    return lookup(s) orelse fail("unknown module {s}", .{ s });
}

fn definition(header: []S, body: []Body, ln: usize) anyerror!void {
    error_line = ln;
    if (header.len < 5 or !eq(header[2], "IN") or eq(header[header.len - 1], "OUT")) return fail("bad module header", .{});
    var op: ?usize = null;
    for (header[3..], 3..) |w, i| if (eq(w, "OUT")) {
        if (op != null) return fail("bad module header", .{});
        op = i;
    };
    const split = op orelse return fail("bad module header", .{});
    if (!name(header[1], true)) return fail("bad module name {s}", .{ header[1] });
    if (lookup(header[1]) != null) return fail("duplicate module {s}", .{ header[1] });
    var ports: std.ArrayList(S) = .empty;
    for (header[3..], 3..) |w, i| {
        if (i == split) continue;
        if (!name(w, false)) return fail("bad name {s}", .{ w });
        if (contains(ports.items, w)) return fail("duplicate port {s}", .{ w });
        try ports.append(A, w);
    }
    const inputs = header[3..split];
    const outputs = header[split + 1..];
    var driven: std.ArrayList(S) = .empty;
    try driven.appendSlice(A, inputs);
    var used: std.ArrayList(S) = .empty;
    var references: std.ArrayList(struct {
        s: S,
        ln: usize
    }) = .empty;
    var ng: usize = 0;
    var ni: usize = 0;
    for (body) |b| {
        error_line = b.ln;
        const w = b.w;
        if (std.meta.stringToEnum(Kind, w[0])) |k| {
            if (w.len < 5 or !eq(w[w.len - 3], "->")) return fail("bad gate syntax", .{});
            var arrows: usize = 0;
            for (w) |s| if (eq(s, "->")) {
                arrows += 1;
            };
            if (arrows != 1) return fail("bad gate syntax", .{});
            if (!name(w[1], false)) return fail("bad name {s}", .{ w[1] });
            const c = w.len - 5;
            const good = switch (k) {
                .NOT,
                .BUF => c == 1,
                .MUX2 => c == 3,
                .DFF => c == 2,
                else => c >= 2 and c <= 8
            };
            if (!good) return fail("bad input count {d} for {s}", .{ c, w[0] });
            for (w[2..w.len - 3]) |s| if (!name(s, false)) return fail("bad name {s}", .{ s });
            const dest = w[w.len - 2];
            if (!name(dest, false)) return fail("bad name {s}", .{ dest });
            const d = number(w[w.len - 1], false) catch return fail("bad delay {s}", .{ w[w.len - 1] });
            if (d > 1000) return fail("bad delay {s}", .{ w[w.len - 1] });
            if (contains(used.items, w[1])) return fail("duplicate name {s}", .{ w[1] });
            if (contains(driven.items, dest)) return fail("multiple drivers for {s}", .{ dest });
            try used.append(A, w[1]);
            try driven.append(A, dest);
            for (w[2..w.len - 3]) |s| try references.append(A, .{ .s = s, .ln = b.ln });
            ng += 1;
        } else if (eq(w[0], "INST")) {
            if (w.len < 3) return fail("bad instance syntax", .{});
            if (!name(w[1], false)) return fail("bad name {s}", .{ w[1] });
            const mi = try module(w[2]);
            const m = modules.items[mi];
            var ps: std.ArrayList(S) = .empty;
            var os: std.ArrayList(S) = .empty;
            for (w[3..]) |conn| {
                const e = std.mem.indexOfScalar(u8, conn, '=') orelse return fail("bad connection {s}", .{ conn });
                if (e == 0 or e + 1 == conn.len or std.mem.indexOfScalar(u8, conn[e + 1..], '=') != null) return fail("bad connection {s}", .{ conn });
                const p = conn[0..e];
                const s = conn[e + 1..];
                if (!contains(m.inputs, p) and !contains(m.outputs, p)) return fail("unknown port {s}", .{ p });
                if (contains(ps.items, p)) return fail("duplicate connection {s}", .{ p });
                if (!name(s, false)) return fail("bad name {s}", .{ s });
                try ps.append(A, p);
                if (contains(m.outputs, p)) try os.append(A, s) else try references.append(A, .{ .s = s, .ln = b.ln });
            }
            for (m.inputs) |p| if (!contains(ps.items, p)) return fail("unconnected input {s}", .{ p });
            if (contains(used.items, w[1])) return fail("duplicate name {s}", .{ w[1] });
            for (os.items) |s| {
                if (contains(driven.items, s)) return fail("multiple drivers for {s}", .{ s });
                try driven.append(A, s);
            }
            try used.append(A, w[1]);
            ni += 1;
        } else return fail("unknown statement {s}", .{ w[0] });
    }
    for (references.items) |r| if (!contains(driven.items, r.s)) {
        error_line = r.ln;
        return fail("undriven signal {s}", .{ r.s });
    };
    error_line = ln;
    for (outputs) |s| if (!contains(driven.items, s)) return fail("undriven signal {s}", .{ s });
    try modules.append(A, .{ .name = header[1], .inputs = inputs, .outputs = outputs, .body = body });
    try line(try fmt("defined {s} inputs {d} outputs {d} gates {d} instances {d}", .{ header[1], inputs.len, outputs.len, ng, ni }));
}

const Raw = struct {
    name: S,
    k: Kind,
    inputs: []S,
    output: S,
    delay: u64
};

const Gate = struct {
    name: S,
    k: Kind,
    ins: []usize,
    output: usize,
    delay: u64
};

const Flat = struct {
    mi: usize,
    n: usize,
    signals: []S,
    outputs: []usize,
    gates: []Gate
};

fn actual(s: S, prefix: S, map: std.StringHashMap(S)) !S {
    return map.get(s) orelse try fmt("{s}{s}", .{ prefix, s });
}

fn expand(mi: usize, prefix: S, map: std.StringHashMap(S), raw: *std.ArrayList(Raw)) anyerror!void {
    for (modules.items[mi].body) |b| {
        const w = b.w;
        if (eq(w[0], "INST")) {
            var child = std.StringHashMap(S).init(A);
            for (w[3..]) |conn| {
                const e = std.mem.indexOfScalar(u8, conn, '=').?;
                try child.put(conn[0..e], try actual(conn[e + 1..], prefix, map));
            }
            try expand(lookup(w[2]).?, try fmt("{s}{s}.", .{ prefix, w[1] }), child, raw);
        } else {
            const ins = try A.alloc(S, w.len - 5);
            for (w[2..w.len - 3], 0..) |s, i| ins[i] = try actual(s, prefix, map);
            try raw.append(A, .{
                .name = try fmt("{s}{s}", .{ prefix, w[1] }),
                .k = std.meta.stringToEnum(Kind, w[0]).?,
                .inputs = ins,
                .output = try actual(w[w.len - 2], prefix, map),
                .delay = try number(w[w.len - 1], false)
            });
        }
    }
}

fn signal(f: Flat, s: S) ?usize {
    for (f.signals, 0..) |v, i| if (eq(v, s)) return i;
    return null;
}

fn flatten(mi: usize) !Flat {
    const m = modules.items[mi];
    var raw: std.ArrayList(Raw) = .empty;
    try expand(mi, "", std.StringHashMap(S).init(A), &raw);
    const sig = try A.alloc(S, m.inputs.len + raw.items.len);
    @memcpy(sig[0..m.inputs.len], m.inputs);
    for (raw.items, 0..) |g, i| sig[m.inputs.len + i] = g.output;
    const f = Flat{
        .mi = mi,
        .n = m.inputs.len,
        .signals = sig,
        .outputs = try A.alloc(usize, m.outputs.len),
        .gates = try A.alloc(Gate, raw.items.len)
    };
    for (m.outputs, 0..) |s, i| f.outputs[i] = signal(f, s).?;
    for (raw.items, 0..) |g, i| {
        const ins = try A.alloc(usize, g.inputs.len);
        for (g.inputs, 0..) |s, j| ins[j] = signal(f, s).?;
        f.gates[i] = .{ .name = g.name, .k = g.k, .ins = ins, .output = f.n + i, .delay = g.delay };
    }
    return f;
}

fn reads(g: Gate, s: usize) bool {
    for (g.ins) |v| if (v == s) return true;
    return false;
}

fn order(f: Flat) !?[]usize {
    const known = try A.alloc(bool, f.signals.len);
    @memset(known, false);
    @memset(known[0..f.n], true);
    for (f.gates) |g| if (g.k == .DFF) {
        known[g.output] = true;
    };
    var list: std.ArrayList(usize) = .empty;
    var changed = true;
    while (changed) {
        changed = false;
        for (f.gates, 0..) |g, i| {
            if (known[g.output]) continue;
            var ready = true;
            for (g.ins) |s| if (!known[s]) {
                ready = false;
            };
            if (ready) {
                known[g.output] = true;
                try list.append(A, i);
                changed = true;
            }
        }
    }
    for (known) |v| if (!v) return null;
    return try list.toOwnedSlice(A);
}

fn combinational(f: Flat) ![]usize {
    const m = modules.items[f.mi];
    for (f.gates) |g| if (g.k == .DFF) return fail("{s} is not combinational", .{ m.name });
    const ord = (try order(f)) orelse return fail("{s} has a combinational loop", .{ m.name });
    if (f.n > 8) return fail("too many inputs {d}", .{ f.n });
    return ord;
}

fn invert(c: u8) u8 {
    return if (c == 'X') 'X' else if (c == '0') '1' else '0';
}

fn gateValue(g: Gate, v: []const u8) u8 {
    if (g.k == .BUF) return v[g.ins[0]];
    if (g.k == .NOT) return invert(v[g.ins[0]]);
    if (g.k == .MUX2) {
        const s = v[g.ins[0]];
        const a = v[g.ins[1]];
        const b = v[g.ins[2]];
        return if (s == '0') a else if (s == '1') b else if (a == b) a else 'X';
    }
    var zeros = false;
    var ones = false;
    var unknown = false;
    var parity = false;
    for (g.ins) |s| {
        zeros = zeros or v[s] == '0';
        ones = ones or v[s] == '1';
        unknown = unknown or v[s] == 'X';
        if (v[s] == '1') parity = !parity;
    }
    const x: u8 = switch (g.k) {
        .AND,
        .NAND => if (zeros) '0' else if (unknown) 'X' else '1',
        .OR,
        .NOR => if (ones) '1' else if (unknown) 'X' else '0',
        else => if (unknown) 'X' else if (parity) '1' else '0'
    };
    return if (g.k == .NAND or g.k == .NOR or g.k == .XNOR) invert(x) else x;
}

fn bits(n: usize, r: usize) !S {
    const b = try A.alloc(u8, n);
    for (0..n) |i| b[i] = if (r & (@as(usize, 1) << @intCast(n - 1 - i)) == 0) '0' else '1';
    return b;
}

fn evaluate(f: Flat, ord: []usize, r: usize, fault: ?usize, v: u8) !S {
    const vals = try A.alloc(u8, f.signals.len);
    @memset(vals, 'X');
    const b = try bits(f.n, r);
    @memcpy(vals[0..f.n], b);
    if (fault) |s| if (s < f.n) {
        vals[s] = v;
    };
    for (ord) |i| {
        const g = f.gates[i];
        vals[g.output] = if (fault == g.output) v else gateValue(g, vals);
    }
    const result = try A.alloc(u8, f.outputs.len);
    for (f.outputs, 0..) |s, i| result[i] = vals[s];
    return result;
}

fn hierarchy(mi: usize, depth: usize) anyerror!void {
    for (modules.items[mi].body) |b| if (eq(b.w[0], "INST")) {
        for (0..depth * 2) |_| try put(" ");
        try line(try fmt("{s} {s}", .{ b.w[1], b.w[2] }));
        try hierarchy(lookup(b.w[2]).?, depth + 1);
    };
}

fn path(f: Flat, end: usize, prev: []?usize) !S {
    var p = end;
    var s = f.signals[p];
    while (prev[p]) |q| {
        s = try fmt("{s} -> {s}", .{ f.signals[q], s });
        p = q;
    }
    return s;
}

fn timing(f: Flat, period: bool) !void {
    const m = modules.items[f.mi];
    var ff: usize = 0;
    for (f.gates) |g| if (g.k == .DFF) {
        ff += 1;
    };
    if (period and ff == 0) return fail("{s} has no flip-flops", .{ m.name });
    const ord = (try order(f)) orelse return fail("{s} has a combinational loop", .{ m.name });
    const latest = try A.alloc(?u64, f.signals.len);
    const earliest = try A.alloc(?u64, f.signals.len);
    const prev = try A.alloc(?usize, f.signals.len);
    @memset(latest, null);
    @memset(earliest, null);
    @memset(prev, null);
    if (period) {
        for (f.gates) |g| if (g.k == .DFF) {
            latest[g.output] = g.delay;
            earliest[g.output] = g.delay;
        };
    } else {
        for (0..f.n) |i| {
            latest[i] = 0;
            earliest[i] = 0;
        }
    }
    for (ord) |i| {
        const g = f.gates[i];
        for (g.ins) |s| if (latest[s]) |l| {
            if (latest[g.output] == null or l + g.delay > latest[g.output].?) {
                latest[g.output] = l + g.delay;
                prev[g.output] = s;
            }
            if (earliest[g.output] == null or earliest[s].? + g.delay < earliest[g.output].?) earliest[g.output] = earliest[s].? + g.delay;
        };
    }
    var endpoint: ?usize = null;
    if (period) {
        for (f.gates) |g| if (g.k == .DFF) {
            const s = g.ins[1];
            if (latest[s] != null and (endpoint == null or latest[s].? > latest[endpoint.?].?)) endpoint = s;
        };
    } else {
        for (f.outputs) |s| {
            if (latest[s]) |l| {
                try line(try fmt("{s} min {d} max {d}", .{ f.signals[s], earliest[s].?, l }));
                if (endpoint == null or l > latest[endpoint.?].?) endpoint = s;
            } else try line(try fmt("{s} unreachable", .{ f.signals[s] }));
        }
    }
    const prefix = if (period) try fmt("flip-flops {d} period", .{ ff }) else "critical";
    if (endpoint) |s| try line(try fmt("{s} {d}: {s}", .{ prefix, latest[s].?, try path(f, s, prev) })) else try line(try fmt("{s} none", .{ prefix }));
}

const Event = struct {
    time: u64,
    s: usize,
    v: u8,
    serial: u64
};

const Change = struct {
    time: u64,
    v: u8
};

const Simulation = struct {
    f: Flat,
    vals: []u8,
    records: []std.ArrayList(Change),
    events: std.ArrayList(Event) = .empty,
    watch: std.ArrayList(usize) = .empty,
    time: u64 = 0,
    processed: u64 = 0,
    serial: u64 = 0,
    halted: bool = false
};

var sim: ?Simulation = null;

fn reset(f: Flat) !Simulation {
    const vals = try A.alloc(u8, f.signals.len);
    @memset(vals, 'X');
    const records = try A.alloc(std.ArrayList(Change), f.signals.len);
    for (records) |*r| r.* = .empty;
    return .{ .f = f, .vals = vals, .records = records };
}

fn eventLess(a: Event, b: Event) bool {
    return a.time < b.time or (a.time == b.time and a.serial < b.serial);
}

fn schedule(s: *Simulation, t: u64, id: usize, v: u8) !void {
    try s.events.append(A, .{ .time = t, .s = id, .v = v, .serial = s.serial });
    s.serial += 1;
    var i = s.events.items.len - 1;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (!eventLess(s.events.items[i], s.events.items[parent])) break;
        std.mem.swap(Event, &s.events.items[i], &s.events.items[parent]);
        i = parent;
    }
}

fn popEvent(s: *Simulation) Event {
    const result = s.events.items[0];
    const last = s.events.pop().?;
    if (s.events.items.len == 0) return result;
    s.events.items[0] = last;
    var i: usize = 0;
    while (2 * i + 1 < s.events.items.len) {
        var child = 2 * i + 1;
        if (child + 1 < s.events.items.len and eventLess(s.events.items[child + 1], s.events.items[child])) child += 1;
        if (!eventLess(s.events.items[child], s.events.items[i])) break;
        std.mem.swap(Event, &s.events.items[i], &s.events.items[child]);
        i = child;
    }
    return result;
}

fn run(s: *Simulation, t: u64) !void {
    if (t <= s.time) return fail("time {d} is not after {d}", .{ t, s.time });
    var total: u64 = 0;
    var glitches: usize = 0;
    while (s.events.items.len > 0) {
        const tau = s.events.items[0].time;
        if (tau >= t) break;
        const start = try A.dupe(u8, s.vals);
        const touched = try A.alloc(bool, s.vals.len);
        @memset(touched, false);
        var count: usize = 0;
        while (s.events.items.len > 0) {
            if (s.events.items[0].time != tau) break;
            if (count == 1000) {
                try line(try fmt("halted: oscillation at time {d}", .{ tau }));
                s.events.clearRetainingCapacity();
                s.time = tau;
                s.halted = true;
                return;
            }
            const e = popEvent(s);
            count += 1;
            total += 1;
            s.processed += 1;
            const old = s.vals[e.s];
            if (old == e.v) continue;
            s.vals[e.s] = e.v;
            touched[e.s] = true;
            for (s.f.gates) |g| if (reads(g, e.s)) {
                if (g.k == .DFF) {
                    if (g.ins[0] == e.s and old == '0' and e.v == '1') try schedule(s, tau + g.delay, g.output, s.vals[g.ins[1]]);
                } else try schedule(s, tau + g.delay, g.output, gateValue(g, s.vals));
            };
        }
        for (s.vals, 0..) |v, i| {
            if (v != start[i]) try s.records[i].append(A, .{ .time = tau, .v = v }) else if (touched[i]) glitches += 1;
        }
        for (s.watch.items) |i| if (s.vals[i] != start[i]) try line(try fmt("{d} {s} {c}", .{ tau, s.f.signals[i], s.vals[i] }));
    }
    s.time = t;
    try line(try fmt("run {d} events {d} glitches {d} pending {d}", .{ t, total, glitches, s.events.items.len }));
}

fn sig(s: *Simulation, n: S) !usize {
    return signal(s.f, n) orelse fail("unknown signal {s}", .{ n });
}

fn inputSig(s: *Simulation, n: S) !usize {
    const i = signal(s.f, n) orelse return fail("not an input {s}", .{ n });
    if (i >= s.f.n) return fail("not an input {s}", .{ n });
    return i;
}

fn time(s: *Simulation, n: S) !u64 {
    const t = try number(n, false);
    if (t < s.time) return fail("time {d} is in the past", .{ t });
    return t;
}

fn watched(s: *Simulation, i: usize) bool {
    for (s.watch.items) |v| if (v == i) return true;
    return false;
}

fn observation(s: *Simulation, c: S, a: []S) !void {
    if (eq(c, "WATCH") or eq(c, "UNWATCH")) {
        const ids = try A.alloc(usize, a.len);
        for (a, 0..) |n, j| {
            const i = try sig(s, n);
            var repeated = false;
            for (ids[0..j]) |v| if (v == i) {
                repeated = true;
            };
            if (eq(c, "WATCH") and (watched(s, i) or repeated)) return fail("already watched {s}", .{ n });
            if (eq(c, "UNWATCH") and (!watched(s, i) or repeated)) return fail("not watched {s}", .{ n });
            ids[j] = i;
        }
        if (eq(c, "WATCH")) try s.watch.appendSlice(A, ids) else {
            var j: usize = 0;
            while (j < s.watch.items.len) {
                var remove = false;
                for (ids) |v| if (v == s.watch.items[j]) {
                    remove = true;
                };
                if (remove) _ = s.watch.orderedRemove(j) else j += 1;
            }
        }
        try put("watching");
        if (s.watch.items.len == 0) try put(" nothing") else for (s.watch.items) |i| try put(try fmt(" {s}", .{ s.f.signals[i] }));
        try put("\n");
    } else if (eq(c, "SHOW")) {
        for (a) |n| {
            _ = try sig(s, n);
        }
        if (a.len > 0) {
            for (a, 0..) |n, j| {
                if (j > 0) try put(" ");
                try put(try fmt("{s}={c}", .{ n, s.vals[(try sig(s, n))] }));
            }
        } else {
            for (0..s.f.n) |i| try put(try fmt("{s}={c} ", .{ s.f.signals[i], s.vals[i] }));
            try put("|");
            for (s.f.outputs) |i| try put(try fmt(" {s}={c}", .{ s.f.signals[i], s.vals[i] }));
        }
        try put("\n");
    } else if (eq(c, "CHECK")) {
        const i = try sig(s, a[0]);
        const v = try value(a[1]);
        try line(if (s.vals[i] == v) try fmt("check {s}={c} ok", .{ a[0], v }) else try fmt("check {s}={c} failed ({c})", .{ a[0], v, s.vals[i] }));
    } else if (eq(c, "PROBE")) {
        const i = try sig(s, a[0]);
        if (i < s.f.n) try line(try fmt("{s}={c} driven by input", .{ a[0], s.vals[i] })) else {
            const g = s.f.gates[i - s.f.n];
            try put(try fmt("{s}={c} driven by {s} {s}", .{ a[0], s.vals[i], g.name, @tagName(g.k) }));
            for (g.ins) |j| try put(try fmt(" {s}={c}", .{ s.f.signals[j], s.vals[j] }));
            try line(try fmt(" delay {d}", .{ g.delay }));
        }
        var count: usize = 0;
        for (s.f.gates) |g| if (reads(g, i)) {
            count += 1;
        };
        try put(try fmt("fanout {d}", .{ count }));
        for (s.f.gates) |g| if (reads(g, i)) try put(try fmt(" {s}", .{ g.name }));
        try put("\n");
    } else if (eq(c, "HISTORY")) {
        const i = try sig(s, a[0]);
        try put(try fmt("history {s} changes {d}", .{ a[0], s.records[i].items.len }));
        for (s.records[i].items) |r| try put(try fmt(" {d}:{c}", .{ r.time, r.v }));
        try put("\n");
    } else if (eq(c, "WAVE")) {
        const t0 = try number(a[0], false);
        const t1 = try number(a[1], false);
        if (t0 >= t1 or t1 > s.time) return fail("bad range {d} {d}", .{ t0, t1 });
        if (s.watch.items.len == 0) return fail("nothing watched", .{});
        for (s.watch.items) |i| {
            try put(try fmt("{s} ", .{ s.f.signals[i] }));
            var t = t0;
            var j: usize = 0;
            var v: u8 = 'X';
            while (t < t1): (t += 1) {
                while (j < s.records[i].items.len and s.records[i].items[j].time <= t): (j += 1) v = s.records[i].items[j].v;
                try out.append(A, v);
            }
            try put("\n");
        }
    } else if (eq(c, "ACTIVITY")) {
        const k = try number(a[0], true);
        const ids = try A.alloc(usize, s.f.signals.len);
        for (ids, 0..) |*v, i| v.* = i;
        const C = struct {
            fn less(ctx: *Simulation, x: usize, y: usize) bool {
                const a1 = ctx.records[x].items.len;
                const b1 = ctx.records[y].items.len;
                return a1 > b1 or (a1 == b1 and std.mem.order(u8, ctx.f.signals[x], ctx.f.signals[y]) == .lt);
            }
        };
        std.mem.sort(usize, ids, s, C.less);
        for (ids[0..@min(k, ids.len)]) |i| try line(try fmt("{s} {d}", .{ s.f.signals[i], s.records[i].items.len }));
    } else if (eq(c, "STATUS")) {
        var zeros: usize = 0;
        var ones: usize = 0;
        for (s.vals) |v| {
            if (v == '0') zeros += 1;
            if (v == '1') ones += 1;
        }
        try line(try fmt("circuit {s} time {d} pending {d} events {d} halted {s}", .{
            modules.items[s.f.mi].name,
            s.time,
            s.events.items.len,
            s.processed,
            if (s.halted) @as(S, "yes") else "no"
        }));
        try line(try fmt("values 0:{d} 1:{d} X:{d}", .{ zeros, ones, s.vals.len - zeros - ones }));
    }
}

fn inspect(c: S, a: []S) !void {
    if (eq(c, "MODULES")) {
        try line(try fmt("modules {d}", .{ modules.items.len }));
        for (modules.items, 0..) |m, i| {
            const f = try flatten(i);
            try line(try fmt("{s} inputs {d} outputs {d} gates {d}", .{ m.name, m.inputs.len, m.outputs.len, f.gates.len }));
        }
        return;
    }
    const mi = try module(a[0]);
    var mi2: usize = 0;
    if (eq(c, "EQUIV")) mi2 = try module(a[1]);
    const f = try flatten(mi);
    const m = modules.items[mi];
    if (eq(c, "BUILD")) {
        sim = try reset(f);
        try line(try fmt("built {s} signals {d} gates {d}", .{ m.name, f.signals.len, f.gates.len }));
    } else if (eq(c, "HIERARCHY")) {
        try line(m.name);
        try hierarchy(mi, 1);
    } else if (eq(c, "NETLIST")) {
        try line(try fmt("netlist {s} gates {d} signals {d}", .{ m.name, f.gates.len, f.signals.len }));
        for (f.gates) |g| {
            try put(try fmt("{s} {s}", .{ g.name, @tagName(g.k) }));
            for (g.ins) |i| try put(try fmt(" {s}", .{ f.signals[i] }));
            try line(try fmt(" -> {s} {d}", .{ f.signals[g.output], g.delay }));
        }
    } else if (eq(c, "STATS")) {
        const ord = try order(f);
        var depth: usize = 0;
        const levels = try A.alloc(usize, f.signals.len);
        @memset(levels, 0);
        if (ord) |o| for (o) |i| {
            const g = f.gates[i];
            var l: usize = 0;
            for (g.ins) |s| l = @max(l, levels[s]);
            levels[g.output] = l + 1;
            depth = @max(depth, l + 1);
        };
        try line(try fmt("stats {s} gates {d} signals {d} depth {s}", .{
            m.name,
            f.gates.len,
            f.signals.len,
            if (ord == null) @as(S, "-") else try fmt("{d}", .{ depth })
        }));
        var counts: [10]usize = [_]usize{
            0
        } ** 10;
        for (f.gates) |g| counts[@intFromEnum(g.k)] += 1;
        try put("types");
        for (counts, 0..) |n, i| if (n > 0) try put(try fmt(" {s} {d}", .{ @tagName(@as(Kind, @enumFromInt(i))), n }));
        try put("\n");
        var best: usize = 0;
        var maximum: usize = 0;
        for (f.signals, 0..) |_, i| {
            var n: usize = 0;
            for (f.gates) |g| if (reads(g, i)) {
                n += 1;
            };
            if (n > maximum) {
                maximum = n;
                best = i;
            }
        }
        try line(try fmt("max fanout {s} {d}", .{ f.signals[best], maximum }));
    } else if (eq(c, "CRITICAL") or eq(c, "PERIOD")) try timing(f, eq(c, "PERIOD")) else {
        const ord = try combinational(f);
        const rows = @as(usize, 1) << @intCast(f.n);
        if (eq(c, "TRUTHTABLE")) {
            for (m.inputs) |s| try put(try fmt("{s} ", .{ s }));
            try put("|");
            for (m.outputs) |s| try put(try fmt(" {s}", .{ s }));
            try put("\n");
            for (0..rows) |r| {
                for (try bits(f.n, r)) |v| try put(try fmt("{c} ", .{ v }));
                try put("|");
                for (try evaluate(f, ord, r, null, 'X')) |v| try put(try fmt(" {c}", .{ v }));
                try put("\n");
            }
        } else if (eq(c, "EQUIV")) {
            const f2 = try flatten(mi2);
            const ord2 = try combinational(f2);
            if (f.n != f2.n or f.outputs.len != f2.outputs.len) return fail("port mismatch", .{});
            for (0..rows) |r| {
                const v = try evaluate(f, ord, r, null, 'X');
                const v2 = try evaluate(f2, ord2, r, null, 'X');
                if (!eq(v, v2)) {
                    try line(try fmt("not equivalent at {s}: {s} vs {s}", .{ try bits(f.n, r), v, v2 }));
                    return;
                }
            }
            try line("equivalent");
        } else if (eq(c, "FAULTS")) {
            var undetected: std.ArrayList(S) = .empty;
            const tests = try A.alloc(bool, rows);
            @memset(tests, false);
            var detected: usize = 0;
            for (f.signals, 0..) |s, i| {
                for ("01") |v| {
                    var found = false;
                    for (0..rows) |r| if (!eq(try evaluate(f, ord, r, null, 'X'), try evaluate(f, ord, r, i, v))) {
                        found = true;
                        tests[r] = true;
                        break;
                    };
                    if (found) detected += 1 else try undetected.append(A, try fmt("undetected {s}/{c}", .{ s, v }));
                }
            }
            try line(try fmt("faults {d} detected {d}", .{ 2 * f.signals.len, detected }));
            for (undetected.items) |s| try line(s);
            try put("tests");
            for (tests, 0..) |yes, r| if (yes) try put(try fmt(" {s}", .{ try bits(f.n, r) }));
            try put("\n");
        }
    }
}

fn command(w: []S) !void {
    const c = w[0];
    const a = w[1..];
    const names = [_]S{
        "BUILD",
        "RESET",
        "SET",
        "APPLY",
        "PULSE",
        "CLOCK",
        "RUN",
        "WATCH",
        "UNWATCH",
        "SHOW",
        "CHECK",
        "PROBE",
        "WAVE",
        "HISTORY",
        "ACTIVITY",
        "STATUS",
        "MODULES",
        "NETLIST",
        "HIERARCHY",
        "STATS",
        "TRUTHTABLE",
        "EQUIV",
        "FAULTS",
        "CRITICAL",
        "PERIOD"
    };
    var id: ?usize = null;
    for (names, 0..) |n, i| if (eq(c, n)) {
        id = i;
        break;
    };
    const j = id orelse return fail("unknown command {s}", .{ c });
    const counts = [_]i32 {
        1,
        0,
        3,
        2,
        3,
        4,
        1, - 1, - 1, - 2,
        2,
        1,
        2,
        1,
        1,
        0,
        0,
        1,
        1,
        1,
        1,
        2,
        1,
        1,
        1
    };
    if ((counts[j] >= 0 and a.len != @as(usize, @intCast(counts[j]))) or (counts[j] ==  - 1 and a.len == 0)) return fail("wrong argument count", .{});
    if (j >= 1 and j <= 15) {
        if (sim == null) return fail("no circuit", .{});
        const s = &sim.?;
        if (j >= 2 and j <= 6 and s.halted) return fail("simulation halted", .{});
        if (eq(c, "RESET")) {
            const watch = s.watch;
            const f = s.f;
            s.* = try reset(f);
            s.watch = watch;
            try line("reset");
        } else if (eq(c, "RUN")) try run(s, try number(a[0], false)) else if (eq(c, "SET")) {
            const t = try time(s, a[0]);
            const i = try inputSig(s, a[1]);
            const v = try value(a[2]);
            try schedule(s, t, i, v);
            try line(try fmt("set {s} {c} at {d}", .{ a[1], v, t }));
        } else if (eq(c, "APPLY")) {
            const t = try time(s, a[0]);
            if (a[1].len != s.f.n) return fail("bad vector {s}", .{ a[1] });
            for (a[1]) |v| if (std.mem.indexOfScalar(u8, "01X", v) == null) return fail("bad vector {s}", .{ a[1] });
            for (a[1], 0..) |v, i| try schedule(s, t, i, v);
            try line(try fmt("apply {s} at {d}", .{ a[1], t }));
        } else if (eq(c, "PULSE")) {
            const i = try inputSig(s, a[0]);
            const t = try time(s, a[1]);
            const width = try number(a[2], true);
            try schedule(s, t, i, '1');
            try schedule(s, t + width, i, '0');
            try line(try fmt("pulse {s} {d} {d}", .{ a[0], t, t + width }));
        } else if (eq(c, "CLOCK")) {
            const i = try inputSig(s, a[0]);
            const t = try time(s, a[1]);
            const half = try number(a[2], true);
            const count = try number(a[3], true);
            for (0..@intCast(count)) |r| try schedule(s, t + r * half, i, if (r % 2 == 0) '0' else '1');
            try line(try fmt("clock {s} events {d} last {d}", .{ a[0], count, t + (count - 1) * half }));
        } else try observation(s, c, a);
    } else try inspect(c, a);
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const text = try input.interface.allocRemaining(A, .unlimited);
    var it = std.mem.splitScalar(u8, text, '\n');
    var lines: std.ArrayList(S) = .empty;
    while (it.next()) |s| try lines.append(A, std.mem.trimEnd(u8, s, "\r"));
    var i: usize = 0;
    while (i < lines.items.len) {
        const s = lines.items[i];
        if (eq(s, "END")) break;
        const w = try words(s);
        const ln = i + 1;
        i += 1;
        error_line = ln;
        if (w.len > 0 and eq(w[0], "MODULE")) {
            var body: std.ArrayList(Body) = .empty;
            while (i < lines.items.len and !eq(lines.items[i], "ENDMODULE")): (i += 1) try body.append(A, .{ .w = try words(lines.items[i]), .ln = i + 1 });
            i += 1;
            definition(w, body.items, ln) catch |e| {
                if (e != error.Invalid) return e;
                try line(try fmt("error: line {d}: {s}", .{ error_line, why }));
            };
        } else command(w) catch |e| {
            if (e != error.Invalid) return e;
            try line(try fmt("error: line {d}: {s}", .{ ln, why }));
        };
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(out.items);
    try sink.interface.flush();
}
