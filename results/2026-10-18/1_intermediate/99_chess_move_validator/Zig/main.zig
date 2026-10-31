const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var output: std.ArrayList(u8) = .empty;

fn eq(a: S, b: S) bool {
    return std.mem.eql(u8, a, b);
}

fn fmt(comptime f: S, a: anytype) !S {
    return std.fmt.allocPrint(A, f, a);
}

fn put(s: S) !void {
    try output.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}

fn sq(s: S) ?usize {
    if (s.len != 2 or s[0] < 'a' or s[0] > 'h' or s[1] < '1' or s[1] > '8') return null;
    return @as(usize, s[1] - '1') * 8 + s[0] - 'a';
}

fn name(s: usize) !S {
    return fmt("{c}{c}", .{ @as(u8, @intCast(s % 8)) + 'a', @as(u8, @intCast(s / 8)) + '1' });
}

fn number(s: S, lo: usize, hi: usize) ?usize {
    if (s.len == 0 or (s.len > 1 and s[0] == '0')) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    const n = std.fmt.parseInt(usize, s, 10) catch return null;
    return if (n >= lo and n <= hi) n else null;
}

fn color(c: u8) bool {
    return std.ascii.isUpper(c);
}

const Move = struct { f: usize, t: usize, p: u8 = 0 };

const Moves = struct {
    a: [2048]Move = undefined,
    n: usize = 0,
    fn add(m: *Moves, v: Move) void {
        m.a[m.n] = v;
        m.n += 1;
    }
};

const Pos = struct { b: [64]u8 = @as([64]u8, @splat('.')), white: bool = true, rights: u8 = 0, ep: ?usize = null, half: usize = 0, full: usize = 1 };

fn attack(p: Pos, f: usize, t: usize) bool {
    if (f == t or p.b[f] == '.') return false;
    const dx = @as(i32, @intCast(t % 8)) - @as(i32, @intCast(f % 8));
    const dy = @as(i32, @intCast(t / 8)) - @as(i32, @intCast(f / 8));
    const ax = @abs(dx);
    const ay = @abs(dy);
    const kind = std.ascii.toUpper(p.b[f]);
    if (kind == 'P') return ax == 1 and dy == (if (color(p.b[f])) @as(i32, 1) else -1);
    if (kind == 'N') return (ax == 1 and ay == 2) or (ax == 2 and ay == 1);
    if (kind == 'K') return ax <= 1 and ay <= 1;
    const straight = dx == 0 or dy == 0;
    const diagonal = ax == ay;
    if (!(kind == 'Q' and (straight or diagonal)) and !(kind == 'R' and straight) and !(kind == 'B' and diagonal)) return false;
    const sx: i32 = if (dx < 0) -1 else if (dx > 0) 1 else 0;
    const sy: i32 = if (dy < 0) -1 else if (dy > 0) 1 else 0;
    var x = @as(i32, @intCast(f % 8)) + sx;
    var y = @as(i32, @intCast(f / 8)) + sy;
    while (x != @as(i32, @intCast(t % 8)) or y != @as(i32, @intCast(t / 8))) : ({
        x += sx;
        y += sy;
    }) {
        if (p.b[@intCast(y * 8 + x)] != '.') return false;
    }
    return true;
}

fn attacked(p: Pos, t: usize, white: bool) bool {
    for (p.b, 0..) |c, f| if (c != '.' and color(c) == white and attack(p, f, t)) return true;
    return false;
}

fn check(p: Pos, white: bool) bool {
    for (p.b, 0..) |c, f| if (c == (if (white) @as(u8, 'K') else 'k')) return attacked(p, f, !white);
    return true;
}

fn castle(p: Pos, m: Move) bool {
    return std.ascii.toUpper(p.b[m.f]) == 'K' and @abs(@as(i32, @intCast(m.t)) - @as(i32, @intCast(m.f))) == 2;
}

fn enpassant(p: Pos, m: Move) bool {
    return std.ascii.toUpper(p.b[m.f]) == 'P' and m.f % 8 != m.t % 8 and p.b[m.t] == '.';
}

fn capture(p: Pos, m: Move) bool {
    return p.b[m.t] != '.' or enpassant(p, m);
}

fn after(p: Pos, m: Move) Pos {
    var q = p;
    const c = p.b[m.f];
    const pawn = std.ascii.toUpper(c) == 'P';
    q.half = if (pawn or capture(p, m)) 0 else p.half + 1;
    if (enpassant(p, m)) q.b[if (p.white) m.t - 8 else m.t + 8] = '.';
    if (castle(p, m)) {
        const base = m.f / 8 * 8;
        const k = m.t > m.f;
        q.b[base + (if (k) @as(usize, 5) else 3)] = q.b[base + (if (k) @as(usize, 7) else 0)];
        q.b[base + (if (k) @as(usize, 7) else 0)] = '.';
    }
    q.b[m.t] = if (m.p == 0) c else if (p.white) m.p else std.ascii.toLower(m.p);
    q.b[m.f] = '.';
    if (std.ascii.toUpper(c) == 'K') q.rights &= if (p.white) @as(u8, 12) else 3;
    for ([_]usize{ 7, 0, 63, 56 }, 0..) |s, i| if (m.f == s or m.t == s) {
        q.rights &= ~(@as(u8, 1) << @intCast(i));
    };
    q.ep = if (pawn and @abs(@as(i32, @intCast(m.t)) - @as(i32, @intCast(m.f))) == 16) (m.f + m.t) / 2 else null;
    if (!p.white) q.full += 1;
    q.white = !p.white;
    return q;
}

fn castleReason(p: Pos, king: bool) ?S {
    const bit: u3 = if (p.white) (if (king) @as(u3, 0) else 1) else (if (king) @as(u3, 2) else 3);
    if (p.rights & (@as(u8, 1) << bit) == 0) return "no castling right";
    const base: usize = if (p.white) 0 else 56;
    const files: []const usize = if (king) &.{ 5, 6 } else &.{ 1, 2, 3 };
    for (files) |f| if (p.b[base + f] != '.') return "path blocked";
    if (check(p, p.white)) return "in check";
    if (attacked(p, base + (if (king) @as(usize, 5) else 3), !p.white)) return "through check";
    if (check(after(p, .{ .f = base + 4, .t = base + (if (king) @as(usize, 6) else 2) }), p.white)) return "into check";
    return null;
}

fn pseudo(p: Pos) Moves {
    var list: Moves = .{};
    for (p.b, 0..) |c, f| {
        if (c == '.' or color(c) != p.white) continue;
        for (0..64) |t| {
            if (p.b[t] != '.' and color(p.b[t]) == p.white) continue;
            var ok = false;
            if (std.ascii.toUpper(c) == 'P') {
                const d: i32 = if (p.white) 8 else -8;
                const diff = @as(i32, @intCast(t)) - @as(i32, @intCast(f));
                if (f % 8 == t % 8 and p.b[t] == '.') {
                    if (diff == d) ok = true;
                    if (diff == 2 * d and f / 8 == (if (p.white) @as(usize, 1) else 6) and p.b[@intCast(@as(i32, @intCast(f)) + d)] == '.') ok = true;
                }
                if (attack(p, f, t) and (p.b[t] != '.' or p.ep == t)) ok = true;
            } else ok = attack(p, f, t);
            if (!ok) continue;
            if (std.ascii.toUpper(c) == 'P' and (t / 8 == 0 or t / 8 == 7)) {
                for ("QRBN") |prom| list.add(.{ .f = f, .t = t, .p = prom });
            } else list.add(.{ .f = f, .t = t });
        }
    }
    return list;
}

fn legal(p: Pos) Moves {
    var list: Moves = .{};
    const ps = pseudo(p);
    for (ps.a[0..ps.n]) |m| if (!check(after(p, m), p.white)) {
        list.add(m);
    };
    for ([_]bool{ true, false }) |k| if (castleReason(p, k) == null) {
        const base: usize = if (p.white) 0 else 56;
        list.add(.{ .f = base + 4, .t = base + (if (k) @as(usize, 6) else 2) });
    };
    return list;
}

fn disamb(p: Pos, m: Move, ls: Moves) !S {
    var any = false;
    var samef = false;
    var samer = false;
    for (ls.a[0..ls.n]) |n| if (n.f != m.f and n.t == m.t and p.b[n.f] == p.b[m.f] and !castle(p, n)) {
        any = true;
        if (n.f % 8 == m.f % 8) samef = true;
        if (n.f / 8 == m.f / 8) samer = true;
    };
    if (!any) return "";
    if (!samef) return fmt("{c}", .{@as(u8, @intCast(m.f % 8)) + 'a'});
    if (!samer) return fmt("{c}", .{@as(u8, @intCast(m.f / 8)) + '1'});
    return name(m.f);
}

fn mark(p: Pos, m: Move) S {
    const q = after(p, m);
    if (!check(q, q.white)) return "";
    return if (legal(q).n == 0) "#" else "+";
}

fn san(p: Pos, m: Move, ls: Moves) !S {
    var s: S = "";
    if (castle(p, m)) s = if (m.t > m.f) "O-O" else "O-O-O" else {
        const pawn = std.ascii.toUpper(p.b[m.f]) == 'P';
        const prefix = if (pawn) (if (capture(p, m)) try fmt("{c}", .{@as(u8, @intCast(m.f % 8)) + 'a'}) else "") else try fmt("{c}{s}", .{ std.ascii.toUpper(p.b[m.f]), try disamb(p, m, ls) });
        s = try fmt("{s}{s}{s}{s}", .{ prefix, if (capture(p, m)) @as(S, "x") else "", try name(m.t), if (m.p != 0) try fmt("={c}", .{m.p}) else "" });
    }
    return fmt("{s}{s}", .{ s, mark(p, m) });
}

fn uci(m: Move) !S {
    return fmt("{s}{s}{s}", .{ try name(m.f), try name(m.t), if (m.p == 0) @as(S, "") else try fmt("{c}", .{std.ascii.toLower(m.p)}) });
}

fn fen(p: Pos) !S {
    var s: std.ArrayList(u8) = .empty;
    var r: usize = 8;
    while (r > 0) {
        r -= 1;
        if (r < 7) try s.append(A, '/');
        var empty: u8 = 0;
        for (0..8) |f| {
            const c = p.b[r * 8 + f];
            if (c == '.') {
                empty += 1;
            } else {
                if (empty > 0) {
                    try s.append(A, '0' + empty);
                    empty = 0;
                }
                try s.append(A, c);
            }
        }
        if (empty > 0) try s.append(A, '0' + empty);
    }
    var rights: std.ArrayList(u8) = .empty;
    for ("KQkq", 0..) |c, i| if (p.rights & (@as(u8, 1) << @intCast(i)) != 0) {
        try rights.append(A, c);
    };
    return fmt("{s} {s} {s} {s} {d} {d}", .{ s.items, if (p.white) @as(S, "w") else "b", if (rights.items.len == 0) @as(S, "-") else rights.items, if (p.ep) |e| try name(e) else "-", p.half, p.full });
}

const ReadFen = struct { p: Pos = .{}, reason: ?S = null };

fn badFen(reason: S) ReadFen {
    return .{ .reason = reason };
}

fn readFen(w: []const S) ReadFen {
    if (w.len != 6) return badFen("fields");
    var p: Pos = .{};
    var ranks = std.mem.splitScalar(u8, w[0], '/');
    var r: usize = 8;
    while (ranks.next()) |rank| {
        if (r == 0) return badFen("placement");
        r -= 1;
        var f: usize = 0;
        var prev = false;
        for (rank) |c| {
            if (c >= '1' and c <= '8') {
                if (prev) return badFen("placement");
                f += c - '0';
                prev = true;
            } else {
                if (std.mem.indexOfScalar(u8, "KQRBNPkqrbnp", c) == null or f >= 8) return badFen("placement");
                p.b[r * 8 + f] = c;
                f += 1;
                prev = false;
            }
            if (f > 8) return badFen("placement");
        }
        if (f != 8) return badFen("placement");
    }
    if (r != 0) return badFen("placement");
    var wk: usize = 0;
    var bk: usize = 0;
    for (p.b) |c| {
        if (c == 'K') wk += 1;
        if (c == 'k') bk += 1;
    }
    if (wk != 1 or bk != 1) return badFen("kings");
    for (0..8) |i| if (std.ascii.toUpper(p.b[i]) == 'P' or std.ascii.toUpper(p.b[56 + i]) == 'P') return badFen("pawns");
    if (!eq(w[1], "w") and !eq(w[1], "b")) return badFen("side");
    p.white = eq(w[1], "w");
    if (!eq(w[2], "-")) {
        var last: i32 = -1;
        if (w[2].len == 0) return badFen("castling");
        for (w[2]) |c| {
            const i = std.mem.indexOfScalar(u8, "KQkq", c) orelse return badFen("castling");
            if (@as(i32, @intCast(i)) <= last) return badFen("castling");
            last = @intCast(i);
            const base: usize = if (i < 2) 0 else 56;
            if (p.b[base + 4] != (if (i < 2) @as(u8, 'K') else 'k') or p.b[base + (if (i % 2 == 0) @as(usize, 7) else 0)] != (if (i < 2) @as(u8, 'R') else 'r')) return badFen("castling");
            p.rights |= @as(u8, 1) << @intCast(i);
        }
    }
    if (!eq(w[3], "-")) {
        const e = sq(w[3]) orelse return badFen("en passant");
        if (e / 8 != (if (p.white) @as(usize, 5) else 2) or p.b[e] != '.' or p.b[if (p.white) e + 8 else e - 8] != '.' or p.b[if (p.white) e - 8 else e + 8] != (if (p.white) @as(u8, 'p') else 'P')) return badFen("en passant");
        p.ep = e;
    }
    p.half = number(w[4], 0, 999) orelse return badFen("clocks");
    p.full = number(w[5], 1, 999) orelse return badFen("clocks");
    if (p.ep != null and p.half != 0) return badFen("clocks");
    if (check(p, !p.white)) return badFen("check");
    return .{ .p = p };
}

const Record = struct { p: Pos, s: S, u: S, c: u8 };

var history: std.ArrayList(Record) = .empty;

var current: Pos = undefined;

var start: Pos = undefined;
var loaded = false;

fn initial() Pos {
    return readFen(&.{ "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", "w", "KQkq", "-", "0", "1" }).p;
}

fn key(p0: Pos) !S {
    var p = p0;
    var ep = false;
    const ls = legal(p);
    for (ls.a[0..ls.n]) |m| if (enpassant(p, m)) {
        ep = true;
    };
    if (!ep) p.ep = null;
    p.half = 0;
    p.full = 1;
    return fen(p);
}

fn repetition() !usize {
    const k = try key(current);
    var n: usize = 1;
    for (history.items) |r| if (eq(k, try key(r.p))) {
        n += 1;
    };
    return n;
}

fn draw() !S {
    var s: S = "";
    if (current.half >= 100) s = " fifty";
    if (try repetition() >= 3) s = try fmt("{s} threefold", .{s});
    var minors: usize = 0;
    var allb = true;
    var parity: ?usize = null;
    var insufficient = true;
    for (current.b, 0..) |c, i| {
        const t = std.ascii.toUpper(c);
        if (c == '.' or t == 'K') continue;
        if (t == 'P' or t == 'R' or t == 'Q') insufficient = false;
        minors += 1;
        if (t != 'B') allb = false;
        const q = (i % 8 + i / 8) % 2;
        if (parity) |v| {
            if (v != q) allb = false;
        } else parity = q;
    }
    if (insufficient and (minors <= 1 or allb)) s = try fmt("{s} insufficient", .{s});
    return s;
}

fn state() S {
    const n = legal(current).n;
    return if (check(current, current.white)) (if (n == 0) "checkmate" else "check") else (if (n == 0) "stalemate" else "normal");
}

fn result() !S {
    const st = state();
    if (eq(st, "checkmate")) return if (current.white) "0-1" else "1-0";
    return if (eq(st, "stalemate") or (try draw()).len > 0) "1/2-1/2" else "*";
}

fn play(m: Move) !void {
    const s = try san(current, m, legal(current));
    try history.append(A, .{ .p = current, .s = s, .u = try uci(m), .c = if (current.b[m.t] != '.') std.ascii.toLower(current.b[m.t]) else if (enpassant(current, m)) @as(u8, 'p') else '-' });
    current = after(current, m);
}

const Parsed = struct { m: Move = .{ .f = 0, .t = 0 }, reason: ?S = null };

fn illegal(reason: S) Parsed {
    return .{ .reason = reason };
}

fn readMove(w: S, isuci: bool) !Parsed {
    var f: ?usize = null;
    var t: usize = 0;
    var prom: u8 = 0;
    var kind: u8 = 'P';
    var cap = false;
    var df: ?u8 = null;
    var dr: ?u8 = null;
    var cm: S = "";
    var cast: ?bool = null;
    var u = w;
    if (isuci) {
        if ((w.len != 4 and w.len != 5) or sq(w[0..@min(2, w.len)]) == null) return illegal("syntax");
        f = sq(w[0..2]);
        t = sq(w[2..4]) orelse return illegal("syntax");
        if (w.len == 5) {
            if (std.mem.indexOfScalar(u8, "qrbn", w[4]) == null) return illegal("syntax");
            prom = std.ascii.toUpper(w[4]);
        }
    } else {
        if (u.len > 0 and (u[u.len - 1] == '+' or u[u.len - 1] == '#')) {
            cm = u[u.len - 1 ..];
            u = u[0 .. u.len - 1];
        }
        if (eq(u, "O-O") or eq(u, "O-O-O")) cast = eq(u, "O-O") else {
            if (u.len >= 2 and u[u.len - 2] == '=') {
                prom = u[u.len - 1];
                if (std.mem.indexOfScalar(u8, "QRBN", prom) == null) return illegal("syntax");
                u = u[0 .. u.len - 2];
            }
            if (u.len < 2) return illegal("syntax");
            t = sq(u[u.len - 2 ..]) orelse return illegal("syntax");
            u = u[0 .. u.len - 2];
            if (u.len > 0 and u[u.len - 1] == 'x') {
                cap = true;
                u = u[0 .. u.len - 1];
            }
            if (u.len > 0 and std.mem.indexOfScalar(u8, "KQRBN", u[0]) != null) {
                kind = u[0];
                u = u[1..];
                if (prom != 0) return illegal("syntax");
                if (u.len > 0 and u[0] >= 'a' and u[0] <= 'h') {
                    df = u[0];
                    u = u[1..];
                }
                if (u.len > 0 and u[0] >= '1' and u[0] <= '8') {
                    dr = u[0];
                    u = u[1..];
                }
                if (u.len != 0) return illegal("syntax");
            } else {
                if (cap) {
                    if (u.len != 1 or u[0] < 'a' or u[0] > 'h') return illegal("syntax");
                    df = u[0];
                } else if (u.len != 0) return illegal("syntax");
            }
        }
    }
    const ls = legal(current);
    if (ls.n == 0) return illegal("game over");
    if (cast) |k| {
        if (castleReason(current, k)) |why| return illegal(why);
        const b: usize = if (current.white) 0 else 56;
        const m: Move = .{ .f = b + 4, .t = b + (if (k) @as(usize, 6) else 2) };
        if (!eq(mark(current, m), cm)) return illegal("check mark");
        return .{ .m = m };
    }
    if (isuci and (current.b[f.?] == '.' or color(current.b[f.?]) != current.white)) return illegal("no piece");
    var matches: Moves = .{};
    const ps = pseudo(current);
    var haspseudo = false;
    for (ps.a[0..ps.n]) |m| if (matching(m, isuci, f, t, kind, df, dr, cap)) {
        haspseudo = true;
    };
    for (ls.a[0..ls.n]) |m| if (matching(m, isuci, f, t, kind, df, dr, cap)) {
        matches.add(m);
    };
    if (matches.n == 0) return illegal(if (haspseudo) "leaves king in check" else "no such move");
    const first = matches.a[0];
    for (matches.a[0..matches.n]) |m| if (m.f != first.f) return illegal("ambiguous");
    if (!isuci and capture(current, first) != cap) return illegal("capture mark");
    if (first.p != 0 and prom == 0) return illegal("missing promotion");
    if (first.p == 0 and prom != 0) return illegal("invalid promotion");
    if (!isuci and kind != 'P') {
        var d: std.ArrayList(u8) = .empty;
        if (df) |c| try d.append(A, c);
        if (dr) |c| try d.append(A, c);
        if (!eq(d.items, try disamb(current, first, ls))) return illegal("disambiguation");
    }
    var m = first;
    m.p = prom;
    if (!isuci and !eq(mark(current, m), cm)) return illegal("check mark");
    return .{ .m = m };
}

fn matching(m: Move, isuci: bool, f: ?usize, t: usize, kind: u8, df: ?u8, dr: ?u8, cap: bool) bool {
    if (m.t != t) return false;
    if (isuci) return m.f == f.?;
    if (castle(current, m) or std.ascii.toUpper(current.b[m.f]) != kind) return false;
    if (df) |c| if (m.f % 8 != c - 'a') return false;
    if (dr) |c| if (m.f / 8 != c - '1') return false;
    return kind != 'P' or (m.f % 8 != m.t % 8) == cap;
}

const Stats = struct { v: [7]u64 = @as([7]u64, @splat(0)) };

fn perft(p: Pos, d: usize) Stats {
    var s: Stats = .{};
    if (d == 0) {
        s.v[0] = 1;
        return s;
    }
    const ls = legal(p);
    for (ls.a[0..ls.n]) |m| {
        const q = after(p, m);
        if (d == 1) {
            s.v[0] += 1;
            if (capture(p, m)) s.v[1] += 1;
            if (enpassant(p, m)) s.v[2] += 1;
            if (castle(p, m)) s.v[3] += 1;
            if (m.p != 0) s.v[4] += 1;
            if (check(q, q.white)) {
                s.v[5] += 1;
                if (legal(q).n == 0) s.v[6] += 1;
            }
        } else {
            const x = perft(q, d - 1);
            for (0..7) |i| s.v[i] += x.v[i];
        }
    }
    return s;
}

const Named = struct { m: Move, s: S };

fn less(_: void, a: Named, b: Named) bool {
    return std.mem.order(u8, a.s, b.s) == .lt;
}

fn command(w: []const S) !void {
    const c = w[0];
    const a = w[1..];
    const zero = eq(c, "NEW") or eq(c, "FEN") or eq(c, "BOARD") or eq(c, "STATUS") or eq(c, "PINS") or eq(c, "HISTORY") or eq(c, "PGN");
    if (!zero and !eq(c, "LOAD") and !eq(c, "MOVE") and !eq(c, "UCI") and !eq(c, "LEGAL") and !eq(c, "UNDO") and !eq(c, "PERFT") and !eq(c, "DIVIDE") and !eq(c, "ATTACKS")) {
        try line("ERROR unknown command");
        return;
    }
    if ((zero and a.len != 0) or ((eq(c, "MOVE") or eq(c, "UCI")) and a.len == 0) or (eq(c, "LEGAL") and (a.len > 1 or (a.len == 1 and sq(a[0]) == null))) or (eq(c, "ATTACKS") and (a.len != 1 or sq(a[0]) == null)) or ((eq(c, "UNDO") or eq(c, "PERFT") or eq(c, "DIVIDE")) and (a.len != 1 or number(a[0], 1, if (eq(c, "UNDO")) 9999 else 3) == null))) {
        try line("ERROR bad arguments");
        return;
    }
    if (eq(c, "NEW")) {
        current = initial();
        start = current;
        history.clearRetainingCapacity();
        loaded = false;
        try line("OK");
    } else if (eq(c, "LOAD")) {
        const r = readFen(a);
        if (r.reason) |why| try line(try fmt("ERROR bad fen ({s})", .{why})) else {
            current = r.p;
            start = current;
            history.clearRetainingCapacity();
            loaded = true;
            try line("OK");
        }
    } else if (eq(c, "FEN")) try line(try fen(current)) else if (eq(c, "BOARD")) {
        var r: usize = 8;
        while (r > 0) {
            r -= 1;
            try put(try fmt("{d}", .{r + 1}));
            for (0..8) |f| try put(try fmt(" {c}", .{current.b[r * 8 + f]}));
            try put("\n");
        }
        try line("  a b c d e f g h");
    } else if (eq(c, "MOVE") or eq(c, "UCI")) {
        const isuci = eq(c, "UCI");
        var sans: std.ArrayList(S) = .empty;
        var failure: ?S = null;
        for (a, 1..) |word, i| {
            const r = try readMove(word, isuci);
            if (r.reason) |why| {
                failure = try fmt("ILLEGAL move {d}: {s} ({s})", .{ i, word, why });
                break;
            }
            try play(r.m);
            try sans.append(A, history.items[history.items.len - 1].s);
        }
        if (isuci and sans.items.len > 0) {
            try put("san");
            for (sans.items) |s| try put(try fmt(" {s}", .{s}));
            try put("\n");
        }
        if (failure) |s| try line(s) else if (!isuci) try line("OK");
    } else if (eq(c, "STATUS")) try line(try fmt("status {s} {s} rep {d}{s}", .{ if (current.white) @as(S, "white") else "black", state(), try repetition(), try draw() })) else if (eq(c, "UNDO")) {
        const n = number(a[0], 1, 9999).?;
        if (n > history.items.len) try line("ERROR cannot undo") else {
            current = history.items[history.items.len - n].p;
            history.shrinkRetainingCapacity(history.items.len - n);
            try line("OK");
        }
    } else if (eq(c, "LEGAL") or eq(c, "DIVIDE")) {
        const ls = legal(current);
        var ns: std.ArrayList(Named) = .empty;
        for (ls.a[0..ls.n]) |m| {
            if (eq(c, "LEGAL") and a.len == 1 and m.f != sq(a[0]).?) continue;
            try ns.append(A, .{ .m = m, .s = try san(current, m, ls) });
        }
        std.mem.sort(Named, ns.items, {}, less);
        if (eq(c, "LEGAL")) {
            try put(try fmt("legal {d}", .{ns.items.len}));
            for (ns.items) |n| try put(try fmt(" {s}", .{n.s}));
            try put("\n");
        } else {
            var total: u64 = 0;
            for (ns.items) |n| {
                const v = perft(after(current, n.m), number(a[0], 1, 3).? - 1).v[0];
                total += v;
                try line(try fmt("{s} {d}", .{ n.s, v }));
            }
            try line(try fmt("total {d}", .{total}));
        }
    } else if (eq(c, "PERFT")) {
        const d = number(a[0], 1, 3).?;
        const s = perft(current, d).v;
        try line(try fmt("perft {d} nodes {d} captures {d} ep {d} castles {d} promotions {d} checks {d} mates {d}", .{ d, s[0], s[1], s[2], s[3], s[4], s[5], s[6] }));
    } else if (eq(c, "ATTACKS")) {
        const t = sq(a[0]).?;
        try put(try fmt("attacks {s}", .{a[0]}));
        for ([_]bool{ true, false }) |white| {
            var n: usize = 0;
            for (current.b, 0..) |piece, f| if (piece != '.' and color(piece) == white and attack(current, f, t)) {
                n += 1;
            };
            try put(try fmt(" {s} {d}", .{ if (white) @as(S, "white") else "black", n }));
            for (current.b, 0..) |piece, f| if (piece != '.' and color(piece) == white and attack(current, f, t)) {
                try put(try fmt(" {s}", .{try name(f)}));
            };
        }
        try put("\n");
    } else if (eq(c, "PINS")) {
        var pins: [64]?usize = @as([64]?usize, @splat(null));
        var king: usize = 0;
        for (current.b, 0..) |piece, i| if (piece == (if (current.white) @as(u8, 'K') else 'k')) {
            king = i;
        };
        for ([_][2]i32{ .{ 0, 1 }, .{ 0, -1 }, .{ 1, 0 }, .{ -1, 0 }, .{ 1, 1 }, .{ 1, -1 }, .{ -1, 1 }, .{ -1, -1 } }) |d| {
            var x = @as(i32, @intCast(king % 8)) + d[0];
            var y = @as(i32, @intCast(king / 8)) + d[1];
            var first: ?usize = null;
            while (x >= 0 and x < 8 and y >= 0 and y < 8) : ({
                x += d[0];
                y += d[1];
            }) {
                const i: usize = @intCast(y * 8 + x);
                const piece = current.b[i];
                if (piece == '.') continue;
                if (first) |f| {
                    const k = std.ascii.toUpper(piece);
                    if (color(piece) != current.white and (k == 'Q' or (k == 'R' and (d[0] == 0 or d[1] == 0)) or (k == 'B' and d[0] != 0 and d[1] != 0))) pins[f] = i;
                    break;
                } else {
                    if (color(piece) != current.white) break;
                    first = i;
                }
            }
        }
        var n: usize = 0;
        for (pins) |v| if (v != null) {
            n += 1;
        };
        try put(try fmt("pins {d}", .{n}));
        for (pins, 0..) |v, i| if (v) |j| try put(try fmt(" {s}-{s}", .{ try name(i), try name(j) }));
        try put("\n");
    } else if (eq(c, "HISTORY")) {
        try line(try fmt("history {d}", .{history.items.len}));
        for (history.items, 1..) |r, i| try line(try fmt("{d} {s} {s} {c}", .{ i, r.u, r.s, r.c }));
    } else if (eq(c, "PGN")) {
        const res = try result();
        try line(try fmt("[Result \"{s}\"]", .{res}));
        if (loaded) {
            try line("[SetUp \"1\"]");
            try line(try fmt("[FEN \"{s}\"]", .{try fen(start)}));
        }
        for (history.items, 0..) |r, i| {
            if (r.p.white) try put(try fmt("{d}. ", .{r.p.full})) else if (i == 0) try put(try fmt("{d}... ", .{r.p.full}));
            try put(try fmt("{s} ", .{r.s}));
        }
        try line(res);
    }
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const text = try input.interface.allocRemaining(A, .unlimited);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const n = try std.fmt.parseInt(usize, lines.next() orelse "0", 10);
    current = initial();
    start = current;
    for (0..n) |_| {
        const l = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
        var words: std.ArrayList(S) = .empty;
        var it = std.mem.tokenizeScalar(u8, l, ' ');
        while (it.next()) |w| try words.append(A, w);
        try command(words.items);
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(output.items);
    try sink.interface.flush();
}
