const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = error{BadCommand} || Allocator.Error || Writer.Error;
const Mode = enum { RNE, RNA, RTZ, RUP, RDN };
const Operation = enum { ADD, SUB, MUL, DIV, SQRT, FMA };
const Relation = enum { LT, EQ, GT };
const IntegerType = enum { I8, U8, I16, U16, I32, U32 };
const Command = enum {
    FORMAT, ENCODE, DECODE, ADD, SUB, MUL, DIV, SQRT, FMA, CONVERT,
    COMPARE, NEXTUP, NEXTDOWN, ULP, TOINT, TABLE, SUM, KAHAN, DOT,
    fn operation(command: Command) ?Operation {
        return switch (command) {
            .ADD => .ADD, .SUB => .SUB, .MUL => .MUL, .DIV => .DIV, .SQRT => .SQRT, .FMA => .FMA,
            else => null,
        };
    }
};

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn parseNumber(word: []const u8) u64 { return std.fmt.parseInt(u64, word, 10) catch unreachable; }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn compareUnsigned(a: u64, b: u64) Relation { return if (a < b) .LT else if (a > b) .GT else .EQ; }
fn compareSigned(a: i64, b: i64) Relation { return if (a < b) .LT else if (a > b) .GT else .EQ; }
fn bitLength(value: u64) i32 {
    var n = value;
    var length: i32 = 0;
    while (n != 0) : (n >>= 1) length += 1;
    return length;
}
fn gcd(a: u64, b: u64) u64 {
    var x = a;
    var y = b;
    while (y != 0) {
        const remainder = x % y;
        x = y;
        y = remainder;
    }
    return x;
}
const Scaled = struct { n: u64, d: u64 };
fn scaled(n: u64, d: u64, exponent: i32) Scaled {
    return if (exponent >= 0) .{ .n = n << @intCast(exponent), .d = d }
        else .{ .n = n, .d = d << @intCast(-exponent) };
}
fn integerSqrt(value: u64) u64 {
    if (value == 0) return 0;
    var root = @as(u64, 1) << @intCast(@divTrunc(bitLength(value) + 1, 2));
    while (true) {
        const next = (root + value / root) / 2;
        if (next >= root) return root;
        root = next;
    }
}
fn increment(mode: Mode, negative: bool, whole: u64, inexact: bool, halfway: Relation) bool {
    if (!inexact) return false;
    return switch (mode) {
        .RNE => halfway == .GT or halfway == .EQ and whole % 2 != 0,
        .RNA => halfway != .LT,
        .RTZ => false,
        .RUP => !negative,
        .RDN => negative,
    };
}
const Units = struct { whole: u64, inexact: bool };
fn roundUnits(exact: Exact, exponent: i32, mode: Mode, square_root: bool) Units {
    const ratio = scaled(exact.n, exact.d, exact.exponent - (if (square_root) 2 * exponent else exponent));
    var whole = if (square_root) integerSqrt(ratio.n / ratio.d) else ratio.n / ratio.d;
    const inexact = if (square_root) whole * whole * ratio.d != ratio.n else ratio.n % ratio.d != 0;
    const midpoint = 2 * whole + 1;
    const halfway = if (square_root) compareUnsigned(4 * ratio.n, ratio.d * midpoint * midpoint)
        else compareUnsigned(2 * (ratio.n % ratio.d), ratio.d);
    if (increment(mode, exact.negative, whole, inexact, halfway)) whole += 1;
    return .{ .whole = whole, .inexact = inexact };
}

const Flags = struct {
    bits: u8 = 0,
    const invalid: u8 = 1;
    const divbyzero: u8 = 2;
    const overflow: u8 = 4;
    const underflow: u8 = 8;
    const inexact: u8 = 16;
    pub fn format(value: Flags, out: *Writer) Writer.Error!void {
        try out.writeAll("flags=");
        if (value.bits == 0) return out.writeAll("none");
        const names = [_][]const u8{ "invalid", "divbyzero", "overflow", "underflow", "inexact" };
        var first = true;
        for (names, 0..) |name, i| if (value.bits & (@as(u8, 1) << @intCast(i)) != 0) {
            if (!first) try out.writeByte(',');
            try out.writeAll(name);
            first = false;
        };
    }
};
const Result = struct { pattern: u32, flags: u8 = 0 };
const Name = struct {
    bytes: [8]u8 = @splat(0),
    len: usize = 0,
    fn init(text: []const u8) Name {
        var result: Name = .{ .len = text.len };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }
    fn matches(name: Name, text: []const u8) bool { return equal(name.bytes[0..name.len], text); }
    pub fn format(name: Name, out: *Writer) Writer.Error!void { try out.writeAll(name.bytes[0..name.len]); }
};
const Binary = struct {
    value: u32,
    width: u6,
    pub fn format(bits: Binary, out: *Writer) Writer.Error!void {
        var left = bits.width;
        while (left > 0) {
            left -= 1;
            try out.writeByte(if (bits.value & (@as(u32, 1) << @intCast(left)) == 0) '0' else '1');
        }
    }
};
const Hex = struct {
    value: u32,
    width: u6,
    pub fn format(hex: Hex, out: *Writer) Writer.Error!void {
        try out.writeAll("0x");
        var left = hex.width;
        while (left > 0) {
            left -= 1;
            try out.writeByte("0123456789ABCDEF"[(hex.value >> @intCast(4 * left)) & 15]);
        }
    }
};

// The magnitude is n * 2^exponent / d; the separate sign preserves negative zero.
const Exact = struct {
    n: u64 = 0,
    exponent: i32 = 0,
    d: u64 = 1,
    negative: bool = false,

    fn negated(exact: Exact) Exact {
        var result = exact;
        result.negative = !result.negative;
        return result;
    }
    fn log2Floor(exact: Exact) i32 {
        const t = bitLength(exact.n) - bitLength(exact.d) + exact.exponent;
        const ratio = scaled(exact.n, exact.d, exact.exponent - t);
        return if (ratio.n < ratio.d) t - 1 else t;
    }
    fn product(a: Exact, b: Exact) Exact {
        return .{ .n = a.n * b.n, .exponent = a.exponent + b.exponent, .d = a.d * b.d, .negative = a.negative != b.negative };
    }
    fn sum(terms: []const Exact, mode: Mode) Exact {
        var exponent: ?i32 = null;
        for (terms) |term| if (term.n != 0 and (exponent == null or term.exponent < exponent.?)) { exponent = term.exponent; };
        if (exponent == null) {
            var same = true;
            for (terms) |term| same = same and term.negative == terms[0].negative;
            return .{ .negative = if (same) terms[0].negative else mode == .RDN };
        }
        // All sums and differences consist of dyadic terms with denominator 1.
        var numerator: i64 = 0;
        for (terms) |term| {
            if (term.n == 0) continue;
            const aligned: i64 = @intCast(term.n << @intCast(term.exponent - exponent.?));
            numerator += if (term.negative) -aligned else aligned;
        }
        return .{ .n = @intCast(if (numerator < 0) -numerator else numerator), .exponent = exponent.?,
            .negative = numerator < 0 or numerator == 0 and mode == .RDN };
    }
    fn decimal(exact: Exact, keep_zero_sign: bool) Decimal { return .{ .exact = exact, .keep_zero_sign = keep_zero_sign }; }
    pub fn format(exact: Exact, out: *Writer) Writer.Error!void {
        if (exact.n == 0) return out.writeByte('0');
        const ratio = scaled(exact.n, exact.d, exact.exponent);
        const factor = gcd(ratio.n, ratio.d);
        if (exact.negative) try out.writeByte('-');
        try out.print("{d}", .{ratio.n / factor});
        if (ratio.d != factor) try out.print("/{d}", .{ratio.d / factor});
    }
};
const Decimal = struct {
    exact: Exact,
    keep_zero_sign: bool = false,
    pub fn format(value: Decimal, out: *Writer) Writer.Error!void {
        const exact = value.exact;
        const ratio = scaled(exact.n, exact.d, exact.exponent);
        if (exact.negative and (exact.n != 0 or value.keep_zero_sign)) try out.writeByte('-');
        try out.print("{d}", .{ratio.n / ratio.d});
        var remainder = ratio.n % ratio.d;
        if (remainder == 0) return;
        try out.writeByte('.');
        while (remainder != 0) {
            remainder *= 10;
            try out.writeByte(@intCast('0' + remainder / ratio.d));
            remainder %= ratio.d;
        }
    }
};

const Fields = struct { negative: bool, exponent: u32, fraction: u32, q: i32 };
const MiniFormat = struct {
    name: Name,
    e: u6,
    m: u6,
    width: u6,
    bias: i32,
    emin: i32,
    emax: i32,
    hidden: u32,
    exponent_mask: u32,
    sign_bit: u32,
    infinity: u32,

    fn init(name: []const u8, e: u6, m: u6) MiniFormat {
        const bias: i32 = @intCast((@as(u32, 1) << @intCast(e - 1)) - 1);
        const hidden = @as(u32, 1) << @intCast(m);
        const mask = (@as(u32, 1) << @intCast(e)) - 1;
        return .{ .name = .init(name), .e = e, .m = m, .width = 1 + e + m, .bias = bias, .emin = 1 - bias, .emax = bias,
            .hidden = hidden, .exponent_mask = mask, .sign_bit = @as(u32, 1) << @intCast(e + m), .infinity = mask * hidden };
    }
    fn fields(f: MiniFormat, pattern: u32) Fields {
        const exponent = (pattern >> @intCast(f.m)) & f.exponent_mask;
        return .{ .negative = pattern & f.sign_bit != 0, .exponent = exponent, .fraction = pattern & (f.hidden - 1),
            .q = (if (exponent == 0) f.emin else @as(i32, @intCast(exponent)) - f.bias) - f.m };
    }
    fn isNaN(f: MiniFormat, pattern: u32) bool { return f.fields(pattern).exponent == f.exponent_mask and f.fields(pattern).fraction != 0; }
    fn isSignaling(f: MiniFormat, pattern: u32) bool { return f.isNaN(pattern) and f.fields(pattern).fraction < f.hidden / 2; }
    fn isInfinity(f: MiniFormat, pattern: u32) bool { return pattern & (f.sign_bit - 1) == f.infinity; }
    fn isZero(f: MiniFormat, pattern: u32) bool { return pattern & (f.sign_bit - 1) == 0; }
    fn isFinite(f: MiniFormat, pattern: u32) bool { return f.fields(pattern).exponent != f.exponent_mask; }
    fn nan(f: MiniFormat) u32 { return f.infinity + f.hidden / 2; }
    fn zero(f: MiniFormat, negative: bool) u32 { return if (negative) f.sign_bit else 0; }
    fn inf(f: MiniFormat, negative: bool) u32 { return f.zero(negative) + f.infinity; }
    fn flip(f: MiniFormat, pattern: u32) u32 { return pattern ^ f.sign_bit; }
    fn exact(f: MiniFormat, pattern: u32) Exact {
        const parts = f.fields(pattern);
        return .{ .n = if (parts.exponent == 0) parts.fraction else f.hidden + parts.fraction, .exponent = parts.q, .negative = parts.negative };
    }
    fn bits(f: MiniFormat, pattern: u32) BitText { return .{ .f = f, .pattern = pattern }; }
    fn hex(f: MiniFormat, pattern: u32) Hex { return .{ .value = pattern, .width = (f.width + 3) / 4 }; }
    fn valueText(f: MiniFormat, pattern: u32) ValueText { return .{ .f = f, .pattern = pattern }; }
    fn patternText(f: MiniFormat, pattern: u32) PatternText { return .{ .f = f, .pattern = pattern }; }
    fn resultText(f: MiniFormat, result: Result) ResultText { return .{ .f = f, .result = result }; }
    fn overflow(f: MiniFormat, negative: bool, mode: Mode) Result {
        const infinity = mode == .RNE or mode == .RNA or mode == .RUP and !negative or mode == .RDN and negative;
        return .{ .pattern = f.zero(negative) + (if (infinity) f.infinity else f.infinity - 1), .flags = Flags.overflow | Flags.inexact };
    }
    fn roundNonzero(f: MiniFormat, exact_value: Exact, mode: Mode, square_root: bool) Result {
        const logarithm = exact_value.log2Floor();
        const t = if (square_root) @divFloor(logarithm, 2) else logarithm;
        const negative = if (square_root) false else exact_value.negative;
        if (t > f.emax) return f.overflow(negative, mode);
        var exponent = @max(t, f.emin) - f.m;
        const units = roundUnits(exact_value, exponent, mode, square_root);
        var n = units.whole;
        if (n == 2 * f.hidden) { n = f.hidden; exponent += 1; }
        if (exponent > f.emax - f.m) return f.overflow(negative, mode);
        const magnitude = if (n >= f.hidden) @as(u32, @intCast(exponent + f.m + f.bias)) * f.hidden + @as(u32, @intCast(n)) - f.hidden
            else @as(u32, @intCast(n));
        var flags: u8 = if (units.inexact) Flags.inexact else 0;
        if (units.inexact and t < f.emin and (t < f.emin - 1 or roundUnits(exact_value, t - f.m, mode, square_root).whole < 2 * f.hidden)) flags |= Flags.underflow;
        return .{ .pattern = f.zero(negative) + magnitude, .flags = flags };
    }
    fn round(f: MiniFormat, exact_value: Exact, mode: Mode) Result {
        return if (exact_value.n == 0) .{ .pattern = f.zero(exact_value.negative) } else f.roundNonzero(exact_value, mode, false);
    }
};

const BitText = struct {
    f: MiniFormat,
    pattern: u32,
    pub fn format(text: BitText, out: *Writer) Writer.Error!void {
        const parts = text.f.fields(text.pattern);
        try out.print("{d}|{f}|{f}", .{ @intFromBool(parts.negative), Binary{ .value = parts.exponent, .width = text.f.e }, Binary{ .value = parts.fraction, .width = text.f.m } });
    }
};
const ValueText = struct {
    f: MiniFormat,
    pattern: u32,
    pub fn format(text: ValueText, out: *Writer) Writer.Error!void {
        if (text.f.isNaN(text.pattern)) return out.writeAll("nan");
        if (text.f.isInfinity(text.pattern)) return out.writeAll(if (text.f.fields(text.pattern).negative) "-inf" else "inf");
        try out.print("{f}", .{text.f.exact(text.pattern).decimal(true)});
    }
};
const PatternText = struct {
    f: MiniFormat,
    pattern: u32,
    pub fn format(text: PatternText, out: *Writer) Writer.Error!void {
        try out.print("{f} {f} {f}", .{ text.f.bits(text.pattern), text.f.hex(text.pattern), text.f.valueText(text.pattern) });
    }
};
const ResultText = struct {
    f: MiniFormat,
    result: Result,
    pub fn format(text: ResultText, out: *Writer) Writer.Error!void {
        try out.print("{f} {f}", .{ text.f.patternText(text.result.pattern), Flags{ .bits = text.result.flags } });
    }
};
const Difference = struct {
    f: MiniFormat,
    pattern: u32,
    exact: Exact,
    pub fn format(text: Difference, out: *Writer) Writer.Error!void {
        if (!text.f.isFinite(text.pattern)) return out.print("{f}", .{text.f.valueText(text.pattern)});
        try out.print("{f}", .{Exact.sum(&.{ text.f.exact(text.pattern), text.exact.negated() }, .RNE)});
    }
};

const RealInput = union(enum) {
    finite: Exact,
    infinity: bool,
    nan,
    fn encoded(input: RealInput, f: MiniFormat, mode: Mode) Result {
        return switch (input) {
            .finite => |number| f.round(number, mode),
            .infinity => |negative| .{ .pattern = f.inf(negative) },
            .nan => .{ .pattern = f.nan() },
        };
    }
    pub fn format(input: RealInput, out: *Writer) Writer.Error!void {
        switch (input) {
            .finite => |number| try out.print("{f}", .{number}),
            .infinity => |negative| try out.writeAll(if (negative) "-inf" else "inf"),
            .nan => try out.writeAll("nan"),
        }
    }
};

fn calculate(f: MiniFormat, operation: Operation, mode: Mode, inputs: []const u32) Result {
    var any_nan = false;
    var signaling = false;
    for (inputs) |pattern| {
        any_nan = any_nan or f.isNaN(pattern);
        signaling = signaling or f.isSignaling(pattern);
    }
    if (any_nan) return .{ .pattern = f.nan(), .flags = if (signaling) Flags.invalid else 0 };
    const a = inputs[0];
    const negative = f.fields(a).negative;
    const invalid: Result = .{ .pattern = f.nan(), .flags = Flags.invalid };
    if (operation == .SQRT) {
        if (f.isZero(a)) return .{ .pattern = a };
        if (negative) return invalid;
        if (f.isInfinity(a)) return .{ .pattern = a };
        return f.roundNonzero(f.exact(a), mode, true);
    }
    const b = if (operation == .SUB) f.flip(inputs[1]) else inputs[1];
    const sigma = negative != f.fields(b).negative;
    if (operation == .ADD or operation == .SUB) {
        if (f.isInfinity(a) and f.isInfinity(b) and sigma) return invalid;
        if (f.isInfinity(a)) return .{ .pattern = a };
        if (f.isInfinity(b)) return .{ .pattern = b };
        return f.round(Exact.sum(&.{ f.exact(a), f.exact(b) }, mode), mode);
    }
    if (operation == .MUL) {
        if (f.isInfinity(a) or f.isInfinity(b)) return if (f.isZero(a) or f.isZero(b)) invalid else .{ .pattern = f.inf(sigma) };
        if (f.isZero(a) or f.isZero(b)) return .{ .pattern = f.zero(sigma) };
        return f.round(Exact.product(f.exact(a), f.exact(b)), mode);
    }
    if (operation == .DIV) {
        if (f.isInfinity(a)) return if (f.isInfinity(b)) invalid else .{ .pattern = f.inf(sigma) };
        if (f.isInfinity(b)) return .{ .pattern = f.zero(sigma) };
        if (f.isZero(b)) return if (f.isZero(a)) invalid else .{ .pattern = f.inf(sigma), .flags = Flags.divbyzero };
        if (f.isZero(a)) return .{ .pattern = f.zero(sigma) };
        const x = f.exact(a);
        const y = f.exact(b);
        return f.round(.{ .n = x.n * y.d, .exponent = x.exponent - y.exponent, .d = x.d * y.n, .negative = sigma }, mode);
    }
    const c = inputs[2];
    if (f.isInfinity(a) or f.isInfinity(b)) {
        if (f.isZero(a) or f.isZero(b) or f.isInfinity(c) and f.fields(c).negative != sigma) return invalid;
        return .{ .pattern = f.inf(sigma) };
    }
    if (f.isInfinity(c)) return .{ .pattern = c };
    return f.round(Exact.sum(&.{ Exact.product(f.exact(a), f.exact(b)), f.exact(c) }, mode), mode);
}

fn nextUp(f: MiniFormat, pattern: u32) u32 {
    return if (pattern == f.infinity) pattern else if (f.isZero(pattern)) 1
        else if (f.fields(pattern).negative) pattern - 1 else pattern + 1;
}
fn orderKey(f: MiniFormat, pattern: u32) i64 {
    return if (f.fields(pattern).negative) -@as(i64, pattern - f.sign_bit) - 1 else pattern;
}

const Program = struct {
    formats: [13]MiniFormat = undefined,
    format_count: usize = 3,
    scratch: Allocator,
    out: *Writer,
    error_message: []const u8 = "",

    fn init(scratch: Allocator, out: *Writer) Program {
        var program: Program = .{ .scratch = scratch, .out = out };
        program.formats[0] = .init("HALF", 5, 10);
        program.formats[1] = .init("E5M2", 5, 2);
        program.formats[2] = .init("E4M3", 4, 3);
        return program;
    }
    fn fail(program: *Program, comptime fmt: []const u8, args: anytype) Error {
        program.error_message = std.fmt.allocPrint(program.scratch, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn findFormat(program: *const Program, name: []const u8) ?MiniFormat {
        for (program.formats[0..program.format_count]) |f| if (f.name.matches(name)) return f;
        return null;
    }
    fn getFormat(program: *Program, name: []const u8) Error!MiniFormat {
        return program.findFormat(name) orelse return program.fail("UNKNOWN FORMAT {s}", .{name});
    }
    fn parseMode(program: *Program, words: []const []const u8, index: usize) Error!Mode {
        if (index == words.len) return .RNE;
        return std.meta.stringToEnum(Mode, words[index]) orelse return program.fail("BAD MODE {s}", .{words[index]});
    }
    fn parseReal(program: *Program, word: []const u8) Error!RealInput {
        if (equal(word, "nan")) return .nan;
        if (equal(word, "inf") or equal(word, "-inf")) return .{ .infinity = word[0] == '-' };
        if (std.mem.startsWith(u8, word, "0b") or std.mem.startsWith(u8, word, "0x")) return program.fail("BAD OPERAND {s}", .{word});
        const negative = word[0] == '-';
        const body = if (negative) word[1..] else word;
        if (std.mem.indexOfScalar(u8, body, '/')) |slash| {
            const n = parseNumber(body[0..slash]);
            const d = parseNumber(body[slash + 1 ..]);
            if (d == 0) return program.fail("BAD OPERAND {s}", .{word});
            return .{ .finite = .{ .n = n, .d = d, .negative = negative } };
        }
        var n: u64 = 0;
        var d: u64 = 1;
        var fractional = false;
        for (body) |ch| {
            if (ch == '.') { fractional = true; continue; }
            n = n * 10 + ch - '0';
            if (fractional) d *= 10;
        }
        return .{ .finite = .{ .n = n, .d = d, .negative = negative } };
    }
    fn operand(program: *Program, f: MiniFormat, word: []const u8) Error!u32 {
        const bits = std.mem.startsWith(u8, word, "0b");
        const hex = std.mem.startsWith(u8, word, "0x");
        if (bits or hex) {
            const width: usize = if (bits) f.width else (f.width + 3) / 4;
            if (word.len - 2 != width) return program.fail("BAD OPERAND {s}", .{word});
            const pattern = std.fmt.parseInt(u32, word[2..], if (bits) 2 else 16) catch unreachable;
            if (pattern >= @as(u32, 1) << @intCast(f.width)) return program.fail("BAD OPERAND {s}", .{word});
            return pattern;
        }
        return (try program.parseReal(word)).encoded(f, .RNE).pattern;
    }
    fn operands(program: *Program, f: MiniFormat, words: []const []const u8, destination: []u32) Error!void {
        for (words, destination) |word, *pattern| pattern.* = try program.operand(f, word);
    }
    fn summary(program: *Program, f: MiniFormat, mode: Mode, patterns: []const u32, result: Result) Writer.Error!void {
        var terms: [20]Exact = undefined;
        for (patterns, 0..) |pattern, i| terms[i] = f.exact(pattern);
        const exact = Exact.sum(terms[0..patterns.len], mode);
        try line(program.out, "RESULT {f}", .{f.resultText(result)});
        try line(program.out, "EXACT {f}", .{exact.decimal(false)});
        try line(program.out, "ROUNDED {f}", .{f.resultText(f.round(exact, mode))});
        try line(program.out, "DIFF {f}", .{Difference{ .f = f, .pattern = result.pattern, .exact = exact }});
    }
    fn summation(program: *Program, command: Command, f: MiniFormat, mode: Mode, patterns: []const u32) Error!void {
        for (patterns) |pattern| if (!f.isFinite(pattern)) return program.fail("NOT FINITE", .{});
        try line(program.out, "{s} {f} {s} count={d}", .{ @tagName(command), f.name, @tagName(mode), patterns.len });
        var sum = patterns[0];
        var compensation: u32 = 0;
        var flags: u8 = 0;
        for (patterns[1..], 1..) |pattern, i| {
            if (command == .SUM) {
                const added = calculate(f, .ADD, mode, &.{ sum, pattern });
                sum = added.pattern;
                flags |= added.flags;
                try line(program.out, "PARTIAL {d} {f}", .{ i + 1, f.resultText(added) });
            } else {
                const y = calculate(f, .SUB, mode, &.{ pattern, compensation });
                const t = calculate(f, .ADD, mode, &.{ sum, y.pattern });
                const d = calculate(f, .SUB, mode, &.{ t.pattern, sum });
                const c = calculate(f, .SUB, mode, &.{ d.pattern, y.pattern });
                sum = t.pattern;
                compensation = c.pattern;
                const step = y.flags | t.flags | d.flags | c.flags;
                flags |= step;
                try line(program.out, "KSTEP {d} sum={f} comp={f} {f}", .{ i + 1, f.valueText(sum), f.valueText(compensation), Flags{ .bits = step } });
            }
        }
        try program.summary(f, mode, patterns, .{ .pattern = sum, .flags = flags });
    }
    fn dot(program: *Program, f: MiniFormat, mode: Mode, a: []const u32, b: []const u32) Error!void {
        if (a.len != b.len) return program.fail("LENGTH MISMATCH", .{});
        for (a) |pattern| if (!f.isFinite(pattern)) return program.fail("NOT FINITE", .{});
        for (b) |pattern| if (!f.isFinite(pattern)) return program.fail("NOT FINITE", .{});
        var naive = calculate(f, .MUL, mode, &.{ a[0], b[0] });
        var chained = naive;
        for (1..a.len) |i| {
            const product = calculate(f, .MUL, mode, &.{ a[i], b[i] });
            const added = calculate(f, .ADD, mode, &.{ naive.pattern, product.pattern });
            naive = .{ .pattern = added.pattern, .flags = naive.flags | product.flags | added.flags };
            const fused = calculate(f, .FMA, mode, &.{ a[i], b[i], chained.pattern });
            chained = .{ .pattern = fused.pattern, .flags = chained.flags | fused.flags };
        }
        var terms: [10]Exact = undefined;
        for (a, b, 0..) |x, y, i| terms[i] = Exact.product(f.exact(x), f.exact(y));
        const exact = Exact.sum(terms[0..a.len], mode);
        try line(program.out, "DOT {f} {s} n={d}", .{ f.name, @tagName(mode), a.len });
        try line(program.out, "NAIVE {f}", .{f.resultText(naive)});
        try line(program.out, "CHAINED {f}", .{f.resultText(chained)});
        try line(program.out, "EXACT {f}", .{exact.decimal(false)});
        try line(program.out, "FUSED {f}", .{f.resultText(f.round(exact, mode))});
        try line(program.out, "DIFF naive={f} chained={f}", .{ Difference{ .f = f, .pattern = naive.pattern, .exact = exact }, Difference{ .f = f, .pattern = chained.pattern, .exact = exact } });
    }
    fn table(program: *Program, f: MiniFormat) Error!void {
        if (f.width > 8) return program.fail("TABLE TOO LARGE", .{});
        const count = f.infinity;
        try line(program.out, "TABLE {f} count={d}", .{ f.name, count });
        var pattern: u32 = 0;
        while (pattern < count) : (pattern += 1) {
            try program.out.print("ENTRY {d} {f} gap=", .{ pattern, f.patternText(pattern) });
            if (pattern == count - 1) try line(program.out, "-", .{}) else {
                const gap = Exact.sum(&.{ f.exact(pattern + 1), f.exact(pattern).negated() }, .RNE);
                try line(program.out, "{f}", .{gap.decimal(false)});
            }
        }
        try line(program.out, "MAX {f}", .{f.patternText(f.infinity - 1)});
        try line(program.out, "MINNORMAL {f}", .{f.patternText(f.hidden)});
        try line(program.out, "MINSUBNORMAL {f}", .{f.patternText(1)});
        const epsilon: Exact = .{ .n = 1, .exponent = -@as(i32, f.m) };
        try line(program.out, "EPSILON {f}", .{epsilon.decimal(false)});
        try line(program.out, "PATTERNS finite={d} infinite=2 nan={d} total={d}", .{ 2 * count, 2 * (f.hidden - 1), @as(u32, 1) << @intCast(f.width) });
    }

    fn execute(program: *Program, words: []const []const u8) Error!void {
        const command = std.meta.stringToEnum(Command, words[0]).?;
        const out = program.out;
        if (command == .FORMAT) {
            const name = words[1];
            const e = parseNumber(words[2]);
            const m = parseNumber(words[3]);
            if (program.findFormat(name) != null) return program.fail("FORMAT EXISTS {s}", .{name});
            if (e < 2 or e > 5 or m < 1 or m > 10) return program.fail("BAD FORMAT", .{});
            const f: MiniFormat = .init(name, @intCast(e), @intCast(m));
            program.formats[program.format_count] = f;
            program.format_count += 1;
            try line(out, "FORMAT {f} e={d} m={d} bits={d} bias={d} emin={d} emax={d}", .{ f.name, e, m, f.width, f.bias, f.emin, f.emax });
            return;
        }
        const f = try program.getFormat(words[1]);
        switch (command) {
            .ENCODE => {
                const input = try program.parseReal(words[2]);
                const mode = try program.parseMode(words, 3);
                try line(out, "ENCODE {f} {s} {f} {f}", .{ f.name, @tagName(mode), input, f.resultText(input.encoded(f, mode)) });
            },
            .CONVERT => {
                const g = try program.getFormat(words[2]);
                const a = try program.operand(f, words[3]);
                const mode = try program.parseMode(words, 4);
                const result: Result = if (f.isNaN(a)) .{ .pattern = g.nan(), .flags = if (f.isSignaling(a)) Flags.invalid else 0 }
                    else if (f.isInfinity(a)) .{ .pattern = g.inf(f.fields(a).negative) } else g.round(f.exact(a), mode);
                try line(out, "CONVERT {f} {f} {s} {f}", .{ f.name, g.name, @tagName(mode), g.resultText(result) });
            },
            .ADD, .SUB, .MUL, .DIV, .SQRT, .FMA => {
                const operation = command.operation().?;
                const count: usize = if (operation == .SQRT) 1 else if (operation == .FMA) 3 else 2;
                var patterns: [3]u32 = undefined;
                try program.operands(f, words[2 .. 2 + count], patterns[0..count]);
                const mode = try program.parseMode(words, 2 + count);
                try line(out, "{s} {f} {s} {f}", .{ @tagName(command), f.name, @tagName(mode), f.resultText(calculate(f, operation, mode, patterns[0..count])) });
            },
            .SUM, .KAHAN => {
                const mode = try program.parseMode(words, 2);
                var patterns: [20]u32 = undefined;
                const count = words.len - 3;
                try program.operands(f, words[3..], patterns[0..count]);
                try program.summation(command, f, mode, patterns[0..count]);
            },
            .DOT => {
                const mode = try program.parseMode(words, 2);
                var separator: usize = 3;
                while (!equal(words[separator], "|")) separator += 1;
                var a: [10]u32 = undefined;
                var b: [10]u32 = undefined;
                const a_count = separator - 3;
                const b_count = words.len - separator - 1;
                try program.operands(f, words[3..separator], a[0..a_count]);
                try program.operands(f, words[separator + 1 ..], b[0..b_count]);
                try program.dot(f, mode, a[0..a_count], b[0..b_count]);
            },
            .TABLE => try program.table(f),
            .DECODE => {
                const a = try program.operand(f, words[2]);
                const parts = f.fields(a);
                const classification: []const u8 = if (f.isNaN(a)) (if (f.isSignaling(a)) "snan" else "qnan")
                    else if (f.isInfinity(a)) "infinity" else if (f.isZero(a)) "zero" else if (parts.exponent == 0) "subnormal" else "normal";
                try line(out, "DECODE {f} {f} {f} {s} sign={d}", .{ f.name, f.bits(a), f.hex(a), classification, @intFromBool(parts.negative) });
                try out.print("FIELDS exponent={d} fraction={d}", .{ parts.exponent, parts.fraction });
                if (f.isFinite(a)) {
                    try line(out, " unbiased={d} significand={d}.{f}", .{ parts.q + f.m, @intFromBool(parts.exponent != 0), Binary{ .value = parts.fraction, .width = f.m } });
                    try line(out, "VALUE {f} {f}", .{ f.exact(a), f.valueText(a) });
                } else if (f.isNaN(a)) try line(out, " payload={d}", .{parts.fraction % (f.hidden / 2)}) else try out.writeByte('\n');
            },
            .COMPARE => {
                const a = try program.operand(f, words[2]);
                const b = try program.operand(f, words[3]);
                const total_order = compareSigned(orderKey(f, a), orderKey(f, b));
                const numeric = if (f.isNaN(a) or f.isNaN(b)) "UN" else if (f.isZero(a) and f.isZero(b)) "EQ" else @tagName(total_order);
                const flags: u8 = if (f.isSignaling(a) or f.isSignaling(b)) Flags.invalid else 0;
                try line(out, "COMPARE {f} {f} {f} {s} total={s} {f}", .{ f.name, f.hex(a), f.hex(b), numeric, @tagName(total_order), Flags{ .bits = flags } });
            },
            .TOINT => {
                const a = try program.operand(f, words[2]);
                const kind = std.meta.stringToEnum(IntegerType, words[3]) orelse return program.fail("BAD TYPE {s}", .{words[3]});
                const mode = try program.parseMode(words, 4);
                const range: struct { minimum: i64, maximum: i64 } = switch (kind) {
                    .I8 => .{ .minimum = -128, .maximum = 127 }, .U8 => .{ .minimum = 0, .maximum = 255 },
                    .I16 => .{ .minimum = -32768, .maximum = 32767 }, .U16 => .{ .minimum = 0, .maximum = 65535 },
                    .I32 => .{ .minimum = -2147483648, .maximum = 2147483647 }, .U32 => .{ .minimum = 0, .maximum = 4294967295 },
                };
                try out.print("TOINT {f} {s} {s} ", .{ f.name, @tagName(kind), @tagName(mode) });
                if (!f.isFinite(a)) try line(out, "invalid flags=invalid", .{}) else {
                    const units = roundUnits(f.exact(a), 0, mode, false);
                    const whole: i64 = @intCast(units.whole);
                    const integer = if (f.fields(a).negative) -whole else whole;
                    if (integer < range.minimum or integer > range.maximum) try line(out, "invalid flags=invalid", .{})
                    else try line(out, "{d} {f}", .{ integer, Flags{ .bits = if (units.inexact) Flags.inexact else 0 } });
                }
            },
            .NEXTUP, .NEXTDOWN, .ULP => {
                const a = try program.operand(f, words[2]);
                const result: Result = if (f.isNaN(a)) .{ .pattern = f.nan(), .flags = if (f.isSignaling(a)) Flags.invalid else 0 }
                    else .{ .pattern = switch (command) {
                        .NEXTUP => nextUp(f, a), .NEXTDOWN => f.flip(nextUp(f, f.flip(a))),
                        .ULP => if (f.isInfinity(a)) f.infinity else f.round(.{ .n = 1, .exponent = f.fields(a).q }, .RNE).pattern,
                        else => unreachable,
                    } };
                try line(out, "{s} {f} {f}", .{ @tagName(command), f.name, f.resultText(result) });
            },
            .FORMAT => unreachable,
        }
    }
};

fn readWords(gpa: Allocator, input: *std.Io.Reader) ![]const []const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    var words: std.ArrayList([]const u8) = .empty;
    var parts = std.mem.tokenizeAny(u8, text, " \r");
    while (parts.next()) |word| try words.append(gpa, word);
    return try words.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    var program: Program = .init(scratch.allocator(), &output.interface);
    const count = try std.fmt.parseInt(usize, (try readWords(scratch.allocator(), &input.interface))[0], 10);
    for (0..count) |_| {
        _ = scratch.reset(.retain_capacity);
        const words = try readWords(scratch.allocator(), &input.interface);
        var response: Writer.Allocating = .init(scratch.allocator());
        defer response.deinit();
        program.out = &response.writer;
        program.execute(words) catch |err| {
            if (err != error.BadCommand) return err;
            try output.interface.print("ERROR {s}\n", .{program.error_message});
            continue;
        };
        try output.interface.writeAll(response.written());
    }
    try output.interface.flush();
}
