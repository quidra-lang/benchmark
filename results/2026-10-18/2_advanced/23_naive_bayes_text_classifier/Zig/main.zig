const std = @import("std");
const e = @import("evaluation.zig");
const t = @import("tokenizer.zig");
const v = @import("vocabulary.zig");
const nb = @import("naive_bayes.zig");
const rocchio = @import("rocchio.zig");
const model_names = [_][]const u8{ "multinomial", "bernoulli", "complement", "rocchio", "vote" };

fn hundredths(text: []const u8) i64 {
    const fields = e.split(text, '.');
    return e.number(fields[0]) * 100 + e.number(fields[1]);
}
fn hundredthsText(value: i64) []const u8 { return e.fmt("{d}.{d:0>2}", .{ @divTrunc(value, 100), @mod(value, 100) }); }
fn classIndex(classes: []const []const u8, name: []const u8) usize {
    for (classes, 0..) |candidate, i| if (e.eq(candidate, name)) return i;
    unreachable;
}
fn stringLessThan(_: void, first: []const u8, second: []const u8) bool { return std.mem.order(u8, first, second) == .lt; }
fn writeLines(io: std.Io, name: []const u8, source: e.Lines) !void {
    var text: e.Text = .{};
    for (source.data.items) |line| text.add("{s}\n", .{line});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = e.fmt("output/{s}", .{name}), .data = text.value() });
}

const Settings = struct {
    alphas: []i64,
    min_df: usize,
    features: usize,
    bigrams: bool,
    top: usize,
    curve: []usize,
    sizes: []usize,
    thresholds: []i64,
    lengths: []usize,
    iterations: usize,
    weight: i64,
    resamples: usize,
    seed: i64,
};
fn readSizes(fields: []const []const u8) []usize {
    const result = e.alloc(usize, fields.len - 1);
    for (fields[1..], result) |text, *value| value.* = e.u(e.number(text));
    return result;
}
fn readHundredths(fields: []const []const u8) []i64 {
    const result = e.alloc(i64, fields.len - 1);
    for (fields[1..], result) |text, *value| value.* = hundredths(text);
    return result;
}
fn readInput(io: std.Io, name: []const u8) ![]const []const u8 {
    return e.lines(try std.Io.Dir.cwd().readFileAlloc(io, e.fmt("input/{s}", .{name}), e.allocator, .unlimited));
}

const Training = struct {
    arena: *std.heap.ArenaAllocator,
    bigrams: bool,
    vocabulary: v.Vocabulary,
    counts: nb.Counts,
    rocchio_model: rocchio.Model,
    models: [3]nb.Model = undefined,

    fn create(backing: std.mem.Allocator, documents: []const *const t.Document, bigrams: bool, classes: usize, min_df: usize, size: usize) Training {
        const arena = &e.alloc(std.heap.ArenaAllocator, 1)[0];
        arena.* = std.heap.ArenaAllocator.init(backing);
        const memory = arena.allocator();
        const vocabulary = v.build(memory, documents, bigrams, classes, min_df, size);
        var scratch = std.heap.ArenaAllocator.init(backing);
        defer scratch.deinit();
        const sequences = e.take(v.Encoded, scratch.allocator(), documents.len);
        for (documents, sequences) |document, *sequence| sequence.* = vocabulary.encode(scratch.allocator(), document.tokens.terms(bigrams));
        return .{ .arena = arena, .bigrams = bigrams, .vocabulary = vocabulary, .counts = nb.trainingCounts(memory, sequences, documents, classes, vocabulary.terms.len), .rocchio_model = rocchio.train(memory, sequences, documents, classes, vocabulary) };
    }
    fn deinit(self: *Training) void { self.arena.deinit(); }
    fn train(self: *Training, alphas: [3]i64) void {
        for (alphas, 0..) |alpha, kind| self.models[kind] = nb.train(self.arena.allocator(), kind, &self.counts, alpha);
    }
    fn classify(self: *const Training, model: usize, sequence: v.Encoded) nb.Prediction {
        return if (model == 3) self.rocchio_model.predict(sequence) else self.models[model].predict(sequence);
    }
};
const CrossValidationRun = struct {
    predictions: [1500]usize = @splat(0),
    fold_correct: [5]usize = @splat(0),
    evaluation: e.Evaluation = undefined,
};
const FoldSummary = struct { train: usize, validate: usize, candidates: usize, vocabulary: usize };

const Experiment = struct {
    backing: std.mem.Allocator,
    settings: Settings,
    classes: []const []const u8,
    training: []t.Document,
    tests: []t.Document,
    unlabelled: []t.Document,
    labelled: []usize,
    truths: []usize,
    cv: [3][10]CrossValidationRun = @splat(@splat(.{})),
    rocchio_cv: CrossValidationRun = .{},
    selected: [3]usize = @splat(0),
    folds: [5]FoldSummary = undefined,
    final: Training = undefined,
    test_sequences: []v.Encoded = undefined,
    predictions: [5][500]nb.Prediction = @splat(@splat(.{})),
    correct: [5][500]bool = @splat(@splat(false)),

    fn load(io: std.Io, backing: std.mem.Allocator) !*Experiment {
        const parameters = try readInput(io, "params.txt");
        var fields: [12][]const []const u8 = undefined;
        for (parameters, 0..) |line, i| fields[i] = e.split(line, ' ');
        const settings: Settings = .{ .alphas = readHundredths(fields[0]), .min_df = e.u(e.number(fields[1][1])), .features = e.u(e.number(fields[2][1])), .bigrams = e.eq(fields[3][1], "yes"), .top = e.u(e.number(fields[4][1])), .curve = readSizes(fields[5]), .sizes = readSizes(fields[6]), .thresholds = readHundredths(fields[7]), .lengths = readSizes(fields[8]), .iterations = e.u(e.number(fields[9][1])), .weight = hundredths(fields[10][1]), .resamples = e.u(e.number(fields[11][1])), .seed = e.number(fields[11][2]) };
        const stopwords = try readInput(io, "stopwords.txt");
        const train_lines = try readInput(io, "train.txt");
        var classes: std.ArrayList([]const u8) = .empty;
        for (train_lines) |line| {
            const name = e.split(line, '\t')[0];
            var present = false;
            for (classes.items) |candidate| if (e.eq(candidate, name)) { present = true; break; };
            if (!present) e.append([]const u8, &classes, name);
        }
        std.mem.sort([]const u8, classes.items, {}, stringLessThan);
        const training = e.alloc(t.Document, train_lines.len);
        for (train_lines, training, 1..) |line, *document, number| {
            const values = e.split(line, '\t');
            document.* = .{ .name = e.fmt("{d}", .{number}), .label = classIndex(classes.items, values[0]), .tokens = t.tokenize(values[1], stopwords) };
        }
        const test_lines = try readInput(io, "test.txt");
        const tests = e.alloc(t.Document, test_lines.len);
        var labelled: std.ArrayList(usize) = .empty;
        var truths: std.ArrayList(usize) = .empty;
        for (test_lines, tests, 0..) |line, *document, i| {
            const values = e.split(line, '\t');
            const label = if (e.eq(values[1], "?")) null else classIndex(classes.items, values[1]);
            document.* = .{ .name = values[0], .label = label, .tokens = t.tokenize(values[2], stopwords) };
            if (label) |truth| { e.append(usize, &labelled, i); e.append(usize, &truths, truth); }
        }
        const unlabelled_lines = try readInput(io, "unlabelled.txt");
        const unlabelled = e.alloc(t.Document, unlabelled_lines.len);
        for (unlabelled_lines, unlabelled, 1..) |line, *document, number| document.* = .{ .name = e.fmt("{d}", .{number}), .label = null, .tokens = t.tokenize(line, stopwords) };
        const experiment = &e.alloc(Experiment, 1)[0];
        experiment.* = .{ .backing = backing, .settings = settings, .classes = classes.items, .training = training, .tests = tests, .unlabelled = unlabelled, .labelled = labelled.items, .truths = truths.items };
        return experiment;
    }

    fn selectedAlphas(self: *const Experiment) [3]i64 {
        var result: [3]i64 = undefined;
        for (0..3) |kind| result[kind] = self.settings.alphas[self.selected[kind]];
        return result;
    }
    fn selectedRun(self: *const Experiment, model: usize) *const CrossValidationRun {
        return if (model == 3) &self.rocchio_cv else &self.cv[model][self.selected[model]];
    }
    fn alphaText(self: *const Experiment, model: usize) []const u8 { return if (model < 3) hundredthsText(self.settings.alphas[self.selected[model]]) else "-"; }
    fn trained(self: *const Experiment, documents: []const *const t.Document, bigrams: bool, size: usize) Training {
        var training = Training.create(self.backing, documents, bigrams, self.classes.len, self.settings.min_df, size);
        training.train(self.selectedAlphas());
        return training;
    }
    fn summarizeCv(self: *const Experiment, run: *CrossValidationRun) void {
        var truths: [1500]usize = undefined;
        for (self.training, 0..) |document, i| {
            truths[i] = document.label.?;
            if (truths[i] == run.predictions[i]) run.fold_correct[i % 5] += 1;
        }
        run.evaluation = e.evaluate(self.classes.len, truths[0..self.training.len], run.predictions[0..self.training.len]);
    }
    fn crossValidate(self: *Experiment) void {
        for (0..5) |fold| {
            var members: [1500]*const t.Document = undefined;
            var held: [1500]usize = undefined;
            var count: usize = 0;
            var held_count: usize = 0;
            for (self.training, 0..) |*document, i| {
                if (i % 5 == fold) { held[held_count] = i; held_count += 1; } else { members[count] = document; count += 1; }
            }
            var training = Training.create(self.backing, members[0..count], self.settings.bigrams, self.classes.len, self.settings.min_df, self.settings.features);
            defer training.deinit();
            self.folds[fold] = .{ .train = count, .validate = held_count, .candidates = training.vocabulary.candidate_count, .vocabulary = training.vocabulary.terms.len };
            const sequences = e.take(v.Encoded, training.arena.allocator(), held_count);
            for (held[0..held_count], sequences) |index, *sequence| sequence.* = training.vocabulary.encode(training.arena.allocator(), self.training[index].tokens.terms(training.bigrams));
            for (0..3) |kind| {
                for (self.settings.alphas, 0..) |alpha, position| {
                    var arena = std.heap.ArenaAllocator.init(self.backing);
                    defer arena.deinit();
                    const model = nb.train(arena.allocator(), kind, &training.counts, alpha);
                    for (held[0..held_count], sequences) |index, sequence| self.cv[kind][position].predictions[index] = model.predict(sequence).label;
                }
            }
            for (held[0..held_count], sequences) |index, sequence| self.rocchio_cv.predictions[index] = training.rocchio_model.predict(sequence).label;
        }
        for (0..3) |kind| {
            for (0..self.settings.alphas.len) |alpha| self.summarizeCv(&self.cv[kind][alpha]);
            for (1..self.settings.alphas.len) |alpha| {
                if (e.decimalValue(self.cv[kind][alpha].evaluation.macro_f1) > e.decimalValue(self.cv[kind][self.selected[kind]].evaluation.macro_f1)) self.selected[kind] = alpha;
            }
        }
        self.summarizeCv(&self.rocchio_cv);
    }
    fn trainFinal(self: *Experiment) void {
        var documents: [1500]*const t.Document = undefined;
        for (self.training, 0..) |*document, i| documents[i] = document;
        self.final = self.trained(documents[0..self.training.len], self.settings.bigrams, self.settings.features);
        self.test_sequences = e.alloc(v.Encoded, self.tests.len);
        for (self.tests, self.test_sequences, 0..) |document, *sequence, i| {
            sequence.* = self.final.vocabulary.encode(e.allocator, document.tokens.terms(self.settings.bigrams));
            var votes: [8]usize = @splat(0);
            for (0..4) |model| {
                self.predictions[model][i] = self.final.classify(model, sequence.*);
                votes[self.predictions[model][i].label] += 1;
            }
            var vote: nb.Prediction = .{ .label = self.predictions[0][i].label };
            for (0..4) |model| {
                const label = self.predictions[model][i].label;
                if (votes[label] > votes[vote.label]) vote.label = label;
            }
            vote.score = e.f(votes[vote.label]) / 4;
            self.predictions[4][i] = vote;
        }
        for (0..5) |model| {
            for (self.labelled, self.truths, 0..) |index, truth, i| self.correct[model][i] = self.predictions[model][index].label == truth;
        }
    }

    fn classCountsText(self: *const Experiment, counts: []const usize) []const u8 {
        var text: e.Text = .{};
        for (self.classes, counts, 0..) |name, count, i| text.add("{s}{s} {d}", .{ if (i > 0) " " else "", name, count });
        return text.value();
    }
    fn vocabularyLines(self: *const Experiment) e.Lines {
        const vocabulary = self.final.vocabulary;
        var lines: e.Lines = .{};
        lines.add("documents {d} terms {d} candidates {d} vocabulary {d}", .{ self.training.len, vocabulary.term_count, vocabulary.candidate_count, vocabulary.terms.len });
        for (vocabulary.ranking, 1..) |entry, rank| lines.add("{d} {s} {d} {s} {s}", .{ rank, t.name(entry.term), entry.frequency, e.realText(entry.score), self.classes[entry.best_class] });
        return lines;
    }
    fn cvLines(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("model,alpha,correct,accuracy,macro_f1,selected");
        for (0..3) |kind| {
            for (self.settings.alphas, 0..) |alpha, i| {
                const evaluation = &self.cv[kind][i].evaluation;
                lines.add("{s},{s},{d},{s},{s},{s}", .{ model_names[kind], hundredthsText(alpha), evaluation.correct, e.realText(evaluation.micro_f1), e.realText(evaluation.macro_f1), if (self.selected[kind] == i) "yes" else "no" });
            }
        }
        const evaluation = &self.rocchio_cv.evaluation;
        lines.add("rocchio,-,{d},{s},{s},yes", .{ evaluation.correct, e.realText(evaluation.micro_f1), e.realText(evaluation.macro_f1) });
        return lines;
    }
    fn predictionLines(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("id,model,label,score");
        for (self.tests, 0..) |document, i| {
            for (model_names, 0..) |name, model| {
                const prediction = self.predictions[model][i];
                lines.add("{s},{s},{s},{s}", .{ document.name, name, self.classes[prediction.label], e.realText(prediction.score) });
            }
        }
        return lines;
    }
    fn studyEvaluations(self: *const Experiment, training: *const Training) [4]e.Evaluation {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const sequences = e.take(v.Encoded, scratch.allocator(), self.labelled.len);
        for (self.labelled, sequences) |index, *sequence| sequence.* = training.vocabulary.encode(scratch.allocator(), self.tests[index].tokens.terms(training.bigrams));
        var result: [4]e.Evaluation = undefined;
        for (0..4) |model| {
            var predicted: [500]usize = undefined;
            for (sequences, 0..) |sequence, i| predicted[i] = training.classify(model, sequence).label;
            result[model] = e.evaluate(self.classes.len, self.truths, predicted[0..self.labelled.len]);
        }
        return result;
    }
    fn curveLines(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("size,vocabulary,model,correct,accuracy,macro_f1");
        var documents: [1500]*const t.Document = undefined;
        for (self.training, 0..) |*document, i| documents[i] = document;
        for (self.settings.curve) |size| {
            var training = self.trained(documents[0..size], self.settings.bigrams, self.settings.features);
            defer training.deinit();
            const evaluations = self.studyEvaluations(&training);
            for (evaluations, 0..) |evaluation, model| lines.add("{d},{d},{s},{d},{s},{s}", .{ size, training.vocabulary.terms.len, model_names[model], evaluation.correct, e.realText(evaluation.micro_f1), e.realText(evaluation.macro_f1) });
        }
        return lines;
    }
    fn featureLines(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("terms,features,vocabulary,model,correct,accuracy,macro_f1");
        var documents: [1500]*const t.Document = undefined;
        for (self.training, 0..) |*document, i| documents[i] = document;
        for ([_]bool{ false, true }) |bigrams| {
            for (self.settings.sizes) |size| {
                var training = self.trained(documents[0..self.training.len], bigrams, size);
                defer training.deinit();
                const evaluations = self.studyEvaluations(&training);
                for (evaluations, 0..) |evaluation, model| lines.add("{s},{d},{d},{s},{d},{s},{s}", .{ if (bigrams) "bigrams" else "unigrams", size, training.vocabulary.terms.len, model_names[model], evaluation.correct, e.realText(evaluation.micro_f1), e.realText(evaluation.macro_f1) });
            }
        }
        return lines;
    }

    fn dataPart(self: *const Experiment) e.Lines {
        const vocabulary = self.final.vocabulary;
        var lines: e.Lines = .{};
        lines.add("documents train {d} test {d} labelled {d} unlabelled {d} classes {d}", .{ self.training.len, self.tests.len, self.labelled.len, self.unlabelled.len, self.classes.len });
        var train_counts: [8]usize = @splat(0);
        var test_counts: [8]usize = @splat(0);
        for (self.training) |document| train_counts[document.label.?] += 1;
        for (self.truths) |truth| test_counts[truth] += 1;
        for (self.classes, 0..) |name, label| lines.add("class {s} train {d} test {d}", .{ name, train_counts[label], test_counts[label] });
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const memory = scratch.allocator();
        const seen = e.take(bool, memory, t.count());
        @memset(seen, false);
        var raw: usize = 0;
        var stopped: usize = 0;
        var short_words: usize = 0;
        var kept: usize = 0;
        var bigrams: usize = 0;
        for (self.training) |document| {
            const tokens = document.tokens;
            raw += tokens.raw_count;
            stopped += tokens.stopword_count;
            short_words += tokens.short_count;
            kept += tokens.words.len;
            if (self.settings.bigrams) bigrams += tokens.bigram_terms.len - tokens.words.len;
            for (tokens.terms(self.settings.bigrams)) |term| seen[term] = true;
        }
        var distinct_words: usize = 0;
        var distinct_bigrams: usize = 0;
        for (seen, 0..) |present, term| {
            if (!present) continue;
            if (std.mem.indexOfScalar(u8, t.name(term), '_') != null) distinct_bigrams += 1 else distinct_words += 1;
        }
        lines.add("train_tokens raw {d} stopwords {d} short {d} unigrams {d} bigrams {d}", .{ raw, stopped, short_words, kept, bigrams });
        lines.add("train_terms unigrams {d} bigrams {d} candidates {d} vocabulary {d}", .{ distinct_words, distinct_bigrams, vocabulary.candidate_count, vocabulary.terms.len });
        var total: usize = 0;
        var inside: usize = 0;
        const counts = e.take(usize, memory, t.count());
        @memset(counts, 0);
        for (self.tests, self.test_sequences) |document, sequence| {
            total += document.tokens.terms(self.settings.bigrams).len;
            inside += sequence.terms.len;
            for (document.tokens.words) |term| if (vocabulary.map[term] == v.missing) { counts[term] += 1; };
        }
        lines.add("test_terms total {d} in_vocabulary {d}", .{ total, inside });
        const Occurrence = struct { term: usize, count: usize };
        const Sort = struct {
            fn lessThan(_: void, first: Occurrence, second: Occurrence) bool {
                return if (first.count != second.count) first.count > second.count else std.mem.order(u8, t.name(first.term), t.name(second.term)) == .lt;
            }
        };
        var oov: std.ArrayList(Occurrence) = .empty;
        for (counts, 0..) |count, term| if (count > 0) { oov.append(memory, .{ .term = term, .count = count }) catch @panic("allocation failed"); };
        std.mem.sort(Occurrence, oov.items, {}, Sort.lessThan);
        var line: e.Text = .{};
        line.write("test_oov");
        for (oov.items[0..@min(oov.items.len, self.settings.top)]) |item| line.add(" {s} {d}", .{ t.name(item.term), item.count });
        lines.write(line.value());
        return lines;
    }
    fn foldsPart(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("folds 5");
        for (self.folds, 1..) |fold, number| lines.add("fold {d} train {d} validate {d} candidates {d} vocabulary {d}", .{ number, fold.train, fold.validate, fold.candidates, fold.vocabulary });
        return lines;
    }
    fn selectionPart(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("selection");
        for (0..4) |model| {
            const run = self.selectedRun(model);
            const evaluation = run.evaluation;
            lines.add("{s} alpha {s} correct {s} macro_f1 {s} folds {d} {d} {d} {d} {d}", .{ model_names[model], self.alphaText(model), e.proportion(e.n(evaluation.correct), e.n(evaluation.total)), e.realText(evaluation.macro_f1), run.fold_correct[0], run.fold_correct[1], run.fold_correct[2], run.fold_correct[3], run.fold_correct[4] });
        }
        return lines;
    }
    fn crossValidationPart(self: *const Experiment, model: usize) e.Lines {
        var lines: e.Lines = .{};
        lines.add("cross_validation {s} alpha {s}", .{ model_names[model], self.alphaText(model) });
        lines.extend(self.selectedRun(model).evaluation.output(self.classes));
        return lines;
    }
    fn testPart(self: *const Experiment, model: usize) e.Lines {
        var predictions: [500]usize = undefined;
        var top_two: usize = 0;
        for (self.labelled, self.truths, 0..) |index, truth, i| {
            const prediction = self.predictions[model][index];
            predictions[i] = prediction.label;
            if (truth == prediction.ranking[0] or truth == prediction.ranking[1]) top_two += 1;
        }
        const evaluation = e.evaluate(self.classes.len, self.truths, predictions[0..self.truths.len]);
        var lines: e.Lines = .{};
        lines.add("test {s} alpha {s}", .{ model_names[model], self.alphaText(model) });
        lines.add("labelled {d} correct {s}", .{ evaluation.total, e.proportion(e.n(evaluation.correct), e.n(evaluation.total)) });
        if (model < 4) lines.add("top2 {s}", .{e.proportion(e.n(top_two), e.n(evaluation.total))});
        lines.extend(evaluation.output(self.classes));
        return lines;
    }
    fn probabilityPart(self: *const Experiment, model: usize) e.Lines {
        const settings = self.settings;
        var bin_rows: [10]usize = @splat(0);
        var bin_correct: [10]usize = @splat(0);
        var bin_sums: [10]f64 = @splat(0);
        var accepted: [9]usize = @splat(0);
        var accepted_correct: [9]usize = @splat(0);
        var loss: f64 = 0;
        var brier: f64 = 0;
        for (self.labelled, self.truths, 0..) |index, truth, i| {
            const prediction = self.predictions[model][index];
            const correct = self.correct[model][i];
            loss += @log(prediction.normalizer) - (prediction.scores[truth] - prediction.scores[prediction.label]);
            var squares: f64 = 0;
            for (prediction.probabilities[0..self.classes.len], 0..) |probability, label| {
                const difference = probability - (if (label == truth) @as(f64, 1) else 0);
                squares += difference * difference;
            }
            brier += squares;
            var bucket: usize = 0;
            for (settings.thresholds, 0..) |threshold, j| {
                if (prediction.score >= e.f(threshold) / 100) {
                    bucket += 1;
                    accepted[j] += 1;
                    accepted_correct[j] += @intFromBool(correct);
                }
            }
            bin_rows[bucket] += 1;
            bin_correct[bucket] += @intFromBool(correct);
            bin_sums[bucket] += prediction.score;
        }
        var lines: e.Lines = .{};
        lines.add("probability {s} alpha {s}", .{ model_names[model], self.alphaText(model) });
        lines.add("log_loss {s} brier {s}", .{ e.realText(loss / e.f(self.labelled.len)), e.realText(brier / e.f(self.labelled.len)) });
        for (0..settings.thresholds.len + 1) |bucket| {
            const bound = if (bucket == 0) 0 else settings.thresholds[bucket - 1];
            const count = bin_rows[bucket];
            if (count == 0) lines.add("bin {s} rows 0", .{hundredthsText(bound)}) else lines.add("bin {s} rows {d} correct {s} mean {s}", .{ hundredthsText(bound), count, e.proportion(e.n(bin_correct[bucket]), e.n(count)), e.realText(bin_sums[bucket] / e.f(count)) });
        }
        for (settings.thresholds, 0..) |threshold, i| lines.add("threshold {s} covered {s} correct {s}", .{ hundredthsText(threshold), e.proportion(e.n(accepted[i]), e.n(self.labelled.len)), if (accepted[i] > 0) e.proportion(e.n(accepted_correct[i]), e.n(accepted[i])) else "-" });
        return lines;
    }

    fn lengthsPart(self: *const Experiment) e.Lines {
        var rows: [10]usize = @splat(0);
        var correct: [5][10]usize = @splat(@splat(0));
        for (self.labelled, 0..) |index, i| {
            var bucket: usize = 0;
            for (self.settings.lengths) |boundary| bucket += @intFromBool(self.test_sequences[index].terms.len >= boundary);
            rows[bucket] += 1;
            for (0..5) |model| correct[model][bucket] += @intFromBool(self.correct[model][i]);
        }
        var lines: e.Lines = .{};
        lines.write("lengths");
        for (0..self.settings.lengths.len + 1) |bucket| {
            var line: e.Text = .{};
            line.add("length {d} rows {d}", .{ if (bucket == 0) 0 else self.settings.lengths[bucket - 1], rows[bucket] });
            if (rows[bucket] > 0) {
                for (model_names, 0..) |name, model| line.add(" {s} {s}", .{ name, e.proportion(e.n(correct[model][bucket]), e.n(rows[bucket])) });
            }
            lines.write(line.value());
        }
        return lines;
    }
    fn comparisonPart(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.write("comparison");
        for (0..4) |first| {
            for (first + 1..4) |second| {
                var agree: usize = 0;
                var b: usize = 0;
                var c: usize = 0;
                for (0..self.tests.len) |i| agree += @intFromBool(self.predictions[first][i].label == self.predictions[second][i].label);
                for (0..self.labelled.len) |i| {
                    b += @intFromBool(self.correct[first][i] and !self.correct[second][i]);
                    c += @intFromBool(self.correct[second][i] and !self.correct[first][i]);
                }
                const difference = @max(0, @as(i64, @intCast(@abs(e.n(b) - e.n(c)))) - 1);
                lines.add("{s} {s} agree {s} b {d} c {d} statistic {s}", .{ model_names[first], model_names[second], e.proportion(e.n(agree), e.n(self.tests.len)), b, c, e.fraction(difference * difference, if (b + c > 0) e.n(b + c) else 1) });
            }
        }
        var errors: [5]usize = @splat(0);
        for (0..self.labelled.len) |i| {
            var wrong: usize = 0;
            for (0..4) |model| wrong += @intFromBool(!self.correct[model][i]);
            errors[wrong] += 1;
        }
        lines.add("errors 0 {d} 1 {d} 2 {d} 3 {d} 4 {d}", .{ errors[0], errors[1], errors[2], errors[3], errors[4] });
        return lines;
    }
    fn bootstrapPart(self: *const Experiment) e.Lines {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const memory = scratch.allocator();
        const resamples = self.settings.resamples;
        const count = self.labelled.len;
        const totals = e.take(usize, memory, 5 * resamples);
        @memset(totals, 0);
        var state = self.settings.seed;
        for (0..resamples) |sample| {
            for (0..count) |_| {
                state = @mod(48271 * state, 2147483647);
                const chosen = e.u(@mod(state, e.n(count)));
                for (0..5) |model| totals[model * resamples + sample] += @intFromBool(self.correct[model][chosen]);
            }
        }
        const Sort = struct { fn lessThan(_: void, first: usize, second: usize) bool { return first < second; } };
        const ordered = e.take(usize, memory, resamples);
        const rank = resamples / 40;
        var lines: e.Lines = .{};
        lines.add("bootstrap resamples {d} seed {d}", .{ resamples, self.settings.seed });
        for (model_names, 0..) |name, model| {
            @memcpy(ordered, totals[model * resamples .. (model + 1) * resamples]);
            std.mem.sort(usize, ordered, {}, Sort.lessThan);
            var sum: i64 = 0;
            for (ordered) |value| sum += e.n(value);
            lines.add("{s} mean {s} low {s} high {s}", .{ name, e.realText(e.f(sum) / e.f(resamples * count)), e.proportion(e.n(ordered[rank]), e.n(count)), e.proportion(e.n(ordered[resamples - 1 - rank]), e.n(count)) });
        }
        for (0..4) |first| {
            for (first + 1..4) |second| {
                var wins: usize = 0;
                var ties: usize = 0;
                var losses: usize = 0;
                for (0..resamples) |i| {
                    const one = totals[first * resamples + i];
                    const other = totals[second * resamples + i];
                    wins += @intFromBool(one > other);
                    ties += @intFromBool(one == other);
                    losses += @intFromBool(one < other);
                }
                lines.add("pair {s} {s} wins {d} ties {d} losses {d}", .{ model_names[first], model_names[second], wins, ties, losses });
            }
        }
        return lines;
    }
    fn hardPart(self: *const Experiment) e.Lines {
        var hard: [1500]usize = undefined;
        var count: usize = 0;
        var class_counts: [8]usize = @splat(0);
        for (self.training, 0..) |document, i| {
            var all_wrong = true;
            for (0..4) |model| all_wrong = all_wrong and self.selectedRun(model).predictions[i] != document.label.?;
            if (all_wrong) { hard[count] = i; count += 1; class_counts[document.label.?] += 1; }
        }
        var lines: e.Lines = .{};
        lines.add("hard_documents {d} {s}", .{ count, self.classCountsText(class_counts[0..self.classes.len]) });
        for (hard[0..@min(count, self.settings.top)]) |index| {
            var line: e.Text = .{};
            line.add("{s} true {s} predicted", .{ self.training[index].name, self.classes[self.training[index].label.?] });
            for (0..4) |model| line.add(" {s}", .{self.classes[self.selectedRun(model).predictions[index]]});
            lines.write(line.value());
        }
        return lines;
    }
    fn uncertainPart(self: *const Experiment) e.Lines {
        var order: [500]usize = undefined;
        for (0..self.tests.len) |i| {
            var position = i;
            while (position > 0 and e.decimalValue(self.predictions[0][i].margin) < e.decimalValue(self.predictions[0][order[position - 1]].margin)) : (position -= 1) order[position] = order[position - 1];
            order[position] = i;
        }
        const shown = @min(self.settings.top, self.tests.len);
        var lines: e.Lines = .{};
        lines.add("uncertain multinomial {d}", .{shown});
        for (order[0..shown]) |index| {
            const document = self.tests[index];
            const prediction = self.predictions[0][index];
            lines.add("{s} predicted {s} runner_up {s} margin {s} posterior {s} true {s}", .{ document.name, self.classes[prediction.label], self.classes[prediction.ranking[1]], e.realText(prediction.margin), e.realText(prediction.score), if (document.label) |truth| self.classes[truth] else "?" });
        }
        return lines;
    }
    fn misclassifiedPart(self: *const Experiment) e.Lines {
        var count: usize = 0;
        for (self.correct[0][0..self.labelled.len]) |correct| if (!correct) { count += 1; };
        var lines: e.Lines = .{};
        lines.add("misclassified multinomial {d}", .{count});
        const counts = &self.final.counts;
        const alpha = self.settings.alphas[self.selected[0]];
        const size = counts.size;
        for (self.labelled, self.truths, 0..) |index, truth, i| {
            if (self.correct[0][i]) continue;
            const prediction = self.predictions[0][index];
            lines.add("{s} true {s} predicted {s} posterior {s}", .{ self.tests[index].name, self.classes[truth], self.classes[prediction.label], e.realText(prediction.score) });
            const sequence = self.test_sequences[index];
            var entries: [600]Ratio = undefined;
            for (sequence.first, 0..) |term, j| entries[j] = .{ .numerator = 100 * counts.occurrences[prediction.label * size + term] + alpha, .denominator = 100 * counts.occurrences[truth * size + term] + alpha, .term = term };
            std.mem.sort(Ratio, entries[0..sequence.first.len], {}, ratioLessThan);
            for (entries[0..@min(sequence.first.len, 3)]) |entry| {
                var frequency: usize = 0;
                for (sequence.first, sequence.frequencies) |term, value| if (term == entry.term) { frequency = value; };
                const weights = self.final.models[0].weights;
                lines.add("  {s} count {d} evidence {s}", .{ t.name(self.final.vocabulary.terms[entry.term]), frequency, e.realText(weights[prediction.label * size + entry.term] - weights[truth * size + entry.term]) });
            }
        }
        return lines;
    }
    fn maximization(self: *const Experiment, memory: std.mem.Allocator, posteriors: []const nb.Prediction, sequences: []const v.Encoded) nb.Model {
        const counts = &self.final.counts;
        const size = counts.size;
        const classes = counts.classes;
        const alpha = self.settings.alphas[self.selected[0]];
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const occurrences = e.take(f64, scratch.allocator(), classes * size);
        var documents: [8]f64 = undefined;
        for (0..classes) |label| {
            documents[label] = e.f(counts.documents[label]);
            for (0..size) |term| occurrences[label * size + term] = e.f(counts.occurrences[label * size + term]);
        }
        const weight = e.f(self.settings.weight) / 100;
        for (posteriors, sequences) |posterior, sequence| {
            for (0..classes) |label| {
                const share = weight * posterior.probabilities[label];
                documents[label] += share;
                for (sequence.first, sequence.frequencies) |term, frequency| occurrences[label * size + term] += share * e.f(frequency);
            }
        }
        var model: nb.Model = .{ .kind = 0, .classes = classes, .size = size, .weights = e.take(f64, memory, classes * size) };
        const scale = e.f(self.training.len) + e.f(self.settings.weight * e.n(self.unlabelled.len)) / 100;
        for (0..classes) |label| {
            var total: f64 = 0;
            for (0..size) |term| total += occurrences[label * size + term];
            for (0..size) |term| model.weights[label * size + term] = @log((100 * occurrences[label * size + term] + e.f(alpha)) / (100 * total + e.f(alpha * e.n(size))));
            model.priors[label] = @log(documents[label] / scale);
        }
        return model;
    }
    fn semiSupervisedPart(self: *const Experiment) e.Lines {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const memory = scratch.allocator();
        const count = self.unlabelled.len;
        const sequences = e.take(v.Encoded, memory, count);
        const posteriors = e.take(nb.Prediction, memory, count);
        const previous = e.take(usize, memory, count);
        for (self.unlabelled, sequences) |document, *sequence| sequence.* = self.final.vocabulary.encode(memory, document.tokens.terms(self.settings.bigrams));
        var model_arena = std.heap.ArenaAllocator.init(self.backing);
        defer model_arena.deinit();
        var model = self.final.models[0];
        var lines: e.Lines = .{};
        lines.add("semi_supervised multinomial alpha {s} weight {s} unlabelled {d}", .{ self.alphaText(0), hundredthsText(self.settings.weight), count });
        for (0..self.settings.iterations + 1) |iteration| {
            var assigned: [8]usize = @splat(0);
            var changed: usize = 0;
            for (sequences, posteriors, previous) |sequence, *posterior, *old| {
                posterior.* = model.predict(sequence);
                assigned[posterior.label] += 1;
                if (iteration > 0 and old.* != posterior.label) changed += 1;
                old.* = posterior.label;
            }
            var predicted: [500]usize = undefined;
            for (self.labelled, 0..) |index, i| predicted[i] = model.predict(self.test_sequences[index]).label;
            const evaluation = e.evaluate(self.classes.len, self.truths, predicted[0..self.labelled.len]);
            lines.add("iteration {d} correct {s} macro_f1 {s} changed {s} assigned {s}", .{ iteration, e.proportion(e.n(evaluation.correct), e.n(evaluation.total)), e.realText(evaluation.macro_f1), if (iteration > 0) e.fmt("{d}", .{changed}) else "-", self.classCountsText(assigned[0..self.classes.len]) });
            if (iteration < self.settings.iterations) {
                _ = model_arena.reset(.free_all);
                model = self.maximization(model_arena.allocator(), posteriors, sequences);
            }
        }
        return lines;
    }
    fn metricsLines(self: *const Experiment) e.Lines {
        var lines: e.Lines = .{};
        lines.paragraph(self.dataPart());
        lines.paragraph(self.foldsPart());
        lines.paragraph(self.selectionPart());
        for (0..4) |model| lines.paragraph(self.crossValidationPart(model));
        for (0..5) |model| lines.paragraph(self.testPart(model));
        for (0..3) |model| lines.paragraph(self.probabilityPart(model));
        lines.paragraph(self.lengthsPart());
        lines.paragraph(self.comparisonPart());
        lines.paragraph(self.bootstrapPart());
        lines.paragraph(self.hardPart());
        lines.paragraph(self.uncertainPart());
        lines.paragraph(self.misclassifiedPart());
        lines.paragraph(self.semiSupervisedPart());
        return lines;
    }
    fn topFeatureLines(self: *const Experiment) e.Lines {
        const counts = &self.final.counts;
        const size = counts.size;
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        const entries = e.take(Ratio, scratch.allocator(), size);
        const term_totals = e.take(i64, scratch.allocator(), size);
        var lines: e.Lines = .{};
        for (0..2) |kind| {
            const alpha = self.settings.alphas[self.selected[kind]];
            const outcomes = if (kind == 0) size else 2;
            const table = if (kind == 0) counts.occurrences else counts.containing;
            for (0..size) |term| {
                term_totals[term] = 0;
                for (0..counts.classes) |label| term_totals[term] += table[label * size + term];
            }
            var heading: e.Lines = .{};
            heading.add("model {s} alpha {s} vocabulary {d} top {d}", .{ model_names[kind], self.alphaText(kind), size, self.settings.top });
            lines.paragraph(heading);
            for (self.classes, 0..) |name, label| {
                const total = if (kind == 0) counts.totals[label] else e.n(counts.documents[label]);
                const other = (if (kind == 0) counts.total else e.n(counts.document_total)) - total;
                var section: e.Lines = .{};
                section.add("class {s} total {d} other {d}", .{ name, total, other });
                for (0..size) |term| entries[term] = .{ .numerator = 100 * table[label * size + term] + alpha, .denominator = 100 * (term_totals[term] - table[label * size + term]) + alpha, .term = term };
                std.mem.sort(Ratio, entries, {}, ratioLessThan);
                for (entries[0..@min(size, self.settings.top)], 1..) |entry, rank| {
                    const count = table[label * size + entry.term];
                    const other_count = term_totals[entry.term] - count;
                    const odds = nb.smoothedLog(count, total, alpha, outcomes) - nb.smoothedLog(other_count, other, alpha, outcomes);
                    section.add("{d} {s} {d} {d} {s}", .{ rank, t.name(self.final.vocabulary.terms[entry.term]), count, other_count, e.realText(odds) });
                }
                lines.paragraph(section);
            }
        }
        return lines;
    }
};

const Ratio = struct { numerator: i64, denominator: i64, term: usize };
fn ratioLessThan(_: void, first: Ratio, second: Ratio) bool {
    const left = first.numerator * second.denominator;
    const right = second.numerator * first.denominator;
    return if (left != right) left > right else first.term < second.term;
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    e.allocator = arena.allocator();
    const experiment = try Experiment.load(init.io, init.gpa);
    experiment.crossValidate();
    experiment.trainFinal();
    defer experiment.final.deinit();
    try std.Io.Dir.cwd().createDirPath(init.io, "output");
    try writeLines(init.io, "vocabulary.txt", experiment.vocabularyLines());
    try writeLines(init.io, "cv_results.csv", experiment.cvLines());
    try writeLines(init.io, "predictions.csv", experiment.predictionLines());
    try writeLines(init.io, "learning_curve.csv", experiment.curveLines());
    try writeLines(init.io, "feature_study.csv", experiment.featureLines());
    try writeLines(init.io, "metrics.txt", experiment.metricsLines());
    try writeLines(init.io, "top_features.txt", experiment.topFeatureLines());
}
