const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = error{BadCommand} || Allocator.Error || std.Io.Writer.Error;
const bases = "ACGT";
const symbols = "_ACMGRSVTWYHKDBN";
const amino_acids = "ACDEFGHIKLMNPQRSTVWY";
const residue_masses = [_]i64{ 71079, 103139, 115089, 129116, 147177, 57052, 137141, 113160, 128174, 113160, 131193, 114104, 97117, 128131, 156188, 87078, 101105, 99133, 186213, 163176 };
const enzyme_names = [_][]const u8{ "EcoRI", "BamHI", "HindIII", "PstI", "SmaI", "KpnI", "XbaI", "NotI", "EcoRV", "HaeIII", "AluI", "TaqI", "Sau3AI", "HincII", "AvaI" };
const recognition = [_][]const u8{ "GAATTC", "GGATCC", "AAGCTT", "CTGCAG", "CCCGGG", "GGTACC", "TCTAGA", "GCGGCCGC", "GATATC", "GGCC", "AGCT", "TCGA", "GATC", "GTYRAC", "CYCGRG" };
const cut_offsets = [_]usize{ 1, 1, 1, 5, 3, 5, 1, 2, 3, 2, 2, 1, 0, 3, 1 };
const Op = enum { SEQ, SLICE, JOIN, MUTATE, DEL, LIST, REVCOMP, COMPLEMENT, REVERSE, TRANSCRIBE, TRANSLATE, CODONS, PROTEIN, ORFS, GC, GCWINDOW, SKEW, KMERS, FIND, RESTRICT, PALINDROMES, REPEATS, HAMMING, ALIGN, CONSENSUS, TM, MASS, PRIMER, FOLD, ASSEMBLE, PACK, UNPACK };
fn find(xs: []const []const u8, s: []const u8) ?usize {
    for (xs, 0..) |x, i| {
        if (std.mem.eql(u8, x, s)) return i;
    }
    return null;
}
fn baseIndex(c: u8) usize {
    return std.mem.findScalar(u8, bases, c).?;
}
fn gc(s: []const u8) i64 {
    return @intCast(std.mem.countScalar(u8, s, 'G') + std.mem.countScalar(u8, s, 'C'));
}
fn transition(a: u8, b: u8) bool {
    return a != b and ((a == 'A' or a == 'G') == (b == 'A' or b == 'G'));
}
fn complementBase(c: u8) u8 {
    const mask = std.mem.findScalar(u8, symbols, c).?;
    const comp = ((mask & 1) << 3) | ((mask & 2) << 1) | ((mask & 4) >> 1) | ((mask & 8) >> 3);
    return symbols[comp];
}
fn aa(codon: []const u8) u8 {
    const code = "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG";
    const alphabet = "TCAG";
    return code[16 * std.mem.findScalar(u8, alphabet, codon[0]).? + 4 * std.mem.findScalar(u8, alphabet, codon[1]).? + std.mem.findScalar(u8, alphabet, codon[2]).?];
}
fn repeatCount(s: []const u8, i: usize, u: usize) usize {
    var count: usize = 1;
    while (i + (count + 1) * u <= s.len and std.mem.eql(u8, s[i .. i + u], s[i + count * u .. i + (count + 1) * u])) count += 1;
    return count;
}
fn palindrome(s: []const u8) bool {
    if (s.len % 2 != 0) return false;
    for (s[0 .. s.len / 2], 0..) |c, i| {
        if (baseIndex(c) + baseIndex(s[s.len - i - 1]) != 3) return false;
    }
    return true;
}
fn tm(s: []const u8) i64 {
    const n: i64 = @intCast(s.len);
    const count = gc(s);
    return if (n < 14) 10 * (2 * (n - count) + 4 * count) else @divTrunc(649 * n + 410 * count - 6724, n);
}
fn mass(s: []const u8) i64 {
    const weights = [_]i64{ 331222, 307197, 347221, 322208 };
    var result: i64 = -@as(i64, @intCast(s.len - 1)) * 18015;
    for (s) |c| result += weights[baseIndex(c)];
    return result;
}
const Count = struct {
    text: []const u8,
    count: i64,

    fn less(_: void, a: @This(), b: @This()) bool {
        return a.count > b.count or (a.count == b.count and std.mem.order(u8, a.text, b.text) == .lt);
    }
};
const ParamKind = enum { name, new, sequence, position, base, frame, number, motif, enzyme, mode, hex };
const Param = struct {
    kind: ParamKind = .name,
    min: i64 = 0,
    max: i64 = 0,
};
fn numberParam(min: i64, max: i64) Param {
    return .{ .kind = .number, .min = min, .max = max };
}
const Dna = struct {
    gpa: Allocator,
    out: *std.Io.Writer,
    error_message: []const u8 = "",
    registry: std.StringArrayHashMapUnmanaged([]const u8) = .empty,
    fn fail(self: *Dna, comptime fmt: []const u8, args: anytype) Error {
        self.error_message = std.fmt.allocPrint(self.gpa, fmt, args) catch return error.OutOfMemory;
        return error.BadCommand;
    }
    fn reverse(self: *Dna, s: []const u8, comp: bool) Allocator.Error![]const u8 {
        const result = try self.gpa.dupe(u8, s);
        std.mem.reverse(u8, result);
        if (comp) for (result) |*c| {
            c.* = complementBase(c.*);
        };
        return result;
    }
    fn pct(self: *Dna, a: i64, b: usize) Allocator.Error![]const u8 {
        const q: u64 = @intCast(@divTrunc(10000 * a, @as(i64, @intCast(b))));
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>2}", .{ q / 100, q % 100 });
    }
    fn milli(self: *Dna, w: i64) Allocator.Error![]const u8 {
        const u: u64 = @intCast(w);
        return std.fmt.allocPrint(self.gpa, "{d}.{d:0>3}", .{ u / 1000, u % 1000 });
    }
    fn temperature(self: *Dna, t: i64) Allocator.Error![]const u8 {
        return std.fmt.allocPrint(self.gpa, "{d}.{d}", .{ @divTrunc(t, 10), @mod(t, 10) });
    }
    fn list(self: *Dna, label: []const u8, items: []const usize) Error!void {
        try self.out.writeAll(label);
        if (items.len == 0) try self.out.writeAll(" none");
        for (items) |item| try self.out.print(" {d}", .{item});
        try self.out.writeByte('\n');
    }
    fn numeric(self: *Dna, s: []const u8, min: i64, max: i64, frame: bool) Error!i64 {
        const first: usize = if (s.len > 0 and s[0] == '-') 1 else 0;
        if (s.len <= first or s.len - first > 6) return self.fail("invalid number {s}", .{s});
        for (s[first..]) |c| {
            if (!std.ascii.isDigit(c)) return self.fail("invalid number {s}", .{s});
        }
        const n = std.fmt.parseInt(i64, s, 10) catch return self.fail("invalid number {s}", .{s});
        if (n < min or n > max or (frame and n == 0)) return self.fail("invalid number {s}", .{s});
        return n;
    }
    fn validate(self: *Dna, op: Op, a: []const []const u8) Error![10]i64 {
        var schema: [10]Param = @splat(.{});
        var min: usize = 1;
        var max: usize = 1;
        switch (op) {
            .SEQ => {
                min = 2;
                max = 2;
                schema[0].kind = .new;
                schema[1].kind = .sequence;
            },
            .SLICE => {
                min = 4;
                max = 4;
                schema[1].kind = .position;
                schema[2].kind = .position;
                schema[3].kind = .new;
            },
            .JOIN => {
                min = 3;
                max = 9;
                schema[0].kind = .new;
            },
            .MUTATE => {
                min = 3;
                max = 3;
                schema[1].kind = .position;
                schema[2].kind = .base;
            },
            .LIST => {
                min = 0;
                max = 0;
            },
            .TRANSLATE, .CODONS, .PROTEIN => {
                min = 2;
                max = 2;
                schema[1].kind = .frame;
            },
            .ORFS => {
                min = 2;
                max = 2;
                schema[1] = numberParam(1, 200);
            },
            .GCWINDOW => {
                min = 3;
                max = 3;
                schema[1] = numberParam(1, 500);
                schema[2] = numberParam(1, 500);
            },
            .KMERS => {
                min = 3;
                max = 3;
                schema[1] = numberParam(1, 12);
                schema[2] = numberParam(1, 100);
            },
            .FIND => {
                min = 2;
                max = 2;
                schema[1].kind = .motif;
            },
            .RESTRICT => {
                min = 2;
                max = 7;
                for (1..7) |i| schema[i].kind = .enzyme;
            },
            .PALINDROMES => {
                min = 3;
                max = 3;
                schema[1] = numberParam(2, 20);
                schema[2] = numberParam(2, 20);
            },
            .REPEATS => {
                min = 4;
                max = 4;
                schema[1] = numberParam(1, 6);
                schema[2] = numberParam(1, 6);
                schema[3] = numberParam(2, 50);
            },
            .HAMMING => {
                min = 2;
                max = 2;
            },
            .ALIGN => {
                min = 6;
                max = 6;
                schema[2].kind = .mode;
                schema[3] = numberParam(1, 20);
                schema[4] = numberParam(-20, 0);
                schema[5] = numberParam(-20, -1);
            },
            .CONSENSUS => {
                min = 2;
                max = 10;
            },
            .FOLD => {
                min = 2;
                max = 2;
                schema[1] = numberParam(0, 10);
            },
            .ASSEMBLE => {
                min = 4;
                max = 10;
                schema[0].kind = .new;
                schema[1] = numberParam(1, 100);
            },
            .UNPACK => {
                min = 3;
                max = 3;
                schema[0].kind = .new;
                schema[1] = numberParam(1, 500);
                schema[2].kind = .hex;
            },
            else => {},
        }
        if (a.len < min or a.len > max) return self.fail("wrong argument count", .{});
        var values: [10]i64 = @splat(0);
        for (a, 0..) |s, i| {
            const p = schema[i];
            switch (p.kind) {
                .name => {
                    if (!self.registry.contains(s)) return self.fail("unknown sequence {s}", .{s});
                },
                .new => {
                    if (s.len < 1 or s.len > 10 or s[0] < 'a' or s[0] > 'z') return self.fail("invalid name {s}", .{s});
                    for (s[1..]) |c| {
                        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c))) return self.fail("invalid name {s}", .{s});
                    }
                },
                .sequence => {
                    for (s, 0..) |c, j| {
                        if (std.mem.findScalar(u8, bases, c) == null) return self.fail("invalid base {c} at {d}", .{ c, j + 1 });
                    }
                },
                .base => {
                    if (s.len != 1 or std.mem.findScalar(u8, bases, s[0]) == null) return self.fail("invalid base {s}", .{s});
                },
                .position => values[i] = try self.numeric(s, 1, @intCast(self.registry.get(a[0]).?.len), false),
                .frame => values[i] = try self.numeric(s, -3, 3, true),
                .number => values[i] = try self.numeric(s, p.min, p.max, false),
                .motif => {
                    if (s.len < 1 or s.len > 30) return self.fail("invalid motif {s}", .{s});
                    for (s) |c| {
                        if (c == '_' or std.mem.findScalar(u8, symbols, c) == null) return self.fail("invalid motif {s}", .{s});
                    }
                },
                .enzyme => {
                    if (find(&enzyme_names, s) == null) return self.fail("unknown enzyme {s}", .{s});
                    for (a[1..i]) |previous| {
                        if (std.mem.eql(u8, previous, s)) return self.fail("duplicate enzyme {s}", .{s});
                    }
                },
                .mode => {
                    if (!std.mem.eql(u8, s, "GLOBAL") and !std.mem.eql(u8, s, "LOCAL")) return self.fail("invalid mode {s}", .{s});
                },
                .hex => {
                    if (s.len != 2 * @as(usize, @intCast(@divTrunc(values[1] + 3, 4)))) return self.fail("invalid hex", .{});
                    for (s) |c| {
                        if (!(std.ascii.isDigit(c) or (c >= 'A' and c <= 'F'))) return self.fail("invalid hex", .{});
                    }
                },
            }
        }
        return values;
    }
    fn store(self: *Dna, name: []const u8, s: []const u8) Error!void {
        if (s.len > 500) return self.fail("too long", .{});
        const old = self.registry.contains(name);
        try self.registry.put(self.gpa, name, s);
        try self.out.print("{s} {s} {d} nt\n", .{ if (old) "replaced" else "stored", name, s.len });
    }
    fn codons(self: *Dna, s: []const u8, frame: i64) Error![][]const u8 {
        const strand = if (frame < 0) try self.reverse(s, true) else s;
        var cs: std.ArrayList([]const u8) = .empty;
        var i: usize = @intCast(@abs(frame) - 1);
        while (i + 2 < strand.len) : (i += 3) try cs.append(self.gpa, strand[i .. i + 3]);
        return cs.items;
    }
    fn translate(self: *Dna, cs: []const []const u8) Allocator.Error![]const u8 {
        const result = try self.gpa.alloc(u8, cs.len);
        for (cs, 0..) |c, i| result[i] = aa(c);
        return result;
    }
    fn counted(self: *Dna, items: []const []const u8) Error![]Count {
        var map: std.StringHashMapUnmanaged(i64) = .empty;
        for (items) |item| try map.put(self.gpa, item, (map.get(item) orelse 0) + 1);
        var result: std.ArrayList(Count) = .empty;
        var it = map.iterator();
        while (it.next()) |entry| try result.append(self.gpa, .{ .text = entry.key_ptr.*, .count = entry.value_ptr.* });
        std.mem.sort(Count, result.items, {}, Count.less);
        return result.items;
    }
    fn occurrences(self: *Dna, s: []const u8, motif: []const u8) Error![]usize {
        var result: std.ArrayList(usize) = .empty;
        var i: usize = 0;
        while (i + motif.len <= s.len) : (i += 1) {
            var matched = true;
            for (motif, 0..) |c, j| {
                const mask = std.mem.findScalar(u8, symbols, c).?;
                if (mask & (@as(usize, 1) << @intCast(baseIndex(s[i + j]))) == 0) {
                    matched = false;
                    break;
                }
            }
            if (matched) try result.append(self.gpa, i + 1);
        }
        return result.items;
    }
    fn alignSequences(self: *Dna, a: []const u8, b: []const u8, local: bool, match_score: i64, mismatch: i64, gap: i64) Error!void {
        const m = a.len;
        const n = b.len;
        const width = n + 1;
        const dp = try self.gpa.alloc(i64, (m + 1) * width);
        @memset(dp, 0);
        if (!local) {
            for (0..m + 1) |i| dp[i * width] = @as(i64, @intCast(i)) * gap;
            for (0..n + 1) |j| dp[j] = @as(i64, @intCast(j)) * gap;
        }
        var score: i64 = 0;
        var i1: usize = 0;
        var j1: usize = 0;
        for (1..m + 1) |i| {
            for (1..n + 1) |j| {
                const value = @max(dp[(i - 1) * width + j - 1] + (if (a[i - 1] == b[j - 1]) match_score else mismatch), dp[(i - 1) * width + j] + gap, dp[i * width + j - 1] + gap);
                dp[i * width + j] = if (local) @max(0, value) else value;
                if (local and dp[i * width + j] > score) {
                    score = dp[i * width + j];
                    i1 = i;
                    j1 = j;
                }
            }
        }
        if (!local) {
            score = dp[m * width + n];
            i1 = m;
            j1 = n;
        }
        if (local and score == 0) {
            try self.out.writeAll("score 0\n");
            return;
        }
        var i = i1;
        var j = j1;
        var top: std.ArrayList(u8) = .empty;
        var bottom: std.ArrayList(u8) = .empty;
        while (if (local) dp[i * width + j] != 0 else i != 0 or j != 0) {
            if (i > 0 and j > 0 and dp[i * width + j] == dp[(i - 1) * width + j - 1] + (if (a[i - 1] == b[j - 1]) match_score else mismatch)) {
                i -= 1;
                j -= 1;
                try top.append(self.gpa, a[i]);
                try bottom.append(self.gpa, b[j]);
            } else if (i > 0 and dp[i * width + j] == dp[(i - 1) * width + j] + gap) {
                i -= 1;
                try top.append(self.gpa, a[i]);
                try bottom.append(self.gpa, '-');
            } else {
                j -= 1;
                try top.append(self.gpa, '-');
                try bottom.append(self.gpa, b[j]);
            }
        }
        std.mem.reverse(u8, top.items);
        std.mem.reverse(u8, bottom.items);
        const middle = try self.gpa.alloc(u8, top.items.len);
        for (top.items, bottom.items, 0..) |x, y, k| {
            middle[k] = if (x == '-' or y == '-') '-' else if (x == y) '|' else '*';
        }
        try self.out.print("score {d} a {d}-{d} b {d}-{d} identity {d}/{d} gaps {d}\n{s}\n{s}\n{s}\n", .{ score, i + 1, i1, j + 1, j1, std.mem.countScalar(u8, middle, '|'), top.items.len, std.mem.countScalar(u8, middle, '-'), top.items, middle, bottom.items });
    }
    fn fold(self: *Dna, s: []const u8, loop: usize) Error!void {
        const n = s.len;
        const dp = try self.gpa.create([100][100]i64);
        dp.* = @splat(@splat(0));
        for (2..n + 1) |length| {
            for (0..n - length + 1) |i| {
                const j = i + length - 1;
                dp[i][j] = dp[i][j - 1];
                var k = i;
                while (k + loop < j) : (k += 1) {
                    if (canPair(s[k], s[j])) dp[i][j] = @max(dp[i][j], foldValue(dp, @intCast(i), @as(isize, @intCast(k)) - 1) + 1 + foldValue(dp, @intCast(k + 1), @as(isize, @intCast(j)) - 1));
                }
            }
        }
        const structure = try self.gpa.alloc(u8, n);
        @memset(structure, '.');
        var stack: std.ArrayList([2]isize) = .empty;
        try stack.append(self.gpa, .{ 0, @intCast(n - 1) });
        while (stack.pop()) |interval| {
            const i = interval[0];
            const j = interval[1];
            const value = foldValue(dp, i, j);
            if (value == 0) continue;
            if (value == foldValue(dp, i, j - 1)) {
                try stack.append(self.gpa, .{ i, j - 1 });
                continue;
            }
            var k = i;
            while (k + @as(isize, @intCast(loop)) < j) : (k += 1) {
                if (canPair(s[@intCast(k)], s[@intCast(j)]) and foldValue(dp, i, k - 1) + 1 + foldValue(dp, k + 1, j - 1) == value) {
                    structure[@intCast(k)] = '(';
                    structure[@intCast(j)] = ')';
                    try stack.append(self.gpa, .{ i, k - 1 });
                    try stack.append(self.gpa, .{ k + 1, j - 1 });
                    break;
                }
            }
        }
        try self.out.print("{s}\npairs {d}\n", .{ structure, dp[0][n - 1] });
    }
    fn execute(self: *Dna, tokens: []const []const u8) Error!void {
        const op = std.meta.stringToEnum(Op, tokens[0]) orelse return self.fail("unknown command {s}", .{tokens[0]});
        const a = tokens[1..];
        const v = try self.validate(op, a);
        const name: []const u8 = if (a.len == 0) "" else a[0];
        const s = self.registry.get(name) orelse "";
        const n = s.len;
        switch (op) {
            .SEQ => try self.store(name, a[1]),
            .SLICE => {
                const start: usize = @intCast(v[1]);
                const end: usize = @intCast(v[2]);
                try self.store(a[3], if (start <= end) s[start - 1 .. end] else try self.reverse(s[end - 1 .. start], true));
            },
            .JOIN => {
                var parts: [8][]const u8 = undefined;
                for (a[1..], 0..) |id, i| parts[i] = self.registry.get(id).?;
                try self.store(name, try std.mem.concat(self.gpa, u8, parts[0 .. a.len - 1]));
            },
            .MUTATE => {
                const p: usize = @intCast(v[1] - 1);
                const old = s[p];
                if (old == a[2][0]) return self.fail("no change", .{});
                const result = try self.gpa.dupe(u8, s);
                result[p] = a[2][0];
                try self.registry.put(self.gpa, name, result);
                try self.out.print("{s} {c}{d}{c} {s}\n", .{ name, old, p + 1, a[2][0], if (transition(old, a[2][0])) "transition" else "transversion" });
            },
            .DEL => {
                _ = self.registry.swapRemove(name);
                try self.out.print("deleted {s}\n", .{name});
            },
            .LIST => {
                const entries = try self.gpa.dupe([]const u8, self.registry.keys());
                std.mem.sort([]const u8, entries, {}, stringLess);
                if (entries.len == 0) try self.out.writeAll("no sequences\n");
                for (entries) |id| try self.out.print("{s} {d} nt\n", .{ id, self.registry.get(id).?.len });
            },
            .REVCOMP, .REVERSE => try self.out.print("{s}\n", .{try self.reverse(s, op == .REVCOMP)}),
            .COMPLEMENT, .TRANSCRIBE => {
                const result = try self.gpa.dupe(u8, s);
                for (result) |*c| c.* = if (op == .COMPLEMENT) complementBase(c.*) else if (c.* == 'T') 'U' else c.*;
                try self.out.print("{s}\n", .{result});
            },
            .TRANSLATE, .CODONS, .PROTEIN => {
                const cs = try self.codons(s, v[1]);
                const translation = try self.translate(cs);
                if (op == .TRANSLATE) {
                    try self.out.print("{s}\n", .{if (translation.len == 0) "none" else translation});
                } else if (op == .CODONS) {
                    const freq = try self.counted(cs);
                    if (freq.len == 0) try self.out.writeAll("none\n");
                    for (freq) |c| try self.out.print("{s} {c} {d}\n", .{ c.text, aa(c.text), c.count });
                } else {
                    const stop = std.mem.findScalar(u8, translation, '*') orelse translation.len;
                    const protein = translation[0..stop];
                    if (protein.len == 0) return self.fail("empty protein", .{});
                    var weight: i64 = 18015;
                    var charge: i64 = 0;
                    var letters: std.ArrayList([]const u8) = .empty;
                    for (protein, 0..) |c, i| {
                        weight += residue_masses[std.mem.findScalar(u8, amino_acids, c).?];
                        if (c == 'K' or c == 'R') charge += 1;
                        if (c == 'D' or c == 'E') charge -= 1;
                        try letters.append(self.gpa, protein[i .. i + 1]);
                    }
                    try self.out.print("{s}\nlength {d} mass {s} charge {s}{d}\n", .{ protein, protein.len, try self.milli(weight), if (charge > 0) "+" else "", charge });
                    for (try self.counted(letters.items), 0..) |c, i| {
                        if (i > 0) try self.out.writeByte(' ');
                        try self.out.print("{s}={d}", .{ c.text, c.count });
                    }
                    try self.out.writeByte('\n');
                }
            },
            .ORFS => {
                const Orf = struct {
                    left: usize,
                    right: usize,
                    frame: i64,
                    protein: []const u8,

                    fn less(_: void, a: @This(), b: @This()) bool {
                        return a.left < b.left;
                    }
                };
                var results: std.ArrayList(Orf) = .empty;
                for ([_]i64{ 1, 2, 3, -1, -2, -3 }) |frame| {
                    const cs = try self.codons(s, frame);
                    var start: ?usize = null;
                    for (cs, 0..) |c, i| {
                        if (start == null and std.mem.eql(u8, c, "ATG")) {
                            start = i;
                        } else if (start != null and aa(c) == '*') {
                            if (i - start.? >= @as(usize, @intCast(v[1]))) {
                                const left = @as(usize, @intCast(@abs(frame))) + 3 * start.?;
                                const right = @as(usize, @intCast(@abs(frame))) + 3 * i + 2;
                                try results.append(self.gpa, .{ .left = if (frame < 0) n + 1 - right else left, .right = if (frame < 0) n + 1 - left else right, .frame = frame, .protein = try self.translate(cs[start.?..i]) });
                            }
                            start = null;
                        }
                    }
                }
                std.mem.sort(Orf, results.items, {}, Orf.less);
                if (results.items.len == 0) try self.out.writeAll("none\n");
                for (results.items) |r| try self.out.print("{s}{d} {d} {d} {d} {s}\n", .{ if (r.frame > 0) "+" else "", r.frame, r.left, r.right, r.protein.len, r.protein });
            },
            .GC => {
                var counts: [4]usize = @splat(0);
                for (s) |c| counts[baseIndex(c)] += 1;
                try self.out.print("A={d} C={d} G={d} T={d} GC={s}%\n", .{ counts[0], counts[1], counts[2], counts[3], try self.pct(gc(s), n) });
            },
            .GCWINDOW => {
                const width: usize = @intCast(v[1]);
                const step: usize = @intCast(v[2]);
                if (width > n) return self.fail("window too large", .{});
                var i: usize = 0;
                while (i + width <= n) : (i += step) try self.out.print("{d}-{d} {s}%\n", .{ i + 1, i + width, try self.pct(gc(s[i .. i + width]), width) });
            },
            .SKEW => {
                const values = try self.gpa.alloc(i64, n + 1);
                values[0] = 0;
                for (s, 0..) |c, i|
                    values[i + 1] = values[i] + @as(i64, if (c == 'G') 1 else if (c == 'C') -1 else 0);
                const low, const high = std.mem.minMax(i64, values);
                try self.out.print("min {d} at", .{low});
                for (values, 0..) |value, i| {
                    if (value == low) try self.out.print(" {d}", .{i});
                }
                try self.out.writeByte('\n');
                try self.out.print("max {d} at", .{high});
                for (values, 0..) |value, i| {
                    if (value == high) try self.out.print(" {d}", .{i});
                }
                try self.out.writeByte('\n');
            },
            .KMERS => {
                const k: usize = @intCast(v[1]);
                if (k > n) return self.fail("k too large", .{});
                var items: std.ArrayList([]const u8) = .empty;
                for (0..n - k + 1) |i| try items.append(self.gpa, s[i .. i + k]);
                const freq = try self.counted(items.items);
                try self.out.print("{d} windows {d} distinct\n", .{ n - k + 1, freq.len });
                for (freq[0..@min(freq.len, @as(usize, @intCast(v[2])))]) |c| try self.out.print("{s} {d}\n", .{ c.text, c.count });
            },
            .FIND => {
                try self.list("forward", try self.occurrences(s, a[1]));
                try self.list("reverse", try self.occurrences(s, try self.reverse(a[1], true)));
            },
            .RESTRICT => {
                var cuts: [501]bool = @splat(false);
                for (a[1..]) |e| {
                    const k = find(&enzyme_names, e).?;
                    var points: std.ArrayList(usize) = .empty;
                    for (try self.occurrences(s, recognition[k])) |p| {
                        const c = p + cut_offsets[k] - 1;
                        if (c >= 1 and c < n) {
                            cuts[c] = true;
                            try points.append(self.gpa, c);
                        }
                    }
                    try self.list(e, points.items);
                }
                var points: std.ArrayList(usize) = .empty;
                try points.append(self.gpa, 0);
                for (1..n) |c| {
                    if (cuts[c]) try points.append(self.gpa, c);
                }
                try points.append(self.gpa, n);
                var sizes: std.ArrayList(usize) = .empty;
                try self.out.writeAll("fragments");
                for (1..points.items.len) |i| {
                    try self.out.print(" {d}-{d}", .{ points.items[i - 1] + 1, points.items[i] });
                    try sizes.append(self.gpa, points.items[i] - points.items[i - 1]);
                }
                try self.out.writeByte('\n');
                std.mem.sort(usize, sizes.items, {}, std.sort.desc(usize));
                try self.list("sizes", sizes.items);
            },
            .PALINDROMES => {
                if (v[1] > v[2]) return self.fail("invalid range", .{});
                var found = false;
                for (0..n) |i| {
                    var len: usize = @intCast(v[1]);
                    while (len <= @as(usize, @intCast(v[2])) and i + len <= n) : (len += 1) {
                        if (palindrome(s[i .. i + len])) {
                            found = true;
                            try self.out.print("{d} {d} {s}\n", .{ i + 1, len, s[i .. i + len] });
                        }
                    }
                }
                if (!found) try self.out.writeAll("none\n");
            },
            .REPEATS => {
                if (v[1] > v[2]) return self.fail("invalid range", .{});
                const Repeat = struct {
                    start: usize,
                    unit: usize,
                    count: usize,

                    fn less(_: void, a: @This(), b: @This()) bool {
                        return a.start < b.start or (a.start == b.start and a.unit < b.unit);
                    }
                };
                var results: std.ArrayList(Repeat) = .empty;
                var u: usize = @intCast(v[1]);
                while (u <= @as(usize, @intCast(v[2]))) : (u += 1) {
                    var i: usize = 0;
                    while (i + u <= n) {
                        const count = repeatCount(s, i, u);
                        var primitive = true;
                        for (1..u) |d| {
                            if (u % d != 0) continue;
                            var repeated = true;
                            for (0..u) |j| {
                                if (s[i + j] != s[i + j % d]) repeated = false;
                            }
                            if (repeated) primitive = false;
                        }
                        if (primitive and count >= @as(usize, @intCast(v[3]))) {
                            try results.append(self.gpa, .{ .start = i, .unit = u, .count = count });
                            i += count * u;
                        } else i += 1;
                    }
                }
                std.mem.sort(Repeat, results.items, {}, Repeat.less);
                if (results.items.len == 0) try self.out.writeAll("none\n");
                for (results.items) |r| try self.out.print("{d}-{d} {s}x{d}\n", .{ r.start + 1, r.start + r.unit * r.count, s[r.start .. r.start + r.unit], r.count });
            },
            .HAMMING => {
                const b = self.registry.get(a[1]).?;
                if (n != b.len) return self.fail("length mismatch", .{});
                var distance: usize = 0;
                var transitions: usize = 0;
                for (s, b) |x, y| {
                    if (x != y) {
                        distance += 1;
                        if (transition(x, y)) transitions += 1;
                    }
                }
                try self.out.print("distance {d} transitions {d} transversions {d}\n", .{ distance, transitions, distance - transitions });
            },
            .ALIGN => try self.alignSequences(s, self.registry.get(a[1]).?, std.mem.eql(u8, a[2], "LOCAL"), v[3], v[4], v[5]),
            .CONSENSUS => {
                for (a) |id| {
                    if (self.registry.get(id).?.len != n) return self.fail("length mismatch", .{});
                }
                var profile: [4][500]usize = @splat(@splat(0));
                const consensus = try self.gpa.alloc(u8, n);
                const iupac = try self.gpa.alloc(u8, n);
                for (0..n) |i| {
                    for (a) |id| profile[baseIndex(self.registry.get(id).?[i])][i] += 1;
                    var maximum: usize = 0;
                    for (0..4) |k| maximum = @max(maximum, profile[k][i]);
                    var mask: usize = 0;
                    var first: ?usize = null;
                    for (0..4) |k| {
                        if (profile[k][i] == maximum) {
                            if (first == null) first = k;
                            mask |= @as(usize, 1) << @intCast(k);
                        }
                    }
                    consensus[i] = bases[first.?];
                    iupac[i] = symbols[mask];
                }
                for (0..4) |k| {
                    try self.out.print("{c}", .{bases[k]});
                    for (0..n) |i| try self.out.print(" {d}", .{profile[k][i]});
                    try self.out.writeByte('\n');
                }
                try self.out.print("consensus {s}\niupac {s}\n", .{ consensus, iupac });
            },
            .TM => try self.out.print("Tm {s} {s}\n", .{ try self.temperature(tm(s)), if (n < 14) "wallace" else "gc" }),
            .MASS => {
                const single = mass(s);
                try self.out.print("ss {s} ds {s}\n", .{ try self.milli(single), try self.milli(single + mass(try self.reverse(s, true))) });
            },
            .PRIMER => {
                var run: usize = 1;
                var max_run: usize = 1;
                var repeat: usize = 0;
                var selfcomp: usize = 0;
                for (1..n) |i| {
                    run = if (s[i] == s[i - 1]) run + 1 else 1;
                    max_run = @max(max_run, run);
                }
                for (0..n - 1) |i| {
                    if (s[i] != s[i + 1]) repeat = @max(repeat, repeatCount(s, i, 2));
                }
                for (1..n) |center| {
                    var radius: usize = 0;
                    while (radius < center and center + radius < n and baseIndex(s[center - radius - 1]) + baseIndex(s[center + radius]) == 3) : (radius += 1) {
                        selfcomp = @max(selfcomp, 2 * (radius + 1));
                    }
                }
                const clamp = gc(s[n - @min(n, 5) ..]);
                const t = tm(s);
                const len: i64 = @intCast(n);
                const g = gc(s);
                const items = [_][]const u8{ "length", "gc", "tm", "clamp", "run", "repeat", "selfcomp" };
                const values = [_][]const u8{ try std.fmt.allocPrint(self.gpa, "{d}", .{n}), try self.pct(g, n), try self.temperature(t), try std.fmt.allocPrint(self.gpa, "{d}", .{clamp}), try std.fmt.allocPrint(self.gpa, "{d}", .{max_run}), try std.fmt.allocPrint(self.gpa, "{d}", .{repeat}), try std.fmt.allocPrint(self.gpa, "{d}", .{selfcomp}) };
                const passed = [_]bool{ n >= 18 and n <= 25, 40 * len <= 100 * g and 100 * g <= 60 * len, t >= 520 and t <= 620, clamp >= 1 and clamp <= 3, max_run <= 4, repeat <= 4, selfcomp <= 6 };
                for (0..7) |i| try self.out.print("{s} {s} {s}\n", .{ items[i], values[i], if (passed[i]) "OK" else "FAIL" });
                try self.out.writeAll(if (std.mem.allEqual(bool, &passed, true)) "PASS" else "FAIL");
                for (0..7) |i| {
                    if (!passed[i]) try self.out.print(" {s}", .{items[i]});
                }
                try self.out.writeByte('\n');
            },
            .FOLD => {
                if (n > 100) return self.fail("too long", .{});
                try self.fold(s, @intCast(v[1]));
            },
            .ASSEMBLE => {
                var fragments: std.ArrayList([]const u8) = .empty;
                for (a[2..]) |id| {
                    const fragment = self.registry.get(id).?;
                    if (find(fragments.items, fragment) == null) try fragments.append(self.gpa, fragment);
                }
                var i: usize = 0;
                while (i < fragments.items.len) {
                    var contained = false;
                    for (fragments.items, 0..) |fragment, j| {
                        if (i != j and std.mem.find(u8, fragment, fragments.items[i]) != null) {
                            contained = true;
                            break;
                        }
                    }
                    if (contained) _ = fragments.orderedRemove(i) else i += 1;
                }
                while (fragments.items.len > 1) {
                    var best: usize = 0;
                    var bx: usize = 0;
                    var by: usize = 0;
                    for (fragments.items, 0..) |x, xi| {
                        for (fragments.items, 0..) |y, yi| {
                            if (xi == yi) continue;
                            var overlap = @min(x.len, y.len) - 1;
                            while (overlap > best) : (overlap -= 1) {
                                if (std.mem.eql(u8, x[x.len - overlap ..], y[0..overlap])) {
                                    best = overlap;
                                    bx = xi;
                                    by = yi;
                                    break;
                                }
                            }
                        }
                    }
                    if (best < @as(usize, @intCast(v[1]))) break;
                    const merged = try std.fmt.allocPrint(self.gpa, "{s}{s}", .{ fragments.items[bx], fragments.items[by][best..] });
                    fragments.items[bx] = merged;
                    var remaining: std.ArrayList([]const u8) = .empty;
                    for (fragments.items, 0..) |fragment, j| {
                        if (j == bx or (j != by and std.mem.find(u8, merged, fragment) == null)) try remaining.append(self.gpa, fragment);
                    }
                    fragments = remaining;
                }
                var longest = fragments.items[0];
                for (fragments.items) |fragment| {
                    if (fragment.len > longest.len) longest = fragment;
                }
                if (longest.len > 500) return self.fail("too long", .{});
                try self.out.print("contigs {d}\n", .{fragments.items.len});
                for (fragments.items) |fragment| try self.out.print("{d} {s}\n", .{ fragment.len, fragment });
                try self.store(name, longest);
            },
            .PACK => {
                try self.out.print("{d} ", .{n});
                var i: usize = 0;
                while (i < n) : (i += 4) {
                    var value: usize = 0;
                    for (0..4) |j| value = value * 4 + (if (i + j < n) baseIndex(s[i + j]) else 0);
                    try self.out.print("{X:0>2}", .{value});
                }
                try self.out.writeByte('\n');
            },
            .UNPACK => {
                const length: usize = @intCast(v[1]);
                var decoded: std.ArrayList(u8) = .empty;
                var i: usize = 0;
                while (i < a[2].len) : (i += 2) {
                    const value = std.fmt.parseInt(usize, a[2][i .. i + 2], 16) catch unreachable;
                    for ([_]usize{ value / 64, value / 16 % 4, value / 4 % 4, value % 4 }) |code| {
                        if (decoded.items.len >= length and code != 0) return self.fail("invalid padding", .{});
                        try decoded.append(self.gpa, bases[code]);
                    }
                }
                try self.store(name, decoded.items[0..length]);
            },
        }
    }
};
fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn canPair(a: u8, b: u8) bool {
    return complementBase(a) == b or (a == 'G' and b == 'T') or (a == 'T' and b == 'G');
}
fn foldValue(dp: *const [100][100]i64, i: isize, j: isize) i64 {
    return if (i > j) 0 else dp[@intCast(i)][@intCast(j)];
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var ib: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &ib);
    var ob: [8192]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(init.io, &ob);
    var dna = Dna{ .gpa = gpa, .out = &output.interface };
    const n = std.fmt.parseInt(usize, (try input.interface.takeDelimiter('\n')).?, 10) catch unreachable;
    for (0..n) |_| {
        const line = try gpa.dupe(u8, (try input.interface.takeDelimiter('\n')).?);
        var tokens: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, ' ');
        while (it.next()) |part| try tokens.append(gpa, part);
        var draft: std.Io.Writer.Allocating = .init(gpa);
        dna.out = &draft.writer;
        dna.execute(tokens.items) catch |err| {
            if (err == error.BadCommand) {
                try output.interface.print("ERROR {s}\n", .{dna.error_message});
                continue;
            }
            return err;
        };
        try output.interface.writeAll(draft.writer.buffered());
    }
    try output.interface.flush();
}
