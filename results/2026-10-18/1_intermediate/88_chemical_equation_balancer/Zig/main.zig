const std = @import("std");
const A = std.heap.page_allocator;
const S = []const u8;

var output: std.ArrayList(u8) = .empty;

var why: S = "";

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
    try output.appendSlice(A, s);
}

fn line(s: S) !void {
    try put(s);
    try put("\n");
}
const symbols = [_]S{ "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca", "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr", "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe" };
const weights = [_]i128{ 1008, 4003, 6941, 9012, 10811, 12011, 14007, 15999, 18998, 20180, 22990, 24305, 26982, 28086, 30974, 32065, 35453, 39948, 39098, 40078, 44956, 47867, 50942, 51996, 54938, 55845, 58933, 58693, 63546, 65380, 69723, 72630, 74922, 78971, 79904, 83798, 85468, 87620, 88906, 91224, 92906, 95950, 98000, 101070, 102906, 106420, 107868, 112414, 114818, 118710, 121760, 127600, 126904, 131293 };

fn element(s: S) ?usize {
    for (symbols, 0..) |v, i| if (eq(s, v)) return i;
    return null;
}

fn checkedElement(s: S) !usize {
    return element(s) orelse fail("unknown element {s}", .{s});
}

fn gcd(a0: i128, b0: i128) i128 {
    var a: i128 = @intCast(@abs(a0));
    var b: i128 = @intCast(@abs(b0));
    while (b != 0) {
        const r = @rem(a, b);
        a = b;
        b = r;
    }
    return a;
}

fn decimal(n: i128, d: usize) !S {
    const scale: i128 = if (d == 2) 100 else if (d == 3) 1000 else 1000000;
    const a: i128 = @intCast(@abs(n));
    const tail = if (d == 2) try fmt("{d:0>2}", .{@mod(a, scale)}) else if (d == 3) try fmt("{d:0>3}", .{@mod(a, scale)}) else try fmt("{d:0>6}", .{@mod(a, scale)});
    return fmt("{s}{d}.{s}", .{ if (n < 0) @as(S, "-") else "", @divTrunc(a, scale), tail });
}

fn signed(n: i128) !S {
    return if (n > 0) fmt("+{d}", .{n}) else fmt("{d}", .{n});
}

const Q = struct {
    p: i128 = 0,
    q: i128 = 1,
    fn make(p: i128, q: i128) Q {
        const g = gcd(p, q);
        return .{ .p = @divTrunc(p, if (q < 0) -g else g), .q = @divTrunc(q, if (q < 0) -g else g) };
    }
    fn sub(a: Q, b: Q) Q {
        return make(a.p * b.q - b.p * a.q, a.q * b.q);
    }
    fn mul(a: Q, b: Q) Q {
        return make(a.p * b.p, a.q * b.q);
    }
    fn div(a: Q, b: Q) Q {
        return make(a.p * b.q, a.q * b.p);
    }
};

fn rational(q: Q) !S {
    if (q.p == 0) return "0";
    if (q.q == 1) return signed(q.p);
    return fmt("{s}/{d}", .{ try signed(q.p), q.q });
}
const Composition = [54]i128;

const Formula = struct {
    a: Composition = @as([54]i128, @splat(0)),
    charge: i128 = 0,
    fn mass(f: Formula) i128 {
        var n: i128 = 0;
        for (f.a, weights) |c, w| n += c * w;
        return n;
    }
};

const FormulaParser = struct {
    s: S,
    i: usize = 0,
    unknown: ?S = null,
    fn number(p: *FormulaParser) !i128 {
        if (p.i >= p.s.len or !std.ascii.isDigit(p.s[p.i])) return 1;
        const start = p.i;
        while (p.i < p.s.len and std.ascii.isDigit(p.s[p.i])) p.i += 1;
        if (p.s[start] == '0') return error.Syntax;
        return std.fmt.parseInt(i128, p.s[start..p.i], 10);
    }
    fn sequence(p: *FormulaParser) anyerror!Composition {
        var result: Composition = @as([54]i128, @splat(0));
        var count: usize = 0;
        while (p.i < p.s.len) {
            const c = p.s[p.i];
            var a: Composition = @as([54]i128, @splat(0));
            if (std.ascii.isUpper(c)) {
                const start = p.i;
                p.i += 1;
                if (p.i < p.s.len and std.ascii.isLower(p.s[p.i])) p.i += 1;
                const sym = p.s[start..p.i];
                if (element(sym)) |e| a[e] = 1 else if (p.unknown == null) p.unknown = sym;
            } else if (c == '(' or c == '[') {
                p.i += 1;
                a = try p.sequence();
                if (p.i >= p.s.len or p.s[p.i] != (if (c == '(') @as(u8, ')') else ']')) return error.Syntax;
                p.i += 1;
            } else break;
            const n = try p.number();
            for (&result, a) |*v, x| v.* = v.* +| (x *| n);
            count += 1;
        }
        if (count == 0) return error.Syntax;
        return result;
    }
    fn parse(p: *FormulaParser) !Formula {
        var f: Formula = .{ .a = try p.sequence() };
        while (p.i < p.s.len and p.s[p.i] == '.') {
            p.i += 1;
            const n = try p.number();
            const a = try p.sequence();
            for (&f.a, a) |*v, x| v.* = v.* +| (n *| x);
        }
        if (p.i < p.s.len and p.s[p.i] == '^') {
            p.i += 1;
            const n = try p.number();
            if (p.i >= p.s.len or (p.s[p.i] != '+' and p.s[p.i] != '-')) return error.Syntax;
            f.charge = if (p.s[p.i] == '+') n else -n;
            p.i += 1;
        }
        if (p.i != p.s.len) return error.Syntax;
        return f;
    }
};

fn formula(s: S, original: S) !Formula {
    var p = FormulaParser{ .s = s };
    const f = p.parse() catch return fail("invalid formula {s}", .{original});
    if (p.unknown) |u| return fail("unknown element {s}", .{u});
    return f;
}

fn hillOrder(a: Composition) ![]usize {
    var list: std.ArrayList(usize) = .empty;
    for (a, 0..) |v, i| if (v > 0) {
        try list.append(A, i);
    };
    const C = struct {
        fn less(carbon: bool, x: usize, y: usize) bool {
            if (carbon) {
                const ax: usize = if (x == 5) 0 else if (x == 0) 1 else 2;
                const ay: usize = if (y == 5) 0 else if (y == 0) 1 else 2;
                if (ax != ay) return ax < ay;
            }
            return std.mem.order(u8, symbols[x], symbols[y]) == .lt;
        }
    };
    std.mem.sort(usize, list.items, a[5] > 0, C.less);
    return list.toOwnedSlice(A);
}

fn hill(f: Formula, charge: bool) !S {
    var s: S = "";
    for (try hillOrder(f.a)) |e| s = try fmt("{s}{s}{s}", .{ s, symbols[e], if (f.a[e] == 1) @as(S, "") else try fmt("{d}", .{f.a[e]}) });
    if (charge and f.charge != 0) s = try fmt("{s}^{s}{c}", .{ s, if (@abs(f.charge) == 1) @as(S, "") else try fmt("{d}", .{@abs(f.charge)}), if (f.charge > 0) @as(u8, '+') else '-' });
    return s;
}

fn scaled(s: S, enthalpy: bool) !i128 {
    const original = s;
    const negative = enthalpy and s.len > 0 and s[0] == '-';
    const u = if (negative) s[1..] else s;
    const dot = std.mem.indexOfScalar(u8, u, '.');
    const a = if (dot) |i| u[0..i] else u;
    const b = if (dot) |i| u[i + 1 ..] else "";
    const d: usize = if (enthalpy) 2 else 3;
    const max: usize = if (enthalpy) 5 else 4;
    var valid = a.len > 0 and a.len <= max and !(a.len > 1 and a[0] == '0') and (dot == null or (b.len > 0 and b.len <= d));
    for (a) |c| valid = valid and std.ascii.isDigit(c);
    for (b) |c| valid = valid and std.ascii.isDigit(c);
    if (!valid) return fail("invalid {s} {s}", .{ if (enthalpy) @as(S, "enthalpy") else "quantity", original });
    const scale: i128 = if (enthalpy) 100 else 1000;
    var n = (try std.fmt.parseInt(i128, a, 10)) * scale;
    if (b.len > 0) {
        var fraction = try std.fmt.parseInt(i128, b, 10);
        for (b.len..d) |_| fraction *= 10;
        n += fraction;
    }
    if (!enthalpy and n == 0) return fail("invalid quantity {s}", .{original});
    return if (negative) -n else n;
}

const Species = struct { name: S, core: S, state: S = "", f: Formula, c: i128 = 1 };

fn species(s: S, coeff: bool) !Species {
    var core = s;
    var state: S = "";
    for ([_]S{ "(s)", "(l)", "(g)", "(aq)" }) |suffix| if (std.mem.endsWith(u8, core, suffix)) {
        state = suffix;
        core = core[0 .. core.len - suffix.len];
        break;
    };
    var offset: usize = 0;
    var c: i128 = 1;
    if (coeff and core.len > 0 and std.ascii.isDigit(core[0])) {
        while (offset < core.len and std.ascii.isDigit(core[offset])) offset += 1;
        if (core[0] == '0') return fail("invalid formula {s}", .{s});
        c = try std.fmt.parseInt(i128, core[0..offset], 10);
    }
    const f = try formula(core[offset..], s);
    return .{ .name = s[offset..], .core = core[offset..], .state = state, .f = f, .c = c };
}

const Equation = struct { xs: []Species, r: usize, aux_start: ?usize = null };

fn equation(w: []const S, coeff: bool) !Equation {
    if (w.len == 0 or w.len % 2 == 0) return fail("malformed equation", .{});
    var arrow: ?usize = null;
    for (w, 0..) |s, i| {
        if (i % 2 == 0) {
            if (eq(s, "+") or eq(s, "->")) return fail("malformed equation", .{});
        } else if (eq(s, "->")) {
            if (arrow != null) return fail("malformed equation", .{});
            arrow = (i + 1) / 2;
        } else if (!eq(s, "+")) return fail("malformed equation", .{});
    }
    const r = arrow orelse return fail("malformed equation", .{});
    const xs = try A.alloc(Species, (w.len + 1) / 2);
    for (xs, 0..) |*v, i| v.* = try species(w[2 * i], coeff);
    return .{ .xs = xs, .r = r };
}

const Matrix = struct { rows: []CompositionRow, elements: []usize, rank: usize, basis: [][]i128 };
const CompositionRow = []i128;

fn matrix(e: Equation) !Matrix {
    var union_a: Composition = @as([54]i128, @splat(0));
    for (e.xs) |s| for (&union_a, s.f.a) |*a, b| a.* += b;
    const els = try hillOrder(union_a);
    const m = els.len + 1;
    const n = e.xs.len;
    const rows = try A.alloc(CompositionRow, m);
    const a = try A.alloc([]Q, m);
    for (0..m) |i| {
        rows[i] = try A.alloc(i128, n);
        a[i] = try A.alloc(Q, n);
        for (e.xs, 0..) |s, j| {
            const v = (if (j < e.r or (e.aux_start != null and j >= e.aux_start.?)) @as(i128, 1) else -1) * (if (i == els.len) s.f.charge else s.f.a[els[i]]);
            rows[i][j] = v;
            a[i][j] = .{ .p = v };
        }
    }
    var rank: usize = 0;
    var pivots: std.ArrayList(usize) = .empty;
    var free: std.ArrayList(usize) = .empty;
    for (0..n) |j| {
        var pivot: ?usize = null;
        for (rank..m) |i| if (a[i][j].p != 0) {
            pivot = i;
            break;
        };
        if (pivot == null) {
            try free.append(A, j);
            continue;
        }
        std.mem.swap([]Q, &a[rank], &a[pivot.?]);
        const divisor = a[rank][j];
        for (a[rank]) |*v| v.* = v.div(divisor);
        for (0..m) |i| {
            if (i == rank) continue;
            const t = a[i][j];
            for (0..n) |k| a[i][k] = a[i][k].sub(t.mul(a[rank][k]));
        }
        try pivots.append(A, j);
        rank += 1;
    }
    var basis: std.ArrayList([]i128) = .empty;
    for (free.items) |f| {
        const v = try A.alloc(Q, n);
        @memset(v, .{});
        v[f] = .{ .p = 1 };
        for (pivots.items, 0..) |p, i| v[p] = .{ .p = -a[i][f].p, .q = a[i][f].q };
        var lcm: i128 = 1;
        for (v) |x| lcm = @divTrunc(lcm, gcd(lcm, x.q)) * x.q;
        const ints = try A.alloc(i128, n);
        var g: i128 = 0;
        for (v, 0..) |x, i| {
            ints[i] = x.p * @divTrunc(lcm, x.q);
            g = gcd(g, ints[i]);
        }
        for (ints) |*x| x.* = @divTrunc(x.*, g);
        try basis.append(A, ints);
    }
    return .{ .rows = rows, .elements = els, .rank = rank, .basis = try basis.toOwnedSlice(A) };
}

const Balance = struct { c: []i128 = &.{}, message: ?S = null };

fn balance(e: Equation, k: usize) !Balance {
    const m = try matrix(e);
    if (m.basis.len == 0) return .{ .message = "IMPOSSIBLE" };
    if (m.basis.len > 1) return .{ .message = try fmt("AMBIGUOUS (nullity {d})", .{m.basis.len}) };
    const c = m.basis[0];
    if (c[0] < 0) for (c) |*v| {
        v.* = -v.*;
    };
    for (c[0..k]) |v| if (v <= 0) return .{ .message = "IMPOSSIBLE" };
    return .{ .c = c };
}

fn term(s: S, c: i128) !S {
    return if (c == 1) s else fmt("{d}{s}", .{ c, s });
}

fn notation(e: Equation, c: []const i128, original: usize) !S {
    var left: S = "";
    var right: S = "";
    for (e.xs, 0..) |s, i| {
        if (c[i] == 0) continue;
        const reactant = if (i < original) i < e.r else c[i] > 0;
        const t = try term(s.name, @intCast(@abs(c[i])));
        const p = if (reactant) &left else &right;
        p.* = try fmt("{s}{s}{s}", .{ p.*, if (p.*.len == 0) @as(S, "") else " + ", t });
    }
    return fmt("{s} -> {s}", .{ left, right });
}

fn ratioReport(a: Composition) !void {
    const els = try hillOrder(a);
    var f = els[0];
    for (els) |e| if (a[e] * weights[f] < a[f] * weights[e]) {
        f = e;
    };
    for (els) |e| try line(try fmt("{s} {s}", .{ symbols[e], try decimal(@divTrunc(1000 * a[e] * weights[f], weights[e] * a[f]), 3) }));
    for (1..13) |k| {
        var comp: Formula = .{};
        var ok = true;
        for (els) |e| {
            const p = @as(i128, @intCast(k)) * a[e] * weights[f];
            const q = weights[e] * a[f];
            const i = @divTrunc(2 * p + q, 2 * q);
            if (20 * @as(i128, @intCast(@abs(p - i * q))) > q) ok = false;
            comp.a[e] = i;
        }
        if (ok) {
            try line(try fmt("{s} (k = {d})", .{ try hill(comp, false), k }));
            return;
        }
    }
    try line("no simple ratio");
}

fn ionPart(s: S, k: i128) !S {
    const end = std.mem.indexOfScalar(u8, s, '^') orelse s.len;
    const core = s[0..end];
    if (k == 1) return core;
    var single = core.len > 0 and std.ascii.isUpper(core[0]);
    for (core[1..], 1..) |c, i| if (i > 1 or !std.ascii.isLower(c)) {
        single = false;
    };
    var bracket = false;
    if (core.len > 0 and core[0] == '[') {
        var depth: i32 = 0;
        for (core, 0..) |c, i| {
            if (c == '[') depth += 1;
            if (c == ']') depth -= 1;
            if (depth == 0) {
                bracket = i + 1 == core.len;
                break;
            }
        }
    }
    return if (single or bracket) fmt("{s}{d}", .{ core, k }) else fmt("({s}){d}", .{ core, k });
}

fn fixed(e: usize) ?i128 {
    return switch (e) {
        2, 10, 18, 36 => 1,
        3, 11, 19, 37 => 2,
        12 => 3,
        else => null,
    };
}

fn oxidation(f: Formula) !void {
    const els = try hillOrder(f.a);
    var values: [54]?Q = @as([54]?Q, @splat(null));
    if (els.len == 1) {
        values[els[0]] = Q.make(f.charge, f.a[els[0]]);
    } else {
        var last: usize = 0;
        if (f.a[8] > 0) {
            values[8] = .{ .p = -1 };
            last = 8;
        }
        for (els) |e| if (fixed(e)) |v| {
            values[e] = .{ .p = v };
            last = e;
        };
        if (f.a[0] > 0) {
            var hydride = true;
            for (els) |e| if (e != 0 and fixed(e) == null) {
                hydride = false;
            };
            values[0] = .{ .p = if (hydride) -1 else 1 };
            last = 0;
        }
        if (f.a[7] > 0) {
            values[7] = .{ .p = -2 };
            last = 7;
        }
        if (f.a[7] == 0 and f.a[8] == 0) {
            for ([_]usize{ 16, 34, 52 }) |e| if (f.a[e] > 0) {
                values[e] = .{ .p = -1 };
                last = e;
                break;
            };
        }
        var undetermined: std.ArrayList(usize) = .empty;
        var sum: i128 = 0;
        for (els) |e| {
            if (values[e]) |v| sum += f.a[e] * v.p else try undetermined.append(A, e);
        }
        if (undetermined.items.len > 1) {
            try put("indeterminate:");
            for (undetermined.items) |e| try put(try fmt(" {s}", .{symbols[e]}));
            try put("\n");
            return;
        }
        if (undetermined.items.len == 1) {
            const e = undetermined.items[0];
            values[e] = Q.make(f.charge - sum, f.a[e]);
        } else if (sum != f.charge) {
            values[last] = Q.make(f.charge - sum + f.a[last] * values[last].?.p, f.a[last]);
        }
    }
    for (els, 0..) |e, i| {
        if (i > 0) try put(", ");
        try put(try fmt("{s} {s}", .{ symbols[e], try rational(values[e].?) }));
    }
    try put("\n");
}

var heats: std.StringHashMapUnmanaged(i128) = .empty;

fn findSpecies(e: Equation, s: S, lo: usize, hi: usize) ?usize {
    for (e.xs[lo..hi], lo..) |x, i| if (eq(x.name, s)) return i;
    return null;
}
const command_names = [_]S{ "ELEMENT", "PARSE", "MASS", "PERCENT", "EMPIRICAL", "DBE", "OXSTATE", "MOLES", "GRAMS", "MOLECULAR", "SALT", "DERIVE", "COMBUST", "BALANCE", "MATRIX", "CHECK", "REDOX", "HALF", "STOICH", "LIMITING", "YIELD", "HEAT", "DELTAH", "HEATS" };

fn command(w: []S) anyerror!void {
    const c = w[0];
    var id: ?usize = null;
    for (command_names, 0..) |s, i| if (eq(c, s)) {
        id = i;
        break;
    };
    const j = id orelse return fail("unknown command {s}", .{c});
    const a = w[1..];
    const good = switch (j) {
        0...6 => a.len == 1,
        7...10, 21 => a.len == 2,
        11 => a.len >= 2 and a.len % 2 == 0,
        12 => a.len == 3,
        13...15, 22 => a.len >= 1,
        16, 17 => a.len >= 2,
        23 => a.len == 0,
        else => true,
    };
    if (!good) return fail("wrong argument count for {s}", .{c});
    if (j == 0) {
        const e = try checkedElement(a[0]);
        try line(try fmt("{s} (Z = {d}) {s} u", .{ a[0], e + 1, try decimal(weights[e], 3) }));
        return;
    }
    if (j <= 10) {
        var f = try formula(a[0], a[0]);
        const els = try hillOrder(f.a);
        const mass = f.mass();
        if (j == 1) {
            var s: S = "";
            for (els, 0..) |e, i| s = try fmt("{s}{s}{s} {d}", .{ s, if (i == 0) @as(S, "") else ", ", symbols[e], f.a[e] });
            try line(try fmt("{s} ({s}; charge {s})", .{ try hill(f, true), s, try signed(f.charge) }));
        } else if (j == 2) try line(try fmt("M({s}) = {s} g/mol", .{ a[0], try decimal(mass, 3) })) else if (j == 3) {
            for (els) |e| try line(try fmt("{s} {s}%", .{ symbols[e], try decimal(@divTrunc(10000 * f.a[e] * weights[e], mass), 2) }));
        } else if (j == 4) {
            var g: i128 = 0;
            for (els) |e| g = gcd(g, f.a[e]);
            for (&f.a) |*v| v.* = @divTrunc(v.*, g);
            try line(try fmt("{s} (n = {d})", .{ try hill(f, false), g }));
        } else if (j == 5) {
            if (f.charge != 0) return fail("charged formula {s}", .{a[0]});
            var t: i128 = 2;
            for (els) |e| {
                const val: i128 = switch (e) {
                    0, 8, 16, 34, 52 => 1,
                    7, 15, 33 => 2,
                    4, 6, 14, 32 => 3,
                    5, 13, 31 => 4,
                    else => return fail("no valence for {s}", .{symbols[e]}),
                };
                t += f.a[e] * (val - 2);
            }
            try line(try fmt("DBE = {s}{d}.{c}", .{ if (t < 0) @as(S, "-") else "", @divTrunc(@as(i128, @intCast(@abs(t))), 2), if (@mod(t, 2) == 0) @as(u8, '0') else '5' }));
        } else if (j == 6) try oxidation(f) else if (j == 7 or j == 8) {
            const q = try scaled(a[1], false);
            if (j == 7) try line(try fmt("{s} g {s} = {s} mol", .{ try decimal(q, 3), a[0], try decimal(@divTrunc(q * 1000000, mass), 6) })) else try line(try fmt("{s} mol {s} = {s} g", .{ try decimal(q, 3), a[0], try decimal(@divTrunc(q * mass, 1000), 3) }));
        } else if (j == 9) {
            if (f.charge != 0) return fail("charged formula {s}", .{a[0]});
            const q = try scaled(a[1], false);
            const k = @divTrunc(2 * q + mass, 2 * mass);
            if (k == 0 or 10 * @as(i128, @intCast(@abs(q - k * mass))) > mass) try line(try fmt("no integer multiple (ratio {s})", .{try decimal(@divTrunc(1000 * q, mass), 3)})) else {
                for (&f.a) |*v| v.* *= k;
                try line(try fmt("{s} (n = {d}, {s} g/mol)", .{ try hill(f, false), k, try decimal(k * mass, 3) }));
            }
        } else {
            const g = try formula(a[1], a[1]);
            if (f.charge <= 0) return fail("not a cation {s}", .{a[0]});
            if (g.charge >= 0) return fail("not an anion {s}", .{a[1]});
            for (a) |s| if (std.mem.indexOfScalar(u8, s, '.') != null) return fail("hydrate ion {s}", .{s});
            const divisor = gcd(f.charge, g.charge);
            const p = @divTrunc(-g.charge, divisor);
            const q = @divTrunc(f.charge, divisor);
            for (&f.a, g.a) |*v, x| v.* = v.* * p + x * q;
            f.charge = 0;
            try line(try fmt("{s}{s} ({s}, {s} g/mol)", .{ try ionPart(a[0], p), try ionPart(a[1], q), try hill(f, false), try decimal(f.mass(), 3) }));
        }
        return;
    }
    if (j == 11) {
        var amounts: Composition = @as([54]i128, @splat(0));
        var total: i128 = 0;
        var i: usize = 0;
        while (i < a.len) : (i += 2) {
            const e = try checkedElement(a[i]);
            if (amounts[e] != 0) return fail("duplicate element {s}", .{a[i]});
            const q = try scaled(a[i + 1], false);
            if (q > 100000) return fail("invalid percentage {s}", .{a[i + 1]});
            amounts[e] = q;
            total += q;
        }
        if (@abs(total - 100000) > 1000) return fail("percentages sum to {s}", .{try decimal(total, 3)});
        try ratioReport(amounts);
        return;
    }
    if (j == 12) {
        const s = try scaled(a[0], false);
        const p = try scaled(a[1], false);
        const r = try scaled(a[2], false);
        var amounts: Composition = @as([54]i128, @splat(0));
        amounts[5] = @divTrunc(p * 12011, 44009);
        amounts[0] = @divTrunc(r * 2016, 18015);
        const oxygen = s - amounts[5] - amounts[0];
        if (amounts[5] == 0 or amounts[0] == 0 or 100 * oxygen < -s) return fail("inconsistent masses", .{});
        if (100 * oxygen > s) amounts[7] = oxygen;
        for ([_]usize{ 5, 0, 7 }) |e| if (amounts[e] > 0) try line(try fmt("mass {s} {s} g", .{ symbols[e], try decimal(amounts[e], 3) }));
        try ratioReport(amounts);
        return;
    }
    if (j == 21) {
        _ = try species(a[0], false);
        const h = try scaled(a[1], true);
        try put(try fmt("dHf({s}) = {s} kJ/mol", .{ a[0], try decimal(h, 2) }));
        if (heats.get(a[0])) |old| try put(try fmt(" (was {s})", .{try decimal(old, 2)}));
        try put("\n");
        try heats.put(A, a[0], h);
        return;
    }
    if (j == 23) {
        if (heats.count() == 0) {
            try line("no enthalpies");
            return;
        }
        var names: std.ArrayList(S) = .empty;
        var it = heats.keyIterator();
        while (it.next()) |s| try names.append(A, s.*);
        const C = struct {
            fn less(_: void, x: S, y: S) bool {
                return std.mem.order(u8, x, y) == .lt;
            }
        };
        std.mem.sort(S, names.items, {}, C.less);
        for (names.items) |s| try line(try fmt("{s} {s} kJ/mol", .{ s, try decimal(heats.get(s).?, 2) }));
        return;
    }
    var eqwords: []const S = a;
    var tail: []const S = &.{};
    var medium: S = "";
    if (j == 16 or j == 17) {
        medium = a[0];
        if (!eq(medium, "acidic") and !eq(medium, "basic")) return fail("invalid medium {s}", .{medium});
        eqwords = a[1..];
    }
    if (j >= 18 and j <= 20) {
        var separator: ?usize = null;
        for (a, 0..) |s, i| if (eq(s, ":")) {
            if (separator != null) return fail("invalid separator", .{});
            separator = i;
        };
        const sep = separator orelse return fail("invalid separator", .{});
        eqwords = a[0..sep];
        tail = a[sep + 1 ..];
        if ((j == 18 and tail.len != 2) or (j == 20 and tail.len != 4)) return fail("wrong argument count for {s}", .{c});
    }
    var e = try equation(eqwords, j == 15);
    const original = e.xs.len;
    var si: usize = 0;
    var sj: usize = 0;
    var q1: i128 = 0;
    var q2: i128 = 0;
    var quantities: []i128 = &.{};
    if (j == 18) {
        si = findSpecies(e, tail[0], 0, e.xs.len) orelse return fail("species {s} not in equation", .{tail[0]});
        q1 = try scaled(tail[1], false);
    } else if (j == 19) {
        if (tail.len != e.r) return fail("expected {d} masses, got {d}", .{ e.r, tail.len });
        quantities = try A.alloc(i128, tail.len);
        for (tail, 0..) |s, i| quantities[i] = try scaled(s, false);
    } else if (j == 20) {
        si = findSpecies(e, tail[0], 0, e.r) orelse return fail("{s} is not a reactant", .{tail[0]});
        sj = findSpecies(e, tail[2], e.r, e.xs.len) orelse return fail("{s} is not a product", .{tail[2]});
        q1 = try scaled(tail[1], false);
        q2 = try scaled(tail[3], false);
    } else if (j == 22) {
        for (e.xs) |s| if (!heats.contains(s.name)) return fail("no enthalpy for {s}", .{s.name});
    }
    if (j == 14 or j == 15) {
        const m = try matrix(e);
        if (j == 14) {
            try put("columns:");
            for (e.xs) |s| try put(try fmt(" {s}", .{s.name}));
            try put("\n");
            for (m.rows, 0..) |row, i| {
                try put(try fmt("{s}:", .{if (i == m.elements.len) @as(S, "charge") else symbols[m.elements[i]]}));
                for (row) |v| try put(try fmt(" {d}", .{v}));
                try put("\n");
            }
            try line(try fmt("rank {d}, nullity {d}", .{ m.rank, m.basis.len }));
            for (m.basis) |row| {
                try put("null:");
                for (row) |v| try put(try fmt(" {d}", .{v}));
                try put("\n");
            }
        } else {
            var mismatch = false;
            for (m.rows) |row| {
                var total: i128 = 0;
                for (row, e.xs) |v, s| total += v * s.c;
                if (total != 0) mismatch = true;
            }
            if (!mismatch) {
                var g: i128 = 0;
                for (e.xs) |s| g = gcd(g, s.c);
                try line(if (g == 1) "balanced" else try fmt("balanced, not in lowest terms (gcd {d})", .{g}));
            } else {
                try line("not balanced");
                for (m.rows, 0..) |row, i| {
                    var left: i128 = 0;
                    var right: i128 = 0;
                    for (row, e.xs, 0..) |v, s, k| if (k < e.r) {
                        left += v * s.c;
                    } else {
                        right -= v * s.c;
                    };
                    if (left != right) try line(try fmt("{s}: {s} != {s}", .{ if (i == m.elements.len) @as(S, "charge") else symbols[m.elements[i]], if (i == m.elements.len) try signed(left) else try fmt("{d}", .{left}), if (i == m.elements.len) try signed(right) else try fmt("{d}", .{right}) }));
                }
            }
        }
        return;
    }
    if (j == 16 or j == 17) {
        for (e.xs) |s| if (eq(s.core, "H^+") or eq(s.core, "OH^-") or eq(s.core, "H2O")) return fail("reserved species {s}", .{s.name});
        const extra: usize = if (j == 17) 3 else 2;
        const xs = try A.alloc(Species, original + extra);
        @memcpy(xs[0..original], e.xs);
        xs[original] = try species(if (eq(medium, "acidic")) "H^+" else "OH^-", false);
        xs[original + 1] = try species("H2O", false);
        if (j == 17) xs[original + 2] = .{ .name = "e^-", .core = "e^-", .f = .{ .charge = -1 } };
        e.xs = xs;
    }
    var b: Balance = undefined;
    if (j == 16 or j == 17) {
        b = try balanceAux(e, original);
    } else b = try balance(e, original);
    if (b.message) |message| {
        try line(message);
        return;
    }
    const coeff = b.c;
    try line(try notation(e, coeff, original));
    if (j == 17) {
        const electron = coeff[coeff.len - 1];
        try line(if (electron > 0) "reduction" else if (electron < 0) "oxidation" else "no electron transfer");
    } else if (j == 18) {
        const d = coeff[si] * e.xs[si].f.mass();
        for (e.xs, coeff) |s, k| {
            try put(try fmt("{s} {s} mol {s} g", .{ s.name, try decimal(@divTrunc(q1 * k * 1000000, d), 6), try decimal(@divTrunc(q1 * k * s.f.mass(), d), 3) }));
            if (eq(s.state, "(g)")) try put(try fmt(" {s} L", .{try decimal(@divTrunc(q1 * k * 22414, d), 3)}));
            try put("\n");
        }
    } else if (j == 19) {
        var limit: usize = 0;
        for (0..e.r) |i| if (quantities[i] * coeff[limit] * e.xs[limit].f.mass() < quantities[limit] * coeff[i] * e.xs[i].f.mass()) {
            limit = i;
        };
        const d = coeff[limit] * e.xs[limit].f.mass();
        const q = quantities[limit];
        try line(try fmt("limiting {s}", .{e.xs[limit].name}));
        try line(try fmt("extent {s} mol", .{try decimal(@divTrunc(q * 1000000, d), 6)}));
        for (e.r..original) |i| {
            const s = e.xs[i];
            try put(try fmt("product {s} {s} g", .{ s.name, try decimal(@divTrunc(q * coeff[i] * s.f.mass(), d), 3) }));
            if (eq(s.state, "(g)")) try put(try fmt(" {s} L", .{try decimal(@divTrunc(q * coeff[i] * 22414, d), 3)}));
            try put("\n");
        }
        for (0..e.r) |i| if (i != limit) try line(try fmt("remaining {s} {s} g", .{ e.xs[i].name, try decimal(@divTrunc(quantities[i] * d - q * coeff[i] * e.xs[i].f.mass(), d), 3) }));
    } else if (j == 20) {
        const t = @divTrunc(q1 * coeff[sj] * e.xs[sj].f.mass(), coeff[si] * e.xs[si].f.mass());
        try line(try fmt("theoretical {s} g", .{try decimal(t, 3)}));
        try line(try fmt("actual {s} g", .{try decimal(q2, 3)}));
        try line(if (t == 0) "yield undefined" else try fmt("yield {s}%", .{try decimal(@divTrunc(q2 * 10000, t), 2)}));
    } else if (j == 22) {
        var delta: i128 = 0;
        for (e.xs, coeff, 0..) |s, k, i| delta += (if (i < e.r) @as(i128, -1) else 1) * k * heats.get(s.name).?;
        try line(try fmt("dH = {s} kJ ({s})", .{ try decimal(delta, 2), if (delta < 0) @as(S, "exothermic") else if (delta > 0) "endothermic" else "thermoneutral" }));
    }
}

fn balanceAux(e: Equation, k: usize) !Balance {
    var modified = e;
    modified.aux_start = k;
    return balance(modified, k);
}

pub fn main(init: std.process.Init) !void {
    var ib: [8192]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    const all = try input.interface.allocRemaining(A, .unlimited);
    var lines = std.mem.splitScalar(u8, all, '\n');
    const n = try std.fmt.parseInt(usize, lines.next() orelse "0", 10);
    for (0..n) |_| {
        const s = std.mem.trimEnd(u8, lines.next() orelse "", "\r");
        var ws: std.ArrayList(S) = .empty;
        var it = std.mem.tokenizeScalar(u8, s, ' ');
        while (it.next()) |w| try ws.append(A, w);
        command(ws.items) catch |e| {
            if (e != error.Invalid) return e;
            try line(try fmt("error: {s}", .{why}));
        };
    }
    var ob: [8192]u8 = undefined;
    var sink = std.Io.File.stdout().writerStreaming(init.io, &ob);
    try sink.interface.writeAll(output.items);
    try sink.interface.flush();
}
