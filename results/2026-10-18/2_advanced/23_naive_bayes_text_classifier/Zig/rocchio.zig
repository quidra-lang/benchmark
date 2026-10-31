const std = @import("std");
const e = @import("evaluation.zig");
const t = @import("tokenizer.zig");
const v = @import("vocabulary.zig");
const nb = @import("naive_bayes.zig");

const Component = struct { term: usize, frequency: usize, value: f64 = 0 };
fn componentLessThan(_: void, first: Component, second: Component) bool { return first.term < second.term; }
pub const Model = struct {
    classes: usize,
    size: usize,
    idf: []f64,
    centroids: []f64,
    lengths: [8]f64 = @splat(0),

    fn vector(self: *const Model, sequence: v.Encoded, components: []Component) f64 {
        for (sequence.first, sequence.frequencies, components) |term, frequency, *component| component.* = .{ .term = term, .frequency = frequency };
        std.mem.sort(Component, components, {}, componentLessThan);
        var squares: f64 = 0;
        for (components) |*component| {
            component.value = e.f(component.frequency) * self.idf[component.term];
            squares += component.value * component.value;
        }
        return @sqrt(squares);
    }
    pub fn predict(self: *const Model, sequence: v.Encoded) nb.Prediction {
        var storage: [600]Component = undefined;
        const components = storage[0..sequence.first.len];
        const length = self.vector(sequence, components);
        var prediction: nb.Prediction = .{};
        for (0..self.classes) |label| {
            var similarity: f64 = 0;
            if (length > 0 and self.lengths[label] > 0) {
                var product: f64 = 0;
                for (components) |component| product += component.value * self.centroids[label * self.size + component.term];
                similarity = product / (length * self.lengths[label]);
            }
            prediction.scores[label] = similarity;
            var position = label;
            while (position > 0 and similarity > prediction.scores[prediction.ranking[position - 1]]) : (position -= 1) prediction.ranking[position] = prediction.ranking[position - 1];
            prediction.ranking[position] = label;
        }
        prediction.label = prediction.ranking[0];
        prediction.score = prediction.scores[prediction.label];
        return prediction;
    }
};

pub fn train(memory: std.mem.Allocator, sequences: []const v.Encoded, documents: []const *const t.Document, classes: usize, vocabulary: v.Vocabulary) Model {
    const size = vocabulary.terms.len;
    var model: Model = .{ .classes = classes, .size = size, .idf = e.take(f64, memory, size), .centroids = e.take(f64, memory, classes * size) };
    @memset(model.centroids, 0);
    var class_sizes: [8]usize = @splat(0);
    for (vocabulary.frequencies, model.idf) |frequency, *value| value.* = @log(e.f(documents.len) / e.f(frequency));
    for (sequences, documents) |sequence, document| {
        const label = document.label.?;
        class_sizes[label] += 1;
        var storage: [600]Component = undefined;
        const components = storage[0..sequence.first.len];
        const length = model.vector(sequence, components);
        if (length > 0) for (components) |component| { model.centroids[label * size + component.term] += component.value / length; };
    }
    for (0..classes) |label| {
        var squares: f64 = 0;
        for (0..size) |term| {
            const value = &model.centroids[label * size + term];
            value.* /= e.f(class_sizes[label]);
            squares += value.* * value.*;
        }
        model.lengths[label] = @sqrt(squares);
    }
    return model;
}
