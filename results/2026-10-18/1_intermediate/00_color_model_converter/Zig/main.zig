const std = @import("std");

const Color = [3]i64;
const Invalid = error{ Invalid };
const CommandError = Invalid || std.Io.Writer.Error;
const names = [_][]const u8{
    "black",
    "maroon",
    "green",
    "olive",
    "navy",
    "purple",
    "teal",
    "silver",
    "gray",
    "red",
    "lime",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
    "orange",
    "pink",
    "brown",
    "gold",
    "coral",
    "salmon",
    "violet",
    "indigo",
};
const builtins = [_]Color{
    .{ 0, 0, 0 },
    .{ 128, 0, 0 },
    .{ 0, 128, 0 },
    .{ 128, 128, 0 },
    .{ 0, 0, 128 },
    .{ 128, 0, 128 },
    .{ 0, 128, 128 },
    .{ 192, 192, 192 },
    .{ 128, 128, 128 },
    .{ 255, 0, 0 },
    .{ 0, 255, 0 },
    .{ 255, 255, 0 },
    .{ 0, 0, 255 },
    .{ 255, 0, 255 },
    .{ 0, 255, 255 },
    .{ 255, 255, 255 },
    .{ 255, 165, 0 },
    .{ 255, 192, 203 },
    .{ 165, 42, 42 },
    .{ 255, 215, 0 },
    .{ 255, 127, 80 },
    .{ 250, 128, 114 },
    .{ 238, 130, 238 },
    .{ 75, 0, 130 },
};

fn same(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn oneOf(s: []const u8, choices: []const []const u8) bool {
    for (choices) |choice| {
        if (same(s, choice))
            return true;
    }
    return false;
}

fn rounded(n: i64, d: i64) i64 {
    return @divFloor(2 * n + d, 2 * d);
}

fn away(n: i64, d: i64) i64 {
    return if (n < 0) -rounded(-n, d) else rounded(n, d);
}

fn clamp(x: i64) i64 {
    return @max(0, @min(255, x));
}

fn percent(n: i64, d: i64) i64 {
    return rounded(100 * n, d);
}

fn equal(a: Color, b: Color) bool {
    return std.mem.eql(i64, &a, &b);
}

fn distance(a: Color, b: Color) i64 {
    var sum: i64 = 0;
    for (a, b) |x, y| {
        const d = x - y;
        sum += d * d;
    }
    return sum;
}

fn squareRoot(n: i64) i64 {
    var lo: i64 = 0;
    var hi = n + 1;
    while (lo + 1 < hi) {
        const mid = @divTrunc(lo + hi, 2);
        if (mid <= @divTrunc(n, mid)) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo;
}

fn writeColor(out: *std.Io.Writer, c: Color) std.Io.Writer.Error!void {
    try out.print("#{X:0>2}{X:0>2}{X:0>2}", .{ @as(u8, @intCast(c[0])), @as(u8, @intCast(c[1])), @as(u8, @intCast(c[2])) });
}

fn writeColors(out: *std.Io.Writer, colors: []const Color) std.Io.Writer.Error!void {
    for (colors, 0..) |c, i| {
        if (i > 0)
            try out.writeByte(' ');
        try writeColor(out, c);
    }
}

fn number(s: []const u8, lo: i64, hi: i64) Invalid!i64 {
    const start: usize = if (s.len > 0 and s[0] == '-') 1 else 0;
    if (s.len <= start or s.len - start > 9)
        return error.Invalid;
    for (s[start..]) |c| {
        if (c < '0' or c > '9')
            return error.Invalid;
    }
    const value = std.fmt.parseInt(i64, s, 10) catch return error.Invalid;
    if (value < lo or value > hi)
        return error.Invalid;
    return value;
}

fn validName(s: []const u8) bool {
    if (s.len < 1 or s.len > 12)
        return false;
    for (s) |c| {
        if (c < 'a' or c > 'z')
            return false;
    }
    return true;
}

fn hexDigit(c: u8) Invalid!i64 {
    if (c >= '0' and c <= '9')
        return c - '0';
    if (c >= 'a' and c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' and c <= 'F')
        return c - 'A' + 10;
    return error.Invalid;
}

fn maximum(c: Color) i64 {
    return @max(c[0], c[1], c[2]);
}

fn minimum(c: Color) i64 {
    return @min(c[0], c[1], c[2]);
}

fn hue(c: Color) i64 {
    const r = c[0];
    const g = c[1];
    const b = c[2];
    const m = maximum(c);
    const d = m - minimum(c);
    if (d == 0)
        return 0;
    var numerator = if (m == r) 60 * (g - b) else if (m == g) 60 * (b - r) + 120 * d else 60 * (r - g) + 240 * d;
    if (numerator < 0)
        numerator += 360 * d;
    return @mod(rounded(numerator, d), 360);
}

fn hsl(c: Color) [3]i64 {
    const m = maximum(c);
    const n = minimum(c);
    const d = m - n;
    const delta = if (m + n >= 255) m + n - 255 else 255 - m - n;
    return .{
        hue(c),
        if (d == 0) 0 else percent(d, 255 - delta),
        percent(m + n, 510)
    };
}

fn hsv(c: Color) [3]i64 {
    const m = maximum(c);
    return .{
        hue(c),
        if (m == 0) 0 else percent(m - minimum(c), m),
        percent(m, 255)
    };
}

fn hwb(c: Color) [3]i64 {
    return .{ hue(c), percent(minimum(c), 255), percent(255 - maximum(c), 255) };
}

fn cmyk(c: Color) [4]i64 {
    const m = maximum(c);
    if (m == 0)
        return .{ 0, 0, 0, 100 };
    return .{
        percent(m - c[0], m),
        percent(m - c[1], m),
        percent(m - c[2], m),
        percent(255 - m, 255)
    };
}

fn ycbcr(c: Color) [3]i64 {
    const r = c[0];
    const g = c[1];
    const b = c[2];
    return .{
        clamp(rounded(299 * r + 587 * g + 114 * b, 1000)),
        clamp(rounded(128000 - 169 * r - 331 * g + 500 * b, 1000)),
        clamp(rounded(128000 + 500 * r - 419 * g - 81 * b, 1000))
    };
}

fn yiq(c: Color) [3]i64 {
    const r = c[0];
    const g = c[1];
    const b = c[2];
    return .{
        rounded(299 * r + 587 * g + 114 * b, 1000),
        rounded(596 * r - 274 * g - 322 * b, 1000),
        rounded(211 * r - 523 * g + 312 * b, 1000)
    };
}
// Every component of base(h,C) is C times one of these factors divided by60.
fn baseFactors(h: i64) [3]i64 {
    const q = @divTrunc(h, 60);
    const f = @mod(h, 60);
    const x = if (@mod(q, 2) == 0) f else 60 - f;
    return switch (q) {
        0 => .{ 60, x, 0 },
        1 => .{ x, 60, 0 },
        2 => .{ 0, 60, x },
        3 => .{ 0, x, 60 },
        4 => .{ x, 0, 60 },
        else => .{ 60, 0, x }
    };
}

fn fromHsl(h: i64, s: i64, l: i64) Color {
    const delta = if (2 * l >= 100) 2 * l - 100 else 100 - 2 * l;
    const c = (100 - delta) * s;
    var result: Color = undefined;
    for (baseFactors(h), 0..) |f, j|
        result[j] = rounded(255 * (2 * c * f + 60 * (200 * l - c)), 1200000);
    return result;
}

fn fromHsv(h: i64, s: i64, v: i64) Color {
    const c = v * s;
    var result: Color = undefined;
    for (baseFactors(h), 0..) |f, j|
        result[j] = rounded(255 * (c * f + 60 * (100 * v - c)), 600000);
    return result;
}

fn fromHwb(h: i64, w: i64, k: i64) Color {
    if (w + k >= 100) {
        const value = rounded(255 * w, w + k);
        return .{ value, value, value };
    }
    var result: Color = undefined;
    for (baseFactors(h), 0..) |f, j|
        result[j] = rounded(255 * (f * (100 - w - k) + 60 * w), 6000);
    return result;
}

fn writeModel(out: *std.Io.Writer, op: []const u8, c: Color) std.Io.Writer.Error!void {
    if (same(op, "CMYK")) {
        const v = cmyk(c);
        try out.print("cmyk({d}%,{d}%,{d}%,{d}%)", .{ v[0], v[1], v[2], v[3] });
        return;
    }
    const v = if (same(op, "HSL")) hsl(c) else if (same(op, "HSV")) hsv(c) else if (same(op, "HWB")) hwb(c) else if (same(op,
        "YCBCR")) ycbcr(c) else yiq(c);
    const label: []const u8 = if (same(op, "HSL")) "hsl" else if (same(op, "HSV")) "hsv" else if (same(op,
        "HWB")) "hwb" else if (same(op, "YCBCR")) "ycbcr" else "yiq";
    const suffix: []const u8 = if (oneOf(op, &.{ "HSL", "HSV", "HWB" })) "%" else "";
    try out.print("{s}({d},{d}{s},{d}{s})", .{ label, v[0], v[1], suffix, v[2], suffix });
}

fn ansi(n: i64) Color {
    if (n < 16)
        return builtins[@intCast(n)];
    if (n >= 232) {
        const v = 8 + 10 * (n - 232);
        return .{ v, v, v };
    }
    const levels = [_]i64{ 0, 95, 135, 175, 215, 255 };
    const i = n - 16;
    return .{
        levels[@intCast(@divTrunc(i, 36))],
        levels[@intCast(@mod(@divTrunc(i, 6), 6))],
        levels[@intCast(@mod(i, 6))]
    };
}

fn luminance(c: Color) i64 {
    return 2126 * c[0] * c[0] + 7152 * c[1] * c[1] + 722 * c[2] * c[2];
}

const Contrast = struct {
    ratio: i64,
    verdict: []const u8
};

fn contrast(a: Color, b: Color) Contrast {
    const y1 = luminance(a);
    const y2 = luminance(b);
    const high = @max(y1, y2) + 32512500;
    const low = @min(y1, y2) + 32512500;
    return .{
        .ratio = rounded(100 * high, low),
        .verdict = if (high >= 7 * low) "AAA" else if (2 * high >= 9 * low) "AA" else "FAIL"
    };
}

fn writeContrast(out: *std.Io.Writer, a: Color, b: Color) std.Io.Writer.Error!void {
    const result = contrast(a, b);
    try out.print("{d}.{d:0>2} {s}", .{
        @divTrunc(result.ratio, 100),
        @as(u8, @intCast(@mod(result.ratio, 100))),
        result.verdict
    });
}

fn rotated(c: Color, d: i64) Color {
    const v = hsl(c);
    return fromHsl(@mod(v[0] + d, 360), v[1], v[2]);
}

fn gradientColor(a: Color, b: Color, i: i64, denominator: i64) Color {
    var result: Color = undefined;
    for (0..3) |j|
        result[j] = a[j] + away((b[j] - a[j]) * i, denominator);
    return result;
}

const Box = struct {
    colors: [32]Color = undefined,
    len: usize = 0,

    fn ranges(self: *const Box) [3]i64 {
        var lo = self.colors[0];
        var hi = lo;
        for (self.colors[1..self.len]) |c| {
            for (0..3) |j| {
                lo[j] = @min(lo[j], c[j]);
                hi[j] = @max(hi[j], c[j]);
            }
        }
        return .{ hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2] };
    }

    fn mean(self: *const Box) Color {
        var sums = Color{ 0, 0, 0 };
        for (self.colors[0..self.len]) |c| {
            for (0..3) |j|
                sums[j] += c[j];
        }
        for (0..3) |j|
            sums[j] = rounded(sums[j], @intCast(self.len));
        return sums;
    }
};

fn palette(k: usize, colors: []const Color) [32]Box {
    var boxes: [32]Box = undefined;
    boxes[0] = Box{};
    boxes[0].len = colors.len;
    for (colors, 0..) |c, i|
        boxes[0].colors[i] = c;
    var len: usize = 1;
    while (len < k) {
        var selected: usize = 0;
        var width: i64 = -1;
        for (boxes[0..len], 0..) |box, i| {
            if (box.len < 2)
                continue;
            const r = box.ranges();
            const w = @max(r[0], r[1], r[2]);
            if (w > width) {
                width = w;
                selected = i;
            }
        }
        const ranges = boxes[selected].ranges();
        var component: usize = 0;
        for (1..3) |j| {
            if (ranges[j] > ranges[component])
                component = j;
        }
        var sorted = boxes[selected];
        for (1..sorted.len) |i| {
            const c = sorted.colors[i];
            var j = i;
            while (j > 0 and sorted.colors[j - 1][component] > c[component]) {
                sorted.colors[j] = sorted.colors[j - 1];
                j -= 1;
            }
            sorted.colors[j] = c;
        }
        const middle = sorted.len / 2;
        var left = Box{};
        var right = Box{};
        left.len = middle;
        right.len = sorted.len - middle;
        for (0..middle) |i|
            left.colors[i] = sorted.colors[i];
        for (middle..sorted.len) |i|
            right.colors[i - middle] = sorted.colors[i];
        var i = len;
        while (i > selected + 1) : (i -= 1)
            boxes[i] = boxes[i - 1];
        boxes[selected] = left;
        boxes[selected + 1] = right;
        len += 1;
    }
    return boxes;
}

fn blendComponent(mode: []const u8, x: i64, y: i64) Invalid!i64 {
    const multiply = @divFloor(x * y, 255);
    const screen = 255 - @divFloor((255 - x) * (255 - y), 255);
    if (same(mode, "MULTIPLY"))
        return multiply;
    if (same(mode, "SCREEN"))
        return screen;
    if (same(mode, "OVERLAY") or same(mode, "HARDLIGHT")) {
        const low = if (same(mode, "OVERLAY")) x < 128 else y < 128;
        return if (low) @divFloor(2 * x * y, 255) else 255 - @divFloor(2 * (255 - x) * (255 - y), 255);
    }
    if (same(mode, "SOFTLIGHT"))
        return @divFloor((255 - x) * multiply + x * screen, 255);
    if (same(mode, "DARKEN"))
        return @min(x, y);
    if (same(mode, "LIGHTEN"))
        return @max(x, y);
    if (same(mode, "DIFFERENCE"))
        return if (x >= y) x - y else y - x;
    if (same(mode, "EXCLUSION"))
        return x + y - @divFloor(2 * x * y, 255);
    if (same(mode, "ADD"))
        return @min(255, x + y);
    if (same(mode, "SUBTRACT"))
        return @max(0, x - y);
    if (same(mode, "COLORDODGE"))
        return if (y == 255) 255 else @min(255, @divFloor(255 * x, 255 - y));
    if (same(mode, "COLORBURN"))
        return if (y == 0) 0 else @max(0, 255 - @divFloor(255 * (255 - x), y));
    return error.Invalid;
}

const Entry = struct {
    name: [12]u8 = undefined,
    len: usize = 0,
    color: Color,

    fn getName(self: *const Entry) []const u8 {
        return self.name[0..self.len];
    }
};

const Engine = struct {
    entries: [500]Entry = undefined,
    len: usize = 0,

    fn registeredIndex(self: *const Engine, name: []const u8) ?usize {
        for (self.entries[0..self.len], 0..) |*entry, i| {
            if (same(entry.getName(), name))
                return i;
        }
        return null;
    }

    fn color(self: *const Engine, s: []const u8) Invalid!Color {
        if ((s.len == 4 or s.len == 7) and s[0] == '#') {
            var result: Color = undefined;
            if (s.len == 4) {
                for (0..3) |j|
                    result[j] = 17 * (try hexDigit(s[j + 1]));
            } else {
                for (0..3) |j|
                    result[j] = 16 * (try hexDigit(s[1 + 2 * j])) + (try hexDigit(s[2 + 2 * j]));
            }
            return result;
        }
        if (s.len >= 5 and same(s[0..4], "rgb(") and s[s.len - 1] == ')') {
            var parts = std.mem.splitScalar(u8, s[4..s.len - 1], ',');
            var result: Color = undefined;
            var count: usize = 0;
            while (parts.next()) |part| {
                if (count == 3 or part.len < 1 or part.len > 3)
                    return error.Invalid;
                for (part) |c| {
                    if (c < '0' or c > '9')
                        return error.Invalid;
                }
                result[count] = try number(part, 0, 255);
                count += 1;
            }
            if (count != 3)
                return error.Invalid;
            return result;
        }
        for (names, builtins) |name, c| {
            if (same(s, name))
                return c;
        }
        if (self.registeredIndex(s)) |index|
            return self.entries[index].color;
        return error.Invalid;
    }

    fn resolveColors(self: *const Engine, args: []const []const u8, buffer: *[33]Color) Invalid![]Color {
        for (args, 0..) |arg, i|
            buffer[i] = try self.color(arg);
        return buffer[0..args.len];
    }

    fn execute(self: *Engine, words: []const []const u8, out: *std.Io.Writer) CommandError!void {
        const op = words[0];
        const a = words[1..];
        if (same(op, "DEFINE")) {
            try requireCount(a, 2);
            if (!validName(a[0]))
                return error.Invalid;
            for (names) |name| {
                if (same(name, a[0]))
                    return error.Invalid;
            }
            const value = try self.color(a[1]);
            if (self.registeredIndex(a[0])) |index| {
                self.entries[index].color = value;
            } else {
                var entry = Entry{ .color = value, .len = a[0].len };
                for (a[0], 0..) |c, i|
                    entry.name[i] = c;
                self.entries[self.len] = entry;
                self.len += 1;
            }
            try out.print("{s} ", .{ a[0] });
            try writeColor(out, value);
            return;
        }
        if (same(op, "UNDEFINE")) {
            try requireCount(a, 1);
            if (!validName(a[0]))
                return error.Invalid;
            const index = self.registeredIndex(a[0]) orelse return error.Invalid;
            var i = index;
            while (i + 1 < self.len) : (i += 1)
                self.entries[i] = self.entries[i + 1];
            self.len -= 1;
            try out.print("{s} removed", .{ a[0] });
            return;
        }
        if (same(op, "LIST")) {
            try requireCount(a, 0);
            if (self.len == 0) {
                try out.writeAll("NONE");
                return;
            }
            var order: [500]usize = undefined;
            for (0..self.len) |i|
                order[i] = i;
            for (1..self.len) |i| {
                const index = order[i];
                var j = i;
                while (j > 0 and std.mem.order(u8, self.entries[order[j - 1]].getName(), self.entries[index].getName()) == .gt) {
                    order[j] = order[j - 1];
                    j -= 1;
                }
                order[j] = index;
            }
            for (order[0..self.len], 0..) |index, i| {
                if (i > 0)
                    try out.writeByte(' ');
                try out.print("{s}=", .{ self.entries[index].getName() });
                try writeColor(out, self.entries[index].color);
            }
            return;
        }
        if (oneOf(op, &.{ "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ", "PARSE" })) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            if (!same(op, "PARSE")) {
                try writeModel(out, op, c);
                return;
            }
            var name: []const u8 = "-";
            for (names, builtins) |n, value| {
                if (equal(c, value)) {
                    name = n;
                    break;
                }
            }
            if (same(name, "-")) {
                for (self.entries[0..self.len]) |*entry| {
                    if (equal(c, entry.color)) {
                        name = entry.getName();
                        break;
                    }
                }
            }
            try writeColor(out, c);
            try out.print(" rgb({d},{d},{d})", .{ c[0], c[1], c[2] });
            for ([_][]const u8{ "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ" }) |m| {
                try out.writeByte(' ');
                try writeModel(out, m, c);
            }
            try out.print(" {s}", .{ name });
            return;
        }
        if (oneOf(op, &.{ "FROMHSL", "FROMHSV", "FROMHWB" })) {
            try requireCount(a, 3);
            const h = try number(a[0], 0, 359);
            const s = try number(a[1], 0, 100);
            const v = try number(a[2], 0, 100);
            try writeColor(out, if (same(op, "FROMHSL")) fromHsl(h, s, v) else if (same(op, "FROMHSV")) fromHsv(h,
                s, v) else fromHwb(h, s, v));
            return;
        }
        if (same(op, "FROMCMYK")) {
            try requireCount(a, 4);
            const c = try number(a[0], 0, 100);
            const m = try number(a[1], 0, 100);
            const y = try number(a[2], 0, 100);
            const k = try number(a[3], 0, 100);
            try writeColor(out, .{
                rounded(255 * (100 - c) * (100 - k), 10000),
                rounded(255 * (100 - m) * (100 - k), 10000),
                rounded(255 * (100 - y) * (100 - k), 10000)
            });
            return;
        }
        if (same(op, "FROMYCBCR") or same(op, "FROMYIQ")) {
            try requireCount(a, 3);
            const is_yiq = same(op, "FROMYIQ");
            const y = try number(a[0], 0, 255);
            const u = try number(a[1], if (is_yiq) -255 else 0, 255);
            const v = try number(a[2], if (is_yiq) -255 else 0, 255);
            var result: Color = if (is_yiq) .{
                1000 * y + 956 * u + 619 * v,
                1000 * y - 272 * u - 647 * v,
                1000 * y - 1106 * u + 1703 * v
            } else .{
                1000 * y + 1402 * (v - 128),
                1000 * y - 344 * (u - 128) - 714 * (v - 128),
                1000 * y + 1772 * (u - 128)
            };
            for (0..3) |j|
                result[j] = clamp(rounded(result[j], 1000));
            try writeColor(out, result);
            return;
        }
        if (same(op, "FROM565")) {
            try requireCount(a, 1);
            if (a[0].len != 6 or !same(a[0][0..2], "0x"))
                return error.Invalid;
            var v: i64 = 0;
            for (a[0][2..]) |c|
                v = 16 * v + (try hexDigit(c));
            try writeColor(out, .{
                rounded(255 * @divTrunc(v, 2048), 31),
                rounded(255 * @mod(@divTrunc(v, 32), 64), 63),
                rounded(255 * @mod(v, 32), 31)
            });
            return;
        }
        if (same(op, "FROMANSI")) {
            try requireCount(a, 1);
            try writeColor(out, ansi(try number(a[0], 0, 255)));
            return;
        }
        if (same(op, "RGB565")) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            const v = 2048 * rounded(31 * c[0], 255) + 32 * rounded(63 * c[1], 255) + rounded(31 * c[2],
                255);
            try out.print("0x{X:0>4}", .{ @as(u16, @intCast(v)) });
            return;
        }
        if (same(op, "ANSI")) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            var best: i64 = 16;
            var i: i64 = 17;
            while (i <= 255) : (i += 1) {
                if (distance(c, ansi(i)) < distance(c, ansi(best)))
                    best = i;
            }
            try out.print("{d} ", .{ best });
            try writeColor(out, ansi(best));
            try out.print(" {d}", .{ distance(c, ansi(best)) });
            return;
        }
        if (same(op, "WEBSAFE") or same(op, "INVERT")) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            var result: Color = undefined;
            for (c, 0..) |x, j|
                result[j] = if (same(op, "INVERT")) 255 - x else
                    51 * rounded(x, 51);
            try writeColor(out, result);
            return;
        }
        if (same(op, "GRAY")) {
            try requireCount(a, 2);
            const c = try self.color(a[0]);
            const r = c[0];
            const g = c[1];
            const b = c[2];
            const value = if (same(a[1], "LUMA")) rounded(299 * r + 587 * g + 114 * b, 1000) else if (same(a[1],
                "AVERAGE")) rounded(r + g + b, 3) else if (same(a[1], "LIGHTNESS")) rounded(maximum(c) + minimum(c),
                2) else if (same(a[1], "HSP")) squareRoot(@divTrunc(299 * r * r + 587 * g * g + 114 * b * b,
                1000)) else return error.Invalid;
            try writeColor(out, .{ value, value, value });
            return;
        }
        if (same(op, "MIX") or same(op, "MIXHSL")) {
            try requireCount(a, 3);
            const c1 = try self.color(a[0]);
            const c2 = try self.color(a[1]);
            const p = try number(a[2], 0, 100);
            if (same(op, "MIX")) {
                var result: Color = undefined;
                for (0..3) |j|
                    result[j] = rounded(c1[j] * (100 - p) + c2[j] * p, 100);
                try writeColor(out, result);
                return;
            }
            const v1 = hsl(c1);
            const v2 = hsl(c2);
            var e = @mod(v2[0] - v1[0], 360);
            if (e > 180)
                e -= 360;
            try writeColor(out, fromHsl(@mod(v1[0] + away(e * p, 100), 360), v1[1] + away((v2[1] - v1[1]) * p,
                100), v1[2] + away((v2[2] - v1[2]) * p, 100)));
            return;
        }
        if (same(op, "GRADIENT")) {
            try requireCount(a, 3);
            const c1 = try self.color(a[0]);
            const c2 = try self.color(a[1]);
            const n = try number(a[2], 2, 16);
            var result: [16]Color = undefined;
            for (0..@as(usize, @intCast(n))) |i|
                result[i] = gradientColor(c1, c2, @intCast(i), n - 1);
            try writeColors(out, result[0..@as(usize, @intCast(n))]);
            return;
        }
        if (oneOf(op, &.{ "TINTS", "SHADES", "TONES" })) {
            try requireCount(a, 2);
            const c = try self.color(a[0]);
            const n = try number(a[1], 1, 10);
            const value: i64 = if (same(op, "TINTS")) 255 else if (same(op, "SHADES")) 0 else 128;
            const target = Color{ value, value, value };
            var result: [10]Color = undefined;
            for (0..@as(usize, @intCast(n))) |i|
                result[i] = gradientColor(c, target, @as(i64, @intCast(i)) + 1, n + 1);
            try writeColors(out, result[0..@as(usize, @intCast(n))]);
            return;
        }
        if (same(op, "BLEND")) {
            try requireCount(a, 3);
            const mode = a[0];
            const base = try self.color(a[1]);
            const top = try self.color(a[2]);
            if (oneOf(mode, &.{ "HUE", "SATURATION", "COLOR", "LUMINOSITY" })) {
                const v1 = hsl(base);
                const v2 = hsl(top);
                try writeColor(out, fromHsl(if (same(mode, "HUE") or same(mode, "COLOR")) v2[0] else v1[0], if (same(mode,
                    "SATURATION") or same(mode, "COLOR")) v2[1] else v1[1], if (same(mode, "LUMINOSITY")) v2[2] else v1[2]));
                return;
            }
            var result: Color = undefined;
            for (0..3) |j|
                result[j] = try blendComponent(mode, base[j], top[j]);
            try writeColor(out, result);
            return;
        }
        if (same(op, "ALPHA")) {
            try requireCount(a, 4);
            const fg = try self.color(a[0]);
            const p = try number(a[1], 0, 100);
            const bg = try self.color(a[2]);
            const q = try number(a[3], 0, 100);
            const opacity = 100 * p + q * (100 - p);
            var result = Color{ 0, 0, 0 };
            if (opacity > 0) {
                for (0..3) |j|
                    result[j] = rounded(100 * p * fg[j] + q * (100 - p) * bg[j], opacity);
            }
            try writeColor(out, result);
            try out.print(" {d}%", .{ rounded(opacity, 100) });
            return;
        }
        if (same(op, "SIMULATE")) {
            try requireCount(a, 2);
            const c = try self.color(a[0]);
            const coefficients: [3][3]i64 = if (same(a[1], "PROTANOPIA"))
                .{ .{567, 433, 0}, .{558, 442, 0}, .{0, 242, 758} }
            else if (same(a[1], "DEUTERANOPIA"))
                .{ .{625, 375, 0}, .{700, 300, 0}, .{0, 300, 700} }
            else if (same(a[1], "TRITANOPIA"))
                .{ .{950, 50, 0}, .{0, 433, 567}, .{0, 475, 525} }
            else if (same(a[1], "ACHROMATOPSIA"))
                .{ .{299, 587, 114}, .{299, 587, 114}, .{299, 587, 114} }
            else return error.Invalid;
            var result: Color = undefined;
            for (coefficients, 0..) |row, j|
                result[j] = rounded(row[0] * c[0] + row[1] * c[1] + row[2] * c[2], 1000);
            try writeColor(out, result);
            return;
        }
        if (same(op, "ROTATE")) {
            try requireCount(a, 2);
            const c = try self.color(a[0]);
            const d = try number(a[1], -720, 720);
            try writeColor(out, rotated(c, d));
            return;
        }
        if (oneOf(op, &.{ "COMPLEMENT", "TRIADIC", "TETRADIC", "SPLITCOMP" })) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            const offsets: []const i64 = if (same(op, "COMPLEMENT")) &.{ 180 } else if (same(op, "TRIADIC")) &.{ 120,
                240 } else if (same(op, "TETRADIC")) &.{ 90, 180, 270 } else &.{ 150, 210 };
            var result: [3]Color = undefined;
            for (offsets, 0..) |d, i|
                result[i] = rotated(c, d);
            try writeColors(out, result[0..offsets.len]);
            return;
        }
        if (same(op, "ANALOGOUS")) {
            try requireCount(a, 3);
            const c = try self.color(a[0]);
            const k = try number(a[1], 1, 6);
            const step = try number(a[2], 1, 60);
            var result: [12]Color = undefined;
            var len: usize = 0;
            var i = -k;
            while (i <= k) : (i += 1) {
                if (i == 0)
                    continue;
                result[len] = rotated(c, i * step);
                len += 1;
            }
            try writeColors(out, result[0..len]);
            return;
        }
        if (oneOf(op, &.{ "LIGHTEN", "DARKEN", "SATURATE", "DESATURATE" })) {
            try requireCount(a, 2);
            var v = hsl(try self.color(a[0]));
            const p = try number(a[1], 0, 100);
            const j: usize = if (same(op, "LIGHTEN") or same(op, "DARKEN")) 2 else 1;
            v[j] = if (same(op, "LIGHTEN") or same(op, "SATURATE")) @min(100, v[j] + p) else @max(0, v[j] - p);
            try writeColor(out, fromHsl(v[0], v[1], v[2]));
            return;
        }
        if (same(op, "NEAREST")) {
            try requireCount(a, 1);
            const c = try self.color(a[0]);
            var best_name = names[0];
            var best_color = builtins[0];
            var d = distance(c, best_color);
            for (names[1..], builtins[1..]) |name, value| {
                const next = distance(c, value);
                if (next < d) {
                    d = next;
                    best_name = name;
                    best_color = value;
                }
            }
            for (self.entries[0..self.len]) |*entry| {
                const next = distance(c, entry.color);
                if (next < d) {
                    d = next;
                    best_name = entry.getName();
                    best_color = entry.color;
                }
            }
            try out.print("{s} ", .{ best_name });
            try writeColor(out, best_color);
            try out.print(" {d}", .{ d });
            return;
        }
        if (same(op, "DISTANCE")) {
            try requireCount(a, 2);
            const c1 = try self.color(a[0]);
            const c2 = try self.color(a[1]);
            const r = c1[0] - c2[0];
            const g = c1[1] - c2[1];
            const b = c1[2] - c2[2];
            const w = (1024 + c1[0] + c2[0]) * r * r + 2048 * g * g + (1534 - c1[0] - c2[0]) * b * b;
            try out.print("{d} {d}", .{ distance(c1, c2), squareRoot(@divTrunc(w, 512)) });
            return;
        }
        if (same(op, "CONTRAST")) {
            try requireCount(a, 2);
            const c1 = try self.color(a[0]);
            const c2 = try self.color(a[1]);
            try writeContrast(out, c1, c2);
            return;
        }
        if (same(op, "ACCESSIBLE")) {
            try requireCount(a, 2);
            const fg = try self.color(a[0]);
            const bg = try self.color(a[1]);
            var result = fg;
            if (same(contrast(fg, bg).verdict, "FAIL")) {
                const v = hsl(fg);
                var t: i64 = 1;
                search: while (t <= 100) : (t += 1) {
                    for ([_]i64{ v[2] - t, v[2] + t }) |l| {
                        if (l < 0 or l > 100)
                            continue;
                        const candidate = fromHsl(v[0], v[1], l);
                        if (!same(contrast(candidate, bg).verdict, "FAIL")) {
                            result = candidate;
                            break :search;
                        }
                    }
                }
            }
            try writeColor(out, result);
            try out.writeByte(' ');
            try writeContrast(out, result, bg);
            return;
        }
        if (same(op, "BEST")) {
            if (a.len < 2 or a.len > 33)
                return error.Invalid;
            var buffer: [33]Color = undefined;
            const colors = try self.resolveColors(a, &buffer);
            const bg = colors[0];
            var best: usize = 1;
            for (2..colors.len) |i| {
                if (contrast(colors[i], bg).ratio > contrast(colors[best], bg).ratio)
                    best = i;
            }
            try writeColor(out, colors[best]);
            try out.writeByte(' ');
            try writeContrast(out, colors[best], bg);
            return;
        }
        if (same(op, "DESCRIBE")) {
            try requireCount(a, 1);
            const v = hsl(try self.color(a[0]));
            const h = v[0];
            const s = v[1];
            const l = v[2];
            if (l <= 5) {
                try out.writeAll("black");
                return;
            }
            if (l >= 95) {
                try out.writeAll("white");
                return;
            }
            const lightness: []const u8 = if (l <= 20) "very dark" else if (l <= 40) "dark" else if (l <= 60) "medium" else if (l <= 80) "light" else "very light";
            if (s < 10) {
                try out.print("{s} gray", .{ lightness });
                return;
            }
            const hues = [_][]const u8{
                "red",
                "orange",
                "yellow",
                "chartreuse",
                "green",
                "spring-green",
                "cyan",
                "azure",
                "blue",
                "violet",
                "magenta",
                "rose"
            };
            const saturation: []const u8 = if (s < 40) "muted" else if (s < 80) "moderate" else "vivid";
            try out.print("{s} {s} {s}", .{
                lightness,
                saturation,
                hues[@intCast(@divTrunc(@mod(h + 15, 360), 30))]
            });
            return;
        }
        if (same(op, "PALETTE") or same(op, "KMEANS")) {
            if (a.len < 2 or a.len > 33)
                return error.Invalid;
            const k: usize = @intCast(try number(a[0], 1, @intCast(a.len - 1)));
            var buffer: [33]Color = undefined;
            const colors = try self.resolveColors(a[1..], &buffer);
            const boxes = palette(k, colors);
            if (same(op, "PALETTE")) {
                for (boxes[0..k], 0..) |box, j| {
                    if (j > 0)
                        try out.writeByte(' ');
                    try writeColor(out, box.mean());
                    try out.print(":{d}", .{ box.len });
                }
                return;
            }
            var representatives: [32]Color = undefined;
            for (0..k) |j|
                representatives[j] = boxes[j].mean();
            var counts: [32]i64 = undefined;
            var iterations: usize = 0;
            for (0..20) |_| {
                iterations += 1;
                counts = [_]i64{ 0 } ** 32;
                var sums = [_]Color{ .{ 0, 0, 0 } } ** 32;
                for (colors) |c| {
                    var best: usize = 0;
                    for (1..k) |j| {
                        if (distance(c, representatives[j]) < distance(c, representatives[best]))
                            best = j;
                    }
                    counts[best] += 1;
                    for (0..3) |j|
                        sums[best][j] += c[j];
                }
                var next = representatives;
                var unchanged = true;
                for (0..k) |j| {
                    if (counts[j] > 0) {
                        for (0..3) |channel|
                            next[j][channel] = rounded(sums[j][channel], counts[j]);
                    }
                    if (!equal(next[j], representatives[j]))
                        unchanged = false;
                }
                representatives = next;
                if (unchanged)
                    break;
            }
            try out.print("{d}", .{ iterations });
            for (0..k) |j| {
                try out.writeByte(' ');
                try writeColor(out, representatives[j]);
                try out.print(":{d}", .{ counts[j] });
            }
            return;
        }
        if (same(op, "SORT")) {
            if (a.len < 1 or a.len > 32)
                return error.Invalid;
            var buffer: [33]Color = undefined;
            const colors = try self.resolveColors(a, &buffer);
            for (1..colors.len) |i| {
                const c = colors[i];
                var j = i;
                while (j > 0 and hslLess(c, colors[j - 1])) {
                    colors[j] = colors[j - 1];
                    j -= 1;
                }
                colors[j] = c;
            }
            try writeColors(out, colors);
            return;
        }
        if (same(op, "DITHER")) {
            if (a.len < 1 or a.len > 32)
                return error.Invalid;
            var buffer: [33]Color = undefined;
            const colors = try self.resolveColors(a, &buffer);
            var err = Color{ 0, 0, 0 };
            for (colors, 0..) |c, i| {
                var corrected: Color = undefined;
                for (0..3) |j|
                    corrected[j] = clamp(c[j] + err[j]);
                var best: usize = 0;
                for (1..16) |j| {
                    if (distance(corrected, builtins[j]) < distance(corrected, builtins[best]))
                        best = j;
                }
                if (i > 0)
                    try out.writeByte(' ');
                try out.writeAll(names[best]);
                for (0..3) |j|
                    err[j] = corrected[j] - builtins[best][j];
            }
            return;
        }
        if (same(op, "RANDOM")) {
            try requireCount(a, 2);
            var state = try number(a[0], 1, 999999999);
            const n: usize = @intCast(try number(a[1], 1, 16));
            var result: [16]Color = undefined;
            for (0..n) |i| {
                state = @mod(state * 48271, 2147483647);
                const h = @mod(state, 360);
                state = @mod(state * 48271, 2147483647);
                const s = 40 + @mod(state, 61);
                state = @mod(state * 48271, 2147483647);
                const l = 25 + @mod(state, 51);
                result[i] = fromHsl(h, s, l);
            }
            try writeColors(out, result[0..n]);
            return;
        }
        return error.Invalid;
    }
};

fn requireCount(args: []const []const u8, n: usize) Invalid!void {
    if (args.len != n)
        return error.Invalid;
}

fn hslLess(a: Color, b: Color) bool {
    const x = hsl(a);
    const y = hsl(b);
    for (0..3) |j| {
        if (x[j] != y[j])
            return x[j] < y[j];
    }
    return false;
}

pub fn main(init: std.process.Init) !void {
    var input_buffer: [2048]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const out = &output.interface;
    const first = (try input.interface.takeDelimiter('\n')).?;
    const n = try std.fmt.parseInt(usize, first, 10);
    var engine = Engine{};
    for (0..n) |_| {
        const line = (try input.interface.takeDelimiter('\n')).?;
        var words: [501][]const u8 = undefined;
        var len: usize = 0;
        var tokens = std.mem.splitScalar(u8, line, ' ');
        while (tokens.next()) |token| {
            words[len] = token;
            len += 1;
        }
        engine.execute(words[0..len], out) catch |err| {
            switch (err) {
                error.Invalid => {
                    try out.writeAll("INVALID\n");
                    continue;
                },
                else => return err,
            }
        };
        try out.writeByte('\n');
    }
    try out.flush();
}
