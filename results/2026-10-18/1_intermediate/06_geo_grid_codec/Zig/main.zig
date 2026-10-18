const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{Invalid} || Allocator.Error || std.Io.Writer.Error;
const system_names = [_][]const u8{ "GEOHASH", "MAIDENHEAD", "PLUSCODE", "GARS", "GEOREF", "MESH" };
const sequences = [_][]const i64{ &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &.{ 2, 4, 6, 8 }, &.{ 2, 4, 6, 8, 10, 11 },
    &.{ 5, 6, 7 }, &.{ 2, 4, 8, 10, 12 }, &.{ 4, 6, 8, 9, 10, 11 } };
const geohash = "0123456789bcdefghjkmnpqrstuvwxyz";
const plus_digits = "23456789CFGHJMPQRVWX";
const l24 = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const g25 = "ABCDEFGHJKLMNOPQRSTUVWXYZ";
const bands = "CDEFGHJKLMNPQRSTUVWX";
const mgrs_rows = "ABCDEFGHJKLMNPQRSTUV";
const columns = [_][]const u8{ "STUVWXYZ", "ABCDEFGH", "JKLMNPQR" };
const maiden_sets = [_][]const u8{ "ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789" };
fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn split(gpa: Allocator, text: []const u8, delimiter: u8) Allocator.Error![][]const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, delimiter);
    while (it.next()) |part| try result.append(gpa, part);
    return result.items;
}
fn digits(text: []const u8) error{Invalid}!i64 {
    if (text.len == 0) return error.Invalid;
    var n: i64 = 0;
    for (text) |c| { if (c < '0' or c > '9') return error.Invalid; n = n * 10 + c - '0'; }
    return n;
}
fn number(text: []const u8, minimum: i64, maximum: i64) error{Invalid}!i64 {
    const negative = text.len > 0 and text[0] == '-';
    const body = if (negative) text[1..] else text;
    if (body.len == 0 or body.len > 9) return error.Invalid;
    const magnitude = try digits(body);
    const n = if (negative) -magnitude else magnitude;
    if (n < minimum or n > maximum) return error.Invalid;
    return n;
}
fn coordinate(text: []const u8, latitude: bool) error{Invalid}!i64 {
    const negative = text.len > 0 and text[0] == '-';
    const body = if (negative) text[1..] else text;
    const dot = std.mem.findScalar(u8, body, '.');
    const whole = if (dot) |i| body[0..i] else body;
    if (whole.len == 0 or whole.len > 3) return error.Invalid;
    var n = try digits(whole) * 1000000;
    if (dot) |i| {
        const fraction = body[i + 1..];
        if (fraction.len == 0 or fraction.len > 6) return error.Invalid;
        n += try digits(fraction) * power(10, 6 - fraction.len);
    }
    if (negative) n = -n;
    if (if (latitude) n < -90000000 or n > 90000000 else n < -180000000 or n >= 180000000) return error.Invalid;
    return n;
}
fn power(base: i64, exponent: usize) i64 { var n: i64 = 1; for (0..exponent) |_| n *= base; return n; }
fn absolute(n: i64) i64 { return if (n < 0) -n else n; }
fn rounded(a: i64, b: i64) i64 { return @divFloor(2 * a + b, 2 * b); }
fn index(set: []const u8, ch: u8) error{Invalid}!i64 { return @intCast(std.mem.findScalar(u8, set, ch) orelse return error.Invalid); }
fn system(text: []const u8) error{Invalid}!usize {
    for (system_names, 0..) |name, i| { if (equal(text, name)) return i; }
    return error.Invalid;
}
fn position(s: usize, p: i64) ?usize {
    for (sequences[s], 0..) |q, i| { if (q == p) return i; }
    return null;
}
fn precision(s: usize, text: []const u8) error{Invalid}!i64 {
    const p = try number(text, 1, 12);
    if (position(s, p) == null) return error.Invalid;
    return p;
}
fn meshScale(p: i64) i64 { return ([_]i64{ 1, 8, 80, 160, 320, 640 })[position(5, p).?]; }
const Grid = struct { w: i64, h: i64 };
fn grid(s: usize, p: i64) Grid {
    const i = position(s, p).?;
    return switch (s) {
        0 => .{ .w = @as(i64, 1) << @intCast(@divFloor(5 * p + 1, 2)), .h = @as(i64, 1) << @intCast(@divFloor(5 * p, 2)) },
        1 => .{ .w = ([_]i64{ 18, 180, 4320, 43200 })[i], .h = ([_]i64{ 18, 180, 4320, 43200 })[i] },
        2 => .{ .w = ([_]i64{ 18, 360, 7200, 144000, 2880000, 11520000 })[i], .h = ([_]i64{ 9, 180, 3600, 72000, 1440000, 7200000 })[i] },
        3 => .{ .w = ([_]i64{ 720, 1440, 4320 })[i], .h = ([_]i64{ 360, 720, 2160 })[i] },
        4 => .{ .w = ([_]i64{ 24, 360, 21600, 216000, 2160000 })[i], .h = ([_]i64{ 12, 180, 10800, 108000, 1080000 })[i] },
        else => .{ .w = 360 * meshScale(p), .h = 270 * meshScale(p) },
    };
}
fn fixedDigits(gpa: Allocator, n: i64, width: usize) Allocator.Error![]const u8 {
    const text = try std.fmt.allocPrint(gpa, "{d}", .{n});
    const result = try gpa.alloc(u8, @max(width, text.len));
    @memset(result, '0');
    @memcpy(result[result.len - text.len..], text);
    return result;
}
fn coordText(gpa: Allocator, n: i64) Allocator.Error![]const u8 {
    const magnitude = absolute(n);
    return std.fmt.allocPrint(gpa, "{s}{d}.{s}", .{ @as([]const u8, if (n < 0) "-" else ""), @divFloor(magnitude, 1000000),
        try fixedDigits(gpa, @mod(magnitude, 1000000), 6) });
}
fn radixDigits(value: i64, radices: []const i64, output: *[6]i64) void {
    var n = value;
    var i = radices.len;
    while (i > 0) { i -= 1; output[i] = @mod(n, radices[i]); n = @divFloor(n, radices[i]); }
}
const Cell = struct {
    s: usize, p: i64, x: i64, y: i64, w: i64, h: i64,
    fn init(s: usize, p: i64, x: i64, y: i64) Cell { const g = grid(s, p); return .{ .s = s, .p = p, .x = x, .y = y, .w = g.w, .h = g.h }; }
    fn ancestor(self: Cell, q: i64) Cell { const g = grid(self.s, q); return .init(self.s, q, @divFloor(self.x * g.w, self.w), @divFloor(self.y * g.h, self.h)); }
    fn same(self: Cell, other: Cell) bool { return self.p == other.p and self.x == other.x and self.y == other.y; }
};
fn containing(s: usize, p: i64, lat: i64, lon: i64) Cell {
    const g = grid(s, p);
    return .init(s, p, @divFloor((lon + 180000000) * g.w, 360000000), @min(@divFloor((lat + 90000000) * g.h, 180000000), g.h - 1));
}
fn encode(gpa: Allocator, cell: Cell) Error!?[]const u8 {
    var x = cell.x; var y = cell.y; const p = cell.p;
    var buffer: std.Io.Writer.Allocating = .init(gpa);
    const out = &buffer.writer;
    switch (cell.s) {
        0 => {
            var xb = @divFloor(5 * p + 1, 2); var yb = @divFloor(5 * p, 2); var value: i64 = 0;
            for (0..@as(usize, @intCast(5 * p))) |i| {
                var bit: i64 = undefined;
                if (i % 2 == 0) { xb -= 1; bit = (x >> @intCast(xb)) & 1; } else { yb -= 1; bit = (y >> @intCast(yb)) & 1; }
                value = 2 * value + bit;
                if (i % 5 == 4) { try out.writeByte(geohash[@intCast(value)]); value = 0; }
            }
        },
        1 => {
            const count: usize = @intCast(@divFloor(p, 2)); const radices = [_]i64{ 18, 10, 24, 10 };
            var xs: [6]i64 = undefined; var ys: [6]i64 = undefined;
            radixDigits(x, radices[0..count], &xs); radixDigits(y, radices[0..count], &ys);
            for (0..count) |i| { try out.writeByte(maiden_sets[i][@intCast(xs[i])]); try out.writeByte(maiden_sets[i][@intCast(ys[i])]); }
        },
        2 => {
            const last = if (p == 11) 4 * @mod(y, 5) + @mod(x, 4) else -1;
            if (p == 11) { x = @divFloor(x, 4); y = @divFloor(y, 5); }
            const count: usize = @intCast(@divFloor(if (p == 11) 10 else p, 2));
            var xs: [6]i64 = undefined; var ys: [6]i64 = undefined;
            const rx = [_]i64{ 18, 20, 20, 20, 20 }; const ry = [_]i64{ 9, 20, 20, 20, 20 };
            radixDigits(x, rx[0..count], &xs); radixDigits(y, ry[0..count], &ys);
            var text: [11]u8 = undefined; var len: usize = 0;
            for (0..count) |i| { text[len] = plus_digits[@intCast(ys[i])]; text[len + 1] = plus_digits[@intCast(xs[i])]; len += 2; }
            if (last >= 0) { text[len] = plus_digits[@intCast(last)]; len += 1; }
            if (p < 8) { try out.writeAll(text[0..len]); for (len..8) |_| try out.writeByte('0'); try out.writeByte('+'); } else {
                try out.writeAll(text[0..8]); try out.writeByte('+'); try out.writeAll(text[8..len]);
            }
        },
        3 => {
            const area = if (p == 7) 1 + @mod(x, 3) + 3 * (2 - @mod(y, 3)) else 0;
            if (p == 7) { x = @divFloor(x, 3); y = @divFloor(y, 3); }
            const quadrant = if (p >= 6) 1 + @mod(x, 2) + 2 * (1 - @mod(y, 2)) else 0;
            if (p >= 6) { x = @divFloor(x, 2); y = @divFloor(y, 2); }
            try out.writeAll(try fixedDigits(gpa, x + 1, 3));
            try out.writeByte(l24[@intCast(@divFloor(y, 24))]); try out.writeByte(l24[@intCast(@mod(y, 24))]);
            if (p >= 6) try out.print("{d}", .{quadrant}); if (p == 7) try out.print("{d}", .{area});
        },
        4 => {
            const m: usize = if (p >= 8) @intCast(@divFloor(p - 4, 2)) else 0;
            const scale: i64 = if (p >= 8) 6 * power(10, m - 1) else 1;
            const east = @mod(x, scale); const north = @mod(y, scale);
            if (p >= 8) { x = @divFloor(x, scale); y = @divFloor(y, scale); }
            const a = if (p >= 4) @divFloor(x, 15) else x; const b = if (p >= 4) @divFloor(y, 15) else y;
            try out.writeByte(l24[@intCast(a)]); try out.writeByte(l24[@intCast(b)]);
            if (p >= 4) { try out.writeByte(l24[@intCast(@mod(x, 15))]); try out.writeByte(l24[@intCast(@mod(y, 15))]); }
            if (p >= 8) { try out.writeAll(try fixedDigits(gpa, east, m)); try out.writeAll(try fixedDigits(gpa, north, m)); }
        },
        5 => {
            const scale = meshScale(p); const u = x - 280 * scale; const v = y - 135 * scale;
            if (u < 0 or u >= 80 * scale or v < 0 or v >= 100 * scale) return null;
            const count = position(5, p).? + 1; const rx = [_]i64{ 80, 8, 10, 2, 2, 2 }; const ry = [_]i64{ 100, 8, 10, 2, 2, 2 };
            var us: [6]i64 = undefined; var vs: [6]i64 = undefined;
            radixDigits(u, rx[0..count], &us); radixDigits(v, ry[0..count], &vs);
            try out.writeAll(try fixedDigits(gpa, vs[0], 2)); try out.writeAll(try fixedDigits(gpa, us[0], 2));
            for (1..count) |i| {
                if (i <= 2) try out.print("{d}{d}", .{ vs[i], us[i] }) else try out.print("{d}", .{1 + us[i] + 2 * vs[i]});
            }
        },
        else => unreachable,
    }
    return out.buffered();
}
fn decode(s: usize, code: []const u8) Error!Cell {
    var p: i64 = @intCast(code.len);
    if (s != 2 and position(s, p) == null) return error.Invalid;
    var x: i64 = 0; var y: i64 = 0;
    switch (s) {
        0 => {
            var bit_index: usize = 0;
            for (code) |ch| {
                const value = try index(geohash, ch);
                var b: usize = 5;
                while (b > 0) { b -= 1; const bit = (value >> @intCast(b)) & 1;
                    if (bit_index % 2 == 0) x = 2 * x + bit else y = 2 * y + bit; bit_index += 1; }
            }
        },
        1 => {
            const radices = [_]i64{ 18, 10, 24, 10 };
            for (0..code.len / 2) |i| { x = x * radices[i] + try index(maiden_sets[i], code[2 * i]); y = y * radices[i] + try index(maiden_sets[i], code[2 * i + 1]); }
        },
        2 => {
            if (code.len < 9 or code[8] != '+') return error.Invalid;
            var plus_count: usize = 0; for (code) |ch| { if (ch == '+') plus_count += 1; }
            if (plus_count != 1) return error.Invalid;
            const before = std.mem.findScalar(u8, code[0..8], '0') orelse 8;
            if (before != 2 and before != 4 and before != 6 and before != 8) return error.Invalid;
            if (before < 8) {
                if (code.len != 9) return error.Invalid;
                for (code[before..8]) |ch| { if (ch != '0') return error.Invalid; }
            } else if (code.len - 9 != 0 and code.len - 9 != 2 and code.len - 9 != 3) return error.Invalid;
            var values: [11]i64 = undefined; var len: usize = 0;
            for (code[0..before]) |ch| { values[len] = try index(plus_digits, ch); len += 1; }
            for (code[9..]) |ch| { values[len] = try index(plus_digits, ch); len += 1; }
            if (values[0] > 8 or values[1] > 17) return error.Invalid;
            p = @intCast(len); const pairs = (if (len == 11) @as(usize, 10) else len) / 2;
            for (0..pairs) |i| { y = y * @as(i64, if (i == 0) 9 else 20) + values[2 * i]; x = x * @as(i64, if (i == 0) 18 else 20) + values[2 * i + 1]; }
            if (len == 11) { x = 4 * x + @mod(values[len - 1], 4); y = 5 * y + @divFloor(values[len - 1], 4); }
        },
        3 => {
            const band = try digits(code[0..3]); if (band < 1 or band > 720) return error.Invalid;
            const a = try index(l24, code[3]); const b = try index(l24, code[4]); if (a >= 15) return error.Invalid;
            x = band - 1; y = 24 * a + b;
            if (p >= 6) { const q = try index("1234", code[5]); x = 2 * x + @mod(q, 2); y = 2 * y + 1 - @divFloor(q, 2); }
            if (p == 7) { const q = try index("123456789", code[6]); x = 3 * x + @mod(q, 3); y = 3 * y + 2 - @divFloor(q, 3); }
        },
        4 => {
            x = try index(l24, code[0]); y = try index(l24, code[1]); if (y >= 12) return error.Invalid;
            if (p >= 4) { const a = try index(l24, code[2]); const b = try index(l24, code[3]); if (a >= 15 or b >= 15) return error.Invalid; x = 15 * x + a; y = 15 * y + b; }
            if (p >= 8) {
                const m: usize = @intCast(@divFloor(p - 4, 2)); const scale = 6 * power(10, m - 1);
                const a = try digits(code[4..4 + m]); const b = try digits(code[4 + m..]); if (a >= scale or b >= scale) return error.Invalid;
                x = x * scale + a; y = y * scale + b;
            }
        },
        5 => {
            _ = try digits(code);
            y = try digits(code[0..2]); x = try digits(code[2..4]); if (x > 79) return error.Invalid;
            if (p >= 6) { const a = try digits(code[4..5]); const b = try digits(code[5..6]); if (a > 7 or b > 7) return error.Invalid; y = 8 * y + a; x = 8 * x + b; }
            if (p >= 8) { y = 10 * y + try digits(code[6..7]); x = 10 * x + try digits(code[7..8]); }
            if (p >= 9) for (code[8..]) |ch| { const q = try index("1234", ch); x = 2 * x + @mod(q, 2); y = 2 * y + @divFloor(q, 2); };
            x += 280 * meshScale(p); y += 135 * meshScale(p);
        },
        else => unreachable,
    }
    return .init(s, p, x, y);
}
fn arity(a: []const []const u8, n: usize) error{Invalid}!void { if (a.len != n + 1) return error.Invalid; }
fn readCell(a: []const []const u8, si: usize, ci: usize) Error!Cell { return decode(try system(a[si]), a[ci]); }
fn writeCode(gpa: Allocator, out: *std.Io.Writer, c: Cell, missing: []const u8) Error!void { try out.writeAll((try encode(gpa, c)) orelse missing); }
fn findCell(cells: []const Cell, target: Cell) ?usize { for (cells, 0..) |c, i| { if (c.same(target)) return i; } return null; }
fn execute(gpa: Allocator, line: []const u8, out: *std.Io.Writer) Error!void {
    const a = try split(gpa, line, ' '); const op = a[0];
    if (equal(op, "ENCODE")) {
        try arity(a, 4); const s = try system(a[1]); const lat = try coordinate(a[2], true); const lon = try coordinate(a[3], false); const p = try precision(s, a[4]);
        try writeCode(gpa, out, containing(s, p, lat, lon), "OUT OF AREA");
    } else if (equal(op, "SIZE")) {
        try arity(a, 2); const s = try system(a[1]); const p = try precision(s, a[2]); const g = grid(s, p);
        try out.print("w={s} h={s} cells={d}", .{ try coordText(gpa, @divFloor(360000000, g.w)), try coordText(gpa, @divFloor(180000000, g.h)),
            if (s == 5) 8000 * meshScale(p) * meshScale(p) else g.w * g.h });
    } else if (equal(op, "DECODE") or equal(op, "NEIGHBORS") or equal(op, "PARENT") or equal(op, "CHILDREN")) {
        try arity(a, 2); const c = try readCell(a, 1, 2); const sequence = sequences[c.s]; const pos = position(c.s, c.p).?;
        if (equal(op, "DECODE")) {
            try out.print("sw={s},{s} ne={s},{s} c={s},{s}", .{
                try coordText(gpa, -90000000 + @divFloor(180000000 * c.y, c.h)), try coordText(gpa, -180000000 + @divFloor(360000000 * c.x, c.w)),
                try coordText(gpa, -90000000 + @divFloor(180000000 * (c.y + 1), c.h)), try coordText(gpa, -180000000 + @divFloor(360000000 * (c.x + 1), c.w)),
                try coordText(gpa, -90000000 + @divFloor(180000000 * (2 * c.y + 1), 2 * c.h)), try coordText(gpa, -180000000 + @divFloor(360000000 * (2 * c.x + 1), 2 * c.w)),
            });
        } else if (equal(op, "NEIGHBORS")) {
            const offsets = [_][2]i64{ .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 }, .{ 1, -1 }, .{ 0, -1 }, .{ -1, -1 }, .{ -1, 0 }, .{ -1, 1 } };
            for (offsets, 0..) |d, i| {
                if (i > 0) try out.writeByte(' ');
                if (c.y + d[1] < 0 or c.y + d[1] >= c.h) try out.writeByte('-') else
                    try writeCode(gpa, out, .init(c.s, c.p, @mod(c.x + d[0], c.w), c.y + d[1]), "-");
            }
        } else if (equal(op, "PARENT")) {
            if (pos == 0) try out.writeAll("NONE") else try writeCode(gpa, out, c.ancestor(sequence[pos - 1]), "-");
        } else if (pos + 1 == sequence.len) try out.writeAll("NONE") else {
            const q = sequence[pos + 1]; const g = grid(c.s, q); const rx = @divFloor(g.w, c.w); const ry = @divFloor(g.h, c.h);
            if (rx * ry > 100) { try out.writeAll("TOO MANY"); return; }
            var j = ry; var first = true;
            while (j > 0) { j -= 1; var i: i64 = 0; while (i < rx) : (i += 1) {
                if (!first) try out.writeByte(' '); first = false;
                try writeCode(gpa, out, .init(c.s, q, rx * c.x + i, ry * c.y + j), "-");
            } }
        }
    } else if (equal(op, "COMMON") or equal(op, "STEPS") or equal(op, "PATH")) {
        try arity(a, 3); const c = try readCell(a, 1, 2); const d = try decode(c.s, a[3]);
        if (equal(op, "COMMON")) {
            var pos = @min(position(c.s, c.p).?, position(c.s, d.p).?) + 1;
            while (pos > 0) { pos -= 1; const x = c.ancestor(sequences[c.s][pos]); const y = d.ancestor(sequences[c.s][pos]); if (x.same(y)) { try writeCode(gpa, out, x, "-"); return; } }
            try out.writeAll("NONE"); return;
        }
        if (c.p != d.p) { try out.writeAll("MISMATCH"); return; }
        var dx = @mod(d.x - c.x, c.w); if (2 * dx > c.w) dx -= c.w;
        const dy = d.y - c.y;
        if (equal(op, "STEPS")) { try out.print("dx={d} dy={d}", .{ dx, dy }); return; }
        const n = @max(absolute(dx), absolute(dy)); if (n + 1 > 100) { try out.writeAll("TOO MANY"); return; }
        var i: i64 = 0; while (i <= n) : (i += 1) {
            if (i > 0) try out.writeByte(' ');
            try writeCode(gpa, out, .init(c.s, c.p, @mod(c.x + (if (n == 0) 0 else rounded(i * dx, n)), c.w), c.y + (if (n == 0) 0 else rounded(i * dy, n))), "-");
        }
    } else if (equal(op, "COMPACT")) {
        if (a.len < 3 or a.len > 102) return error.Invalid;
        const s = try system(a[1]); var cells: std.ArrayList(Cell) = .empty;
        for (a[2..]) |code| { const c = try decode(s, code); if (findCell(cells.items, c) == null) try cells.append(gpa, c); }
        var i: usize = 0;
        while (i < cells.items.len) {
            const c = cells.items[i]; var contained = false;
            for (sequences[s]) |q| { if (q < c.p and findCell(cells.items, c.ancestor(q)) != null) { contained = true; break; } }
            if (contained) _ = cells.orderedRemove(i) else i += 1;
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (cells.items) |c| {
                const pos = position(s, c.p).?; if (pos == 0) continue;
                const parent = c.ancestor(sequences[s][pos - 1]); const rx = @divFloor(c.w, parent.w); const ry = @divFloor(c.h, parent.h);
                if (rx * ry > @as(i64, @intCast(cells.items.len))) continue;
                var children: std.ArrayList(Cell) = .empty; var complete = true;
                var j: i64 = 0; while (j < ry) : (j += 1) {
                    var x: i64 = 0; while (x < rx) : (x += 1) {
                        const child = Cell.init(s, c.p, parent.x * rx + x, parent.y * ry + j);
                        if (findCell(cells.items, child) == null) complete = false;
                        try children.append(gpa, child);
                    }
                }
                if (complete) {
                    for (children.items) |child| _ = cells.orderedRemove(findCell(cells.items, child).?);
                    try cells.append(gpa, parent); changed = true; break;
                }
            }
        }
        for (1..@max(1, cells.items.len)) |j| {
            const entry = cells.items[j]; var x = j;
            while (x > 0) {
                const b = cells.items[x - 1];
                if (!(entry.p < b.p or (entry.p == b.p and (entry.y > b.y or (entry.y == b.y and entry.x < b.x))))) break;
                cells.items[x] = b; x -= 1;
            }
            cells.items[x] = entry;
        }
        for (cells.items, 0..) |c, j| { if (j > 0) try out.writeByte(' '); try writeCode(gpa, out, c, "-"); }
    } else if (equal(op, "CONTAINS")) {
        try arity(a, 4); const c = try readCell(a, 1, 2); const d = containing(c.s, c.p, try coordinate(a[3], true), try coordinate(a[4], false));
        try out.writeAll(if (c.same(d)) "YES" else "NO");
    } else if (equal(op, "COVER")) {
        try arity(a, 6); const s = try system(a[1]); const p = try precision(s, a[2]);
        const lat1 = try coordinate(a[3], true); const lon1 = try coordinate(a[4], false); const lat2 = try coordinate(a[5], true); const lon2 = try coordinate(a[6], false);
        if (lat1 > lat2) return error.Invalid;
        const c = containing(s, p, lat1, lon1); const d = containing(s, p, lat2, lon2);
        const width = if (lon1 <= lon2) d.x - c.x + 1 else @min(c.w, d.x - c.x + 1 + c.w);
        if (width * (d.y - c.y + 1) > 100) { try out.writeAll("TOO MANY"); return; }
        var y = d.y; var first = true;
        while (y >= c.y) : (y -= 1) { var i: i64 = 0; while (i < width) : (i += 1) {
            if (!first) try out.writeByte(' '); first = false; try writeCode(gpa, out, .init(s, p, @mod(c.x + i, c.w), y), "-");
        } }
    } else if (equal(op, "CONVERT")) {
        try arity(a, 5); const c = try readCell(a, 1, 2); if (!equal(a[3], "TO")) return error.Invalid;
        const s = try system(a[4]); const p = try precision(s, a[5]); const g = grid(s, p);
        try writeCode(gpa, out, .init(s, p, @divFloor((2 * c.x + 1) * g.w, 2 * c.w), @divFloor((2 * c.y + 1) * g.h, 2 * c.h)), "OUT OF AREA");
    } else if (equal(op, "RELATE")) {
        try arity(a, 4); const c = try readCell(a, 1, 2); const d = try readCell(a, 3, 4);
        const x1 = c.x * d.w; const x2 = (c.x + 1) * d.w; const x3 = d.x * c.w; const x4 = (d.x + 1) * c.w;
        const y1 = c.y * d.h; const y2 = (c.y + 1) * d.h; const y3 = d.y * c.h; const y4 = (d.y + 1) * c.h;
        const relation: []const u8 = if (x1 == x3 and x2 == x4 and y1 == y3 and y2 == y4) "EQUAL" else
            if (x1 >= x3 and x2 <= x4 and y1 >= y3 and y2 <= y4) "INSIDE" else
            if (x3 >= x1 and x4 <= x2 and y3 >= y1 and y4 <= y2) "CONTAINS" else
            if (x1 < x4 and x3 < x2 and y1 < y4 and y3 < y2) "OVERLAP" else
            if (y1 <= y4 and y3 <= y2 and ((x1 <= x4 and x3 <= x2) or (c.x + 1 == c.w and d.x == 0) or (d.x + 1 == d.w and c.x == 0))) "TOUCH" else "DISJOINT";
        try out.writeAll(relation);
    } else if (equal(op, "SHORTEN") or equal(op, "RECOVER")) {
        try arity(a, 3); const lat = try coordinate(a[2], true); const lon = try coordinate(a[3], false);
        if (equal(op, "SHORTEN")) {
            const c = try decode(2, a[1]); if (c.p < 8) return error.Invalid;
            const dy = absolute(180000000 * (2 * c.y + 1) - (lat + 90000000) * 2 * c.h);
            const dx = absolute(360000000 * (2 * c.x + 1) - (lon + 180000000) * 2 * c.w);
            try out.writeAll(if (dy < 15000 * 2 * c.h and dx < 15000 * 2 * c.w) a[1][6..] else
                if (dy < 300000 * 2 * c.h and dx < 300000 * 2 * c.w) a[1][4..] else a[1]);
        } else {
            const short = a[1]; const at = std.mem.findScalar(u8, short, '+') orelse return error.Invalid;
            if ((at != 2 and at != 4) or (short.len - at - 1 != 0 and short.len - at - 1 != 2 and short.len - at - 1 != 3)) return error.Invalid;
            for (short, 0..) |ch, i| { if (i != at) _ = try index(plus_digits, ch); }
            const removed = 8 - at; const prefix = (try encode(gpa, containing(2, 10, lat, lon))).?;
            const c = try decode(2, try std.fmt.allocPrint(gpa, "{s}{s}", .{ prefix[0..removed], short }));
            var x = c.x; var y = c.y; const distance: i64 = if (removed == 4) 1000000 else 50000;
            const my = @divFloor(distance * c.h, 180000000); const mx = @divFloor(distance * c.w, 360000000);
            const cy = 180000000 * (2 * y + 1); const cx = 360000000 * (2 * x + 1);
            if ((lat + 90000000 + @divFloor(distance, 2)) * 2 * c.h < cy and cy - distance * 2 * c.h >= 0) y -= my else
                if ((lat + 90000000 - @divFloor(distance, 2)) * 2 * c.h > cy and cy + distance * 2 * c.h <= 180000000 * 2 * c.h) y += my;
            if ((lon + 180000000 + @divFloor(distance, 2)) * 2 * c.w < cx) x = @mod(x - mx, c.w) else
                if ((lon + 180000000 - @divFloor(distance, 2)) * 2 * c.w > cx) x = @mod(x + mx, c.w);
            try writeCode(gpa, out, .init(2, c.p, x, y), "-");
        }
    } else if (equal(op, "UTMZONE")) {
        try arity(a, 2); const lat = try coordinate(a[1], true); const lon = try coordinate(a[2], false);
        if (lat < -80000000 or lat >= 84000000) { try out.writeAll("NONE"); return; }
        const band = bands[@intCast(@min(@divFloor(lat + 80000000, 8000000), 19))];
        var zone = @divFloor(lon + 180000000, 6000000) + 1;
        if (band == 'V' and lon >= 3000000 and lon < 12000000) zone = 32;
        if (band == 'X' and lon >= 0 and lon < 42000000) zone = if (lon < 9000000) 31 else if (lon < 21000000) 33 else if (lon < 33000000) 35 else 37;
        try out.print("{d}{c}", .{ zone, band });
    } else if (equal(op, "OSGB") or equal(op, "MGRS")) {
        const mgrs = equal(op, "MGRS"); try arity(a, if (mgrs) 5 else 3);
        const zone = if (mgrs) try number(a[1], 1, 60) else 0;
        if (mgrs) { if (a[2].len != 1) return error.Invalid; _ = try index(bands, a[2][0]); }
        const e = try number(a[if (mgrs) 3 else 1], if (mgrs) 100000 else 0, if (mgrs) 899999 else 699999);
        const n = try number(a[if (mgrs) 4 else 2], 0, if (mgrs) 9999999 else 1299999); const d: usize = @intCast(try number(a[if (mgrs) 5 else 3], 0, 5));
        if (mgrs) try out.print("{d}{s} {c}{c}", .{ zone, a[2], columns[@intCast(@mod(zone, 3))][@intCast(@divFloor(e, 100000) - 1)],
            mgrs_rows[@intCast(@mod(@divFloor(n, 100000) + @as(i64, if (@mod(zone, 2) == 0) 5 else 0), 20))] }) else
            try out.print("{c}{c}", .{ g25[@intCast(5 * (3 - @divFloor(n, 500000)) + 2 + @divFloor(e, 500000))],
                g25[@intCast(5 * (4 - @mod(@divFloor(n, 100000), 5)) + @mod(@divFloor(e, 100000), 5))] });
        if (d > 0) { const east = try fixedDigits(gpa, @mod(e, 100000), 5); const north = try fixedDigits(gpa, @mod(n, 100000), 5); try out.print(" {s} {s}", .{ east[0..d], north[0..d] }); }
    } else if (equal(op, "UNOSGB") or equal(op, "UNMGRS")) {
        const mgrs = equal(op, "UNMGRS"); const base: usize = if (mgrs) 2 else 1;
        if (a.len != base + 1 and a.len != base + 3) return error.Invalid;
        var e: i64 = 0; var n: i64 = 0; var size: i64 = 100000;
        if (mgrs) {
            const gzd = a[1]; if (gzd.len < 2 or gzd.len > 3 or gzd[0] == '0') return error.Invalid;
            const zone = try digits(gzd[0..gzd.len - 1]); if (zone < 1 or zone > 60) return error.Invalid;
            _ = try index(bands, gzd[gzd.len - 1]); if (a[2].len != 2) return error.Invalid;
            e = 100000 * ((try index(columns[@intCast(@mod(zone, 3))], a[2][0])) + 1);
            n = 100000 * @mod((try index(mgrs_rows, a[2][1])) - @as(i64, if (@mod(zone, 2) == 0) 5 else 0), 20);
        } else {
            if (a[1].len != 2) return error.Invalid; const first = try index(g25, a[1][0]); const second = try index(g25, a[1][1]);
            e = 500000 * (@mod(first, 5) - 2) + 100000 * @mod(second, 5);
            n = 500000 * (3 - @divFloor(first, 5)) + 100000 * (4 - @divFloor(second, 5));
            if (e < 0 or e >= 700000 or n < 0 or n >= 1300000) return error.Invalid;
        }
        if (a.len == base + 3) {
            const east = a[base + 1]; const north = a[base + 2];
            if (east.len == 0 or east.len > 5 or east.len != north.len) return error.Invalid;
            size = power(10, 5 - east.len); e += try digits(east) * size; n += try digits(north) * size;
        }
        if (mgrs) try out.print("{s} ", .{a[1]});
        try out.print("sw={d},{d} size={d}", .{ e, n, size });
    } else if (equal(op, "QUADKEY")) {
        try arity(a, 3); const z: usize = @intCast(try number(a[3], 1, 23)); const maximum = (@as(i64, 1) << @intCast(z)) - 1;
        const x = try number(a[1], 0, maximum); const y = try number(a[2], 0, maximum);
        var i = z; while (i > 0) { i -= 1; try out.writeByte(@as(u8, @intCast(((x >> @intCast(i)) & 1) + 2 * ((y >> @intCast(i)) & 1))) + '0'); }
    } else if (equal(op, "UNQUADKEY")) {
        try arity(a, 1); if (a[1].len == 0 or a[1].len > 23) return error.Invalid;
        var x: i64 = 0; var y: i64 = 0;
        for (a[1]) |ch| { const v = try index("0123", ch); x = 2 * x + @mod(v, 2); y = 2 * y + @divFloor(v, 2); }
        try out.print("x={d} y={d} z={d}", .{ x, y, a[1].len });
    } else return error.Invalid;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator); defer arena.deinit(); const gpa = arena.allocator();
    var input_buffer: [4096]u8 = undefined; var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined; var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count: usize = @intCast(try number((try input.interface.takeDelimiter('\n')).?, 1, 500));
    for (0..count) |_| {
        const line = (try input.interface.takeDelimiter('\n')).?;
        var command_arena = std.heap.ArenaAllocator.init(gpa); defer command_arena.deinit();
        var draft: std.Io.Writer.Allocating = .init(command_arena.allocator());
        execute(command_arena.allocator(), line, &draft.writer) catch |err| {
            if (err == error.Invalid) { try output.interface.writeAll("INVALID\n"); continue; }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered()); try output.interface.writeByte('\n');
    }
    try output.interface.flush();
}
