const std = @import("std");
const d = @import("sequence_io.zig");
const suffix = @import("suffix_array.zig");
const fm = @import("fm_index.zig");
const search = @import("search.zig");
const sam = @import("sam_writer.zig");
const ratio = sam.ratio;
const n = d.n;
const u = d.u;
const bases = "ACGT";
const alphabet = "$#ACGT";
var work_allocator: std.mem.Allocator = undefined;
fn workAppend(comptime T: type, list: *std.ArrayList(T), value: T) void {
    list.append(work_allocator, value) catch @panic("allocation failed");
}
fn bit(index: usize) u16 {
    return @as(u16, 1) << @intCast(index);
}
fn baseIndex(base: u8) usize {
    return std.mem.indexOfScalar(u8, "ACGTN", base).?;
}
const Params = struct {
    mismatches: i64,
    minimum_length: usize,
    trim_quality: i64,
    seed_length: usize,
    seed_step: usize,
    maximum_seed_hits: usize,
    band_width: i64,
    match: i64,
    mismatch: i64,
    gap_open: i64,
    gap_extend: i64,
    minimum_score: i64,
    maximum_alternatives: usize,
    occ_interval: usize,
    sample_interval: usize,
    direct_limit: usize,
    coverage_window: usize,
    coverage_mapq: i64,
    variant_depth: i64,
    variant_quality: i64,
    variant_percent: i64,
    homozygous_percent: i64,
    fn init(input: d.Input) Params {
        const p = input.parameters;
        return .{ .mismatches = p[0][0], .minimum_length = u(p[1][0]), .trim_quality = p[2][0],
             .seed_length = u(p[3][0]), .seed_step = u(p[4][0]), .maximum_seed_hits = u(p[5][0]),
             .band_width = p[6][0], .match = p[7][0], .mismatch = p[7][1], .gap_open = p[7][2],
             .gap_extend = p[7][3], .minimum_score = p[8][0], .maximum_alternatives = u(p[9][0]),
             .occ_interval = u(p[10][0]), .sample_interval = u(p[11][0]), .direct_limit = u(p[12][0]),
             .coverage_window = u(p[13][0]), .coverage_mapq = p[14][0], .variant_depth = p[15][0],
             .variant_quality = p[15][1], .variant_percent = p[15][2], .homozygous_percent = p[15][3] };
    }
};
const Position = struct { reference: usize, offset: usize };
const ReferenceText = struct {
    references: []const d.Reference,
    offsets: []const usize,
    text: []const u8,
    reverse: []const u8,
    fn init(references: []const d.Reference) ReferenceText {
        const offsets = d.alloc(usize, references.len);
        var text: d.Text = .{};
        for (references, offsets) |reference, *offset| {
            offset.* = text.value().len;
            text.add("{s}#", .{reference.bases});
        }
        text.data.items[text.data.items.len - 1] = '$';
        const reverse = d.alloc(u8, text.value().len);
        for (reverse[0 .. reverse.len - 1], 0..) |*character, i| character.* = text.value()[text.value().len - i - 2];
        reverse[reverse.len - 1] = '$';
        return .{ .references = references, .offsets = offsets, .text = text.value(), .reverse = reverse };
    }
    fn position(self: ReferenceText, value: usize) ?Position {
        var reference = self.references.len - 1;
        while (reference > 0 and self.offsets[reference] > value) reference -= 1;
        const offset = value - self.offsets[reference];
        if (offset >= self.references[reference].bases.len) return null;
        return .{ .reference = reference, .offset = offset };
    }
    fn label(self: ReferenceText, value: usize) []const u8 {
        const located = self.position(value) orelse return "*";
        return d.fmt("{s}:{d}", .{ self.references[located.reference].name, located.offset + 1 });
    }
};
const Run = struct { operation: u8, count: usize };
fn runs(operations: []const u8) []const Run {
    var out: std.ArrayList(Run) = .empty;
    for (operations) |operation| {
        if (out.items.len == 0 or out.items[out.items.len - 1].operation != operation) d.append(Run,
             &out, .{ .operation = operation, .count = 1 }) else out.items[out.items.len - 1].count += 1;
    }
    return out.items;
}
fn describe(reference: usize, position: usize, strand: usize, operations: []const u8, result: d.Result,
     references: []const d.Reference) d.Alignment {
    const oriented = if (strand == 0) result.core else d.reverseComplement(result.core);
    var out: d.Alignment = .{ .reference = reference, .position = position, .strand = strand,
         .operations = operations, .oriented = oriented };
    const sequence = references[reference].bases;
    const pairs = d.alloc(d.AlignedPair, result.length);
    var pair_count: usize = 0;
    var i: usize = 0;
    var j = position;
    var matches: usize = 0;
    var cigar: d.Text = .{};
    var md: d.Text = .{};
    for (runs(operations)) |run| {
        cigar.add("{d}{c}", .{ run.count, run.operation });
        switch (run.operation) {
            'I' => {
                i += run.count;
                out.nm += n(run.count);
            },
            'D' => {
                md.add("{d}^{s}", .{ matches, sequence[j .. j + run.count] });
                matches = 0;
                j += run.count;
                out.nm += n(run.count);
            },
            else => for (0..run.count) |_| {
                pairs[pair_count] = .{ .read = i, .reference = j };
                pair_count += 1;
                if (oriented[i] == sequence[j]) matches += 1 else {
                    md.add("{d}{c}", .{ matches, sequence[j] });
                    matches = 0;
                    out.nm += 1;
                }
                i += 1;
                j += 1;
            },
        }
    }
    md.add("{d}", .{matches});
    out.cigar = cigar.value();
    if (result.trimmed > 0) out.cigar = if (strand == 0) d.fmt("{s}{d}S", .{ out.cigar, result.trimmed }) else d.fmt("{d}S{s}",
         .{ result.trimmed, out.cigar });
    out.md = md.value();
    out.pairs = pairs[0..pair_count];
    return out;
}
const unreachable_value: i64 = -1000000;
const BandRow = struct {
    first: i64,
    last: i64,
    values: [3][]i64,
    fn get(self: BandRow, state: usize, column: i64) i64 {
        if (column < self.first or column > self.last) return unreachable_value;
        return self.values[state][u(column - self.first)];
    }
};
fn subtract(value: i64, penalty: i64) i64 {
    return if (value == unreachable_value) unreachable_value else value - penalty;
}
const Banded = struct { score: i64, position: usize, operations: []const u8 };
fn bandedAlignment(oriented: []const u8, reference: []const u8, center: i64, p: Params) ?Banded {
    const rows = work_allocator.alloc(BandRow, oriented.len + 1) catch @panic("allocation failed");
    defer work_allocator.free(rows);
    for (rows, 0..) |*row, i| {
        row.first = @max(0, n(i) + center - p.band_width);
        row.last = @min(n(reference.len), n(i) + center + p.band_width);
        const count = u(@max(0, row.last - row.first + 1));
        for (&row.values, 0..) |*values, state| {
            values.* = work_allocator.alloc(i64, count) catch @panic("allocation failed");
            @memset(values.*, if (i == 0 and state == 0) 0 else unreachable_value);
        }
    }
    defer for (rows) |row| for (row.values) |values| {
        work_allocator.free(values);
    };
    for (1..rows.len) |i| {
        const row = &rows[i];
        var j = row.first;
        while (j <= row.last) : (j += 1) {
            const column = u(j - row.first);
            row.values[2][column] = @max(subtract(rows[i - 1].get(0, j), p.gap_open + p.gap_extend),
                 subtract(rows[i - 1].get(2, j), p.gap_extend));
            var diagonal = unreachable_value;
            if (j >= 1) {
                row.values[1][column] = @max(subtract(row.get(0, j - 1), p.gap_open + p.gap_extend),
                     subtract(row.get(1, j - 1), p.gap_extend));
                const previous = rows[i - 1].get(0, j - 1);
                if (previous != unreachable_value) diagonal = previous + (if (oriented[i - 1] == reference[u(j - 1)]) p.match else -p.mismatch);
            }
            row.values[0][column] = @max(diagonal, @max(row.values[1][column], row.values[2][column]));
        }
    }
    const last = rows[oriented.len];
    var best = unreachable_value;
    var endpoint: ?i64 = null;
    var j = last.first;
    while (j <= last.last) : (j += 1) {
        const value = last.get(0, j);
        if (value > best) {
            best = value;
            endpoint = j;
        }
    }
    var column = endpoint orelse return null;
    var row = oriented.len;
    var state: usize = 0;
    var backward: d.Text = .{};
    while (true) {
        if (state == 0) {
            if (row == 0) break;
            const previous = if (column >= 1) rows[row - 1].get(0, column - 1) else unreachable_value;
            if (previous != unreachable_value and rows[row].get(0, column) == previous + (if (oriented[row - 1] == reference[u(column - 1)]) p.match else -p.mismatch)) {
                backward.add("M", .{});
                row -= 1;
                column -= 1;
                continue;
            }
            state = if (rows[row].get(2, column) != unreachable_value and rows[row].get(0,
                 column) == rows[row].get(2, column)) 1 else 2;
        } else if (state == 1) {
            backward.add("I", .{});
            const previous = rows[row - 1].get(2, column);
            state = if (previous != unreachable_value and rows[row].get(2, column) == previous - p.gap_extend) 1 else 0;
            row -= 1;
        } else {
            backward.add("D", .{});
            const previous = rows[row].get(1, column - 1);
            state = if (previous != unreachable_value and rows[row].get(1, column) == previous - p.gap_extend) 2 else 0;
            column -= 1;
        }
    }
    const operations = backward.data.items;
    for (0..operations.len / 2) |i| std.mem.swap(u8, &operations[i], &operations[operations.len - i - 1]);
    return .{ .score = best, .position = u(column), .operations = operations };
}
const SearchTotals = struct { calls: i64 = 0, nodes: i64 = 0, leaves: i64 = 0, positions: i64 = 0 };
const SeedTotals = struct { reads: i64 = 0, seeds: i64 = 0, with_n: i64 = 0, repetitive: i64 = 0,
     without_hit: i64 = 0, candidates: i64 = 0, passing: i64 = 0 };
const Hit = struct { mismatches: i64, reference: usize, position: usize, strand: usize };
fn hitLess(_: void, a: Hit, b: Hit) bool {
    if (a.mismatches != b.mismatches) return a.mismatches < b.mismatches;
    if (a.reference != b.reference) return a.reference < b.reference;
    return if (a.position != b.position) a.position < b.position else a.strand < b.strand;
}
const Candidate = struct { strand: usize, reference: usize, center: i64 };
fn candidateLess(_: void, a: Candidate, b: Candidate) bool {
    if (a.strand != b.strand) return a.strand < b.strand;
    return if (a.reference != b.reference) a.reference < b.reference else a.center < b.center;
}
const Accepted = struct { score: i64, reference: usize, position: usize, strand: usize, operations: []const u8 };
fn acceptedLess(_: void, a: Accepted, b: Accepted) bool {
    if (a.score != b.score) return a.score > b.score;
    if (a.reference != b.reference) return a.reference < b.reference;
    return if (a.position != b.position) a.position < b.position else a.strand < b.strand;
}
const Mapper = struct {
    reference: ReferenceText,
    forward: fm.Index,
    reverse: fm.Index,
    p: Params,
    searches: SearchTotals = .{},
    seeds: SeedTotals = .{},
    fn locate(self: *const Mapper, row: usize) Position {
        return self.reference.position(self.forward.locate(row).position).?;
    }
    fn mapRead(self: *Mapper, read: d.Read) d.Result {
        const qualities = d.alloc(i64, read.quality.len);
        for (read.quality, qualities) |character, *quality| quality.* = @as(i64, character) - 33;
        var length = read.bases.len;
        while (length > 0 and qualities[length - 1] < self.p.trim_quality) length -= 1;
        var out: d.Result = .{ .read = read, .core = read.bases[0..length], .qualities = qualities,
             .length = length, .trimmed = read.bases.len - length };
        if (length < self.p.minimum_length) return out;
        const oriented = [_][]const u8{ out.core, d.reverseComplement(out.core) };
        const exact = [_]fm.Interval{ self.forward.backwardSearch(oriented[0]), self.forward.backwardSearch(oriented[1]) };
        const maximum = if (!exact[0].empty() or !exact[1].empty()) @as(i64, 1) else self.p.mismatches;
        var hits: std.ArrayList(Hit) = .empty;
        defer hits.deinit(work_allocator);
        for (oriented, 0..) |sequence, strand| {
            const found = search.backtrack(sequence, maximum, self.forward, self.reverse, work_allocator);
            self.searches.calls += 1;
            self.searches.nodes += found.nodes;
            self.searches.leaves += n(found.leaves.len);
            self.searches.positions += found.positions;
            for (found.leaves) |leaf| for (leaf.lower..leaf.upper) |row| {
                const located = self.locate(row);
                workAppend(Hit, &hits, .{ .mismatches = leaf.mismatches, .reference = located.reference,
                     .position = located.offset, .strand = strand });
            };
            work_allocator.free(found.leaves);
        }
        if (hits.items.len > 0) {
            std.mem.sort(Hit, hits.items, {}, hitLess);
            const best = hits.items[0].mismatches;
            var eligible: usize = 0;
            for (hits.items) |hit| {
                out.x0 += @intFromBool(hit.mismatches == best);
                out.x1 += @intFromBool(hit.mismatches == best + 1);
                eligible += @intFromBool(hit.mismatches <= best + 1);
                if (hit.mismatches == best) out.targets |= bit(hit.reference);
            }
            const operations = d.alloc(u8, length);
            @memset(operations, 'M');
            const first = hits.items[0];
            out.primary = describe(first.reference, first.position, first.strand, operations,
                 out, self.reference.references);
            out.other_count = eligible - 1;
            if (out.other_count <= self.p.maximum_alternatives) {
                const others = d.alloc(d.Alignment, out.other_count);
                for (hits.items[1..eligible], others) |hit, *other| other.* = describe(hit.reference,
                     hit.position, hit.strand, operations, out, self.reference.references);
                out.others = others;
            }
            out.mapped = true;
            out.method = if (best == 0) "EXACT" else "MISMATCH";
            out.score = (n(length) - best) * self.p.match - best * self.p.mismatch;
            out.mapq = if (out.x0 >= 2) 0 else if (out.x1 == 0) 60 - 12 * best else @max(30 - 12 * best - 3 * out.x1,
                 1);
            return out;
        }
        out.reason = "NOHIT";
        if (length < self.p.seed_length) return out;
        self.seeds.reads += 1;
        var seen: [2][10][]bool = undefined;
        var accepted_indices: [2][10][]?usize = undefined;
        for (0..2) |strand| for (self.reference.references, 0..) |reference, r| {
            seen[strand][r] = work_allocator.alloc(bool, reference.bases.len + 101) catch @panic("allocation failed");
            @memset(seen[strand][r], false);
            accepted_indices[strand][r] = work_allocator.alloc(?usize, reference.bases.len + 1) catch @panic("allocation failed");
            @memset(accepted_indices[strand][r], null);
        };
        defer for (0..2) |strand| for (0..self.reference.references.len) |r| {
            work_allocator.free(seen[strand][r]);
            work_allocator.free(accepted_indices[strand][r]);
        };
        var candidates: std.ArrayList(Candidate) = .empty;
        defer candidates.deinit(work_allocator);
        for (oriented, 0..) |sequence, strand| {
            var start: usize = 0;
            while (start + self.p.seed_length <= length) : (start += self.p.seed_step) {
                self.seeds.seeds += 1;
                const seed = sequence[start .. start + self.p.seed_length];
                if (std.mem.indexOfScalar(u8, seed, 'N') != null) {
                    self.seeds.with_n += 1;
                    continue;
                }
                const interval = self.forward.backwardSearch(seed);
                if (interval.upper - interval.lower > self.p.maximum_seed_hits) {
                    self.seeds.repetitive += 1;
                    continue;
                }
                if (interval.empty()) {
                    self.seeds.without_hit += 1;
                    continue;
                }
                for (interval.lower..interval.upper) |row| {
                    const located = self.locate(row);
                    const center = n(located.offset) - n(start);
                    const index = u(center + 100);
                    if (!seen[strand][located.reference][index]) {
                        seen[strand][located.reference][index] = true;
                        workAppend(Candidate, &candidates, .{ .strand = strand, .reference = located.reference,
                             .center = center });
                    }
                }
            }
        }
        self.seeds.candidates += n(candidates.items.len);
        std.mem.sort(Candidate, candidates.items, {}, candidateLess);
        var accepted: std.ArrayList(Accepted) = .empty;
        defer accepted.deinit(work_allocator);
        for (candidates.items) |candidate| {
            const alignment = bandedAlignment(oriented[candidate.strand], self.reference.references[candidate.reference].bases,
                 candidate.center, self.p) orelse continue;
            if (100 * alignment.score < self.p.minimum_score * self.p.match * n(length)) continue;
            const index = &accepted_indices[candidate.strand][candidate.reference][alignment.position];
            if (index.* == null) {
                index.* = accepted.items.len;
                workAppend(Accepted, &accepted, .{ .score = alignment.score, .reference = candidate.reference,
                     .position = alignment.position, .strand = candidate.strand, .operations = alignment.operations });
            } else if (alignment.score > accepted.items[index.*.?].score) {
                accepted.items[index.*.?].score = alignment.score;
                accepted.items[index.*.?].operations = alignment.operations;
            }
        }
        self.seeds.passing += n(accepted.items.len);
        if (accepted.items.len == 0) return out;
        std.mem.sort(Accepted, accepted.items, {}, acceptedLess);
        out.score = accepted.items[0].score;
        var second: i64 = 0;
        for (accepted.items) |alignment| {
            if (alignment.score == out.score) {
                out.x0 += 1;
                out.targets |= bit(alignment.reference);
            } else second = @max(second, alignment.score);
        }
        out.x1 = n(accepted.items.len) - out.x0;
        out.other_count = accepted.items.len - 1;
        const first = accepted.items[0];
        out.primary = describe(first.reference, first.position, first.strand, first.operations,
             out, self.reference.references);
        if (out.other_count <= self.p.maximum_alternatives) {
            const others = d.alloc(d.Alignment, out.other_count);
            for (accepted.items[1..], others) |alignment, *other| other.* = describe(alignment.reference,
                 alignment.position, alignment.strand, alignment.operations, out, self.reference.references);
            out.others = others;
        }
        out.mapped = true;
        out.method = "SEED";
        out.mapq = if (out.x0 >= 2) 0 else @divTrunc(60 * (out.score - second), out.score);
        return out;
    }
};
fn runCount(value: []const u8) usize {
    var count: usize = 0;
    for (value, 0..) |character, i| count += @intFromBool(i == 0 or character != value[i - 1]);
    return count;
}
fn indexStatistics(reference: ReferenceText, suffixes: suffix.SuffixArray, forward: fm.Index,
     reverse_suffixes: suffix.SuffixArray, reverse: fm.Index, p: Params) d.Lines {
    const text = reference.text;
    const size = text.len;
    var out: d.Lines = .{};
    out.add("text length {d} sequences {d}", .{ size, reference.references.len });
    for (reference.references, reference.offsets) |item, offset| {
        var gc: i64 = 0;
        for (item.bases) |base| gc += @intFromBool(base == 'G' or base == 'C');
        out.add("sequence {s} length {d} offset {d} gc {s} masked {d}", .{ item.name, item.bases.len,
             offset, ratio(gc, n(item.bases.len)), item.masked });
    }
    var frequencies = [_]usize{0} ** 6;
    for (text) |character| frequencies[suffix.symbolNumber(character)] += 1;
    var row: d.Text = .{};
    row.add("symbols", .{});
    for (alphabet, frequencies) |symbol, count| row.add(" {c} {d}", .{ symbol, count });
    out.add("{s}", .{row.value()});
    out.add("", .{});
    out.add("forward_index", .{});
    out.add("suffix_array rounds {d}", .{suffixes.classes.len - 1});
    for (suffixes.classes, 0..) |count, t| out.add("round {d} prefix_length {d} classes {d}",
         .{ t, @as(usize, 1) << @intCast(t), count });
    const checked = suffix.adjacentCheck(text, suffixes.order);
    out.add("sa_check pairs {d} ordered {d} lcp_sum {d} mean_lcp {s} max_lcp {d}", .{ size - 1,
         checked.ordered, checked.lcp_sum, ratio(checked.lcp_sum, n(size - 1)), checked.maximum });
    out.add("longest_repeat {d} {s} {s}", .{ checked.maximum, reference.label(suffixes.order[checked.row - 1]),
         reference.label(suffixes.order[checked.row]) });
    const base_runs = d.alloc(usize, size + 1);
    @memset(base_runs, 0);
    var i = size;
    while (i > 0) {
        i -= 1;
        if (text[i] != '#' and text[i] != '$') base_runs[i] = base_runs[i + 1] + 1;
    }
    var occurrences: i64 = 0;
    var distinct: i64 = 0;
    var unique: i64 = 0;
    var maximum: i64 = 0;
    var group: i64 = 0;
    var previous: ?usize = null;
    for (suffixes.order) |position| {
        if (base_runs[position] < p.seed_length) continue;
        occurrences += 1;
        if (previous != null and std.mem.eql(u8, text[previous.? .. previous.? + p.seed_length],
             text[position .. position + p.seed_length])) group += 1 else {
            if (group > 0) {
                distinct += 1;
                unique += @intFromBool(group == 1);
                maximum = @max(maximum, group);
            }
            group = 1;
        }
        previous = position;
    }
    if (group > 0) {
        distinct += 1;
        unique += @intFromBool(group == 1);
        maximum = @max(maximum, group);
    }
    out.add("kmers length {d} occurrences {d} distinct {d} unique {d} max_occurrence {d} unique_fraction {s}",
         .{ p.seed_length, occurrences, distinct, unique, maximum, ratio(unique, occurrences) });
    out.add("bwt runs {d} head {s}", .{ runCount(forward.bwt), forward.bwt[0..@min(60, size)] });
    row = .{};
    row.add("c_array", .{});
    for (alphabet, forward.C) |symbol, count| row.add(" {c} {d}", .{ symbol, count });
    out.add("{s}", .{row.value()});
    out.add("occ interval {d} checkpoints {d}", .{ forward.interval, forward.checkpoints.len });
    out.add("sa_sample interval {d} samples {d}", .{ p.sample_interval, forward.sample_count });
    var correct: usize = 0;
    var total_steps: i64 = 0;
    var max_steps: usize = 0;
    for (suffixes.order, 0..) |position, sa_row| {
        const located = forward.locate(sa_row);
        correct += @intFromBool(located.position == position);
        total_steps += n(located.steps);
        max_steps = @max(max_steps, located.steps);
    }
    out.add("locate rows {d} correct {d} total_steps {d} max_steps {d} mean_steps {s}", .{ size,
         correct, total_steps, max_steps, ratio(total_steps, n(size)) });
    out.add("inverse_bwt identical {s}", .{if (d.eq(forward.inverse(), text)) "yes" else "no"});
    out.add("", .{});
    out.add("reverse_index", .{});
    out.add("suffix_array rounds {d}", .{reverse_suffixes.classes.len - 1});
    const reverse_check = suffix.adjacentCheck(reference.reverse, reverse_suffixes.order);
    out.add("sa_check pairs {d} ordered {d}", .{ size - 1, reverse_check.ordered });
    out.add("bwt runs {d} head {s}", .{ runCount(reverse.bwt), reverse.bwt[0..@min(60, size)] });
    out.add("inverse_bwt identical {s}", .{if (d.eq(reverse.inverse(), reference.reverse)) "yes" else "no"});
    out.add("", .{});
    out.add("direct_sort", .{});
    var checks: usize = 0;
    for (reference.references) |item| if (item.bases.len <= p.direct_limit) {
        const sequence = d.fmt("{s}$", .{item.bases});
        const doubled = suffix.build(sequence);
        out.add("{s} length {d} rounds {d} identical {s}", .{ item.name, sequence.len, doubled.classes.len - 1,
             if (std.mem.eql(usize, doubled.order, suffix.directSort(sequence))) "yes" else "no" });
        checks += 1;
    };
    if (checks == 0) out.add("none", .{});
    const occurrence_bytes = 24 * n(forward.checkpoints.len);
    const sample_bytes = 4 * n(forward.sample_count);
    const bitmap_bytes = n((size + 7) / 8);
    const total_bytes = n(size) + occurrence_bytes + sample_bytes + bitmap_bytes;
    out.add("", .{});
    out.add("index_size bwt_bytes {d} occ_bytes {d} sample_bytes {d} bitmap_bytes {d} total_bytes {d} full_bytes {d} ratio {s}",
         .{ size, occurrence_bytes, sample_bytes, bitmap_bytes, total_bytes, 5 * size, ratio(total_bytes,
         5 * n(size)) });
    return out;
}
const PileupReports = struct { coverage: d.Lines, variants: d.Lines };
fn coverageAndVariants(results: []const d.Result, references: []const d.Reference, p: Params) PileupReports {
    const Pileup = [4][2]i64;
    const depths = d.alloc([]i64, references.len);
    const starts = d.alloc([]i64, references.len);
    const pileups = d.alloc([]Pileup, references.len);
    for (references, depths, starts, pileups) |reference, *depth, *start, *pileup| {
        depth.* = d.alloc(i64, reference.bases.len);
        @memset(depth.*, 0);
        start.* = d.alloc(i64, reference.bases.len);
        @memset(start.*, 0);
        pileup.* = d.alloc(Pileup, reference.bases.len);
        @memset(pileup.*, std.mem.zeroes(Pileup));
    }
    for (results) |result| {
        if (!result.mapped) continue;
        const alignment = result.primary;
        const r = alignment.reference;
        if (result.mapq == 0) starts[r][alignment.position] += 1;
        if (result.mapq < p.coverage_mapq) continue;
        for (alignment.pairs) |pair| {
            const i = pair.read;
            const j = pair.reference;
            depths[r][j] += 1;
            const base = alignment.oriented[i];
            const cycle = if (alignment.strand == 0) i + 1 else result.length - i;
            if (base != 'N' and result.qualities[cycle - 1] >= p.variant_quality) pileups[r][j][baseIndex(base)][alignment.strand] += 1;
        }
    }
    var out: PileupReports = .{ .coverage = .{}, .variants = .{} };
    out.coverage.add("window {d} min_mapq {d}", .{ p.coverage_window, p.coverage_mapq });
    out.variants.add("min_depth {d} min_base_quality {d} min_alt_percent {d} hom_percent {d}",
         .{ p.variant_depth, p.variant_quality, p.variant_percent, p.homozygous_percent });
    var callable: i64 = 0;
    var variant_count: i64 = 0;
    var heterozygous: i64 = 0;
    var homozygous: i64 = 0;
    for (references, 0..) |reference, r| {
        const length = reference.bases.len;
        var covered: i64 = 0;
        var total: i64 = 0;
        var maximum: i64 = 0;
        for (depths[r]) |depth| {
            covered += @intFromBool(depth > 0);
            total += depth;
            maximum = @max(maximum, depth);
        }
        out.coverage.add("reference {s} length {d} covered {d} breadth {s} mean_depth {s} max_depth {d}",
             .{ reference.name, length, covered, ratio(covered, n(length)), ratio(total, n(length)),
             maximum });
        var histogram = [_]i64{0} ** 401;
        for (depths[r]) |depth| histogram[u(depth)] += 1;
        var row: d.Text = .{};
        row.add("depth_histogram", .{});
        for (0..u(maximum) + 1) |depth| row.add(" {d}:{d}", .{ depth, histogram[depth] });
        out.coverage.add("{s}", .{row.value()});
        var first: usize = 0;
        while (first < length) : (first += p.coverage_window) {
            const last = @min(first + p.coverage_window, length);
            const size = last - first;
            var gc: i64 = 0;
            var sum: i64 = 0;
            var zero: i64 = 0;
            var mapq_zero: i64 = 0;
            var largest: i64 = 0;
            for (first..last) |j| {
                gc += @intFromBool(reference.bases[j] == 'G' or reference.bases[j] == 'C');
                sum += depths[r][j];
                largest = @max(largest, depths[r][j]);
                zero += @intFromBool(depths[r][j] == 0);
                mapq_zero += starts[r][j];
            }
            const bar = d.alloc(u8, u(@divTrunc(10 * sum, n(size))));
            @memset(bar, '#');
            out.coverage.add("{s} {d} {d} gc {s} sum {d} mean {s} max {d} zero {d} mapq0 {d} |{s}",
                 .{ reference.name, first + 1, last, ratio(gc, n(size)), sum, ratio(sum, n(size)),
                 largest, zero, mapq_zero, bar });
        }
        for (pileups[r], 0..) |strands, j| {
            var counts = [_]i64{0} ** 4;
            var depth: i64 = 0;
            for (strands, counts[0..]) |pair, *count| {
                count.* = pair[0] + pair[1];
                depth += count.*;
            }
            if (depth < p.variant_depth) continue;
            callable += 1;
            var alternative: ?usize = null;
            for (0..4) |base| if (bases[base] != reference.bases[j] and (alternative == null or counts[base] > counts[alternative.?])) {
                alternative = base;
            };
            const base = alternative.?;
            const count = counts[base];
            if (count < 2 or 100 * count < p.variant_percent * depth) continue;
            const homo = 100 * count >= p.homozygous_percent * depth;
            homozygous += @intFromBool(homo);
            heterozygous += @intFromBool(!homo);
            variant_count += 1;
            out.variants.add("{s} {d} {c}>{c} depth {d} alt {d} fraction {s} genotype {s} strands {d} {d} counts {d} {d} {d} {d}",
                 .{ reference.name, j + 1, reference.bases[j], bases[base], depth, count, ratio(count,
                 depth), if (homo) "1/1" else "0/1", strands[base][0], strands[base][1], counts[0],
                 counts[1], counts[2], counts[3] });
        }
    }
    out.variants.add("callable {d} variants {d} heterozygous {d} homozygous {d}", .{ callable,
         variant_count, heterozygous, homozygous });
    return out;
}
fn errorStatistics(results: []const d.Result, references: []const d.Reference) d.Lines {
    var maximum_cycle: usize = 0;
    var cycles = [_][2]i64{[_]i64{0} ** 2} ** 101;
    var substitutions = [_][5]i64{[_]i64{0} ** 5} ** 4;
    var quality_counts = [_]i64{0} ** 2;
    var quality_sums = [_]i64{0} ** 2;
    var quality_bins = [_][2]i64{[_]i64{0} ** 2} ** 5;
    var operations = [_]i64{0} ** 4;
    var events = [_]i64{0} ** 2;
    var indel_bases = [_]i64{0} ** 2;
    for (results) |result| {
        maximum_cycle = @max(maximum_cycle, result.read.bases.len);
        if (!result.mapped) continue;
        const alignment = result.primary;
        for (alignment.operations) |operation| operations[
            switch (operation) {
                'M' => 0,
                'I' => 1,
                else => 2,
            }
        ] += 1;
        operations[3] += n(result.trimmed);
        if (result.x0 != 1) continue;
        const reference = references[alignment.reference].bases;
        for (alignment.pairs) |pair| {
            const i = pair.read;
            const j = pair.reference;
            const observed = alignment.oriented[i];
            const expected = reference[j];
            const mismatch: usize = @intFromBool(observed != expected);
            const cycle = if (alignment.strand == 0) i + 1 else result.length - i;
            const quality = result.qualities[cycle - 1];
            cycles[cycle][0] += 1;
            cycles[cycle][1] += n(mismatch);
            substitutions[baseIndex(expected)][baseIndex(observed)] += 1;
            quality_counts[mismatch] += 1;
            quality_sums[mismatch] += quality;
            const bin = @min(u(@divTrunc(quality, 10)), 4);
            quality_bins[bin][0] += 1;
            quality_bins[bin][1] += n(mismatch);
        }
        for (runs(alignment.operations)) |run| if (run.operation == 'I' or run.operation == 'D') {
            const kind: usize = if (run.operation == 'I') 0 else 1;
            events[kind] += 1;
            indel_bases[kind] += n(run.count);
        };
    }
    const aligned = quality_counts[0] + quality_counts[1];
    const mismatches = quality_counts[1];
    var out: d.Lines = .{};
    out.add("error_profile aligned_bases {d} mismatches {d} rate {s}", .{ aligned, mismatches,
         ratio(mismatches, aligned) });
    out.add("substitutions", .{});
    out.add("ref A C G T N", .{});
    for (substitutions, 0..) |counts, base| out.add("{c} {d} {d} {d} {d} {d}", .{ bases[base],
         counts[0], counts[1], counts[2], counts[3], counts[4] });
    out.add("mismatch_by_cycle", .{});
    for (1..maximum_cycle + 1) |cycle| out.add("cycle {d} aligned {d} mismatches {d} rate {s}",
         .{ cycle, cycles[cycle][0], cycles[cycle][1], ratio(cycles[cycle][1], cycles[cycle][0]) });
    out.add("quality matched {d} mean {s} mismatched {d} mean {s}", .{ quality_counts[0], ratio(quality_sums[0],
         quality_counts[0]), quality_counts[1], ratio(quality_sums[1], quality_counts[1]) });
    out.add("quality_bins", .{});
    for ([_][]const u8{ "0-9", "10-19", "20-29", "30-39", "40-" }, quality_bins) |range, counts| out.add("{s} aligned {d} mismatches {d} rate {s}",
         .{ range, counts[0], counts[1], ratio(counts[1], counts[0]) });
    out.add("cigar M {d} I {d} D {d} S {d}", .{ operations[0], operations[1], operations[2], operations[3] });
    out.add("indels insertions {d} {d} deletions {d} {d}", .{ events[0], indel_bases[0], events[1], indel_bases[1] });
    return out;
}
const Target = struct { names: []const u8, count: i64 = 0 };
fn targetLess(_: void, a: Target, b: Target) bool {
    return std.mem.order(u8, a.names, b.names) == .lt;
}
fn mappingStatistics(results: []const d.Result, references: []const d.Reference, searches: SearchTotals,
     seeds: SeedTotals) d.Lines {
    var mapped: i64 = 0;
    var unique: i64 = 0;
    var short_reads: i64 = 0;
    var no_hit: i64 = 0;
    var trimmed: i64 = 0;
    var trimmed_bases: i64 = 0;
    var forward: i64 = 0;
    var reverse: i64 = 0;
    var minimum_length: usize = 101;
    var maximum_length: usize = 0;
    var n_reads: i64 = 0;
    var n_bases: i64 = 0;
    var n_mapped: i64 = 0;
    var method_counts = [_]i64{0} ** 3;
    const reference_counts = d.alloc([4]i64, references.len);
    @memset(reference_counts, [_]i64{0} ** 4);
    var length_bins = [_][3]i64{[_]i64{0} ** 3} ** 11;
    var mapq_counts = [_]i64{0} ** 61;
    var maximum_nm: i64 = 0;
    var targets: std.ArrayList(Target) = .empty;
    for (results) |result| {
        trimmed += @intFromBool(result.trimmed > 0);
        trimmed_bases += n(result.trimmed);
        minimum_length = @min(minimum_length, result.length);
        maximum_length = @max(maximum_length, result.length);
        var count: i64 = 0;
        for (result.read.bases) |base| count += @intFromBool(base == 'N');
        if (count > 0) {
            n_reads += 1;
            n_bases += count;
            n_mapped += @intFromBool(result.mapped);
        }
        const bin = result.length / 10;
        length_bins[bin][0] += 1;
        length_bins[bin][1] += @intFromBool(result.mapped);
        length_bins[bin][2] += @intFromBool(result.mapped and result.x0 == 1);
        if (!result.mapped) {
            short_reads += @intFromBool(d.eq(result.reason, "SHORT"));
            no_hit += @intFromBool(d.eq(result.reason, "NOHIT"));
            continue;
        }
        mapped += 1;
        unique += @intFromBool(result.x0 == 1);
        const method: usize = if (d.eq(result.method, "EXACT")) 0 else if (d.eq(result.method, "MISMATCH")) 1 else 2;
        method_counts[method] += 1;
        forward += @intFromBool(result.primary.strand == 0);
        reverse += @intFromBool(result.primary.strand == 1);
        mapq_counts[u(result.mapq)] += 1;
        maximum_nm = @max(maximum_nm, result.primary.nm);
        const r = result.primary.reference;
        reference_counts[r][0] += 1;
        reference_counts[r][1] += @intFromBool(result.x0 == 1);
        reference_counts[r][2 + result.primary.strand] += 1;
        if (result.x0 >= 2) {
            var names: d.Text = .{};
            for (references, 0..) |reference, i| if (result.targets & bit(i) != 0) {
                names.add("{s}{s}", .{ if (names.value().len == 0) "" else "+", reference.name });
            };
            var found: ?usize = null;
            for (targets.items, 0..) |target, i| if (d.eq(target.names, names.value())) {
                found = i;
                break;
            };
            if (found == null) {
                found = targets.items.len;
                d.append(Target, &targets, .{ .names = names.value() });
            }
            targets.items[found.?].count += 1;
        }
    }
    const nm_counts = d.alloc(i64, u(maximum_nm) + 1);
    @memset(nm_counts, 0);
    for (results) |result| if (result.mapped) {
        nm_counts[u(result.primary.nm)] += 1;
    };
    var out: d.Lines = .{};
    out.add("reads total {d} trimmed {d} trimmed_bases {d} short {d}", .{ results.len, trimmed,
         trimmed_bases, short_reads });
    out.add("mapped {d} rate {s} unique {d} multi {d} unmapped {d}", .{ mapped, ratio(mapped,
         n(results.len)), unique, mapped - unique, n(results.len) - mapped });
    out.add("unmapped short {d} nohit {d}", .{ short_reads, no_hit });
    out.add("method exact {d} mismatch {d} seed {d}", .{ method_counts[0], method_counts[1], method_counts[2] });
    out.add("strand forward {d} reverse {d}", .{ forward, reverse });
    for (references, reference_counts) |reference, counts| out.add("reference {s} mapped {d} unique {d} forward {d} reverse {d}",
         .{ reference.name, counts[0], counts[1], counts[2], counts[3] });
    out.add("length_bins", .{});
    var lower = minimum_length / 10 * 10;
    while (lower <= maximum_length / 10 * 10) : (lower += 10) {
        const counts = length_bins[lower / 10];
        out.add("{d}-{d} reads {d} mapped {d} unique {d}", .{ lower, lower + 9, counts[0], counts[1], counts[2] });
    }
    out.add("n_reads {d} n_bases {d} mapped {d}", .{ n_reads, n_bases, n_mapped });
    out.add("multi_targets", .{});
    if (targets.items.len == 0) out.add("none", .{}) else {
        std.mem.sort(Target, targets.items, {}, targetLess);
        for (targets.items) |target| out.add("{s} {d}", .{ target.names, target.count });
    }
    out.add("mapq_histogram", .{});
    var quality: usize = 61;
    while (quality > 0) {
        quality -= 1;
        if (mapq_counts[quality] > 0) out.add("{d} {d}", .{ quality, mapq_counts[quality] });
    }
    out.add("nm_histogram", .{});
    for (nm_counts, 0..) |count, value| if (count > 0) out.add("{d} {d}", .{ value, count });
    out.extend(errorStatistics(results, references));
    out.add("search dfs_calls {d} dfs_nodes {d} dfs_leaves {d} dfs_positions {d}", .{ searches.calls,
         searches.nodes, searches.leaves, searches.positions });
    out.add("seeds reads {d} seeds {d} with_n {d} repetitive {d} without_hit {d} candidates {d} passing {d}",
         .{ seeds.reads, seeds.seeds, seeds.with_n, seeds.repetitive, seeds.without_hit, seeds.candidates,
         seeds.passing });
    return out;
}
pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    d.allocator = arena.allocator();
    work_allocator = init.gpa;
    const input = try d.readInputs(init.io);
    const p = Params.init(input);
    const reference = ReferenceText.init(input.references);
    const suffixes = suffix.build(reference.text);
    const reverse_suffixes = suffix.build(reference.reverse);
    const forward = fm.Index.init(reference.text, suffixes.order, p.occ_interval, p.sample_interval);
    const reverse = fm.Index.init(reference.reverse, reverse_suffixes.order, p.occ_interval, null);
    const index = indexStatistics(reference, suffixes, forward, reverse_suffixes, reverse, p);
    var mapper: Mapper = .{ .reference = reference, .forward = forward, .reverse = reverse, .p = p };
    const results = d.alloc(d.Result, input.reads.len);
    for (input.reads, results) |read, *result| result.* = mapper.mapRead(read);
    var sam_lines = sam.header(input.references);
    for (results) |result| sam_lines.add("{s}", .{sam.record(result, input.references, p.maximum_alternatives)});
    const pileup = coverageAndVariants(results, input.references, p);
    const summary = mappingStatistics(results, input.references, mapper.searches, mapper.seeds);
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try sam.save(init.io, "alignments.sam", sam_lines);
    try sam.save(init.io, "coverage.txt", pileup.coverage);
    try sam.save(init.io, "variants.txt", pileup.variants);
    try sam.save(init.io, "index_stats.txt", index);
    try sam.save(init.io, "summary.txt", summary);
}
