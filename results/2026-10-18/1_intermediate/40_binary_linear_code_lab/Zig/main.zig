const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Error = Allocator.Error || Writer.Error || error{Invalid};
const Word = u32;
const Verb = enum {
    GEN, PCHECK, HAMMING, SIMPLEX, REPETITION, PARITY, RM, CYCLIC, DUAL, EXTEND,
    PUNCTURE, SHORTEN, AUGMENT, EXPURGATE, PERMUTE, DIRECTSUM, UUV, PRODUCT,
    LIST, DELETE, SHOW, INFO, SYSTEMATIC, WEIGHTS, COVERING, BURST, TRELLIS,
    STDARRAY, EQUAL, ENCODE, SYNDROME, DECODE, BOUNDED, COSET, ERASURE, INTERLEAVE,
    CRC, CRCCHECK, FACTOR, MACWILLIAMS, BOUNDS,
};
const Argument = enum { name, code, number, bits, erasure };
const Format = struct { types: []const Argument, repeated: ?Argument = null, maximum: usize = 0 };

fn equal(a: []const u8, b: []const u8) bool { return std.mem.eql(u8, a, b); }
fn one(shift: usize) Word { return @as(Word, 1) << @intCast(shift); }
fn bit(word: Word, length: usize, column: usize) bool { return word & one(length - column - 1) != 0; }
fn weight(word: Word) usize { return @popCount(word); }
fn degree(word: Word) usize { return 31 - @as(usize, @clz(word)); }
fn integer(text: []const u8) usize { return std.fmt.parseInt(usize, text, 10) catch unreachable; }
fn binary(text: []const u8) Word { return std.fmt.parseInt(Word, text, 2) catch unreachable; }
fn yes(value: bool) []const u8 { return if (value) "yes" else "no"; }
fn line(out: *Writer, comptime fmt: []const u8, args: anytype) Writer.Error!void { try out.print(fmt ++ "\n", args); }
fn lessWord(_: void, a: Word, b: Word) bool { return a < b; }

const Bits = struct {
    word: Word,
    length: usize,
    pub fn format(value: Bits, out: *Writer) Writer.Error!void {
        for (0..value.length) |column| try out.writeByte(if (bit(value.word, value.length, column)) '1' else '0');
    }
};
fn bits(word: Word, length: usize) Bits { return .{ .word = word, .length = length }; }

const Name = struct {
    bytes: [8]u8 = undefined,
    len: usize = 0,
    fn init(text: []const u8) Name {
        var result: Name = .{ .len = text.len };
        @memcpy(result.bytes[0..text.len], text);
        return result;
    }
    fn slice(value: *const Name) []const u8 { return value.bytes[0..value.len]; }
    pub fn format(value: Name, out: *Writer) Writer.Error!void { try out.writeAll(value.slice()); }
};
const Matrix = struct {
    rows: [30]Word = undefined,
    len: usize = 0,
    fn add(matrix: *Matrix, row: Word) void { matrix.rows[matrix.len] = row; matrix.len += 1; }
    fn slice(matrix: *const Matrix) []const Word { return matrix.rows[0..matrix.len]; }
};
const Echelon = struct { rows: Matrix, columns: [30]usize };
const Division = struct { quotient: Word, remainder: Word };

fn divide(original: Word, divisor: Word) Division {
    var dividend = original;
    var quotient: Word = 0;
    const d = degree(divisor);
    while (dividend != 0 and degree(dividend) >= d) {
        const shift = degree(dividend) - d;
        quotient ^= one(shift);
        dividend ^= divisor << @intCast(shift);
    }
    return .{ .quotient = quotient, .remainder = dividend };
}
fn basis(rows: []const Word, length: usize) Matrix {
    var pivots: [30]Word = @splat(0);
    var result: Matrix = .{};
    for (rows) |original| {
        var row = original;
        for (0..length) |column| {
            if (!bit(row, length, column)) continue;
            if (pivots[column] != 0) {
                row ^= pivots[column];
            } else {
                pivots[column] = row;
                result.add(original);
                break;
            }
        }
    }
    return result;
}
fn rref(original: Matrix, length: usize) Echelon {
    var rows = original;
    var columns: [30]usize = undefined;
    var count: usize = 0;
    for (0..length) |column| {
        var found = count;
        while (found < rows.len and !bit(rows.rows[found], length, column)) : (found += 1) {}
        if (found == rows.len) continue;
        const old = rows.rows[count];
        rows.rows[count] = rows.rows[found];
        rows.rows[found] = old;
        for (0..rows.len) |row| if (row != count and bit(rows.rows[row], length, column)) { rows.rows[row] ^= rows.rows[count]; };
        columns[count] = column;
        count += 1;
    }
    rows.len = count;
    return .{ .rows = rows, .columns = columns };
}
fn nullspace(original: Matrix, length: usize) Matrix {
    const reduced = rref(original, length);
    var result: Matrix = .{};
    for (0..length) |column| {
        var is_pivot = false;
        for (reduced.columns[0..reduced.rows.len]) |pivot| if (pivot == column) { is_pivot = true; break; };
        if (is_pivot) continue;
        var word = one(length - column - 1);
        for (reduced.rows.slice(), 0..) |row, index| {
            if (bit(row, length, column)) word |= one(length - reduced.columns[index] - 1);
        }
        result.add(word);
    }
    return result;
}
fn spanWord(rows: Matrix, message: usize) Word {
    var result: Word = 0;
    for (rows.slice(), 0..) |row, index| if (message & (@as(usize, 1) << @intCast(index)) != 0) { result ^= row; };
    return result;
}
fn distribution(words: []const Word) [25]usize {
    var result: [25]usize = @splat(0);
    for (words) |word| result[weight(word)] += 1;
    return result;
}
fn weightList(out: *Writer, counts: []const usize) Writer.Error!void {
    var first = true;
    for (counts, 0..) |count, index| {
        if (count == 0) continue;
        if (!first) try out.writeByte(' ');
        try out.print("{d}:{d}", .{ index, count });
        first = false;
    }
}
fn removeBit(word: Word, length: usize, column: usize) Word {
    const low = length - column - 1;
    return ((word >> @intCast(low + 1)) << @intCast(low)) | (word & (one(low) - 1));
}
fn reedMuller(order: usize, variables: usize) Matrix {
    const length = @as(usize, 1) << @intCast(variables);
    var result: Matrix = .{};
    if (order == 0) {
        result.add(one(length) - 1);
        return result;
    }
    const first = reedMuller(@min(order, variables - 1), variables - 1);
    for (first.slice()) |row| result.add((row << @intCast(length / 2)) | row);
    const second = reedMuller(order - 1, variables - 1);
    for (second.slice()) |row| result.add(row);
    return result;
}

const binomials = blk: {
    @setEvalBranchQuota(5000);
    var table: [25][25]i64 = @splat(@splat(0));
    for (0..25) |n| {
        table[n][0] = 1;
        table[n][n] = 1;
        if (n >= 2) for (1..n) |k| { table[n][k] = table[n - 1][k - 1] + table[n - 1][k]; };
    }
    break :blk table;
};
fn binomial(n: usize, k: usize) i64 { return if (k > n) 0 else binomials[n][k]; }
fn volume(n: usize, t: usize) i64 {
    var sum: i64 = 0;
    for (binomials[n][0 .. t + 1]) |value| sum += value;
    return sum;
}
fn gcd(first: i64, second: i64) i64 {
    var a: i64 = @intCast(@abs(first));
    var b: i64 = @intCast(@abs(second));
    while (b != 0) {
        const remainder = @mod(a, b);
        a = b;
        b = remainder;
    }
    return a;
}

const Decoded = struct { word: Word, message: Word, err: Word };
const Code = struct {
    n: usize,
    g: Matrix,
    h: Matrix,
    polynomial: ?Word,
    encoded: []const Word = &.{},
    words: []const Word = &.{},
    cached_leaders: ?[]const Word = null,

    fn k(code: *const Code) usize { return code.g.len; }
    fn encoder(code: *const Code) []const u8 { return if (code.polynomial == null) "matrix" else "polynomial"; }
    fn create(gpa: Allocator, n: usize, g: Matrix, h: ?Matrix, polynomial: ?Word) Allocator.Error!*Code {
        const code = try gpa.create(Code);
        code.* = .{ .n = n, .g = g, .h = h orelse nullspace(g, n), .polynomial = polynomial };
        const encoded = try gpa.alloc(Word, one(g.len));
        for (encoded, 0..) |*word, message| word.* = code.encode(@intCast(message));
        code.encoded = encoded;
        const words = try gpa.dupe(Word, encoded);
        std.sort.heap(Word, words, {}, lessWord);
        code.words = words;
        return code;
    }
    fn encode(code: *const Code, message: Word) Word {
        if (code.polynomial) |polynomial| {
            const shifted = message << @intCast(code.n - code.k());
            return shifted | divide(shifted, polynomial).remainder;
        }
        var word: Word = 0;
        for (code.g.slice(), 0..) |row, index| if (bit(message, code.k(), index)) { word ^= row; };
        return word;
    }
    fn syndrome(code: *const Code, word: Word) usize {
        var result: usize = 0;
        for (code.h.slice()) |row| result = (result << 1) | (weight(row & word) % 2);
        return result;
    }
    fn messageFor(code: *const Code, word: Word) Word {
        for (code.encoded, 0..) |value, index| if (value == word) return @intCast(index);
        unreachable;
    }
    fn leaders(code: *Code, gpa: Allocator) Allocator.Error![]const Word {
        if (code.cached_leaders) |values| return values;
        const missing = ~@as(Word, 0);
        const result = try gpa.alloc(Word, one(code.n - code.k()));
        @memset(result, missing);
        result[0] = 0;
        var remaining = result.len - 1;
        var count: usize = 1;
        while (remaining > 0) : (count += 1) {
            var word = one(count) - 1;
            while (word < one(code.n)) {
                const s = code.syndrome(word);
                if (result[s] == missing) {
                    result[s] = word;
                    remaining -= 1;
                    if (remaining == 0) break;
                }
                const lowest = word & (0 -% word);
                const next = word + lowest;
                word = next | (((next ^ word) >> 2) / lowest);
            }
        }
        code.cached_leaders = result;
        return result;
    }
    fn decode(code: *Code, gpa: Allocator, received: Word) Allocator.Error!Decoded {
        const table = try code.leaders(gpa);
        const err = table[code.syndrome(received)];
        const word = received ^ err;
        return .{ .word = word, .message = code.messageFor(word), .err = err };
    }
};
const Entry = struct { name: Name, code: *Code };
const Laboratory = struct {
    gpa: Allocator,
    codes: std.ArrayList(Entry) = .empty,
    fn find(lab: *const Laboratory, name: []const u8) ?usize {
        for (lab.codes.items, 0..) |entry, index| if (equal(entry.name.slice(), name)) return index;
        return null;
    }
    fn get(lab: *const Laboratory, name: []const u8) *Code { return lab.codes.items[lab.find(name).?].code; }
};

fn formatOf(verb: Verb) Format {
    return switch (verb) {
        .GEN, .PCHECK => .{ .types = &.{.name}, .repeated = .bits, .maximum = 24 },
        .HAMMING, .SIMPLEX, .REPETITION, .PARITY => .{ .types = &.{ .name, .number } },
        .RM => .{ .types = &.{ .name, .number, .number } },
        .CYCLIC => .{ .types = &.{ .name, .number, .bits } },
        .DUAL, .EXTEND, .AUGMENT, .EXPURGATE => .{ .types = &.{ .name, .code } },
        .PUNCTURE, .SHORTEN => .{ .types = &.{ .name, .code, .number } },
        .PERMUTE => .{ .types = &.{ .name, .code }, .repeated = .number, .maximum = 24 },
        .DIRECTSUM, .UUV, .PRODUCT => .{ .types = &.{ .name, .code, .code } },
        .LIST => .{ .types = &.{} },
        .DELETE, .SHOW, .INFO, .SYSTEMATIC, .WEIGHTS, .COVERING, .BURST, .TRELLIS, .STDARRAY => .{ .types = &.{.code} },
        .EQUAL => .{ .types = &.{ .code, .code } },
        .ENCODE, .SYNDROME, .DECODE, .COSET => .{ .types = &.{ .code, .bits } },
        .BOUNDED => .{ .types = &.{ .code, .number, .bits } },
        .ERASURE => .{ .types = &.{ .code, .erasure } },
        .INTERLEAVE => .{ .types = &.{ .code, .number, .number }, .repeated = .bits, .maximum = 8 },
        .CRC, .CRCCHECK => .{ .types = &.{ .bits, .bits } },
        .FACTOR => .{ .types = &.{.number} },
        .MACWILLIAMS => .{ .types = &.{.number}, .repeated = .number, .maximum = 25 },
        .BOUNDS => .{ .types = &.{ .number, .number } },
    };
}
fn letter(character: u8) bool { return (character >= 'A' and character <= 'Z') or (character >= 'a' and character <= 'z'); }
fn valid(text: []const u8, kind: Argument) bool {
    if (text.len == 0) return false;
    switch (kind) {
        .name, .code => {
            if (text.len > 8 or !letter(text[0])) return false;
            for (text) |character| if (!letter(character) and (character < '0' or character > '9')) return false;
        },
        .number => {
            if (text.len > 4 or (text.len > 1 and text[0] == '0')) return false;
            for (text) |character| if (character < '0' or character > '9') return false;
        },
        .bits, .erasure => {
            if (text.len > 30) return false;
            for (text) |character| if (character != '0' and character != '1' and !(kind == .erasure and character == '?')) return false;
        },
    }
    return true;
}

const Session = struct {
    lab: *Laboratory,
    gpa: Allocator,
    out: *Writer,
    problem: []const u8 = "",
    fn fail(session: *Session, comptime fmt: []const u8, args: anytype) Error {
        session.problem = try std.fmt.allocPrint(session.gpa, fmt, args);
        return error.Invalid;
    }
    fn dimension(session: *Session, n: usize, k: usize) Error!void {
        if (k < 1 or k > 12 or n <= k or n - k > 12) return session.fail("bad dimension {d} {d}", .{ n, k });
    }
    fn parse(session: *Session, words: []const []const u8) Error!Verb {
        const verb = std.meta.stringToEnum(Verb, words[0]) orelse return session.fail("unknown command {s}", .{words[0]});
        const spec = formatOf(verb);
        const args = words[1..];
        if (args.len < spec.types.len) return session.fail("bad arguments", .{});
        const extra = args.len - spec.types.len;
        if (if (spec.repeated == null) extra != 0 else extra < 1 or extra > spec.maximum) return session.fail("bad arguments", .{});
        for (args, 0..) |word, index| {
            const kind = if (index < spec.types.len) spec.types[index] else spec.repeated.?;
            if (!valid(word, kind)) return session.fail("bad arguments", .{});
        }
        for (spec.types, 0..) |kind, index| {
            if (kind == .code and session.lab.find(args[index]) == null) return session.fail("no code {s}", .{args[index]});
        }
        return verb;
    }
    fn define(session: *Session, verb: Verb, args: []const []const u8) Error!void {
        const lab = session.lab;
        const name = args[0];
        var n: usize = 0;
        var g: Matrix = .{};
        var h: ?Matrix = null;
        var polynomial: ?Word = null;
        switch (verb) {
            .GEN, .PCHECK => {
                n = args[1].len;
                var input: Matrix = .{};
                for (args[1..]) |text| {
                    if (text.len != n) return session.fail("bad length", .{});
                    input.add(binary(text));
                }
                const rows = basis(input.slice(), n);
                if (verb == .GEN) g = rows else {
                    h = rows;
                    g = nullspace(rows, n);
                }
            },
            .HAMMING, .SIMPLEX => {
                const r = integer(args[1]);
                if (r < 2 or r > 4) return session.fail("bad parameter", .{});
                n = one(r) - 1;
                var rows: Matrix = .{};
                for (0..r) |_| rows.add(0);
                for (1 .. n + 1) |column| {
                    for (0..r) |row| rows.rows[row] = (rows.rows[row] << 1) | @intFromBool(bit(@intCast(column), r, row));
                }
                if (verb == .HAMMING) {
                    h = rows;
                    g = nullspace(rows, n);
                } else g = rows;
            },
            .REPETITION, .PARITY => {
                n = integer(args[1]);
                if (n < 2 or n > 24) return session.fail("bad parameter", .{});
                if (verb == .REPETITION) g.add(one(n) - 1) else {
                    for (0 .. n - 1) |row| g.add(one(n - row - 1) | 1);
                }
            },
            .RM => {
                const order = integer(args[1]);
                const variables = integer(args[2]);
                if (variables < 1 or variables > 4 or order > variables) return session.fail("bad parameter", .{});
                n = one(variables);
                g = reedMuller(order, variables);
            },
            .CYCLIC => {
                n = integer(args[1]);
                const text = args[2];
                if (n < 2 or n > 24 or text[0] == '0' or text.len < 2 or text.len > n) return session.fail("bad parameter", .{});
                const p = binary(text);
                if (divide(one(n) | 1, p).remainder != 0) return session.fail("not a divisor", .{});
                const d = text.len - 1;
                const k = n - d;
                try session.dimension(n, k);
                polynomial = p;
                for (0..k) |row| g.add(p << @intCast(k - row - 1));
                var rows: Matrix = .{};
                for (0..d) |_| rows.add(0);
                for (0..n) |column| {
                    const remainder = divide(one(n - column - 1), p).remainder;
                    for (0..d) |row| rows.rows[row] = (rows.rows[row] << 1) | @intFromBool(bit(remainder, d, row));
                }
                h = rows;
            },
            .DUAL => {
                const a = lab.get(args[1]);
                n = a.n;
                g = a.h;
                h = a.g;
            },
            .EXTEND => {
                const a = lab.get(args[1]);
                n = a.n + 1;
                for (a.g.slice()) |row| g.add((row << 1) | @as(Word, @intCast(weight(row) % 2)));
            },
            .PUNCTURE, .SHORTEN => {
                const a = lab.get(args[1]);
                const position = integer(args[2]);
                if (position < 1 or position > a.n) return session.fail("bad position", .{});
                const column = position - 1;
                var rows = a.g;
                if (verb == .SHORTEN) {
                    var pivot: ?usize = null;
                    for (rows.slice(), 0..) |row, index| if (bit(row, a.n, column)) { pivot = index; break; };
                    if (pivot) |index| {
                        var kept: Matrix = .{};
                        const z = rows.rows[index];
                        for (rows.slice(), 0..) |row, i| if (i != index) { kept.add(if (bit(row, a.n, column)) row ^ z else row); };
                        rows = kept;
                    }
                }
                n = a.n - 1;
                for (rows.slice()) |row| g.add(removeBit(row, a.n, column));
                if (verb == .PUNCTURE) g = basis(g.slice(), n);
            },
            .AUGMENT => {
                const a = lab.get(args[1]);
                n = a.n;
                var rows = a.g;
                rows.add(one(n) - 1);
                g = basis(rows.slice(), n);
            },
            .EXPURGATE => {
                const a = lab.get(args[1]);
                n = a.n;
                var pivot: ?usize = null;
                for (a.g.slice(), 0..) |row, index| if (weight(row) % 2 == 1) { pivot = index; break; };
                if (pivot) |index| {
                    const z = a.g.rows[index];
                    for (a.g.slice(), 0..) |row, i| if (i != index) { g.add(if (weight(row) % 2 == 1) row ^ z else row); };
                } else g = a.g;
            },
            .PERMUTE => {
                const a = lab.get(args[1]);
                n = a.n;
                if (args.len - 2 != n) return session.fail("bad permutation", .{});
                var seen: [24]bool = @splat(false);
                var order: [24]usize = undefined;
                for (args[2..], 0..) |text, index| {
                    const position = integer(text);
                    if (position < 1 or position > n or seen[position - 1]) return session.fail("bad permutation", .{});
                    seen[position - 1] = true;
                    order[index] = position - 1;
                }
                for (a.g.slice()) |row| {
                    var word: Word = 0;
                    for (order[0..n]) |column| word = (word << 1) | @intFromBool(bit(row, n, column));
                    g.add(word);
                }
            },
            .DIRECTSUM, .UUV, .PRODUCT => {
                const a = lab.get(args[1]);
                const b = lab.get(args[2]);
                if (verb == .UUV and a.n != b.n) return session.fail("bad length", .{});
                n = if (verb == .PRODUCT) a.n * b.n else a.n + b.n;
                try session.dimension(n, if (verb == .PRODUCT) a.k() * b.k() else a.k() + b.k());
                if (verb == .PRODUCT) {
                    for (a.g.slice()) |x| for (b.g.slice()) |y| {
                        var row: Word = 0;
                        for (0..a.n) |column| row = (row << @intCast(b.n)) | (if (bit(x, a.n, column)) y else 0);
                        g.add(row);
                    };
                } else {
                    for (a.g.slice()) |row| g.add((row << @intCast(b.n)) | (if (verb == .UUV) row else 0));
                    for (b.g.slice()) |row| g.add(row);
                }
            },
            else => unreachable,
        }
        try session.dimension(n, g.len);
        const code = try Code.create(lab.gpa, n, g, h, polynomial);
        const previous = lab.find(name);
        if (previous) |index| lab.codes.items[index].code = code else {
            try lab.codes.append(lab.gpa, .{ .name = Name.init(name), .code = code });
        }
        try line(session.out, "{s} {s} n {d} k {d}", .{ if (previous != null) "redefined" else "defined", name, n, code.k() });
    }
    fn systematic(session: *Session, name: []const u8, code: *const Code) Error!void {
        const n = code.n;
        const k = code.k();
        var rows = code.g;
        var order: [24]usize = undefined;
        for (0..n) |column| order[column] = column + 1;
        for (0..k) |pivot| {
            var column = pivot;
            var found = pivot;
            while (true) {
                found = pivot;
                while (found < k and !bit(rows.rows[found], n, column)) : (found += 1) {}
                if (found < k) break;
                column += 1;
            }
            if (column != pivot) {
                const mask = one(n - column - 1) | one(n - pivot - 1);
                for (rows.rows[0..k]) |*row| if (bit(row.*, n, column) != bit(row.*, n, pivot)) { row.* ^= mask; };
                const old = order[pivot];
                order[pivot] = order[column];
                order[column] = old;
            }
            const old = rows.rows[pivot];
            rows.rows[pivot] = rows.rows[found];
            rows.rows[found] = old;
            for (0..k) |row| if (row != pivot and bit(rows.rows[row], n, pivot)) { rows.rows[row] ^= rows.rows[pivot]; };
        }
        const out = session.out;
        try out.print("systematic {s} perm", .{name});
        for (order[0..n]) |column| try out.print(" {d}", .{column});
        try out.writeByte('\n');
        for (rows.slice()) |row| try line(out, "G {f}", .{bits(row, n)});
        for (k..n) |column| {
            var row: Word = 0;
            for (rows.slice()) |value| row = (row << 1) | @intFromBool(bit(value, n, column));
            row = (row << @intCast(n - k)) | one(n - column - 1);
            try line(out, "H {f}", .{bits(row, n)});
        }
    }
    fn burst(session: *Session, name: []const u8, code: *const Code) Error!void {
        var detect = code.n;
        for (code.words[1..]) |word| detect = @min(detect, degree(word) - @as(usize, @ctz(word)));
        var seen: [4096]bool = @splat(false);
        seen[0] = true;
        for (1 .. code.n + 1) |length| {
            for (0 .. code.n - length + 1) |start| {
                const limit: usize = if (length == 1) 1 else one(length - 2);
                for (0..limit) |middle| {
                    const pattern: Word = if (length == 1) 1 else one(length - 1) | (@as(Word, @intCast(middle)) << 1) | 1;
                    const s = code.syndrome(pattern << @intCast(code.n - start - length));
                    if (seen[s]) return line(session.out, "burst {s} detect {d} correct {d}", .{ name, detect, length - 1 });
                    seen[s] = true;
                }
            }
        }
        unreachable;
    }
    fn decodedText(session: *Session, code: *const Code, value: Decoded) Error!void {
        try session.out.print("codeword {f} message {f} error {f} weight {d}", .{
            bits(value.word, code.n), bits(value.message, code.k()), bits(value.err, code.n), weight(value.err),
        });
    }
    fn interleave(session: *Session, name: []const u8, code: *Code, args: []const []const u8) Error!void {
        const messages = args[3..];
        const depth = messages.len;
        const start = integer(args[1]);
        const length = integer(args[2]);
        for (messages) |message| if (message.len != code.k()) return session.fail("bad length", .{});
        if (start < 1 or length < 1 or start + length - 1 > depth * code.n) return session.fail("bad burst", .{});
        var sent_words: [8]Word = undefined;
        var received_words: [8]Word = @splat(0);
        for (messages, 0..) |message, row| sent_words[row] = code.encode(binary(message));
        var sent: [192]u8 = undefined;
        var received: [192]u8 = undefined;
        for (0..code.n) |column| for (0..depth) |row| {
            const index = column * depth + row;
            const original = bit(sent_words[row], code.n, column);
            const changed = original != (start <= index + 1 and index + 1 < start + length);
            sent[index] = if (original) '1' else '0';
            received[index] = if (changed) '1' else '0';
            received_words[row] = (received_words[row] << 1) | @intFromBool(changed);
        };
        const out = session.out;
        try line(out, "interleave {s} depth {d} burst {d} {d}", .{ name, depth, start, length });
        try line(out, "sent {s}", .{sent[0 .. depth * code.n]});
        try line(out, "recv {s}", .{received[0 .. depth * code.n]});
        var correct: usize = 0;
        for (messages, 0..) |message, row| {
            const decoded = try code.decode(session.lab.gpa, received_words[row]);
            const ok = decoded.message == binary(message);
            correct += @intFromBool(ok);
            try line(out, "row {d} errors {d} corrected {d} message {f} {s}", .{
                row + 1, weight(received_words[row] ^ sent_words[row]), weight(decoded.err),
                bits(decoded.message, code.k()), if (ok) "ok" else "wrong",
            });
        }
        try line(out, "result ok {d} wrong {d}", .{ correct, depth - correct });
    }
    fn independent(session: *Session, verb: Verb, args: []const []const u8) Error!void {
        const out = session.out;
        if (verb == .CRC or verb == .CRCCHECK) {
            const generator = args[0];
            const text = args[1];
            if (generator[0] == '0' or generator.len < 2 or generator.len > 17) return session.fail("bad parameter", .{});
            const d = generator.len - 1;
            if (verb == .CRC and text.len + d > 30) return session.fail("bad length", .{});
            const word = binary(text);
            const remainder = divide(if (verb == .CRC) word << @intCast(d) else word, binary(generator)).remainder;
            if (verb == .CRC) return line(out, "crc remainder {f} frame {s}{f}", .{ bits(remainder, d), text, bits(remainder, d) });
            return line(out, "crccheck {s} remainder {f}", .{ if (remainder == 0) "ok" else "error", bits(remainder, d) });
        }
        const n = integer(args[0]);
        if (verb == .BOUNDS) {
            const d = integer(args[1]);
            if (d < 1 or d > n or n > 24) return session.fail("bad parameter", .{});
            const v = volume(n, (d - 1) / 2);
            var hamming: usize = 0;
            var griesmer: usize = 0;
            var sum: usize = 0;
            for (0 .. n + 1) |k| if (@as(i64, one(k)) * v <= @as(i64, one(n))) { hamming = k; };
            for (1 .. n + 1) |k| {
                const denominator: usize = one(k - 1);
                sum += (d + denominator - 1) / denominator;
                if (sum <= n) griesmer = k;
            }
            return line(out, "bounds n {d} d {d} singleton {d} hamming {d} griesmer {d}", .{ n, d, n - d + 1, hamming, griesmer });
        }
        if (n < 1 or n > 24) return session.fail("bad parameter", .{});
        if (verb == .FACTOR) {
            var remaining = one(n) | 1;
            var candidate: Word = 2;
            var divisors: usize = 1;
            try out.print("factor {d}", .{n});
            while (2 * degree(candidate) <= degree(remaining)) : (candidate += 1) {
                var exponent: usize = 0;
                while (divide(remaining, candidate).remainder == 0) {
                    remaining = divide(remaining, candidate).quotient;
                    exponent += 1;
                }
                if (exponent > 0) {
                    try out.print(" {f}^{d}", .{ bits(candidate, degree(candidate) + 1), exponent });
                    divisors *= exponent + 1;
                }
            }
            if (remaining > 1) {
                try out.print(" {f}^1", .{bits(remaining, degree(remaining) + 1)});
                divisors *= 2;
            }
            return line(out, " divisors {d}", .{divisors});
        }
        if (args.len - 1 != n + 1) return session.fail("bad length", .{});
        if (integer(args[1]) != 1) return session.fail("bad parameter", .{});
        var counts: [25]i64 = undefined;
        var size: i64 = 0;
        for (args[1..], 0..) |text, index| {
            counts[index] = @intCast(integer(text));
            size += counts[index];
        }
        try line(out, "macwilliams n {d} size {d}", .{ n, size });
        try out.writeAll("dual");
        var feasible = size & (size - 1) == 0;
        for (0 .. n + 1) |j| {
            var numerator: i64 = 0;
            for (0 .. n + 1) |x| {
                var krawtchouk: i64 = 0;
                for (0 .. j + 1) |y| {
                    const sign: i64 = if (y % 2 == 0) 1 else -1;
                    krawtchouk += sign * binomial(x, y) * binomial(n - x, j - y);
                }
                numerator += counts[x] * krawtchouk;
            }
            const divisor = gcd(numerator, size);
            const p = @divTrunc(numerator, divisor);
            const q = @divTrunc(size, divisor);
            if (q == 1) try out.print(" {d}", .{p}) else try out.print(" {d}/{d}", .{ p, q });
            if (q != 1 or p < 0) feasible = false;
        }
        try out.writeByte('\n');
        try line(out, "feasible {s}", .{yes(feasible)});
    }
    fn execute(session: *Session, words: []const []const u8) Error!void {
        const verb = try session.parse(words);
        const args = words[1..];
        const lab = session.lab;
        const out = session.out;
        if (@intFromEnum(verb) <= @intFromEnum(Verb.PRODUCT)) return session.define(verb, args);
        switch (verb) {
            .CRC, .CRCCHECK, .FACTOR, .MACWILLIAMS, .BOUNDS => return session.independent(verb, args),
            .LIST => {
                const entries = try session.gpa.dupe(Entry, lab.codes.items);
                std.sort.heap(Entry, entries, {}, struct {
                    fn less(_: void, a: Entry, b: Entry) bool { return std.mem.order(u8, a.name.slice(), b.name.slice()) == .lt; }
                }.less);
                try line(out, "codes {d}", .{entries.len});
                for (entries) |entry| try line(out, "{f} n {d} k {d} encoder {s}", .{ entry.name, entry.code.n, entry.code.k(), entry.code.encoder() });
                return;
            },
            .DELETE => {
                _ = lab.codes.orderedRemove(lab.find(args[0]).?);
                return line(out, "deleted {s}", .{args[0]});
            },
            else => {},
        }
        const name = args[0];
        const code = lab.get(name);
        const n = code.n;
        const k = code.k();
        switch (verb) {
            .SHOW => {
                try line(out, "code {s} n {d} k {d} encoder {s}", .{ name, n, k, code.encoder() });
                if (code.polynomial) |p| try line(out, "poly g {f} h {f}", .{ bits(p, n - k + 1), bits(divide(one(n) | 1, p).quotient, k + 1) });
                for (code.g.slice()) |row| try line(out, "G {f}", .{bits(row, n)});
                for (code.h.slice()) |row| try line(out, "H {f}", .{bits(row, n)});
            },
            .INFO => {
                var distance = n;
                for (code.words[1..]) |word| distance = @min(distance, weight(word));
                const t = (distance - 1) / 2;
                const divisor: usize = @intCast(gcd(@intCast(n), @intCast(k)));
                var cyclic = true;
                for (code.g.slice()) |row| {
                    const rotated = ((row << 1) & (one(n) - 1)) | (row >> @intCast(n - 1));
                    if (code.syndrome(rotated) != 0) cyclic = false;
                }
                try out.print("info {s} n {d} k {d} rate {d}/{d} d {d} t {d} perfect {s} mds {s} cyclic ", .{
                    name, n, k, k / divisor, n / divisor, distance, t,
                    yes(volume(n, t) == @as(i64, one(n - k))), yes(distance == n - k + 1),
                });
                if (cyclic) try line(out, "{f}", .{bits(code.words[1], degree(code.words[1]) + 1)}) else try line(out, "no", .{});
            },
            .SYSTEMATIC => try session.systematic(name, code),
            .WEIGHTS => {
                const a = distribution(code.words);
                var b: [25]usize = @splat(0);
                for (0..one(code.h.len)) |message| b[weight(spanWord(code.h, message))] += 1;
                var orthogonal = true;
                for (code.g.slice()) |x| for (code.g.slice()) |y| {
                    if (weight(x & y) % 2 != 0) orthogonal = false;
                };
                try out.print("weights {s} ", .{name});
                try weightList(out, a[0 .. n + 1]);
                try out.writeByte('\n');
                try out.print("dual {s} ", .{name});
                try weightList(out, b[0 .. n + 1]);
                try out.writeByte('\n');
                try line(out, "duality {s} self-orthogonal {s} self-dual {s} formally-self-dual {s}", .{
                    name, yes(orthogonal), yes(orthogonal and n == 2 * k), yes(std.mem.eql(usize, &a, &b)),
                });
            },
            .COVERING => {
                const counts = distribution(try code.leaders(lab.gpa));
                var radius = n;
                while (counts[radius] == 0) : (radius -= 1) {}
                try out.print("covering {s} radius {d} leaders", .{ name, radius });
                for (counts[0 .. radius + 1], 0..) |count, index| try out.print(" {d}:{d}", .{ index, count });
                try out.writeByte('\n');
            },
            .BURST => try session.burst(name, code),
            .TRELLIS => {
                var profile: [25]usize = undefined;
                var maximum: usize = 0;
                for (0 .. n + 1) |cut| {
                    const right = n - cut;
                    var prefix: Matrix = .{};
                    var suffix: Matrix = .{};
                    for (code.g.slice()) |row| {
                        prefix.add(row >> @intCast(right));
                        suffix.add(row & (one(right) - 1));
                    }
                    profile[cut] = basis(prefix.slice(), cut).len + basis(suffix.slice(), right).len - k;
                    maximum = @max(maximum, profile[cut]);
                }
                try out.print("trellis {s} profile", .{name});
                for (profile[0 .. n + 1]) |value| try out.print(" {d}", .{value});
                try line(out, " max {d}", .{maximum});
            },
            .STDARRAY => {
                if (n - k > 6 or k > 4) return session.fail("too large", .{});
                const leaders = try code.leaders(lab.gpa);
                const syndromes = try session.gpa.alloc(usize, leaders.len);
                for (syndromes, 0..) |*s, index| s.* = index;
                std.sort.heap(usize, syndromes, leaders, struct {
                    fn less(values: []const Word, a: usize, b: usize) bool {
                        const x = values[a];
                        const y = values[b];
                        return if (weight(x) != weight(y)) weight(x) < weight(y) else x < y;
                    }
                }.less);
                try line(out, "stdarray {s} rows {d} columns {d}", .{ name, leaders.len, code.words.len });
                for (syndromes) |s| {
                    try out.print("{f}:", .{bits(@intCast(s), n - k)});
                    for (code.words) |word| try out.print(" {f}", .{bits(leaders[s] ^ word, n)});
                    try out.writeByte('\n');
                }
            },
            .EQUAL => {
                const other = lab.get(args[1]);
                if (n != other.n) return line(out, "equal {s} {s} no lengths {d} {d}", .{ name, args[1], n, other.n });
                var combined = code.g;
                for (other.g.slice()) |row| combined.add(row);
                const common = k + other.k() - basis(combined.slice(), n).len;
                try line(out, "equal {s} {s} {s} intersection {d}", .{ name, args[1], yes(k == common and other.k() == common), common });
            },
            .ENCODE => {
                if (args[1].len != k) return session.fail("bad length", .{});
                try line(out, "encode {s} message {s} codeword {f}", .{ name, args[1], bits(code.encode(binary(args[1])), n) });
            },
            .SYNDROME, .DECODE, .BOUNDED, .COSET => {
                const text = args[if (verb == .BOUNDED) @as(usize, 2) else 1];
                if (text.len != n) return session.fail("bad length", .{});
                const word = binary(text);
                const s = code.syndrome(word);
                if (verb == .SYNDROME) return line(out, "syndrome {s} {f} codeword {s}", .{ name, bits(@intCast(s), n - k), yes(s == 0) });
                const decoded = try code.decode(lab.gpa, word);
                if (verb == .COSET) {
                    var counts: [25]usize = @splat(0);
                    for (code.words) |c| counts[weight(c ^ word)] += 1;
                    try out.print("coset {s} syndrome {f} leader {f} weights ", .{ name, bits(@intCast(s), n - k), bits(decoded.err, n) });
                    try weightList(out, counts[0 .. n + 1]);
                    return out.writeByte('\n');
                }
                if (verb == .BOUNDED and weight(decoded.err) > integer(args[1])) return line(out, "bounded {s} fail weight {d}", .{ name, weight(decoded.err) });
                try out.print("{s} {s} ", .{ if (verb == .BOUNDED) "bounded" else "decode", name });
                try session.decodedText(code, decoded);
                try out.writeByte('\n');
            },
            .ERASURE => {
                const text = args[1];
                if (text.len != n) return session.fail("bad length", .{});
                var mask: Word = 0;
                var known: Word = 0;
                var erased: usize = 0;
                for (text) |character| {
                    mask = (mask << 1) | @intFromBool(character != '?');
                    known = (known << 1) | @intFromBool(character == '1');
                    erased += @intFromBool(character == '?');
                }
                var count: usize = 0;
                var candidate: Word = 0;
                for (code.words) |word| if (word & mask == known) { count += 1; candidate = word; };
                try out.print("erasure {s} erased {d} candidates {d}", .{ name, erased, count });
                if (count == 1) try out.print(" codeword {f} message {f}", .{ bits(candidate, n), bits(code.messageFor(candidate), k) });
                try out.writeByte('\n');
            },
            .INTERLEAVE => try session.interleave(name, code, args),
            else => unreachable,
        }
    }
};

fn readLine(gpa: Allocator, input: *std.Io.Reader) ![]const u8 {
    var buffer: Writer.Allocating = .init(gpa);
    defer buffer.deinit();
    _ = try input.streamDelimiterEnding(&buffer.writer, '\n');
    if (input.seek < input.end) input.toss(1) else if (buffer.written().len == 0) return error.EndOfStream;
    const text = try buffer.toOwnedSlice();
    return if (text.len > 0 and text[text.len - 1] == '\r') text[0 .. text.len - 1] else text;
}
fn splitWords(gpa: Allocator, text: []const u8) Allocator.Error![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.tokenizeScalar(u8, text, ' ');
    while (tokens.next()) |word| try result.append(gpa, word);
    return result.toOwnedSlice(gpa);
}
pub fn main(init: std.process.Init) !void {
    var storage = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer storage.deinit();
    var lab: Laboratory = .{ .gpa = storage.allocator() };
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    const count = integer(try readLine(lab.gpa, &input.interface));
    for (0..count) |_| {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const gpa = scratch.allocator();
        const words = try splitWords(gpa, try readLine(gpa, &input.interface));
        var response: Writer.Allocating = .init(gpa);
        defer response.deinit();
        var session: Session = .{ .lab = &lab, .gpa = gpa, .out = &response.writer };
        session.execute(words) catch |err| {
            if (err != error.Invalid) return err;
            try line(&output.interface, "error: {s}", .{session.problem});
            try output.interface.flush();
            continue;
        };
        try output.interface.writeAll(response.written());
        try output.interface.flush();
    }
}
