const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var out: std.ArrayList(u8) = .empty;

fn eq(a: S, b: S) bool {
    return std.mem.eql(u8, a, b);
}

fn fmt(comptime f: S, a: anytype) !S {
    return std.fmt.allocPrint(A, f, a);
}

fn put(s: S) !void {
    try out.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}
const kinds = "IOTSZJL";
const rotations = [_]S{
    "0",
    "R",
    "2",
    "L"
};
const ops = [_]S{
    "L",
    "R",
    "LL",
    "RR",
    "SD",
    "DD",
    "CW",
    "CCW",
    "HD",
    "LOCK",
    "HOLD"
};
const commands = [_]S{
    "NEW",
    "PRINT",
    "NEXT",
    "PREVIEW",
    "STATUS",
    "ANALYZE",
    "ROW",
    "GARBAGE",
    "ATTACK",
    "TICK",
    "UNDO",
    "SAVE",
    "LOAD",
    "SPINS",
    "HINT",
    "AUTO"
};
const clear_names = [_]S{
    "SINGLE",
    "DOUBLE",
    "TRIPLE",
    "TETRIS",
    "TSPIN_MINI",
    "TSPIN_MINI_SINGLE",
    "TSPIN_MINI_DOUBLE",
    "TSPIN",
    "TSPIN_SINGLE",
    "TSPIN_DOUBLE",
    "TSPIN_TRIPLE"
};
const Board = [22][10]bool;

const Pos = struct {
    s: usize = 0,
    x: i32 = 4,
    y: i32 = 22
};

const State = struct {
    b: Board = [_][10]bool{
        [_]bool{
            false
        } ** 10
    } ** 22,
    rng: u64 = 1,
    queue: [21]u8 = undefined,
    qn: usize = 0,
    hold: ?u8 = null,
    used: bool = false,
    k: u8 = 0,
    p: Pos = .{},
    motion: u8 = 0,
    test: usize = 0,
    keys: i64 = 0,
    drop: i64 = 0,
    fall: i64 = 0,
    ground: i64 = 0,
    resets: i64 = 0,
    low: i32 = 0,
    initial: i64 = 1,
    level: i64 = 1,
    score: i64 = 0,
    lines: i64 = 0,
    pieces: i64 = 0,
    streak: i64 = 0,
    chain: i64 = 0,
    pending: [500]i64 = undefined,
    pn: usize = 0,
    drops: i64 = 0,
    holds: i64 = 0,
    operations: i64 = 0,
    faults: i64 = 0,
    perfect: i64 = 0,
    sent: i64 = 0,
    cancelled: i64 = 0,
    received: i64 = 0,
    maxcombo: i64 = 0,
    maxchain: i64 = 0,
    counts: [7]i64 = [_]i64 {
        0
    } ** 7,
    clears: [11]i64 = [_]i64 {
        0
    } ** 11,
    ended: bool = false
};

const Save = struct {
    s: State,
    start: State,
    history: []State
};

var state: State = .{};

var start: State = .{};

var history: std.ArrayList(State) = .empty;

var saves: std.StringHashMapUnmanaged(Save) = .empty;

var games: usize = 0;

const Cell = struct {
    x: i32,
    y: i32
};

fn blocks(k: u8, p: Pos)[4]Cell {
    const initial = [7][4][2]i32 {
         .{
             .{ 0, 1 },
             .{ 1, 1 },
             .{ 2, 1 },
             .{ 3, 1 }
        },
         .{
             .{ 0, 0 },
             .{ 1, 0 },
             .{ 0, 1 },
             .{ 1, 1 }
        },
         .{
             .{ 1, 0 },
             .{ 0, 1 },
             .{ 1, 1 },
             .{ 2, 1 }
        },
         .{
             .{ 1, 0 },
             .{ 2, 0 },
             .{ 0, 1 },
             .{ 1, 1 }
        },
         .{
             .{ 0, 0 },
             .{ 1, 0 },
             .{ 1, 1 },
             .{ 2, 1 }
        },
         .{
             .{ 0, 0 },
             .{ 0, 1 },
             .{ 1, 1 },
             .{ 2, 1 }
        },
         .{
             .{ 2, 0 },
             .{ 0, 1 },
             .{ 1, 1 },
             .{ 2, 1 }
        }
    };
    const n: i32 = if (k == 0) 4 else if (k == 1) 2 else 3;
    var result: [4]Cell = undefined;
    for (initial[k], 0..) |v, i| {
        var x = v[0];
        var y = v[1];
        for (0..p.s) |_| {
            const xx = n - 1 - y;
            y = x;
            x = xx;
        }
        result[i] = .{ .x = p.x + x, .y = p.y - y };
    }
    return result;
}

fn occupied(b: Board, c: Cell) bool {
    return c.x < 1 or c.x > 10 or c.y < 1 or c.y > 22 or b[@intCast(c.y - 1)][@intCast(c.x - 1)];
}

fn fits(b: Board, k: u8, p: Pos) bool {
    for (blocks(k, p)) |c| if (occupied(b, c)) return false;
    return true;
}

fn same(a: Pos, b: Pos) bool {
    return a.s == b.s and a.x == b.x and a.y == b.y;
}

fn spawnPos(k: u8) Pos {
    return .{ .x = if (k == 1) 5 else 4 };
}

fn lowest(k: u8, p: Pos) i32 {
    var low: i32 = 23;
    for (blocks(k, p)) |c| low = @min(low, c.y);
    return low;
}

const Motion = struct {
    p: Pos,
    test: usize = 0
};

fn move(b: Board, k: u8, p: Pos, op: usize) ?Motion {
    var q = p;
    if (op < 6) {
        const dx: i32 = if (op == 0 or op == 2) - 1 else if (op == 1 or op == 3) 1 else 0;
        const dy: i32 = if (op >= 4) - 1 else 0;
        var ok = false;
        while (true) {
            var n = q;
            n.x += dx;
            n.y += dy;
            if (!fits(b, k, n)) break;
            q = n;
            ok = true;
            if (op == 0 or op == 1 or op == 4) break;
        }
        return if (ok) .{ .p = q } else null;
    }
    q.s = (p.s + (if (op == 6) @as(usize, 1) else 3)) % 4;
    if (k == 1) return if (fits(b, k, q)) .{ .p = q, .test = 1 } else null;
    const normal = [4][5][2]i32 {
         .{
             .{ 0, 0 },
             .{ - 1, 0 },
             .{ - 1, 1 },
             .{ 0, - 2 },
             .{ - 1, - 2 }
        },
         .{
             .{ 0, 0 },
             .{ 1, 0 },
             .{ 1, - 1 },
             .{ 0, 2 },
             .{ 1, 2 }
        },
         .{
             .{ 0, 0 },
             .{ 1, 0 },
             .{ 1, 1 },
             .{ 0, - 2 },
             .{ 1, - 2 }
        },
         .{
             .{ 0, 0 },
             .{ - 1, 0 },
             .{ - 1, - 1 },
             .{ 0, 2 },
             .{ - 1, 2 }
        }
    };
    const ikicks = [4][5][2]i32 {
         .{
             .{ 0, 0 },
             .{ - 2, 0 },
             .{ 1, 0 },
             .{ - 2, - 1 },
             .{ 1, 2 }
        },
         .{
             .{ 0, 0 },
             .{ - 1, 0 },
             .{ 2, 0 },
             .{ - 1, 2 },
             .{ 2, - 1 }
        },
         .{
             .{ 0, 0 },
             .{ 2, 0 },
             .{ - 1, 0 },
             .{ 2, 1 },
             .{ - 1, - 2 }
        },
         .{
             .{ 0, 0 },
             .{ 1, 0 },
             .{ - 2, 0 },
             .{ 1, - 2 },
             .{ - 2, 1 }
        }
    };
    if (k == 0) {
        const from = if (op == 6) p.s else q.s;
        for (ikicks[from], 1..) |d, test| {
            var n = q;
            const sign: i32 = if (op == 6) 1 else -1;
            n.x += sign * d[0];
            n.y += sign * d[1];
            if (fits(b, k, n)) return .{ .p = n, .test = test };
        }
    } else {
        const row: usize = if (p.s == 1) 1 else if (p.s == 3) 3 else if (q.s == 1) 0 else 2;
        for (normal[row], 1..) |d, test| {
            var n = q;
            n.x += d[0];
            n.y += d[1];
            if (fits(b, k, n)) return .{ .p = n, .test = test };
        }
    }
    return null;
}

fn landing(b: Board, k: u8, p: Pos) Pos {
    return if (move(b, k, p, 5)) |m| m.p else p;
}

fn random(s: *State) u64 {
    s.rng = s.rng * 48271 % 2147483647;
    return s.rng;
}

fn bag(s: *State) void {
    var b = [_]u8{
        0,
        1,
        2,
        3,
        4,
        5,
        6
    };
    var i: usize = 6;
    while (i > 0): (i -= 1) {
        const j: usize = @intCast(random(s) % (i + 1));
        std.mem.swap(u8, &b[i], &b[j]);
    }
    for (b) |k| {
        s.queue[s.qn] = k;
        s.qn += 1;
    }
}

fn take(s: *State) u8 {
    const k = s.queue[0];
    std.mem.copyForwards(u8, s.queue[0..s.qn - 1], s.queue[1..s.qn]);
    s.qn -= 1;
    if (s.qn < 5) bag(s);
    return k;
}

fn pending(s: State) i64 {
    var n: i64 = 0;
    for (s.pending[0..s.pn]) |v| n += v;
    return n;
}

fn ratio(a: i64, b: i64) !S {
    const q = if (b == 0) 0 else @divTrunc(a * 100, b);
    return fmt("{d}.{d:0>2}", .{ @divTrunc(q, 100), @mod(q, 100) });
}

fn summary() !void {
    const s = &state;
    try line(try fmt("summary game {d} score {d} level {d} lines {d} pieces {d}", .{ games, s.score, s.level, s.lines, s.pieces }));
    try line(try fmt("clears single {d} double {d} triple {d} tetris {d} perfect {d}", .{ s.clears[0], s.clears[1], s.clears[2], s.clears[3], s.perfect }));
    try line(try fmt("tspins mini {d} mini_single {d} mini_double {d} zero {d} single {d} double {d} triple {d}", .{
        s.clears[4],
        s.clears[5],
        s.clears[6],
        s.clears[7],
        s.clears[8],
        s.clears[9],
        s.clears[10]
    }));
    try put("pieces");
    for (kinds, 0..) |k, i| try put(try fmt(" {c} {d}", .{ k, s.counts[i] }));
    try put("\n");
    try line(try fmt("best combo {d} chain {d} holds {d} drops {d} faults {d}", .{ s.maxcombo, s.maxchain, s.holds, s.drops, s.faults }));
    try line(try fmt("garbage sent {d} cancelled {d} received {d}", .{ s.sent, s.cancelled, s.received }));
    try line(try fmt("rates app {s} apl {s} kpp {s}", .{
        try ratio(s.sent, s.pieces),
        try ratio(s.sent, s.lines),
        try ratio(s.operations, s.pieces)
    }));
}

fn over(reason: S) !void {
    state.ended = true;
    try line(try fmt("game over {s}", .{ reason }));
    try summary();
}

fn spawn(k: u8) !void {
    const s = &state;
    s.k = k;
    s.p = spawnPos(k);
    s.motion = 0;
    s.test = 0;
    s.keys = 0;
    s.drop = 0;
    s.fall = 0;
    s.ground = 0;
    s.resets = 0;
    s.low = lowest(k, s.p);
    if (!fits(s.b, k, s.p)) try over("block out");
}

fn update(p: Pos, motion: u8, test: usize) void {
    const s = &state;
    s.p = p;
    s.motion = motion;
    s.test = test;
    const low = lowest(s.k, p);
    if (low < s.low) {
        s.low = low;
        s.resets = 0;
    }
}

fn clear(b: *Board) usize {
    var n: usize = 0;
    var dest: usize = 0;
    for (0..22) |r| {
        var full = true;
        for (b[r]) |v| full = full and v;
        if (full) n += 1 else {
            b[dest] = b[r];
            dest += 1;
        }
    }
    while (dest < 22): (dest += 1) b[dest] = [_]bool{
        false
    } ** 10;
    return n;
}

fn place(b: Board, k: u8, p: Pos) struct {
    b: Board,
    n: usize
}
{
    var q = b;
    for (blocks(k, p)) |c| q[@intCast(c.y - 1)][@intCast(c.x - 1)] = true;
    const n = clear(&q);
    return .{ .b = q, .n = n };
}

fn spin(b: Board, k: u8, p: Pos, test: usize) u8 {
    if (k != 2) return 0;
    const corners = [_]Cell{
         .{ .x = p.x, .y = p.y },
         .{ .x = p.x + 2, .y = p.y },
         .{ .x = p.x + 2, .y = p.y - 2 },
         .{ .x = p.x, .y = p.y - 2 }
    };
    var n: usize = 0;
    for (corners) |c| if (occupied(b, c)) {
        n += 1;
    };
    if (n < 3) return 0;
    return if ((occupied(b, corners[p.s]) and occupied(b, corners[(p.s + 1) % 4])) or test == 5) 2 else 1;
}

fn typeIndex(n: usize, t: u8) ?usize {
    return if (t == 0)(if (n == 0) null else n - 1) else if (t == 1) 4 + n else 7 + n;
}

const Reach = struct {
    p: Pos,
    parent: ?usize,
    op: usize
};

fn poskey(p: Pos) usize {
    return (p.s * 28 + @as(usize, @intCast(p.y))) * 20 + @as(usize, @intCast(p.x + 5));
}

fn reachable(b: Board, k: u8, origin: Pos) ![]Reach {
    var list: std.ArrayList(Reach) = .empty;
    if (!fits(b, k, origin)) return list.items;
    var seen: [4 * 28 * 20]bool = [_]bool{
        false
    } ** (4 * 28 * 20);
    try list.append(A, .{ .p = origin, .parent = null, .op = 0 });
    seen[poskey(origin)] = true;
    var i: usize = 0;
    while (i < list.items.len): (i += 1) {
        const p = list.items[i].p;
        for (0..8) |op| if (move(b, k, p, op)) |m| {
            const key = poskey(m.p);
            if (!seen[key]) {
                seen[key] = true;
                try list.append(A, .{ .p = m.p, .parent = i, .op = op });
            }
        };
    }
    return list.toOwnedSlice(A);
}

fn sequence(rs: []Reach, index: usize) ![]usize {
    var reversed: std.ArrayList(usize) = .empty;
    var i = index;
    while (rs[i].parent) |p| {
        try reversed.append(A, rs[i].op);
        i = p;
    }
    std.mem.reverse(usize, reversed.items);
    return reversed.toOwnedSlice(A);
}

fn shortest(b: Board, k: u8, p: Pos) !?[]usize {
    const rs = try reachable(b, k, spawnPos(k));
    for (rs, 0..) |r, i| if (same(landing(b, k, r.p), p)) return try sequence(rs, i);
    return null;
}

fn operations(a: []const usize) !S {
    var s: S = "";
    for (a, 0..) |op, i| s = try fmt("{s}{s}{s}", .{ s, if (i == 0) @as(S, "") else " ", ops[op] });
    return s;
}

fn garbage(n: usize, h: usize) !bool {
    for (22 - n..22) |r| for (state.b[r]) |v| if (v) {
        try over("top out");
        return false;
    };
    var r: usize = 22;
    while (r > n) {
        r -= 1;
        state.b[r] = state.b[r - n];
    }
    for (0..n) |i| {
        state.b[i] = [_]bool{
            true
        } ** 10;
        state.b[i][h - 1] = false;
    }
    return true;
}

fn reduce(n0: i64) void {
    var n = n0;
    while (n > 0) {
        const c = @min(n, state.pending[0]);
        state.pending[0] -= c;
        n -= c;
        if (state.pending[0] == 0) {
            std.mem.copyForwards(i64, state.pending[0..state.pn - 1], state.pending[1..state.pn]);
            state.pn -= 1;
        }
    }
}

fn lock() !void {
    const s = &state;
    const k = s.k;
    const p = s.p;
    const seq = try shortest(s.b, k, p);
    const t = if (s.motion == 2) spin(s.b, k, p, s.test) else 0;
    const placed = place(s.b, k, p);
    s.b = placed.b;
    const n = placed.n;
    try history.append(A, start);
    s.pieces += 1;
    s.counts[k] += 1;
    s.operations += s.keys;
    const ti = typeIndex(n, t);
    const bases = [_]i64 {
        100,
        300,
        500,
        800,
        100,
        200,
        400,
        400,
        800,
        1200,
        1600
    };
    const sends = [_]i64 {
        0,
        1,
        2,
        4,
        0,
        0,
        1,
        0,
        2,
        4,
        6
    };
    const v = s.level;
    var points: i64 = if (ti) |i| bases[i] * v else 0;
    var send: i64 = if (ti) |i| sends[i] else 0;
    var b2b = false;
    if (n > 0) {
        s.streak += 1;
        if (n == 4 or t != 0) {
            s.chain += 1;
            b2b = s.chain >= 2;
        } else s.chain = 0;
    } else s.streak = 0;
    if (b2b) {
        points = @divTrunc(points * 3, 2);
        send += 1;
    }
    const combo = s.streak - 1;
    const cp = if (combo >= 1) 50 * combo * v else 0;
    const combos = [_]i64 {
        0,
        1,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
        4,
        5
    };
    if (combo >= 0) send += combos[@intCast(@min(combo, 10))];
    var perfect = n > 0;
    for (s.b) |row| for (row) |filled| {
        if (filled) perfect = false;
    };
    var pp: i64 = 0;
    if (perfect) {
        const ps = [_]i64 {
            800,
            1200,
            1800,
            2000
        };
        pp = (if (n == 4 and b2b) @as(i64, 3200) else ps[n - 1]) * v;
        send += 10;
        s.perfect += 1;
    }
    const gained = points + cp + pp;
    s.score += gained;
    s.lines += @intCast(n);
    s.sent += send;
    s.maxcombo = @max(s.maxcombo, combo);
    s.maxchain = @max(s.maxchain, s.chain);
    try line(try fmt("lock {d} {c} {s} {d} {d} keys {d} {s} drop {d} lines {d} sent {d} +{d} total {d}", .{
        s.pieces,
        kinds[k],
        rotations[p.s],
        p.x,
        p.y,
        s.keys,
        if (seq) |a| try fmt("{d}", .{ a.len }) else "-",
        s.drop,
        n,
        send,
        gained,
        s.score
    }));
    if (seq) |a| if (s.keys > @as(i64, @intCast(a.len))) {
        s.faults += 1;
        try line(try fmt("finesse {s}", .{ if (a.len == 0) @as(S, "none") else try operations(a) }));
    };
    if (ti) |i| {
        s.clears[i] += 1;
        try put(try fmt("clear {s} {d}", .{ clear_names[i], points }));
        if (b2b) try put(" b2b");
        if (combo >= 1) try put(try fmt(" combo {d} {d}", .{ combo, cp }));
        if (perfect) try put(try fmt(" perfect {d}", .{ pp }));
        try put("\n");
    }
    const level = s.initial + @divTrunc(s.lines, 10);
    if (level > v) {
        s.level = level;
        try line(try fmt("level {d}", .{ level }));
    }
    var lockout = true;
    for (blocks(k, p)) |c| if (c.y <= 20) {
        lockout = false;
    };
    if (lockout) {
        try over("lock out");
        return;
    }
    const cancelled = @min(send, pending(s.*));
    if (cancelled > 0) {
        reduce(cancelled);
        s.cancelled += cancelled;
        try line(try fmt("cancel {d} pending {d}", .{ cancelled, pending(s.*) }));
    }
    if (n == 0) {
        var risen: i64 = 0;
        while (s.pn > 0 and risen < 8) {
            const count = @min(s.pending[0], 8 - risen);
            const h: usize = @intCast(random(s) % 10 + 1);
            if (!try garbage(@intCast(count), h)) return;
            s.received += count;
            risen += count;
            reduce(count);
            try line(try fmt("rise {d} hole {d} pending {d}", .{ count, h, pending(s.*) }));
        }
    }
    s.used = false;
    const next = take(s);
    try spawn(next);
    if (!s.ended) start = s.*;
}

fn operate(op: usize) !void {
    const s = &state;
    if (op < 8) {
        s.keys += 1;
        if (move(s.b, s.k, s.p, op)) |m| {
            if (op == 4 or op == 5) {
                const n = s.p.y - m.p.y;
                s.score += n;
                s.drop += n;
                s.drops += n;
                update(m.p, 1, 0);
                s.fall = 0;
                s.ground = 0;
            } else {
                update(m.p, if (op >= 6) 2 else 1, m.test);
                if (s.ground > 0 and s.resets < 15) {
                    s.ground = 0;
                    s.resets += 1;
                }
            }
        } else try line(try fmt("fail {s}", .{ ops[op] }));
    } else if (op == 8) {
        const p = landing(s.b, s.k, s.p);
        const n = 2 * (s.p.y - p.y);
        s.score += n;
        s.drop += n;
        s.drops += n;
        if (n > 0) update(p, 1, 0);
        try lock();
    } else if (op == 9) {
        if (move(s.b, s.k, s.p, 4) == null) try lock() else try line("fail LOCK");
    } else {
        if (s.used) {
            try line("fail HOLD");
            return;
        }
        s.used = true;
        s.holds += 1;
        const k = s.k;
        const next = if (s.hold) |h| h else take(s);
        s.hold = k;
        try spawn(next);
    }
}

const Evaluation = struct {
    heights: [10]i64 = [_]i64 {
        0
    } ** 10,
    holes: i64 = 0,
    bump: i64 = 0,
    value: i64 = 0
};

fn evaluate(b: Board, n: usize) Evaluation {
    var e: Evaluation = .{};
    var sum: i64 = 0;
    for (0..10) |c| {
        for (0..22) |r| if (b[r][c]) {
            e.heights[c] = @intCast(r + 1);
        };
        sum += e.heights[c];
        for (0..@intCast(e.heights[c])) |r| if (!b[r][c]) {
            e.holes += 1;
        };
        if (c > 0) e.bump += @intCast(@abs(e.heights[c] - e.heights[c - 1]));
    }
    e.value = 76 * @as(i64, @intCast(n)) - 51 * sum - 36 * e.holes - 18 * e.bump;
    return e;
}

const Candidate = struct {
    k: u8,
    p: Pos,
    ops: []usize,
    value: i64,
    serial: usize
};

fn sameCells(k: u8, a: Pos, b: Pos) bool {
    const aa = blocks(k, a);
    const bb = blocks(k, b);
    for (aa) |c| {
        var found = false;
        for (bb) |d| if (c.x == d.x and c.y == d.y) {
            found = true;
        };
        if (!found) return false;
    }
    return true;
}

fn candidates(list: *std.ArrayList(Candidate), k: u8, p: Pos, hold: bool) !void {
    var seen: std.ArrayList(Pos) = .empty;
    for (0..4) |r| {
        var q = p;
        var prefix: std.ArrayList(usize) = .empty;
        if (hold) try prefix.append(A, 10);
        var ok = true;
        const rs: []const usize = if (r == 0) & .{} else if (r == 1) & .{ 6 } else if (r == 2) & .{ 6, 6 } else & .{ 7 };
        for (rs) |op| {
            if (move(state.b, k, q, op)) |m| {
                q = m.p;
                try prefix.append(A, op);
            } else {
                ok = false;
                break;
            }
        }
        if (!ok) continue;
        for (0..3) |dir| {
            var at = q;
            var seq: std.ArrayList(usize) = .empty;
            try seq.appendSlice(A, prefix.items);
            while (true) {
                if (dir > 0) {
                    const op: usize = if (dir == 1) 0 else 1;
                    const m = move(state.b, k, at, op) orelse break;
                    at = m.p;
                    try seq.append(A, op);
                }
                const land = landing(state.b, k, at);
                var duplicate = false;
                for (seen.items) |v| if (sameCells(k, v, land)) {
                    duplicate = true;
                };
                if (!duplicate) {
                    try seen.append(A, land);
                    const b = place(state.b, k, land);
                    const commands_list = try A.alloc(usize, seq.items.len + 1);
                    @memcpy(commands_list[0..seq.items.len], seq.items);
                    commands_list[seq.items.len] = 8;
                    try list.append(A, .{
                        .k = k,
                        .p = land,
                        .ops = commands_list,
                        .value = evaluate(b.b, b.n).value,
                        .serial = list.items.len
                    });
                }
                if (dir == 0) break;
            }
        }
    }
}

fn ranked() ![]Candidate {
    var list: std.ArrayList(Candidate) = .empty;
    try candidates(&list, state.k, state.p, false);
    if (!state.used) {
        const k = state.hold orelse state.queue[0];
        const p = spawnPos(k);
        if (fits(state.b, k, p)) try candidates(&list, k, p, true);
    }
    const C = struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return a.value > b.value or (a.value == b.value and a.serial < b.serial);
        }
    };
    std.mem.sort(Candidate, list.items, {}, C.less);
    return list.toOwnedSlice(A);
}

fn numeric(s: S, lo: u64, hi: u64) ?u64 {
    if (s.len == 0 or (s.len > 1 and s[0] == '0')) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    const n = std.fmt.parseInt(u64, s, 10) catch return null;
    return if (n >= lo and n <= hi) n else null;
}

fn saveName(s: S) bool {
    if (s.len == 0 or s.len > 8) return false;
    for (s) |c| if (!std.ascii.isLower(c)) return false;
    return true;
}

fn hasCell(k: u8, p: Pos, x: usize, y: usize) bool {
    for (blocks(k, p)) |c| if (c.x == @as(i32, @intCast(x)) and c.y == @as(i32, @intCast(y))) return true;
    return false;
}

fn command(w: []S) !void {
    const c = w[0];
    const a = w[1..];
    var id: ?usize = null;
    for (commands, 0..) |n, i| if (eq(c, n)) {
        id = i;
        break;
    };
    if (id == null) {
        var actions: std.ArrayList(usize) = .empty;
        for (w) |word| {
            var op: ?usize = null;
            for (ops, 0..) |n, i| if (eq(word, n)) {
                op = i;
                break;
            };
            if (op == null) {
                try line(try fmt("ERROR unknown {s}", .{ word }));
                return;
            }
            try actions.append(A, op.?);
        }
        if (games == 0) {
            try line("ERROR no game");
            return;
        }
        if (state.ended) {
            try line("ERROR game over");
            return;
        }
        for (actions.items) |op| {
            try operate(op);
            if (state.ended) break;
        }
        return;
    }
    const j = id.?;
    var valid_args = true;
    var n: u64 = 0;
    var m: u64 = 0;
    switch (j) {
        0 => {
            valid_args = a.len == 2;
            if (valid_args) {
                n = numeric(a[0], 1, 2147483646) orelse 0;
                m = numeric(a[1], 1, 15) orelse 0;
                valid_args = n != 0 and m != 0;
            }
        },
        3,
        8,
        9,
        14,
        15 => {
            valid_args = a.len == 1;
            if (valid_args) {
                n = numeric(a[0], 1, switch (j) {
                    3 => 14,
                    8 => 20,
                    9 => 1000,
                    14 => 10,
                    else => 50
                }) orelse 0;
                valid_args = n != 0;
            }
        },
        6 => {
            valid_args = a.len == 2;
            if (valid_args) {
                n = numeric(a[0], 1, 22) orelse 0;
                valid_args = n > 0 and a[1].len == 10 and std.mem.indexOfScalar(u8, a[1], '.') != null;
                for (a[1]) |v| if (v != '#' and v != '.') {
                    valid_args = false;
                };
            }
        },
        7 => {
            valid_args = a.len == 2;
            if (valid_args) {
                n = numeric(a[0], 1, 10) orelse 0;
                m = numeric(a[1], 1, 10) orelse 0;
                valid_args = n > 0 and m > 0;
            }
        },
        11,
        12 => valid_args = a.len == 1 and saveName(a[0]),
        else => valid_args = a.len == 0
    }
    if (!valid_args) {
        try line("ERROR bad arguments");
        return;
    }
    if (j != 0 and games == 0) {
        try line("ERROR no game");
        return;
    }
    const allowed = j == 1 or j == 2 or j == 3 or j == 4 or j == 5 or j == 12;
    if (j != 0 and !allowed and state.ended) {
        try line("ERROR game over");
        return;
    }
    if (j == 0) {
        if (games > 0 and !state.ended) {
            try line("game stopped");
            try summary();
        }
        games += 1;
        state = .{ .rng = n, .initial = @intCast(m), .level = @intCast(m) };
        history.clearRetainingCapacity();
        saves.clearRetainingCapacity();
        try line(try fmt("game {d} seed {d} level {d}", .{ games, n, m }));
        bag(&state);
        const k = take(&state);
        try spawn(k);
        start = state;
    } else if (j == 1) {
        const land = landing(state.b, state.k, state.p);
        var r: usize = 22;
        while (r > 0) {
            r -= 1;
            try put(try fmt("{d: >2} ", .{ r + 1 }));
            for (0..10) |col| {
                const ch: u8 = if (state.b[r][col]) '#' else if (!state.ended and hasCell(state.k, state.p, col + 1, r + 1)) '@' else if (!state.ended and hasCell(state.k, land, col + 1, r + 1)) '+' else '.';
                try out.append(A, ch);
            }
            try put("\n");
        }
    } else if (j == 2) {
        try put(try fmt("hold {c} next ", .{ if (state.hold) |k| kinds[k] else '-' }));
        for (state.queue[0..5]) |k| try out.append(A, kinds[k]);
        try put("\n");
    } else if (j == 3) {
        var copy = state;
        while (copy.qn < n) bag(&copy);
        try put("preview ");
        for (copy.queue[0..@intCast(n)]) |k| try out.append(A, kinds[k]);
        try put("\n");
    } else if (j == 4) {
        try line(try fmt("score {d} level {d} lines {d} pieces {d}", .{ state.score, state.level, state.lines, state.pieces }));
        try line(try fmt("piece {s} streak {d} chain {d} pending {d}", .{
            if (state.ended) @as(S, "-") else try fmt("{c} {s} {d} {d}", .{ kinds[state.k], rotations[state.p.s], state.p.x, state.p.y }),
            state.streak,
            state.chain,
            pending(state)
        }));
    } else if (j == 5) {
        const e = evaluate(state.b, 0);
        try put("heights");
        for (e.heights) |h| try put(try fmt(" {d}", .{ h }));
        try put("\n");
        try line(try fmt("holes {d} bumpiness {d} value {d}", .{ e.holes, e.bump, e.value }));
    } else if (j == 6) {
        for (a[1], 0..) |ch, col| if (ch == '#' and hasCell(state.k, state.p, col + 1, @intCast(n))) {
            try line("ERROR overlap");
            return;
        };
        for (a[1], 0..) |ch, col| state.b[@intCast(n - 1)][col] = ch == '#';
        try line("OK");
    } else if (j == 7) {
        if (!try garbage(@intCast(n), @intCast(m))) return;
        var y: usize = 0;
        while (y <= n): (y += 1) {
            var p = state.p;
            p.y += @intCast(y);
            if (fits(state.b, state.k, p)) {
                state.p = p;
                try line("OK");
                return;
            }
        }
        try over("top out");
    } else if (j == 8) {
        state.pending[state.pn] = @intCast(n);
        state.pn += 1;
        try line(try fmt("pending {d}", .{ pending(state) }));
    } else if (j == 9) {
        const intervals = [_]i64 {
            60,
            48,
            37,
            28,
            21,
            16,
            11,
            8,
            6,
            4,
            3,
            2
        };
        for (0..@intCast(n)) |_| {
            if (move(state.b, state.k, state.p, 4)) |motion| {
                state.ground = 0;
                state.fall += 1;
                const interval = if (state.level >= 13) 1 else intervals[@intCast(state.level - 1)];
                if (state.fall >= interval) {
                    update(motion.p, 1, 0);
                    state.fall = 0;
                }
            } else {
                state.ground += 1;
                if (state.ground >= 30) try lock();
            }
            if (state.ended) break;
        }
    } else if (j == 10) {
        if (history.items.len == 0) try line("ERROR nothing to undo") else {
            state = history.pop().?;
            start = state;
            try line(try fmt("undo {d} {c}", .{ state.pieces, kinds[state.k] }));
        }
    } else if (j == 11) {
        try saves.put(A, a[0], .{ .s = state, .start = start, .history = try A.dupe(State, history.items) });
        try line("OK");
    } else if (j == 12) {
        if (saves.get(a[0])) |save| {
            state = save.s;
            start = save.start;
            history.clearRetainingCapacity();
            try history.appendSlice(A, save.history);
            try line(try fmt("load {d} {c}", .{ state.pieces, kinds[state.k] }));
        } else try line("ERROR unknown save");
    } else if (j == 13) {
        if (state.k != 2) {
            try line("spins 0");
            return;
        }
        const rs = try reachable(state.b, state.k, state.p);
        const Spin = struct {
            p: Pos,
            t: u8
        };
        var list: std.ArrayList(Spin) = .empty;
        for (rs) |r| for ([_]usize{
            6,
            7
        }) |op| if (move(state.b, state.k, r.p, op)) |motion| {
            const p = motion.p;
            if (move(state.b, state.k, p, 4) != null) continue;
            const t = spin(state.b, state.k, p, motion.test);
            if (t == 0) continue;
            var found = false;
            for (list.items) |*v| if (same(v.p, p)) {
                v.t = @max(v.t, t);
                found = true;
            };
            if (!found) try list.append(A, .{ .p = p, .t = t });
        };
        const C = struct {
            fn less(_: void, x: Spin, y: Spin) bool {
                return x.p.y < y.p.y or (x.p.y == y.p.y and (x.p.x < y.p.x or (x.p.x == y.p.x and x.p.s < y.p.s)));
            }
        };
        std.mem.sort(Spin, list.items, {}, C.less);
        for (list.items) |v| try line(try fmt("spin {s} {d} {d} {s}", .{
            rotations[v.p.s],
            v.p.x,
            v.p.y,
            clear_names[typeIndex(place(state.b, state.k, v.p).n, v.t).?]
        }));
        try line(try fmt("spins {d}", .{ list.items.len }));
    } else if (j == 14) {
        const list = try ranked();
        for (list[0..@min(n, list.len)], 1..) |v, r| try line(try fmt("hint {d} {c} {s} value {d}", .{ r, kinds[v.k], try operations(v.ops), v.value }));
    } else if (j == 15) {
        for (0..@intCast(n)) |_| {
            const list = try ranked();
            if (list.len == 0) break;
            const best = list[0];
            try line(try fmt("auto {c} {s}", .{ kinds[best.k], try operations(best.ops) }));
            for (best.ops) |op| {
                try operate(op);
                if (state.ended) break;
            }
            if (state.ended) break;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const text = try input.interface.allocRemaining(A, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const n = try std.fmt.parseInt(usize, lines.next() orelse "0", 10);
    for (0..n) |_| {
        const s = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
        var ws: std.ArrayList(S) = .empty;
        var it = std.mem.tokenizeScalar(u8, s, ' ');
        while (it.next()) |w| try ws.append(A, w);
        try command(ws.items);
    }
    if (games > 0 and !state.ended) {
        try line("game stopped");
        try summary();
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(out.items);
    try sink.interface.flush();
}
