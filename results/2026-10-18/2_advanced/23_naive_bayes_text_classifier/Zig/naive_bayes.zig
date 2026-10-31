const std = @import("std");
const e = @import("evaluation.zig");
const t = @import("tokenizer.zig");
const v = @import("vocabulary.zig");

pub const Counts = struct {
    classes: usize,
    size: usize,
    document_total: usize,
    documents: [8]usize = @splat(0),
    occurrences: []i64,
    containing: []i64,
    term_totals: []i64,
    totals: [8]i64 = @splat(0),
    total: i64 = 0,
};
pub fn trainingCounts(memory: std.mem.Allocator, sequences: []const v.Encoded, documents: []const *const t.Document, classes: usize, size: usize) Counts {
    var counts: Counts = .{ .classes = classes, .size = size, .document_total = documents.len, .occurrences = e.take(i64, memory, classes * size), .containing = e.take(i64, memory, classes * size), .term_totals = e.take(i64, memory, size) };
    @memset(counts.occurrences, 0);
    @memset(counts.containing, 0);
    @memset(counts.term_totals, 0);
    for (sequences, documents) |sequence, document| {
        const label = document.label.?;
        counts.documents[label] += 1;
        for (sequence.terms) |term| counts.occurrences[label * size + term] += 1;
        for (sequence.first) |term| counts.containing[label * size + term] += 1;
    }
    for (0..classes) |label| {
        for (0..size) |term| {
            const value = counts.occurrences[label * size + term];
            counts.totals[label] += value;
            counts.term_totals[term] += value;
        }
        counts.total += counts.totals[label];
    }
    return counts;
}
pub fn smoothedLog(count: i64, total: i64, alpha: i64, outcomes: usize) f64 {
    const numerator = 100 * count + alpha;
    const denominator = 100 * total + alpha * e.n(outcomes);
    return @log(e.f(numerator) / e.f(denominator));
}
pub const Prediction = struct {
    label: usize = 0,
    ranking: [8]usize = @splat(0),
    score: f64 = 0,
    scores: [8]f64 = @splat(0),
    probabilities: [8]f64 = @splat(0),
    normalizer: f64 = 0,
    margin: f64 = 0,
};
pub fn posterior(scores: []const f64) Prediction {
    var result: Prediction = .{};
    for (scores, 0..) |score, label| {
        result.scores[label] = score;
        var position = label;
        while (position > 0 and score > scores[result.ranking[position - 1]]) : (position -= 1) result.ranking[position] = result.ranking[position - 1];
        result.ranking[position] = label;
    }
    result.label = result.ranking[0];
    for (scores, 0..) |score, label| {
        result.probabilities[label] = @exp(score - scores[result.label]);
        result.normalizer += result.probabilities[label];
    }
    for (0..scores.len) |label| result.probabilities[label] /= result.normalizer;
    result.score = result.probabilities[result.label];
    result.margin = scores[result.label] - scores[result.ranking[1]];
    return result;
}
pub const Model = struct {
    kind: usize,
    classes: usize,
    size: usize,
    priors: [8]f64 = @splat(0),
    base: [8]f64 = @splat(0),
    weights: []f64,

    pub fn predict(self: *const Model, sequence: v.Encoded) Prediction {
        const terms = if (self.kind == 1) sequence.first else sequence.terms;
        var scores: [8]f64 = undefined;
        for (0..self.classes) |label| {
            var score = self.base[label];
            for (terms) |term| score += self.weights[label * self.size + term];
            scores[label] = score + self.priors[label];
        }
        return posterior(scores[0..self.classes]);
    }
};
pub fn train(memory: std.mem.Allocator, kind: usize, counts: *const Counts, alpha: i64) Model {
    var model: Model = .{ .kind = kind, .classes = counts.classes, .size = counts.size, .weights = e.take(f64, memory, counts.classes * counts.size) };
    for (0..model.classes) |label| {
        model.priors[label] = @log(e.f(counts.documents[label]) / e.f(counts.document_total));
        for (0..model.size) |term| {
            const index = label * model.size + term;
            if (kind == 0) {
                model.weights[index] = smoothedLog(counts.occurrences[index], counts.totals[label], alpha, model.size);
            } else if (kind == 1) {
                const present_count = counts.containing[index];
                const document_count = e.n(counts.documents[label]);
                const present = smoothedLog(present_count, document_count, alpha, 2);
                const absent = smoothedLog(document_count - present_count, document_count, alpha, 2);
                model.base[label] += absent;
                model.weights[index] = present - absent;
            } else model.weights[index] = -smoothedLog(counts.term_totals[term] - counts.occurrences[index], counts.total - counts.totals[label], alpha, model.size);
        }
    }
    return model;
}
