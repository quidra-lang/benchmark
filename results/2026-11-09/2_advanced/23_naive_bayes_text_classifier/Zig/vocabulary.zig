const std = @import("std");
const t = @import("tokenizer.zig");
const e = @import("evaluation.zig");
pub const missing = std.math.maxInt(usize);
pub const RankedTerm = struct { term: usize, frequency: usize, score: f64, best_class: usize };
pub const Encoded = struct { terms: []const usize, first: []const usize, frequencies: []const usize };
pub const Vocabulary = struct {
    term_count: usize,
    candidate_count: usize,
    terms: []usize,
    frequencies: []usize,
    map: []usize,
    ranking: []RankedTerm,

    pub fn encode(self: Vocabulary, memory: std.mem.Allocator, terms: []const usize) Encoded {
        const data = e.take(usize, memory, 3 * terms.len);
        const ordered = data[0..terms.len];
        const first = data[terms.len .. 2 * terms.len];
        const frequencies = data[2 * terms.len ..];
        @memset(frequencies, 0);
        var buckets: [2048]usize = @splat(0);
        var length: usize = 0;
        var distinct: usize = 0;
        for (terms) |global| {
            const term = self.map[global];
            if (term == missing) continue;
            ordered[length] = term;
            length += 1;
            var position = (term *% 2654435761) % 2048;
            while (buckets[position] != 0 and first[buckets[position] - 1] != term) position = (position + 1) % 2048;
            if (buckets[position] == 0) {
                first[distinct] = term;
                distinct += 1;
                buckets[position] = distinct;
            }
            frequencies[buckets[position] - 1] += 1;
        }
        return .{ .terms = ordered[0..length], .first = first[0..distinct], .frequencies = frequencies[0..distinct] };
    }
};
fn chiSquare(with_term: i64, frequency: i64, class_size: i64, total: i64) f64 {
    const others_with = frequency - with_term;
    const without = class_size - with_term;
    const others_without = total - class_size - others_with;
    const difference = with_term * others_without - others_with * without;
    const numerator = total * difference * difference;
    const denominator = frequency * (total - frequency) * class_size * (total - class_size);
    return if (denominator == 0) 0 else e.f(numerator) / e.f(denominator);
}
fn rankedLessThan(_: void, first: RankedTerm, second: RankedTerm) bool {
    return if (first.score != second.score) first.score > second.score else std.mem.order(u8, t.name(first.term), t.name(second.term)) == .lt;
}
fn termLessThan(_: void, first: usize, second: usize) bool { return std.mem.order(u8, t.name(first), t.name(second)) == .lt; }

pub fn build(memory: std.mem.Allocator, documents: []const *const t.Document, bigrams: bool, classes: usize, min_df: usize, size: usize) Vocabulary {
    var scratch = std.heap.ArenaAllocator.init(memory);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    const total_terms = t.count();
    const counts = e.take(usize, temporary, total_terms * classes);
    const seen = e.take(usize, temporary, total_terms);
    @memset(counts, 0);
    @memset(seen, 0);
    var class_sizes: [8]usize = @splat(0);
    for (documents, 1..) |document, serial| {
        const label = document.label.?;
        class_sizes[label] += 1;
        for (document.tokens.terms(bigrams)) |term| {
            if (seen[term] == serial) continue;
            seen[term] = serial;
            counts[term * classes + label] += 1;
        }
    }
    var ranking: std.ArrayList(RankedTerm) = .empty;
    var terms_present: usize = 0;
    for (0..total_terms) |term| {
        var frequency: usize = 0;
        for (0..classes) |label| frequency += counts[term * classes + label];
        if (frequency > 0) terms_present += 1;
        if (frequency < min_df) continue;
        var entry: RankedTerm = .{ .term = term, .frequency = frequency, .score = chiSquare(e.n(counts[term * classes]), e.n(frequency), e.n(class_sizes[0]), e.n(documents.len)), .best_class = 0 };
        for (1..classes) |label| {
            const score = chiSquare(e.n(counts[term * classes + label]), e.n(frequency), e.n(class_sizes[label]), e.n(documents.len));
            if (score > entry.score) { entry.score = score; entry.best_class = label; }
        }
        ranking.append(temporary, entry) catch @panic("allocation failed");
    }
    std.mem.sort(RankedTerm, ranking.items, {}, rankedLessThan);
    const selected = if (size > 0) @min(size, ranking.items.len) else ranking.items.len;
    const ranked = e.take(RankedTerm, memory, selected);
    @memcpy(ranked, ranking.items[0..selected]);
    const terms = e.take(usize, memory, selected);
    const frequencies = e.take(usize, memory, selected);
    const map = e.take(usize, memory, total_terms);
    @memset(map, missing);
    for (ranked, terms) |entry, *term| term.* = entry.term;
    std.mem.sort(usize, terms, {}, termLessThan);
    for (terms, 0..) |term, i| {
        map[term] = i;
        frequencies[i] = 0;
        for (0..classes) |label| frequencies[i] += counts[term * classes + label];
    }
    return .{ .term_count = terms_present, .candidate_count = ranking.items.len, .terms = terms, .frequencies = frequencies, .map = map, .ranking = ranked };
}
